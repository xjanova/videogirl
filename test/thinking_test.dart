/// อนิเมชั่นตอนเธอกำลังคิด
///
/// ช่วงนี้ยาวจริง — สมองในเครื่องใช้เวลาหลายวินาทีต่อคำตอบ · ถ้าจอนิ่งสนิท
/// ระหว่างนั้น คนกดจะอ่านว่าแอปค้าง แล้วกดซ้ำ (การกดซ้ำถูกกันไว้ที่ state
/// แต่**ความรู้สึกว่าแอปค้าง**ไม่มีอะไรกันไว้เลย)
///
/// เทสต์นี้จับสองอย่างที่หลุดง่ายและไม่มีใครเห็นตอนดูด้วยตา:
/// จุดขยับจริงหรือแค่วาดค้างไว้ · และธง `sending` ที่ทั้งสี่จุดบนจอฟังอยู่
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/theme/tokens.dart';
import 'package:videogirl/widgets/thinking.dart';

/// สมองที่ค้างอยู่จนกว่าจะสั่งให้ตอบ — จำลองช่วงที่เธอกำลังคิด
class _SlowBrain extends OpenAiClient {
  _SlowBrain();

  final gate = Completer<String>();

  @override
  bool get usable => true;

  @override
  Future<String> reply({
    required String system,
    required List<Turn> history,
    String? model,
  }) =>
      gate.future;

  @override
  void close() {}
}

Widget _wrap(Widget child, {bool stillness = false}) => MaterialApp(
      locale: const Locale('th'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLang.values.map((l) => l.locale),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: stillness),
        child: Scaffold(body: Center(child: child)),
      ),
    );

/// Transform เฉพาะที่อยู่ในจุดสามจุด — MaterialApp กับ Scaffold มีของตัวเองด้วย
Finder get _dots => find.descendant(
      of: find.byType(ThinkingDots),
      matching: find.byType(Transform),
    );

/// ตำแหน่งแนวตั้งของจุดทั้งสาม ณ เฟรมนี้
List<double> _dotTops(WidgetTester t) => t
    .widgetList<Transform>(_dots)
    .map((w) => w.transform.getTranslation().y)
    .toList();

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('จุดสามจุด', () {
    testWidgets('มีสามจุดเสมอ', (t) async {
      await t.pumpWidget(_wrap(const ThinkingDots(color: Colors.white)));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byType(ThinkingDots), findsOneWidget);
      // จุดละสอง Transform (ลอยขึ้น + ย่อขยาย)
      expect(_dots, findsNWidgets(6));
    });

    testWidgets('🔴 ต้องขยับจริง ไม่ใช่วาดค้างไว้เฉย ๆ', (t) async {
      await t.pumpWidget(_wrap(const ThinkingDots(color: Colors.white)));
      await t.pump(const Duration(milliseconds: 60));
      final first = _dotTops(t);

      await t.pump(const Duration(milliseconds: 260));
      final later = _dotTops(t);

      expect(later, isNot(equals(first)),
          reason: 'จุดที่ไม่ขยับ = ภาพนิ่งที่อ่านว่าแอปค้าง ซึ่งแย่กว่าไม่มี');
    });

    testWidgets('จุดไม่ขยับพร้อมกันทั้งสามจุด', (t) async {
      await t.pumpWidget(_wrap(const ThinkingDots(color: Colors.white)));
      await t.pump(const Duration(milliseconds: 200));

      final tops = _dotTops(t).toSet();
      expect(tops.length, greaterThan(1),
          reason: 'ขยับพร้อมกันหมดอ่านเป็นการกะพริบ ไม่ใช่การไล่กัน');
    });

    testWidgets('ปิดอนิเมชั่นในเครื่องแล้วต้องนิ่ง แต่ยังเห็นครบสามจุด',
        (t) async {
      await t.pumpWidget(
          _wrap(const ThinkingDots(color: Colors.white), stillness: true));
      await t.pump(const Duration(milliseconds: 60));
      final first = _dotTops(t);

      await t.pump(const Duration(milliseconds: 400));
      expect(_dotTops(t), equals(first),
          reason: 'คนที่ปิดอนิเมชั่นมักปิดเพราะการเคลื่อนไหวทำให้เวียนหัว');
      expect(_dots, findsNWidgets(3));
    });

    testWidgets('ตัวอ่านหน้าจอต้องรู้ว่ากำลังรออะไรอยู่', (t) async {
      await t.pumpWidget(_wrap(const ThinkingDots(color: Colors.white)));
      await t.pump(const Duration(milliseconds: 60));

      expect(
        find.bySemanticsLabel(const S(AppLang.th).thinkingLabel),
        findsOneWidget,
        reason: 'จุดสามจุดไม่มีความหมายกับคนที่ฟังจอ',
      );
    });

    testWidgets('ถอดออกจากจอแล้วตัวขับอนิเมชั่นต้องถูกปล่อย', (t) async {
      await t.pumpWidget(_wrap(const ThinkingDots(color: Colors.white)));
      await t.pump(const Duration(milliseconds: 60));

      await t.pumpWidget(_wrap(const SizedBox.shrink()));
      await t.pump(const Duration(seconds: 2));
      // AnimationController ที่ค้างไว้จะทำให้เฟรมวิ่งตลอดกาล
      // และ flutter_test จะฟ้องตอนจบเทสต์ถ้ามีตัวที่ยังไม่ถูก dispose
      expect(find.byType(ThinkingDots), findsNothing);
    });
  });

  group('ฟองกำลังคิด', () {
    testWidgets('ฟองในแผงแชทใช้สีตามโหมด', (t) async {
      await t.pumpWidget(_wrap(const ThinkingBubble(mode: MindMode.love)));
      await t.pump(const Duration(milliseconds: 60));
      expect(find.byType(ThinkingDots), findsOneWidget);
    });

    testWidgets('ฟองบนเวทีเป็นกระจก ไม่ทึบจนบังหน้าเธอ', (t) async {
      await t.pumpWidget(_wrap(const ThinkingPuff()));
      await t.pump(const Duration(milliseconds: 60));

      final box = t.widget<Container>(
        find
            .descendant(
              of: find.byType(ThinkingPuff),
              matching: find.byType(Container),
            )
            .first,
      );
      final deco = box.decoration! as BoxDecoration;
      expect(deco.color, MindColors.glass72,
          reason: 'ฟองลอยทับตัวเธอ ถ้าทึบจะบังหน้า');
    });
  });

  group('ธงที่ทั้งจอฟังอยู่', () {
    // เทสต์ธรรมดา ไม่ใช่ testWidgets — ในโซนเวลาปลอมของ testWidgets
    // future จะเดินต่อก็ต่อเมื่อมีการ pump ซึ่งทำให้ `await` ที่นี่ค้างตลอดกาล
    test('🔴 กำลังคิดอยู่ = sending ต้องเป็นจริงตลอดช่วงนั้น', () async {
      final brain = _SlowBrain();
      final s = MindState(openai: brain);
      await s.load();
      s.setBrain(BrainProvider.openai);
      await s.setOpenAiKey('sk-test-key-for-unit-tests');

      expect(s.sending, isFalse);

      final pending = s.send('วันนี้มีนัดไหม');
      await Future<void>.delayed(Duration.zero);
      expect(s.sending, isTrue,
          reason: 'ทั้งฟองบนเวที ปุ่มพับ ฟองในแผง และปุ่มส่ง อ่านธงนี้ตัวเดียว');

      brain.gate.complete('บ่ายว่างค่ะ');
      await pending;
      expect(s.sending, isFalse);
      s.dispose();
    });
  });
}
