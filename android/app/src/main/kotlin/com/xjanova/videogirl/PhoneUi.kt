package com.xjanova.videogirl

import android.animation.ValueAnimator
import android.app.Activity
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.provider.ContactsContract
import android.provider.Settings
import android.telephony.PhoneNumberUtils
import android.telephony.TelephonyManager
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.graphics.drawable.RoundedBitmapDrawableFactory
import java.io.File
import java.util.Locale

/**
 * หน้าตาของจอโทรศัพท์ — สี ปุ่ม พื้นหลัง รูปคน เสียงแป้น ที่ [DialerActivity] กับ [InCallActivity] ใช้ร่วมกัน
 *
 * เนทีฟล้วนด้วยเหตุผลเดียวกับจอสาย: ต้องขึ้นทันทีโดยไม่รอ Flutter engine · สีถอดจาก
 * `lib/theme/tokens.dart` (MindColors / MindGradients) ให้จอโทรศัพท์กับแอปเป็นของชุดเดียวกัน
 * แก้สีที่ tokens.dart ก่อน แล้วค่อยถอดมาที่นี่
 *
 * 🔴 ทุกอย่างในไฟล์นี้ล้มต้องเงียบ ไม่ใช่ทำจอพัง · จอสายพัง = เจ้าของรับสายไม่ได้ทั้งเครื่อง
 */
object PhoneUi {

    // ── สี (tokens.dart) ────────────────────────────────────
    const val INK = 0xFF23204A.toInt()
    const val INK55 = 0x8C23204A.toInt()
    const val INK22 = 0x3823204A.toInt()
    const val INK10 = 0x1A23204A.toInt()
    const val VIOLET = 0xFF7C6CFF.toInt()
    const val PINK = 0xFFFF6FAE.toInt()
    const val TEAL = 0xFF00C2A8.toInt()
    const val GREEN = 0xFF2BD67B.toInt()
    const val GREEN_DEEP = 0xFF00A05A.toInt()
    const val RED = 0xFFFF5C7A.toInt()
    const val RED_DEEP = 0xFFD93A5B.toInt()
    const val GLASS = 0xD9FFFFFF.toInt()
    const val GLASS_BORDER = 0xE6FFFFFF.toInt()

    /** จอสายเป็นโทนกลางคืน · ตัวหนังสือขาวอ่านง่ายตอนยกขึ้นดูกลางสาย และไม่แสบตาตอนกริ่งดังตอนดึก */
    const val NIGHT_GLASS = 0x1FFFFFFF
    const val NIGHT_GLASS_ON = 0xF2FFFFFF.toInt()
    const val WHITE70 = 0xB3FFFFFF.toInt()
    const val WHITE55 = 0x8CFFFFFF.toInt()

    /** สีไล่ของวงรูปคนที่ไม่มีรูป · เลือกจากชื่อ คนเดิมได้สีเดิมทุกครั้ง */
    private val AVATAR = arrayOf(
        intArrayOf(PINK, VIOLET),
        intArrayOf(TEAL, VIOLET),
        intArrayOf(0xFFFFA26B.toInt(), PINK),
        intArrayOf(0xFF5AC8FA.toInt(), VIOLET),
        intArrayOf(0xFF7FEDD6.toInt(), 0xFF00A894.toInt()),
    )

    fun dp(context: Context, v: Float): Int = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v, context.resources.displayMetrics
    ).toInt()

    fun dp(context: Context, v: Int): Int = dp(context, v.toFloat())

    // ── พื้นหลัง ─────────────────────────────────────────────

    /** ก้อนแสงหนึ่งก้อน · ตำแหน่งและรัศมีเป็นสัดส่วนของจอ */
    class Orb(val x: Float, val y: Float, val radius: Float, val color: Int)

    /**
     * พื้นไล่สีกับก้อนแสงฟุ้ง แบบ LiquidBackground ฝั่ง Flutter แต่**นิ่ง**
     *
     * จอสายเปิดค้างได้เป็นชั่วโมง · ก้อนแสงที่ขยับ = วาดใหม่ 60 ครั้งต่อวินาทีตลอดสาย กินแบตเปล่า ๆ
     */
    class Backdrop(private val colors: IntArray, private val orbs: List<Orb>) : Drawable() {
        private val base = Paint(Paint.ANTI_ALIAS_FLAG)
        private val glow = Paint(Paint.ANTI_ALIAS_FLAG)

        override fun onBoundsChange(bounds: Rect) {
            super.onBoundsChange(bounds)
            base.shader = LinearGradient(
                bounds.left.toFloat(), bounds.top.toFloat(),
                bounds.right.toFloat() * .35f, bounds.bottom.toFloat(),
                colors, null, Shader.TileMode.CLAMP
            )
        }

        override fun draw(canvas: Canvas) {
            val b = bounds
            // ขนาดศูนย์ = รัศมีศูนย์ · RadialGradient โยน IllegalArgumentException ทั้งจอพัง
            if (b.isEmpty) return
            canvas.drawRect(b, base)
            val size = maxOf(b.width(), b.height()).toFloat()
            for (o in orbs) {
                val cx = b.left + b.width() * o.x
                val cy = b.top + b.height() * o.y
                val r = size * o.radius
                glow.shader = RadialGradient(
                    cx, cy, r, o.color, o.color and 0x00FFFFFF, Shader.TileMode.CLAMP
                )
                canvas.drawCircle(cx, cy, r, glow)
            }
        }

        override fun setAlpha(alpha: Int) = Unit
        override fun setColorFilter(colorFilter: ColorFilter?) = Unit

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.OPAQUE
    }

    /** แป้นโทร — พาสเทลเดียวกับหน้าหลักของแอป (MindGradients ตัวแรก) */
    fun lightBackdrop() = Backdrop(
        intArrayOf(0xFFFFF2E4.toInt(), 0xFFF1E9FF.toInt(), 0xFFE2F8FF.toInt()),
        listOf(
            Orb(.12f, .10f, .42f, 0x8CFFB0D8.toInt()),
            Orb(.98f, .38f, .40f, 0x737FEDD6),
            Orb(.18f, .92f, .48f, 0x80B0A8FF.toInt()),
        )
    )

    /** จอสาย — ม่วงกลางคืน แสงม่วง ชมพู มิ้นต์จากชุดสีเดียวกัน */
    fun nightBackdrop() = Backdrop(
        intArrayOf(0xFF130F33.toInt(), 0xFF231952.toInt(), 0xFF32174A.toInt()),
        listOf(
            Orb(.88f, .08f, .55f, 0x707C6CFF),
            Orb(.05f, .50f, .45f, 0x45FF6FAE),
            Orb(.92f, .96f, .45f, 0x3800C2A8),
        )
    )

    // ── รูปทรง ───────────────────────────────────────────────

    fun oval(color: Int, stroke: Int = 0, strokeColor: Int = 0) = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(color)
        if (stroke > 0) setStroke(stroke, strokeColor)
    }

    fun ovalGradient(colors: IntArray) = GradientDrawable(
        GradientDrawable.Orientation.TL_BR, colors
    ).apply { shape = GradientDrawable.OVAL }

    fun rounded(color: Int, radius: Float, stroke: Int = 0, strokeColor: Int = 0) =
        GradientDrawable().apply {
            cornerRadius = radius
            setColor(color)
            if (stroke > 0) setStroke(stroke, strokeColor)
        }

    fun roundedGradient(colors: IntArray, radius: Float) = GradientDrawable(
        GradientDrawable.Orientation.TL_BR, colors
    ).apply { cornerRadius = radius }

    /** ระลอกน้ำตอนแตะ · ขอบเขตตามรูปทรงของปุ่ม ไม่ล้นออกเป็นสี่เหลี่ยม */
    fun ripple(content: Drawable, rippleColor: Int, mask: Drawable? = null) =
        RippleDrawable(ColorStateList.valueOf(rippleColor), content, mask ?: content)

    fun icon(context: Context, res: Int, tint: Int, sizeDp: Int) = ImageView(context).apply {
        setImageResource(res)
        imageTintList = ColorStateList.valueOf(tint)
        scaleType = ImageView.ScaleType.FIT_CENTER
        layoutParams = FrameLayout.LayoutParams(dp(context, sizeDp), dp(context, sizeDp), Gravity.CENTER)
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    fun text(context: Context, sp: Float, color: Int, bold: Boolean = false) = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sp)
        setTextColor(color)
        if (bold) typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        includeFontPadding = false
    }

    /** หดนิดหนึ่งตอนกด ปล่อยแล้วเด้งกลับ · ให้รู้สึกว่าปุ่มรับนิ้วจริง */
    fun pressScale(view: View) {
        view.setOnTouchListener { v, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> v.animate().scaleX(.92f).scaleY(.92f).setDuration(70).start()
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                    v.animate().scaleX(1f).scaleY(1f).setDuration(140)
                        .setInterpolator(DecelerateInterpolator()).start()
            }
            false
        }
    }

    // ── ขอบจอ ───────────────────────────────────────────────

    /**
     * วาดใต้แถบสถานะ/แถบนำทาง แล้วเว้นขอบให้เนื้อหาเอง
     *
     * 🔴 targetSdk 35+ บน Android 15 บังคับวาดใต้แถบระบบอยู่แล้ว · ไม่เว้นเอง = ชื่อคนโทรไปซ่อน
     * ใต้นาฬิกา และปุ่มวางสายไปอยู่ใต้แถบนำทาง · คีย์บอร์ดก็ไม่ดันจอขึ้นให้อีก ต้องนับ IME เอง
     */
    fun edgeToEdge(activity: Activity, root: View, lightBars: Boolean) {
        val window = activity.window
        // 🔴 ทั้งสองจอเรียกที่นี่ก่อน setContentView · ตอนนั้นยังไม่มี DecorView แล้ว
        // window.insetsController ยิง NPE ใน PhoneWindow (`?.` กันไม่ได้ พังข้างใน) ·
        // 0.1.53 เปิดแป้นโทรแล้วแอปเด้งออกทุกครั้ง · decorView สร้างมันขึ้นมาก่อน
        // ค่าที่ตั้งตอนยังไม่ติดหน้าต่าง ระบบเก็บไว้ใช้ตอนติดเอง
        val decor = window.decorView
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false)
            val appearance = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            window.insetsController?.setSystemBarsAppearance(if (lightBars) appearance else 0, appearance)
        } else {
            @Suppress("DEPRECATION")
            decor.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                (if (lightBars) View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR else 0)
        }
        @Suppress("DEPRECATION")
        window.statusBarColor = Color.TRANSPARENT
        @Suppress("DEPRECATION")
        window.navigationBarColor = Color.TRANSPARENT

        val base = intArrayOf(root.paddingLeft, root.paddingTop, root.paddingRight, root.paddingBottom)
        root.setOnApplyWindowInsetsListener { v, insets ->
            val top: Int
            val bottom: Int
            if (Build.VERSION.SDK_INT >= 30) {
                val bars = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout())
                val ime = insets.getInsets(WindowInsets.Type.ime())
                top = bars.top
                bottom = maxOf(bars.bottom, ime.bottom)
            } else {
                @Suppress("DEPRECATION")
                top = insets.systemWindowInsetTop
                @Suppress("DEPRECATION")
                bottom = insets.systemWindowInsetBottom
            }
            v.setPadding(base[0], base[1] + top, base[2], base[3] + bottom)
            insets
        }
        root.requestApplyInsets()
    }

    // ── คน ──────────────────────────────────────────────────

    /**
     * ตัวอักษรแรกที่ใช้แทนรูปคน
     *
     * ชื่อไทยที่ขึ้นต้นด้วยสระหน้า (เ แ โ ใ ไ) ข้ามไปเอาพยัญชนะ · "เอก" ต้องเป็น "อ" ไม่ใช่ "เ"
     */
    fun initialOf(name: String?): String? {
        val n = name?.trim().orEmpty()
        if (n.isEmpty() || n.none { it.isLetter() }) return null
        val c = n.firstOrNull { it.isLetter() && it !in 'เ'..'ไ' } ?: return null
        return c.uppercaseChar().toString()
    }

    fun paletteFor(key: String?): IntArray =
        AVATAR[((key?.hashCode() ?: 0) and 0x7FFFFFFF) % AVATAR.size]

    /**
     * วงรูปคน: รูปจากสมุดโทรศัพท์ → ตัวอักษรแรกบนสีไล่ → ไอคอนคน (เบอร์ที่ไม่รู้จัก)
     */
    fun avatar(context: Context, name: String?, key: String?, photo: Bitmap?, sizeDp: Int): FrameLayout {
        val box = FrameLayout(context)
        bindAvatar(box, name, key, photo, sizeDp)
        return box
    }

    fun bindAvatar(box: FrameLayout, name: String?, key: String?, photo: Bitmap?, sizeDp: Int) {
        val context = box.context
        box.removeAllViews()
        if (photo != null) {
            box.background = null
            box.addView(ImageView(context).apply {
                setImageDrawable(RoundedBitmapDrawableFactory.create(context.resources, photo).apply { isCircular = true })
                scaleType = ImageView.ScaleType.CENTER_CROP
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
            return
        }
        box.background = ovalGradient(paletteFor(key ?: name))
        val initial = initialOf(name)
        if (initial != null) {
            box.addView(text(context, sizeDp * .40f, Color.WHITE, bold = true).apply {
                text = initial
                gravity = Gravity.CENTER
            }, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
        } else {
            box.addView(icon(context, R.drawable.ic_ph_person, Color.WHITE, (sizeDp * .52f).toInt()))
        }
    }

    /** รูปของเบอร์นี้ในสมุดโทรศัพท์ · null ถ้าไม่มี/ไม่มีสิทธิ์/อ่านพัง */
    fun contactPhoto(context: Context, number: String?, maxPx: Int): Bitmap? {
        if (number.isNullOrBlank()) return null
        if (!CallBridge(context).canReadContacts()) return null
        return try {
            val uri = Uri.withAppendedPath(ContactsContract.PhoneLookup.CONTENT_FILTER_URI, Uri.encode(number))
            val photo = context.contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.PHOTO_URI, ContactsContract.PhoneLookup.PHOTO_THUMBNAIL_URI),
                null, null, null
            )?.use { c -> if (c.moveToFirst()) c.getString(0) ?: c.getString(1) else null }
            decode(context, photo, maxPx)
        } catch (e: Exception) {
            null
        }
    }

    /** อ่านรูปจาก content:// แบบย่อขนาดตอนถอด · รูปเต็มจากกล้องกินแรมหลายสิบ MB */
    fun decode(context: Context, uri: String?, maxPx: Int): Bitmap? {
        if (uri.isNullOrBlank()) return null
        return try {
            val u = Uri.parse(uri)
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(u)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= maxPx && bounds.outHeight / (sample * 2) >= maxPx) sample *= 2
            val opts = BitmapFactory.Options().apply { inSampleSize = sample }
            context.contentResolver.openInputStream(u)?.use { BitmapFactory.decodeStream(it, null, opts) }
        } catch (e: Exception) {
            null
        }
    }

    /** หน้าเธอที่แอปแคชไว้ (mind_face.png) · ไม่มีก็ไม่เป็นไร */
    fun mindFace(context: Context, maxPx: Int): Bitmap? = try {
        val f = File(context.filesDir, "mind_face.png")
        if (!f.exists()) null else {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(f.path, bounds)
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= maxPx) sample *= 2
            BitmapFactory.decodeFile(f.path, BitmapFactory.Options().apply { inSampleSize = sample })
        }
    } catch (e: Exception) {
        null
    }

    // ── เบอร์ ───────────────────────────────────────────────

    fun countryIso(context: Context): String = try {
        val tm = context.getSystemService(TelephonyManager::class.java)
        (tm?.networkCountryIso?.takeIf { it.isNotBlank() } ?: tm?.simCountryIso?.takeIf { it.isNotBlank() } ?: "th")
            .uppercase(Locale.ROOT)
    } catch (e: Exception) {
        "TH"
    }

    /** 0812345678 → 081 234 5678 ตามรูปแบบของประเทศ · จัดไม่ได้ก็คืนตามที่พิมพ์ */
    fun formatNumber(raw: String?, iso: String): String {
        val n = raw?.trim().orEmpty()
        if (n.isEmpty()) return n
        return try {
            PhoneNumberUtils.formatNumber(n, iso) ?: n
        } catch (e: Exception) {
            n
        }
    }

    /** ตัวเลขล้วน และ +66 เป็น 0 · ไว้เทียบว่าเป็นเบอร์เดียวกันไหม */
    fun localDigits(raw: String?): String {
        val d = raw.orEmpty().filter { it.isDigit() }
        return if (raw.orEmpty().trim().startsWith("+66") && d.length > 2) "0" + d.drop(2) else d
    }

    // ── เสียงและแรงสั่นของแป้น ──────────────────────────────

    /**
     * เสียงแป้นตอนกดเบอร์ + สั่นเบา ๆ — ตามที่เจ้าของตั้งในเครื่องเสมอ
     *
     * เสียงแป้นปิดใน "เสียงแป้นกด" ของระบบ หรือเครื่องอยู่โหมดเงียบ/สั่น = ไม่มีเสียง ·
     * แรงสั่นใช้ haptic ของระบบ ซึ่งปิดตามที่ตั้งไว้ให้เอง
     */
    class KeyFeedback(private val context: Context) {
        private var tones: ToneGenerator? = null

        fun start() {
            if (tones != null) return
            tones = try {
                ToneGenerator(AudioManager.STREAM_DTMF, 70)
            } catch (e: RuntimeException) {
                null
            }
        }

        fun stop() {
            tones?.release()
            tones = null
        }

        fun press(view: View, key: Char, sound: Boolean = true) {
            view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
            if (!sound || !soundWanted()) return
            val tone = when (key) {
                in '0'..'9' -> ToneGenerator.TONE_DTMF_0 + (key - '0')
                '*' -> ToneGenerator.TONE_DTMF_S
                '#' -> ToneGenerator.TONE_DTMF_P
                else -> return
            }
            tones?.startTone(tone, 120)
        }

        private fun soundWanted(): Boolean = try {
            val audio = context.getSystemService(AudioManager::class.java)
            Settings.System.getInt(context.contentResolver, Settings.System.DTMF_TONE_WHEN_DIALING, 1) == 1 &&
                audio?.ringerMode == AudioManager.RINGER_MODE_NORMAL
        } catch (e: Exception) {
            false
        }
    }

    // ── แป้นตัวเลข ──────────────────────────────────────────

    private val LETTERS = mapOf(
        '1' to "", '2' to "ABC", '3' to "DEF", '4' to "GHI", '5' to "JKL",
        '6' to "MNO", '7' to "PQRS", '8' to "TUV", '9' to "WXYZ", '0' to "+", '*' to "", '#' to "",
    )

    /**
     * แป้น 4×3 ใช้ทั้งแป้นโทร (สว่าง) และแป้นกดเลขระหว่างสาย (มืด)
     *
     * [onDown]/[onUp] แยกกันเพราะเสียงโทนในสายต้องดังตลอดที่นิ้วกดค้าง แล้วหยุดตอนปล่อย ·
     * [onLong] คืน true = ใช้การกดค้างไปแล้ว (เช่น 0 ค้าง = +)
     */
    fun keypad(
        context: Context,
        dark: Boolean,
        keyDp: Int,
        gapDp: Int,
        onDown: (Char, View) -> Unit,
        onUp: (Char) -> Unit,
        onLong: ((Char) -> Boolean)? = null,
    ): LinearLayout {
        val grid = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
        }
        val rows = listOf("123", "456", "789", "*0#")
        for ((r, row) in rows.withIndex()) {
            val line = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
            }
            for ((i, k) in row.withIndex()) {
                val key = key(context, k, dark, keyDp)
                key.setOnTouchListener { v, e ->
                    when (e.actionMasked) {
                        MotionEvent.ACTION_DOWN -> {
                            v.isPressed = true
                            v.animate().scaleX(.93f).scaleY(.93f).setDuration(60).start()
                            onDown(k, v)
                        }
                        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                            v.isPressed = false
                            v.animate().scaleX(1f).scaleY(1f).setDuration(120).start()
                            onUp(k)
                        }
                    }
                    false
                }
                key.setOnClickListener { }
                if (onLong != null) key.setOnLongClickListener { onLong(k) }
                line.addView(key, LinearLayout.LayoutParams(dp(context, keyDp), dp(context, keyDp)).also {
                    if (i > 0) it.leftMargin = dp(context, gapDp * 2)
                })
            }
            grid.addView(line, LinearLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT).also {
                if (r > 0) it.topMargin = dp(context, gapDp)
            })
        }
        return grid
    }

    private fun key(context: Context, k: Char, dark: Boolean, keyDp: Int): FrameLayout {
        val face = if (dark) oval(NIGHT_GLASS, dp(context, 1), 0x24FFFFFF)
        else oval(GLASS, dp(context, 1), GLASS_BORDER)
        val box = FrameLayout(context).apply {
            background = ripple(face, if (dark) 0x40FFFFFF else 0x337C6CFF, oval(Color.WHITE))
            contentDescription = k.toString()
            isClickable = true
            isFocusable = true
        }
        val col = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        col.addView(text(context, keyDp * .40f, if (dark) Color.WHITE else INK).apply {
            text = k.toString()
            gravity = Gravity.CENTER
            typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
        })
        val letters = LETTERS[k].orEmpty()
        col.addView(text(context, 9.5f, if (dark) WHITE55 else INK55, bold = true).apply {
            text = letters.ifEmpty { " " }
            letterSpacing = .18f
            gravity = Gravity.CENTER
            setPadding(0, dp(context, 2), 0, 0)
        })
        box.addView(col, FrameLayout.LayoutParams(WRAP_CONTENT, WRAP_CONTENT, Gravity.CENTER))
        return box
    }

    // ── ปุ่มควบคุมในสาย ──────────────────────────────────────

    /**
     * ปุ่มกลม + ป้ายใต้ปุ่ม (ปิดไมค์ ลำโพง พักสาย…) · เปิดอยู่ = วงขาวทึบ ไอคอนเข้ม แบบที่คนคุ้นจากโทรศัพท์ทุกยี่ห้อ
     */
    class ControlButton(context: Context, iconRes: Int, label: String) : LinearLayout(context) {
        private val circle = FrameLayout(context)
        private val glyph = icon(context, iconRes, Color.WHITE, 26)
        private val caption = text(context, 12f, WHITE70).apply {
            text = label
            gravity = Gravity.CENTER
            maxLines = 1
        }
        var on = false
            private set

        init {
            orientation = VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            isClickable = true
            isFocusable = true
            circle.addView(glyph)
            addView(circle, LayoutParams(dp(context, 64), dp(context, 64)))
            addView(caption, LayoutParams(WRAP_CONTENT, WRAP_CONTENT).also { it.topMargin = dp(context, 8) })
            contentDescription = label
            pressScale(this)
            paint()
        }

        fun set(on: Boolean, enabled: Boolean = true) {
            if (this.on == on && isEnabled == enabled) return
            this.on = on
            isEnabled = enabled
            alpha = if (enabled) 1f else .35f
            paint()
        }

        fun relabel(iconRes: Int, label: String) {
            glyph.setImageResource(iconRes)
            caption.text = label
            contentDescription = label
        }

        private fun paint() {
            val face = if (on) oval(NIGHT_GLASS_ON) else oval(NIGHT_GLASS, dp(context, 1), 0x24FFFFFF)
            circle.background = ripple(face, if (on) 0x337C6CFF else 0x40FFFFFF, oval(Color.WHITE))
            glyph.imageTintList = ColorStateList.valueOf(if (on) INK else Color.WHITE)
            isSelected = on
        }
    }

    /** ปุ่มกลมใหญ่สีเต็ม (รับ / วาง / โทร) */
    fun bigRound(context: Context, iconRes: Int, colors: IntArray, sizeDp: Int, iconDp: Int, description: String): FrameLayout =
        FrameLayout(context).apply {
            background = ripple(ovalGradient(colors), 0x55FFFFFF, oval(Color.WHITE))
            elevation = dp(context, 6).toFloat()
            addView(icon(context, iconRes, Color.WHITE, iconDp))
            contentDescription = description
            isClickable = true
            isFocusable = true
            pressScale(this)
            layoutParams = LinearLayout.LayoutParams(dp(context, sizeDp), dp(context, sizeDp))
        }

    /**
     * วงแหวนกระเพื่อมรอบรูปคนตอนกริ่งดัง · หยุดเมื่อไม่ได้ดัง (ไม่วาดค้างทั้งสาย)
     */
    class PulseView(context: Context) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = dp(context, 2).toFloat()
            color = Color.WHITE
        }
        private var t = 0f
        private var anim: ValueAnimator? = null
        var innerRadiusPx = 0f

        fun start() {
            if (anim != null) return
            anim = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 1800
                repeatCount = ValueAnimator.INFINITE
                addUpdateListener {
                    t = it.animatedValue as Float
                    invalidate()
                }
                start()
            }
        }

        fun stop() {
            anim?.cancel()
            anim = null
            t = 0f
            invalidate()
        }

        override fun onDetachedFromWindow() {
            stop()
            super.onDetachedFromWindow()
        }

        override fun onDraw(canvas: Canvas) {
            if (anim == null) return
            val cx = width / 2f
            val cy = height / 2f
            val span = minOf(cx, cy) - innerRadiusPx
            for (k in 0..1) {
                val p = (t + k * .5f) % 1f
                paint.alpha = ((1f - p) * 150).toInt()
                canvas.drawCircle(cx, cy, innerRadiusPx + span * p, paint)
            }
        }
    }
}
