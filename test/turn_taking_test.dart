/// เจ้าของพูดจบตาแล้วหรือยัง — ความเงียบ + ประโยคฟังดูจบไหม
///
/// ที่มา: เจ้าของ — "ต้องเข้าใจว่าบริบทไหนที่เราหยุดให้เธอปฏิบัติได้ เช่นพูดแล้วหยุดเว้นให้เธอคิดได้เลย
/// ไม่ต้องมากดส่งอีก เพราะเราออกแบบให้แอพนี้ใช้งานแม้ในขับรถได้"
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/ai/turn_taking.dart';

/// ป้อนเสียงทีละ 100 มิลลิวินาที (3200 ไบต์ที่ 16 kHz)
class _Sim {
  final t = TurnTaker();
  int ms = 0, bytes = 0;

  TurnStep chunk(double level) {
    ms += 100;
    bytes += 3200;
    return t.feed(level, ms, bytes);
  }

  List<TurnStep> run(double level, int n) => [for (var i = 0; i < n; i++) chunk(level)];

  /// พูดจริงมีช่องว่างระหว่างคำ · เสียงดังคงที่ยาว ๆ ระบบถือเป็นเสียงพื้นหลัง (แอร์ เครื่องยนต์) โดยตั้งใจ
  List<TurnStep> speech(int n) => [for (var i = 0; i < n; i++) chunk(i % 4 == 3 ? _quiet : _voice)];
}

const _quiet = .004;
const _voice = .1;

void main() {
  group('ประโยคฟังจบไหม', () {
    test('คำเชื่อม/คำลังเลท้ายประโยค = ยังไม่จบ', () {
      for (final s in ['โทรหาบัว แล้วก็', 'บอกเขาว่า', 'เอ่อ', 'เพราะว่า', 'ถ้า', 'call mom and', 'tell her that', 'um']) {
        expect(TurnEnd.looksUnfinished(s), isTrue, reason: s);
      }
    });

    test('คำลงท้ายสุภาพ / คำถาม = จบ แม้คำก่อนหน้าเป็นคำเชื่อม', () {
      for (final s in ['โทรหาบัวหน่อยค่ะ', 'ช่วยดูให้หน่อยนะ', 'วันนี้ฝนตกไหม', 'ไปกันอ่ะ', 'แค่นี้ก็พอ', 'what time is it', '']) {
        expect(TurnEnd.looksUnfinished(s), isFalse, reason: s);
      }
    });

    test('จุดไข่ปลาท้ายประโยค = ยังคิดอยู่', () {
      expect(TurnEnd.looksUnfinished('โทรหาบัว...'), isTrue);
      expect(TurnEnd.looksUnfinished('call her…'), isTrue);
    });
  });

  group('คำสั่งปิดไมค์', () {
    test('ทั้งประโยคเป็นคำสั่ง (ตัดคำสุภาพและชื่อเธอออก) = ปิด', () {
      for (final s in ['พอแล้วค่ะ', 'จบ', 'ปิดไมค์นะ', 'บาย มายด์', 'Stop.', "That's all", 'bye bye']) {
        expect(VoiceStop.matches(s), isTrue, reason: s);
      }
    });

    test('🔴 คำสั่งปนประโยคอื่น = ไม่ปิด (ไม่งั้นพูด "พอแล้วไปไหนต่อ" ไมค์ดับกลางทาง)', () {
      for (final s in ['พอแล้วไปไหนต่อดี', 'stop the music', 'จบงานกี่โมง', 'บายพาสทางด่วน', 'มายด์']) {
        expect(VoiceStop.matches(s), isFalse, reason: s);
      }
    });
  });

  group('จับจังหวะจบตา', () {
    test('หยุด 0.7 วิ = ขอถอดครั้งเดียว · ประโยคฟังจบ = จบตาทันที ไม่ต้องรอ', () {
      final s = _Sim();
      expect(s.run(_quiet, 5).toSet(), {TurnStep.none});
      expect(s.run(_voice, 10).toSet(), {TurnStep.none});
      expect(s.run(_quiet, 6).toSet(), {TurnStep.none});
      expect(s.chunk(_quiet), TurnStep.transcribe);
      final asked = s.t.askedAt;
      expect(asked, s.bytes);
      expect(s.chunk(_quiet), TurnStep.none, reason: 'ผลยังไม่มา');
      s.t.heard('โทรหาบัวหน่อยค่ะ', asked);
      expect(s.chunk(_quiet), TurnStep.done);
      expect(s.t.text, 'โทรหาบัวหน่อยค่ะ');
    });

    test('🔴 ประโยคค้าง ("แล้วก็") = รอจนเงียบครบ 2.2 วิ ไม่ตัดคนที่หยุดคิด', () {
      final s = _Sim()
        ..run(_quiet, 5)
        ..run(_voice, 10)
        ..run(_quiet, 6);
      expect(s.chunk(_quiet), TurnStep.transcribe);
      s.t.heard('โทรหาบัว แล้วก็', s.t.askedAt);
      expect(s.run(_quiet, 14).toSet(), {TurnStep.none}, reason: 'เงียบยังไม่ถึง 2.2 วิ');
      expect(s.chunk(_quiet), TurnStep.done);
    });

    test('พูดต่อหลังขอถอดแล้ว = ผลเก่าทิ้ง ขอใหม่รอบหน้า', () {
      final s = _Sim()
        ..run(_quiet, 5)
        ..run(_voice, 10)
        ..run(_quiet, 6);
      expect(s.chunk(_quiet), TurnStep.transcribe);
      final first = s.t.askedAt;
      s.chunk(_voice);
      expect(s.t.askedAt, -1);
      s.t.heard('โทรหาบัว', first);
      expect(s.t.text, isNull, reason: 'ผลของเสียงที่สั้นกว่าตอนนี้');
      s.run(_voice, 5);
      expect(s.run(_quiet, 6).toSet(), {TurnStep.none});
      expect(s.chunk(_quiet), TurnStep.transcribe);
      expect(s.t.askedAt, greaterThan(first));
    });

    test('เสียงคลิกสั้น ๆ = ไม่ส่งไปถอด · เงียบครบ = ทิ้ง', () {
      final s = _Sim()..run(_quiet, 5);
      final steps = [...s.run(_voice, 2), ...s.run(_quiet, 22)];
      expect(steps, isNot(contains(TurnStep.transcribe)));
      expect(steps.last, TurnStep.noise);
    });

    test('ถอดแล้วว่างเปล่า = เสียงรบกวน', () {
      final s = _Sim()
        ..run(_quiet, 5)
        ..run(_voice, 10)
        ..run(_quiet, 6);
      expect(s.chunk(_quiet), TurnStep.transcribe);
      s.t.heard('', s.t.askedAt);
      expect(s.chunk(_quiet), TurnStep.noise);
    });

    test('พูดยาวไม่หยุดครบ 30 วิ = จบตาให้เธอตอบ', () {
      final s = _Sim()..run(_quiet, 5);
      expect(s.speech(296), isNot(contains(TurnStep.done)));
      expect(s.speech(8), contains(TurnStep.done));
    });

    test('🔴 เงียบรอนานก่อนพูด ไม่นับเข้าเพดาน 30 วิ (เคยตัดตั้งแต่พยางค์แรก)', () {
      final s = _Sim()..run(_quiet, 400);
      expect(s.run(_voice, 10).toSet(), {TurnStep.none});
    });

    test('🔴 เริ่มตาใหม่จำพื้นเสียงไว้ · เจ้าของพูดทันทีที่เธอพูดจบ ตายังนับว่าเริ่ม', () {
      final s = _Sim()
        ..run(_quiet, 5)
        ..run(_voice, 3);
      s.t.reset();
      expect(s.t.started, isFalse);
      s.chunk(_voice);
      expect(s.t.started, isTrue);
    });

    test('จบตาโดยยังไม่มีคำขอ = askNow ขอถอดทั้งหมด · ขอซ้ำที่ความยาวเดิม = ไม่ส่งซ้ำ', () {
      final s = _Sim()
        ..run(_quiet, 5)
        ..run(_voice, 4);
      expect(s.t.askNow(s.bytes), isTrue);
      expect(s.t.askNow(s.bytes), isFalse);
      s.t.heard('ไปไหนดี', s.bytes);
      expect(s.t.text, 'ไปไหนดี');
    });
  });
}
