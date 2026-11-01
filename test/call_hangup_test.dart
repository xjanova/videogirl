/// เธอลาแล้วต้องวางจริง โดยเผื่อคู่สายยังพูดไม่จบ
///
/// ที่มา: เจ้าของ — "เธอพูดว่าขออนุญาติ วางสายนะคะ ก็ควรวางสายเลย ดีเลย์ไว้สัก 3 วินาที พอเผือ อีกฝ่ายยังพูดไม่จบ"
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/phone/call_hangup.dart';

void main() {
  final t0 = DateTime(2026, 11, 1, 12);
  const ms100 = Duration(milliseconds: 100);
  const old = Duration(minutes: 1);

  /// เดินนาฬิกาทีละ 100 มิลลิวินาที · คืนจังหวะที่สั่งวาง (null = ไม่วาง)
  Duration? run(CallHangUp h, Duration span, {bool Function(Duration at)? her, bool Function(Duration at)? caller}) {
    for (var at = Duration.zero; at <= span; at += ms100) {
      if (h.due(t0.add(at), age: old, herVoice: her?.call(at) ?? false, callerTalking: caller?.call(at) ?? false)) {
        return at;
      }
    }
    return null;
  }

  group('🔴 นับสามวินาทีหลังเสียงลาจบ', () {
    test('เสียงลาจบแล้วเงียบครบ = วาง · ไม่ก่อนสามวินาที', () {
      final h = CallHangUp()..arm();
      final at = run(h, const Duration(seconds: 10), her: (t) => t < const Duration(seconds: 2));
      expect(at, const Duration(seconds: 5));
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
  });

  group('🔴 คู่สายพูดระหว่างรอ', () {
    test('กำลังพูดอยู่ = ไม่วาง ต่อให้เกินสามวินาที · หยุดแล้วนับใหม่', () {
      final h = CallHangUp()..arm();
      final at = run(h, const Duration(seconds: 15),
          caller: (t) => t >= const Duration(seconds: 2) && t < const Duration(seconds: 8));
      expect(at, const Duration(seconds: 11));
    });

    test('บทของคำที่พูดหลังเธอลามาถึง = เลิกวาง · ให้เธอตอบต่อ', () {
      final h = CallHangUp()..arm();
      expect(run(h, const Duration(seconds: 2), caller: (t) => t < const Duration(seconds: 1)), isNull);
      h.callerSaid();
      expect(h.armed, isFalse);
      expect(run(h, const Duration(seconds: 10)), isNull);
    });

    test('เธอตอบแล้วลาใหม่ = นับสามวินาทีใหม่', () {
      final h = CallHangUp()..arm();
      run(h, const Duration(seconds: 1), caller: (_) => true);
      h
        ..callerSaid()
        ..arm();
      expect(run(h, const Duration(seconds: 2)), isNull);
      expect(h.armed, isTrue);
      expect(h.due(t0.add(CallHangUp.wait), age: old), isTrue);
    });

    test('🔴 บทของคำก่อนเธอลา มาถึงช้า = ไม่เลิกวาง · ไม่งั้นสายค้าง', () {
      final h = CallHangUp()..arm();
      h.callerSaid();
      expect(h.armed, isTrue);
      expect(run(h, const Duration(seconds: 4)), isNotNull);
    });

    test('เสียงรบกวนที่ไม่กลายเป็นบท = แค่นับใหม่ ยังวาง', () {
      final h = CallHangUp()..arm();
      expect(run(h, const Duration(seconds: 6), caller: (t) => t < ms100 * 3), isNotNull);
    });

    test('พักสายรอเจ้าของตอบ = ไม่วาง', () {
      final h = CallHangUp()..arm();
      expect(h.due(t0, age: old, held: true), isFalse);
      expect(h.due(t0.add(const Duration(seconds: 9)), age: old, held: true), isFalse);
      expect(h.armed, isTrue);
    });
  });

  test('🔴 ห้าวินาทีแรกของสายไม่วาง แม้เงียบครบแล้ว · พ้นด่านแล้ววาง', () {
    final h = CallHangUp()..arm();
    expect(h.due(t0, age: const Duration(seconds: 1)), isFalse);
    expect(h.due(t0.add(const Duration(seconds: 3)), age: const Duration(seconds: 4)), isFalse);
    expect(h.due(t0.add(const Duration(seconds: 5)), age: const Duration(seconds: 6)), isTrue);
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

    test('คุยสด: เสียงเธอ คู่สายพูด พักสาย ต้องกันการวาง · เจ้าของแทรกแล้วไม่วาง', () {
      final at = session.indexOf('_leaving.due(');
      final block = session.substring(at, session.indexOf('unawaited(hangUp())', at));
      expect(block, contains('herVoice: speaking'));
      expect(block, contains('callerTalking: rt.callerTalking'));
      expect(block, contains('held: _ownerAnswer != null'));
      expect(block, contains('_turn != CallTurn.handedOver'));
    });

    test('คำลาในบทของเธอวางได้เหมือน end_call · บทคู่สายยกเลิกการวาง', () {
      expect(session, contains('CallGoodbye.says(t) && !_leaving.armed'));
      expect(session, contains('_leaving.callerSaid()'));
    });

    test('ทางเดิม: แท็กหรือคำลา = รอบฟังสามวินาทีก่อนวาง ไม่วางทันที', () {
      expect(session, contains('leaving = (c.hangUp || CallGoodbye.says(c.text)) && age > CallHangUp.guard'));
      expect(session, contains('_listen(patience: leaving ? CallHangUp.wait : null)'));
      expect(session, isNot(contains('if (c.hangUp &&')));
    });

    test('เจ้าของพิมพ์ให้เธอพูดระหว่างรอ = เลิกวาง · ทุกทาง', () {
      final say = session.indexOf('Future<void> say(');
      expect(session.substring(say, say + 400), contains('_leaving.disarm()'));
      expect(session, contains('cutIn == null'));
    });

    test('GPT-Live: end_call ครั้งที่สองต้องทำงาน · บอกได้ว่าคู่สายพูดอยู่', () {
      final live = File('lib/phone/live_call.dart').readAsStringSync();
      expect(live, isNot(contains('_hangUp ??=')));
      expect(live, contains('bool get callerTalking'));
      expect(File('lib/phone/realtime_call.dart').readAsStringSync(), contains('bool get callerTalking'));
    });
  });
}
