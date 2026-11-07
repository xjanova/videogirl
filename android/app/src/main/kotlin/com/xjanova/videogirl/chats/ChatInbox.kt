package com.xjanova.videogirl.chats

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.notification.StatusBarNotification
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.RemoteInput
import com.xjanova.videogirl.MainActivity
import com.xjanova.videogirl.MindEngine
import com.xjanova.videogirl.R
import com.xjanova.videogirl.hands.AskOverlay

/**
 * แชทที่มีคนทักมาทาง WhatsApp → มายด์ร่างคำตอบ → **ถามเจ้าของก่อนส่งทุกครั้ง** → ส่งผ่านปุ่ม "ตอบกลับ" ของ WhatsApp เอง
 *
 * เจ้าของ (2026-11-07): "ทำให้เธอตอบ what app ได้ด้วย · เมื่อมีคนแชทมา" · ไม่ใช้ API หรือการล็อกอินใด ๆ
 * (เจ้าของชอบให้เธอใช้แอปที่มีในเครื่องมากกว่าขอสิทธิ์บัญชี) · อ่านจากแจ้งเตือน ([ChatWatch]) แล้วตอบผ่าน
 * RemoteInput ของแจ้งเตือนนั้น · ปิดอยู่เป็นค่าเริ่มต้น เจ้าของเปิดในตั้งค่า + ให้สิทธิ์เข้าถึงการแจ้งเตือนเอง
 *
 * ## 🔒
 * - ส่งได้ทางเดียวคือเจ้าของกด "ส่งเลย" / พิมพ์แก้แล้วส่ง · สมองไม่มีเครื่องมือส่งเอง
 * - กลุ่มไม่ตอบ · ข้อความของเจ้าของเอง (ตอบจากที่อื่น) ไม่นับ · แจ้งเตือนสรุป "3 ข้อความใหม่" ไม่นับ
 * - ไม่ลงข้อความหรือชื่อคนใน log
 * - แจ้งเตือนถามบนจอล็อกมีแค่หัวเรื่องกลาง ๆ · กล่องลอยไม่ขึ้นบนจอล็อก ([AskOverlay])
 */
object ChatInbox {

    val APPS = setOf("com.whatsapp", "com.whatsapp.w4b")

    private const val PREFS = "giggok_chats"
    private const val KEY_ON = "on"
    private const val CHANNEL = "giggok_chat_ask"
    private const val NOTIFICATION_BASE = 7110
    private const val FIRST_ID = 1_000_000
    const val ACTION_SEND = "com.xjanova.videogirl.chats.SEND"
    const val ACTION_SKIP = "com.xjanova.videogirl.chats.SKIP"
    const val EXTRA_ID = "giggok.chat_id"
    const val KEY_EDIT = "chat_edit"

    /** ข้อความเก่ากว่านี้ไม่ตอบ (แจ้งเตือนค้างที่ระบบส่งซ้ำตอนบริการต่อใหม่) */
    private const val FRESH_MS = 10 * 60_000L
    private const val KEEP = 20

    private val main = Handler(Looper.getMainLooper())

    private class Pending(
        val id: Int,
        val key: String,
        val app: String,
        val who: String,
        val text: String,
        val at: Long,
        val action: Notification.Action,
        @Volatile var draft: String = "",
        @Volatile var asked: Boolean = false,
    )

    private val lock = Any()
    private val pending = LinkedHashMap<Int, Pending>()
    private val seen = ArrayDeque<String>()
    private var nextId = FIRST_ID
    private val queue = ArrayList<Map<String, Any>>()

    /** ส่งเหตุการณ์ให้ Dart (ChatBridge ตั้ง) · null = ยังไม่มี engine */
    @Volatile var events: ((String, Map<String, Any>?) -> Unit)? = null

    fun on(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ON, false)

    fun setOn(context: Context, v: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ON, v).apply()
        if (!v) synchronized(lock) {
            pending.clear()
            queue.clear()
        }
    }

    fun access(context: Context): Boolean =
        NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)

    fun accessComponent(context: Context) = ComponentName(context, ChatWatch::class.java)

    /** แจ้งเตือนใหม่จาก [ChatWatch] */
    fun onPosted(context: Context, sbn: StatusBarNotification) {
        if (sbn.packageName !in APPS || !on(context)) return
        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val action = n.actions?.firstOrNull { !it.remoteInputs.isNullOrEmpty() } ?: return
        val msg = read(n) ?: return
        if (System.currentTimeMillis() - msg.at > FRESH_MS) return
        val stamp = "${sbn.key}|${msg.at}|${msg.text.hashCode()}"
        val item: Map<String, Any>
        synchronized(lock) {
            if (stamp in seen) return
            seen.addLast(stamp)
            while (seen.size > 200) seen.removeFirst()
            // คนเดิมทักซ้ำก่อนเจ้าของตอบ = คำถามเก่าตกไป · ร่างใหม่จากข้อความล่าสุด
            val older = pending.values.filter { it.key == sbn.key }
            for (o in older) {
                pending.remove(o.id)
                cancelAsk(context, o.id)
            }
            val id = nextId++
            pending[id] = Pending(id, sbn.key, sbn.packageName, msg.who, msg.text, msg.at, action)
            while (pending.size > KEEP) pending.remove(pending.keys.first())
            item = mapOf(
                "id" to id,
                "app" to sbn.packageName,
                "who" to msg.who,
                "text" to msg.text,
                "at" to msg.at,
                "earlier" to msg.earlier,
            )
            queue.add(item)
            while (queue.size > KEEP) queue.removeAt(0)
        }
        // ตัวเธออาจหลับอยู่ (แอปถูกปิด) · ปลุกแล้วบอก · Dart ที่เพิ่งตื่นจะมา take เอง
        main.post {
            MindEngine.wake(context.applicationContext)
            events?.invoke("arrived", null)
        }
    }

    private class Msg(val who: String, val text: String, val at: Long, val earlier: List<String>)

    private fun read(n: Notification): Msg? {
        val style = NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(n)
        if (style != null) {
            if (style.isGroupConversation) return null
            val msgs = style.messages
            val last = msgs.lastOrNull() ?: return null
            // ข้อความล่าสุดเป็นของเจ้าของเอง (ตอบไปแล้ว) = ไม่มีอะไรต้องตอบ
            val from = last.person ?: return null
            if (from.key != null && from.key == style.user.key) return null
            val text = last.text?.toString()?.trim().orEmpty()
            if (text.isEmpty()) return null
            val who = from.name?.toString()?.trim().orEmpty()
                .ifEmpty { style.conversationTitle?.toString()?.trim().orEmpty() }
            val earlier = msgs.dropLast(1).takeLast(4).mapNotNull { m ->
                val t = m.text?.toString()?.trim().orEmpty()
                if (t.isEmpty()) null else "${if (m.person == null) "me" else "them"}: ${t.take(300)}"
            }
            return Msg(who, text.take(1000), if (last.timestamp > 0) last.timestamp else n.`when`, earlier)
        }
        val extras = n.extras ?: return null
        if (extras.getBoolean(NotificationCompat.EXTRA_IS_GROUP_CONVERSATION)) return null
        val who = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        if (who.isEmpty() || text.isEmpty()) return null
        return Msg(who, text.take(1000), n.`when`, emptyList())
    }

    /** ของที่มาก่อน Dart ตื่น / ระหว่างนั้น · เอาแล้วล้าง */
    fun take(): List<Map<String, Any>> = synchronized(lock) {
        val out = queue.toList()
        queue.clear()
        out
    }

    /**
     * ถามเจ้าของ: แจ้งเตือนเด้ง (ส่งเลย · แก้แล้วส่ง · ไม่ส่ง) + กล่องลอยเมื่อบริการมือเปิดอยู่ ·
     * false = ข้อความนี้หมดอายุแล้ว (คนเดิมทักใหม่ / ปิดฟีเจอร์)
     */
    fun ask(context: Context, id: Int, draft: String, title: String, body: String): Boolean {
        val p = synchronized(lock) { pending[id] } ?: return false
        p.draft = draft
        p.asked = true
        val app = context.applicationContext
        val nm = app.getSystemService(NotificationManager::class.java) ?: return false
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, app.getString(R.string.chat_ask_channel), NotificationManager.IMPORTANCE_HIGH)
            )
        }
        fun broadcast(action: String, mutable: Boolean) = PendingIntent.getBroadcast(
            app, id * 4 + (if (action == ACTION_SEND) (if (mutable) 1 else 0) else 2),
            Intent(app, ChatAskReceiver::class.java).setAction(action).putExtra(EXTRA_ID, id),
            PendingIntent.FLAG_UPDATE_CURRENT or (if (mutable) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE),
        )
        val edit = RemoteInput.Builder(KEY_EDIT).setLabel(app.getString(R.string.chat_edit_label)).build()
        val open = PendingIntent.getActivity(
            app, 0,
            Intent(app, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val hidden = NotificationCompat.Builder(app, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(app.getString(R.string.chat_public_title))
            .build()
        val n = NotificationCompat.Builder(app, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(hidden)
            .setContentIntent(open)
            .setDeleteIntent(broadcast(ACTION_SKIP, false))
            .addAction(R.mipmap.ic_launcher, app.getString(R.string.chat_send), broadcast(ACTION_SEND, false))
            .addAction(
                NotificationCompat.Action.Builder(R.mipmap.ic_launcher, app.getString(R.string.chat_edit), broadcast(ACTION_SEND, true))
                    .addRemoteInput(edit).setAllowGeneratedReplies(false).build()
            )
            .addAction(R.mipmap.ic_launcher, app.getString(R.string.chat_skip), broadcast(ACTION_SKIP, false))
            .build()
        try {
            nm.notify(NOTIFICATION_BASE + (id % 8), n)
        } catch (_: SecurityException) {
            // ปิดการแจ้งเตือนไว้ · กล่องลอยยังถามได้ถ้าบริการมือเปิดอยู่
        }
        AskOverlay.show(id, title, body, R.string.chat_send, R.string.chat_skip) { c, allow ->
            if (allow) send(c, id, null) else skip(c, id)
        }
        return true
    }

    private fun cancelAsk(context: Context, id: Int) {
        NotificationManagerCompat.from(context.applicationContext).cancel(NOTIFICATION_BASE + (id % 8))
        AskOverlay.hide(id)
    }

    /** เจ้าของกดส่ง · [edited] = ข้อความที่พิมพ์แก้ (null = ส่งร่างของเธอ) */
    fun send(context: Context, id: Int, edited: String?) {
        val p = synchronized(lock) { pending.remove(id) }
        cancelAsk(context, id)
        if (p == null || !p.asked) {
            report("answered", mapOf("id" to id, "sent" to false, "error" to "expired"))
            return
        }
        val text = (edited?.trim()?.takeIf { it.isNotEmpty() } ?: p.draft).take(2000)
        if (text.isBlank()) {
            report("answered", mapOf("id" to id, "sent" to false, "error" to "empty"))
            return
        }
        val error = try {
            val inputs = p.action.remoteInputs
            val intent = Intent()
            val results = Bundle()
            for (ri in inputs) results.putCharSequence(ri.resultKey, text)
            android.app.RemoteInput.addResultsToIntent(inputs, intent, results)
            p.action.actionIntent.send(context.applicationContext, 0, intent)
            null
        } catch (_: PendingIntent.CanceledException) {
            "expired"
        } catch (_: Exception) {
            "failed"
        }
        report("answered", buildMap {
            put("id", id)
            put("sent", error == null)
            put("text", text)
            put("who", p.who)
            if (error != null) put("error", error)
        })
    }

    fun skip(context: Context, id: Int) {
        val p = synchronized(lock) { pending.remove(id) }
        cancelAsk(context, id)
        if (p != null) report("answered", mapOf("id" to id, "sent" to false, "error" to "skipped"))
    }

    private fun report(name: String, args: Map<String, Any>) {
        main.post { events?.invoke(name, args) }
    }

    /** ตอนนี้ยังจำปุ่มตอบของข้อความนี้อยู่ไหม (เทสต์/Dart ใช้ก่อนถาม) */
    fun has(id: Int): Boolean = synchronized(lock) { pending.containsKey(id) }
}

/** ปุ่มในแจ้งเตือนถาม · ส่งเลย / แก้แล้วส่ง / ไม่ส่ง (ปัดทิ้ง = ไม่ส่ง) */
class ChatAskReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(ChatInbox.EXTRA_ID, Int.MIN_VALUE)
        if (id == Int.MIN_VALUE) return
        when (intent.action) {
            ChatInbox.ACTION_SEND -> {
                val edited = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(ChatInbox.KEY_EDIT)?.toString()
                ChatInbox.send(context, id, edited)
            }
            ChatInbox.ACTION_SKIP -> ChatInbox.skip(context, id)
        }
    }
}
