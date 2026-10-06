package com.xjanova.videogirl

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.role.RoleManager
import android.content.ContentUris
import android.content.Intent
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.os.Bundle
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.CalendarContract
import android.provider.Settings
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telecom.TelecomManager
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

    /// ถอดเสียงในเครื่อง — ช่องแยกจาก giggok/system โดยตั้งใจ
    /// (ฝั่ง Dart ของช่องนั้นมี CallWatch เป็นเจ้าของ handler แต่ผู้เดียว)
    private val speech by lazy { MindSpeech(this) }

    /// สตูดิโอ — จอลอย จอไม่ดับ เก็บคลิปลงแกลเลอรี · ช่องแยกเหมือนตัวถอดเสียง
    private val studio by lazy { MindStudio(this) }

    /// ช่องคุยกับ Dart — เก็บไว้เพื่อ **ยิงกลับ** ตอนสายเข้า
    /// ไม่ใช่แค่ตอบคำถามที่ Dart ถามมา
    private var channel: MethodChannel? = null

    private var pending: MethodChannel.Result? = null
    private var pendingNotify: MethodChannel.Result? = null

    /// สิทธิ์ที่ค้างอยู่ — ต้องจำไว้เพราะ shouldShowRequestPermissionRationale
    /// ถามเป็นรายสิทธิ์ ถามผิดตัวจะได้คำตอบของสิทธิ์อื่น
    private var pendingPermission: String? = null

    /**
     * engine ก้อนเดียวของทั้งแอป (ดู [MindEngine]) แทนการสร้างของตัวเอง
     *
     * 🔴 สายเข้าตอนแอปปิด จอสายปลุกตัวเธอขึ้นมาก่อนแล้ว · เปิดแอปตอนนั้นต้องได้
     * ตัวเดิมที่กำลังคุยในสายอยู่ ไม่ใช่ตัวใหม่อีกตัวที่ไม่รู้ว่ามีสาย
     * · สร้างไม่ได้ด้วยเหตุใดก็ตาม = คืน null แล้ว FlutterActivity สร้างเองแบบเดิม
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine? = try {
        MindEngine.obtain(context)
    } catch (e: Throwable) {
        null
    }

    /**
     * Activity ตาย → engine ตายด้วย **เหมือนเดิม** ยกเว้นตอนมีสายอยู่
     *
     * 🔴 engine ที่อยู่ต่อหลัง Activity ตาย = เวที (WebView) ของ Activity เก่าถูกทิ้ง
     * แต่ฝั่ง Dart ยังคิดว่ามีอยู่ · เปิดแอปใหม่แล้วตัวเธอไม่ขึ้น · เก็บ engine ไว้
     * เฉพาะตอนเธอยังคุยสายอยู่ (ฆ่าตอนนั้น = ตัดบทกลางสาย) แล้วบอก Dart ให้ทิ้ง
     * เวทีไปสร้างใหม่ตอนจอกลับมา (ดู onDestroy)
     */
    override fun shouldDestroyEngineWithHost(): Boolean {
        val e = engine ?: return super.shouldDestroyEngineWithHost()
        // engine ที่ไม่ได้มาจาก MindEngine = ของ Activity นี้เอง · ทำแบบเดิม
        if (MindEngine.bridgeOf(e) == null) return super.shouldDestroyEngineWithHost()
        return MindInCallService.service == null
    }

    /// ช่องส่วนที่ไม่ต้องมีจอ · ของ engine ก้อนนี้ (อยู่ต่อหลัง Activity ตาย)
    private var bridge: SystemBridge? = null
    private var engine: FlutterEngine? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        dartAlive = true
        engine = flutterEngine
        ensureWatchChannel()
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // engine ที่ไม่ได้มาจาก MindEngine (สร้างไม่สำเร็จ) ต้องมีช่องของตัวเอง
        val b = MindEngine.bridgeOf(flutterEngine)
            ?: SystemBridge(applicationContext).also { it.attach(messenger) }
        bridge = b
        speech.attach(messenger)
        studio.attach(messenger)
        channel = MethodChannel(messenger, CHANNEL)
        channel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "request" -> request(result)
                    "openSettings" -> {
                        openAppSettings()
                        result.success(true)
                    }
                    "hasScreen" -> result.success(true)

                    // ── งานเบื้องหลัง ────────────────────────────
                    "requestBatteryExempt" -> {
                        requestBatteryExempt()
                        result.success(true)
                    }
                    "requestNotify" -> requestNotify(result)

                    // ── สิทธิ์ที่ต้องมีจอให้กด ───────────────────
                    "requestMic" -> ask(Manifest.permission.RECORD_AUDIO, REQ_MIC, result)
                    "requestCalendar" ->
                        ask(Manifest.permission.READ_CALENDAR, REQ_CALENDAR, result)
                    "requestCall" -> askMany(
                        arrayOf(
                            Manifest.permission.READ_PHONE_STATE,
                            Manifest.permission.READ_CALL_LOG
                        ),
                        REQ_CALL, result
                    )
                    "requestContacts" ->
                        ask(Manifest.permission.READ_CONTACTS, REQ_CONTACTS, result)
                    "requestAnswer" -> askMany(
                        arrayOf(Manifest.permission.ANSWER_PHONE_CALLS),
                        REQ_ANSWER, result
                    )

                    // ── แอปโทรศัพท์หลัก ──────────────────────────
                    "requestDefaultDialer" -> {
                        requestDefaultDialer()
                        result.success(true)
                    }

                    // ปุ่มย้อนกลับที่หน้าแรก = พักแอปไว้เบื้องหลัง ไม่ใช่ปิด
                    "moveToBack" -> result.success(moveTaskToBack(true))
                    "exitApp" -> {
                        result.success(true)
                        exitApp()
                    }

                    // ── ไฟล์ทั้งเครื่อง (สำเนาที่รอดการถอนแอป) ────
                    "requestAllFiles" -> {
                        requestAllFiles()
                        result.success(true)
                    }

                    // ── ติดตั้งแอปที่ไม่รู้จัก ────────────────────
                    "requestInstall" -> {
                        requestInstall()
                        result.success(true)
                    }

                    // ที่เหลือ (ถามสิทธิ์ สาย ปฏิทิน เสียงในสาย ฯลฯ) ไม่ต้องมีจอ
                    // · ตัวเดียวกับที่ตอบตอนเธอถูกปลุกมาคุยในสายเบื้องหลัง
                    else -> if (!b.handle(call, result)) result.notImplemented()
                }
            }
    }

    private fun granted(permission: String) = ContextCompat.checkSelfPermission(
        this, permission
    ) == PackageManager.PERMISSION_GRANTED

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

    /// ดู [SystemBridge.canInstall] · ขอผ่านกล่องปกติไม่ได้ ต้องพาไปหน้าตั้งค่าของระบบ
    private fun canInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= 26) packageManager.canRequestPackageInstalls() else true

    /// ดู [SystemBridge.allFilesGranted] — สำเนาที่รอดจากการถอนแอป
    private fun allFilesGranted(): Boolean =
        if (Build.VERSION.SDK_INT >= 30) {
            Environment.isExternalStorageManager()
        } else {
            granted(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }

    /**
     * ขอสิทธิ์ไฟล์ทั้งเครื่อง
     *
     * เหมือนสิทธิ์ติดตั้งแอป: **ขอผ่านกล่องปกติไม่ได้** ต้องพาไปหน้าตั้งค่า
     * ของระบบ แล้วรู้ผลตอนผู้ใช้กลับมา (ฝั่ง Dart refresh ตอน resumed)
     */
    private fun requestAllFiles() {
        if (allFilesGranted()) return
        if (Build.VERSION.SDK_INT < 30) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                REQ_ALL_FILES
            )
            return
        }
        // หน้าเฉพาะแอปเรามาก่อน · ถ้าเครื่องไหนไม่มี ค่อยตกไปหน้ารวม
        // แล้วผู้ใช้ต้องเลื่อนหาชื่อแอปเอง ซึ่งแย่กว่าแต่ยังทำได้
        val direct = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
            .setData(Uri.parse("package:" + packageName))
        try {
            startActivity(direct)
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            } catch (e2: Exception) {
                openAppSettings()
            }
        }
    }

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

    /// ปล่อยตัวถอดเสียงตอนแอปถูกทำลาย
    ///
    /// SpeechRecognizer จองไมค์กับบริการของระบบไว้ · ไม่ปล่อยแล้วปิดแอป
    /// ตอนที่ยังฟังอยู่ = ไมค์ค้างจนกว่าระบบจะเก็บกวาดเอง ซึ่งอาจนาน
    ///
    /// 🔴 engine อยู่ต่อหลัง Activity ตาย (ดู [MindEngine]) · คืนช่อง giggok/system
    /// ให้ตัวที่ไม่ต้องมีจอ ไม่งั้นทุกคำถามของ Dart วิ่งเข้า Activity ที่ตายแล้ว
    override fun onDestroy() {
        speech.dispose()
        studio.detach()
        val e = engine
        val b = bridge
        if (e != null && b != null && MindEngine.bridgeOf(e) === b && !shouldDestroyEngineWithHost()) {
            b.reclaim(e.dartExecutor.binaryMessenger)
            // เวทีของ Activity นี้ตายไปด้วย · Dart ต้องทิ้งแล้วสร้างใหม่ตอนจอกลับมา
            MethodChannel(e.dartExecutor.binaryMessenger, LIFE_CHANNEL).invokeMethod("viewGone", null)
        }
        if (live?.get() === this) live = null
        dartAlive = false
        // 🔴 super ก่อน แล้วค่อยลืม engine · FlutterActivity ถาม shouldDestroyEngineWithHost
        // ระหว่าง super.onDestroy ซึ่งต้องยังเห็น engine ไม่งั้นตอบผิดแล้ว engine ไม่ถูกปิด
        super.onDestroy()
        engine = null
    }

    /// ปุ่มเพิ่ม/ลดเสียงตอนอยู่ในแอป = เสียงสื่อ (ช่องที่เสียงเธอออก)
    ///
    /// 🔴 ไม่ตั้ง = ตอนเธอเงียบอยู่ ปุ่มเสียงไปปรับเสียงเรียกเข้าแทน · คนที่ได้ยิน
    /// เธอเบาแล้วกดเพิ่มเสียง จะเพิ่มผิดช่องแล้วเธอเบาเท่าเดิม
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        volumeControlStream = AudioManager.STREAM_MUSIC
        live = java.lang.ref.WeakReference(this)
        overLockFrom(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        overLockFrom(intent)
    }

    /// ขึ้นทับจอล็อกอยู่ไหม (เฉพาะระหว่างสายที่เธอถือ)
    private var overLock = false

    /**
     * จอสายขอให้ขึ้นทับจอล็อก — เจ้าของเห็นเธอคุยสายโดยไม่ต้องปลดล็อก
     *
     * 🔴 รับเฉพาะตอนเธอถือสายอยู่จริง · intent เก่าที่ค้างมา (เปิดแอปซ้ำจากประวัติ)
     * ต้องไม่ทำให้แอปทั้งแอปขึ้นทับจอล็อกได้นอกเวลาสาย
     */
    private fun overLockFrom(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_OVER_LOCK, false) != true) return
        intent.removeExtra(EXTRA_OVER_LOCK)
        if (!MindInCallService.mindHandling) return
        setOverLock(true)
    }

    private fun setOverLock(on: Boolean) {
        overLock = on
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(on)
            setTurnScreenOn(on)
        } else {
            @Suppress("DEPRECATION")
            val flags = android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (on) window.addFlags(flags) else window.clearFlags(flags)
        }
    }

    /// ปิดแอปจริง — ทางเดียวที่คืนหน่วยความจำของสมองในเครื่องกับตัวเธอทั้งหมด
    ///
    /// 🔴 `finish()` อย่างเดียวไม่พอ · โปรเซสยังอยู่ (บริการเฝ้างานอยู่ในโปรเซส
    /// เดียวกัน) และหน่วยความจำของ Dart/WebView ที่ระบบยังไม่เก็บก็ยังค้าง ·
    /// ปิดหน้าทิ้งจากรายการแอปล่าสุดก่อน แล้วค่อยจบโปรเซส ให้ฝั่ง Dart ตอบกลับ
    /// ทันก่อน (ไม่งั้นช่องสื่อสารค้างครึ่งทาง)
    private fun exitApp() {
        dartAlive = false
        finishAndRemoveTask()
        android.os.Handler(mainLooper).postDelayed({
            android.os.Process.killProcess(android.os.Process.myPid())
        }, 400)
    }

    /// เข้า/ออกจอลอย — ฝั่ง Dart ซ่อนปุ่มทั้งหมดตอนเหลือแต่ตัวเธอในหน้าต่างเล็ก
    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        studio.onPipChanged(isInPictureInPictureMode)
    }

    /// กด Home ตอนอยู่ในสตูดิโอ = ย่อเป็นจอลอย (Android 12 ขึ้นไประบบทำเอง)
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        studio.onUserLeaveHint()
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
    private fun batteryExempt(): Boolean =
        bridge?.batteryExempt() ?: SystemBridge(applicationContext).batteryExempt()

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
    private fun requestNotify(result: MethodChannel.Result) {
        if (SystemBridge(applicationContext).notifyGranted()) {
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
     * ขอเป็นแอปโทรศัพท์หลัก
     *
     * 🔴 **เป็นแล้วทุกสายของเครื่องผ่านแอปนี้** ไม่ใช่แค่สายที่เราสนใจ
     * ถ้า InCallActivity หรือ DialerActivity พัง เจ้าของโทรออกรับสายไม่ได้
     * ทั้งเครื่อง · ผู้ใช้ต้องกดยอมรับเองเสมอ ระบบไม่ยอมให้ตั้งเงียบ ๆ
     * และถอนออกได้ตลอดจากหน้าตั้งค่าของเครื่อง
     */
    private fun requestDefaultDialer() {
        if (SystemBridge.isDefaultDialer(this)) return
        try {
            val intent = if (Build.VERSION.SDK_INT >= 29) {
                getSystemService(RoleManager::class.java)
                    ?.createRequestRoleIntent(RoleManager.ROLE_DIALER)
            } else {
                @Suppress("DEPRECATION")
                Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER)
                    .putExtra(
                        TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME,
                        packageName
                    )
            } ?: return
            startActivityForResult(intent, REQ_DIALER_ROLE)
        } catch (e: Exception) {
            // บาง ROM ถอดหน้านี้ออก — พาไปหน้าตั้งค่าแอปแทน ดีกว่าไม่เกิดอะไร
            openAppSettings()
        }
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
        /// จอสายขอให้ขึ้นทับจอล็อกระหว่างสายที่เธอถือ · ดู [overLockFrom]
        const val EXTRA_OVER_LOCK = "giggok.overLock"

        private var live: java.lang.ref.WeakReference<MainActivity>? = null

        /**
         * สายจบ → ถอนตัวจากหน้าจอล็อกทันที
         *
         * 🔴 ไม่ถอน = แอปทั้งแอป (แชท ความจำ หน้าตั้งค่า) เปิดได้โดยไม่ต้องปลดล็อก
         * ไปจนกว่าจะปิดแอป · เรียกจาก [MindInCallService] ตอนไม่เหลือสายแล้ว
         */
        @JvmStatic
        fun leaveLockScreen() {
            val a = live?.get() ?: return
            if (!a.overLock) return
            a.setOverLock(false)
            val keyguard = a.getSystemService(Context.KEYGUARD_SERVICE) as? android.app.KeyguardManager
            if (keyguard?.isKeyguardLocked == true) a.moveTaskToBack(true)
        }

        /// ฝั่ง Dart (ที่เป็นคนคุยในสายจริง ๆ) ยังมีชีวิตอยู่ไหม
        ///
        /// จอสายเนทีฟรับสายเองได้ แต่**คุยไม่ได้** · บทสนทนาทั้งหมดอยู่ใน
        /// CallSession ฝั่ง Dart · ดู InCallActivity.armAutoAnswer
        @JvmStatic
        @Volatile
        var dartAlive = false
            private set

        private const val CHANNEL = "giggok/system"

        /// ช่องแยก · handler ของ giggok/system ฝั่ง Dart เป็นของ CallWatch แต่ผู้เดียว
        private const val LIFE_CHANNEL = "giggok/life"
        private const val REQ_CAMERA = 8747
        private const val REQ_ALL_FILES = 8756
        private const val REQ_NOTIFY = 8748
        private const val REQ_MIC = 8749
        private const val REQ_CALENDAR = 8750
        private const val REQ_CALL = 8751
        private const val REQ_CONTACTS = 8752
        private const val REQ_ANSWER = 8753
        private const val REQ_DIALER_ROLE = 8754

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
