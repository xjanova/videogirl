package com.xjanova.videogirl

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.MethodChannel

/**
 * ถอดเสียงเป็นข้อความ **โดยไม่ให้เสียงออกนอกเครื่อง**
 *
 * ## 🔴 ทำไมต้องเป็น on-device เท่านั้น ไม่ใช่ SpeechRecognizer ธรรมดา
 *
 * `SpeechRecognizer.createSpeechRecognizer()` ตัวปกติ **ส่งเสียงขึ้นเซิร์ฟเวอร์
 * ของกูเกิล** ซึ่งขัดกับสัญญาข้อเดียวที่ "สมองในเครื่อง" ให้ไว้กับผู้ใช้
 * (ดู mind_state.dart · `_networkBrain`) และเสียงพูดเป็นข้อมูลที่อ่อนไหว
 * กว่าข้อความที่พิมพ์อีก
 *
 * `EXTRA_PREFER_OFFLINE` **ไม่พอ** เพราะมันเป็นแค่ *คำขอ* — ถ้าเครื่องไม่มี
 * ชุดภาษาออฟไลน์ ระบบจะเงียบ ๆ ตกไปใช้ทางออนไลน์แทน ซึ่งเป็นความล้มเหลว
 * แบบที่ไม่มีใครเห็น และเป็นแบบที่แย่ที่สุดสำหรับเรื่องความเป็นส่วนตัว
 *
 * `createOnDeviceSpeechRecognizer()` (Android 12 / API 31 ขึ้นไป) เป็นทางเดียว
 * ที่**รับประกัน**ว่าเสียงไม่ออกไปไหน · เครื่องที่เก่ากว่านั้นตอบว่าใช้ไม่ได้
 * ตรง ๆ ดีกว่าใช้ทางที่อาจส่งเสียงออกไปโดยที่เจ้าของไม่รู้
 *
 * ## ช่องคุยแยกจาก giggok/system โดยตั้งใจ
 *
 * ฝั่ง Dart ของช่องนั้นมี [CallWatch] เป็นเจ้าของ handler แต่เพียงผู้เดียว
 * ตั้งซ้อนจะไปทับของมันเงียบ ๆ แล้วสัญญาณสายเข้าหายไปทั้งแอปโดยไม่มี error
 */
class MindSpeech(private val activity: MainActivity) {

    companion object {
        const val CHANNEL = "giggok/stt"

        /** ต่ำกว่านี้ไม่มี `createOnDeviceSpeechRecognizer` = ไม่มีทางรับประกัน */
        private const val MIN_SDK_ON_DEVICE = 31
    }

    private var channel: MethodChannel? = null
    private var recognizer: SpeechRecognizer? = null

    /** รอบนี้ได้ข้อความอะไรมาแล้วบ้าง — ใช้ตอนผู้ใช้กดหยุดเอง */
    private var heard: String = ""
    private var listening = false

    fun attach(messenger: io.flutter.plugin.common.BinaryMessenger) {
        channel = MethodChannel(messenger, CHANNEL)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(available())
                "start" -> {
                    start(call.argument<String>("locale") ?: "th-TH")
                    result.success(true)
                }
                "stop" -> {
                    stop()
                    result.success(true)
                }
                "cancel" -> {
                    cancel()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * เครื่องนี้ถอดเสียงในเครื่องได้ไหม
     *
     * ตอบ false เมื่อ **ยังไม่ได้โหลดชุดภาษาลงเครื่อง** ด้วย ซึ่งเป็นกรณี
     * ที่พบบ่อยกว่าเครื่องเก่าเสียอีก · ฝั่ง Dart เอาไปบอกผู้ใช้ว่าต้องไปโหลด
     */
    private fun available(): Boolean {
        if (Build.VERSION.SDK_INT < MIN_SDK_ON_DEVICE) return false
        return try {
            SpeechRecognizer.isOnDeviceRecognitionAvailable(activity)
        } catch (e: Throwable) {
            // เมธอดนี้เพิ่งมีใน API 33 · เครื่อง 31–32 ตกมาที่นี่
            // ตอบ true ไว้ก่อนแล้วให้ความล้มเหลวจริงมาทาง onError
            // ซึ่งมีข้อความบอกสาเหตุชัดกว่าการเดาตรงนี้
            Build.VERSION.SDK_INT >= MIN_SDK_ON_DEVICE
        }
    }

    private fun start(locale: String) {
        if (listening) return
        if (!available()) {
            send("error", mapOf("code" to "unavailable"))
            return
        }

        heard = ""
        activity.runOnUiThread {
            try {
                release()
                // 🔴 createOnDeviceSpeechRecognizer เท่านั้น ห้ามตกไปใช้ตัวปกติ
                // ตัวปกติส่งเสียงขึ้นเซิร์ฟเวอร์ ซึ่งเป็นสิ่งเดียวที่ทั้งไฟล์นี้
                // มีไว้เพื่อป้องกัน
                val r = SpeechRecognizer.createOnDeviceSpeechRecognizer(activity)
                recognizer = r
                r.setRecognitionListener(listener)

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                    .putExtra(
                        RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                        RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                    )
                    .putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                    // ขอผลระหว่างพูดด้วย — ผู้ใช้จะได้เห็นว่ามันได้ยินอยู่จริง
                    // ไม่ใช่นั่งมองจอนิ่ง ๆ แล้วเดาว่าไมค์ทำงานหรือเปล่า
                    .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    // ย้ำอีกชั้นแม้ตัว on-device จะออฟไลน์อยู่แล้ว —
                    // ไม่เสียอะไร และกันกรณีที่ระบบเปลี่ยนพฤติกรรมในอนาคต
                    .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)

                listening = true
                r.startListening(intent)
                send("listening", emptyMap())
            } catch (e: Throwable) {
                listening = false
                send("error", mapOf("code" to "start", "detail" to (e.message ?: "")))
            }
        }
    }

    /** ผู้ใช้กดหยุด — บอกให้ระบบสรุปผลจากที่ได้ยินมาแล้ว */
    private fun stop() {
        if (!listening) return
        activity.runOnUiThread {
            try {
                recognizer?.stopListening()
            } catch (e: Throwable) {
                finish()
            }
        }
    }

    /** ทิ้งรอบนี้ไปเลย ไม่เอาผล */
    private fun cancel() {
        activity.runOnUiThread {
            try {
                recognizer?.cancel()
            } catch (e: Throwable) {
                // ยกเลิกไม่สำเร็จก็ปล่อย · release ข้างล่างเก็บให้อยู่แล้ว
            }
            listening = false
            heard = ""
            release()
            send("cancelled", emptyMap())
        }
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) = send("ready", emptyMap())

        override fun onBeginningOfSpeech() {}

        /**
         * ระดับเสียง — ส่งต่อให้วงรอบปุ่มไมค์เต้นตามเสียงจริง
         *
         * ค่าที่ได้เป็นเดซิเบลคร่าว ๆ ราว -2..10 ไม่ใช่ 0..1 · แปลงฝั่ง Dart
         * เพื่อให้ตรรกะการแปลงอยู่ที่เดียวกับที่ใช้กับทางอัดเสียงเอง
         */
        override fun onRmsChanged(rmsdB: Float) =
            send("level", mapOf("rms" to rmsdB))

        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() {}

        override fun onError(error: Int) {
            listening = false
            release()
            send("error", mapOf("code" to codeOf(error)))
        }

        override fun onResults(results: Bundle?) {
            val best = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                ?: heard
            listening = false
            release()
            send("result", mapOf("text" to best))
        }

        override fun onPartialResults(partial: Bundle?) {
            val text = partial
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull()
                ?: return
            if (text.isNotBlank()) heard = text
            send("partial", mapOf("text" to text))
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    /**
     * แปลงรหัสของระบบเป็นชื่อที่ฝั่ง Dart เอาไปเลือกข้อความเองได้
     *
     * ส่งเป็น**ชื่อ** ไม่ใช่ข้อความภาษาคน เพราะข้อความต้องแปลสองภาษา
     * และตารางแปลอยู่ฝั่ง Dart ที่เดียว (ดู i18n/strings.dart)
     */
    private fun codeOf(error: Int): String = when (error) {
        SpeechRecognizer.ERROR_NO_MATCH -> "noMatch"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "noMatch"
        SpeechRecognizer.ERROR_AUDIO -> "mic"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "permission"
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "language"
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "language"
        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "busy"
        else -> "failed"
    }

    private fun finish() {
        listening = false
        release()
        send("result", mapOf("text" to heard))
    }

    private fun release() {
        try {
            recognizer?.destroy()
        } catch (e: Throwable) {
            // ปล่อยไม่สำเร็จก็ปล่อย · ตัวใหม่จะถูกสร้างทับรอบหน้าอยู่แล้ว
        }
        recognizer = null
    }

    private fun send(event: String, data: Map<String, Any?>) {
        channel?.invokeMethod("onStt", data + mapOf("event" to event))
    }

    fun dispose() {
        listening = false
        release()
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
