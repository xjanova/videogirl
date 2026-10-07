package com.xjanova.videogirl

import android.app.Activity

/**
 * จอติดค้างตลอดที่เธอถือสาย — ไม่ใช่เรื่องหน้าตา เป็นเงื่อนไขให้เธอ**ได้ยิน**ปลายสาย
 *
 * ## 🔴 ทำไม
 *
 * เจ้าของ: "คนที่โทรมาไม่ได้ยินเสียงที่มายด์พูดเลย และมายด์ก็ไม่ได้ยินเสียงที่พูดมาเลย"
 *
 * ระหว่างมีสาย (MODE_IN_CALL) Android ยอมให้แอปที่เป็นบริการการช่วยเหลือพิเศษอัดเสียงจาก
 * ไมค์ได้ก็ต่อเมื่อ (AOSP `AudioPolicyService::updateUidStates_l`):
 *
 * 1. แหล่งเสียงเป็น `VOICE_RECOGNITION` (CallSession ใช้อยู่แล้ว) และแอปอยู่สถานะ "บนสุด"
 * 2. **และ** สิทธิ์ไมค์แบบ "ระหว่างใช้งาน" ยังมีผล — ต้องมีจอของแอปอยู่บนสุดจริง ·
 *    บริการที่ระบบโทรศัพท์ผูกไว้ ([MindInCallService]) ยกแอปได้แค่ระดับบริการเบื้องหน้า
 *    ซึ่ง**ไม่มีสิทธิ์ไมค์** (บริการเฝ้างานของเราก็เป็นชนิด specialUse ไม่ใช่ microphone)
 *
 * จอดับเมื่อไหร่ (ครบเวลาพักจอ ซึ่งลำโพงเปิดไม่มีอะไรมาแตะจอเลย) จอเราไม่อยู่บนสุดอีก →
 * ระบบส่ง**ความเงียบ**ให้ไมค์ของเธอทันที ไม่มี error · เธอหูดับกลางสาย คู่สายพูดอะไรก็ไม่ตอบ
 * · ของเดิมติดจอค้างเฉพาะ Android ต่ำกว่า 8.1 (ทางเก่าใน InCallActivity) ส่วน MainActivity
 * ไม่ได้ติดเลย
 *
 * ใช้ `keepScreenOn` ของ decorView ไม่ใช่ธงของหน้าต่าง · ธงหน้าต่างของ MainActivity
 * สตูดิโอใช้อยู่ ([MindStudio]) ปลดของเราต้องไม่ไปปลดของสตูดิโอด้วย
 */
object CallScreen {

    /** ตอนนี้ควรติดจอค้างไหม: เธอถือสายที่ต่อติดแล้ว */
    @JvmStatic
    fun wanted(): Boolean = MindInCallService.mindLive()

    @JvmStatic
    fun apply(activity: Activity, on: Boolean = wanted()) {
        val decor = activity.window?.decorView ?: return
        if (decor.keepScreenOn != on) decor.keepScreenOn = on
    }
}
