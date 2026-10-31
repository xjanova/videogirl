package com.xjanova.videogirl.hands

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.xjanova.videogirl.MainActivity
import com.xjanova.videogirl.R

/**
 * แจ้งเตือนค้างระหว่างมายด์ใช้เครื่องแทน · มีปุ่มหยุดเสมอ
 *
 * เจ้าของต้องเห็นทุกครั้งที่เธอกำลังแตะเครื่อง และหยุดได้จากแถบแจ้งเตือนโดยไม่ต้องเปิดแอป ·
 * เป็น foreground service (specialUse) ให้ระบบไม่ฆ่าระหว่างงาน · ระบบไม่ยอมให้เริ่ม (แอปอยู่
 * เบื้องหลัง) = ขึ้นแจ้งเตือนเดียวกันแบบธรรมดาแทน ปุ่มหยุดยังใช้ได้
 *
 * แจ้งเตือนอีกตัว (heads-up) ถามเจ้าของก่อนทำขั้นที่ย้อนกลับไม่ได้ · คำตอบไปรอใน [HandsControl]
 * ให้ Dart มารับผ่าน `poll`
 *
 * 🔒 ข้อความในแจ้งเตือนมาจาก Dart (สิ่งที่เจ้าของสั่ง) · ไม่ลง log
 */
class HandsService : Service() {
    companion object {
        private const val TAG = "GigGokHands"
        private const val CHANNEL = "giggok_hands"
        private const val ASK_CHANNEL = "giggok_hands_ask"
        private const val NOTIFICATION = 7061
        private const val ASK_NOTIFICATION = 7062

        // รหัส PendingIntent · 7043-7047 เป็นของแจ้งเตือนเสียงตรง
        private const val PI_OPEN = 7061
        private const val PI_STOP = 7062
        private const val PI_DONE = 7063
        private const val PI_CANCEL = 7064
        private const val PI_ALLOW = 7065
        private const val PI_DENY = 7066
        private const val PI_DISMISS = 7067

        private const val ACTION_SHOW = "com.xjanova.videogirl.hands.SHOW"
        private const val ACTION_STOP = "com.xjanova.videogirl.hands.STOP"
        private const val ACTION_DONE = "com.xjanova.videogirl.hands.DONE"
        private const val ACTION_ALLOW = "com.xjanova.videogirl.hands.ALLOW"
        private const val ACTION_DENY = "com.xjanova.videogirl.hands.DENY"
        private const val EXTRA_ID = "giggok.hands.ask_id"

        private val main = Handler(Looper.getMainLooper())
        @Volatile private var live: HandsService? = null

        /** เริ่มงาน/เริ่มจำ · ขึ้นแจ้งเตือน */
        fun start(context: Context) {
            val app = context.applicationContext
            ensureChannels(app)
            try {
                ContextCompat.startForegroundService(app, Intent(app, HandsService::class.java).setAction(ACTION_SHOW))
            } catch (e: RuntimeException) {
                // แอปอยู่เบื้องหลัง (Android 12+) · แจ้งเตือนธรรมดาแทน ปุ่มหยุดยังอยู่
                Log.w(TAG, "fgs refused: ${e.javaClass.simpleName}")
                post(app)
            }
        }

        /** อัปเดตบรรทัดในแจ้งเตือน (ใช้ได้ทั้งตอนเป็น foreground และตอนเป็นแจ้งเตือนธรรมดา) */
        fun refresh(context: Context) {
            if (!HandsControl.active) return
            post(context.applicationContext)
        }

        /** ตัวจบงานสำรอง · ดู [requestStop] */
        @Volatile private var stuckApp: Context? = null
        private val forceEnd = Runnable {
            val app = stuckApp ?: return@Runnable
            if (HandsControl.active && HandsControl.stopRequested) end(app)
        }

        /**
         * เจ้าของ (หรือการพักให้แอปธนาคาร) สั่งหยุด · ทุกคำสั่งตอบ stopped ทันที
         *
         * 🔴 ปกติ Dart เห็นจาก `poll` แล้วเรียก `end` เอง · ถ้าฝั่ง Dart ค้างหรือตาย งานจะค้าง
         * "กำลังทำ" ตลอดและบริการไม่ถูกปิด · ครบ 15 วิแล้วยังไม่จบ = จบเองที่นี่
         */
        fun requestStop(context: Context) {
            val app = context.applicationContext
            HandsControl.requestStop()
            refresh(app)
            stuckApp = app
            main.removeCallbacks(forceEnd)
            main.postDelayed(forceEnd, 15_000L)
        }

        /** จบงาน/จบการจำ · ปิดแจ้งเตือน · ปิดบริการหลังว่าง (ถ้าเราเป็นคนเปิด) */
        fun end(context: Context) {
            val app = context.applicationContext
            main.removeCallbacks(forceEnd)
            HandsControl.release()
            finish(app)
            if (HandsSwitch.enabledByUs(app)) HandsSwitch.scheduleIdleOff(app)
        }

        /** ปิดแจ้งเตือนทั้งสองตัว */
        fun finish(context: Context) {
            val app = context.applicationContext
            main.post {
                live?.let {
                    it.stopForeground(Service.STOP_FOREGROUND_REMOVE)
                    it.stopSelf()
                }
            }
            val nm = NotificationManagerCompat.from(app)
            nm.cancel(NOTIFICATION)
            nm.cancel(ASK_NOTIFICATION)
        }

        /** ถามเจ้าของก่อนทำ (ทำเลย / ไม่ต้อง) */
        fun ask(context: Context, id: Int, title: String, body: String) {
            val app = context.applicationContext
            ensureChannels(app)
            HandsControl.ask(id)
            fun action(code: Int, name: String) = PendingIntent.getService(
                app, code,
                Intent(app, HandsService::class.java).setAction(name).putExtra(EXTRA_ID, id),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val n = NotificationCompat.Builder(app, ASK_CHANNEL)
                .setSmallIcon(R.drawable.ic_hands)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setPublicVersion(publicVersion(app, ASK_CHANNEL, R.string.hands_public_ask))
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setContentIntent(open(app))
                // ปัดทิ้ง = ไม่ต้อง · ไม่ปล่อยให้เธอรอจนหมดเวลา
                .setDeleteIntent(action(PI_DISMISS, ACTION_DENY))
                .addAction(R.drawable.ic_hands, app.getString(R.string.hands_allow), action(PI_ALLOW, ACTION_ALLOW))
                .addAction(R.drawable.ic_hands, app.getString(R.string.hands_deny), action(PI_DENY, ACTION_DENY))
                .build()
            notify(app, ASK_NOTIFICATION, n)
        }

        fun askDone(context: Context, id: Int) {
            HandsControl.askDone(id)
            NotificationManagerCompat.from(context.applicationContext).cancel(ASK_NOTIFICATION)
        }

        private fun ensureChannels(context: Context) {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(CHANNEL) == null) {
                nm.createNotificationChannel(NotificationChannel(CHANNEL,
                    context.getString(R.string.hands_channel), NotificationManager.IMPORTANCE_LOW).apply {
                    setShowBadge(false)
                })
            }
            if (nm.getNotificationChannel(ASK_CHANNEL) == null) {
                nm.createNotificationChannel(NotificationChannel(ASK_CHANNEL,
                    context.getString(R.string.hands_ask_channel), NotificationManager.IMPORTANCE_HIGH))
            }
        }

        private fun open(context: Context) = PendingIntent.getActivity(
            context, PI_OPEN,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        /**
         * 🔒 สิ่งที่จอล็อกเห็น · หัวเรื่องกลาง ๆ อย่างเดียว
         *
         * เป้าหมายงาน บรรทัดความคืบหน้า และคำถาม มีชื่อปุ่ม ชื่อคน ข้อความแชท · คนที่หยิบเครื่อง
         * ที่ล็อกอยู่ต้องไม่เห็น · เจ้าของปลดล็อกแล้วเห็นตัวเต็มพร้อมปุ่มตามปกติ
         */
        private fun publicVersion(context: Context, channel: String, title: Int): Notification =
            NotificationCompat.Builder(context, channel)
                .setSmallIcon(R.drawable.ic_hands)
                .setContentTitle(context.getString(title))
                .build()

        private fun notify(context: Context, id: Int, n: Notification) {
            try {
                NotificationManagerCompat.from(context).notify(id, n)
            } catch (_: SecurityException) {
                // ปิดการแจ้งเตือนไว้ · ปุ่มหยุดในแอปยังใช้ได้ (status.notifications บอก Dart)
            }
        }

        private fun post(context: Context) {
            ensureChannels(context)
            notify(context, NOTIFICATION, build(context))
        }

        private fun build(context: Context): Notification {
            fun action(code: Int, name: String) = PendingIntent.getService(
                context, code,
                Intent(context, HandsService::class.java).setAction(name),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val stopping = HandsControl.stopRequested
            val recording = HandsControl.recording
            val text = when {
                stopping -> context.getString(R.string.hands_stopping)
                recording -> context.getString(R.string.hands_record_body)
                else -> HandsControl.line
            }
            val b = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_hands)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setPublicVersion(publicVersion(context, CHANNEL, R.string.hands_public_working))
                .setContentTitle(HandsControl.title.ifEmpty { "GigGok" })
                .setContentText(text)
                .setContentIntent(open(context))
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setOnlyAlertOnce(true)
                .setOngoing(true)
            if (text.isNotEmpty()) b.setStyle(NotificationCompat.BigTextStyle().bigText(text))
            if (!stopping) {
                if (recording) {
                    b.addAction(R.drawable.ic_hands, context.getString(R.string.hands_record_done), action(PI_DONE, ACTION_DONE))
                    b.addAction(R.drawable.ic_hands, context.getString(R.string.hands_record_cancel), action(PI_CANCEL, ACTION_STOP))
                } else {
                    b.addAction(R.drawable.ic_hands, context.getString(R.string.hands_stop), action(PI_STOP, ACTION_STOP))
                }
            }
            return b.build()
        }
    }

    private var foreground = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        live = this
        ensureChannels(this)
    }

    override fun onDestroy() {
        if (live === this) live = null
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> requestStop(this)
            ACTION_DONE -> {
                if (HandsControl.recording) HandsControl.recordDone = true
            }
            ACTION_ALLOW, ACTION_DENY -> {
                val id = intent.getIntExtra(EXTRA_ID, Int.MIN_VALUE)
                HandsControl.answer(id, intent.action == ACTION_ALLOW)
                NotificationManagerCompat.from(this).cancel(ASK_NOTIFICATION)
            }
            else -> goForeground()
        }
        if (!HandsControl.active) {
            // งานจบไปแล้ว (หรือโปรเซสเคยตาย) · แจ้งเตือนที่ค้างอยู่ไม่มีงานให้หยุดแล้ว
            finish(this)
            if (!foreground) stopSelf(startId)
        } else if (!foreground) {
            // มาจากปุ่มในแจ้งเตือนธรรมดา (เริ่มแบบ foreground ไม่ได้) · ไม่ต้องอยู่ต่อ
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    /** ต้องเรียกทุกครั้งที่ถูกเริ่มด้วย startForegroundService · ไม่งั้นระบบฆ่าแอป */
    private fun goForeground() {
        val n = build(this)
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIFICATION, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(NOTIFICATION, n)
            }
            foreground = true
        } catch (e: RuntimeException) {
            Log.w(TAG, "startForeground: ${e.javaClass.simpleName}")
            notify(this, NOTIFICATION, n)
        }
    }
}
