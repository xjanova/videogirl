import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// คีย์เซ็นแอป — อยู่ใน android/key.properties ซึ่งถูก .gitignore ไว้แล้ว
//
// สำคัญมากสำหรับ auto-update: Android ปฏิเสธการติดตั้งทับถ้าลายเซ็นไม่ตรงกับ
// ตัวที่ลงอยู่ ถ้าปล่อยให้ release เซ็นด้วย debug key ทุกเครื่องที่ build จะได้
// ลายเซ็นคนละอัน แล้วอัปเดตจะล้มเหลวด้วย INSTALL_FAILED_UPDATE_INCOMPATIBLE
// โดยไม่มีอะไรบอกสาเหตุ ต้องใช้ keystore เดียวกันตลอดอายุแอป
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val hasReleaseKey = keystorePropertiesFile.exists()

android {
    namespace = "com.xjanova.videogirl"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.xjanova.videogirl"

        // API 26 = Android 8.0 — ต่ำกว่านี้ไม่ได้เพราะ:
        //  · ANSWER_PHONE_CALLS (รับสายแทน) เพิ่มมาใน API 26
        //  · WebView รุ่นเก่ากว่านี้เรนเดอร์ VRM ผ่าน WebGL2 ไม่ไหว
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // ไม่มี key.properties = เซ็นด้วย debug key ได้ แต่ **ห้ามเอาไปปล่อย**
            // เพราะเครื่องที่ลงตัวนั้นจะอัปเดตต่อไม่ได้อีกเลย
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // R8/shrink เปิดอยู่แล้วโดย Flutter gradle plugin จึงไม่ตั้งซ้ำตรงนี้
            // (ตั้งซ้ำจะไปทับตรรกะของมันที่ปิด shrink ให้เองในบาง build)
            //
            // แต่ **ผูก proguard-rules.pro เองแบบชัด ๆ** ถึงแม้ Flutter จะหยิบให้
            // อัตโนมัติอยู่แล้ว เพราะ CI ใช้ channel stable ซึ่งเลื่อนเวอร์ชันไปเรื่อย ๆ
            // ถ้าวันหนึ่งพฤติกรรมนั้นเปลี่ยน build release จะตายที่ R8 โดยที่เครื่อง
            // เราเองยัง build ผ่าน — เขียนไว้เองปลอดภัยกว่าและไม่มีผลข้างเคียง
            proguardFiles("proguard-rules.pro")

            ndk {
                // universal APK ใส่ .so ครบทั้ง 4 ABI = ใหญ่ขึ้นเท่าตัวโดยเปล่าประโยชน์
                // มือถือจริงไม่มี x86 แล้ว เก็บไว้แค่สองตัวที่ใช้จริง
                abiFilters += listOf("arm64-v8a", "armeabi-v7a")
            }
        }
        debug {
            // debug ต้องมี x86_64 ไว้ให้ emulator ไม่งั้นรันบน AVD ไม่ได้
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }
}

flutter {
    source = "../.."
}
