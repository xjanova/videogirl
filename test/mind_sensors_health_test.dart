/// เธออ่านเซ็นเซอร์และข้อมูลสุขภาพตอนเจ้าของถาม
///
/// ที่มา: เจ้าของถามว่าเธอตรวจเรื่องสุขภาพ เซ็นเซอร์ และระบบได้ลึกแค่ไหน · สิ่งที่เทสต์นี้เฝ้า: ค่าจริงหรือเหตุผลตรง ๆ ·
/// สมองบนคลาวด์เห็นเฉพาะที่ถาม · เครื่องล็อกหรือมีสาย ต้องไม่อ่านเลย
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/mind_persona.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_ai.dart';
import 'package:videogirl/phone/call_watch.dart';
import 'package:videogirl/phone/phone_lookup.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';
import 'package:videogirl/theme/tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // อาทิตย์ 1 พ.ย. 2026 สิบโมงเช้า
  final now = DateTime(2026, 11, 1, 10);

  late List<MethodCall> calls;
  late Map<String, Object? Function(MethodCall)> answers;

  void mock() {
    calls = [];
    answers = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kSystemChannel, (c) async {
      calls.add(c);
      return answers[c.method]?.call(c);
    });
  }

  void unmock() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(kSystemChannel, null);

  Iterable<MethodCall> called(String method) => calls.where((c) => c.method == method);
  Map<Object?, Object?> argsOf(String method) => called(method).last.arguments as Map<Object?, Object?>;

  /// คำตอบของ sensorsRead · อ่านเฉพาะชื่อที่ขอ เหมือนของจริง
  Map<String, Object?> sensorBoard(MethodCall c, Map<String, Map<String, Object?>> board,
      {List<String> present = const ['light', 'proximity'], bool steps = false, bool heart = false}) {
    final names = ((c.arguments as Map)['names'] as List).cast<String>();
    return {
      'readings': {for (final n in names) n: board[n] ?? {'state': 'absent'}},
      'present': present,
      'stepCounter': steps,
      'heartRate': heart,
    };
  }

  group('แท็ก', () {
    test('อ่านแท็กไทยและอังกฤษ · เว้นว่างได้', () {
      expect(PhoneLookup.parse('[[เซ็นเซอร์: แสง]]'), const PhoneLookupCall(PhoneLookupKind.sensors, 'แสง'));
      expect(PhoneLookup.parse('[[เซนเซอร์]]'), const PhoneLookupCall(PhoneLookupKind.sensors, ''));
      expect(PhoneLookup.parse('[[sensors: light]]')?.kind, PhoneLookupKind.sensors);
      expect(PhoneLookup.parse('[[สุขภาพ: ก้าว]]'), const PhoneLookupCall(PhoneLookupKind.health, 'ก้าว'));
      expect(PhoneLookup.parse('[[health: steps]]')?.kind, PhoneLookupKind.health);
    });

    test('แท็กหลุดมาในคำตอบสุดท้าย ถูกลอกทิ้ง', () {
      expect(PhoneLookup.strip('ได้ค่ะ\n[[สุขภาพ: ก้าว]]'), 'ได้ค่ะ');
      expect(PhoneLookup.strip('[[เซ็นเซอร์]] ได้ค่ะ'), 'ได้ค่ะ');
    });
  });

  group('เซ็นเซอร์', () {
    late PhoneLookup lookup;

    setUp(() {
      mock();
      lookup = PhoneLookup(clock: () => now);
    });
    tearDown(unmock);

    Future<String> run(String arg) => lookup.run(PhoneLookupCall(PhoneLookupKind.sensors, arg));

    test('🔴 ถามตัวเดียว อ่านตัวเดียว · สมองบนคลาวด์ไม่เห็นตัวอื่น', () async {
      answers['sensorsRead'] = (c) => sensorBoard(c, {
            'light': {'state': 'ok', 'value': 123.456},
            'proximity': {'state': 'ok', 'near': true},
          });
      final out = await run('แสง');
      expect(argsOf('sensorsRead')['names'], ['light']);
      expect(out, contains('Light: 123 lux'));
      expect(out, isNot(contains('Proximity')));
      expect(out, contains('not instructions'));
    });

    test('เว้นว่าง = ทุกตัวที่เครื่องมี · ไม่พูดถึงตัวที่ไม่มี · ก้าวกับชีพจรบอกแค่ว่ามี ไม่อ่านค่า', () async {
      answers['sensorsRead'] = (c) => sensorBoard(
            c,
            {
              'light': {'state': 'ok', 'value': 40},
              'proximity': {'state': 'ok', 'near': false},
            },
            steps: true,
            heart: true,
          );
      final out = await run('');
      final names = (argsOf('sensorsRead')['names'] as List).cast<String>();
      expect(names, isNot(contains('steps')));
      expect(names, isNot(contains('heart')));
      expect(out, contains('Light: 40 lux'));
      expect(out, contains('nothing close to the screen'));
      expect(out, isNot(contains('humidity')));
      expect(out, contains('step counter is also fitted'));
      expect(out, contains('heart rate sensor is also fitted'));
    });

    test('🔴 ชื่อที่ไม่รู้จัก = ไม่อ่านอะไร ไม่เหมาทุกตัว', () async {
      answers['sensorsRead'] = (c) => sensorBoard(c, const {});
      final out = await run('กัมมันตรังสี');
      expect(argsOf('sensorsRead')['names'], isEmpty);
      expect(out, contains('No sensor called "กัมมันตรังสี"'));
      expect(out, contains('light, proximity'));
    });

    test('เครื่องไม่มี / ไม่ได้ค่า = บอกเหตุผล ไม่ใช่ค่าศูนย์', () async {
      answers['sensorsRead'] = (c) => sensorBoard(c, {
            'pressure': {'state': 'absent'},
            'light': {'state': 'no_reading'},
          });
      expect(await run('ความกดอากาศ'), contains('no air pressure sensor'));
      final out = await run('แสง');
      expect(out, contains('gave no reading'));
      expect(out, contains('open the app'));
    });

    test('อ่านจากเครื่องไม่ได้ = บอกตรง ๆ ไม่เดา', () async {
      answers['sensorsRead'] = (_) => throw PlatformException(code: 'x');
      expect(await run('แสง'), contains('do not guess'));
    });

    test('🔴 ตัวเลขทศนิยมสั้น · ไม่มีทศนิยมยาวให้เธออ่านออกเสียง', () {
      expect(PhoneLookup.describeSensor('accelerometer', {
        'state': 'ok',
        'xyz': [0.1234567, 0.0, 9.8123456],
      }), allOf(contains('0.1 / 0.0 / 9.8'), contains('total 9.8')));
      expect(PhoneLookup.describeSensor('magnetic', {
        'state': 'ok',
        'xyz': [30.0, 40.0, 0.0],
      }), 'Magnetic field: 50 µT');
      expect(PhoneLookup.describeSensor('temperature', {'state': 'ok', 'value': 27.3456}), 'Room temperature: 27.3 C');
    });

    test('🔴 ถามก้าวผ่านแท็กเซ็นเซอร์ ก็ต้องผ่านด่านสุขภาพ', () async {
      lookup.healthBarred = () async => 'locked';
      final out = await run('ก้าว');
      expect(out, contains('locked'));
      expect(called('sensorsRead'), isEmpty);
      expect(called('healthRead'), isEmpty);
    });
  });

  group('สุขภาพ', () {
    late PhoneLookup lookup;
    late List<List<String>> askedHealth;
    late List<MindPermission> askedPerm;

    setUp(() {
      mock();
      askedHealth = [];
      askedPerm = [];
      lookup = PhoneLookup(clock: () => now)
        ..healthBarred = (() async => null)
        ..askHealth = (types) async {
          askedHealth.add(types);
          return false;
        }
        ..askPermission = (p) async {
          askedPerm.add(p);
          return false;
        };
    });
    tearDown(unmock);

    Future<String> run(String arg) => lookup.run(PhoneLookupCall(PhoneLookupKind.health, arg));

    Map<String, Object?> hc(Map<String, Map<String, Object?>> rows, MethodCall c) {
      final types = ((c.arguments as Map)['types'] as List).cast<String>();
      return {
        'status': 'ok',
        'types': {
          for (final t in types)
            t: rows[t] ?? {'state': 'empty'},
        },
      };
    }

    test('🔴 ไม่ได้ต่อด่าน = อ่านไม่ได้ ไม่มีทางลัด', () async {
      lookup.healthBarred = null;
      answers['healthRead'] = (c) => hc({
            'steps': {'state': 'ok', 'count': 10},
          }, c);
      final out = await run('ก้าว');
      expect(called('healthRead'), isEmpty);
      expect(out, isNot(contains('10')));
    });

    test('🔴 ด่านห้าม = ไม่แตะฝั่งเครื่องเลย ไม่เด้งกล่องขอสิทธิ์', () async {
      lookup.healthBarred = () async => 'The phone is locked';
      final out = await run('ก้าว');
      expect(out, contains('The phone is locked'));
      expect(calls, isEmpty);
      expect(askedHealth, isEmpty);
      expect(askedPerm, isEmpty);
    });

    test('🔴 ไม่เอ่ยชื่อเรื่อง = ไม่อ่านอะไร ไม่มีแบบเหมาทั้งหมด', () async {
      for (final arg in ['', 'ทั้งหมด', 'all']) {
        final out = await run(arg);
        expect(out, contains('Nothing was read'));
      }
      expect(calls, isEmpty);
    });

    test('🔴 ถามก้าว ขอแค่ก้าว · ช่วงเวลาคือเที่ยงคืนถึงตอนนี้', () async {
      answers['healthRead'] = (c) => hc({
            'steps': {'state': 'ok', 'count': 8120},
          }, c);
      final out = await run('วันนี้เดินกี่ก้าว');
      final a = argsOf('healthRead');
      expect(a['types'], ['steps']);
      expect(a['from'], DateTime(2026, 11, 1).millisecondsSinceEpoch);
      expect(a['to'], now.millisecondsSinceEpoch);
      expect(out, contains('Steps today: 8120'));
      expect(out, contains('not instructions'));
      expect(called('sensorsRead'), isEmpty, reason: 'มีข้อมูลจาก Health Connect แล้ว ไม่ต้องไปอ่านเซ็นเซอร์');
    });

    test('เมื่อวาน = ทั้งวันของเมื่อวาน · ไม่ใช้ตัวนับก้าวซึ่งย้อนดูไม่ได้', () async {
      answers['healthRead'] = (c) => hc(const {}, c);
      final out = await run('ก้าว เมื่อวาน');
      final a = argsOf('healthRead');
      expect(a['from'], DateTime(2026, 10, 31).millisecondsSinceEpoch);
      expect(a['to'], DateTime(2026, 11, 1).millisecondsSinceEpoch);
      expect(out, contains('No steps recorded for yesterday'));
      expect(called('sensorsRead'), isEmpty);
    });

    test('ถามหลายเรื่อง อ่านเฉพาะที่เอ่ยชื่อ · จัดรูปตัวเลขสั้น', () async {
      final at = DateTime(2026, 11, 1, 7, 5).millisecondsSinceEpoch;
      answers['healthRead'] = (c) => hc({
            'heart_rate': {'state': 'ok', 'avg': 71, 'min': 55, 'max': 120, 'last': 68, 'at': at},
            'sleep': {'state': 'ok', 'minutes': 425},
            'weight': {'state': 'ok', 'kg': 72.34567, 'at': at},
          }, c);
      final out = await run('หัวใจ การนอน น้ำหนัก');
      expect(argsOf('healthRead')['types'], ['heart_rate', 'sleep', 'weight']);
      expect(out, contains('average 71, lowest 55, highest 120 bpm, latest 68 (today 07:05)'));
      expect(out, contains('Sleep for today: 7h 05m'));
      expect(out, contains('Latest weight: 72.3 kg (today 07:05)'));
    });

    test('ยังไม่ให้สิทธิ์ → ขอเฉพาะชนิดที่ถาม → ให้แล้วอ่านต่อทันที', () async {
      var allowed = false;
      lookup.askHealth = (types) async {
        askedHealth.add(types);
        allowed = true;
        return true;
      };
      answers['healthRead'] = (c) => hc({
            'steps': allowed ? {'state': 'ok', 'count': 500} : {'state': 'no_permission'},
          }, c);
      final out = await run('ก้าว');
      expect(askedHealth, [
        ['steps'],
      ]);
      expect(out, contains('Steps today: 500'));
    });

    test('🔴 ปฏิเสธ Health Connect แล้ว ไม่เด้งกล่องขอสิทธิ์ตัวนับก้าวซ้ำ · บอกทางไปเปิดเอง', () async {
      answers['healthRead'] = (c) => hc({
            'steps': {'state': 'no_permission'},
          }, c);
      answers['sensorsRead'] = (c) => sensorBoard(c, {
            'steps': {'state': 'no_permission'},
          });
      final out = await run('ก้าว');
      expect(askedHealth, hasLength(1));
      expect(askedPerm, isEmpty);
      expect(out, contains('has not allowed it yet'));
      expect(out, contains('Health Connect app'));
    });

    test('ปฏิเสธ Health Connect แต่ให้ตัวนับก้าวไว้แล้ว = ยังตอบได้จากเครื่อง', () async {
      answers['healthRead'] = (c) => hc({
            'steps': {'state': 'no_permission'},
          }, c);
      answers['sensorsRead'] = (c) => sensorBoard(c, {
            'steps': {'state': 'ok', 'steps': 4321, 'hours': 26.4},
          });
      final out = await run('ก้าว');
      expect(out, contains('4321 steps since it last restarted 26 hours ago'));
      expect(out, isNot(contains('has not allowed')));
    });

    test('🔴 Health Connect ไม่มีข้อมูล → ตัวนับก้าวของเครื่อง · ต้องบอกว่าไม่ใช่ของวันนี้', () async {
      answers['healthRead'] = (c) => hc(const {}, c);
      answers['sensorsRead'] = (c) => sensorBoard(c, {
            'steps': {'state': 'ok', 'steps': 12000, 'hours': 50.0},
          });
      final out = await run('ก้าว');
      expect(out, contains('No steps recorded for today'));
      expect(out, contains('12000 steps since it last restarted 50 hours ago'));
      expect(out, contains('cannot split out today'));
    });

    test('ตัวนับก้าวยังไม่ได้สิทธิ์ → ขอตอนนั้น · ปฏิเสธ = บอกตรง ๆ ไม่ใช่ว่าเครื่องไม่มี', () async {
      answers['healthRead'] = (c) => hc(const {}, c);
      answers['sensorsRead'] = (c) => sensorBoard(c, {
            'steps': {'state': 'no_permission'},
          });
      final out = await run('ก้าว');
      expect(askedPerm, [MindPermission.activity]);
      expect(out, contains('has not allowed it yet'));
      expect(out, isNot(contains('no step counter')));
    });

    test('เครื่องไม่มี Health Connect: บอกเหตุผล · ก้าวยังตอบจากตัวนับได้', () async {
      answers['healthRead'] = (_) => {'status': 'none'};
      answers['sensorsRead'] = (c) => sensorBoard(c, {
            'steps': {'state': 'ok', 'steps': 900, 'hours': 3.0},
          });
      final out = await run('ก้าว');
      expect(out, contains('Health Connect is not available'));
      expect(out, contains('900 steps'));
      expect(askedHealth, isEmpty);
    });

    test('Android เก่าที่ยังไม่ลงแอป Health Connect: บอกให้ลง', () async {
      answers['healthRead'] = (_) => {'status': 'update'};
      expect(await run('น้ำหนัก'), contains('install or update'));
    });

    test('🔴 Health Connect ล้ม/ค้าง ไม่ทำให้ก้าวจากเครื่องหายไปด้วย', () async {
      answers['healthRead'] = (_) => throw PlatformException(code: 'x');
      answers['sensorsRead'] = (c) => sensorBoard(c, {
            'steps': {'state': 'ok', 'steps': 77, 'hours': 1.0},
          });
      final out = await run('ก้าว');
      expect(out, contains('did not answer'));
      expect(out, contains('77 steps'));
    });

    test('อยู่หลังบ้าน: บอกให้เปิดแอป ไม่ปนกับไม่ได้ให้สิทธิ์', () async {
      answers['healthRead'] = (c) => hc({
            'weight': {'state': 'background'},
          }, c);
      final out = await run('น้ำหนัก');
      expect(out, contains('while the app is open on screen'));
      expect(out, isNot(contains('has not allowed')));
    });

    test('ชีพจร: เครื่องไม่มีตัววัด = บอกตรง ๆ ไม่ขอสิทธิ์', () async {
      answers['healthRead'] = (c) => hc(const {}, c);
      answers['sensorsRead'] = (c) => sensorBoard(c, {
            'heart': {'state': 'absent'},
          });
      final out = await run('หัวใจ');
      expect(out, contains('no heart rate sensor'));
      expect(askedPerm, isEmpty);
    });

    test('ชีพจร: มีตัววัด ยังไม่ได้สิทธิ์ → ขอ BODY_SENSORS · ไม่ได้ค่า = บอกให้วางนิ้ว', () async {
      var allowed = false;
      lookup.askPermission = (p) async {
        askedPerm.add(p);
        allowed = true;
        return true;
      };
      answers['healthRead'] = (c) => hc(const {}, c);
      answers['sensorsRead'] = (c) => sensorBoard(c, {
            'heart': {'state': allowed ? 'no_reading' : 'no_permission'},
          });
      final out = await run('ชีพจร');
      expect(askedPerm, [MindPermission.bodySensors]);
      expect(out, contains('hold a finger still'));
    });

    test('ไม่ log ค่าสุขภาพ', () {
      final source = File('lib/phone/phone_lookup.dart').readAsStringSync();
      final logs = RegExp(r'debugPrint\([^;]*;').allMatches(source).map((m) => m.group(0)!).toList();
      expect(logs, isNotEmpty);
      for (final l in logs) {
        expect(l, isNot(matches(RegExp(r'rows|row\[|body|count'))), reason: l);
      }
    });
  });

  group('สิทธิ์ขอเมื่อใช้', () {
    setUp(mock);
    tearDown(unmock);

    test('🔴 ปุ่มขอทีเดียวไม่แตะสิทธิ์ร่างกาย · ไม่นับว่ายังขาด', () async {
      for (final p in MindPermission.values) {
        if (!p.onDemand) answers[p.check] = (_) => true;
      }
      final perms = MindPermissions();
      await perms.refresh();
      expect(perms.of(MindPermission.activity), isFalse);
      expect(perms.allGranted, isTrue);
      expect(perms.missing, 0);
      await perms.requestAllMissing();
      expect(called(MindPermission.activity.ask), isEmpty);
      expect(called(MindPermission.bodySensors.ask), isEmpty);
    });

    test('สิทธิ์ที่แอปต้องใช้ยังนับเหมือนเดิม', () async {
      final perms = MindPermissions();
      await perms.refresh();
      expect(perms.allGranted, isFalse);
      expect(perms.missing, MindPermission.values.where((p) => !p.onDemand).length);
    });
  });

  group('ด่านจริงใน MindState', () {
    final gated = {'kind': 'health', 'query': 'ก้าว'};

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mock();
      answers['healthRead'] = (_) => {
            'status': 'ok',
            'types': {
              'steps': {'state': 'ok', 'count': 3210},
            },
          };
    });
    tearDown(unmock);

    MindState make() {
      final s = MindState();
      addTearDown(s.dispose);
      return s;
    }

    test('ไม่ล็อก ไม่มีสาย = อ่านได้', () async {
      final s = make()..phoneLocked = (() async => false);
      expect(await s.runVoiceTool('phone_lookup', gated), contains('3210'));
    });

    test('🔴 เครื่องล็อก = ไม่อ่าน แม้ไม่ได้เรียกด้วยเสียง · บอกให้ปลดล็อก', () async {
      final notices = <String>[];
      final s = make()
        ..phoneLocked = (() async => true)
        ..onHerNotice = notices.add;
      expect(s.handsFree, isFalse);
      final out = await s.runVoiceTool('phone_lookup', gated);
      expect(called('healthRead'), isEmpty);
      expect(out, isNot(contains('3210')));
      expect(out, contains('locked'));
      expect(notices, [s.s.healthUnlockFirst]);
    });

    test('ไม่มีคุยเสียงอยู่ = ไม่มีใครบอกเจ้าของ เธอต้องบอกเอง', () async {
      final s = make()..phoneLocked = (() async => true);
      expect(await s.runVoiceTool('phone_lookup', gated), contains('Tell the owner to unlock'));
      expect(called('healthRead'), isEmpty);
    });

    test('🔴 ถามสถานะล็อกไม่ได้ = ถือว่าล็อก', () async {
      final s = make()..phoneLocked = (() async => throw StateError('no service'));
      await s.runVoiceTool('phone_lookup', gated);
      expect(called('healthRead'), isEmpty);
    });

    test('🔴 มีสายอยู่ = ไม่อ่าน แม้เครื่องไม่ล็อก', () async {
      final watch = CallWatch();
      addTearDown(watch.dispose);
      final s = make()
        ..phoneLocked = (() async => false)
        ..attachCalls(watch);
      await watch.start();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
          kSystemChannel.name,
          kSystemChannel.codec.encodeMethodCall(const MethodCall('onCallState', {'state': 2})),
          (_) {});
      final out = await s.runVoiceTool('phone_lookup', gated);
      expect(called('healthRead'), isEmpty);
      expect(out, contains('during a phone call'));
    });

    test('🔴 เซ็นเซอร์รอบตัวอ่านได้ตอนล็อก · ก้าวไม่ได้', () async {
      answers['sensorsRead'] = (c) => sensorBoard(c, {
            'light': {'state': 'ok', 'value': 10},
            'steps': {'state': 'ok', 'steps': 999, 'hours': 1.0},
          });
      final s = make()..phoneLocked = (() async => true);
      expect(await s.runVoiceTool('phone_lookup', {'kind': 'sensors', 'query': 'light'}), contains('10 lux'));
      final steps = await s.runVoiceTool('phone_lookup', {'kind': 'sensors', 'query': 'steps'});
      expect(steps, isNot(contains('999')));
    });
  });

  group('ในแชท', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mock();
    });
    tearDown(unmock);

    test('🔴 ถามก้าว → สมองเห็นแค่ผลของคำถามนี้ · ผลไม่ลงบทสนทนา', () async {
      answers['healthRead'] = (_) => {
            'status': 'ok',
            'types': {
              'steps': {'state': 'ok', 'count': 4567},
            },
          };
      final brain = _SeqBrain(['[[สุขภาพ: ก้าว]]', 'วันนี้เดินไปสี่พันห้าร้อยก้าวค่ะ']);
      final s = MindState(openai: brain);
      addTearDown(s.dispose);
      await s.load();
      s.setBrain(BrainProvider.openai);
      await s.setOpenAiKey('sk-test-key-for-unit-tests');
      await s.send('วันนี้เดินไปกี่ก้าว');
      expect(argsOf('healthRead')['types'], ['steps']);
      expect(brain.histories, hasLength(2));
      expect(brain.histories.last.last.text, contains('Steps today: 4567'));
      expect(brain.systems.first, contains('[[สุขภาพ:'));
      expect(s.messages.last.text, 'วันนี้เดินไปสี่พันห้าร้อยก้าวค่ะ');
      expect(s.messages.any((m) => m.text.contains('[[') || m.text.contains('4567')), isFalse);
    });
  });

  group('🔴 ในสายต้องไม่มีทางถึงเลย', () {
    String prompt({required AppLang lang, required bool onCall}) => MindPersona.system(
          lang: lang,
          mode: MindMode.work,
          flirt: .3,
          ownerProfile: '',
          boundaries: '',
          phoneData: true,
          onCall: onCall,
        );

    test('แชทสอนแท็ก · ในสายไม่สอน', () {
      expect(prompt(lang: AppLang.th, onCall: false), contains('[[สุขภาพ:'));
      expect(prompt(lang: AppLang.en, onCall: false), contains('[[health:'));
      for (final lang in AppLang.values) {
        final p = prompt(lang: lang, onCall: true);
        expect(p, isNot(contains('[[สุขภาพ:')));
        expect(p, isNot(contains('[[เซ็นเซอร์:')));
        expect(p, isNot(contains('[[health:')));
        expect(p, isNot(contains('[[sensors:')));
      }
    });

    test('เครื่องมือของสายไม่มี phone_lookup และโค้ดสายไม่เคยเรียกการอ่านสุขภาพ', () {
      final session = File('lib/phone/voice_session.dart').readAsStringSync();
      expect(session, isNot(contains('phone_lookup')));
      for (final f in Directory('lib/phone').listSync().whereType<File>()) {
        if (f.path.endsWith('phone_lookup.dart')) continue;
        final src = f.readAsStringSync();
        expect(src, isNot(contains('healthRead')), reason: f.path);
        expect(src, isNot(contains('PhoneLookup(')), reason: f.path);
      }
    });
  });
}

/// สมองปลอมของแชท · ตอบตามลำดับที่ให้ · จด system กับบทสนทนาที่ได้รับทุกครั้ง
class _SeqBrain extends OpenAiClient {
  _SeqBrain(this.answers);
  final List<String> answers;
  final systems = <String>[];
  final histories = <List<Turn>>[];
  int _i = 0;

  @override
  bool get usable => true;

  @override
  void close() {}

  @override
  Future<String> reply({required String system, required List<Turn> history, String? model}) async {
    systems.add(system);
    histories.add(List.of(history));
    return _i < answers.length ? answers[_i++] : answers.last;
  }
}
