package com.xjanova.videogirl.hands

import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent

/**
 * จำขั้นตอนที่เจ้าของทำให้ดูหนึ่งครั้ง ("ทำให้ดูครั้งเดียว") · เธอเอาไปทำซ้ำเองทีหลัง
 *
 * - ไม่จำอะไรในแอปเราเองและแอปใน [HandsPolicy] (ธนาคาร การเงิน ฯลฯ)
 * - ช่องรหัสผ่าน: จำแค่ว่า "พิมพ์รหัสผ่าน" ไม่จำตัวอักษร
 * - พิมพ์ต่อเนื่องในช่องเดียวกัน = ขั้นเดียว (เอาข้อความสุดท้าย) · เลื่อนทางเดิมติดกัน = ขั้นเดียว
 * - เกิน [CAP] ขั้นไม่จำเพิ่ม
 * - ไม่ลง log อะไรทั้งนั้น
 */
internal object HandsRecorder {
    private const val CAP = 200
    private const val TYPED_MAX = 2000

    private val steps = ArrayList<HashMap<String, Any>>()
    private var startedAt = 0L
    private var lastApp = ""
    private var typingKey: String? = null
    private var lastScrollY = -1

    @Synchronized fun start() {
        steps.clear()
        startedAt = SystemClock.uptimeMillis()
        lastApp = ""
        typingKey = null
        lastScrollY = -1
    }

    @Synchronized fun take(): List<Map<String, Any>> {
        val out = steps.map { HashMap(it) }
        steps.clear()
        typingKey = null
        return out
    }

    @Synchronized fun onEvent(context: Context, e: AccessibilityEvent) {
        val pkg = e.packageName?.toString() ?: return
        if (HandsPolicy.isBlocked(context, pkg)) return
        val t = SystemClock.uptimeMillis() - startedAt
        when (e.eventType) {
            AccessibilityEvent.TYPE_VIEW_CLICKED -> click(context, e, pkg, t, "tap")
            AccessibilityEvent.TYPE_VIEW_LONG_CLICKED -> click(context, e, pkg, t, "long")
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> typed(context, e, pkg, t)
            AccessibilityEvent.TYPE_VIEW_SCROLLED -> scrolled(context, e, pkg, t)
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                if (pkg != lastApp && HandsPolicy.isLaunchable(context, pkg)) {
                    lastApp = pkg
                    add(base(context, "app", pkg, t))
                    typingKey = null
                }
            }
        }
    }

    private fun add(step: HashMap<String, Any>) {
        if (steps.size < CAP) steps.add(step)
    }

    private fun base(context: Context, kind: String, pkg: String, t: Long) = hashMapOf<String, Any>(
        "kind" to kind,
        "package" to pkg,
        "app" to HandsPolicy.label(context, pkg),
        "t" to t,
    )

    private fun click(context: Context, e: AccessibilityEvent, pkg: String, t: Long, kind: String) {
        typingKey = null
        val step = base(context, kind, pkg, t)
        val node = e.source
        val pwd = e.isPassword || node?.isPassword == true
        var text = if (pwd) "" else MindHands.clip(node?.text ?: e.text.joinToString(" "))
        val desc = if (pwd) "" else MindHands.clip(node?.contentDescription ?: e.contentDescription)
        if (text.isEmpty() && desc.isEmpty() && !pwd && node != null) text = MindHands.descendantText(node)
        if (text.isNotEmpty()) step["text"] = text
        if (desc.isNotEmpty()) step["desc"] = desc
        node?.let { MindHands.viewId(it) }?.takeIf { it.isNotEmpty() }?.let { step["vid"] = it }
        MindHands.simpleClass(e.className).takeIf { it.isNotEmpty() }?.let { step["cls"] = it }
        if (pwd) step["pwd"] = true
        add(step)
    }

    private fun typed(context: Context, e: AccessibilityEvent, pkg: String, t: Long) {
        val node = e.source
        val pwd = e.isPassword || node?.isPassword == true
        val vid = node?.let { MindHands.viewId(it) } ?: ""
        val cls = MindHands.simpleClass(e.className)
        val key = "$pkg|${e.windowId}|$vid|$cls"
        val last = steps.lastOrNull()
        val step = if (key == typingKey && last != null && last["kind"] == "type") {
            last["t"] = t
            last
        } else {
            typingKey = key
            val s = base(context, "type", pkg, t)
            // ช่องไหน · คำใบ้/คำอธิบาย/ชื่อ id ไม่ใช่สิ่งที่พิมพ์
            val hint = MindHands.clip(node?.hintText)
            if (hint.isNotEmpty()) s["hint"] = hint
            val desc = if (pwd) "" else MindHands.clip(node?.contentDescription ?: e.contentDescription)
            if (desc.isNotEmpty()) s["desc"] = desc
            if (vid.isNotEmpty()) s["vid"] = vid
            if (cls.isNotEmpty()) s["cls"] = cls
            if (steps.size >= CAP) return
            steps.add(s)
            s
        }
        if (pwd) {
            step.remove("typed")
            step["pwd"] = true
        } else {
            val all = e.text.joinToString("")
            step["typed"] = if (all.length > TYPED_MAX) all.substring(0, TYPED_MAX) else all
        }
    }

    private fun scrolled(context: Context, e: AccessibilityEvent, pkg: String, t: Long) {
        val dir = if (Build.VERSION.SDK_INT >= 28 && e.scrollDeltaY != 0) {
            if (e.scrollDeltaY > 0) "down" else "up"
        } else if (Build.VERSION.SDK_INT >= 28 && e.scrollDeltaX != 0) {
            return // เลื่อนข้าง (รูป แท็บ) ไม่จำ
        } else if (lastScrollY >= 0 && e.scrollY != lastScrollY) {
            if (e.scrollY > lastScrollY) "down" else "up"
        } else {
            lastScrollY = e.scrollY
            return
        }
        lastScrollY = e.scrollY
        typingKey = null
        val last = steps.lastOrNull()
        if (last != null && last["kind"] == "scroll" && last["dir"] == dir && last["package"] == pkg) {
            last["t"] = t
            return
        }
        val s = base(context, "scroll", pkg, t)
        s["dir"] = dir
        add(s)
    }
}
