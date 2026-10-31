package com.xjanova.videogirl.direct.setup

import android.app.*
import android.content.*
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.content.pm.PackageManager
import android.os.*
import android.provider.Settings
import android.telecom.TelecomManager
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import com.xjanova.videogirl.direct.AudioProtocol
import com.xjanova.videogirl.R
import com.xjanova.videogirl.MindInCallService
import io.github.muntashirakon.adb.AdbAuthenticationFailedException
import io.github.muntashirakon.adb.AdbPairingRequiredException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Pairing is user-initiated. Recovery briefly enables only Wireless debugging, then restores it. */
object DirectAudioSetup {
    private const val CHANNEL = "giggok_direct_pairing"
    private const val NOTIFICATION = 7041
    const val CODE = "pairing_code"
    private val work = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile var status = "not_started"
        private set
    @Volatile private var busy = false
    @Volatile private var lastGrantAttempt = 0L
    /** Why the last setup failed, in step + class words only. vivo drops app logcat, so this rides on the
     *  card's extras where `adb shell dumpsys notification --noredact` shows it; the card text stays Thai. */
    @Volatile private var diag = ""

    fun attach(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "giggok/direct_setup").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status)
                "open" -> {
                    context.startActivity(Intent(context, DirectAudioSetupActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "reconnect" -> { reconnect(context.applicationContext); result.success(true) }
                "pauseStatus" -> work.execute {
                    BankingPause.tick(context.applicationContext)
                    val answer = BankingPause.status(context.applicationContext)
                    main.post { result.success(answer) }
                }
                "pause" -> pause(context, call.argument<Int>("minutes") ?: 5) { result.success(it) }
                "extendPause" -> extendPause(context) { result.success(it) }
                "restorePause" -> restorePause(context) { result.success(it) }
                "live" -> work.execute {
                    val answer = live(context.applicationContext)
                    main.post { result.success(answer) }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun begin(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 30) { status = "requires_android_11"; return false }
        status = "waiting_for_code"
        notify(context, "เปิด Wireless debugging แล้วเลือกจับคู่อุปกรณ์ด้วยรหัส", true)
        context.startActivity(Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        return true
    }

    fun pair(context: Context, code: String, complete: () -> Unit = {}) {
        if (!code.matches(Regex("[0-9]{6}"))) { status = "invalid_code"; notify(context, "กรอกรหัสจับคู่ 6 หลักจากหน้าตั้งค่า", true); complete(); return }
        submit(context, complete, pairing = true) {
            status = "finding_pairing_port"
            LocalAdbIdentity(context).use { adb ->
                val port = discover(context, "_adb-tls-pairing._tcp.")
                check(adb.pair("127.0.0.1", port, code)) { "pairing_rejected" }
                status = "paired_connecting"
                launch(context, adb)
            }
        }
    }

    fun reconnect(context: Context) = submit(context) {
        LocalAdbIdentity(context).use { launch(context, it) }
    }

    fun pause(context: Context, minutes: Int, complete: (Boolean) -> Unit) = control(context,
        { BankingPause.pause(it, minutes) }, complete)

    fun extendPause(context: Context, complete: (Boolean) -> Unit) = control(context,
        { BankingPause.extend(it) }, complete)

    fun restorePause(context: Context, complete: (Boolean) -> Unit) = control(context,
        { BankingPause.restore(it) }, complete)

    private fun control(context: Context, action: (Context) -> Boolean, complete: (Boolean) -> Unit) {
        val app = context.applicationContext
        work.execute {
            val answer = try { action(app) } catch (_: Exception) { false }
            DirectAudioMonitorService.start(app)
            main.post { complete(answer) }
        }
    }

    /** Serialized with pairing and manual reconnect. Reports only fixed states to the status service. */
    fun monitor(context: Context, recover: Boolean, update: (String) -> Unit) {
        val app = context.applicationContext
        work.execute {
            try { if (!restorePendingWireless(app)) { main.post { update("offline") }; return@execute } }
            catch (_: Exception) { main.post { update("offline") }; return@execute }
            var state = live(app)
            if (state == "ready" &&
                app.checkSelfPermission(android.Manifest.permission.WRITE_SECURE_SETTINGS) != PackageManager.PERMISSION_GRANTED &&
                wifiAvailable(app) && !phoneBusy(app) &&
                Settings.Global.getInt(app.contentResolver, "adb_wifi_enabled", 0) == 1 &&
                (lastGrantAttempt == 0L || SystemClock.elapsedRealtime() - lastGrantAttempt > 300_000L)) {
                lastGrantAttempt = SystemClock.elapsedRealtime()
                try {
                    LocalAdbIdentity(app).use { adb ->
                        val port = discover(app, "_adb-tls-connect._tcp.")
                        if (adb.connect("127.0.0.1", port) || adb.isConnected) grantSettings(app, adb)
                    }
                } catch (_: Exception) { /* Do not replace a running helper to grant the permission. */ }
            }
            if (recover && state == "offline" && !busy && wifiAvailable(app) && !phoneBusy(app)) {
                main.post { update("connecting") }
                busy = true
                var changed = false
                try {
                    val before = Settings.Global.getInt(app.contentResolver, "adb_wifi_enabled", 0)
                    if (before == 0) {
                        if (app.checkSelfPermission(android.Manifest.permission.WRITE_SECURE_SETTINGS) != PackageManager.PERMISSION_GRANTED) {
                            throw IllegalStateException("secure_settings_unavailable")
                        }
                        val prefs = app.getSharedPreferences("giggok_direct_control", Context.MODE_PRIVATE)
                        check(prefs.edit().putInt("wifi_previous", before).putBoolean("wifi_restore_pending", true).commit())
                        check(Settings.Global.putInt(app.contentResolver, "adb_wifi_enabled", 1))
                        changed = true
                    }
                    LocalAdbIdentity(app).use { launch(app, it) }
                    state = if (probe(app)) "ready" else "unsupported"
                } catch (e: Exception) {
                    state = if (e is AdbAuthenticationFailedException || e is AdbPairingRequiredException) "key_rejected" else "offline"
                    status = state
                } finally {
                    if (changed) {
                        try { if (!restorePendingWireless(app)) state = "offline" }
                        catch (_: Exception) { state = "offline" }
                    }
                    busy = false
                }
                // A ROM can kill the helper when Wireless debugging returns to its previous state.
                if (state == "ready") state = live(app)
            }
            main.post { update(state) }
        }
    }

    private fun wifiAvailable(context: Context): Boolean {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        return manager.allNetworks.any { network ->
            manager.getNetworkCapabilities(network)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
    }

    private fun phoneBusy(context: Context): Boolean {
        if (MindInCallService.current != null) return true
        return try { context.getSystemService(TelecomManager::class.java).isInCall }
        catch (_: RuntimeException) { true }
    }

    /** A killed process must not leave the debugging switch that we enabled behind. */
    internal fun restorePendingWireless(context: Context): Boolean {
        val prefs = context.getSharedPreferences("giggok_direct_control", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("wifi_restore_pending", false)) return true
        if (context.checkSelfPermission(android.Manifest.permission.WRITE_SECURE_SETTINGS) != PackageManager.PERMISSION_GRANTED) return false
        val previous = prefs.getInt("wifi_previous", 0)
        val current = Settings.Global.getInt(context.contentResolver, "adb_wifi_enabled", previous)
        if (current == 1 && !Settings.Global.putInt(context.contentResolver, "adb_wifi_enabled", previous)) return false
        return prefs.edit().remove("wifi_previous").remove("wifi_restore_pending").commit()
    }

    private fun submit(context: Context, complete: () -> Unit = {}, pairing: Boolean = false, job: () -> Unit) {
        synchronized(this) { if (busy) { complete(); return }; busy = true }
        diag = ""
        status = "connecting"
        work.execute {
            try {
                check(!phoneBusy(context)) { "call_in_progress" }
                check(!BankingPause.isPaused(context)) { "pause_active" }
                job()
                val ready = probe(context)
                status = if (ready) "helper_started" else "device_unsupported"
                notify(context, if (ready) "เปิดทางเสียงตรงแล้ว กลับไปที่ GigGok ได้" else "รุ่นนี้ยังไม่รองรับทางเสียงตรง", false)
            }
            catch (e: Exception) {
                // Do not log a pairing code, key, token, shell output or exception message.
                val keyRejected = e is AdbAuthenticationFailedException || e is AdbPairingRequiredException
                status = if (!pairing && keyRejected) "key_rejected" else "setup_failed"
                if (diag.isEmpty()) diag = "setup: ${e.javaClass.simpleName}"
                notify(context,
                    context.getString(if (pairing) R.string.direct_pairing_failed
                        else if (keyRejected) R.string.direct_pair_again else R.string.direct_reconnect_failed),
                    pairing || keyRejected)
            } finally { busy = false; complete() }
        }
    }

    private fun launch(context: Context, adb: LocalAdbIdentity) {
        val port = discover(context, "_adb-tls-connect._tcp.")
        check(!phoneBusy(context)) { "call_in_progress" }
        check(adb.connect("127.0.0.1", port) || adb.isConnected) { "connect_failed" }
        grantSettings(context, adb)
        val prefs = context.getSharedPreferences("giggok_direct_audio", Context.MODE_PRIVATE)
        val random = SecureRandom()
        val token = prefs.getString("token", null) ?: ByteArray(32).also(random::nextBytes).joinToString("") { "%02x".format(it.toInt() and 255) }
        // Below the kernel's ephemeral range, so an outgoing connection's local port never takes it.
        val helperPort = prefs.getInt("port", 0).takeIf { it in PORTS } ?: (PORTS.first + random.nextInt(PORTS.count()))
        require(token.matches(Regex("[a-f0-9]{64}")))
        check(prefs.edit().putString("token", token).putInt("port", helperPort).remove("socket").commit())
        val apk = context.applicationInfo.sourceDir
        // APK is supplied by PackageManager; still quote it as shell code, never JSON-quote.
        fun quote(s: String) = "'" + s.replace("'", "'\"'\"'") + "'"
        // adbd hands this stream a PTY, so when sh exits the kernel SIGHUPs its process group, which still
        // holds the helper until setsid runs. Ignoring HUP first is inherited across fork/exec and closes
        // that race; setsid then takes the helper out of adbd's session so closing the stream cannot reach it.
        // A helper left over from before an app update still runs the old APK and holds the socket name, so
        // the new one could never bind: reconnect replaces it (setup refuses during a call, so none is in use).
        // The ^app_process anchor cannot match this sh, whose own command line also names the class.
        val script = "trap '' HUP; IFS= read -r secret; " +
            "pkill -f '^app_process / com[.]xjanova[.]videogirl[.]direct[.]DirectAudioServer ' 2>/dev/null && sleep 1; " +
            "S=; command -v setsid >/dev/null 2>&1 && S=setsid; " +
            "printf '%s\\n' \"\$secret\" | \$S nohup env CLASSPATH=${quote(apk)} app_process / com.xjanova.videogirl.direct.DirectAudioServer $helperPort ${context.applicationInfo.uid} >/dev/null 2>>/data/local/tmp/giggok-helper.log &"
        check(!phoneBusy(context)) { "call_in_progress" }
        adb.openStream("shell:sh -c ${quote(script)}").use { stream ->
            stream.openOutputStream().apply { write((token + "\n").toByteArray(Charsets.US_ASCII)); flush() }
            // Keep transport alive briefly so nohup has consumed stdin before adb closes.
            Thread.sleep(800)
        }
    }

    private fun grantSettings(context: Context, adb: LocalAdbIdentity) {
        // One fixed command, only after authenticated local adb connect. Failure leaves manual setup usable.
        if (context.checkSelfPermission(android.Manifest.permission.WRITE_SECURE_SETTINGS) != PackageManager.PERMISSION_GRANTED) {
            try {
                adb.openStream("shell:pm grant com.xjanova.videogirl android.permission.WRITE_SECURE_SETTINGS")
                    .use { it.openInputStream().readBytes() }
            } catch (_: Exception) { /* Some ROMs refuse the development permission. */ }
        }
    }

    private val PORTS = 10000..31999

    /** An authenticated connection to the helper: loopback TCP, then both ends prove the token. */
    class Channel(val socket: Socket, val input: DataInputStream, val output: DataOutputStream) : java.io.Closeable {
        override fun close() = socket.close()
    }

    fun open(context: Context, stage: (String) -> Unit = {}): Channel {
        val prefs = context.getSharedPreferences("giggok_direct_audio", Context.MODE_PRIVATE)
        val port = prefs.getInt("port", 0).takeIf { it in PORTS } ?: error("not_configured")
        val token = prefs.getString("token", null)?.takeIf { it.matches(Regex("[a-f0-9]{64}")) } ?: error("not_configured")
        val socket = Socket()
        try {
            stage("connect")
            socket.tcpNoDelay = true
            socket.connect(InetSocketAddress(InetAddress.getLoopbackAddress(), port), 1000)
            stage("handshake")
            socket.soTimeout = 1000
            val input = DataInputStream(BufferedInputStream(socket.getInputStream()))
            val output = DataOutputStream(BufferedOutputStream(socket.getOutputStream()))
            AudioProtocol.clientHello(input, output, token.toByteArray(Charsets.US_ASCII))
            return Channel(socket, input, output)
        } catch (e: Exception) { socket.close(); throw e }
    }

    /** Asked while it rings. On a phone set up for direct audio a helper that is gone
     *  means she would answer and the caller would hear nothing. Answers on the main thread. */
    fun helperDown(context: Context, answer: (Boolean) -> Unit) {
        val app = context.applicationContext
        work.execute {
            val down = live(app) == "offline"
            main.post { answer(down) }
        }
    }

    /** What the settings card shows: asked of the helper now, not remembered from an earlier setup.
     *  Runs on [work], so never alongside a setup probe. */
    private fun live(context: Context): String {
        val prefs = context.getSharedPreferences("giggok_direct_audio", Context.MODE_PRIVATE)
        if (prefs.getString("token", null) == null) return "not_paired"
        // The helper serves one session at a time; during a call that session is the call.
        if (context.getSystemService(android.media.AudioManager::class.java).mode == android.media.AudioManager.MODE_IN_CALL) return "in_call"
        return try {
            open(context).use { ch ->
                AudioProtocol.write(ch.output, AudioProtocol.STATUS, 1, ByteArray(0))
                val reply = AudioProtocol.read(ch.input)
                if (reply.type == AudioProtocol.REPLY && reply.text() == "ready") "ready" else "unsupported"
            }
        } catch (_: Exception) { "offline" }
    }

    private fun probe(context: Context): Boolean {
        var last: Exception? = null
        var stage = "connect"
        // A cold app_process binds in ~0.6 s on a quiet phone, after the launcher's 1 s for a stale helper.
        for (attempt in 1..25) {
            try {
                open(context) { stage = it }.use { ch ->
                    stage = "status"
                    AudioProtocol.write(ch.output, AudioProtocol.STATUS, 1, ByteArray(0))
                    val reply = AudioProtocol.read(ch.input)
                    check(reply.type == AudioProtocol.REPLY && reply.id == 1)
                    val text = reply.text()
                    check(text == "ready" || text == "unsupported")
                    return text == "ready"
                }
            } catch (e: AudioProtocol.HandshakeException) {
                // Whoever holds the port cannot prove the token: another app took it before the helper could
                // bind. The next reconnect starts the helper on a fresh port instead of retrying this one.
                context.getSharedPreferences("giggok_direct_audio", Context.MODE_PRIVATE).edit().remove("port").commit()
                last = e; stage = "auth"
                break
            } catch (e: Exception) { last = e; Thread.sleep(200) }
        }
        // Exception text can contain connection details or credentials; log class and fixed stage only.
        diag = "probe failed at $stage: ${last?.javaClass?.simpleName}"
        android.util.Log.w("GigGokDirect", diag)
        throw last ?: IllegalStateException("helper_unavailable")
    }

    /** Discover separate ports, accepting only an address belonging to this phone. */
    private fun discover(context: Context, type: String): Int {
        val nsd = context.getSystemService(NsdManager::class.java)
        val found = CountDownLatch(1)
        val port = java.util.concurrent.atomic.AtomicInteger(0)
        val resolving = java.util.concurrent.atomic.AtomicBoolean(false)
        val local = NetworkInterface.getNetworkInterfaces().toList().flatMap { it.inetAddresses.toList() }.map { it.hostAddress }.toSet()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(t: String) {}
            override fun onDiscoveryStopped(t: String) {}
            override fun onStartDiscoveryFailed(t: String, code: Int) { found.countDown() }
            override fun onStopDiscoveryFailed(t: String, code: Int) {}
            override fun onServiceLost(service: NsdServiceInfo) {}
            override fun onServiceFound(service: NsdServiceInfo) {
                if (!resolving.compareAndSet(false, true)) return
                @Suppress("DEPRECATION")
                nsd.resolveService(service, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(s: NsdServiceInfo, code: Int) { resolving.set(false) }
                    override fun onServiceResolved(s: NsdServiceInfo) {
                        val host = s.host
                        if (host != null && (host.isLoopbackAddress || local.contains(host.hostAddress)) && s.port in 1..65535) {
                            port.set(s.port); found.countDown()
                        }
                        resolving.set(false)
                    }
                })
            }
        }
        main.post { nsd.discoverServices(type, NsdManager.PROTOCOL_DNS_SD, listener) }
        try { check(found.await(15, TimeUnit.SECONDS) && port.get() > 0) { "discovery_timeout" }; return port.get() }
        finally { main.post { try { nsd.stopServiceDiscovery(listener) } catch (_: Exception) {} } }
    }

    private fun notify(context: Context, text: String, input: Boolean) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "ตั้งค่าเสียงในสาย", NotificationManager.IMPORTANCE_HIGH))
        val open = PendingIntent.getActivity(context, 0, Intent(context, DirectAudioSetupActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = NotificationCompat.Builder(context, CHANNEL).setSmallIcon(android.R.drawable.stat_sys_phone_call)
            .setContentTitle("GigGok · เสียงตรงในสาย").setContentText(text).setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setOnlyAlertOnce(true).setAutoCancel(!input)
            .addExtras(Bundle().apply { putString("giggok.diag", diag) })
        // While the pairing sheet waits for its code, opening GigGok would close it and void the code.
        if (!input) builder.setContentIntent(open)
        if (input) {
            val reply = PendingIntent.getBroadcast(context, 1, Intent(context, DirectPairingReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
            builder.addAction(NotificationCompat.Action.Builder(android.R.drawable.ic_menu_edit, "กรอกรหัส 6 หลัก", reply)
                .addRemoteInput(RemoteInput.Builder(CODE).setLabel("รหัสจับคู่ 6 หลัก").build()).build())
        }
        try { manager.notify(NOTIFICATION, builder.build()) } catch (_: SecurityException) { status = "notifications_required" }
    }
}

class DirectPairingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val code = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(DirectAudioSetup.CODE)?.toString()?.trim() ?: return
        // Discovery + TLS can outlive BroadcastReceiver's short execution window.
        androidx.core.content.ContextCompat.startForegroundService(context,
            Intent(context, DirectPairingService::class.java).putExtra(DirectAudioSetup.CODE, code))
    }
}

class DirectPairingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel("giggok_pairing_work", "กำลังเชื่อมต่อเสียงในสาย", NotificationManager.IMPORTANCE_LOW))
        startForeground(7042, NotificationCompat.Builder(this, "giggok_pairing_work")
            .setSmallIcon(android.R.drawable.stat_sys_phone_call).setContentTitle("GigGok กำลังจับคู่กับเครื่องนี้")
            .setContentText("รอสักครู่ โดยคงหน้ารหัสจับคู่ไว้").setOngoing(true).build())
        val code = intent?.getStringExtra(DirectAudioSetup.CODE) ?: ""
        DirectAudioSetup.pair(applicationContext, code) {
            stopForeground(STOP_FOREGROUND_REMOVE); stopSelf(startId)
        }
        return START_NOT_STICKY
    }
}
