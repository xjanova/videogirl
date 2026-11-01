package com.xjanova.videogirl.sos

import com.xjanova.videogirl.OutgoingRules

/**
 * ใครต้องได้รับแจ้ง ตามลำดับ · เป็นฟังก์ชันล้วน เทสต์ได้โดยไม่มีเครื่อง
 *
 * ## 🔴 ด่านที่ห้ามหลุด
 *
 * - **ซ้อม/ทดสอบ ห้ามออกไปหาเจ้าหน้าที่หรือผู้ติดต่อจริงเด็ดขาด** · ส่งได้แค่เบอร์ทดสอบที่ไม่ใช่เบอร์ฉุกเฉิน
 *   [drillSafe] ตรวจซ้ำทั้งรายการของเราและรายการของซิม ([isEcc]) ไม่ใช่เชื่อค่าที่เก็บไว้
 * - แรงกระแทกความมั่นใจต่ำ (ไม่รู้ความเร็ว) แจ้งผู้ติดต่อเท่านั้น ไม่แจ้งเจ้าหน้าที่ · การแจ้งผิดกินสายของคนอื่น
 */
object SosRouter {

    fun route(
        plan: SosPlan,
        kind: SosKind,
        confidence: SosConfidence,
        drill: Boolean,
        abroad: Boolean,
        isEcc: (String) -> Boolean,
    ): List<SosStep> {
        if (drill) {
            // 🔴 โทรเบอร์ที่ตรวจแล้ว ไม่ใช่ค่าดิบ · "," กับ ";" ในเบอร์คือคำสั่งกดต่อของระบบโทรศัพท์
            val to = OutgoingRules.normalize(plan.testNumber) ?: return emptyList()
            if (!drillSafe(to, isEcc)) return emptyList()
            return listOf(
                SosStep.Sms(to, DRILL_WHO, withHealth = true),
                SosStep.Call(to, DRILL_WHO, official = false),
            )
        }
        val texts = plan.contacts.filter { contactSafe(it.number) }
            .mapNotNull { c -> OutgoingRules.normalize(c.number)?.let { c.copy(number = it) } }
        val sms = texts.map { SosStep.Sms(it.number, it.name, it.health) }
        val officials = if (confidence == SosConfidence.HIGH) {
            val numbers = if (abroad) plan.abroad else plan.routes[kind.name].orEmpty()
            numbers.filter { it in OFFICIAL }.map { SosStep.Call(it, it, official = true) }
        } else {
            emptyList()
        }
        // สายถึงเจ้าหน้าที่ล้มหรือไม่รับ · ผู้ติดต่อคือคนต่อไปที่ยังโทรหาแทนได้
        val family = texts.map { SosStep.Call(it.number, it.name, official = false) }
        // SMS ก่อนเสมอ · ส่งเสร็จในไม่กี่วินาที แบตหมด/สายหลุดกลางคันก็ยังมีคนรู้พิกัด
        return sms + officials + family
    }

    /**
     * เหตุนี้จำลองไหม · 🔴 โหมดทดสอบคุมทุกทางเข้า รวมปุ่ม คำพูด และแจ้งเงียบ ·
     * ปิดอยู่ แรงกระแทกยังจำลองจนกว่าจะเปิดด่านโทรอัตโนมัติ
     */
    fun rehearses(plan: SosPlan, how: SosTrigger, autoCallAllowed: Boolean) =
        plan.testMode || (how == SosTrigger.IMPACT && !autoCallAllowed)

    /** เบอร์ทดสอบใช้ได้จริงไหม · เบอร์สั้นไม่ใช่เบอร์มือถือของเจ้าของ */
    fun drillSafe(number: String, isEcc: (String) -> Boolean): Boolean {
        val n = OutgoingRules.normalize(number) ?: return false
        if (n.trimStart('+').length < MIN_PHONE_DIGITS) return false
        return !OutgoingRules.blocked(n) && !isEcc(n)
    }

    /** ผู้ติดต่อต้องเป็นเบอร์เต็ม · 1900 คิดเงินตามนาที เบอร์สั้นคือคอลเซ็นเตอร์ */
    fun contactSafe(number: String): Boolean {
        val n = OutgoingRules.normalize(number) ?: return false
        return n.trimStart('+').length >= MIN_PHONE_DIGITS && !OutgoingRules.blocked(n)
    }

    private const val MIN_PHONE_DIGITS = 9

    /**
     * 🔴 แผนมาจาก Dart · ตรงนี้คือด่านสุดท้ายว่า "สายทางการ" โทรได้แค่เบอร์เหล่านี้ · ไฟล์แผนถูกแก้ก็ไปเบอร์อื่นไม่ได้
     * เพิ่มเบอร์ใหม่ใน lib/sos/sos_directory.dart ต้องเพิ่มที่นี่ด้วย
     */
    private val OFFICIAL = setOf("191", "1669", "199", "112")
    const val DRILL_WHO = "test"
}
