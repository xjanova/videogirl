package com.xjanova.videogirl.sos

import kotlin.math.sqrt

/**
 * จับแรงกระแทก · ฟังก์ชันล้วน รับตัวเลขจากเซ็นเซอร์ เทสต์ด้วยข้อมูลจำลองได้
 *
 * เจ้าของ: "ให้เธอจับความรุนแรงของเซ็นเซอร์ ถ้ามีการสะเทือนรุนแรงให้คาดไว้ก่อนว่าน่าจะเกิดอุบัติเหตุ"
 *
 * ## ดูอะไรบ้าง
 *
 * มือถือตกพื้นมีแรง "สูงสุด" เท่ารถชนได้ · ค่าเดียวแยกไม่ออก ต้องดูบริบทสามอย่าง:
 * 1. **แรงต่อเนื่อง** เกิน [Config.hitG] นานพอ และความเร็วที่เปลี่ยน ([Config.minDeltaV]) · พื้นแข็งกระแทกแค่ไม่กี่มิลลิวินาที
 * 2. **ตกอิสระก่อนกระแทก** (แรงใกล้ศูนย์) = มือถือหล่น ไม่ใช่คน
 * 3. **ความเร็วก่อนเกิดและหลังเกิด** · รถวิ่งเร็วแล้วหยุดกะทันหัน = ความมั่นใจสูง · ยังวิ่งต่อ = แค่มือถือหล่นในรถ
 *
 * 🔴 **ค่าเกณฑ์ทั้งหมดเป็นค่าตั้งต้นจากการคำนวณ ยังไม่ผ่านการวัดบนเครื่องจริง** ·
 * เซ็นเซอร์มือถือส่วนใหญ่อิ่มที่ 8–16 g จึงดูระยะเวลาและความเร็วที่เปลี่ยน ไม่ใช่ค่าสูงสุดอย่างเดียว ·
 * โหมดซ้อมจดทุกเหตุการณ์ ([Reading]) ให้ดูค่าจริงก่อนเปิดโทรอัตโนมัติ
 */
class ImpactDetector(private val cfg: Config = Config.forLevel(1)) {

    data class Config(
        val hitG: Double,
        val peakG: Double,
        val hitMs: Long,
        val minDeltaV: Double,
        val strongPeakG: Double,
        val strongDeltaV: Double,
        val fastKmh: Double = 25.0,
        val stillMovingKmh: Double = 15.0,
        val speedMemoryMs: Long = 30_000,
        val settleMs: Long = 12_000,
        val freeFallG: Double = 0.35,
        val freeFallMs: Long = 120,
        val stillStd: Double = 0.06,
    ) {
        companion object {
            fun forLevel(level: Int): Config = when (level) {
                0 -> Config(5.0, 8.0, 60, 3.5, 12.0, 5.0)
                2 -> Config(3.0, 5.0, 30, 2.0, 7.0, 3.0)
                else -> Config(4.0, 6.0, 40, 2.8, 9.0, 4.0)
            }
        }
    }

    /** ตัวเลขของเหตุการณ์หนึ่ง · ไม่มีพิกัด · โหมดซ้อมเก็บไว้ให้เจ้าของดู */
    data class Reading(
        val atMs: Long,
        val peakG: Double,
        val deltaV: Double,
        val speedBefore: Double?,
        val speedAfter: Double?,
        val freeFall: Boolean,
        val still: Boolean,
        val verdict: String,
    )

    /** มีเหตุที่ต้องเรียกเจ้าของไหม · null = ไม่ใช่อุบัติเหตุ · [reading] มีเสมอเมื่อเหตุการณ์จบ */
    data class Outcome(val confidence: SosConfidence?, val reading: Reading)

    private var above = false
    private var aboveFrom = 0L
    private var lastT = 0L
    private var peak = 0.0
    private var deltaV = 0.0

    private var fallFrom = 0L
    private var fallEnd = 0L

    private var pending: Pending? = null

    private class Pending(
        val atMs: Long,
        val peak: Double,
        val deltaV: Double,
        val speedBefore: Double?,
        val freeFall: Boolean,
    )

    private var speed: Double? = null
    private var speedAt = 0L
    private var fastest = 0.0
    private var fastestAt = 0L

    /** สถิติความนิ่งหลังกระแทก · Welford · ไม่เก็บตัวอย่างทั้งหมด */
    private var n = 0
    private var mean = 0.0
    private var m2 = 0.0

    /** กำลังรอดูหลังกระแทก · บริการต้องเซ็นเซอร์ติดต่อจนจบ */
    val busy: Boolean get() = pending != null

    fun onSpeed(tMs: Long, kmh: Double) {
        speed = kmh
        speedAt = tMs
        if (kmh >= fastest || tMs - fastestAt > cfg.speedMemoryMs) {
            fastest = kmh
            fastestAt = tMs
        }
    }

    /** [g] แรงรวมเป็นเท่าของแรงโน้มถ่วง (ตั้งนิ่ง = 1) */
    fun onSample(tMs: Long, g: Double): Outcome? {
        val dtMs = if (lastT == 0L) 0L else (tMs - lastT).coerceIn(0L, 200L)
        lastT = tMs

        val p = pending
        if (p != null) {
            n++
            val d = g - mean
            mean += d / n
            m2 += d * (g - mean)
            return if (tMs - p.atMs >= cfg.settleMs) settle(tMs, p) else null
        }

        if (g <= cfg.freeFallG) {
            if (fallFrom == 0L) fallFrom = tMs
            fallEnd = tMs
        } else if (tMs - fallEnd > FALL_GAP_MS) {
            fallFrom = 0L
        }

        if (g >= cfg.hitG) {
            if (!above) {
                above = true
                aboveFrom = tMs
                peak = 0.0
                deltaV = 0.0
            }
            if (g > peak) peak = g
            deltaV += (g - 1.0).coerceAtLeast(0.0) * G * dtMs / 1000.0
            return null
        }
        if (!above) return null
        above = false
        if (tMs - aboveFrom < cfg.hitMs || peak < cfg.peakG || deltaV < cfg.minDeltaV) return null

        val fell = fallFrom != 0L && fallEnd - fallFrom >= cfg.freeFallMs && aboveFrom - fallEnd <= FALL_GAP_MS
        val before = fastestAt.takeIf { it != 0L && tMs - it <= cfg.speedMemoryMs }?.let { fastest }
        pending = Pending(tMs, peak, deltaV, before, fell)
        n = 0
        mean = 0.0
        m2 = 0.0
        return null
    }

    private fun settle(tMs: Long, p: Pending): Outcome {
        pending = null
        val after = speed?.takeIf { speedAt > p.atMs }
        val std = if (n > 1) sqrt(m2 / (n - 1)) else 0.0
        val still = std <= cfg.stillStd
        val verdict: Pair<SosConfidence?, String> = when {
            after != null && after >= cfg.stillMovingKmh -> null to "kept_moving"
            p.speedBefore != null && p.speedBefore >= cfg.fastKmh ->
                if (after != null || still) SosConfidence.HIGH to "crash" else SosConfidence.LOW to "fast_unsure"
            p.freeFall -> null to "dropped"
            !still -> null to "handled"
            p.peak >= cfg.strongPeakG && p.deltaV >= cfg.strongDeltaV -> SosConfidence.LOW to "hard_hit"
            else -> null to "weak"
        }
        return Outcome(
            verdict.first,
            Reading(p.atMs, p.peak, p.deltaV, p.speedBefore, after, p.freeFall, still, verdict.second),
        )
    }

    companion object {
        private const val G = 9.80665
        private const val FALL_GAP_MS = 150L
    }
}

/**
 * ตัดสินคำตอบของเจ้าของ · ไม่ส่งให้โมเดล · ทำในเครื่องทั้งหมด
 *
 * 🔴 ต้องตรง**ทั้งประโยค** · วิทยุหรือคนข้าง ๆ พูดว่า "ไม่เป็นไรหรอกเรื่องนี้" แล้วยกเลิกการแจ้งเหตุจริง = อันตรายกว่า
 * แจ้งผิด · คำที่เธอพูดเอง ("เป็นอะไรไหมคะ") ต้องไม่นับ
 */
object SosReply {
    enum class Answer { FINE, HELP, UNKNOWN }

    private val fine = setOf(
        "ไม่เป็นไร", "ไม่เป็นไรค่ะ", "ไม่เป็นไรครับ", "ไม่เป็นไรคะ", "ไม่เป็นอะไร", "ไม่เป็นอะไรค่ะ", "ไม่เป็นอะไรครับ",
        "โอเค", "โอเคค่ะ", "โอเคครับ", "สบายดี", "ปลอดภัย", "ปลอดภัยดี", "ยกเลิก", "หยุด",
        "ไม่เจ็บ", "ไม่เจ็บเลย", "ไม่ปวด", "ไม่ต้องช่วย", "ไม่ต้องเรียกหมอ", "ไม่ต้องเรียกรถพยาบาล", "ไม่ต้องแจ้งเหตุ",
        "im fine", "i am fine", "im ok", "im okay", "i am ok", "i am okay", "cancel", "stop", "no help needed",
        "im not hurt", "i am not hurt", "not hurt", "dont need help", "no ambulance",
    )

    /** คำนำหน้าที่กลับความหมาย · "ไม่เจ็บ" ไม่ใช่การขอความช่วยเหลือ และการแจ้งเหตุเพราะคำนี้ไม่มีนับถอยหลัง */
    private val negated = listOf("ไม่ต้อง", "ไม่ได้", "ไม่", "not", "dont", "dontneed", "noneed", "no")

    private val help = listOf(
        "ช่วยด้วย", "ช่วยที", "ช่วยหน่อย", "ช่วยฉัน", "ช่วยผม", "เจ็บ", "ปวด", "เรียกรถพยาบาล", "เรียกหมอ",
        "แจ้งเหตุ", "ฉุกเฉิน", "ไม่ไหว", "เลือดออก", "หายใจไม่", "help", "ambulance", "emergency", "hurt",
    )

    fun classify(raw: String): Answer {
        val t = raw.lowercase().replace(Regex("[\\s'’.,!?]+"), " ").trim()
        if (t.isEmpty()) return Answer.UNKNOWN
        val squeezed = t.replace(" ", "")
        // ขอความช่วยเหลือชนะเสมอ · "ไม่เป็นไร ช่วยด้วย" ไม่ใช่การยกเลิก
        if (help.any { asked(squeezed, it.replace(" ", "")) }) return Answer.HELP
        if (t in fine || squeezed in fine.map { it.replace(" ", "") }) return Answer.FINE
        return Answer.UNKNOWN
    }

    /** มีคำนี้แบบไม่ถูกปฏิเสธอย่างน้อยหนึ่งที่ · "ไม่เจ็บ แต่เลือดออก" ยังนับ */
    private fun asked(said: String, word: String): Boolean {
        var at = said.indexOf(word)
        while (at >= 0) {
            val start = at
            if (negated.none { said.startsWith(it, start - it.length) }) return true
            at = said.indexOf(word, at + 1)
        }
        return false
    }
}
