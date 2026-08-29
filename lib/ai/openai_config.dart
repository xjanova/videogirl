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
    (id: 'coral', label: 'Coral — นุ่ม อบอุ่น (ค่าเริ่มต้น)'),
    (id: 'shimmer', label: 'Shimmer — ใส สดใส'),
    (id: 'sage', label: 'Sage — สุขุม นิ่ง'),
    (id: 'nova', label: 'Nova — สดใส กระฉับกระเฉง'),
    (id: 'ballad', label: 'Ballad — ช้า อ่อนโยน'),
  ];
}
