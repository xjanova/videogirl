package com.xjanova.videogirl.listen

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * จับคำเรียก ("น้องมายด์") ในเครื่อง ด้วยเสียงตัวอย่างของเจ้าของเอง
 *
 * ## ทำไมไม่ใช้โมเดลสำเร็จรูป
 *
 * Porcupine / openWakeWord ไม่มีภาษาไทย · ตัวถอดเสียงของเครื่องมีเสียงบี๊ปทุกรอบและเปิดค้างทั้งวันไม่ได้ ·
 * ส่งเสียงทั้งวันไปถอดบนเซิร์ฟเวอร์ = เครื่องอัดเสียงของ OpenAI ซึ่งเจ้าของไม่ได้ขอ · เจ้าของตั้งคำเองได้ด้วย
 * จึงเทียบรูปคลื่นเสียง (MFCC + DTW) กับตัวอย่างที่เจ้าของพูดไว้ ได้ทุกภาษา ทุกคำ ไม่มีค่าใช้จ่าย
 *
 * ## 🔴 เสียงไม่ออกจากเครื่อง
 *
 * ทุกอย่างในไฟล์นี้อยู่ในหน่วยความจำ ไม่เก็บ PCM · ไฟล์ตัวอย่างเก็บแค่ค่า MFCC (ฟังย้อนเป็นเสียงไม่ได้)
 *
 * ## กันเรียกผิด
 *
 * เจ้าของ: "ระบบเรียกปลุก มันไวเกินไปไหม ไม่ได้เรียก ก็ขานแล้ว" · คำเรียกต้องเป็น**คำโดด ๆ** ไม่ใช่ต้นประโยค
 *
 * - เว้นจังหวะก่อนเรียก (anchored) · "พี่ว่าน้องมายด์เก่ง" ไม่นับ
 * - เว้นจังหวะหลังเรียกด้วย ([SETTLE_HOPS]) · ของเดิมเทียบทุกต้นประโยค ทุกคำพูดรอบตัวจึงมีโอกาสตรงหลายสิบครั้ง
 * - ความยาวใกล้ตัวอย่าง · คำสั้นหรือประโยคยาวไม่ถูกเทียบเลย
 * - ต้องเหมือนตัวอย่างอย่างน้อยสองตัว ไม่ใช่ตัวเดียว
 * - เกณฑ์มาจากค่ากลางของตัวอย่าง ([WakeWord.typical]) · ตัวอย่างแปลกตัวเดียวต้องไม่ทำให้เกณฑ์หลวมทั้งชุด
 *
 * ไม่มี import ของ Android โดยตั้งใจ · เทสต์ด้วย JVM ได้ (test/.../WakeMatcherTest)
 */
class WakeMatcher(private var word: WakeWord?, private val trace: ((String) -> Unit)? = null) {

    companion object {
        const val RATE = 16000
        const val HOP = 160 // 10 มิลลิวินาที
        const val FRAME = 400 // 25 มิลลิวินาที
        private const val FFT = 512
        private const val MELS = 26
        const val COEFFS = 13

        /** เสียงก่อนจุดเริ่มพูด · พยัญชนะต้นเบากว่าเกณฑ์ ไม่เก็บ = ขึ้นต้นไม่ตรงตัวอย่าง */
        private const val PRE_ROLL_HOPS = 15

        /** เสียงต่อกันเท่านี้ถึงนับว่าเริ่มพูด (40 มิลลิวินาที) · กันเสียงกระแทกสั้น ๆ */
        private const val ONSET_HOPS = 4

        /** เงียบเท่านี้ = จบช่วงเสียง */
        private const val HANGOVER_HOPS = 30

        /** เงียบเท่านี้หลังคำ ถึงเทียบกับตัวอย่าง (0.18 วิ) · ช่องว่างในคำสั้นกว่านี้ เธอจึงยังขานทันที */
        private const val SETTLE_HOPS = 18

        /** ความยาวเทียบกับตัวอย่างที่สั้น/ยาวที่สุด */
        private const val SHORTEST_RATIO = 0.8f
        private const val LONGEST_RATIO = 1.25f

        private const val MIN_WORD_HOPS = 30 // 0.3 วิ
        private const val MAX_WORD_HOPS = 250 // 2.5 วิ

        /** เบากว่านี้ไม่นับเป็นเสียงพูดแม้ห้องเงียบสนิท (ค่าเฉลี่ยของ PCM 16 บิต) */
        private const val MIN_LOUD = 120f

        const val SAMPLES_NEEDED = 4

        /** ต้องเหมือนตัวอย่างอย่างน้อยเท่านี้ตัว */
        private const val VOTES = 2

        private val window = FloatArray(FRAME) { (0.54 - 0.46 * cos(2 * PI * it / (FRAME - 1))).toFloat() }
        private val filters = melFilters()
        private val dct = Array(COEFFS) { c ->
            FloatArray(MELS) { m -> cos(PI * (c + 1) * (m + 0.5) / MELS).toFloat() }
        }

        private fun hzToMel(hz: Double) = 2595.0 * kotlin.math.log10(1.0 + hz / 700.0)
        private fun melToHz(mel: Double) = 700.0 * (10.0.pow(mel / 2595.0) - 1.0)

        private fun melFilters(): Array<FloatArray> {
            val lo = hzToMel(80.0)
            val hi = hzToMel(7600.0)
            val bins = IntArray(MELS + 2) {
                val hz = melToHz(lo + (hi - lo) * it / (MELS + 1))
                ((FFT + 1) * hz / RATE).toInt()
            }
            return Array(MELS) { m ->
                FloatArray(FFT / 2 + 1).also { f ->
                    for (k in bins[m] until bins[m + 1]) {
                        f[k] = (k - bins[m]).toFloat() / max(1, bins[m + 1] - bins[m])
                    }
                    for (k in bins[m + 1] until bins[m + 2]) {
                        f[k] = (bins[m + 2] - k).toFloat() / max(1, bins[m + 2] - bins[m + 1])
                    }
                }
            }
        }

        /** FFT แบบ radix-2 ในที่ · ขนาดคงที่ เรียกเฉพาะตอนมีเสียงพูด */
        private fun fft(re: FloatArray, im: FloatArray) {
            val n = re.size
            var j = 0
            for (i in 1 until n) {
                var bit = n shr 1
                while (j and bit != 0) {
                    j = j xor bit
                    bit = bit shr 1
                }
                j = j xor bit
                if (i < j) {
                    val t = re[i]; re[i] = re[j]; re[j] = t
                }
            }
            var len = 2
            while (len <= n) {
                val step = -2 * PI / len
                for (i in 0 until n step len) {
                    for (k in 0 until len / 2) {
                        val c = cos(step * k).toFloat()
                        val s = sin(step * k).toFloat()
                        val a = i + k
                        val b = a + len / 2
                        val tr = re[b] * c - im[b] * s
                        val ti = re[b] * s + im[b] * c
                        re[b] = re[a] - tr
                        im[b] = im[a] - ti
                        re[a] += tr
                        im[a] += ti
                    }
                }
                len = len shl 1
            }
        }

        /** MFCC ของเสียงหนึ่งก้อนยาว [FRAME] */
        fun mfcc(pcm: FloatArray): FloatArray {
            val re = FloatArray(FFT)
            val im = FloatArray(FFT)
            for (i in 0 until FRAME) re[i] = pcm[i] * window[i]
            fft(re, im)
            val power = FloatArray(FFT / 2 + 1) { re[it] * re[it] + im[it] * im[it] }
            val mel = FloatArray(MELS) { m ->
                var sum = 1f
                val f = filters[m]
                for (k in power.indices) sum += f[k] * power[k]
                ln(sum)
            }
            return FloatArray(COEFFS) { c ->
                var sum = 0f
                val d = dct[c]
                for (m in 0 until MELS) sum += d[m] * mel[m]
                sum
            }
        }

        /** ลบค่าเฉลี่ยของแต่ละสัมประสิทธิ์ · ตัดผลของไมค์ ระยะ และความดังออก */
        fun normalize(frames: List<FloatArray>, count: Int = frames.size): Array<FloatArray> {
            val mean = FloatArray(COEFFS)
            for (i in 0 until count) for (c in 0 until COEFFS) mean[c] += frames[i][c]
            for (c in 0 until COEFFS) mean[c] /= max(1, count)
            return Array(count) { i -> FloatArray(COEFFS) { c -> frames[i][c] - mean[c] } }
        }

        private fun dist(a: FloatArray, b: FloatArray): Float {
            var sum = 0f
            for (c in 0 until COEFFS) {
                val d = a[c] - b[c]
                sum += d * d
            }
            return sqrt(sum)
        }

        /**
         * ระยะห่างแบบ DTW จากตัวอย่าง [t] ถึงส่วนต้นของ [s] · ปลายเปิด: เลือกจุดจบที่ดีที่สุด
         * เจ้าของพูดต่อท้ายคำเรียก ("น้องมายด์ เปิดเมลหน่อย") ก็ยังเทียบได้
         *
         * คืนระยะเฉลี่ยต่อเฟรม (ยิ่งน้อยยิ่งเหมือน) · เทียบไม่ได้ = ค่าใหญ่มาก
         */
        fun score(t: Array<FloatArray>, s: Array<FloatArray>): Float {
            val n = t.size
            val m = s.size
            if (n == 0 || m == 0) return Float.MAX_VALUE
            val band = max(10, n / 4)
            val firstEnd = (n * 0.85f).toInt().coerceAtLeast(1)
            val lastEnd = min(m, (n * 1.35f).toInt())
            if (firstEnd > lastEnd) return Float.MAX_VALUE
            val inf = Float.MAX_VALUE / 4
            var prev = FloatArray(m + 1) { inf }
            var row = FloatArray(m + 1) { inf }
            prev[0] = 0f
            for (i in 1..n) {
                row.fill(inf)
                val from = max(1, i - band)
                val to = min(lastEnd, i + band)
                for (j in from..to) {
                    val best = min(prev[j - 1], min(prev[j], row[j - 1]))
                    if (best < inf) row[j] = best + dist(t[i - 1], s[j - 1])
                }
                val swap = prev
                prev = row
                row = swap
            }
            var best = Float.MAX_VALUE
            for (j in firstEnd..lastEnd) {
                if (prev[j] < inf) best = min(best, prev[j] / (n + j))
            }
            return best
        }

        /** เกณฑ์จากตัวอย่างเอง · ตัวอย่างที่เหมือนกันมาก = เกณฑ์แคบ · ไม่ใช้ค่าตายตัวเพราะแต่ละเสียงแตกต่าง */
        fun spread(samples: List<Array<FloatArray>>): Float {
            var worst = 0f
            for (a in samples.indices) for (b in samples.indices) {
                if (a != b) {
                    val v = score(samples[a], samples[b])
                    if (v < Float.MAX_VALUE) worst = max(worst, v)
                }
            }
            return worst
        }
    }

    enum class Hit { NONE, WORD, ENDED }

    private val pending = FloatArray(HOP * 4)
    private var pendingFill = 0

    /** เสียงย้อนหลังในบัฟเฟอร์เดียว · ไม่จองก้อนใหม่ทุก 10 มิลลิวินาที (เงียบทั้งวัน = GC ทั้งวัน) */
    private val history = FloatArray(FRAME + PRE_ROLL_HOPS * HOP)
    private val frame = FloatArray(FRAME)
    private val frames = ArrayList<FloatArray>()

    private var floor = 0f
    private var loudRun = 0
    private var quietRun = 0
    private var speaking = false
    private var gaveUp = false

    /** ค่าที่ดีที่สุดรอบล่าสุด · ไว้ปรับเกณฑ์บนเครื่องจริงจาก log (เป็นตัวเลข ไม่ใช่เสียง) */
    @Volatile
    var lastScore = 0f
        private set

    /** ช่วงเสียงล่าสุดที่จบแล้ว · ตอนสอนคำเรียก */
    var lastSegment: Array<FloatArray>? = null
        private set

    fun setWord(w: WakeWord?) {
        word = w
        reset()
    }

    fun reset() {
        frames.clear()
        history.fill(0f)
        loudRun = 0
        quietRun = 0
        speaking = false
        gaveUp = false
        pendingFill = 0
    }

    /** ป้อน PCM 16 บิต · เงียบอยู่ = แค่นับความดัง ไม่แตะ FFT (ค่าไฟส่วนใหญ่ของทั้งวัน) */
    fun feed(pcm: ShortArray, length: Int): Hit {
        var hit = Hit.NONE
        var i = 0
        while (i < length) {
            val take = min(length - i, HOP - pendingFill)
            for (k in 0 until take) pending[pendingFill + k] = pcm[i + k].toFloat()
            pendingFill += take
            i += take
            if (pendingFill == HOP) {
                pendingFill = 0
                // ได้คำเรียกแล้วห้ามถูกทับด้วย "จบช่วงเสียง" ในก้อนเดียวกัน
                val h = hop()
                if (h != Hit.NONE && hit != Hit.WORD) hit = h
            }
        }
        return hit
    }

    private fun hop(): Hit {
        var energy = 0f
        for (k in 0 until HOP) energy += abs(pending[k])
        energy /= HOP
        System.arraycopy(history, HOP, history, 0, history.size - HOP)
        System.arraycopy(pending, 0, history, history.size - HOP, HOP)

        floor = if (floor == 0f) energy else min(floor * 1.002f, max(energy, 1f))
        val loud = energy > max(MIN_LOUD, floor * 3f)

        if (!speaking) {
            loudRun = if (loud) loudRun + 1 else 0
            if (loudRun < ONSET_HOPS) return Hit.NONE
            speaking = true
            gaveUp = false
            quietRun = 0
            frames.clear()
            for (back in PRE_ROLL_HOPS downTo 0) addFrame(back)
            return Hit.NONE
        }

        quietRun = if (loud) 0 else quietRun + 1
        // เทียบตอนคำจบแล้วเท่านั้น · หยุดกลางคำก็ยังเทียบรอบถัดไปได้
        if (quietRun == SETTLE_HOPS && !gaveUp && check()) return Hit.WORD
        if (quietRun >= HANGOVER_HOPS) {
            speaking = false
            loudRun = 0
            val end = max(0, frames.size - HANGOVER_HOPS)
            lastSegment = if (end in MIN_WORD_HOPS..MAX_WORD_HOPS) normalize(frames, end) else null
            frames.clear()
            return Hit.ENDED
        }
        if (gaveUp || frames.size > MAX_WORD_HOPS + HANGOVER_HOPS) return Hit.NONE
        addFrame(0)
        // ยาวเกินทุกตัวอย่าง = ไม่ใช่คำเรียก · เลิกเก็บเฟรมจนกว่าจะเงียบ ไม่เปลืองไฟ
        val w = word
        if (w != null && frames.size > w.longest * LONGEST_RATIO + SETTLE_HOPS) gaveUp = true
        return Hit.NONE
    }

    /** MFCC ของเฟรมที่จบก่อนปลายบัฟเฟอร์ [back] ก้าว */
    private fun addFrame(back: Int) {
        System.arraycopy(history, history.size - FRAME - back * HOP, frame, 0, FRAME)
        frames.add(mfcc(frame))
    }

    private fun check(): Boolean {
        val w = word ?: return false
        val end = frames.size - SETTLE_HOPS
        if (end < w.shortest * SHORTEST_RATIO || end > w.longest * LONGEST_RATIO) return false
        val s = normalize(frames, end)
        val limit = w.limit
        var best = Float.MAX_VALUE
        var votes = 0
        for (t in w.samples) {
            val v = score(t, s)
            best = min(best, v)
            if (v <= limit) votes++
        }
        lastScore = best
        val need = min(VOTES, w.samples.size)
        trace?.invoke("wake check best=$best votes=$votes/$need limit=$limit typical=${w.typical} spread=${w.spread} frames=$end")
        return votes >= need
    }
}

/** คำเรียกที่เจ้าของสอนไว้ · [spread] คือความต่างมากสุดระหว่างตัวอย่างของเจ้าของเอง */
class WakeWord(val samples: List<Array<FloatArray>>, val spread: Float, var sensitivity: Int = 1) {
    val shortest = samples.minOf { it.size }
    val longest = samples.maxOf { it.size }

    /** ค่ากลางของความต่างระหว่างตัวอย่าง · คำนวณจากตัวอย่าง ไฟล์ที่สอนไว้แล้วจึงใช้ต่อได้ ไม่ต้องสอนใหม่ */
    val typical: Float by lazy {
        val all = ArrayList<Float>()
        for (a in samples.indices) for (b in samples.indices) {
            if (a != b) WakeMatcher.score(samples[a], samples[b]).let { if (it < Float.MAX_VALUE) all.add(it) }
        }
        if (all.isEmpty()) spread else all.sorted()[all.size / 2]
    }

    /** 0 = เข้ม (เรียกผิดน้อย) · 1 = ปกติ · 2 = ไว (ได้ยินจากไกล แต่เรียกผิดง่าย) */
    val limit: Float
        get() = min(spread, typical) * when (sensitivity) {
            0 -> 1.1f
            2 -> 1.45f
            else -> 1.25f
        }

    fun save(file: File) {
        // เขียนไฟล์ชั่วคราวก่อน · ไฟดับกลางเขียน = ไม่เสียคำเรียกเดิม
        val tmp = File(file.parentFile, "${file.name}.tmp")
        DataOutputStream(FileOutputStream(tmp).buffered()).use { o ->
            o.writeInt(MAGIC)
            o.writeFloat(spread)
            o.writeInt(sensitivity)
            o.writeInt(samples.size)
            for (s in samples) {
                o.writeInt(s.size)
                for (f in s) for (v in f) o.writeFloat(v)
            }
        }
        if (!tmp.renameTo(file)) {
            file.delete()
            tmp.renameTo(file)
        }
    }

    companion object {
        private const val MAGIC = 0x4d574b31 // MWK1

        /** ไฟล์เสีย/ไม่มี = null (ถือว่ายังไม่ได้สอน) · ไม่ล้มทั้งบริการ */
        fun load(file: File): WakeWord? {
            if (!file.exists()) return null
            return try {
                DataInputStream(FileInputStream(file).buffered()).use { i ->
                    if (i.readInt() != MAGIC) return null
                    val spread = i.readFloat()
                    val sensitivity = i.readInt()
                    val count = i.readInt()
                    if (count !in 1..16) return null
                    val samples = List(count) {
                        val frames = i.readInt()
                        if (frames !in 1..1000) return null
                        Array(frames) { FloatArray(WakeMatcher.COEFFS) { i.readFloat() } }
                    }
                    WakeWord(samples, spread, sensitivity)
                }
            } catch (e: java.io.IOException) {
                null
            }
        }
    }
}
