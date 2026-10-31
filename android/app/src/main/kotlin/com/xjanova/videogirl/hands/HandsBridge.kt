package com.xjanova.videogirl.hands

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import com.xjanova.videogirl.direct.setup.BankingPause
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.concurrent.Executors

/**
 * ช่อง `giggok/hands` · คู่กับ lib/hands/hands_bridge.dart (ชื่อเมธอด คีย์ และรหัสผิดพลาดต้องตรงกัน)
 *
 * งานช้า (รอจอนิ่ง รอบริการเชื่อม ปัดนิ้ว) ทำบนเธรดงานเดียว แล้วตอบกลับบนเธรดหลัก ·
 * ความผิดพลาดที่คาดไว้ตอบเป็นแผนที่ `{ok:false, error}` ไม่โยนเข้า Dart
 *
 * 🔒 ไม่ลง log เป้าหมายงาน ข้อความบนจอ หรือข้อความที่พิมพ์ · ลงแค่ชื่อเมธอดกับชนิดของข้อผิดพลาด
 * · ตั้งปลุกใช้สิทธิ์ปกติ com.android.alarm.permission.SET_ALARM (ประกาศใน manifest)
 */
object HandsBridge {
    private const val TAG = "GigGokHands"
    private val work = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /**
     * เรียกจาก SystemBridge.attach ทุกครั้งที่มี engine (ทั้ง engine ที่สายปลุก และของ Activity) ·
     * เรียกซ้ำได้: แค่ตั้ง handler ใหม่ทับบนช่องเดิม · เธรดงานกับสถานะเป็นของ object ตัวเดียว ไม่สร้างใหม่
     */
    fun attach(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, "giggok/hands").setMethodCallHandler { call, result ->
            try {
                handle(app, call, result)
            } catch (e: Exception) {
                Log.w(TAG, "${call.method}: ${e.javaClass.simpleName}")
                result.success(err("failed"))
            }
        }
    }

    private fun err(code: String): Map<String, Any> = mapOf("ok" to false, "error" to code)
    private val ok: Map<String, Any> = mapOf("ok" to true)

    private fun str(call: MethodCall, key: String): String = call.argument<Any>(key) as? String ?: ""
    private fun num(call: MethodCall, key: String): Number? = call.argument<Any>(key) as? Number

    /** งานช้า · ตอบบนเธรดหลัก · ไม่หลุด exception ไปถึง Dart */
    private fun slow(method: String, result: MethodChannel.Result, job: () -> Any?) {
        work.execute {
            val answer = try {
                job()
            } catch (e: Exception) {
                Log.w(TAG, "$method: ${e.javaClass.simpleName}")
                err("failed")
            }
            main.post { result.success(answer) }
        }
    }

    private fun handle(app: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(mapOf(
                "supported" to (Build.VERSION.SDK_INT >= 26),
                "enabled" to (MindHands.instance != null),
                "canAutoEnable" to HandsSwitch.canAutoEnable(app),
                "paused" to BankingPause.isPaused(app),
                "running" to HandsControl.running,
                "notifications" to NotificationManagerCompat.from(app).areNotificationsEnabled(),
            ))
            "begin" -> begin(app, call, result, record = false)
            "recordStart" -> begin(app, call, result, record = true)
            "progress" -> {
                if (HandsControl.running) {
                    HandsControl.line = str(call, "text").take(300)
                    HandsControl.step = num(call, "step")?.toInt() ?: HandsControl.step
                    HandsService.refresh(app)
                }
                result.success(true)
            }
            "end" -> {
                if (HandsControl.running) HandsService.end(app)
                result.success(true)
            }
            "recordStop" -> {
                val steps = HandsRecorder.take()
                if (HandsControl.recording) HandsService.end(app)
                result.success(mapOf("ok" to true, "steps" to steps))
            }
            "snapshot" -> {
                HandsControl.blockReason(app)?.let { return result.success(err(it)) }
                val max = num(call, "max")?.toInt() ?: 120
                val quiet = num(call, "quietMs")?.toLong() ?: 350L
                val wait = num(call, "maxWaitMs")?.toLong() ?: 2500L
                slow("snapshot", result) {
                    HandsControl.blockReason(app)?.let { err(it) }
                        ?: MindHands.instance?.snapshot(max, quiet.coerceIn(0L, 5_000L), wait.coerceIn(0L, 10_000L))
                        ?: err("not_enabled")
                }
            }
            "act" -> {
                HandsControl.blockReason(app)?.let { return result.success(err(it)) }
                val action = str(call, "do")
                val id = num(call, "id")?.toInt()
                val text = call.argument<Any>("text") as? String
                val dir = call.argument<Any>("dir") as? String
                slow("act", result) {
                    HandsControl.blockReason(app)?.let { err(it) }
                        ?: MindHands.instance?.act(action, id, text, dir)
                        ?: err("not_enabled")
                }
            }
            "openApp" -> {
                HandsControl.blockReason(app)?.let { return result.success(err(it)) }
                val name = str(call, "name")
                slow("openApp", result) { openApp(app, name) }
            }
            "setAlarm" -> {
                HandsControl.blockReason(app)?.let { return result.success(err(it)) }
                val intent = Intent(AlarmClock.ACTION_SET_ALARM)
                    .putExtra(AlarmClock.EXTRA_HOUR, (num(call, "hour")?.toInt() ?: 0).coerceIn(0, 23))
                    .putExtra(AlarmClock.EXTRA_MINUTES, (num(call, "minute")?.toInt() ?: 0).coerceIn(0, 59))
                    .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
                val label = str(call, "label")
                if (label.isNotEmpty()) intent.putExtra(AlarmClock.EXTRA_MESSAGE, label)
                result.success(launch(app, intent))
            }
            "addEvent" -> {
                HandsControl.blockReason(app)?.let { return result.success(err(it)) }
                val begin = num(call, "begin")?.toLong() ?: System.currentTimeMillis()
                val end = num(call, "end")?.toLong()?.takeIf { it >= begin } ?: (begin + 3_600_000L)
                // เปิดหน้าเพิ่มนัดของแอปปฏิทินให้เจ้าของกดบันทึกเอง · แอปนี้ไม่มีสิทธิ์เขียนปฏิทินโดยตั้งใจ
                val intent = Intent(Intent.ACTION_INSERT, CalendarContract.Events.CONTENT_URI)
                    .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, begin)
                    .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
                    .putExtra(CalendarContract.Events.TITLE, str(call, "title"))
                val location = str(call, "location")
                if (location.isNotEmpty()) intent.putExtra(CalendarContract.Events.EVENT_LOCATION, location)
                result.success(launch(app, intent))
            }
            "composeEmail" -> {
                HandsControl.blockReason(app)?.let { return result.success(err(it)) }
                val to = str(call, "to").trim()
                // เปิดหน้าเขียนอีเมลไว้ให้ · ยังไม่ส่ง (กดส่งเป็นขั้นที่ต้องถามเจ้าของ)
                val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:" + Uri.encode(to)))
                    .putExtra(Intent.EXTRA_SUBJECT, str(call, "subject"))
                    .putExtra(Intent.EXTRA_TEXT, str(call, "body"))
                if (to.isNotEmpty()) intent.putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
                result.success(launch(app, intent))
            }
            "poll" -> {
                val reply = HashMap<String, Any>()
                reply["stop"] = HandsControl.stopRequested
                HandsControl.takeAnswer()?.let { (id, allow) -> reply["confirm"] = mapOf("id" to id, "allow" to allow) }
                reply["recordDone"] = HandsControl.recordDone
                reply["running"] = HandsControl.running
                reply["recording"] = HandsControl.recording
                result.success(reply)
            }
            "askConfirm" -> {
                val id = num(call, "id")?.toInt()
                if (id != null) HandsService.ask(app, id, str(call, "title"), str(call, "body"))
                result.success(true)
            }
            "confirmDone" -> {
                num(call, "id")?.toInt()?.let { HandsService.askDone(app, it) }
                result.success(true)
            }
            "stop" -> {
                HandsService.requestStop(app)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /** begin / recordStart · ไม่ลง log เป้าหมายงาน */
    private fun begin(app: Context, call: MethodCall, result: MethodChannel.Result, record: Boolean) {
        if (HandsControl.active) return result.success(err("busy"))
        if (BankingPause.isPaused(app)) return result.success(err("paused"))
        if (!HandsControl.claim(record, str(call, "title").take(120), call.argument<Any>("inCall") == true)) {
            return result.success(err("busy"))
        }
        HandsSwitch.cancelIdleOff()
        if (record) HandsRecorder.start()
        work.execute {
            val error = try {
                HandsSwitch.ensure(app)
            } catch (e: Exception) {
                Log.w(TAG, "begin: ${e.javaClass.simpleName}")
                "not_enabled"
            }
            if (error != null) {
                HandsControl.release()
                // เปิดแล้วแต่ไม่เชื่อม · ไม่ทิ้งไว้เปิดค้าง
                try { HandsSwitch.disableIfOurs(app) } catch (_: Exception) {}
            }
            main.post {
                if (error != null) {
                    result.success(err(error))
                } else {
                    HandsService.start(app)
                    result.success(ok)
                }
            }
        }
    }

    /** เปิดหน้าของแอปอื่น · จาก context ของบริการถ้ามี (บริการการช่วยเหลือพิเศษเปิดหน้าจากเบื้องหลังได้) */
    private fun launch(app: Context, intent: Intent): Map<String, Any> {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            (MindHands.instance ?: app).startActivity(intent)
            ok
        } catch (_: ActivityNotFoundException) {
            err("not_found")
        } catch (e: Exception) {
            Log.w(TAG, "launch: ${e.javaClass.simpleName}")
            err("failed")
        }
    }

    private fun openApp(app: Context, name: String): Map<String, Any> {
        HandsControl.blockReason(app)?.let { return err(it) }
        val query = name.trim()
        if (query.isEmpty()) return mapOf("ok" to false, "error" to "not_found", "candidates" to emptyList<String>())
        var pkg: String? = null
        var label = ""
        if (query.contains('.') && !query.contains(' ') && HandsPolicy.isLaunchable(app, query)) {
            pkg = query
            label = HandsPolicy.label(app, query)
        }
        val apps by lazy { HandsPolicy.launcherApps(app) }
        if (pkg == null) {
            val q = query.lowercase(Locale.ROOT)
            val qc = q.replace(" ", "")
            var best: Pair<String, String>? = null
            var bestScore = 0
            for (a in apps) {
                val l = a.second.lowercase(Locale.ROOT)
                val lc = l.replace(" ", "")
                if (l.isEmpty()) continue
                val score = when {
                    l == q || lc == qc -> 3
                    l.startsWith(q) || lc.startsWith(qc) -> 2
                    l.contains(q) || lc.contains(qc) -> 1
                    else -> 0
                }
                if (score > bestScore || (score == bestScore && score > 0 && a.second.length < (best?.second?.length ?: Int.MAX_VALUE))) {
                    best = a
                    bestScore = score
                }
            }
            best?.let {
                pkg = it.first
                label = it.second
            }
        }
        val target = pkg
        if (target == null) {
            val qc = query.lowercase(Locale.ROOT).replace(" ", "")
            val near = apps.filter { it.second.isNotEmpty() && !HandsPolicy.isBlocked(app, it.first) }
                .sortedBy { distance(qc, it.second.lowercase(Locale.ROOT).replace(" ", "")) }
                .take(5)
                .map { it.second }
            return mapOf("ok" to false, "error" to "not_found", "candidates" to near)
        }
        if (HandsPolicy.isBlocked(app, target)) return mapOf("ok" to false, "error" to "blocked", "label" to label)
        HandsControl.blockReason(app)?.let { return err(it) }
        val intent = app.packageManager.getLaunchIntentForPackage(target)
            ?: return mapOf("ok" to false, "error" to "not_found", "candidates" to emptyList<String>())
        val r = launch(app, intent)
        return if (r["ok"] == true) mapOf("ok" to true, "package" to target, "label" to label) else r
    }

    /** ระยะห่างของคำ (Levenshtein) · ใช้เสนอชื่อแอปที่ใกล้ที่สุดตอนหาไม่เจอ */
    private fun distance(a: String, b: String): Int {
        if (a.isEmpty()) return b.length
        if (b.isEmpty()) return a.length
        var prev = IntArray(b.length + 1) { it }
        var cur = IntArray(b.length + 1)
        for (i in 1..a.length) {
            cur[0] = i
            for (j in 1..b.length) {
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                cur[j] = minOf(cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost)
            }
            val t = prev
            prev = cur
            cur = t
        }
        return prev[b.length]
    }
}
