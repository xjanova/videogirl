/// เครื่องมือของมายด์เอง — เปิดเสียงสาย เปิดแอป ดูเครื่อง ดึงจอกลับ กล้อง และตา
///
/// ที่มา: เจ้าของ — "มายด์ ต้องเปิดยูทูป หรือแอพอื่นๆในเครื่องได้ จัดการเครื่อง ดูแรม สเปค ได้ทั้งหมด
/// เปิดกล้อง เพื่อถ่ายรูป และให้เธอมีตา คือเห็นเราผ่านกล้องมือถือได้ ขณะคุยกับเรา"
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/mind_eyes.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/ai/realtime_chat.dart';
import 'package:videogirl/ai/voice_chat.dart';
import 'package:videogirl/hands/hands_bridge.dart';
import 'package:videogirl/hands/hands_tag.dart';
import 'package:videogirl/phone/call_notes.dart';
import 'package:videogirl/phone/call_target.dart';
import 'package:videogirl/phone/phone_lookup.dart';
import 'package:videogirl/phone/realtime_call.dart';
import 'package:videogirl/phone/voice_session.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';
import 'package:videogirl/widgets/eyes_overlay.dart';

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

class _Socket implements RtSocket {
  final sent = <Map<String, Object?>>[];
  final _in = StreamController<Object?>();
  bool closed = false;
  @override
  Stream<Object?> get messages => _in.stream;
  @override
  void send(String text) => sent.add((jsonDecode(text) as Map).cast<String, Object?>());
  @override
  Future<void> close() async {
    closed = true;
    if (!_in.isClosed) await _in.close();
  }

  void push(Map<String, Object?> e) => _in.add(jsonEncode(e));

  /// รายการที่ส่งเข้าบทสนทนา · ชนิดตาม item.type หรือ content[0].type
  List<String> get items => [
        for (final e in sent.where((e) => e['type'] == 'conversation.item.create'))
          () {
            final item = e['item'] as Map;
            final c = item['content'];
            return c is List && c.isNotEmpty ? '${(c.first as Map)['type']}' : '${item['type']}';
          }(),
      ];
}

class _Mic implements ChatMic {
  StreamController<Uint8List>? ctl;
  @override
  bool survivesBackground = true;
  @override
  Future<Stream<Uint8List>> open() async {
    ctl = StreamController<Uint8List>();
    return ctl!.stream;
  }

  @override
  Future<void> close() async => ctl?.close();

  @override
  void dispose() {}
}

/// กล้องปลอม · จดลำดับคำสั่ง · [gateOpen] / [gateSnap] ค้างคำสั่งไว้จนกว่าเทสต์จะปล่อย
class _Camera implements EyeCamera {
  final log = <String>[];
  Completer<void>? gateOpen, gateSnap;
  bool failOpen = false;

  @override
  Future<void> open({required bool front}) async {
    log.add(front ? 'open:front' : 'open:back');
    await gateOpen?.future;
    if (failOpen) throw StateError('in use');
  }

  @override
  Future<Uint8List> snap() async {
    log.add('snap');
    await gateSnap?.future;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> close() async => log.add('close');

  @override
  Widget preview() => const SizedBox.shrink();
}

/// มือปลอม · ใช้แค่สองคำสั่ง
class _Hands implements Hands {
  _Hands({this.reply = const HandsReply(true, data: {'ok': true, 'label': 'YouTube'})});
  HandsReply reply;
  HandsStatus state = const HandsStatus(supported: true, enabled: true);
  final opened = <String>[];

  @override
  Future<HandsStatus> status() async => state;

  @override
  Future<HandsReply> openApp(String name) async {
    opened.add(name);
    return reply;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _settle([int times = 12]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

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

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(kSystemChannel, null));

  Future<MindState> mind({String answer = 'ได้ค่ะ'}) async {
    final s = MindState(openai: _Brain(answer));
    addTearDown(s.dispose);
    await s.load();
    s.setBrain(BrainProvider.openai);
    await s.setOpenAiKey('sk-test-key-for-unit-tests');
    s.debugCallTargets = CallTargetResolver(clock: () => DateTime.now());
    return s;
  }

  Iterable<MethodCall> sys(String method) => calls.where((c) => c.method == method);

  group('คำของเจ้าของเรื่องกล้อง', () {
    test('คำที่นับว่าขอให้มอง · "ดู" ทั่วไปไม่นับ', () {
      for (final t in ['เปิดกล้องหน่อย', 'มองหน้าฉันสิ', 'เห็นไหม', 'ถ่ายรูปให้หน่อย', 'ดูหน่อยซิ', 'ดูชุดนี้', 'can you see me', 'take a selfie']) {
        expect(EyesWords.ask.hasMatch(t), isTrue, reason: t);
      }
      for (final t in ['ดูข่าววันนี้ให้หน่อย', 'ดูแรมเครื่องให้ที', 'เห็นด้วยค่ะ', 'look up the weather', 'โทรหาแม่']) {
        expect(EyesWords.ask.hasMatch(t), isFalse, reason: t);
      }
    });

    test('คำสั่งปิดกล้อง', () {
      for (final t in ['ปิดกล้องด้วย', 'เลิกมองได้แล้ว', 'stop looking', 'turn off the camera']) {
        expect(EyesWords.off(t), isTrue, reason: t);
      }
      expect(EyesWords.off('เปิดกล้องหน่อย'), isFalse);
    });
  });

  group('แท็กที่ทำได้ทันที', () {
    test('แยกแอป เสียงสาย รูป ออกจากคำตอบ', () {
      final q = QuickTag.parse('ได้ค่ะ\n[[เปิดแอป: YouTube]]\n[[เปิดเสียงสาย: แม่]]\n[[ถ่ายรูป: หลัง]]');
      expect(q.text, 'ได้ค่ะ');
      expect(q.app, 'YouTube');
      expect(q.recording, 'แม่');
      expect(q.photo, 'หลัง');
      expect(QuickTag.backCamera(q.photo!), isTrue);
    });

    test('ไม่ระบุ = ล่าสุด / กล้องหน้า · ไม่มีแท็ก = null', () {
      final q = QuickTag.parse('[[เปิดเสียงสาย]] [[ถ่ายรูป]]');
      expect(q.recording, '');
      expect(q.photo, '');
      expect(QuickTag.backCamera(q.photo!), isFalse);
      final none = QuickTag.parse('สวัสดีค่ะ');
      expect((none.app, none.recording, none.photo), (null, null, null));
    });
  });

  group('ดูเครื่อง', () {
    final phone = {
      'maker': 'vivo',
      'model': 'V2144',
      'android': '15',
      'sdk': 35,
      'cores': 8,
      'abi': 'arm64-v8a',
      'ramTotal': 8 * 1024 * 1024 * 1024,
      'ramFree': 3 * 1024 * 1024 * 1024,
      'diskTotal': 128 * 1024 * 1024 * 1024,
      'diskFree': 64 * 1024 * 1024 * 1024,
      'battery': 76,
      'charging': true,
    };

    test('สรุปแรม พื้นที่ แบต เป็นตัวเลขอ่านได้', () {
      final d = PhoneLookup.describeDevice(phone);
      expect(d, contains('vivo V2144'));
      expect(d, contains('RAM: 3.0 GB free of 8.0 GB'));
      expect(d, contains('Storage: 64.0 GB free of 128.0 GB'));
      expect(d, contains('Battery: 76%, charging'));
    });

    test('เธอถามเครื่องผ่านเครื่องมือ phone_lookup', () async {
      native['deviceStatus'] = (_) => phone;
      final s = await mind();
      expect(await s.runVoiceTool('phone_lookup', {'kind': 'device', 'query': ''}), contains('RAM: 3.0 GB'));
    });
  });

  group('เปิดแอป', () {
    Future<(MindState, _Hands)> ready({HandsReply? reply}) async {
      final s = await mind();
      final h = _Hands(reply: reply ?? const HandsReply(true, data: {'ok': true, 'label': 'YouTube'}));
      s.debugHands = h;
      s.setPhoneControl(true);
      return (s, h);
    }

    test('🔴 เปิดได้ทันทีด้วยเครื่องมือ', () async {
      final (s, h) = await ready();
      expect(await s.runVoiceTool('open_app', {'name': 'YouTube'}), contains('YouTube'));
      expect(h.opened, ['YouTube']);
    });

    test('ปิดสิทธิ์ควบคุมเครื่องไว้ = ไม่เปิด', () async {
      final (s, h) = await ready();
      s.setPhoneControl(false);
      await s.runVoiceTool('open_app', {'name': 'YouTube'});
      expect(h.opened, isEmpty);
    });

    test('🔴 เครื่องล็อกตอนมือว่าง = ไม่เปิด (คำเรียกไม่ใช่การยืนยันตัวตน)', () async {
      final (s, h) = await ready();
      s
        ..setHandsFree(true)
        ..phoneLocked = () async => true;
      await s.runVoiceTool('open_app', {'name': 'YouTube'});
      expect(h.opened, isEmpty);
      s.setHandsFree(false);
    });

    test('🔴 แอปการเงินถูกกันที่ฝั่ง Android = บอกตรง ๆ ไม่อ้างว่าเปิดแล้ว', () async {
      final (s, _) = await ready(reply: const HandsReply(false, error: 'blocked', data: {'label': 'KBank'}));
      final out = await s.runVoiceTool('open_app', {'name': 'KBank'});
      expect(out, contains('KBank'));
      expect(out, contains(s.s.openAppBlocked('KBank')));
    });

    test('มีงานในเครื่องค้างอยู่ = ไม่แทรก', () async {
      final (s, h) = await ready();
      h.state = const HandsStatus(supported: true, enabled: true, running: true);
      await s.runVoiceTool('open_app', {'name': 'YouTube'});
      expect(h.opened, isEmpty);
    });
  });

  group('เปิดเสียงสายที่บันทึกไว้', () {
    late Directory dir;
    late CallNotes notes;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('recordings');
      CallRecordings.debugDir = dir;
      notes = CallNotes();
    });

    tearDown(() async {
      CallRecordings.debugDir = null;
      await dir.delete(recursive: true);
    });

    Future<void> note(String id, String who) async {
      await File('${dir.path}/$id.wav').writeAsBytes([0, 1, 2, 3]);
      await notes.add(CallNote(id: id, at: DateTime(2026, 11, 1), who: who, summary: 'นัดส่งของ', lines: const []));
    }

    test('🔴 "เปิดเสียงที่บันทึกไว้ให้ฟัง" = เล่นไฟล์ของคนนั้น แล้วหยุดได้', () async {
      await note('a1', 'คุณแม่');
      await note('a2', 'ร้านกาแฟ');
      final finish = Completer<bool>();
      native['playAudioFile'] = (_) => finish.future;
      final s = await mind();
      s.attachCallNotes(notes);
      await s.runVoiceTool('play_recording', {'who': 'แม่'});
      expect(s.playingRecording, isTrue);
      await _settle();
      final played = sys('playAudioFile').single.arguments as Map;
      expect(played['path'], endsWith('a1.wav'));

      await s.stopRecording();
      expect(s.playingRecording, isFalse);
      expect(sys('stopAudioFile'), hasLength(1));
      finish.complete(true);
    });

    test('ไม่บอกชื่อ = ล่าสุด · ไม่เจอ = บอกตรง ๆ ไม่เล่น', () async {
      await note('a1', 'คุณแม่');
      await note('a2', 'ร้านกาแฟ');
      native['playAudioFile'] = (_) => true;
      final s = await mind();
      s.attachCallNotes(notes);
      expect(await s.runVoiceTool('play_recording', {'who': 'ธนาคาร'}), contains(s.s.recordingNone('ธนาคาร')));
      expect(s.playingRecording, isFalse);
      await s.runVoiceTool('play_recording', {'who': ''});
      await _settle();
      expect((sys('playAudioFile').single.arguments as Map)['path'], endsWith('a2.wav'));
    });

    test('🔴 เครื่องล็อกตอนมือว่าง = ไม่เล่นบทสนทนาของเจ้าของออกลำโพง', () async {
      await note('a1', 'คุณแม่');
      final s = await mind();
      s
        ..attachCallNotes(notes)
        ..setHandsFree(true)
        ..phoneLocked = () async => true;
      await s.runVoiceTool('play_recording', {'who': 'แม่'});
      expect(s.playingRecording, isFalse);
      s.setHandsFree(false);
    });
  });

  group('🔴 ดึงจอกลับมาให้เจ้าของแตะ', () {
    Future<void> card(MindState s) async {
      await s.runVoiceTool('call_someone', {'who': '0899999999', 'task': 'นัด', 'script': 'ฮัลโล'});
      await _settle();
    }

    test('แอปอยู่หลังบ้าน = เรียกกลับ · กล่องหาย = เก็บแจ้งเตือน', () async {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final s = await mind();
      await card(s);
      expect(sys('comeBack'), hasLength(1));
      expect((sys('comeBack').single.arguments as Map)['body'], contains('0899999999'));
      s.cancelPendingCall();
      await _settle();
      expect(sys('comeBackDone'), hasLength(1));
    });

    test('แก้บทในกล่องเดิม ไม่เรียกซ้ำ · แอปอยู่บนจออยู่แล้วไม่เรียก', () async {
      final s = await mind();
      await card(s);
      expect(sys('comeBack'), isEmpty);

      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      s.cancelPendingCall();
      await card(s);
      await s.runVoiceTool('call_someone', {'who': '0899999999', 'task': 'นัดใหม่', 'script': 'ฮัลโล'});
      await _settle();
      expect(sys('comeBack'), hasLength(1));
    });
  });

  test('🔴 ทีละตา: เธอถาม "โทรเลยไหมคะ" แล้ว "ใช่" = โทร ไม่ต้องพูดซ้ำ', () async {
    final s = await mind(answer: 'จะแจ้งเรื่องเลื่อนนัดนะคะ โทรเลยไหมคะ');
    await s.runVoiceTool('call_someone', {'who': '0899999999', 'task': 'นัด', 'script': 'ฮัลโล'});
    await _settle();
    s.setHandsFree(true);
    await s.send('สรุปให้ฟังหน่อย');
    expect(sys('mindPlaceCall'), isEmpty);
    await s.send('ใช่');
    expect(sys('mindPlaceCall'), hasLength(1));
    s.setHandsFree(false);
  });

  group('กล้อง (MindEyes)', () {
    test('เปิด ปิด · ข้างเดิมไม่เปิดซ้ำ · สลับข้างปิดก่อนเปิด', () async {
      final cam = _Camera();
      final e = MindEyes(camera: cam);
      expect(await e.turnOn(), isTrue);
      expect(await e.turnOn(), isTrue);
      expect(cam.log, ['open:front']);
      expect(await e.turnOn(front: false), isTrue);
      expect(cam.log, ['open:front', 'close', 'open:back']);
      await e.turnOff();
      expect(e.on, isFalse);
      expect(e.showing, isFalse);
      expect(cam.log.last, 'close');
    });

    test('🔴 สัญญาณขึ้นตั้งแต่เริ่มเปิด · ปิดระหว่างเปิด = ไม่ค้าง', () async {
      final cam = _Camera()..gateOpen = Completer<void>();
      final e = MindEyes(camera: cam);
      final opening = e.turnOn();
      await _settle();
      expect(e.showing, isTrue);
      expect(e.on, isFalse);

      final off = e.turnOff();
      expect(e.showing, isFalse, reason: 'สัญญาณหายทันที');
      cam.gateOpen!.complete();
      expect(await opening, isFalse);
      await off;
      expect(e.on, isFalse);
      expect(cam.log, ['open:front', 'close']);
    });

    test('เปิด-ปิด-เปิดเร็ว ๆ = กล้องจริงรับทีละคำสั่ง · ไม่เปิดซ้อน', () async {
      final gate = Completer<void>();
      final cam = _Camera()..gateOpen = gate;
      final e = MindEyes(camera: cam);
      final first = e.turnOn();
      await _settle();
      final off = e.turnOff();
      final second = e.turnOn();
      await _settle();
      expect(cam.log, ['open:front'], reason: 'รอคำสั่งแรกจบก่อน');
      gate.complete();
      expect(await first, isFalse);
      await off;
      expect(await second, isTrue);
      expect(cam.log, ['open:front', 'close', 'open:front']);
      expect(e.on, isTrue);
    });

    test('🔴 ปิดระหว่างถ่าย = ภาพนั้นไม่ออกไป', () async {
      final cam = _Camera();
      final e = MindEyes(camera: cam);
      await e.turnOn();
      cam.gateSnap = Completer<void>();
      final look = e.look();
      await _settle();
      unawaited(e.turnOff());
      cam.gateSnap!.complete();
      expect(await look, isNull);
    });

    test('เปิดไม่ได้ (แอปอื่นถือกล้อง) = false · ปิดอยู่ = ไม่มีภาพ', () async {
      final e = MindEyes(camera: _Camera()..failOpen = true);
      expect(await e.turnOn(), isFalse);
      expect(e.showing, isFalse);
      expect(await e.look(), isNull);
    });
  });

  testWidgets('🔴 สัญญาณกล้อง: บอกว่าภาพไปไหน · หน้าที่เปิดทับบังไม่ได้ · แตะปิดทันที', (t) async {
    final e = MindEyes(camera: _Camera());
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      builder: (context, child) => Stack(fit: StackFit.expand, children: [child!, EyesOverlay(eyes: e)]),
      home: const Scaffold(body: SizedBox.expand()),
    ));
    expect(find.text('Camera on'), findsNothing);

    await t.runAsync(e.turnOn);
    await t.pump();
    unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Settings')))));
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Camera on'), findsOneWidget);
    expect(find.textContaining('OpenAI'), findsOneWidget);

    await t.tap(find.byIcon(Icons.close_rounded));
    await t.pump();
    expect(e.showing, isFalse);
    expect(find.text('Camera on'), findsNothing);
  });

  group('🔴 กล้องเปิดเมื่อเจ้าของขอเท่านั้น', () {
    Future<(MindState, _Camera)> eyed() async {
      final s = await mind();
      final cam = _Camera();
      s.debugEyes = MindEyes(camera: cam);
      return (s, cam);
    }

    test('เจ้าของไม่ได้ขอ = เปิดไม่ได้ · โมเดลหรือข้อความจากเว็บสั่งเองไม่ได้', () async {
      final (s, cam) = await eyed();
      s.noteVoiceLine(fromHer: false, text: 'ค้นข่าววันนี้ให้หน่อย');
      final out = await s.runVoiceTool('open_eyes', {'camera': 'front'});
      expect(out, contains('Not opened'));
      expect(cam.log, isEmpty);
    });

    test('เจ้าของขอแล้วนานเกินครึ่งนาที = คำนั้นหมดอายุ', () async {
      var now = DateTime(2026, 11, 1, 12);
      final s = MindState(openai: _Brain('ได้ค่ะ'), clock: () => now);
      addTearDown(s.dispose);
      await s.load();
      final cam = _Camera();
      s.debugEyes = MindEyes(camera: cam);
      s.noteVoiceLine(fromHer: false, text: 'มองหน้าฉันหน่อย');
      now = now.add(const Duration(seconds: 31));
      await s.runVoiceTool('open_eyes', {'camera': 'front'});
      expect(cam.log, isEmpty);
    });

    test('เจ้าของขอ = เปิด · ปิดด้วยเครื่องมือได้', () async {
      final (s, cam) = await eyed();
      s.noteVoiceLine(fromHer: false, text: 'มองหน้าฉันหน่อย');
      expect(await s.runVoiceTool('open_eyes', {'camera': 'front'}), contains('camera is on'));
      expect(s.eyes.on, isTrue);
      await s.runVoiceTool('close_eyes', {});
      expect(s.eyes.on, isFalse);
      expect(cam.log, ['open:front', 'close']);
    });

    test('คำของเจ้าของมาช้ากว่าเครื่องมือ = รอฟังก่อนตัดสิน', () async {
      final (s, cam) = await eyed();
      final opening = s.runVoiceTool('open_eyes', {'camera': 'back'});
      await Future<void>.delayed(const Duration(milliseconds: 250));
      s.noteVoiceLine(fromHer: false, text: 'ดูนี่หน่อยสิ');
      await opening;
      expect(cam.log, ['open:back']);
    });

    test('เครื่องล็อกตอนมือว่าง = ไม่เปิด แม้พูดว่าขอ', () async {
      final (s, cam) = await eyed();
      s
        ..setHandsFree(true)
        ..phoneLocked = () async => true;
      s.noteVoiceLine(fromHer: false, text: 'เปิดกล้องหน่อย');
      expect(await s.runVoiceTool('open_eyes', {'camera': 'front'}), contains('locked'));
      expect(cam.log, isEmpty);
      s.setHandsFree(false);
    });

    test('แอปอยู่หลังบ้าน = ไม่เปิด · เจ้าของไม่เห็นสัญญาณ', () async {
      final (s, cam) = await eyed();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      s.noteVoiceLine(fromHer: false, text: 'เปิดกล้องหน่อย');
      await s.runVoiceTool('open_eyes', {'camera': 'front'});
      expect(cam.log, isEmpty);
    });

    test('🔴 ถ่ายรูป: เก็บเข้าคลัง ปิดกล้องคืน · ภาพให้เธอเห็นครั้งเดียว', () async {
      native['savePhoto'] = (_) => true;
      final (s, cam) = await eyed();
      s.noteVoiceLine(fromHer: false, text: 'ถ่ายรูปให้หน่อย');
      expect(await s.runVoiceTool('take_photo', {'camera': 'back'}), contains(s.s.photoSaved));
      expect(cam.log, ['open:back', 'snap', 'close']);
      expect(s.eyes.showing, isFalse);
      expect(sys('savePhoto'), hasLength(1));
      expect(s.takeLastPhoto(), isNotNull);
      expect(s.takeLastPhoto(), isNull);
    });

    test('กำลังมองอยู่แล้วถ่ายกล้องหลัง = กลับมาข้างเดิม ไม่ปิดตา', () async {
      native['savePhoto'] = (_) => true;
      final (s, cam) = await eyed();
      s.noteVoiceLine(fromHer: false, text: 'เปิดกล้องแล้วถ่ายรูป');
      await s.runVoiceTool('open_eyes', {'camera': 'front'});
      await s.runVoiceTool('take_photo', {'camera': 'back'});
      expect(cam.log, ['open:front', 'close', 'open:back', 'snap', 'close', 'open:front']);
      expect(s.eyes.on, isTrue);
      expect(s.eyes.front, isTrue);
    });

    test('แชทพิมพ์: ถ่ายเก็บได้ · ภาพไม่ถูกเก็บไว้ส่งต่อ', () async {
      native['savePhoto'] = (_) => true;
      final s = await mind(answer: 'ได้ค่ะ [[ถ่ายรูป: หลัง]]');
      final cam = _Camera();
      s.debugEyes = MindEyes(camera: cam);
      await s.send('ถ่ายรูปให้หน่อย');
      await _settle(40);
      expect(cam.log, ['open:back', 'snap', 'close']);
      expect(s.takeLastPhoto(), isNull);
      expect(s.messages.last.text, s.s.photoSaved);
    });
  });

  group('🔴 ตาขณะคุยสด', () {
    late DateTime now;
    late _Mic mic;

    setUp(() {
      now = DateTime(2026, 11, 1, 9);
      mic = _Mic();
    });

    Future<(MindState, VoiceChat, _Socket, _Camera)> live() async {
      final s = await mind();
      final cam = _Camera();
      s.debugEyes = MindEyes(camera: cam);
      final sock = _Socket();
      native['liveAudioStart'] = (_) => true;
      native['liveAudioPending'] = (_) => 0;
      s.debugRealtimeConnect = (_, _) async => sock;
      final c = VoiceChat(state: s, sendTurn: (_) async {}, ensureMic: () async => true, mic: mic, clock: () => now);
      addTearDown(c.dispose);
      await c.start();
      expect(c.engine, VoiceChatEngine.live);
      return (s, c, sock, cam);
    }

    Future<void> openEyes(_Socket sock) async {
      sock.push({'type': 'conversation.item.input_audio_transcription.completed', 'transcript': 'มองหน้าฉันหน่อย'});
      await _settle();
      sock.push({
        'type': 'response.output_item.done',
        'item': {'type': 'function_call', 'name': 'open_eyes', 'call_id': 'c1', 'arguments': '{"camera":"front"}'},
      });
      await _settle(30);
    }

    test('เปิดตา = ภาพไปก่อนผลเครื่องมือ · เธอตอบจากภาพนั้นได้ทันที', () async {
      final (_, c, sock, _) = await live();
      await openEyes(sock);
      expect(sock.items, ['input_image', 'function_call_output']);
      final image = sock.sent.firstWhere((e) => e['type'] == 'conversation.item.create')['item'] as Map;
      expect(image['role'], 'user');
      expect(((image['content'] as List).first as Map)['image_url'], startsWith('data:image/jpeg;base64,'));
      await c.stop();
    });

    test('ส่งภาพตอนเจ้าของเริ่มพูด ไม่ถี่กว่า minGap · ไม่ใช่วิดีโอ', () async {
      final (_, c, sock, _) = await live();
      await openEyes(sock);
      int images() => sock.items.where((t) => t == 'input_image').length;

      sock.push({'type': 'input_audio_buffer.speech_started'});
      await _settle();
      expect(images(), 1, reason: 'เพิ่งส่งไป');

      now = now.add(MindEyes.minGap);
      sock.push({'type': 'input_audio_buffer.speech_started'});
      await _settle();
      expect(images(), 2);
      await c.stop();
    });

    test('กล้องปิดอยู่ = เจ้าของพูดก็ไม่มีภาพ', () async {
      final (_, c, sock, cam) = await live();
      sock.push({'type': 'input_audio_buffer.speech_started'});
      await _settle();
      expect(sock.items.contains('input_image'), isFalse);
      expect(cam.log, isEmpty);
      await c.stop();
    });

    test('🔴 "ปิดกล้อง" ปิดทันทีในเครื่อง ไม่รอโมเดล', () async {
      final (s, c, sock, _) = await live();
      await openEyes(sock);
      expect(s.eyes.on, isTrue);
      sock.push({'type': 'conversation.item.input_audio_transcription.completed', 'transcript': 'ปิดกล้องได้แล้ว'});
      await _settle();
      expect(s.eyes.showing, isFalse);
      await c.stop();
    });

    test('🔴 ปิดไมค์ = กล้องปิดด้วย · ไม่เปิดคืนเอง', () async {
      final (s, c, sock, cam) = await live();
      await openEyes(sock);
      await c.stop();
      expect(s.eyes.showing, isFalse);
      expect(cam.log.last, 'close');
    });
  });

  test('sendImage ส่งเป็นข้อความผู้ใช้ และไม่สั่งให้เธอตอบ', () async {
    final sock = _Socket();
    final rt = RealtimeChat(
      apiKey: 'k',
      instructions: 'i',
      tools: chatVoiceTools(web: false, phone: false),
      runChatTool: (_, _) async => '',
      connect: (_, _) async => sock,
    );
    await rt.start();
    sock.sent.clear();
    rt.sendImage(Uint8List.fromList([1, 2]));
    expect(sock.items, ['input_image']);
    expect(sock.sent.where((e) => e['type'] == 'response.create'), isEmpty);
    await rt.close();
  });

  test('เครื่องมือตาอยู่ในชุดคุยสดเสมอ · เปิดแอปเฉพาะเมื่อให้คุมเครื่อง', () {
    List<Object?> names(bool phone) => [for (final t in chatVoiceTools(web: false, phone: phone)) t['name']];
    expect(names(false), containsAll(['open_eyes', 'close_eyes', 'take_photo', 'play_recording']));
    expect(names(false), isNot(contains('open_app')));
    expect(names(true), contains('open_app'));
  });
}
