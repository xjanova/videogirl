package com.xjanova.videogirl.direct.setup

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkRequest
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.xjanova.videogirl.MainActivity
import com.xjanova.videogirl.R

/** Keeps the owner-visible direct audio state alive across Flutter engine and app restarts. */
class DirectAudioMonitorService : Service() {
    companion object {
        private const val CHANNEL = "giggok_direct_status"
        private const val NOTIFICATION = 7043
        private const val ACTION_RETRY = "com.xjanova.videogirl.direct.RETRY"
        private const val ACTION_PAUSE = "com.xjanova.videogirl.direct.PAUSE"
        private const val ACTION_EXTEND = "com.xjanova.videogirl.direct.EXTEND"
        private const val ACTION_RESTORE = "com.xjanova.videogirl.direct.RESTORE"

        fun start(context: Context) {
            try {
                ContextCompat.startForegroundService(context.applicationContext,
                    Intent(context, DirectAudioMonitorService::class.java))
            } catch (_: RuntimeException) { /* Background-start restrictions: next resume catches up. */ }
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val manager by lazy { getSystemService(NotificationManager::class.java) }
    private val connectivity by lazy { getSystemService(ConnectivityManager::class.java) }
    private var checking = false
    private var state = "checking"
    private var failures = 0
    private var nextAttempt = 0L
    private var keyRejected = false
    private var networkRegistered = false
    private var unlockRegistered = false
    private val network = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { main.post { refresh(force = true) } }
    }
    private val unlock = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) { refresh(force = true) }
    }
    private val tick = object : Runnable {
        override fun run() {
            refresh()
            main.postDelayed(this, 15_000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        manager.createNotificationChannel(NotificationChannel(CHANNEL,
            getString(R.string.direct_status_channel), NotificationManager.IMPORTANCE_LOW))
        startForeground(NOTIFICATION, notification())
        try {
            connectivity.registerNetworkCallback(NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build(), network)
            networkRegistered = true
        } catch (_: RuntimeException) { /* Periodic check still works. */ }
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(unlock, IntentFilter(Intent.ACTION_USER_PRESENT), Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(unlock, IntentFilter(Intent.ACTION_USER_PRESENT))
            }
            unlockRegistered = true
        } catch (_: RuntimeException) { /* The timer and boot/resume still catch up. */ }
        main.post(tick)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_RETRY) {
            keyRejected = false
            nextAttempt = 0L
        } else if (intent?.action == ACTION_PAUSE) {
            if (BankingPause.status(this)["needsConfirmation"] == false) {
                DirectAudioSetup.pause(this, 5) { refresh(force = true) }
            }
            return START_STICKY
        } else if (intent?.action == ACTION_EXTEND) {
            DirectAudioSetup.extendPause(this) { refresh(force = true) }
            return START_STICKY
        } else if (intent?.action == ACTION_RESTORE) {
            DirectAudioSetup.restorePause(this) { refresh(force = true) }
            return START_STICKY
        }
        refresh(force = true)
        return START_STICKY
    }

    override fun onDestroy() {
        main.removeCallbacks(tick)
        if (unlockRegistered) unregisterReceiver(unlock)
        if (networkRegistered) try { connectivity.unregisterNetworkCallback(network) } catch (_: RuntimeException) {}
        super.onDestroy()
    }

    private fun refresh(force: Boolean = false) {
        if (checking) return
        if (try { BankingPause.tick(this) } catch (_: Exception) { BankingPause.isPaused(this) }) {
            state = "paused"
            showNotification()
            return
        }
        checking = true
        val recover = !keyRejected && (force || SystemClock.elapsedRealtime() >= nextAttempt)
        DirectAudioSetup.monitor(this, recover) { result ->
            if (result == "connecting") {
                state = result
                showNotification()
                return@monitor
            }
            checking = false
            state = if (BankingPause.isPaused(this)) "paused" else result
            if (result == "key_rejected") keyRejected = true
            if (result == "ready") {
                failures = 0
                keyRejected = false
                nextAttempt = 0L
            } else if (recover && result == "offline") {
                failures = (failures + 1).coerceAtMost(5)
                nextAttempt = SystemClock.elapsedRealtime() + (15_000L shl failures)
            }
            if (keyRejected && state == "offline") state = "key_rejected"
            showNotification()
        }
    }

    private fun showNotification() {
        try { manager.notify(NOTIFICATION, notification()) }
        catch (_: SecurityException) { /* POST_NOTIFICATIONS may be denied; the card explains this. */ }
    }

    private fun notification(): Notification {
        val icon = when (state) {
            "ready", "in_call" -> R.drawable.ic_direct_ready
            "connecting", "checking" -> R.drawable.ic_direct_working
            "paused" -> R.drawable.ic_direct_paused
            else -> R.drawable.ic_direct_offline
        }
        val detail = when (state) {
            "ready" -> R.string.direct_status_ready
            "in_call" -> R.string.direct_status_in_call
            "connecting", "checking" -> R.string.direct_status_working
            "key_rejected" -> R.string.direct_status_key_rejected
            "not_paired" -> R.string.direct_status_not_paired
            else -> R.string.direct_status_offline
        }
        val open = PendingIntent.getActivity(this, 7043,
            Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun action(code: Int, name: String) = PendingIntent.getService(this, code,
            Intent(this, DirectAudioMonitorService::class.java).setAction(name),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val content = if (state == "paused") {
            val until = BankingPause.status(this)["until"] as Long
            val remaining = ((until - System.currentTimeMillis() + 59_999L) / 60_000L).coerceAtLeast(0L)
            if (remaining == 0L) getString(R.string.direct_status_paused_wait)
            else getString(R.string.direct_status_paused, remaining)
        } else getString(detail)
        val builder = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(icon)
            .setContentTitle(getString(R.string.direct_status_title))
            .setContentText(content)
            .setContentIntent(open)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
        if (state == "paused") {
            builder.addAction(R.drawable.ic_direct_paused, getString(R.string.direct_status_extend), action(7045, ACTION_EXTEND))
            builder.addAction(R.drawable.ic_direct_ready, getString(R.string.direct_status_restore), action(7046, ACTION_RESTORE))
        } else {
            builder.addAction(R.drawable.ic_direct_working, getString(R.string.direct_status_retry), action(7044, ACTION_RETRY))
            if (BankingPause.status(this)["needsConfirmation"] == false && BankingPause.status(this)["supported"] == true) {
                builder.addAction(R.drawable.ic_direct_paused, getString(R.string.direct_status_pause), action(7047, ACTION_PAUSE))
            }
        }
        return builder.build()
    }
}

class DirectAudioBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            // A hands service we switched on for a task that died with the process must not stay on.
            com.xjanova.videogirl.hands.HandsSwitch.cleanupAfterBoot(context)
            DirectAudioMonitorService.start(context)
        }
    }
}
