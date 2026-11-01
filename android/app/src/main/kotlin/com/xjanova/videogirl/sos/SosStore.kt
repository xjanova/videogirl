package com.xjanova.videogirl.sos

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * แผน + สถิติ · แผนอยู่ใน [SosVault] (เข้ารหัส) · สถิติอยู่ใน prefs เพราะไม่มีข้อมูลส่วนตัว (ไม่มีพิกัด ไม่มีเบอร์)
 *
 * 🔴 นับการซ้อมแยกจากเหตุจริงเสมอ · ด่านเปิดโทรอัตโนมัติอ่าน [drills] · เหตุจริงอ่าน [cooldown] ·
 * ซ้อมต้องไม่ไปกินโควตาหรือเวลาพักของเหตุจริง
 */
object SosStore {
    const val PLAN = "plan"
    const val PROFILE = "profile"
    private const val PREFS = "giggok_sos"
    private const val MAX_READINGS = 30

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun plan(c: Context): SosPlan? = SosVault.read(c, PLAN)?.let { parse(it) }

    fun parse(json: String): SosPlan? = try {
        val o = JSONObject(json)
        SosPlan(
            armed = o.optBoolean("armed"),
            autoCall = o.optBoolean("autoCall"),
            countdownSec = o.optInt("countdownSec", 30).coerceIn(10, 120),
            manualCountdownSec = o.optInt("manualCountdownSec", 5).coerceIn(3, 30),
            routes = o.getJSONObject("routes").let { r ->
                r.keys().asSequence().associateWith { k -> strings(r.getJSONArray(k)) }
            },
            abroad = strings(o.getJSONArray("abroad")),
            contacts = o.getJSONArray("contacts").let { a ->
                (0 until a.length()).map {
                    val p = a.getJSONObject(it)
                    SosContact(p.optString("name"), p.optString("number"), p.optBoolean("health", true))
                }
            },
            testNumber = o.optString("testNumber"),
            sensitivity = o.optInt("sensitivity", 1).coerceIn(0, 2),
            th = texts(o.getJSONObject("th")),
            en = texts(o.getJSONObject("en")),
        )
    } catch (e: Exception) {
        android.util.Log.w("GigGokSos", "plan: ${e.javaClass.simpleName}")
        null
    }

    private fun strings(a: JSONArray) = (0 until a.length()).map { a.getString(it) }

    private fun texts(o: JSONObject) = SosTexts(
        alertPrompt = o.getString("alertPrompt"),
        sms = o.getString("sms"),
        smsHealth = o.optString("smsHealth"),
        smsLow = o.getString("smsLow"),
        smsCancel = o.getString("smsCancel"),
        smsDrillPrefix = o.getString("smsDrillPrefix"),
        scriptOpen = o.getJSONObject("scriptOpen").let { r -> r.keys().asSequence().associateWith { r.getString(it) } },
        scriptWho = o.optString("scriptWho"),
        scriptWhere = o.getString("scriptWhere"),
        scriptNoFix = o.getString("scriptNoFix"),
        scriptClose = o.optString("scriptClose"),
        ageNow = o.getString("ageNow"),
        ageOld = o.getString("ageOld"),
        noFix = o.getString("noFix"),
        smsSilent = o.optString("smsSilent"),
        scriptCloseSilent = o.optString("scriptCloseSilent"),
    )

    // ── สถิติ ──

    fun drills(c: Context): Int = prefs(c).getInt("drills", 0)
    fun addDrill(c: Context) = prefs(c).edit().putInt("drills", drills(c) + 1).apply()

    /** เหตุจริงล่าสุดจบเมื่อไหร่ · แรงกระแทกซ้ำในช่วงพัก = รถคันเดิมกำลังถูกลาก ไม่ใช่เหตุใหม่ */
    fun cooldownUntil(c: Context): Long = prefs(c).getLong("cooldown", 0)
    fun cooldown(c: Context, untilMs: Long) = prefs(c).edit().putLong("cooldown", untilMs).apply()

    fun addReading(c: Context, r: ImpactDetector.Reading) {
        val a = try {
            JSONArray(prefs(c).getString("readings", "[]"))
        } catch (e: Exception) {
            JSONArray()
        }
        a.put(
            JSONObject()
                .put("at", r.atMs)
                .put("peak", r.peakG)
                .put("dv", r.deltaV)
                .put("before", r.speedBefore ?: JSONObject.NULL)
                .put("after", r.speedAfter ?: JSONObject.NULL)
                .put("fall", r.freeFall)
                .put("still", r.still)
                .put("verdict", r.verdict)
        )
        while (a.length() > MAX_READINGS) a.remove(0)
        prefs(c).edit().putString("readings", a.toString()).apply()
    }

    fun readings(c: Context): String = prefs(c).getString("readings", "[]") ?: "[]"

    fun addBattery(c: Context, armedMs: Long, tripMs: Long, percent: Int) {
        val p = prefs(c)
        p.edit()
            .putLong("armedMs", p.getLong("armedMs", 0) + armedMs)
            .putLong("tripMs", p.getLong("tripMs", 0) + tripMs)
            .putInt("batteryDrop", p.getInt("batteryDrop", 0) + percent)
            .apply()
    }

    fun battery(c: Context): Map<String, Any> {
        val p = prefs(c)
        return mapOf(
            "armedMs" to p.getLong("armedMs", 0),
            "tripMs" to p.getLong("tripMs", 0),
            "batteryDrop" to p.getInt("batteryDrop", 0),
        )
    }

    /** เหตุที่ยังไม่จบ · ระบบปิดแอปกลางเหตุแล้วต้องทำต่อได้ · 🔒 ชนิดเหตุกับเวลาเท่านั้น */
    data class Live(val kind: SosKind, val how: SosTrigger, val confidence: SosConfidence, val atMs: Long, val silent: Boolean)

    // commit ไม่ใช่ apply · บันทึกนี้มีไว้สำหรับตอนโปรเซสตายทันที
    fun saveLive(c: Context, kind: SosKind, how: SosTrigger, confidence: SosConfidence, atMs: Long, silent: Boolean) {
        prefs(c).edit().putString("live", "${kind.name}|${how.name}|${confidence.name}|$atMs|$silent").commit()
    }

    fun live(c: Context): Live? {
        val p = prefs(c).getString("live", null)?.split('|') ?: return null
        return try {
            Live(SosKind.valueOf(p[0]), SosTrigger.valueOf(p[1]), SosConfidence.valueOf(p[2]), p[3].toLong(), p.getOrNull(4).toBoolean())
        } catch (e: Exception) {
            null
        }
    }

    fun clearLive(c: Context) {
        prefs(c).edit().remove("live").commit()
    }

    /** null = ยังไม่รู้ · เครื่องที่ยังไม่เคยเปิดระบบ */
    fun thaiVoice(c: Context): Boolean? = prefs(c).let { if (it.contains("thaiVoice")) it.getBoolean("thaiVoice", false) else null }
    fun thaiVoice(c: Context, has: Boolean) = prefs(c).edit().putBoolean("thaiVoice", has).apply()

    /** เจ้าของลบข้อมูลฉุกเฉิน · 🔴 ด่านโทรอัตโนมัติกลับไปเริ่มใหม่ด้วย */
    fun wipe(c: Context) {
        SosVault.delete(c, PLAN)
        SosVault.delete(c, PROFILE)
        prefs(c).edit().clear().apply()
    }
}
