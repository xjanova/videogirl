package com.xjanova.videogirl.sos

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SosCoreTest {

    private val texts = SosTexts(
        alertPrompt = "เป็นอะไรไหมคะ ได้ยินไหมคะ",
        sms = "SOS\n{loc}",
        smsHealth = "เลือด O",
        smsLow = "อาจเกิดเหตุ\n{loc}",
        smsCancel = "ยกเลิกแล้ว",
        smsDrillPrefix = "[ทดสอบ]",
        scriptOpen = mapOf("CRASH" to "รถชน", "OTHER" to "เหตุฉุกเฉิน"),
        scriptWho = "ชื่อสมชาย",
        scriptWhere = "ละติจูด {lat} ลองจิจูด {lng} {age}",
        scriptNoFix = "ไม่มีพิกัด",
        scriptClose = "พูดซ้ำ",
        ageNow = "ล่าสุด",
        ageOld = "เก่า {min} นาที",
        noFix = "ไม่มีพิกัด",
    )

    private fun plan(
        contacts: List<SosContact> = listOf(SosContact("แม่", "0811111111", true), SosContact("พี่", "0822222222", false)),
        test: String = "0899999999",
    ) = SosPlan(
        armed = true, autoCall = false, countdownSec = 30, manualCountdownSec = 5,
        routes = mapOf("CRASH" to listOf("1669", "191"), "FIRE" to listOf("199")),
        abroad = listOf("112"), contacts = contacts, testNumber = test, sensitivity = 1, th = texts, en = texts,
    )

    private val noEcc: (String) -> Boolean = { false }

    @Test
    fun `test mode simulates every way in, even with automatic calling allowed`() {
        val p = plan()
        assertEquals(true, p.testMode)
        for (how in SosTrigger.values()) assertTrue(SosRouter.rehearses(p, how, autoCallAllowed = true))
    }

    @Test
    fun `with test mode off only the impact gate still rehearses`() {
        val p = plan().copy(testMode = false)
        assertTrue(SosRouter.rehearses(p, SosTrigger.IMPACT, autoCallAllowed = false))
        assertFalse(SosRouter.rehearses(p, SosTrigger.IMPACT, autoCallAllowed = true))
        assertFalse(SosRouter.rehearses(p, SosTrigger.BUTTON, autoCallAllowed = false))
        assertFalse(SosRouter.rehearses(p, SosTrigger.VOICE, autoCallAllowed = false))
    }

    @Test
    fun `a silent alert warns people not to call back and says so to officers`() {
        val t = texts.copy(
            smsSilent = "silent {loc}",
            scriptCloseSilent = "cannot speak",
            scriptOpen = texts.scriptOpen + ("SILENT" to "quiet open"),
        )
        val fix = SosFix(13.7, 100.5, 10.0, 1_000L)
        assertTrue(SosText.sms(t, fix, fix.atMs, withHealth = false, low = false, drill = false, silent = true).startsWith("silent "))
        val script = SosText.script(t, SosKind.OTHER, fix, fix.atMs, "จุด", silent = true)
        assertTrue(script.startsWith("quiet open"))
        assertTrue(script.endsWith("cannot speak"))
        assertFalse(SosText.script(t, SosKind.OTHER, fix, fix.atMs, "จุด").contains("cannot speak"))
    }

    @Test
    fun `negated words never count as a cry for help`() {
        for (s in listOf("ไม่เจ็บ", "ไม่ต้องเรียกหมอ", "ไม่ต้องเรียกรถพยาบาล", "ไม่ต้องแจ้งเหตุ", "no help needed", "not hurt", "don't need help")) {
            assertEquals(s, SosReply.Answer.FINE, SosReply.classify(s))
        }
        assertEquals(SosReply.Answer.UNKNOWN, SosReply.classify("ไม่ได้ปวดมาก"))
        assertEquals(SosReply.Answer.HELP, SosReply.classify("ไม่เจ็บ แต่เลือดออก"))
        assertEquals(SosReply.Answer.HELP, SosReply.classify("เจ็บ"))
        assertEquals(SosReply.Answer.HELP, SosReply.classify("I need help"))
        assertEquals(SosReply.Answer.HELP, SosReply.classify("ไม่ไหวแล้ว"))
        assertEquals(SosReply.Answer.HELP, SosReply.classify("หายใจไม่ออก"))
    }

    @Test
    fun `real run texts everyone first then officials then family`() {
        val steps = SosRouter.route(plan(), SosKind.CRASH, SosConfidence.HIGH, drill = false, abroad = false, isEcc = noEcc)
        assertEquals(
            listOf("sms 0811111111", "sms 0822222222", "call 1669", "call 191", "call 0811111111", "call 0822222222"),
            steps.map { describe(it) },
        )
    }

    @Test
    fun `drill never reaches an official or a real contact`() {
        val steps = SosRouter.route(plan(), SosKind.CRASH, SosConfidence.HIGH, drill = true, abroad = false, isEcc = noEcc)
        assertEquals(listOf("sms 0899999999", "call 0899999999"), steps.map { describe(it) })
        assertTrue(steps.none { it is SosStep.Call && it.official })
    }

    @Test
    fun `drill refuses emergency short codes and premium numbers as the test number`() {
        for (n in listOf("1669", "191", "112", "+66191", "19001234", "", "abc")) {
            val steps = SosRouter.route(plan(test = n), SosKind.CRASH, SosConfidence.HIGH, true, false, noEcc)
            assertTrue("test number $n must send nothing", steps.isEmpty())
        }
    }

    @Test
    fun `drill refuses a number the sim lists as emergency`() {
        val steps = SosRouter.route(plan(), SosKind.CRASH, SosConfidence.HIGH, true, false) { it == "0899999999" }
        assertTrue(steps.isEmpty())
    }

    @Test
    fun `low confidence tells family but never officials`() {
        val steps = SosRouter.route(plan(), SosKind.CRASH, SosConfidence.LOW, false, false, noEcc)
        assertTrue(steps.none { it is SosStep.Call && it.official })
        assertTrue(steps.any { it is SosStep.Sms })
    }

    @Test
    fun `abroad uses the abroad number not the Thai one`() {
        val steps = SosRouter.route(plan(contacts = emptyList()), SosKind.CRASH, SosConfidence.HIGH, false, true, noEcc)
        assertEquals(listOf("call 112"), steps.map { describe(it) })
    }

    @Test
    fun `premium or short contact numbers are dropped`() {
        val p = plan(contacts = listOf(SosContact("x", "19001234567", true), SosContact("y", "1669", true)))
        val steps = SosRouter.route(p, SosKind.FIRE, SosConfidence.HIGH, false, false, noEcc)
        assertEquals(listOf("call 199"), steps.map { describe(it) })
    }

    private fun describe(s: SosStep) = when (s) {
        is SosStep.Sms -> "sms ${s.to}"
        is SosStep.Call -> "call ${s.to}"
    }

    private val fix = SosFix(13.756331, 100.501765, 12.4, 1_700_000_000_000)

    @Test
    fun `location block has every form and how old it is`() {
        val now = fix.atMs + 7 * 60_000
        val s = SosText.locationBlock(fix, now, texts, ZoneOffset.ofHours(7))
        assertTrue(s, s.contains("https://maps.google.com/?q=13.756331,100.501765"))
        assertTrue(s, s.contains("13.756331, 100.501765"))
        assertTrue(s, s.contains("±12m"))
        assertTrue(s, s.contains("เก่า 7 นาที"))
        assertTrue(s, s.contains("Plus 7P52"))
    }

    @Test
    fun `no fix says so instead of a blank`() {
        assertEquals("ไม่มีพิกัด", SosText.locationBlock(null, 0, texts))
    }

    @Test
    fun `numbers stay ascii in a thai or german locale`() {
        val saved = java.util.Locale.getDefault()
        try {
            for (tag in listOf("th-TH-u-nu-thai", "de-DE", "ar-EG")) {
                java.util.Locale.setDefault(java.util.Locale.forLanguageTag(tag))
                assertEquals("https://maps.google.com/?q=13.756331,100.501765", SosText.mapLink(fix))
            }
        } finally {
            java.util.Locale.setDefault(saved)
        }
    }

    @Test
    fun `drill sms is marked and health goes only when allowed`() {
        val yes = SosText.sms(texts, fix, fix.atMs, withHealth = true, low = false, drill = true)
        val no = SosText.sms(texts, fix, fix.atMs, withHealth = false, low = false, drill = false)
        assertTrue(yes, yes.startsWith("[ทดสอบ]"))
        assertTrue(yes, yes.contains("เลือด O"))
        assertFalse(no, no.contains("เลือด O"))
        assertFalse(no, no.contains("[ทดสอบ]"))
    }

    @Test
    fun `script reads digits one by one`() {
        val s = SosText.script(texts, SosKind.CRASH, fix, fix.atMs, "จุด")
        assertTrue(s, s.startsWith("รถชน ละติจูด"))
        assertTrue(s, s.indexOf("ชื่อสมชาย") > s.indexOf("ลองจิจูด"))
        assertTrue(s, s.contains("1 3 จุด 7 5 6 3 3"))
        assertTrue(s, s.endsWith("พูดซ้ำ"))
    }

    @Test
    fun `script without a fix still speaks`() {
        val s = SosText.script(texts, SosKind.MEDICAL, null, 0, "จุด")
        assertTrue(s, s.contains("เหตุฉุกเฉิน"))
        assertTrue(s, s.contains("ไม่มีพิกัด"))
    }

    @Test
    fun `plus code matches the reference vectors`() {
        // เวกเตอร์ทดสอบของ Open Location Code
        assertEquals("7FG49QCJ+2V", PlusCode.encode(20.3700625, 2.7821875))
        assertEquals("8FVC2222+22", PlusCode.encode(47.0000625, 8.0000625))
        assertEquals("4VCPPQGP+Q9", PlusCode.encode(-41.2730625, 174.7859375))
    }

    @Test
    fun `plus code survives the edges of the map`() {
        assertEquals(11, PlusCode.encode(90.0, 180.0).length)
        assertEquals(11, PlusCode.encode(-90.0, -180.0).length)
        assertEquals(11, PlusCode.encode(0.0, 540.0).length)
    }

    // ── แรงกระแทก ──

    /** เหตุการณ์จำลองที่ 50 Hz · คืนผลตอนจบ */
    private class Sim(level: Int = 1) {
        val d = ImpactDetector(ImpactDetector.Config.forLevel(level))
        var t = 1_000L
        var out: ImpactDetector.Outcome? = null

        fun feed(g: Double, ms: Long) {
            var left = ms
            while (left > 0) {
                t += 20
                left -= 20
                d.onSample(t, g)?.let { out = it }
            }
        }

        fun speed(kmh: Double) = d.onSpeed(t, kmh)

        /** กระแทกต่อเนื่องเหมือนรถชน ~100 มิลลิวินาที */
        fun crash() = feed(12.0, 100)
    }

    @Test
    fun `fast then stopped is a crash`() {
        val s = Sim()
        s.feed(1.0, 500)
        s.speed(60.0)
        s.feed(1.0, 500)
        s.crash()
        s.feed(1.0, 1000)
        s.speed(0.0)
        s.feed(1.0, 13_000)
        assertEquals(SosConfidence.HIGH, s.out?.confidence)
        assertEquals("crash", s.out?.reading?.verdict)
    }

    @Test
    fun `fast and still driving is the phone falling in the car`() {
        val s = Sim()
        s.speed(60.0)
        s.feed(1.0, 500)
        s.crash()
        s.feed(1.0, 1000)
        s.speed(58.0)
        s.feed(1.0, 13_000)
        assertNull(s.out?.confidence)
        assertEquals("kept_moving", s.out?.reading?.verdict)
    }

    @Test
    fun `no speed and free fall first is a dropped phone`() {
        val s = Sim()
        s.feed(1.0, 500)
        s.feed(0.1, 300)
        s.feed(15.0, 100)
        s.feed(1.0, 13_000)
        assertNull(s.out?.confidence)
        assertEquals("dropped", s.out?.reading?.verdict)
    }

    @Test
    fun `no speed but a very hard hit then stillness asks at low confidence`() {
        val s = Sim()
        s.feed(1.0, 500)
        s.feed(14.0, 120)
        s.feed(1.0, 13_000)
        assertEquals(SosConfidence.LOW, s.out?.confidence)
    }

    @Test
    fun `picked up right after the hit is not an accident`() {
        val s = Sim()
        s.feed(1.0, 500)
        s.feed(14.0, 120)
        var up = false
        repeat(650) {
            up = !up
            s.feed(if (up) 1.4 else 0.7, 20)
        }
        assertNull(s.out?.confidence)
        assertEquals("handled", s.out?.reading?.verdict)
    }

    @Test
    fun `a sharp tap below the duration is ignored`() {
        val s = Sim()
        s.feed(1.0, 500)
        s.feed(20.0, 20)
        s.feed(1.0, 14_000)
        assertNull(s.out)
        assertFalse(s.d.busy)
    }

    @Test
    fun `a stale speed does not count as moving`() {
        val s = Sim()
        s.speed(80.0)
        s.feed(1.0, 40_000)
        s.feed(14.0, 120)
        s.feed(1.0, 13_000)
        assertEquals(null, s.out?.reading?.speedBefore)
    }

    // ── คำตอบของเจ้าของ ──

    @Test
    fun `fine only when that is the whole sentence`() {
        for (t in listOf("ไม่เป็นไร", "ไม่เป็นไรค่ะ", "ไม่ เป็น ไร", "โอเคครับ", "I'm fine", "cancel")) {
            assertEquals(t, SosReply.Answer.FINE, SosReply.classify(t))
        }
        for (t in listOf("ไม่เป็นไรหรอกเรื่องนี้เดี๋ยวก็หาย", "เขาบอกว่าไม่เป็นไร", "")) {
            assertEquals(t, SosReply.Answer.UNKNOWN, SosReply.classify(t))
        }
    }

    @Test
    fun `help always wins`() {
        for (t in listOf("ช่วยด้วย", "เจ็บมาก", "ไม่เป็นไร ช่วยด้วย", "เรียกรถพยาบาลที", "help me")) {
            assertEquals(t, SosReply.Answer.HELP, SosReply.classify(t))
        }
    }

    @Test
    fun `her own question never answers itself`() {
        assertEquals(SosReply.Answer.UNKNOWN, SosReply.classify(texts.alertPrompt))
    }

    // ── เสียง ──

    private fun wav(rate: Int, channels: Int, samples: ShortArray): ByteArray {
        val data = samples.size * 2
        val b = ByteBuffer.allocate(44 + data).order(ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()).putInt(36 + data).put("WAVE".toByteArray())
        b.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(channels.toShort()).putInt(rate)
        b.putInt(rate * channels * 2).putShort((channels * 2).toShort()).putShort(16)
        b.put("data".toByteArray()).putInt(data)
        samples.forEach { b.putShort(it) }
        return b.array()
    }

    @Test
    fun `wav at any rate comes out at 24k mono`() {
        val pcm = SosWav.parse(wav(16_000, 1, ShortArray(16_000) { 100 }))
        assertNotNull(pcm)
        val line = SosWav.toLine(pcm!!)
        assertEquals(48_000, line.size)
    }

    @Test
    fun `stereo folds down and a zero data size still reads`() {
        val bytes = wav(24_000, 2, ShortArray(400) { 300 })
        ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).putInt(40, 0)
        val pcm = SosWav.parse(bytes)
        assertNotNull(pcm)
        assertEquals(400, SosWav.toLine(pcm!!).size)
    }

    @Test
    fun `garbage is refused not crashed on`() {
        assertNull(SosWav.parse(ByteArray(10)))
        assertNull(SosWav.parse(ByteArray(100)))
    }
}
