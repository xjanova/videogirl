package com.xjanova.videogirl.sos

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.TriggerEvent
import android.hardware.TriggerEventListener
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.telecom.Call
import android.telecom.TelecomManager
import android.telephony.PhoneNumberUtils
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.xjanova.videogirl.MainActivity
import com.xjanova.videogirl.MindInCallService
import com.xjanova.videogirl.R
import com.xjanova.videogirl.SystemBridge
import kotlin.math.sqrt

/**
 * ระบบแจ้งเหตุฉุกเฉินของมายด์ · ทำงานเองทั้งหมดโดยไม่ต้องมี Dart หรือหน้าจอ
 *
 * เจ้าของ: "ถ้ามีการสะเทือนรุนแรงให้คาดไว้ก่อนว่าน่าจะเกิดอุบัติเหตุ ให้เธอส่งเสียงเรียกหาเจ้าของก่อน ว่าเป็นอะไร
 * ได้ยินเธอไหม และถ้าไม่มีการตอบภายในเวลาที่กำหนด ให้เริ่มกระบวนการแจ้งเหตุฉุกเฉินทันที แต่หยุดกระบวนการได้ถ้าเรา
 * แตะปุ่มหยุดทัน"
 *
 * ## ลำดับ
 *
 * แรงกระแทก → เรียกเจ้าของ (เสียงดังสุด สั่น เต็มจอบนจอล็อก) → นับถอยหลัง →
 * ตอบ "ไม่เป็นไร"/กดหยุด = ยกเลิก · ขอช่วย/ไม่ตอบ = [dispatch]
 *
 * ## 🔴 ทางเปิดข้อยกเว้นเบอร์ฉุกเฉินมีทางเดียว
 *
 * [OutgoingRules][com.xjanova.videogirl.OutgoingRules] ยังกันการโทรทั่วไปเหมือนเดิม · ที่นี่กด `placeCall` เองเฉพาะเบอร์ที่มาจาก
 * [SosRouter] ซึ่งมาจากแผนที่เจ้าของตั้ง · ช่อง Dart ไม่มีคำสั่งไหนรับเบอร์ · โมเดลสั่งเบอร์ไม่ได้ ไม่ว่าจะถูกหลอกแค่ไหน
 *
 * ## 🔴 ถ้าระบบปิดแอป ระบบนี้หยุดด้วย
 *
 * บริการอยู่ในโปรเซสแอป · vivo ปิดแอปเบื้องหลังเก่งมาก · ต้องตั้งยกเว้นแบต · ปุ่ม "ออกจากแอป" หยุดระบบนี้ (บอกทางแจ้งเตือน)
 */
class SosService : Service(), SensorEventListener {

    enum class Phase { IDLE, ALERT, DISPATCH, DONE }

    /** ภาพรวมที่จอและ Dart อ่าน · 🔒 ไม่มีพิกัดและข้อมูลสุขภาพ ขึ้นจอล็อกได้ */
    data class Snapshot(
        val phase: Phase,
        val kind: SosKind?,
        val drill: Boolean,
        val rehearsal: Boolean,
        val secondsLeft: Int,
        val low: Boolean,
        val sent: List<SosSent>,
        val pending: List<SosStep>,
        val cancelled: Boolean,
        val voicePath: String,
        val silent: Boolean = false,
    )

    /** 🔴 ถือแผนของตัวเอง · ลบหรือบันทึกแผนใหม่กลางเหตุต้องไม่ทำให้เหตุที่กำลังเดินค้าง */
    private inner class Incident(
        val plan: SosPlan,
        val kind: SosKind,
        val trigger: SosTrigger,
        var confidence: SosConfidence,
        val drill: Boolean,
        var rehearsal: Boolean,
        val deadline: Long,
        val startedAt: Long,
        /** แจ้งเงียบ · ไม่มีเสียง จอ สั่น หรือแจ้งเตือนที่คนข้าง ๆ เห็น · ดู [begin] */
        var silent: Boolean,
    ) {
        val abroad = isAbroad()
        val sent = ArrayList<SosSent>()
        var steps: ArrayDeque<SosStep> = ArrayDeque()
        var cancelled = false
        var ownerBusy = false
        var busySince = 0L
        val silentCallAt = SystemClock.elapsedRealtime() + SILENT_CALL_WAIT_MS
    }

    private val main = Handler(Looper.getMainLooper())
    private lateinit var locator: SosLocator
    private lateinit var voice: SosVoice
    private var sensors: SensorManager? = null
    private var accel: Sensor? = null
    private var motion: Sensor? = null
    private var sensorThread: HandlerThread? = null
    private var wake: PowerManager.WakeLock? = null

    private var plan: SosPlan? = null
    private var detector = ImpactDetector()
    private var incident: Incident? = null
    private var phase = Phase.IDLE
    private var sampling = false
    private var sampleUntil = 0L

    private var armedAt = 0L
    private var tripFrom = 0L
    private var tripTotal = 0L
    private var batteryAtArm = -1

    // ── วงจรชีวิต ──

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        live = this
        locator = SosLocator(this)
        voice = SosVoice(this)
        sensors = getSystemService(SensorManager::class.java)
        accel = sensors?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        motion = sensors?.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION)
        locator.onSpeed = { kmh ->
            detector.onSpeed(SystemClock.elapsedRealtime(), kmh)
            // ยังเดินทางอยู่ = เซ็นเซอร์ต้องติดต่อ
            if (kmh >= MOVING_KMH) sampleUntil = SystemClock.elapsedRealtime() + TRIP_MS
        }
        ensureChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 🔴 startForeground ก่อนอย่างอื่น · startForegroundService ให้เวลาห้าวินาที ไม่งั้นระบบฆ่าทั้งแอป
        // ล้มระหว่างมีเหตุ = เดินเหตุต่อ · การหยุดบริการตรงนี้คือทิ้งเหตุจริง
        if (!goForeground() && incident == null) {
            postResume(applicationContext)
            stopSelf()
            return START_NOT_STICKY
        }
        val action = intent?.action
        val first = plan == null
        when (action) {
            ACTION_STOP -> stopIncident()
            ACTION_HELP -> incident?.let { askHelp(it) }
            ACTION_TRIGGER -> {
                val kind = intent.getStringExtra(EXTRA_KIND)?.let { runCatching { SosKind.valueOf(it) }.getOrNull() }
                begin(
                    kind ?: SosKind.OTHER,
                    if (intent.getBooleanExtra(EXTRA_VOICE, false)) SosTrigger.VOICE else SosTrigger.BUTTON,
                    SosConfidence.HIGH,
                    drill = intent.getBooleanExtra(EXTRA_DRILL, false),
                    silent = intent.getBooleanExtra(EXTRA_SILENT, false),
                )
            }
        }
        // บริการที่เริ่มด้วยปุ่มหรือคำสั่งเสียงก็ต้องเฝ้าการเคลื่อนไหวต่อเหมือนกัน
        if (first || action == null || action == ACTION_SYNC) applyPlan()
        return START_STICKY
    }

    private fun applyPlan() {
        val p = SosStore.plan(this)
        plan = p
        if (p == null || !p.armed) {
            if (incident == null) quit()
            return
        }
        detector = ImpactDetector(ImpactDetector.Config.forLevel(p.sensitivity))
        if (armedAt == 0L) {
            armedAt = SystemClock.elapsedRealtime()
            batteryAtArm = batteryPercent()
        }
        locator.lastKnown()
        armMotion()
        refresh()
        if (incident == null) {
            resumeLive()
            checkVoice()
        }
    }

    /** ระบบปิดแอปกลางเหตุ · เรียกเจ้าของใหม่แล้วนับสั้น ๆ · ส่ง SMS ซ้ำดีกว่าไม่มีใครรู้ */
    private fun resumeLive() {
        val l = SosStore.live(this) ?: return
        val age = System.currentTimeMillis() - l.atMs
        if (age !in 0..RESUME_MAX_MS) {
            SosStore.clearLive(this)
            return
        }
        // 🔴 เหตุเงียบต้องฟื้นแบบเงียบ · เรียกเสียงดังตรงนี้คือบอกคนร้ายว่าเจ้าของกำลังแจ้งเหตุ
        begin(l.kind, l.how, l.confidence, drill = false, silent = l.silent, resumedFrom = l.atMs)
    }

    /** หน้าตั้งค่าบอกเจ้าของล่วงหน้า · เครื่องไม่มีเสียงไทยรู้ตอนโทรหาเจ้าหน้าที่ก็สายไปแล้ว */
    private fun checkVoice() {
        voice.prepare {
            SosStore.thaiVoice(this, voice.hasThai)
            if (incident == null) voice.release()
        }
    }

    private fun quit() {
        recordBattery()
        stopSampling()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        recordBattery()
        // 🔴 ตัวจับการเคลื่อนไหวไม่หยุดเองตอนบริการจบ · ไม่ยกเลิก = ตัวที่ถูกทำลายแล้วตื่นมาเปิดเซ็นเซอร์และแจ้งเหตุได้
        motion?.let { sensors?.cancelTriggerSensor(trigger, it) }
        plan = null
        stopSampling()
        locator.close()
        voice.close()
        main.removeCallbacksAndMessages(null)
        if (live === this) live = null
        super.onDestroy()
    }

    /** วัดแบตจริง · เจ้าของตัดสินใจได้จากตัวเลขว่าคุ้มเปิดไว้ไหม */
    private fun recordBattery() {
        if (armedAt == 0L) return
        val now = SystemClock.elapsedRealtime()
        val trip = tripTotal + if (tripFrom != 0L) now - tripFrom else 0L
        val drop = if (batteryAtArm >= 0) (batteryAtArm - batteryPercent()).coerceAtLeast(0) else 0
        SosStore.addBattery(this, now - armedAt, trip, drop)
        armedAt = 0L
        tripTotal = 0L
        tripFrom = if (tripFrom != 0L) now else 0L
    }

    private fun batteryPercent(): Int =
        getSystemService(BatteryManager::class.java)?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1

    private fun goForeground(): Boolean = try {
        val n = currentNotice()
        if (Build.VERSION.SDK_INT >= 34) {
            val fine = has(Manifest.permission.ACCESS_FINE_LOCATION) || has(Manifest.permission.ACCESS_COARSE_LOCATION)
            val type = if (fine) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            else ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            startForeground(NOTIFICATION, n, type)
        } else {
            startForeground(NOTIFICATION, n)
        }
        true
    } catch (e: RuntimeException) {
        // เริ่มตำแหน่งเบื้องหลังไม่ได้ (ไม่มีสิทธิ์ตลอดเวลา) · ลองเป็นบริการธรรมดา ไม่งั้นระบบ SOS ดับเงียบ
        android.util.Log.w("GigGokSos", "foreground: ${e.javaClass.simpleName}")
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIFICATION, currentNotice(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
                true
            } else {
                false
            }
        } catch (e2: RuntimeException) {
            false
        }
    }

    private fun has(p: String) = ContextCompat.checkSelfPermission(this, p) == PackageManager.PERMISSION_GRANTED

    // ── เซ็นเซอร์ ──
    //
    // ตั้งนิ่ง: เหลือแค่ตัวจับการเคลื่อนไหวของชิป (กินไฟน้อย ปลุกแอปได้แม้จอดับ) ·
    // เริ่มเดินทาง: เปิดความเร่ง 50 Hz + GPS · เครื่องไม่มีตัวจับ = เปิดความเร่งตลอด (กินแบตกว่า ตัวเลขบอกในหน้าตั้งค่า)

    private val trigger = object : TriggerEventListener() {
        override fun onTrigger(event: TriggerEvent?) {
            startSampling()
            armMotion()
        }
    }

    private fun armMotion() {
        val m = motion
        if (m == null) {
            startSampling(forever = true)
            return
        }
        sensors?.requestTriggerSensor(trigger, m)
    }

    @SuppressLint("WakelockTimeout")
    private fun startSampling(forever: Boolean = false) {
        sampleUntil = if (forever) Long.MAX_VALUE else SystemClock.elapsedRealtime() + TRIP_MS
        if (sampling) return
        val s = sensors ?: return
        val a = accel ?: return
        sampling = true
        tripFrom = SystemClock.elapsedRealtime()
        val pm = getSystemService(PowerManager::class.java)
        wake = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "giggok:sos")?.apply {
            setReferenceCounted(false)
            acquire(WAKE_MS)
        }
        val t = HandlerThread("giggok-sos-sensor").also { it.start() }
        sensorThread = t
        s.registerListener(this, a, SAMPLE_US, Handler(t.looper))
        locator.track(true)
        main.postDelayed(sampleCheck, CHECK_MS)
    }

    private val sampleCheck = object : Runnable {
        override fun run() {
            if (!sampling) return
            wake?.acquire(WAKE_MS)
            if (SystemClock.elapsedRealtime() >= sampleUntil && !detector.busy && incident == null) {
                stopSampling()
            } else {
                main.postDelayed(this, CHECK_MS)
            }
        }
    }

    private fun stopSampling() {
        if (!sampling) return
        sampling = false
        sensors?.unregisterListener(this)
        sensorThread?.quitSafely()
        sensorThread = null
        locator.track(false)
        main.removeCallbacks(sampleCheck)
        wake?.let { if (it.isHeld) it.release() }
        wake = null
        if (tripFrom != 0L) tripTotal += SystemClock.elapsedRealtime() - tripFrom
        tripFrom = 0L
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onSensorChanged(e: SensorEvent) {
        val v = e.values
        val g = sqrt((v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).toDouble()) / SensorManager.GRAVITY_EARTH
        val out = detector.onSample(SystemClock.elapsedRealtime(), g) ?: return
        main.post { onImpact(out) }
    }

    private fun onImpact(out: ImpactDetector.Outcome) {
        // 🔒 ตัวเลขแรงกับความเร็วเท่านั้น · ไม่มีพิกัด
        SosStore.addReading(this, out.reading)
        events?.invoke("reading", emptyMap())
        val c = out.confidence ?: return
        if (SystemClock.elapsedRealtime() < cooldownAfterCancel) return
        if (System.currentTimeMillis() < SosStore.cooldownUntil(this)) return
        begin(SosKind.CRASH, SosTrigger.IMPACT, c, drill = false)
    }

    private var cooldownAfterCancel = 0L

    // ── เหตุการณ์ ──

    private fun begin(
        kind: SosKind,
        how: SosTrigger,
        confidence: SosConfidence,
        drill: Boolean,
        silent: Boolean = false,
        resumedFrom: Long? = null,
    ) {
        val p = plan ?: SosStore.plan(this)?.also { plan = it } ?: return
        // 🔴 เจ้าของต้องเปิดเอง ยอมรับข้อจำกัดก่อน · ยังไม่เปิด = ไม่มีใครสั่งให้โทรได้
        if (!p.armed) return
        val cur = incident
        if (cur != null) {
            // ขอความช่วยเหลือซ้ำระหว่างนับถอยหลัง = เจ้าของยืนยันเอง · ห้ามทิ้งเงียบ
            if (drill || how == SosTrigger.IMPACT) return
            if (!cur.drill) {
                // 🔴 ไม่เปลี่ยนเป็นเหตุเงียบ · คนร้องช่วยด้วยหลังรถชนต้องไม่ถูกแจ้งว่าอยู่กับคนร้าย และเครื่องส่งเสียงไปแล้ว
                askHelp(cur)
                return
            }
            stopIncident() // กำลังซ้อมอยู่แล้วเกิดเหตุจริง · เหตุจริงมาก่อน
        }
        val rehearsal = SosRouter.rehearses(p, how, autoCallAllowed(p))
        // เสียงให้เวลามากกว่าปุ่ม · ปุ่มคือเจ้าของกดเอง เสียงคือตัวถอดเสียงที่ฟังผิดได้
        val sec = when {
            resumedFrom != null -> RESUME_COUNTDOWN_SEC
            how == SosTrigger.IMPACT -> p.countdownSec
            how == SosTrigger.VOICE -> maxOf(p.manualCountdownSec, VOICE_COUNTDOWN_SEC)
            else -> p.manualCountdownSec
        }
        val inc = Incident(
            p, kind, how, confidence, drill, rehearsal,
            SystemClock.elapsedRealtime() + sec * 1000L, resumedFrom ?: System.currentTimeMillis(), silent,
        )
        incident = inc
        phase = Phase.ALERT
        if (!drill && !rehearsal) SosStore.saveLive(this, kind, how, confidence, inc.startedAt, silent)
        locator.lastKnown()
        locator.track(true)
        startSampling()
        // 🔴 เจ้าของ: "ไม่ต้องถาม ไม่ต้องพูดอะไร ไม่ต้องเปิดเสียง ให้มายด์ทำเงียบๆ เพื่อแจ้งเหตุเพราะบางที อยู่กับโจร"
        // ไม่เรียก ไม่นับถอยหลัง ไม่เปิดจอ ไม่สั่น ไม่บอก Dart ให้เวทีสะดุ้ง · ทุกอย่างที่คนข้าง ๆ รับรู้ได้ต้องไม่เกิดที่นี่
        if (silent) {
            refresh()
            main.post { dispatch() }
            return
        }
        alertNotice(inc)
        openScreen()
        voice.prepare { voice.language(speakEnglish(inc)) }
        if (!inCall()) voice.raiseAlarm()
        promptCycle()
        main.post(ticker)
        events?.invoke("alert", mapOf("kind" to kind.name, "drill" to drill, "rehearsal" to rehearsal))
        refresh()
    }

    /** เครื่องไม่มีเสียงไทย · อ่านบทไทยด้วยเสียงอังกฤษฟังไม่รู้เรื่อง อังกฤษยังดีกว่า */
    private fun speakEnglish(inc: Incident) = inc.abroad || voice.noThai

    /**
     * เจ้าของขอความช่วยเหลือเอง · แตะปุ่ม ตอบด้วยเสียง หรือพูดซ้ำ
     *
     * 🔴 ปลดโหมดซ้อมและความมั่นใจต่ำ · สองด่านนั้นกันเครื่องตัดสินเอง ไม่ใช่กันคนที่บอกว่าต้องการความช่วยเหลือ
     * ซ้อมจริง ([Incident.drill]) ยังส่งแค่เบอร์ทดสอบ
     */
    private fun askHelp(inc: Incident) {
        if (phase != Phase.ALERT) return
        // 🔴 โหมดทดสอบไม่มีทางปลด · ตอบ "ช่วยด้วย" ก็แค่จบการจำลองเร็วขึ้น
        if (!inc.drill && !testing(inc)) {
            inc.rehearsal = false
            inc.confidence = SosConfidence.HIGH
            SosStore.saveLive(this, inc.kind, SosTrigger.BUTTON, SosConfidence.HIGH, inc.startedAt, inc.silent)
        }
        dispatch()
    }

    /** 🔴 ด่านซ้ำฝั่งเนทีฟ · หน้าตั้งค่ากันแล้วก็ยังต้องมี · แผนในไฟล์ถูกแก้ได้ */
    private fun autoCallAllowed(p: SosPlan) = p.autoCall && SosStore.drills(this) >= 1

    /** ใช้แผนล่าสุด · เจ้าของอาจเปิดโหมดทดสอบระหว่างนับถอยหลัง */
    private fun testing(inc: Incident) = (plan ?: inc.plan).testMode

    private val ticker = object : Runnable {
        override fun run() {
            val inc = incident ?: return
            if (phase != Phase.ALERT) return
            if (SystemClock.elapsedRealtime() >= inc.deadline) {
                dispatch()
                return
            }
            refresh()
            main.postDelayed(this, TICK_MS)
        }
    }

    /** เรียก-เว้นให้ตอบ-เรียก · 🔴 ติดสายอยู่ = ห้ามพูดดังแทรกสาย เหลือสั่นกับเสียงเตือนเบา ๆ */
    private fun promptCycle() {
        val inc = incident ?: return
        if (phase != Phase.ALERT) return
        val inCall = inCall()
        voice.buzz()
        voice.beep(inCall)
        if (inCall) {
            main.postDelayed({ promptCycle() }, PROMPT_GAP_MS)
            return
        }
        val text = inc.plan.texts(speakEnglish(inc)).alertPrompt
        main.postDelayed({
            // กดหยุดระหว่างเสียงบี๊บ · ต้องไม่พูดต่อ
            if (incident === inc && phase == Phase.ALERT) {
                voice.sayAloud(text) { main.postDelayed({ promptCycle() }, PROMPT_GAP_MS) }
            }
        }, BEEP_MS)
    }

    /** เรียกจากจอหรือแจ้งเตือน · ไม่ต้องปลดล็อก · หยุดได้ทุกช่วง */
    private fun stopIncident() {
        val inc = incident
        if (inc == null) {
            SosStore.clearLive(this) // โปรเซสเพิ่งตาย · กดหยุดแล้วต้องไม่ฟื้นเหตุกลับมา
            return
        }
        when (phase) {
            Phase.ALERT -> {
                inc.cancelled = true
                cooldownAfterCancel = SystemClock.elapsedRealtime() + CANCEL_QUIET_MS
                finish(inc)
            }
            Phase.DISPATCH -> {
                inc.cancelled = true
                cooldownAfterCancel = SystemClock.elapsedRealtime() + CANCEL_QUIET_MS
                inc.steps.clear()
                hangUpOurCall(inc)
                cancelNotice(inc)
                finish(inc)
            }
            else -> Unit
        }
    }

    /** ส่งข้อความไปแล้วเรียกคืนไม่ได้ · ทางเดียวคือตามไปบอกว่าปลอดภัย */
    private fun cancelNotice(inc: Incident) {
        val body = SosText.cancel(inc.plan.texts(inc.abroad), inc.drill)
        val told = HashSet<String>()
        for (s in inc.sent.toList()) {
            val step = s.step as? SosStep.Sms ?: continue
            if (s.outcome == "failed" || !told.add(step.to)) continue
            sendSms(step.to, body, inc, cancelText = true)
        }
    }

    private fun finish(inc: Incident) {
        phase = Phase.DONE
        main.removeCallbacks(ticker)
        main.removeCallbacks(nextRun)
        main.removeCallbacks(callWatch)
        currentCall = null
        voice.quiet()
        voice.endScript()
        if (!sampling) locator.track(false)
        SosStore.clearLive(this)
        lastReport = snapshot()
        // 🔴 ไม่มีอะไรออกไปจริง = ด่านซ้อมไม่ผ่าน และเหตุถัดไปต้องไม่ติดเวลาพัก
        val delivered = inc.sent.any { it.outcome in DELIVERED }
        if (inc.drill && !inc.cancelled && delivered) SosStore.addDrill(this)
        // 🔴 ซ้อมไม่นับเป็นเหตุจริง · ไม่เข้าเวลาพัก ไม่กันเหตุจริงที่ตามมา
        if (!inc.drill && !inc.rehearsal && !inc.cancelled && delivered) {
            SosStore.cooldown(this, System.currentTimeMillis() + REAL_COOLDOWN_MS)
        }
        reportNotice(inc)
        events?.invoke("over", mapOf("cancelled" to inc.cancelled, "drill" to inc.drill))
        incident = null
        main.postDelayed({
            if (incident == null) {
                phase = Phase.IDLE
                refresh()
            }
        }, DONE_MS)
        refresh()
        // ระหว่างเหตุเจ้าของอาจปิดระบบหรือลบข้อมูล · ถึงเวลาทำตามแล้ว
        main.post { if (incident == null) applyPlan() }
    }

    // ── แจ้งเหตุ ──

    private fun dispatch() {
        val inc = incident ?: return
        val p = inc.plan
        if (phase != Phase.ALERT) return
        phase = Phase.DISPATCH
        voice.quiet()
        main.removeCallbacks(ticker)
        inc.ownerBusy = inCall()
        if (!inc.drill && testing(inc)) inc.rehearsal = true

        val steps = SosRouter.route(p, inc.kind, inc.confidence, inc.drill, inc.abroad, ::isEcc)
        // โหมดซ้อม: ครบทุกขั้นแต่ไม่แตะโลกภายนอก · บอกเจ้าของว่าถ้าเป็นจริงจะแจ้งใคร
        if (inc.rehearsal) {
            for (s in steps) inc.sent.add(SosSent(s, System.currentTimeMillis(), "simulated"))
            finish(inc)
            return
        }
        inc.steps = ArrayDeque(steps)
        if (steps.isEmpty()) {
            finish(inc)
            return
        }
        // ส่งค่าที่มีทันที · เหตุจริงรอ GPS ไม่ได้ · ได้พิกัดดีขึ้นค่อยตามไปให้ในสาย
        locator.settle(FIX_WAIT_MS) { }
        main.post(nextRun)
        refresh()
    }

    private val nextRun = Runnable { nextStep() }

    private fun nextStep() {
        val inc = incident ?: return
        if (phase != Phase.DISPATCH) return
        val s = inc.steps.removeFirstOrNull()
        if (s == null) {
            finish(inc)
            return
        }
        when (s) {
            is SosStep.Sms -> {
                sendStep(s, inc)
                main.postDelayed(nextRun, SMS_GAP_MS)
            }
            is SosStep.Call -> callStep(s, inc)
        }
    }

    private fun sendStep(s: SosStep.Sms, inc: Incident) {
        val body = SosText.sms(
            inc.plan.texts(inc.abroad), locator.best ?: locator.lastKnown(), System.currentTimeMillis(),
            s.withHealth, inc.confidence == SosConfidence.LOW, inc.drill, silent = inc.silent,
        )
        val ok = sendSms(s.to, body, inc, cancelText = false)
        inc.sent.add(SosSent(s, System.currentTimeMillis(), if (ok) "sent" else "failed"))
        refresh()
    }

    private fun sendSms(to: String, body: String, inc: Incident, cancelText: Boolean): Boolean {
        if (!has(Manifest.permission.SEND_SMS)) return false
        return try {
            val sm = smsManager()
            sm.sendMultipartTextMessage(to, null, sm.divideMessage(body), null, null)
            true
        } catch (e: Exception) {
            // 🔒 ไม่ลงเบอร์หรือเนื้อความ
            android.util.Log.w("GigGokSos", "sms: ${e.javaClass.simpleName}")
            false
        }
    }

    /**
     * 🔴 เครื่องสองซิมไม่ตั้งซิมหลักสำหรับ SMS · ตัวเริ่มต้นของระบบอาจถามว่าใช้ซิมไหน แล้วไม่มีใครตอบ · ข้อความหายเงียบ
     */
    @SuppressLint("MissingPermission")
    private fun smsManager(): SmsManager {
        var sub = SubscriptionManager.getDefaultSmsSubscriptionId()
        if (sub == SubscriptionManager.INVALID_SUBSCRIPTION_ID && has(Manifest.permission.READ_PHONE_STATE)) {
            sub = try {
                getSystemService(SubscriptionManager::class.java)?.activeSubscriptionInfoList?.firstOrNull()?.subscriptionId
                    ?: sub
            } catch (e: SecurityException) {
                sub
            }
        }
        val valid = sub != SubscriptionManager.INVALID_SUBSCRIPTION_ID
        return if (Build.VERSION.SDK_INT >= 31) {
            val sm = getSystemService(SmsManager::class.java)
            if (valid) sm.createForSubscriptionId(sub) else sm
        } else {
            @Suppress("DEPRECATION")
            if (valid) SmsManager.getSmsManagerForSubscriptionId(sub) else SmsManager.getDefault()
        }
    }

    private var callPlacedAt = 0L
    private var callSeen = false
    private var callConnected = false
    private var callOverOwner = false
    private var scriptOn = false
    private var currentCall: SosStep.Call? = null

    private fun callStep(s: SosStep.Call, inc: Incident) {
        // เจ้าของคุยอยู่ก่อนเกิดเหตุ · โทรซ้อน = สายเดิมถูกพักหรือหลุดแบบเจ้าของไม่รู้ตัว · รอจบแล้วค่อยโทร
        // 🔴 ดูเฉพาะสายที่มีอยู่ก่อนส่ง SMS · ญาติโทรกลับหลังได้ข้อความต้องไม่ทำให้สายถึง 1669 ช้าไปห้านาที
        if (inc.ownerBusy && inCall()) {
            if (inc.busySince == 0L) inc.busySince = SystemClock.elapsedRealtime()
            if (SystemClock.elapsedRealtime() - inc.busySince < BUSY_WAIT_MS) {
                inc.steps.addFirst(s)
                main.postDelayed(nextRun, BUSY_POLL_MS)
                return
            }
        }
        // 🔴 แอปโทรเบอร์ฉุกเฉินเองไม่ได้ · เครื่องจะเปิดแป้นโทรพร้อมเลข 191 บนจอให้คนร้ายเห็น · ข้ามไปคนถัดไป
        if (inc.silent && isEcc(s.to) && !SystemBridge.isDefaultDialer(this)) {
            inc.sent.add(SosSent(s, System.currentTimeMillis(), "not_dialer"))
            main.postDelayed(nextRun, STEP_GAP_MS)
            return
        }
        // แจ้งเงียบไม่มีนับถอยหลัง · SMS ออกทันที แต่รอก่อนโทรหาเจ้าหน้าที่ · ปากบอกยกเลิกทันก่อนสายจริงออก
        if (inc.silent && s.official) {
            val wait = inc.silentCallAt - SystemClock.elapsedRealtime()
            if (wait > 0) {
                inc.steps.addFirst(s)
                main.postDelayed(nextRun, wait)
                return
            }
        }
        callOverOwner = inc.ownerBusy && inCall()
        val why = place(s.to)
        if (why != null) {
            inc.sent.add(SosSent(s, System.currentTimeMillis(), why))
            main.postDelayed(nextRun, STEP_GAP_MS)
            return
        }
        currentCall = s
        callPlacedAt = SystemClock.elapsedRealtime()
        callSeen = false
        callConnected = false
        scriptOn = false
        main.postDelayed(callWatch, CALL_POLL_MS)
        refresh()
    }

    /** พูดเมื่อมีคนฟังแล้ว · ตอนรอสายยังไม่มีทางเสียงให้ตัวช่วย และคำแรกจะหายไปกับเสียงรอสาย */
    private fun speakScript(inc: Incident) {
        scriptOn = true
        voice.prepare {
            val english = speakEnglish(inc)
            voice.language(english)
            val t = inc.plan.texts(english)
            val body = SosText.script(
                t, inc.kind, locator.best ?: locator.lastKnown(),
                System.currentTimeMillis(), if (english) "point" else "จุด", inc.silent,
            )
            // 🔴 ปลายสายของการซ้อมต้องรู้ว่าซ้อม · บทจริงฟังเหมือนเจ้าของเกิดเหตุจริงทุกคำ
            voice.scriptInCall(if (inc.drill) "${t.smsDrillPrefix.trim('[', ']')} $body" else body, inc.silent)
        }
    }

    /**
     * ดูสายที่โทรออก
     *
     * 🔴 สายฉุกเฉินจริงอยู่กับแอปโทรศัพท์ของเครื่อง เราไม่เห็นสถานะละเอียด · เห็นแค่ "มีสาย" ·
     * เสียงรอสายกับคนรับแยกกันไม่ได้ · ค้าง [CALL_UNSURE_MS] = ไม่แน่ใจ โทรเบอร์ถัดไปต่อ ·
     * ค้าง [CALL_REACHED_MS] = นับว่าถึง · แจ้งซ้ำสองหน่วยดีกว่าเชื่อว่าถึงแล้วไม่มีใครมา
     */
    private val callWatch = object : Runnable {
        override fun run() {
            val inc = incident ?: return
            val s = currentCall ?: return
            if (phase != Phase.DISPATCH) return
            val now = SystemClock.elapsedRealtime()
            val elapsed = now - callPlacedAt
            // 🔴 ดูเฉพาะสายที่เบอร์ตรง · สายของเจ้าของที่คุยค้างอยู่ต้องไม่ถูกนับเป็นเจ้าหน้าที่รับ
            val ours = ourCall(s.to)
            if (ours != null && MindInCallService.stateOf(ours) == Call.STATE_ACTIVE) callConnected = true
            val inCall = inCall()
            if (inCall) callSeen = true
            // สายที่เราถือบอกได้ว่ารับแล้ว · สายที่แอปโทรศัพท์ของเครื่องถือ (เบอร์ฉุกเฉิน) บอกไม่ได้ จึงนับเวลาเอา
            val blind = ours == null && !callOverOwner
            if (!scriptOn && inCall && (callConnected || (blind && elapsed >= BLIND_ANSWER_MS))) {
                speakScript(inc)
            }
            val over = callSeen && !inCall
            val neverStarted = !callSeen && elapsed > CALL_START_MS
            // ไม่รับ · เครือข่ายไม่ต่อ · ไปคนถัดไป (ทำได้เฉพาะสายที่อยู่กับเรา)
            val ringTooLong = !callConnected && !blind && elapsed > CALL_RING_MS
            if (ringTooLong) ours?.disconnect()
            if (over || neverStarted || ringTooLong) {
                voice.endScript()
                val outcome = when {
                    callConnected || (blind && callSeen && elapsed >= CALL_REACHED_MS) -> "reached"
                    blind && callSeen && elapsed >= CALL_UNSURE_MS -> "unsure"
                    // 🔴 Android ไม่ให้แอปทั่วไปโทรเบอร์ฉุกเฉินเอง · แค่เปิดแป้นโทรให้กด · คนหมดสติกดไม่ได้
                    !callSeen && s.official && !SystemBridge.isDefaultDialer(this@SosService) -> "not_dialer"
                    else -> "no_answer"
                }
                inc.sent.add(SosSent(s, System.currentTimeMillis(), outcome))
                currentCall = null
                // มีคนรับแล้ว · เธอไม่มีอะไรจะพูดเพิ่ม โทรต่อคนถัดไปเป็นแค่สายรบกวน
                if (outcome == "reached") inc.steps.removeAll { it is SosStep.Call }
                main.postDelayed(nextRun, STEP_GAP_MS)
                refresh()
                return
            }
            main.postDelayed(this, CALL_POLL_MS)
        }
    }

    /** 🔴 จุดเดียวในแอปที่โทรเบอร์ฉุกเฉินได้ · ดูหัวไฟล์ · ผู้เรียกมีแค่ [callStep] */
    @SuppressLint("MissingPermission")
    private fun place(number: String): String? {
        if (!has(Manifest.permission.CALL_PHONE)) return "no_permission"
        val tm = getSystemService(TelecomManager::class.java) ?: return "no_telecom"
        return try {
            val extras = Bundle()
            // 🔴 เครื่องสองซิมไม่ตั้งซิมหลัก = ระบบถามว่าใช้ซิมไหน แล้วไม่มีใครตอบ · เลือกให้เอง
            if (has(Manifest.permission.READ_PHONE_STATE)) {
                val account = tm.getDefaultOutgoingPhoneAccount("tel") ?: tm.callCapablePhoneAccounts.firstOrNull()
                if (account != null) extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, account)
            }
            tm.placeCall(Uri.fromParts("tel", number, null), extras)
            null
        } catch (e: SecurityException) {
            "no_permission"
        } catch (e: RuntimeException) {
            android.util.Log.w("GigGokSos", "place: ${e.javaClass.simpleName}")
            "no_telecom"
        }
    }

    /** สายที่เราเห็นและเบอร์ตรงกับที่โทร · ไม่ใช่ [MindInCallService.current] ซึ่งอาจเป็นสายของเจ้าของ */
    private fun ourCall(number: String): Call? {
        val want = number.filter { it.isDigit() }
        return MindInCallService.topCalls().firstOrNull { c ->
            c.details?.handle?.schemeSpecificPart?.filter { it.isDigit() } == want
        }
    }

    /**
     * วางเฉพาะสายที่ SOS โทร · ไม่แตะสายของเจ้าของ
     *
     * 🔴 สายฉุกเฉินที่ระบบถืออยู่ วางจากแอปไม่ได้ · ลงรายงานเป็น "stopped" จอจะบอกให้เจ้าของวางเอง
     */
    private fun hangUpOurCall(inc: Incident) {
        val s = currentCall ?: return
        currentCall = null
        main.removeCallbacks(callWatch)
        inc.sent.add(SosSent(s, System.currentTimeMillis(), "stopped"))
        chaseHangUp(s.to, HANG_TRIES)
    }

    /** Telecom เพิ่มสายช้ากว่า placeCall · กดหยุดทันทีหลังโทร สายยังไม่มีให้วาง · ตามไปวางอีกสักพัก */
    private fun chaseHangUp(number: String, left: Int) {
        val c = ourCall(number)
        if (c != null) {
            c.disconnect()
        } else if (left > 0) {
            main.postDelayed({ chaseHangUp(number, left - 1) }, CALL_POLL_MS)
        }
    }

    @SuppressLint("MissingPermission") // เช็ก has() แล้ว · lint มองไม่เห็นผ่านฟังก์ชันช่วย
    private fun inCall(): Boolean = try {
        if (has(Manifest.permission.READ_PHONE_STATE)) {
            getSystemService(TelecomManager::class.java)?.isInCall == true
        } else {
            MindInCallService.topCalls().isNotEmpty()
        }
    } catch (e: Exception) {
        false
    }

    private fun isEcc(number: String): Boolean = eccOf(this, number)

    private fun isAbroad(): Boolean {
        val iso = getSystemService(TelephonyManager::class.java)?.networkCountryIso?.lowercase().orEmpty()
        // ไม่มีเครือข่าย = ไม่รู้ · เจ้าของอยู่ไทยเป็นส่วนใหญ่ · 112 ในไทยยังยืนยันไม่ได้ว่าเข้าศูนย์ไหน
        return iso.isNotEmpty() && iso != "th"
    }

    private fun snapshot(): Snapshot {
        val inc = incident
        val left = inc?.let { (((it.deadline - SystemClock.elapsedRealtime()) + 999) / 1000).toInt().coerceAtLeast(0) } ?: 0
        return Snapshot(
            phase, inc?.kind, inc?.drill == true, inc?.rehearsal == true, left,
            inc?.confidence == SosConfidence.LOW, inc?.sent?.toList().orEmpty(), inc?.steps?.toList().orEmpty(),
            inc?.cancelled == true, voice.path, inc?.silent == true,
        )
    }

    private fun refresh() {
        val s = snapshot()
        now = s
        listeners.forEach { it(s) }
    }

    // ── จอกับแจ้งเตือน ──

    private fun openScreen() {
        try {
            startActivity(Intent(this, SosActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: RuntimeException) {
            // ระบบกันเปิดจอจากเบื้องหลัง · แจ้งเตือนแบบเต็มจอใน [alertNotice] เป็นทางหลักอยู่แล้ว
            android.util.Log.w("GigGokSos", "screen: ${e.javaClass.simpleName}")
        }
    }

    private fun screenIntent() = PendingIntent.getActivity(
        this, PI_SCREEN, Intent(this, SosActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun action(code: Int, act: String) = PendingIntent.getBroadcast(
        this, code, Intent(this, SosReceiver::class.java).setAction(act),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** 🔴 ทุกคำสั่งเข้าบริการต้องเรียก startForeground · ใส่แจ้งเตือนผิดตัว = ปุ่มหยุดหายกลางเหตุ */
    private fun currentNotice(): Notification =
        incident?.takeUnless { it.silent }?.let { alertNotification(it) } ?: armedNotice()

    private fun armedNotice(): Notification = NotificationCompat.Builder(this, CHANNEL_ARMED)
        .setSmallIcon(R.drawable.ic_listen)
        .setContentTitle(getString(R.string.sos_armed_title))
        .setContentText(getString(if (plan?.testMode != false) R.string.sos_armed_test else R.string.sos_armed_body))
        .setOngoing(true)
        .setSilent(true)
        // 🔒 ขึ้นจอล็อกได้เพราะไม่มีข้อมูลส่วนตัว · ปุ่มนี้คือทางเรียก SOS เองโดยไม่ต้องปลดล็อก
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        .addAction(0, getString(R.string.sos_action_call), action(PI_MANUAL, ACTION_MANUAL_SCREEN))
        .setContentIntent(
            PendingIntent.getActivity(
                this, PI_OPEN, Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        )
        .build()

    private fun alertNotice(inc: Incident) {
        getSystemService(NotificationManager::class.java)?.notify(NOTIFICATION, alertNotification(inc))
    }

    private fun alertNotification(inc: Incident): Notification =
        NotificationCompat.Builder(this, CHANNEL_ALERT)
            .setSmallIcon(R.drawable.ic_listen)
            .setContentTitle(getString(if (inc.drill || inc.rehearsal) R.string.sos_alert_title_drill else R.string.sos_alert_title))
            .setContentText(getString(R.string.sos_alert_body))
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setFullScreenIntent(screenIntent(), true)
            .setContentIntent(screenIntent())
            .addAction(0, getString(R.string.sos_action_stop), action(PI_STOP, ACTION_STOP))
            .addAction(0, getString(R.string.sos_action_help), action(PI_HELP, ACTION_HELP))
            .build()

    /** บอกชัดว่าอะไรออกไปแล้วบ้าง · 🔒 ไม่มีเบอร์ญาติบนจอล็อก (เห็นตอนเปิดดูหลังปลดล็อก) */
    private fun reportNotice(inc: Incident) {
        val texts = inc.sent.count { it.step is SosStep.Sms && it.outcome == "sent" }
        val calls = inc.sent.count { it.step is SosStep.Call && it.outcome == "reached" }
        val nm = getSystemService(NotificationManager::class.java)
        if (inc.silent) {
            // 🔴 ไม่บอกอะไรบนจอล็อก · คนร้ายหยิบเครื่องไปดูได้ · ผลจริงอยู่ในตั้งค่า › ฉุกเฉิน
            val quiet = NotificationCompat.Builder(this, CHANNEL_ARMED)
                .setSmallIcon(R.drawable.ic_listen)
                .setContentTitle(getString(R.string.sos_silent_report))
                .setVisibility(NotificationCompat.VISIBILITY_SECRET)
                .setSilent(true)
                .setAutoCancel(true)
                .setContentIntent(
                    PendingIntent.getActivity(
                        this, PI_OPEN, Intent(this, MainActivity::class.java),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                )
                .build()
            nm?.notify(REPORT_NOTIFICATION, quiet)
            nm?.notify(NOTIFICATION, armedNotice())
            return
        }
        val title = getString(reportTitle(snapshot()))
        val n = NotificationCompat.Builder(this, CHANNEL_ALERT)
            .setSmallIcon(R.drawable.ic_listen)
            .setContentTitle(title)
            .setContentText(getString(R.string.sos_report_counts, texts, calls))
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(screenIntent())
            .setAutoCancel(true)
            .build()
        nm?.notify(REPORT_NOTIFICATION, n)
        nm?.notify(NOTIFICATION, armedNotice())
    }

    companion object {
        private const val CHANNEL_ARMED = "giggok_sos_armed"
        private const val CHANNEL_ALERT = "giggok_sos_alert"
        private const val NOTIFICATION = 7091
        private const val REPORT_NOTIFICATION = 7092
        private const val RESUME_NOTIFICATION = 7093

        private const val PI_SCREEN = 7091
        private const val PI_STOP = 7092
        private const val PI_HELP = 7093
        private const val PI_OPEN = 7094
        private const val PI_MANUAL = 7095

        const val ACTION_SYNC = "com.xjanova.videogirl.sos.SYNC"
        const val ACTION_STOP = "com.xjanova.videogirl.sos.STOP"
        const val ACTION_HELP = "com.xjanova.videogirl.sos.HELP"
        const val ACTION_TRIGGER = "com.xjanova.videogirl.sos.TRIGGER"
        const val ACTION_MANUAL_SCREEN = "com.xjanova.videogirl.sos.MANUAL"
        private const val EXTRA_KIND = "kind"
        private const val EXTRA_VOICE = "voice"
        private const val EXTRA_DRILL = "drill"
        private const val EXTRA_SILENT = "silent"

        private const val SAMPLE_US = 20_000
        private const val MOVING_KMH = 8.0
        private const val TRIP_MS = 5 * 60_000L
        private const val CHECK_MS = 30_000L
        private const val WAKE_MS = 90_000L
        private const val TICK_MS = 250L
        private const val BEEP_MS = 600L
        private const val PROMPT_GAP_MS = 5_000L
        private const val CANCEL_QUIET_MS = 60_000L
        private const val REAL_COOLDOWN_MS = 10 * 60_000L
        private const val DONE_MS = 60_000L
        private const val FIX_WAIT_MS = 8_000L
        private const val SMS_GAP_MS = 800L
        private const val STEP_GAP_MS = 2_000L
        private const val CALL_POLL_MS = 1_000L
        private const val CALL_START_MS = 8_000L
        private const val CALL_RING_MS = 45_000L
        private const val CALL_REACHED_MS = 90_000L
        private const val BLIND_ANSWER_MS = 6_000L
        private const val CALL_UNSURE_MS = 25_000L
        private const val VOICE_COUNTDOWN_SEC = 10
        private const val RESUME_COUNTDOWN_SEC = 15
        private const val RESUME_MAX_MS = 15 * 60_000L
        private const val HANG_TRIES = 10
        private const val SILENT_CALL_WAIT_MS = 20_000L
        private const val BUSY_POLL_MS = 3_000L
        private const val BUSY_WAIT_MS = 5 * 60_000L

        @Volatile private var live: SosService? = null

        /** สถานะล่าสุด · จออ่านค่านี้ */
        @Volatile var now: Snapshot = Snapshot(Phase.IDLE, null, false, false, 0, false, emptyList(), emptyList(), false, "none")
            private set

        /** รายงานเหตุล่าสุด (ค้างไว้ให้อ่านหลังจบ) */
        @Volatile var lastReport: Snapshot? = null
            private set

        val listeners = java.util.concurrent.CopyOnWriteArrayList<(Snapshot) -> Unit>()

        /** ยิงหา Dart · ตั้งโดย [SosBridge] · null = ไม่มี Dart ซึ่งเป็นเรื่องปกติ */
        @Volatile var events: ((String, Map<String, Any?>) -> Unit)? = null

        /** ผลที่แปลว่ามีอะไรออกไปจริง · ใช้ตัดสินรายงาน ด่านซ้อม และเวลาพัก */
        private val DELIVERED = setOf("sent", "reached", "unsure")

        /** 🔴 ห้ามบอกว่า "แจ้งเหตุแล้ว" ถ้าไม่มีอะไรออกไป · เจ้าของจะนั่งรอคนที่ไม่มีวันมา */
        fun reportTitle(s: Snapshot): Int = when {
            s.rehearsal -> R.string.sos_report_rehearsal
            s.cancelled && s.sent.isEmpty() -> R.string.sos_report_cancelled
            s.cancelled -> R.string.sos_report_cancelled_late
            s.sent.none { it.outcome in DELIVERED } -> R.string.sos_report_failed
            else -> R.string.sos_report_done
        }

        @JvmStatic
        val running: Boolean get() = live != null

        fun eccOf(c: Context, number: String): Boolean = try {
            if (Build.VERSION.SDK_INT >= 29) {
                c.getSystemService(TelephonyManager::class.java)?.isEmergencyNumber(number) == true
            } else {
                @Suppress("DEPRECATION")
                PhoneNumberUtils.isEmergencyNumber(number)
            }
        } catch (e: RuntimeException) {
            false
        }

        private fun start(c: Context, action: String, extras: Intent.() -> Unit = {}) {
            val app = c.applicationContext
            ensureChannels(app)
            try {
                ContextCompat.startForegroundService(
                    app, Intent(app, SosService::class.java).setAction(action).apply(extras)
                )
            } catch (e: RuntimeException) {
                android.util.Log.w("GigGokSos", "start: ${e.javaClass.simpleName}")
                postResume(app)
            }
        }

        /** ซิงก์กับแผนที่เก็บไว้ · ตอนเปิดแอป บันทึกค่า บูตเครื่อง */
        fun sync(c: Context) {
            val p = SosStore.plan(c)
            if (p?.armed == true || live != null) start(c, ACTION_SYNC)
        }

        fun trigger(c: Context, kind: String, voice: Boolean, drill: Boolean, silent: Boolean = false): Boolean {
            if (SosStore.plan(c)?.armed != true) return false
            start(c, ACTION_TRIGGER) {
                putExtra(EXTRA_KIND, kind)
                putExtra(EXTRA_VOICE, voice)
                putExtra(EXTRA_DRILL, drill)
                putExtra(EXTRA_SILENT, silent)
            }
            return true
        }

        fun stop(c: Context) = start(c, ACTION_STOP)

        fun helpNow(c: Context) = start(c, ACTION_HELP)

        /** เจ้าของปิดเอง/ลบข้อมูล · ปิดบริการ */
        fun off(c: Context) {
            val app = c.applicationContext
            // 🔴 ปิดระบบหรือลบข้อมูลกลางเหตุ = เจ้าของสั่งหยุด · แผนเก่าต้องไม่เดินต่อ
            live?.let {
                it.stopIncident()
                if (it.incident == null) it.quit()
            }
            SosStore.clearLive(app)
            app.getSystemService(NotificationManager::class.java)?.cancel(RESUME_NOTIFICATION)
        }

        /** ปุ่ม "ออกจากแอป" จบทั้งโปรเซส · บอกตรง ๆ ว่า SOS หยุดแล้ว */
        @JvmStatic
        fun warnStopped(c: Context) {
            if (live != null) postResume(c.applicationContext)
        }

        private fun postResume(c: Context) {
            ensureChannels(c)
            val n = NotificationCompat.Builder(c, CHANNEL_ALERT)
                .setSmallIcon(R.drawable.ic_listen)
                .setContentTitle(c.getString(R.string.sos_stopped_title))
                .setContentText(c.getString(R.string.sos_stopped_body))
                .setAutoCancel(true)
                .setContentIntent(
                    PendingIntent.getActivity(
                        c, PI_OPEN, Intent(c, MainActivity::class.java),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                )
                .build()
            try {
                c.getSystemService(NotificationManager::class.java)?.notify(RESUME_NOTIFICATION, n)
            } catch (e: SecurityException) {
                android.util.Log.w("GigGokSos", "notify denied")
            }
        }

        fun ensureChannels(c: Context) {
            val nm = c.getSystemService(NotificationManager::class.java) ?: return
            if (nm.getNotificationChannel(CHANNEL_ARMED) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL_ARMED, c.getString(R.string.sos_channel_armed), NotificationManager.IMPORTANCE_LOW).apply {
                        setShowBadge(false)
                        setSound(null, null)
                        enableVibration(false)
                        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    }
                )
            }
            if (nm.getNotificationChannel(CHANNEL_ALERT) == null) {
                nm.createNotificationChannel(
                    NotificationChannel(CHANNEL_ALERT, c.getString(R.string.sos_channel_alert), NotificationManager.IMPORTANCE_HIGH).apply {
                        // เสียงมาจากบริการเองผ่านช่องปลุก · ไม่ซ้อนเสียงแจ้งเตือน
                        setSound(null, null)
                        enableVibration(false)
                        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    }
                )
            }
        }
    }
}
