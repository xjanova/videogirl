package com.xjanova.videogirl

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent

/**
 * บริการการช่วยเหลือพิเศษ — มีไว้เรื่องเดียว: **ให้เธอได้ยินปลายสาย**
 *
 * ## 🔴 ทำไมต้องมี
 *
 * ตั้งแต่ Android 10 ระหว่างมีสาย แอปทั่วไปที่อัดเสียงจากไมค์ได้**ความเงียบ**
 * (ไม่มี error) · ข้อยกเว้นตามเอกสาร Android มีแค่แอประบบ กับแอปที่เป็น
 * บริการการช่วยเหลือพิเศษ ("The app can capture audio if it is an accessibility
 * service") · เป็นแอปโทรศัพท์หลักไม่ได้ช่วย · ผลเดิม: เธอรับสายแล้วหูหนวกทั้งสาย
 * ไม่ตอบอะไรเลย · เจ้าของ: "รับแล้ว แต่ไม่ยอมพูดตอบโต้อะไรเลย"
 *
 * ## 🔴 ตัวนี้ไม่อ่านอะไรเลย
 *
 * ไม่อ่านหน้าจอ (`canRetrieveWindowContent=false`) ไม่กดอะไรแทน ไม่ส่งอะไรออก ·
 * ฟังเหตุการณ์ชนิดเดียวที่แทบไม่เกิด (ประกาศ) แล้วทิ้ง · สิทธิ์ที่ได้จริงคือ
 * "อัดเสียงระหว่างสายได้" ซึ่งใช้เฉพาะตอนเธอถือสาย (CallSession)
 */
class MindAccessibility : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // ไม่ใช้ · ดูหัวไฟล์
    }

    override fun onInterrupt() {}

    companion object {
        /** เจ้าของเปิดบริการนี้ไว้ในหน้าการช่วยเหลือพิเศษหรือยัง */
        @JvmStatic
        fun enabled(context: Context): Boolean {
            val me = ComponentName(context, MindAccessibility::class.java)
            val list = try {
                Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                )
            } catch (e: Exception) {
                null
            } ?: return false
            return list.split(':').any {
                ComponentName.unflattenFromString(it)?.let { c ->
                    c.packageName == me.packageName && c.className == me.className
                } == true
            }
        }
    }
}
