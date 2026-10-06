/// แท็กท้ายคำตอบของน้องมายในสาย — วางสาย / แจ้งเรื่องด่วน
///
/// แยกไฟล์เพราะคำไทยในแท็ก (`วางสาย` `ด่วน`) ต้อง**จับให้ได้**จากคำตอบของโมเดล
/// ไม่ใช่ข้อความที่ผู้ใช้เห็น (ดู test/i18n_test.dart) · คำสั่งที่สอนโมเดลอยู่ใน
/// MindPersona.phoneStyle
library;

/// แท็กสั่งโทรออกในแชท — `[[โทร: เบอร์หรือชื่อในสมุด | เรื่องที่ต้องคุย]]`
///
/// เจ้าของ: "ทำส่วนโทรออกต่อ" · เธอเขียนแท็กนี้เมื่อเจ้าของสั่งให้โทรแทน · แอป**ไม่โทร
/// ทันที** · ขึ้นกล่องให้เจ้าของกดยืนยันก่อนทุกครั้ง (MindState.pendingCall)
abstract final class CallOutTag {
  static final _tag = RegExp(
    r'\[\[\s*(โทร|โทรออก|call)\s*[:：]\s*([^\]|\n]{1,80})\|([^\]\n]{1,400})\]\]',
    caseSensitive: false,
  );

  /// คำตอบที่ไม่มีแท็ก · ใคร (เบอร์/ชื่อ) · เรื่องที่ต้องคุย (null = ไม่ได้สั่งโทร)
  static ({String text, String? target, String? task}) parse(String reply) {
    final m = _tag.firstMatch(reply);
    if (m == null) return (text: reply, target: null, task: null);
    final text = reply.replaceAll(_tag, '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return (text: text, target: m.group(2)!.trim(), task: m.group(3)!.trim());
  }
}

/// แท็กท้ายคำตอบในสาย (ทางเดิม · ไม่มีเครื่องมือ) — ดู MindPersona.phoneStyle
abstract final class CallTags {
  static final _hang = RegExp(r'\[\[\s*(วางสาย|hang\s*up)\s*\]\]', caseSensitive: false);
  static final _urgent =
      RegExp(r'\[\[\s*(ด่วน|urgent)\s*[:：]\s*([^\]\n]{1,200})\]\]', caseSensitive: false);

  /// ข้อความที่จะพูด (ไม่มีแท็ก) · ขอวางสายไหม · เรื่องด่วน (null = ไม่ด่วน)
  static ({String text, bool hangUp, String? urgent}) parse(String reply) {
    final hang = _hang.hasMatch(reply);
    final m = _urgent.firstMatch(reply);
    final text = reply
        .replaceAll(_hang, '')
        .replaceAll(_urgent, '')
        // แท็กแปลก ๆ ที่โมเดลแต่งเอง · ไม่อ่านวงเล็บออกเสียงไม่ว่ากรณีไหน
        .replaceAll(RegExp(r'\[\[[^\]]*\]\]'), '')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
    return (text: text, hangUp: hang, urgent: m?.group(2)?.trim());
  }
}
