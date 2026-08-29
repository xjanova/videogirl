# ออก release ให้ auto-update ทำงาน

แอปเช็ครุ่นใหม่จาก `https://api.github.com/repos/xjanova/videogirl/releases/latest`
repo เป็น public จึงอ่านได้โดยไม่ต้องมี token — **อย่าฝัง GitHub token ลง APK เด็ดขาด**

## กฎที่ห้ามพลาด

### 1. ทุก release ต้องมี `SHA256SUMS.txt`

ไม่มีแฮช = แอปโหลดมาแล้ว**ลบทิ้ง** ไม่ยอมติดตั้ง (ตั้งใจให้เป็นแบบนั้น)
ไฟล์ที่โหลดมาครึ่ง ๆ หรือถูกสลับระหว่างทาง จะถูกส่งเข้า installer โดยตรง
ถ้าไม่ตรวจ — นั่นคือช่องลงมัลแวร์ที่ตรงที่สุดที่แอปหนึ่งจะเปิดให้ได้

รูปแบบเหมือน `sha256sum` มาตรฐาน:

```
d2f1a4...  giggok-0.2.0.apk
```

### 2. ต้องเซ็นด้วย keystore ตัวเดิมทุกครั้ง

Android ปฏิเสธการติดตั้งทับถ้าลายเซ็นไม่ตรง (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`)
ถ้าปล่อย release ที่เซ็นด้วย debug key ออกไป **เครื่องที่ลงตัวนั้นจะอัปเดตต่อไม่ได้อีกเลย**
ต้องถอนแล้วลงใหม่ (ข้อมูลหาย)

workflow จะหยุดทันทีถ้าไม่มี secret `ANDROID_KEYSTORE_BASE64`

### 3. tag ต้องขึ้นต้นด้วย `v` และเวอร์ชันต้องเพิ่มขึ้น

แอปเทียบเวอร์ชันเป็นตัวเลขทีละส่วน `1.10.0` > `1.9.0` (ไม่ใช่เทียบสตริง)
และต้องขยับ `version:` ใน `pubspec.yaml` ให้ตรงกับ tag ด้วย

## ครั้งแรก — สร้าง keystore

```bash
keytool -genkey -v -keystore videogirl-release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias videogirl
```

**เก็บไฟล์นี้ให้ดีที่สุด** ทำหายแล้วออกอัปเดตให้เครื่องที่ลงไปแล้วไม่ได้อีกเลย
สำรองไว้นอกเครื่องอย่างน้อยหนึ่งที่

ตั้ง secrets ใน repo:

```bash
gh secret set ANDROID_KEYSTORE_BASE64 < <(base64 -w0 videogirl-release.jks)
gh secret set ANDROID_STORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
gh secret set OPENAI_API_KEY
```

> คีย์ OpenAI ที่ใส่ตรงนี้จะ**ฝังอยู่ใน APK สาธารณะ** ใครโหลดไปก็อ่านได้
> ดู [security.md](security.md) — ก่อนเปิดให้คนอื่นใช้ต้องย้ายไป backend ก่อน

สำหรับ build ในเครื่อง สร้าง `android/key.properties` (ถูก gitignore แล้ว):

```properties
storeFile=/path/ที่/เก็บ/videogirl-release.jks
storePassword=...
keyAlias=videogirl
keyPassword=...
```

## ออก release

```bash
git tag v0.2.0
git push origin v0.2.0
```

[workflow](../.github/workflows/release.yml) จะ analyze → test → build → ทำแฮช → สร้าง release ให้เอง

## ทดสอบก่อนปล่อยจริง

1. ลง release ก่อนหน้าลงเครื่องจริง
2. push tag ใหม่
3. เปิดแอป → หน้าตั้งค่า → การ์ด "อัปเดตแอป" ต้องขึ้นรุ่นใหม่ภายในไม่กี่วินาที
4. กดดาวน์โหลด → ต้องเห็น "กำลังตรวจว่าไฟล์ตรงกับที่ประกาศไว้" ก่อนเปิดตัวติดตั้ง
5. ติดตั้งทับต้องผ่าน ไม่ขึ้น error เรื่องลายเซ็น

ถ้าตัวติดตั้งไม่เปิด: ผู้ใช้ต้องอนุญาต **"ติดตั้งแอปที่ไม่รู้จัก"** ให้แอปนี้ก่อน
(Android ไม่มีทางข้ามขั้นนี้ได้ และไม่ควรมี)
