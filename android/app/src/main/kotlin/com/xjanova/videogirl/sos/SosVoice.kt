package com.xjanova.videogirl.sos

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.ToneGenerator
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import com.xjanova.videogirl.CallAudio
import com.xjanova.videogirl.DirectAudioClient
import com.xjanova.videogirl.MindInCallService
import java.io.File
import java.util.Locale

/**
 * เสียงของมายด์ตอนเกิดเหตุ · ใช้ตัวสังเคราะห์เสียงในเครื่องซึ่งไม่ต้องมีเน็ตและไม่ต้องมี Dart
 *
 * ## ในสาย: ลำดับทางที่ลอง
 *
 * 1. **เสียงตรง** ([DirectAudioClient]) · ทางเดียวที่ขึ้นสายจริงบน vivo V2144
 * 2. **ลำโพง → ไมค์** · ตัวตัดเสียงก้องของ V2144 ลบเสียงเธอทิ้ง (ดู docs/telephony.md) แต่เครื่องอื่นอาจรอด ·
 *    ต้องเปิดไว้เสมอ ไม่งั้นสายเงียบสนิท · อย่างน้อยคนรอบข้างได้ยิน
 *
 * ## 🔴 สายเบอร์ฉุกเฉินไม่ได้ผ่านจอสายของเรา
 *
 * Android ใช้แอปโทรศัพท์ที่มากับเครื่องเสมอเมื่อเป็นเบอร์ฉุกเฉิน แม้แอปเราเป็นแอปหลัก · [MindInCallService]
 * อาจไม่ได้รับสายนั้น · เสียงตรงไม่ผูกกับบริการนี้จึงยังน่าจะใช้ได้ แต่ทดสอบกับเบอร์จริงไม่ได้
 */
class SosVoice(context: Context) {
    private val app = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val audio = app.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    private var tts: TextToSpeech? = null
    private var ready = false
    private var thai = false
    private var waiting: (() -> Unit)? = null

    private var savedAlarm: Int? = null
    private var tone: ToneGenerator? = null

    fun prepare(then: (() -> Unit)? = null) {
        if (ready) {
            then?.invoke()
            return
        }
        waiting = then
        if (tts != null) return
        tts = TextToSpeech(app) { status ->
            ready = status == TextToSpeech.SUCCESS
            if (ready) {
                val t = tts
                thai = (t?.setLanguage(Locale.forLanguageTag("th-TH")) ?: TextToSpeech.LANG_NOT_SUPPORTED) >= 0
                t?.setSpeechRate(0.92f)
            }
            main.post {
                // 🔴 ล้มก็ต้องเรียกต่อ · ไม่งั้นสายเงียบโดยไม่มีคำเตือน no_voice · ทิ้งตัวเก่าไว้ให้รอบหน้าลองใหม่
                if (!ready) release()
                val then2 = waiting
                waiting = null
                then2?.invoke()
            }
        }
    }

    /** ไม่ค้างการเชื่อมต่อกับตัวสังเคราะห์ตอนไม่มีเหตุ · เหตุถัดไปเปิดใหม่ */
    fun release() {
        tts?.shutdown()
        tts = null
        ready = false
    }

    /** เครื่องนี้พูดไทยได้ไหม · ตัวตรวจความพร้อมถาม */
    val hasThai: Boolean get() = ready && thai

    /** รู้แน่แล้วว่าไม่มีเสียงไทย · ยังเปิดตัวสังเคราะห์ไม่เสร็จไม่นับ */
    val noThai: Boolean get() = ready && !thai

    fun language(abroad: Boolean) {
        tts?.setLanguage(if (abroad) Locale.US else Locale.forLanguageTag("th-TH"))
    }

    // ── เรียกเจ้าของ ──

    /** ดังสุดผ่านช่องปลุก · เปิดเสียงเงียบ/โหมดห้ามรบกวนก็ยังได้ยิน · คืนค่าเดิมใน [quiet] */
    fun raiseAlarm() {
        val a = audio ?: return
        try {
            if (savedAlarm == null) savedAlarm = a.getStreamVolume(AudioManager.STREAM_ALARM)
            a.setStreamVolume(AudioManager.STREAM_ALARM, a.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
        } catch (e: Exception) {
            android.util.Log.w("GigGokSos", "alarm volume: ${e.javaClass.simpleName}")
        }
    }

    fun beep(inCall: Boolean) {
        try {
            val t = tone ?: ToneGenerator(
                if (inCall) AudioManager.STREAM_VOICE_CALL else AudioManager.STREAM_ALARM,
                if (inCall) 60 else ToneGenerator.MAX_VOLUME,
            ).also { tone = it }
            t.startTone(ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 500)
        } catch (e: Exception) {
            android.util.Log.w("GigGokSos", "tone: ${e.javaClass.simpleName}")
        }
    }

    fun buzz() {
        val v = app.getSystemService(Vibrator::class.java) ?: return
        val effect = VibrationEffect.createWaveform(longArrayOf(0, 500, 200, 500), -1)
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                v.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
            } else {
                v.vibrate(effect)
            }
        } catch (e: Exception) {
            android.util.Log.w("GigGokSos", "vibrate: ${e.javaClass.simpleName}")
        }
    }

    /** พูดออกลำโพง · [done] เรียกเสมอ แม้ตัวสังเคราะห์ล้ม · ถูกใช้เป็นจังหวะเปิดฟังคำตอบ */
    fun sayAloud(text: String, done: () -> Unit) {
        val t = tts
        if (t == null || !ready) {
            main.post(done)
            return
        }
        val id = "say${System.nanoTime()}"
        var fired = false
        val once = {
            if (!fired) {
                fired = true
                done()
            }
        }
        t.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
        t.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) { main.post(once) }

            @Deprecated("ระบบเก่ายังเรียก")
            override fun onError(utteranceId: String?) { main.post(once) }
        })
        if (t.speak(text, TextToSpeech.QUEUE_FLUSH, Bundle(), id) != TextToSpeech.SUCCESS) main.post(once)
        // ตัวสังเคราะห์บางยี่ห้อไม่ยิง onDone · นับถอยหลังต้องไม่หยุดรอมัน
        main.postDelayed(once, SAY_LIMIT_MS)
    }

    fun quiet() {
        tts?.stop()
        try {
            tone?.stopTone()
            tone?.release()
        } catch (e: Exception) {
            android.util.Log.w("GigGokSos", "tone stop: ${e.javaClass.simpleName}")
        }
        tone = null
        savedAlarm?.let { v ->
            try {
                audio?.setStreamVolume(AudioManager.STREAM_ALARM, v, 0)
            } catch (e: Exception) {
                android.util.Log.w("GigGokSos", "alarm restore: ${e.javaClass.simpleName}")
            }
        }
        savedAlarm = null
    }

    // ── พูดเข้าสาย ──

    @Volatile private var scriptRun = 0
    private var fallbackPlayer: MediaPlayer? = null
    private var speakerForced = false

    /** ทางเสียงที่ใช้จริงในสายล่าสุด · ไปอยู่ในรายงานที่เจ้าของอ่าน */
    @Volatile var path: String = "none"
        private set

    /**
     * พูดบทซ้ำเรื่อย ๆ จนสั่งหยุด · [text] มีพิกัดแล้ว
     *
     * เจ้าหน้าที่รับสายช้าหรือคำแรกหลุดได้ · วนซ้ำให้ฟังทันช่วงใดช่วงหนึ่ง
     */
    fun scriptInCall(text: String, silent: Boolean = false) {
        val run = ++scriptRun
        synth(text) { wav ->
            if (run != scriptRun) return@synth
            if (wav == null) {
                path = "no_voice"
                return@synth
            }
            Thread({ loop(run, wav, silent) }, "giggok-sos-script").apply { isDaemon = true; start() }
        }
    }

    private fun synth(text: String, done: (File?) -> Unit) {
        val t = tts
        if (t == null || !ready) {
            done(null)
            return
        }
        val out = File(app.cacheDir, "sos_script.wav")
        val id = "synth${System.nanoTime()}"
        var fired = false
        val once = { f: File? ->
            if (!fired) {
                fired = true
                done(f)
            }
        }
        t.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) { main.post { once(out) } }

            @Deprecated("ระบบเก่ายังเรียก")
            override fun onError(utteranceId: String?) { main.post { once(null) } }
        })
        if (t.synthesizeToFile(text, Bundle(), out, id) != TextToSpeech.SUCCESS) main.post { once(null) }
        main.postDelayed({ once(if (out.length() > 44) out else null) }, SYNTH_LIMIT_MS)
    }

    /**
     * เจ้าของ: "แจ้งให้เจ้าหน้าที่ฟัง ว่าเป็นระบบช่วยแจ้งเหตุ ต่อไปจะปิดไมค์ให้เจ้าหน้าที่ตั้งใจฟัง"
     *
     * รอบแรกเปิดไมค์ไว้ แล้วปิดรอบเว้นรอบ · 🔴 ยังไม่รู้ว่าปิดไมค์ตัดเสียงที่ใส่เข้าสายด้วยไหม · ถ้าตัด เจ้าหน้าที่ยังได้ยินรอบที่เปิด ·
     * ช่วงเว้นระหว่างรอบเปิดไมค์เสมอ · เจ้าของที่ยังมีสติต้องตะโกนบอกเจ้าหน้าที่ได้ ·
     * ทางลำโพงห้ามปิด เสียงเธอขึ้นสายผ่านไมค์นี้
     */
    private fun loop(run: Int, wav: File, silent: Boolean) {
        try {
            val line = SosWav.parse(wav.readBytes())?.let { SosWav.toLine(it) }
            var direct = line != null && DirectAudioClient.sosStart(app)
            path = if (direct) "direct" else "speaker"
            for (round in 0 until MAX_ROUNDS) {
                if (run != scriptRun) return
                // 🔴 แจ้งเงียบไม่มีทางตรง = เงียบต่อ · เปิดลำโพงตอนนี้คือบอกคนร้าย · เจ้าหน้าที่ยังได้ยินเสียงรอบตัวผ่านไมค์
                if (!direct && silent) {
                    path = "no_voice"
                    return
                }
                if (direct) holdMic(run, round % 2 == 1)
                val ok = if (direct) writeDirect(run, line!!) else speakerOnce(run, wav)
                holdMic(run, false)
                if (run != scriptRun) return
                if (!ok && direct) {
                    // ตัวช่วยหลุดกลางสาย · ถอยไปลำโพงทันที เจ้าหน้าที่ยังต้องได้ยิน
                    path = "direct_lost"
                    direct = false
                    continue
                }
                Thread.sleep(GAP_MS)
            }
        } catch (e: Exception) {
            // 🔴 เธรดนี้ล้มแล้วไม่มีใครรับ = แอปดับทั้งโปรเซสกลางเหตุ · จบสายลบไฟล์ระหว่างอ่านก็มาทางนี้
            android.util.Log.w("GigGokSos", "script: ${e.javaClass.simpleName}")
            if (run == scriptRun) path = "no_voice"
        } finally {
            holdMic(run, false)
        }
    }

    private var micHeld = false

    /** ใช้ของ Telecom เท่านั้น · 🔴 AudioManager ค้างข้ามสาย · โปรเซสตายกลางทาง สายถัดไปของเจ้าของจะเป็นใบ้ */
    private fun holdMic(run: Int, on: Boolean) {
        main.post {
            val s = MindInCallService.service
            if (s != null && on != micHeld && !(on && run != scriptRun)) {
                micHeld = on
                s.setMuted(on)
            }
        }
    }

    /** ส่งตามจังหวะเวลาจริง · เทรวดเดียวเกินคิวของตัวช่วย */
    private fun writeDirect(run: Int, line: ByteArray): Boolean {
        var at = 0
        while (at < line.size) {
            if (run != scriptRun) return true
            val end = minOf(at + FRAME_BYTES, line.size)
            if (!DirectAudioClient.sosWrite(line.copyOfRange(at, end))) return false
            at = end
            Thread.sleep(FRAME_MS)
        }
        return true
    }

    private fun speakerOnce(run: Int, wav: File): Boolean {
        val finished = java.util.concurrent.CountDownLatch(1)
        main.post {
            if (run != scriptRun) {
                finished.countDown()
                return@post
            }
            if (MindInCallService.service != null) {
                if (!CallAudio.open) CallAudio.open(app)
                CallAudio.play(app, wav.path, CallAudio.STREAM_CALL) { finished.countDown() }
            } else {
                // สายฉุกเฉินที่แอปโทรศัพท์ของเครื่องถือไว้ · เราสั่งเส้นทางผ่าน Telecom ไม่ได้
                forceSpeaker()
                playPlain(wav) { finished.countDown() }
            }
        }
        finished.await(SYNTH_LIMIT_MS * 3, java.util.concurrent.TimeUnit.MILLISECONDS)
        return true
    }

    @Suppress("DEPRECATION")
    private fun forceSpeaker() {
        try {
            audio?.isSpeakerphoneOn = true
            speakerForced = true
        } catch (e: Exception) {
            android.util.Log.w("GigGokSos", "speaker: ${e.javaClass.simpleName}")
        }
    }

    private fun playPlain(wav: File, done: () -> Unit) {
        try {
            fallbackPlayer?.release()
            fallbackPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                setDataSource(wav.path)
                setOnCompletionListener { done() }
                setOnErrorListener { _, _, _ -> done(); true }
                prepare()
                start()
            }
        } catch (e: Exception) {
            android.util.Log.w("GigGokSos", "player: ${e.javaClass.simpleName}")
            done()
        }
    }

    @Suppress("DEPRECATION")
    fun endScript() {
        scriptRun++
        if (micHeld) {
            micHeld = false
            MindInCallService.service?.setMuted(false)
        }
        DirectAudioClient.sosStop()
        CallAudio.stop()
        if (MindInCallService.service != null) CallAudio.close(app)
        try {
            fallbackPlayer?.release()
        } catch (e: Exception) {
            android.util.Log.w("GigGokSos", "player stop: ${e.javaClass.simpleName}")
        }
        fallbackPlayer = null
        if (speakerForced) {
            try {
                audio?.isSpeakerphoneOn = false
            } catch (e: Exception) {
                android.util.Log.w("GigGokSos", "speaker off: ${e.javaClass.simpleName}")
            }
            speakerForced = false
        }
        File(app.cacheDir, "sos_script.wav").delete()
    }

    fun close() {
        quiet()
        endScript()
        release()
    }

    companion object {
        private const val SAY_LIMIT_MS = 9_000L
        private const val SYNTH_LIMIT_MS = 15_000L
        private const val GAP_MS = 3_000L
        private const val MAX_ROUNDS = 12

        /** 200 มิลลิวินาทีของ 24 kHz 16 บิต · เท่าเพดานต่อเฟรมที่ DirectAudioClient ตัด */
        private const val FRAME_BYTES = 9_600
        private const val FRAME_MS = 190L
    }
}
