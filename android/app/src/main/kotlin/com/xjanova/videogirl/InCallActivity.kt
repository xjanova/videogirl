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
 */
class InCallActivity : Activity() {

    private lateinit var who: TextView
    private lateinit var status: TextView
    private lateinit var answer: Button
    private lateinit var decline: Button
    private lateinit var speaker: Button

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
        status = TextView(this).apply {
            setTextColor(Color.parseColor("#7A7490"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, dp(40))
        }
        root.addView(who, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        root.addView(status, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        speaker = pill("🔊", "#5A4DE0") { toggleSpeaker() }
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
            finishAndRemoveTask()
            return
        }

        val number = call.details.handle?.schemeSpecificPart
        val name = CallBridge(this).nameFor(number)
        who.text = name ?: number ?: getString(R.string.call_unknown)

        val state = if (Build.VERSION.SDK_INT >= 31) call.details.state else {
            @Suppress("DEPRECATION") call.state
        }

        status.setText(
            when (state) {
                Call.STATE_RINGING -> R.string.call_incoming
                Call.STATE_DIALING, Call.STATE_CONNECTING -> R.string.call_dialing
                Call.STATE_ACTIVE -> R.string.call_active
                Call.STATE_HOLDING -> R.string.call_holding
                Call.STATE_DISCONNECTED -> R.string.call_ended
                else -> R.string.call_connecting
            }
        )

        // ปุ่มรับมีเฉพาะตอนสายกำลังดัง · ปุ่มแดงเปลี่ยนความหมายจาก "ปฏิเสธ"
        // เป็น "วางสาย" ตามสถานะ ซึ่งเป็นสิ่งเดียวกันในทางเทคนิคแต่คนละคำ
        val ringing = state == Call.STATE_RINGING
        answer.visibility = if (ringing) View.VISIBLE else View.GONE
        decline.text = getString(
            if (ringing) R.string.call_decline else R.string.call_hangup
        )
        speaker.visibility = if (ringing) View.GONE else View.VISIBLE
    }

    private fun pickUp() {
        MindInCallService.current?.answer(VideoProfile.STATE_AUDIO_ONLY)
    }

    private fun hangUp() {
        val call = MindInCallService.current ?: return
        val state = if (Build.VERSION.SDK_INT >= 31) call.details.state else {
            @Suppress("DEPRECATION") call.state
        }
        if (state == Call.STATE_RINGING) call.reject(false, null) else call.disconnect()
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
