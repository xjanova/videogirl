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

**แท็กคือแหล่งความจริงของเวอร์ชัน ไม่ใช่ `pubspec.yaml`** — workflow อ่านแท็ก
ล่าสุดแล้ว `+1` เอง จากนั้นส่งเข้า build ผ่าน `--build-name` / `--build-number`
ค่า `version:` ใน pubspec เป็นแค่ค่าตั้งต้นตอนยังไม่มี release สักตัว

`versionCode` คิดจากเลขเวอร์ชันตรง ๆ (`major*10000 + minor*100 + patch`)
ไม่ใช่เลข run ของ Actions เพราะเลข run รีเซ็ตได้เวลาเปลี่ยนชื่อไฟล์ workflow
แล้ว versionCode จะเดินถอยหลัง ซึ่ง Android จะปฏิเสธการติดตั้งทับทันที
(ผลพลอยได้: minor กับ patch ห้ามเกิน 99 — เกินแล้ว workflow จะหยุดพร้อมบอกเหตุ)

## ครั้งแรก — สร้าง keystore

> ทำไปแล้วสำหรับ repo นี้ (31 ส.ค. 2026) — เก็บไว้เป็นวิธีทำถ้าต้องเริ่มใหม่
> ของจริงอยู่ที่ `android/app/release.jks` และสำรองไว้ที่ `~/.videogirl-release-key/`
> secrets ใน repo ตั้งครบแล้ว ยกเว้น `OPENAI_API_KEY` (ตั้งใจไม่ตั้ง — ดูข้างล่าง)

```bash
keytool -genkeypair -v -keystore android/app/release.jks -storetype PKCS12   -keyalg RSA -keysize 4096 -validity 10000 -alias videogirl
```

**เก็บไฟล์นี้ให้ดีที่สุด** ทำหายแล้วออกอัปเดตให้เครื่องที่ลงไปแล้วไม่ได้อีกเลย
สำรองไว้นอกเครื่องอย่างน้อยหนึ่งที่ — และอย่าคิดว่า GitHub secret คือสำเนา
**secret อ่านกลับออกมาไม่ได้** เขียนทับได้อย่างเดียว

ตั้ง secrets ใน repo:

```bash
base64 -w0 android/app/release.jks | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_STORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
```

> **workflow ไม่ `--dart-define` คีย์อะไรเข้าไปเลย โดยตั้งใจ** — release นี้ให้เธอ
> คิดด้วย Gemma บนเครื่อง ไม่ต้องพึ่งคีย์ของใคร และคีย์ที่ `--dart-define` เข้าไป
> จะ **ฝังอยู่ใน APK สาธารณะ** ใครโหลดไปแกะก็อ่านได้ (`--obfuscate` ไม่ช่วย
> เพราะค่าคงที่ยังเป็นสตริงเปล่า ๆ อยู่ดี) ถ้าวันหนึ่งต้องใช้บริการที่มีคีย์จริง ๆ
> ให้ต่อผ่าน backend ของเราเอง ไม่ใช่กลับมายัดคีย์ตรงนี้ ดู [security.md](security.md)

สำหรับ build ในเครื่อง สร้าง `android/key.properties` (ถูก gitignore แล้ว):

```properties
storeFile=release.jks
storePassword=...
keyAlias=videogirl
keyPassword=...
```

`storeFile` เป็น path ที่นับจาก `android/app/` ไม่ใช่จากรากโปรเจกต์

## ขนาด APK — ตัดอะไรออกไปบ้าง

271 MB → ~79 MB · **ที่ใหญ่ไม่เคยเป็นโมเดลภาษา** (โมเดล Gemma โหลดตอนรัน
จาก HuggingFace ไม่ได้อยู่ใน APK) แต่เป็น `.so` ของ MediaPipe/LiteRT ที่
`flutter_gemma` ลากมา

ตัดสองก้อนใน `packaging { jniLibs { excludes } }` ของ
[build.gradle.kts](../android/app/build.gradle.kts):

| ตัดอะไร | ได้คืน |
|---|---|
| `lib/x86*`, `lib/armeabi-v7a` | ~106 MB |
| ไลบรารี RAG / vision / image-gen ที่แอปไม่ได้เรียก 7 ตัว | ~85 MB |

**ห้ามใช้ `ndk { abiFilters }` แทน — มันไม่กรองอะไรเลย** วัดจาก APK จริงแล้ว
ตั้ง abiFilters เป็น arm64+v7a แต่ x86_64 ยังหลุดมาครบ 71.6 MB รวม
`libflutter.so` ของ x86_64 ด้วย ส่วน `--target-platform android-arm64` ก็คุมได้
แค่ `.so` ที่ Flutter สร้างเอง ไม่ถึง `.so` ที่มาจาก AAR ของ plugin

🔴 **วันไหนจะใช้ RAG / ความจำแบบเวกเตอร์ / วิเคราะห์ภาพ ต้องกลับไปลบบรรทัด
ที่เกี่ยวออกจาก excludes ก่อน** ไม่งั้นได้ `UnsatisfiedLinkError` ตอนรันจริง
โดยไม่มีอะไรเตือนตอน build

## เวอร์ชัน Flutter ถูกตรึงไว้

workflow ตรึง `flutter-version: 3.41.7` ไม่ใช้ `channel: stable` ลอย ๆ

`flutter analyze` นับ info เป็น error ด้วย พอ Flutter ออก stable ใหม่ที่มี
deprecation warning เพิ่ม release จะพังเองทั้งที่ไม่มีใครแตะโค้ด — เกิดมาแล้วจริง
ตอน CI ได้ 3.47.2 แล้วเตือน `axisAlignment` ใน `home_screen.dart` ซึ่งเครื่องที่ใช้
3.41.7 มองไม่เห็น และแก้ตามที่มันบอกก็ไม่ได้ เพราะ `alignment` ที่เป็นตัวแทน
ยังไม่มีใน 3.41.7 — แก้แล้วเครื่องจะ build ไม่ผ่านแทน

เวลาจะขยับ Flutter: ขยับในเครื่องก่อน แก้ deprecation ที่โผล่ให้หมด แล้วค่อยแก้
เลขใน workflow **เป็น commit แยก** จะได้แยกออกว่าอะไรพังเพราะ Flutter ไม่ใช่โค้ดเรา

## ออก release

**ปกติไม่ต้องทำอะไร** — push ขึ้น `main` แล้ว
[workflow](../.github/workflows/release.yml) จะ
คิดเวอร์ชันถัดไป → analyze → test → build APK → ทำแฮช → ออก release ให้เอง

| อยากได้ | ทำ |
|---|---|
| patch อัตโนมัติ (`0.1.0` → `0.1.1`) | push ขึ้น `main` เฉย ๆ |
| ไม่ต้องออก release รอบนี้ | ใส่ `[skip release]` ในข้อความ commit |
| minor / major | Actions → release → Run workflow → เลือก bump |
| กำหนดเวอร์ชันเอง | Actions → release → Run workflow → กรอกช่อง version |

push ที่แตะแค่ `*.md`, `docs/`, `.gitignore`, `.gitattributes`, `.idea/`
จะไม่ปลุก workflow (ดู `paths-ignore`)

release ที่ออกมาจะมี 3 ไฟล์: APK, `SHA256SUMS.txt` และ `debug-symbols-*.zip`
(ตัวหลังเก็บไว้อ่าน stack trace เพราะ build จริงใช้ `--obfuscate`)

### ต้องออก release ซ้ำเวอร์ชันเดิม

workflow จะหยุดถ้าแท็กนั้นมีอยู่แล้ว ลบทั้ง release และแท็กก่อน แล้วสั่งใหม่:

```bash
gh release delete v0.1.1 --cleanup-tag --yes
```

## ชุดตัวมายด์ (avatar pack) — ต้องแยกจาก release เสมอ

🔴 **APK ที่ CI build ไม่มีตัวเธออยู่ข้างใน** เพราะ `assets/avatar/model/` ถูก
`.gitignore` ทั้งโฟลเดอร์ (repo public + คลิป Mixamo แจกต่อไม่ได้ ดู THIRD_PARTY.md)
ใครลง APK จาก release จะเห็นกรอบ placeholder แทนตัวเธอ จนกว่าจะโหลดชุด

**ห้ามแนบชุดไปกับ GitHub Release** — release เป็น public เท่ากับแจกคลิป Mixamo ต่อ

> โครงไฟล์เต็ม ๆ กับวิธีทำชุดเพิ่ม (ชุดอื่น ทรงอื่น เลขาคนอื่น) อยู่ที่ [packs.md](packs.md)

### ทำไฟล์ชุด

```bash
cd assets/avatar/model && zip -r ../../../giggok-avatar-pack.zip . -x .gitkeep && cd -
sha256sum giggok-avatar-pack.zip
```

โครงในไฟล์ต้องเป็น **ไฟล์วางแบน ๆ ไม่มีโฟลเดอร์ครอบ** — แอปเสิร์ฟจากรากของ
โฟลเดอร์ที่แตกไว้ ถ้ามีโฟลเดอร์ครอบ `minde.vrm` จะหาไม่เจอ แล้วขึ้นว่าแพ็กผิดโครง

### เอาไปวางที่ไหน

ที่ไหนก็ได้ที่เป็น **HTTPS และเปิดอ่านได้โดยไม่ต้องล็อกอิน** เช่น
Cloudflare R2 (public bucket) หรือเซิร์ฟเวอร์ในบ้านของเจ้าของ

> อย่าใช้ private GitHub release — ต้องมี token ถึงจะโหลดได้
> และ token ที่ฝังใน APK คือ token ที่ใครแกะ APK ก็อ่านได้

### ตั้งในแอป

หน้าตั้งค่า → การ์ด **ชุดตัวมายด์** → วาง URL → กดโหลดชุด
โหลดครั้งเดียวอยู่ในเครื่องเลย · อยากตั้งค่าเริ่มต้นให้ทุกเครื่องก็ใส่ตอน build:

```bash
flutter build apk --release --dart-define=AVATAR_PACK_URL=https://…/giggok-avatar-pack.zip
```

## ทดสอบก่อนปล่อยจริง

1. ลง release ก่อนหน้าลงเครื่องจริง
2. push tag ใหม่
3. เปิดแอป → หน้าตั้งค่า → การ์ด "อัปเดตแอป" ต้องขึ้นรุ่นใหม่ภายในไม่กี่วินาที
4. กดดาวน์โหลด → ต้องเห็น "กำลังตรวจว่าไฟล์ตรงกับที่ประกาศไว้" ก่อนเปิดตัวติดตั้ง
5. ติดตั้งทับต้องผ่าน ไม่ขึ้น error เรื่องลายเซ็น

ถ้าตัวติดตั้งไม่เปิด: ผู้ใช้ต้องอนุญาต **"ติดตั้งแอปที่ไม่รู้จัก"** ให้แอปนี้ก่อน
(Android ไม่มีทางข้ามขั้นนี้ได้ และไม่ควรมี)
