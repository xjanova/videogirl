/// เธอลาแล้วต้องวางจริง โดยเผื่อคู่สายยังพูดไม่จบ
///
/// ที่มา: เจ้าของ — "เธอพูดว่าขออนุญาติ วางสายนะคะ ก็ควรวางสายเลย ดีเลย์ไว้สัก 3 วินาที พอเผือ อีกฝ่ายยังพูดไม่จบ" ·
/// แล้ว (2026-11-03) "เรื่องวางสาย เธอต้องวางสายเลยไม่ต้อง รอฟัง แล้ว เพราะ เธอไม่ยอมวางสักที"
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/phone/call_hangup.dart';

void main() {
  final t0 = DateTime(2026, 11, 1, 12);
  const ms100 = Duration(milliseconds: 100);
  const old = Duration(minutes: 1);

  /// เดินนาฬิกาทีละ 100 มิลลิวินาที · คืนจังหวะที่สั่งวาง (null = ไม่วาง)
  Duration? run(CallHangUp h, Duration span, {bool Function(Duration at)? her}) {
    for (var at = Duration.zero; at <= span; at += ms100) {
      if (h.due(t0.add(at), age: old, herVoice: her?.call(at) ?? false)) return at;
    }
    return null;
  }

  group('🔴 ลาแล้ววางเมื่อเสียงลาจบ ไม่รอฟังคู่สาย', () {
    test('เสียงลาจบ = วางในหนึ่งวินาที', () {
      final h = CallHangUp()..arm();
      final at = run(h, const Duration(seconds: 10), her: (t) => t < const Duration(seconds: 2));
      expect(at, const Duration(seconds: 3));
      expect(h.armed, isFalse);
    });

    test('ยังไม่ได้ลา = ไม่วาง', () {
      expect(run(CallHangUp(), const Duration(seconds: 10)), isNull);
    });

    test('สั่งวางครั้งเดียว', () {
      final h = CallHangUp()..arm();
      expect(run(h, const Duration(seconds: 5)), isNotNull);
      expect(run(h, const Duration(seconds: 5)), isNull);
    });

    test('🔴 เสียงเธอค้างไม่จบ = วางอยู่ดีเมื่อครบเวลา', () {
      final h = CallHangUp()..arm();
      expect(run(h, const Duration(seconds: 30), her: (_) => true), CallHangUp.cap);
    });

    test('พักสายรอเจ้าของตอบ = ไม่วาง', () {
      final h = CallHangUp()..arm();
      expect(h.due(t0, age: old, held: true), isFalse);
      expect(h.due(t0.add(const Duration(seconds: 9)), age: old, held: true), isFalse);
      expect(h.armed, isTrue);
    });

    test('🔴 ไม่มีทางให้คู่สายยกเลิกการวาง', () {
      final src = File('lib/phone/call_hangup.dart').readAsStringSync();
      expect(src, isNot(contains('callerTalking')));
      expect(src, isNot(contains('callerSaid')));
    });
  });

  test('🔴 ห้าวินาทีแรกของสายไม่วาง แม้เงียบครบแล้ว · พ้นด่านแล้ววาง', () {
    final h = CallHangUp()..arm();
    expect(h.due(t0, age: const Duration(seconds: 1)), isFalse);
    expect(h.due(t0.add(const Duration(seconds: 3)), age: const Duration(seconds: 4)), isFalse);
    expect(h.due(t0.add(const Duration(seconds: 5)), age: const Duration(seconds: 6)), isFalse);
    expect(h.due(t0.add(const Duration(seconds: 6)), age: const Duration(seconds: 7)), isTrue);
  });

  group('คำในบทที่นับว่าจะวาง', () {
    test('บอกว่าจะวาง = นับ', () {
      for (final t in [
        'ขออนุญาตวางสายนะคะ',
        'ขอบคุณมากค่ะ ขออนุญาตวางสายนะคะ สวัสดีค่ะ',
        'ขอวางสายก่อนนะคะ',
        'ขอตัววางสายนะคะ',
        'งั้นวางสายนะคะ',
        'จะวางสายแล้วนะคะ',
        "I'll hang up now, thank you.",
        'Hanging up now.',
      ]) {
        expect(CallGoodbye.says(t), isTrue, reason: t);
      }
    });

    test('🔴 ถาม หรือบอกว่ายังไม่ไป = ไม่นับ', () {
      for (final t in [
        'ขอวางสายได้ไหมคะ',
        'ขออนุญาตวางสายนะคะ มีอะไรอีกไหมคะ',
        'ขอวางสายเลยดีมั้ยคะ',
        'วางสายเลยหรือเปล่าคะ',
        'อย่าเพิ่งวางสายนะคะ',
        'กรุณาอย่าวางสายค่ะ',
        'ไม่วางสายนะคะ รอสักครู่',
        'ก่อนวางสายขอทวนนัดนะคะ',
        'ก่อนจะวางสาย ขอถามอีกข้อค่ะ',
        'คุณจะวางสายเลยนะคะ',
        'พอวางสายแล้วจะแจ้งเจ้านายค่ะ',
        'May I hang up?',
        'สวัสดีค่ะ มายด์เลขาคุณบอสค่ะ',
      ]) {
        expect(CallGoodbye.says(t), isFalse, reason: t);
      }
    });
  });

  // ทางคุยสดผูกกับลำโพงจริงและนาฬิกา 100 มิลลิวินาที · ตรึงการเดินสายไว้ด้วยการอ่านซอร์ส
  group('🔴 เดินสายครบทุกทาง', () {
    final session = File('lib/phone/call_session.dart').readAsStringSync();

    test('คุยสด: เสียงเธอ พักสาย กันการวาง · คู่สายพูดไม่กัน · เจ้าของแทรกแล้วไม่วาง', () {
      final at = session.indexOf('_leaving.due(');
      final block = session.substring(at, session.indexOf('unawaited(hangUp())', at));
      expect(block, contains('herVoice: speaking'));
      expect(block, isNot(contains('callerTalking')));
      expect(block, contains('held: _ownerAnswer != null'));
      expect(block, contains('_turn != CallTurn.handedOver'));
    });

    test('คำลาในบทของเธอวางได้เหมือน end_call · บทคู่สายไม่ยกเลิกการวาง', () {
      expect(session, contains('CallGoodbye.says(t) && !_leaving.armed'));
      expect(session, isNot(contains('_leaving.callerSaid()')));
    });

    test('ทางเดิม: แท็กหรือคำลา = วางหลังเสียงลาจบ ไม่เปิดรอบฟังอีก', () {
      expect(session, contains('leaving = (c.hangUp || CallGoodbye.says(c.text)) && age > CallHangUp.guard'));
      final at = session.indexOf('    var leaving = false;');
      final loop = session.substring(at, session.indexOf('final heard = await _listen();', at));
      expect(loop, contains('await Future<void>.delayed(CallHangUp.wait)'));
      expect(loop, contains('await hangUp()'));
      expect(session, isNot(contains('patience: leaving')));
    });

    test('เจ้าของพิมพ์ให้เธอพูดระหว่างรอ = เลิกวาง · ทุกทาง', () {
      final say = session.indexOf('Future<void> say(');
      expect(session.substring(say, say + 400), contains('_leaving.disarm()'));
      expect(session, contains('if (_saying == null && _turn != CallTurn.handedOver)'));
    });

    test('GPT-Live: end_call ครั้งที่สองต้องทำงาน · บอกได้ว่าคู่สายพูดอยู่', () {
      final live = File('lib/phone/live_call.dart').readAsStringSync();
      expect(live, isNot(contains('_hangUp ??=')));
      expect(live, contains('bool get callerTalking'));
      expect(File('lib/phone/realtime_call.dart').readAsStringSync(), contains('bool get callerTalking'));
    });
  });
}
