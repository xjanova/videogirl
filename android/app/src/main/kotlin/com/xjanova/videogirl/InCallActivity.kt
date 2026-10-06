package com.xjanova.videogirl

import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telecom.Call
import android.telecom.VideoProfile
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File

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
 * ไม่มี XML ไม่มี engine ไม่มีอะไรต้องรอ
 *
 * รูปหน้าเธอใช้ไฟล์ที่แคชไว้แล้ว (mind_face.png) ถ้ามี · ไม่มีก็ไม่เป็นไร
 * จอต้องขึ้นทันทีเสมอ ไม่ว่ามีรูปหรือไม่
 *
 * ## 🔴 จอนี้ไม่ตายเมื่อมายด์รับสาย
 *
 * พอเธอรับ เราเปิดจอ Flutter (ที่มีตัวเธอยกโทรศัพท์จริง ๆ) ทับขึ้นไป
 * แต่**ไม่ปิดจอนี้ทิ้ง** เพราะจอนี้คือทางหนีเมื่อ Flutter ไม่ขึ้นหรือถูกปัดทิ้ง
 * ถ้าปิดแล้ว Flutter ไม่ขึ้น เจ้าของจะเหลือสายที่วางไม่ได้อยู่ในมือ
 *
 * ตอนจอล็อก ย้ายไป Flutter ก็ต่อเมื่อเจ้าของเปิด "ขึ้นจอเธอตอนรับสาย" ไว้
 * (ค่าตั้งต้น) · MainActivity ขึ้นทับจอล็อกเฉพาะระหว่างสายนั้น ([handToFlutter])
 */
class InCallActivity : Activity() {

    private lateinit var who: TextView

    /** สายนี้เข้าทางซิมไหน · ซ่อนเมื่อเครื่องมีซิมเดียว (บอกไปก็ไม่มีประโยชน์) */
    private lateinit var sim: TextView
    private lateinit var status: TextView

    /** เธอจะรับเองไหม — นับถอยหลัง หรือเหตุผลที่ไม่รับ · เดิมเงียบ เจ้าของเดาไม่ออก */
    private lateinit var autoHint: TextView
    private lateinit var answer: Button
    private lateinit var decline: Button
    private lateinit var speaker: Button
    private lateinit var mind: Button

    private val ui = Handler(Looper.getMainLooper())

    /// นาฬิกาปล่อยกริ่งก่อนเธอรับ · ต้องยกเลิกได้ทุกทางที่สายจบ
    private var autoAnswer: Runnable? = null
    private var autoArmed = false

    /// เวลาที่เธอจะรับ (uptime) · ใช้นับถอยหลังบนจอ
    private var autoAt = 0L
    private val tick = object : Runnable {
        override fun run() {
            if (autoAnswer == null) return
            val left = ((autoAt - android.os.SystemClock.uptimeMillis() + 999) / 1000).toInt()
            autoHint.text = if (left > 0) getString(R.string.call_auto_in, left)
            else getString(R.string.call_auto_now)
            ui.postDelayed(this, 500)
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
        setContentView(buildUi())

        open = this
        registerReceiver(
            onChanged,
            IntentFilter(MindInCallService.ACTION_CALL_CHANGED),
            if (Build.VERSION.SDK_INT >= 33) Context.RECEIVER_NOT_EXPORTED else 0
        )
        render()
    }

    override fun onDestroy() {
        if (open === this) open = null
        cancelAutoAnswer()
        try {
            unregisterReceiver(onChanged)
        } catch (e: IllegalArgumentException) {
            // ไม่ได้ลงทะเบียนไว้ — ไม่ใช่เรื่องที่ต้องพัง
        }
        super.onDestroy()
    }

    /**
     * ต้องขึ้นทับจอล็อกและปลุกจอ
     *
     * ไม่ทำ = สายเข้าตอนจอดับแล้วไม่มีอะไรขึ้นเลย ซึ่งกับแอปโทรศัพท์หลัก
     * แปลว่ารับสายไม่ได้
     */
    private fun showOverLockScreen() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            (getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager)
                ?.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    private fun dp(v: Int) = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics
    ).toInt()

    private fun buildUi(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.parseColor("#F6F2F7"))
            setPadding(dp(28), dp(64), dp(28), dp(48))
        }

        // หน้าเธอถ้ามีไฟล์แคชไว้ · ไม่มีก็ข้ามไป จอต้องขึ้นทันทีเสมอ
        val face = File(filesDir, "mind_face.png")
        if (face.exists()) {
            BitmapFactory.decodeFile(face.path)?.let { bmp ->
                root.addView(ImageView(this).apply {
                    setImageBitmap(bmp)
                    layoutParams = LinearLayout.LayoutParams(dp(132), dp(132))
                        .also { it.bottomMargin = dp(24) }
                })
            }
        }

        who = TextView(this).apply {
            setTextColor(Color.parseColor("#231F3A"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 26f)
            gravity = Gravity.CENTER
        }
        sim = TextView(this).apply {
            setTextColor(Color.parseColor("#5A4DE0"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            gravity = Gravity.CENTER
            setPadding(0, dp(6), 0, 0)
            visibility = View.GONE
        }
        status = TextView(this).apply {
            setTextColor(Color.parseColor("#7A7490"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, dp(6))
        }
        autoHint = TextView(this).apply {
            setTextColor(Color.parseColor("#5A4DE0"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, dp(34))
        }
        root.addView(who, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        root.addView(sim, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        root.addView(status, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        root.addView(autoHint, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        // ปุ่มของมายด์ — "ให้มายด์รับ" ตอนสายดัง เปลี่ยนเป็น "แทรกสาย" ตอนเธอคุยอยู่
        // ปุ่มเดียวสองความหมายเพราะเป็นสวิตช์เดียวกัน: ใครถือสายนี้อยู่
        mind = pill(getString(R.string.call_mind_answer), "#5A4DE0") { toggleMind() }
        root.addView(mind, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            .also { it.bottomMargin = dp(14) })

        speaker = pill("🔊", "#7A7490") { toggleSpeaker() }
        root.addView(speaker, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
            .also { it.bottomMargin = dp(28) })

        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        decline = pill(getString(R.string.call_decline), "#D93A5B") { hangUp() }
        answer = pill(getString(R.string.call_answer), "#00A05A") { pickUp() }
        row.addView(decline, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
            .also { it.rightMargin = dp(10) })
        row.addView(answer, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
        root.addView(row, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        return root
    }

    private fun pill(label: String, colour: String, onTap: () -> Unit) =
        Button(this).apply {
            text = label
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            setPadding(dp(20), dp(20), dp(20), dp(20))
            background = GradientDrawable().apply {
                cornerRadius = dp(28).toFloat()
                setColor(Color.parseColor(colour))
            }
            stateListAnimator = null
            setOnClickListener { onTap() }
        }

    private fun render() {
        val call = MindInCallService.current
        if (call == null) {
            cancelAutoAnswer()
            finishAndRemoveTask()
            return
        }

        val number = call.details.handle?.schemeSpecificPart
        val name = CallBridge(this).nameFor(number)
        who.text = name ?: number ?: getString(R.string.call_unknown)

        // ซิมของสาย · อ่านทุกรอบ render ได้ (ถูก) แต่ล้มต้องไม่ทำจอนี้พัง
        val s = SimInfo.of(this, call)
        val simText = when {
            s == null || s.count < 2 -> null
            s.slot != null && s.label != null -> getString(R.string.call_sim_label, s.slot, s.label)
            s.slot != null -> getString(R.string.call_sim, s.slot)
            else -> s.label
        }
        sim.text = simText ?: ""
        sim.visibility = if (simText == null) View.GONE else View.VISIBLE

        val state = MindInCallService.stateOf(call)
        val ringing = state == Call.STATE_RINGING
        val mindOn = MindInCallService.mindHandling

        status.setText(
            when {
                mindOn && state == Call.STATE_ACTIVE -> R.string.call_mind_talking
                ringing -> R.string.call_incoming
                state == Call.STATE_DIALING || state == Call.STATE_CONNECTING ->
                    R.string.call_dialing
                state == Call.STATE_ACTIVE -> R.string.call_active
                state == Call.STATE_HOLDING -> R.string.call_holding
                state == Call.STATE_DISCONNECTED -> R.string.call_ended
                else -> R.string.call_connecting
            }
        )

        // ปุ่มรับมีเฉพาะตอนสายกำลังดัง · ปุ่มแดงเปลี่ยนความหมายจาก "ปฏิเสธ"
        // เป็น "วางสาย" ตามสถานะ ซึ่งเป็นสิ่งเดียวกันในทางเทคนิคแต่คนละคำ
        answer.visibility = if (ringing) View.VISIBLE else View.GONE
        decline.text = getString(
            if (ringing) R.string.call_decline else R.string.call_hangup
        )
        speaker.visibility = if (ringing || mindOn) View.GONE else View.VISIBLE

        // ปุ่มของเธอมีได้ก็ต่อเมื่อระบบผูกกับบริการเราอยู่จริง — ไม่งั้นกดแล้ว
        // เปิดลำโพงไม่ได้ ซึ่งแปลว่าเธอรับแล้วปลายสายเงียบสนิท
        val canMind = MindInCallService.service != null &&
            (ringing || state == Call.STATE_ACTIVE)
        mind.visibility = if (canMind) View.VISIBLE else View.GONE
        mind.text = getString(
            if (mindOn) R.string.call_mind_barge else R.string.call_mind_answer
        )

        if (ringing) armAutoAnswer() else {
            // นับถอยหลังอยู่แล้วกริ่งหยุด = เจ้าของคว้าเครื่องทัน หรือคนโทรวางก่อน
            if (autoAnswer != null) MindPrefs.noteAutoAnswer(this, "stopped_ringing")
            cancelAutoAnswer()
            autoHint.text = ""
        }
        if (mindOn && state == Call.STATE_ACTIVE) handToFlutter()
    }

    // ── ให้เธอรับเอง ────────────────────────────────────────

    /**
     * ตั้งเวลาให้เธอรับเองถ้าเจ้าของไม่คว้าเครื่องทัน
     *
     * 🔴 ตั้งได้ครั้งเดียวต่อสาย · [render] ถูกเรียกทุกครั้งที่สถานะขยับ
     * ถ้าไม่กันไว้ นาฬิกาจะถูกตั้งใหม่ทุกรอบแล้วเลื่อนออกไปเรื่อย ๆ
     * จนไม่มีวันถึงเวลา — เงียบสนิท ดูเหมือนสวิตช์ในหน้าตั้งค่าไม่มีผล
     */
    private fun armAutoAnswer() {
        if (autoArmed) return
        // ตัดสินครั้งเดียวต่อสาย ทั้งรับและไม่รับ · ไม่งั้นทุก render จดเหตุผลซ้ำ
        autoArmed = true

        if (!MindPrefs.autoAnswer(this)) return skip("off", R.string.call_auto_off)
        if (MindInCallService.service == null) return skip("no_service", R.string.call_auto_no_mind)

        // เฉพาะเบอร์ในสมุดโทรศัพท์ — **เมื่อเจ้าของเลือกไว้เท่านั้น** (ค่าตั้งต้นรับทุกสาย)
        //
        // เดิมบังคับเสมอ เพราะผู้ช่วยในสายเคยรู้ตารางงานของเจ้าของ · ตอนนี้สายไม่มี
        // ข้อมูลส่วนตัวเลย (MindState.callPrompt) · เบอร์ซ่อน/เบอร์แปลกคุยกับเธอได้
        // แค่ฝากเรื่อง ซึ่งคือสิ่งที่เลขาทำ
        if (MindPrefs.contactsOnly(this)) {
            val number = MindInCallService.current?.details?.handle?.schemeSpecificPart
            if (CallBridge(this).nameFor(number) == null) {
                return skip("not_contact", R.string.call_auto_not_contact)
            }
        }

        // สายซ้อน = เจ้าของกำลังคุยอีกสายอยู่ · รับแทนตอนนี้คือพักสายที่เขาคุยอยู่
        // ทิ้งโดยที่เขาไม่ได้กดอะไรเลย · ปล่อยให้เขาตัดสินใจเอง
        if (MindInCallService.hasOtherCall()) return skip("other_call", R.string.call_auto_other_call)

        val delay = MindPrefs.ringSeconds(this) * 1000L
        val task = Runnable {
            autoAnswer = null
            if (MindInCallService.stateOf(MindInCallService.current) != Call.STATE_RINGING) return@Runnable
            // 🔴 รับแล้วต้องมีคนคุยจริง · บทสนทนาอยู่ฝั่ง Dart ทั้งหมด · ปลุกไม่ขึ้น
            // แล้วยังรับ = ลำโพงเปิด ปลายสายได้ยินเสียงในห้องเจ้าของโดยไม่มีใครรู้
            if (!mindAwake()) {
                skip("no_mind", R.string.call_auto_no_mind)
                return@Runnable
            }
            MindPrefs.noteAutoAnswer(this, "answered")
            letMindAnswer()
        }
        autoAnswer = task
        autoAt = android.os.SystemClock.uptimeMillis() + delay
        ui.postDelayed(task, delay)
        ui.post(tick)

        // ปลุกตัวเธอ**ตอนนี้** ไม่ใช่ตอนรับ · Dart เปิดตัว (ค่าตั้ง สมอง) ระหว่างกริ่งดัง
        // · ทำหลังจอสายวาดเสร็จ การสร้าง engine กินเธรดหลักชั่วครู่
        ui.post { mindAwake() }
    }

    /// ตัวเธอ (Dart) ตื่นอยู่ หรือปลุกขึ้นได้ตอนนี้ไหม · ดู [MindEngine]
    private fun mindAwake(): Boolean =
        MainActivity.dartAlive || MindEngine.running || MindEngine.wake(this)

    /** ไม่รับเอง — บอกบนจอ และจดไว้ให้รายงาน/หน้าตั้งค่าเห็น */
    private fun skip(reason: String, text: Int) {
        cancelAutoAnswer()
        autoHint.setText(text)
        MindPrefs.noteAutoAnswer(this, reason)
    }

    private fun cancelAutoAnswer() {
        autoAnswer?.let { ui.removeCallbacks(it) }
        autoAnswer = null
        ui.removeCallbacks(tick)
    }

    private fun toggleMind() {
        if (MindInCallService.mindHandling) {
            MindInCallService.handOver(this)
            render()
        } else {
            letMindAnswer()
        }
    }

    private fun letMindAnswer() {
        cancelAutoAnswer()
        autoHint.text = ""
        // เจ้าของกด "ให้มายด์รับ" เองตอนแอปปิด = ปลุกเธอด้วย ไม่งั้นรับแล้วเงียบ
        mindAwake()
        val ok = MindInCallService.mindAnswer(this, MindPrefs.callStream(this))
        if (!ok) {
            // รับไปแล้วแต่เปิดลำโพงไม่ได้ = ปลายสายจะไม่ได้ยินเธอเลย
            // ต้องบอก ไม่ใช่ปล่อยให้เห็นว่า "กำลังคุย" แล้วสงสัยเองว่าทำไมเงียบ
            status.setText(R.string.call_mind_mute_warn)
        }
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

    private fun pickUp() {
        MindInCallService.current?.answer(VideoProfile.STATE_AUDIO_ONLY)
    }

    private fun hangUp() {
        cancelAutoAnswer()
        MindInCallService.disconnect()
    }

    private fun toggleSpeaker() {
        MindInCallService.setSpeaker(!MindInCallService.speakerOn())
    }

    companion object {
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
