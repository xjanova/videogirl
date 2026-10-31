package com.xjanova.videogirl.hands

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import com.xjanova.videogirl.direct.setup.BankingPause

/**
 * เปิด [MindHands] ตอนเริ่มงาน ปิดเองหลังว่าง · เปิดเฉพาะตอนเธอทำงาน
 *
 * 🔴 เจ้าของ: แอปธนาคารตรวจเจอบริการการช่วยเหลือพิเศษที่เปิดค้างไว้ แล้วไม่ยอมทำงาน ·
 * บริการนี้จึงต้องปิดอยู่ทุกครั้งที่เธอไม่ได้ทำงาน
 *
 * - เปิดเองได้เฉพาะเมื่อแอปมีสิทธิ์เขียนค่าระบบ (WRITE_SECURE_SETTINGS จากการตั้งค่าเสียงตรง)
 * - เติม/ลบ **เฉพาะชื่อบริการของเรา** · บริการของคนอื่นในรายการต้องอยู่ครบเหมือนเดิมทุกตัว
 * - ปิดเฉพาะเมื่อเราเป็นคนเปิด ([BY_US]) · เจ้าของเปิดเองในหน้าตั้งค่า = ไม่ไปปิดให้
 * - ตอนปิด **ไม่แตะ** ACCESSIBILITY_ENABLED · บริการอื่นที่เปิดอยู่ต้องทำงานต่อ
 * - ธงอยู่ในไฟล์ giggok_hands ซึ่งไม่ถูกสำรองข้อมูล (ดู res/xml/direct_control_*_rules.xml) ·
 *   ย้ายเครื่องแล้วธงตามไป = ไปปิดบริการที่เจ้าของเปิดเองบนเครื่องใหม่
 */
internal object HandsSwitch {
    private const val PREFS = "giggok_hands"
    private const val BY_US = "enabled_by_us"
    private const val TAG = "GigGokHands"

    /** ว่างนานเท่านี้หลังจบงานแล้วปิด · งานต่อเนื่องไม่ต้องรอเปิดใหม่ทุกครั้ง */
    private const val IDLE_OFF_MS = 60_000L

    private val main = Handler(Looper.getMainLooper())
    @Volatile private var app: Context? = null
    private val idleOff = Runnable {
        val c = app ?: return@Runnable
        try { disableIfOurs(c) } catch (e: Exception) { Log.w(TAG, "idle off: ${e.javaClass.simpleName}") }
    }

    fun canAutoEnable(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED

    fun enabledByUs(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(BY_US, false)

    /** ลืมว่าเราเปิดไว้ · พักให้แอปธนาคารเอาชื่อออกไปแล้ว (ดู [BankingPause]) */
    fun forget(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(BY_US).commit()
    }

    private fun own(context: Context) = ComponentName(context, MindHands::class.java)

    /**
     * ให้บริการพร้อมทำงาน · null = พร้อม · ไม่งั้นคืนรหัส ('paused' 'not_enabled')
     *
     * รอได้ถึง ~4 วิ · ห้ามเรียกจากเธรดหลัก
     */
    fun ensure(context: Context): String? {
        if (MindHands.instance != null) return null
        if (BankingPause.isPaused(context)) return "paused"
        if (!canAutoEnable(context)) return "not_enabled"
        if (!enable(context)) return "not_enabled"
        val until = SystemClock.uptimeMillis() + 4_000L
        while (MindHands.instance == null && SystemClock.uptimeMillis() < until) {
            Thread.sleep(100)
        }
        return if (MindHands.instance != null) null else "not_enabled"
    }

    @Synchronized private fun enable(context: Context): Boolean {
        if (BankingPause.isPaused(context)) return false
        return try {
            val resolver = context.contentResolver
            val me = own(context)
            val current = Settings.Secure.getString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            val entries = current?.split(':')?.filter { it.isNotEmpty() } ?: emptyList()
            if (entries.none { ComponentName.unflattenFromString(it) == me }) {
                // ธงก่อนค่าระบบ · โปรเซสตายระหว่างสองบรรทัดนี้ = ยังรู้ว่าต้องปิดคืน
                val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                if (!prefs.edit().putBoolean(BY_US, true).commit()) return false
                val next = (entries + me.flattenToString()).joinToString(":")
                check(Settings.Secure.putString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, next))
            }
            if (Settings.Secure.getInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 0) != 1) {
                check(Settings.Secure.putInt(resolver, Settings.Secure.ACCESSIBILITY_ENABLED, 1))
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "enable: ${e.javaClass.simpleName}")
            false
        }
    }

    /**
     * เอาชื่อเราออก ถ้าเราเป็นคนเปิด · ไม่แตะบริการอื่น ไม่แตะ ACCESSIBILITY_ENABLED
     * · มีงานทำอยู่ = ไม่ปิด (งานใหม่เริ่มทันระหว่างรอ)
     */
    @Synchronized fun disableIfOurs(context: Context): Boolean {
        main.removeCallbacks(idleOff)
        if (!enabledByUs(context)) return false
        if (HandsControl.active) return false
        if (!canAutoEnable(context)) return false
        return try {
            val resolver = context.contentResolver
            val me = own(context)
            val current = Settings.Secure.getString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            if (current != null) {
                val next = current.split(':').filter { it.isNotEmpty() && ComponentName.unflattenFromString(it) != me }
                    .joinToString(":")
                if (next != current) {
                    check(Settings.Secure.putString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, next))
                }
            }
            forget(context)
            true
        } catch (e: Exception) {
            Log.w(TAG, "disable: ${e.javaClass.simpleName}")
            false
        }
    }

    /** ปิดหลังว่าง [IDLE_OFF_MS] · งานใหม่มาก่อนก็ยกเลิก ([cancelIdleOff]) */
    fun scheduleIdleOff(context: Context) {
        app = context.applicationContext
        main.removeCallbacks(idleOff)
        main.postDelayed(idleOff, IDLE_OFF_MS)
    }

    fun cancelIdleOff() {
        main.removeCallbacks(idleOff)
    }

    /** เปิดเครื่อง/อัปเดตแอป · ค้างจากโปรเซสที่ตายกลางงาน = ปิดคืน */
    fun cleanupAfterBoot(context: Context) {
        try {
            if (enabledByUs(context)) disableIfOurs(context)
        } catch (e: Exception) {
            Log.w(TAG, "boot cleanup: ${e.javaClass.simpleName}")
        }
    }
}
