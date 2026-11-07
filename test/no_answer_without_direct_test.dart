/// เสียงตรงหลุด = มายด์ไม่รับเอง ปล่อยกริ่งดังให้เจ้าของ
///
/// เจ้าของ: "ถ้า debug wifi หลุด ระบบรับสายเอง จะได้ยิน มายด์ ปกติไหม" → "แก้เลย" · บน vivo V2144 ทางลำโพง
/// ปลายสายไม่ได้ยิน · ด่านเดิมมีอยู่แล้ว แต่ถามตัวช่วยต่อคิวหลังงานต่อเสียงตรงเบื้องหลัง (หลายสิบวิ)
/// แล้ว "ตอบไม่ทันสามวิ = รับ" · คู่สายได้ยินความเงียบ
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _kotlin = 'android/app/src/main/kotlin/com/xjanova/videogirl';
String _src(String name) => File('$_kotlin/$name').readAsStringSync();

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

void main() {
  test('🔴 ถามตัวช่วยตอนกริ่งดังบนเธรดของตัวเอง ไม่ต่อคิวหลังงานต่อเสียงตรง', () {
    final down = _body(_src('direct/setup/DirectAudioSetup.kt'), 'fun helperDown(');
    expect(down, isNot(contains('work.execute')), reason: 'คิวนั้นถูกงานต่อใหม่ถือไว้ได้หลายสิบวิ');
    expect(down, contains('Thread('));
    expect(down, contains('catch (_: Exception) { true }'), reason: 'ถามแล้วพัง = ถือว่าหลุด');
  });

  test('🔴 เครื่องที่ตั้งเสียงตรงไว้ ตัวช่วยตอบไม่ทัน = ไม่รับ · เครื่องที่ไม่เคยตั้ง ไม่ขวาง', () {
    final arm = _body(_src('InCallActivity.kt'), 'private fun armAutoAnswer(');
    expect(arm, contains('directDown == null && DirectAudioSetup.configured(this@InCallActivity)'));
    final gate = arm.indexOf('skip("direct_offline"');
    expect(gate, greaterThan(0));
    expect(arm.indexOf('letMindAnswer()'), greaterThan(gate), reason: 'ด่านต้องมาก่อนรับ');
    expect(arm.indexOf('DirectAudioMonitorService.missedCall(', gate), greaterThan(gate),
        reason: 'เจ้าของอาจไม่อยู่หน้าเครื่อง ต้องมีแจ้งเตือนบอก');
    final configured = _body(_src('direct/setup/DirectAudioSetup.kt'), 'fun configured(');
    expect(configured, contains('getString("token", null) != null'));
  });

  test('🔴 จบสายแล้วลองต่อเสียงตรงให้เอง · ระหว่างสายต่อไม่ได้ (setup ปฏิเสธ)', () {
    final gone = _body(_src('MindInCallService.kt'), 'private fun allCallsGone(');
    expect(gone, contains('DirectAudioMonitorService.callsGone(this)'));
    final monitor = _src('direct/setup/DirectAudioMonitorService.kt');
    final callsGone = _body(monitor, 'fun callsGone(');
    expect(callsGone, contains('if (!retryAfterCall) return'), reason: 'สายปกติไม่ไปปลุกการต่อใหม่ทุกครั้ง');
    expect(callsGone, contains('postDelayed('), reason: 'Telecom ยังบอกว่ามีสายอยู่ครู่หนึ่งหลังสายสุดท้ายหาย');
    final missed = _body(monitor, 'fun missedCall(');
    expect(missed, contains('retryAfterCall = true'));
    expect(missed, contains('IMPORTANCE_HIGH'), reason: 'การ์ดสถานะเดิมเงียบ (LOW) เจ้าของไม่เห็น');
    expect(missed, contains('ACTION_RETRY'));
  });

  test('ลองใหม่ระหว่างที่กำลังเช็กอยู่ไม่หาย · ต่อติดแล้วแจ้งเตือน "ปล่อยสายให้ดัง" หายเอง', () {
    final monitor = _src('direct/setup/DirectAudioMonitorService.kt');
    final retry = _body(monitor, 'private fun retry(');
    expect(retry, contains('nextAttempt = 0L'));
    expect(retry, contains('if (checking) retryPending = true'));
    final refresh = _body(monitor, 'private fun refresh(');
    expect(refresh, contains('if (result == "ready") manager.cancel(MISSED)'));
    expect(refresh, contains('if (retryPending)'));
  });

  test('ข้อความแจ้งเตือนมีทั้งไทยและอังกฤษ', () {
    for (final dir in ['values', 'values-en']) {
      final xml = File('android/app/src/main/res/$dir/strings.xml').readAsStringSync();
      for (final name in ['direct_missed_channel', 'direct_missed_title', 'direct_missed_text']) {
        expect(xml, contains('name="$name"'), reason: '$dir ขาด $name');
      }
    }
  });
}
