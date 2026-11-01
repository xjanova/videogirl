/// แท็ก `[[ทำในเครื่อง: …]]` ที่เธอเขียนในแชทเมื่อเจ้าของสั่งงานที่ต้องทำในมือถือ
///
/// สอนไว้ที่ MindPersona.phoneControlBlock · MindState อ่านแล้วส่งให้ PhoneAgent ·
/// แท็กไม่ขึ้นจอ ไม่ถูกอ่านออกเสียง
library;

/// คำของเจ้าของเรื่องกล้อง · ตัดสินในเครื่อง ไม่ใช่จากโมเดล (ดู MindEyes)
abstract final class EyesWords {
  /// ขอให้เปิด/ดู/ถ่าย · ไม่มีคำเหล่านี้ = โมเดลคิดเปิดเอง หรือถูกข้อความจากที่อื่นสั่ง
  /// "ดู" เดี่ยว ๆ ไม่นับ เพราะ "ดูข่าว" "ดูแรม" ไม่ใช่การขอให้มอง · "ดูหน้า" "ดูหน่อย" "ดูนี่" นับ
  static final ask = RegExp(
    r'กล้อง|ถ่าย|เซลฟี่|มอง|เห็น(?!ด้วย)|ดู(หน้า|หน่อย|นี่|นี้|นั่น|ซิ|สิ|ดิ|ที|ฉัน|ผม|เรา|พี่|ชุด|รูป|ภาพ)|'
    r'camera|photo|picture|selfie|look(?!\s+up)|\bsee\b',
    caseSensitive: false,
  );

  /// (?<!เ) เพราะ "ปิดกล้อง" ซ้อนอยู่ใน "เปิดกล้อง" · ไม่กันคือสั่งเปิดแล้วปิดทันที
  static final _off = RegExp(
    r'(?<!เ)ปิดกล้อง|(?<!เ)ปิดตา|เลิกมอง|หยุดมอง|ไม่ต้องมอง|พอแล้วไม่ต้องดู|camera off|close the camera|turn off the camera|stop looking',
    caseSensitive: false,
  );

  /// สั่งปิดกล้อง · ไม่ผ่านโมเดล · ต้องปิดทันที
  static bool off(String text) => _off.hasMatch(text);
}

/// แท็กของที่เธอทำได้ทันทีไม่ต้องใช้มือ: `[[เปิดแอป: YouTube]]` · `[[เปิดเสียงสาย: ชื่อ]]` · `[[ถ่ายรูป: หลัง]]`
abstract final class QuickTag {
  static final _app = RegExp(r'\[\[\s*(เปิดแอป|เปิดแอพ|open app)\s*[:：]\s*([^\]\n]{1,80})\]\]', caseSensitive: false);
  static final _recording =
      RegExp(r'\[\[\s*(เปิดเสียงสาย|play recording)\s*(?:[:：]\s*([^\]\n]{0,80}))?\]\]', caseSensitive: false);
  static final _photo = RegExp(r'\[\[\s*(ถ่ายรูป|take photo)\s*(?:[:：]\s*([^\]\n]{0,20}))?\]\]', caseSensitive: false);

  /// [app] = ชื่อแอป · [recording] = คนที่จะเปิดเสียงสาย ('' = ล่าสุด · null = ไม่มีแท็ก) ·
  /// [photo] = กล้องที่จะถ่าย ('หลัง'/'back' = กล้องหลัง · null = ไม่มีแท็ก)
  static ({String text, String? app, String? recording, String? photo}) parse(String reply) {
    final app = _app.firstMatch(reply)?.group(2)?.trim();
    final rec = _recording.firstMatch(reply);
    final photo = _photo.firstMatch(reply);
    final text = reply
        .replaceAll(_app, '')
        .replaceAll(_recording, '')
        .replaceAll(_photo, '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return (
      text: text,
      app: app == null || app.isEmpty ? null : app,
      recording: rec == null ? null : (rec.group(2) ?? '').trim(),
      photo: photo == null ? null : (photo.group(2) ?? '').trim(),
    );
  }

  static bool backCamera(String which) => RegExp(r'หลัง|back|rear', caseSensitive: false).hasMatch(which);
}

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
