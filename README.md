# มายด์ (videogirl)

แอป Android — ผู้ช่วยส่วนตัวรูปสาว 3D คุยได้ พูดได้ ขยับปากตามเสียงจริง
สลับได้ระหว่าง **โหมดงาน** (เลขาฯ) กับ **โหมดส่วนตัว**

> ⚠️ repo นี้เป็น **public** — ห้าม commit API key, token, `.env`, keystore, โมเดล VRM
> หรือคลิป Mixamo เด็ดขาด (ดู [.gitignore](.gitignore))

## ตอนนี้ทำอะไรได้แล้ว

| หน้าจอ | สถานะ |
|---|---|
| หน้าหลัก — อวาตาร์ + แชทกระจก | ✅ สมองสี่ทาง: Gemma ในเครื่อง (GPU/CPU) · คีย์ OpenAI ของตัวเอง · พร็อกซีหลังบ้าน · เซิร์ฟเวอร์ในบ้าน |
| เมล | ⏸ ยังไม่ได้เชื่อมกล่องเมล — หน้าบอกตรง ๆ ไม่ใช้ข้อมูลตัวอย่างแล้ว |
| ปฏิทิน | ✅ อ่านปฏิทินจริงของเครื่อง (อ่านอย่างเดียว) |
| ไทม์ไลน์ — วันนี้เธอทำอะไรให้ | ✅ สมุดบันทึกจริง |
| ตั้งค่า — บุคลิก เสียง ขอบเขต | ✅ ใช้งานได้จริง บันทึกลง SQLite + สำเนาที่รอดการถอนแอป |
| อัปเดตในตัว | ✅ ถาม xman studio ก่อน (ตกไป GitHub Releases) + ตรวจ SHA-256 |
| รับสายแทน | 🧪 รับสาย/พูดเข้าสายได้ · รับฝากเรื่องลงไทม์ไลน์ · ฟังคู่สายต้องใช้สมองที่ถอดเสียงได้ — ดู [docs/telephony.md](docs/telephony.md) |
| รายงานบั๊ก | ✅ ส่งเข้า bug-reports ของ xman studio (ทั้งกดเอง ส่งเองเมื่อมีข้อผิดพลาด และ crash) |
| หน้าเปิดแอป — วิดีโอโลโก้ | ✅ เล่นทับเชลล์ที่กำลังโหลด แตะข้ามได้ |
| กล้องเชิดหุ่น (mocap ใบหน้า) | ✅ ใช้ได้บนเครื่องจริง |
| สตูดิโอวิดีโอ — วิดีโอคอล (แชร์จอ) · จอลอย · ฉากเขียว · อัดคลิป | 🧪 ยังไม่ได้ลองบนเครื่องจริง — ดู [docs/studio.md](docs/studio.md) |

## เริ่มพัฒนา

```bash
flutter pub get
```

ต้องมี **avatar pack** ก่อนถึงจะเห็นตัวเธอ — ดู [assets/avatar/MODEL.md](assets/avatar/MODEL.md)
ถ้าไม่มี แอปยังรันได้ปกติ แต่จะขึ้นกรอบ placeholder แทน

รันพร้อมคีย์ OpenAI (คีย์อยู่นอก repo เสมอ):

```bash
flutter run --dart-define-from-file=../videogirl-secrets.json
```

ไฟล์ `videogirl-secrets.json` (เก็บไว้**นอก**โฟลเดอร์โปรเจกต์):

```json
{ "OPENAI_API_KEY": "<คีย์ OpenAI ของคุณ>", "OPENAI_MODEL": "gpt-5.6-sol" }
```

ไม่ใส่คีย์ก็รันได้ — เธอจะตอบด้วยประโยคสำเร็จรูป และใช้เสียงฟรีของ Android แทน

## โครงสร้าง

```
lib/
  ai/          สมอง + เสียง (OpenAI, TTS เครื่อง, บุคลิก)
  avatar/      สะพานไป WebView ที่เรนเดอร์ VRM
  screens/     6 หน้าจอ ถอดจาก artboard
  state/       MindState — โหมด แชท ค่าตั้ง
  theme/       design token ถอดตรงจาก artboard
  update/      อัปเดตตัวเองจาก GitHub Releases
  widgets/     กระจก ก้อนแสง ชิ้นส่วนใช้ซ้ำ
assets/avatar/ เครื่องยนต์ VRM (ยกจาก BrainX) + vendor three.js
```

## ที่มาของดีไซน์

ทุกสี ระยะ และมุมโค้ง ถอดจาก artboard ของ Claude Design ใน
`ai-assistant-avatar-app/project/Mind Android Liquid.dc.html` (หน้าจอ 2a–2h)

**artboard คือแหล่งความจริง** — จะเปลี่ยนหน้าตา ให้แก้ที่นั่นก่อนแล้วถอดกลับมาที่
[lib/theme/tokens.dart](lib/theme/tokens.dart) อย่าแก้ค่าในโค้ดลอย ๆ ไม่งั้นดีไซน์กับโค้ดจะหลุดจากกัน

สิ่งเดียวที่ไม่ได้มาจาก artboard คือ**แถบนำทางล่างจอ** — artboard แยกเป็นคนละหน้า
เลยไม่มีทางเดินระหว่างหน้า จึงเพิ่มเข้ามาให้แอปใช้งานได้จริง

## อ่านต่อ

- [docs/security.md](docs/security.md) — ทำไมคีย์ใน APK ยังไม่ปลอดภัยพอสำหรับปล่อยจริง
- [docs/telephony.md](docs/telephony.md) — ข้อจำกัดของ Android เรื่องเสียงสายโทรศัพท์
- [docs/openai-models.md](docs/openai-models.md) — รุ่น OpenAI ที่ใช้ ตรวจกับเอกสารจริง และวันที่รุ่นเสียง/ถอดเสียงจะถูกปิด
- [docs/studio.md](docs/studio.md) — ทำไมเป็นแชร์จอ ไม่ใช่กล้องเสมือน · ฉากเขียว · อัดคลิป · ปากในสาย
- [docs/release.md](docs/release.md) — วิธีออก release ให้ auto-update ทำงาน
- [THIRD_PARTY.md](THIRD_PARTY.md) — ไลบรารีและสินทรัพย์ของคนอื่น
