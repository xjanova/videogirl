package com.xjanova.videogirl

import android.content.Intent
import android.telecom.Call
import android.telecom.CallAudioState
import android.telecom.InCallService

/**
 * แอปโทรศัพท์หลัก — ฝั่งที่ระบบเรียกเมื่อมีสาย
 *
 * ## 🔴 สิ่งที่การเป็นแอปโทรศัพท์หลัก **ไม่ได้** ให้
 *
 * **ป้อนเสียงเข้าไปในสายไม่ได้** ไม่ว่าจะเป็นแอปหลักหรือไม่ก็ตาม
 * Android ไม่มี API สำหรับเรื่องนี้เลย — เสียงขาออกของสายมาจากไมค์ฮาร์ดแวร์
 * ทางเดียวที่ทำได้จริงคือเปิดลำโพงแล้วให้เธอพูดออกลำโพงให้ไมค์รับเข้าไป
 * ซึ่งได้ยินจริงแต่มีเสียงก้องและเสียงห้องปนไป
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
    }
}
