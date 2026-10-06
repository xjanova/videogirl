package com.xjanova.videogirl

import android.Manifest
import android.app.NotificationManager
import android.app.NotificationChannel
import android.app.role.RoleManager
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.CalendarContract
import android.provider.Settings
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * ช่อง `giggok/system` ส่วนที่**ไม่ต้องมีจอ** — ใช้ได้ทั้งตอนแอปเปิดอยู่ และตอนที่
 * ตัวเธอถูกปลุกขึ้นมาเบื้องหลังเพื่อคุยในสาย (ดู [MindEngine])
 *
 * ## 🔴 ทำไมแยกออกจาก MainActivity
 *
 * เดิมทั้งช่องอยู่ใน MainActivity · แอปถูกระบบปิด (vivo/OPPO/Xiaomi ปิดเก่งมาก)
 * แล้วสายเข้าตอนจอล็อก = ไม่มี Dart ให้คุย เธอจึง**ไม่รับสายเลย** · เจ้าของ:
 * "ไม่ยอมรับสายเองเลย" · ตอนนี้จอสายปลุก Dart ขึ้นมาเองระหว่างกริ่งดัง ซึ่งไม่มี
 * Activity · ทุกอย่างที่ Dart ต้องใช้ตอนเปิดตัวและตอนคุยในสายจึงต้องตอบได้ด้วย
 * Context อย่างเดียว · ของที่ต้องมีจอจริง (ขอสิทธิ์ เปิดหน้าตั้งค่า พับแอป)
 * ยังอยู่ใน MainActivity ซึ่งส่งต่อทุกอย่างที่เหลือมาที่นี่
 */
class SystemBridge(context: Context) {

    private val context: Context = context.applicationContext
    private val calls = CallBridge(this.context)
    private val main = Handler(Looper.getMainLooper())

    /// ช่องสำหรับ **ยิงกลับ** หา Dart ตอนสถานะสายเปลี่ยน
    private var channel: MethodChannel? = null
    private var phoneListener: Any? = null

    /** ผูกกับ engine · ตั้ง handler ของตัวเองด้วย (ใช้ตอนไม่มี Activity) */
    fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (!handle(call, result)) result.notImplemented()
            }
        }
    }

    /** คืน handler ให้ตัวเองอีกครั้ง — ตอน Activity ที่เคยรับช่วงไปถูกทำลาย */
    fun reclaim(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (!handle(call, result)) result.notImplemented()
        }
    }

    private fun granted(permission: String) =
        ContextCompat.checkSelfPermission(context, permission) ==
            PackageManager.PERMISSION_GRANTED

    /** ตอบได้ = true · ไม่ใช่ของช่องนี้ = false (ผู้เรียกตัดสินใจเอง) */
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "status" -> result.success(if (granted(Manifest.permission.CAMERA)) GRANTED else DENIED)
            "batteryExempt" -> result.success(batteryExempt())
            "notifyGranted" -> result.success(notifyGranted())
            "micGranted" -> result.success(granted(Manifest.permission.RECORD_AUDIO))
            "calendarGranted" -> result.success(granted(Manifest.permission.READ_CALENDAR))
            "readCalendar" -> readCalendar(
                (call.argument<Number>("from") ?: 0).toLong(),
                (call.argument<Number>("to") ?: 0).toLong(),
                result
            )
            "callGranted" -> result.success(calls.canReadCalls())
            "contactsGranted" -> result.success(calls.canReadContacts())
            "answerGranted" -> result.success(calls.canAnswer())
            "recentCalls" ->
                result.success(calls.recentCalls(call.argument<Int>("limit") ?: 30))
            "answerCall" -> result.success(calls.answer())
            "hangUp" -> result.success(calls.hangUp())
            "watchCalls" -> {
                watchCalls()
                result.success(true)
            }
            "isDefaultDialer" -> result.success(isDefaultDialer(context))
            "callInfo" -> result.success(MindInCallService.callInfo(context))
            "mindAnswer" -> result.success(
                MindInCallService.mindAnswer(
                    context,
                    call.argument<String>("stream") ?: CallAudio.STREAM_CALL
                )
            )
            "mindHandOver" -> {
                MindInCallService.handOver(context)
                result.success(true)
            }
            "callSpeak" -> callSpeak(
                call.argument<String>("path"),
                call.argument<String>("stream"),
                result
            )
            "mediaVolume" -> result.success(mediaVolume())
            "callStopSpeak" -> {
                CallAudio.stop()
                result.success(true)
            }
            "callEndAudio" -> {
                CallAudio.close(context)
                result.success(true)
            }
            "callDisconnect" -> result.success(MindInCallService.disconnect())
            "allFilesGranted" -> result.success(allFilesGranted())
            "deviceIds" -> result.success(deviceIds())
            "notifyCallNote" -> result.success(
                notifyCallNote(call.argument<String>("title"), call.argument<String>("body"))
            )
            "canInstall" -> result.success(canInstall())
            // ตอนนี้มีจอให้คนเห็นไหม · ไม่มี = ตัวเธอถูกปลุกมาคุยในสายเบื้องหลัง
            "hasScreen" -> result.success(false)
            "lastAutoAnswer" -> result.success(MindPrefs.lastAutoAnswer(context))
            // ── น้องมายโทรออกแทนเจ้าของ · เจ้าของกดยืนยันในแอปแล้วเท่านั้น ──
            // คืน null = กดโทรแล้ว · สตริง = เหตุผลที่โทรไม่ได้ (bad_number/blocked/not_dialer/busy/no_permission)
            "mindPlaceCall" -> result.success(
                MindInCallService.placeMindCall(context, call.argument<String>("number") ?: "")
            )
            "findContacts" -> result.success(calls.findContacts(call.argument<String>("name") ?: ""))
            // ── เสียงสดของเธอ (OpenAI Realtime) · ดู CallAudio.liveStart ──
            "liveAudioStart" -> result.success(
                CallAudio.liveStart(call.argument<String>("stream") ?: CallAudio.STREAM_CALL)
            )
            "liveAudioWrite" -> {
                call.argument<ByteArray>("pcm")?.let { CallAudio.liveWrite(it) }
                result.success(true)
            }
            "liveAudioPending" -> result.success(CallAudio.livePendingMs())
            "liveAudioClear" -> {
                CallAudio.liveClear(call.argument<String>("stream") ?: CallAudio.STREAM_CALL)
                result.success(true)
            }
            "liveAudioStop" -> {
                CallAudio.liveStop()
                result.success(true)
            }
            // ให้เธอได้ยินปลายสาย · ดู MindAccessibility
            "accessibilityOn" -> result.success(MindAccessibility.enabled(context))
            // เปิดฟังเสียงสนทนาที่บันทึกไว้ (ไม่ใช่ระหว่างสาย · เสียงสื่อธรรมดา)
            "playAudioFile" -> playFile(call.argument<String>("path"), result)
            "stopAudioFile" -> {
                stopFile()
                result.success(true)
            }
            else -> return false
        }
        return true
    }

    /**
     * เล่นเสียงเธอออกลำโพงให้ไมค์รับเข้าสาย แล้วตอบกลับ**เมื่อเล่นจบ**
     *
     * 🔴 ตอบตอนเริ่มเล่นไม่ได้ · ฝั่ง Dart ใช้ค่าที่คืนมาเป็นสัญญาณว่า
     * "ถึงตาปลายสายพูดแล้ว" ถ้าตอบทันที เธอจะเริ่มฟังตั้งแต่ตัวเองยังพูดอยู่
     * แล้วได้ยินเสียงตัวเองกลับเข้ามาเป็นคำถามของปลายสาย
     *
     * [CallAudio.play] รับประกันว่าเรียก onDone ครั้งเดียวเสมอ ทั้งตอนจบปกติ
     * ตอนพัง และตอนถูกสั่งหยุดกลางคัน — ซึ่งจำเป็น เพราะ MethodChannel.Result
     * ตอบซ้ำแล้วโยน IllegalStateException ทิ้งทั้ง engine
     */
    private fun callSpeak(path: String?, stream: String?, result: MethodChannel.Result) {
        if (path.isNullOrEmpty()) {
            result.success(false)
            return
        }
        CallAudio.play(context, path, stream ?: CallAudio.STREAM_CALL) { ok ->
            main.post { result.success(ok) }
        }
    }

    private var filePlayer: android.media.MediaPlayer? = null
    private var fileDone: MethodChannel.Result? = null

    /**
     * เล่นไฟล์เสียงสนทนาที่บันทึกไว้ · ตอบกลับเมื่อเล่นจบ (true) หรือถูกหยุด/พัง (false)
     *
     * แยกจาก [CallAudio] โดยตั้งใจ · ตัวนั้นเป็นเสียงเธอ**ในสาย** (ช่องเสียงสาย
     * เร่งเสียงสุด) ตัวนี้คือเจ้าของฟังย้อนหลังด้วยเสียงสื่อธรรมดา
     */
    private fun playFile(path: String?, result: MethodChannel.Result) {
        stopFile()
        if (path.isNullOrEmpty() || !java.io.File(path).exists()) {
            result.success(false)
            return
        }
        fileDone = result
        try {
            val mp = android.media.MediaPlayer()
            filePlayer = mp
            mp.setAudioAttributes(
                android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_MEDIA)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            mp.setDataSource(path)
            mp.setOnCompletionListener { finishFile(true) }
            mp.setOnErrorListener { _, _, _ -> finishFile(false); true }
            mp.setOnPreparedListener { it.start() }
            mp.prepareAsync()
        } catch (e: Exception) {
            finishFile(false)
        }
    }

    private fun stopFile() = finishFile(false)

    /** ตอบครั้งเดียวเสมอ · Result ที่ตอบซ้ำโยนทิ้งทั้ง engine */
    private fun finishFile(ok: Boolean) {
        filePlayer?.let {
            try {
                it.release()
            } catch (e: Exception) {
                // ปล่อยซ้ำ — ไม่ใช่เรื่องที่ต้องพัง
            }
        }
        filePlayer = null
        val r = fileDone
        fileDone = null
        r?.success(ok)
    }

    /// ระดับเสียงสื่อตอนนี้ · {now, max} — เสียงเธอออกช่องนี้ทั้งจากเวทีและทางสำรอง
    private fun mediaVolume(): Map<String, Int>? {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return null
        return try {
            mapOf(
                "now" to am.getStreamVolume(AudioManager.STREAM_MUSIC),
                "max" to am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            )
        } catch (e: Exception) {
            null
        }
    }

    /// 🔴 ตัวชี้ขาดว่างานเบื้องหลังจะเชื่อถือได้ไหม
    ///
    /// ไม่ได้ยกเว้น = ระบบหรี่ให้ตื่นทุก 9–15 นาทีแทนที่จะเป็นตามที่ตั้งไว้
    /// และบาง ROM (Xiaomi/Huawei/OPPO) ฆ่าทิ้งเลย · ประกาศใน manifest
    /// อย่างเดียวไม่พอ ผู้ใช้ต้องกดยอมรับเองเท่านั้น
    fun batteryExempt(): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    /// Android 13+ การแจ้งเตือนเป็นสิทธิ์ที่ต้องขอ · ไม่ได้ขอ = บริการรันอยู่จริง
    /// แต่ผู้ใช้ไม่เห็นอะไรเลย แล้วจะคิดว่ามันไม่ทำงาน
    fun notifyGranted(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return granted("android.permission.POST_NOTIFICATIONS")
    }

    /**
     * ติดตั้ง APK ที่โหลดมาเองได้ไหม
     *
     * 🔴 ถ้าไม่ได้ auto-update จะโหลดไฟล์จนจบ (หลายร้อยเมก) แล้วค่อยล้ม
     * ตรงขั้นสุดท้าย · ต้องเช็ค**ก่อน**เริ่มโหลด ไม่ใช่ค้นพบตอนจบ
     */
    fun canInstall(): Boolean =
        if (Build.VERSION.SDK_INT >= 26) context.packageManager.canRequestPackageInstalls() else true

    /**
     * เข้าถึงไฟล์ทั้งเครื่องได้ไหม — ใช้เก็บ**สำเนาที่รอดจากการถอนแอป**เท่านั้น
     *
     * Android 10 ลงมาไม่มีสิทธิ์ตัวนี้ ใช้ WRITE_EXTERNAL_STORAGE แทน
     */
    fun allFilesGranted(): Boolean =
        if (Build.VERSION.SDK_INT >= 30) {
            Environment.isExternalStorageManager()
        } else {
            granted(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }

    /**
     * รหัสเครื่องสำหรับขอไลเซนส์ฟรีจาก xman studio — **แฮช SHA-256 แล้วเสมอ**
     *
     * แบบเดียวกับแอปพี่น้อง (Tping/LocalVPN) ที่หลังบ้านใช้จับคู่ไลเซนส์กับ
     * เครื่อง: Widevine device id (อยู่รอดการถอนแอป) + ANDROID_ID (อยู่รอดการ
     * ลงใหม่ด้วยกุญแจเซ็นเดิม) · ส่งเฉพาะแฮช ไม่ส่งค่าดิบ ค่าที่ได้จึงย้อนกลับไป
     * เป็นรหัสจริงของเครื่องไม่ได้ และใช้กับแอปอื่นไม่ได้ (ผสมชื่อแอปไว้)
     *
     * ค่าใดอ่านไม่ได้ (บางเครื่องไม่มี Widevine) ก็ส่ง null ของตัวนั้น
     */
    private fun deviceIds(): Map<String, String?> {
        fun sha(v: String): String = java.security.MessageDigest.getInstance("SHA-256")
            .digest("giggok:$v".toByteArray())
            .joinToString("") { "%02x".format(it) }

        val drm = try {
            val uuid = java.util.UUID.fromString("edef8ba9-79d6-4ace-a3c8-27dcd51d21ed") // Widevine
            val md = android.media.MediaDrm(uuid)
            try {
                val bytes = md.getPropertyByteArray(android.media.MediaDrm.PROPERTY_DEVICE_UNIQUE_ID)
                bytes.joinToString("") { "%02x".format(it) }
            } finally {
                if (Build.VERSION.SDK_INT >= 28) md.close() else @Suppress("DEPRECATION") md.release()
            }
        } catch (e: Throwable) {
            null
        }
        val android = try {
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
        } catch (e: Throwable) {
            null
        }
        return mapOf(
            "drm" to drm?.takeIf { it.isNotEmpty() }?.let(::sha),
            "android" to android?.takeIf { it.isNotEmpty() }?.let(::sha),
        )
    }

    /**
     * แจ้งเจ้าของว่ามายด์รับสายแทนและรับฝากเรื่องไว้
     *
     * ช่องแยกจากของงานเบื้องหลัง เพราะความสำคัญต่างกัน: ตัวนั้นเงียบ ค้างอยู่
     * ตลอด · ตัวนี้คือ "มีคนฝากเรื่องไว้" ต้องดังและเด้งให้เห็น · และเจ้าของ
     * ปิดอย่างใดอย่างหนึ่งในตั้งค่าของเครื่องได้โดยไม่กระทบอีกอย่าง
     *
     * ไม่ได้สิทธิ์แจ้งเตือน = คืน false เงียบ ๆ · บันทึกยังอยู่ในไทม์ไลน์ครบ
     */
    private fun notifyCallNote(title: String?, body: String?): Boolean {
        if (!notifyGranted()) return false
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return false
        if (nm.getNotificationChannel(CALL_NOTE_CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CALL_NOTE_CHANNEL,
                    context.getString(R.string.call_note_channel),
                    NotificationManager.IMPORTANCE_HIGH,
                )
            )
        }
        val open = android.app.PendingIntent.getActivity(
            context, 0,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                android.app.PendingIntent.FLAG_IMMUTABLE,
        )
        val text = body.orEmpty()
        val n = androidx.core.app.NotificationCompat.Builder(context, CALL_NOTE_CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title.orEmpty())
            .setContentText(text)
            .setStyle(androidx.core.app.NotificationCompat.BigTextStyle().bigText(text))
            .setCategory(androidx.core.app.NotificationCompat.CATEGORY_MESSAGE)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        return try {
            // id ตามเวลา = แต่ละสายเป็นแจ้งเตือนของตัวเอง ไม่ทับกัน
            nm.notify((System.currentTimeMillis() / 1000).toInt(), n)
            true
        } catch (e: SecurityException) {
            false
        }
    }

    /**
     * อ่านนัดจากปฏิทินของเครื่องในช่วงเวลาที่ขอมา
     *
     * ใช้ `Instances` ไม่ใช่ `Events` เพราะนัดที่เกิดซ้ำทุกสัปดาห์มีแถวเดียว
     * ใน `Events` แต่มีทุกครั้งใน `Instances` · ถามจาก `Events` ตรง ๆ จะได้
     * ประชุมประจำสัปดาห์มาแค่ครั้งแรกครั้งเดียว แล้วสัปดาห์อื่นหายหมด
     * โดยไม่มีอะไรบอกว่าขาด
     *
     * 🔴 ทำในเธรดอื่น ไม่ใช่เธรดหลัก · ContentResolver ของปฏิทินช้าได้จริง
     * บนเครื่องที่ซิงก์หลายบัญชี และ MethodChannel เรียกบนเธรด UI
     */
    private fun readCalendar(from: Long, to: Long, result: MethodChannel.Result) {
        if (!granted(Manifest.permission.READ_CALENDAR)) {
            result.success(null)
            return
        }
        if (to <= from) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }

        Thread {
            val events = try {
                queryInstances(from, to)
            } catch (e: Exception) {
                // ปฏิทินอ่านไม่ได้ไม่ควรทำให้ทั้งแท็บพัง — คืน null แปลว่า
                // "ถามไม่สำเร็จ" ซึ่งต่างจาก emptyList ที่แปลว่า "ไม่มีนัด"
                null
            }
            main.post { result.success(events) }
        }.start()
    }

    private fun queryInstances(from: Long, to: Long): List<Map<String, Any?>> {
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().let {
            ContentUris.appendId(it, from)
            ContentUris.appendId(it, to)
            it.build()
        }
        val cols = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.CALENDAR_DISPLAY_NAME,
            CalendarContract.Instances.DISPLAY_COLOR,
            CalendarContract.Instances.SELF_ATTENDEE_STATUS
        )

        val out = ArrayList<Map<String, Any?>>()
        context.contentResolver.query(uri, cols, null, null, CalendarContract.Instances.BEGIN + " ASC")
            ?.use { c ->
                while (c.moveToNext()) {
                    // นัดที่เจ้าของกดปฏิเสธไปแล้ว ไม่ใช่ตารางของเขา
                    val status = c.getInt(8)
                    if (status == CalendarContract.Attendees.ATTENDEE_STATUS_DECLINED) continue

                    out.add(
                        mapOf(
                            "id" to c.getLong(0),
                            "title" to (c.getString(1) ?: ""),
                            "begin" to c.getLong(2),
                            "end" to c.getLong(3),
                            "allDay" to (c.getInt(4) == 1),
                            "location" to c.getString(5),
                            "calendar" to c.getString(6),
                            "color" to c.getInt(7)
                        )
                    )
                }
            }
        return out
    }

    /**
     * เฝ้าสถานะสาย แล้วบอก Dart ทุกครั้งที่เปลี่ยน
     *
     * 🔴 เบอร์ที่ได้จากตรงนี้ **ว่างเปล่าบน Android 9+ ถ้าไม่มี READ_CALL_LOG**
     * และไม่มี error อะไรบอก · ฝั่ง Dart จึงต้องเผื่อเบอร์ว่างเสมอ และไปอ่าน
     * จากบันทึกการโทรหลังสายจบแทน
     *
     * ผูกกับ engine ไม่ใช่กับ Activity · Activity ถูกทำลายแล้ว engine ยังอยู่
     * (ดู [MindEngine]) สัญญาณสายต้องไปถึง Dart ต่อ
     */
    private fun watchCalls() {
        if (phoneListener != null) return
        val tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager ?: return

        try {
            if (Build.VERSION.SDK_INT >= 31) {
                val cb = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                    override fun onCallStateChanged(state: Int) = sendCallState(state, null)
                }
                tm.registerTelephonyCallback(context.mainExecutor, cb)
                phoneListener = cb
            } else {
                @Suppress("DEPRECATION")
                val l = object : PhoneStateListener() {
                    override fun onCallStateChanged(state: Int, phoneNumber: String?) =
                        sendCallState(state, phoneNumber)
                }
                @Suppress("DEPRECATION")
                tm.listen(l, PhoneStateListener.LISTEN_CALL_STATE)
                phoneListener = l
            }
        } catch (e: SecurityException) {
            // ยังไม่ได้สิทธิ์สถานะโทรศัพท์ (Android 12+ บังคับ) · ไม่มีสัญญาณก็ยังถามเอาได้
        }
    }

    private fun sendCallState(state: Int, number: String?) {
        channel?.invokeMethod(
            "onCallState",
            mapOf(
                "state" to state,
                "number" to number,
                "name" to calls.nameFor(number)
            )
        )
    }

    companion object {
        const val CHANNEL = "giggok/system"
        const val GRANTED = "granted"
        const val DENIED = "denied"
        const val BLOCKED = "blocked"

        /// แจ้งเตือน "มายด์รับสายแทนและรับฝากเรื่องไว้"
        private const val CALL_NOTE_CHANNEL = "call_notes"

        /**
         * แอปนี้เป็นแอปโทรศัพท์หลักของเครื่องอยู่หรือเปล่า
         *
         * ถามผ่าน RoleManager บน Android 10 ขึ้นไป ที่เหลือถาม TelecomManager
         * สองทางนี้ตอบเรื่องเดียวกัน แต่ทางเก่าถูกเลิกใช้ไปแล้วบนรุ่นใหม่
         */
        @JvmStatic
        fun isDefaultDialer(context: Context): Boolean {
            if (Build.VERSION.SDK_INT >= 29) {
                val rm = context.getSystemService(RoleManager::class.java) ?: return false
                return rm.isRoleHeld(RoleManager.ROLE_DIALER)
            }
            val tm = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
                ?: return false
            return tm.defaultDialerPackage == context.packageName
        }
    }
}
