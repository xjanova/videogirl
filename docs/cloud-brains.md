# สมองบนคลาวด์ · ตัวถอดเสียง · ปรับแต่ง ElevenLabs

ตรวจกับเอกสาร/หน้าราคาทางการ **2026-11-02** · รายการรุ่นมีแต่รุ่นปัจจุบัน
ไม่ใส่รุ่นที่ประกาศเลิกหรือถูกแทนแล้ว (เจ้าของสั่ง)

## สมอง (`lib/ai/cloud_brains.dart`)

| เจ้า | ทาง | คีย์ | รุ่น (USD ต่อล้านโทเคน เข้า/ออก) |
|---|---|---|---|
| OpenAI | `/v1/chat/completions` | `sk-…` | 5.6 Sol 4/20 · 6.1 Sol 2/10 · 6.1 Terra 1/5 · 5.6 Terra 2/12 · 6 Luna 0.10/0.50 · 6 Astra 10/50 |
| xAI Grok | `https://api.x.ai/v1` (OpenAI-compatible) | `xai-…` | grok-4.3 1.25/2.50 · grok-4.7 2/6 |
| Anthropic Claude | Messages API `/v1/messages` (`x-api-key`, `anthropic-version: 2023-06-01`) | `sk-ant-…` | Haiku 5.5 0.10/0.50 (≤100k) · Sonnet 5.5 2/10 · Opus 5.5 4/20 · Fable 5.1 10/50 |
| Google Gemini | `…/v1beta/openai` (OpenAI-compatible) | `AIza…` (ร่วมกับเสียง Gemini) | 3.5 Flash-Lite 0.30/2.50 · 3.8 Flash 0.75/3.75 (ถึง 31 ธ.ค. 26) · 4 Argon 2/10 (ถึง 30 พ.ย. 26) |

- ไม่ใช้ชั้น OpenAI-compatible ของ Anthropic — เอกสารบอกว่ามีไว้ทดสอบ
- `reasoning_effort`: grok-4.3 → `none` · grok-4.7 ไม่ส่ง (เอกสารไม่ระบุ) · Gemini → `minimal`
- Claude: `output_config.effort = low`, `max_tokens 2000`, ข้อความแรกต้องเป็น user และสลับฝั่ง
- เลิกแล้ว ห้ามใส่: grok-4.5/4.6/4.20 (ถูกแทน), gemini-3.5/3.6/3.7-flash (redirect)

## ตัวถอดเสียง (`lib/ai/stt_engine.dart`)

`auto` = ตามสมอง (Claude/Gemini/ในเครื่อง → ถอดในเครื่อง · Grok → Grok STT · ที่เหลือทางเดียวกับสมอง)
· อื่น ๆ: ในเครื่อง · OpenAI gpt-transcribe · ElevenLabs `scribe_v2` ($0.22/ชม.) · Grok `grok-voice-transcribe-2.0` (รองรับไทย)

## ElevenLabs (`lib/ai/eleven_tuning.dart`, `premium_tts.dart`)

- v4 → `text-to-dialogue`: `settings.stability`, `settings.similarity` เท่านั้น
- v3 → `text-to-speech`: `voice_settings` (stability, similarity_boost, style, use_speaker_boost, speed 0.7–1.2)
- ทั้งคู่: `audio_effects` (filter_preset_id, environment_id, background_noise_id, distance — ไม่เพิ่มราคา),
  `apply_text_normalization`, `seed`, แท็กอารมณ์นำหน้า `[warmly]`
- แคตตาล็อกเอฟเฟกต์: `GET /v1/audio-effects/catalog` · แผน/เครดิต: `GET /v1/user/subscription`
- โคลนเสียงเจ้าของ: `POST /v1/voices/add` (Instant Voice Clone, แผน Starter ขึ้นไป) · ลบ: `DELETE /v1/voices/{id}`
  ใช้ได้ทั้งช่อง "คุย" และ "รับสาย"
