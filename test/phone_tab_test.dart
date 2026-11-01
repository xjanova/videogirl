/// แท็บ "โทรศัพท์" ในแถบล่าง
///
/// ที่มา (2026-11-01, 0.1.53): แป้นโทรมีแล้วแต่ในแอปไม่มีทางเข้า · เจ้าของ:
/// "ต้องมีปุ่มกดโทรสิจะเข้ายังไง" · ไทม์ไลน์ย้ายไปเป็นปุ่มสลับในแท็บปฏิทิน
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/theme/tokens.dart';
import 'package:videogirl/widgets/segment_switch.dart';

void main() {
  test('ชื่อคำสั่งเปิดแป้นโทรตรงกันทั้ง Dart และ Kotlin', () {
    final dart = File('lib/phone/dialer.dart').readAsStringSync();
    final kotlin = File(
            'android/app/src/main/kotlin/com/xjanova/videogirl/MainActivity.kt')
        .readAsStringSync();
    expect(dart.contains("invokeMethod<bool>('openDialer')"), isTrue);
    expect(kotlin.contains('"openDialer" ->'), isTrue,
        reason: 'ชื่อไม่ตรง = แตะแท็บโทรศัพท์แล้วได้ notImplemented เงียบ ๆ');
  });

  // 0.1.53: แตะไอคอนโทรศัพท์แล้วแอปเด้งออกทุกครั้ง · logcat: NPE ใน
  // PhoneWindow.getInsetsController เพราะยังไม่มี DecorView · จอสายเข้าเรียกที่เดียวกัน
  test('🔴 edgeToEdge สร้าง decorView ก่อนแตะ insetsController', () {
    final ui = File(
            'android/app/src/main/kotlin/com/xjanova/videogirl/PhoneUi.kt')
        .readAsStringSync();
    final start = ui.indexOf('fun edgeToEdge(');
    expect(start, isNot(-1));
    // คอมเมนต์ในฟังก์ชันพูดถึง insetsController ด้วย · ดูเฉพาะโค้ด
    final body = ui.substring(start).replaceAll(RegExp(r'//[^\n]*'), '');
    final decor = body.indexOf('window.decorView');
    final insets = body.indexOf('window.insetsController');
    expect(decor, isNot(-1));
    expect(insets, isNot(-1));
    expect(decor < insets, isTrue,
        reason: 'แป้นโทรและจอสายเรียก edgeToEdge ก่อน setContentView');
  });

  test('แถบล่างมีแท็บโทรศัพท์ และยังเป็นเลขคี่ มายด์อยู่กลาง', () {
    final shell = File('lib/shell.dart').readAsStringSync();
    final m = RegExp(r'_order = <int>\[([^\]]*)\]').firstMatch(shell);
    expect(m, isNotNull);
    final order = m!.group(1)!.split(',').map((s) => s.trim()).toList();
    expect(order, contains('_phoneTab'));
    expect(order.length.isOdd, isTrue);
    expect(order[order.length ~/ 2], '0');
  });

  testWidgets('ปุ่มสลับ: แตะช่องอื่นสลับ · แตะช่องที่เลือกอยู่ไม่ทำอะไร',
      (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MindSegmentSwitch(
          labels: const ['ปฏิทิน', 'ไทม์ไลน์'],
          selected: 0,
          mode: MindMode.work,
          onSelect: picked.add,
        ),
      ),
    ));
    await tester.tap(find.text('ปฏิทิน'));
    await tester.tap(find.text('ไทม์ไลน์'));
    await tester.pump();
    expect(picked, [1]);
  });
}
