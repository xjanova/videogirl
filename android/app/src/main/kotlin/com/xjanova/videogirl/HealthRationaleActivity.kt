package com.xjanova.videogirl

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * หน้าบอกว่าเอาข้อมูลสุขภาพไปทำอะไร · Health Connect เปิดหน้านี้จากกล่องขอสิทธิ์
 *
 * 🔴 ไม่มีหน้านี้ใน manifest (ทั้ง rationale และ alias ของ Android 14) กล่องขอสิทธิ์ Health Connect
 * **ไม่ขึ้นเลย** และตอบกลับเหมือนเจ้าของกดปฏิเสธ · ไม่มี error · ดู manifest
 *
 * เปิดจากภายนอกได้ จึงมีแต่ข้อความตายตัว ไม่อ่าน intent และไม่แตะข้อมูลใด ๆ
 */
class HealthRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pad = (24 * resources.displayMetrics.density).toInt()
        val page = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(pad, pad, pad, pad)
            addView(TextView(context).apply {
                setText(R.string.health_rationale_title)
                textSize = 22f
                setPadding(0, 0, 0, pad / 2)
            })
            addView(TextView(context).apply {
                setText(R.string.health_rationale_body)
                textSize = 16f
                setPadding(0, 0, 0, pad)
            })
            addView(
                Button(context).apply {
                    setText(R.string.health_rationale_close)
                    setOnClickListener { finish() }
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { gravity = Gravity.END },
            )
        }
        setContentView(ScrollView(this).apply { addView(page) })
    }
}
