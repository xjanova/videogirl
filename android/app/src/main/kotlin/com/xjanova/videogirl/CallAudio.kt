package com.xjanova.videogirl

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.telecom.CallAudioState

/**
 * เสียงของมายด์เข้าไปใน**สายจริง** — กลไกอ้อม ไม่ใช่ API
 *
 * ## 🔴 อ่านก่อนแตะ: Android ไม่มีทางป้อนเสียงเข้าสาย
 *
 * `VOICE_UPLINK` / `VOICE_DOWNLINK` / `VOICE_CALL` ถูกสงวนให้แอประบบและแอป
 * ของผู้ให้บริการเครือข่ายตั้งแต่ Android 10 · เป็นแอปโทรศัพท์หลักก็ไม่ได้
 * สิทธิ์นี้ · ที่นี่จึงไม่ได้ "ป้อนเสียงเข้าสาย" แต่ทำสิ่งเดียวที่เหลืออยู่:
 *
 *   **เปิดลำโพง → เล่นเสียงเธอออกลำโพงจริง → ไมค์ของเครื่องรับเข้าไปเอง**
 *
 * เสียงเดินทางเป็นคลื่นในอากาศจากลำโพงไปไมค์ แล้วขึ้นสายตามทางปกติ
 * ปลายสายได้ยินจริง แต่ต้องรู้ข้อแลกเปลี่ยนสามข้อ:
 *
 * **หนึ่ง — คุณภาพต่ำกว่าเสียงตรง** มีเสียงห้องและเสียงก้องปนขึ้นไปด้วย
 *
 * **สอง — ตัวตัดเสียงก้อง (AEC) ของเครื่องอาจลบเสียงเธอทิ้ง**
 * AEC มีหน้าที่ลบสิ่งที่ลำโพงเล่นออกจากสัญญาณไมค์พอดี ๆ ซึ่งคือสิ่งที่เรา
 * กำลังทำ · บางชิปอ้างอิงเฉพาะเสียงขาลงของสาย (เสียงเธอรอด) บางชิปอ้างอิง
 * เสียงลำโพงทั้งหมด (เสียงเธอโดนลบ) **ต่างกันตามชิปและตาม ROM
 * อ่านจากโค้ดไม่ได้ ต้องลองกับเครื่องจริงเท่านั้น** — [play] จึงเลือก
 * ช่องเสียงได้สองทาง ให้เจ้าของลองว่าเครื่องนี้ทางไหนรอด
 *
 * **สาม — ต้องเป็นแอปโทรศัพท์หลัก** การบังคับเส้นทางเสียงของสายทำได้ผ่าน
 * [android.telecom.InCallService.setAudioRoute] เท่านั้น ซึ่งมีก็ต่อเมื่อ
 * ระบบผูกกับ [MindInCallService] อยู่ · ไม่ได้เป็นแอปหลัก = สั่งเปิดลำโพงไม่ได้
 * = ไม่มีอะไรทำงานทั้งกลไก · [open] จึงคืน false ไม่ใช่เงียบ ๆ ปล่อยผ่าน
 *
 * ทางที่ไม่ต้องลุ้นเลยคือรับสายฝั่งเซิร์ฟเวอร์ · ดู docs/telephony.md
 *
 * สิทธิ์: ต้องมี MODIFY_AUDIO_SETTINGS ประกาศไว้ใน manifest ถึงจะขยับ
 * ระดับเสียงของช่องสายได้ · เป็นสิทธิ์ระดับปกติ ระบบให้ตั้งแต่ติดตั้ง
 * ไม่ต้องขอผู้ใช้
 */
object CallAudio {

    /** ช่องเสียงที่ใช้เล่นเสียงเธอ · ดูเหตุผลที่มีสองทางในหัวไฟล์ */
    const val STREAM_CALL = "call"
    const val STREAM_MEDIA = "media"

    private var player: MediaPlayer? = null

    /// 🔴 คำตอบที่ยังค้างอยู่ของประโยคที่กำลังเล่น
    ///
    /// ต้องเก็บไว้ที่นี่ ไม่ใช่ปล่อยให้อยู่แต่ใน closure ของ [play] — เพราะ
    /// การหยุดกลางคัน (เจ้าของแทรกสาย สายวาง หรือสั่งพูดประโยคใหม่ทับ)
    /// ไม่ทำให้ MediaPlayer เรียก onCompletion เลย · ถ้าไม่มีใครตอบแทน
    /// **Future ฝั่ง Dart จะรอประโยคที่จบไปแล้วตลอดกาล แล้วบทสนทนาค้างทั้งสาย**
    private var pendingDone: ((Boolean) -> Unit)? = null

    /// ระดับเสียงเดิมของแต่ละช่อง — ต้องคืนให้เสมอ ไม่งั้นเจ้าของจะเจอสาย
    /// ถัดไปดังสุดโดยไม่รู้ว่าใครไปเร่งไว้
    private var savedCallVolume: Int? = null
    private var savedMediaVolume: Int? = null

    /// เปิดลำโพงให้เธอไปแล้วหรือยัง
    var open = false
        private set

    /// เจ้าของกดสลับลำโพงเองระหว่างที่เธอถือสาย · [keepSpeaker] เลิกเปิดทับ
    @Volatile
    var ownerRouted = false

    private var openStream = STREAM_CALL
    private var reasserts = 0
    private var raisedOnSpeaker = false

    /// เปิดลำโพงซ้ำได้กี่ครั้งต่อสาย · กันวนแย่งกับ ROM ที่ไม่ยอมจริง ๆ
    private const val MAX_REASSERTS = 8

    /**
     * เปิดทางให้เธอพูดเข้าสาย · คืน false ถ้าทำไม่ได้จริง
     *
     * false = ยังไม่ได้เป็นแอปโทรศัพท์หลัก หรือระบบยังไม่ได้ผูกกับบริการเรา
     * ผู้เรียกต้องบอกผู้ใช้ ไม่ใช่เล่นเสียงต่อไปแล้วให้ปลายสายเงียบ
     *
     * 🔴 สั่งครั้งเดียวที่นี่ไม่พอ · สายเข้าถูกสั่งตอน**กริ่งยังดัง** (`answer()` ยังไม่เสร็จ)
     * แล้วหลายเครื่องตั้งเส้นทางเสียงใหม่เป็นหูฟังตอนสายต่อติด · เสียงเธอไปออกหูฟังเบา ๆ
     * ไมค์ไม่ได้ยิน ปลายสายไม่ได้ยิน · [keepSpeaker] คอยเปิดคืนตลอดสาย
     */
    fun open(context: Context, stream: String): Boolean {
        val service = MindInCallService.service ?: return false

        openStream = stream
        ownerRouted = false
        reasserts = 0
        raisedOnSpeaker = false
        open = true
        service.setAudioRoute(CallAudioState.ROUTE_SPEAKER)
        raise(context, stream)
        return true
    }

    /**
     * ลำโพงต้องเปิดอยู่ตลอดที่เธอถือสาย · เรียกทุกครั้งที่สถานะสายหรือเส้นทางเสียงเปลี่ยน
     *
     * ไม่ทำอะไรเมื่อเธอไม่ได้ถือสาย ([open] = false · เจ้าของแทรกสายแล้ว) หรือเจ้าของ
     * สลับลำโพงเอง ([ownerRouted]) · หูฟังบลูทูธ/หูฟังสายก็สลับมาลำโพง เพราะตอนนั้น
     * ไม่มีใครฟังอยู่ที่หู และไมค์ของหูฟังไม่ได้ยินเสียงเธอจากลำโพงเครื่อง
     */
    fun keepSpeaker(context: Context) {
        if (!open || ownerRouted) return
        val service = MindInCallService.service ?: return
        val state = service.callAudioState ?: return
        // ไมค์ของสายถูกปิด = ไม่มีเสียงอะไรขึ้นสายเลย · แอปเราไม่มีปุ่มปิดไมค์ ที่ปิดมาจากที่อื่น
        // (ปุ่มบนหูฟังบลูทูธ / สายก่อนหน้า) · ตอนเธอถือสายไม่มีใครตั้งใจให้ปิด
        if (state.isMuted && reasserts < MAX_REASSERTS) {
            reasserts++
            service.setMuted(false)
        }
        val route = state.route
        if (route == CallAudioState.ROUTE_SPEAKER) {
            // ระดับเสียงสายแยกตามอุปกรณ์ · ที่เร่งไว้ตอนกริ่งดังอาจเป็นของหูฟัง
            if (!raisedOnSpeaker) {
                raisedOnSpeaker = true
                raise(context, openStream)
            }
            return
        }
        if (reasserts >= MAX_REASSERTS) return
        reasserts++
        service.setAudioRoute(CallAudioState.ROUTE_SPEAKER)
    }

    /**
     * เจ้าของแทรกสาย — คืนเสียงให้หูฟังแล้วหยุดเธอทันที
     *
     * หยุดเสียงเธอ**ก่อน**เปลี่ยนเส้นทาง ไม่ใช่หลัง · ไม่งั้นประโยคที่ค้างอยู่
     * จะไปโผล่ที่หูฟังตอนเจ้าของเพิ่งยกขึ้นแนบหู ซึ่งดังมากและงงมาก
     */
    fun handOver(context: Context) {
        stop()
        liveStop()
        restore(context)
        // ปิดธงก่อนสลับ · [keepSpeaker] ที่ตามมากับการเปลี่ยนเส้นทางต้องไม่เปิดลำโพงคืน
        open = false
        MindInCallService.service?.setAudioRoute(CallAudioState.ROUTE_EARPIECE)
    }

    /** จบสาย หรือเลิกให้เธอพูด — คืนระดับเสียงเดิมทุกครั้ง */
    fun close(context: Context) {
        stop()
        liveStop()
        restore(context)
        open = false
        ownerRouted = false
    }

    /**
     * เล่นเสียงเธอออกลำโพง แล้วบอกกลับเมื่อจบ
     *
     * 🔴 **ไม่ขอ audio focus** โดยตั้งใจ · การขอ focus ระหว่างมีสายอยู่
     * ทำให้บางเครื่องหรี่หรือพักสายทิ้ง ซึ่งแย่กว่าเสียงเธอเบาไปมาก
     *
     * [onDone] ถูกเรียกครั้งเดียวเสมอ ทั้งตอนจบปกติ ตอนพัง และตอนถูกสั่งหยุด
     * ไม่งั้นฝั่ง Dart จะรอเทิร์นที่ไม่มีวันจบ แล้วบทสนทนาค้างทั้งสาย
     */
    fun play(context: Context, path: String, stream: String, onDone: (Boolean) -> Unit) {
        // ประโยคเก่าที่ยังค้างต้องถูกตอบว่า "ไม่จบ" ก่อนเสมอ ไม่ใช่ถูกทิ้ง
        stop()
        pendingDone = onDone

        val usage = if (stream == STREAM_MEDIA) {
            AudioAttributes.USAGE_MEDIA
        } else {
            AudioAttributes.USAGE_VOICE_COMMUNICATION
        }

        try {
            val mp = MediaPlayer()
            player = mp
            // ต้องตั้งก่อน setDataSource · ตั้งหลัง prepare ไม่มีผลกับเส้นทางเสียง
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(usage)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            mp.setDataSource(path)
            mp.setOnCompletionListener {
                releasePlayer(mp)
                settle(true)
            }
            mp.setOnErrorListener { _, _, _ ->
                releasePlayer(mp)
                settle(false)
                true
            }
            mp.setOnPreparedListener { it.start() }
            mp.prepareAsync()
        } catch (e: Exception) {
            player = null
            settle(false)
        }
    }

    /** หยุดเสียงที่กำลังเล่น · ปลอดภัยที่จะเรียกซ้ำหรือตอนไม่มีอะไรเล่นอยู่ */
    fun stop() {
        val mp = player
        player = null
        if (mp != null) {
            try {
                if (mp.isPlaying) mp.stop()
            } catch (e: IllegalStateException) {
                // เล่นจบไปแล้วหรือยังไม่เริ่ม — ไม่ใช่เรื่องที่ต้องพัง
            }
            try {
                mp.release()
            } catch (e: Exception) {
                // ปล่อยซ้ำ — ไม่ใช่เรื่องที่ต้องพัง
            }
        }
        settle(false)
    }

    /**
     * ตอบประโยคที่ค้างอยู่ · ตอบได้ครั้งเดียวเสมอ
     *
     * ล้างตัวแปรก่อนเรียก ไม่ใช่หลัง — ผู้รับอาจสั่งพูดประโยคถัดไปทันที
     * ซึ่งจะวน [play] → [stop] → settle ซ้อนเข้ามา ถ้ายังไม่ล้างจะตอบซ้ำ
     */
    private fun settle(ok: Boolean) {
        val done = pendingDone ?: return
        pendingDone = null
        done(ok)
    }

    private fun releasePlayer(mp: MediaPlayer) {
        if (player === mp) player = null
        try {
            mp.release()
        } catch (e: Exception) {
            // ปล่อยซ้ำ — ไม่ใช่เรื่องที่ต้องพัง
        }
    }

    /**
     * เร่งเสียงช่องที่จะใช้ขึ้นสุด
     *
     * ไม่เร่ง = เครื่องที่เจ้าของหรี่เสียงสายไว้จะเล่นเสียงเธอเบาจนไมค์
     * แทบไม่ได้ยิน ซึ่งอ่านออกมาเป็น "ปลายสายไม่ได้ยิน" ทั้งที่กลไกทำงานครบ
     */
    private fun raise(context: Context, stream: String) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        // ระหว่างสาย ระบบกดเสียงสื่อไม่ให้ดังเกินเสียงสาย · เลือกช่องสื่อก็ต้องเร่งช่องสายด้วย
        raiseOne(am, STREAM_CALL)
        if (stream == STREAM_MEDIA) raiseOne(am, STREAM_MEDIA)
    }

    private fun raiseOne(am: AudioManager, stream: String) {
        val type = streamType(stream)
        val saved = if (stream == STREAM_MEDIA) savedMediaVolume else savedCallVolume

        // จำค่าเดิมครั้งแรกครั้งเดียว · เร่งซ้ำแล้วจำใหม่ = จำค่าที่เราเร่งเอง
        // แล้วคืนค่าจริงไม่ได้อีกเลย
        if (saved == null) {
            val now = try {
                am.getStreamVolume(type)
            } catch (e: Exception) {
                return
            }
            if (stream == STREAM_MEDIA) savedMediaVolume = now else savedCallVolume = now
        }

        try {
            am.setStreamVolume(type, am.getStreamMaxVolume(type), 0)
        } catch (e: SecurityException) {
            // บาง ROM ล็อกระดับเสียงของสายไว้ · เสียงเธอจะเบากว่าที่ควร
            // แต่ยังได้ยิน — ดีกว่าล้มทั้งสาย
        }
    }

    private fun restore(context: Context) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        savedCallVolume?.let { restoreOne(am, AudioManager.STREAM_VOICE_CALL, it) }
        savedMediaVolume?.let { restoreOne(am, AudioManager.STREAM_MUSIC, it) }
        savedCallVolume = null
        savedMediaVolume = null
    }

    private fun restoreOne(am: AudioManager, type: Int, level: Int) {
        try {
            am.setStreamVolume(type, level, 0)
        } catch (e: Exception) {
            // คืนไม่ได้ก็ปล่อย — เจ้าของปรับเองได้ ไม่คุ้มที่จะล้มทั้งสาย
        }
    }

    private fun streamType(stream: String) =
        if (stream == STREAM_MEDIA) AudioManager.STREAM_MUSIC else AudioManager.STREAM_VOICE_CALL

    // ── เสียงสด (OpenAI Realtime) ─────────────────────────────────────
    //
    // เจ้าของ: "ต้องทำ real time พูดคุยเลย ถ้าตั้งค่าเป็น open ai" · เสียงเธอมาเป็นชิ้น
    // PCM 16 บิต 24 kHz ทีละไม่กี่สิบมิลลิวินาที ต้องเล่นทันทีที่มาถึง ไม่ใช่รอทั้งประโยค
    // แล้วเขียนไฟล์ (ทางเดิม [play]) · ออกลำโพงทางเดียวกับ [play] (ดูหัวไฟล์)

    /** หนึ่งรอบการเล่น · เปลี่ยนก้อนใหม่ทั้งก้อนตอนล้าง ไม่ใช้ของเก่าต่อ */
    private class Live(val track: android.media.AudioTrack, val rate: Int) {
        val queue = java.util.concurrent.LinkedBlockingQueue<ByteArray>()
        val written = java.util.concurrent.atomic.AtomicLong(0)   // เฟรมที่ส่งให้ลำโพงแล้ว
        val queued = java.util.concurrent.atomic.AtomicLong(0)    // ไบต์ที่ยังรอคิว
        @Volatile var alive = true
        val writer = Thread {
            try {
                while (alive) {
                    val b = queue.take()
                    queued.addAndGet(-b.size.toLong())
                    if (!alive) break
                    var off = 0
                    while (off < b.size && alive) {
                        val n = track.write(b, off, b.size - off)
                        if (n <= 0) break
                        off += n
                    }
                    written.addAndGet((off / 2).toLong())
                }
            } catch (e: InterruptedException) {
                // หยุดตามสั่ง
            }
        }.apply { isDaemon = true; name = "mind-live-audio" }
    }

    @Volatile
    private var live: Live? = null

    /** เริ่มช่องเสียงสด · ทุกครั้งที่เรียกได้ช่องใหม่สะอาด (ทิ้งเสียงที่ค้างอยู่) */
    fun liveStart(stream: String, rate: Int = 24000): Boolean {
        liveStop()
        return try {
            val usage = if (stream == STREAM_MEDIA) {
                AudioAttributes.USAGE_MEDIA
            } else {
                AudioAttributes.USAGE_VOICE_COMMUNICATION
            }
            val min = android.media.AudioTrack.getMinBufferSize(
                rate,
                android.media.AudioFormat.CHANNEL_OUT_MONO,
                android.media.AudioFormat.ENCODING_PCM_16BIT
            )
            val track = android.media.AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(usage)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    android.media.AudioFormat.Builder()
                        .setSampleRate(rate)
                        .setEncoding(android.media.AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(android.media.AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                // บัฟเฟอร์เล็ก = ตัดเสียงได้ไว ตอบไว · ไม่ต่ำกว่าที่เครื่องต้องการ
                .setBufferSizeInBytes(maxOf(min, rate * 2 / 5))
                .setTransferMode(android.media.AudioTrack.MODE_STREAM)
                .build()
            track.play()
            val l = Live(track, rate)
            live = l
            l.writer.start()
            true
        } catch (e: Exception) {
            live = null
            false
        }
    }

    fun liveWrite(pcm: ByteArray) {
        val l = live ?: return
        l.queued.addAndGet(pcm.size.toLong())
        l.queue.offer(pcm)
    }

    /** ยังเหลือเสียงเธอที่ยังไม่ออกลำโพงกี่มิลลิวินาที · 0 = เงียบแล้ว */
    fun livePendingMs(): Int {
        val l = live ?: return 0
        val head = l.track.playbackHeadPosition.toLong() and 0xffffffffL
        val frames = (l.written.get() - head).coerceAtLeast(0) + l.queued.get() / 2
        return (frames * 1000 / l.rate).toInt()
    }

    /** ทิ้งเสียงที่ค้างอยู่ทันที (เจ้าของแทรกสาย / ยกเลิกคำตอบ) แล้วพร้อมเล่นต่อ */
    fun liveClear(stream: String) {
        val rate = live?.rate ?: return
        liveStart(stream, rate)
    }

    fun liveStop() {
        val l = live ?: return
        live = null
        l.alive = false
        l.queue.clear()
        l.writer.interrupt()
        try {
            l.track.pause()
            l.track.flush()
            l.track.release()
        } catch (e: Exception) {
            // ปล่อยซ้ำ/ยังไม่เริ่ม — ไม่ใช่เรื่องที่ต้องพัง
        }
    }
}
