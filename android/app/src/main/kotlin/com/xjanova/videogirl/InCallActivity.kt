package com.xjanova.videogirl

import android.annotation.SuppressLint
import android.app.Activity
import android.app.KeyguardManager
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import android.text.TextUtils
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowInsets
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.xjanova.videogirl.PhoneUi.dp
import com.xjanova.videogirl.direct.setup.DirectAudioSetup
import java.util.Locale

/**
 * จอสาย — จอเดียวที่เจ้าของจะเห็นตอนมีสาย เมื่อแอปนี้เป็นแอปโทรศัพท์หลัก
 *
 * ## 🔴 ทำไมเป็นเนทีฟ ไม่ใช่ Flutter
 *
 * เป็นแอปหลักแล้ว **ทุกสายต้องผ่านจอนี้** สายออก สายเข้า สายซ้อน ทั้งหมด
 * ถ้าจอนี้ขึ้นช้าหรือพัง เจ้าของโทรออกรับสายไม่ได้ทั้งเครื่อง
 *
 * การเปิด Flutter engine ตอนสายกำลังดังกินได้หลายวินาทีถ้าแอปไม่ได้เปิดค้าง
 * ซึ่งแปลว่า**โทรศัพท์ดังแต่จอว่างเปล่า** · จอนี้จึงสร้างด้วย View เนทีฟล้วน
 * ไม่มี XML ไม่มี engine ไม่มีอะไรต้องรอ · หน้าตาอยู่ใน [PhoneUi]
 *
 * ## 🔴 จอนี้ไม่ตายเมื่อมายด์รับสาย
 *
 * พอเธอรับ เราเปิดจอ Flutter (ที่มีตัวเธอยกโทรศัพท์จริง ๆ) ทับขึ้นไป
 * แต่**ไม่ปิดจอนี้ทิ้ง** เพราะจอนี้คือทางหนีเมื่อ Flutter ไม่ขึ้นหรือถูกปัดทิ้ง
 * ถ้าปิดแล้ว Flutter ไม่ขึ้น เจ้าของจะเหลือสายที่วางไม่ได้อยู่ในมือ
 *
 * ตอนจอล็อก ย้ายไป Flutter ก็ต่อเมื่อเจ้าของเปิด "ขึ้นจอเธอตอนรับสาย" ไว้
 * (ค่าตั้งต้น) · MainActivity ขึ้นทับจอล็อกเฉพาะระหว่างสายนั้น ([handToFlutter])
 *
 * ## ปุ่มในสาย — เจ้าของคุยเอง
 *
 * ปิดไมค์ · แป้นกด (ส่งเสียงกดเลขเข้าสาย) · ลำโพง/บลูทูธ · พักสาย · เพิ่มสาย ·
 * สองสายแล้วกลายเป็น สลับสาย/รวมสาย · ให้มายด์คุยต่อ
 *
 * 🔴 ตอนเธอถือสาย ปิดไมค์/พักสาย/เพิ่มสาย/แป้นกด**กดไม่ได้** · เสียงเธอขึ้นสายผ่านไมค์ (ทางลำโพง)
 * ปิดไมค์ = ปลายสายไม่ได้ยินเธอ · พักสาย = ฝั่ง Dart เห็นว่าสายไม่ได้คุยอยู่แล้วปิดบทสนทนากลางสาย ·
 * เหลือลำโพงกับแทรกสาย
 *
 * 🔴 แนบหูแล้วจอต้องดับ ([syncProximity]) · ไม่ดับ = แก้มกดปิดไมค์หรือวางสายกลางประโยค
 */
class InCallActivity : Activity() {

    private val ui = Handler(Looper.getMainLooper())
    private var iso = "TH"
    private var avatarDp = 112

    private lateinit var heldBar: LinearLayout
    private lateinit var heldText: TextView
    private lateinit var avatarBox: FrameLayout
    private lateinit var pulse: PhoneUi.PulseView
    private lateinit var avatar: FrameLayout
    private lateinit var who: TextView
    private lateinit var numberLine: TextView

    /** สายนี้เข้าทางซิมไหน · ซ่อนเมื่อเครื่องมีซิมเดียว (บอกไปก็ไม่มีประโยชน์) */
    private lateinit var sim: TextView
    private lateinit var status: TextView

    /** เธอจะรับเองไหม — นับถอยหลัง หรือเหตุผลที่ไม่รับ · เดิมเงียบ เจ้าของเดาไม่ออก */
    private lateinit var autoHint: TextView

    private lateinit var ringPanel: LinearLayout
    private lateinit var mindPill: LinearLayout
    private lateinit var waitingNote: TextView

    private lateinit var callPanel: LinearLayout
    private lateinit var controls: LinearLayout
    private lateinit var pickPanel: LinearLayout
    private lateinit var keypadPanel: LinearLayout
    private lateinit var dtmfDigits: TextView
    private lateinit var postDial: TextView
    private lateinit var hideKeypad: TextView
    private lateinit var muteBtn: PhoneUi.ControlButton
    private lateinit var keypadBtn: PhoneUi.ControlButton
    private lateinit var audioBtn: PhoneUi.ControlButton

    /** เพิ่มสาย · มีสองสายแล้วเป็น รวมสาย */
    private lateinit var slotA: PhoneUi.ControlButton

    /** พักสาย · มีสองสายแล้วเป็น สลับสาย */
    private lateinit var slotB: PhoneUi.ControlButton
    private lateinit var mindBtn: PhoneUi.ControlButton

    private lateinit var routeSheet: FrameLayout
    private lateinit var routeList: LinearLayout

    private var twoCalls = false
    private var keypadOpen = false
    private val dtmf = StringBuilder()
    private var dtmfFor: Call? = null
    private var toneCall: Call? = null
    private var pickFor: Call? = null
    private var avatarKey: String? = null
    private var named: Pair<String?, String?>? = null

    /** คำเตือนที่ต้องค้างจนกว่าเรื่องจะจบ (เปิดลำโพงให้เธอไม่ได้) · render ปกติทับไม่ได้ */
    private var notice: Int? = null
    private var resumed = false
    private var lastActionAt = 0L
    private var proximity: PowerManager.WakeLock? = null

    /// นาฬิกาปล่อยกริ่งก่อนเธอรับ · ต้องยกเลิกได้ทุกทางที่สายจบ
    private var autoAnswer: Runnable? = null

    /// สายที่ตัดสินเรื่องรับเองไปแล้ว · ดู [armAutoAnswer]
    private var armedFor: Call? = null

    /** ตัวช่วยเสียงตรงหายไหม · null = ยังถามไม่เสร็จ · ดู [armAutoAnswer] */
    private var directDown: Boolean? = null

    /// เวลาที่เธอจะรับ (uptime) · ใช้นับถอยหลังบนจอ
    private var autoAt = 0L
    private val tick = object : Runnable {
        override fun run() {
            if (autoAnswer == null) return
            val left = ((autoAt - SystemClock.uptimeMillis() + 999) / 1000).toInt()
            hint(if (left > 0) getString(R.string.call_auto_in, left) else getString(R.string.call_auto_now))
            ui.postDelayed(this, 500)
        }
    }

    /** นาฬิกาสาย · เดินเฉพาะตอนจอนี้อยู่บนสุด */
    private val clock = object : Runnable {
        override fun run() {
            MindInCallService.focusCall()?.let { status.text = statusText(it) }
            ui.postDelayed(this, 1000)
        }
    }

    /// ย้ายไปจอ Flutter ไปแล้วหรือยัง — กันการเด้งซ้ำทุกครั้งที่ render
    private var handedOver = false

    private val onChanged = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) = render()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen()
        iso = PhoneUi.countryIso(this)
        val heightDp = resources.displayMetrics.heightPixels / resources.displayMetrics.density
        avatarDp = if (heightDp < 700f) 92 else 112
        setContentView(buildUi())

        open = this
        registerReceiver(
            onChanged,
            IntentFilter(MindInCallService.ACTION_CALL_CHANGED),
            if (Build.VERSION.SDK_INT >= 33) Context.RECEIVER_NOT_EXPORTED else 0
        )
        if (Build.VERSION.SDK_INT >= 33) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT,
                backCallback as android.window.OnBackInvokedCallback
            )
        }
        render()
    }

    /** สายซ้อนดังเข้ามาตอนจอนี้เปิดอยู่ · ระบบเรียกจอเดิม ต้องวาดสายใหม่ทันที ไม่ใช่รอสถานะขยับ */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        render()
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        render()
        ui.removeCallbacks(clock)
        ui.post(clock)
    }

    override fun onPause() {
        resumed = false
        ui.removeCallbacks(clock)
        stopTone()
        pulse.stop()
        releaseProximity()
        super.onPause()
    }

    override fun onDestroy() {
        if (open === this) open = null
        cancelAutoAnswer()
        ui.removeCallbacksAndMessages(null)
        releaseProximity()
        if (Build.VERSION.SDK_INT >= 33) {
            onBackInvokedDispatcher.unregisterOnBackInvokedCallback(backCallback as android.window.OnBackInvokedCallback)
        }
        try {
            unregisterReceiver(onChanged)
        } catch (e: IllegalArgumentException) {
            // ไม่ได้ลงทะเบียนไว้ — ไม่ใช่เรื่องที่ต้องพัง
        }
        super.onDestroy()
    }

    /**
     * ย้อนกลับ = ปิดแผงที่เปิดอยู่ก่อน แล้วค่อยถอยจอไปข้างหลัง ([goBack])
     *
     * 🔴 ไม่ปิดจอทิ้ง · ปิด = onDestroy ยกเลิกนาฬิกาที่ให้เธอรับเองกลางกริ่ง · กลับมาได้จากแจ้งเตือนสาย
     *
     * 🔴 สองทาง · Android 16 กับแอปที่ target 36 ไม่เรียก onBackPressed แล้ว (ย้อนกลับแบบใหม่เปิดเอง)
     * ต้องลงทะเบียน [backCallback] ด้วย · เครื่องที่ยังไม่เปิดแบบใหม่ ระบบไม่สนตัวที่ลงทะเบียน
     * ไว้และเรียก onBackPressed ตามเดิม = ไม่ทำซ้ำสองรอบ
     */
    @Suppress("OVERRIDE_DEPRECATION", "DEPRECATION")
    override fun onBackPressed() {
        if (!goBack()) super.onBackPressed()
    }

    private val backCallback: Any? = if (Build.VERSION.SDK_INT >= 33) {
        android.window.OnBackInvokedCallback { if (!goBack()) finish() }
    } else null

    /**
     * ต้องขึ้นทับจอล็อกและปลุกจอ
     *
     * ไม่ทำ = สายเข้าตอนจอดับแล้วไม่มีอะไรขึ้นเลย ซึ่งกับแอปโทรศัพท์หลัก
     * แปลว่ารับสายไม่ได้
     *
     * 🔴 **ไม่ขอปลดล็อก** (`requestDismissKeyguard`) · ขึ้นทับจอล็อกพอแล้วสำหรับรับ/วางสาย ·
     * ขอปลดล็อกบนเครื่องที่ล็อกด้วย PIN = แป้นกรอกรหัสเด้งขึ้นมาบังจอสายตั้งแต่กริ่งดัง แล้ว
     * หมดเวลาจอดับในไม่กี่วินาที (จอที่ถูกบังไม่นับเป็นจอที่ขอติดค้าง) · จอดับระหว่างที่เธอถือสาย
     * = ไมค์ของเธอได้แต่ความเงียบ (ดู [CallScreen])
     */
    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    // ── โครงจอ ───────────────────────────────────────────────

    private fun buildUi(): View {
        val root = FrameLayout(this).apply { background = PhoneUi.nightBackdrop() }
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(this@InCallActivity, 22), dp(this@InCallActivity, 14), dp(this@InCallActivity, 22), dp(this@InCallActivity, 18))
        }
        root.addView(col, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        PhoneUi.edgeToEdge(this, col, lightBars = false)

        col.addView(heldBar(), LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        col.addView(identity(), LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
        ringPanel = ringPanel()
        col.addView(ringPanel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        callPanel = callPanel()
        col.addView(callPanel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        routeSheet = routeSheet()
        root.addView(routeSheet, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        return root
    }

    /** อีกสายที่พักไว้ · แตะ = สลับไปคุยสายนั้น */
    private fun heldBar(): View {
        heldText = PhoneUi.text(this, 13f, PhoneUi.WHITE70, bold = true).apply {
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        heldBar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(this@InCallActivity, 14), dp(this@InCallActivity, 9), dp(this@InCallActivity, 12), dp(this@InCallActivity, 9))
            background = PhoneUi.ripple(
                PhoneUi.rounded(PhoneUi.NIGHT_GLASS, dp(this@InCallActivity, 20).toFloat(), dp(this@InCallActivity, 1), 0x24FFFFFF),
                0x40FFFFFF, null
            )
            isClickable = true
            setOnClickListener { swap() }
            visibility = View.GONE
            addView(PhoneUi.icon(this@InCallActivity, R.drawable.ic_ph_pause, PhoneUi.WHITE70, 16))
            addView(heldText, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).also {
                it.leftMargin = dp(this@InCallActivity, 8)
                it.rightMargin = dp(this@InCallActivity, 10)
            })
            addView(PhoneUi.icon(this@InCallActivity, R.drawable.ic_ph_swap, Color.WHITE, 18))
        }
        return heldBar
    }

    private fun identity(): View {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        avatarBox = FrameLayout(this)
        pulse = PhoneUi.PulseView(this).apply { innerRadiusPx = dp(this@InCallActivity, avatarDp) / 2f }
        avatarBox.addView(pulse, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        avatar = FrameLayout(this).apply { elevation = dp(this@InCallActivity, 8).toFloat() }
        avatarBox.addView(avatar, FrameLayout.LayoutParams(dp(this, avatarDp), dp(this, avatarDp), Gravity.CENTER))
        val ring = dp(this, avatarDp + 76)
        box.addView(avatarBox, LinearLayout.LayoutParams(ring, ring))

        who = PhoneUi.text(this, 30f, Color.WHITE, bold = true).apply {
            gravity = Gravity.CENTER
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
        }
        box.addView(who, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).also { it.topMargin = dp(this, 6) })
        numberLine = PhoneUi.text(this, 15f, PhoneUi.WHITE70).apply { gravity = Gravity.CENTER }
        box.addView(numberLine, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).also { it.topMargin = dp(this, 6) })
        sim = PhoneUi.text(this, 12f, Color.WHITE, bold = true).apply {
            gravity = Gravity.CENTER
            setPadding(dp(this@InCallActivity, 12), dp(this@InCallActivity, 4), dp(this@InCallActivity, 12), dp(this@InCallActivity, 4))
            background = PhoneUi.rounded(0x337C6CFF, dp(this@InCallActivity, 12).toFloat())
            visibility = View.GONE
        }
        box.addView(sim, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).also { it.topMargin = dp(this, 10) })
        status = PhoneUi.text(this, 15f, PhoneUi.WHITE70).apply { gravity = Gravity.CENTER }
        box.addView(status, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).also { it.topMargin = dp(this, 12) })
        autoHint = PhoneUi.text(this, 13f, HINT).apply {
            gravity = Gravity.CENTER
            setLineSpacing(0f, 1.2f)
            visibility = View.GONE
        }
        box.addView(autoHint, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).also { it.topMargin = dp(this, 8) })
        return box
    }

    /** ตอนสายดัง: ให้มายด์รับ · ปฏิเสธ · รับสาย */
    private fun ringPanel(): LinearLayout {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(0, 0, 0, dp(this@InCallActivity, 10))
        }
        // ปุ่มของมายด์ — ปุ่มเดียวกับ "แทรกสาย" ในสาย: สวิตช์เดียวว่าใครถือสายนี้อยู่
        mindPill = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(this@InCallActivity, 20), dp(this@InCallActivity, 12), dp(this@InCallActivity, 24), dp(this@InCallActivity, 12))
            background = PhoneUi.ripple(
                PhoneUi.roundedGradient(intArrayOf(PhoneUi.PINK, PhoneUi.VIOLET), dp(this@InCallActivity, 26).toFloat()),
                0x55FFFFFF, null
            )
            elevation = dp(this@InCallActivity, 6).toFloat()
            isClickable = true
            contentDescription = getString(R.string.call_mind_answer)
            // รับแทนอย่างเดียว ไม่สลับ · ใช้ toggleMind ตอนเธอถือสายแรกอยู่ = ดึงสายแรกคืน สายที่ดังยังดังต่อ
            setOnClickListener { if (once() && !MindInCallService.mindHandling) letMindAnswer() }
            PhoneUi.pressScale(this)
            addView(PhoneUi.icon(this@InCallActivity, R.drawable.ic_ph_sparkle, Color.WHITE, 20))
            addView(PhoneUi.text(this@InCallActivity, 15f, Color.WHITE, bold = true).apply {
                setText(R.string.call_mind_answer)
            }, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).also { it.leftMargin = dp(this@InCallActivity, 10) })
        }
        panel.addView(mindPill, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT))
        waitingNote = PhoneUi.text(this, 12.5f, PhoneUi.WHITE70).apply {
            gravity = Gravity.CENTER
            setText(R.string.call_waiting_note)
            visibility = View.GONE
        }
        panel.addView(waitingNote, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).also { it.topMargin = dp(this, 12) })

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        val decline = PhoneUi.bigRound(this, R.drawable.ic_ph_call_end, intArrayOf(PhoneUi.RED, PhoneUi.RED_DEEP), 76, 32, getString(R.string.call_decline))
        decline.setOnClickListener { hangUp() }
        val answer = PhoneUi.bigRound(this, R.drawable.ic_ph_call, intArrayOf(PhoneUi.GREEN, PhoneUi.GREEN_DEEP), 76, 32, getString(R.string.call_answer))
        answer.setOnClickListener { pickUp() }
        row.addView(labelled(decline, R.string.call_decline), LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        row.addView(labelled(answer, R.string.call_answer), LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        panel.addView(row, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).also { it.topMargin = dp(this, 26) })
        return panel
    }

    private fun labelled(button: View, label: Int): View = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        addView(button)
        addView(PhoneUi.text(this@InCallActivity, 13f, PhoneUi.WHITE70).apply { setText(label) },
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).also { it.topMargin = dp(this@InCallActivity, 10) })
    }

    /** ในสาย: แป้นกด (ซ่อนอยู่) · เลือกซิม · ปุ่มควบคุม · ส่งเลขต่อ · วางสาย */
    private fun callPanel(): LinearLayout {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }

        keypadPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            visibility = View.GONE
        }
        dtmfDigits = PhoneUi.text(this, 28f, Color.WHITE).apply {
            gravity = Gravity.CENTER
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.START
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
            letterSpacing = .06f
        }
        keypadPanel.addView(dtmfDigits, LinearLayout.LayoutParams(MATCH_PARENT, dp(this, 44)))
        val heightDp = resources.displayMetrics.heightPixels / resources.displayMetrics.density
        val keyDp = ((heightDp - 430f) / 4.9f).toInt().coerceIn(56, 74)
        keypadPanel.addView(
            PhoneUi.keypad(
                this, dark = true, keyDp = keyDp, gapDp = 10,
                onDown = { k, v -> tone(k, v) },
                onUp = { stopTone() },
            ),
            LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).also { it.topMargin = dp(this, 6) }
        )
        panel.addView(keypadPanel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        pickPanel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
        }
        panel.addView(pickPanel, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        muteBtn = PhoneUi.ControlButton(this, R.drawable.ic_ph_mic_off, getString(R.string.call_mute))
        muteBtn.setOnClickListener { toggleMute() }
        keypadBtn = PhoneUi.ControlButton(this, R.drawable.ic_ph_dialpad, getString(R.string.dial_tab_keypad))
        keypadBtn.setOnClickListener { setKeypad(!keypadOpen) }
        audioBtn = PhoneUi.ControlButton(this, R.drawable.ic_ph_speaker, getString(R.string.call_speaker))
        audioBtn.setOnClickListener { onAudioTap() }
        slotA = PhoneUi.ControlButton(this, R.drawable.ic_ph_add_call, getString(R.string.call_add))
        slotA.setOnClickListener { if (twoCalls) merge() else addCall() }
        slotB = PhoneUi.ControlButton(this, R.drawable.ic_ph_pause, getString(R.string.call_hold))
        slotB.setOnClickListener { if (twoCalls) swap() else toggleHold() }
        mindBtn = PhoneUi.ControlButton(this, R.drawable.ic_ph_sparkle, getString(R.string.call_mind_take))
        mindBtn.setOnClickListener { toggleMind() }

        controls = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        for ((i, row) in listOf(listOf(muteBtn, keypadBtn, audioBtn), listOf(slotA, slotB, mindBtn)).withIndex()) {
            val line = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            for (b in row) line.addView(b, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
            controls.addView(line, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).also {
                if (i > 0) it.topMargin = dp(this, 20)
            })
        }
        panel.addView(controls, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        postDial = PhoneUi.text(this, 14f, Color.WHITE, bold = true).apply {
            gravity = Gravity.CENTER
            setPadding(dp(this@InCallActivity, 20), dp(this@InCallActivity, 11), dp(this@InCallActivity, 20), dp(this@InCallActivity, 11))
            background = PhoneUi.ripple(
                PhoneUi.roundedGradient(intArrayOf(PhoneUi.TEAL, PhoneUi.VIOLET), dp(this@InCallActivity, 22).toFloat()),
                0x55FFFFFF, null
            )
            isClickable = true
            visibility = View.GONE
            setOnClickListener { MindInCallService.focusCall()?.let { MindInCallService.continuePostDial(it) } }
        }
        panel.addView(postDial, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).also { it.topMargin = dp(this, 16) })

        val endRow = FrameLayout(this)
        val end = PhoneUi.bigRound(this, R.drawable.ic_ph_call_end, intArrayOf(PhoneUi.RED, PhoneUi.RED_DEEP), 72, 30, getString(R.string.call_hangup))
        end.setOnClickListener { hangUp() }
        endRow.addView(end, FrameLayout.LayoutParams(dp(this, 72), dp(this, 72), Gravity.CENTER))
        hideKeypad = PhoneUi.text(this, 14f, PhoneUi.WHITE70, bold = true).apply {
            setText(R.string.call_keypad_hide)
            setPadding(dp(this@InCallActivity, 12), dp(this@InCallActivity, 10), dp(this@InCallActivity, 12), dp(this@InCallActivity, 10))
            isClickable = true
            visibility = View.GONE
            setOnClickListener { setKeypad(false) }
        }
        endRow.addView(hideKeypad, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.END or Gravity.CENTER_VERTICAL))
        panel.addView(endRow, LinearLayout.LayoutParams(MATCH_PARENT, dp(this, 84)).also { it.topMargin = dp(this, 22) })
        return panel
    }

    /** เลือกทางเสียง (หูโทรศัพท์/หูฟัง · ลำโพง · บลูทูธแต่ละตัว) · มีเมื่อต่อบลูทูธไว้เท่านั้น */
    private fun routeSheet(): FrameLayout {
        val sheet = FrameLayout(this).apply {
            setBackgroundColor(0x990B0820.toInt())
            isClickable = true
            visibility = View.GONE
            setOnClickListener { showRoutes(false) }
        }
        val r = dp(this, 28).toFloat()
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(this@InCallActivity, 18), dp(this@InCallActivity, 20), dp(this@InCallActivity, 18), dp(this@InCallActivity, 18))
            background = GradientDrawable().apply {
                cornerRadii = floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f)
                setColor(0xFF1E1745.toInt())
            }
            isClickable = true
        }
        card.addView(PhoneUi.text(this, 13f, PhoneUi.WHITE55, bold = true).apply {
            setText(R.string.call_route_title)
            letterSpacing = .08f
            setPadding(dp(this@InCallActivity, 16), 0, 0, dp(this@InCallActivity, 8))
        })
        routeList = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        card.addView(routeList)
        sheet.addView(card, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT, Gravity.BOTTOM))
        // แผ่นเลื่อนขึ้นจากขอบล่าง · เว้นแถบนำทางเอง (วาดใต้แถบระบบ ดู PhoneUi.edgeToEdge)
        sheet.setOnApplyWindowInsetsListener { _, insets ->
            val bottom = if (Build.VERSION.SDK_INT >= 30) {
                insets.getInsets(WindowInsets.Type.systemBars()).bottom
            } else {
                @Suppress("DEPRECATION")
                val legacy = insets.systemWindowInsetBottom
                legacy
            }
            card.setPadding(card.paddingLeft, card.paddingTop, card.paddingRight, dp(this, 18) + bottom)
            insets
        }
        return sheet
    }

    // ── วาด ─────────────────────────────────────────────────

    private fun render() {
        val call = MindInCallService.focusCall()
        if (call == null) {
            cancelAutoAnswer()
            releaseProximity()
            finishAndRemoveTask()
            return
        }

        val state = MindInCallService.stateOf(call)
        val ringing = state == Call.STATE_RINGING
        val mindOn = MindInCallService.mindHandling
        val top = MindInCallService.topCalls()

        renderWho(call)
        renderSim(call)
        status.text = statusText(call)

        val held = top.firstOrNull { it !== call && MindInCallService.stateOf(it) == Call.STATE_HOLDING }
        heldBar.visibility = if (held != null && !ringing) View.VISIBLE else View.GONE
        if (held != null) heldText.text = getString(R.string.call_on_hold_who, labelOf(held))

        ringPanel.visibility = if (ringing) View.VISIBLE else View.GONE
        callPanel.visibility = if (ringing) View.GONE else View.VISIBLE
        if (ringing && resumed) pulse.start() else pulse.stop()

        if (ringing) {
            if (keypadOpen) setKeypad(false)
            showRoutes(false)
            // ปุ่มของเธอมีได้ก็ต่อเมื่อระบบผูกกับบริการเราอยู่จริง — ไม่งั้นกดแล้ว
            // เปิดลำโพงไม่ได้ ซึ่งแปลว่าเธอรับแล้วปลายสายเงียบสนิท
            // เธอถือสายแรกอยู่แล้ว (สายซ้อนดังเข้ามา) = ไม่มีปุ่มนี้ · เธอคุยสองสายพร้อมกันไม่ได้
            mindPill.visibility =
                if (MindInCallService.service != null && !mindOn) View.VISIBLE else View.GONE
            waitingNote.visibility = if (top.size > 1) View.VISIBLE else View.GONE
        } else {
            renderPick(call, state == Call.STATE_SELECT_PHONE_ACCOUNT)
            renderControls(call, state, mindOn, top)
        }

        if (ringing) armAutoAnswer(call) else {
            // นับถอยหลังอยู่แล้วกริ่งหยุด = เจ้าของคว้าเครื่องทัน หรือคนโทรวางก่อน
            if (autoAnswer != null) MindPrefs.noteAutoAnswer(this, "stopped_ringing")
            cancelAutoAnswer()
            if (!mindOn) notice = null
            hint(notice?.let { getString(it) })
        }
        // จอติดค้างตลอดที่เธอถือสาย (ทั้งตอนอยู่จอนี้ และตอนจอนี้อยู่ใต้จอเธอ) · ดู [CallScreen]
        CallScreen.apply(this)
        syncProximity(state, mindOn)
        if (mindOn && state == Call.STATE_ACTIVE) handToFlutter()
    }

    private fun hint(text: CharSequence?) {
        autoHint.text = text ?: ""
        autoHint.visibility = if (text.isNullOrEmpty()) View.GONE else View.VISIBLE
    }

    private fun renderWho(call: Call) {
        val number = call.details.handle?.schemeSpecificPart?.takeIf { it.isNotBlank() }
        val conference = call.details.hasProperty(Call.Details.PROPERTY_CONFERENCE)
        val name = if (conference) null else nameOf(number)
        who.text = when {
            conference -> getString(R.string.call_conference, call.children.size.coerceAtLeast(2))
            name != null -> name
            number != null -> PhoneUi.formatNumber(number, iso)
            else -> getString(R.string.call_unknown)
        }
        val showNumber = name != null && number != null && !keypadOpen
        numberLine.text = if (showNumber) PhoneUi.formatNumber(number, iso) else ""
        numberLine.visibility = if (showNumber) View.VISIBLE else View.GONE
        bindAvatar(if (conference) "conference" else number ?: "unknown", name, number, conference)
    }

    /** ชื่อในสมุดโทรศัพท์ · จำเบอร์ล่าสุดไว้ จอวาดใหม่ทุกครั้งที่สายขยับ ไม่ต้องค้นซ้ำ */
    private fun nameOf(number: String?): String? {
        named?.let { (n, name) -> if (n == number) return name }
        val name = CallBridge(this).nameFor(number)
        named = number to name
        return name
    }

    private fun labelOf(call: Call): String {
        if (call.details.hasProperty(Call.Details.PROPERTY_CONFERENCE)) {
            return getString(R.string.call_conference, call.children.size.coerceAtLeast(2))
        }
        val number = call.details.handle?.schemeSpecificPart?.takeIf { it.isNotBlank() }
        return CallBridge(this).nameFor(number)
            ?: number?.let { PhoneUi.formatNumber(it, iso) }
            ?: getString(R.string.call_unknown)
    }

    /** รูปคนโทร · ถอดรูปจากสมุดโทรศัพท์บนเธรดแยก จอต้องขึ้นก่อนเสมอ */
    private fun bindAvatar(key: String, name: String?, number: String?, conference: Boolean) {
        if (avatarKey == key) return
        avatarKey = key
        PhoneUi.bindAvatar(avatar, name, number ?: key, null, avatarDp)
        if (conference || number == null) return
        val app = applicationContext
        val px = dp(this, avatarDp * 2)
        Thread {
            val bmp = PhoneUi.contactPhoto(app, number, px)
            if (bmp != null) ui.post {
                if (!isDestroyed && avatarKey == key) PhoneUi.bindAvatar(avatar, name, number, bmp, avatarDp)
            }
        }.start()
    }

    private fun renderSim(call: Call) {
        // ซิมของสาย · อ่านทุกรอบ render ได้ (ถูก) แต่ล้มต้องไม่ทำจอนี้พัง
        val s = SimInfo.of(this, call)
        val carrier = s?.carrier(this)
        val simText = when {
            s == null || s.count < 2 -> null
            s.slot != null && carrier != null -> getString(R.string.call_sim_label, s.slot, carrier)
            s.slot != null -> getString(R.string.call_sim, s.slot)
            else -> s.label
        }
        sim.text = simText ?: ""
        sim.visibility = if (simText == null || keypadOpen) View.GONE else View.VISIBLE
    }

    private fun statusText(call: Call): String {
        val state = MindInCallService.stateOf(call)
        val base = getString(
            when {
                MindInCallService.mindHandling && state == Call.STATE_ACTIVE -> R.string.call_mind_talking
                state == Call.STATE_RINGING -> R.string.call_incoming
                state == Call.STATE_SELECT_PHONE_ACCOUNT -> R.string.call_pick_sim
                state == Call.STATE_DIALING || state == Call.STATE_CONNECTING -> R.string.call_dialing
                state == Call.STATE_ACTIVE -> R.string.call_active
                state == Call.STATE_HOLDING -> R.string.call_holding
                state == Call.STATE_DISCONNECTED || state == Call.STATE_DISCONNECTING -> R.string.call_ended
                else -> R.string.call_connecting
            }
        )
        val since = call.details.connectTimeMillis
        if (state != Call.STATE_ACTIVE || since <= 0) return base
        val s = ((System.currentTimeMillis() - since) / 1000).coerceAtLeast(0)
        val time = if (s >= 3600) String.format(Locale.ROOT, "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
        else String.format(Locale.ROOT, "%02d:%02d", s / 60, s % 60)
        return "$base · $time"
    }

    private fun renderControls(call: Call, state: Int, mindOn: Boolean, top: List<Call>) {
        val picking = state == Call.STATE_SELECT_PHONE_ACCOUNT
        val over = state == Call.STATE_DISCONNECTED || state == Call.STATE_DISCONNECTING
        val talking = state == Call.STATE_ACTIVE
        val owner = !mindOn && !over
        val audio = MindInCallService.service?.callAudioState
        twoCalls = top.size > 1

        if (keypadOpen && !(owner && talking)) setKeypad(false)
        controls.visibility = if (picking || keypadOpen) View.GONE else View.VISIBLE

        muteBtn.set(
            audio?.isMuted == true,
            owner && audio != null && (talking || state == Call.STATE_HOLDING ||
                state == Call.STATE_DIALING || state == Call.STATE_CONNECTING)
        )
        keypadBtn.set(keypadOpen, owner && talking)
        renderAudio(audio, !over && audio != null)

        val active = top.firstOrNull { MindInCallService.stateOf(it) == Call.STATE_ACTIVE }
        if (twoCalls) {
            slotA.relabel(R.drawable.ic_ph_merge, getString(R.string.call_merge))
            slotA.set(false, owner && canMerge(active))
            slotB.relabel(R.drawable.ic_ph_swap, getString(R.string.call_swap))
            slotB.set(false, owner && top.any { MindInCallService.stateOf(it) == Call.STATE_HOLDING })
        } else {
            val holding = state == Call.STATE_HOLDING
            slotA.relabel(R.drawable.ic_ph_add_call, getString(R.string.call_add))
            slotA.set(false, owner && (talking || holding))
            slotB.relabel(R.drawable.ic_ph_pause, getString(R.string.call_hold))
            slotB.set(holding, owner && (holding || (talking && call.details.can(Call.Details.CAPABILITY_HOLD))))
        }

        if (mindOn) {
            mindBtn.relabel(R.drawable.ic_ph_barge, getString(R.string.call_mind_barge))
            mindBtn.set(true, !over)
        } else {
            mindBtn.relabel(R.drawable.ic_ph_sparkle, getString(R.string.call_mind_take))
            mindBtn.set(false, MindInCallService.service != null && talking && !twoCalls)
        }

        val pending = MindInCallService.postDialFor(call)
        postDial.visibility = if (pending != null && !over) View.VISIBLE else View.GONE
        if (pending != null) postDial.text = getString(R.string.call_post_dial, pending)
    }

    private fun renderAudio(audio: CallAudioState?, enabled: Boolean) {
        val route = audio?.route ?: CallAudioState.ROUTE_EARPIECE
        val bt = audio != null && has(audio.supportedRouteMask, CallAudioState.ROUTE_BLUETOOTH)
        when {
            route == CallAudioState.ROUTE_BLUETOOTH ->
                audioBtn.relabel(R.drawable.ic_ph_bluetooth, getString(R.string.call_route_bluetooth))
            bt && route == CallAudioState.ROUTE_WIRED_HEADSET ->
                audioBtn.relabel(R.drawable.ic_ph_headset, getString(R.string.call_route_headset))
            bt && route == CallAudioState.ROUTE_EARPIECE ->
                audioBtn.relabel(R.drawable.ic_ph_earpiece, getString(R.string.call_route_earpiece))
            else -> audioBtn.relabel(R.drawable.ic_ph_speaker, getString(R.string.call_speaker))
        }
        audioBtn.set(route == CallAudioState.ROUTE_SPEAKER || route == CallAudioState.ROUTE_BLUETOOTH, enabled)
    }

    // ── เลือกซิม ─────────────────────────────────────────────

    /**
     * สายออกที่ยังไม่รู้ว่าจะออกซิมไหน (เครื่องสองซิมที่ตั้ง "ถามทุกครั้ง")
     *
     * 🔴 ระบบรอแอปโทรศัพท์หลักเลือกให้ · ไม่มีใครเลือก = สายค้าง "กำลังต่อสาย" ไม่มีวันออก
     * (แตะเบอร์จากเว็บ/แชท หรือแป้นโทรของยี่ห้อเครื่อง จะมาทางนี้)
     */
    private fun renderPick(call: Call, picking: Boolean) {
        pickPanel.visibility = if (picking) View.VISIBLE else View.GONE
        if (!picking || pickFor === call) return
        pickFor = call
        pickPanel.removeAllViews()
        for ((i, handle) in accountsFor(call).withIndex()) {
            val s = SimInfo.of(this, handle)
            val pill = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(dp(this@InCallActivity, 20), 0, dp(this@InCallActivity, 20), 0)
                background = PhoneUi.ripple(
                    PhoneUi.rounded(PhoneUi.NIGHT_GLASS, dp(this@InCallActivity, 30).toFloat(), dp(this@InCallActivity, 1), 0x24FFFFFF),
                    0x40FFFFFF, null
                )
                isClickable = true
                contentDescription = getString(R.string.dial_call_sim, s?.slot ?: (i + 1))
                setOnClickListener { choose(call, handle) }
                PhoneUi.pressScale(this)
            }
            pill.addView(PhoneUi.icon(this, R.drawable.ic_ph_sim, Color.WHITE, 24))
            val texts = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
            texts.addView(PhoneUi.text(this, 16f, Color.WHITE, bold = true).apply {
                text = getString(R.string.dial_sim, s?.slot ?: (i + 1))
            })
            s?.carrier(this)?.let { label ->
                texts.addView(PhoneUi.text(this, 12f, PhoneUi.WHITE70).apply {
                    text = label
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    setPadding(0, dp(this@InCallActivity, 3), 0, 0)
                })
            }
            pill.addView(texts, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).also { it.leftMargin = dp(this, 14) })
            pickPanel.addView(pill, LinearLayout.LayoutParams(MATCH_PARENT, dp(this, 62)).also {
                if (i > 0) it.topMargin = dp(this, 12)
            })
        }
    }

    private fun accountsFor(call: Call): List<PhoneAccountHandle> {
        val offered = offeredAccounts(call)
        if (!offered.isNullOrEmpty()) return offered
        return try {
            getSystemService(TelecomManager::class.java)?.callCapablePhoneAccounts.orEmpty()
        } catch (e: SecurityException) {
            emptyList()
        }
    }

    /** ซิมที่ระบบเสนอมากับสาย · อยู่ใน intent extras ของสายที่รอเลือกซิม */
    @Suppress("DEPRECATION")
    private fun offeredAccounts(call: Call): List<PhoneAccountHandle>? = try {
        val extras = call.details.intentExtras
        if (Build.VERSION.SDK_INT >= 33) {
            extras?.getParcelableArrayList(Call.AVAILABLE_PHONE_ACCOUNTS, PhoneAccountHandle::class.java)
        } else {
            extras?.getParcelableArrayList<PhoneAccountHandle>(Call.AVAILABLE_PHONE_ACCOUNTS)
        }
    } catch (e: RuntimeException) {
        null
    }

    private fun choose(call: Call, handle: PhoneAccountHandle) {
        if (!once() || MindInCallService.stateOf(call) != Call.STATE_SELECT_PHONE_ACCOUNT) return
        call.phoneAccountSelected(handle, false)
    }

    // ── ปุ่มในสาย ─────────────────────────────────────────────

    /** ปุ่มที่สั่งเครือข่าย (พัก สลับ รวม เพิ่มสาย) · กดรัวภายในเสี้ยววินาทีนับครั้งเดียว */
    private fun once(): Boolean {
        val now = SystemClock.uptimeMillis()
        if (now - lastActionAt < 700) return false
        lastActionAt = now
        return true
    }

    private fun has(mask: Int, route: Int) = (mask and route) != 0

    private fun toggleMute() {
        val service = MindInCallService.service ?: return
        if (MindInCallService.mindHandling) return
        service.setMuted(service.callAudioState?.isMuted != true)
    }

    private fun toggleHold() {
        if (!once()) return
        val call = MindInCallService.focusCall() ?: return
        when (MindInCallService.stateOf(call)) {
            Call.STATE_HOLDING -> call.unhold()
            Call.STATE_ACTIVE -> if (call.details.can(Call.Details.CAPABILITY_HOLD)) call.hold()
        }
    }

    /** สลับสาย: สายที่พักไว้กลับมาคุย · ระบบพักสายที่คุยอยู่ให้เอง */
    private fun swap() {
        if (!once() || MindInCallService.mindHandling) return
        val top = MindInCallService.topCalls()
        val active = top.firstOrNull { MindInCallService.stateOf(it) == Call.STATE_ACTIVE }
        val held = top.firstOrNull { MindInCallService.stateOf(it) == Call.STATE_HOLDING }
        when {
            active != null && active.details.can(Call.Details.CAPABILITY_SWAP_CONFERENCE) -> active.swapConference()
            held != null -> held.unhold()
        }
    }

    private fun canMerge(active: Call?) = active != null &&
        (active.conferenceableCalls.isNotEmpty() || active.details.can(Call.Details.CAPABILITY_MERGE_CONFERENCE))

    private fun merge() {
        if (!once()) return
        val active = MindInCallService.topCalls().firstOrNull { MindInCallService.stateOf(it) == Call.STATE_ACTIVE } ?: return
        val other = active.conferenceableCalls.firstOrNull()
        when {
            other != null -> active.conference(other)
            active.details.can(Call.Details.CAPABILITY_MERGE_CONFERENCE) -> active.mergeConference()
        }
    }

    /** เพิ่มสาย = เปิดแป้นโทร · กดโทรจากที่นั่น ระบบพักสายนี้ให้เอง · แถบเขียวด้านบนพากลับมา */
    private fun addCall() {
        if (!once()) return
        try {
            startActivity(Intent(this, DialerActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) {
            // เปิดแป้นไม่ได้ก็อยู่ในสายต่อ
        }
    }

    private fun setKeypad(open: Boolean) {
        if (keypadOpen == open) return
        keypadOpen = open
        keypadPanel.visibility = if (open) View.VISIBLE else View.GONE
        hideKeypad.visibility = if (open) View.VISIBLE else View.GONE
        avatarBox.visibility = if (open) View.GONE else View.VISIBLE
        if (!open) stopTone()
        render()
    }

    /** สายที่รับเสียงกดเลข · ต้องเป็นสายที่กำลังคุยอยู่จริง ไม่ใช่สายที่พักไว้ */
    private fun dtmfTarget(): Call? =
        MindInCallService.topCalls().firstOrNull { MindInCallService.stateOf(it) == Call.STATE_ACTIVE }

    /** กดค้าง = เสียงยาวตามนิ้ว (ระบบตอบรับอัตโนมัติบางเจ้าฟังความยาว) · ปล่อยแล้วหยุด */
    private fun tone(k: Char, v: View) {
        v.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        val target = dtmfTarget() ?: return
        if (dtmfFor !== target) {
            dtmfFor = target
            dtmf.setLength(0)
        }
        stopTone()
        target.playDtmfTone(k)
        toneCall = target
        dtmf.append(k)
        if (dtmf.length > 40) dtmf.delete(0, dtmf.length - 40)
        dtmfDigits.text = dtmf
    }

    private fun stopTone() {
        val call = toneCall ?: return
        toneCall = null
        call.stopDtmfTone()
    }

    // ── ทางเสียง ─────────────────────────────────────────────

    /** ไม่มีบลูทูธ = สลับลำโพงตรง ๆ · มีบลูทูธ = ให้เลือก (สองทางจำไม่ได้ว่ากดแล้วจะไปไหน) */
    private fun onAudioTap() {
        val audio = MindInCallService.service?.callAudioState ?: return
        if (has(audio.supportedRouteMask, CallAudioState.ROUTE_BLUETOOTH)) {
            openRoutes(audio)
        } else {
            route(
                if (audio.route == CallAudioState.ROUTE_SPEAKER) CallAudioState.ROUTE_WIRED_OR_EARPIECE
                else CallAudioState.ROUTE_SPEAKER
            )
        }
    }

    /** ไม่ขอ EARPIECE ตรง ๆ · เสียบหูฟังสายอยู่ระบบทิ้งคำสั่งนั้น (ดู MindInCallService.setSpeaker) */
    @Suppress("DEPRECATION")
    private fun route(route: Int) {
        val service = MindInCallService.service ?: return
        // เจ้าของเลือกทางเสียงเองระหว่างที่เธอถือสาย · ไม่ไปเปิดลำโพงทับ (ดู CallAudio.keepSpeaker)
        if (MindInCallService.mindHandling) CallAudio.ownerRouted = route != CallAudioState.ROUTE_SPEAKER
        service.setAudioRoute(route)
    }

    @Suppress("DEPRECATION")
    private fun useBluetooth(device: BluetoothDevice) {
        val service = MindInCallService.service ?: return
        if (MindInCallService.mindHandling) CallAudio.ownerRouted = true
        if (Build.VERSION.SDK_INT >= 28) service.requestBluetoothAudio(device)
        else service.setAudioRoute(CallAudioState.ROUTE_BLUETOOTH)
    }

    private fun openRoutes(audio: CallAudioState) {
        routeList.removeAllViews()
        val mask = audio.supportedRouteMask
        val now = audio.route
        if (has(mask, CallAudioState.ROUTE_WIRED_HEADSET)) {
            routeRow(R.drawable.ic_ph_headset, getString(R.string.call_route_headset), now == CallAudioState.ROUTE_WIRED_HEADSET) {
                route(CallAudioState.ROUTE_WIRED_OR_EARPIECE)
            }
        } else if (has(mask, CallAudioState.ROUTE_EARPIECE)) {
            routeRow(R.drawable.ic_ph_earpiece, getString(R.string.call_route_earpiece), now == CallAudioState.ROUTE_EARPIECE) {
                route(CallAudioState.ROUTE_WIRED_OR_EARPIECE)
            }
        }
        if (has(mask, CallAudioState.ROUTE_SPEAKER)) {
            routeRow(R.drawable.ic_ph_speaker, getString(R.string.call_speaker), now == CallAudioState.ROUTE_SPEAKER) {
                route(CallAudioState.ROUTE_SPEAKER)
            }
        }
        if (has(mask, CallAudioState.ROUTE_BLUETOOTH)) {
            val devices = if (Build.VERSION.SDK_INT >= 28) audio.supportedBluetoothDevices.toList() else emptyList()
            val using = if (Build.VERSION.SDK_INT >= 28) audio.activeBluetoothDevice else null
            if (devices.isEmpty()) {
                routeRow(R.drawable.ic_ph_bluetooth, getString(R.string.call_route_bluetooth), now == CallAudioState.ROUTE_BLUETOOTH) {
                    route(CallAudioState.ROUTE_BLUETOOTH)
                }
            }
            for (d in devices) {
                val on = now == CallAudioState.ROUTE_BLUETOOTH && d == using
                routeRow(R.drawable.ic_ph_bluetooth, btName(d) ?: getString(R.string.call_route_bluetooth), on) {
                    useBluetooth(d)
                }
            }
        }
        showRoutes(true)
    }

    /**
     * ชื่ออุปกรณ์บลูทูธ · Android 12+ ต้องมีสิทธิ์ BLUETOOTH_CONNECT ซึ่งแอปไม่ได้ขอ (ไม่ได้ประกาศใน manifest)
     * · ระบบโยน SecurityException → เรียกว่า "บลูทูธ" เฉย ๆ
     */
    @SuppressLint("MissingPermission")
    private fun btName(device: BluetoothDevice): String? {
        return try {
            device.name?.takeIf { it.isNotBlank() }
        } catch (e: SecurityException) {
            null
        }
    }

    private fun routeRow(icon: Int, label: String, selected: Boolean, onTap: () -> Unit) {
        val radius = dp(this, 18).toFloat()
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(this@InCallActivity, 16), dp(this@InCallActivity, 14), dp(this@InCallActivity, 16), dp(this@InCallActivity, 14))
            background = PhoneUi.ripple(
                PhoneUi.rounded(if (selected) 0x26FFFFFF else Color.TRANSPARENT, radius),
                0x40FFFFFF, PhoneUi.rounded(Color.WHITE, radius)
            )
            isClickable = true
            isSelected = selected
            contentDescription = label
            setOnClickListener {
                showRoutes(false)
                onTap()
            }
        }
        row.addView(PhoneUi.icon(this, icon, Color.WHITE, 22), LinearLayout.LayoutParams(dp(this, 22), dp(this, 22)))
        row.addView(PhoneUi.text(this, 16f, Color.WHITE, bold = selected).apply {
            text = label
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).also { it.leftMargin = dp(this, 14) })
        if (selected) {
            row.addView(PhoneUi.icon(this, R.drawable.ic_ph_check, MINT, 20), LinearLayout.LayoutParams(dp(this, 20), dp(this, 20)))
        }
        routeList.addView(row, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).also { it.topMargin = dp(this, 4) })
    }

    private fun showRoutes(show: Boolean) {
        if ((routeSheet.visibility == View.VISIBLE) == show) return
        if (show) {
            routeSheet.alpha = 0f
            routeSheet.visibility = View.VISIBLE
            routeSheet.animate().alpha(1f).setDuration(160).start()
        } else {
            routeSheet.animate().cancel()
            routeSheet.visibility = View.GONE
        }
        // แผ่นเปิดอยู่ = เจ้าของกำลังมองจอ · ห้ามดับจอด้วยเซนเซอร์ใกล้หู
        MindInCallService.focusCall()?.let { syncProximity(MindInCallService.stateOf(it), MindInCallService.mindHandling) }
    }

    // ── แนบหูแล้วจอดับ ───────────────────────────────────────

    /**
     * จอดับเมื่อเซนเซอร์ใกล้หูถูกบัง — เฉพาะตอนเจ้าของคุยเองทางหูโทรศัพท์
     *
     * ลำโพง/บลูทูธ/หูฟัง = ไม่ได้แนบหู · แป้นกดหรือแผ่นเลือกเสียงเปิด = กำลังมองจอ ·
     * 🔴 เธอถือสาย = **ห้ามดับ** · จอดับ = ระบบส่งความเงียบให้ไมค์ของเธอ (ดู [CallScreen])
     */
    private fun syncProximity(state: Int, mindOn: Boolean) {
        val route = MindInCallService.service?.callAudioState?.route
        val want = resumed && !mindOn && !keypadOpen && routeSheet.visibility != View.VISIBLE &&
            route == CallAudioState.ROUTE_EARPIECE &&
            (state == Call.STATE_ACTIVE || state == Call.STATE_DIALING || state == Call.STATE_CONNECTING)
        if (want) acquireProximity() else releaseProximity()
    }

    private fun acquireProximity() {
        if (proximity?.isHeld == true) return
        try {
            val pm = getSystemService(PowerManager::class.java) ?: return
            if (!pm.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) return
            val lock = proximity ?: pm.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "GigGok:InCallProximity")
                .also {
                    it.setReferenceCounted(false)
                    proximity = it
                }
            // มีเพดานเวลา · ถ้าทางปล่อยทุกทางพลาด อย่างน้อยไม่ค้างทั้งวัน
            lock.acquire(PROXIMITY_MAX_MS)
        } catch (e: RuntimeException) {
            // ไม่มีเซนเซอร์/ไม่มีสิทธิ์ WAKE_LOCK · จอไม่ดับเอง ไม่ใช่เรื่องที่ต้องพัง
        }
    }

    /** ปล่อยแบบรอหน้าออกจากเซนเซอร์ก่อน · ไม่งั้นจอสว่างวาบใส่แก้มตอนสายเพิ่งจบ */
    private fun releaseProximity() {
        val lock = proximity ?: return
        try {
            if (lock.isHeld) lock.release(PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY)
        } catch (e: RuntimeException) {
            // ปล่อยไปแล้ว
        }
    }

    // ── ให้เธอรับเอง ────────────────────────────────────────

    /**
     * ตั้งเวลาให้เธอรับเองถ้าเจ้าของไม่คว้าเครื่องทัน
     *
     * 🔴 ตั้งได้ครั้งเดียวต่อสาย ([armedFor]) · [render] ถูกเรียกทุกครั้งที่สถานะขยับ
     * ถ้าไม่กันไว้ นาฬิกาจะถูกตั้งใหม่ทุกรอบแล้วเลื่อนออกไปเรื่อย ๆ
     * จนไม่มีวันถึงเวลา — เงียบสนิท ดูเหมือนสวิตช์ในหน้าตั้งค่าไม่มีผล
     */
    private fun armAutoAnswer(call: Call) {
        if (armedFor === call) return
        // ตัดสินครั้งเดียวต่อสาย ทั้งรับและไม่รับ · ไม่งั้นทุก render จดเหตุผลซ้ำ
        armedFor = call

        if (!MindPrefs.autoAnswer(this)) return skip("off", R.string.call_auto_off)
        if (MindInCallService.service == null) return skip("no_service", R.string.call_auto_no_mind)

        // เฉพาะเบอร์ในสมุดโทรศัพท์ — **เมื่อเจ้าของเลือกไว้เท่านั้น** (ค่าตั้งต้นรับทุกสาย)
        //
        // เดิมบังคับเสมอ เพราะผู้ช่วยในสายเคยรู้ตารางงานของเจ้าของ · ตอนนี้สายไม่มี
        // ข้อมูลส่วนตัวเลย (MindState.callPrompt) · เบอร์ซ่อน/เบอร์แปลกคุยกับเธอได้
        // แค่ฝากเรื่อง ซึ่งคือสิ่งที่เลขาทำ
        if (MindPrefs.contactsOnly(this)) {
            val number = call.details?.handle?.schemeSpecificPart
            if (CallBridge(this).nameFor(number) == null) {
                return skip("not_contact", R.string.call_auto_not_contact)
            }
        }

        // สายซ้อน = เจ้าของกำลังคุยอีกสายอยู่ · รับแทนตอนนี้คือพักสายที่เขาคุยอยู่
        // ทิ้งโดยที่เขาไม่ได้กดอะไรเลย · ปล่อยให้เขาตัดสินใจเอง
        if (MindInCallService.hasOtherCall()) return skip("other_call", R.string.call_auto_other_call)

        // 🔴 เครื่องที่ตั้งเสียงตรงไว้ แปลว่าทางลำโพงใช้ไม่ได้ (AEC ลบเสียงเธอทิ้ง) · ตัวช่วยหายไป
        // (รีบูต/อัปเดตแอป) แล้วยังรับ = คู่สายได้ยินความเงียบ · ปล่อยกริ่งดังให้เจ้าของรับเองดีกว่า
        directDown = null
        DirectAudioSetup.helperDown(this) { directDown = it }

        val delay = MindPrefs.ringSeconds(this) * 1000L
        val task = object : Runnable {
            override fun run() {
                autoAnswer = null
                // กริ่งหยุด หรือสายที่ดังเปลี่ยนเป็นอีกสายแล้ว = ไม่รับแทน (mindAnswer รับ "สายปัจจุบัน")
                if (MindInCallService.stateOf(call) != Call.STATE_RINGING || MindInCallService.current !== call) return
                // ถามตัวช่วยยังไม่เสร็จ (ตั้งให้รับทันที) · ไม่ตอบเกินสามวิ = ไม่รู้ ไม่ขวางเธอ
                val waited = SystemClock.uptimeMillis() - autoAt
                if (directDown == null && waited < 3000) {
                    autoAnswer = this
                    ui.postDelayed(this, 100)
                    return
                }
                if (directDown == true) {
                    skip("direct_offline", R.string.call_auto_no_direct)
                    return
                }
                // 🔴 ไม่มีเน็ตแต่สมองต้องใช้เน็ต = รับไปแล้วทักได้คำเดียวแล้วเงียบ · ให้กริ่งดังให้เจ้าของรับเอง
                // · เน็ตมือถือที่ใช้ได้ผ่านด่านนี้เหมือน Wi-Fi (ดูแค่ว่าออกเน็ตได้จริง ไม่ดูชนิด)
                if (MindPrefs.brainNeedsInternet(this@InCallActivity) && !online()) {
                    skip("no_internet", R.string.call_auto_no_net)
                    return
                }
                // 🔴 รับแล้วต้องมีคนคุยจริง · บทสนทนาอยู่ฝั่ง Dart ทั้งหมด · ปลุกไม่ขึ้น
                // แล้วยังรับ = ลำโพงเปิด ปลายสายได้ยินเสียงในห้องเจ้าของโดยไม่มีใครรู้
                if (!mindAwake()) {
                    skip("no_mind", R.string.call_auto_no_mind)
                    return
                }
                MindPrefs.noteAutoAnswer(this@InCallActivity, "answered")
                letMindAnswer()
            }
        }
        autoAnswer = task
        autoAt = SystemClock.uptimeMillis() + delay
        ui.postDelayed(task, delay)
        ui.post(tick)

        // ปลุกตัวเธอ**ตอนนี้** ไม่ใช่ตอนรับ · Dart เปิดตัว (ค่าตั้ง สมอง) ระหว่างกริ่งดัง
        // · ทำหลังจอสายวาดเสร็จ การสร้าง engine กินเธรดหลักชั่วครู่
        ui.post { mindAwake() }
    }

    /// มีเครือข่ายที่ระบบตรวจแล้วว่าออกอินเทอร์เน็ตได้จริง (Wi-Fi หรือเน็ตมือถือ) · ถามไม่ได้ = ไม่ขวางเธอ
    private fun online(): Boolean {
        val cm = getSystemService(android.net.ConnectivityManager::class.java) ?: return true
        return try {
            val caps = cm.getNetworkCapabilities(cm.activeNetwork ?: return false) ?: return false
            caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        } catch (e: SecurityException) {
            true
        }
    }

    /// ตัวเธอ (Dart) ตื่นอยู่ หรือปลุกขึ้นได้ตอนนี้ไหม · ดู [MindEngine]
    private fun mindAwake(): Boolean =
        MainActivity.dartAlive || MindEngine.running || MindEngine.wake(this)

    /** ไม่รับเอง — บอกบนจอ และจดไว้ให้รายงาน/หน้าตั้งค่าเห็น */
    private fun skip(reason: String, text: Int) {
        cancelAutoAnswer()
        hint(getString(text))
        MindPrefs.noteAutoAnswer(this, reason)
    }

    private fun cancelAutoAnswer() {
        autoAnswer?.let { ui.removeCallbacks(it) }
        autoAnswer = null
        ui.removeCallbacks(tick)
    }

    /**
     * 🔴 กันกดซ้ำ · ปุ่มนี้สลับความหมายทันทีที่กด (ให้มายด์รับ → แทรกสาย) แต่สายยังดังอยู่อีกครู่
     * กดสองทีเร็ว ๆ = ทีที่สองดึงสายคืนจากเธอทันทีที่เพิ่งให้รับ
     */
    private fun toggleMind() {
        if (!once()) return
        if (MindInCallService.mindHandling) {
            MindInCallService.handOver(this)
            notice = null
            render()
        } else {
            letMindAnswer()
        }
    }

    private fun letMindAnswer() {
        cancelAutoAnswer()
        hint(null)
        // เจ้าของกด "ให้มายด์รับ" เองตอนแอปปิด = ปลุกเธอด้วย ไม่งั้นรับแล้วเงียบ
        mindAwake()
        val ok = MindInCallService.mindAnswer(this)
        // รับไปแล้วแต่เปิดลำโพงไม่ได้ = ปลายสายจะไม่ได้ยินเธอเลย
        // ต้องบอก ไม่ใช่ปล่อยให้เห็นว่า "กำลังคุย" แล้วสงสัยเองว่าทำไมเงียบ
        // · เก็บไว้ใน [notice] เพราะ render ข้างล่างเขียนสถานะใหม่ทับทุกครั้ง
        notice = if (ok) null else R.string.call_mind_mute_warn
        render()
    }

    /**
     * ย้ายไปจอ Flutter ที่มีตัวเธอยกโทรศัพท์จริง ๆ
     *
     * ไม่ปิดจอนี้ทิ้ง (ดูหัวคลาส) · ตอนจอล็อก MainActivity ขอขึ้นทับจอล็อก
     * **เฉพาะระหว่างสายที่เธอถือ** แล้วถอนตัวเมื่อสายจบ (เจ้าของปิดได้ในหน้าตั้งค่า)
     * · ระหว่างสายแอปซ่อนทุกทางไปหน้าอื่น เหลือแค่จอสายของเธอ
     */
    private fun handToFlutter() {
        if (handedOver) return
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val locked = keyguard?.isKeyguardLocked == true
        // จอล็อก + เจ้าของไม่ได้เลือกให้ขึ้นจอเธอ = อยู่จอนี้ (ขึ้นทับจอล็อกได้อยู่แล้ว)
        if (locked && !MindPrefs.showOnCall(this)) return
        handedOver = true

        try {
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    // 🔴 ขอขึ้นทับจอล็อกเฉพาะสายนี้ · วางสายแล้ว MainActivity ถอนตัวเอง
                    // กลับไปหลังจอล็อกทันที (ดู MainActivity.leaveLockScreen)
                    .putExtra(MainActivity.EXTRA_OVER_LOCK, locked)
            )
        } catch (e: Exception) {
            // เปิดไม่ได้ = อยู่จอนี้ต่อ ซึ่งวางสายได้อยู่แล้ว
            handedOver = false
        }
    }

    /** เจ้าของรับเอง · ยกเลิกนาฬิกาของเธอก่อน ไม่งั้นนาฬิกาที่ถึงเวลาพอดีรับซ้อนแล้วเปิดลำโพง */
    private fun pickUp() {
        if (autoAnswer != null) MindPrefs.noteAutoAnswer(this, "stopped_ringing")
        cancelAutoAnswer()
        hint(null)
        val call = MindInCallService.focusCall() ?: return
        if (MindInCallService.stateOf(call) == Call.STATE_RINGING) call.answer(VideoProfile.STATE_AUDIO_ONLY)
    }

    /**
     * ปฏิเสธสายที่ดัง หรือวางสายที่คุยอยู่ · สายซ้อน: วางเฉพาะสายที่โชว์อยู่ สายที่พักไว้ยังอยู่
     *
     * 🔴 แตะซ้ำเร็ว ๆ ต้องไม่ไปโดนอีกสาย · สายที่สั่งวางกลายเป็น "กำลังวาง" แทบทันที แล้วสายที่พักไว้
     * ขึ้นมาเป็นสายหลักก่อนจอวาดใหม่ · แตะที่สองภายในวินาทีครึ่งทำได้กับสายเดิมเท่านั้น
     */
    private fun hangUp() {
        cancelAutoAnswer()
        val call = MindInCallService.focusCall() ?: return
        val now = SystemClock.uptimeMillis()
        if (call !== hungUp && now - hungUpAt < 1500) return
        hungUp = call
        hungUpAt = now
        if (MindInCallService.stateOf(call) == Call.STATE_RINGING) call.reject(false, null) else call.disconnect()
    }

    private var hungUp: Call? = null
    private var hungUpAt = 0L

    /** ย้อนกลับ · คืน false = ไม่มีอะไรให้ทำ (ไม่มีสายแล้ว) ผู้เรียกปิดจอเอง */
    private fun goBack(): Boolean {
        when {
            routeSheet.visibility == View.VISIBLE -> showRoutes(false)
            keypadOpen -> setKeypad(false)
            MindInCallService.focusCall() != null -> moveTaskToBack(true)
            else -> return false
        }
        return true
    }

    companion object {
        /** เจ้าของรับ/วางจากแจ้งเตือน · หยุดนาฬิกาให้มายด์รับของจอที่เปิดอยู่ (ถ้ามี) ก่อนสั่งสาย */
        fun cancelAuto() {
            val screen = open ?: return
            if (screen.autoAnswer != null) MindPrefs.noteAutoAnswer(screen, "stopped_ringing")
            screen.cancelAutoAnswer()
        }

        private const val HINT = 0xFFFFB8D9.toInt()
        private const val MINT = 0xFF7FEDD6.toInt()
        private const val PROXIMITY_MAX_MS = 4 * 60 * 60 * 1000L

        /// อ้างถึงจอที่เปิดอยู่ เพื่อปิดได้ตรง ๆ ตอนสายจบ
        ///
        /// ปิดด้วยการ startActivity ซ้ำแล้วให้มันปิดตัวเองก็ทำได้ แต่แปลว่า
        /// จอกะพริบขึ้นมาอีกครั้งก่อนหายไป ซึ่งเห็นได้ด้วยตา
        private var open: InCallActivity? = null

        fun show(context: Context, call: Call) {
            context.startActivity(
                Intent(context, InCallActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }

        fun dismiss(context: Context) {
            open?.finishAndRemoveTask()
        }
    }
}
