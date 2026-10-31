package com.xjanova.videogirl.hands

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap

/**
 * แอปที่มายด์ห้ามอ่าน ห้ามกด ห้ามเปิด · ด่านสุดท้ายอยู่ที่นี่ ไม่ใช่ฝั่ง Dart
 *
 * 🔴 รายชื่อนี้เป็น**ความพยายามที่ดีที่สุด** ไม่ใช่การรับประกัน · แอปการเงินใหม่ที่ชื่อแพ็กเกจ
 * ไม่มีคำที่จับได้และไม่อยู่ในรายการจะหลุดได้ · กันเกินดีกว่ากันขาด จึงจับด้วยคำในชื่อแพ็กเกจด้วย
 * ไม่ใช่แค่รายชื่อตายตัว · แอปที่ไม่ใช่การเงินแต่โดนคำจับ ให้เติมใน [NOT_FINANCE]
 */
internal object HandsPolicy {

    /** ตัวติดตั้งแอปและหน้าขอสิทธิ์ · กดแทนที่นี่ = ติดตั้งอะไรก็ได้ ให้สิทธิ์อะไรก็ได้ */
    private val SYSTEM_GATES = setOf(
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
    )

    /**
     * ธนาคารและการเงินไทยที่รู้ชื่อแพ็กเกจแน่นอน (ตัวเล็กทั้งหมด เทียบหลัง lowercase)
     *
     * ยังไม่แน่ใจ ไม่ใส่ (ตรวจกับเครื่องจริงก่อนเติม): MyMo ของออมสิน (com.mymo.android?),
     * UOB TMRW, CIMB THAI, KKP Mobile, Dime!, ธ.ก.ส. A-Mobile, GHB ALL, KTC Mobile, MAKE by KBank
     * · ส่วนใหญ่โดนคำในชื่อแพ็กเกจจับอยู่แล้ว (bank / แบรนด์ใน [BRAND_SEGMENTS])
     */
    private val FINANCE = setOf(
        "com.kasikorn.retail.mbanking.wap", // K PLUS
        "com.scb.phone", // SCB EASY
        "ktbcs.netbank", // Krungthai NEXT
        "com.bbl.mobilebanking", // Bangkok Bank Mobile Banking
        "com.krungsri.kma", // KMA (กรุงศรี)
        "com.tmbtouch.production", // ttb touch (com.TMBTOUCH.PRODUCTION)
        "th.co.truemoney.wallet", // TrueMoney Wallet
    )

    /** คำที่อยู่ที่ไหนก็ได้ในชื่อแพ็กเกจ */
    private val KEYWORDS = listOf(
        "bank", "banking", "mbanking", "wallet", "finance", "securities", "crypto",
        "bitkub", "binance", "truemoney", "paypal", "paotang", "settrade",
    )

    /** ชื่อแบรนด์ธนาคาร/บัตร ที่ต้องเป็นทั้งท่อนของชื่อแพ็กเกจ (สั้นเกินจะเทียบแบบมีอยู่ข้างใน) */
    private val BRAND_SEGMENTS = setOf(
        "scb", "ktb", "bbl", "kbank", "kasikorn", "kasikornbank", "krungsri", "gsb", "baac", "ghb",
        "uob", "cimb", "tmb", "ttb", "tmbtouch", "kkp", "ktc",
    )

    /** ไม่ใช่การเงิน แม้คำจะไปชน · ข้ามเฉพาะการเดาจากคำ ไม่ข้ามด่านอื่น */
    private val NOT_FINANCE = setOf(
        "com.android.vending",
        "com.google.android.apps.messaging",
        "com.google.android.gm",
        "com.android.chrome",
        "jp.naver.line.android",
    )

    private val labels = ConcurrentHashMap<String, String>()
    private val launchable = ConcurrentHashMap<String, Boolean>()

    /** ห้ามอ่าน ห้ามกด ห้ามเปิด */
    fun isBlocked(context: Context, pkg: String?): Boolean {
        if (pkg.isNullOrEmpty()) return false
        if (pkg == context.packageName) return true
        val p = pkg.lowercase(Locale.ROOT)
        if (p in SYSTEM_GATES || p in FINANCE) return true
        if (p in NOT_FINANCE) return false
        if (KEYWORDS.any { p.contains(it) }) return true
        // pay ต้องเป็นหัวหรือท้ายของท่อน (paypal · paytm · linepay · spay) · play / display ไม่ชน
        for (seg in p.split('.')) {
            if (seg in BRAND_SEGMENTS) return true
            if (seg.startsWith("pay") || seg.endsWith("pay")) return true
        }
        return false
    }

    /** ชื่อแอปที่เห็นบนเครื่อง · ไม่รู้ = '' */
    fun label(context: Context, pkg: String?): String {
        if (pkg.isNullOrEmpty()) return ""
        labels[pkg]?.let { return it }
        val pm = context.packageManager
        val name = try {
            val info = if (Build.VERSION.SDK_INT >= 33) {
                pm.getApplicationInfo(pkg, PackageManager.ApplicationInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getApplicationInfo(pkg, 0)
            }
            pm.getApplicationLabel(info).toString()
        } catch (_: Exception) {
            ""
        }
        if (labels.size > 200) labels.clear()
        labels[pkg] = name
        return name
    }

    /** มีไอคอนบนหน้าแอป (เปิดได้จากตัวเปิดแอป) */
    fun isLaunchable(context: Context, pkg: String): Boolean {
        launchable[pkg]?.let { return it }
        val yes = try {
            context.packageManager.getLaunchIntentForPackage(pkg) != null
        } catch (_: Exception) {
            false
        }
        if (launchable.size > 200) launchable.clear()
        launchable[pkg] = yes
        return yes
    }

    /** แอปที่มีไอคอนบนหน้าแอปทั้งหมด · (แพ็กเกจ, ชื่อ) */
    fun launcherApps(context: Context): List<Pair<String, String>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val found = try {
            if (Build.VERSION.SDK_INT >= 33) {
                pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.queryIntentActivities(intent, 0)
            }
        } catch (_: Exception) {
            emptyList()
        }
        val seen = HashSet<String>()
        val out = ArrayList<Pair<String, String>>()
        for (r in found) {
            val pkg = r.activityInfo?.packageName ?: continue
            if (!seen.add(pkg)) continue
            val name = try { r.loadLabel(pm).toString() } catch (_: Exception) { "" }
            out.add(pkg to name)
        }
        return out
    }
}
