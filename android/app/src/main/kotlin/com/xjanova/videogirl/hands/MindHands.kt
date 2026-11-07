package com.xjanova.videogirl.hands

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeInfo.AccessibilityAction
import android.view.accessibility.AccessibilityWindowInfo
import java.io.ByteArrayOutputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

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
        AskOverlay.hide()
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

    /** มีแอปที่ห้ามอ่านอยู่บนจอไหม · ตรวจทุกหน้าต่าง (จอแยก หน้าต่างลอย) · ถามไม่ได้ = ถือว่ามี */
    private fun blockedOnScreen(): Boolean = try {
        HandsPolicy.isBlocked(this, activeRoot()?.packageName?.toString()) || windows.any { w ->
            val pkg = w.root?.packageName?.toString()
            pkg != packageName && HandsPolicy.isBlocked(this, pkg)
        }
    } catch (_: Exception) {
        true
    }

    /** ขนาดจอจริง (พิกเซล) จากภาพจอล่าสุด · 0 = ยังไม่เคยถ่าย · [tapAt] กดได้เฉพาะในกรอบนี้ */
    @Volatile private var shotW = 0
    @Volatile private var shotH = 0

    /**
     * ถ่ายภาพจอเป็น JPEG ด้านยาวไม่เกิน [maxEdge] · เรียกนอกเธรดหลัก
     *
     * 🔴 กติกาเดียวกับ [snapshot]: แอปใน [HandsPolicy] ไม่ถ่าย · ตรวจทั้งก่อนและหลังถ่าย
     * เพราะแอปธนาคารเปิดขึ้นมาระหว่างรอภาพได้ · หน้าต่างกันถ่ายจอ (FLAG_SECURE) ตอบ `secure`
     *
     * [marks] = ตีกรอบและเลขของปุ่มจากภาพจอตัวหนังสือล่าสุด ([snapshot]) ลงบนภาพ · ไอคอนที่ไม่มีชื่อ
     * เธอเห็นว่าเป็นปุ่มเลขไหน แล้วกดด้วยเลขได้ (ฝั่งแอปรู้ว่ากดอะไร ถามเจ้าของได้ถูกปุ่ม)
     * · คืน `w`/`h` = ขนาดภาพ · `sw`/`sh` = ขนาดจอจริง ไว้แปลงจุดบนภาพเป็นจุดบนจอ
     */
    fun screenshot(maxEdge: Int, marks: Boolean = false): Map<String, Any> {
        if (Build.VERSION.SDK_INT < 30) return err("unsupported")
        HandsControl.blockReason(this)?.let { return err(it) }
        if (blockedOnScreen()) return err("blocked")
        val latch = CountDownLatch(1)
        val shot = AtomicReference<ScreenshotResult?>()
        val failure = AtomicReference<Int?>()
        val late = AtomicBoolean(false)
        takeScreenshot(Display.DEFAULT_DISPLAY, mainExecutor, object : TakeScreenshotCallback {
            override fun onSuccess(result: ScreenshotResult) {
                // รอเลิกไปแล้ว · ไม่มีใครปิดบัฟเฟอร์ให้
                if (late.get()) result.hardwareBuffer.close() else shot.set(result)
                latch.countDown()
            }

            override fun onFailure(errorCode: Int) {
                failure.set(errorCode)
                latch.countDown()
            }
        })
        if (!latch.await(4, TimeUnit.SECONDS)) late.set(true)
        val result = shot.getAndSet(null)
            ?: return err(if (failure.get() == ERROR_TAKE_SCREENSHOT_SECURE_WINDOW) "secure" else "failed")
        val buffer = result.hardwareBuffer
        try {
            if (blockedOnScreen()) return err("blocked")
            val hardware = Bitmap.wrapHardwareBuffer(buffer, result.colorSpace) ?: return err("failed")
            val soft = hardware.copy(Bitmap.Config.ARGB_8888, false)
            hardware.recycle()
            if (soft == null) return err("failed")
            val sw = soft.width
            val sh = soft.height
            val scale = maxEdge.toFloat() / maxOf(sw, sh)
            var small = if (scale < 1f) {
                Bitmap.createScaledBitmap(soft, (sw * scale).toInt(), (sh * scale).toInt(), true)
            } else {
                soft
            }
            if (marks) {
                val drawable = if (small.isMutable) small else small.copy(Bitmap.Config.ARGB_8888, true)
                if (drawable != null) {
                    if (drawable !== small && small !== soft) small.recycle()
                    small = drawable
                    drawMarks(small, small.width.toFloat() / sw)
                }
            }
            val out = ByteArrayOutputStream()
            small.compress(Bitmap.CompressFormat.JPEG, 70, out)
            val w = small.width
            val h = small.height
            if (small !== soft) small.recycle()
            soft.recycle()
            shotW = sw
            shotH = sh
            return mapOf("ok" to true, "jpeg" to out.toByteArray(), "w" to w, "h" to h, "sw" to sw, "sh" to sh)
        } finally {
            buffer.close()
        }
    }

    /** กรอบและเลขของปุ่มที่กด/พิมพ์ได้ · ใช้กรอบที่จำไว้ตอนอ่านจอ ไม่ถามระบบซ้ำทีละปุ่ม */
    private fun drawMarks(bmp: Bitmap, scale: Float) {
        val nodes = synchronized(nodesLock) { lastNodes }
        if (nodes.isEmpty()) return
        val canvas = Canvas(bmp)
        val box = Paint().apply {
            style = Paint.Style.STROKE
            strokeWidth = 2f
            color = Color.MAGENTA
        }
        val tag = Paint().apply { color = Color.MAGENTA }
        val num = Paint().apply {
            color = Color.WHITE
            textSize = 18f
            isAntiAlias = true
            typeface = Typeface.DEFAULT_BOLD
        }
        val r = Rect()
        for ((id, n) in nodes.withIndex()) {
            if (!(n.isClickable || n.isLongClickable || n.isCheckable || n.isEditable)) continue
            n.getBoundsInScreen(r)
            if (r.isEmpty) continue
            val left = r.left * scale
            val top = r.top * scale
            canvas.drawRect(left, top, r.right * scale, r.bottom * scale, box)
            val label = id.toString()
            val tw = num.measureText(label)
            canvas.drawRect(left, top, left + tw + 6f, top + 20f, tag)
            canvas.drawText(label, left + 3f, top + 16f, num)
        }
    }

    // ── ทำ ─────────────────────────────────────────────────

    /**
     * แตะจุดบนจอ (พิกเซลจริง) · ใช้กับสิ่งที่ไม่มีในภาพจอตัวหนังสือ (แผงสั่งอุปกรณ์ที่วาดเป็นภาพ ปุ่มในเว็บ)
     *
     * 🔴 กดได้เฉพาะหลังถ่ายภาพจอแล้ว (เธอต้องเห็นก่อนกด) · มีแอปที่ห้ามแตะอยู่บนจอ = ไม่กดเลย ·
     * จุดที่ตกบนช่องรหัสผ่านไม่กด · ถามเจ้าของก่อนกดเป็นหน้าที่ของ PhonePolicy ฝั่งแอป
     */
    fun tapAt(x: Int, y: Int): Map<String, Any> {
        HandsControl.blockReason(this)?.let { return err(it) }
        if (shotW <= 0 || shotH <= 0) return err("no_look")
        if (x < 0 || y < 0 || x >= shotW || y >= shotH) return err("bad_point")
        if (blockedOnScreen()) return err("blocked")
        val hit = activeRoot()?.let { nodeAtPoint(it, x, y, 0) }
        if (hit != null) {
            if (blocked(hit)) return err("blocked")
            if (hit.isPassword) return err("password")
        }
        HandsControl.blockReason(this)?.let { return err(it) }
        val ok = gesture(x.toFloat(), y.toFloat(), x.toFloat(), y.toFloat(), 60L)
        return if (ok) mapOf("ok" to true) else err("failed")
    }

    /** ชิ้นในสุดที่มองเห็นและครอบจุดนี้ */
    private fun nodeAtPoint(node: AccessibilityNodeInfo, x: Int, y: Int, depth: Int): AccessibilityNodeInfo? {
        if (depth > 64 || !node.isVisibleToUser) return null
        val r = Rect()
        node.getBoundsInScreen(r)
        if (!r.contains(x, y)) return null
        for (i in node.childCount - 1 downTo 0) {
            val c = node.getChild(i) ?: continue
            nodeAtPoint(c, x, y, depth + 1)?.let { return it }
        }
        return node
    }

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
            "tap", "long_press" -> tap(id, action == "long_press", finger = false)
            "press" -> tap(id, long = false, finger = true)
            "type" -> type(id, text ?: "")
            "submit" -> submit(id)
            "scroll" -> scroll(id, dir ?: "down")
            "drag" -> drag(id, text?.toIntOrNull(), dir)
            else -> err("unsupported")
        }
    }

    private fun global(what: Int): Map<String, Any> =
        if (performGlobalAction(what)) mapOf("ok" to true) else err("failed")

    /**
     * [finger] = แตะด้วยนิ้วจริงที่กลางปุ่มเลย ไม่สั่งกดผ่านระบบ · ปุ่มในหน้าเว็บของแอป (การ์ดอุปกรณ์ใน Tuya)
     * ตอบว่ากดแล้วแต่ไม่มีอะไรเกิดขึ้น · ฝั่งแอปเลือกเองเมื่อการกดแบบปกติไม่ทำให้จอเปลี่ยน ·
     * ปุ่มที่อยู่ในหน้าเว็บใช้นิ้วตั้งแต่ครั้งแรกเลย (เจอบนเครื่อง v0.1.66: กดครั้งแรกไม่ติด เธอระวังไม่กดซ้ำสวิตช์ไฟ เลยยอมแพ้)
     */
    private fun tap(id: Int?, long: Boolean, finger: Boolean): Map<String, Any> {
        val node = (if (id == null) null else nodeAt(id)) ?: return err("stale")
        if (blocked(node)) return err("blocked")
        val action = if (long) AccessibilityNodeInfo.ACTION_LONG_CLICK else AccessibilityNodeInfo.ACTION_CLICK
        fun can(n: AccessibilityNodeInfo) = if (long) n.isLongClickable else n.isClickable
        if (finger || (!long && inWebPage(node))) {
            // นิ้วตกที่สิ่งที่อยู่บนสุดตรงจุดนั้น · กติกาเดียวกับ tapAt
            val r = Rect()
            node.getBoundsInScreen(r)
            val hit = if (r.isEmpty) null else activeRoot()?.let { nodeAtPoint(it, r.centerX(), r.centerY(), 0) }
            if (hit != null) {
                if (blocked(hit)) return err("blocked")
                if (hit.isPassword) return err("password")
            }
        } else if (can(node)) {
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

    /** อยู่ในหน้าเว็บ (WebView หรือเว็บวิวของแอปเอง) · ปุ่มในเว็บตอบรับคำสั่งกดผ่านระบบแต่ไม่ทำอะไร */
    private fun inWebPage(node: AccessibilityNodeInfo): Boolean {
        var p: AccessibilityNodeInfo? = node
        var depth = 0
        while (p != null && depth < 40) {
            if (p.className?.toString()?.contains("WebView", ignoreCase = true) == true) return true
            p = p.parent
            depth++
        }
        return false
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

    /**
     * ลากจากปุ่มหนึ่งไปอีกปุ่ม หรือไปขอบจอ ([dir] left/right = พลิกหน้า) · เจ้าของ: "จัดเรียงไอค่อน หน้าจอได้ จัดหมวดหมู่ได้"
     *
     * 🔴 Android ไม่มีทางให้แอปอื่นสั่งย้ายไอคอนของตัวเปิดแอป · ทางเดียวคือนิ้วจำลองแบบเดียวกับคน: กดค้างจนไอคอนหลุด
     * แล้วลาก · ทั้งเส้นต้องเป็นนิ้วเดียวไม่ยกขึ้น จึงต่อเส้นด้วย continueStroke แทนการปัดธรรมดา
     */
    private fun drag(id: Int?, toId: Int?, dir: String?): Map<String, Any> {
        val from = (if (id == null) null else nodeAt(id)) ?: return err("stale")
        if (blocked(from)) return err("blocked")
        val a = Rect()
        from.getBoundsInScreen(a)
        if (a.isEmpty) return err("failed")
        val edge = toId == null
        val dm = resources.displayMetrics
        val end = if (toId != null) {
            val to = nodeAt(toId) ?: return err("stale")
            if (blocked(to)) return err("blocked")
            val b = Rect()
            to.getBoundsInScreen(b)
            if (b.isEmpty) return err("failed")
            b.exactCenterX() to b.exactCenterY()
        } else {
            when (dir) {
                "left" -> 4f to a.exactCenterY()
                "right" -> dm.widthPixels - 4f to a.exactCenterY()
                else -> return err("failed")
            }
        }
        HandsControl.blockReason(this)?.let { return err(it) }
        val x1 = a.exactCenterX()
        val y1 = a.exactCenterY()
        fun line(fromX: Float, fromY: Float, toX: Float, toY: Float) = Path().apply {
            moveTo(fromX, fromY)
            lineTo(toX, toY)
        }
        // เส้นยาวศูนย์ใช้ไม่ได้ · ขยับหนึ่งพิกเซลแทนการอยู่นิ่ง
        val hold = GestureDescription.StrokeDescription(line(x1, y1, x1 + 1f, y1), 0L, 750L, true)
        val move = hold.continueStroke(line(x1 + 1f, y1, end.first, end.second), 0L, 650L, true)
        // ค้างที่ปลายทาง ตัวเปิดแอปจะได้เปิดช่องหรือพลิกหน้า ก่อนปล่อย
        val rest = move.continueStroke(line(end.first, end.second, end.first, end.second + 1f), 0L, if (edge) 1200L else 450L, false)
        for (stroke in listOf(hold, move, rest)) {
            if (!send(GestureDescription.Builder().addStroke(stroke).build())) return err("failed")
        }
        return mapOf("ok" to true)
    }

    /** แตะ/กดค้าง/ปัด ด้วยนิ้วจำลอง · รอผลไม่เกิน 3 วิ */
    private fun gesture(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long): Boolean {
        val path = Path().apply {
            moveTo(x1.coerceAtLeast(0f), y1.coerceAtLeast(0f))
            if (x1 != x2 || y1 != y2) lineTo(x2.coerceAtLeast(0f), y2.coerceAtLeast(0f))
        }
        return send(
            GestureDescription.Builder()
                .addStroke(GestureDescription.StrokeDescription(path, 0L, durationMs))
                .build(),
        )
    }

    private fun send(g: GestureDescription): Boolean {
        // 🔒 กล่อง "ทำเลย / ไม่ต้อง" ลอยอยู่ = นิ้วจำลองแตะอะไรไม่ได้ · เธอต้องไม่กดอนุมัติตัวเอง (ดู AskOverlay)
        if (AskOverlay.showing) return false
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
