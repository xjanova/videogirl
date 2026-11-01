package com.xjanova.videogirl.listen

import android.Manifest
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.xjanova.videogirl.MainActivity
import com.xjanova.videogirl.R
import java.io.File

/**
 * ไมค์ของมายด์ที่อยู่ได้ตอนแอปไม่อยู่บนจอ
 *
 * เจ้าของ: "พอเราสั่งให้ทำอะไร มายด์ต้องยังคงรันเบื้องหลัง เธอต้องยังคงตอบพูดคุยกับฉันได้อยู่แม้หน้าจอจะไม่ใช่แอพแล้ว
 * เพราะเธออาจไปเปิดเมลหรือเปิดเว็บให้เรา" · "ใช้คำพิเศษเรียกเธอให้รับคำสั่งได้ เช่นน้องมายด์ เธอต้องขานทันที"
 *
 * ## บริการเดียวถือไมค์ตัวเดียว
 *
 * - [Mode.WATCH] รอคำเรียก · เสียงอยู่ในหน่วยความจำของ [WakeMatcher] ไม่ออกไปไหน ไม่ถึง Dart ด้วยซ้ำ
 * - [Mode.STREAM] คุยกับเจ้าของ · ส่ง PCM ให้ Dart ([com.xjanova.videogirl.listen.ListenBridge]) แล้ว Dart ส่งต่อ
 * - [Mode.TEACH] เจ้าของกำลังสอนคำเรียก
 *
 * สลับ WATCH → STREAM โดยไม่ปิดไมค์ · ปิดแล้วเปิดใหม่ = เสียงหายช่วงที่เจ้าของเริ่มสั่งพอดี
 *
 * ## 🔴 ข้อจำกัดของ Android 14+
 *
 * ไมค์ใน foreground service ใช้ได้เมื่อ**เริ่มตอนแอปอยู่บนจอ**เท่านั้น · เริ่มจาก BOOT_COMPLETED / sticky restart
 * ถูกปฏิเสธ · หลังรีสตาร์ตเครื่อง/อัปเดตแอป จึงต้องให้เจ้าของแตะแจ้งเตือนหนึ่งครั้ง ([postResume]) · ทางอื่นไม่มี
 *
 * ## 🔴 ไมค์เปิดค้าง = ต้องเห็นเสมอ
 *
 * แจ้งเตือนค้างตลอด มีปุ่มหยุด · ไมค์ปล่อยเองเมื่อมีสาย หรือแอปอื่นขอใช้ไมค์ ([othersUsingMic])
 */
class ListenService : Service() {

    enum class Mode { WATCH, STREAM, TEACH }

    companion object {
        private const val TAG = "GigGokListen"
        private const val CHANNEL = "giggok_listen"
        private const val NOTIFICATION = 7081
        private const val RESUME_NOTIFICATION = 7082

        // รหัส PendingIntent · 7061-7067 เป็นของ HandsService
        private const val PI_OPEN = 7081
        private const val PI_STOP = 7082
        private const val PI_RESUME = 7083

        private const val ACTION_RUN = "com.xjanova.videogirl.listen.RUN"
        private const val ACTION_STOP = "com.xjanova.videogirl.listen.STOP"
        private const val EXTRA_MODE = "giggok.listen.mode"

        private const val PREFS = "giggok_listen"
        private const val KEY_WAKE = "wake_on"
        private const val KEY_WORD = "word"
        private const val WORD_FILE = "wake_word.bin"
        private const val REPLY_DIR = "wake_replies"

        private const val RATE = WakeMatcher.RATE
        private const val READ = RATE / 50 // 20 มิลลิวินาที
        private const val CHUNK_BYTES = RATE / 10 * 2 // ส่งให้ Dart ทีละ 100 มิลลิวินาที

        /** เสียงที่เก็บไว้รอ Dart เปิดรับ (เจ้าของสั่งต่อทันทีตอนคุยสดกำลังต่อเซิร์ฟเวอร์) */
        private const val BACKLOG_CHUNKS = 100

        /** หลังเธอขานแล้วไมค์ยังไม่ส่ง · ลำโพงยังปล่อยหาง · ไม่กั้น = เธอได้ยินคำว่า "ขา" ของตัวเอง */
        private const val ACK_TAIL_MS = 250L

        /** Dart ไม่มารับหลังขาน (ค้าง / มีสาย) = กลับไปรอฟัง ไม่ค้างเป็นไมค์ที่ไม่มีใครฟัง */
        private const val CLAIM_LIMIT_MS = 6_000L
        private const val FORCE_CLOSE_MS = 3_000L

        /** กันเรียกซ้ำตอนเพิ่งคุยจบ · เจ้าของยังพูดค้างอยู่ได้ */
        private const val QUIET_AFTER_CHAT_MS = 1_500L
        private const val WAKE_LOCK_MS = 10 * 60 * 1000L

        private val main = Handler(Looper.getMainLooper())

        @Volatile private var live: ListenService? = null

        /** ส่ง PCM ให้ Dart · null = ยังไม่มีใครรับ */
        @Volatile var sink: ((ByteArray) -> Unit)? = null

        /** ยิงเหตุการณ์หา Dart · ตั้งโดย [ListenBridge] */
        @Volatile var events: ((String, Map<String, Any?>) -> Unit)? = null

        private var readyCallback: ((Boolean) -> Unit)? = null

        /** บริการไมค์ทำงานอยู่ · จอตายแล้ว engine ต้องอยู่ต่อ (ดู MainActivity.shouldDestroyEngineWithHost) */
        @JvmStatic
        val running: Boolean get() = live != null

        private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        private fun wordFile(c: Context) = File(c.noBackupFilesDir, WORD_FILE)
        private fun micGranted(c: Context) =
            ContextCompat.checkSelfPermission(c, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

        /** เจ้าของเปิดรอคำเรียกไว้ และพร้อมจริง (สอนแล้ว · มีสิทธิ์ไมค์) */
        private fun wantsWatch(c: Context) =
            prefs(c).getBoolean(KEY_WAKE, false) && micGranted(c) && wordFile(c).exists()

        private fun start(c: Context, mode: Mode, ready: ((Boolean) -> Unit)?) {
            val app = c.applicationContext
            ensureChannel(app)
            readyCallback = ready
            try {
                // 🔴 ไม่ใช้ startForegroundService · มันบังคับว่าต้องได้ startForeground ไม่งั้นระบบฆ่าทั้งแอป ·
                // ไมค์ถูกปฏิเสธจากเบื้องหลังได้ (แอปที่ได้ยกเว้นแบตผ่านด่านแรก ไปโดนที่ startForeground) ·
                // ทุกทางเรียกตอนแอปอยู่บนจอ startService ธรรมดาจึงพอ
                app.startService(
                    Intent(app, ListenService::class.java).setAction(ACTION_RUN).putExtra(EXTRA_MODE, mode.name)
                )
            } catch (e: RuntimeException) {
                // แอปอยู่เบื้องหลัง · ระบบไม่ให้เริ่มไมค์
                Log.w(TAG, "start refused: ${e.javaClass.simpleName}")
                readyCallback = null
                ready?.invoke(false)
            }
        }

        /** เปิดไมค์ให้คุย · [ready] false = เริ่มไม่ได้ (ใช้ไมค์แบบต้องอยู่บนจอแทน) */
        fun open(c: Context, ready: (Boolean) -> Unit) {
            val s = live
            if (s != null) {
                s.claimed()
                s.switchTo(Mode.STREAM)
                ready(true)
            } else {
                start(c, Mode.STREAM, ready)
            }
        }

        /** Dart รับช่วงการปลุกแล้ว (เธอกำลังเปิดคุยสด) */
        fun claim() {
            live?.claimed()
        }

        /** จบคุย · กลับไปรอคำเรียกถ้าเปิดไว้ ไม่งั้นปิดไมค์ */
        fun close(c: Context) {
            val s = live ?: return
            // กำลังสอนคำเรียก · คุยต่อเนื่องที่ปิดอยู่ไม่ได้เกี่ยวด้วย
            if (s.mode == Mode.TEACH) return
            s.claimed()
            s.backToRest()
        }

        fun teachStart(c: Context, ready: (Boolean) -> Unit) {
            val s = live
            if (s != null) {
                // กำลังคุยอยู่ · สอนทับ = ไมค์ของคุยต่อเนื่องเงียบหายโดยไม่มีใครรู้
                if (s.mode == Mode.STREAM) {
                    ready(false)
                    return
                }
                s.beginTeach()
                ready(true)
            } else {
                start(c, Mode.TEACH, ready)
            }
        }

        fun teachStop(c: Context) {
            val s = live ?: return
            if (s.mode == Mode.TEACH) s.backToRest()
        }

        /** ซิงก์ตามค่าที่ตั้ง · ตอนเปิดแอป และตอนเจ้าของกดสวิตช์ */
        fun sync(c: Context) {
            val s = live
            if (wantsWatch(c)) {
                // มีคำขอเปิดค้างอยู่ · เริ่มซ้อน = ทับ callback ของ open แล้วโหมดกลับไปรอฟังกลางคุย
                if (s == null && readyCallback == null) start(c, Mode.WATCH, null)
            } else if (s != null && s.mode == Mode.WATCH) {
                s.stopNow()
            }
        }

        fun setWake(c: Context, on: Boolean) {
            prefs(c).edit().putBoolean(KEY_WAKE, on).apply()
            NotificationManagerCompat.from(c).cancel(RESUME_NOTIFICATION)
            sync(c)
        }

        fun setSensitivity(c: Context, level: Int) {
            val w = WakeWord.load(wordFile(c)) ?: return
            w.sensitivity = level.coerceIn(0, 2)
            w.save(wordFile(c))
            live?.reloadWord()
        }

        fun setLabel(c: Context, word: String) {
            prefs(c).edit().putString(KEY_WORD, word).apply()
            live?.refresh()
        }

        /** ลบคำเรียกที่สอนไว้ · ปิดการรอฟังด้วย */
        fun forget(c: Context) {
            val s = live
            prefs(c).edit().putBoolean(KEY_WAKE, false).remove(KEY_WORD).apply()
            wordFile(c).delete()
            if (s != null && s.mode != Mode.STREAM) s.stopNow() else s?.reloadWord()
        }

        /** เสียงขานที่สังเคราะห์ไว้ล่วงหน้า · ขานทันทีได้เพราะไม่ต้องรอเน็ต */
        fun setReplies(c: Context, clips: List<Pair<ByteArray, String>>) {
            val dir = File(c.filesDir, REPLY_DIR)
            dir.deleteRecursively()
            dir.mkdirs()
            clips.forEachIndexed { i, (bytes, ext) -> File(dir, "$i.$ext").writeBytes(bytes) }
            live?.loadReplies()
        }

        fun playReply(c: Context) {
            val s = live
            if (s != null) {
                s.ack()
                return
            }
            // ยังไม่ได้เปิดบริการ (เพิ่งสอนเสร็จ) · ลองฟังจากไฟล์ตรง ๆ
            val f = File(c.filesDir, REPLY_DIR).listFiles()?.firstOrNull() ?: return
            try {
                MediaPlayer().apply {
                    setAudioAttributes(replyAttributes)
                    setDataSource(f.path)
                    setOnCompletionListener { it.release() }
                    prepare()
                    start()
                }
            } catch (e: Exception) {
                Log.w(TAG, "reply preview: ${e.javaClass.simpleName}")
            }
        }

        /** ปุ่มออกจากแอป · ไม่ให้ sticky ปลุกกลับขึ้นมา */
        @JvmStatic
        fun shutdown() {
            live?.stopNow()
        }

        /** ล็อกด้วยรหัส/ลายนิ้วมืออยู่ · ปัดเปิดเฉย ๆ ไม่นับ */
        fun locked(c: Context): Boolean =
            c.getSystemService(KeyguardManager::class.java)?.isDeviceLocked != false

        fun status(c: Context): Map<String, Any?> {
            val s = live
            val w = WakeWord.load(wordFile(c))
            return mapOf(
                "running" to (s != null),
                "mode" to s?.mode?.name,
                "paused" to (s?.paused == true),
                "wake" to prefs(c).getBoolean(KEY_WAKE, false),
                "taught" to (w != null),
                "word" to prefs(c).getString(KEY_WORD, null),
                "sensitivity" to (w?.sensitivity ?: 1),
                "replies" to (File(c.filesDir, REPLY_DIR).list()?.size ?: 0),
            )
        }

        private val replyAttributes: AudioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

        private fun ensureChannel(c: Context) {
            val nm = c.getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(CHANNEL) != null) return
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    c.getString(R.string.listen_channel),
                    NotificationManager.IMPORTANCE_LOW
                ).apply { setShowBadge(false) }
            )
        }

        private fun openApp(c: Context, code: Int): PendingIntent = PendingIntent.getActivity(
            c, code,
            Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        /** ไมค์เริ่มเองไม่ได้ (รีสตาร์ตเครื่อง อัปเดตแอป ถูกระบบปิด) · ให้เจ้าของแตะหนึ่งครั้ง */
        fun postResume(c: Context) {
            val app = c.applicationContext
            if (!prefs(app).getBoolean(KEY_WAKE, false)) return
            ensureChannel(app)
            val n = NotificationCompat.Builder(app, CHANNEL)
                .setSmallIcon(R.drawable.ic_listen)
                .setContentTitle(app.getString(R.string.listen_resume_title))
                .setContentText(app.getString(R.string.listen_resume_text))
                .setContentIntent(openApp(app, PI_RESUME))
                .setAutoCancel(true)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .build()
            try {
                NotificationManagerCompat.from(app).notify(RESUME_NOTIFICATION, n)
            } catch (e: SecurityException) {
                Log.w(TAG, "resume notice: ${e.javaClass.simpleName}")
            }
        }
    }

    @Volatile var mode = Mode.WATCH
        private set

    /** ปล่อยไมค์อยู่เพราะมีสาย / แอปอื่นใช้ */
    @Volatile var paused = false
        private set

    private val matcher = WakeMatcher(null)

    /** ตัวอย่างที่ได้ตอนสอน · แตะบนเธรดไมค์เท่านั้น */
    private val teach = ArrayList<Array<FloatArray>>()

    // 🔴 matcher ไม่ปลอดภัยข้ามเธรด · เธรดอื่นฝากคำสั่งไว้ตรงนี้ แล้วเธรดไมค์ทำเองตอนต้นรอบ ·
    // แตะตรง ๆ จากเธรดหลัก = รายการเฟรมถูกล้างกลางการคำนวณ แล้วบริการไมค์ตายทั้งตัว
    @Volatile private var wordChanged = true
    @Volatile private var clearTeach = false

    private var mic: Mic? = null
    private var lock: PowerManager.WakeLock? = null
    private var lockAt = 0L
    @Volatile private var replies: List<MediaPlayer> = emptyList()
    private var nextReply = 0
    private var tone: ToneGenerator? = null

    /** ก่อนเวลานี้ PCM ที่ส่งออกเป็นความเงียบ · เสียง "ขา" ของเธอเอง */
    @Volatile private var muteUntil = 0L
    @Volatile private var quietUntil = 0L

    private val forceClose = Runnable { backToRest() }
    private val unclaimed = Runnable {
        Log.w(TAG, "wake not claimed")
        backToRest()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        live = this
        ensureChannel(this)
        reloadWord()
        loadReplies()
        tone = try {
            ToneGenerator(AudioManager.STREAM_MUSIC, 80)
        } catch (e: RuntimeException) {
            null
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            onStopPressed()
            return START_NOT_STICKY
        }
        val asked = intent?.getStringExtra(EXTRA_MODE)?.let { runCatching { Mode.valueOf(it) }.getOrNull() }
        // intent ว่าง = ระบบปลุกกลับหลังฆ่าโปรเซส · รอฟังต่อถ้าเปิดไว้
        if (asked == null && !wantsWatch(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        mode = asked ?: Mode.WATCH
        val ready = readyCallback
        readyCallback = null
        if (!goForeground()) {
            ready?.invoke(false)
            postResume(this)
            stopSelf()
            return START_NOT_STICKY
        }
        NotificationManagerCompat.from(this).cancel(RESUME_NOTIFICATION)
        applyMode()
        if (mic == null) mic = Mic().also { it.start() }
        ready?.invoke(true)
        return START_STICKY
    }

    private fun goForeground(): Boolean = try {
        val n = build()
        if (Build.VERSION.SDK_INT >= 30) {
            startForeground(NOTIFICATION, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else {
            startForeground(NOTIFICATION, n)
        }
        true
    } catch (e: RuntimeException) {
        // Android 14+: เริ่มจากเบื้องหลัง · ไม่มีสิทธิ์ไมค์ · แจ้งเตือนถูกปิด
        Log.w(TAG, "startForeground: ${e.javaClass.simpleName}")
        false
    }

    private fun build(): Notification {
        val word = prefs(this).getString(KEY_WORD, null).orEmpty()
        val talking = mode == Mode.STREAM
        val title = getString(if (talking) R.string.listen_talking_title else R.string.listen_watch_title)
        val text = if (talking) getString(R.string.listen_talking_text)
        else getString(R.string.listen_watch_text, word.ifEmpty { getString(R.string.listen_default_word) })
        val stop = PendingIntent.getService(
            this, PI_STOP,
            Intent(this, ListenService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_listen)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openApp(this, PI_OPEN))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(R.drawable.ic_listen, getString(if (talking) R.string.listen_stop_talk else R.string.listen_stop_watch), stop)
            .build()
    }

    fun refresh() {
        try {
            NotificationManagerCompat.from(this).notify(NOTIFICATION, build())
        } catch (e: SecurityException) {
            Log.w(TAG, "refresh: ${e.javaClass.simpleName}")
        }
    }

    fun switchTo(m: Mode) {
        mode = m
        applyMode()
    }

    /** กลับสภาพพัก: รอคำเรียก หรือปิดบริการ */
    fun backToRest() {
        main.removeCallbacks(forceClose)
        main.removeCallbacks(unclaimed)
        quietUntil = SystemClock.elapsedRealtime() + QUIET_AFTER_CHAT_MS
        if (wantsWatch(this)) switchTo(Mode.WATCH) else stopNow()
    }

    fun claimed() {
        main.removeCallbacks(unclaimed)
    }

    fun beginTeach() {
        clearTeach = true
        switchTo(Mode.TEACH)
    }

    private fun applyMode() {
        reloadWord()
        val m = mode
        if (m == Mode.STREAM) {
            acquireLock()
        } else {
            releaseLock()
            mic?.clearBacklog()
        }
        refresh()
    }

    fun reloadWord() {
        wordChanged = true
    }

    private fun acquireLock() {
        val l = lock ?: (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "giggok:listen")
            .also {
                it.setReferenceCounted(false)
                lock = it
            }
        l.acquire(WAKE_LOCK_MS)
        lockAt = SystemClock.elapsedRealtime()
    }

    private fun releaseLock() {
        val l = lock ?: return
        if (l.isHeld) l.release()
    }

    private fun onStopPressed() {
        if (mode == Mode.WATCH) {
            // เจ้าของกดหยุดรอฟัง = ปิดจริง · เปิดแอปครั้งหน้าต้องไม่เปิดไมค์กลับเอง
            prefs(this).edit().putBoolean(KEY_WAKE, false).apply()
            events?.invoke("wakeOff", emptyMap())
            stopNow()
            return
        }
        events?.invoke("stop", emptyMap())
        // Dart ค้าง = ไมค์ต้องปิดอยู่ดี
        main.removeCallbacks(forceClose)
        main.postDelayed(forceClose, FORCE_CLOSE_MS)
    }

    fun stopNow() {
        main.removeCallbacks(forceClose)
        main.removeCallbacks(unclaimed)
        mic?.alive = false
        mic = null
        releaseLock()
        // onDestroy มาทีหลัง · ระหว่างนั้นคำสั่งใหม่ต้องเห็นว่าไม่มีบริการ ไม่ใช่สั่งตัวที่กำลังตาย (ไมค์ดับไปแล้ว)
        if (live === this) live = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        mic?.alive = false
        mic = null
        releaseLock()
        replies.forEach { runCatching { it.release() } }
        replies = emptyList()
        tone?.release()
        if (live === this) live = null
        super.onDestroy()
    }

    // ═══ ขานรับ ══════════════════════════════════════════════

    fun loadReplies() {
        val old = replies
        val loaded = ArrayList<MediaPlayer>()
        for (f in File(filesDir, REPLY_DIR).listFiles()?.sortedBy { it.name }.orEmpty()) {
            try {
                loaded.add(
                    MediaPlayer().apply {
                        setAudioAttributes(replyAttributes)
                        setDataSource(f.path)
                        prepare()
                    }
                )
            } catch (e: Exception) {
                Log.w(TAG, "reply: ${e.javaClass.simpleName}")
            }
        }
        replies = loaded
        old.forEach { runCatching { it.release() } }
    }

    /** ขาน · เตรียมไว้แล้วจึงดังทันที · ไม่มีไฟล์เสียง = เสียงสั้น ๆ ดีกว่าเงียบ · คืนความยาว */
    fun ack(): Long {
        val list = replies
        if (list.isEmpty()) {
            main.post { tone?.startTone(ToneGenerator.TONE_PROP_ACK, 180) }
            return 200L
        }
        val p = list[nextReply++ % list.size]
        main.post {
            try {
                p.seekTo(0)
                p.start()
            } catch (e: IllegalStateException) {
                Log.w(TAG, "ack: ${e.javaClass.simpleName}")
            }
        }
        // เรียกจากเธรดไมค์ · [loadReplies] ปล่อยตัวเก่าพร้อมกันได้ · เสียงขานพลาดต้องไม่ล้มทั้งแอป
        return try {
            p.duration.toLong().coerceIn(100L, 1500L)
        } catch (e: IllegalStateException) {
            200L
        }
    }

    private fun woke(now: Long) {
        Log.i(TAG, "wake score=${matcher.lastScore}")
        // ระบบปลุกบริการกลับโดยไม่มี Dart (Android เก่า) · ขานแล้วไม่มีใครฟัง = แย่กว่าไม่ขาน
        if (events == null) {
            postResume(this)
            return
        }
        mic?.clearBacklog()
        muteUntil = now + ack() + ACK_TAIL_MS
        switchTo(Mode.STREAM)
        main.postDelayed(unclaimed, CLAIM_LIMIT_MS)
        main.post { events?.invoke("wake", emptyMap()) }
    }

    /** ตัวอย่างหนึ่งช่วงเสียงตอนสอน · เสียงยาว/สั้นเกิน หรือไม่เหมือนตัวก่อน ๆ = บอกให้พูดใหม่ */
    private fun onTeachSample() {
        val seg = matcher.lastSegment
        if (seg == null) {
            main.post { events?.invoke("teach", mapOf("ok" to false, "why" to "length", "count" to teach.size)) }
            return
        }
        if (teach.size >= 2) {
            val spread = WakeMatcher.spread(teach)
            val best = teach.minOf { minOf(WakeMatcher.score(it, seg), WakeMatcher.score(seg, it)) }
            if (best > spread * 1.8f) {
                Log.i(TAG, "teach: unlike score=$best spread=$spread")
                main.post { events?.invoke("teach", mapOf("ok" to false, "why" to "unlike", "count" to teach.size)) }
                return
            }
        }
        teach.add(seg)
        val count = teach.size
        if (count < WakeMatcher.SAMPLES_NEEDED) {
            main.post { events?.invoke("teach", mapOf("ok" to true, "count" to count)) }
            return
        }
        val spread = WakeMatcher.spread(teach)
        Log.i(TAG, "teach: done spread=$spread")
        WakeWord(ArrayList(teach), spread).save(wordFile(this))
        teach.clear()
        main.post {
            events?.invoke("teach", mapOf("ok" to true, "count" to count, "done" to true))
            backToRest()
        }
    }

    /** มีสาย / แอปอื่นกำลังใช้ไมค์ · รอคำเรียกต้องหลีกทาง · ไม่งั้นอัดเสียงสายซ้อน และบางเครื่องทำให้อีกแอปเงียบ */
    private fun othersUsingMic(am: AudioManager, holding: Boolean): Boolean {
        if (am.mode != AudioManager.MODE_NORMAL) return true
        return am.activeRecordingConfigurations.size > (if (holding) 1 else 0)
    }

    private inner class Mic : Thread("mind-listen") {
        @Volatile var alive = true
        private var rec: AudioRecord? = null
        private var aec: AcousticEchoCanceler? = null
        private var ns: NoiseSuppressor? = null
        private val backlog = ArrayDeque<ByteArray>()
        private var chunk = ByteArray(CHUNK_BYTES)
        private var filled = 0

        @Volatile private var clearRequested = false

        fun clearBacklog() {
            clearRequested = true
        }

        private fun openRec(): AudioRecord? {
            val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            return try {
                val r = AudioRecord(
                    MediaRecorder.AudioSource.VOICE_RECOGNITION,
                    RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    maxOf(min, RATE)
                )
                if (r.state != AudioRecord.STATE_INITIALIZED) {
                    r.release()
                    return null
                }
                r.startRecording()
                if (r.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                    r.release()
                    return null
                }
                if (AcousticEchoCanceler.isAvailable()) aec = AcousticEchoCanceler.create(r.audioSessionId)
                if (NoiseSuppressor.isAvailable()) ns = NoiseSuppressor.create(r.audioSessionId)
                r
            } catch (e: RuntimeException) {
                // SecurityException รวมอยู่ในนี้ · ไม่มีสิทธิ์/ไมค์ถูกใช้อยู่
                Log.w(TAG, "open mic: ${e.javaClass.simpleName}")
                null
            }
        }

        private fun closeRec() {
            aec?.release()
            ns?.release()
            aec = null
            ns = null
            rec?.let {
                runCatching { it.stop() }
                it.release()
            }
            rec = null
        }

        private fun emit(bytes: ByteArray, now: Long) {
            if (now < muteUntil) bytes.fill(0)
            val out = sink
            if (out == null) {
                backlog.addLast(bytes)
                if (backlog.size > BACKLOG_CHUNKS) backlog.removeFirst()
                return
            }
            while (backlog.isNotEmpty()) out(backlog.removeFirst())
            out(bytes)
        }

        private fun stream(buf: ShortArray, got: Int, now: Long) {
            for (i in 0 until got) {
                val v = buf[i].toInt()
                chunk[filled++] = v.toByte()
                chunk[filled++] = (v shr 8).toByte()
                if (filled == chunk.size) {
                    emit(chunk, now)
                    chunk = ByteArray(CHUNK_BYTES)
                    filled = 0
                }
            }
        }

        override fun run() {
            // เธรดนี้ล้ม = ทั้งแอปล้ม รวมถึงสายที่คุยอยู่ · เสียไมค์อย่างเดียวพอ
            try {
                listen()
            } catch (e: RuntimeException) {
                Log.e(TAG, "mic thread: ${e.javaClass.simpleName}")
                lost()
            } finally {
                closeRec()
            }
        }

        private fun lost() {
            main.post {
                events?.invoke("micLost", emptyMap())
                postResume(this@ListenService)
                stopNow()
            }
        }

        private fun listen() {
            val am = getSystemService(AUDIO_SERVICE) as AudioManager
            val buf = ShortArray(READ)
            var checkedAt = 0L
            var failures = 0
            var lastMode: Mode? = null
            while (alive) {
                val m = mode
                val now = SystemClock.elapsedRealtime()
                if (clearRequested) {
                    clearRequested = false
                    backlog.clear()
                    filled = 0
                }
                if (clearTeach) {
                    clearTeach = false
                    teach.clear()
                }
                if (m != lastMode) {
                    lastMode = m
                    wordChanged = true
                    // เสียงจากลำโพงไม่มีตอนรอฟัง · เปิดเฉพาะตอนคุย ประหยัดไฟ
                    runCatching {
                        aec?.enabled = m == Mode.STREAM
                        ns?.enabled = m == Mode.STREAM
                    }
                }
                if (wordChanged) {
                    wordChanged = false
                    // ตอนสอน matcher ต้องไม่มีคำ · ไม่งั้นมันเลิกดูเสียงยาวแล้วตัวอย่างขาด
                    matcher.setWord(if (m == Mode.TEACH) null else WakeWord.load(wordFile(this@ListenService)))
                }
                if (now - checkedAt > 500) {
                    checkedAt = now
                    paused = m == Mode.WATCH && othersUsingMic(am, rec != null)
                    if (m == Mode.STREAM && now - lockAt > WAKE_LOCK_MS / 2) acquireLock()
                }
                if (paused) {
                    if (rec != null) {
                        closeRec()
                        matcher.reset()
                    }
                    SystemClock.sleep(300)
                    continue
                }
                if (rec == null) {
                    rec = openRec()
                    if (rec == null) {
                        if (++failures >= 10) {
                            Log.w(TAG, "mic unavailable")
                            lost()
                            return
                        }
                        SystemClock.sleep(1000)
                        continue
                    }
                    failures = 0
                    lastMode = null
                    continue
                }
                val got = rec!!.read(buf, 0, buf.size)
                if (got <= 0) {
                    Log.w(TAG, "read: $got")
                    closeRec()
                    continue
                }
                when (m) {
                    Mode.STREAM -> stream(buf, got, now)
                    Mode.WATCH -> {
                        if (matcher.feed(buf, got) == WakeMatcher.Hit.WORD && now >= quietUntil) woke(now)
                    }
                    Mode.TEACH -> {
                        if (matcher.feed(buf, got) == WakeMatcher.Hit.ENDED) onTeachSample()
                    }
                }
            }
        }
    }
}

/**
 * รีสตาร์ตเครื่อง/อัปเดตแอปแล้วไมค์ไม่กลับมาเอง (Android ห้ามเริ่มไมค์จากเบื้องหลัง) ·
 * เจ้าของที่เปิดรอคำเรียกไว้ต้องรู้ ไม่ใช่เรียกแล้วเธอเงียบไปเฉย ๆ
 */
class ListenBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> ListenService.postResume(context)
        }
    }
}
