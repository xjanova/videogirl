package com.xjanova.videogirl

import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService
import android.telecom.VideoProfile

/**
 * แอปโทรศัพท์หลัก — ฝั่งที่ระบบเรียกเมื่อมีสาย
 *
 * ## 🔴 สิ่งที่การเป็นแอปโทรศัพท์หลัก **ไม่ได้** ให้
 *
 * **ป้อนเสียงเข้าไปในสายไม่ได้** ไม่ว่าจะเป็นแอปหลักหรือไม่ก็ตาม
 * Android ไม่มี API สำหรับเรื่องนี้เลย — เสียงขาออกของสายมาจากไมค์ฮาร์ดแวร์
 * ทางเดียวที่ทำได้จริงคือเปิดลำโพงแล้วให้เธอพูดออกลำโพงให้ไมค์รับเข้าไป
 * ซึ่งเป็นสิ่งที่ [CallAudio] ทำ · อ่านหัวไฟล์นั้นก่อนคาดหวังอะไรจากเสียง
 *
 * ที่ได้จริงคือ: **การควบคุมสาย** (รับ วาง ปิดไมค์ สลับลำโพง กดโทน)
 * และ **หน้าจอสายเป็นของเราเอง** ซึ่งเป็นที่เดียวที่เธอจะโผล่มาตอนมีสายได้
 *
 * ## 🔴 เป็นแอปหลักแล้ว = รับผิดชอบ**ทุกสาย**
 *
 * ไม่ใช่แค่สายที่เราสนใจ · สายออก สายซ้อน สายประชุม ทั้งหมดต้องผ่านจอนี้
 * ถ้าจอนี้พัง เจ้าของโทรออกรับสายไม่ได้เลยทั้งเครื่อง · จอสายจึงเขียนเป็น
 * Activity เนทีฟ ไม่ใช่ Flutter — เปิด Flutter engine ตอนสายกำลังดัง
 * อาจกินหลายวินาที ซึ่งแปลว่าโทรศัพท์ดังแต่จอว่างเปล่า
 */
class MindInCallService : InCallService() {

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        current = call
        service = this
        // สายที่น้องมายเพิ่งโทรออกตามที่เจ้าของสั่ง (ไม่ใช่สายที่เจ้าของกดโทรเอง)
        if (claimOutgoing(call)) {
            mindOutgoing = true
            mindHandling = true
        }
        call.registerCallback(callback)
        InCallActivity.show(this, call)
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        call.unregisterCallback(callback)
        // 🔴 สายซ้อนจบไปหนึ่งสาย ≠ ไม่มีสายแล้ว · ของเดิมตั้ง null ทิ้ง จอสาย
        // จึงปิดตัวเองทั้งที่สายแรกยังคุยอยู่ และวางสายจากจอนี้ไม่ได้อีก
        if (current == call) current = pick(calls)
        if (calls.isEmpty()) {
            // 🔴 ต้องคืนเสียงก่อนปล่อย service เป็น null
            //
            // [CallAudio.close] คืนระดับเสียงที่เราเร่งไว้ · ถ้าปล่อย null ก่อน
            // แล้วค่อยคืน จะไม่มีใครคืนเลย แล้วเจ้าของเจอสายถัดไปดังสุด
            // โดยไม่รู้ว่าใครไปเร่งไว้ — เงียบสนิท ไม่มีอะไรบอก
            CallAudio.close(this)
            mindHandling = false
            mindOutgoing = false
            service = null
            InCallActivity.dismiss(this)
            // จอเธอที่ขึ้นทับจอล็อกระหว่างสาย ต้องถอนตัวทันทีที่สายจบ
            MainActivity.leaveLockScreen()
            // ตัวเธอที่ถูกปลุกมาคุยสายเบื้องหลัง · ไม่มีจอแล้วก็ปล่อย (หลังสรุปสายเสร็จ)
            MindEngine.releaseWhenIdle()
        }
    }

    override fun onCallAudioStateChanged(audioState: CallAudioState) {
        super.onCallAudioStateChanged(audioState)
        // ระบบย้ายเสียงกลับหูฟัง/บลูทูธระหว่างที่เธอถือสาย = ปลายสายไม่ได้ยินเธออีก
        CallAudio.keepSpeaker(this)
        notifyChanged()
    }

    private val callback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) {
            if (state == Call.STATE_ACTIVE && mindHandling) onMindCallActive()
            notifyChanged()
        }
    }

    /**
     * สายที่เธอถือต่อติดแล้ว · เปิดลำโพง**ตอนนี้** ไม่ใช่แค่ตอนสั่งรับ
     *
     * 🔴 สายเข้า: [mindAnswer] สั่งลำโพงตอนกริ่งยังดัง แล้วหลายเครื่องรีเซ็ตเส้นทาง
     * เป็นหูฟังตอนสายต่อติด · สายออก: ฝั่ง Dart รู้ว่าปลายสายรับช้ากว่านี้ถึงหนึ่งวินาที
     * (ถามทุกวินาที) คำแรกของปลายสายกับคำทักของเธอจะหลุดไปทางหูฟัง · ตามเช็กซ้ำอีกสองครั้ง
     * เพราะบาง ROM สลับเส้นทางหลังสายติดไปแล้วโดยไม่บอก
     */
    private fun onMindCallActive() {
        if (!CallAudio.open) CallAudio.open(this, MindPrefs.callStream(this))
        CallAudio.keepSpeaker(this)
        val ui = Handler(Looper.getMainLooper())
        for (delay in longArrayOf(800L, 2500L)) {
            ui.postDelayed({ CallAudio.keepSpeaker(this) }, delay)
        }
    }

    private fun notifyChanged() {
        sendBroadcast(Intent(ACTION_CALL_CHANGED).setPackage(packageName))
    }

    companion object {
        const val ACTION_CALL_CHANGED = "com.xjanova.videogirl.CALL_CHANGED"

        /// สายที่กำลังสนใจอยู่ · เก็บเป็น static เพราะ Activity กับ Service
        /// คนละอายุกัน และ Call ส่งผ่าน Intent ไม่ได้ (ไม่ใช่ Parcelable)
        @JvmStatic
        var current: Call? = null
            private set

        @JvmStatic
        var service: MindInCallService? = null
            private set

        /**
         * สายนี้มายด์เป็นคนรับ ไม่ใช่เจ้าของ
         *
         * 🔴 เป็น static เพราะ**ฝั่ง Dart รู้เรื่องนี้ทีหลังเสมอ** — จอสายเนทีฟ
         * ตัดสินใจตอนที่ Flutter engine อาจยังไม่ได้เริ่มด้วยซ้ำ · Dart จึงต้อง
         * **ถามเอา** ([callInfo]) ไม่ใช่รอให้ยิงมาบอก ไม่งั้นสายที่รับตอนแอปปิด
         * จะไม่มีใครรู้เลยว่ามายด์เป็นคนรับ แล้วหน้าจอสายก็ไม่ขึ้น
         *
         * ล้างตอนสายจบเสมอ ไม่งั้นสายถัดไปที่เจ้าของรับเองจะถูกนับว่าเป็นของเธอ
         */
        @JvmStatic
        var mindHandling = false

        /** สายนี้น้องมายเป็นคนโทรออก (เจ้าของสั่งจากแชท) · ล้างตอนสายจบ */
        @JvmStatic
        @Volatile
        var mindOutgoing = false

        /// เบอร์ที่เพิ่งสั่งให้น้องมายโทร (ตัวเลขล้วน) + เวลา · [onCallAdded] จับคู่กับสายที่เข้ามา
        @Volatile
        private var armed: Pair<String, Long>? = null

        /**
         * ให้น้องมายโทรออก · คืนเหตุผลถ้าโทรไม่ได้ (null = กดโทรแล้ว)
         *
         * 🔴 เจ้าของกดยืนยันในแอปก่อนทุกครั้ง (ฝั่ง Dart) · ที่นี่กันเพิ่มอีกชั้น: เบอร์ฉุกเฉิน
         * และเบอร์เก็บเงินพิเศษ น้องมายไม่โทรเด็ดขาด · ต้องเป็นแอปโทรศัพท์หลัก ไม่งั้นสายไป
         * ออกแอปโทรศัพท์อื่น เธอไม่มีทางคุยในสายนั้น
         */
        @JvmStatic
        fun placeMindCall(context: android.content.Context, raw: String): String? {
            val number = OutgoingRules.normalize(raw) ?: return "bad_number"
            if (OutgoingRules.blocked(number)) return "blocked"
            if (!SystemBridge.isDefaultDialer(context)) return "not_dialer"
            if (service?.calls?.isNotEmpty() == true) return "busy"
            if (androidx.core.content.ContextCompat.checkSelfPermission(
                    context, android.Manifest.permission.CALL_PHONE
                ) != android.content.pm.PackageManager.PERMISSION_GRANTED
            ) return "no_permission"
            val tm = context.getSystemService(android.content.Context.TELECOM_SERVICE)
                as? android.telecom.TelecomManager ?: return "no_telecom"
            armed = number to SystemClock.uptimeMillis()
            return try {
                tm.placeCall(android.net.Uri.fromParts("tel", number, null), android.os.Bundle())
                null
            } catch (e: SecurityException) {
                armed = null
                "no_permission"
            }
        }

        /** สายที่เพิ่มเข้ามาคือสายที่น้องมายเพิ่งกดโทรไหม (เบอร์ตรง ภายในหนึ่งนาที) */
        private fun claimOutgoing(call: Call): Boolean {
            val (number, at) = armed ?: return false
            armed = null
            if (SystemClock.uptimeMillis() - at > 60_000) return false
            val got = OutgoingRules.normalize(call.details.handle?.schemeSpecificPart ?: "") ?: return false
            // +66812345678 กับ 0812345678 คือเบอร์เดียวกัน · เทียบท้ายเก้าหลัก
            return got.takeLast(9) == number.takeLast(9)
        }

        /** สายที่ควรเป็นตัวหลักจากหลายสาย: กำลังคุย > กำลังดัง > ตัวแรก */
        private fun pick(calls: List<Call>): Call? =
            calls.firstOrNull { stateOf(it) == Call.STATE_ACTIVE }
                ?: calls.firstOrNull { stateOf(it) == Call.STATE_RINGING }
                ?: calls.firstOrNull()

        /** สายที่กำลังคุยอยู่จริง ไม่ว่าจะมีสายซ้อนดังอยู่หรือไม่ */
        private fun activeCall(): Call? =
            service?.calls?.firstOrNull { stateOf(it) == Call.STATE_ACTIVE }

        /** มีมากกว่าหนึ่งสายอยู่ตอนนี้ไหม — สายซ้อน */
        @JvmStatic
        fun hasOtherCall(): Boolean = (service?.calls?.size ?: 0) > 1

        /** ทำเสียงออกลำโพงหรือหูฟัง · ใช้ตอนจะให้เธอพูดออกลำโพง */
        @JvmStatic
        fun setSpeaker(on: Boolean) {
            service?.setAudioRoute(
                if (on) CallAudioState.ROUTE_SPEAKER else CallAudioState.ROUTE_EARPIECE
            )
        }

        @JvmStatic
        fun speakerOn(): Boolean =
            service?.callAudioState?.route == CallAudioState.ROUTE_SPEAKER

        /// สถานะของสายที่ระบบส่งมาให้เรา · -1 = ไม่มีสาย
        ///
        /// `Call.getState()` ถูกเลิกใช้ตั้งแต่ API 31 แต่ `details.state` เพิ่งมี
        /// ตอน 31 พอดี · ต้องแยกทางตามรุ่น ไม่มีทางเดียวที่ใช้ได้ทั้งหมด
        @JvmStatic
        fun stateOf(call: Call?): Int {
            if (call == null) return -1
            return if (Build.VERSION.SDK_INT >= 31) call.details.state else {
                @Suppress("DEPRECATION") call.state
            }
        }

        /**
         * ทุกอย่างที่ฝั่ง Dart ต้องรู้เกี่ยวกับสายตอนนี้ ในการถามครั้งเดียว
         *
         * ถามทีละอย่างจะได้ภาพที่ไม่ตรงกันเอง เพราะสายเปลี่ยนสถานะระหว่างถาม
         * ได้จริง (คนวางสายตอนที่เราถามข้อสองอยู่พอดี)
         */
        /// ครั้งล่าสุดที่ Dart ถามสถานะสาย (uptime) · ใช้ตัดสินว่ามีใครคุยในสายจริงไหม
        @Volatile
        private var dartSeenAt = 0L

        @JvmStatic
        fun callInfo(context: android.content.Context): Map<String, Any?> {
            dartSeenAt = SystemClock.uptimeMillis()
            // 🔴 "มีสายที่คุยอยู่ไหม" ต้องดูจากทุกสาย ไม่ใช่สายที่เพิ่งเข้ามา
            // · สายซ้อนดังขึ้นมาระหว่างที่เธอคุยสายแรก = `current` ชี้ไปสายที่ดัง
            // แล้วฝั่ง Dart เห็น live=false → ปิดบทสนทนาและคืนเสียงกลางสายแรก
            val talking = activeCall()
            val call = talking ?: current
            val state = stateOf(call)
            val number = call?.details?.handle?.schemeSpecificPart
            return mapOf(
                "state" to state,
                "live" to (state == Call.STATE_ACTIVE),
                "ringing" to (stateOf(current) == Call.STATE_RINGING),
                "mind" to mindHandling,
                "mindOutgoing" to mindOutgoing,
                "speaker" to speakerOn(),
                "number" to number,
                "name" to CallBridge(context).nameFor(number),
                "outgoing" to (state == Call.STATE_DIALING || state == Call.STATE_CONNECTING)
            ) + (SimInfo.of(context, call)?.toMap() ?: emptyMap())
        }

        /**
         * ให้มายด์รับสายนี้
         *
         * รวมไว้ที่เดียวเพราะสามขั้นนี้ต้องเกิดครบและเรียงกัน: ตั้งธงก่อนรับ
         * (ไม่งั้น Dart ที่ตื่นมาเพราะสายถูกรับ จะถามธงตอนที่ยังไม่ได้ตั้ง)
         * แล้วค่อยรับ แล้วค่อยเปิดลำโพง
         *
         * คืน false เมื่อเปิดลำโพงไม่ได้ — สายถูกรับไปแล้วแต่**ปลายสายจะไม่ได้ยิน
         * เธอเลย** ผู้เรียกต้องบอกผู้ใช้ ไม่ใช่ทำเหมือนสำเร็จ
         */
        @JvmStatic
        fun mindAnswer(context: android.content.Context, stream: String): Boolean {
            val call = current ?: return false
            mindHandling = true
            if (stateOf(call) == Call.STATE_RINGING) {
                call.answer(VideoProfile.STATE_AUDIO_ONLY)
                watchForSilence(context.applicationContext, call)
            }
            return CallAudio.open(context, stream)
        }

        /**
         * 🔴 รับแล้วไม่มีใครคุย = วางสาย
         *
         * ตัวเธอถูกปลุกขึ้นมาตอนแอปปิด (ดู [MindEngine]) ถ้า Dart เปิดตัวไม่ขึ้น
         * สายจะค้างบนลำโพงที่ไมค์เปิด ปลายสายได้ยินเสียงในห้องเจ้าของโดยไม่มีใครรู้
         * · Dart ที่ตื่นอยู่ถามสถานะสายทุกวินาทีตลอดสาย ([callInfo]) · เงียบเกินเวลา
         * = ไม่มีใครอยู่ · จดเหตุผลไว้ให้รายงานเห็น
         */
        private fun watchForSilence(context: android.content.Context, call: Call) {
            val answeredAt = SystemClock.uptimeMillis()
            Handler(Looper.getMainLooper()).postDelayed({
                if (current === call && mindHandling &&
                    stateOf(call) == Call.STATE_ACTIVE && dartSeenAt < answeredAt
                ) {
                    MindPrefs.noteAutoAnswer(context, "no_talk")
                    call.disconnect()
                }
            }, SILENCE_LIMIT_MS)
        }

        /// Dart เปิดตัวจากศูนย์ (ค่าตั้ง ฐานข้อมูล ความจำ) ช้าสุดที่วัดได้ราว 10 วิ · เผื่อไว้มาก
        private const val SILENCE_LIMIT_MS = 45_000L

        /** เจ้าของแทรกสาย — เธอหยุด เสียงกลับเข้าหูฟัง สายยังอยู่ */
        @JvmStatic
        fun handOver(context: android.content.Context) {
            mindHandling = false
            CallAudio.handOver(context)
        }

        /** วางสายที่กำลังดังหรือกำลังคุยอยู่ ผ่านสายที่ระบบส่งมาให้เราโดยตรง */
        @JvmStatic
        fun disconnect(): Boolean {
            val call = current ?: return false
            if (stateOf(call) == Call.STATE_RINGING) {
                call.reject(false, null)
            } else {
                call.disconnect()
            }
            return true
        }
    }
}
