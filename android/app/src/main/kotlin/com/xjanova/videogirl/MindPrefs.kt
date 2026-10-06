package com.xjanova.videogirl

import android.content.Context

/**
 * ค่าที่ผู้ใช้ตั้งไว้ในแอป อ่านจากฝั่งเนทีฟ
 *
 * ## 🔴 ทำไมต้องอ่านเอง แทนที่จะถาม Dart
 *
 * จอสายเป็นเนทีฟล้วนโดยตั้งใจ (ดู [InCallActivity]) และตอนสายดัง **Flutter
 * engine อาจยังไม่ได้เริ่มด้วยซ้ำ** ถ้าจอสายต้องรอถาม Dart ว่า "ให้เธอรับ
 * อัตโนมัติไหม" คำตอบจะมาถึงหลังสายหยุดดังไปแล้ว
 *
 * ## 🔴 สะพานนี้ผูกกันด้วยชื่อคีย์ล้วน ๆ และขาดแบบเงียบที่สุด
 *
 * `shared_preferences` ฝั่ง Android เก็บลงไฟล์ `FlutterSharedPreferences`
 * โดยเติมหน้าว่า `flutter.` ให้ทุกคีย์ · และ **`setInt` ของ Dart กลายเป็น
 * `putLong` ของ Android** ไม่ใช่ `putInt` — อ่านผิดชนิดจะได้
 * ClassCastException หรือค่าตั้งต้นเงียบ ๆ แล้วแต่รุ่น
 *
 * ชื่อคีย์ที่นี่ต้องตรงกับที่ [MindState] เขียนลงไปเป๊ะ ๆ ถ้าไม่ตรง
 * **ไม่มี error อะไรเลย** — แค่ได้ค่าตั้งต้นทุกครั้ง แล้วสวิตช์ในหน้าตั้งค่า
 * ก็ดูเหมือนไม่มีผลกับอะไร · มีเทสต์ที่อ่านซอร์สสองฝั่งมาเทียบกันคุมไว้
 * (test/native_bridge_test.dart)
 */
object MindPrefs {

    private const val FILE = "FlutterSharedPreferences"
    private const val PREFIX = "flutter."

    /// ต้องตรงกับคีย์ใน lib/state/mind_state.dart
    const val KEY_AUTO_ANSWER = "autoAnswer"
    const val KEY_RING_SECONDS = "ringSeconds"
    const val KEY_CALL_STREAM = "callStream"
    const val KEY_CONTACTS_ONLY = "autoAnswerContactsOnly"
    const val KEY_SHOW_ON_CALL = "showMindOnCall"

    /// เขียนฝั่งนี้ อ่านฝั่ง Dart (ผ่านช่อง `lastAutoAnswer` ไม่ใช่ shared_preferences
    /// ซึ่งจำค่าเก่าไว้ในหน่วยความจำ) · "เหตุผล|เวลา"
    private const val LAST_AUTO = "lastAutoAnswer"

    private fun prefs(context: Context) =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    /** ให้เธอรับสายเองไหม · ค่าตั้งต้นต้องตรงกับฝั่ง Dart */
    fun autoAnswer(context: Context): Boolean = try {
        prefs(context).getBoolean(PREFIX + KEY_AUTO_ANSWER, true)
    } catch (e: ClassCastException) {
        true
    }

    /**
     * ปล่อยให้กริ่งดังกี่วินาทีก่อนเธอรับ · 0 = รับทันที
     *
     * `getLong` ไม่ใช่ `getInt` — ดูเหตุผลในหัวไฟล์
     */
    fun ringSeconds(context: Context): Int = try {
        prefs(context).getLong(PREFIX + KEY_RING_SECONDS, 15L).toInt().coerceIn(0, 60)
    } catch (e: ClassCastException) {
        15
    }

    /**
     * ให้เธอรับเฉพาะเบอร์ในสมุดโทรศัพท์ไหม · **ปิดเป็นค่าตั้งต้น** (รับทุกสาย)
     *
     * เดิมรับเฉพาะเบอร์ในสมุดเสมอ เพราะผู้ช่วยในสายเคยรู้ตารางและความจำของเจ้าของ ·
     * ตอนนี้สายไม่มีข้อมูลส่วนตัวเลย (MindState.callPrompt) เหตุผลนั้นหมดไป · และ
     * เลขาที่รับแต่สายคนรู้จักไม่ใช่เลขา · เจ้าของ: "ไม่ยอมรับสายเองเลย"
     */
    fun contactsOnly(context: Context): Boolean = try {
        prefs(context).getBoolean(PREFIX + KEY_CONTACTS_ONLY, false)
    } catch (e: ClassCastException) {
        false
    }

    /**
     * เธอรับสายแล้วตัดไปจอของเธอ (ตัวเธอคุย + คำที่คุยกันสด ๆ) **แม้จอล็อก** ไหม
     * · เปิดเป็นค่าตั้งต้น · เจ้าของ: "ตอนเธอรับสายให้ตัดมาหน้าจอเธอ"
     *
     * ปิด = จอล็อกอยู่ก็อยู่ที่จอสายเนทีฟ (ไม่มีอะไรของแอปขึ้นทับจอล็อก)
     */
    fun showOnCall(context: Context): Boolean = try {
        prefs(context).getBoolean(PREFIX + KEY_SHOW_ON_CALL, true)
    } catch (e: ClassCastException) {
        true
    }

    /** จดว่าสายล่าสุดเธอรับเองหรือไม่ และทำไม — ให้ Dart ใส่ในรายงานและบอกเจ้าของได้ */
    fun noteAutoAnswer(context: Context, outcome: String) {
        try {
            prefs(context).edit()
                .putString(PREFIX + LAST_AUTO, "$outcome|${System.currentTimeMillis()}")
                .apply()
        } catch (e: Exception) {
            // จดไม่ได้ไม่ใช่เหตุให้จอสายพัง
        }
    }

    fun lastAutoAnswer(context: Context): String? = try {
        prefs(context).getString(PREFIX + LAST_AUTO, null)
    } catch (e: ClassCastException) {
        null
    }

    /** ช่องเสียงที่ใช้ส่งเสียงเธอเข้าสาย · ดู [CallAudio] */
    fun callStream(context: Context): String = try {
        prefs(context).getString(PREFIX + KEY_CALL_STREAM, CallAudio.STREAM_CALL)
            ?: CallAudio.STREAM_CALL
    } catch (e: ClassCastException) {
        CallAudio.STREAM_CALL
    }
}
