package com.xjanova.videogirl.sos

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat

/**
 * พิกัดของเจ้าของ · ไม่พึ่ง Google Play Services
 *
 * ถือค่าดีสุดล่าสุดไว้ในหน่วยความจำเท่านั้น ไม่ลงไฟล์ · ไม่ลง log
 *
 * 🔴 เหตุเกิดในอุโมงค์/ใต้ตึกไม่มีสัญญาณ · ต้องส่งค่าล่าสุดพร้อมบอกอายุ ดีกว่ารอ GPS จนข้อความไม่ออก
 */
class SosLocator(context: Context) {
    private val app = context.applicationContext
    private val lm = app.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    var best: SosFix? = null
        private set

    /** ความเร็ว km/h จาก GPS · ตัวจับแรงกระแทกใช้ */
    var onSpeed: ((Double) -> Unit)? = null

    fun granted() = ContextCompat.checkSelfPermission(app, Manifest.permission.ACCESS_FINE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED ||
        ContextCompat.checkSelfPermission(app, Manifest.permission.ACCESS_COARSE_LOCATION) ==
        PackageManager.PERMISSION_GRANTED

    private val listener = object : LocationListener {
        override fun onLocationChanged(l: Location) = take(l)

        @Deprecated("ระบบเก่ายังเรียก")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }

    private fun take(l: Location) {
        val fix = SosFix(l.latitude, l.longitude, if (l.hasAccuracy()) l.accuracy.toDouble() else null, l.time)
        if (better(fix, best)) best = fix
        if (l.hasSpeed()) onSpeed?.invoke(l.speed * 3.6)
    }

    /** ใหม่กว่าสองนาทีชนะเสมอ · ไม่งั้นเอาตัวแม่นกว่า */
    private fun better(a: SosFix, b: SosFix?): Boolean {
        if (b == null) return true
        if (a.atMs - b.atMs > 120_000) return true
        if (b.atMs - a.atMs > 120_000) return false
        return (a.accuracyM ?: 9_999.0) <= (b.accuracyM ?: 9_999.0) || a.atMs > b.atMs
    }

    /** ค่าที่เครื่องจำไว้ · ไม่กินแบต · ไม่รอ */
    @SuppressLint("MissingPermission")
    fun lastKnown(): SosFix? {
        if (!granted() || lm == null) return best
        for (p in lm.getProviders(false)) {
            try {
                lm.getLastKnownLocation(p)?.let { l ->
                    val fix = SosFix(l.latitude, l.longitude, if (l.hasAccuracy()) l.accuracy.toDouble() else null, l.time)
                    if (better(fix, best)) best = fix
                }
            } catch (e: Exception) {
                // provider ปิดอยู่
            }
        }
        return best
    }

    private var tracking = false

    /** GPS ติดตามตอนกำลังเดินทาง / ตอนเกิดเหตุ */
    @SuppressLint("MissingPermission")
    fun track(on: Boolean, everyMs: Long = 2_000) {
        if (lm == null || !granted() || on == tracking) return
        try {
            if (on) {
                for (p in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                    // ทีละตัว · ให้แค่ตำแหน่งโดยประมาณแล้ว GPS โยน SecurityException · เครือข่ายต้องได้ลงทะเบียนต่อ
                    try {
                        if (lm.allProviders.contains(p)) {
                            lm.requestLocationUpdates(p, everyMs, 0f, listener, Looper.getMainLooper())
                        }
                    } catch (e: Exception) {
                        android.util.Log.w("GigGokSos", "track: ${e.javaClass.simpleName}")
                    }
                }
            } else {
                lm.removeUpdates(listener)
            }
            tracking = on
        } catch (e: Exception) {
            android.util.Log.w("GigGokSos", "track: ${e.javaClass.simpleName}")
        }
    }

    /** ขอพิกัดสดสั้น ๆ · ครบเวลาคืนค่าดีสุดที่มี · ไม่เคยไม่ตอบ */
    fun settle(timeoutMs: Long, done: (SosFix?) -> Unit) {
        val had = tracking
        track(true)
        main.postDelayed({
            if (!had) track(false)
            done(lastKnown())
        }, timeoutMs)
    }

    fun close() = track(false)
}
