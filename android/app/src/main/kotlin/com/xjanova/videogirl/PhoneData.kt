package com.xjanova.videogirl

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.provider.Telephony
import androidx.core.content.ContextCompat

/**
 * ของในเครื่องที่เธอเปิดดูตอนเจ้าของถามในแชท — สมุดโทรศัพท์ · SMS · แอปเมล
 *
 * เจ้าของ: "ตอนนี้เธอไม่เห็นสมุดโทรศัพท์ ไม่เห็นสายโทรเข้าออกล่าสุด หรือ sms
 * ต้องทำให้เธอรับรู้ได้" · ฝั่ง Dart (PhoneLookup) อ่านผ่านตรงนี้เฉพาะตอนเธอขอ
 * ด้วยแท็กในแชท · ไม่มีรายการไหนถูกยัดเข้า system prompt ทั้งก้อน
 *
 * ## 🔴 กติกา
 *
 * - อ่านอย่างเดียว · ไม่ส่ง ไม่ลบ ไม่แก้ SMS หรือรายชื่อ
 * - ห้ามต่อ "LIMIT n" ท้าย sortOrder · provider รุ่นใหม่โยน
 *   `IllegalArgumentException: Invalid token LIMIT` (ดู [CallBridge.recentCalls]) ·
 *   นับเองในลูป และหยุดสแกนที่ [SCAN_CAP] แถว
 * - null = อ่านไม่ได้ (ยังไม่ให้สิทธิ์ / provider ล้ม) · [] = อ่านได้แต่ไม่เจอ ·
 *   คนละเรื่องกัน ฝั่ง Dart บอกเธอคนละอย่าง
 * - ห้าม log เบอร์ ชื่อ หรือเนื้อ SMS · รายงานบั๊กออกนอกเครื่องได้
 * - ทุกฟังก์ชันช้าได้ (สมุดใหญ่ / SMS หลายพันข้อความ) · ผู้เรียกต้องรันนอกเธรดหลัก
 */
class PhoneData(private val context: Context, private val calls: CallBridge) {

    private fun granted(permission: String) =
        ContextCompat.checkSelfPermission(context, permission) ==
            PackageManager.PERMISSION_GRANTED

    fun canReadSms() = granted(Manifest.permission.READ_SMS)

    /**
     * ค้นสมุดโทรศัพท์ด้วยชื่อ**หรือ**เบอร์ · [query] ว่าง = คนติดดาวก่อน แล้วเรียงตามชื่อ
     *
     * ชื่อใช้ `LIKE %q%` ไม่ใช่ CONTENT_FILTER_URI · ตัวกรองของระบบเทียบแค่ต้นคำ
     * แต่ชื่อไทยไม่มีช่องว่าง ("คุณแม่" ค้น "แม่" ไม่เจอ) · เบอร์ใช้ตัวกรองของระบบ
     * เพราะเบอร์เดียวกันถูกบันทึกได้หลายรูป (+66… / 0… / มีขีด)
     *
     * คืน `{total, items}` · total = จำนวนรายชื่อที่มีเบอร์ทั้งสมุด
     */
    fun contacts(query: String, limit: Int): Map<String, Any?>? {
        if (!calls.canReadContacts()) return null
        val cap = limit.coerceIn(1, 50)
        val q = query.trim()
        val out = LinkedHashMap<String, Map<String, Any?>>()
        val phone = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
        val cols = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER,
            ContactsContract.CommonDataKinds.Phone.TYPE,
            ContactsContract.CommonDataKinds.Phone.LABEL,
            ContactsContract.CommonDataKinds.Phone.STARRED
        )

        fun collect(uri: Uri, selection: String?, args: Array<String>?, sort: String?) {
            context.contentResolver.query(uri, cols, selection, args, sort)?.use { c ->
                var scanned = 0
                while (c.moveToNext() && out.size < cap && scanned++ < SCAN_CAP) {
                    val name = c.getString(0) ?: continue
                    val number = c.getString(1) ?: continue
                    val key = number.filter { it.isDigit() }.takeLast(9)
                    if (key.isEmpty() || out.containsKey(key)) continue
                    val label = ContactsContract.CommonDataKinds.Phone
                        .getTypeLabel(context.resources, c.getInt(2), c.getString(3))
                        ?.toString()
                    out[key] = mapOf(
                        "name" to name,
                        "number" to number,
                        "label" to label,
                        "starred" to (c.getInt(4) == 1)
                    )
                }
            }
        }

        return try {
            if (q.isEmpty()) {
                collect(
                    phone, null, null,
                    "${ContactsContract.CommonDataKinds.Phone.STARRED} DESC, " +
                        "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} COLLATE LOCALIZED ASC"
                )
            } else {
                collect(
                    phone,
                    "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} LIKE ?",
                    arrayOf("%$q%"),
                    "${ContactsContract.CommonDataKinds.Phone.STARRED} DESC, " +
                        "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} COLLATE LOCALIZED ASC"
                )
                if (q.count { it.isDigit() } >= 3 && out.size < cap) {
                    collect(
                        Uri.withAppendedPath(
                            ContactsContract.CommonDataKinds.Phone.CONTENT_FILTER_URI,
                            Uri.encode(q)
                        ),
                        null, null, null
                    )
                }
            }
            mapOf("total" to contactTotal(), "items" to out.values.toList())
        } catch (e: Exception) {
            null
        }
    }

    /**
     * ทั้งสมุดแบบย่อ (ชื่อ · เบอร์) ให้ฝั่ง Dart หาชื่อที่ใกล้เคียงตอนสั่งโทร
     *
     * เจ้าของ: "ให้เธอโทรออกหาลูกค้าชื่อบัว เธอบอกไม่มี แทนที่จะค้นรายชื่อที่ใกล้เคียงมาถามฉันก่อน" ·
     * `LIKE` หา "บัว" ไม่เจอเมื่อสมุดเขียน "บัวร์" / "Bua" หรือเธอเขียน "ลูกค้าบัว" ·
     * เทียบความใกล้เคียงต้องเห็นทุกชื่อ · ผลไม่ออกจากเครื่อง (ฝั่ง Dart คัดเหลือไม่กี่ชื่อให้เจ้าของเลือก)
     *
     * เรียงคนที่ติดต่อบ่อยก่อน · หยุดที่ [INDEX_CAP] รายการ
     */
    fun contactIndex(): List<Map<String, String>>? {
        if (!calls.canReadContacts()) return null
        val out = LinkedHashMap<String, Map<String, String>>()
        return try {
            context.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER
                ),
                null, null,
                "${ContactsContract.CommonDataKinds.Phone.TIMES_CONTACTED} DESC"
            )?.use { c ->
                while (c.moveToNext() && out.size < INDEX_CAP) {
                    val name = c.getString(0) ?: continue
                    val number = c.getString(1) ?: continue
                    val key = number.filter { it.isDigit() }.takeLast(9)
                    if (key.isEmpty() || out.containsKey(key)) continue
                    out[key] = mapOf("name" to name, "number" to number)
                }
            }
            out.values.toList()
        } catch (e: Exception) {
            null
        }
    }

    private fun contactTotal(): Int = try {
        context.contentResolver.query(
            ContactsContract.Contacts.CONTENT_URI,
            arrayOf(ContactsContract.Contacts._ID),
            "${ContactsContract.Contacts.HAS_PHONE_NUMBER} = 1",
            null, null
        )?.use { it.count } ?: 0
    } catch (e: Exception) {
        0
    }

    /**
     * SMS ล่าสุด (กล่องเข้า + ที่ส่งออก) · [query] ว่าง = ล่าสุดทั้งหมด
     *
     * [query] ตรงกับ ชื่อในสมุด · ผู้ส่ง (เบอร์หรือชื่อธุรกิจเช่น "KBank") · เนื้อข้อความ ·
     * เบอร์เทียบเลขท้าย 8 หลัก เพราะ +66 กับ 0 นำหน้าไม่ตรงกัน
     *
     * 🔴 RCS ("แชท" ของ Google Messages) ไม่อยู่ใน content://sms · เห็นแค่ SMS/MMS ธรรมดา
     */
    fun sms(query: String, limit: Int): List<Map<String, Any?>>? {
        if (!canReadSms()) return null
        val cap = limit.coerceIn(1, 50)
        val q = query.trim()
        val qLower = q.lowercase()
        val qDigits = q.filter { it.isDigit() }
        val names = HashMap<String, String?>()
        val out = ArrayList<Map<String, Any?>>()
        return try {
            context.contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                arrayOf(
                    Telephony.Sms.ADDRESS,
                    Telephony.Sms.BODY,
                    Telephony.Sms.DATE,
                    Telephony.Sms.TYPE,
                    Telephony.Sms.READ
                ),
                null, null,
                Telephony.Sms.DATE + " DESC"
            )?.use { c ->
                var scanned = 0
                while (c.moveToNext() && out.size < cap && scanned++ < SCAN_CAP) {
                    val address = c.getString(0) ?: ""
                    val body = c.getString(1) ?: ""
                    val name = names.getOrPut(address) { calls.nameFor(address) }
                    if (q.isNotEmpty()) {
                        val digits = address.filter { it.isDigit() }
                        val hit = address.lowercase().contains(qLower) ||
                            (name?.lowercase()?.contains(qLower) == true) ||
                            body.lowercase().contains(qLower) ||
                            (qDigits.length >= 6 && digits.isNotEmpty() &&
                                digits.takeLast(8) == qDigits.takeLast(8))
                        if (!hit) continue
                    }
                    out.add(
                        mapOf(
                            "address" to address,
                            "name" to name,
                            "body" to if (body.length > BODY_CAP) body.substring(0, BODY_CAP) else body,
                            "at" to c.getLong(2),
                            "type" to c.getInt(3),
                            "read" to (c.getInt(4) == 1)
                        )
                    )
                }
            }
            out
        } catch (e: Exception) {
            null
        }
    }

    /**
     * แอปเมลที่เปิดได้ในเครื่อง · (ชื่อบนไอคอน, แพ็กเกจ) · Gmail มาก่อนถ้ามี
     *
     * หาจากแอปที่รับ `mailto:` (ต้องประกาศใน `<queries>` ของ manifest ·
     * Android 11+ ไม่ประกาศ = เห็นแค่แอปตัวเอง) รวมกับรายชื่อแอปเมลที่รู้จัก ·
     * เอาเฉพาะที่มีไอคอนบนหน้าแอป เพราะมือของเธอเปิดได้แค่แอปแบบนั้น
     */
    fun mailApps(): List<Map<String, String>> {
        val pm = context.packageManager
        val found = LinkedHashSet<String>()
        try {
            val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
            val handlers = if (Build.VERSION.SDK_INT >= 33) {
                pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.queryIntentActivities(intent, 0)
            }
            handlers.mapNotNullTo(found) { it.activityInfo?.packageName }
        } catch (_: Exception) {
        }
        KNOWN_MAIL.forEach { found.add(it) }
        val ordered = found.sortedBy { KNOWN_MAIL.indexOf(it).let { i -> if (i < 0) Int.MAX_VALUE else i } }
        val out = ArrayList<Map<String, String>>()
        for (pkg in ordered) {
            if (pkg == context.packageName) continue
            val launchable = try {
                pm.getLaunchIntentForPackage(pkg) != null
            } catch (_: Exception) {
                false
            }
            if (!launchable) continue
            val label = try {
                pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
            } catch (_: Exception) {
                pkg
            }
            out.add(mapOf("name" to label, "package" to pkg))
        }
        return out
    }

    companion object {
        /** สแกนไม่เกินเท่านี้แถวต่อครั้ง · SMS หลายหมื่นข้อความไม่ทำให้ค้าง */
        private const val SCAN_CAP = 600

        /** สมุดใหญ่กว่านี้ ชื่อที่ไม่ค่อยติดต่อหลุดจากการเทียบ · ส่งข้ามช่องทางราว 200 KB ที่เพดาน */
        private const val INDEX_CAP = 5000

        /** เนื้อ SMS ยาวกว่านี้ตัดทิ้ง · เธอต้องการใจความ ไม่ใช่โฆษณาทั้งก้อน */
        private const val BODY_CAP = 400

        /** แอปเมลที่คนใช้กันมาก · ลำดับนี้คือลำดับที่แสดง */
        private val KNOWN_MAIL = listOf(
            "com.google.android.gm",
            "com.microsoft.office.outlook",
            "com.yahoo.mobile.client.android.mail",
            "com.samsung.android.email.provider",
            "com.vivo.email",
            "com.android.email",
            "ch.protonmail.android",
            "com.readdle.spark",
            "me.bluemail.mail",
            "com.fsck.k9",
            "net.thunderbird.android",
            "com.zoho.mail",
            "com.google.android.gm.lite"
        )
    }
}
