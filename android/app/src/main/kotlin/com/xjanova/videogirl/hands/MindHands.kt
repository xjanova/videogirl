package com.xjanova.videogirl.hands

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction
import android.view.accessibility.AccessibilityWindowInfo
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * บริการ "ให้มายด์ใช้เครื่องแทน" — อ่านจอเป็นตัวหนังสือ แล้วกด พิมพ์ เลื่อนแทนเจ้าของ
 *
 * ## 🔴 แยกจาก MindAccessibility โดยตั้งใจ
 *
 * MindAccessibility มีไว้ให้ได้ยินสาย และสัญญาว่า**ไม่อ่านหน้าจอ** · ตัวนี้อ่านได้ จึงเป็นอีกตัว
 * ที่เปิดเฉพาะตอนเธอทำงานที่เจ้าของสั่ง แล้วปิดเองหลังว่าง (ดู [HandsSwitch]) ·
 * แอปธนาคารตรวจเจอบริการที่เปิดค้าง เจ้าของจึงไม่อยากให้มันเปิดทิ้งไว้
 *
 * ## 🔴 สิ่งที่ห้ามเด็ดขาด (บังคับด้วยโค้ด ไม่ใช่ด้วยคำสั่งถึงสมอง)
 *
 * - แอปใน [HandsPolicy] (ธนาคาร การเงิน ตัวติดตั้งแอป หน้าขอสิทธิ์ แอปเราเอง): ไม่อ่านอะไรเลย
 *   กดอะไรไม่ได้นอกจากย้อนกลับ/หน้าหลัก/แอปล่าสุด
 * - ช่องรหัสผ่าน: บอกว่ามีช่อง แต่ไม่ส่งตัวอักษรออกมา และพิมพ์ลงไม่ได้
 * - ไม่ลง log ข้อความบนจอ ข้อความที่พิมพ์ หรืออะไรที่มาจากจอ · ลงแค่ชื่อคำสั่งกับรหัสผิดพลาด
 * - เจ้าของกดหยุด = ทุกคำสั่งตอบ `stopped` ทันที (ดู [HandsControl])
 */
class MindHands : AccessibilityService() {

    companion object {
        /** บริการที่เชื่อมอยู่ตอนนี้ · null = ปิดอยู่ */
        @Volatile
        var instance: MindHands? = null
            private set

        private const val TEXT_MAX = 80
        private const val TYPE_MAX = 2000
        private val SPACES = Regex("\\s+")

        internal fun clip(s: CharSequence?): String {
            if (s == null) return ""
            val t = s.toString().replace(SPACES, " ").trim()
            return if (t.length > TEXT_MAX) t.substring(0, TEXT_MAX) else t
        }

        internal fun simpleClass(s: CharSequence?): String = s?.toString()?.substringAfterLast('.') ?: ""

        internal fun viewId(node: AccessibilityNodeInfo): String {
            val raw = node.viewIdResourceName ?: return ""
            val i = raw.indexOf(":id/")
            return if (i >= 0) raw.substring(i + 4) else raw
        }

        /** ข้อความของลูกหลานต่อกัน (ปุ่มที่ตัวเองไม่มีข้อความ) · ข้ามช่องรหัสผ่านและสิ่งที่มองไม่เห็น */
        internal fun descendantText(node: AccessibilityNodeInfo): String {
            val sb = StringBuilder()
            fun walk(n: AccessibilityNodeInfo, depth: Int) {
                if (sb.length >= TEXT_MAX || depth > 8) return
                for (i in 0 until n.childCount) {
                    val c = n.getChild(i) ?: continue
                    if (!c.isVisibleToUser || c.isPassword) continue
                    val t = clip(c.text).ifEmpty { clip(c.contentDescription) }
                    if (t.isNotEmpty()) {
                        if (sb.isNotEmpty()) sb.append(' ')
                        sb.append(t)
                    }
                    walk(c, depth + 1)
                    if (sb.length >= TEXT_MAX) return
                }
            }
            walk(node, 0)
            return clip(sb)
        }
    }

    /** เวลาที่จอเปลี่ยนล่าสุด (uptime) · ใช้รอจอนิ่งก่อนอ่าน */
    @Volatile private var lastChange = 0L

    /** ปุ่ม/ช่องของภาพจอล่าสุด · เลขในภาพจอ = ตำแหน่งในรายการนี้ */
    private val nodesLock = Any()
    private var lastNodes: List<AccessibilityNodeInfo> = emptyList()

    override fun onServiceConnected() {
        super.onServiceConnected()
        // ซ่อมตัวเอง: โปรเซสตายกลางงานแล้วระบบผูกบริการคืน → ไม่มีงานแล้ว ปิดคืนหลังว่าง
        if (HandsSwitch.enabledByUs(this) && !HandsControl.active) HandsSwitch.scheduleIdleOff(this)
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        if (instance === this) instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        synchronized(nodesLock) { lastNodes = emptyList() }
        super.onDestroy()
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> lastChange = SystemClock.uptimeMillis()
        }
        // จำขั้นตอนเฉพาะตอนเจ้าของทำให้ดู · ระหว่างเธอทำเองไม่จำ
        if (HandsControl.recording && !HandsControl.running) {
            try { HandsRecorder.onEvent(this, event) } catch (_: Exception) { /* ขั้นหนึ่งหาย ดีกว่าบริการล้ม */ }
        }
    }

    // ── อ่านจอ ─────────────────────────────────────────────

    private fun err(code: String): Map<String, Any> = mapOf("ok" to false, "error" to code)

    /** หน้าต่างที่เจ้าของเห็นอยู่ */
    private fun activeRoot(): AccessibilityNodeInfo? {
        rootInActiveWindow?.let { return it }
        return try {
            val list = windows
            (list.firstOrNull { it.isFocused } ?: list.firstOrNull { it.isActive })?.root
        } catch (_: Exception) {
            null
        }
    }

    private fun keyboardShown(): Boolean = try {
        windows.any { it.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD }
    } catch (_: Exception) {
        false
    }

    /** รอจอนิ่ง แล้วอ่านจอเป็นตัวหนังสือ · เรียกนอกเธรดหลัก */
    fun snapshot(max: Int, quietMs: Long, maxWaitMs: Long): Map<String, Any> {
        val start = SystemClock.uptimeMillis()
        while (true) {
            if (HandsControl.stopRequested) return err("stopped")
            val now = SystemClock.uptimeMillis()
            if (now - lastChange >= quietMs || now - start >= maxWaitMs) break
            Thread.sleep(40)
        }
        HandsControl.blockReason(this)?.let { return err(it) }
        val root = activeRoot() ?: return err("failed")
        val pkg = root.packageName?.toString() ?: ""
        val app = HandsPolicy.label(this, pkg)
        val keyboard = keyboardShown()
        if (HandsPolicy.isBlocked(this, pkg)) {
            // ไม่อ่านอะไรของแอปนี้เลย · เลขจากภาพจอก่อนหน้าใช้ไม่ได้แล้ว
            synchronized(nodesLock) { lastNodes = emptyList() }
            return mapOf(
                "ok" to true, "package" to pkg, "app" to app, "blocked" to true,
                "keyboard" to keyboard, "nodes" to emptyList<Any>(),
            )
        }
        val limit = max.coerceIn(1, 500)
        val kept = ArrayList<AccessibilityNodeInfo>()
        val out = ArrayList<Map<String, Any>>()
        var truncated = false
        val rect = Rect()

        fun visit(node: AccessibilityNodeInfo, depth: Int) {
            if (truncated || depth > 64 || HandsControl.stopRequested) return
            if (!node.isVisibleToUser) return
            val nodePkg = node.packageName?.toString()
            if (nodePkg != null && nodePkg != pkg && HandsPolicy.isBlocked(this, nodePkg)) return
            val pwd = node.isPassword
            val text = if (pwd) "" else clip(node.text)
            val desc = if (pwd) "" else clip(node.contentDescription)
            val hint = clip(node.hintText)
            val worth = text.isNotEmpty() || desc.isNotEmpty() || hint.isNotEmpty() ||
                node.isClickable || node.isLongClickable || node.isEditable || node.isScrollable || node.isCheckable
            if (worth) {
                if (out.size >= limit) {
                    truncated = true
                    return
                }
                val m = HashMap<String, Any>()
                m["id"] = kept.size
                simpleClass(node.className).takeIf { it.isNotEmpty() }?.let { m["cls"] = it }
                val shown = if (text.isEmpty() && desc.isEmpty() && !pwd && node.isClickable) descendantText(node) else text
                if (shown.isNotEmpty()) m["text"] = shown
                if (desc.isNotEmpty()) m["desc"] = desc
                if (hint.isNotEmpty()) m["hint"] = hint
                viewId(node).takeIf { it.isNotEmpty() }?.let { m["vid"] = it }
                if (node.isClickable) m["click"] = true
                if (node.isLongClickable) m["long"] = true
                if (node.isEditable) m["edit"] = true
                if (node.isScrollable) m["scroll"] = true
                if (node.isCheckable) m["check"] = true
                // Android 16 เพิ่ม getChecked() แบบสามสถานะ · isChecked ยังตอบถูกทุกรุ่น
                @Suppress("DEPRECATION")
                if (node.isChecked) m["on"] = true
                if (pwd) m["pwd"] = true
                if (node.isSelected) m["sel"] = true
                node.getBoundsInScreen(rect)
                m["b"] = listOf(rect.left, rect.top, rect.right, rect.bottom)
                kept.add(node)
                out.add(m)
            }
            for (i in 0 until node.childCount) {
                val c = node.getChild(i) ?: continue
                visit(c, depth + 1)
                if (truncated) return
            }
        }
        visit(root, 0)
        HandsControl.blockReason(this)?.let { return err(it) }
        synchronized(nodesLock) { lastNodes = kept }
        val reply = HashMap<String, Any>()
        reply["ok"] = true
        reply["package"] = pkg
        reply["app"] = app
        reply["blocked"] = false
        reply["keyboard"] = keyboard
        reply["nodes"] = out
        if (truncated) reply["truncated"] = true
        return reply
    }

    // ── ทำ ─────────────────────────────────────────────────

    /** ปุ่มจากภาพจอล่าสุด · null = เลขเก่า/ปุ่มหายไปแล้ว */
    private fun nodeAt(id: Int): AccessibilityNodeInfo? {
        val n = synchronized(nodesLock) { lastNodes.getOrNull(id) } ?: return null
        return if (n.refresh()) n else null
    }

    private fun blocked(node: AccessibilityNodeInfo): Boolean =
        HandsPolicy.isBlocked(this, node.packageName?.toString())

    /** ทำหนึ่งอย่าง · เรียกนอกเธรดหลัก */
    fun act(action: String, id: Int?, text: String?, dir: String?): Map<String, Any> {
        HandsControl.blockReason(this)?.let { return err(it) }
        val front = activeRoot()?.packageName?.toString()
        if (HandsPolicy.isBlocked(this, front) && action !in setOf("back", "home", "recents")) return err("blocked")
        return when (action) {
            "back" -> global(GLOBAL_ACTION_BACK)
            "home" -> global(GLOBAL_ACTION_HOME)
            "recents" -> global(GLOBAL_ACTION_RECENTS)
            "notifications" -> global(GLOBAL_ACTION_NOTIFICATIONS)
            "tap", "long_press" -> tap(id, action == "long_press")
            "type" -> type(id, text ?: "")
            "submit" -> submit(id)
            "scroll" -> scroll(id, dir ?: "down")
            else -> err("unsupported")
        }
    }

    private fun global(what: Int): Map<String, Any> =
        if (performGlobalAction(what)) mapOf("ok" to true) else err("failed")

    private fun tap(id: Int?, long: Boolean): Map<String, Any> {
        val node = (if (id == null) null else nodeAt(id)) ?: return err("stale")
        if (blocked(node)) return err("blocked")
        val action = if (long) AccessibilityNodeInfo.ACTION_LONG_CLICK else AccessibilityNodeInfo.ACTION_CLICK
        fun can(n: AccessibilityNodeInfo) = if (long) n.isLongClickable else n.isClickable
        if (can(node)) {
            if (node.performAction(action)) return mapOf("ok" to true)
        } else {
            // ข้อความในปุ่มกดเองไม่ได้ · กดที่ตัวปุ่มที่ห่อมันอยู่
            var p = node.parent
            var depth = 0
            while (p != null && depth < 6) {
                if (blocked(p)) return err("blocked")
                if (can(p)) {
                    if (p.performAction(action)) return mapOf("ok" to true)
                    break
                }
                p = p.parent
                depth++
            }
        }
        val r = Rect()
        node.getBoundsInScreen(r)
        if (r.isEmpty) return err("failed")
        HandsControl.blockReason(this)?.let { return err(it) }
        val ok = gesture(r.exactCenterX(), r.exactCenterY(), r.exactCenterX(), r.exactCenterY(), if (long) 800L else 60L)
        return if (ok) mapOf("ok" to true) else err("failed")
    }

    private fun firstEditable(node: AccessibilityNodeInfo, depth: Int = 0): AccessibilityNodeInfo? {
        if (depth > 12) return null
        for (i in 0 until node.childCount) {
            val c = node.getChild(i) ?: continue
            if (c.isEditable && c.isVisibleToUser) return c
            firstEditable(c, depth + 1)?.let { return it }
        }
        return null
    }

    private fun type(id: Int?, text: String): Map<String, Any> {
        var target: AccessibilityNodeInfo? = null
        if (id != null) {
            val node = nodeAt(id) ?: return err("stale")
            target = if (node.isEditable) node else firstEditable(node)
        }
        if (target == null) target = findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (target == null || !target.isEditable) return err("failed")
        if (blocked(target)) return err("blocked")
        if (target.isPassword) return err("password")
        if (!target.isFocused) {
            if (!target.performAction(AccessibilityNodeInfo.ACTION_FOCUS)) target.performAction(AccessibilityNodeInfo.ACTION_CLICK)
        }
        HandsControl.blockReason(this)?.let { return err(it) }
        val args = Bundle()
        args.putCharSequence(
            AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
            if (text.length > TYPE_MAX) text.substring(0, TYPE_MAX) else text,
        )
        return if (target.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)) mapOf("ok" to true) else err("failed")
    }

    private fun submit(id: Int?): Map<String, Any> {
        val target = if (id != null) (nodeAt(id) ?: return err("stale")) else findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (Build.VERSION.SDK_INT < 30) return err("unsupported")
        if (target == null) return err("failed")
        if (blocked(target)) return err("blocked")
        return if (target.performAction(AccessibilityAction.ACTION_IME_ENTER.id)) mapOf("ok" to true) else err("failed")
    }

    private fun scroll(id: Int?, dir: String): Map<String, Any> {
        if (dir !in setOf("down", "up", "left", "right")) return err("failed")
        var target: AccessibilityNodeInfo? = null
        if (id != null) {
            var n: AccessibilityNodeInfo? = nodeAt(id) ?: return err("stale")
            var depth = 0
            while (n != null && depth < 12) {
                if (n.isScrollable) { target = n; break }
                n = n.parent
                depth++
            }
        }
        if (target == null) {
            val list = synchronized(nodesLock) { lastNodes }
            target = list.firstOrNull { it.isScrollable && it.refresh() }
        }
        if (target != null) {
            if (blocked(target)) return err("blocked")
            val directional = when (dir) {
                "down" -> AccessibilityAction.ACTION_SCROLL_DOWN
                "up" -> AccessibilityAction.ACTION_SCROLL_UP
                "left" -> AccessibilityAction.ACTION_SCROLL_LEFT
                else -> AccessibilityAction.ACTION_SCROLL_RIGHT
            }
            if (target.actionList.any { it.id == directional.id } && target.performAction(directional.id)) {
                return mapOf("ok" to true)
            }
            val plain = if (dir == "down" || dir == "right") AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            if (target.performAction(plain)) return mapOf("ok" to true)
        }
        HandsControl.blockReason(this)?.let { return err(it) }
        // ไม่มีอะไรเลื่อนได้ในต้นไม้ (เกม เว็บบางหน้า) · ปัดกลางจอแทน
        val dm = resources.displayMetrics
        val w = dm.widthPixels.toFloat()
        val h = dm.heightPixels.toFloat()
        val ok = when (dir) {
            "down" -> gesture(w / 2, h * 0.7f, w / 2, h * 0.3f, 300L)
            "up" -> gesture(w / 2, h * 0.3f, w / 2, h * 0.7f, 300L)
            "right" -> gesture(w * 0.8f, h / 2, w * 0.2f, h / 2, 300L)
            else -> gesture(w * 0.2f, h / 2, w * 0.8f, h / 2, 300L)
        }
        return if (ok) mapOf("ok" to true) else err("failed")
    }

    /** แตะ/กดค้าง/ปัด ด้วยนิ้วจำลอง · รอผลไม่เกิน 3 วิ */
    private fun gesture(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long): Boolean {
        val path = Path().apply {
            moveTo(x1.coerceAtLeast(0f), y1.coerceAtLeast(0f))
            if (x1 != x2 || y1 != y2) lineTo(x2.coerceAtLeast(0f), y2.coerceAtLeast(0f))
        }
        val g = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0L, durationMs))
            .build()
        val done = CountDownLatch(1)
        val ok = AtomicBoolean(false)
        val sent = try {
            dispatchGesture(g, object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    ok.set(true)
                    done.countDown()
                }

                override fun onCancelled(gestureDescription: GestureDescription?) {
                    done.countDown()
                }
            }, null)
        } catch (_: Exception) {
            false
        }
        if (!sent) return false
        done.await(3, TimeUnit.SECONDS)
        return ok.get()
    }
}
