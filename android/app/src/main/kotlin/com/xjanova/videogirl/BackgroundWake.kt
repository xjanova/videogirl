package com.xjanova.videogirl

import id.flutter.flutter_background_service.BackgroundService

/**
 * Lets the CPU sleep while Mind's background watch is on.
 *
 * flutter_background_service takes a PARTIAL wake lock with no timeout when its service starts
 * (`BackgroundService.runService`, and again in its `BootReceiver`) and never releases it, so the CPU
 * never slept while the watch was on: measured on the owner's phone, 10 min of that lock in a 67 min
 * stretch with the screen off. The watch's 5-minute beat (update check) does not need it; it runs
 * whenever the phone is awake anyway, for the wake-word mic, a call or the screen.
 * Owner: "ตอนมันทำงานเบื้องหลัง ให้ประหยัดแบต ให้เหลือแต่ การรอฟัง ปลุกและรอรับสาย".
 */
internal object BackgroundWake {
    fun drop() {
        val lock = BackgroundService.lockStatic ?: return
        // Reference counted: the plugin acquires once per start, and once more after boot.
        try { while (lock.isHeld) lock.release() } catch (_: RuntimeException) { /* already released */ }
    }
}
