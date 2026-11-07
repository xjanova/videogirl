package com.xjanova.videogirl.chats

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SmsSenderTest {

    @Test
    fun realNumbersPass() {
        assertEquals("0812345678", SmsSender.phoneDigits("081-234-5678"))
        assertEquals("66812345678", SmsSender.phoneDigits("+66 81 234 5678"))
        assertEquals("021234567", SmsSender.phoneDigits("(02) 123 4567"))
        assertEquals("91234567", SmsSender.phoneDigits("9123 4567"))
        assertTrue(SmsSender.ok("+66812345678", null, null))
        assertTrue(SmsSender.ok("แม่", null, "tel:+66812345678"))
    }

    @Test
    fun savedContactPasses() {
        assertTrue(SmsSender.ok("แม่", "แม่", "content://com.android.contacts/contacts/lookup/abc/12"))
    }

    @Test
    fun banksOtpAndPromosAreRefused() {
        for (who in listOf("KBank", "SCB", "AIS", "Shopee", "TrueMoney", "Grab", "K PLUS", "1677", "4567890", "027777")) {
            assertFalse(who, SmsSender.ok(who, who, null))
        }
        // แอปแนบเบอร์สั้นมา = เชื่อเบอร์นั้น ไม่ใช่ชื่อที่โชว์
        assertFalse(SmsSender.ok("0812345678", null, "tel:1677"))
        assertFalse(SmsSender.ok("x", null, "mailto:a@b.c"))
    }

    @Test
    fun oddShapesAreNotNumbers() {
        assertNull(SmsSender.phoneDigits("08+12345678"))
        assertNull(SmsSender.phoneDigits("++66812345678"))
        assertNull(SmsSender.phoneDigits("0812345678901234567"))
        assertNull(SmsSender.phoneDigits(""))
        assertNull(SmsSender.phoneDigits(null))
    }

    @Test
    fun smsAppsAreKnown() {
        assertTrue(SmsSender.isSms("com.google.android.apps.messaging"))
        assertTrue(SmsSender.isSms("com.samsung.android.messaging"))
        assertTrue(SmsSender.isSms("com.android.mms"))
        assertFalse(SmsSender.isSms("com.whatsapp"))
    }
}
