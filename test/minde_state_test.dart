import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/state/minde_state.dart';
import 'package:videogirl/theme/tokens.dart';

void main() {
  group('โหมดอัตโนมัติ', () {
    // กติกาจาก artboard 2g: ในเวลางานเป็นเลขาฯ หลังสองทุ่มและวันหยุดเป็นตัวเอง
    MindeState at(DateTime when) => MindeState(clock: () => when)
      ..setPersona(PersonaSetting.auto);

    test('วันธรรมดาเวลางาน = โหมดงาน', () {
      // พุธ 2 ก.ย. 2026, 10:00
      expect(at(DateTime(2026, 9, 2, 10)).mode, MindeMode.work);
    });

    test('วันธรรมดาหลังสองทุ่ม = โหมดส่วนตัว', () {
      expect(at(DateTime(2026, 9, 2, 20, 1)).mode, MindeMode.love);
    });

    test('ตีสองของวันธรรมดา = โหมดส่วนตัว', () {
      expect(at(DateTime(2026, 9, 2, 2)).mode, MindeMode.love);
    });

    test('เสาร์กลางวัน = โหมดส่วนตัว', () {
      // เสาร์ 5 ก.ย. 2026
      expect(at(DateTime(2026, 9, 5, 10)).mode, MindeMode.love);
    });

    test('สวิตช์บนหัวจอสลับจากโหมดที่มีผลจริง ไม่ใช่จากค่าที่ตั้งไว้', () {
      // ตั้งไว้ auto และตอนนี้คลี่ออกเป็น work → กดแล้วต้องได้ love
      final s = at(DateTime(2026, 9, 2, 10))..toggleMode();
      expect(s.persona, PersonaSetting.love);
      expect(s.mode, MindeMode.love);
    });
  });

  group('ระดับการจีบ', () {
    test('โหมดงานกดเพดานลงครึ่งหนึ่ง', () {
      final s = MindeState()..setFlirt(0.8);
      expect(s.mode, MindeMode.work);
      expect(s.effectiveFlirt, closeTo(0.4, 1e-9));

      s.setPersona(PersonaSetting.love);
      expect(s.effectiveFlirt, closeTo(0.8, 1e-9));
    });

    test('ค่าที่เกินขอบถูกบีบกลับเข้าช่วง 0–1', () {
      final s = MindeState()
        ..setPersona(PersonaSetting.love)
        ..setFlirt(9.0);
      expect(s.flirt, 1.0);

      s.setFlirt(-3);
      expect(s.flirt, 0.0);
    });
  });

  group('ส่งข้อความ', () {
    test('ข้อความว่างหรือมีแต่ช่องว่างไม่ถูกส่ง', () async {
      final s = MindeState();
      final before = s.messages.length;
      await s.send('   ');
      expect(s.messages.length, before);
    });

    test('กดส่งรัวสองครั้งได้ข้อความเดียว', () async {
      final s = MindeState();
      final before = s.messages.length;

      final first = s.send('ทดสอบ');
      // ยังไม่ await ตัวแรก — จำลองการกดซ้ำระหว่างที่ยังส่งไม่เสร็จ
      await s.send('ทดสอบ');
      await first;

      // เพิ่มแค่คู่เดียว: ของเรา 1 + ของเธอ 1
      expect(s.messages.length, before + 2);
    });

    test('ประวัติไม่เกิน 6 ข้อความ ไม่งั้นแผงแชทจะบังตัวเธอ', () async {
      final s = MindeState();
      for (var i = 0; i < 5; i++) {
        await s.send('ข้อความที่ $i');
      }
      expect(s.messages.length, lessThanOrEqualTo(6));
    });

    test('น้ำเสียงที่ตอบเปลี่ยนตามโหมด', () async {
      final work = MindeState();
      await work.send('ช่วยหน่อย');
      expect(work.messages.last.text, contains('มินเดะจัดการให้'));

      final love = MindeState()..setPersona(PersonaSetting.love);
      await love.send('ช่วยหน่อย');
      expect(love.messages.last.text, contains('คำชม'));
    });
  });

  test('ฟองคำพูดหยิบข้อความล่าสุดของเธอ ไม่ใช่ของเรา', () async {
    final s = MindeState();
    await s.send('อันนี้เราพิมพ์เอง');
    expect(s.bubbleText, isNot('อันนี้เราพิมพ์เอง'));
    expect(s.messages.last.fromHer, isTrue);
    expect(s.bubbleText, s.messages.last.text);
  });
}
