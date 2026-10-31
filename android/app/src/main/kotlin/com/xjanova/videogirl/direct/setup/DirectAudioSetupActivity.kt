package com.xjanova.videogirl.direct.setup

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.*
import com.xjanova.videogirl.R

/** Small native guide so entering the code never closes Android's pairing sheet. */
class DirectAudioSetupActivity : Activity() {
    private lateinit var status: TextView
    private val handler = Handler(Looper.getMainLooper())
    private val refresh = object : Runnable {
        override fun run() {
            status.text = when (DirectAudioSetup.status) {
                "helper_started" -> "✅ ต่อสายตรงแล้ว น้องมายจะพูดเข้าสายตรง ไม่ผ่านลำโพง"
                "waiting_for_code" -> "รอรหัสจากการแจ้งเตือน — อย่าปิดหน้ารหัสจับคู่"
                "connecting", "finding_pairing_port", "paired_connecting" -> "กำลังเชื่อมต่อกับเครื่องนี้…"
                "setup_failed" -> "ยังไม่สำเร็จ ตรวจ Wi-Fi และ Wireless debugging แล้วลองใหม่"
                "key_rejected" -> getString(R.string.direct_pair_again)
                "notifications_required" -> "ต้องเปิดการแจ้งเตือนเพื่อกรอกรหัสขณะหน้าตั้งค่าเปิดอยู่"
                "requires_android_11" -> "ทางเสียงตรงต้องใช้ Android 11 ขึ้นไป"
                "device_unsupported" -> "รุ่นนี้ยังไม่รองรับทางเสียงตรง"
                "invalid_code" -> "รหัสต้องเป็นตัวเลข 6 หลัก"
                else -> "ยังไม่ได้เชื่อมต่อ"
            }
            handler.postDelayed(this, 700)
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(28, 32, 28, 32)
        }
        fun text(value: String, size: Float = 16f) = TextView(this).apply {
            this.text = value; textSize = size; setPadding(0, 10, 0, 16)
        }
        content.addView(text("เสียงตรงในสาย", 24f))
        content.addView(text("ให้คู่สายได้ยินน้องมายชัดขึ้น โดยไม่ต้องลงแอปเสริม\n\n1. ต่อ Wi-Fi และเปิดตัวเลือกนักพัฒนา\n2. เปิด Wireless debugging แล้วเลือกจับคู่อุปกรณ์ด้วยรหัส\n3. คงหน้ารหัสไว้ เปิดแถบแจ้งเตือน แล้วกดกรอกรหัส 6 หลักของ GigGok\n\nหลังเชื่อมต่อ ระบบจะตรวจว่ารุ่นนี้รองรับหรือไม่"))
        status = text(""); content.addView(status)
        content.addView(Button(this).apply {
            text = "เริ่มตั้งค่า"
            setOnClickListener {
                if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7041)
                } else begin()
            }
        })
        content.addView(Button(this).apply { text = "เคยจับคู่แล้ว — เชื่อมต่ออีกครั้ง"; setOnClickListener { DirectAudioSetup.reconnect(applicationContext) } })
        content.addView(text(getString(R.string.direct_setup_auto_reconnect_hint), 14f))
        content.addView(Button(this).apply { text = "กลับ"; setOnClickListener { finish() } })
        setContentView(ScrollView(this).apply { addView(content) })
    }
    private fun begin() {
        try { DirectAudioSetup.begin(this) }
        catch (_: Exception) { Toast.makeText(this, "เปิดหน้าตั้งค่าไม่ได้ กรุณาเปิดตัวเลือกนักพัฒนาจากการตั้งค่าเครื่อง", Toast.LENGTH_LONG).show() }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7041 && grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) begin()
    }
    override fun onResume() { super.onResume(); handler.post(refresh) }
    override fun onPause() { handler.removeCallbacks(refresh); super.onPause() }
}
