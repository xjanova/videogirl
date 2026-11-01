import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_sos.dart';
import 'package:videogirl/screens/sos_panel.dart';
import 'package:videogirl/sos/mind_sos.dart';
import 'package:videogirl/sos/sos_directory.dart';
import 'package:videogirl/sos/sos_phrases.dart';
import 'package:videogirl/sos/sos_plan.dart';
import 'package:videogirl/sos/sos_profile.dart';
import 'package:videogirl/system/permissions.dart';

const _sos = MethodChannel('giggok/sos');

/// รับทุกคำสั่งที่ออกไปฝั่งเนทีฟ · 🔴 ไม่มีอะไรในเทสต์นี้ถึงเครื่องจริง
class _Native {
  final calls = <MethodCall>[];
  String? profile;
  Map<String, Object?> status = {'phase': 'IDLE'};
  bool triggerOk = true;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_sos, (c) async {
      calls.add(c);
      return switch (c.method) {
        'sosStatus' => status,
        'sosProfile' => profile,
        'sosSave' => _save(c),
        'sosTrigger' => triggerOk,
        'sosLocation' => null,
        _ => true,
      };
    });
  }

  bool _save(MethodCall c) {
    profile = (c.arguments as Map<Object?, Object?>)['profile'] as String?;
    return true;
  }

  Iterable<MethodCall> named(String method) => calls.where((c) => c.method == method);
}

const _full = SosProfile(
  name: 'สมชาย ใจดี',
  birthYear: 1990,
  blood: 'O',
  allergies: 'เพนิซิลลิน',
  conditions: 'เบาหวาน',
  medicines: 'เมตฟอร์มิน',
  plate: 'กข 1234',
  armed: true,
  consent: kSosConsentVersion,
);

Map<String, dynamic> _plan(SosProfile p) => jsonDecode(SosPlanBuilder.build(p, year: 2026)) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SosDirectory', () {
    test('every incident has a route and each route starts with the right desk', () {
      for (final k in SosKindName.values) {
        expect(SosDirectory.routes[k], isNotEmpty, reason: k.name);
      }
      expect(SosDirectory.wireRoutes['CRASH'], ['1669', '191']);
      expect(SosDirectory.wireRoutes['MEDICAL'], ['1669', '191']);
      expect(SosDirectory.wireRoutes['FIRE'], ['199', '191']);
      expect(SosDirectory.wireRoutes['CRIME'], ['191']);
    });

    test('112 stays out of the routes used inside Thailand', () {
      for (final numbers in SosDirectory.wireRoutes.values) {
        expect(numbers, isNot(contains('112')));
      }
      expect(SosDirectory.abroad, ['112']);
    });

    test('reference numbers are unique', () {
      final numbers = SosDirectory.reference.map((n) => n.number).toList();
      expect(numbers.toSet().length, numbers.length);
    });
  });

  group('SosProfile', () {
    test('round trips through encode and parse', () {
      const p = SosProfile(
        name: 'ก',
        birthYear: 1985,
        contacts: [SosContactInfo(name: 'แม่', number: '0812345678', health: false)],
        testNumber: '0899999999',
        autoCall: true,
        consent: 1,
        countdownSec: 45,
        sensitivity: 2,
      );
      final back = SosProfile.parse(p.encode());
      expect(back.encode(), p.encode());
      expect(back.contacts.single.health, isFalse);
    });

    test('a broken file opens empty instead of crashing', () {
      expect(SosProfile.parse('{not json').name, '');
      expect(SosProfile.parse(null).armed, isFalse);
      expect(SosProfile.parse('{"birthYear":"x"}').birthYear, isNull);
    });

    test('nonsense birth years give no age, so nobody speaks one', () {
      expect(const SosProfile(birthYear: 1800).ageIn(2026), isNull);
      expect(const SosProfile(birthYear: 2050).ageIn(2026), isNull);
      expect(const SosProfile(birthYear: 2000).ageIn(2026), 26);
    });
  });

  group('SosPlanBuilder', () {
    test('an unconsented profile can never arm, whatever the flags say', () {
      final m = _plan(const SosProfile(armed: true, autoCall: true));
      expect(m['armed'], isFalse);
      expect(m['autoCall'], isFalse);
    });

    test('🔴 test mode stays on until the owner turns it off', () {
      expect(const SosProfile().testMode, isTrue);
      expect(SosProfile.parse('{"armed":true}').testMode, isTrue, reason: 'old files must not go live');
      expect(_plan(const SosProfile(consent: kSosConsentVersion))['testMode'], isTrue);
      expect(_plan(const SosProfile(testMode: false))['testMode'], isTrue, reason: 'no consent, never live');
      const live = SosProfile(consent: kSosConsentVersion, testMode: false);
      expect(_plan(live)['testMode'], isFalse);
      expect(SosProfile.parse(live.encode()).testMode, isFalse);
    });

    test('empty fields are not spoken and nothing is invented', () {
      final th = _plan(const SosProfile(consent: kSosConsentVersion))['th'] as Map<String, dynamic>;
      for (final word in ['กรุ๊ปเลือด', 'แพ้ยา', 'โรคประจำตัว', 'ยาที่ใช้', 'ทะเบียนรถ', 'อายุ']) {
        expect(th['scriptWho'], isNot(contains(word)));
      }
      expect(th['smsHealth'], '');
      expect(th['scriptWho'], contains('เจ้าของโทรศัพท์เครื่องนี้'));
    });

    test('filled fields reach the script', () {
      final th = _plan(_full)['th'] as Map<String, dynamic>;
      for (final word in ['สมชาย ใจดี', 'อายุ 36 ปี', 'กรุ๊ปเลือด O', 'แพ้ยา เพนิซิลลิน', 'กข 1234']) {
        expect(th['scriptWho'], contains(word));
      }
    });

    test('she announces she is an automated assistant, in both languages', () {
      final m = _plan(_full);
      for (final k in SosKindName.values) {
        expect(((m['th'] as Map)['scriptOpen'] as Map)[k.wire], contains('ระบบช่วยแจ้งเหตุอัตโนมัติ'));
        expect(((m['en'] as Map)['scriptOpen'] as Map)[k.wire], contains('automated emergency alert system'));
      }
    });

    test('the script says the mic will close before it gives any details', () {
      final open = ((_plan(_full)['th'] as Map)['scriptOpen'] as Map)['CRASH'] as String;
      expect(open.indexOf('ปิดไมค์'), lessThan(open.indexOf('สมชาย ใจดี')));
    });

    test('a silent alert tells everyone not to call back', () {
      final m = _plan(_full);
      expect((m['th'] as Map)['smsSilent'], contains('ห้ามโทรกลับ'));
      expect((m['en'] as Map)['smsSilent'], contains('DO NOT call back'));
      expect(((m['th'] as Map)['scriptOpen'] as Map)['SILENT'], contains('ห้ามโทรกลับ'));
    });

    test('the alert prompt cannot cancel itself through the mic', () {
      final m = _plan(_full);
      expect((m['th'] as Map)['alertPrompt'], isNot(contains('ไม่เป็นไร')));
      expect((m['en'] as Map)['alertPrompt'], isNot(contains("I'm fine")));
    });

    test('keys match what SosStore.parse reads on the Android side', () {
      final store = File('android/app/src/main/kotlin/com/xjanova/videogirl/sos/SosStore.kt').readAsStringSync();
      final m = _plan(_full);
      final keys = {...m.keys, ...(m['th'] as Map<String, dynamic>).keys};
      for (final k in ['routes', 'contacts', 'testNumber', 'scriptOpen', 'scriptWho', 'scriptWhere', 'smsCancel']) {
        expect(keys, contains(k));
        expect(store, contains('"$k"'), reason: k);
      }
    });
  });

  group('SosPhrases', () {
    test('plain cries for help match', () {
      expect(SosPhrases.match('ช่วยด้วย'), SosKindName.other);
      expect(SosPhrases.match('ช่วยด้วยค่ะน้องมายด์'), SosKindName.other);
      expect(SosPhrases.match('น้องมายด์ ช่วยด้วย'), SosKindName.other);
      expect(SosPhrases.match('มายด์ เรียกตำรวจ'), SosKindName.crime);
      expect(SosPhrases.match('SOS!'), SosKindName.other);
      expect(SosPhrases.match('เรียกรถพยาบาลด่วน'), SosKindName.medical);
      expect(SosPhrases.match('ไฟไหม้ ๆ'), SosKindName.fire);
      expect(SosPhrases.match('เรียกตำรวจที'), SosKindName.crime);
      expect(SosPhrases.match('รถชน'), SosKindName.crash);
    });

    test('silent means the cry for help and nothing else', () {
      expect(SosPhrases.silent('ช่วยด้วย'), isTrue);
      expect(SosPhrases.silent('น้องมายด์ ช่วยด้วยค่ะ'), isTrue);
      expect(SosPhrases.silent('sos'), isFalse);
      expect(SosPhrases.silent('ไฟไหม้'), isFalse);
      expect(SosPhrases.silent('เรียกรถพยาบาล'), isFalse);
    });

    test('questions, negatives and chatter do not', () {
      for (final s in [
        'วิธีแจ้งเหตุฉุกเฉินทำยังไง',
        'ไม่ต้องเรียกรถพยาบาล',
        'help',
        'fire',
        'ช่วยดูหน่อย',
        'เมื่อวานรถชนกันที่หน้าบ้าน',
        '',
      ]) {
        expect(SosPhrases.match(s), isNull, reason: s);
      }
    });

    test('a long message never fires', () {
      expect(SosPhrases.match('ช่วยด้วย' * 8), isNull);
    });
  });

  group('MindSos', () {
    late _Native native;

    setUp(() {
      native = _Native()..install();
    });

    test('a cry for help starts the voice countdown and skips her brain', () async {
      var sent = 0;
      final send = MindSos.instance.guarded((_) async => sent++);
      await send('ช่วยด้วย');
      expect(sent, 0);
      final args = native.named('sosTrigger').single.arguments as Map<Object?, Object?>;
      expect(args, {'kind': 'OTHER', 'voice': true, 'silent': true});
    });

    test('a silent drill asks for silence and still goes through the drill channel', () async {
      await MindSos.instance.drill(silent: true);
      expect(native.named('sosTrigger'), isEmpty);
      expect((native.named('sosDrill').single.arguments as Map<Object?, Object?>)['silent'], isTrue);
    });

    test('only the cry for help is silent, SOS keeps its audible countdown', () async {
      await MindSos.instance.heard('SOS');
      await MindSos.instance.heard('เรียกรถพยาบาล');
      for (final c in native.named('sosTrigger')) {
        expect((c.arguments as Map<Object?, Object?>)['silent'], isFalse);
      }
    });

    test('saying cancel stops a silent alert and nothing reaches her brain', () async {
      native.status = {'phase': 'DISPATCH', 'silent': true};
      var sent = 0;
      await MindSos.instance.guarded((_) async => sent++)('ยกเลิก');
      expect(sent, 0);
      expect(native.named('sosStop'), hasLength(1));
    });

    test('saying cancel with no silent alert is ordinary chat', () async {
      native.status = {'phase': 'ALERT'};
      var sent = 0;
      await MindSos.instance.guarded((_) async => sent++)('ไม่เป็นไร');
      expect(sent, 1);
      expect(native.named('sosStop'), isEmpty);
    });

    test('with the system off the words still reach her', () async {
      native.triggerOk = false;
      var sent = 0;
      final send = MindSos.instance.guarded((_) async => sent++);
      await send('ช่วยด้วย');
      expect(sent, 1);
    });

    test('ordinary chat never touches the channel', () async {
      var sent = 0;
      await MindSos.instance.guarded((_) async => sent++)('วันนี้กินอะไรดี');
      expect(sent, 1);
      expect(native.calls, isEmpty);
    });

    test('no outgoing method carries a phone number', () async {
      await MindSos.instance.trigger(SosKindName.crash);
      await MindSos.instance.drill();
      await MindSos.instance.share('sms');
      for (final c in native.calls) {
        expect(jsonEncode(c.arguments), isNot(matches(RegExp(r'\d{3,}'))), reason: c.method);
      }
      final bridge = File('android/app/src/main/kotlin/com/xjanova/videogirl/sos/SosBridge.kt').readAsStringSync();
      expect(bridge, isNot(contains('argument<String>("number")')));
    });

    test('status survives an empty or damaged reply', () {
      expect(SosStatus.empty.readings, isEmpty);
      expect(SosStatus.empty.lastReport, isEmpty);
      expect(const SosStatus({'readings': 'junk'}).readings, isEmpty);
      expect(const SosStatus({'phase': 'ALERT'}).busy, isTrue);
      expect(const SosStatus({'phase': 'DONE'}).busy, isFalse);
    });
  });

  group('SosPanel', () {
    late _Native native;

    Widget host() => ChangeNotifierProvider(
          create: (_) => MindPermissions(),
          child: MaterialApp(
            home: const Scaffold(body: SingleChildScrollView(child: SosPanel(accent: Colors.red))),
          ),
        );

    setUp(() {
      native = _Native()..install();
    });

    testWidgets('opening fresh shows empty fields and does not save anything', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsWidgets);
      expect(native.named('sosSave'), isEmpty);
    });

    testWidgets('a returning owner sees what they saved', (tester) async {
      native.profile = _full.encode();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('สมชาย ใจดี'), findsOneWidget);
      expect(find.text('1990'), findsOneWidget);
    });

    testWidgets('turning on needs the warning accepted first', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.byType(TextButton).last); // ยกเลิก
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
      expect(native.named('sosSave'), isEmpty);
    });

    testWidgets('leaving the page keeps what was typed', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'มานี');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(SosProfile.parse(native.profile).name, 'มานี');
    });

    testWidgets('a bad birth year is not saved over the good one when leaving', (tester) async {
      native.profile = _full.encode();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, const S(AppLang.en).sosBirthYear), '99');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(SosProfile.parse(native.profile).birthYear, 1990);
    });

    testWidgets('automatic calling stays locked until a drill has passed', (tester) async {
      native.profile = _full.encode();
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final auto = tester.widget<Switch>(find.byType(Switch).last);
      expect(auto.onChanged, isNull);
    });
  });
}
