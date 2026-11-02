# รุ่นของ OpenAI ที่แอปใช้ — ตรวจล่าสุด 2026-11-02

ตรวจกับเอกสาร OpenAI โดยตรง (developers.openai.com/api/docs/models และหน้า
deprecations) · โค้ดอยู่ที่ `lib/ai/openai_config.dart` · ถ้าหน้านี้กับโค้ดขัดกัน
ให้เชื่อโค้ด แล้วมาแก้หน้านี้

## สมอง (`/v1/chat/completions`)

| id | ในรายการ | หมายเหตุ |
|---|---|---|
| `gpt-5.6-sol` | ✅ ค่าตั้งต้น | ตัวท็อปของรุ่น 5.6 |
| `gpt-6.1-sol` | ✅ | ใหม่ (29 ก.ย. 2026) · ไม่รับ `reasoning_effort: none` → ใช้ `low` |
| `gpt-6.1-terra` | ✅ | $1 / $5 ต่อล้านโทเคน · context 1,050,000 · effort none…max · รับรูป · มีทั้ง Chat Completions และ Responses · เอกสารบอกว่า tool calling ต้องใช้ Responses API แต่สมองแชทของแอปใช้แท็ก ไม่ส่ง `tools` |
| `gpt-5.6-terra` | ✅ | ระดับ mini |
| `gpt-6-luna` | ✅ | ถูกและเร็วที่สุด (แทน `gpt-5.6-luna`) |
| `gpt-6-astra` | ✅ | ตัวท็อป แพงสุด · ไม่รับ `none` และไม่รับ temperature |
| `gpt-5.5`, `gpt-5.4-mini`, `gpt-5.6-luna` | ❌ ถอดออก | ยังไม่ถูกปิด ใช้ต่อได้ผ่านช่องพิมพ์ชื่อรุ่นเอง |

🔴 **ต้องส่ง `reasoning_effort` เสมอ** (`OpenAiConfig.effortFor`) · ไม่ส่ง =
รุ่น 5.6/6 คิดภายในระดับ medium และ `max_completion_tokens` **นับรวม reasoning
tokens** · เพดาน 600 ของแอปจึงหมดไปกับการคิดได้ แล้วคำตอบกลับมาว่าง
ส่งเฉพาะตอนยิง OpenAI ตรง — พร็อกซีของเรากับเซิร์ฟเวอร์ในบ้านไม่รู้จักฟิลด์นี้

## เสียงพูด (`/v1/audio/speech`)

- เหลือ `gpt-4o-mini-tts` ตัวเดียว · `tts-1` / `tts-1-hd` ถูกประกาศเลิกใช้ และ**ใช้กับ
  เสียง ballad / marin / cedar ไม่ได้** · ค่าที่เคยเลือกถูกย้ายตอนโหลด (`migrateTts`)
- เสียง: marin, cedar (OpenAI แนะนำว่าดีที่สุด), coral, shimmer, sage, nova, ballad
- ⚠️ **`gpt-4o-mini-tts` ถูกประกาศปิด 2027-01-06** และยังไม่มีรุ่นแทนบน endpoint นี้
  (ตัวแทนที่ประกาศคือ `gpt-realtime-2.1-mini` ซึ่งเป็น Realtime API) — **ต้องย้ายก่อนวันนั้น**

## ถอดเสียง (`/v1/audio/transcriptions`)

- ยังใช้ `whisper-1` · ⚠️ **ปิด 2027-02-26**
- ตัวแทนที่ OpenAI แนะนำคือ `gpt-transcribe` · ส่ง multipart แบบเดียวกันได้ แต่ใช้
  `languages[]` แทน `language` และยังยืนยันไม่ได้ว่ารับภาษาไทย (`th`) · ต้องลองจริง
  ก่อนย้าย

## คุยสด (Realtime · GPT-Live)

ใช้จริงแล้วทั้งในสาย (`lib/phone/realtime_call.dart` · `live_call.dart`) และตอนกดไมค์
(`lib/ai/realtime_chat.dart`) · ต้องเป็นสมอง OpenAI ด้วยคีย์ของเจ้าของ · ต่อไม่ได้ = ตกไปทางเดิม

🔴 คุยสดพูดด้วยเสียงของ OpenAI เท่านั้น · ElevenLabs Gemini Azure และเสียงเครื่องไม่เกี่ยว ·
เสียงที่รุ่นนั้นไม่รู้จักกลายเป็น `marin` เงียบ ๆ (`RealtimeCall.voices` ไม่รวม `nova` ·
`LiveCall.voices` เป็นคนละชุด เหมือนกันแค่ `marin`) · หน้าตั้งค่าเตือนเมื่อเสียงที่เลือกไม่ถูกใช้
(`MindState.callLiveVoice` · `voiceChatVoice`) · การ์ดรับสายแทนมีบรรทัด "คุยสด"
ทางเดิมในสาย: ฟัง = ตัวถอดเสียงของสมองที่เลือก · คิด = สมองที่เลือก · พูด = เสียงแท็บ "ในสาย"

## วิธีเอาคีย์

คู่มือทีละขั้น (ไทย/อังกฤษ) อยู่ใต้ช่องคีย์ของแต่ละเจ้าในแอป พร้อมปุ่มเปิดหน้าออกคีย์ ·
ข้อความอยู่ที่ `lib/i18n/strings_voice.dart` (`keyGuide*`) · ลิงก์อยู่ที่ `_keyPages` ใน
`settings_screen.dart`

## สิ่งที่ยังยืนยันจากเอกสารไม่ได้

- คุณภาพภาษาไทยของทุกรุ่น (เอกสารไม่พูดถึง)
- `gpt-transcribe` รับ `th` ไหม / รับ `response_format=text` ไหม
