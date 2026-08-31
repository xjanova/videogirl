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
  static const brainChoices = <({String id, String label})>[
    (id: 'gpt-5.6-sol', label: 'Sol'),
    (id: 'gpt-5.6-luna', label: 'Luna'),
    (id: 'gpt-5.6-terra', label: 'Terra'),
    (id: 'gpt-5.5', label: '5.5'),
    (id: 'gpt-5.4-mini', label: '5.4 mini'),
  ];

  /// เสียงของ gpt-4o-mini-tts ที่เข้ากับบุคลิกมายด์
  static const voiceChoices = <String>[
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
  static const ttsChoices = <String>['gpt-4o-mini-tts', 'tts-1-hd', 'tts-1'];

  /// โมเดลคุยสด (speech-to-speech) สำหรับตอนรับสาย/โทรออกจริง
  /// ยังไม่ได้ต่อ — ดู docs/telephony.md
  static const realtimeChoices = <({String id, String label})>[
    (id: 'gpt-realtime-2.1', label: 'Realtime 2.1'),
    (id: 'gpt-realtime-2.1-mini', label: 'Realtime 2.1 mini'),
    (id: 'gpt-realtime', label: 'Realtime'),
  ];

  /// โมเดลที่รับพารามิเตอร์ `instructions` — ตัวอื่นส่งไปก็ไม่มีผล
  static bool supportsInstructions(String ttsModel) =>
      ttsModel.startsWith('gpt-4o') || ttsModel.startsWith('gpt-audio');
}
