package com.xjanova.videogirl.sos

import android.Manifest
import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.speech.SpeechRecognizer
import androidx.core.content.ContextCompat
import com.xjanova.videogirl.SystemBridge
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * ช่อง SOS ของ Dart · คู่กับ lib/sos/mind_sos.dart
 *
 * 🔴 **ไม่มีคำสั่งไหนรับเบอร์โทร** · สั่งได้แค่ "เกิดเหตุชนิดนี้" แล้ว [SosRouter] เลือกเบอร์จากแผนที่เจ้าของตั้ง ·
 * สิ่งที่โมเดลทำได้มากสุดคือทำให้นับถอยหลังเริ่ม ซึ่งเจ้าของกดหยุดได้ · อย่าเพิ่มเมธอดโทรตรงเด็ดขาด
 *
 * อยู่ใน [SystemBridge.attach] เหตุผลเดียวกับ HandsBridge
 */
object SosBridge {
    private const val LINE_PACKAGE = "jp.naver.line.android"
    private val main = Handler(Looper.getMainLooper())

    fun attach(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        val channel = MethodChannel(messenger, "giggok/sos")
        SosService.events = { name, args -> main.post { channel.invokeMethod(name, args) } }
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "sosStatus" -> result.success(status(app))
                    "sosSave" -> {
                        val plan = call.argument<String>("plan").orEmpty()
                        val profile = call.argument<String>("profile").orEmpty()
                        val valid = SosStore.parse(plan) != null
                        val ok = valid && SosVault.write(app, SosStore.PLAN, plan) &&
                            SosVault.write(app, SosStore.PROFILE, profile)
                        if (ok) {
                            if (SosStore.plan(app)?.armed == true) SosService.sync(app) else SosService.off(app)
                        }
                        result.success(ok)
                    }
                    "sosProfile" -> result.success(SosVault.read(app, SosStore.PROFILE))
                    "sosTrigger" -> result.success(
                        SosService.trigger(
                            app, call.argument<String>("kind") ?: SosKind.OTHER.name,
                            voice = call.argument<Boolean>("voice") == true, drill = false,
                            silent = call.argument<Boolean>("silent") == true,
                        )
                    )
                    "sosDrill" -> result.success(
                        SosService.trigger(
                            app, call.argument<String>("kind") ?: SosKind.CRASH.name, voice = false, drill = true,
                            silent = call.argument<Boolean>("silent") == true,
                        )
                    )
                    "sosStop" -> {
                        SosService.stop(app)
                        result.success(true)
                    }
                    "sosSync" -> {
                        SosService.sync(app)
                        result.success(true)
                    }
                    "sosLocation" -> result.success(location(app))
                    "sosShare" -> result.success(shareLocation(app, call.argument<String>("target") ?: "any"))
                    "sosOpenSetting" -> result.success(open(app, call.argument<String>("which").orEmpty()))
                    "sosWipe" -> {
                        SosService.off(app)
                        SosStore.wipe(app)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                android.util.Log.w("GigGokSos", "${call.method}: ${e.javaClass.simpleName}")
                result.success(null)
            }
        }
    }

    private fun has(c: Context, p: String) = ContextCompat.checkSelfPermission(c, p) == PackageManager.PERMISSION_GRANTED

    /** ความพร้อมที่หน้าตั้งค่าอ่าน · ไม่มีข้อมูลส่วนตัว */
    private fun status(c: Context): Map<String, Any?> {
        val sensors = c.getSystemService(SensorManager::class.java)
        val nm = c.getSystemService(NotificationManager::class.java)
        val pm = c.getSystemService(PowerManager::class.java)
        val plan = SosStore.plan(c)
        val numbers = (plan?.routes?.values?.flatten().orEmpty() + plan?.abroad.orEmpty()).distinct()
        val snap = SosService.now
        return mapOf(
            "armed" to (plan?.armed == true),
            "running" to SosService.running,
            "phase" to snap.phase.name,
            "silent" to snap.silent,
            "autoCall" to (plan?.autoCall == true),
            "drills" to SosStore.drills(c),
            "readings" to SosStore.readings(c),
            "battery" to SosStore.battery(c),
            "accel" to (sensors?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null),
            "lowPower" to (sensors?.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION) != null),
            "location" to has(c, Manifest.permission.ACCESS_FINE_LOCATION),
            "background" to has(c, Manifest.permission.ACCESS_BACKGROUND_LOCATION),
            "sms" to has(c, Manifest.permission.SEND_SMS),
            "call" to has(c, Manifest.permission.CALL_PHONE),
            "phone" to has(c, Manifest.permission.READ_PHONE_STATE),
            "mic" to has(c, Manifest.permission.RECORD_AUDIO),
            "notify" to (nm?.areNotificationsEnabled() == true),
            "fullScreen" to (Build.VERSION.SDK_INT < 34 || nm?.canUseFullScreenIntent() == true),
            "battExempt" to (pm?.isIgnoringBatteryOptimizations(c.packageName) == true),
            "dialer" to SystemBridge.isDefaultDialer(c),
            "recognizer" to SpeechRecognizer.isRecognitionAvailable(c),
            "thaiVoice" to SosStore.thaiVoice(c),
            "ecc" to numbers.associateWith { SosService.eccOf(c, it) },
            "lastReport" to SosService.lastReport?.let { r ->
                mapOf(
                    "cancelled" to r.cancelled,
                    "drill" to r.drill,
                    "rehearsal" to r.rehearsal,
                    "voicePath" to r.voicePath,
                    "sent" to r.sent.map { s ->
                        when (val st = s.step) {
                            is SosStep.Sms -> mapOf("type" to "sms", "who" to st.who, "outcome" to s.outcome)
                            is SosStep.Call -> mapOf("type" to "call", "who" to st.who, "outcome" to s.outcome)
                        }
                    },
                )
            },
        )
    }

    private fun fix(c: Context): SosFix? = SosLocator(c).lastKnown()

    /** ทุกรูปแบบในก้อนเดียว · 🔒 Dart เรียกตอนเจ้าของเปิดดูเองเท่านั้น ไม่ลง log */
    private fun location(c: Context): Map<String, Any?>? {
        val f = fix(c) ?: return null
        val now = System.currentTimeMillis()
        return mapOf(
            "link" to SosText.mapLink(f),
            "coords" to SosText.coords(f),
            "plus" to PlusCode.encode(f.lat, f.lng),
            "accuracy" to f.accuracyM,
            "ageMs" to (now - f.atMs).coerceAtLeast(0),
        )
    }

    /**
     * เจ้าของกดส่งเอง · ไม่ส่งอัตโนมัติทางแอปแชท
     *
     * 🔴 LINE ไม่มี API ส่งหาคนอื่นจากแอปภายนอก · ทางที่มีคือ intent แชร์ (เจ้าของเลือกห้องแล้วกดส่งเอง)
     * หรือบริการการช่วยเหลือพิเศษ · ตอนเกิดเหตุไม่มีคนกด จึงใช้ SMS เป็นทางอัตโนมัติ
     */
    fun shareLocation(c: Context, target: String): Boolean {
        val app = c.applicationContext
        val plan = SosStore.plan(app)
        val texts = plan?.th
        val f = fix(app)
        val body = if (texts != null) SosText.locationBlock(f, System.currentTimeMillis(), texts)
        else f?.let { "${SosText.mapLink(it)}\n${SosText.coords(it)}" } ?: return false
        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, body)
        return try {
            when (target) {
                "copy" -> {
                    app.getSystemService(ClipboardManager::class.java)
                        ?.setPrimaryClip(ClipData.newPlainText("location", body))
                    true
                }
                "sms" -> {
                    c.startActivity(
                        Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:")).putExtra("sms_body", body)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                    true
                }
                "line" -> {
                    c.startActivity(send.setPackage(LINE_PACKAGE).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    true
                }
                else -> {
                    c.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    true
                }
            }
        } catch (e: RuntimeException) {
            android.util.Log.w("GigGokSos", "share: ${e.javaClass.simpleName}")
            false
        }
    }

    private fun open(c: Context, which: String): Boolean {
        val pkg = Uri.parse("package:${c.packageName}")
        val intent = when (which) {
            "fullScreen" -> if (Build.VERSION.SDK_INT >= 34) {
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, pkg)
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg)
            }
            "tts" -> Intent("com.android.settings.TTS_SETTINGS")
            else -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg)
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            c.startActivity(intent)
            true
        } catch (e: RuntimeException) {
            c.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, pkg).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        }
    }
}
