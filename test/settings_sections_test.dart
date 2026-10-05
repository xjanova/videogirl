/// หน้าตั้งค่าแบบแบ่งหมวด + ซีเรียลที่ต้องหาเจอเสมอ
///
/// ที่มา: เจ้าของถามว่า "คีย์ให้ใส่ซีเรียลอยู่ไหน" — ของเดิมช่องไลเซนส์โผล่
/// เฉพาะตอนเลือกสมองแบบพร็อกซี ซึ่งไม่ใช่ค่าตั้งต้น คนส่วนใหญ่จึงไม่เคยเห็นมัน
/// และหน้าตั้งค่าเป็นการ์ดสิบเจ็ดใบเรียงยาวในหน้าเดียว
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/avatar/avatar_pack.dart';
import 'package:videogirl/avatar/avatar_view.dart';
import 'package:videogirl/background/mind_watch.dart';
import 'package:videogirl/diagnostics/debug_reporter.dart';
import 'package:videogirl/diagnostics/mind_log.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_settings.dart';
import 'package:videogirl/persona/mind_soul.dart';
import 'package:videogirl/screens/settings_screen.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/store/mind_vault.dart';
import 'package:videogirl/system/permissions.dart';
import 'package:videogirl/update/updater.dart';

Future<(MindState, ValueNotifier<SettingsSection?>)> _mount(WidgetTester t) async {
  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);

  final state = MindState()..setBrain(BrainProvider.onDevice);
  final section = ValueNotifier<SettingsSection?>(null);
  addTearDown(section.dispose);

  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<MindState>.value(value: state),
      ChangeNotifierProvider(create: (_) => MindPermissions()),
      ChangeNotifierProvider(create: (_) => AvatarPacks()),
      ChangeNotifierProvider(create: (_) => MindSoul()),
      ChangeNotifierProvider(create: (_) => MindWatch()),
      ChangeNotifierProvider(create: (_) => MindVault(hasAllFiles: () => false)),
      ChangeNotifierProvider(create: (_) => Updater()),
      ChangeNotifierProvider(create: (_) => DebugReporter()),
      ChangeNotifierProvider(create: (_) => MindAvatarController()),
      ChangeNotifierProvider.value(value: state.memory),
    ],
    child: MaterialApp(home: Scaffold(body: SettingsScreen(section: section))),
  ));
  await t.pump(const Duration(milliseconds: 300));
  return (state, section);
}

/// ภาษาเดียวกับที่จอใช้จริง (MaterialApp ในเทสต์ไม่ได้ตั้ง locale)
S _s(WidgetTester t) => S.of(t.element(find.byType(SettingsScreen)));

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('หน้าแรกเป็นเมนูหมวด ไม่ใช่การ์ดเรียงยาว', (t) async {
    final (state, _) = await _mount(t);
    final s = _s(t);
    for (final title in [
      s.settingsSecAccount,
      s.settingsSecHer,
      s.settingsSecBrain,
      s.settingsSecYou,
      s.settingsSecCalls,
      s.settingsSecGeneral,
      s.settingsSecData,
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'ไม่มีหมวด $title');
    }
    expect(find.text(s.licenseSection), findsNothing,
        reason: 'การ์ดต้องอยู่ในหมวด ไม่ใช่หน้าเมนู');
    await t.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('🔴 ซีเรียลหาเจอได้ แม้ใช้สมองในเครื่อง (ไม่ใช่พร็อกซี)', (t) async {
    final (state, section) = await _mount(t);
    state.setLicenseKey('FREE-ABCDEFGHIJKLMNOPQRST');
    await t.pump();

    // หน้าเมนูบอกสถานะซีเรียลไว้ใต้หมวดบัญชีเลย ไม่ต้องเดาว่าอยู่หมวดไหน
    expect(find.textContaining('FREE'), findsOneWidget);

    final s = _s(t);
    await t.tap(find.text(s.settingsSecAccount));
    await t.pump(const Duration(milliseconds: 300));
    expect(section.value, SettingsSection.account);
    expect(find.text(s.licenseSerial), findsOneWidget);
    expect(find.text(s.licenseEnter), findsOneWidget,
        reason: 'ต้องมีที่ให้ใส่ซีเรียลที่ซื้อมา');
    expect(find.textContaining('ABCDEFGHIJKLMNOPQRST'), findsNothing,
        reason: 'ซีเรียลซ่อนกลางไว้ก่อน หน้าจอถูกแคปได้');

    await t.tap(find.text(s.licenseShow));
    await t.pump();
    expect(find.textContaining('ABCDEFGHIJKLMNOPQRST'), findsOneWidget);

    // ปิดหมวด = กลับเมนู (shell ทำแบบเดียวกันตอนกด Back)
    section.value = null;
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(s.licenseSerial), findsNothing);
    expect(find.text(s.settingsSecAccount), findsOneWidget);

    await t.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('ยังไม่มีซีเรียล = บอกตรง ๆ และมีปุ่มลองลงทะเบียนใหม่', (t) async {
    final (state, section) = await _mount(t);
    section.value = SettingsSection.account;
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(_s(t).licenseRetry), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  group('log ที่ไปกับรายงานบั๊กต้องไม่มีบทสนทนา', () {
    test('คำที่สตรีมทีละคำ ถูกทิ้งทั้งบรรทัด', () {
      expect(MindLog.scrub('InferenceChat: Received filtered token: "สวัสดี"'), isNull);
      expect(MindLog.scrub('InferenceChat: Emitting text token: "ค่ะ"'), isNull);
    });

    test('ข้อความทั้งก้อน เหลือแค่ว่าเกิดขึ้น ไม่มีเนื้อหา', () {
      final out = MindLog.scrub('Current Message:\nเบอร์ฉัน 0812345678 อยู่บ้านเลขที่ 9')!;
      expect(out, isNot(contains('0812345678')));
      expect(out, startsWith('Current Message:'));
      final reply = MindLog.scrub(
          'InferenceChat: Raw response from native model:\n--- START ---\nความลับ\n--- END ---')!;
      expect(reply, isNot(contains('ความลับ')));
    });

    test('บรรทัดไล่บั๊กปกติยังอยู่ครบ', () {
      const line = 'gemma: เปิดสมอง gemma-4-e2b-cpu ด้วย gpu ใน 5400 ms';
      expect(MindLog.scrub(line), line);
    });
  });
}
