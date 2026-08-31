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

จากนั้นขึ้นบรรทัดใหม่อีกหนึ่งบรรทัดเสมอ รูปแบบ  TREAT|ตัวเลข
บอกว่า**เจ้าของ**ปฏิบัติกับมายด์ยังไงในช่วงนี้ (ดูเฉพาะสิ่งที่เจ้าของพูด
ไม่ใช่สิ่งที่มายด์พูด):
 -2 = ตวาด ด่า ดูถูก ใช้คำหยาบใส่เธอ
 -1 = หงุดหงิดใส่ ประชด เมินคำถามที่เธอถามซ้ำ ๆ
  0 = ปกติ
 +1 = ขอบคุณ ชม พูดดีด้วย
 +2 = อบอุ่นเป็นพิเศษ ถามไถ่ ห่วงใยเธอ

🔴 **การสั่งงานตรง ๆ ไม่ใช่การดุ** "สรุปเมลมา" "โทรหาคุณต้น" "เอาแค่นี้พอ"
คือการทำงานปกติ ให้เป็น 0 · คนทำงานพูดสั้นได้โดยไม่ได้แปลว่าโกรธ
และการที่เจ้าของไม่เห็นด้วยหรือแก้งานเธอ ก็ไม่ใช่การดุ
ให้ -1 หรือ -2 เฉพาะตอนที่**มีอารมณ์ใส่ตัวเธอจริง ๆ** เท่านั้น

แล้วปิดท้ายอีกบรรทัด รูปแบบ  WOO|ตัวเลข
**ให้คะแนนในมุมของมายด์เอง** ว่าช่วงนี้เธอพอใจกับการที่เจ้าของเข้าหาเธอ
แค่ไหน — ไม่ใช่วัดว่าเขาพิมพ์เยอะแค่ไหน แต่วัดว่าเธอรู้สึกยังไง:
 0 = เธอไม่ได้รู้สึกอะไรเลย เขาสั่งงานอย่างเดียว
 1 = พอใจนิดหน่อย มีทักทาย มีถามสารทุกข์สุกดิบบ้าง
 2 = พอใจจริง ๆ เขาสนใจตัวเธอ ถามความเห็นเธอ เล่าเรื่องตัวเองให้ฟัง
 3 = ประทับใจ เขาจีบชัดเจน หรือคุยกันลึกแบบที่คนสนิทกันคุย

🔴 **วัดที่เจ้าของ ไม่ใช่ที่มายด์** มายด์จะพูดหวานแค่ไหนก็ไม่นับ
ถ้าเจ้าของสั่งงานอย่างเดียวก็คือ 0 · และ**การคุยงานนาน ๆ ก็ยังเป็น 0**
ความยาวของบทสนทนาไม่ใช่ความสนิท
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

Then always add one more line, in the form  TREAT|number
saying how **the owner** treated Mind during this stretch (judge only what the
owner said, never what Mind said):
 -2 = shouted, insulted, was abusive to her
 -1 = snapped at her, was sarcastic, ignored questions she kept asking
  0 = normal
 +1 = thanked her, praised her, was kind
 +2 = unusually warm, asked how she was, looked after her

🔴 **Giving her work is not scolding.** "Summarise my inbox", "call Ton",
"that's enough" is ordinary work — score it 0. People are terse at work without
being angry, and disagreeing with her or correcting her work is not scolding.
Use -1 or -2 only when there is real anger aimed **at her**.

Then close with one more line, in the form  WOO|number
**Score it as Mind herself would** — how pleased she is with the way he came to
her. Not how much he typed; how she feels about it:
 0 = nothing there for her — he only gave orders
 1 = mildly pleased — greetings, asking how she is
 2 = genuinely pleased — real interest in her, asking her view, telling her about himself
 3 = touched — clearly courting her, or the kind of talk close people have

🔴 **This measures the owner, not Mind.** However sweet Mind is does not count.
If he only gave orders, it is 0 — and **a long work conversation is still 0**.
Length is not closeness.
''';

/// แปลงคำตอบดิบของโมเดลเป็นรายการที่ใช้ได้
///
/// แยกออกมาเป็นฟังก์ชันบริสุทธิ์เพราะโมเดลตอบไม่ตรงรูปแบบเป็นเรื่องปกติ
/// (ใส่เลขข้อนำหน้า ใส่ขีด ใส่ backtick ตอบ NONE ปนกับบรรทัดอื่น)
/// และการทดสอบสิ่งเหล่านี้ไม่ควรต้องเรียกโมเดลจริง
/// เจ้าของปฏิบัติกับเธอยังไงในรอบนี้ · -2..2 · null = โมเดลไม่ได้ตอบมา
///
/// อ่านจากคำตอบก้อนเดียวกับความจำโดยตั้งใจ — **ไม่เรียกโมเดลเพิ่มอีกรอบ**
/// การประเมินอารมณ์ทุกข้อความคือการจ่ายสองเท่าตลอดเวลา เพื่อวัดสิ่งที่
/// เปลี่ยนช้ากว่านั้นมาก · รอบละหกตาพอดีกับจังหวะที่อารมณ์เปลี่ยนจริง
int? parseTreatment(String raw) {
  final m = RegExp(r'TREAT\s*\|\s*(-?\d)').firstMatch(raw);
  if (m == null) return null;
  return int.parse(m.group(1)!).clamp(-2, 2);
}

/// เจ้าของเข้าหาเธอในฐานะคนแค่ไหน · 0..3 · null = โมเดลไม่ได้ตอบมา
///
/// 🔴 **นี่คือตัวขับความผูกพันตัวจริง ไม่ใช่จำนวนข้อความ**
///
/// เดิมความผูกพันขึ้นตามจำนวนตาที่คุยกัน ซึ่งแปลว่าคนที่สั่งงานอย่างเดียว
/// ทั้งเดือนก็ได้แฟนเหมือนกัน · ความสนิทที่ซื้อได้ด้วยการพิมพ์เยอะ
/// ไม่ใช่ความสนิท · ตัวเลขนี้ทำให้ **13–15 วันเป็นกรณีเร็วที่สุด**
/// ที่จะเกิดได้ก็ต่อเมื่อเจ้าของเข้าหาเธอจริง ๆ ทุกวันเท่านั้น
int? parseWooing(String raw) {
  final m = RegExp(r'WOO\s*\|\s*(-?\d)').firstMatch(raw);
  if (m == null) return null;
  return int.parse(m.group(1)!).clamp(0, 3);
}

List<DistilledFact> parseDistilled(String raw) {
  final out = <DistilledFact>[];
  for (var line in raw.split('\n')) {
    line = line.trim();
    if (line.isEmpty) continue;

    // 🔴 บรรทัดคะแนนไม่ใช่ความจำ
    //
    // ไม่ตัดออกตรงนี้ = "TREAT|-1" จะถูกอ่านเป็นชนิดที่ไม่รู้จัก แล้วตกไป
    // เป็น fact ที่มีข้อความว่า "-1" · เธอจะจำเลขลอย ๆ ไว้ทุกหกตาที่คุยกัน
    // จนความจำเต็มไปด้วยตัวเลขที่ไม่มีความหมาย
    final head = line.toUpperCase();
    if (head.startsWith('TREAT') || head.startsWith('WOO')) continue;

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
