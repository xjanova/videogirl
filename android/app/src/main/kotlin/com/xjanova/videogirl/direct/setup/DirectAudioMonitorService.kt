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
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.xjanova.videogirl.BackgroundWake
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

        private const val MISSED_CHANNEL = "giggok_direct_missed"
        private const val MISSED = 7052
        private const val PI_MISSED_OPEN = 7053
        private const val PI_MISSED_RETRY = 7054

        @Volatile private var instance: DirectAudioMonitorService? = null
        @Volatile private var retryAfterCall = false

        fun start(context: Context) {
            try {
                ContextCompat.startForegroundService(context.applicationContext,
                    Intent(context, DirectAudioMonitorService::class.java))
            } catch (_: RuntimeException) { /* Background-start restrictions: next resume catches up. */ }
        }

        /**
         * She let a call ring because the helper was gone. The owner may not be at the phone, and the
         * ongoing card is silent, so say it once out loud. The reconnect waits for the call to end
         * ([callsGone]): setup refuses during a call, and a try while it rings only lengthens the back-off.
         */
        fun missedCall(context: Context) {
            retryAfterCall = true
            val app = context.applicationContext
            val manager = app.getSystemService(NotificationManager::class.java) ?: return
            try {
                manager.createNotificationChannel(NotificationChannel(MISSED_CHANNEL,
                    app.getString(R.string.direct_missed_channel), NotificationManager.IMPORTANCE_HIGH))
                val open = PendingIntent.getActivity(app, PI_MISSED_OPEN,
                    Intent(app, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val retry = PendingIntent.getForegroundService(app, PI_MISSED_RETRY,
                    Intent(app, DirectAudioMonitorService::class.java).setAction(ACTION_RETRY),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val text = app.getString(R.string.direct_missed_text)
                manager.notify(MISSED, NotificationCompat.Builder(app, MISSED_CHANNEL)
                    .setSmallIcon(R.drawable.ic_direct_offline)
                    .setContentTitle(app.getString(R.string.direct_missed_title))
                    .setContentText(text)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(text))
                    .setContentIntent(open)
                    .setAutoCancel(true)
                    .addAction(R.drawable.ic_direct_working, app.getString(R.string.direct_status_retry), retry)
                    .build())
            } catch (_: RuntimeException) { /* POST_NOTIFICATIONS denied: the call screen already said it. */ }
        }

        /** No call left. Telecom can still say "in call" for a moment, so the reconnect waits a little. */
        fun callsGone(context: Context) {
            if (!retryAfterCall) return
            retryAfterCall = false
            val app = context.applicationContext
            Handler(Looper.getMainLooper()).postDelayed({
                val running = instance
                if (running != null) running.retry() else start(app)
            }, 3000)
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
    private var shown: String? = null
    /** A retry asked for while a check runs: run it when that check ends, not drop it. */
    private var retryPending = false
    private val power by lazy { getSystemService(PowerManager::class.java) }
    private val network = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) { main.post { refresh(force = true) } }
    }
    private val unlock = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) { refresh(force = true) }
    }
    /**
     * Every 15 s while the screen is on, every 60 s while it is off: the owner can only see this card,
     * or use direct audio, with the screen on, and unlocking checks at once ([unlock]). Network changes
     * check at once too.
     */
    private val tick = object : Runnable {
        override fun run() {
            refresh()
            BackgroundWake.drop()
            main.postDelayed(this, if (power?.isInteractive != false) 15_000L else 60_000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
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
            retry()
            return START_STICKY
        } else if (intent?.action == ACTION_PAUSE) {
            if (BankingPause.status(this)["needsConfirmation"] == false) {
                DirectAudioSetup.pause(this, 5, "notification") { refresh(force = true) }
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
        if (instance === this) instance = null
        main.removeCallbacks(tick)
        if (unlockRegistered) unregisterReceiver(unlock)
        if (networkRegistered) try { connectivity.unregisterNetworkCallback(network) } catch (_: RuntimeException) {}
        super.onDestroy()
    }

    /** The owner's button, or the end of a call she let ring: try now, past any back-off. */
    private fun retry() {
        keyRejected = false
        nextAttempt = 0L
        if (checking) retryPending = true else refresh(force = true)
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
            // Back up: the "she let a call ring" card is no longer true.
            if (result == "ready") manager.cancel(MISSED)
            showNotification()
            if (retryPending) { retryPending = false; main.post { retry() } }
        }
    }

    /** Posts only a card that changed: an unchanged repost every tick woke the system and the shade for nothing. */
    private fun showNotification() {
        val key = "$state|${content()}|${canPause()}"
        if (key == shown) return
        try {
            manager.notify(NOTIFICATION, notification())
            shown = key
        } catch (_: SecurityException) { /* POST_NOTIFICATIONS may be denied; the card explains this. */ }
    }

    private fun canPause(): Boolean {
        val pause = BankingPause.status(this)
        return pause["needsConfirmation"] == false && pause["supported"] == true
    }

    private fun content(): String {
        if (state == "paused") {
            val until = BankingPause.status(this)["until"] as Long
            val remaining = ((until - System.currentTimeMillis() + 59_999L) / 60_000L).coerceAtLeast(0L)
            return if (remaining == 0L) getString(R.string.direct_status_paused_wait)
            else getString(R.string.direct_status_paused, remaining)
        }
        return getString(when (state) {
            "ready" -> R.string.direct_status_ready
            "in_call" -> R.string.direct_status_in_call
            "connecting", "checking" -> R.string.direct_status_working
            "key_rejected" -> R.string.direct_status_key_rejected
            "not_paired" -> R.string.direct_status_not_paired
            else -> R.string.direct_status_offline
        })
    }

    private fun notification(): Notification {
        val icon = when (state) {
            "ready", "in_call" -> R.drawable.ic_direct_ready
            "connecting", "checking" -> R.drawable.ic_direct_working
            "paused" -> R.drawable.ic_direct_paused
            else -> R.drawable.ic_direct_offline
        }
        val open = PendingIntent.getActivity(this, 7043,
            Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun action(code: Int, name: String) = PendingIntent.getService(this, code,
            Intent(this, DirectAudioMonitorService::class.java).setAction(name),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(icon)
            .setContentTitle(getString(R.string.direct_status_title))
            .setContentText(content())
            .setContentIntent(open)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
        if (state == "paused") {
            builder.addAction(R.drawable.ic_direct_paused, getString(R.string.direct_status_extend), action(7045, ACTION_EXTEND))
            builder.addAction(R.drawable.ic_direct_ready, getString(R.string.direct_status_restore), action(7046, ACTION_RESTORE))
        } else {
            builder.addAction(R.drawable.ic_direct_working, getString(R.string.direct_status_retry), action(7044, ACTION_RETRY))
            if (canPause()) {
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
