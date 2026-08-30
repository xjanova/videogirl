package com.xjanova.videogirl

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentUris
import android.content.Intent
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.CalendarContract
import android.provider.Settings
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * สะพานขอสิทธิ์กล้อง สำหรับกล้องเชิดหุ่น (mocap ใบหน้า)
 *
 * ทำไมไม่ใช้ permission_handler: เวอร์ชันล่าสุดใช้ Kotlin DSL แบบใหม่ใน
 * build.gradle.kts ของตัวเอง ซึ่ง resolve ไม่ผ่านกับชุด AGP 8.11 / Kotlin 2.2.20
 * ของโปรเจกต์นี้ (Unresolved reference: compilerOptions) การไล่ปักหมุดเวอร์ชันเก่า
 * ก็เสี่ยงพังอีกทางเพราะ toolchain ที่นี่ใหม่กว่าที่แพ็กเกจเก่ารองรับ
 * เราต้องการแค่สิทธิ์เดียว โค้ดสี่สิบบรรทัดจึงคุ้มกว่าการพึ่งแพ็กเกจทั้งก้อน
 *
 * 🔴 ทำไมต้องมีชั้นนี้เลย: ปลั๊กอิน WebView **ไม่ได้ขอสิทธิ์ระดับระบบให้**
 * onPermissionRequest ของมันเรียกแค่ request.grant() ซึ่งเป็นการอนุญาตในชั้นเว็บ
 * ถ้าแอปไม่มีสิทธิ์ CAMERA จริง getUserMedia จะถูกปฏิเสธโดยไม่มีอะไรบอกว่าทำไม
 */
class MainActivity : FlutterActivity() {

    private val calls by lazy { CallBridge(this) }

    /// ช่องคุยกับ Dart — เก็บไว้เพื่อ **ยิงกลับ** ตอนสายเข้า
    /// ไม่ใช่แค่ตอบคำถามที่ Dart ถามมา
    private var channel: MethodChannel? = null

    private var phoneListener: Any? = null

    private var pending: MethodChannel.Result? = null
    private var pendingNotify: MethodChannel.Result? = null

    /// สิทธิ์ที่ค้างอยู่ — ต้องจำไว้เพราะ shouldShowRequestPermissionRationale
    /// ถามเป็นรายสิทธิ์ ถามผิดตัวจะได้คำตอบของสิทธิ์อื่น
    private var pendingPermission: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureWatchChannel()
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(if (granted()) GRANTED else DENIED)
                    "request" -> request(result)
                    "openSettings" -> {
                        openAppSettings()
                        result.success(true)
                    }

                    // ── งานเบื้องหลัง ────────────────────────────
                    "batteryExempt" -> result.success(batteryExempt())
                    "requestBatteryExempt" -> {
                        requestBatteryExempt()
                        result.success(true)
                    }
                    "notifyGranted" -> result.success(notifyGranted())
                    "requestNotify" -> requestNotify(result)

                    // ── ไมค์ ─────────────────────────────────────
                    "micGranted" -> result.success(granted(Manifest.permission.RECORD_AUDIO))
                    "requestMic" -> ask(Manifest.permission.RECORD_AUDIO, REQ_MIC, result)

                    // ── ปฏิทินของเครื่อง ─────────────────────────
                    "calendarGranted" ->
                        result.success(granted(Manifest.permission.READ_CALENDAR))
                    "requestCalendar" ->
                        ask(Manifest.permission.READ_CALENDAR, REQ_CALENDAR, result)
                    "readCalendar" -> readCalendar(
                        (call.argument<Number>("from") ?: 0).toLong(),
                        (call.argument<Number>("to") ?: 0).toLong(),
                        result
                    )

                    // ── สายโทรเข้า ───────────────────────────────
                    "callGranted" -> result.success(calls.canReadCalls())
                    "requestCall" -> askMany(
                        arrayOf(
                            Manifest.permission.READ_PHONE_STATE,
                            Manifest.permission.READ_CALL_LOG
                        ),
                        REQ_CALL, result
                    )
                    "contactsGranted" -> result.success(calls.canReadContacts())
                    "requestContacts" ->
                        ask(Manifest.permission.READ_CONTACTS, REQ_CONTACTS, result)
                    "answerGranted" -> result.success(calls.canAnswer())
                    "requestAnswer" -> askMany(
                        arrayOf(Manifest.permission.ANSWER_PHONE_CALLS),
                        REQ_ANSWER, result
                    )
                    "recentCalls" ->
                        result.success(calls.recentCalls(call.argument<Int>("limit") ?: 30))
                    "answerCall" -> result.success(calls.answer())
                    "hangUp" -> result.success(calls.hangUp())
                    "watchCalls" -> {
                        watchCalls()
                        result.success(true)
                    }

                    // ── ติดตั้งแอปที่ไม่รู้จัก ────────────────────
                    "canInstall" -> result.success(canInstall())
                    "requestInstall" -> {
                        requestInstall()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun granted(permission: String) = ContextCompat.checkSelfPermission(
        this, permission
    ) == PackageManager.PERMISSION_GRANTED

    private fun granted() = granted(Manifest.permission.CAMERA)

    private fun request(result: MethodChannel.Result) =
        ask(Manifest.permission.CAMERA, REQ_CAMERA, result)

    /**
     * ขอสิทธิ์หนึ่งตัว แล้วตอบกลับเป็น granted / denied / blocked
     *
     * ตัวเดียวใช้ได้ทุกสิทธิ์ เพราะการแยก "ปฏิเสธแต่ถามใหม่ได้" ออกจาก
     * "ปฏิเสธถาวร" เป็นตรรกะเดียวกันหมด และเป็นจุดที่พลาดง่ายที่สุด
     */
    private fun ask(permission: String, code: Int, result: MethodChannel.Result) {
        if (granted(permission)) {
            result.success(GRANTED)
            return
        }
        // มีคำขอค้างอยู่แล้ว — ตอบตัวเก่าว่าถูกยกเลิก ไม่งั้น Future ฝั่ง Dart
        // จะค้างตลอดกาลและปุ่มจะกดไม่ได้อีกเลยทั้งเซสชัน
        pending?.success(DENIED)
        pending = result
        pendingPermission = permission
        ActivityCompat.requestPermissions(this, arrayOf(permission), code)
    }

    /**
     * ติดตั้ง APK ที่โหลดมาเองได้ไหม
     *
     * 🔴 ถ้าไม่ได้ auto-update จะโหลดไฟล์จนจบ (หลายร้อยเมก) แล้วค่อยล้ม
     * ตรงขั้นสุดท้าย · ต้องเช็ค**ก่อน**เริ่มโหลด ไม่ใช่ค้นพบตอนจบ
     *
     * Android 8+ สิทธิ์นี้ให้ทีละแอป และ**ขอผ่านกล่องปกติไม่ได้**
     * ต้องพาไปหน้าตั้งค่าของระบบเท่านั้น
     */
    private fun canInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= 26) packageManager.canRequestPackageInstalls() else true

    private fun requestInstall() {
        if (canInstall()) return
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
            .setData(Uri.parse("package:" + packageName))
        try {
            startActivity(intent)
        } catch (e: Exception) {
            openAppSettings()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode == REQ_NOTIFY) {
            val reply = pendingNotify ?: return
            pendingNotify = null
            reply.success(grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED)
            return
        }

        // 🔴 เคยเขียนเป็น `if (requestCode != REQ_CAMERA && != REQ_MIC) return`
        //
        // ทุกสิทธิ์ที่เพิ่มเข้ามาทีหลัง (ปฏิทิน สาย สมุดโทรศัพท์ รับสาย) จึงหลุด
        // ออกทางนี้โดยไม่ตอบ `pending` เลย · ผลคือ Future ฝั่ง Dart **ค้างตลอด
        // กาล** และเพราะ MindPermissions.request() ตั้ง _busy ไว้จนกว่าจะได้
        // คำตอบ **ปุ่มขอสิทธิ์ทั้งแอปก็ตายตามไปด้วยทั้งเซสชัน**
        //
        // ไม่มี error ไม่มี log · ผู้ใช้เห็นแค่ปุ่มที่กดแล้วไม่มีอะไรเกิดขึ้น
        // เพิ่มสิทธิ์ใหม่เมื่อไหร่ ต้องเพิ่มรหัสตรงนี้ด้วยเสมอ
        if (requestCode !in KNOWN_REQUESTS) return

        val reply = pending ?: return
        val which = pendingPermission ?: Manifest.permission.CAMERA
        pending = null
        pendingPermission = null

        // ต้องได้ **ครบทุกตัว** ที่ขอไป ไม่ใช่แค่ตัวแรก
        //
        // สายขอ READ_PHONE_STATE คู่กับ READ_CALL_LOG · ถ้าดูแค่ตัวแรก
        // คนที่ให้ตัวเดียวจะถูกนับว่าให้ครบ แล้วฟีเจอร์ทำงานครึ่ง ๆ
        // โดยที่ UI บอกว่าเรียบร้อย
        val ok = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }

        // แยก "ปฏิเสธแต่ถามใหม่ได้" ออกจาก "ปฏิเสธถาวร" ให้ได้ ไม่งั้น UI จะบอก
        // ให้กดใหม่ทั้งที่กดไปก็ไม่มีอะไรขึ้น
        //
        // shouldShowRequestPermissionRationale เป็น false ได้สองกรณี คือ
        // "ยังไม่เคยถาม" กับ "ปฏิเสธถาวร" — แต่ตรงนี้เราเพิ่งถามไปหมาด ๆ
        // กรณีแรกจึงถูกตัดออกไปเอง ไม่ต้องจำสถานะลงดิสก์ให้ยุ่ง
        val canAskAgain = ActivityCompat.shouldShowRequestPermissionRationale(this, which)

        reply.success(if (ok) GRANTED else if (canAskAgain) DENIED else BLOCKED)
    }

    /**
     * สร้างช่องแจ้งเตือนของบริการเบื้องหลัง
     *
     * 🔴 ไม่มีช่องนี้ = `startForeground` โยน
     * `CannotPostForegroundServiceNotificationException` ทันทีที่บริการเริ่ม
     * แล้วบริการตายก่อนทำอะไรสักอย่าง · Android ไม่ได้บอกว่า "ไม่มีช่อง"
     * มันบอกแค่ "Bad notification" ซึ่งชี้ไปผิดทางว่าเนื้อการแจ้งเตือนมีปัญหา
     *
     * ปลั๊กอิน flutter_background_service **ไม่ได้สร้างช่องให้** มันแค่ใช้ id
     * ที่เราส่งไป · ต้องสร้างที่นี่ ฝั่ง native เพราะช่องต้องมีอยู่ก่อน
     * บริการจะเริ่ม และตอนบริการเริ่ม isolate ฝั่ง Dart ยังไม่ทันรัน
     *
     * IMPORTANCE_LOW เพราะเป็นการแจ้งเตือนค้างที่ต้องอยู่ทั้งวัน
     * ถ้าดังหรือเด้ง heads-up ทุกครั้งที่อัปเดตข้อความ คนจะปิดแอปทิ้ง
     */
    private fun ensureWatchChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        if (nm.getNotificationChannel(WATCH_CHANNEL) != null) return
        nm.createNotificationChannel(
            NotificationChannel(
                WATCH_CHANNEL,
                "GigGok",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
        )
    }

    /// 🔴 ตัวชี้ขาดว่างานเบื้องหลังจะเชื่อถือได้ไหม
    ///
    /// ไม่ได้ยกเว้น = ระบบหรี่ให้ตื่นทุก 9–15 นาทีแทนที่จะเป็นตามที่ตั้งไว้
    /// และบาง ROM (Xiaomi/Huawei/OPPO) ฆ่าทิ้งเลย · ประกาศใน manifest
    /// อย่างเดียวไม่พอ ผู้ใช้ต้องกดยอมรับเองเท่านั้น
    private fun batteryExempt(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun requestBatteryExempt() {
        if (batteryExempt()) return
        // กล่องขอตรง ๆ ก่อน · เครื่องที่ไม่มี activity รองรับ (บาง ROM ถอดออก)
        // ให้ตกไปหน้าตั้งค่าแบตของระบบแทน ดีกว่าไม่เกิดอะไรขึ้นเลย
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
            .setData(Uri.parse("package:" + packageName))
        val fallback = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        val intent = if (direct.resolveActivity(packageManager) != null) direct else fallback
        try {
            startActivity(intent)
        } catch (e: Exception) {
            openAppSettings()
        }
    }

    /// Android 13+ การแจ้งเตือนเป็นสิทธิ์ที่ต้องขอ · ไม่ได้ขอ = บริการรันอยู่จริง
    /// แต่ผู้ใช้ไม่เห็นอะไรเลย แล้วจะคิดว่ามันไม่ทำงาน
    private fun notifyGranted(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return ContextCompat.checkSelfPermission(
            this, "android.permission.POST_NOTIFICATIONS"
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestNotify(result: MethodChannel.Result) {
        if (notifyGranted()) {
            result.success(true)
            return
        }
        pendingNotify?.success(false)
        pendingNotify = result
        ActivityCompat.requestPermissions(
            this, arrayOf("android.permission.POST_NOTIFICATIONS"), REQ_NOTIFY
        )
    }

    /**
     * อ่านนัดจากปฏิทินของเครื่องในช่วงเวลาที่ขอมา
     *
     * ใช้ `Instances` ไม่ใช่ `Events` เพราะนัดที่เกิดซ้ำทุกสัปดาห์มีแถวเดียว
     * ใน `Events` แต่มีทุกครั้งใน `Instances` · ถามจาก `Events` ตรง ๆ จะได้
     * ประชุมประจำสัปดาห์มาแค่ครั้งแรกครั้งเดียว แล้วสัปดาห์อื่นหายหมด
     * โดยไม่มีอะไรบอกว่าขาด
     *
     * 🔴 ทำในเธรดอื่น ไม่ใช่เธรดหลัก · ContentResolver ของปฏิทินช้าได้จริง
     * บนเครื่องที่ซิงก์หลายบัญชี และ MethodChannel เรียกบนเธรด UI
     */
    private fun readCalendar(from: Long, to: Long, result: MethodChannel.Result) {
        if (!granted(Manifest.permission.READ_CALENDAR)) {
            result.success(null)
            return
        }
        if (to <= from) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }

        Thread {
            val events = try {
                queryInstances(from, to)
            } catch (e: Exception) {
                // ปฏิทินอ่านไม่ได้ไม่ควรทำให้ทั้งแท็บพัง — คืน null แปลว่า
                // "ถามไม่สำเร็จ" ซึ่งต่างจาก emptyList ที่แปลว่า "ไม่มีนัด"
                null
            }
            runOnUiThread { result.success(events) }
        }.start()
    }

    private fun queryInstances(from: Long, to: Long): List<Map<String, Any?>> {
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().let {
            ContentUris.appendId(it, from)
            ContentUris.appendId(it, to)
            it.build()
        }
        val cols = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
            CalendarContract.Instances.DISPLAY_COLOR,
            CalendarContract.Instances.SELF_ATTENDEE_STATUS
        )

        val out = ArrayList<Map<String, Any?>>()
        contentResolver.query(uri, cols, null, null, CalendarContract.Instances.BEGIN + " ASC")
            ?.use { c ->
                while (c.moveToNext()) {
                    // นัดที่เจ้าของกดปฏิเสธไปแล้ว ไม่ใช่ตารางของเขา
                    val status = c.getInt(8)
                    if (status == CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED) continue

                    out.add(
                        mapOf(
                            "id" to c.getLong(0),
                            "title" to (c.getString(1) ?: ""),
                            "begin" to c.getLong(2),
                            "end" to c.getLong(3),
                            "allDay" to (c.getInt(4) == 1),
                            "location" to c.getString(5),
                            "calendar" to c.getString(6),
                            "color" to c.getInt(7)
                        )
                    )
                }
            }
        return out
    }

    /**
     * ขอสิทธิ์หลายตัวพร้อมกัน
     *
     * แยกจาก [ask] เพราะสายต้องใช้ READ_PHONE_STATE **คู่กับ** READ_CALL_LOG
     * เสมอ (ไม่งั้นเบอร์ที่โทรเข้าจะว่างเปล่าโดยไม่มีอะไรบอก) การขอทีละตัว
     * แปลว่าผู้ใช้อาจให้ตัวเดียว แล้วฟีเจอร์ทำงานครึ่ง ๆ อย่างเงียบที่สุด
     */
    private fun askMany(
        permissions: Array<String>,
        code: Int,
        result: MethodChannel.Result,
    ) {
        if (permissions.all { granted(it) }) {
            result.success(GRANTED)
            return
        }
        pending?.success(DENIED)
        pending = result
        pendingPermission = permissions.first()
        ActivityCompat.requestPermissions(this, permissions, code)
    }

    /**
     * เฝ้าสถานะสาย แล้วบอก Dart ทุกครั้งที่เปลี่ยน
     *
     * 🔴 เบอร์ที่ได้จากตรงนี้ **ว่างเปล่าบน Android 9+ ถ้าไม่มี READ_CALL_LOG**
     * และไม่มี error อะไรบอก · ฝั่ง Dart จึงต้องเผื่อเบอร์ว่างเสมอ และไปอ่าน
     * จากบันทึกการโทรหลังสายจบแทน
     */
    private fun watchCalls() {
        if (phoneListener != null) return
        val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager ?: return

        if (Build.VERSION.SDK_INT >= 31) {
            val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) = sendCallState(state, null)
            }
            phoneListener = cb
            tm.registerTelephonyCallback(mainExecutor, cb)
        } else {
            @Suppress("DEPRECATION")
            val l = object : PhoneStateListener() {
                override fun onCallStateChanged(state: Int, phoneNumber: String?) =
                    sendCallState(state, phoneNumber)
            }
            phoneListener = l
            @Suppress("DEPRECATION")
            tm.listen(l, PhoneStateListener.LISTEN_CALL_STATE)
        }
    }

    private fun sendCallState(state: Int, number: String?) {
        channel?.invokeMethod(
            "onCallState",
            mapOf(
                "state" to state,
                "number" to number,
                "name" to calls.nameFor(number)
            )
        )
    }

    private fun openAppSettings() {
        startActivity(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", packageName, null)
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    companion object {
        private const val CHANNEL = "giggok/system"
        private const val REQ_CAMERA = 8747
        private const val REQ_NOTIFY = 8748
        private const val REQ_MIC = 8749
        private const val REQ_CALENDAR = 8750
        private const val REQ_CALL = 8751
        private const val REQ_CONTACTS = 8752
        private const val REQ_ANSWER = 8753

        /// รหัสคำขอทุกตัวที่ [ask] / [askMany] ใช้
        ///
        /// ต้องครบ ไม่งั้นคำขอที่หายไปจะไม่มีใครตอบ แล้วปุ่มขอสิทธิ์
        /// ทั้งแอปค้างทั้งเซสชัน · ดู onRequestPermissionsResult
        private val KNOWN_REQUESTS = setOf(
            REQ_CAMERA, REQ_MIC, REQ_CALENDAR, REQ_CALL, REQ_CONTACTS, REQ_ANSWER
        )

        /// ต้องตรงกับ kMindChannelId ใน lib/background/mind_background.dart
        /// ไม่ตรงกัน = บริการหาช่องไม่เจอ แล้วตายแบบเดียวกับไม่มีช่องเลย
        private const val WATCH_CHANNEL = "mind_watch"
        private const val GRANTED = "granted"
        private const val DENIED = "denied"
        private const val BLOCKED = "blocked"
    }
}
