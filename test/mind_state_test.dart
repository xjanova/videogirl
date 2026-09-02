import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/theme/tokens.dart';

void main() {
  group('โหมดอัตโนมัติ', () {
    // กติกาจาก artboard 2g: ในเวลางานเป็นเลขาฯ หลังสองทุ่มและวันหยุดเป็นตัวเอง
    MindState at(DateTime when) => MindState(clock: () => when)
      ..setPersona(PersonaSetting.auto);

    test('วันธรรมดาเวลางาน = โหมดงาน', () {
      // พุธ 2 ก.ย. 2026, 10:00
      expect(at(DateTime(2026, 9, 2, 10)).mode, MindMode.work);
    });

    test('วันธรรมดาหลังสองทุ่ม = โหมดส่วนตัว', () {
      expect(at(DateTime(2026, 9, 2, 20, 1)).mode, MindMode.love);
    });

    test('ตีสองของวันธรรมดา = โหมดส่วนตัว', () {
      expect(at(DateTime(2026, 9, 2, 2)).mode, MindMode.love);
    });

    test('เสาร์กลางวัน = โหมดส่วนตัว', () {
      // เสาร์ 5 ก.ย. 2026
      expect(at(DateTime(2026, 9, 5, 10)).mode, MindMode.love);
    });

    test('สวิตช์บนหัวจอสลับจากโหมดที่มีผลจริง ไม่ใช่จากค่าที่ตั้งไว้', () {
      // ตั้งไว้ auto และตอนนี้คลี่ออกเป็น work → กดแล้วต้องได้ love
      final s = at(DateTime(2026, 9, 2, 10))..toggleMode();
      expect(s.persona, PersonaSetting.love);
      expect(s.mode, MindMode.love);
    });
  });

  group('ระดับการจีบ', () {
    test('โหมดงานกดเพดานลงครึ่งหนึ่ง', () {
      final s = MindState()..setFlirt(0.8);
      expect(s.mode, MindMode.work);
      expect(s.effectiveFlirt, closeTo(0.4, 1e-9));

      s.setPersona(PersonaSetting.love);
      expect(s.effectiveFlirt, closeTo(0.8, 1e-9));
    });

    test('ค่าที่เกินขอบถูกบีบกลับเข้าช่วง 0–1', () {
      final s = MindState()
        ..setPersona(PersonaSetting.love)
        ..setFlirt(9.0);
      expect(s.flirt, 1.0);

      s.setFlirt(-3);
      expect(s.flirt, 0.0);
    });
  });

  group('ส่งข้อความ', () {
    test('ข้อความว่างหรือมีแต่ช่องว่างไม่ถูกส่ง', () async {
      final s = MindState();
      final before = s.messages.length;
      await s.send('   ');
      expect(s.messages.length, before);
    });

    test('กดส่งรัวสองครั้งได้ข้อความเดียว', () async {
      final s = MindState();
      final before = s.messages.length;

      final first = s.send('ทดสอบ');
      // ยังไม่ await ตัวแรก — จำลองการกดซ้ำระหว่างที่ยังส่งไม่เสร็จ
      await s.send('ทดสอบ');
      await first;

      // เพิ่มแค่คู่เดียว: ของเรา 1 + ของเธอ 1
      expect(s.messages.length, before + 2);
    });

    test('ประวัติไม่เกิน 6 ข้อความ ไม่งั้นแผงแชทจะบังตัวเธอ', () async {
      final s = MindState();
      for (var i = 0; i < 5; i++) {
        await s.send('ข้อความที่ $i');
      }
      expect(s.messages.length, lessThanOrEqualTo(6));
    });

    // เทสต์เดิมยืนยันว่าเวลาสมองล้ม เธอตอบ "มายด์จัดการให้แล้ว" — ซึ่งคือ
    // ตัวบั๊กเอง ไม่ใช่พฤติกรรมที่ถูก · ในเทสต์ไม่มีคีย์ ไม่มีโมเดล จึงล้มเสมอ
    // เทสต์นั้นจึงล็อกไว้ว่า "ล้มแล้วโกหกว่าสำเร็จ" ถือว่าใช้ได้
    test('สมองล้ม ต้องบอกตามจริง ไม่ใช่ตอบเหมือนทำให้แล้ว', () async {
      final s = MindState();
      await s.send('ช่วยหน่อย');

      final reply = s.messages.last.text;

      expect(reply, isNot(contains('มายด์จัดการให้')),
          reason: 'ตอบเหมือนสำเร็จทั้งที่ไม่มีอะไรถูกส่งออกไปเลย');
      expect(reply, contains('ไม่ได้'), reason: 'ต้องบอกว่าทำให้ไม่ได้');
      // และต้องบอกเหตุผลที่พอเอาไปแก้ได้ ไม่ใช่ล้มเฉย ๆ
      expect(s.lastError, isNotNull);
      expect(reply, contains(s.lastError!));
    });

    test('ข้อผิดพลาดปิดได้ และปิดแล้วหายจริง', () async {
      final s = MindState();
      await s.send('ช่วยหน่อย');
      expect(s.lastError, isNotNull);

      s.clearError();

      // ถ้าไม่หาย แถบเตือนบนจอจะค้างอยู่ตลอดกาล
      expect(s.lastError, isNull);
    });
  });

  test('ฟองคำพูดหยิบข้อความล่าสุดของเธอ ไม่ใช่ของเรา', () async {
    final s = MindState();
    await s.send('อันนี้เราพิมพ์เอง');
    expect(s.bubbleText, isNot('อันนี้เราพิมพ์เอง'));
    expect(s.messages.last.fromHer, isTrue);
    expect(s.bubbleText, s.messages.last.text);
  });
}
