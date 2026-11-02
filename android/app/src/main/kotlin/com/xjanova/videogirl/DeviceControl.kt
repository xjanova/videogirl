package com.xjanova.videogirl

import android.content.Context
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.view.KeyEvent

/**
 * เสียง ไฟฉาย เพลง โหมดเสียงเรียกเข้า · ของที่แอปสั่งเองได้ ไม่ต้องใช้มือ ไม่ต้องมีจอ
 *
 * เจ้าของ: "เบาเสียงลดเสียง และควบคุมเรื่องอื่นๆได้ หมด เปิดไฟฉาย" · Wi-Fi บลูทูธ ความสว่าง ห้ามรบกวน
 * Android ไม่ให้แอปสั่งตรง เธอไปกดเองผ่านแผงด่วนด้วยมือ (phone_task)
 */
internal class DeviceControl(context: Context) {
    private val app = context.applicationContext
    private val audio = app.getSystemService(AudioManager::class.java)

    fun run(action: String, level: Int?, stream: String?): Map<String, Any> = try {
        when (action) {
            "volume_up" -> stepVolume(stream, 1)
            "volume_down" -> stepVolume(stream, -1)
            "volume_set" -> if (level == null) fail("failed") else setPercent(stream, level)
            "volume_mute" -> mute(stream, AudioManager.ADJUST_MUTE)
            "volume_unmute" -> mute(stream, AudioManager.ADJUST_UNMUTE)
            "flashlight_on" -> torch(true)
            "flashlight_off" -> torch(false)
            "media_play" -> media(KeyEvent.KEYCODE_MEDIA_PLAY)
            "media_pause" -> media(KeyEvent.KEYCODE_MEDIA_PAUSE)
            "media_next" -> media(KeyEvent.KEYCODE_MEDIA_NEXT)
            "media_previous" -> media(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
            "ringer_normal" -> ringer(AudioManager.RINGER_MODE_NORMAL)
            "ringer_vibrate" -> ringer(AudioManager.RINGER_MODE_VIBRATE)
            else -> fail("failed")
        }
    } catch (_: SecurityException) {
        // เสียงเรียกเข้าลงถึงศูนย์ = เปลี่ยนห้ามรบกวน ซึ่งต้องมีสิทธิ์แยก
        fail("dnd")
    } catch (_: RuntimeException) {
        fail("failed")
    }

    private fun fail(why: String) = mapOf<String, Any>("ok" to false, "error" to why)

    /** ไม่ระบุ = เสียงที่เจ้าของได้ยินอยู่ตอนนี้ · ติดสาย = เสียงในสาย · นอกนั้น = เสียงสื่อ */
    private fun streamOf(name: String?): Int = when (name) {
        "media" -> AudioManager.STREAM_MUSIC
        "ring" -> AudioManager.STREAM_RING
        "alarm" -> AudioManager.STREAM_ALARM
        "notification" -> AudioManager.STREAM_NOTIFICATION
        "call" -> AudioManager.STREAM_VOICE_CALL
        else -> if (audio.mode == AudioManager.MODE_IN_CALL || audio.mode == AudioManager.MODE_IN_COMMUNICATION) {
            AudioManager.STREAM_VOICE_CALL
        } else {
            AudioManager.STREAM_MUSIC
        }
    }

    private fun report(stream: Int): Map<String, Any> {
        val max = audio.getStreamMaxVolume(stream).coerceAtLeast(1)
        val level = Math.round(audio.getStreamVolume(stream) * 100f / max)
        return mapOf("ok" to true, "level" to level, "muted" to audio.isStreamMute(stream))
    }

    /** ทีละสิบเปอร์เซ็นต์ · ปุ่มข้างเครื่องทีละขีด สั่งด้วยเสียงแล้วแทบไม่ได้ยินความต่าง */
    private fun stepVolume(name: String?, dir: Int): Map<String, Any> {
        val stream = streamOf(name)
        val max = audio.getStreamMaxVolume(stream)
        val step = (max / 10).coerceAtLeast(1)
        return setIndex(stream, audio.getStreamVolume(stream) + dir * step)
    }

    private fun setPercent(name: String?, percent: Int): Map<String, Any> {
        val stream = streamOf(name)
        return setIndex(stream, Math.round(percent.coerceIn(0, 100) * audio.getStreamMaxVolume(stream) / 100f))
    }

    private fun setIndex(stream: Int, index: Int): Map<String, Any> {
        // ปิดเสียงค้างอยู่ · ตั้งระดับเฉย ๆ เครื่องยังเงียบ
        if (index > 0 && audio.isStreamMute(stream)) audio.adjustStreamVolume(stream, AudioManager.ADJUST_UNMUTE, 0)
        audio.setStreamVolume(stream, index.coerceIn(0, audio.getStreamMaxVolume(stream)), AudioManager.FLAG_SHOW_UI)
        return report(stream)
    }

    private fun mute(name: String?, how: Int): Map<String, Any> {
        val stream = streamOf(name)
        audio.adjustStreamVolume(stream, how, AudioManager.FLAG_SHOW_UI)
        return report(stream)
    }

    private fun torch(on: Boolean): Map<String, Any> {
        val cameras = app.getSystemService(CameraManager::class.java)
        fun flash(id: String) = cameras.getCameraCharacteristics(id).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        fun back(id: String) =
            cameras.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
        return try {
            val ids = cameras.cameraIdList.filter(::flash)
            val id = ids.firstOrNull(::back) ?: ids.firstOrNull() ?: return fail("no_flash")
            cameras.setTorchMode(id, on)
            mapOf("ok" to true)
        } catch (e: CameraAccessException) {
            // กล้องนั้นถูกใช้อยู่ (ตาของเธอเอง หรือแอปกล้อง)
            fail(if (e.reason == CameraAccessException.CAMERA_IN_USE || e.reason == CameraAccessException.MAX_CAMERAS_IN_USE) "camera_busy" else "failed")
        }
    }

    private fun media(code: Int): Map<String, Any> {
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
        return mapOf("ok" to true)
    }

    private fun ringer(mode: Int): Map<String, Any> {
        audio.ringerMode = mode
        return mapOf("ok" to true)
    }
}
