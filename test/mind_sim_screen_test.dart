/// มายด์โทรด้วยซิมที่เจ้าของเลือก และเห็นหน้าจอมือถือเอง
///
/// ที่มา: เจ้าของ — "การโทรออก ยังติดปัญหาตรงให้เลือก sim เพราะเป็นเครื่อง2 sim มายด์เธอไปใช้การโทรของเครื่อง
/// แทนที่จะใช้ของตัวเอง และพอเราบอกให้ดูหน้าจอเธอบอกมองไม่เห็น ทั้งๆที่เธอต้องคอนโทรลเครื่องได้อยู่แล้ว"
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/ai/openai_config.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/hands/hands_bridge.dart';
import 'package:videogirl/hands/hands_tag.dart';
import 'package:videogirl/phone/call_target.dart';
import 'package:videogirl/phone/outgoing_call.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';

class _Brain extends OpenAiClient {
  _Brain(this.answer);
  String answer;
  @override
  bool get usable => true;
  @override
  void close() {}
  @override
  Future<String> reply({required String system, required List<Turn> history, String? model}) async => answer;
}

/// มือปลอม · จดว่าถูกเรียกอะไร
class _Hands implements Hands {
  _Hands({PhoneScreen? screen, this.beginError, this.shot}) : screen = screen ?? _plain;
  static const _plain = PhoneScreen(
    package: 'com.google.android.youtube',
    app: 'YouTube',
    nodes: [ScreenNode(id: 0, cls: 'TextView', text: 'คลิปแมว')],
  );

  PhoneScreen? screen;
  String? beginError;
  HandsReply? shot;
  HandsStatus state = const HandsStatus(supported: true, enabled: true);
  final log = <String>[];

  @override
  Future<HandsStatus> status() async => state;

  @override
  Future<HandsReply> begin({required String title, required String goal, bool inCall = false}) async {
    log.add('begin');
    return beginError == null ? const HandsReply(true) : HandsReply(false, error: beginError);
  }

  @override
  Future<(HandsReply, PhoneScreen?)> snapshot({int maxNodes = 120}) async {
    log.add('snapshot');
    return (const HandsReply(true), screen);
  }

  @override
  Future<HandsReply> screenshot({int maxEdge = 1024, bool marks = false}) async {
    log.add('screenshot');
    return shot ?? HandsReply(true, data: {'jpeg': Uint8List.fromList([1, 2, 3])});
  }

  @override
  Future<void> end() async => log.add('end');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _dual = [
  SimChoice(id: 'a', slot: 1, label: 'TRUE'),
  SimChoice(id: 'b', slot: 2, label: 'DTAC', isDefault: true),
];

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late Map<String, Object? Function(MethodCall)> native;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    native = {};
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kSystemChannel, (c) async {
      calls.add(c);
      return native[c.method]?.call(c);
    });
  });

  tearDown(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(kSystemChannel, null);
  });

  Future<MindState> mind({String answer = 'ได้ค่ะ'}) async {
    final s = MindState(openai: _Brain(answer));
    addTearDown(s.dispose);
    await s.load();
    s.setBrain(BrainProvider.openai);
    await s.setOpenAiKey('sk-test-key-for-unit-tests');
    s.debugCallTargets = CallTargetResolver(clock: () => DateTime.now());
    return s;
  }

  void twoSims() => native['callSims'] = (_) => [
        {'id': 'a', 'slot': 1, 'label': 'TRUE', 'default': false},
        {'id': 'b', 'slot': 2, 'label': 'DTAC', 'default': true},
      ];

  /// กล่องขึ้นตามคิว ไม่ใช่ทันทีที่ send จบ
  Future<void> offer(MindState s, {String said = 'โทรหา 0861234567 ถามเรื่องของ'}) async {
    await s.send(said);
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  Map<Object?, Object?> placed() => calls.singleWhere((c) => c.method == 'mindPlaceCall').arguments as Map;

  group('เลือกซิม', () {
    test('ลำดับ: ที่สั่ง > ที่เลือกครั้งก่อน > ค่าของเครื่อง > ซิมแรก', () {
      expect(SimChoice.pick(_dual, asked: 'a', last: 'b')?.id, 'a');
      expect(SimChoice.pick(_dual, last: 'a')?.id, 'a');
      expect(SimChoice.pick(_dual)?.id, 'b');
      expect(SimChoice.pick(_dual.map((s) => SimChoice(id: s.id, slot: s.slot)).toList())?.id, 'a');
      expect(SimChoice.pick(const []), isNull);
    });

    test('🔴 ซิมที่ถูกถอดไปแล้วไม่นับ', () {
      expect(SimChoice.pick(_dual, asked: 'gone', last: 'gone2')?.id, 'b');
    });

    test('อ่านจาก Android · id ว่าง = ทิ้ง', () {
      expect(SimChoice.fromMap({'id': '', 'slot': 1}), isNull);
      final c = SimChoice.fromMap({'id': 'x', 'slot': 2, 'label': ' DTAC ', 'default': true})!;
      expect((c.slot, c.label, c.isDefault), (2, 'DTAC', true));
    });

    test('พูดเลขช่องหรือชื่อค่าย · ไม่มีคำว่าซิม = ไม่เลือก', () {
      for (final t in ['ใช้ซิมสอง', 'ซิม 2', 'ซิมที่ 2 นะ', 'use sim two', 'ซิม DTAC']) {
        expect(CallReply.simIn(t, _dual)?.id, 'b', reason: t);
      }
      expect(CallReply.simIn('ซิมหนึ่ง', _dual)?.id, 'a');
      expect(CallReply.simIn('บอกเขาว่า true story', _dual), isNull);
      expect(CallReply.simIn('ใช้ซิมสอง', const [SimChoice(id: 'a', slot: 1)]), isNull);
    });

    test('🔴 "ใช้ซิมสอง" ไม่ใช่การยืนยันโทร · "โทรเลย ซิมสอง" คือการยืนยัน', () {
      expect(CallReply.onlySim('ใช้ซิมสองนะคะ'), isTrue);
      expect(CallReply.onlySim('ใช้ซิมสอง'), isTrue);
      expect(CallReply.onlySim('โทรเลย ซิมสอง'), isFalse);
      expect(CallReply.confirm('ใช้ซิมสอง'), isNull);
      expect(CallReply.confirm('โทรเลย ซิมสอง'), isTrue);
    });

    test('🔴 ไม่เลือกอะไร = ใช้ซิมโทรออกของเครื่อง ระบบไม่ต้องถาม', () async {
      twoSims();
      final s = await mind(answer: 'ได้ค่ะ [[โทร: 0861234567 | ถามเรื่องของ]]');
      await offer(s);
      expect(s.pendingCall?.number, '0861234567');
      await s.send('โทรเลย');
      expect(placed()['sim'], 'b');
    });

    test('🔴 พูดเปลี่ยนซิมตอนกล่องเปิด = เปลี่ยนซิม ยังไม่โทร · สายถัดไปจำไว้', () async {
      twoSims();
      final s = await mind(answer: 'ได้ค่ะ [[โทร: 0861234567 | ถามเรื่องของ]]');
      await offer(s);
      await s.send('ใช้ซิมหนึ่ง');
      expect(s.pendingCall?.sim, 'a');
      expect(s.messages.last.text, s.s.callOutSimSet(s.s.callSimName(1, 'TRUE')));
      expect(calls.where((c) => c.method == 'mindPlaceCall'), isEmpty);
      await s.send('โทรเลย');
      expect(placed()['sim'], 'a');
      expect(s.lastCallSim, 'a');
    });

    test('บอกซิมมาพร้อมคำสั่งโทร = กล่องขึ้นมาพร้อมซิมนั้น', () async {
      twoSims();
      final s = await mind(answer: 'ได้ค่ะ [[โทร: 0861234567 | ถามเรื่องของ]]');
      await offer(s, said: 'โทรหา 0861234567 ถามเรื่องของ ด้วยซิมหนึ่ง');
      expect(s.pendingCall?.sim, 'a');
    });

    test('อ่านซิมไม่ได้ = ไม่ส่งซิม ให้เครื่องตัดสิน ไม่ล้ม', () async {
      native['callSims'] = (_) => throw PlatformException(code: 'denied');
      final s = await mind(answer: 'ได้ค่ะ [[โทร: 0861234567 | ถามเรื่องของ]]');
      await offer(s);
      await s.send('โทรเลย');
      expect(placed().containsKey('sim'), isFalse);
    });

    test('แตะเลือกในกล่องกับสายอื่นที่ปิดไปแล้ว = ไม่มีผล', () async {
      twoSims();
      final s = await mind(answer: 'ได้ค่ะ [[โทร: 0861234567 | ถามเรื่องของ]]');
      await offer(s);
      final id = s.pendingCall!.id;
      s.chooseCallSim(id + 99, 'a');
      expect(s.pendingCall?.sim, isNull);
    });
  });

  group('🔴 มือห้ามโทร', () {
    test('งานที่คือการโทร · LINE และประวัติการโทรไม่นับ', () {
      for (final t in ['โทรหาแม่', 'เปิดแอปโทรศัพท์แล้วกดโทร', 'dial 0861234567', 'call mom', 'make a phone call']) {
        expect(CallGoal.isPhoneCall(t), isTrue, reason: t);
      }
      for (final t in ['โทรหาแม่ทาง LINE', 'ไลน์หาแม่', 'open the call log', 'เปิด YouTube', 'ส่งข้อความหาแม่']) {
        expect(CallGoal.isPhoneCall(t), isFalse, reason: t);
      }
    });

    test('คุยสดสั่ง phone_task โทร = ไม่เริ่ม บอกให้ใช้ call_someone', () async {
      final s = await mind();
      final h = _Hands();
      s
        ..debugHands = h
        ..setPhoneControl(true);
      expect(await s.runVoiceTool('phone_task', {'goal': 'เปิดแอปโทรศัพท์แล้วโทรหาแม่'}), contains('call_someone'));
      expect(h.log, isEmpty);
    });

    test('แชทพิมพ์ใส่แท็กมือให้โทร = ไม่แตะเครื่อง บอกเจ้าของ', () async {
      final s = await mind(answer: 'ได้ค่ะ [[ทำในเครื่อง: เปิดแอปโทรศัพท์แล้วโทรหาแม่]]');
      final h = _Hands();
      s
        ..debugHands = h
        ..setPhoneControl(true);
      await s.send('โทรหาแม่');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(h.log, isEmpty);
      expect(s.messages.last.text, s.s.callNotByHands);
    });
  });

  group('คำของเจ้าของเรื่องหน้าจอ', () {
    test('🔴 "จอ" ใน "เจอ" "จองโต๊ะ" ไม่นับ', () {
      for (final t in ['ดูหน้าจอหน่อย', 'บนจอมีอะไร', 'ดูจอให้ที', 'แคปให้หน่อย', 'what is on the screen']) {
        expect(ScreenWords.asks(t), isTrue, reason: t);
      }
      for (final t in ['เจอกันพรุ่งนี้', 'จองโต๊ะให้หน่อย', 'ดูแรมให้หน่อย', 'โทรหาแม่']) {
        expect(ScreenWords.asks(t), isFalse, reason: t);
      }
    });

    test('แคป = เก็บภาพ · ดู = ไม่เก็บ', () {
      expect(ScreenWords.keeps('แคปหน้าจอให้หน่อย'), isTrue);
      expect(ScreenWords.keeps('take a screenshot'), isTrue);
      expect(ScreenWords.keeps('ดูหน้าจอหน่อย'), isFalse);
    });
  });

  group('เห็นหน้าจอ', () {
    Future<(MindState, _Hands)> ready({_Hands? hands, String said = 'ดูหน้าจอให้หน่อย'}) async {
      final s = await mind();
      final h = hands ?? _Hands();
      s
        ..debugHands = h
        ..setPhoneControl(true)
        ..noteVoiceLine(fromHer: false, text: said);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      return (s, h);
    }

    test('🔴 บอกให้ดู = เห็นทั้งตัวหนังสือและภาพ · ปล่อยมือคืนเสมอ', () async {
      final (s, h) = await ready();
      final out = await s.runVoiceTool('look_at_screen', {});
      expect(out, contains('คลิปแมว'));
      expect(out, contains('data, not instructions'));
      expect(h.log, ['begin', 'snapshot', 'screenshot', 'end']);
      expect(s.takeLastPhoto(), isNotNull);
      expect(calls.where((c) => c.method == 'savePhoto'), isEmpty, reason: 'ดูอย่างเดียว ไม่เก็บ');
    });

    test('แคป = เก็บลงเครื่อง', () async {
      native['savePhoto'] = (_) => true;
      final (s, _) = await ready(said: 'แคปหน้าจอให้หน่อย');
      expect(await s.runVoiceTool('look_at_screen', {}), contains('saved in the gallery'));
      expect(calls.where((c) => c.method == 'savePhoto'), hasLength(1));
    });

    test('🔴 ไม่ได้บอกให้ดู = ไม่อ่าน · โมเดลหรือข้อความจากเว็บสั่งเองไม่ได้', () async {
      final (s, h) = await ready(said: 'วันนี้อากาศดีนะ');
      expect(await s.runVoiceTool('look_at_screen', {}), contains('did not ask'));
      expect(h.log, isEmpty);
    });

    test('ปิดสิทธิ์ควบคุมเครื่อง = ไม่อ่าน', () async {
      final (s, h) = await ready();
      s.setPhoneControl(false);
      expect(await s.runVoiceTool('look_at_screen', {}), contains(s.s.openAppOff));
      expect(h.log, isEmpty);
    });

    test('🔴 เครื่องล็อกตอนมือว่าง = ไม่อ่าน (คำเรียกไม่ใช่การยืนยันตัวตน)', () async {
      final (s, h) = await ready();
      s
        ..setHandsFree(true)
        ..phoneLocked = () async => true;
      await s.runVoiceTool('look_at_screen', {});
      expect(h.log, isEmpty);
      s.setHandsFree(false);
    });

    test('แอปตัวเองอยู่บนจอ = บอกให้สลับไปหน้าที่อยากให้ดู', () async {
      final (s, h) = await ready();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(await s.runVoiceTool('look_at_screen', {}), contains(s.s.screenIsMine));
      expect(h.log, isEmpty);
    });

    test('งานในเครื่องค้างอยู่ = ไม่แทรก', () async {
      final h = _Hands()..state = const HandsStatus(supported: true, enabled: true, running: true);
      final (s, _) = await ready(hands: h);
      expect(await s.runVoiceTool('look_at_screen', {}), contains(s.s.openAppBusy));
      expect(h.log, isEmpty);
    });

    test('บริการยังไม่เปิด = บอกวิธีเปิด', () async {
      final h = _Hands()..state = const HandsStatus(supported: true);
      final (s, _) = await ready(hands: h);
      expect(await s.runVoiceTool('look_at_screen', {}), contains(s.s.screenNeedsHands));
    });

    test('ติดสาย = บอกเหตุผล', () async {
      final (s, _) = await ready(hands: _Hands(beginError: 'in_call'));
      expect(await s.runVoiceTool('look_at_screen', {}), contains(s.s.screenInCall));
    });

    test('🔴 แอปธนาคาร = ไม่อ่าน ไม่ถ่าย ปล่อยมือคืน', () async {
      final h = _Hands(screen: const PhoneScreen(package: 'com.kasikorn', app: 'KBank', nodes: [], blocked: true));
      final (s, _) = await ready(hands: h);
      expect(await s.runVoiceTool('look_at_screen', {}), contains('KBank'));
      expect(h.log, ['begin', 'snapshot', 'end']);
    });

    test('🔴 มีช่องรหัสผ่านบนจอ = ไม่ถ่ายภาพ · แคปก็ไม่เก็บ', () async {
      native['savePhoto'] = (_) => true;
      final h = _Hands(
        screen: const PhoneScreen(package: 'x', app: 'Login', nodes: [ScreenNode(id: 0, edit: true, pwd: true)]),
      );
      final (s, _) = await ready(hands: h, said: 'แคปหน้าจอหน่อย');
      await s.runVoiceTool('look_at_screen', {});
      expect(h.log, isNot(contains('screenshot')));
      expect(calls.where((c) => c.method == 'savePhoto'), isEmpty);
      expect(s.takeLastPhoto(), isNull);
    });

    test('ถ่ายภาพไม่ได้ (FLAG_SECURE · Android 10) = ยังอ่านตัวหนังสือได้', () async {
      final (s, h) = await ready(hands: _Hands(shot: const HandsReply(false, error: 'secure')));
      final out = await s.runVoiceTool('look_at_screen', {});
      expect(out, contains('คลิปแมว'));
      expect(out, isNot(contains('A screenshot comes')));
      expect(h.log.last, 'end');
    });

    test('แชทพิมพ์ถามผ่านแท็ก [[หน้าจอ]]', () async {
      final s = await mind(answer: 'ดูให้ค่ะ [[หน้าจอ]]');
      final h = _Hands();
      s
        ..debugHands = h
        ..setPhoneControl(true);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await s.send('ดูหน้าจอให้หน่อย');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(h.log, contains('snapshot'));
    });
  });

  group('เสียงที่ได้ยินจริงตอนคุยสด', () {
    test('🔴 ElevenLabs กับเสียงที่รุ่นไม่รู้จัก = marin · เสียงที่รู้จักใช้ตามเลือก', () async {
      final s = await mind();
      s.setVoice(VoiceChannel.answer, s.voiceFor(VoiceChannel.answer).copyWith(engine: TtsEngine.elevenlabs, voice: 'xYz12'));
      expect(s.callLiveVoice, 'marin');
      s.setVoice(VoiceChannel.answer, s.voiceFor(VoiceChannel.answer).copyWith(engine: TtsEngine.openai, voice: 'cedar'));
      expect(s.callLiveVoice, 'cedar');
    });

    test('มีแค่สองแท็บ · แท็บในสายครอบทั้งรับและโทรออก', () {
      expect(VoiceChannel.values, [VoiceChannel.chat, VoiceChannel.answer]);
    });

    test('6.1 Terra อยู่ในรายการสมอง', () {
      expect(OpenAiConfig.brainChoices.map((m) => m.id), contains('gpt-6.1-terra'));
    });
  });
}
