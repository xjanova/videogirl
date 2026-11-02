package com.xjanova.videogirl

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.aggregate.AggregateMetric
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BloodPressureRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import java.time.Instant
import java.time.temporal.ChronoUnit
import kotlin.reflect.KClass

/**
 * อ่านข้อมูลสุขภาพจาก Health Connect · อ่านอย่างเดียว ขอสิทธิ์ทีละชนิด เฉพาะชนิดที่เจ้าของถาม
 *
 * ## 🔴 ความเป็นส่วนตัว
 *
 * - คืนเฉพาะชนิดที่ขอ และเป็นตัวเลขสรุป · ไม่มีชื่อแอปต้นทาง ไม่มีโน้ตหรือชื่อรายการ ข้อความพวกนั้นคนอื่นเขียนได้
 * - ด่านล็อกจอและด่านในสายอยู่ฝั่ง Dart (`PhoneLookup.healthBarred`) · ช่องนี้ไม่มีด่านเอง
 * - ห้าม log ค่าใด ๆ · รายงานบั๊กออกนอกเครื่องได้
 *
 * ทุกชนิดตอบเป็นสถานะของตัวเอง: `ok` · `empty` · `no_permission` · `background` · `failed`
 *
 * 🔴 Health Connect ให้แอปอ่านเฉพาะตอนอยู่หน้าจอ · อยู่หลังบ้านจะโยน SecurityException ทั้งที่ให้สิทธิ์แล้ว
 * (เราไม่ขอ READ_HEALTH_DATA_IN_BACKGROUND โดยตั้งใจ) จึงแยกเป็น `background` ไม่ปนกับ `no_permission`
 */
internal class MindHealth(context: Context) {
    private val app = context.applicationContext

    /** `ok` · `update` (Android 13 ลงมาต้องลงแอป Health Connect ก่อน) · `none` */
    fun status(): String = when (HealthConnectClient.getSdkStatus(app)) {
        HealthConnectClient.SDK_AVAILABLE -> "ok"
        HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "update"
        else -> "none"
    }

    /** ทำงานนอกเธรดหลักเท่านั้น · [from]/[to] เป็นมิลลิวินาที (ฝั่ง Dart คิดขอบวันตามเวลาท้องถิ่น) */
    fun read(types: List<String>, from: Long, to: Long): Map<String, Any?> {
        val status = status()
        if (status != "ok") return mapOf("status" to status)
        val client = HealthConnectClient.getOrCreate(app)
        return runBlocking {
            withTimeout(READ_TIMEOUT_MS) {
                val allowed = client.permissionController.getGrantedPermissions()
                val start = Instant.ofEpochMilli(from)
                val end = Instant.ofEpochMilli(to)
                mapOf(
                    "status" to "ok",
                    "types" to types.distinct().filter { it in PERMISSIONS }.associateWith { type ->
                        if (PERMISSIONS.getValue(type) !in allowed) {
                            mapOf("state" to "no_permission")
                        } else {
                            one(client, type, start, end)
                        }
                    },
                )
            }
        }
    }

    private suspend fun one(client: HealthConnectClient, type: String, from: Instant, to: Instant): Map<String, Any?> = try {
        when (type) {
            "steps" -> total(client, StepsRecord.COUNT_TOTAL, from, to)?.let { ok("count" to it) }
            "distance" -> total(client, DistanceRecord.DISTANCE_TOTAL, from, to)?.let { ok("km" to it.inKilometers) }
            "calories" -> total(client, ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL, from, to)
                ?.let { ok("kcal" to it.inKilocalories) }
            "heart_rate" -> heart(client, from, to)
            "sleep" -> sleep(client, from)
            "weight" -> latest(client, WeightRecord::class, to)
                ?.let { ok("kg" to it.weight.inKilograms, "at" to it.time.toEpochMilli()) }
            "blood_pressure" -> latest(client, BloodPressureRecord::class, to)?.let {
                ok(
                    "systolic" to it.systolic.inMillimetersOfMercury,
                    "diastolic" to it.diastolic.inMillimetersOfMercury,
                    "at" to it.time.toEpochMilli(),
                )
            }
            "oxygen" -> latest(client, OxygenSaturationRecord::class, to)
                ?.let { ok("percent" to it.percentage.value, "at" to it.time.toEpochMilli()) }
            else -> null
        } ?: mapOf("state" to "empty")
    } catch (e: CancellationException) {
        throw e
    } catch (e: SecurityException) {
        mapOf("state" to "background")
    } catch (e: Exception) {
        mapOf("state" to "failed")
    }

    private fun ok(vararg fields: Pair<String, Any?>): Map<String, Any?> = mapOf("state" to "ok", *fields)

    /**
     * 🔴 ใช้ aggregate ห้ามบวกเอง · นาฬิกากับแอปออกกำลังกายเขียนก้าวเดียวกันซ้ำได้ Health Connect ตัดซ้ำให้
     * เฉพาะทางนี้ ไม่มีแถวในช่วงนั้น = null ไม่ใช่ศูนย์
     */
    private suspend fun <T : Any> total(client: HealthConnectClient, metric: AggregateMetric<T>, from: Instant, to: Instant): T? =
        client.aggregate(AggregateRequest(setOf(metric), TimeRangeFilter.between(from, to)))[metric]

    private suspend fun heart(client: HealthConnectClient, from: Instant, to: Instant): Map<String, Any?>? {
        val filter = TimeRangeFilter.between(from, to)
        val sum = client.aggregate(
            AggregateRequest(setOf(HeartRateRecord.BPM_AVG, HeartRateRecord.BPM_MIN, HeartRateRecord.BPM_MAX), filter)
        )
        val avg = sum[HeartRateRecord.BPM_AVG] ?: return null
        val last = client.readRecords(ReadRecordsRequest(HeartRateRecord::class, filter, ascendingOrder = false, pageSize = 1))
            .records.firstOrNull()?.samples?.maxByOrNull { it.time }
        return ok(
            "avg" to avg,
            "min" to sum[HeartRateRecord.BPM_MIN],
            "max" to sum[HeartRateRecord.BPM_MAX],
            "last" to last?.beatsPerMinute,
            "at" to last?.time?.toEpochMilli(),
        )
    }

    /** นอนคืนก่อนเริ่มก่อนเที่ยงคืน · นับจาก 18:00 ของเมื่อวานถึง 18:00 ของวันนั้น ไม่งั้นตัดครึ่งคืน */
    private suspend fun sleep(client: HealthConnectClient, dayStart: Instant): Map<String, Any?>? {
        val filter = TimeRangeFilter.between(dayStart.minus(6, ChronoUnit.HOURS), dayStart.plus(18, ChronoUnit.HOURS))
        val slept = client.aggregate(AggregateRequest(setOf(SleepSessionRecord.SLEEP_DURATION_TOTAL), filter))[
            SleepSessionRecord.SLEEP_DURATION_TOTAL,
        ] ?: return null
        return ok("minutes" to slept.toMinutes())
    }

    /** ค่าล่าสุดใน [LATEST_DAYS] วัน · น้ำหนักหรือความดันไม่ได้วัดทุกวัน */
    private suspend fun <T : Record> latest(client: HealthConnectClient, type: KClass<T>, to: Instant): T? =
        client.readRecords(
            ReadRecordsRequest(
                type,
                TimeRangeFilter.between(to.minus(LATEST_DAYS, ChronoUnit.DAYS), to),
                ascendingOrder = false,
                pageSize = 1,
            )
        ).records.firstOrNull()

    companion object {
        private const val READ_TIMEOUT_MS = 8_000L
        private const val LATEST_DAYS = 30L

        const val HEART_RATE = "android.permission.health.READ_HEART_RATE"

        /** ชื่อชนิด → สิทธิ์ของมัน · ต้องตรงกับ `<uses-permission>` ใน manifest และ PhoneLookup ฝั่ง Dart */
        val PERMISSIONS = mapOf(
            "steps" to "android.permission.health.READ_STEPS",
            "distance" to "android.permission.health.READ_DISTANCE",
            "calories" to "android.permission.health.READ_ACTIVE_CALORIES_BURNED",
            "heart_rate" to HEART_RATE,
            "sleep" to "android.permission.health.READ_SLEEP",
            "weight" to "android.permission.health.READ_WEIGHT",
            "blood_pressure" to "android.permission.health.READ_BLOOD_PRESSURE",
            "oxygen" to "android.permission.health.READ_OXYGEN_SATURATION",
        )
    }
}
