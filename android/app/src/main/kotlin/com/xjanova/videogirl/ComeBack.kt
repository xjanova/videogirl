package com.xjanova.videogirl

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.xjanova.videogirl.hands.MindHands

/**
 * เรียกเจ้าของกลับมาที่แอป ตอนมีกล่องที่ต้องแตะ (ยืนยันโทร · เลือกคน) แต่แอปอยู่หลังบ้าน
 *
 * เจ้าของ: "หน้าจอต้องสลับกลับมาส่วนการโทรทันที เพื่อให้เรากด หรือส่วนที่เราต้องยืนยันได้ทันที"
 *
 * 🔴 Android 10+ ห้ามแอปเบื้องหลังเปิดหน้าเอง และการห้ามนี้**ไม่โยน error** · ระบบแค่ทิ้งเงียบ ๆ ·
 * ทางที่ผ่านจริงมีสองทาง จึงทำทั้งคู่เสมอ ไม่รอดูว่าทางแรกได้ผลไหม:
 *
 * 1. เปิดจาก context ของบริการการช่วยเหลือพิเศษ ([MindHands]) · ระบบยกเว้นบริการที่ระบบผูกไว้
 *    แต่มีเฉพาะตอนเปิดให้เธอใช้มือถือไว้
 * 2. แจ้งเตือนแบบเต็มจอ · จอดับ/ล็อก = ระบบเปิดจอให้ · จอติดในแอปอื่น = ขึ้นแถบเด้งบนจอให้แตะ
 *    (Android ไม่ให้แจ้งเตือนแย่งจอตอนคนใช้เครื่องอยู่)
 *
 * [MainActivity.onResume] ถอนแจ้งเตือนนี้ · กลับมาแล้วไม่ต้องเรียกอีก
 *
 * ไม่ขึ้นทับจอล็อก · ยืนยันโทรต้องปลดล็อกก่อน (ฝั่ง Dart: `_voiceBarred`)
 */
object ComeBack {
    private const val TAG = "GigGokComeBack"
    private const val CHANNEL = "owner_needed"
    private const val NOTICE_ID = 7741

    fun now(context: Context, title: String, body: String) {
        val app = context.applicationContext
        val open = Intent(app, MainActivity::class.java).addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP
        )
        notice(app, open, title, body)
        try {
            (MindHands.instance ?: app).startActivity(open)
        } catch (e: Exception) {
            Log.w(TAG, "open: ${e.javaClass.simpleName}")
        }
    }

    fun done(context: Context) {
        NotificationManagerCompat.from(context).cancel(NOTICE_ID)
    }

    private fun notice(app: Context, open: Intent, title: String, body: String) {
        val nm = app.getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, app.getString(R.string.come_back_channel), NotificationManager.IMPORTANCE_HIGH)
            )
        }
        val tap = PendingIntent.getActivity(
            app, NOTICE_ID, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val n = NotificationCompat.Builder(app, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(tap)
            .setFullScreenIntent(tap, true)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            // ชื่อคนที่จะโทรไม่ขึ้นบนจอล็อก
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .build()
        try {
            NotificationManagerCompat.from(app).notify(NOTICE_ID, n)
        } catch (e: SecurityException) {
            Log.w(TAG, "notice: ${e.javaClass.simpleName}") // ปิดแจ้งเตือนไว้ · ยังเหลือทางที่ 1 กับเสียงของเธอ
        }
    }
}
