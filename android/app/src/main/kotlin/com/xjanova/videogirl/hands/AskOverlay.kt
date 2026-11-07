package com.xjanova.videogirl.hands

import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.app.NotificationManagerCompat
import com.xjanova.videogirl.R

/**
 * กล่อง "ทำเลย / ไม่ต้อง" ที่ลอยเหนือทุกแอป ตอนมายด์ถามก่อนทำขั้นที่ย้อนกลับไม่ได้
 *
 * เจ้าของ (2026-11-07): "ในการที่เธอถามว่าจะให้ทำอะไรแล้วยืนยัน ควรเป็น ป๊อบอัพเด้งเหนือทุกโปรแกรม
 * เพื่อจะได้สั่งงานได้ตรง เช่นทำเลย หรือไม่ทำ" · ของเดิมถามแค่แจ้งเตือน (ยุบอยู่ในแถบ มองไม่เห็นตอนเธอ
 * ทำงานในแอปอื่น) กับกล่องในแอป (ไม่ขึ้นเพราะแอปไม่ได้อยู่บนจอ) · ตอบด้วยเสียงก็ได้ยินผิดได้
 *
 * วาดเป็นหน้าต่างของบริการมือ ([MindHands] · `TYPE_ACCESSIBILITY_OVERLAY`) จึง**ไม่ต้องขอสิทธิ์
 * แสดงทับแอปอื่นเพิ่ม** · ตอบทางเดียวกับปุ่มในแจ้งเตือน ([HandsControl.answer]) ทางไหนมาก่อนใช้ทางนั้น
 *
 * ## 🔒 ด่าน
 * - จอล็อก = ไม่ขึ้น · ล็อกระหว่างขึ้นอยู่ = ซ่อน แล้วขึ้นใหม่หลังปลดล็อก (คนหยิบเครื่องที่ล็อกอยู่ต้องไม่เห็นงาน
 *   และกด "ทำเลย" แทนเจ้าของไม่ได้ · แจ้งเตือนบนจอล็อกมีแค่หัวเรื่องกลาง ๆ อยู่แล้ว)
 * - ปุ่มกดได้หลังขึ้นมาแล้ว [ARM_MS] · นิ้วที่กำลังจะแตะแอปข้างล่างต้องไม่ตกที่ "ทำเลย" พอดี
 * - ไม่รับแตะเมื่อมีหน้าต่างอื่นบังอยู่ (filterTouchesWhenObscured) · กันแอปอื่นวางของหลอกทับ
 * - ระหว่างกล่องขึ้น นิ้วจำลองของเธอแตะอะไรไม่ได้ ([MindHands] ถาม [showing]) · เธออนุมัติตัวเองไม่ได้
 */
object AskOverlay {

    private const val ARM_MS = 700L
    private const val ASK_NOTIFICATION = 7062

    private val main = Handler(Looper.getMainLooper())

    /** [onAnswer] null = คำถามของงานมือ (ตอบผ่าน [HandsControl] เหมือนปุ่มในแจ้งเตือน) */
    private data class Ask(
        val id: Int,
        val title: String,
        val body: String,
        val allow: Int,
        val deny: Int,
        val onAnswer: ((Context, Boolean) -> Unit)?,
    )

    @Volatile private var pending: Ask? = null
    private var view: View? = null
    private var host: WindowManager? = null
    private var screen: BroadcastReceiver? = null
    private var screenOwner: Context? = null

    /** มีกล่องถามค้างอยู่ (ขึ้นจออยู่ หรือซ่อนไว้รอปลดล็อก) · นิ้วจำลองต้องไม่แตะอะไรระหว่างนี้ */
    val showing: Boolean get() = pending != null

    /** ขึ้นกล่อง · บริการมือไม่ได้เปิด = ไม่ขึ้น (แจ้งเตือนยังถามอยู่) · คืนว่าวาดได้ไหม (บอกได้แค่ว่าบริการมืออยู่) */
    fun show(
        id: Int,
        title: String,
        body: String,
        allow: Int = R.string.hands_allow,
        deny: Int = R.string.hands_deny,
        onAnswer: ((Context, Boolean) -> Unit)? = null,
    ): Boolean {
        if (MindHands.instance == null) return false
        main.post {
            val service = MindHands.instance ?: return@post
            hideNow()
            pending = Ask(id, title, body, allow, deny, onAnswer)
            watchScreen(service)
            attach(service)
        }
        return true
    }

    /** ถามจบแล้ว (ตอบทางไหนก็ได้ / หมดเวลา / งานหยุด) · [id] null = ปิดทุกกล่อง */
    fun hide(id: Int? = null) {
        main.post {
            if (id == null || pending?.id == id) hideNow()
        }
    }

    private fun hideNow() {
        pending = null
        detach()
        unwatchScreen()
    }

    private fun locked(context: Context): Boolean =
        context.getSystemService(KeyguardManager::class.java)?.isKeyguardLocked ?: true

    private fun attach(service: MindHands) {
        val ask = pending ?: return
        if (view != null || locked(service)) return
        val wm = service.getSystemService(WindowManager::class.java) ?: return
        val v = build(service, ask)
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            // ไม่แย่งคีย์บอร์ด · แตะนอกกล่อง = ไปถึงแอปข้างล่างตามปกติ
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM
            y = dp(service, 24)
        }
        try {
            wm.addView(v, lp)
            view = v
            host = wm
        } catch (_: Exception) {
            // ระบบไม่ยอมให้วาด · แจ้งเตือนยังถามอยู่
        }
    }

    private fun detach() {
        val v = view ?: return
        view = null
        try { host?.removeView(v) } catch (_: Exception) {}
        host = null
    }

    private fun watchScreen(context: Context) {
        if (screen != null) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                when (intent.action) {
                    Intent.ACTION_SCREEN_OFF -> detach()
                    Intent.ACTION_USER_PRESENT -> MindHands.instance?.let { attach(it) }
                }
            }
        }
        try {
            val f = IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_USER_PRESENT)
            }
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(r, f, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(r, f)
            }
            screen = r
            screenOwner = context
        } catch (_: Exception) {}
    }

    private fun unwatchScreen() {
        val r = screen ?: return
        screen = null
        try { screenOwner?.unregisterReceiver(r) } catch (_: Exception) {}
        screenOwner = null
    }

    private fun answer(context: Context, ask: Ask, allow: Boolean) {
        // กดบนจอล็อก (ล็อกระหว่างที่นิ้วกำลังลง) = ไม่นับ
        if (locked(context)) return
        if (pending?.id != ask.id) return
        hideNow()
        val custom = ask.onAnswer
        if (custom != null) {
            custom(context.applicationContext, allow)
            return
        }
        HandsControl.answer(ask.id, allow)
        NotificationManagerCompat.from(context).cancel(ASK_NOTIFICATION)
    }

    private fun build(context: Context, ask: Ask): View {
        val pad = dp(context, 20)
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, dp(context, 16))
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadius = dp(context, 24).toFloat()
                setStroke(dp(context, 1), Color.parseColor("#22000000"))
            }
            elevation = dp(context, 12).toFloat()
        }
        val head = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        head.addView(ImageView(context).apply {
            setImageResource(R.drawable.ic_hands)
            setColorFilter(Color.parseColor("#E91E63"))
        }, LinearLayout.LayoutParams(dp(context, 24), dp(context, 24)).apply { marginEnd = dp(context, 10) })
        head.addView(TextView(context).apply {
            text = ask.title
            setTextColor(Color.parseColor("#1F1F1F"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            typeface = Typeface.DEFAULT_BOLD
        })
        card.addView(head)

        val body = TextView(context).apply {
            text = ask.body
            setTextColor(Color.parseColor("#3C3C3C"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setLineSpacing(0f, 1.15f)
        }
        // ข้อความยาวไม่ดันปุ่มตกจอ
        val scroll = ScrollView(context).apply { addView(body) }
        card.addView(scroll, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(context, 10) })
        body.post {
            if (body.height > dp(context, 220)) {
                scroll.layoutParams = scroll.layoutParams.apply { height = dp(context, 220) }
            }
        }

        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }
        fun button(label: Int, filled: Boolean, allow: Boolean) = Button(context).apply {
            text = context.getString(label)
            isAllCaps = false
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(if (filled) Color.WHITE else Color.parseColor("#E91E63"))
            background = GradientDrawable().apply {
                cornerRadius = dp(context, 24).toFloat()
                if (filled) setColor(Color.parseColor("#E91E63"))
                else {
                    setColor(Color.WHITE)
                    setStroke(dp(context, 2), Color.parseColor("#E91E63"))
                }
            }
            setPadding(dp(context, 22), 0, dp(context, 22), 0)
            minHeight = dp(context, 48)
            minimumHeight = dp(context, 48)
            filterTouchesWhenObscured = true
            isEnabled = false
            alpha = 0.5f
            setOnClickListener { answer(context, ask, allow) }
        }
        val deny = button(ask.deny, filled = false, allow = false)
        val allow = button(ask.allow, filled = true, allow = true)
        row.addView(deny, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, dp(context, 48),
        ).apply { marginEnd = dp(context, 12) })
        row.addView(allow, LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, dp(context, 48)))
        card.addView(row, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(context, 16) })

        main.postDelayed({
            for (b in listOf(deny, allow)) {
                b.isEnabled = true
                b.alpha = 1f
            }
        }, ARM_MS)

        return LinearLayout(context).apply {
            setPadding(dp(context, 12), 0, dp(context, 12), 0)
            addView(card, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
            ))
        }
    }

    private fun dp(context: Context, v: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), context.resources.displayMetrics).toInt()
}
