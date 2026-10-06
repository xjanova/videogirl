package com.xjanova.videogirl

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telecom.Call
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat

/**
 * สายนี้เข้ามาทางซิมไหน — เครื่องสองซิม
 *
 * เจ้าของใช้ซิมหนึ่งเป็นเบอร์งาน อีกซิมเป็นเบอร์ส่วนตัว · "มีสายจากเบอร์นี้"
 * ไม่พอ ต้องบอกว่า**โทรเข้าเบอร์ไหน** ถึงจะรู้ว่าเป็นเรื่องงานหรือเรื่องบ้าน
 *
 * ## 🔴 ทางที่ระบบให้มา (และกับดักของแต่ละทาง)
 *
 * สายผูกกับ `PhoneAccountHandle` ไม่ใช่ช่องซิมตรง ๆ · ต้องแปลงสองต่อ:
 * handle → subscription id → [SubscriptionInfo] (ช่องซิม + ชื่อค่าย/ชื่อที่ตั้ง)
 *
 * - API 30+: `TelephonyManager.getSubscriptionId(handle)` ตรงที่สุด
 * - ต่ำกว่านั้น: `handle.id` ของซิมส่วนใหญ่ **คือ** subscription id หรือ ICCID
 *   (ขึ้นกับผู้ผลิต) · ลองตีเป็นเลขก่อน แล้วค่อยเทียบ ICCID
 * - อ่าน [SubscriptionInfo] ต้องมี READ_PHONE_STATE · ไม่มี = ใช้ชื่อบัญชี
 *   ของ Telecom แทน (เช่น "AIS") ซึ่งไม่ต้องใช้สิทธิ์ แต่ไม่รู้ช่องซิม
 *
 * ทุกทางล้มได้บน ROM แปลก ๆ · **ล้มต้องคืน null เงียบ ๆ ไม่ใช่ทำจอสายพัง**
 * จอสายพัง = เจ้าของรับสายไม่ได้ทั้งเครื่อง
 */
object SimInfo {

    /** ช่องซิม (1/2 · null = ไม่รู้) · ชื่อที่คนอ่านรู้เรื่อง · มีซิมใช้งานกี่ใบ */
    data class Sim(val slot: Int?, val label: String?, val count: Int) {
        fun toMap(): Map<String, Any?> = mapOf(
            "simSlot" to slot,
            "simLabel" to label,
            "simCount" to count,
        )
    }

    private fun canRead(context: Context) =
        ContextCompat.checkSelfPermission(context, Manifest.permission.READ_PHONE_STATE) ==
            PackageManager.PERMISSION_GRANTED

    /** มีซิมที่ใช้งานอยู่กี่ใบ · 0 = ถามไม่ได้ */
    fun activeCount(context: Context): Int {
        if (!canRead(context)) return 0
        return try {
            val sm = context.getSystemService(SubscriptionManager::class.java) ?: return 0
            sm.activeSubscriptionInfoCount
        } catch (e: Exception) {
            0
        }
    }

    fun of(context: Context, call: Call?): Sim? {
        val handle = call?.details?.accountHandle ?: return null
        return of(context, handle)
    }

    fun of(context: Context, handle: PhoneAccountHandle): Sim? = try {
        val count = activeCount(context)
        val info = subscription(context, handle)
        val slot = info?.simSlotIndex?.takeIf { it >= 0 }?.plus(1)
        // ชื่อที่เจ้าของตั้งเองในหน้าตั้งค่าซิม ("งาน", "ส่วนตัว") มาก่อนชื่อค่าย
        val label = info?.displayName?.toString()?.trim()?.takeIf { it.isNotEmpty() }
            ?: info?.carrierName?.toString()?.trim()?.takeIf { it.isNotEmpty() }
            ?: accountLabel(context, handle)
        if (slot == null && label == null) null else Sim(slot, label, count)
    } catch (e: Exception) {
        null
    }

    /**
     * ซิมของแถวในบันทึกการโทร · `CallLog.Calls.PHONE_ACCOUNT_ID` คือ `handle.id`
     * ของบัญชีที่สายนั้นผ่าน · เทียบกับบัญชีที่โทรได้ทั้งหมดของเครื่อง
     */
    fun ofAccountId(context: Context, accountId: String?): Sim? {
        if (accountId.isNullOrBlank() || !canRead(context)) return null
        return try {
            val tm = context.getSystemService(TelecomManager::class.java) ?: return null
            val handle = tm.callCapablePhoneAccounts.firstOrNull { it.id == accountId }
                ?: return null
            of(context, handle)
        } catch (e: Exception) {
            null
        }
    }

    private fun subscription(
        context: Context,
        handle: PhoneAccountHandle,
    ): android.telephony.SubscriptionInfo? {
        if (!canRead(context)) return null
        val sm = context.getSystemService(SubscriptionManager::class.java) ?: return null
        val subId = if (Build.VERSION.SDK_INT >= 30) {
            context.getSystemService(TelephonyManager::class.java)
                ?.getSubscriptionId(handle)
                ?.takeIf { it != SubscriptionManager.INVALID_SUBSCRIPTION_ID }
        } else {
            null
        } ?: handle.id.toIntOrNull()

        if (subId != null) {
            sm.getActiveSubscriptionInfo(subId)?.let { return it }
        }
        // บางผู้ผลิตใช้ ICCID เป็น handle.id (Android ใหม่ซ่อน ICCID ไว้ = ไม่เจอ ไม่เป็นไร)
        return sm.activeSubscriptionInfoList?.firstOrNull {
            !it.iccId.isNullOrEmpty() && it.iccId == handle.id
        }
    }

    /** ชื่อบัญชีโทรศัพท์ของระบบ (ส่วนใหญ่คือชื่อค่าย) · ไม่ต้องใช้สิทธิ์ */
    private fun accountLabel(context: Context, handle: PhoneAccountHandle): String? = try {
        context.getSystemService(TelecomManager::class.java)
            ?.getPhoneAccount(handle)
            ?.label
            ?.toString()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    } catch (e: Exception) {
        null
    }
}
