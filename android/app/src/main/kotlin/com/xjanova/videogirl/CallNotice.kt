package com.xjanova.videogirl

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.telecom.Call
import android.telecom.VideoProfile

/**
 * แจ้งเตือน "กำลังคุยสาย" ค้างไว้ตลอดที่มีสาย — ทางกลับเข้าจอสาย และปุ่มวางสายจากแถบแจ้งเตือน
 *
 * เป็นแอปโทรศัพท์หลักแล้ว ไม่มีแจ้งเตือนนี้ = เจ้าของกดออกจากจอสายแล้ว**ไม่มีทางกลับ**
 * นอกจากเปิดแป้นโทรหาแถบสีเขียว · วางสายก็ทำไม่ได้จนกว่าจะหาจอเจอ
 *
 * 🔴 ไม่ใช้ `CallStyle` · Android 12+ โยน IllegalArgumentException ถ้าแจ้งเตือนแบบนั้นไม่ได้มาจาก
 * foreground service หรือไม่มี full-screen intent · ล้มตรงนี้ = บริการสายพังกลางสาย
 *
 * 🔴 ทุกอย่างในไฟล์นี้ล้มต้องเงียบ · ไม่มีสิทธิ์แจ้งเตือน (POST_NOTIFICATIONS ถูกปฏิเสธ) ก็แค่ไม่มีแจ้งเตือน
 */
object CallNotice {
    private const val CHANNEL = "giggok_calls"
    private const val NOTIFICATION = 7071
    private const val PI_OPEN = 7071
    private const val PI_HANGUP = 7072
    private const val PI_ANSWER = 7073

    const val ACTION_HANGUP = "com.xjanova.videogirl.CALL_NOTICE_HANGUP"
    const val ACTION_ANSWER = "com.xjanova.videogirl.CALL_NOTICE_ANSWER"

    fun update(context: Context) {
        val call = MindInCallService.focusCall() ?: return cancel(context)
        try {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(CHANNEL) == null) {
                // เงียบ ไม่เด้ง · กริ่งเป็นของระบบโทรศัพท์ จอสายขึ้นเองอยู่แล้ว
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL, context.getString(R.string.call_notice_channel), NotificationManager.IMPORTANCE_LOW)
                        .apply { setShowBadge(false) }
                )
            }
            nm.notify(NOTIFICATION, build(context, call))
        } catch (e: RuntimeException) {
            // แจ้งเตือนพังต้องไม่ลากบริการสายพังตาม
        }
    }

    fun cancel(context: Context) {
        try {
            context.getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION)
        } catch (e: RuntimeException) {
            // ไม่มีอะไรให้ลบ
        }
    }

    private fun build(context: Context, call: Call): Notification {
        val state = MindInCallService.stateOf(call)
        val ringing = state == Call.STATE_RINGING
        val number = call.details.handle?.schemeSpecificPart
        val who = nameOf(context, number)
            ?: number?.let { PhoneUi.formatNumber(it, PhoneUi.countryIso(context)) }
            ?: context.getString(R.string.call_unknown)
        val status = context.getString(
            when {
                MindInCallService.mindHandling && state == Call.STATE_ACTIVE -> R.string.call_mind_talking
                ringing -> R.string.call_incoming
                state == Call.STATE_ACTIVE -> R.string.call_active
                state == Call.STATE_HOLDING -> R.string.call_holding
                state == Call.STATE_DISCONNECTED || state == Call.STATE_DISCONNECTING -> R.string.call_ended
                else -> R.string.call_dialing
            }
        )

        val open = PendingIntent.getActivity(
            context, PI_OPEN,
            Intent(context, InCallActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        // จอล็อกเห็นแค่ว่ามีสาย ไม่เห็นชื่อ/เบอร์ของคนในสาย
        val locked = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_ph_call)
            .setContentTitle(status)
            .build()

        val b = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_ph_call)
            .setColor(PhoneUi.VIOLET)
            .setContentTitle(who)
            .setContentText(if (ringing) status else "$status · ${context.getString(R.string.call_notice_return)}")
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_CALL)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(locked)

        // นาฬิกาสายนับเองบนแถบแจ้งเตือน ไม่ต้องให้เราอัปเดตทุกวินาที
        val since = call.details.connectTimeMillis
        if (state == Call.STATE_ACTIVE && since > 0) {
            b.setWhen(since).setShowWhen(true).setUsesChronometer(true)
        } else {
            b.setShowWhen(false)
        }

        val hangup = action(context, PI_HANGUP, ACTION_HANGUP, call)
        if (ringing) {
            b.addAction(Notification.Action.Builder(
                Icon.createWithResource(context, R.drawable.ic_ph_call_end), context.getString(R.string.call_decline), hangup
            ).build())
            b.addAction(Notification.Action.Builder(
                Icon.createWithResource(context, R.drawable.ic_ph_call), context.getString(R.string.call_answer),
                action(context, PI_ANSWER, ACTION_ANSWER, call)
            ).build())
        } else {
            b.addAction(Notification.Action.Builder(
                Icon.createWithResource(context, R.drawable.ic_ph_call_end), context.getString(R.string.call_hangup), hangup
            ).build())
        }
        return b.build()
    }

    /** เบอร์ล่าสุดกับชื่อในสมุดโทรศัพท์ · แจ้งเตือนวาดใหม่ทุกครั้งที่สายขยับ ไม่ต้องค้นซ้ำทุกรอบ */
    private var named: Pair<String?, String?>? = null

    private fun nameOf(context: Context, number: String?): String? {
        named?.let { (n, name) -> if (n == number) return name }
        val name = CallBridge(context).nameFor(number)
        named = number to name
        return name
    }

    /** ส่งตรงถึง [CallNoticeReceiver] ในแอปเราเท่านั้น · receiver ไม่ export แอปอื่นสั่งวางสายไม่ได้ */
    private fun action(context: Context, code: Int, what: String, call: Call) = PendingIntent.getBroadcast(
        context, code,
        Intent(context, CallNoticeReceiver::class.java).setAction(what).putExtra(EXTRA_CALL, idOf(call)),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )

    const val EXTRA_CALL = "call"

    /** ตัวระบุสายในกระบวนการนี้ · Call ไม่ได้ override equals ตัวเดียวกัน = สายเดียวกัน */
    fun idOf(call: Call): Int = System.identityHashCode(call)
}

/**
 * ปุ่มบนแจ้งเตือนสาย · ทำกับสายที่แจ้งเตือนโชว์อยู่**ตอนวาด**เท่านั้น
 *
 * 🔴 สายเปลี่ยนไปแล้ว (วางสายแรกแล้วสายที่พักไว้ขึ้นมาแทน · กดซ้ำเร็ว ๆ) = ไม่ทำอะไร ·
 * ไม่งั้นแตะ "วางสาย" สองทีเท่ากับวางทั้งสายที่คุยและสายที่พักไว้ · รับได้เฉพาะสายที่ยังดังอยู่
 */
class CallNoticeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val call = MindInCallService.focusCall() ?: return CallNotice.cancel(context)
        if (intent.getIntExtra(CallNotice.EXTRA_CALL, 0) != CallNotice.idOf(call)) return CallNotice.update(context)
        val ringing = MindInCallService.stateOf(call) == Call.STATE_RINGING
        // เจ้าของตัดสินเองแล้ว · นาฬิกาให้มายด์รับต้องหยุดก่อน (สายที่เพิ่งรับยังรายงานว่าดังอยู่อีกครู่)
        InCallActivity.cancelAuto()
        when (intent.action) {
            CallNotice.ACTION_HANGUP -> if (ringing) call.reject(false, null) else call.disconnect()
            CallNotice.ACTION_ANSWER -> if (ringing) call.answer(VideoProfile.STATE_AUDIO_ONLY)
        }
    }
}
