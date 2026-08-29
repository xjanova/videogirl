package com.xjanova.videogirl

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(if (granted()) GRANTED else DENIED)
                    "request" -> request(result)
                    "openSettings" -> {
                        openAppSettings()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun granted() = ContextCompat.checkSelfPermission(
        this, Manifest.permission.CAMERA
    ) == PackageManager.PERMISSION_GRANTED

    private fun request(result: MethodChannel.Result) {
        if (granted()) {
            result.success(GRANTED)
            return
        }
        // มีคำขอค้างอยู่แล้ว — ตอบตัวเก่าว่าถูกยกเลิก ไม่งั้น Future ฝั่ง Dart
        // จะค้างตลอดกาลและปุ่มจะกดไม่ได้อีกเลยทั้งเซสชัน
        pending?.success(DENIED)
        pending = result
        ActivityCompat.requestPermissions(
            this, arrayOf(Manifest.permission.CAMERA), REQ_CAMERA
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_CAMERA) return

        val reply = pending ?: return
        pending = null

        val ok = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED

        // แยก "ปฏิเสธแต่ถามใหม่ได้" ออกจาก "ปฏิเสธถาวร" ให้ได้ ไม่งั้น UI จะบอก
        // ให้กดใหม่ทั้งที่กดไปก็ไม่มีอะไรขึ้น
        //
        // shouldShowRequestPermissionRationale เป็น false ได้สองกรณี คือ
        // "ยังไม่เคยถาม" กับ "ปฏิเสธถาวร" — แต่ตรงนี้เราเพิ่งถามไปหมาด ๆ
        // กรณีแรกจึงถูกตัดออกไปเอง ไม่ต้องจำสถานะลงดิสก์ให้ยุ่ง
        val canAskAgain = ActivityCompat.shouldShowRequestPermissionRationale(
            this, Manifest.permission.CAMERA
        )

        reply.success(if (ok) GRANTED else if (canAskAgain) DENIED else BLOCKED)
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
        private const val CHANNEL = "giggok/camera"
        private const val REQ_CAMERA = 8747
        private const val GRANTED = "granted"
        private const val DENIED = "denied"
        private const val BLOCKED = "blocked"
    }
}
