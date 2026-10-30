package com.xjanova.videogirl.direct.setup

import android.app.*
import android.content.*
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.LocalSocket
import android.net.LocalSocketAddress
import android.os.*
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.net.InetAddress
import java.net.NetworkInterface
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** User-initiated setup only. Never turns debugging on/off or reboots the phone silently. */
object DirectAudioSetup {
    private const val CHANNEL = "giggok_direct_pairing"
    private const val NOTIFICATION = 7041
    const val CODE = "pairing_code"
    private val work = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile var status = "not_started"
        private set
    @Volatile private var busy = false

    fun attach(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "giggok/direct_setup").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(status)
                "open" -> {
                    context.startActivity(Intent(context, DirectAudioSetupActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "reconnect" -> { reconnect(context.applicationContext); result.success(true) }
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
        submit(context, complete) {
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

    private fun submit(context: Context, complete: () -> Unit = {}, job: () -> Unit) {
        synchronized(this) { if (busy) { complete(); return }; busy = true }
        work.execute {
            try {
                check(context.getSystemService(android.media.AudioManager::class.java).mode != android.media.AudioManager.MODE_IN_CALL) { "call_in_progress" }
                job()
                val ready = probe(context)
                status = if (ready) "helper_started" else "device_unsupported"
                notify(context, if (ready) "เปิดทางเสียงตรงแล้ว กลับไปที่ GigGok ได้" else "รุ่นนี้ยังไม่รองรับทางเสียงตรง จะใช้ทางลำโพงเดิม", false)
            }
            catch (e: Exception) {
                // Do not log a pairing code, key, token, shell output or exception message.
                status = "setup_failed"
                notify(context, "ยังเชื่อมต่อไม่ได้ เปิด Wi-Fi และ Wireless debugging แล้วลองรหัสใหม่", true)
            } finally { busy = false; complete() }
        }
    }

    private fun launch(context: Context, adb: LocalAdbIdentity) {
        val port = discover(context, "_adb-tls-connect._tcp.")
        check(adb.connect("127.0.0.1", port) || adb.isConnected) { "connect_failed" }
        val prefs = context.getSharedPreferences("giggok_direct_audio", Context.MODE_PRIVATE)
        val random = SecureRandom()
        val token = prefs.getString("token", null) ?: ByteArray(32).also(random::nextBytes).joinToString("") { "%02x".format(it.toInt() and 255) }
        val socket = prefs.getString("socket", null) ?: "giggok_${context.applicationInfo.uid}_${java.util.UUID.randomUUID().toString().replace("-", "") }"
        require(token.matches(Regex("[a-f0-9]{64}")) && socket.matches(Regex("giggok_[a-zA-Z0-9_]{1,80}")))
        check(prefs.edit().putString("token", token).putString("socket", socket).commit())
        val apk = context.applicationInfo.sourceDir
        // APK is supplied by PackageManager; still quote it as shell code, never JSON-quote.
        fun quote(s: String) = "'" + s.replace("'", "'\"'\"'") + "'"
        // setsid takes the helper out of adbd's session so closing this stream cannot take it down.
        val script = "IFS= read -r secret; S=; command -v setsid >/dev/null 2>&1 && S=setsid; " +
            "printf '%s\\n' \"\$secret\" | \$S nohup env CLASSPATH=${quote(apk)} app_process / com.xjanova.videogirl.direct.DirectAudioServer $socket ${context.applicationInfo.uid} >/dev/null 2>&1 &"
        adb.openStream("shell:sh -c ${quote(script)}").use { stream ->
            stream.openOutputStream().apply { write((token + "\n").toByteArray(Charsets.US_ASCII)); flush() }
            // Keep transport alive briefly so nohup has consumed stdin before adb closes.
            Thread.sleep(800)
        }
    }

    private fun probe(context: Context): Boolean {
        val prefs = context.getSharedPreferences("giggok_direct_audio", Context.MODE_PRIVATE)
        val socketName = prefs.getString("socket", null) ?: error("not_configured")
        val token = prefs.getString("token", null) ?: error("not_configured")
        var last: Exception? = null
        repeat(5) {
            try {
                LocalSocket().use { socket ->
                    socket.connect(LocalSocketAddress(socketName, LocalSocketAddress.Namespace.ABSTRACT))
                    socket.soTimeout = 1000
                    check(socket.peerCredentials.uid == 2000)
                    val output = java.io.DataOutputStream(socket.outputStream)
                    output.writeInt(1); output.write(token.toByteArray(Charsets.US_ASCII))
                    output.writeInt(1); output.writeInt(1); output.writeInt(0); output.flush()
                    val input = java.io.DataInputStream(socket.inputStream)
                    check(input.readInt() == 100 && input.readInt() == 1)
                    val size = input.readInt(); check(size in 0..128)
                    val text = ByteArray(size).also(input::readFully).toString(Charsets.UTF_8)
                    check(text == "ready" || text == "unsupported")
                    return text == "ready"
                }
            } catch (e: Exception) { last = e; Thread.sleep(200) }
        }
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
