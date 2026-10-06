package com.xjanova.videogirl

/**
 * เบอร์ที่น้องมายโทรออกแทนเจ้าของได้ / ไม่ได้
 *
 * 🔴 เบอร์ฉุกเฉินต้องเป็นคนกดเอง · ผู้ช่วย AI ที่โทรเข้าศูนย์ฉุกเฉินเพราะตีความคำสั่งผิด
 * (หรือถูกหลอกให้โทร) คือการกินสายที่คนอื่นกำลังต้องใช้ · เบอร์เก็บเงินพิเศษ (1900)
 * กินเงินเจ้าของตามนาที · ทั้งสองแบบน้องมายไม่โทร ไม่ว่าคำสั่งจะเขียนว่าอะไร
 *
 * ฝั่ง Dart มีรายการเดียวกัน (lib/phone/outgoing_call.dart) เพื่อบอกเจ้าของตั้งแต่ก่อนกด ·
 * ที่นี่คือด่านสุดท้ายที่ข้ามไม่ได้
 */
object OutgoingRules {

    /** ไทย + สากลที่คนไทยอาจพิมพ์ · ตรงตัวเท่านั้น (1xxx ส่วนใหญ่คือคอลเซ็นเตอร์ ไม่ห้าม) */
    private val EMERGENCY = setOf(
        "191", "199", "1669", "1155", "1554", "1784", "1300", "1192", "1193", "1196", "1690",
        "911", "112", "999", "000", "110", "119"
    )

    /** ตัวเลขล้วน (คงเครื่องหมาย + นำหน้าไว้) · null = ไม่ใช่เบอร์ */
    fun normalize(raw: String): String? {
        val plus = raw.trim().startsWith("+")
        val digits = raw.filter { it.isDigit() }
        if (digits.length < 3 || digits.length > 15) return null
        return if (plus) "+$digits" else digits
    }

    fun blocked(number: String): Boolean {
        val d = number.trimStart('+')
        return d in EMERGENCY || d.startsWith("1900")
    }
}
