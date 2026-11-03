/// จอไม่ดับระหว่างคุยกับมายด์
///
/// เจ้าของ (v0.1.70): "เรื่องที่กำลังใช้งาน มายด์ คุยงาน หรือ บังคับเครื่อง ต้องจอไม่ดับ" ·
/// พิมพ์ถามแล้ววางเครื่องรอ · เธอคิดนาน (ค้นเว็บ ใช้มือ) เกินเวลาจอดับ 2 นาที = จอดับกลางคำตอบ ·
/// ของเดิมเป็นธงตัวเดียวที่สตูดิโอกับคุยต่อเนื่องใช้ร่วมกัน ออกจากสตูดิโอกลางคุย = ธงหลุด
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final kotlin = File('android/app/src/main/kotlin/com/xjanova/videogirl/MindStudio.kt').readAsStringSync();
  final app = File('lib/main.dart').readAsStringSync();

  String body(String src, String fun) {
    final start = src.indexOf(fun);
    expect(start, isNonNegative, reason: 'ไม่เจอ $fun');
    final open = src.indexOf('{', start);
    var depth = 0;
    for (var i = open; i < src.length; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}' && --depth == 0) return src.substring(open, i + 1);
    }
    fail('$fun ไม่ปิดวงเล็บ');
  }

  test('🔴 จอค้างนับผู้ถือ · ปล่อยครบทุกคนจอถึงดับได้', () {
    final keep = body(kotlin, 'private fun keepScreenOn(');
    expect(keep, contains('holders.add(who)'));
    expect(keep, contains('holders.remove(who)'));
    expect(keep, contains('holders.isNotEmpty()'));
    expect(keep, contains('FLAG_KEEP_SCREEN_ON'));
  });

  test('🔴 wake lock ระดับจอ (ใช้ได้ตอนแอปอื่นอยู่บนจอ) · ไม่ปลุกจอที่ดับอยู่ · หมดอายุเอง', () {
    final hold = body(kotlin, 'private fun holdScreen(');
    expect(hold, contains('SCREEN_BRIGHT_WAKE_LOCK'));
    expect(hold, contains('ON_AFTER_RELEASE'));
    expect(hold, isNot(contains('ACQUIRE_CAUSES_WAKEUP')));
    expect(hold, contains('setReferenceCounted(false)'));
    expect(hold, contains('acquire(HOLD_MS)'));
    // Activity หาย = ปล่อยทันที ไม่ค้างจนหมดเวลา
    expect(body(kotlin, 'fun detach('), contains('letScreenSleep()'));
  });

  test('🔴 เธอคิด พูด หรือใช้เครื่องอยู่ = ถือจอ · ติดสาย = ไม่ถือ', () {
    final turn = body(app, 'void _watchTurn(');
    for (final s in ['_state.sending', '_state.speaking', '_state.phoneTask != null', 'CallState.idle']) {
      expect(turn, contains(s));
    }
    expect(turn, contains("_holdScreen(busy, 'turn')"));
    expect(app, contains('_state.addListener(_watchTurn)'));
    expect(app, contains('_calls.addListener(_watchTurn)'));
    expect(app, contains("_holdScreen(on, 'voice')"));
  });
}
