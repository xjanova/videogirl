package com.xjanova.videogirl

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * ตัวเธอ (Dart ทั้งก้อน) ที่อยู่ได้โดยไม่ต้องมีจอ
 *
 * ## 🔴 ปัญหาที่แก้
 *
 * บทสนทนาในสายอยู่ฝั่ง Dart ทั้งหมด (สมอง เสียง ฟัง) · เดิม Dart เกิดพร้อม
 * MainActivity และตายพร้อมมัน · แอปถูกระบบปิด (vivo/OPPO/Xiaomi ปิดแอปเบื้องหลัง
 * เก่งมาก) แล้วสายเข้าตอนจอล็อก = ไม่มีใครคุย จอสายจึง**ไม่ยอมให้เธอรับเลย**
 * (รับแล้วไม่มีคนคุย = ลำโพงเปิด ปลายสายได้ยินเสียงในห้องเจ้าของ)
 * · เจ้าของ: "สำคัญคือ ไม่ยอมรับสายเองเลย"
 *
 * ## ทำยังไง
 *
 * engine ก้อนเดียวของทั้งแอป เก็บใน [FlutterEngineCache] · ใครมาก่อนสร้าง:
 * - เปิดแอปปกติ → MainActivity ขอผ่าน `provideFlutterEngine` (แทนการสร้างของตัวเอง)
 * - สายดังแล้วไม่มีตัวเธอ → จอสาย ([InCallActivity]) ปลุกขึ้นมาระหว่างกริ่งดัง
 *   Dart เปิดตัวเต็มรูปแบบ (ค่าตั้ง สมอง ความจำ) แค่ไม่มีจอ · ตอบช่อง
 *   giggok/system ด้วย [SystemBridge]
 *
 * Activity ถูกทำลาย engine ไม่ตาย (เจ้าของ engine คือที่นี่ ไม่ใช่ Activity) ·
 * ปุ่ม "ออกจากแอป" ยังปิดทุกอย่างจริงเพราะจบทั้งโปรเซส
 */
object MindEngine {

    private const val ID = "mind"
    private const val TAG = "MindEngine"

    @Volatile
    private var bridge: SystemBridge? = null

    /** ตัวเธอตื่นอยู่ไหม (Dart กำลังวิ่งใน engine ก้อนนี้) */
    @JvmStatic
    val running: Boolean
        get() = FlutterEngineCache.getInstance().contains(ID)

    /** ช่องที่ไม่ต้องมีจอของ engine นี้ · null = engine ไม่ได้มาจากที่นี่ */
    @JvmStatic
    fun bridgeOf(engine: FlutterEngine): SystemBridge? =
        bridge?.takeIf { FlutterEngineCache.getInstance().get(ID) === engine }

    /**
     * engine ของทั้งแอป · ยังไม่มี = สร้างแล้วเริ่ม Dart ทันที
     *
     * ต้องเรียกบนเธรดหลัก (FlutterEngine บังคับ)
     */
    @JvmStatic
    fun obtain(context: Context): FlutterEngine {
        main.removeCallbacks(release)
        FlutterEngineCache.getInstance().get(ID)?.let { return it }
        val app = context.applicationContext
        val engine = FlutterEngine(app)
        // 🔴 ตั้งช่องก่อนเริ่ม Dart · คำถามแรกของ Dart (สิทธิ์ สถานะสาย) ต้องมีคนตอบ
        val b = SystemBridge(app)
        b.attach(engine.dartExecutor.binaryMessenger)
        bridge = b
        engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {}
            override fun onEngineWillDestroy() {
                FlutterEngineCache.getInstance().remove(ID)
                bridge = null
            }
        })
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ID, engine)
        return engine
    }

    /**
     * ปลุกตัวเธอขึ้นมาถ้ายังไม่ตื่น · ล้มเงียบ ๆ (คืน false) — จอสายต้องไม่พังตาม
     *
     * จอสายพัง = เจ้าของรับสายไม่ได้ทั้งเครื่อง · ปลุกไม่ขึ้นแย่น้อยกว่ามาก
     */
    private val main = Handler(Looper.getMainLooper())

    private val release = Runnable {
        // เจ้าของเปิดแอปอยู่ หรือมีสายใหม่เข้ามา = ยังต้องใช้
        if (MainActivity.dartAlive || MindInCallService.service != null) return@Runnable
        FlutterEngineCache.getInstance().get(ID)?.destroy()
    }

    /**
     * สายจบแล้ว ไม่มีจอ = ปล่อยตัวเธอที่ถูกปลุกมาเบื้องหลัง
     *
     * 🔴 รอก่อน · หลังวางสาย Dart ยังสรุปเรื่องที่ฝากไว้ด้วยสมอง (สมองในเครื่องช้า)
     * · ไม่ปล่อยเลย = สมองในเครื่อง (หลาย GB) ค้างอยู่เบื้องหลัง เครื่องร้อนเปล่า ๆ
     */
    @JvmStatic
    fun releaseWhenIdle() {
        main.removeCallbacks(release)
        main.postDelayed(release, RELEASE_AFTER_MS)
    }

    private const val RELEASE_AFTER_MS = 120_000L

    @JvmStatic
    fun wake(context: Context): Boolean = try {
        obtain(context)
        true
    } catch (e: Throwable) {
        Log.w(TAG, "wake failed: ${e.javaClass.simpleName}")
        false
    }
}
