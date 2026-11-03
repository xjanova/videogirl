/// วางสายที่เธอโทรแล้ว เธอต้องกลับมาคุยต่อ
///
/// เจ้าของ (2026-11-03): "ถ้าเธอโทรไม่สำเร็จ หรือเรากดวางสายขณะเธอโทร เธอจะหายไปและเหมือนไม่ตอบรับอะไรอีกเลย" ·
/// ของเดิมปิดคุยต่อเนื่องตอนสายเริ่ม (ไมค์เป็นของสาย) แล้วไม่เปิดคืน · ผลโทรขึ้นแค่ตัวหนังสือ ไม่มีใครพูด
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final app = File('lib/main.dart').readAsStringSync();
  final state = File('lib/state/mind_state.dart').readAsStringSync();

  String body(String src, String fun) {
    final start = src.indexOf(fun);
    expect(start, isNonNegative, reason: 'ไม่เจอ $fun');
    // ข้ามวงเล็บของพารามิเตอร์แบบมีชื่อ ({...}) · ตัวฟังก์ชันเริ่มหลัง ')'
    final open = src.indexOf('{', src.indexOf(')', start));
    var depth = 0;
    for (var i = open; i < src.length; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}' && --depth == 0) return src.substring(open, i + 1);
    }
    fail('$fun ไม่ปิดวงเล็บ');
  }

  test('🔴 ปิดคุยให้สายที่เธอโทรเอง = จำไว้ · วางแล้วเปิดคืนและให้เธอบอกผล', () {
    final y = body(app, 'void _yieldMicToCall(');
    expect(y, contains('_resumeChat = _state.outgoing != null'));
    expect(y, contains('_afterCall()'));
    final after = body(app, 'Future<void> _afterCall(');
    expect(after, contains('_state.takeCallOutcome()'));
    expect(after, contains('await _voiceChat.start()'));
    expect(after, contains('if (_voiceChat.active)'));
    expect(after, contains('_voiceChat.announce(said)'));
    // พิมพ์สั่งโทร (ไม่ได้คุยเสียง) = ยังได้ยินผลโทรด้วยเสียง
    expect(after, contains('_state.speakNotice(said)'));
  });

  test('🔴 รู้ว่าเป็นสายของเธอตั้งแต่ก่อนกดโทร · สัญญาณยกหูมาก่อนคำสั่งโทรตอบได้', () {
    final c = body(state, 'Future<void> confirmPendingCall(');
    expect(c.indexOf('_outgoing = (who:'), lessThan(c.indexOf("'mindPlaceCall'")));
    // โทรไม่ออก = ไม่ค้างเป็นสายของเธอ
    expect(c, contains('_outgoing = null'));
  });

  test('ผลโทรที่ไม่ได้คุย เก็บไว้ให้พูดได้ครั้งเดียว', () {
    expect(body(state, 'void _outgoingEnded('), contains('_callOutcome = text'));
    expect(body(state, 'String? takeCallOutcome('), contains('_callOutcome = null'));
  });
}
