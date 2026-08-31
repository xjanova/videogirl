package com.xjanova.videogirl

import android.content.Intent
import android.os.Build
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
        call.registerCallback(callback)
        InCallActivity.show(this, call)
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        call.unregisterCallback(callback)
        if (current == call) current = null
        if (calls.isEmpty()) {
            // 🔴 ต้องคืนเสียงก่อนปล่อย service เป็น null
            //
            // [CallAudio.close] คืนระดับเสียงที่เราเร่งไว้ · ถ้าปล่อย null ก่อน
            // แล้วค่อยคืน จะไม่มีใครคืนเลย แล้วเจ้าของเจอสายถัดไปดังสุด
            // โดยไม่รู้ว่าใครไปเร่งไว้ — เงียบสนิท ไม่มีอะไรบอก
            CallAudio.close(this)
            mindHandling = false
            service = null
            InCallActivity.dismiss(this)
        }
    }

    override fun onCallAudioStateChanged(audioState: CallAudioState) {
        super.onCallAudioStateChanged(audioState)
        notifyChanged()
    }

    private val callback = object : Call.Callback() {
        override fun onStateChanged(call: Call, state: Int) = notifyChanged()
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
        @JvmStatic
        fun callInfo(context: android.content.Context): Map<String, Any?> {
            val call = current
            val state = stateOf(call)
            val number = call?.details?.handle?.schemeSpecificPart
            return mapOf(
                "state" to state,
                "live" to (state == Call.STATE_ACTIVE),
                "ringing" to (state == Call.STATE_RINGING),
                "mind" to mindHandling,
                "speaker" to speakerOn(),
                "number" to number,
                "name" to CallBridge(context).nameFor(number),
                "outgoing" to (state == Call.STATE_DIALING || state == Call.STATE_CONNECTING)
            )
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
            }
            return CallAudio.open(context, stream)
        }

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
