package com.xjanova.videogirl.hands

import android.content.Context
import android.media.AudioManager
import android.telecom.TelecomManager
import com.xjanova.videogirl.MindInCallService

/**
 * สถานะงานที่มายด์ทำในเครื่องแทนเจ้าของ · ทุกช่องอ่าน/เขียนข้ามเธรดได้
 *
 * 🔴 ปุ่มหยุดบังคับด้วยโค้ดที่นี่ ไม่ใช่ฝั่ง Dart · กดหยุดแล้ว [stopRequested] ค้างจนกว่า
 * จะเริ่มงานใหม่ และระหว่างนั้นทุกคำสั่งที่แตะเครื่อง (อ่านจอ กด พิมพ์ เปิดแอป) ตอบ `stopped` ทันที
 */
internal object HandsControl {
    @Volatile var stopRequested = false
        private set
    @Volatile var running = false
        private set
    @Volatile var recording = false
        private set
    @Volatile var recordDone = false

    /** งานนี้สั่งมาจากคนในสายที่ยืนยันตัวแล้ว (begin inCall=true) · ดู [blockReason] */
    @Volatile var inCall = false
        private set

    /** หัวแจ้งเตือน (ส่งมาจาก Dart ตอนเริ่ม) และบรรทัดล่าสุด · ข้อความของเจ้าของ ไม่ลง log */
    @Volatile var title = ""
    @Volatile var line = ""
    @Volatile var step = 0

    /** คำถามที่รอเจ้าของตอบอยู่ (null = ไม่มี) · คำตอบของคำถามอื่นถูกทิ้ง */
    @Volatile var askId: Int? = null
        private set

    /** คำตอบที่ยังไม่ส่งให้ Dart · (เลขคำถาม, ทำได้ไหม) */
    @Volatile private var pendingAnswer: Pair<Int, Boolean>? = null

    val active: Boolean get() = running || recording

    /** จองงานใหม่ · false = มีงานอยู่แล้ว · เรียกจากเธรดหลักเท่านั้น (ช่องของ Dart ตอบที่นั่น) */
    @Synchronized fun claim(record: Boolean, title: String, inCall: Boolean = false): Boolean {
        if (running || recording) return false
        stopRequested = false
        recordDone = false
        this.inCall = inCall && !record
        pendingAnswer = null
        askId = null
        this.title = title
        line = ""
        step = 0
        if (record) recording = true else running = true
        return true
    }

    /** จบงาน (หรือเริ่มไม่สำเร็จ) */
    @Synchronized fun release() {
        running = false
        recording = false
        inCall = false
        askId = null
    }

    fun requestStop() {
        stopRequested = true
    }

    /**
     * ห้ามแตะเครื่องตอนนี้เพราะอะไร · null = แตะได้ · เรียกก่อนทุกอย่างที่อ่านจอหรือแตะเครื่อง
     *
     * - 'stopped' เจ้าของกดหยุด
     * - 'in_call' 🔴 งานที่สั่งจากแชท แต่ตอนนี้สายเข้า/มีสายอยู่ · กดย้อนกลับ/หน้าหลักทับจอสายเข้า
     *   = เจ้าของพลาดสาย (หรือวางสายโดยไม่ตั้งใจ) · งานที่คนในสายสั่ง (inCall) ไม่โดนกัน
     */
    fun blockReason(context: Context): String? {
        if (stopRequested) return "stopped"
        if (!inCall && phoneBusy(context)) return "in_call"
        return null
    }

    /**
     * สายดังหรือมีสายอยู่ · เหมือน BankingPause.phoneBusy ยกเว้นตอนไม่มีสิทธิ์ถามระบบสาย
     *
     * isInCall ต้องมี READ_PHONE_STATE (หรือเป็นแอปโทรศัพท์หลัก) · ไม่มี = SecurityException ·
     * นับเป็น "มีสายตลอด" แบบ BankingPause จะทำให้ใช้เครื่องแทนไม่ได้เลย จึงดูโหมดเสียงแทน
     * (เสียงเรียกเข้า / สายโทรศัพท์) · ไม่นับ MODE_IN_COMMUNICATION เพราะเสียงคุยกับเธอในแอป
     * (WebRTC) ก็ตั้งโหมดนี้ · ผิดพลาดแบบอื่น = ถือว่ามีสาย (กันไว้ก่อน)
     */
    fun phoneBusy(context: Context): Boolean {
        if (MindInCallService.current != null) return true
        try {
            if (context.getSystemService(TelecomManager::class.java)?.isInCall == true) return true
        } catch (_: SecurityException) {
            // ไม่มีสิทธิ์ถามระบบสาย · ดูโหมดเสียงข้างล่าง
        } catch (_: RuntimeException) {
            return true
        }
        val mode = context.getSystemService(AudioManager::class.java)?.mode
        return mode == AudioManager.MODE_RINGTONE || mode == AudioManager.MODE_IN_CALL
    }

    fun ask(id: Int) {
        pendingAnswer = null
        askId = id
    }

    /** เจ้าของกดในแจ้งเตือน · รับเฉพาะคำถามที่ถามอยู่ */
    @Synchronized fun answer(id: Int, allow: Boolean): Boolean {
        if (askId != id) return false
        askId = null
        pendingAnswer = id to allow
        return true
    }

    fun askDone(id: Int) {
        if (askId == id) askId = null
    }

    /** ส่งคำตอบให้ Dart ครั้งเดียว */
    @Synchronized fun takeAnswer(): Pair<Int, Boolean>? {
        val a = pendingAnswer
        pendingAnswer = null
        return a
    }
}
