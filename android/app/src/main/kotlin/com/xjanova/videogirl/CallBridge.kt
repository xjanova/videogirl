package com.xjanova.videogirl

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.CallLog
import android.provider.ContactsContract
import android.telecom.TelecomManager
import androidx.core.content.ContextCompat

/**
 * สายโทรเข้า — ฝั่ง Android
 *
 * แยกจาก MainActivity เพราะเรื่องสายมีกฎของตัวเองเยอะกว่าสิทธิ์อื่นทั้งหมด
 * รวมกัน และเกือบทุกกฎล้มแบบเงียบ ๆ
 *
 * ## 🔴 สามอย่างที่ต้องรู้ก่อนแตะโค้ดนี้
 *
 * **หนึ่ง — เบอร์ที่โทรเข้าไม่ได้มากับ broadcast อีกแล้ว**
 * ตั้งแต่ Android 9 (API 28) `EXTRA_INCOMING_NUMBER` จะเป็นค่าว่างถ้าแอป
 * ไม่มี `READ_CALL_LOG` และ**ไม่มี error ไม่มี log อะไรทั้งนั้น** ดูเหมือน
 * ทำงานปกติ แค่ไม่มีเบอร์ · ทางที่เชื่อถือได้กว่าคืออ่านจากบันทึกการโทร
 * หลังสายจบ ซึ่งเป็นสิ่งที่ [recentCalls] ทำ
 *
 * **สอง — รับสายได้ แต่พูดในสายไม่ได้**
 * `TelecomManager.acceptRingingCall()` รับสายได้จริงด้วย ANSWER_PHONE_CALLS
 * แต่**เสียงของสายเป็นทางเดินที่แอปธรรมดาแตะไม่ได้** จะป้อนเสียงเธอเข้าไป
 * หรือดึงเสียงคู่สายออกมาไม่ได้เลย ถ้าไม่ได้เป็นแอปโทรศัพท์หลัก
 * (InCallService + ผู้ใช้ตั้งเป็น default dialer เอง)
 * ดังนั้น [answer] = รับสายแล้วปล่อยเข้าลำโพงตามปกติ ไม่ใช่เธอคุยแทน
 *
 * **สาม — ชื่อผู้โทรต้องเปิดสมุดโทรศัพท์เอง**
 * ระบบไม่ได้ส่งชื่อมากับสาย ส่งมาแต่เบอร์ · [nameFor] คือที่ที่เบอร์
 * กลายเป็นคน
 */
class CallBridge(private val context: Context) {

    private fun granted(permission: String) =
        ContextCompat.checkSelfPermission(context, permission) ==
            PackageManager.PERMISSION_GRANTED

    fun canReadCalls() =
        granted(Manifest.permission.READ_PHONE_STATE) &&
            granted(Manifest.permission.READ_CALL_LOG)

    fun canReadContacts() = granted(Manifest.permission.READ_CONTACTS)

    fun canAnswer() =
        Build.VERSION.SDK_INT >= 26 &&
            granted(Manifest.permission.ANSWER_PHONE_CALLS)

    /**
     * ชื่อในสมุดโทรศัพท์ของเบอร์นี้ · null ถ้าไม่รู้จักหรือยังไม่ได้ให้สิทธิ์
     *
     * ใช้ PhoneLookup ไม่ใช่การเทียบสตริง เพราะเบอร์เดียวกันถูกบันทึกได้
     * หลายรูป (+66818884444 / 0818884444 / 081-888-4444) การเทียบเองจะพลาด
     * เกือบทุกครั้งที่เบอร์ถูกบันทึกในรูปสากล
     */
    fun nameFor(number: String?): String? {
        if (number.isNullOrBlank() || !canReadContacts()) return null

        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(number)
        )
        return try {
            context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null, null, null
            )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * ประวัติการโทรล่าสุด
     *
     * `type` ตรงกับ CallLog.Calls: 1 เข้า · 2 ออก · 3 ไม่ได้รับ · 5 ถูกปฏิเสธ
     * ส่งเป็นตัวเลขดิบไปให้ฝั่ง Dart ตีความ เพราะการแปลงเป็นคำเป็นเรื่องของ
     * ภาษา ซึ่งอยู่ฝั่งนั้นทั้งหมด
     */
    fun recentCalls(limit: Int): List<Map<String, Any?>>? {
        if (!canReadCalls()) return null

        val cols = arrayOf(
            CallLog.Calls._ID,
            CallLog.Calls.NUMBER,
            CallLog.Calls.CACHED_NAME,
            CallLog.Calls.TYPE,
            CallLog.Calls.DATE,
            CallLog.Calls.DURATION
        )
        val out = ArrayList<Map<String, Any?>>()
        val cap = limit.coerceIn(1, 200)

        // 🔴 ห้ามต่อ "LIMIT n" ท้าย sortOrder
        //
        // เคยเขียนแบบนั้นแล้วได้ IllegalArgumentException: Invalid token LIMIT
        // จาก provider โดยตรง · Android รุ่นใหม่กัน SQL ที่ยัดมาทาง sortOrder
        // ไว้ทั้งหมด (กัน injection) และเทสต์ที่ mock ฝั่ง platform ไว้
        // **จับเรื่องนี้ไม่ได้เลย** — เห็นครั้งแรกตอนรันบนเครื่องจริง
        // นับเองในลูปจึงเป็นทางที่ใช้ได้กับทุกรุ่น
        context.contentResolver.query(
            CallLog.Calls.CONTENT_URI,
            cols, null, null,
            CallLog.Calls.DATE + " DESC"
        )?.use { c ->
            while (c.moveToNext()) {
                if (out.size >= cap) break
                val number = c.getString(1)
                out.add(
                    mapOf(
                        "id" to c.getLong(0),
                        "number" to number,
                        // ชื่อที่ระบบแคชไว้อาจเก่าหรือว่าง ถามสมุดโทรศัพท์ซ้ำ
                        // ให้เสมอ ไม่งั้นคนที่เพิ่งบันทึกชื่อจะยังขึ้นเป็นเบอร์
                        "name" to (c.getString(2) ?: nameFor(number)),
                        "type" to c.getInt(3),
                        "at" to c.getLong(4),
                        "seconds" to c.getLong(5)
                    )
                )
            }
        }
        return out
    }

    /**
     * รับสายที่กำลังดังอยู่
     *
     * 🔴 อ่าน doc ของคลาสนี้ก่อน — รับได้จริง แต่เธอ **พูดในสายไม่ได้**
     * ถ้าแอปไม่ใช่แอปโทรศัพท์หลัก · คืน false เมื่อทำไม่ได้ ไม่ใช่เงียบ ๆ
     */
    fun answer(): Boolean {
        if (!canAnswer()) return false
        val tm = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
            ?: return false
        return try {
            tm.acceptRingingCall()
            true
        } catch (e: SecurityException) {
            false
        }
    }

    /** วางสายที่กำลังดังหรือกำลังคุยอยู่ */
    fun hangUp(): Boolean {
        if (!canAnswer()) return false
        val tm = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager
            ?: return false
        return try {
            @Suppress("DEPRECATION")
            tm.endCall()
        } catch (e: SecurityException) {
            false
        }
    }
}
