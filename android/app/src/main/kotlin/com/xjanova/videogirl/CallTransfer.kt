package com.xjanova.videogirl

import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.telecom.Call
import android.telecom.DisconnectCause
import android.telecom.TelecomManager
import androidx.core.content.ContextCompat

/**
 * น้องมายโอนสายคนโทรไปหาเจ้าของอีกเบอร์ — ฝั่งสาย (ลำดับบทพูดอยู่ที่ lib/phone/call_transfer.dart)
 *
 * เจ้าของ: "สามารถส่งต่อสายไปหาเจ้าของ อีกเบอร์ได้ถ้าคู่สนทนายืนยันว่าจะคุยกับเจ้าของเท่านั้น"
 *
 * ## 🔴 สิ่งที่แอปโทรศัพท์หลักทำได้จริง
 *
 * - **ไม่มีคำสั่ง "ส่งต่อสายนี้ไปเบอร์อื่น"** สำหรับสายที่รับไปแล้ว · `Call.deflect` ใช้ได้เฉพาะสายที่กำลังดัง
 *   และรหัสโอนสายของเครือข่าย (`**21*`) มีผลกับสายถัดไป ไม่ใช่สายที่คุยอยู่
 * - **โอนแบบ ECT ใช้ไม่ได้** · `Call.consultativeTransfer` กับ `CAPABILITY_TRANSFER_CONSULTATIVE` เป็น API
 *   ของแอประบบ (SystemApi) คอมไพล์กับ SDK สาธารณะไม่ผ่าน · เรียกผ่าน reflection = ชน hidden-API ของ Android 9+
 * - ทางที่มีจริงคือแบบเลขาคนจริง: โทรสายที่สองหาเจ้าของ (ระบบ**พักสายคนโทรในเครือข่าย**ให้เอง) →
 *   เจ้าของรับ → เธอบอกว่าใครโทรมาเรื่องอะไร → **รวมสาย** (conference · เครือข่ายต้องเปิดให้รวมสาย)
 * - รวมสายแล้วเครื่องนี้ยังอยู่ในวง (ไมค์ปิด) · วางจากเครื่องนี้ = วงจบทั้งวงในเครือข่ายส่วนใหญ่ จึงไม่วางเอง
 * - ระหว่างพักสายในเครือข่าย **เสียงจากแอปไปไม่ถึงคนโทร** · ไมค์และสายตรงเข้าเฉพาะสายที่คุยอยู่
 *   คนโทรได้ยินเสียงพักสายของเครือข่ายเอง (ส่วนใหญ่เงียบ) · เพลงพักสายใช้ได้กับการพักสายในแอป (ask_owner)
 * - สายคนโทรพักไม่ได้ (เครือข่าย/สายบางแบบ) = ไม่โทรสายที่สองเลย · Telecom จะไม่ยอมโทรหรือตัดสายแรกทิ้ง
 */
object CallTransfer {

    /** สายคนโทรที่เธอถือตอนเริ่มโอน · ล้างตอนจบ */
    @Volatile
    var caller: Call? = null
        private set

    /** สายที่เธอโทรหาเจ้าของ · null = ยังไม่ขึ้นมา (เพิ่งสั่งโทร) หรือจบไปแล้ว ([ended]) */
    @Volatile
    var leg: Call? = null
        private set

    @Volatile
    private var armed: Pair<String, Long>? = null

    /** สายหาเจ้าของจบเพราะอะไร · ดู [causeOf] */
    @Volatile
    private var ended: String? = null

    /** สายหาเจ้าของเคยต่อติด (เจ้าของรับแล้ว) */
    @Volatile
    private var answered = false

    /** สั่งยกเลิกไปแล้ว · สายที่ขึ้นมาทีหลังต้องวางทันที */
    @Volatile
    private var cancelled = false

    /** กำลังรวมสาย ("conference" / "merge") · ระหว่างนี้สายที่หายไปคือถูกรวม ไม่ใช่วาง */
    @Volatile
    private var connecting: String? = null

    /** รวมสายสำเร็จแล้ว · วงที่เหลือเป็นของเจ้าของ */
    @Volatile
    private var connected = false

    /** คนโทรวางไปก่อนต่อได้ */
    @Volatile
    private var callerGone = false

    /** Dart เลิกโอนแล้วแต่สายเจ้าของยังไม่หายไป · หายเมื่อไหร่ค่อยคืนสายคนโทรแล้วล้าง (ดู [finish]) */
    @Volatile
    private var finishing = false

    val active: Boolean get() = caller != null

    /**
     * เริ่มโทรหาเจ้าของ · null = กดโทรแล้ว · สตริง = เหตุผลที่โทรไม่ได้
     *
     * (bad_number · blocked · not_dialer · not_mind · busy · not_active · same_number · no_hold · no_permission)
     */
    fun start(context: Context, raw: String): String? {
        if (caller != null) return "busy"
        val number = OutgoingRules.normalize(raw) ?: return "bad_number"
        if (OutgoingRules.blocked(number)) return "blocked"
        if (!SystemBridge.isDefaultDialer(context)) return "not_dialer"
        if (!MindInCallService.mindHandling) return "not_mind"
        val top = MindInCallService.topCalls()
        if (top.size != 1) return "busy"
        val call = top[0]
        if (MindInCallService.stateOf(call) != Call.STATE_ACTIVE) return "not_active"
        val them = OutgoingRules.normalize(call.details.handle?.schemeSpecificPart ?: "")
        // โอนกลับไปหาคนที่โทรมาเอง = สายวนหาตัวเอง
        if (them != null && sameNumber(them, number)) return "same_number"
        if (!call.details.can(Call.Details.CAPABILITY_HOLD)) return "no_hold"
        if (ContextCompat.checkSelfPermission(context, android.Manifest.permission.CALL_PHONE) !=
            PackageManager.PERMISSION_GRANTED
        ) return "no_permission"
        val tm = context.getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return "no_telecom"
        // ซิมเดียวกับสายคนโทร · เครื่องสองซิมคุยได้ทีละซิม รวมสายข้ามซิมไม่ได้
        val extras = Bundle()
        call.details.accountHandle?.let { extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, it) }
        reset()
        caller = call
        armed = number to SystemClock.uptimeMillis()
        return try {
            tm.placeCall(Uri.fromParts("tel", number, null), extras)
            null
        } catch (e: SecurityException) {
            reset()
            "no_permission"
        }
    }

    /** สายที่เพิ่งเพิ่มเข้ามาคือสายหาเจ้าของที่เธอเพิ่งกดโทรไหม · ดู MindInCallService.onCallAdded */
    fun claim(call: Call): Boolean {
        val (number, at) = armed ?: return false
        if (SystemClock.uptimeMillis() - at > 60_000) {
            armed = null
            return false
        }
        val got = OutgoingRules.normalize(call.details.handle?.schemeSpecificPart ?: "") ?: return false
        if (!sameNumber(got, number)) return false
        armed = null
        leg = call
        // ยกเลิกไประหว่างระบบกำลังสร้างสาย · ไม่มีใครรอคุยกับเจ้าของแล้ว
        if (cancelled) call.disconnect()
        return true
    }

    /** สถานะสายโอน · Dart ถามถี่ ๆ ระหว่างโอน (ดู lib/phone/call_transfer.dart) */
    fun status(): Map<String, Any?> {
        val c = caller
        val l = leg
        if (connecting != null && !connected) connected = joined(c, l)
        val legState = when {
            connected -> "connected"
            l == null -> if (ended != null) "ended" else if (c == null) "none" else "dialing"
            else -> when (MindInCallService.stateOf(l)) {
                Call.STATE_ACTIVE -> "active"
                Call.STATE_HOLDING -> "held"
                Call.STATE_DISCONNECTING, Call.STATE_DISCONNECTED -> "ended"
                else -> "dialing"
            }
        }
        val callerState = when {
            callerGone -> "ended"
            c == null -> "none"
            else -> when (MindInCallService.stateOf(c)) {
                Call.STATE_ACTIVE -> "active"
                Call.STATE_HOLDING -> "held"
                Call.STATE_DISCONNECTING, Call.STATE_DISCONNECTED -> "ended"
                else -> "other"
            }
        }
        return mapOf(
            "leg" to legState,
            "ended" to (ended ?: l?.takeIf { legState == "ended" }?.let { causeOf(it.details.disconnectCause?.code ?: 0, answered) }),
            "caller" to callerState,
        )
    }

    /**
     * เจ้าของตกลงรับสาย · รวมคนโทรเข้าสายเจ้าของ · คืนวิธีที่สั่งไป หรือ "unsupported"
     *
     * สั่งแล้วยังไม่ได้แปลว่าต่อติด · ผลมาทาง [status] ("connected") ภายในไม่กี่วินาที
     * [retry] = รอบแรกสั่งรวมแล้วไม่ติด · รอบนี้ลองอีกทาง (รวมเข้าวงที่ระบบเตรียมไว้)
     */
    fun connect(retry: Boolean = false): String {
        val c = caller ?: return "unsupported"
        val l = leg ?: return "unsupported"
        if (MindInCallService.stateOf(l) != Call.STATE_ACTIVE) return "unsupported"
        val conferenceable = l.conferenceableCalls.contains(c) || c.conferenceableCalls.contains(l)
        val conference = MindInCallService.topCalls().firstOrNull {
            it.details.can(Call.Details.CAPABILITY_MERGE_CONFERENCE)
        }
        val method = connectMethod(conferenceable && !retry, conference != null)
        try {
            when (method) {
                "conference" -> l.conference(c)
                "merge" -> conference?.mergeConference()
                else -> return "unsupported"
            }
        } catch (e: Exception) {
            return "unsupported"
        }
        connecting = method
        return method
    }

    /** ไม่ต่อแล้ว (เจ้าของไม่รับ/ไม่ว่าง/หมดเวลา) · วางสายเจ้าของ แล้วคืนสายคนโทร */
    fun cancel() {
        cancelled = true
        armed = null
        // สั่งรวมไปแล้วแต่ไม่ติด · สายเจ้าของที่จะหายไปต่อจากนี้คือวาง ไม่ใช่ถูกรวม ต้องคืนสายคนโทร
        connecting = null
        val l = leg
        if (l != null && MindInCallService.stateOf(l) != Call.STATE_DISCONNECTED) {
            l.disconnect()
        } else {
            unholdCaller()
        }
    }

    /** คืนสายคนโทรที่ยังพักอยู่ · ระบบไม่คืนให้เองเมื่อสายที่สองจบ */
    fun unholdCaller() {
        val c = caller ?: return
        if (MindInCallService.stateOf(c) == Call.STATE_HOLDING) c.unhold()
    }

    /** สายหนึ่งในสองหายไปจากระบบ · ดู MindInCallService.onCallRemoved */
    fun onRemoved(call: Call) {
        if (call === leg) {
            if (ended == null) ended = causeOf(call.details.disconnectCause?.code ?: 0, answered)
            leg = null
            // ถูกรวมเข้าวง (IMS ถอดสายเดิมออกตอนรวมเสร็จ) ≠ วาง · ไม่คืนสายคนโทรทับวงที่เพิ่งรวม
            if (connecting == null) unholdCaller()
            if (finishing) reset()
        } else if (call === caller) {
            if (connecting != null || connected) return
            callerGone = true
            // ไม่มีใครให้ต่อหาแล้ว · เจ้าของรับมาก็เจอสายเปล่า
            leg?.let { if (MindInCallService.stateOf(it) != Call.STATE_DISCONNECTED) it.disconnect() }
        }
    }

    /** สถานะสายหาเจ้าของเปลี่ยน · จำว่าเจ้าของเคยรับ (วางหลังรับ = ไม่สะดวก ไม่ใช่สายไม่ว่าง) */
    fun onState(call: Call, state: Int) {
        if (call === leg && state == Call.STATE_ACTIVE) answered = true
    }

    /** โอน/รวมเสร็จ · เธอเลิกถือสาย · ที่เหลือ (รวมสาย) เป็นของเจ้าของ ไมค์เครื่องนี้ปิดไว้ ห้องนี้ไม่เข้าวง */
    fun done(context: Context) {
        val stillHere = MindInCallService.topCalls().isNotEmpty()
        MindInCallService.handOver(context)
        if (stillHere) MindInCallService.service?.setMuted(true)
        reset()
    }

    /**
     * Dart กลับมาคุยกับคนโทรแล้ว · ล้างสถานะ
     *
     * 🔴 สายเจ้าของยังไม่หายไป (สั่งวางแล้วแต่ระบบยังไม่ถอด / ยังสร้างสายไม่เสร็จ) = ยังล้างไม่ได้ ·
     * ล้างตอนนี้แล้วสายนั้นหายไปทีหลัง ไม่มีใครจำได้ว่าต้องคืนสายใคร คนโทรค้างพักสายจนวางเอง
     */
    fun finish() {
        val l = leg
        if (l != null && MindInCallService.stateOf(l) != Call.STATE_DISCONNECTED) {
            finishing = true
            cancel()
            return
        }
        if (armed != null) {
            // ยังสร้างสายไม่เสร็จ · [claim] วางทิ้งทันทีที่ขึ้นมา แล้ว [onRemoved] คืนสายคนโทร
            finishing = true
            cancelled = true
            return
        }
        unholdCaller()
        reset()
    }

    fun reset() {
        caller = null
        leg = null
        armed = null
        ended = null
        answered = false
        cancelled = false
        connecting = null
        connected = false
        callerGone = false
        finishing = false
    }

    /** รวมสายเสร็จ = มีวงขึ้นมา (IMS สร้างสายวงใหม่แล้วถอดสองสายเดิม · GSM ย้ายสองสายเข้าไปเป็นลูกวง) */
    private fun joined(c: Call?, l: Call?): Boolean =
        MindInCallService.topCalls().any {
            it.details.hasProperty(Call.Details.PROPERTY_CONFERENCE) || it.children.isNotEmpty()
        } || (c != null && c.parent != null && c.parent === l?.parent)

    /** +66812345678 กับ 0812345678 คือเบอร์เดียวกัน · เทียบท้ายเก้าหลัก (เหมือน claimOutgoing) */
    fun sameNumber(a: String, b: String): Boolean {
        val x = a.filter { it.isDigit() }
        val y = b.filter { it.isDigit() }
        if (x.isEmpty() || y.isEmpty()) return false
        return if (x.length >= 9 && y.length >= 9) x.takeLast(9) == y.takeLast(9) else x == y
    }

    /** วิธีรวมสายที่มี · รวมสองสายเข้าด้วยกัน > รวมเข้าวงที่ระบบเตรียมไว้ (บางเครือข่ายให้แค่แบบนี้) */
    fun connectMethod(conferenceable: Boolean, mergeable: Boolean): String = when {
        conferenceable -> "conference"
        mergeable -> "merge"
        else -> "unsupported"
    }

    /**
     * สายหาเจ้าของจบแบบไหน · [answered] = เจ้าของเคยรับ
     *
     * busy = สายไม่ว่าง/กดตัดสาย · hung_up = รับแล้ววาง · cancelled = เราวางเอง · unreachable = ติดต่อไม่ได้
     */
    fun causeOf(code: Int, answered: Boolean): String = when {
        answered && code != DisconnectCause.LOCAL -> "hung_up"
        code == DisconnectCause.BUSY || code == DisconnectCause.REJECTED || code == DisconnectCause.REMOTE -> "busy"
        code == DisconnectCause.LOCAL || code == DisconnectCause.CANCELED || code == DisconnectCause.MISSED -> "cancelled"
        else -> "unreachable"
    }
}
