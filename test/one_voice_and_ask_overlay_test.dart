/// เสียงมายด์ดังทีละเสียง · กล่องยืนยันลอยเหนือทุกแอป
///
/// เจ้าของ (2026-11-07): "การแชท ของมายด์มีเสียงพูดซ้อนกันหลายตัว ได้ไง และยังคงพูดเรื่องเก่า
/// ในการที่เธอถามว่าจะให้ทำอะไรแล้วยืนยัน ควรเป็น ป๊อบอัพเด้งเหนือทุกโปรแกรมเพื่อจะได้สั่งงานได้ตรง
/// เช่นทำเลย หรือไม่ทำ"
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String path) => File(path).readAsStringSync();

String _body(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'หา $signature ไม่เจอ');
  var depth = 0;
  for (var i = source.indexOf('{', start); i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}' && --depth == 0) return source.substring(start, i + 1);
  }
  fail('ปีกกาของ $signature ไม่ครบ');
}

const _hands = 'android/app/src/main/kotlin/com/xjanova/videogirl/hands';

void main() {
  group('เสียงเดียว', () {
    test('🔴 ประโยคก่อนหน้ายังดัง = หยุดทุกทางก่อนเล่นประโยคใหม่ · ไม่ยกเลิกประโยคใหม่เอง', () {
      final state = _src('lib/state/mind_state.dart');
      // พารามิเตอร์แบบมีชื่อมีปีกกาเอง · ตัดถึงฟังก์ชันถัดไปแทน
      final from = state.indexOf('Future<void> _speakIfEnabled(');
      final speak = state.substring(from, state.indexOf('Future<Utterance> synthesizeWithFallback(', from));
      final cut = speak.indexOf('await _silenceOthers()');
      expect(cut, greaterThan(0));
      expect(speak.indexOf('final played = await out(utterance)'), greaterThan(cut),
          reason: 'ต้องหยุดเสียงเก่าก่อนเล่น');
      expect(speak.substring(speak.indexOf('if (_speaking)'), cut), isNot(contains('_speechSeq++')));
      final others = _body(_src('lib/state/mind_state.dart'), 'Future<void> _silenceOthers(');
      expect(others, isNot(contains('_speechSeq')), reason: 'hush ยกเลิกรอบ · ตัวนี้แค่หยุดเสียง');
      expect(others, contains('.timeout('));
    });

    test('🔴 เวทีเล่นไม่จบ/บอกว่าเงียบ = สั่งเวทีหยุดก่อนเล่นซ้ำทางสำรอง', () {
      final shell = _src('lib/shell.dart');
      final fallback = shell.indexOf('played = await MindAudio.play(u.bytes, mime: u.mime);');
      final stop = shell.lastIndexOf('await _avatar.stop()', fallback);
      expect(stop, greaterThan(0));
      expect(shell.lastIndexOf('if (!played) {', fallback), lessThan(stop));
    });
  });

  group('กล่องยืนยันลอย', () {
    test('🔴 แอปไม่อยู่บนจอ = ขอกล่องลอย · ตอบทางเดียวกับปุ่มในแจ้งเตือน', () {
      final confirm = _body(_src('lib/state/mind_state.dart'), 'Future<bool> _confirmInChat(');
      expect(confirm, contains('float: !_appVisible'));
      expect(_src('lib/hands/hands_bridge.dart'), contains("'float': float"));
      final ask = _body(_src('$_hands/HandsService.kt'), 'fun ask(');
      expect(ask, contains('if (float) AskOverlay.show(id, title, body)'));
      final overlay = _src('$_hands/AskOverlay.kt');
      expect(_body(overlay, 'private fun answer('), contains('HandsControl.answer(ask.id, allow)'));
    });

    test('🔴 ถามจบทางไหนก็ปิดกล่อง (ตอบในแจ้งเตือน · หมดเวลา · งานจบ · บริการมือปิด)', () {
      final service = _src('$_hands/HandsService.kt');
      expect(_body(service, 'fun askDone('), contains('AskOverlay.hide(id)'));
      expect(_body(service, 'fun finish('), contains('AskOverlay.hide()'));
      final start = service.indexOf('ACTION_ALLOW, ACTION_DENY ->');
      expect(service.indexOf('AskOverlay.hide(id)', start), greaterThan(start));
      expect(_body(_src('$_hands/MindHands.kt'), 'override fun onDestroy('), contains('AskOverlay.hide()'));
    });

    test('🔒 ไม่ต้องขอสิทธิ์แสดงทับแอปอื่น · จอล็อกไม่ขึ้นและกดไม่ได้ · ปุ่มรอก่อนกดได้ · กันของหลอกทับ', () {
      final overlay = _src('$_hands/AskOverlay.kt');
      expect(overlay, contains('TYPE_ACCESSIBILITY_OVERLAY'));
      expect(overlay, isNot(contains('TYPE_APPLICATION_OVERLAY')));
      expect(_src('android/app/src/main/AndroidManifest.xml'), isNot(contains('SYSTEM_ALERT_WINDOW')));
      expect(_body(overlay, 'private fun attach('), contains('locked(service)'));
      expect(_body(overlay, 'private fun answer('), contains('if (locked(context)) return'));
      expect(overlay, contains('Intent.ACTION_SCREEN_OFF -> detach()'));
      expect(overlay, contains('filterTouchesWhenObscured = true'));
      expect(overlay, contains('isEnabled = false'));
      expect(overlay, contains('}, ARM_MS)'));
    });

    test('🔒 ระหว่างกล่องขึ้น นิ้วจำลองของเธอแตะอะไรไม่ได้ · อนุมัติตัวเองไม่ได้', () {
      final send = _body(_src('$_hands/MindHands.kt'), 'private fun send(');
      expect(send.indexOf('if (AskOverlay.showing) return false'), lessThan(send.indexOf('dispatchGesture(')));
    });

    test('ปุ่มมีทั้งไทยและอังกฤษ', () {
      for (final dir in ['values', 'values-en']) {
        final xml = _src('android/app/src/main/res/$dir/strings.xml');
        expect(xml, contains('name="hands_allow"'));
        expect(xml, contains('name="hands_deny"'));
      }
    });
  });
}
