package com.xjanova.videogirl

import android.Manifest
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.CallLog
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.provider.Settings
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.text.Editable
import android.text.TextUtils
import android.text.TextWatcher
import android.text.format.DateUtils
import android.util.LruCache
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.View
import android.view.ViewGroup
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.inputmethod.EditorInfo
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import android.widget.Toast
import com.xjanova.videogirl.PhoneUi.dp
import java.text.Collator
import java.util.Locale
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * แอปโทรศัพท์ของเครื่อง — แป้นกด · สายล่าสุด · รายชื่อ
 *
 * ## 🔴 ทำไมต้องมี ทั้งที่เธอโทรแทนได้
 *
 * เป็นแอปโทรศัพท์หลักแล้ว **แอปนี้คือแอปโทรศัพท์ของเครื่อง** ทั้งใบ
 * ระบบส่ง `DIAL` มาที่นี่ทุกครั้งที่ใครกดเบอร์จากที่ไหนก็ตาม และเจ้าของเปิดจากไอคอน
 * "โทรศัพท์" บนหน้าจอหลักเพื่อโทรเอง · ไม่มีจอนี้ = ตั้งเป็นแอปหลักแล้วโทรออกไม่ได้ทั้งเครื่อง
 *
 * เนทีฟด้วยเหตุผลเดียวกับ [InCallActivity] — ต้องขึ้นได้โดยไม่รอ engine · หน้าตาอยู่ใน [PhoneUi]
 *
 * ## 🔴 ที่ต้องระวัง
 *
 * - อ่านสมุดโทรศัพท์/ประวัติการโทรบนเธรดแยกเสมอ · รายชื่อหลายพันคนอ่านบนเธรดหลัก = จอค้างตอนเปิด
 * - กดโทรซ้ำเร็ว ๆ = สายออกสองสาย · กันไว้ที่ [place]
 * - เครื่องสองซิม: แสดงปุ่มโทรแยกซิม · สายที่มาจากที่อื่นโดยไม่ระบุซิม จอสายถามเอง (ดู InCallActivity)
 */
class DialerActivity : Activity() {

    private class Contact(
        val name: String,
        val number: String,
        val local: String,
        val label: String?,
        val photo: String?,
        val starred: Boolean,
        val t9: List<String>,
    )

    private class Recent(
        val number: String,
        val name: String?,
        val type: Int,
        val at: Long,
        var count: Int,
        val accountId: String?,
        val photo: String?,
        val hidden: Boolean,
    )

    /** หนึ่งแถวในรายการ (ล่าสุด/รายชื่อ) · สร้างจากข้อมูลบนเธรดหลัก ผูกกับ [Holder] */
    private class Row(
        val title: String,
        val titleColor: Int,
        val subtitle: String,
        val typeIcon: Int,
        val typeTint: Int,
        val typeDescription: String?,
        val number: String?,
        val accountId: String?,
        val avatarName: String?,
        val avatarKey: String,
        val photo: String?,
        val starred: Boolean,
    )

    private val ui = Handler(Looper.getMainLooper())
    private val io: ExecutorService = Executors.newSingleThreadExecutor()
    private lateinit var feedback: PhoneUi.KeyFeedback
    private var iso = "TH"

    private val digits = StringBuilder()
    private var contacts: List<Contact> = emptyList()
    private var byLocal: Map<String, Contact> = emptyMap()
    private var recents: List<Recent> = emptyList()
    private var simSlot: Map<String, Int> = emptyMap()
    private var contactsGranted = true
    private var recentsGranted = true
    private var loadSeq = 0
    private var page = PAGE_KEYPAD
    private var missedOnly = false
    private var lastPlacedAt = 0L
    private var pendingCall: Pair<String, PhoneAccountHandle?>? = null
    private val deniedForever = HashSet<String>()

    private lateinit var callBanner: LinearLayout
    private lateinit var callBannerText: TextView
    private lateinit var pageViews: Array<View>
    private lateinit var suggestions: LinearLayout
    private lateinit var display: TextView
    private lateinit var displayName: TextView
    private lateinit var backspace: FrameLayout
    private lateinit var callRow: LinearLayout
    private lateinit var recentsList: ListView
    private lateinit var recentsEmpty: LinearLayout
    private lateinit var contactsList: ListView
    private lateinit var contactsEmpty: LinearLayout
    private lateinit var search: EditText
    private lateinit var chipAll: TextView
    private lateinit var chipMissed: TextView
    private val tabs = ArrayList<LinearLayout>()
    private val recentsAdapter = RowAdapter()
    private val contactsAdapter = RowAdapter()

    /** รูปคนในรายการ · ถอดบนเธรดแยก จำไว้ไม่ต้องถอดซ้ำตอนเลื่อน */
    private val photos = LruCache<String, Bitmap>(80)
    private val noPhoto = HashSet<String>()

    private val onCallChanged = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) = renderBanner()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        feedback = PhoneUi.KeyFeedback(this)
        iso = PhoneUi.countryIso(this)
        takeNumber(intent)
        setContentView(buildUi())
        renderDigits()
        showPage(page)
    }

    /** singleTop · แตะเบอร์จากแอปอื่นตอนแป้นเปิดค้างอยู่ ต้องได้เบอร์ใหม่ ไม่ใช่เบอร์เก่าที่ค้างจอ */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (takeNumber(intent)) {
            renderDigits()
            showPage(PAGE_KEYPAD)
        }
    }

    private fun takeNumber(intent: Intent?): Boolean {
        val n = intent?.data?.takeIf { it.scheme == "tel" }?.schemeSpecificPart?.let { Uri.decode(it) }
            ?: return false
        digits.setLength(0)
        digits.append(n.filter { it.isDigit() || it in DIAL_CHARS })
        page = PAGE_KEYPAD
        return true
    }

    override fun onStart() {
        super.onStart()
        registerReceiver(
            onCallChanged,
            IntentFilter(MindInCallService.ACTION_CALL_CHANGED),
            if (Build.VERSION.SDK_INT >= 33) Context.RECEIVER_NOT_EXPORTED else 0
        )
    }

    override fun onStop() {
        try {
            unregisterReceiver(onCallChanged)
        } catch (e: IllegalArgumentException) {
            // ไม่ได้ลงทะเบียนไว้ — ไม่ใช่เรื่องที่ต้องพัง
        }
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        feedback.start()
        renderBanner()
        renderCallRow()
        // กลับจากสาย = มีสายใหม่ในประวัติ · โหลดใหม่ทุกครั้งที่กลับมา
        load()
    }

    override fun onPause() {
        feedback.stop()
        super.onPause()
    }

    override fun onDestroy() {
        loadSeq++
        io.shutdownNow()
        ui.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    // ── โครงจอ ───────────────────────────────────────────────

    private fun buildUi(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = PhoneUi.lightBackdrop()
            setPadding(dp(this@DialerActivity, 16), dp(this@DialerActivity, 8), dp(this@DialerActivity, 16), dp(this@DialerActivity, 10))
        }
        PhoneUi.edgeToEdge(this, root, lightBars = true)

        root.addView(topBar(), LinearLayout.LayoutParams(MATCH_PARENT, dp(this, 52)))
        callBanner = banner()
        root.addView(callBanner, LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).also {
            it.bottomMargin = dp(this, 8)
        })

        val pages = FrameLayout(this)
        pageViews = arrayOf(keypadPage(), recentsPage(), contactsPage())
        for (p in pageViews) pages.addView(p, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        root.addView(pages, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
        root.addView(tabBar(), LinearLayout.LayoutParams(MATCH_PARENT, dp(this, 62)).also {
            it.topMargin = dp(this, 8)
        })
        return root
    }

    private fun topBar(): View {
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(this@DialerActivity, 4), 0, 0, 0)
        }
        bar.addView(PhoneUi.text(this, 26f, PhoneUi.INK, bold = true).apply {
            setText(R.string.dial_app_label)
        }, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))

        // หน้าเธอ — แตะแล้วไปหาเธอในแอป (สั่งโทรด้วยเสียง ถามว่าใครโทรมา)
        val face = PhoneUi.mindFace(this, dp(this, 80))
        val mind = FrameLayout(this).apply {
            contentDescription = getString(R.string.dial_open_mind)
            isClickable = true
            foreground = PhoneUi.ripple(ColorDrawable(Color.TRANSPARENT), 0x337C6CFF, PhoneUi.oval(Color.WHITE))
            setOnClickListener { openMind() }
            PhoneUi.pressScale(this)
        }
        if (face != null) {
            PhoneUi.bindAvatar(mind, null, null, face, 40)
            mind.setPadding(dp(this, 2), dp(this, 2), dp(this, 2), dp(this, 2))
            mind.background = PhoneUi.ovalGradient(intArrayOf(PhoneUi.PINK, PhoneUi.VIOLET))
        } else {
            mind.background = PhoneUi.ovalGradient(intArrayOf(PhoneUi.PINK, PhoneUi.VIOLET))
            mind.addView(PhoneUi.icon(this, R.drawable.ic_ph_sparkle, Color.WHITE, 22))
        }
        bar.addView(mind, LinearLayout.LayoutParams(dp(this, 42), dp(this, 42)))
        return bar
    }

    private fun banner(): LinearLayout {
        callBannerText = PhoneUi.text(this, 14f, Color.WHITE, bold = true).apply {
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(this@DialerActivity, 16), dp(this@DialerActivity, 12), dp(this@DialerActivity, 16), dp(this@DialerActivity, 12))
            background = PhoneUi.ripple(
                PhoneUi.roundedGradient(intArrayOf(PhoneUi.GREEN, PhoneUi.GREEN_DEEP), dp(this@DialerActivity, 22).toFloat()),
                0x55FFFFFF, null
            )
            addView(PhoneUi.icon(this@DialerActivity, R.drawable.ic_ph_earpiece, Color.WHITE, 20))
            addView(callBannerText, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).also {
                it.leftMargin = dp(this@DialerActivity, 10)
            })
            visibility = View.GONE
            isClickable = true
            setOnClickListener { backToCall() }
        }
    }

    private fun tabBar(): View {
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(this@DialerActivity, 5), dp(this@DialerActivity, 5), dp(this@DialerActivity, 5), dp(this@DialerActivity, 5))
            background = PhoneUi.rounded(0xB8FFFFFF.toInt(), dp(this@DialerActivity, 31).toFloat(), dp(this@DialerActivity, 1), PhoneUi.GLASS_BORDER)
            elevation = dp(this@DialerActivity, 3).toFloat()
        }
        val items = listOf(
            R.drawable.ic_ph_dialpad to R.string.dial_tab_keypad,
            R.drawable.ic_ph_history to R.string.dial_tab_recents,
            R.drawable.ic_ph_person to R.string.dial_tab_contacts,
        )
        for ((i, item) in items.withIndex()) {
            val tab = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                isClickable = true
                contentDescription = getString(item.second)
                setOnClickListener { showPage(i) }
            }
            tab.addView(PhoneUi.icon(this, item.first, PhoneUi.INK55, 22))
            tab.addView(PhoneUi.text(this, 11f, PhoneUi.INK55, bold = true).apply {
                setText(item.second)
                setPadding(0, dp(this@DialerActivity, 3), 0, 0)
            })
            tabs.add(tab)
            bar.addView(tab, LinearLayout.LayoutParams(0, MATCH_PARENT, 1f))
        }
        return bar
    }

    private fun showPage(i: Int) {
        page = i
        for ((k, v) in pageViews.withIndex()) v.visibility = if (k == i) View.VISIBLE else View.GONE
        for ((k, tab) in tabs.withIndex()) {
            val on = k == i
            tab.background = if (on) PhoneUi.roundedGradient(intArrayOf(PhoneUi.PINK, PhoneUi.VIOLET), dp(this, 26).toFloat())
            else PhoneUi.ripple(ColorDrawable(Color.TRANSPARENT), 0x267C6CFF, PhoneUi.rounded(Color.WHITE, dp(this, 26).toFloat()))
            val tint = if (on) Color.WHITE else PhoneUi.INK55
            (tab.getChildAt(0) as ImageView).imageTintList = android.content.res.ColorStateList.valueOf(tint)
            (tab.getChildAt(1) as TextView).setTextColor(tint)
        }
        if (i != PAGE_CONTACTS) hideKeyboard()
    }

    // ── แป้นกด ───────────────────────────────────────────────

    private fun keypadPage(): View {
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        suggestions = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.BOTTOM
        }
        col.addView(suggestions, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))

        val row = FrameLayout(this)
        display = PhoneUi.text(this, 36f, PhoneUi.INK).apply {
            gravity = Gravity.CENTER
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.START
            setAutoSizeTextTypeUniformWithConfiguration(18, 38, 1, TypedValue.COMPLEX_UNIT_SP)
            setOnLongClickListener { paste(); true }
        }
        row.addView(display, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT).also {
            it.leftMargin = dp(this, 48)
            it.rightMargin = dp(this, 48)
        })
        backspace = FrameLayout(this).apply {
            contentDescription = getString(R.string.dial_backspace)
            background = PhoneUi.ripple(ColorDrawable(Color.TRANSPARENT), 0x267C6CFF, PhoneUi.oval(Color.WHITE))
            addView(PhoneUi.icon(this@DialerActivity, R.drawable.ic_ph_backspace, PhoneUi.INK55, 24))
            isClickable = true
            setOnClickListener {
                if (digits.isNotEmpty()) {
                    digits.deleteCharAt(digits.length - 1)
                    it.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    renderDigits()
                }
            }
            // กดค้าง = ล้างทั้งเบอร์
            setOnLongClickListener {
                digits.setLength(0)
                it.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                renderDigits()
                true
            }
        }
        row.addView(backspace, FrameLayout.LayoutParams(dp(this, 46), dp(this, 46), Gravity.END or Gravity.CENTER_VERTICAL))
        col.addView(row, LinearLayout.LayoutParams(MATCH_PARENT, dp(this, 60)))

        displayName = PhoneUi.text(this, 14f, PhoneUi.VIOLET, bold = true).apply {
            gravity = Gravity.CENTER
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        }
        col.addView(displayName, LinearLayout.LayoutParams(MATCH_PARENT, dp(this, 20)))

        // แป้นใหญ่ที่สุดที่จอนี้รับไหว · จอเตี้ยต้องไม่ดันปุ่มโทรตกขอบ
        val heightDp = resources.displayMetrics.heightPixels / resources.displayMetrics.density
        val keyDp = ((heightDp - 430f) / 4.7f).toInt().coerceIn(54, 76)
        val pad = PhoneUi.keypad(
            this, dark = false, keyDp = keyDp, gapDp = 11,
            onDown = { k, v ->
                feedback.press(v, k)
                digits.append(k)
                renderDigits()
            },
            onUp = { },
            onLong = { k -> longKey(k) },
        )
        col.addView(pad, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).also { it.topMargin = dp(this, 10) })

        callRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        col.addView(callRow, LinearLayout.LayoutParams(MATCH_PARENT, dp(this, 76)).also { it.topMargin = dp(this, 14) })
        return col
    }

    /** 0 ค้าง = + (โทรต่างประเทศ) · * ค้าง = หยุดรอ (,) · # ค้าง = รอกดต่อ (;) */
    private fun longKey(k: Char): Boolean {
        val swap = when (k) {
            '0' -> '+'
            '*' -> ','
            '#' -> ';'
            else -> return false
        }
        if (digits.isNotEmpty() && digits[digits.length - 1] == k) digits.setCharAt(digits.length - 1, swap)
        else digits.append(swap)
        display.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        renderDigits()
        return true
    }

    private fun paste() {
        val clip = getSystemService(ClipboardManager::class.java)?.primaryClip ?: return
        val text = clip.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(this)?.toString() ?: return
        val clean = text.filter { it.isDigit() || it in DIAL_CHARS }
        if (clean.isEmpty()) return
        digits.setLength(0)
        digits.append(clean.take(40))
        renderDigits()
    }

    private fun renderDigits() {
        if (digits.isEmpty()) {
            display.text = getString(R.string.dial_hint)
            display.setTextColor(PhoneUi.INK22)
            backspace.visibility = View.INVISIBLE
        } else {
            val raw = digits.toString()
            display.text = if (raw.all { it.isDigit() || it == '+' }) PhoneUi.formatNumber(raw, iso) else raw
            display.setTextColor(PhoneUi.INK)
            backspace.visibility = View.VISIBLE
        }
        displayName.text = nameFor(digits.toString()).orEmpty()
        renderSuggestions()
    }

    /** ชื่อของเบอร์ที่กดครบแล้ว (เทียบเก้าหลักท้าย ไม่สนว่าบันทึกเป็น +66 หรือ 0) */
    private fun nameFor(number: String): String? {
        val local = PhoneUi.localDigits(number)
        if (local.length < 9) return null
        return byLocal[local.takeLast(9)]?.name
    }

    /**
     * คนที่น่าจะใช่ ระหว่างกดเบอร์ — เบอร์ที่มีเลขชุดนี้ หรือชื่อภาษาอังกฤษที่ตรงกับแป้น (2=ABC…)
     * และเบอร์ที่เพิ่งโทรเข้ามาแต่ยังไม่ได้บันทึก
     */
    private fun renderSuggestions() {
        suggestions.removeAllViews()
        val q = digits.filter { it.isDigit() }.toString()
        if (q.length < 2 || nameFor(digits.toString()) != null) return
        val picked = ArrayList<Triple<String, String, String?>>() // name, number, photo
        val seen = HashSet<String>()
        for (c in contacts) {
            val hit = (q.length >= 3 && c.local.contains(q)) || c.t9.any { it.startsWith(q) }
            if (hit && seen.add(c.local.takeLast(9))) picked.add(Triple(c.name, c.number, c.photo))
            if (picked.size >= 3) break
        }
        if (picked.size < 3 && q.length >= 3) {
            for (r in recents) {
                if (r.hidden) continue
                val local = PhoneUi.localDigits(r.number)
                if (!local.contains(q) || !seen.add(local.takeLast(9))) continue
                picked.add(Triple(r.name ?: PhoneUi.formatNumber(r.number, iso), r.number, r.photo))
                if (picked.size >= 3) break
            }
        }
        for ((name, number, photo) in picked) suggestions.addView(suggestion(name, number, photo))
    }

    private fun suggestion(name: String, number: String, photo: String?): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(this@DialerActivity, 10), dp(this@DialerActivity, 8), dp(this@DialerActivity, 12), dp(this@DialerActivity, 8))
            background = PhoneUi.ripple(
                PhoneUi.rounded(0x99FFFFFF.toInt(), dp(this@DialerActivity, 18).toFloat(), dp(this@DialerActivity, 1), PhoneUi.GLASS_BORDER),
                0x267C6CFF, null
            )
            isClickable = true
            setOnClickListener {
                digits.setLength(0)
                digits.append(number.filter { c -> c.isDigit() || c in DIAL_CHARS })
                renderDigits()
            }
        }
        val avatar = PhoneUi.avatar(this, name, number, cachedPhoto(photo), 36)
        row.addView(avatar, LinearLayout.LayoutParams(dp(this, 36), dp(this, 36)))
        val texts = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        texts.addView(PhoneUi.text(this, 14f, PhoneUi.INK, bold = true).apply {
            text = name
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
        })
        texts.addView(PhoneUi.text(this, 12f, PhoneUi.INK55).apply {
            text = PhoneUi.formatNumber(number, iso)
            setPadding(0, dp(this@DialerActivity, 3), 0, 0)
        })
        row.addView(texts, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).also { it.leftMargin = dp(this, 10) })
        return FrameLayout(this).apply {
            setPadding(0, dp(this@DialerActivity, 3), 0, dp(this@DialerActivity, 3))
            addView(row)
        }
    }

    /** ปุ่มโทร · เครื่องสองซิมมีปุ่มต่อซิม เจ้าของเลือกเบอร์ที่จะโทรออกได้ตั้งแต่ตรงนี้ */
    private fun renderCallRow() {
        callRow.removeAllViews()
        val sims = simAccounts()
        if (sims.size < 2) {
            val call = PhoneUi.bigRound(this, R.drawable.ic_ph_call, intArrayOf(PhoneUi.GREEN, PhoneUi.GREEN_DEEP), 70, 30, getString(R.string.dial_call))
            call.setOnClickListener { onCallTap(null) }
            callRow.addView(call)
            return
        }
        for ((i, s) in sims.withIndex()) {
            val slot = s.second?.slot ?: (i + 1)
            val pill = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
                setPadding(dp(this@DialerActivity, 14), 0, dp(this@DialerActivity, 18), 0)
                background = PhoneUi.ripple(
                    PhoneUi.roundedGradient(intArrayOf(PhoneUi.GREEN, PhoneUi.GREEN_DEEP), dp(this@DialerActivity, 32).toFloat()),
                    0x55FFFFFF, null
                )
                elevation = dp(this@DialerActivity, 5).toFloat()
                isClickable = true
                contentDescription = getString(R.string.dial_call_sim, slot)
                setOnClickListener { onCallTap(s.first) }
                PhoneUi.pressScale(this)
            }
            pill.addView(PhoneUi.icon(this, R.drawable.ic_ph_call, Color.WHITE, 24))
            val texts = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
            texts.addView(PhoneUi.text(this, 15f, Color.WHITE, bold = true).apply {
                text = getString(R.string.dial_sim, slot)
            })
            s.second?.label?.let { label ->
                texts.addView(PhoneUi.text(this, 11f, 0xD9FFFFFF.toInt()).apply {
                    text = label
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    setPadding(0, dp(this@DialerActivity, 2), 0, 0)
                })
            }
            pill.addView(texts, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).also { it.leftMargin = dp(this, 10) })
            callRow.addView(pill, LinearLayout.LayoutParams(0, dp(this, 64), 1f).also {
                if (i > 0) it.leftMargin = dp(this, 12)
            })
        }
    }

    private fun simAccounts(): List<Pair<PhoneAccountHandle, SimInfo.Sim?>> {
        if (checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
            return emptyList()
        }
        return try {
            val tm = getSystemService(TelecomManager::class.java) ?: return emptyList()
            tm.callCapablePhoneAccounts
                .map { it to SimInfo.of(this, it) }
                .sortedBy { it.second?.slot ?: 9 }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun onCallTap(account: PhoneAccountHandle?) {
        if (digits.isEmpty()) {
            // แป้นว่างแล้วกดโทร = เรียกเบอร์ที่โทรออกล่าสุดขึ้นมาให้ (แบบแอปโทรศัพท์ทั่วไป) · ยังไม่โทร
            recents.firstOrNull { it.type == CallLog.Calls.OUTGOING_TYPE && !it.hidden }?.let {
                digits.append(it.number.filter { c -> c.isDigit() || c in DIAL_CHARS })
                renderDigits()
            }
            return
        }
        place(digits.toString(), account)
    }

    /**
     * โทรออกผ่าน Telecom ไม่ใช่ ACTION_CALL
     *
     * `placeCall` เป็นทางของแอปโทรศัพท์ · ยิง ACTION_CALL แทนจะวนกลับมาหา
     * ตัวเองเพราะเราคือแอปที่รับ intent นั้น
     *
     * 🔴 กดซ้ำภายในสองวินาทีครึ่งไม่โทรซ้ำ · นิ้วสั่นหรือจอช้า = สายออกสองสายไปหาคนเดียวกัน
     */
    private fun place(number: String, account: PhoneAccountHandle?) {
        val n = number.trim()
        if (n.isEmpty()) return
        val now = SystemClock.uptimeMillis()
        if (now - lastPlacedAt < 2500) return
        if (checkSelfPermission(Manifest.permission.CALL_PHONE) != PackageManager.PERMISSION_GRANTED) {
            pendingCall = n to account
            requestPermissions(arrayOf(Manifest.permission.CALL_PHONE), REQ_CALL_PHONE)
            return
        }
        val tm = getSystemService(TelecomManager::class.java)
        if (tm == null) {
            toast(R.string.dial_failed)
            return
        }
        val extras = Bundle()
        if (account != null) extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, account)
        try {
            lastPlacedAt = now
            tm.placeCall(Uri.fromParts("tel", n, null), extras)
            if (digits.toString() == number) {
                digits.setLength(0)
                renderDigits()
            }
        } catch (e: SecurityException) {
            // ไม่ได้เป็นแอปหลัก หรือสิทธิ์หาย · บอก ไม่ใช่เงียบ (เดิมเงียบ เจ้าของกดแล้วไม่มีอะไรเกิดขึ้น)
            lastPlacedAt = 0
            toast(R.string.dial_failed)
        }
    }

    // ── ล่าสุด ────────────────────────────────────────────────

    private fun recentsPage(): View {
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val chips = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(this@DialerActivity, 4), 0, dp(this@DialerActivity, 10))
        }
        chipAll = chip(R.string.dial_recents_all) { setMissedOnly(false) }
        chipMissed = chip(R.string.dial_recents_missed) { setMissedOnly(true) }
        chips.addView(chipAll)
        chips.addView(chipMissed, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).also { it.leftMargin = dp(this, 8) })
        col.addView(chips)

        val frame = FrameLayout(this)
        recentsList = list(recentsAdapter)
        frame.addView(recentsList, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        recentsEmpty = emptyState(R.drawable.ic_ph_history)
        frame.addView(recentsEmpty, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        col.addView(frame, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
        paintChips()
        return col
    }

    private fun chip(text: Int, onTap: () -> Unit) = PhoneUi.text(this, 13f, PhoneUi.INK55, bold = true).apply {
        setText(text)
        setPadding(dp(this@DialerActivity, 16), dp(this@DialerActivity, 8), dp(this@DialerActivity, 16), dp(this@DialerActivity, 8))
        isClickable = true
        setOnClickListener { onTap() }
    }

    private fun setMissedOnly(on: Boolean) {
        missedOnly = on
        paintChips()
        renderRecents()
    }

    private fun paintChips() {
        for ((chip, on) in listOf(chipAll to !missedOnly, chipMissed to missedOnly)) {
            chip.background = if (on) PhoneUi.rounded(PhoneUi.INK, dp(this, 18).toFloat())
            else PhoneUi.rounded(0x99FFFFFF.toInt(), dp(this, 18).toFloat(), dp(this, 1), PhoneUi.GLASS_BORDER)
            chip.setTextColor(if (on) Color.WHITE else PhoneUi.INK55)
        }
    }

    private fun renderRecents() {
        val dual = simSlot.size > 1
        val rows = recents.filter { !missedOnly || missed(it.type) }.map { r ->
            val local = PhoneUi.localDigits(r.number)
            val contact = if (local.length >= 9) byLocal[local.takeLast(9)] else null
            val name = r.name ?: contact?.name
            val title = when {
                r.hidden -> getString(R.string.dial_private)
                name != null -> name
                else -> PhoneUi.formatNumber(r.number, iso)
            } + if (r.count > 1) "  (${r.count})" else ""
            val (icon, tint, desc) = typeOf(r.type)
            val parts = ArrayList<String>()
            if (name != null && !r.hidden) parts.add(contact?.label ?: PhoneUi.formatNumber(r.number, iso))
            if (dual) simSlot[r.accountId]?.let { parts.add(getString(R.string.dial_sim, it)) }
            parts.add(whenText(r.at))
            Row(
                title = title,
                titleColor = if (missed(r.type)) PhoneUi.RED_DEEP else PhoneUi.INK,
                subtitle = parts.joinToString(" · "),
                typeIcon = icon,
                typeTint = tint,
                typeDescription = desc,
                number = r.number.takeIf { !r.hidden },
                accountId = r.accountId,
                avatarName = name,
                avatarKey = local.ifEmpty { title },
                photo = r.photo ?: contact?.photo,
                starred = false,
            )
        }
        recentsAdapter.rows = rows
        renderEmpty(
            recentsEmpty, recentsList, rows.isEmpty(), recentsGranted,
            if (missedOnly) R.string.dial_recents_none_missed else R.string.dial_recents_empty,
            R.string.dial_need_calllog, Manifest.permission.READ_CALL_LOG,
        )
    }

    private fun missed(type: Int) = type == CallLog.Calls.MISSED_TYPE

    private fun typeOf(type: Int): Triple<Int, Int, String?> = when (type) {
        CallLog.Calls.OUTGOING_TYPE -> Triple(R.drawable.ic_ph_call_made, PhoneUi.VIOLET, getString(R.string.dial_type_out))
        CallLog.Calls.MISSED_TYPE -> Triple(R.drawable.ic_ph_call_missed, PhoneUi.RED_DEEP, getString(R.string.dial_type_missed))
        CallLog.Calls.REJECTED_TYPE, CallLog.Calls.BLOCKED_TYPE ->
            Triple(R.drawable.ic_ph_block, PhoneUi.INK55, getString(R.string.dial_type_rejected))
        else -> Triple(R.drawable.ic_ph_call_received, PhoneUi.TEAL, getString(R.string.dial_type_in))
    }

    private fun whenText(at: Long): String {
        val time = DateUtils.formatDateTime(this, at, DateUtils.FORMAT_SHOW_TIME)
        return when {
            DateUtils.isToday(at) -> time
            DateUtils.isToday(at + DateUtils.DAY_IN_MILLIS) -> getString(R.string.dial_yesterday, time)
            System.currentTimeMillis() - at < 6 * DateUtils.DAY_IN_MILLIS -> DateUtils.formatDateTime(
                this, at, DateUtils.FORMAT_SHOW_WEEKDAY or DateUtils.FORMAT_ABBREV_WEEKDAY or DateUtils.FORMAT_SHOW_TIME
            )
            else -> DateUtils.formatDateTime(this, at, DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_ABBREV_MONTH)
        }
    }

    // ── รายชื่อ ───────────────────────────────────────────────

    private fun contactsPage(): View {
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(this@DialerActivity, 14), 0, dp(this@DialerActivity, 6), 0)
            background = PhoneUi.rounded(0xCCFFFFFF.toInt(), dp(this@DialerActivity, 24).toFloat(), dp(this@DialerActivity, 1), PhoneUi.GLASS_BORDER)
        }
        box.addView(PhoneUi.icon(this, R.drawable.ic_ph_search, PhoneUi.INK55, 20))
        search = EditText(this).apply {
            setHint(R.string.dial_search_hint)
            setHintTextColor(PhoneUi.INK22)
            setTextColor(PhoneUi.INK)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            background = null
            maxLines = 1
            isSingleLine = true
            imeOptions = EditorInfo.IME_ACTION_SEARCH
            setPadding(dp(this@DialerActivity, 10), 0, 0, 0)
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) = Unit
                override fun afterTextChanged(s: Editable?) = renderContacts()
            })
        }
        box.addView(search, LinearLayout.LayoutParams(0, MATCH_PARENT, 1f))
        val clear = FrameLayout(this).apply {
            contentDescription = getString(R.string.dial_search_clear)
            background = PhoneUi.ripple(ColorDrawable(Color.TRANSPARENT), 0x267C6CFF, PhoneUi.oval(Color.WHITE))
            addView(PhoneUi.icon(this@DialerActivity, R.drawable.ic_ph_close, PhoneUi.INK55, 18))
            isClickable = true
            setOnClickListener { search.setText("") }
        }
        box.addView(clear, LinearLayout.LayoutParams(dp(this, 36), dp(this, 36)))
        col.addView(box, LinearLayout.LayoutParams(MATCH_PARENT, dp(this, 48)).also {
            it.topMargin = dp(this, 4)
            it.bottomMargin = dp(this, 10)
        })

        val frame = FrameLayout(this)
        contactsList = list(contactsAdapter)
        frame.addView(contactsList, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        contactsEmpty = emptyState(R.drawable.ic_ph_person)
        frame.addView(contactsEmpty, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        col.addView(frame, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
        return col
    }

    private fun renderContacts() {
        val q = search.text?.toString()?.trim().orEmpty()
        val qLower = q.lowercase(Locale.ROOT)
        val qDigits = q.filter { it.isDigit() }
        val rows = contacts.asSequence().filter { c ->
            q.isEmpty() || c.name.lowercase(Locale.ROOT).contains(qLower) ||
                (qDigits.length >= 2 && c.local.contains(qDigits))
        }.take(600).map { c ->
            Row(
                title = c.name,
                titleColor = PhoneUi.INK,
                subtitle = listOfNotNull(c.label, PhoneUi.formatNumber(c.number, iso)).joinToString(" · "),
                typeIcon = 0,
                typeTint = 0,
                typeDescription = null,
                number = c.number,
                accountId = null,
                avatarName = c.name,
                avatarKey = c.local,
                photo = c.photo,
                starred = c.starred,
            )
        }.toList()
        contactsAdapter.rows = rows
        renderEmpty(
            contactsEmpty, contactsList, rows.isEmpty(), contactsGranted,
            if (q.isEmpty()) R.string.dial_contacts_empty else R.string.dial_contacts_none,
            R.string.dial_need_contacts, Manifest.permission.READ_CONTACTS,
        )
    }

    // ── รายการ ───────────────────────────────────────────────

    private fun list(adapter: RowAdapter) = ListView(this).apply {
        this.adapter = adapter
        divider = ColorDrawable(Color.TRANSPARENT)
        dividerHeight = dp(this@DialerActivity, 8)
        selector = ColorDrawable(Color.TRANSPARENT)
        clipToPadding = false
        setPadding(0, 0, 0, dp(this@DialerActivity, 8))
        isVerticalScrollBarEnabled = false
        overScrollMode = View.OVER_SCROLL_NEVER
        setOnScrollListener(object : android.widget.AbsListView.OnScrollListener {
            override fun onScrollStateChanged(view: android.widget.AbsListView?, state: Int) {
                if (state != android.widget.AbsListView.OnScrollListener.SCROLL_STATE_IDLE) hideKeyboard()
            }

            override fun onScroll(view: android.widget.AbsListView?, first: Int, visible: Int, total: Int) = Unit
        })
    }

    private fun emptyState(icon: Int): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        gravity = Gravity.CENTER
        setPadding(dp(this@DialerActivity, 28), 0, dp(this@DialerActivity, 28), dp(this@DialerActivity, 40))
        addView(PhoneUi.icon(this@DialerActivity, icon, PhoneUi.INK22, 44))
        addView(PhoneUi.text(this@DialerActivity, 14f, PhoneUi.INK55).apply {
            gravity = Gravity.CENTER
            setLineSpacing(0f, 1.3f)
            setPadding(0, dp(this@DialerActivity, 12), 0, dp(this@DialerActivity, 14))
        })
        addView(PhoneUi.text(this@DialerActivity, 14f, Color.WHITE, bold = true).apply {
            gravity = Gravity.CENTER
            setPadding(dp(this@DialerActivity, 22), dp(this@DialerActivity, 11), dp(this@DialerActivity, 22), dp(this@DialerActivity, 11))
            background = PhoneUi.ripple(
                PhoneUi.roundedGradient(intArrayOf(PhoneUi.PINK, PhoneUi.VIOLET), dp(this@DialerActivity, 22).toFloat()),
                0x55FFFFFF, null
            )
            isClickable = true
        })
        visibility = View.GONE
    }

    /** ว่างเพราะไม่มีข้อมูล = บอกเฉย ๆ · ว่างเพราะไม่มีสิทธิ์ = บอกว่าทำไม พร้อมปุ่มขอ */
    private fun renderEmpty(
        empty: LinearLayout,
        list: ListView,
        isEmpty: Boolean,
        granted: Boolean,
        emptyText: Int,
        needText: Int,
        permission: String,
    ) {
        val show = isEmpty || !granted
        empty.visibility = if (show) View.VISIBLE else View.GONE
        list.visibility = if (show) View.GONE else View.VISIBLE
        if (!show) return
        val message = empty.getChildAt(1) as TextView
        val button = empty.getChildAt(2) as TextView
        if (granted) {
            message.text = if (emptyText == R.string.dial_contacts_none) {
                getString(emptyText, search.text?.toString()?.trim().orEmpty())
            } else getString(emptyText)
            button.visibility = View.GONE
        } else {
            message.setText(needText)
            button.visibility = View.VISIBLE
            val forever = permission in deniedForever
            button.setText(if (forever) R.string.dial_open_settings else R.string.dial_grant)
            button.setOnClickListener {
                if (forever) openAppSettings() else askFor(permission)
            }
        }
    }

    private inner class RowAdapter : BaseAdapter() {
        var rows: List<Row> = emptyList()
            set(value) {
                field = value
                notifyDataSetChanged()
            }

        override fun getCount() = rows.size
        override fun getItem(position: Int): Any = rows[position]
        override fun getItemId(position: Int) = position.toLong()

        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
            val holder = convertView?.tag as? Holder ?: Holder()
            holder.bind(rows[position])
            return holder.view
        }
    }

    private inner class Holder {
        val view = LinearLayout(this@DialerActivity)
        private val avatar = FrameLayout(this@DialerActivity)
        private val title = PhoneUi.text(this@DialerActivity, 15f, PhoneUi.INK, bold = true)
        private val star = PhoneUi.icon(this@DialerActivity, R.drawable.ic_ph_star, 0xFFFFB020.toInt(), 14)
        private val type = PhoneUi.icon(this@DialerActivity, R.drawable.ic_ph_call_received, PhoneUi.TEAL, 14)
        private val sub = PhoneUi.text(this@DialerActivity, 12f, PhoneUi.INK55)
        private val call = FrameLayout(this@DialerActivity)
        private var row: Row? = null
        private var photoKey: String? = null

        init {
            val ctx = this@DialerActivity
            view.orientation = LinearLayout.HORIZONTAL
            view.gravity = Gravity.CENTER_VERTICAL
            view.setPadding(dp(ctx, 10), dp(ctx, 10), dp(ctx, 8), dp(ctx, 10))
            view.background = PhoneUi.ripple(
                PhoneUi.rounded(0x99FFFFFF.toInt(), dp(ctx, 20).toFloat(), dp(ctx, 1), PhoneUi.GLASS_BORDER),
                0x267C6CFF, null
            )
            view.addView(avatar, LinearLayout.LayoutParams(dp(ctx, 44), dp(ctx, 44)))

            val texts = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
            val top = LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }
            title.maxLines = 1
            title.ellipsize = TextUtils.TruncateAt.END
            top.addView(title, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
            top.addView(star, LinearLayout.LayoutParams(dp(ctx, 14), dp(ctx, 14)).also { it.leftMargin = dp(ctx, 6) })
            texts.addView(top)
            val bottom = LinearLayout(ctx).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                setPadding(0, dp(ctx, 4), 0, 0)
            }
            bottom.addView(type, LinearLayout.LayoutParams(dp(ctx, 14), dp(ctx, 14)).also { it.rightMargin = dp(ctx, 5) })
            sub.maxLines = 1
            sub.ellipsize = TextUtils.TruncateAt.END
            bottom.addView(sub, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
            texts.addView(bottom)
            view.addView(texts, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f).also {
                it.leftMargin = dp(ctx, 12)
                it.rightMargin = dp(ctx, 6)
            })

            call.background = PhoneUi.ripple(PhoneUi.oval(0x2200A05A), 0x3300A05A, PhoneUi.oval(Color.WHITE))
            call.addView(PhoneUi.icon(ctx, R.drawable.ic_ph_call, PhoneUi.GREEN_DEEP, 20))
            call.isClickable = true
            view.addView(call, LinearLayout.LayoutParams(dp(ctx, 42), dp(ctx, 42)))

            view.isClickable = true
            view.setOnClickListener { row?.number?.let { openInKeypad(it) } }
            view.setOnLongClickListener { row?.number?.let { copy(it) }; row?.number != null }
            call.setOnClickListener { row?.let { r -> r.number?.let { place(it, handleFor(r.accountId)) } } }
            view.tag = this
        }

        fun bind(r: Row) {
            row = r
            title.text = r.title
            title.setTextColor(r.titleColor)
            star.visibility = if (r.starred) View.VISIBLE else View.GONE
            if (r.typeIcon != 0) {
                type.visibility = View.VISIBLE
                type.setImageResource(r.typeIcon)
                type.imageTintList = android.content.res.ColorStateList.valueOf(r.typeTint)
            } else {
                type.visibility = View.GONE
            }
            sub.text = r.subtitle
            sub.contentDescription = listOfNotNull(r.typeDescription, r.subtitle).joinToString(", ")
            call.visibility = if (r.number != null) View.VISIBLE else View.INVISIBLE
            call.contentDescription = getString(R.string.dial_call_who, r.title)

            photoKey = r.photo
            val cached = r.photo?.let { photos.get(it) }
            PhoneUi.bindAvatar(avatar, r.avatarName, r.avatarKey, cached, 44)
            val uri = r.photo
            if (cached == null && uri != null && uri !in noPhoto) {
                loadPhoto(uri) { bmp -> if (photoKey == uri && bmp != null) PhoneUi.bindAvatar(avatar, r.avatarName, r.avatarKey, bmp, 44) }
            }
        }
    }

    private fun cachedPhoto(uri: String?): Bitmap? = uri?.let { photos.get(it) }

    private fun loadPhoto(uri: String, done: (Bitmap?) -> Unit) {
        val app = applicationContext
        val px = dp(this, 88)
        try {
            io.execute {
                val bmp = PhoneUi.decode(app, uri, px)
                ui.post {
                    if (isDestroyed) return@post
                    if (bmp != null) photos.put(uri, bmp) else noPhoto.add(uri)
                    done(bmp)
                }
            }
        } catch (e: java.util.concurrent.RejectedExecutionException) {
            // จอปิดไปแล้ว
        }
    }

    private fun handleFor(accountId: String?): PhoneAccountHandle? {
        if (accountId == null || simSlot.size < 2) return null
        return simAccounts().firstOrNull { it.first.id == accountId }?.first
    }

    private fun openInKeypad(number: String) {
        digits.setLength(0)
        digits.append(number.filter { it.isDigit() || it in DIAL_CHARS })
        renderDigits()
        showPage(PAGE_KEYPAD)
    }

    private fun copy(number: String) {
        getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText("number", number))
        // Android 13+ แสดงว่าคัดลอกแล้วให้เอง · ซ้ำกันสองอันดูรก
        if (Build.VERSION.SDK_INT < 33) toast(R.string.dial_copied)
    }

    // ── โหลดข้อมูล ───────────────────────────────────────────

    /**
     * อ่านสมุดโทรศัพท์ + ประวัติการโทรบนเธรดแยก แล้วค่อยวาด
     *
     * [loadSeq] กันผลเก่ามาทับผลใหม่ (กลับหน้าจอเร็ว ๆ สองรอบ) และกันวาดลงจอที่ปิดไปแล้ว
     */
    private fun load() {
        val seq = ++loadSeq
        val app = applicationContext
        try {
            io.execute {
                val c = readContacts(app)
                val r = readRecents(app)
                val slots = readSimSlots(app)
                ui.post {
                    if (seq != loadSeq || isDestroyed) return@post
                    contactsGranted = c != null
                    recentsGranted = r != null
                    contacts = c.orEmpty()
                    byLocal = contacts.filter { it.local.length >= 9 }.associateBy { it.local.takeLast(9) }
                    recents = r.orEmpty()
                    simSlot = slots
                    renderRecents()
                    renderContacts()
                    renderDigits()
                }
            }
        } catch (e: java.util.concurrent.RejectedExecutionException) {
            // จอปิดไปแล้ว
        }
    }

    private fun readContacts(context: Context): List<Contact>? {
        if (!CallBridge(context).canReadContacts()) return null
        val out = ArrayList<Contact>()
        val seen = HashSet<String>()
        try {
            context.contentResolver.query(
                Phone.CONTENT_URI,
                arrayOf(
                    Phone.CONTACT_ID, Phone.DISPLAY_NAME_PRIMARY, Phone.NUMBER, Phone.TYPE,
                    Phone.LABEL, Phone.PHOTO_THUMBNAIL_URI, Phone.STARRED,
                ),
                null, null, null
            )?.use { c ->
                while (c.moveToNext() && out.size < MAX_CONTACTS) {
                    val number = c.getString(2)?.trim().orEmpty()
                    if (number.isEmpty()) continue
                    val local = PhoneUi.localDigits(number)
                    if (!seen.add("${c.getLong(0)}:$local")) continue
                    val name = c.getString(1)?.trim().orEmpty().ifEmpty { number }
                    val label = try {
                        Phone.getTypeLabel(context.resources, c.getInt(3), c.getString(4))?.toString()
                    } catch (e: Exception) {
                        null
                    }
                    out.add(Contact(name, number, local, label, c.getString(5), c.getInt(6) == 1, t9Words(name)))
                }
            }
        } catch (e: Exception) {
            // อ่านได้เท่าไหร่ใช้เท่านั้น · จอต้องขึ้น
        }
        // ไทยกับอังกฤษเรียงด้วยกันตามที่คนไทยคาด · คนโปรดขึ้นก่อน
        val collator = Collator.getInstance(Locale.forLanguageTag("th-TH"))
        out.sortWith { a, b ->
            if (a.starred != b.starred) (if (a.starred) -1 else 1) else collator.compare(a.name, b.name)
        }
        return out
    }

    private fun readRecents(context: Context): List<Recent>? {
        if (context.checkSelfPermission(Manifest.permission.READ_CALL_LOG) != PackageManager.PERMISSION_GRANTED) return null
        val out = ArrayList<Recent>()
        // 🔴 ห้ามต่อ LIMIT ท้าย sortOrder · provider รุ่นใหม่โยน IllegalArgumentException (ดู CallBridge.recentCalls)
        try {
            context.contentResolver.query(
                CallLog.Calls.CONTENT_URI,
                arrayOf(
                    CallLog.Calls.NUMBER, CallLog.Calls.CACHED_NAME, CallLog.Calls.TYPE, CallLog.Calls.DATE,
                    CallLog.Calls.PHONE_ACCOUNT_ID, CallLog.Calls.CACHED_PHOTO_URI, CallLog.Calls.NUMBER_PRESENTATION,
                ),
                null, null, CallLog.Calls.DATE + " DESC"
            )?.use { c ->
                var read = 0
                while (c.moveToNext() && read++ < 600 && out.size < 200) {
                    val number = c.getString(0)?.trim().orEmpty()
                    val hidden = number.isEmpty() || c.getInt(6) != CallLog.Calls.PRESENTATION_ALLOWED
                    val type = c.getInt(2)
                    val at = c.getLong(3)
                    // สายติดกันจากเบอร์เดียว ชนิดเดียว วันเดียว = แถวเดียว (3) แบบแอปโทรศัพท์ทั่วไป
                    val prev = out.lastOrNull()
                    if (prev != null && !hidden && !prev.hidden && missed(prev.type) == missed(type) &&
                        PhoneUi.localDigits(prev.number) == PhoneUi.localDigits(number) &&
                        DateUtils.isToday(prev.at) == DateUtils.isToday(at) &&
                        prev.at - at < DateUtils.DAY_IN_MILLIS
                    ) {
                        prev.count++
                        continue
                    }
                    out.add(
                        Recent(
                            number, c.getString(1)?.trim()?.takeIf { it.isNotEmpty() }, type, at, 1,
                            c.getString(4), c.getString(5), hidden
                        )
                    )
                }
            }
        } catch (e: Exception) {
            // อ่านได้เท่าไหร่ใช้เท่านั้น
        }
        return out
    }

    /** id บัญชีโทร → ช่องซิม · ว่างเมื่อมีซิมเดียว (บอกซิมไปก็ไม่มีประโยชน์) */
    private fun readSimSlots(context: Context): Map<String, Int> {
        if (SimInfo.activeCount(context) < 2) return emptyMap()
        return try {
            val tm = context.getSystemService(TelecomManager::class.java) ?: return emptyMap()
            tm.callCapablePhoneAccounts.mapNotNull { h -> SimInfo.of(context, h)?.slot?.let { h.id to it } }.toMap()
        } catch (e: Exception) {
            emptyMap()
        }
    }

    private fun t9Words(name: String): List<String> =
        name.lowercase(Locale.ROOT).split(' ', '-', '.', '_').mapNotNull { word ->
            if (word.isEmpty() || word.any { it !in T9 }) null else word.map { T9.getValue(it) }.joinToString("")
        }

    // ── สาย / ทางออก ─────────────────────────────────────────

    private fun renderBanner() {
        val call = MindInCallService.current
        if (call == null) {
            callBanner.visibility = View.GONE
            return
        }
        val number = call.details.handle?.schemeSpecificPart
        val who = CallBridge(this).nameFor(number) ?: number?.let { PhoneUi.formatNumber(it, iso) }
        callBannerText.text = if (who.isNullOrBlank()) getString(R.string.dial_back_to_call)
        else getString(R.string.dial_back_to_call_who, who)
        callBanner.visibility = View.VISIBLE
    }

    private fun backToCall() {
        val call = MindInCallService.current ?: return renderBanner()
        InCallActivity.show(this, call)
    }

    private fun openMind() {
        try {
            startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) {
            // เปิดไม่ได้ก็อยู่แป้นต่อ
        }
    }

    private fun askFor(permission: String) {
        val all = if (permission == Manifest.permission.READ_CALL_LOG) {
            arrayOf(Manifest.permission.READ_CALL_LOG, Manifest.permission.READ_PHONE_STATE)
        } else arrayOf(permission)
        requestPermissions(all, REQ_READ)
    }

    private fun openAppSettings() {
        try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (e: Exception) {
            // ไม่มีหน้าตั้งค่า (ROM แปลก) ก็อยู่ต่อ
        }
    }

    private fun hideKeyboard() {
        if (!::search.isInitialized) return
        getSystemService(android.view.inputmethod.InputMethodManager::class.java)
            ?.hideSoftInputFromWindow(search.windowToken, 0)
    }

    private fun toast(text: Int) = Toast.makeText(this, text, Toast.LENGTH_LONG).show()

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            REQ_CALL_PHONE -> {
                val pending = pendingCall
                pendingCall = null
                if (pending != null && grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                    place(pending.first, pending.second)
                }
            }
            REQ_READ -> {
                // ปฏิเสธแบบ "ไม่ต้องถามอีก" = ระบบไม่ถามให้อีกแล้ว · ปุ่มต้องพาไปหน้าตั้งค่าแทน ไม่ใช่กดแล้วเงียบ
                for ((i, p) in permissions.withIndex()) {
                    if (grantResults.getOrNull(i) != PackageManager.PERMISSION_GRANTED &&
                        !shouldShowRequestPermissionRationale(p)
                    ) deniedForever.add(p)
                }
                renderCallRow()
                load()
            }
        }
    }

    companion object {
        private const val REQ_CALL_PHONE = 8760
        private const val REQ_READ = 8761
        private const val PAGE_KEYPAD = 0
        private const val PAGE_CONTACTS = 2
        private const val MAX_CONTACTS = 5000

        /** อักขระที่โทรได้นอกจากตัวเลข: + ต่างประเทศ · * # รหัส · , ; หยุดรอกดต่อ */
        private const val DIAL_CHARS = "+*#,;"

        private val T9: Map<Char, Char> = buildMap {
            for ((d, letters) in listOf('2' to "abc", '3' to "def", '4' to "ghi", '5' to "jkl", '6' to "mno", '7' to "pqrs", '8' to "tuv", '9' to "wxyz")) {
                for (l in letters) put(l, d)
            }
        }
    }
}
