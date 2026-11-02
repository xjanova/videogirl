package com.xjanova.videogirl

import android.telecom.DisconnectCause
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** น้องมายโอนสายคนโทรไปหาเจ้าของ · ส่วนที่ตัดสินใจโดยไม่ต้องมีสายจริง (ดู CallTransfer) */
class CallTransferTest {

    @Test
    fun `สองสายรวมกันได้ = รวมสายตรง ๆ ก่อน`() {
        assertEquals("conference", CallTransfer.connectMethod(conferenceable = true, mergeable = true))
    }

    @Test
    fun `เครือข่ายให้แค่วงที่เตรียมไว้ (หรือรอบแรกไม่ติด) = รวมเข้าวง`() {
        assertEquals("merge", CallTransfer.connectMethod(conferenceable = false, mergeable = true))
    }

    @Test
    fun `ไม่มีทางรวมสายเลย = บอกตรง ๆ ว่าต่อไม่ได้`() {
        assertEquals("unsupported", CallTransfer.connectMethod(conferenceable = false, mergeable = false))
    }

    @Test
    fun `เจ้าของสายไม่ว่าง กดตัด หรือปฏิเสธก่อนรับ = ไม่ว่าง`() {
        assertEquals("busy", CallTransfer.causeOf(DisconnectCause.BUSY, answered = false))
        assertEquals("busy", CallTransfer.causeOf(DisconnectCause.REJECTED, answered = false))
        assertEquals("busy", CallTransfer.causeOf(DisconnectCause.REMOTE, answered = false))
    }

    @Test
    fun `เจ้าของรับแล้ววาง = ไม่สะดวก ไม่ใช่สายไม่ว่าง`() {
        assertEquals("hung_up", CallTransfer.causeOf(DisconnectCause.REMOTE, answered = true))
    }

    @Test
    fun `เราวางเอง (หมดเวลา หรือยกเลิก) = ยกเลิก แม้เจ้าของเคยรับ`() {
        assertEquals("cancelled", CallTransfer.causeOf(DisconnectCause.LOCAL, answered = false))
        assertEquals("cancelled", CallTransfer.causeOf(DisconnectCause.LOCAL, answered = true))
        assertEquals("cancelled", CallTransfer.causeOf(DisconnectCause.MISSED, answered = false))
    }

    @Test
    fun `เครือข่ายขัดข้อง ปิดเครื่อง ไม่มีสัญญาณ = ติดต่อไม่ได้`() {
        assertEquals("unreachable", CallTransfer.causeOf(DisconnectCause.ERROR, answered = false))
        assertEquals("unreachable", CallTransfer.causeOf(DisconnectCause.OTHER, answered = false))
    }

    @Test
    fun `เบอร์เดียวกันคนละรูปแบบ = เบอร์เดียวกัน (กันโอนกลับหาคนโทร)`() {
        assertTrue(CallTransfer.sameNumber("+66812345678", "0812345678"))
        assertTrue(CallTransfer.sameNumber("081-234-5678", "0812345678"))
        assertFalse(CallTransfer.sameNumber("0812345678", "0812345679"))
        assertFalse(CallTransfer.sameNumber("", "0812345678"))
    }

    @Test
    fun `เบอร์สั้นเทียบทั้งเบอร์ ไม่ตัดท้าย`() {
        assertTrue(CallTransfer.sameNumber("1112", "1112"))
        assertFalse(CallTransfer.sameNumber("1112", "21112"))
    }
}
