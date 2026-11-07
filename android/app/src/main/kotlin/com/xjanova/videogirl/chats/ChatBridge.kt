package com.xjanova.videogirl.chats

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * ช่อง `giggok/chats` · คู่กับ lib/chats/chat_inbox.dart
 *
 * อยู่ใน SystemBridge.attach เหตุผลเดียวกับ HandsBridge · ข้อความเข้ามาตอนไม่มีจอก็ต้องมีคนรับ
 * 🔒 ไม่ลงข้อความแชทหรือชื่อคนใน log
 */
object ChatBridge {
    private const val TAG = "GigGokChats"
    private val main = Handler(Looper.getMainLooper())

    fun attach(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        val channel = MethodChannel(messenger, "giggok/chats")
        ChatInbox.events = { name, args -> main.post { channel.invokeMethod(name, args) } }
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(mapOf("on" to ChatInbox.on(app), "access" to ChatInbox.access(app)))
                    "setOn" -> {
                        ChatInbox.setOn(app, call.argument<Boolean>("on") == true)
                        result.success(true)
                    }
                    "take" -> result.success(ChatInbox.take())
                    "ask" -> {
                        val id = (call.argument<Any>("id") as? Number)?.toInt()
                        result.success(
                            id != null && ChatInbox.ask(
                                app, id,
                                call.argument<String>("draft").orEmpty(),
                                call.argument<String>("title").orEmpty(),
                                call.argument<String>("body").orEmpty(),
                            )
                        )
                    }
                    "skip" -> {
                        (call.argument<Any>("id") as? Number)?.toInt()?.let { ChatInbox.skip(app, it) }
                        result.success(true)
                    }
                    "openAccess" -> result.success(openAccess(app))
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.w(TAG, "${call.method}: ${e.javaClass.simpleName}")
                result.success(false)
            }
        }
    }

    /** หน้าของระบบที่เจ้าของเปิดสิทธิ์เอง · Android 11+ ไปตรงหน้าของแอปเรา */
    private fun openAccess(context: Context): Boolean {
        val direct = if (Build.VERSION.SDK_INT >= 30) {
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                .putExtra(
                    Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                    ChatInbox.accessComponent(context).flattenToString(),
                )
        } else {
            null
        }
        for (intent in listOfNotNull(direct, Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))) {
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return true
            } catch (_: ActivityNotFoundException) {
            } catch (_: SecurityException) {
            }
        }
        return false
    }
}
