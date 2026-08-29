import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/theme/tokens.dart';
import 'package:videogirl/widgets/mind_nav_bar.dart';

const _tabs = <MindNavItem>[
  MindNavItem(
      index: 0, label: 'มายด์', icon: Icons.face_retouching_natural_rounded),
  MindNavItem(index: 1, label: 'เมล', icon: Icons.mail_outline_rounded),
  MindNavItem(index: 2, label: 'ปฏิทิน', icon: Icons.calendar_today_rounded),
  MindNavItem(index: 3, label: 'ไทม์ไลน์', icon: Icons.timeline_rounded),
  MindNavItem(index: 4, label: 'ตั้งค่า', icon: Icons.tune_rounded),
];
const _order = <int>[1, 2, 0, 3, 4];

const _w = 360.0, _h = 800.0, _dpr = 3.0;

void _screen(WidgetTester t, {double safeBottom = 34}) {
  t.view.devicePixelRatio = _dpr;
  t.view.physicalSize = const Size(_w * _dpr, _h * _dpr);
  t.view.padding = FakeViewPadding(bottom: safeBottom * _dpr);
  t.view.viewPadding = FakeViewPadding(bottom: safeBottom * _dpr);
  addTearDown(t.view.reset);
}

Widget _app({
  required int current,
  required void Function(int) onSelect,
  bool speaking = false,
}) {
  return MaterialApp(
    home: Scaffold(
      extendBody: true,
      body: const SizedBox.expand(),
      bottomNavigationBar: MindNavBar(
        items: [for (final i in _order) _tabs[i]],
        current: current,
        centerIndex: 0,
        mode: MindMode.work,
        avatarReady: true,
        speaking: speaking,
        onSelect: onSelect,
      ),
    ),
  );
}

void main() {
  testWidgets('เต็มความกว้าง ชนขอบล่าง สูงตามสูตร', (t) async {
    _screen(t);
    await t.pumpWidget(_app(current: 0, onSelect: (_) {}));
    await t.pump(const Duration(milliseconds: 400));

    final bar = t.getRect(find.byType(MindNavBar));
    expect(bar.left, 0);
    expect(bar.right, _w);
    expect(bar.bottom, _h);
    expect(bar.height, MindNavBar.lift + MindNavBar.barHeight + 34);
  });

  testWidgets('ปุ่มกลางอยู่กึ่งกลางแนวนอน และยกพ้นแผ่นกระจก', (t) async {
    _screen(t);
    await t.pumpWidget(_app(current: 0, onSelect: (_) {}));
    await t.pump(const Duration(milliseconds: 400));

    final bar = t.getRect(find.byType(MindNavBar));
    final face =
        t.getRect(find.byIcon(Icons.face_retouching_natural_rounded));
    expect(face.center.dx, closeTo(_w / 2, 0.5));
    // ยอดปุ่มแตะขอบบนของวิดเจ็ตพอดี = ยก 16px พ้นแผ่นกระจก
    expect(face.center.dy - MindNavBar.faceSize / 2, closeTo(bar.top, 1));
  });

  testWidgets('กดได้ทุกแท็บ รวมทั้งยอดปุ่มกลางที่พ้นแผ่นกระจกออกมา', (t) async {
    _screen(t);
    var picked = -1;
    await t.pumpWidget(_app(current: 1, onSelect: (i) => picked = i));
    await t.pump(const Duration(milliseconds: 400));

    await t.tap(find.text('ตั้งค่า'));
    expect(picked, 4);

    final bar = t.getRect(find.byType(MindNavBar));
    await t.tapAt(Offset(_w / 2, bar.top + 4));
    expect(picked, 0, reason: 'ครึ่งบนของปุ่มกลางต้องกดได้');
  });

  testWidgets('กดแท็บที่เลือกอยู่ซ้ำ ๆ ไม่ยิง callback', (t) async {
    _screen(t);
    var hits = 0;
    await t.pumpWidget(_app(current: 4, onSelect: (_) => hits++));
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('ตั้งค่า'));
    await t.tap(find.text('ตั้งค่า'));
    expect(hits, 0);
  });

  testWidgets('safe area = 0 (ปุ่มสามเหลี่ยม/แท็บเล็ต) ก็ยังวางถูก', (t) async {
    _screen(t, safeBottom: 0);
    await t.pumpWidget(_app(current: 0, onSelect: (_) {}));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.getRect(find.byType(MindNavBar)).height,
        MindNavBar.lift + MindNavBar.barHeight);
  });

  testWidgets('safe area 48 (ปุ่มสามปุ่มแบบเก่า) กระจกยืดตาม', (t) async {
    _screen(t, safeBottom: 48);
    await t.pumpWidget(_app(current: 0, onSelect: (_) {}));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.getRect(find.byType(MindNavBar)).height,
        MindNavBar.lift + MindNavBar.barHeight + 48);
  });

  testWidgets('พูดอยู่แล้วหยุด — ticker ไม่ค้าง', (t) async {
    _screen(t);
    await t.pumpWidget(_app(current: 0, onSelect: (_) {}, speaking: true));
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpWidget(_app(current: 0, onSelect: (_) {}, speaking: false));
    await t.pumpAndSettle();
  });
}
