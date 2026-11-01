package com.xjanova.videogirl.sos

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * ที่เก็บข้อมูลฉุกเฉินแบบเข้ารหัส · ข้อมูลสุขภาพ เบอร์ญาติ และแผนการแจ้งเหตุ
 *
 * ## ทำไมไม่ใช้ SecretStore ของ Dart
 *
 * ตอนเกิดเหตุ Dart อาจไม่อยู่ · ฝั่งเนทีฟต้องอ่านได้เองตอนเครื่องล็อก · กุญแจอยู่ใน Android Keystore
 * ไม่ผูกกับการปลดล็อก (ไม่งั้นบริการอ่านแผนไม่ได้ตอนจอล็อก ซึ่งคือตอนที่ต้องใช้ที่สุด) ·
 * ไฟล์อยู่ใน noBackupFilesDir ไม่หลุดไปกับ backup และไม่เข้าสำเนาที่รอดการถอนแอป
 *
 * 🔒 ห้าม log เนื้อหา · log ได้แค่ชนิดของข้อผิดพลาด
 */
object SosVault {
    private const val KEYSTORE = "AndroidKeyStore"
    private const val ALIAS = "giggok_sos_v1"
    private const val DIR = "sos"
    private const val TAG_BITS = 128
    private const val IV_BYTES = 12

    private fun file(c: Context, name: String) = File(File(c.noBackupFilesDir, DIR).apply { mkdirs() }, "$name.bin")

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }

    fun write(c: Context, name: String, text: String): Boolean = try {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val body = cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        val f = file(c, name)
        // เขียนไฟล์ชั่วคราวแล้วย้าย · แบตหมดกลางการเขียน = แผนเดิมยังอยู่ ไม่กลายเป็นไฟล์ครึ่งเดียว
        val tmp = File(f.parentFile, "${f.name}.tmp")
        tmp.writeBytes(cipher.iv + body)
        tmp.renameTo(f)
    } catch (e: Exception) {
        android.util.Log.w("GigGokSos", "vault write: ${e.javaClass.simpleName}")
        false
    }

    /** null = ไม่มี หรืออ่านไม่ได้ (กุญแจหายหลังกู้เครื่อง) · ผู้เรียกถือว่ายังไม่ได้ตั้ง */
    fun read(c: Context, name: String): String? = try {
        val f = file(c, name)
        if (!f.exists()) {
            null
        } else {
            val all = f.readBytes()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, all.copyOfRange(0, IV_BYTES)))
            String(cipher.doFinal(all, IV_BYTES, all.size - IV_BYTES), Charsets.UTF_8)
        }
    } catch (e: Exception) {
        android.util.Log.w("GigGokSos", "vault read: ${e.javaClass.simpleName}")
        null
    }

    fun delete(c: Context, name: String) {
        file(c, name).delete()
    }
}
