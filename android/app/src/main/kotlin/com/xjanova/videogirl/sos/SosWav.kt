package com.xjanova.videogirl.sos

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * แปลงไฟล์ WAV จากตัวสังเคราะห์เสียงของเครื่องเป็น PCM ที่ตัวช่วยเสียงตรงกิน
 *
 * ตัวสังเคราะห์แต่ละยี่ห้อคืน 16k/22.05k/24k ไม่เหมือนกัน · ตัวช่วยรับ 24 kHz 16 บิตช่องเดียวเท่านั้น ·
 * เสียงผิดอัตรา = เจ้าหน้าที่ได้ยินเสียงเธอเร็ว/ช้าจนฟังไม่รู้เรื่อง โดยไม่มี error ใด ๆ
 */
object SosWav {
    const val OUT_RATE = 24_000

    data class Pcm(val rate: Int, val channels: Int, val samples: ShortArray)

    /** null = ไม่ใช่ WAV 16 บิตที่อ่านได้ */
    fun parse(bytes: ByteArray): Pcm? {
        if (bytes.size < 44) return null
        val b = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        if (String(bytes, 0, 4, Charsets.US_ASCII) != "RIFF") return null
        if (String(bytes, 8, 4, Charsets.US_ASCII) != "WAVE") return null
        var at = 12
        var rate = 0
        var channels = 0
        var bits = 0
        while (at + 8 <= bytes.size) {
            val id = String(bytes, at, 4, Charsets.US_ASCII)
            val size = b.getInt(at + 4)
            if (size < 0) return null
            val body = at + 8
            when (id) {
                "fmt " -> {
                    if (body + 16 > bytes.size) return null
                    channels = b.getShort(body + 2).toInt()
                    rate = b.getInt(body + 4)
                    bits = b.getShort(body + 14).toInt()
                }
                "data" -> {
                    if (bits != 16 || rate <= 0 || channels !in 1..2) return null
                    // ตัวสังเคราะห์บางตัวเขียนขนาดเป็น 0 หรือเกินไฟล์ระหว่างสตรีม
                    val end = minOf(bytes.size.toLong(), body.toLong() + (if (size == 0) Int.MAX_VALUE else size)).toInt()
                    val out = ShortArray((end - body) / 2)
                    for (i in out.indices) out[i] = b.getShort(body + i * 2)
                    return Pcm(rate, channels, out)
                }
            }
            val next = body.toLong() + size + (size and 1)
            if (next > bytes.size) return null
            at = next.toInt()
        }
        return null
    }

    /** เป็น 24 kHz ช่องเดียว little-endian · เส้นตรงพอสำหรับเสียงพูดในสายที่ตัดเหลือ 8 kHz อยู่แล้ว */
    fun toLine(pcm: Pcm): ByteArray {
        val mono = if (pcm.channels == 2) {
            ShortArray(pcm.samples.size / 2) { ((pcm.samples[it * 2] + pcm.samples[it * 2 + 1]) / 2).toShort() }
        } else {
            pcm.samples
        }
        if (mono.isEmpty()) return ByteArray(0)
        val count = (mono.size.toLong() * OUT_RATE / pcm.rate).toInt().coerceAtLeast(1)
        val out = ByteBuffer.allocate(count * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (i in 0 until count) {
            val pos = i.toDouble() * pcm.rate / OUT_RATE
            val a = pos.toInt().coerceAtMost(mono.size - 1)
            val c = (a + 1).coerceAtMost(mono.size - 1)
            val f = pos - a
            out.putShort((mono[a] * (1 - f) + mono[c] * f).toInt().toShort())
        }
        return out.array()
    }
}
