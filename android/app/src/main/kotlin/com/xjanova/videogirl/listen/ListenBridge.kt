package com.xjanova.videogirl.listen

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * ช่องไมค์ของมายด์ · คู่กับ lib/ai/mind_listen.dart
 *
 * อยู่ใน [com.xjanova.videogirl.SystemBridge.attach] เหตุผลเดียวกับ HandsBridge · ต้องตอบได้โดยไม่มี Activity
 *
 * 🔒 ไม่ลงเนื้อเสียงหรือข้อความใน log
 */
object ListenBridge {
    private const val TAG = "GigGokListen"
    private val main = Handler(Looper.getMainLooper())

    fun attach(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        val channel = MethodChannel(messenger, "giggok/listen")
        ListenService.events = { name, args -> main.post { channel.invokeMethod(name, args) } }
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(ListenService.status(app))
                    "locked" -> result.success(ListenService.locked(app))
                    "sync" -> {
                        ListenService.sync(app)
                        result.success(true)
                    }
                    // คืนเมื่อบริการขึ้นจริงแล้วเท่านั้น · Dart ต้องรู้ว่าไมค์อยู่รอดเบื้องหลังไหม
                    "open" -> ListenService.open(app) { ok -> main.post { result.success(ok) } }
                    "claim" -> {
                        ListenService.claim()
                        result.success(true)
                    }
                    "close" -> {
                        ListenService.close(app)
                        result.success(true)
                    }
                    "teachStart" -> ListenService.teachStart(app) { ok -> main.post { result.success(ok) } }
                    "teachStop" -> {
                        ListenService.teachStop(app)
                        result.success(true)
                    }
                    "setWake" -> {
                        ListenService.setWake(app, call.argument<Boolean>("on") == true)
                        result.success(true)
                    }
                    "setSensitivity" -> {
                        ListenService.setSensitivity(app, call.argument<Int>("level") ?: 1)
                        result.success(true)
                    }
                    "setLabel" -> {
                        ListenService.setLabel(app, call.argument<String>("word").orEmpty())
                        result.success(true)
                    }
                    "forget" -> {
                        ListenService.forget(app)
                        result.success(true)
                    }
                    "setReplies" -> {
                        val clips = call.argument<List<Map<String, Any?>>>("clips").orEmpty().mapNotNull { c ->
                            val bytes = c["bytes"] as? ByteArray ?: return@mapNotNull null
                            bytes to (if (c["ext"] == "wav") "wav" else "mp3")
                        }
                        ListenService.setReplies(app, clips)
                        result.success(true)
                    }
                    "playReply" -> {
                        ListenService.playReply(app)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.w(TAG, "${call.method}: ${e.javaClass.simpleName}")
                result.success(false)
            }
        }
        EventChannel(messenger, "giggok/listen/pcm").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                ListenService.sink = { pcm -> main.post { events.success(pcm) } }
            }

            override fun onCancel(arguments: Any?) {
                ListenService.sink = null
            }
        })
    }
}
