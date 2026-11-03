import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/widgets/ambient_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('เดินตาม fps ที่ตั้ง ไม่ใช่ทุก vsync', (t) async {
    final c = AmbientClock(fps: 12);
    var ticks = 0;
    c.addListener(() => ticks++);
    c.setRunning(true);
    await t.pump(const Duration(seconds: 1));
    expect(ticks, inInclusiveRange(11, 12));
    c.dispose();
  });

  testWidgets('แอปไปอยู่เบื้องหลัง = หยุดปลุก CPU · กลับมา = เดินต่อจากเดิม', (t) async {
    final c = AmbientClock(fps: 30);
    var ticks = 0;
    c.addListener(() => ticks++);
    c.setRunning(true);

    c.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(c.running, isFalse);
    await t.pump(const Duration(seconds: 1));
    expect(ticks, 0);

    // จอลอย (PiP) ยังเห็นเธออยู่ · ต้องเดิน
    c.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(c.running, isTrue);
    c.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(c.running, isFalse);
    c.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(c.running, isTrue);
    c.dispose();
  });

  testWidgets('ปิดเอง (แท็บอื่น) = หยุด · dispose แล้วสั่งเดินไม่พัง', (t) async {
    final c = AmbientClock(fps: 30);
    c.setRunning(true);
    c.setRunning(false);
    expect(c.running, isFalse);
    c.dispose();
    c.setRunning(true);
    expect(c.running, isFalse);
  });

  test('ก้อนแสงกับวงแหวนไม่ใช้ ticker วนไม่รู้จบแล้ว', () {
    final bg = File('lib/widgets/liquid_background.dart').readAsStringSync();
    final home = File('lib/screens/home_screen.dart').readAsStringSync();
    expect(bg, isNot(contains('.repeat()')));
    expect(bg, contains('AmbientClock(fps: 12)'));
    expect(home, isNot(contains('AnimationController(vsync: this, duration: const Duration(seconds: 3))')));
    expect(home, contains('final _ring = AmbientClock(fps: 30);'));
    // ออกจากแท็บเธอ = หยุดทั้งคู่
    expect(home, contains('_ring.setRunning(widget.active);'));
    expect(home, contains('animate: widget.active,'));
  });
}
