package com.xjanova.videogirl.sos

import android.Manifest
import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.xjanova.videogirl.R

/**
 * จอฉุกเฉิน · ขึ้นทับจอล็อก · เนทีฟล้วน ขึ้นได้ทันทีโดยไม่รอ Flutter
 *
 * เจ้าของ: "หยุดกระบวนการได้ถ้าเราแตะปุ่มหยุดทัน" · ปุ่มหยุดใหญ่กินครึ่งจอ ใช้ได้โดยไม่ปลดล็อก
 *
 * 🔒 จอนี้เปิดได้โดยไม่ปลดล็อก · **ห้ามมีข้อมูลสุขภาพ เบอร์ญาติ หรือพิกัด** · คนเก็บเครื่องได้ก็เห็นจอนี้ ·
 * แชร์พิกัดต้องปลดล็อกก่อนเสมอ ([share])
 */
class SosActivity : Activity() {
    private val ui = Handler(Looper.getMainLooper())
    private lateinit var title: TextView
    private lateinit var count: TextView
    private lateinit var line: TextView
    private lateinit var stop: Button
    private lateinit var help: Button
    private lateinit var share: Button

    private var recognizer: SpeechRecognizer? = null
    private var listening = false
    private var answered = false

    private val onState: (SosService.Snapshot) -> Unit = { s -> ui.post { render(s) } }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContentView(layout())
    }

    private fun layout(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#1B0B0D"))
            setPadding(dp(20), dp(40), dp(20), dp(24))
            gravity = Gravity.CENTER_HORIZONTAL
        }
        title = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 24f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        count = TextView(this).apply {
            setTextColor(Color.parseColor("#FFB4AB"))
            textSize = 72f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        line = TextView(this).apply {
            setTextColor(Color.parseColor("#F5DDDA"))
            textSize = 15f
            gravity = Gravity.CENTER
            setPadding(0, dp(6), 0, dp(14))
        }
        stop = big(getString(R.string.sos_action_stop), "#FFFFFF", "#B3261E", 34f).apply {
            setOnClickListener {
                answered = true
                SosService.stop(this@SosActivity)
            }
        }
        help = big(getString(R.string.sos_action_help), "#3B0A0A", "#FFB4AB", 18f).apply {
            setOnClickListener {
                answered = true
                SosService.helpNow(this@SosActivity)
            }
        }
        share = big(getString(R.string.sos_share_location), "#3B0A0A", "#FFDAD6", 16f).apply {
            visibility = View.GONE
            setOnClickListener { share() }
        }
        root.addView(title, full(wrap = true))
        root.addView(count, full(wrap = true))
        root.addView(line, full(wrap = true))
        root.addView(stop, LinearLayout.LayoutParams(-1, 0, 1f).apply { bottomMargin = dp(12) })
        root.addView(help, LinearLayout.LayoutParams(-1, dp(72)).apply { bottomMargin = dp(8) })
        root.addView(share, LinearLayout.LayoutParams(-1, dp(56)))
        return root
    }

    private fun full(wrap: Boolean) = LinearLayout.LayoutParams(-1, if (wrap) -2 else -1)

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    private fun big(text: String, fg: String, bg: String, size: Float) = Button(this).apply {
        this.text = text
        setTextColor(Color.parseColor(fg))
        textSize = size
        typeface = Typeface.DEFAULT_BOLD
        isAllCaps = false
        background = GradientDrawable().apply {
            cornerRadius = 32f * resources.displayMetrics.density
            setColor(Color.parseColor(bg))
        }
    }

    override fun onStart() {
        super.onStart()
        SosService.listeners.add(onState)
        render(SosService.now)
    }

    override fun onStop() {
        SosService.listeners.remove(onState)
        stopListening()
        super.onStop()
    }

    override fun onDestroy() {
        recognizer?.destroy()
        recognizer = null
        super.onDestroy()
    }

    private fun render(s: SosService.Snapshot) {
        val report = if (s.phase == SosService.Phase.DONE || s.phase == SosService.Phase.IDLE) {
            SosService.lastReport
        } else {
            null
        }
        when (s.phase) {
            SosService.Phase.ALERT -> {
                title.setText(
                    if (s.drill || s.rehearsal) R.string.sos_alert_title_drill else R.string.sos_alert_title
                )
                count.text = s.secondsLeft.toString()
                count.visibility = View.VISIBLE
                line.setText(R.string.sos_alert_body)
                stop.visibility = View.VISIBLE
                help.visibility = View.VISIBLE
                listen()
            }
            SosService.Phase.DISPATCH -> {
                stopListening()
                title.setText(R.string.sos_dispatching)
                count.visibility = View.GONE
                line.text = describe(s)
                stop.visibility = View.VISIBLE
                help.visibility = View.GONE
                share.visibility = View.VISIBLE
            }
            else -> {
                stopListening()
                answered = false // เหตุถัดไปในจอเดิมต้องฟังใหม่
                count.visibility = View.GONE
                stop.visibility = View.GONE
                help.visibility = View.GONE
                val r = report
                if (r == null) {
                    finish()
                    return
                }
                title.setText(SosService.reportTitle(r))
                line.text = describe(r)
                share.visibility = if (r.sent.isEmpty()) View.GONE else View.VISIBLE
            }
        }
    }

    /** 🔒 นับจำนวน ไม่บอกเบอร์ · เบอร์ฉุกเฉินบอกได้ เบอร์ญาติห้าม */
    private fun describe(s: SosService.Snapshot): String {
        val sms = s.sent.count { it.step is SosStep.Sms && (it.outcome == "sent" || it.outcome == "simulated") }
        val failed = s.sent.count { it.step is SosStep.Sms && it.outcome == "failed" }
        val calls = s.sent.filter { it.step is SosStep.Call }
        val lines = ArrayList<String>()
        lines.add(getString(R.string.sos_line_sms, sms))
        if (failed > 0) lines.add(getString(R.string.sos_line_sms_failed, failed))
        for (c in calls) {
            val step = c.step as SosStep.Call
            val who = if (step.official) step.to else getString(R.string.sos_line_contact)
            lines.add(
                when (c.outcome) {
                    "reached" -> getString(R.string.sos_line_reached, who)
                    "unsure" -> getString(R.string.sos_line_unsure, who)
                    "stopped" -> getString(R.string.sos_line_hang_up, who)
                    "not_dialer" -> getString(R.string.sos_line_not_dialer, who)
                    "simulated" -> getString(R.string.sos_line_would_call, who)
                    else -> getString(R.string.sos_line_no_answer, who)
                }
            )
        }
        if (s.cancelled && s.sent.any { it.step is SosStep.Call && it.outcome == "reached" && (it.step as SosStep.Call).official }) {
            lines.add(getString(R.string.sos_line_call_back))
        }
        if (s.voicePath == "no_voice") lines.add(getString(R.string.sos_line_no_voice))
        return lines.joinToString("\n")
    }

    /** 🔒 พิกัดออกจากเครื่องด้วยมือเจ้าของ · บนจอล็อกต้องปลดล็อกก่อน คนเก็บเครื่องได้ส่งไม่ได้ */
    private fun share() {
        val km = getSystemService(KeyguardManager::class.java)
        val go = { SosBridge.shareLocation(this, "any") }
        if (km?.isKeyguardLocked == true && Build.VERSION.SDK_INT >= 26) {
            km.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() { go() }
            })
        } else {
            go()
        }
    }

    // ── ฟังคำตอบ ──
    //
    // ใช้ตัวถอดเสียงของเครื่อง · ไม่มี/ล้ม = เหลือปุ่ม นับถอยหลังเดินต่อ · ไม่พึ่งการฟังเลยในการแจ้งเหตุ

    private fun listen() {
        if (listening || answered) return
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) return
        if (!SpeechRecognizer.isRecognitionAvailable(this)) return
        val r = recognizer ?: try {
            SpeechRecognizer.createSpeechRecognizer(this)
        } catch (e: RuntimeException) {
            null
        }?.also {
            it.setRecognitionListener(listener)
            recognizer = it
        } ?: return
        listening = true
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "th-TH")
            .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
        try {
            r.startListening(intent)
        } catch (e: RuntimeException) {
            listening = false
        }
    }

    private fun stopListening() {
        if (!listening) return
        listening = false
        try {
            recognizer?.cancel()
        } catch (e: RuntimeException) {
            android.util.Log.w("GigGokSos", "recognizer: ${e.javaClass.simpleName}")
        }
    }

    /** 🔒 ไม่ลงคำที่ได้ยิน */
    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onPartialResults(partialResults: Bundle?) {}
        override fun onEvent(eventType: Int, params: Bundle?) {}

        override fun onError(error: Int) {
            listening = false
            // รอบไม่ได้ยินอะไร · ลองใหม่ถ้ายังนับอยู่ · ล้มถาวรก็แค่ไม่มีเสียง ไม่ติดลูป
            if (error != SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS &&
                error != SpeechRecognizer.ERROR_RECOGNIZER_BUSY
            ) {
                ui.postDelayed({ if (SosService.now.phase == SosService.Phase.ALERT) listen() }, RETRY_MS)
            }
        }

        override fun onResults(results: Bundle?) {
            listening = false
            val heard = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION).orEmpty()
            val answers = heard.map { SosReply.classify(it) }
            when {
                SosReply.Answer.HELP in answers -> {
                    answered = true
                    SosService.helpNow(this@SosActivity)
                }
                SosReply.Answer.FINE in answers -> {
                    answered = true
                    SosService.stop(this@SosActivity)
                }
                else -> ui.postDelayed({ if (SosService.now.phase == SosService.Phase.ALERT) listen() }, RETRY_MS)
            }
        }
    }

    companion object {
        private const val RETRY_MS = 400L
    }
}

/** ปุ่มบนแจ้งเตือน · ไม่ export แอปอื่นสั่งไม่ได้ · ใช้ได้จากจอล็อกโดยไม่ปลดล็อก */
class SosReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            SosService.ACTION_STOP -> SosService.stop(context)
            SosService.ACTION_HELP -> SosService.helpNow(context)
            SosService.ACTION_MANUAL_SCREEN -> SosService.trigger(context, SosKind.OTHER.name, voice = false, drill = false)
        }
    }
}

/** เปิดเครื่อง/อัปเดตแอป · ตัวจับต้องกลับมาทำงานเองโดยเจ้าของไม่ต้องเปิดแอป */
class SosBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            SosService.sync(context)
        }
    }
}
