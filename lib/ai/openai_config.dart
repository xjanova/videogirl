/// ตั้งค่าการต่อ OpenAI
///
/// คีย์ **ไม่เคย** อยู่ในซอร์ส — repo นี้เป็น public การฝังคีย์ลงไปคือการแจกคีย์
/// ส่งเข้ามาตอน build แทน:
///
///   flutter run --dart-define=OPENAI_API_KEY=sk-...
///   flutter build apk --dart-define-from-file=secrets.json
///
/// ถ้าไม่ได้ส่งเข้ามา แอปยังเปิดได้ปกติ แต่มายด์จะตอบด้วยประโยคสำเร็จรูป
/// และไม่มีเสียง (ดู [configured])
library;

abstract final class OpenAiConfig {
  static const apiKey = String.fromEnvironment('OPENAI_API_KEY');

  /// สมองของเธอ — ค่าเริ่มต้นคือรุ่นที่เจ้าของเลือก
  static const brainModel =
      String.fromEnvironment('OPENAI_MODEL', defaultValue: 'gpt-5.6-sol');

  static const ttsModel =
      String.fromEnvironment('OPENAI_TTS_MODEL', defaultValue: 'gpt-4o-mini-tts');

  /// เสียงรับสายแบบเรียลไทม์ (ยังไม่ได้ต่อ — ดู docs/telephony.md)
  static const realtimeModel =
      String.fromEnvironment('OPENAI_REALTIME_MODEL', defaultValue: 'gpt-realtime-2.1');

  /// ถอดเสียงปลายสายเป็นข้อความ
  ///
  /// ตั้งไว้ที่ `whisper-1` โดยตั้งใจ ทั้งที่มีรุ่นใหม่กว่า — รุ่นนี้เป็นรุ่น
  /// ที่**ทุกบัญชีเรียกได้แน่นอน** ส่วนตระกูล gpt-4o-transcribe ต้องเช็ค
  /// กับบัญชีก่อน · เลือกผิดจะได้ 404 ตอนสายจริง ซึ่งผู้ใช้เห็นเป็น
  /// "เธอฟังไม่ออก" ไม่ใช่ "เรียกโมเดลไม่ได้"
  ///
  /// เปลี่ยนได้ตอน build: --dart-define=OPENAI_STT_MODEL=gpt-4o-mini-transcribe
  static const sttModel =
      String.fromEnvironment('OPENAI_STT_MODEL', defaultValue: 'whisper-1');

  static const baseUrl = 'https://api.openai.com/v1';

  static bool get configured => apiKey.isNotEmpty;

  /// รายการที่ให้เลือกในหน้าตั้งค่า — ยืนยันแล้วว่าบัญชีเรียกได้จริง
  /// (ดึงจาก GET /v1/models เมื่อ 2026-08-29 ไม่ได้เดาชื่อ)
  /// ชื่อรุ่นเป็นวิสามานยนาม ไม่ต้องแปล · คำอธิบายอยู่ใน i18n/enum_labels.dart
  /// ตรวจกับเอกสาร OpenAI เมื่อ 2026-10-06 (developers.openai.com/api/docs/models)
  /// · ทุกตัวใช้กับ /v1/chat/completions ได้ · เรียงจากค่าตั้งต้น → ใหม่ → ถูก → แพง
  ///
  /// ถอดออก: `gpt-5.5` (เก่ากว่าและแพงกว่า 5.6 Sol) · `gpt-5.4-mini` และ
  /// `gpt-5.6-luna` (มี 6 Luna ที่ถูกกว่าแทน) · ใครเลือกไว้แล้วยังใช้ต่อได้
  /// ผ่านช่อง "พิมพ์ชื่อรุ่นเอง" เพราะ OpenAI ยังไม่ได้ปิดรุ่นพวกนั้น
  static const brainChoices = <({String id, String label})>[
    (id: 'gpt-5.6-sol', label: '5.6 Sol'),
    (id: 'gpt-6.1-sol', label: '6.1 Sol'),
    (id: 'gpt-5.6-terra', label: '5.6 Terra'),
    (id: 'gpt-6-luna', label: '6 Luna'),
    (id: 'gpt-6-astra', label: '6 Astra'),
  ];

  /// ระดับการคิดภายใน (`reasoning_effort`) ที่จะขอ · null = ไม่ส่ง
  ///
  /// 🔴 ต้องส่งเอง · ไม่ส่ง = รุ่น 5.6/6 คิดภายในระดับ medium ซึ่งกินโควตา
  /// `max_completion_tokens` เดียวกับคำตอบ (เอกสาร: นับรวม reasoning tokens)
  /// · เพดานคำตอบ 600 ของแอปจึงหมดไปกับการคิดได้ แล้วเธอตอบกลับมาว่างเปล่า
  /// และงานคุยเล่นไม่ต้องคิดลึก การคิดยิ่งมากยิ่งรอนาน
  ///
  /// - 6 Astra / 6.1 Sol ไม่รับ `none` (ตอบ 400) → ต่ำสุดคือ `low`
  /// - 5.x ที่มีจุด (5.1 ขึ้นไป) และ 6 อื่น ๆ → `none`
  /// - `gpt-5` / `gpt-5-mini` / `gpt-5-nano` รุ่นแรกไม่มี `none` → `minimal`
  /// - รุ่นอื่น (gpt-4o, รุ่นที่พิมพ์เอง) → ไม่ส่ง ไม่งั้นรุ่นที่ไม่ใช่สาย
  ///   reasoning ตอบ 400 "Unsupported parameter"
  static String? effortFor(String model) {
    final id = model.trim().toLowerCase();
    if (id.contains('-chat')) return null;
    if (id.startsWith('gpt-6-astra') || id.startsWith('gpt-6.1-sol')) return 'low';
    if (RegExp(r'^gpt-5\.\d').hasMatch(id) || id.startsWith('gpt-6')) return 'none';
    if (RegExp(r'^gpt-5(-mini|-nano)?(-\d{4}-\d{2}-\d{2})?$').hasMatch(id)) {
      return 'minimal';
    }
    return null;
  }

  /// เสียงของ gpt-4o-mini-tts ที่เข้ากับบุคลิกมายด์
  /// marin กับ cedar มาก่อน — เอกสาร OpenAI แนะนำสองตัวนี้ว่าคุณภาพดีที่สุด
  /// (ตรวจ 2026-10-06) · ทุกตัวในรายการใช้กับ gpt-4o-mini-tts ได้
  static const voiceChoices = <String>[
    'marin',
    'cedar',
    'coral',
    'shimmer',
    'sage',
    'nova',
    'ballad',
  ];

  /// โมเดลเสียงที่บัญชีนี้เรียกได้ (ยืนยันจาก GET /v1/models 2026-08-29)
  ///
  /// มีแค่ gpt-4o-mini-tts ที่รับ `instructions` สั่งอารมณ์เสียงได้
  /// ตระกูล tts-1 เก่ากว่าและไม่รับ จึงเสียคำสั่งน้ำเสียงไปเปล่า ๆ
  ///
  /// 🔴 เหลือตัวเดียวโดยตั้งใจ (ตรวจ 2026-10-06) · `tts-1` / `tts-1-hd` ถูก
  /// ประกาศเลิกใช้ (ปิด 2027-01-06) และ**ใช้กับเสียง ballad/marin/cedar
  /// ไม่ได้** (ตอบ error) · ค่าที่เคยเลือกไว้ถูกย้ายมาตัวนี้ตอนโหลด ([migrateTts])
  ///
  /// ⚠️ ตัวนี้ก็ถูกประกาศปิด 2027-01-06 เหมือนกัน และ OpenAI ยังไม่มีรุ่นแทน
  /// บน /v1/audio/speech (ตัวแทนที่ประกาศเป็นรุ่น Realtime) · ต้องย้ายก่อนวันนั้น
  static const ttsChoices = <String>['gpt-4o-mini-tts'];

  /// รุ่นเสียงที่เลิกเสนอแล้ว → รุ่นที่ใช้แทน
  static String migrateTts(String model) =>
      model == 'tts-1' || model == 'tts-1-hd' ? 'gpt-4o-mini-tts' : model;

  /// โมเดลคุยสด (speech-to-speech) สำหรับตอนรับสาย/โทรออกจริง
  /// ยังไม่ได้ต่อ — ดู docs/telephony.md
  static const realtimeChoices = <({String id, String label})>[
    (id: 'gpt-realtime-2.1', label: 'Realtime 2.1'),
    (id: 'gpt-realtime-2.1-mini', label: 'Realtime 2.1 mini'),
  ];

  /// `gpt-realtime` ถูกประกาศปิด 2027-01-20 → ถอดออกจากรายการ ตัวแทนคือ 2.1
  static String migrateRealtime(String model) =>
      model == 'gpt-realtime' ? 'gpt-realtime-2.1' : model;

  /// โมเดลที่รับพารามิเตอร์ `instructions` — ตัวอื่นส่งไปก็ไม่มีผล
  static bool supportsInstructions(String ttsModel) =>
      ttsModel.startsWith('gpt-4o') || ttsModel.startsWith('gpt-audio');
}
