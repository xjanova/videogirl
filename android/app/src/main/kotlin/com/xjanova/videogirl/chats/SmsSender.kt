package com.xjanova.videogirl.chats

/**
 * SMS จากคนจริงเท่านั้น · เจ้าของ (2026-11-07): ให้เธอตอบ SMS ได้ แต่ไม่ใช่ธนาคาร OTP หรือโปรโมชัน
 *
 * ## 🔒
 * - ผู้ส่งต้องเป็นเบอร์โทรจริง (8–15 หลัก) หรือคนที่บันทึกไว้ในสมุดโทรศัพท์ (แอปข้อความผูกเข้ากับรายชื่อแล้ว)
 * - ชื่อผู้ส่งเป็นตัวหนังสือ (KBank, AIS, Shopee) หรือเบอร์สั้น (1677, 4567890 ฯลฯ) = ไม่ตอบเลย ไม่ร่าง ไม่ถาม
 * - SMS ไม่ตอบเองเด็ดขาด ต่อให้เปิด "ตอบเองทุกแชท" หรืออนุญาตคนนั้นไว้ · ส่ง SMS เสียเงิน ถามเจ้าของทุกครั้ง
 *
 * ไม่มีของ Android ในไฟล์นี้ · เทสต์ใน src/test ได้ตรง ๆ
 */
object SmsSender {

    /** แอป SMS ประจำเครื่อง · Google ข้อความ · Samsung · vivo / เครื่องที่ใช้แอปของ AOSP */
    val APPS = setOf(
        "com.google.android.apps.messaging",
        "com.samsung.android.messaging",
        "com.android.mms",
    )

    fun isSms(pkg: String): Boolean = pkg in APPS

    private const val SEPARATORS = "+-() . "

    /**
     * ตัวเลขของเบอร์โทรจริง · null = ไม่ใช่เบอร์ (มีตัวหนังสือ) หรือเป็นเบอร์สั้นของบริการ
     *
     * เบอร์สั้นที่ธนาคาร/โปรโมชันใช้ยาวไม่เกินเจ็ดหลัก · เบอร์มือถือ/บ้านสั้นสุดที่ใช้กันคือแปดหลัก (สิงคโปร์ ฮ่องกง)
     */
    fun phoneDigits(raw: String?): String? {
        val t = raw?.trim()?.removePrefix("tel:")?.trim().orEmpty()
        if (t.isEmpty() || !t.all { it.isDigit() || it in SEPARATORS }) return null
        val plus = t.count { it == '+' }
        if (plus > 1 || (plus == 1 && !t.startsWith('+'))) return null
        val digits = t.filter(Char::isDigit)
        return if (digits.length in 8..15) digits else null
    }

    /**
     * ตอบคนนี้ได้ไหม · [who] = ชื่อที่แจ้งเตือนโชว์ · [title] = หัวห้อง · [uri] = ตัวตนที่แอปข้อความแนบมา
     * (`tel:` = เบอร์ · `content://com.android.contacts/…` = แอปผูกกับรายชื่อที่บันทึกไว้แล้ว)
     */
    fun ok(who: String?, title: String?, uri: String?): Boolean {
        val u = uri?.trim().orEmpty()
        if (u.startsWith("tel:", ignoreCase = true)) return phoneDigits(u) != null
        if (u.startsWith("content://com.android.contacts/")) return true
        return phoneDigits(who) != null || phoneDigits(title) != null
    }
}
