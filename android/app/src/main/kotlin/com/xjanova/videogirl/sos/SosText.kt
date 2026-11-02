package com.xjanova.videogirl.sos

import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * เติมพิกัดลงข้อความ · ทุกตัวเลขใช้ [Locale.ROOT]
 *
 * 🔴 ตัวเลขทศนิยมผ่าน locale ของเครื่องได้ "13,75000" หรือเลขไทย · ลิงก์แผนที่พังเงียบ ๆ ตอนเกิดเหตุจริง
 */
object SosText {

    fun coords(fix: SosFix): String =
        String.format(Locale.ROOT, "%.6f, %.6f", fix.lat, fix.lng)

    fun mapLink(fix: SosFix): String =
        String.format(Locale.ROOT, "https://maps.google.com/?q=%.6f,%.6f", fix.lat, fix.lng)

    fun accuracy(fix: SosFix): String =
        fix.accuracyM?.let { String.format(Locale.ROOT, "±%dm", Math.round(it)) } ?: "±?"

    /** อายุพิกัด · พิกัดเก่าที่ไม่บอกว่าเก่าคือการพาคนไปผิดที่ */
    fun age(fix: SosFix, nowMs: Long, t: SosTexts): String {
        val min = ((nowMs - fix.atMs).coerceAtLeast(0)) / 60_000
        return if (min < 1) t.ageNow else t.ageOld.replace("{min}", min.toString())
    }

    fun clock(fix: SosFix, zone: ZoneId = ZoneId.systemDefault()): String =
        DateTimeFormatter.ofPattern("HH:mm", Locale.ROOT).format(Instant.ofEpochMilli(fix.atMs).atZone(zone))

    /** ตัวอักษรที่แทรกในข้อความออก · เลขตัวเดียว = 5 บรรทัด ก็ยังไม่เกินหนึ่ง SMS ภาษาไทยมากนัก */
    fun locationBlock(fix: SosFix?, nowMs: Long, t: SosTexts, zone: ZoneId = ZoneId.systemDefault()): String {
        if (fix == null) return t.noFix
        return listOf(
            mapLink(fix),
            coords(fix),
            "Plus ${PlusCode.encode(fix.lat, fix.lng)}",
            "${accuracy(fix)} ${clock(fix, zone)} (${age(fix, nowMs, t)})",
        ).joinToString("\n")
    }

    fun sms(
        t: SosTexts,
        fix: SosFix?,
        nowMs: Long,
        withHealth: Boolean,
        low: Boolean,
        drill: Boolean,
        zone: ZoneId = ZoneId.systemDefault(),
        silent: Boolean = false,
    ): String {
        val template = when {
            silent -> t.smsSilent.ifBlank { t.sms }
            low -> t.smsLow
            else -> t.sms
        }
        val body = template.replace("{loc}", locationBlock(fix, nowMs, t, zone))
        val health = if (withHealth) t.smsHealth else ""
        val all = listOf(body, health).filter { it.isNotBlank() }.joinToString("\n")
        return if (drill) "${t.smsDrillPrefix}\n$all" else all
    }

    fun cancel(t: SosTexts, drill: Boolean): String =
        if (drill) "${t.smsDrillPrefix}\n${t.smsCancel}" else t.smsCancel

    private const val SILENT_KEY = "SILENT"

    /** พูดตัวเลขทีละหลัก · "13.7" อ่านรวบ = เจ้าหน้าที่จดผิด */
    fun spokenCoord(value: Double, dot: String): String {
        val raw = String.format(Locale.ROOT, "%.5f", value)
        return raw.map { c -> if (c == '.') dot else c.toString() }.joinToString(" ")
    }

    /** บทพูดเข้าสาย: เกิดอะไร · ที่ไหน · ใคร · ปิดท้าย · ตามลำดับที่ศูนย์รับแจ้งถาม · สายหลุดกลางประโยคยังได้ที่อยู่ */
    fun script(t: SosTexts, kind: SosKind, fix: SosFix?, nowMs: Long, dot: String, silent: Boolean = false): String {
        val where = if (fix == null) {
            t.scriptNoFix
        } else {
            t.scriptWhere
                .replace("{lat}", spokenCoord(fix.lat, dot))
                .replace("{lng}", spokenCoord(fix.lng, dot))
                .replace("{age}", age(fix, nowMs, t))
                .replace("{acc}", fix.accuracyM?.let { Math.round(it).toString() } ?: "?")
        }
        val open = (if (silent) t.scriptOpen[SILENT_KEY] else null)
            ?: t.scriptOpen[kind.name] ?: t.scriptOpen[SosKind.OTHER.name].orEmpty()
        val close = if (silent) t.scriptCloseSilent.ifBlank { t.scriptClose } else t.scriptClose
        return listOf(open, where, t.scriptWho, close).filter { it.isNotBlank() }.joinToString(" ")
    }
}

/** Open Location Code ความละเอียด 10 หลัก (~14 เมตร) · อ่านออกเสียง/พิมพ์ลง Google Maps ได้ · ไม่ต้องมีเน็ต */
object PlusCode {
    private const val ALPHABET = "23456789CFGHJMPQRVWX"

    fun encode(lat: Double, lng: Double): String {
        // ตั้งใจใช้จำนวนเต็มตามสูตรมาตรฐาน · หารทศนิยมซ้ำ ๆ ปัดผิดหลักท้ายได้
        val latScaled = Math.floor((lat.coerceIn(-90.0, 90.0 - 1e-9) + 90.0) * 8000.0 + 1e-6).toLong()
        var lon = lng
        while (lon < -180.0) lon += 360.0
        while (lon >= 180.0) lon -= 360.0
        val lngScaled = Math.floor((lon + 180.0) * 8000.0 + 1e-6).toLong()
        val digits = CharArray(10)
        var la = latScaled
        var ln = lngScaled
        for (i in 4 downTo 0) {
            digits[i * 2 + 1] = ALPHABET[(ln % 20).toInt()]
            digits[i * 2] = ALPHABET[(la % 20).toInt()]
            la /= 20
            ln /= 20
        }
        val s = String(digits)
        return s.substring(0, 8) + "+" + s.substring(8)
    }
}
