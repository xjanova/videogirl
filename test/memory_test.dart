import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/memory/distiller.dart';
import 'package:videogirl/memory/mind_memory.dart';

/// ความจำเป็นของที่**อยู่บนดิสก์และอยู่ตลอดไป** จึงต้องล็อกสองอย่าง:
/// สิ่งที่ห้ามจำ และการที่เจ้าของลบได้จริง
void main() {
  _distillerTests();

  group('ห้ามจำความลับ', () {
    test('รหัสผ่าน / OTP / API key ต้องไม่ถูกจำ', () {
      const bad = [
        'รหัสผ่านคือ hunter2',
        'password: correcthorse',
        'OTP 483920 ใช้ยืนยัน',
        'api key sk-proj-abcdefghijklmnopqrstuvwx',
        'token: ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345',
      ];
      for (final t in bad) {
        expect(looksLikeSecret(t), isTrue, reason: 'ควรกัน: $t');
      }
    });

    test('เลขบัตร / เลขบัญชี / เลขประชาชน ต้องไม่ถูกจำ', () {
      for (final t in [
        'บัตรเลข 4111 1111 1111 1111',
        'เลขบัญชี 1234567890123',
        'บัตรประชาชน 1234567890123',
      ]) {
        expect(looksLikeSecret(t), isTrue, reason: 'ควรกัน: $t');
      }
    });

    test('เรื่องธรรมดาต้องไม่ถูกกันผิด ๆ', () {
      for (final t in [
        'เจ้าของแพ้กุ้ง',
        'ประชุมทีมทุกวันอังคาร 10 โมง',
        'ชอบกาแฟดำ ไม่ใส่น้ำตาล',
        'คุณต้นเป็นหัวหน้าทีมออกแบบ',
        'ตื่นตีห้าทุกวัน',
      ]) {
        expect(looksLikeSecret(t), isFalse, reason: 'ไม่ควรกัน: $t');
      }
    });
  });

  group('เก็บและลบได้จริง', () {
    late Directory tmp;
    late MindMemory mem;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('memtest');
      mem = MindMemory(dir: tmp);
      await mem.load();
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('จำแล้วอ่านกลับได้หลังเปิดใหม่ — นี่คือสิ่งที่ของเดิมทำไม่ได้', () async {
      await mem.remember('เจ้าของแพ้กุ้ง');
      final again = MindMemory(dir: tmp);
      await again.load();
      expect(again.count, 1);
      expect(again.facts.first.text, 'เจ้าของแพ้กุ้ง');
    });

    test('ความลับถูกปฏิเสธ ไม่ใช่แค่ไม่โชว์', () async {
      expect(await mem.remember('รหัสผ่านคือ hunter2'), isFalse);
      expect(mem.count, 0, reason: 'ต้องไม่ลงดิสก์เลย ไม่ใช่เก็บแล้วซ่อน');
    });

    test('เรื่องซ้ำไม่จำสองรอบ แม้ช่องว่างต่างกัน', () async {
      expect(await mem.remember('ชอบกาแฟดำ'), isTrue);
      expect(await mem.remember('  ชอบกาแฟดำ  '), isFalse);
      expect(mem.count, 1);
    });

    test('ยาวเกินไม่จำ — ความจำคือข้อเท็จจริงหนึ่งบรรทัด ไม่ใช่บทสนทนา', () async {
      expect(await mem.remember('ก' * (kMemoryMaxChars + 1)), isFalse);
    });

    test('เจ้าของลบได้ และลบทั้งหมดได้', () async {
      await mem.remember('เรื่องหนึ่ง');
      await mem.remember('เรื่องสอง');
      await mem.forget(mem.facts.first.id);
      expect(mem.count, 1);
      await mem.forgetAll();
      expect(mem.count, 0);

      final again = MindMemory(dir: tmp);
      await again.load();
      expect(again.count, 0, reason: 'ลบแล้วต้องหายจากดิสก์จริง');
    });

    test('ปักหมุดแล้วไม่โดนตัดตอนความจำเต็ม', () async {
      await mem.remember('เรื่องเก่าที่สำคัญ');
      await mem.setPinned(mem.facts.first.id, true);

      for (var i = 0; i < kMemoryLimit + 5; i++) {
        await mem.remember('เรื่องใหม่ $i');
      }

      expect(mem.count, lessThanOrEqualTo(kMemoryLimit));
      expect(mem.facts.any((f) => f.text == 'เรื่องเก่าที่สำคัญ'), isTrue,
          reason: 'ปักหมุดไว้แล้วยังโดนตัด = ปักหมุดไม่มีความหมาย');
    });

    test('ที่ยัดเข้า prompt เอาปักหมุดขึ้นก่อนเสมอ', () async {
      await mem.remember('เรื่องเก่า');
      await mem.setPinned(mem.facts.first.id, true);
      await mem.remember('เรื่องใหม่กว่า');

      final top = mem.forPrompt(limit: 2).first;
      expect(top.text, 'เรื่องเก่า',
          reason: 'ไม่งั้นเรื่องสำคัญที่จำไว้นานจะถูกเรื่องใหม่เบียดออก');
    });

    test('ยังไม่จำอะไร ก้อน prompt ต้องว่าง ไม่ใช่หัวข้อเปล่า', () {
      expect(mem.promptBlock(), isEmpty);
    });
  });
}

/// โมเดลตอบไม่ตรงรูปแบบเป็นเรื่องปกติ — ตัวแยกต้องทนได้
/// และต้องทดสอบได้โดยไม่ต้องเรียกโมเดลจริง
void _distillerTests() {
  group('แยกสิ่งที่สกัดมา', () {
    test('รูปแบบตรงเป๊ะ', () {
      final r = parseDistilled('fact|เจ้าของแพ้กุ้ง\npreference|ชอบกาแฟดำ');
      expect(r.length, 2);
      expect(r.first.kind, MemoryKind.fact);
      expect(r.first.text, 'เจ้าของแพ้กุ้ง');
      expect(r.last.kind, MemoryKind.preference);
    });

    test('โมเดลใส่เลขข้อ ขีด หรือ backtick มาเอง ต้องลอกออก', () {
      final r = parseDistilled('''
```
1. fact|เจ้าของชื่อบิล
- routine|ประชุมทุกอังคาร
```
''');
      expect(r.length, 2);
      expect(r.first.text, 'เจ้าของชื่อบิล');
      expect(r.last.kind, MemoryKind.routine);
    });

    test('ลืมใส่ชนิด ยังเก็บข้อความไว้ ไม่ทิ้งทั้งบรรทัด', () {
      final r = parseDistilled('เจ้าของตื่นตีห้า');
      expect(r.length, 1);
      expect(r.first.kind, MemoryKind.fact);
      expect(r.first.text, 'เจ้าของตื่นตีห้า');
    });

    test('NONE แปลว่าไม่มีอะไรใหม่ ไม่ใช่ข้อความที่ต้องจำ', () {
      expect(parseDistilled('NONE'), isEmpty);
      expect(parseDistilled('none'), isEmpty);
    });

    test('ชนิดที่ไม่รู้จัก ตกเป็น fact ไม่ใช่ถูกทิ้ง', () {
      final r = parseDistilled('mood|เจ้าของอารมณ์ดีวันนี้');
      expect(r.length, 1);
      expect(r.first.kind, MemoryKind.fact);
    });

    test('🔴 ด่านที่สอง — ความลับที่โมเดลไม่เชื่อฟังต้องถูกทิ้งที่นี่', () {
      final r = parseDistilled('fact|รหัสผ่านของเจ้าของคือ hunter2\n'
          'fact|เจ้าของแพ้กุ้ง');
      expect(r.length, 1, reason: 'สั่งห้ามแล้วแต่ห้ามเชื่อว่ามันเชื่อฟัง');
      expect(r.first.text, 'เจ้าของแพ้กุ้ง');
    });

    test('ยาวเกินเพดานถูกทิ้ง', () {
      expect(parseDistilled('fact|${'ก' * (kMemoryMaxChars + 1)}'), isEmpty);
    });

    test('บทสนทนาถูกประกอบให้อ่านออกว่าใครพูด', () {
      final block = conversationBlock(
        [(fromHer: false, text: 'สวัสดี'), (fromHer: true, text: 'ค่ะ')],
        me: 'เจ้าของ',
        her: 'มายด์',
      );
      expect(block, 'เจ้าของ: สวัสดี\nมายด์: ค่ะ');
    });
  });
}
