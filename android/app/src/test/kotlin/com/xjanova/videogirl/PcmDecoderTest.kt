package com.xjanova.videogirl

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** เสียงทุกเจ้าต้องกลายเป็น PCM 24 kHz ช่องเดียวก่อนเข้าสายตรง (ดู PcmDecoder) */
class PcmDecoderTest {

    private fun shorts(vararg v: Int): ByteArray {
        val b = ByteBuffer.allocate(v.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (s in v) b.putShort(s.toShort())
        return b.array()
    }

    private fun floats(vararg v: Float): ByteArray {
        val b = ByteBuffer.allocate(v.size * 4).order(ByteOrder.LITTLE_ENDIAN)
        for (f in v) b.putFloat(f)
        return b.array()
    }

    @Test
    fun `mp3 สเตอริโอ = เฉลี่ยสองช่องเป็นช่องเดียว`() {
        val mono = PcmDecoder.mono(shorts(1000, 3000, -2000, -4000), channels = 2, float = false)
        assertArrayEquals(shortArrayOf(2000, -3000), mono)
    }

    @Test
    fun `ตัวถอดที่คืน float = แปลงเป็น 16 บิต ไม่ล้นขอบ`() {
        val mono = PcmDecoder.mono(floats(0.5f, -1f, 1.5f), channels = 1, float = true)
        assertEquals(16384.0, mono[0].toDouble(), 1.0)
        assertEquals(-32767, mono[1].toInt())
        assertEquals(32767, mono[2].toInt())
    }

    @Test
    fun `อัตราเดียวกัน = ไม่แตะ`() {
        val pcm = shortArrayOf(1, 2, 3)
        assertSame(pcm, PcmDecoder.resample(pcm, 24000, 24000))
    }

    @Test
    fun `ElevenLabs 44_1 kHz → 24 kHz ความยาวเสียงเท่าเดิม`() {
        val second = ShortArray(44100) { 1000 }
        val out = PcmDecoder.resample(second, 44100, 24000)
        assertEquals(24000, out.size)
        assertTrue(out.all { it.toInt() == 1000 })
    }

    @Test
    fun `เสียงเครื่อง 16 kHz → 24 kHz ลากเส้นระหว่างตัวอย่าง`() {
        val out = PcmDecoder.resample(shortArrayOf(0, 300, 600, 900), 16000, 24000)
        assertEquals(6, out.size)
        assertArrayEquals(shortArrayOf(0, 200, 400, 600, 800, 900), out)
    }

    @Test
    fun `ลดอัตรา = เฉลี่ยในช่วง กันเสียงสูงพับลงมา`() {
        // สลับบวกลบทุกตัวอย่าง = ความถี่สูงสุดของ 48 kHz · ลงไป 24 kHz ต้องหายเป็นศูนย์ ไม่ใช่เหลือเป็นเสียงซ่า
        val out = PcmDecoder.resample(ShortArray(480) { if (it % 2 == 0) 8000 else -8000 }, 48000, 24000)
        assertEquals(240, out.size)
        assertTrue(out.all { it.toInt() == 0 })
    }

    @Test
    fun `กลับเป็นไบต์ little-endian ให้ตัวช่วย`() {
        assertArrayEquals(shorts(1, -2, 32767), PcmDecoder.toBytes(shortArrayOf(1, -2, 32767)))
    }

    @Test
    fun `เพลงพักสายยาว = หยุดถอดเมื่อครบช่วงที่ขอ · เสียงประโยค (0) ไม่จำกัด`() {
        assertTrue(!PcmDecoder.reached(119_999_999L, 120_000))
        assertTrue(PcmDecoder.reached(120_000_000L, 120_000))
        assertTrue(!PcmDecoder.reached(Long.MAX_VALUE, 0))
    }
}
