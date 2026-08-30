package com.xjanova.videogirl

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.telecom.TelecomManager
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.content.ContextCompat

/**
 * แป้นโทรออก
 *
 * ## 🔴 ทำไมต้องมี ทั้งที่เธอไม่ได้ต้องใช้
 *
 * เป็นแอปโทรศัพท์หลักแล้ว **แอปนี้คือแอปโทรศัพท์ของเครื่อง** ทั้งใบ
 * ระบบจะส่ง `DIAL` มาที่นี่ทุกครั้งที่ใครกดเบอร์จากที่ไหนก็ตาม และถ้าเจ้าของ
 * เปิดแอปโทรศัพท์เพื่อกดเบอร์ ก็จะมาที่นี่
 *
 * ไม่มีจอนี้ = ตั้งเป็นแอปหลักแล้ว**โทรออกไม่ได้ทั้งเครื่อง** ซึ่งแย่กว่า
 * ไม่ได้เป็นแอปหลักเลยมาก · จอนี้จึงไม่ใช่ของแถม แต่เป็นเงื่อนไข
 *
 * เนทีฟด้วยเหตุผลเดียวกับ [InCallActivity] — ต้องขึ้นได้โดยไม่รอ engine
 */
class DialerActivity : Activity() {

    private lateinit var display: TextView
    private val digits = StringBuilder()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // มากับเบอร์อยู่แล้ว (แตะเบอร์จากที่อื่น) ให้เติมลงแป้นไว้เลย
        intent?.data?.takeIf { it.scheme == "tel" }
            ?.schemeSpecificPart
            ?.let { digits.append(Uri.decode(it)) }

        setContentView(buildUi())
        render()
    }

    private fun dp(v: Int) = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics
    ).toInt()

    private fun buildUi(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#F6F2F7"))
            setPadding(dp(20), dp(48), dp(20), dp(28))
        }

        display = TextView(this).apply {
            setTextColor(Color.parseColor("#231F3A"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 32f)
            gravity = Gravity.CENTER
            setPadding(0, dp(20), 0, dp(28))
        }
        root.addView(display, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        val keys = listOf(
            listOf("1", "2", "3"),
            listOf("4", "5", "6"),
            listOf("7", "8", "9"),
            listOf("*", "0", "#"),
        )
        for (row in keys) {
            val line = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
            for (k in row) {
                line.addView(
                    key(k) { digits.append(k); render() },
                    LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f)
                        .also { it.setMargins(dp(5), dp(5), dp(5), dp(5)) }
                )
            }
            root.addView(line, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        }

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(16), 0, 0)
        }
        actions.addView(
            pill("⌫", "#8C86A0") { if (digits.isNotEmpty()) digits.deleteCharAt(digits.length - 1); render() },
            LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).also { it.rightMargin = dp(10) }
        )
        actions.addView(
            pill(getString(R.string.dial_call), "#00A05A") { place() },
            LinearLayout.LayoutParams(0, WRAP_CONTENT, 2f)
        )
        root.addView(actions, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))

        return root
    }

    private fun key(label: String, onTap: () -> Unit) = Button(this).apply {
        text = label
        setTextColor(Color.parseColor("#231F3A"))
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
        setPadding(0, dp(18), 0, dp(18))
        background = GradientDrawable().apply {
            cornerRadius = dp(22).toFloat()
            setColor(Color.parseColor("#FFFFFF"))
        }
        stateListAnimator = null
        setOnClickListener { onTap() }
    }

    private fun pill(label: String, colour: String, onTap: () -> Unit) = Button(this).apply {
        text = label
        setTextColor(Color.WHITE)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
        setPadding(0, dp(18), 0, dp(18))
        background = GradientDrawable().apply {
            cornerRadius = dp(26).toFloat()
            setColor(Color.parseColor(colour))
        }
        stateListAnimator = null
        setOnClickListener { onTap() }
    }

    private fun render() {
        display.text = if (digits.isEmpty()) getString(R.string.dial_hint) else digits
    }

    /**
     * โทรออกผ่าน Telecom ไม่ใช่ ACTION_CALL
     *
     * `placeCall` เป็นทางของแอปโทรศัพท์ · ยิง ACTION_CALL แทนจะวนกลับมาหา
     * ตัวเองเพราะเราคือแอปที่รับ intent นั้น
     */
    private fun place() {
        if (digits.isEmpty()) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.CALL_PHONE), REQ_CALL_PHONE)
            return
        }
        val tm = getSystemService(Context.TELECOM_SERVICE) as? TelecomManager ?: return
        try {
            tm.placeCall(Uri.fromParts("tel", digits.toString(), null), Bundle())
        } catch (e: SecurityException) {
            // ไม่ได้เป็นแอปหลัก หรือสิทธิ์หาย — เงียบดีกว่าพัง จอยังอยู่ให้กดใหม่
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_CALL_PHONE &&
            grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            place()
        }
    }

    companion object {
        private const val REQ_CALL_PHONE = 8760
    }
}
