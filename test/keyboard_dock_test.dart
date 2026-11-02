import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ช่องพิมพ์แชทจมใต้คีย์บอร์ด — วัดบนเครื่องจริง (vivo V2144, 2.75x):
/// ขอบบนคีย์บอร์ด 1498 · ช่องพิมพ์ [1458..1563] · จมไป 65px
///
/// สาเหตุ: เพดานแผงแชทอยู่ในคอลัมน์ที่ให้ maxHeight อนันต์ จึงคิดจากความสูงจอ
/// ทั้งจอ · และ Scaffold ลบ viewInsets ออกจาก MediaQuery ของ body ด้วย
/// (อ่านคีย์บอร์ดจากตรงนั้นได้ 0) · แผงสูงเกินที่เหลือ คอลัมน์ล้นลงใต้คีย์บอร์ด
///
/// โครงจำลองเดียวกับหน้าเธอ: หัวจอ → เวที (Expanded) → แผงแชทที่มีเพดาน → ช่องพิมพ์
enum _Cap { screenOnly, screenMinusInsets, column }

Widget _home(_Cap how, double keyboard) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(392, 872),
        padding: const EdgeInsets.only(top: 24),
        viewInsets: EdgeInsets.only(bottom: keyboard),
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: LayoutBuilder(builder: (context, col) {
            final screen = MediaQuery.sizeOf(context).height;
            final cap = switch (how) {
              _Cap.screenOnly => screen * .58,
              _Cap.screenMinusInsets =>
                (screen - MediaQuery.viewInsetsOf(context).bottom) * .58,
              _Cap.column => math.min(screen * .58, col.maxHeight * .72),
            };
            return Column(children: [
              const SizedBox(height: 60), // หัวจอ
              const Expanded(child: SizedBox()), // เวที
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: cap),
                child: const Column(mainAxisSize: MainAxisSize.min, children: [
                  // บทสนทนายาว ๆ เลื่อนได้ · กินที่เต็มเพดาน
                  Flexible(child: SingleChildScrollView(child: SizedBox(height: 2000))),
                  TextField(key: ValueKey('input')),
                ]),
              ),
            ]);
          }),
        ),
      ),
    ),
  );
}

/// ขอบล่างของช่องพิมพ์ · null = คอลัมน์ล้น
Future<double?> _inputBottom(WidgetTester t, _Cap how, {double keyboard = 328}) async {
  t.view.physicalSize = const Size(392, 872);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(_home(how, keyboard));
  if (t.takeException() != null) return null;
  return t.getBottomLeft(find.byKey(const ValueKey('input'))).dy;
}

void main() {
  testWidgets('คีย์บอร์ดเปิด: ช่องพิมพ์อยู่เหนือคีย์บอร์ดทั้งช่อง', (t) async {
    final bottom = await _inputBottom(t, _Cap.column);
    expect(bottom, isNotNull, reason: 'คอลัมน์ล้น');
    expect(bottom, lessThanOrEqualTo(872 - 328));
  });

  // RenderFlex รายงานล้นครั้งเดียวต่อตัว · แยกเทสต์ ไม่งั้นรอบสองเงียบ
  testWidgets('สูตรเดิม (ความสูงจอ) ล้นจริง — เทสต์นี้จับบั๊กได้', (t) async {
    expect(await _inputBottom(t, _Cap.screenOnly), isNull);
  });

  testWidgets('อ่านคีย์บอร์ดจาก MediaQuery ใน body ไม่ได้ · Scaffold ลบทิ้งไปแล้ว', (t) async {
    expect(await _inputBottom(t, _Cap.screenMinusInsets), isNull);
  });

  testWidgets('ตอนพักไม่มีคีย์บอร์ด เพดานเท่าเดิม (58% ของจอ)', (t) async {
    t.view.physicalSize = const Size(392, 872);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_home(_Cap.column, 0));
    final dock = t.getSize(find.byType(ConstrainedBox).last).height;
    expect(dock, closeTo(872 * .58, 1));
  });

  test('หน้าเธอคิดเพดานจากคอลัมน์จริง', () {
    final home = File('lib/screens/home_screen.dart').readAsStringSync();
    expect(home, contains('child: _cappedDock(state, mode, col.maxHeight))'));
    expect(home, contains('math.min(screen * _dockMaxShare, column * _dockMaxOfColumn)'));
  });
}
