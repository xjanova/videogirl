package com.xjanova.videogirl

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import androidx.core.content.ContextCompat
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.roundToLong

/**
 * อ่านเซ็นเซอร์ในเครื่องหนึ่งครั้งตอนเจ้าของถาม · ฟังแล้วถอนทันที ไม่มีการเฝ้าค้าง
 *
 * ทุกชื่อตอบเป็นสถานะของตัวเอง: `ok` · `absent` (เครื่องนี้ไม่มี) · `no_permission` · `no_reading`
 *
 * 🔴 ไม่มีสิทธิ์ ≠ ไม่มีเซ็นเซอร์ · ตั้งแต่ Android 10 ตัวนับก้าวที่ขาด ACTIVITY_RECOGNITION และตัววัดชีพจรที่ขาด
 * BODY_SENSORS ถูก**ซ่อนจากรายการ** getDefaultSensor คืน null เหมือนเครื่องไม่มี · ต้องดูสิทธิ์ก่อนเสมอ
 * ไม่งั้นเธอบอกเจ้าของว่าเครื่องไม่มีตัวนับก้าวทั้งที่แค่ยังไม่ได้ให้สิทธิ์
 *
 * 🔴 แอปอยู่หลังบ้านโดยไม่มีบริการหน้าจอ Android ไม่ส่งค่าเซ็นเซอร์มาเลย (ไม่มี error) · หมดเวลา = `no_reading`
 * ไม่ใช่ค่าศูนย์
 */
internal class MindSensors(context: Context) {
    private val app = context.applicationContext
    private val manager = app.getSystemService(SensorManager::class.java)

    fun canCountSteps(): Boolean = Build.VERSION.SDK_INT < 29 || granted(Manifest.permission.ACTIVITY_RECOGNITION)

    fun canReadHeart(): Boolean = granted(heartPermission())

    private fun granted(permission: String) =
        ContextCompat.checkSelfPermission(app, permission) == PackageManager.PERMISSION_GRANTED

    private fun hasFeature(name: String) = app.packageManager.hasSystemFeature(name)

    /** ทำงานนอกเธรดหลักเท่านั้น · รอค่าจริงจากเซ็นเซอร์ได้นานถึง [HEART_WAIT_MS] */
    fun read(names: List<String>): Map<String, Any?> {
        val out = HashMap<String, Map<String, Any?>>()
        val waiting = HashMap<String, Sensor>()
        for (name in names.distinct()) {
            val type = TYPES[name] ?: continue
            val blocked = blockedState(name)
            val sensor = if (blocked == null) manager?.getDefaultSensor(type) else null
            when {
                blocked != null -> out[name] = mapOf("state" to blocked)
                sensor == null -> out[name] = mapOf("state" to "absent")
                else -> waiting[name] = sensor
            }
        }
        val got = if (waiting.isEmpty()) emptyMap() else listen(waiting)
        for (name in waiting.keys) out[name] = got[name] ?: mapOf("state" to "no_reading")
        return mapOf(
            "readings" to out,
            "present" to AMBIENT.filter { manager?.getDefaultSensor(TYPES.getValue(it)) != null },
            "stepCounter" to hasFeature(PackageManager.FEATURE_SENSOR_STEP_COUNTER),
            "heartRate" to hasFeature(PackageManager.FEATURE_SENSOR_HEART_RATE),
        )
    }

    /**
     * ด่านก่อนแตะเซ็นเซอร์ · null = ไปต่อ
     *
     * ตัววัดชีพจรมีน้อยเครื่อง จึงดูฮาร์ดแวร์ก่อน ไม่เด้งกล่องขอสิทธิ์ใส่เครื่องที่ให้แล้วก็ไม่ได้อะไร ·
     * ตัวนับก้าวดูสิทธิ์ก่อน เพราะแทบทุกเครื่องมี และบาง ROM ไม่ประกาศ feature นี้ทั้งที่มี
     */
    private fun blockedState(name: String): String? = when (name) {
        "steps" -> if (canCountSteps()) null else "no_permission"
        "heart" -> when {
            !hasFeature(PackageManager.FEATURE_SENSOR_HEART_RATE) -> "absent"
            !canReadHeart() -> "no_permission"
            else -> null
        }
        else -> null
    }

    private fun listen(sensors: Map<String, Sensor>): Map<String, Map<String, Any?>> {
        val sm = manager ?: return emptyMap()
        val readings = ConcurrentHashMap<String, Map<String, Any?>>()
        val latch = CountDownLatch(sensors.size)
        val thread = HandlerThread("mind-sensors").apply { start() }
        val handler = Handler(thread.looper)
        val listeners = sensors.map { (name, sensor) ->
            object : SensorEventListener {
                private var done = false

                override fun onSensorChanged(event: SensorEvent) {
                    if (done) return
                    val reading = reading(name, event) ?: return
                    done = true
                    readings[name] = reading
                    sm.unregisterListener(this)
                    latch.countDown()
                }

                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
            }.also {
                if (!sm.registerListener(it, sensor, SensorManager.SENSOR_DELAY_NORMAL, handler)) latch.countDown()
            }
        }
        try {
            latch.await(if ("heart" in sensors) HEART_WAIT_MS else WAIT_MS, TimeUnit.MILLISECONDS)
        } finally {
            listeners.forEach { sm.unregisterListener(it) }
            thread.quitSafely()
        }
        return readings
    }

    /** null = ค่านี้ใช้ไม่ได้ รอค่าถัดไป */
    private fun reading(name: String, event: SensorEvent): Map<String, Any?>? {
        val values = event.values
        return when (name) {
            "proximity" -> ok("near" to (values[0] < event.sensor.maximumRange))
            "steps" -> ok(
                "steps" to values[0].roundToLong(),
                "hours" to SystemClock.elapsedRealtime() / 3_600_000.0,
            )
            // ยังไม่แตะนิ้ว = ค่าศูนย์หรือความแม่นยำ NO_CONTACT · ไม่ใช่หัวใจหยุดเต้น
            "heart" -> if (event.accuracy < SensorManager.SENSOR_STATUS_ACCURACY_LOW || values[0] <= 0f) {
                null
            } else {
                ok("bpm" to values[0].roundToLong())
            }
            "accelerometer", "gyroscope", "magnetic" -> ok("xyz" to values.take(3).map { it.toDouble() })
            else -> ok("value" to values[0].toDouble())
        }
    }

    private fun ok(vararg fields: Pair<String, Any?>): Map<String, Any?> = mapOf("state" to "ok", *fields)

    companion object {
        private const val WAIT_MS = 2_000L

        /** ตัววัดชีพจรต้องรอนิ้วนิ่งหลายวินาที */
        private const val HEART_WAIT_MS = 12_000L

        private val TYPES = mapOf(
            "light" to Sensor.TYPE_LIGHT,
            "proximity" to Sensor.TYPE_PROXIMITY,
            "accelerometer" to Sensor.TYPE_ACCELEROMETER,
            "gyroscope" to Sensor.TYPE_GYROSCOPE,
            "magnetic" to Sensor.TYPE_MAGNETIC_FIELD,
            "pressure" to Sensor.TYPE_PRESSURE,
            "temperature" to Sensor.TYPE_AMBIENT_TEMPERATURE,
            "humidity" to Sensor.TYPE_RELATIVE_HUMIDITY,
            "steps" to Sensor.TYPE_STEP_COUNTER,
            "heart" to Sensor.TYPE_HEART_RATE,
        )

        /** ตัวที่ไม่บอกเรื่องร่างกาย · ก้าวกับชีพจรต้องขอชื่อตรง ๆ */
        private val AMBIENT = TYPES.keys - setOf("steps", "heart")

        /**
         * Android 16 แอปที่ตั้งเป้า API 36 ใช้สิทธิ์ของ Health Connect แทน BODY_SENSORS · ดู manifest (maxSdkVersion 35)
         */
        fun heartPermission(): String = if (Build.VERSION.SDK_INT >= 36) {
            MindHealth.HEART_RATE
        } else {
            Manifest.permission.BODY_SENSORS
        }
    }
}
