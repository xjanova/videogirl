/// ข้อความเสียงในแจ้งเตือนแชท · แยกจาก chat_inbox.dart เพราะคำไทยในนี้คือคำที่ต้อง**จับให้ได้** ไม่ใช่ข้อความบนจอ
library;

/// ข้อความเสียงในแจ้งเตือนแชท · แอปไม่ส่งไฟล์เสียงมา มีแต่คำบอก เช่น WhatsApp "🎤 Voice message (0:12)" ·
/// LINE / Messenger "Ann sent a voice message." · ไทย "🎤 ข้อความเสียง (0:12)" "Ann ส่งข้อความเสียง"
///
/// 🔴 ต้องเป็นทั้งข้อความ ไม่ใช่แค่มีคำนี้อยู่ข้างใน · "ส่ง voice message มาหน่อย" คือข้อความพิมพ์ ไม่ใช่เสียง
abstract final class VoiceNote {
  static const _mic = ['🎤', '🎙'];
  static final _duration = RegExp(r'\(?\b(\d{1,2}:\d{2})\b\)?');
  static final _word = RegExp(
    r'voice (message|note|clip)|audio( message)?|ข้อความเสียง|คลิปเสียง|sprachnachricht|mensaje de voz|'
    r'message vocal|音声メッセージ|语音|語音|음성 메시지',
    caseSensitive: false,
  );
  static final _whole = RegExp(
    r'^(.{1,40}\s)?(sent (you )?(a |an )?)?(voice (message|note|clip)|audio message)\.?$|'
    r'^(.{1,40}\s)?ส่ง(ข้อความเสียง|คลิปเสียง)(ถึงคุณ|ให้คุณ)?(แล้ว)?$|'
    r'^(ข้อความเสียง|คลิปเสียง|voice message|audio)\s*(\(?\d{1,2}:\d{2}\)?)?$',
    caseSensitive: false,
  );

  static bool matches(String text) {
    final t = text.trim();
    if (t.isEmpty || t.length > 60) return false;
    for (final m in _mic) {
      if (t.startsWith(m)) {
        final rest = t.substring(m.length).replaceFirst('️', '').trim();
        // 🎤 เฉย ๆ (แอปแนบเสียงมาแต่ไม่มีคำ) · มีความยาวเสียง · หรือคำว่าข้อความเสียงในภาษาใดก็ได้
        return rest.isEmpty || _duration.hasMatch(rest) || _word.hasMatch(rest);
      }
    }
    return _whole.hasMatch(t);
  }

  /// ความยาว "0:12" · ไม่รู้ = ว่าง
  static String duration(String text) => _duration.firstMatch(text)?.group(1) ?? '';
}
