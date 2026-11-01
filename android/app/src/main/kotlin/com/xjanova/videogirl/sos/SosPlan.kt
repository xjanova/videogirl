package com.xjanova.videogirl.sos

/**
 * แผนฉุกเฉินที่เจ้าของตั้งไว้ · Dart เป็นคนประกอบ (lib/sos/sos_plan.dart) แล้วเก็บเข้ารหัสใน [SosVault]
 *
 * ## 🔴 ทำไมทุกอย่างต้องอยู่ฝั่งเนทีฟตอนเกิดเหตุ
 *
 * เหตุเกิดตอนจอดับ เครื่องล็อก แอปอาจไม่ได้เปิด · Dart อาจไม่มีชีวิตอยู่เลย ·
 * Dart แค่เตรียมแผนล่วงหน้า · ตอนเกิดเหตุฝั่งนี้ทำเองทั้งหมดจากแผนที่เก็บไว้
 * ข้อความขาออกอยู่ในแผน (ภาษาตามที่เจ้าของตั้ง) · เหลือแค่เติมพิกัด ณ ตอนนั้น
 */
data class SosPlan(
    val armed: Boolean,
    /** แรงกระแทกโทรจริงได้ · false = โหมดซ้อม: เธอถามเหมือนจริงแต่ไม่แจ้งใคร */
    val autoCall: Boolean,
    val countdownSec: Int,
    val manualCountdownSec: Int,
    /** kind.name → เบอร์เรียงตามลำดับ · ในไทย */
    val routes: Map<String, List<String>>,
    val abroad: List<String>,
    val contacts: List<SosContact>,
    val testNumber: String,
    /** ความไวของตัวจับแรงกระแทก 0 ไวน้อย · 1 ปกติ · 2 ไวมาก */
    val sensitivity: Int,
    val th: SosTexts,
    val en: SosTexts,
) {
    fun texts(abroad: Boolean) = if (abroad) en else th
}

data class SosContact(val name: String, val number: String, val health: Boolean)

/** ข้อความขาออกทั้งหมด · `{…}` เติมตอนเกิดเหตุ ([SosText]) */
data class SosTexts(
    /** เธอเรียกเจ้าของออกลำโพง · 🔴 ห้ามมีคำตอบที่ [SosReply] นับ ไม่งั้นเธอยกเลิกตัวเอง */
    val alertPrompt: String,
    val sms: String,
    val smsHealth: String,
    val smsLow: String,
    val smsCancel: String,
    val smsDrillPrefix: String,
    val scriptOpen: Map<String, String>,
    val scriptWho: String,
    val scriptWhere: String,
    val scriptNoFix: String,
    val scriptClose: String,
    val ageNow: String,
    val ageOld: String,
    val noFix: String,
    /** แจ้งเงียบ · บอกผู้รับว่าห้ามโทรกลับ · เสียงเรียกเข้าคือสิ่งที่จะทำให้คนร้ายรู้ */
    val smsSilent: String = "",
    val scriptCloseSilent: String = "",
)

enum class SosKind { CRASH, MEDICAL, FIRE, CRIME, OTHER }

enum class SosTrigger { IMPACT, BUTTON, VOICE }

/** ความมั่นใจของแรงกระแทก · มือถือตกกับรถชนแยกกันไม่ขาด เบอร์ที่แจ้งจึงต่างกัน ดู [SosRouter] */
enum class SosConfidence { HIGH, LOW }

/** พิกัดหนึ่งจุด · [atMs] เวลาจริง (ไม่ใช่ uptime) · [accuracyM] null = เครื่องไม่บอก */
data class SosFix(val lat: Double, val lng: Double, val accuracyM: Double?, val atMs: Long)

/** ทางออกหนึ่งก้าวของการแจ้งเหตุ */
sealed class SosStep {
    data class Sms(val to: String, val who: String, val withHealth: Boolean) : SosStep()
    data class Call(val to: String, val who: String, val official: Boolean) : SosStep()
}

/** สิ่งที่ออกไปจากเครื่องจริง · บอกเจ้าของได้ตรง ๆ ตอนกดหยุด */
data class SosSent(val step: SosStep, val atMs: Long, val outcome: String)
