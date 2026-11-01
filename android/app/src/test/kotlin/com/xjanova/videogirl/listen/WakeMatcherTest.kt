package com.xjanova.videogirl.listen

import java.io.File
import java.util.Random
import kotlin.math.PI
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * ตัวจับคำเรียกกับเสียงสังเคราะห์ · เสียงคนจริงต้องวัดบนเครื่อง (ดู lastScore ใน log)
 *
 * "คำ" ในเทสต์นี้คือลำดับเสียงสระเทียม (ฮาร์มอนิกหลายตัวตามความถี่ที่ต่างกันทีละพยางค์) ·
 * พูดซ้ำ = ความถี่ เวลา และความดังขยับเล็กน้อย เหมือนคนพูดคำเดิมไม่เหมือนเดิมเป๊ะ
 */
class WakeMatcherTest {

    private val rate = WakeMatcher.RATE

    /** พยางค์ (ความถี่พื้น, เรโซแนนซ์, วินาที) */
    private data class Syl(val pitch: Double, val formant: Double, val seconds: Double)

    private val word = listOf(Syl(190.0, 700.0, .18), Syl(220.0, 1500.0, .16), Syl(170.0, 500.0, .28))
    private val other = listOf(Syl(210.0, 2200.0, .20), Syl(160.0, 900.0, .22), Syl(240.0, 2800.0, .20))

    private fun speak(sylls: List<Syl>, r: Random, gain: Double = 6000.0, wobble: Double = .03): ShortArray {
        val out = ArrayList<Short>()
        for (s in sylls) {
            val scale = 1 + (r.nextDouble() - .5) * wobble * 2
            val n = (s.seconds * scale * rate).toInt()
            val pitch = s.pitch * (1 + (r.nextDouble() - .5) * wobble)
            val formant = s.formant * (1 + (r.nextDouble() - .5) * wobble)
            for (i in 0 until n) {
                val t = i.toDouble() / rate
                val env = sin(PI * i / n).coerceAtLeast(.05)
                var v = 0.0
                var h = 1
                while (h * pitch < 4000) {
                    val f = h * pitch
                    val near = 1 / (1 + ((f - formant) / 250).let { it * it })
                    v += near * sin(2 * PI * f * t)
                    h++
                }
                out.add((v * env * gain).coerceIn(-32000.0, 32000.0).toInt().toShort())
            }
        }
        return out.toShortArray()
    }

    private fun quiet(seconds: Double, r: Random, level: Double = 30.0) =
        ShortArray((seconds * rate).toInt()) { (r.nextGaussian() * level).toInt().toShort() }

    private fun feed(m: WakeMatcher, pcm: ShortArray): List<WakeMatcher.Hit> {
        val hits = ArrayList<WakeMatcher.Hit>()
        var i = 0
        while (i < pcm.size) {
            val n = minOf(320, pcm.size - i)
            val hit = m.feed(pcm.copyOfRange(i, i + n), n)
            if (hit != WakeMatcher.Hit.NONE) hits.add(hit)
            i += n
        }
        return hits
    }

    private fun teach(r: Random): WakeWord {
        val m = WakeMatcher(null)
        val samples = ArrayList<Array<FloatArray>>()
        feed(m, quiet(.5, r))
        repeat(WakeMatcher.SAMPLES_NEEDED) {
            val hits = feed(m, speak(word, r))
            val tail = feed(m, quiet(.8, r))
            assertTrue(WakeMatcher.Hit.ENDED in hits + tail)
            samples.add(assertSegment(m))
        }
        return WakeWord(samples, WakeMatcher.spread(samples))
    }

    private fun assertSegment(m: WakeMatcher): Array<FloatArray> {
        val s = m.lastSegment
        assertNotNull(s)
        return s!!
    }

    @Test
    fun `calling the word wakes her in quiet and with a different loudness`() {
        val r = Random(7)
        val w = teach(r)
        val m = WakeMatcher(w)
        var woke = 0
        repeat(20) { i ->
            feed(m, quiet(.6, r))
            val gain = if (i % 2 == 0) 6000.0 else 2500.0
            if (WakeMatcher.Hit.WORD in feed(m, speak(word, r, gain)) + feed(m, quiet(.6, r))) woke++
        }
        assertTrue("woke $woke/20", woke >= 18)
    }

    @Test
    fun `a different word does not wake her`() {
        val r = Random(11)
        val m = WakeMatcher(teach(r))
        repeat(40) {
            feed(m, quiet(.5, r))
            assertFalse(WakeMatcher.Hit.WORD in feed(m, speak(other, r)))
            feed(m, quiet(.5, r))
        }
    }

    @Test
    fun `silence and noise never wake her`() {
        val r = Random(13)
        val m = WakeMatcher(teach(r))
        repeat(50) { assertFalse(WakeMatcher.Hit.WORD in feed(m, quiet(1.0, r, 200.0))) }
    }

    @Test
    fun `the start of a sentence is not a call even if it sounds like the word`() {
        val r = Random(17)
        val m = WakeMatcher(teach(r))
        repeat(10) {
            feed(m, quiet(.6, r))
            assertFalse(WakeMatcher.Hit.WORD in feed(m, speak(word + other, r)))
            feed(m, quiet(.6, r))
        }
    }

    @Test
    fun `calling the word then pausing before the command wakes her`() {
        val r = Random(18)
        val m = WakeMatcher(teach(r))
        var woke = 0
        repeat(10) {
            feed(m, quiet(.6, r))
            val hits = feed(m, speak(word, r)) + feed(m, quiet(.25, r))
            if (WakeMatcher.Hit.WORD in hits) woke++
            feed(m, speak(other, r))
            feed(m, quiet(.6, r))
        }
        assertTrue("woke $woke/10", woke >= 8)
    }

    @Test
    fun `a sample that came out odd does not loosen the limit`() {
        val r = Random(21)
        val taught = teach(r)
        val m = WakeMatcher(null)
        feed(m, quiet(.5, r))
        feed(m, speak(other, r))
        feed(m, quiet(.8, r))
        val samples = taught.samples.dropLast(1) + listOf(m.lastSegment!!)
        val odd = WakeWord(samples, WakeMatcher.spread(samples))
        assertTrue("typical ${odd.typical} spread ${odd.spread}", odd.typical < odd.spread)
        assertTrue(odd.limit < odd.spread * 1.25f)
    }

    @Test
    fun `strict is tighter than normal and normal tighter than eager`() {
        val r = Random(22)
        val w = teach(r)
        val strict = WakeWord(w.samples, w.spread, 0).limit
        val normal = WakeWord(w.samples, w.spread, 1).limit
        val eager = WakeWord(w.samples, w.spread, 2).limit
        assertTrue(strict < normal && normal < eager)
    }

    @Test
    fun `the word in the middle of a sentence is not a call`() {
        val r = Random(19)
        val m = WakeMatcher(teach(r))
        repeat(10) {
            feed(m, quiet(.6, r))
            assertFalse(WakeMatcher.Hit.WORD in feed(m, speak(other + other + word, r)))
            feed(m, quiet(.6, r))
        }
    }

    @Test
    fun `a clap is too short to teach and a monologue too long`() {
        val r = Random(23)
        val m = WakeMatcher(null)
        feed(m, quiet(.5, r))
        feed(m, speak(listOf(Syl(200.0, 800.0, .05)), r))
        feed(m, quiet(.8, r))
        assertNull(m.lastSegment)
        feed(m, speak(List(12) { Syl(200.0, 800.0, .3) }, r))
        feed(m, quiet(.8, r))
        assertNull(m.lastSegment)
    }

    @Test
    fun `saved word comes back the same and a broken file is no word`() {
        val r = Random(29)
        val w = teach(r).also { it.sensitivity = 2 }
        val f = File.createTempFile("wake", ".bin")
        w.save(f)
        val back = WakeWord.load(f)!!
        assertEquals(w.samples.size, back.samples.size)
        assertEquals(w.spread, back.spread, 0f)
        assertEquals(2, back.sensitivity)
        assertEquals(w.samples[1][3][4], back.samples[1][3][4], 0f)
        f.writeBytes(byteArrayOf(1, 2, 3))
        assertNull(WakeWord.load(f))
        f.delete()
        assertNull(WakeWord.load(f))
    }

    /** เงียบทั้งวันคือค่าไฟส่วนใหญ่ · หนึ่งนาทีของเสียงต้องใช้เวลาคำนวณน้อยกว่า 0.5% */
    @Test
    fun `an idle minute costs almost nothing`() {
        val r = Random(31)
        val m = WakeMatcher(teach(r))
        val minute = quiet(60.0, r)
        val at = System.nanoTime()
        feed(m, minute)
        val ms = (System.nanoTime() - at) / 1_000_000
        assertTrue("took ${ms}ms", ms < 300)
    }
}
