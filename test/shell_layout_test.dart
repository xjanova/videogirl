/// เนื้อหาทุกแท็บต้องเต็มจอ
///
/// ที่มา (2026-11-01, 0.1.50): เจ้าของเจอ "แอพมืด" ทุกแท็บ เหลือแต่แถบนำทาง
/// กับก้อนแสงก้อนเดียว · บนเครื่อง uiautomator เห็นแค่ปุ่มแถบนำทาง และก้อนแสงที่
/// อิงขอบขวา/ล่างไปโผล่ผิดที่ = ตัวเนื้อหามีขนาด 0×0 · ไม่มี error สักบรรทัด
/// เพราะ Flutter ถือว่า Stack ขนาดศูนย์เป็นเรื่องปกติ
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// โครงเดียวกับ body ของ MindShell: แท็บเต็มพื้นที่ + แถบงานที่ตอนว่าง
/// คืน SizedBox.shrink แบบไม่ Positioned
Widget _shellBody(StackFit fit, Key tabs) => MaterialApp(
      home: Scaffold(
        extendBody: true,
        body: Stack(
          fit: fit,
          children: [
            Positioned.fill(child: SizedBox(key: tabs)),
            const SizedBox.shrink(),
          ],
        ),
      ),
    );

void main() {
  testWidgets('Stack แบบเดิมโดนแถบงานที่ว่างบีบเหลือ 0×0', (tester) async {
    const tabs = Key('tabs');
    await tester.pumpWidget(_shellBody(StackFit.loose, tabs));
    expect(tester.getSize(find.byKey(tabs)), Size.zero);
  });

  testWidgets('StackFit.expand ให้แท็บเต็มจอ แม้ไม่มีงานค้าง', (tester) async {
    const tabs = Key('tabs');
    await tester.pumpWidget(_shellBody(StackFit.expand, tabs));
    expect(tester.getSize(find.byKey(tabs)),
        tester.getSize(find.byType(Scaffold)));
  });

  test('body ของ MindShell ยังเป็น Stack แบบ expand', () {
    final shell = File('lib/shell.dart').readAsStringSync();
    expect(
      RegExp(r'body: Stack\(\s*fit: StackFit\.expand,').hasMatch(shell),
      isTrue,
      reason: 'ไม่มี expand = ทุกแท็บขนาด 0×0 จอดำทั้งแอปตอนไม่มีงานในเครื่อง',
    );
  });
}
