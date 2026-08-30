/// สกัด "สิ่งที่ควรจำ" ออกจากบทสนทนา
///
/// **ทำไมไม่จำทุกอย่าง:** บทสนทนากับข้อเท็จจริงมีอายุไม่เท่ากัน
/// "บ่ายนี้ว่างไหม" หมดความหมายในไม่กี่ชั่วโมง แต่ "เจ้าของแพ้กุ้ง" อยู่ตลอดไป
/// เก็บทุกอย่างแล้วยัดเข้า prompt = จ่าย token ให้ขยะทุกครั้งที่คุย
/// และเรื่องสำคัญจะจมอยู่ใต้กองเรื่องที่ไม่สำคัญ
///
/// **ทำไมสกัดเป็นรอบ ไม่ใช่ทุกข้อความ:** การสกัดคือการเรียกโมเดลอีกครั้ง
/// ทำทุกข้อความ = จ่ายสองเท่าและช้าสองเท่าตลอดเวลา ทั้งที่คนคุยกันสิบประโยค
/// อาจมีเรื่องที่ควรจำแค่เรื่องเดียว
library;

import 'package:flutter/foundation.dart';

import 'mind_memory.dart';

/// คุยกันกี่ตาถึงจะสกัดหนึ่งรอบ
///
/// ถี่กว่านี้เปลืองโดยไม่ได้อะไรเพิ่ม ห่างกว่านี้เรื่องที่ควรจำจะหลุดออกจาก
/// หน้าต่างบทสนทนาไปก่อนที่จะได้สกัด
const kDistillEvery = 6;

/// สิ่งที่สกัดได้หนึ่งข้อ ก่อนจะถูกกลั่นเข้าความจำจริง
@immutable
class DistilledFact {
  const DistilledFact(this.kind, this.text);
  final MemoryKind kind;
  final String text;
}

/// คำสั่งที่ส่งให้โมเดล
///
/// สั่งห้ามใส่ความลับไว้ด้วย **ทั้งที่มีด่านกรองอยู่แล้ว** — กันสองชั้น
/// เพราะด่านกรองเป็นการจับรูปแบบ ซึ่งไม่มีทางครอบคลุมทุกแบบ
/// การไม่ให้มันหลุดออกมาตั้งแต่ต้นทางถูกกว่าการไล่จับปลายทาง
String distillPrompt(bool thai) => thai
    ? '''
อ่านบทสนทนาข้างล่าง แล้วสรุปเฉพาะ**ข้อเท็จจริงที่อยู่ทน**เกี่ยวกับเจ้าของ
ที่ยังไม่เคยรู้มาก่อน

ตอบบรรทัดละหนึ่งข้อ รูปแบบ  ชนิด|ข้อความ
ชนิดมีสี่แบบ: fact | preference | routine | person
- fact = ข้อเท็จจริงที่ไม่เปลี่ยน (ชื่อ อาชีพ แพ้อะไร)
- preference = ชอบ/ไม่ชอบ วิธีที่อยากให้ตอบ
- routine = สิ่งที่ทำซ้ำ ๆ ตามเวลา
- person = คนรอบตัวว่าใครเป็นใคร

กฎ:
- เขียนสั้น หนึ่งบรรทัดหนึ่งเรื่อง ไม่เกิน 200 ตัวอักษร
- เอาเฉพาะเรื่องที่จะยังจริงในอีกเดือนหนึ่ง ไม่เอานัดหมายเฉพาะวัน
- **ห้ามใส่รหัสผ่าน เลขบัตร OTP เลขบัญชี หรือความลับใด ๆ เด็ดขาด**
- ถ้าไม่มีอะไรใหม่ที่ควรจำ ตอบคำเดียวว่า NONE
'''
    : '''
Read the conversation below and extract only **durable facts** about the owner
that were not already known.

Answer one per line, in the form  kind|text
kind is one of: fact | preference | routine | person
- fact = unchanging facts (name, job, allergies)
- preference = likes/dislikes, how they want to be answered
- routine = things they do repeatedly on a schedule
- person = who the people around them are

Rules:
- Keep each line short, one thing per line, under 200 characters
- Only things still true in a month — not one-off appointments
- **Never include passwords, card numbers, OTPs, account numbers or any secret**
- If there is nothing new worth remembering, answer with the single word NONE
''';

/// แปลงคำตอบดิบของโมเดลเป็นรายการที่ใช้ได้
///
/// แยกออกมาเป็นฟังก์ชันบริสุทธิ์เพราะโมเดลตอบไม่ตรงรูปแบบเป็นเรื่องปกติ
/// (ใส่เลขข้อนำหน้า ใส่ขีด ใส่ backtick ตอบ NONE ปนกับบรรทัดอื่น)
/// และการทดสอบสิ่งเหล่านี้ไม่ควรต้องเรียกโมเดลจริง
List<DistilledFact> parseDistilled(String raw) {
  final out = <DistilledFact>[];
  for (var line in raw.split('\n')) {
    line = line.trim();
    if (line.isEmpty) continue;

    // ลอกสิ่งที่โมเดลชอบใส่มาเอง: ``` , -, *, 1. , 1)
    line = line.replaceAll('`', '').trim();
    line = line.replaceFirst(RegExp(r'^[-*•]\s*'), '');
    line = line.replaceFirst(RegExp(r'^\d+[.)]\s*'), '');
    if (line.isEmpty) continue;

    if (line.toUpperCase() == 'NONE') continue;

    final bar = line.indexOf('|');
    // ไม่มีขีดคั่น = โมเดลลืมใส่ชนิด · ยังเอาข้อความไว้ ถือเป็น fact
    // ทิ้งไปเลยจะเสียของที่ถูกต้องเพียงเพราะรูปแบบไม่เป๊ะ
    final kind = bar < 0
        ? MemoryKind.fact
        : MemoryKind.parse(line.substring(0, bar).trim().toLowerCase());
    final text = (bar < 0 ? line : line.substring(bar + 1)).trim();

    if (text.isEmpty || text.length > kMemoryMaxChars) continue;
    // ด่านที่สอง — ต้นทางสั่งห้ามแล้ว แต่ห้ามเชื่อว่ามันเชื่อฟัง
    if (looksLikeSecret(text)) {
      debugPrint('distill: ทิ้งบรรทัดที่เข้าข่ายความลับ');
      continue;
    }
    out.add(DistilledFact(kind, text));
  }
  return out;
}

/// ประกอบบทสนทนาให้โมเดลอ่าน
String conversationBlock(
  List<({bool fromHer, String text})> turns, {
  required String me,
  required String her,
}) =>
    turns.map((t) => '${t.fromHer ? her : me}: ${t.text}').join('\n');
