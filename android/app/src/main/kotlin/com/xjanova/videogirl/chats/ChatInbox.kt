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
 * แชทที่มีคนทักมา (WhatsApp, LINE, Messenger, …) → มายด์ร่างคำตอบ → ถามเจ้าของก่อนส่ง → ส่งผ่านปุ่ม "ตอบกลับ" ของแอปนั้นเอง
 *
 * เจ้าของเปิด "ตอบเองทุกแชท" ได้ (2026-11-07: "เธอตอบแทนเราได้เอง ทุกแชท เหมือนรับโทรศัพท์ได้เลย") หรืออนุญาตรายคน ·
 * ถึงเปิดแล้วก็ยังถามเมื่อ: เจ้าของเข้ามาพิมพ์ในห้องนั้นเอง · ข้อความดูเป็นรหัส/เรื่องเงิน · ตอบเองเกินโควตาของคนนั้น
 *
 * เจ้าของ (2026-11-07): "ทำให้เธอตอบ what app ได้ด้วย · เมื่อมีคนแชทมา" · ไม่ใช้ API หรือการล็อกอินใด ๆ
 * (เจ้าของชอบให้เธอใช้แอปที่มีในเครื่องมากกว่าขอสิทธิ์บัญชี) · อ่านจากแจ้งเตือน ([ChatWatch]) แล้วตอบผ่าน
 * RemoteInput ของแจ้งเตือนนั้น · ปิดอยู่เป็นค่าเริ่มต้น เจ้าของเปิดในตั้งค่า + ให้สิทธิ์เข้าถึงการแจ้งเตือนเอง
 *
 * ## 🔒
 * - ส่งได้เมื่อเจ้าของกด "ส่งเลย" / พิมพ์แก้แล้วส่ง หรือเจ้าของเปิดให้ตอบเองไว้ · สมองไม่มีเครื่องมือส่งเอง
 * - กลุ่มไม่ตอบ · ข้อความของเจ้าของเอง (ตอบจากที่อื่น) ไม่นับ · แจ้งเตือนสรุป "3 ข้อความใหม่" ไม่นับ
 * - ไม่ลงข้อความหรือชื่อคนใน log
 * - แจ้งเตือนถามบนจอล็อกมีแค่หัวเรื่องกลาง ๆ · กล่องลอยไม่ขึ้นบนจอล็อก ([AskOverlay])
 * - SMS: ตอบเฉพาะเบอร์จริง/คนในสมุดโทรศัพท์ ([SmsSender]) · ถามทุกครั้ง ไม่มีตอบเอง ไม่มีอนุญาตถาวร (ส่ง SMS เสียเงิน)
 *
 * ข้อความเสียง (🎤): แจ้งเตือนไม่มีไฟล์เสียงมาด้วย (WhatsApp/LINE ส่งมาแค่คำว่า "ข้อความเสียง (0:12)") และไฟล์ในเครื่อง
 * อยู่ในโฟลเดอร์ของแอปนั้นที่ scoped storage กันไว้ (ต้องขอสิทธิ์อ่านไฟล์ทั้งเครื่อง) · จึงไม่ถอดความ ·
 * ส่งธง `voice` ให้ Dart บอกเจ้าของ และร่างคำตอบว่าได้รับแล้ว จะส่งต่อให้เจ้าของฟัง
 */
object ChatInbox {

    /**
     * แอปแชทที่ตอบผ่านปุ่ม "ตอบกลับ" ในแจ้งเตือนได้ · เจ้าของ: "มีการแชทเด้งมา … เธอตอบแทนเราได้เอง ทุกแชท"
     * 🔒 แอป SMS ([SmsSender.APPS]) รวมด้วย แต่ OTP / ธนาคาร / โปรโมชันมาทางนั้น · ผ่านเฉพาะคนจริง ([SmsSender.ok]) และถามเสมอ
     */
    val APPS = setOf(
        "com.whatsapp", "com.whatsapp.w4b",
        "jp.naver.line.android",
        "com.facebook.orca", "com.facebook.mlite",
        "com.instagram.android",
        "org.telegram.messenger", "org.telegram.messenger.web", "org.thunderdog.challegram",
        "com.viber.voip",
        "org.thoughtcrime.securesms",
        "com.discord",
        "com.zing.zalo",
        "com.kakao.talk",
        "com.skype.raider",
        "com.microsoft.teams",
    ) + SmsSender.APPS

    private const val PREFS = "giggok_chats"
    private const val KEY_ON = "on"
    private const val CHANNEL = "giggok_chat_ask"
    private const val NOTIFICATION_BASE = 7110
    private const val FIRST_ID = 1_000_000
    const val ACTION_SEND = "com.xjanova.videogirl.chats.SEND"
    const val ACTION_SKIP = "com.xjanova.videogirl.chats.SKIP"
    const val ACTION_SEND_TRUST = "com.xjanova.videogirl.chats.SEND_TRUST"
    private const val KEY_TRUST = "trust"
    private const val KEY_AUTO = "auto"
    private const val KEY_INTRO = "intro"

    /** ไม่ได้คุยกับคนนี้นานเท่านี้ = ทักใหม่ แนะนำตัวใหม่ (เจ้าของ: "ก่อนตอบต้องบอกก่อนว่าตัวเองเป็นเลขาชื่ออะไร") */
    private const val INTRO_AGAIN_MS = 24 * 60 * 60_000L

    /** ตอบเองได้ไม่เกินเท่านี้ต่อคนในช่วงเวลานี้ · เกิน = กลับไปถามเจ้าของ (กันบอทสองตัวตอบกันไม่จบ) */
    private const val AUTO_MAX = 6
    private const val AUTO_WINDOW_MS = 10 * 60_000L

    /** ข้อความแบบนี้ไม่ตอบเองเด็ดขาด ต่อให้เปิดโหมดตอบเอง · ถามเจ้าของเสมอ */
    private val SENSITIVE = Regex(
        "(?i)\\b(otp|one[- ]time|verification code|passcode|pin)\\b|รหัส\\s*(otp|ยืนยัน|ผ่าน)|โอนเงิน|เลขบัญชี|พร้อมเพย์",
    )
    const val EXTRA_ID = "giggok.chat_id"
    const val KEY_EDIT = "chat_edit"

    /** ข้อความเก่ากว่านี้ไม่ตอบ (แจ้งเตือนค้างที่ระบบส่งซ้ำตอนบริการต่อใหม่) */
    private const val FRESH_MS = 10 * 60_000L
    private const val KEEP = 20

    private val main = Handler(Looper.getMainLooper())

    private class Pending(
        val id: Int,
        val key: String,
        /** ตัวคนในแอปนั้น (แท็กของแจ้งเตือน = ห้องแชท) · ใช้จำว่า "ส่งให้คนนี้ได้เลย" */
        val contact: String,
        val app: String,
        val who: String,
        val text: String,
        val at: Long,
        val action: Notification.Action,
        /** ตัดสินตอนข้อความเข้า: ส่งเองได้ไม่ต้องถาม (โหมดตอบเอง / คนที่อนุญาตไว้ · เจ้าของไม่ได้เข้ามาคุยเอง · ไม่เกินโควตา) */
        val auto: Boolean,
        /** SMS · ถามทุกครั้ง ไม่มีปุ่ม "ส่งได้เลยทุกครั้ง" */
        val sms: Boolean = false,
        @Volatile var draft: String = "",
        @Volatile var asked: Boolean = false,
    )

    private val lock = Any()
    private val pending = LinkedHashMap<Int, Pending>()
    private val seen = ArrayDeque<String>()
    private var nextId = FIRST_ID
    private val queue = ArrayList<Map<String, Any>>()

    /** ข้อความที่เธอส่งไปเองต่อคน (hash) · ข้อความ "ของเจ้าของ" ในห้องที่ไม่อยู่ในนี้ = เจ้าของเข้ามาคุยเองแล้ว */
    private val herSent = HashMap<String, ArrayDeque<Int>>()
    private val autoTimes = HashMap<String, ArrayDeque<Long>>()

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

    // ── อนุญาตถาวรรายคน · เจ้าของ: "ให้เราเปิดการอนุญาตถาวร โดยไม่ต้องถามเราทุกครั้ง" ──
    // เก็บเป็น "contact\tชื่อที่เห็น" · ให้ได้จากกล่องถามเท่านั้น (เจ้าของกดเอง) · ยกเลิกได้ในตั้งค่า

    private fun trustSet(context: Context): Set<String> =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(KEY_TRUST, emptySet()) ?: emptySet()

    fun trusted(context: Context, contact: String): Boolean =
        trustSet(context).any { it.substringBefore('\t') == contact }

    private fun trust(context: Context, contact: String, name: String) {
        val next = trustSet(context).filterNot { it.substringBefore('\t') == contact }.toMutableSet()
        next.add("$contact\t${name.replace('\t', ' ').take(80)}")
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putStringSet(KEY_TRUST, next).apply()
    }

    fun untrust(context: Context, contact: String?) {
        val next = if (contact == null) emptySet() else trustSet(context).filterNot { it.substringBefore('\t') == contact }.toSet()
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putStringSet(KEY_TRUST, next).apply()
    }

    fun trustedList(context: Context): List<Map<String, String>> =
        trustSet(context).map { mapOf("contact" to it.substringBefore('\t'), "name" to it.substringAfter('\t', "")) }
            .sortedBy { it["name"] }

    /** โหมด "ตอบเองทุกแชท" · เจ้าของเปิดเองในตั้งค่า (แอปเตือนก่อนเปิด) */
    fun auto(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_AUTO, false)

    fun setAuto(context: Context, v: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_AUTO, v).apply()
    }

    /** เธอคุยกับคนนี้ล่าสุดเมื่อไหร่ · เก็บเป็น "contact\tเวลา" · ข้ามการเปิดแอปใหม่ */
    private fun introAt(context: Context, contact: String): Long =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getStringSet(KEY_INTRO, emptySet()).orEmpty()
            .firstOrNull { it.substringBefore('\t') == contact }?.substringAfter('\t', "")?.toLongOrNull() ?: 0L

    private fun markIntro(context: Context, contact: String, now: Long) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val rest = prefs.getStringSet(KEY_INTRO, emptySet()).orEmpty()
            .filterNot { it.substringBefore('\t') == contact }
            .sortedByDescending { it.substringAfter('\t', "").toLongOrNull() ?: 0L }
            .take(300)
        prefs.edit().putStringSet(KEY_INTRO, (rest + "$contact\t$now").toSet()).apply()
    }

    private fun underQuota(contact: String, now: Long): Boolean {
        val times = autoTimes[contact] ?: return true
        while (times.isNotEmpty() && now - times.first() > AUTO_WINDOW_MS) times.removeFirst()
        return times.size < AUTO_MAX
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
        // 🔒 SMS จากธนาคาร OTP โปรโมชัน (ชื่อเป็นตัวหนังสือ / เบอร์สั้น) = ไม่ร่าง ไม่ถาม ไม่บอก
        val sms = SmsSender.isSms(sbn.packageName)
        if (sms && !SmsSender.ok(msg.who, msg.title, msg.uri)) return
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
            val contact = "${sbn.packageName}|${sbn.tag ?: msg.who}"
            // เจ้าของพิมพ์ในห้องนี้เอง (ข้อความ "ของเรา" ที่เธอไม่ได้ส่ง) = เจ้าของรับเรื่องต่อแล้ว เหมือนรับสายต่อ · กลับไปถาม
            val mine = herSent[contact]
            val ownerSpoke = msg.mine.any { mine == null || it.hashCode() !in mine }
            // 🔒 SMS ไม่ตอบเองเด็ดขาด (เสียเงิน) · ต่อให้เปิดตอบเองทุกแชทหรืออนุญาตคนนี้ไว้
            val auto = !sms && (auto(context) || trusted(context, contact)) && !ownerSpoke &&
                !SENSITIVE.containsMatchIn(msg.text) && underQuota(contact, System.currentTimeMillis())
            pending[id] = Pending(id, sbn.key, contact, sbn.packageName, msg.who, msg.text, msg.at, action, auto, sms)
            while (pending.size > KEEP) pending.remove(pending.keys.first())
            item = mapOf(
                "id" to id,
                "app" to sbn.packageName,
                "who" to msg.who,
                "text" to msg.text,
                "at" to msg.at,
                "earlier" to msg.earlier,
                "contact" to contact,
                "auto" to auto,
                "sms" to sms,
                "voice" to msg.voice,
                "introduce" to (System.currentTimeMillis() - introAt(context, contact) > INTRO_AGAIN_MS),
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

    /**
     * [mine] = ข้อความฝั่งเรา (เจ้าของหรือเธอ) ในห้องที่แจ้งเตือนยังโชว์อยู่ · [uri] / [title] = ตัวตนของผู้ส่ง (ใช้กับ SMS) ·
     * [voice] = แอปแนบข้อมูลเสียงมากับข้อความ (ไม่ได้อ่านไฟล์ · Dart ดูคำว่า "ข้อความเสียง" เพิ่มเอง)
     */
    private class Msg(
        val who: String,
        val text: String,
        val at: Long,
        val earlier: List<String>,
        val mine: List<String>,
        val uri: String? = null,
        val title: String? = null,
        val voice: Boolean = false,
    )

    private fun read(n: Notification): Msg? {
        val style = NotificationCompat.MessagingStyle.extractMessagingStyleFromNotification(n)
        if (style != null) {
            if (style.isGroupConversation) return null
            val msgs = style.messages
            val last = msgs.lastOrNull() ?: return null
            // ข้อความล่าสุดเป็นของเจ้าของเอง (ตอบไปแล้ว) = ไม่มีอะไรต้องตอบ
            val from = last.person ?: return null
            if (from.key != null && from.key == style.user.key) return null
            val voice = last.dataMimeType?.startsWith("audio/") == true
            val text = last.text?.toString()?.trim().orEmpty().ifEmpty { if (voice) "🎤" else "" }
            if (text.isEmpty()) return null
            val who = from.name?.toString()?.trim().orEmpty()
                .ifEmpty { style.conversationTitle?.toString()?.trim().orEmpty() }
            fun self(m: NotificationCompat.MessagingStyle.Message) =
                m.person == null || (m.person?.key != null && m.person?.key == style.user.key)
            val recent = msgs.dropLast(1).takeLast(8)
            val earlier = recent.mapNotNull { m ->
                val t = m.text?.toString()?.trim().orEmpty()
                if (t.isEmpty()) null else "${if (self(m)) "me" else "them"}: ${t.take(300)}"
            }
            val mine = recent.filter(::self).mapNotNull { m -> m.text?.toString()?.trim()?.takeIf { it.isNotEmpty() } }
            return Msg(
                who, text.take(1000), if (last.timestamp > 0) last.timestamp else n.`when`, earlier, mine,
                uri = from.uri, title = style.conversationTitle?.toString()?.trim(), voice = voice,
            )
        }
        val extras = n.extras ?: return null
        if (extras.getBoolean(NotificationCompat.EXTRA_IS_GROUP_CONVERSATION)) return null
        val who = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        if (who.isEmpty() || text.isEmpty()) return null
        val uri = if (android.os.Build.VERSION.SDK_INT >= 28) {
            @Suppress("DEPRECATION")
            extras.getParcelableArrayList<android.app.Person>(Notification.EXTRA_PEOPLE_LIST)?.firstOrNull()?.uri
        } else {
            null
        }
        return Msg(who, text.take(1000), n.`when`, emptyList(), emptyList(), uri = uri, title = who)
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
        // ตอบเองได้ (ตัดสินไว้ตอนข้อความเข้า) = ส่งเลย · Dart บอกเจ้าของในแชทว่าตอบอะไรไป
        if (p.auto && !p.sms) {
            send(app, id, null)
            return true
        }
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
        // 🔒 SMS ไม่มี "ส่งได้เลยทุกครั้ง" · ถามทุกครั้ง
        if (!p.sms) {
            n.addAction(R.mipmap.ic_launcher, app.getString(R.string.chat_send_trust), PendingIntent.getBroadcast(
                app, id * 4 + 3,
                Intent(app, ChatAskReceiver::class.java).setAction(ACTION_SEND_TRUST).putExtra(EXTRA_ID, id),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ))
        }
        n.addAction(R.mipmap.ic_launcher, app.getString(R.string.chat_skip), broadcast(ACTION_SKIP, false))
        try {
            nm.notify(NOTIFICATION_BASE + (id % 8), n.build())
        } catch (_: SecurityException) {
            // ปิดการแจ้งเตือนไว้ · กล่องลอยยังถามได้ถ้าบริการมือเปิดอยู่
        }
        AskOverlay.show(
            id, title, body, R.string.chat_send, R.string.chat_skip,
            onAnswer = { c, allow, always -> if (allow) send(c, id, null, trust = always) else skip(c, id) },
            always = !p.sms,
            alwaysLabel = R.string.chat_always_check,
        )
        return true
    }

    private fun cancelAsk(context: Context, id: Int) {
        NotificationManagerCompat.from(context.applicationContext).cancel(NOTIFICATION_BASE + (id % 8))
        AskOverlay.hide(id)
    }

    /** เจ้าของกดส่ง · [edited] = ข้อความที่พิมพ์แก้ (null = ส่งร่างของเธอ) */
    fun send(context: Context, id: Int, edited: String?, trust: Boolean = false) {
        val p = synchronized(lock) { pending.remove(id) }
        cancelAsk(context, id)
        if (p == null || !p.asked) {
            report("answered", mapOf("id" to id, "sent" to false, "error" to "expired"))
            return
        }
        if (trust && !p.sms) trust(context.applicationContext, p.contact, p.who)
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
        if (error == null) markIntro(context.applicationContext, p.contact, System.currentTimeMillis())
        if (error == null) synchronized(lock) {
            val sent = herSent.getOrPut(p.contact) { ArrayDeque() }
            sent.addLast(text.trim().hashCode())
            while (sent.size > 30) sent.removeFirst()
            if (p.auto) autoTimes.getOrPut(p.contact) { ArrayDeque() }.addLast(System.currentTimeMillis())
            while (herSent.size > 200) herSent.remove(herSent.keys.first())
            while (autoTimes.size > 200) autoTimes.remove(autoTimes.keys.first())
        }
        report("answered", buildMap {
            put("id", id)
            put("contact", p.contact)
            put("auto", p.auto)
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
            ChatInbox.ACTION_SEND_TRUST -> ChatInbox.send(context, id, null, trust = true)
            ChatInbox.ACTION_SKIP -> ChatInbox.skip(context, id)
        }
    }
}
