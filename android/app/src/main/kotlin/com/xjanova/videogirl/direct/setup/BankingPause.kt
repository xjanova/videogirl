package com.xjanova.videogirl.direct.setup

import android.Manifest
import android.content.Context
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.provider.Settings
import android.telecom.TelecomManager
import com.xjanova.videogirl.MindAccessibility
import com.xjanova.videogirl.MindInCallService
import com.xjanova.videogirl.hands.HandsService
import com.xjanova.videogirl.hands.HandsSwitch
import com.xjanova.videogirl.hands.MindHands
import android.content.ComponentName
import org.json.JSONObject

/**
 * An explicit, timed pause. Changes only the owner's debugging switches and our two accessibility
 * entries: MindAccessibility (call audio) and MindHands (Mind using the phone). Pausing also stops a
 * running hands task. On restore MindHands comes back only if the owner had enabled it; one that
 * GigGok switched on for a task stays off.
 */
internal object BankingPause {
    private const val PREFS = "giggok_direct_control"
    private const val SNAPSHOT = "pause_snapshot"
    private const val OFF_UNTIL = "pause_off_until"
    private const val CONFIRMED = "pause_confirmed"
    private const val HANDS_ON_DEMAND = "hands_on_demand"
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

    @Synchronized fun pause(context: Context, minutes: Int): Boolean {
        require(minutes == 5 || minutes == 15 || minutes == 30)
        if (!hasPermission(context) || phoneBusy(context)) return false
        if (try { !DirectAudioSetup.restorePendingWireless(context) } catch (_: Exception) { true }) return false
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val until = System.currentTimeMillis() + minutes * 60_000L
        if (prefs.contains(SNAPSHOT)) {
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
            prefs.edit().putBoolean(CONFIRMED, true).commit()
        } catch (_: Exception) {
            restore(context)
            false
        }
    }

    @Synchronized fun extend(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.contains(SNAPSHOT)) return false
        if (try { !DirectAudioSetup.restorePendingWireless(context) } catch (_: Exception) { true }) return true
        return prefs.edit().putLong(OFF_UNTIL,
            maxOf(System.currentTimeMillis(), prefs.getLong(OFF_UNTIL, 0L)) + 5 * 60_000L).commit()
    }

    /** Returns true once the original state is restored. A live call defers restoration. */
    @Synchronized fun restore(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(SNAPSHOT, null) ?: return true
        if (!hasPermission(context) || phoneBusy(context)) return false
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
            prefs.edit().remove(SNAPSHOT).remove(OFF_UNTIL).commit()
        } catch (_: Exception) { false }
    }

    @Synchronized fun tick(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.contains(SNAPSHOT)) return false
        if (System.currentTimeMillis() >= prefs.getLong(OFF_UNTIL, 0L)) restore(context)
        else if (hasPermission(context)) try { applyOff(context) } catch (_: Exception) {}
        return prefs.contains(SNAPSHOT)
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
