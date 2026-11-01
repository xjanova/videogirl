import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/background/mind_background.dart' show kPrefBgUpdate;
import 'package:videogirl/theme/tokens.dart';
import 'package:videogirl/update/update_prompt.dart';
import 'package:videogirl/update/updater.dart';
import 'package:videogirl/widgets/update_sheet.dart';

const _info = UpdateInfo(
  version: '0.1.55',
  notes: '· a phone tab',
  apkUrl: 'https://example.invalid/a.apk',
  apkName: 'giggok-0.1.55.apk',
  sizeBytes: 94371840,
  sha256: null,
);

void main() {
  // เจ้าของ 2026-11-01: "ระบบอัพเดท ควรเด้งขึ้นมาเมื่อมีเวอร์ชั่นใหม่ไม่ใช่เหรอ"
  group('เมื่อไหร่ถึงเวลาถามหลังบ้าน', () {
    final t0 = DateTime(2026, 11, 1, 12);

    test('เปิดแอปครั้งแรกในโปรเซสนี้ = ถามเลย', () {
      expect(UpdatePrompt.isDue(lastCheck: null, now: t0), isTrue);
    });

    test('กลับเข้าแอปถี่ ๆ ไม่ยิงซ้ำ · ครบรอบแล้วถามใหม่', () {
      expect(
          UpdatePrompt.isDue(
              lastCheck: t0, now: t0.add(const Duration(minutes: 5))),
          isFalse);
      expect(
          UpdatePrompt.isDue(
              lastCheck: t0, now: t0.add(UpdatePrompt.recheckEvery)),
          isTrue);
    });

    test('บริการเบื้องหลังเจอรุ่นที่ยังไม่ได้บอก = ถามทันทีไม่รอรอบ', () {
      final soon = t0.add(const Duration(minutes: 1));
      expect(
          UpdatePrompt.isDue(
              lastCheck: t0, now: soon, bgFound: '0.1.55', bgSeen: null),
          isTrue);
      expect(
          UpdatePrompt.isDue(
              lastCheck: t0, now: soon, bgFound: '0.1.55', bgSeen: '0.1.55'),
          isFalse);
    });

    test('นาฬิกาถูกตั้งย้อน = ถาม ไม่เงียบไปหลายชั่วโมง', () {
      expect(
          UpdatePrompt.isDue(
              lastCheck: t0, now: t0.subtract(const Duration(hours: 3))),
          isTrue);
    });
  });

  group('ไว้ทีหลัง', () {
    final now = DateTime(2026, 11, 1, 12);
    final ms = now.millisecondsSinceEpoch;

    test('เลื่อนรุ่นนี้ไว้ = ไม่ถามรุ่นนี้จนหมดเวลา', () {
      final until = ms + const Duration(hours: 2).inMilliseconds;
      expect(
          UpdatePrompt.isSnoozed(
              version: '0.1.55',
              snoozedVersion: '0.1.55',
              untilMs: until,
              now: now),
          isTrue);
      expect(
          UpdatePrompt.isSnoozed(
              version: '0.1.55',
              snoozedVersion: '0.1.55',
              untilMs: ms - 1,
              now: now),
          isFalse);
    });

    test('รุ่นที่ใหม่กว่ารุ่นที่เลื่อนไว้ = ถามทันที', () {
      expect(
          UpdatePrompt.isSnoozed(
              version: '0.1.56',
              snoozedVersion: '0.1.55',
              untilMs: ms + 1000,
              now: now),
          isFalse);
    });

    test('เวลาที่เลื่อนไว้ไกลเกินจริง (นาฬิกาเคยเดินหน้าผิด) ไม่เชื่อ', () {
      final far = ms + const Duration(days: 30).inMilliseconds;
      expect(
          UpdatePrompt.isSnoozed(
              version: '0.1.55',
              snoozedVersion: '0.1.55',
              untilMs: far,
              now: now),
          isFalse);
    });

    test('จำไว้ในเครื่อง · เปิดแอปใหม่ก็ยังเลื่อนอยู่', () async {
      SharedPreferences.setMockInitialValues({});
      var clock = DateTime(2026, 11, 1, 12);
      final a = UpdatePrompt(now: () => clock);
      await a.snooze('0.1.55');

      final b = UpdatePrompt(now: () => clock); // โปรเซสใหม่
      expect(await b.snoozed('0.1.55'), isTrue);
      expect(await b.snoozed('0.1.56'), isFalse);

      clock = clock.add(UpdatePrompt.snoozeFor + const Duration(minutes: 1));
      expect(await b.snoozed('0.1.55'), isFalse);
    });

    test('รอบถามนับในโปรเซส · ค่าจากบริการเบื้องหลังปลุกได้ทันที', () async {
      SharedPreferences.setMockInitialValues({});
      var clock = DateTime(2026, 11, 1, 12);
      final p = UpdatePrompt(now: () => clock);
      expect(await p.due(), isTrue);
      await p.markChecked();
      clock = clock.add(const Duration(minutes: 2));
      expect(await p.due(), isFalse);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefBgUpdate, '0.1.55');
      expect(await p.due(), isTrue);
      await p.markChecked();
      expect(await p.due(), isFalse);
    });
  });

  group('กล่องเด้ง', () {
    Future<Updater> pumpSheet(WidgetTester tester, List<bool?> results) async {
      final up = Updater();
      addTearDown(up.dispose);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: up,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  results.add(await showModalBottomSheet<bool>(
                    context: context,
                    builder: (_) =>
                        UpdateSheet(info: _info, mode: MindMode.values.first),
                  ));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return up;
    }

    testWidgets('บอกรุ่นใหม่และขนาดไฟล์ · ไม่โหลดเองก่อนกด', (tester) async {
      final results = <bool?>[];
      final up = await pumpSheet(tester, results);
      expect(find.text('Version 0.1.55 available'), findsOneWidget);
      expect(find.textContaining('Update now · 90.0 MB'), findsOneWidget);
      expect(up.stage, UpdateStage.idle);
    });

    testWidgets('ไว้ทีหลัง = ปิดกล่องและบอกว่าไม่ได้กดอัปเดต · แตะรัวปิดครั้งเดียว',
        (tester) async {
      final results = <bool?>[];
      await pumpSheet(tester, results);
      await tester.tap(find.text('Later'));
      await tester.tap(find.text('Later'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(results, [false]);
      expect(find.text('open'), findsOneWidget); // จอใต้กล่องยังอยู่
    });
  });

  test('เชลล์ต่อกล่องเด้งไว้ · ฟังการกลับเข้าแอป รอหน้าเปิดแอป และไม่ขวางสาย', () {
    final src = File('lib/shell.dart').readAsStringSync();
    expect(src, contains('AppLifecycleListener(onResume:'));
    expect(src, contains('gate.addListener(_onSplashGone)'));
    expect(src, contains('CallState.idle'));
    expect(src, contains('_life?.dispose()'));
    expect(src, contains('_calls?.removeListener(_showUpdateIfFree)'));
  });
}
