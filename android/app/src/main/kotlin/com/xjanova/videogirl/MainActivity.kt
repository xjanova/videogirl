package com.xjanova.videogirl

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
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

    private var pending: MethodChannel.Result? = null
    private var pendingNotify: MethodChannel.Result? = null

    /// สิทธิ์ที่ค้างอยู่ — ต้องจำไว้เพราะ shouldShowRequestPermissionRationale
    /// ถามเป็นรายสิทธิ์ ถามผิดตัวจะได้คำตอบของสิทธิ์อื่น
    private var pendingPermission: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ensureWatchChannel()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
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

        if (requestCode != REQ_CAMERA && requestCode != REQ_MIC) return

        val reply = pending ?: return
        val which = pendingPermission ?: Manifest.permission.CAMERA
        pending = null
        pendingPermission = null

        val ok = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED

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

        /// ต้องตรงกับ kMindChannelId ใน lib/background/mind_background.dart
        /// ไม่ตรงกัน = บริการหาช่องไม่เจอ แล้วตายแบบเดียวกับไม่มีช่องเลย
        private const val WATCH_CHANNEL = "mind_watch"
        private const val GRANTED = "granted"
        private const val DENIED = "denied"
        private const val BLOCKED = "blocked"
    }
}
