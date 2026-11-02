package com.xjanova.videogirl

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.SystemClock
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.roundToInt

/**
 * ถอดไฟล์เสียงหนึ่งประโยค (mp3 · wav · อะไรก็ได้ที่เครื่องถอดได้) เป็น PCM 16 บิต ช่องเดียว ตามอัตราที่ขอ
 *
 * ทางต่อสายตรง ([DirectAudioClient]) รับแต่ PCM 24 kHz · เจ้าเสียงแต่ละเจ้าคืนไฟล์คนละแบบ
 * (ElevenLabs · Azure · OpenAI tts = mp3 · Gemini · Realtime · เสียงเครื่อง = wav หลายอัตรา) ·
 * ถอดที่นี่ที่เดียวด้วยตัวถอดของเครื่อง ไม่ต้องสอนทุกเจ้าให้ส่งรูปแบบพิเศษตอนอยู่ในสาย
 *
 * 🔴 ของเดิมทางคุยผลัดกันพูดเล่นไฟล์ออกลำโพงอย่างเดียว · เครื่องที่ต่อสายตรงไว้คือเครื่องที่ AEC
 * ลบเสียงลำโพงทิ้ง → เลือกเสียงอื่นที่ไม่ใช่คุยสด OpenAI แล้วปลายสายไม่ได้ยินอะไรเลย
 */
object PcmDecoder {

    /// หนึ่งประโยคถอดเสร็จในไม่กี่ร้อยมิลลิวินาที · ตัวถอดที่ค้าง (ROM แปลก ๆ) ต้องไม่ทำให้เธอเงียบทั้งสาย
    private const val LIMIT_MS = 15_000L

    /**
     * null = ถอดไม่ได้ (ไม่มีแทร็กเสียง · ไม่มีตัวถอด · ค้างเกินเวลา)
     *
     * [maxMs] > 0 = เอาแค่ช่วงแรกยาวเท่านี้ · เพลงพักสายสามนาทีถอดเต็มไฟล์ = PCM ดิบหลายสิบเมกะไบต์ในหน่วยความจำ
     */
    fun decode(path: String, rate: Int, maxMs: Int = 0): ByteArray? {
        val ex = MediaExtractor()
        try {
            ex.setDataSource(path)
            val index = (0 until ex.trackCount).firstOrNull {
                ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return null
            ex.selectTrack(index)
            val format = ex.getTrackFormat(index)
            var from = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var float = false
            val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            try {
                codec.configure(format, null, null, 0)
                codec.start()
                val raw = ByteArrayOutputStream()
                val info = MediaCodec.BufferInfo()
                val until = SystemClock.elapsedRealtime() + LIMIT_MS
                var inputDone = false
                while (SystemClock.elapsedRealtime() < until) {
                    if (!inputDone) {
                        val i = codec.dequeueInputBuffer(10_000)
                        if (i >= 0) {
                            val n = ex.readSampleData(codec.getInputBuffer(i)!!, 0)
                            if (n < 0) {
                                codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                codec.queueInputBuffer(i, 0, n, ex.sampleTime, 0)
                                ex.advance()
                            }
                        }
                    }
                    val o = codec.dequeueOutputBuffer(info, 10_000)
                    if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        // อัตรา/จำนวนช่องจริงมาตอนนี้ · ของในหัวไฟล์ mp3 บางไฟล์ไม่ตรงกับที่ถอดได้
                        val f = codec.outputFormat
                        from = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        float = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                    } else if (o >= 0) {
                        val buf = codec.getOutputBuffer(o)
                        if (buf != null && info.size > 0) {
                            val chunk = ByteArray(info.size)
                            buf.position(info.offset)
                            buf.get(chunk)
                            raw.write(chunk)
                        }
                        codec.releaseOutputBuffer(o, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0 || reached(info.presentationTimeUs, maxMs)) {
                            return toBytes(resample(mono(raw.toByteArray(), channels, float), from, rate))
                        }
                    }
                }
                return null
            } finally {
                try {
                    codec.stop()
                } catch (e: IllegalStateException) {
                    // ยังไม่ได้เริ่ม (configure พัง) — ไม่ใช่เรื่องที่ต้องพัง
                }
                codec.release()
            }
        } catch (e: Exception) {
            return null
        } finally {
            ex.release()
        }
    }

    /** ถอดมาครบช่วงที่ขอแล้ว · 0 = ไม่จำกัด (เสียงเธอหนึ่งประโยค) */
    fun reached(presentationUs: Long, maxMs: Int): Boolean = maxMs > 0 && presentationUs >= maxMs * 1000L

    /** PCM ที่ตัวถอดคืนมา (16 บิต หรือ float · กี่ช่องก็ได้) → 16 บิต ช่องเดียว · เฉลี่ยทุกช่อง */
    fun mono(raw: ByteArray, channels: Int, float: Boolean): ShortArray {
        val ch = channels.coerceAtLeast(1)
        val width = if (float) 4 else 2
        val buf = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN)
        val out = ShortArray(raw.size / (width * ch))
        for (i in out.indices) {
            var sum = 0.0
            for (c in 0 until ch) {
                val at = (i * ch + c) * width
                sum += if (float) buf.getFloat(at) * 32767.0 else buf.getShort(at).toDouble()
            }
            out[i] = (sum / ch).roundToInt().coerceIn(-32768, 32767).toShort()
        }
        return out
    }

    /**
     * เปลี่ยนอัตรา · ลดอัตรา = เฉลี่ยตัวอย่างในช่วงเดียวกัน (กันเสียงสูงพับลงมาเป็นเสียงซ่า) ·
     * เพิ่มอัตรา = ลากเส้นตรงระหว่างตัวอย่าง
     */
    fun resample(src: ShortArray, from: Int, to: Int): ShortArray {
        if (from <= 0 || to <= 0 || from == to || src.isEmpty()) return src
        val n = (src.size.toLong() * to / from).toInt()
        val out = ShortArray(n)
        val step = from.toDouble() / to
        for (i in 0 until n) {
            val pos = i * step
            val j = pos.toInt().coerceAtMost(src.size - 1)
            if (to < from) {
                val end = ((i + 1) * step).toInt().coerceIn(j + 1, src.size)
                var sum = 0L
                for (k in j until end) sum += src[k]
                out[i] = (sum.toDouble() / (end - j)).roundToInt().toShort()
            } else {
                val a = src[j].toDouble()
                val b = src[minOf(j + 1, src.size - 1)].toDouble()
                out[i] = (a + (b - a) * (pos - j)).roundToInt().toShort()
            }
        }
        return out
    }

    fun toBytes(pcm: ShortArray): ByteArray {
        val buf = ByteBuffer.allocate(pcm.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        for (s in pcm) buf.putShort(s)
        return buf.array()
    }
}
