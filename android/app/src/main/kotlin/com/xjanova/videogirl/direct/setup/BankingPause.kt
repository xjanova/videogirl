package com.xjanova.videogirl.direct.setup

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.provider.Settings
import android.telecom.TelecomManager
import com.xjanova.videogirl.MindAccessibility
import com.xjanova.videogirl.MindInCallService
import com.xjanova.videogirl.hands.HandsService
import com.xjanova.videogirl.hands.HandsSwitch
import com.xjanova.videogirl.hands.MindHands
import android.content.ComponentName
import androidx.core.app.NotificationCompat
import com.xjanova.videogirl.R
import org.json.JSONObject
import java.io.File

/**
 * An explicit, timed pause. Changes only the owner's debugging switches and our two accessibility
 * entries: MindAccessibility (call audio) and MindHands (Mind using the phone). Pausing also stops a
 * running hands task. On restore MindHands comes back only if the owner had enabled it; one that
 * GigGok switched on for a task stays off.
 *
 * Every pause, extend, restore and wait is written to `Android/data/<package>/files/banking_pause.log`
 * (and logcat tag GigGokPause). The owner once found Developer options off with nothing to say why.
 */
internal object BankingPause {
    private const val PREFS = "giggok_direct_control"
    private const val SNAPSHOT = "pause_snapshot"
    private const val OFF_UNTIL = "pause_off_until"
    private const val CONFIRMED = "pause_confirmed"
    private const val HANDS_ON_DEMAND = "hands_on_demand"
    private const val EXPECT = "restore_expect"
    private const val RESTORED_AT = "restore_at"
    private const val VERIFY_AFTER_MS = 20_000L
    private const val REVERTED_NOTIFICATION = 7048
    private var waiting: String? = null
    private val globals = arrayOf("adb_wifi_enabled", "adb_enabled", "development_settings_enabled")

    fun status(context: Context): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return mapOf(
            "paused" to prefs.contains(SNAPSHOT),
            "until" to prefs.getLong(OFF_UNTIL, 0L),
            "needsConfirmation" to !prefs.getBoolean(CONFIRMED, false),
            "supported" to hasPermission(context),
            "notificationsEnabled" to context.getSystemService(NotificationManager::class.java).areNotificationsEnabled(),
        )
    }

    fun isPaused(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).contains(SNAPSHOT)

    @Synchronized fun pause(context: Context, minutes: Int, source: String = "app"): Boolean {
        require(minutes == 5 || minutes == 15 || minutes == 30)
        if (!hasPermission(context) || phoneBusy(context)) return false
        if (try { !DirectAudioSetup.restorePendingWireless(context) } catch (_: Exception) { true }) return false
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val until = System.currentTimeMillis() + minutes * 60_000L
        if (prefs.contains(SNAPSHOT)) {
            log(context, "pause again from $source · $minutes min")
            alarm(context, until)
            return prefs.edit().putLong(OFF_UNTIL, until).commit()
        }

        val snapshot = JSONObject()
        for (key in globals) snapshot.put(key, Settings.Global.getString(context.contentResolver, key) ?: JSONObject.NULL)
        val accessibility = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        snapshot.put("enabled_accessibility_services", accessibility ?: JSONObject.NULL)
        // A hands entry GigGok added for a task is not the owner's setting; restore must not bring it back.
        val handsOnDemand = HandsSwitch.enabledByUs(context)
        snapshot.put(HANDS_ON_DEMAND, handsOnDemand)
        // Commit recovery data first. A process death between individual writes can then be repaired.
        if (!prefs.edit().putString(SNAPSHOT, snapshot.toString()).putLong(OFF_UNTIL, until).commit()) return false
        if (phoneBusy(context)) {
            prefs.edit().remove(SNAPSHOT).remove(OFF_UNTIL).commit()
            return false
        }
        // The banking app is next: Mind stops touching the phone before her service goes away.
        HandsService.requestStop(context)
        return try {
            applyOff(context)
            if (handsOnDemand) HandsSwitch.forget(context)
            log(context, "pause from $source · $minutes min · before ${values(snapshot)}")
            alarm(context, until)
            prefs.edit().putBoolean(CONFIRMED, true).commit()
        } catch (e: Exception) {
            log(context, "pause from $source failed: ${e.javaClass.simpleName}")
            restore(context)
            false
        }
    }

    @Synchronized fun extend(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.contains(SNAPSHOT)) return false
        if (try { !DirectAudioSetup.restorePendingWireless(context) } catch (_: Exception) { true }) return true
        val until = maxOf(System.currentTimeMillis(), prefs.getLong(OFF_UNTIL, 0L)) + 5 * 60_000L
        log(context, "extend +5 min")
        alarm(context, until)
        return prefs.edit().putLong(OFF_UNTIL, until).commit()
    }

    /** Returns true once the original state is restored. A live call defers restoration. */
    @Synchronized fun restore(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(SNAPSHOT, null) ?: return true
        val wait = when {
            !hasPermission(context) -> "no WRITE_SECURE_SETTINGS"
            phoneBusy(context) -> "a call is live"
            else -> null
        }
        if (wait != null) {
            if (wait != waiting) log(context, "restore waits: $wait")
            waiting = wait
            alarm(context, System.currentTimeMillis() + 60_000L)
            return false
        }
        waiting = null
        return try {
            val snapshot = JSONObject(raw)
            // Restore the controls that were on before, never turn on one that was originally off.
            for (key in globals.reversed()) {
                val previous = snapshot.opt(key).takeUnless { it == JSONObject.NULL } as? String
                check(Settings.Global.putString(context.contentResolver, key, previous))
            }
            val previous = snapshot.opt("enabled_accessibility_services").takeUnless { it == JSONObject.NULL } as? String
            val current = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            val withoutOwn = removeOwn(context, previous)
            val handsOnDemand = snapshot.optBoolean(HANDS_ON_DEMAND, false) || HandsSwitch.enabledByUs(context)
            val wanted = if (handsOnDemand) removeHands(context, previous) else previous
            val merged = if (current == withoutOwn) wanted else addOwnIfPreviouslyEnabled(context, current, wanted)
            // The flag is cleared below, so an on-demand hands entry left in place would never be switched off.
            val restored = if (handsOnDemand) removeHands(context, merged) else merged
            if (restored != current) {
                check(Settings.Secure.putString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, restored))
            }
            if (handsOnDemand) HandsSwitch.forget(context)
            val now = JSONObject()
            for (key in globals) now.put(key, Settings.Global.getString(context.contentResolver, key) ?: JSONObject.NULL)
            log(context, "restored · now ${values(now)}")
            prefs.edit().remove(SNAPSHOT).remove(OFF_UNTIL)
                .putString(EXPECT, now.toString()).putLong(RESTORED_AT, System.currentTimeMillis()).commit()
        } catch (e: Exception) {
            log(context, "restore failed: ${e.javaClass.simpleName}: ${e.message}")
            alarm(context, System.currentTimeMillis() + 60_000L)
            false
        }
    }

    @Synchronized fun tick(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        verify(context, prefs)
        if (!prefs.contains(SNAPSHOT)) return false
        if (System.currentTimeMillis() >= prefs.getLong(OFF_UNTIL, 0L)) restore(context)
        else if (hasPermission(context)) try { applyOff(context) } catch (_: Exception) {}
        return prefs.contains(SNAPSHOT)
    }

    /**
     * A ROM may switch Developer options off again right after an app turns them back on. Checked once,
     * [VERIFY_AFTER_MS] after a restore: logged, and the owner is told how to turn them on. Wireless
     * debugging is only logged: Android turns it off by itself whenever Wi-Fi drops.
     */
    private fun verify(context: Context, prefs: SharedPreferences) {
        val raw = prefs.getString(EXPECT, null) ?: return
        if (System.currentTimeMillis() - prefs.getLong(RESTORED_AT, 0L) < VERIFY_AFTER_MS) return
        prefs.edit().remove(EXPECT).remove(RESTORED_AT).commit()
        val expected = try { JSONObject(raw) } catch (_: Exception) { return }
        val resolver = context.contentResolver
        val changed = globals.filter { key ->
            (expected.opt(key).takeUnless { it == JSONObject.NULL } as? String) != Settings.Global.getString(resolver, key)
        }
        if (changed.isEmpty()) {
            log(context, "restore held")
            return
        }
        log(context, "restore did not hold: " + changed.joinToString(" ") { "$it=${Settings.Global.getString(resolver, it)}" })
        if ("development_settings_enabled" !in changed) return
        val text = context.getString(R.string.direct_pause_dev_off_text)
        val notice = NotificationCompat.Builder(context, "giggok_direct_status")
            .setSmallIcon(R.drawable.ic_direct_offline)
            .setContentTitle(context.getString(R.string.direct_pause_dev_off_title))
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .build()
        try { context.getSystemService(NotificationManager::class.java).notify(REVERTED_NOTIFICATION, notice) }
        catch (_: SecurityException) { /* Notifications denied: the log still has it. */ }
    }

    /**
     * Restores at the deadline while the phone sleeps too: the status service's timer stops in deep
     * sleep, so on its own it could leave Developer options off until the screen next came on.
     */
    private fun alarm(context: Context, at: Long) {
        try {
            val intent = PendingIntent.getBroadcast(context, 7049, Intent(context, BankingPauseReceiver::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            context.getSystemService(AlarmManager::class.java)
                .setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at + 1_000L, intent)
        } catch (_: RuntimeException) { /* The status service and the app opening still restore. */ }
    }

    private fun values(json: JSONObject) =
        globals.joinToString(" ") { "$it=${json.opt(it).takeUnless { v -> v == JSONObject.NULL } ?: "-"}" }

    private fun log(context: Context, line: String) {
        android.util.Log.i("GigGokPause", line)
        try {
            val file = File(context.getExternalFilesDir(null) ?: context.filesDir, "banking_pause.log")
            if (file.length() > 64_000L) file.writeText(file.readText().takeLast(32_000))
            val at = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date())
            file.appendText("$at $line\n")
        } catch (_: Exception) { /* Logcat still has it. */ }
    }

    private fun applyOff(context: Context) {
        val resolver = context.contentResolver
        val current = Settings.Secure.getString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        val withoutOwn = removeOwn(context, current)
        if (withoutOwn != current) {
            check(Settings.Secure.putString(resolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, withoutOwn))
        }
        for (key in globals) check(Settings.Global.putString(resolver, key, "0"))
    }

    private fun owned(context: Context) = listOf(
        ComponentName(context, MindAccessibility::class.java),
        ComponentName(context, MindHands::class.java),
    )

    private fun removeOwn(context: Context, value: String?): String? {
        if (value == null) return null
        val own = owned(context)
        return value.split(':').filter { ComponentName.unflattenFromString(it) !in own }.joinToString(":")
    }

    private fun removeHands(context: Context, value: String?): String? {
        if (value == null) return null
        val hands = ComponentName(context, MindHands::class.java)
        return value.split(':').filter { ComponentName.unflattenFromString(it) != hands }.joinToString(":")
    }

    /** [previous] already lacks a hands entry that GigGok added on demand, so only the owner's come back. */
    private fun addOwnIfPreviouslyEnabled(context: Context, current: String?, previous: String?): String? {
        var result = current
        for (own in owned(context)) {
            val oldEntry = previous?.split(':')?.firstOrNull { ComponentName.unflattenFromString(it) == own } ?: continue
            if (result?.split(':')?.any { ComponentName.unflattenFromString(it) == own } == true) continue
            result = if (result.isNullOrEmpty()) oldEntry else "$result:$oldEntry"
        }
        return result
    }

    private fun hasPermission(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS) == PackageManager.PERMISSION_GRANTED

    private fun phoneBusy(context: Context): Boolean {
        if (MindInCallService.current != null) return true
        return try { context.getSystemService(TelecomManager::class.java).isInCall }
        catch (_: RuntimeException) { true }
    }
}

/** The pause deadline, and a retry a minute later while a call keeps the restore waiting. */
class BankingPauseReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        val done = goAsync()
        Thread {
            try { BankingPause.tick(app) } catch (_: Exception) { /* The status service tries again. */ }
            finally { done.finish() }
        }.start()
    }
}
