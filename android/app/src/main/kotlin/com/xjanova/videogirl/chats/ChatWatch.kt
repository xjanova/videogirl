package com.xjanova.videogirl.chats

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * ตาที่ดูแจ้งเตือนแชท (WhatsApp) · เจ้าของให้สิทธิ์ "การเข้าถึงการแจ้งเตือน" เองในหน้าของระบบ
 *
 * 🔒 ดูเฉพาะแอปใน [ChatInbox.APPS] และเฉพาะตอนเจ้าของเปิดฟีเจอร์ · แอปอื่นไม่อ่านอะไรเลย · ไม่ลง log ข้อความ
 */
class ChatWatch : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        try {
            ChatInbox.onPosted(this, sbn)
        } catch (_: Exception) {
            // แจ้งเตือนหน้าตาแปลก ๆ หนึ่งอัน ต้องไม่ทำให้ตาทั้งตัวล้ม
        }
    }
}
