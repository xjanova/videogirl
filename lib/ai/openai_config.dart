/// ตั้งค่าการต่อ OpenAI
///
/// คีย์ **ไม่เคย** อยู่ในซอร์ส — repo นี้เป็น public การฝังคีย์ลงไปคือการแจกคีย์
/// ส่งเข้ามาตอน build แทน:
///
///   flutter run --dart-define=OPENAI_API_KEY=sk-...
///   flutter build apk --dart-define-from-file=secrets.json
///
/// ถ้าไม่ได้ส่งเข้ามา แอปยังเปิดได้ปกติ แต่มินเดะจะตอบด้วยประโยคสำเร็จรูป
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

  static const baseUrl = 'https://api.openai.com/v1';

  static bool get configured => apiKey.isNotEmpty;

  /// รายการที่ให้เลือกในหน้าตั้งค่า — ยืนยันแล้วว่าบัญชีเรียกได้จริง
  /// (ดึงจาก GET /v1/models เมื่อ 2026-08-29 ไม่ได้เดาชื่อ)
  static const brainChoices = <({String id, String label, String hint})>[
    (id: 'gpt-5.6-sol', label: 'Sol', hint: 'ฉลาดที่สุด เหมือนคนที่สุด · ค่าเริ่มต้น'),
    (id: 'gpt-5.6-luna', label: 'Luna', hint: 'รุ่น 5.6 อีกบุคลิก'),
    (id: 'gpt-5.6-terra', label: 'Terra', hint: 'รุ่น 5.6 อีกบุคลิก'),
    (id: 'gpt-5.5', label: '5.5', hint: 'รุ่นก่อนหน้า ถูกกว่า'),
    (id: 'gpt-5.4-mini', label: '5.4 mini', hint: 'เร็วและถูกที่สุด'),
  ];

  /// เสียงของ gpt-4o-mini-tts ที่เข้ากับบุคลิกมินเดะ
  static const voiceChoices = <({String id, String label})>[
    (id: 'coral', label: 'Coral — นุ่ม อบอุ่น'),
    (id: 'shimmer', label: 'Shimmer — ใส ฟังชัด'),
    (id: 'sage', label: 'Sage — สุขุม เป็นทางการ'),
    (id: 'nova', label: 'Nova — สดใส กระฉับกระเฉง'),
    (id: 'ballad', label: 'Ballad — ช้า อ่อนโยน'),
  ];

  /// โมเดลเสียงที่บัญชีนี้เรียกได้ (ยืนยันจาก GET /v1/models 2026-08-29)
  ///
  /// มีแค่ gpt-4o-mini-tts ที่รับ `instructions` สั่งอารมณ์เสียงได้
  /// ตระกูล tts-1 เก่ากว่าและไม่รับ จึงเสียคำสั่งน้ำเสียงไปเปล่า ๆ
  static const ttsChoices = <({String id, String label, String hint})>[
    (
      id: 'gpt-4o-mini-tts',
      label: 'gpt-4o-mini-tts',
      hint: 'สั่งอารมณ์เสียงได้ · สมจริงที่สุด'
    ),
    (id: 'tts-1-hd', label: 'tts-1-hd', hint: 'คมกว่า แต่สั่งอารมณ์ไม่ได้'),
    (id: 'tts-1', label: 'tts-1', hint: 'เร็วและถูกที่สุด · สั่งอารมณ์ไม่ได้'),
  ];

  /// โมเดลคุยสด (speech-to-speech) สำหรับตอนรับสาย/โทรออกจริง
  /// ยังไม่ได้ต่อ — ดู docs/telephony.md
  static const realtimeChoices = <({String id, String label, String hint})>[
    (id: 'gpt-realtime-2.1', label: 'Realtime 2.1', hint: 'ดีเลย์ต่ำ คุณภาพสูงสุด'),
    (id: 'gpt-realtime-2.1-mini', label: 'Realtime 2.1 mini', hint: 'ถูกกว่า เร็วกว่า'),
    (id: 'gpt-realtime', label: 'Realtime', hint: 'รุ่นก่อนหน้า'),
  ];

  /// โมเดลที่รับพารามิเตอร์ `instructions` — ตัวอื่นส่งไปก็ไม่มีผล
  static bool supportsInstructions(String ttsModel) =>
      ttsModel.startsWith('gpt-4o') || ttsModel.startsWith('gpt-audio');
}
