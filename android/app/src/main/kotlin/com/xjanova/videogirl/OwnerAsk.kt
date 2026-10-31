package com.xjanova.videogirl

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput

/**
 * น้องมายถามเจ้าของกลางสายที่เธอโทรออกแทน แล้วรอคำตอบ (เครื่องมือ ask_owner)
 *
 * เจ้าของ: "เธอต้องฉลาด มีการโต้ตอบ รับเรื่องราวได้ คุยงานแทนเราได้จริง" · ปลายสายถามเรื่องที่
 * เจ้าของไม่ได้สั่งไว้ (เวลาอื่นแทน ราคา ตัวเลือก) ของเดิมเธอตอบได้แค่ "จะเช็กแล้วโทรกลับ"
 *
 * ตอบได้จากแถบแจ้งเตือนเลย ไม่ต้องเปิดแอป · คำตอบไม่วิ่งกลับหา Dart เอง (ช่อง giggok/system
 * มี handler ตัวเดียวของ CallWatch) แต่ฝากไว้ให้ [MindInCallService.callInfo] ส่งไปในรอบถามถัดไป
 * ซึ่งจอสายถามทุกวินาทีอยู่แล้ว
 *
 * 🔒 ไม่ลงข้อความคำถาม/คำตอบใน log · เป็นเรื่องงานของเจ้าของกับคนนอก
 */
object OwnerAsk {
    private const val CHANNEL = "call_notes"
    private const val NOTIFICATION = 7051
    const val KEY = "owner_reply"
    const val EXTRA_ID = "giggok.ask_id"

    /** คำตอบล่าสุดที่ยังไม่ส่งให้ Dart · (เลขคำถาม, ข้อความ) */
    @Volatile
    private var reply: Pair<Int, String>? = null

    fun post(
        context: Context,
        id: Int,
        title: String,
        body: String,
        label: String,
        choices: List<String>,
    ): Boolean {
        val nm = context.getSystemService(NotificationManager::class.java) ?: return false
        if (!nm.areNotificationsEnabled()) return false
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, context.getString(R.string.call_note_channel), NotificationManager.IMPORTANCE_HIGH)
            )
        }
        // เลขคำถามเป็น requestCode · คำถามใหม่ได้ PendingIntent ใหม่ คำตอบของคำถามเก่าไม่ทับคำถามใหม่
        val send = PendingIntent.getBroadcast(
            context, id,
            Intent(context, OwnerReplyReceiver::class.java).putExtra(EXTRA_ID, id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
        )
        val quick = choices.map { it.trim() }.filter { it.isNotEmpty() }.take(3)
        val input = RemoteInput.Builder(KEY).setLabel(label)
            .apply { if (quick.isNotEmpty()) setChoices(quick.toTypedArray()) }.build()
        val open = PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(open)
            .setAutoCancel(true)
            .addAction(NotificationCompat.Action.Builder(android.R.drawable.ic_menu_send, label, send)
                .addRemoteInput(input).setAllowGeneratedReplies(false).build())
            .build()
        return try {
            nm.notify(NOTIFICATION, n)
            true
        } catch (e: SecurityException) {
            false
        }
    }

    fun cancel(context: Context) {
        context.getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION)
    }

    internal fun received(context: Context, id: Int, text: String) {
        reply = id to text
        // ตอบแล้วต้องปิดแจ้งเตือน · ไม่ปิด = ปุ่มส่งหมุนค้าง และเจ้าของไม่รู้ว่าส่งถึงหรือยัง
        cancel(context)
    }

    /** ส่งคำตอบที่ค้างให้ Dart ครั้งเดียว · null = ไม่มี */
    fun take(): Map<String, Any>? {
        val r = reply ?: return null
        reply = null
        return mapOf("id" to r.first, "text" to r.second)
    }

    /** สายจบ · คำตอบที่มาไม่ทันไม่ไหลไปสายหน้า */
    fun clear(context: Context) {
        reply = null
        cancel(context)
    }
}

class OwnerReplyReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val text = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(OwnerAsk.KEY)?.toString()?.trim()
        val id = intent.getIntExtra(OwnerAsk.EXTRA_ID, 0)
        if (text.isNullOrEmpty() || id == 0) {
            OwnerAsk.cancel(context)
            return
        }
        OwnerAsk.received(context, id, text.take(500))
    }
}
