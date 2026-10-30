package com.xjanova.videogirl.direct.setup

import android.content.Context
import android.os.Build
import android.util.AtomicFile
import io.github.muntashirakon.adb.AbsAdbConnectionManager
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import java.io.File
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.cert.Certificate
import java.security.cert.CertificateFactory
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Date
import java.util.concurrent.TimeUnit

/** RSA material stays in noBackupFilesDir, never shared storage or Android backup. */
internal class LocalAdbIdentity(context: Context) : AbsAdbConnectionManager() {
    private val key: PrivateKey
    private val certificate: Certificate
    init {
        setApi(Build.VERSION.SDK_INT)
        setHostAddress("127.0.0.1")
        setTimeout(10, TimeUnit.SECONDS)
        setThrowOnUnauthorised(true)
        val file = AtomicFile(File(context.noBackupFilesDir, "direct-adb-identity.bin"))
        if (file.baseFile.exists()) {
            java.io.DataInputStream(file.openRead()).use { input ->
                val keySize = input.readInt()
                require(keySize in 256..8192)
                val encoded = ByteArray(keySize).also(input::readFully)
                key = KeyFactory.getInstance("RSA").generatePrivate(PKCS8EncodedKeySpec(encoded))
                certificate = CertificateFactory.getInstance("X.509").generateCertificate(input)
            }
        } else {
            val random = SecureRandom()
            val pair = KeyPairGenerator.getInstance("RSA").apply { initialize(2048, random) }.generateKeyPair()
            val subject = X500Name("CN=GigGok local call audio")
            // Sign and convert with the platform providers. BouncyCastleProvider loads its algorithms
            // by class name, R8 strips those classes, and SHA256withRSA then fails in release only.
            val cert = JcaX509v3CertificateBuilder(subject, BigInteger(128, random),
                Date(System.currentTimeMillis() - 86400000L), Date(System.currentTimeMillis() + 315360000000L),
                subject, pair.public).build(JcaContentSignerBuilder("SHA256withRSA").build(pair.private))
            key = pair.private
            certificate = JcaX509CertificateConverter().getCertificate(cert)
            val output = file.startWrite()
            try {
                val data = java.io.DataOutputStream(output)
                data.writeInt(key.encoded.size); data.write(key.encoded); data.write(certificate.encoded); data.flush()
                file.finishWrite(output)
            } catch (e: Exception) { file.failWrite(output); throw e }
        }
    }
    override fun getPrivateKey(): PrivateKey = key
    override fun getCertificate(): Certificate = certificate
    override fun getDeviceName(): String = "GigGok"
}
