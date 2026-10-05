package com.xjanova.videogirl

import android.Manifest
import android.app.PictureInPictureParams
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Rational
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * สตูดิโอของเธอ — จอลอย (PiP), จอไม่ดับ, และเก็บคลิปลงแกลเลอรี
 *
 * ช่องแยกจาก giggok/system โดยตั้งใจ (ฝั่ง Dart ของช่องนั้นมี CallWatch เป็น
 * เจ้าของ handler แต่ผู้เดียว) · ช่องนี้ยิงกลับ Dart ด้วย `onPip`
 *
 * ## 🔴 ทำไมไม่ทำกล้องเสมือน
 *
 * Android ไม่มี API ให้แอปทั่วไปประกาศตัวเป็นกล้อง (ต้อง root หรือเป็นแอประบบ)
 * แอปวิดีโอคอลจึงเลือกเธอเป็น "กล้อง" ไม่ได้ · ทางที่ทำได้จริงคือแชร์หน้าจอ
 * ซึ่งทุกแอปวิดีโอคอลหลักมี — สตูดิโอจึงทำให้หน้าจอทั้งจอเป็นเธอล้วน ๆ
 */
class MindStudio(private val activity: MainActivity) {

    companion object {
        const val CHANNEL = "giggok/studio"
        private const val ALBUM = "GigGok"
    }

    private var channel: MethodChannel? = null

    /** ออกจากแอป (กด Home) แล้วเข้าจอลอยเอง — เปิดเฉพาะตอนอยู่ในสตูดิโอ */
    var autoPip = false
        private set

    /** สัดส่วนจอลอย · PiP ยอมแค่ 1:2.39 ถึง 2.39:1 */
    private var aspect = Rational(3, 4)

    fun attach(messenger: io.flutter.plugin.common.BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "keepScreenOn" -> {
                    keepScreenOn(call.argument<Boolean>("on") == true)
                    result.success(true)
                }
                "pipSupported" -> result.success(pipSupported())
                "enterPip" -> {
                    setAspect(call.argument<Int>("w"), call.argument<Int>("h"))
                    result.success(enterPip())
                }
                "autoPip" -> {
                    autoPip = call.argument<Boolean>("on") == true
                    setAspect(call.argument<Int>("w"), call.argument<Int>("h"))
                    pushParams()
                    result.success(true)
                }
                "saveVideo" -> saveVideo(
                    call.argument<String>("path"),
                    call.argument<String>("name"),
                    call.argument<String>("mime"),
                    result
                )
                else -> result.notImplemented()
            }
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    /** MainActivity บอกมาเมื่อเข้า/ออกจอลอย — ฝั่ง Dart ซ่อนปุ่มทั้งหมดตอนอยู่ในจอลอย */
    fun onPipChanged(inPip: Boolean) {
        channel?.invokeMethod("onPip", mapOf("on" to inPip))
    }

    /** Android 8–11 ไม่มี setAutoEnterEnabled · MainActivity เรียกตัวนี้จาก onUserLeaveHint */
    fun onUserLeaveHint() {
        if (autoPip && Build.VERSION.SDK_INT < 31) enterPip()
    }

    private fun keepScreenOn(on: Boolean) {
        activity.runOnUiThread {
            if (on) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= 26 &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun setAspect(w: Int?, h: Int?) {
        if (w == null || h == null || w <= 0 || h <= 0) return
        val r = w.toFloat() / h
        // นอกช่วงที่ระบบยอม = enterPictureInPictureMode โยน IllegalArgumentException
        if (r < 1f / 2.39f || r > 2.39f) return
        aspect = Rational(w, h)
    }

    private fun params(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < 26) return null
        val b = PictureInPictureParams.Builder().setAspectRatio(aspect)
        if (Build.VERSION.SDK_INT >= 31) b.setAutoEnterEnabled(autoPip)
        return b.build()
    }

    private fun pushParams() {
        if (!pipSupported()) return
        val p = params() ?: return
        try {
            activity.setPictureInPictureParams(p)
        } catch (e: Exception) {
            // บางเครื่องปิด PiP ไว้ในตั้งค่า — ไม่ใช่เรื่องที่ต้องพัง
        }
    }

    private fun enterPip(): Boolean {
        if (!pipSupported()) return false
        val p = params() ?: return false
        return try {
            activity.enterPictureInPictureMode(p)
        } catch (e: Exception) {
            // ผู้ใช้ปิดสิทธิ์จอลอยของแอปนี้ไว้ในตั้งค่าเครื่อง
            false
        }
    }

    /**
     * ย้ายคลิปที่อัดเสร็จเข้าแกลเลอรี (Movies/GigGok)
     *
     * คืน {path} เมื่อสำเร็จ · {error: "permission"} บน Android 9 ลงมาที่ยังไม่ได้
     * สิทธิ์เขียนไฟล์ · {error: "failed"} นอกนั้น
     *
     * ทำบนเธรดแยก · คลิปยาวหลายสิบเมกะไบต์ คัดลอกบนเธรดหลัก = จอค้าง
     */
    private fun saveVideo(path: String?, name: String?, mime: String?, result: MethodChannel.Result) {
        if (path.isNullOrEmpty() || name.isNullOrEmpty() || name.contains('/')) {
            result.success(mapOf("error" to "failed"))
            return
        }
        val type = if (mime == "video/mp4") "video/mp4" else "video/webm"
        Thread {
            val out: Map<String, String> = try {
                copyToGallery(File(path), name, type)
            } catch (e: Exception) {
                mapOf("error" to "failed")
            }
            activity.runOnUiThread { result.success(out) }
        }.start()
    }

    private fun copyToGallery(src: File, name: String, mime: String): Map<String, String> {
        if (!src.exists() || src.length() == 0L) return mapOf("error" to "failed")
        val shown = "${Environment.DIRECTORY_MOVIES}/$ALBUM/$name"

        if (Build.VERSION.SDK_INT >= 29) {
            val resolver = activity.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, name)
                put(MediaStore.Video.Media.MIME_TYPE, mime)
                put(MediaStore.Video.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MOVIES}/$ALBUM")
                // ซ่อนไว้จนเขียนเสร็จ · ไม่งั้นแกลเลอรีโชว์คลิปครึ่งไฟล์ที่เปิดไม่ได้
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
            val uri = resolver.insert(
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
                values
            ) ?: return mapOf("error" to "failed")
            try {
                val stream = resolver.openOutputStream(uri) ?: throw IllegalStateException("no stream")
                stream.use { o -> src.inputStream().use { it.copyTo(o) } }
                values.clear()
                values.put(MediaStore.Video.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                return mapOf("error" to "failed")
            }
            return mapOf("path" to shown)
        }

        // Android 8–9: ต้องมีสิทธิ์เขียนไฟล์ก่อน (ประกาศไว้ใน manifest แล้ว)
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_EXTERNAL_STORAGE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return mapOf("error" to "permission")
        }
        @Suppress("DEPRECATION")
        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), ALBUM)
        if (!dir.exists() && !dir.mkdirs()) return mapOf("error" to "failed")
        val dst = File(dir, name)
        src.copyTo(dst, overwrite = true)
        MediaScannerConnection.scanFile(activity, arrayOf(dst.absolutePath), arrayOf(mime), null)
        return mapOf("path" to shown)
    }
}
