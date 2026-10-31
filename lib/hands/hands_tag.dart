/// แท็ก `[[ทำในเครื่อง: …]]` ที่เธอเขียนในแชทเมื่อเจ้าของสั่งงานที่ต้องทำในมือถือ
///
/// สอนไว้ที่ MindPersona.phoneControlBlock · MindState อ่านแล้วส่งให้ PhoneAgent ·
/// แท็กไม่ขึ้นจอ ไม่ถูกอ่านออกเสียง
library;

abstract final class HandsTag {
  static final _tag = RegExp(
    r'\[\[\s*(ทำในเครื่อง|ใช้เครื่อง|ทำในมือถือ|phone|on phone|do on phone)\s*[:：]\s*([^\]\n]{1,600})\]\]',
    caseSensitive: false,
  );

  /// [text] = ข้อความที่เหลือ (ตัดแท็กออก) · [goal] = งานที่สั่ง (null = ไม่มีแท็ก)
  static ({String text, String? goal}) parse(String reply) {
    final m = _tag.firstMatch(reply);
    final goal = m?.group(2)?.trim();
    final text = reply.replaceAll(_tag, '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return (text: text, goal: goal == null || goal.isEmpty ? null : goal);
  }
}
