/// คุยต่อเนื่องด้วยเสียงในแชท — แตะไมค์ครั้งเดียว พูดแล้วหยุด เธอตอบเอง ไม่ต้องกดส่ง
///
/// ที่มา: เจ้าของ — "การกดไมค์พูดกับเธอควรพูดโต้ตอบได้เรียลไทม์ เหมือนที่เราทำกับการรับสาย ...
/// ไม่ต้องมากดส่งอีก เพราะเราออกแบบให้แอพนี้ใช้งานแม้ในขับรถได้"
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/ai/realtime_chat.dart';
import 'package:videogirl/ai/voice_chat.dart';
import 'package:videogirl/i18n/strings_ai.dart';
import 'package:videogirl/phone/call_target.dart';
import 'package:videogirl/phone/voice_session.dart';
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
  Iterable<Map<String, Object?>> of(String type) => sent.where((e) => e['type'] == type);
}

class _Mic implements ChatMic {
  StreamController<Uint8List>? ctl;
  int opened = 0, closed = 0;
  @override
  Future<Stream<Uint8List>> open() async {
    opened++;
    ctl = StreamController<Uint8List>();
    return ctl!.stream;
  }

  @override
  Future<void> close() async {
    closed++;
    await ctl?.close();
  }

  @override
  void dispose() {}
}

/// เสียง 100 มิลลิวินาทีที่ระดับ [level] (RMS)
Uint8List _pcm(double level) {
  final b = ByteData(1600 * 2);
  final v = (level * 32767).round();
  for (var i = 0; i < 1600; i++) {
    b.setInt16(i * 2, v, Endian.little);
  }
  return b.buffer.asUint8List();
}

Map<String, Object?> _call(String number, DateTime at, {int type = 1}) => {
      'id': at.millisecondsSinceEpoch,
      'at': at.millisecondsSinceEpoch,
      'type': type,
      'number': number,
      'name': null,
      'seconds': 0,
    };

Future<void> _settle([int times = 6]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late Map<String, Object? Function(MethodCall)> native;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    native = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kSystemChannel, (c) async {
      calls.add(c);
      return native[c.method]?.call(c);
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(kSystemChannel, null));

  Future<MindState> mind() async {
    final s = MindState(openai: _Brain('ได้ค่ะ'));
    addTearDown(s.dispose);
    await s.load();
    s.setBrain(BrainProvider.openai);
    await s.setOpenAiKey('sk-test-key-for-unit-tests');
    s.debugCallTargets = CallTargetResolver(clock: () => DateTime.now());
    return s;
  }

  void phoneWithBua() {
    native['findContacts'] = (_) => <Object?>[];
    native['contactIndex'] = (_) => [
          {'name': 'บัวบาน', 'number': '0822222222'},
          {'name': 'Bua Flower', 'number': '0844444444'},
        ];
    native['recentCalls'] = (_) => [_call('0861234567', DateTime.now().subtract(const Duration(hours: 2)), type: 3)];
  }

  group('ในแชท (MindState)', () {
    test('คุยสดได้เมื่อเป็น OpenAI ด้วยคีย์ของเจ้าของ และไม่ได้ปิดไว้', () async {
      final s = await mind();
      expect(s.voiceChatLiveReady, isTrue);
      s.setVoiceChatLive(false);
      expect(s.voiceChatLiveReady, isFalse);
    });

    test('prompt คุยสด = บุคลิกในแชท + เครื่องมือ · ไม่สอนแท็ก [[โทร]] (เธอจะอ่านวงเล็บออกเสียง)', () async {
      final s = await mind();
      final p = s.voiceChatPrompt();
      expect(p, contains('call_someone'));
      expect(p, contains('end_conversation'));
      expect(p, isNot(contains('[[โทร:')));
      expect(p, isNot(contains('[[รายชื่อ')));
    });

    test('🔴 call_someone: ไม่ชัด = คืนรายการให้เธอถาม · ไม่โทร · รายการขึ้นแชทให้แตะได้', () async {
      phoneWithBua();
      final s = await mind();
      final out = await s.runVoiceTool('call_someone', {'who': 'ลูกค้าบัว', 'task': 'ถามว่าได้รับของหรือยัง'});
      expect(out, contains('Not dialed'));
      expect(out, contains('บัวบาน'));
      expect(out, contains('0861234567'));
      expect(s.callChoice?.choices, hasLength(3));
      expect(s.pendingCall, isNull);
      expect(s.messages.last.fromHer, isTrue);
      expect(s.messages.last.text, contains('บัวบาน'));
      expect(calls.where((c) => c.method == 'mindPlaceCall'), isEmpty);
    });

    test('🔴 เลือกแล้ว = กล่องยืนยัน · "โทรเลยค่ะ" จากปากเจ้าของ = โทร · ประโยคอื่นไม่นับ', () async {
      phoneWithBua();
      final s = await mind();
      await s.runVoiceTool('call_someone', {'who': 'บัว', 'task': 'ถามเรื่องของ'});
      final out = await s.runVoiceTool('call_someone', {'who': 'บัวบาน', 'task': 'ถามเรื่องของ'});
      expect(out, contains('confirmation card'));
      expect(out, contains('Do not say the call has started'));
      await _settle();
      expect(s.pendingCall?.number, '0822222222');
      expect(calls.where((c) => c.method == 'mindPlaceCall'), isEmpty, reason: 'ยังไม่ยืนยัน ห้ามโทร');

      expect(await s.confirmCallByVoice('โทรหาแม่ด้วยนะ'), isFalse);
      expect(await s.confirmCallByVoice('โอเคค่ะ'), isFalse, reason: 'ด้วยเสียง "โอเค" อาจตอบคำถามอื่นของเธอ');
      expect(s.pendingCall, isNotNull);
      expect(await s.confirmCallByVoice('โทรเลยค่ะ'), isTrue);
      final place = calls.singleWhere((c) => c.method == 'mindPlaceCall');
      expect((place.arguments as Map)['number'], '0822222222');
    });

    test('"ยกเลิก" = ไม่โทร · ไม่มีกล่องค้าง = ไม่ตัดสินอะไร', () async {
      phoneWithBua();
      final s = await mind();
      expect(await s.confirmCallByVoice('โทรเลย'), isFalse);
      await s.runVoiceTool('call_someone', {'who': '0899999999', 'task': 'นัดส่งของ'});
      await _settle();
      expect(s.pendingCall?.number, '0899999999');
      expect(await s.confirmCallByVoice('ยกเลิกค่ะ'), isTrue);
      expect(s.pendingCall, isNull);
      expect(calls.where((c) => c.method == 'mindPlaceCall'), isEmpty);
    });

    test('คำที่นับว่า "สั่งโทร" ด้วยเสียง ต้องมีคำว่าโทรชัด ๆ', () {
      for (final s in ['โทรเลย', 'โทรเลยค่ะ', 'โอเคโทรเลย', 'call now', 'ยืนยัน', 'go ahead']) {
        expect(CallReply.saysCall(s), isTrue, reason: s);
      }
      for (final s in ['ใช่', 'โอเค', 'ได้ค่ะ', 'เอาเลย', 'ไม่โทร', 'โทรหาแม่ด้วย']) {
        expect(CallReply.saysCall(s), isFalse, reason: s);
      }
    });

    test('🔴 โหมดมือว่าง (ทีละตา): "ใช่" เฉย ๆ ไม่กดโทร · "โทรเลย" = โทร', () async {
      final s = await mind();
      await s.runVoiceTool('call_someone', {'who': '0899999999', 'task': 'นัดส่งของ'});
      await _settle();
      s.setHandsFree(true);
      await s.send('ใช่');
      expect(calls.where((c) => c.method == 'mindPlaceCall'), isEmpty);
      expect(s.pendingCall, isNotNull);
      await s.send('โทรเลย');
      expect(calls.where((c) => c.method == 'mindPlaceCall'), hasLength(1));
      s.setHandsFree(false);
    });

    test('ใช้มือถือไม่ได้เมื่อเจ้าของปิดไว้ · เครื่องมือที่ไม่รู้จัก = บอกตรง ๆ', () async {
      final s = await mind();
      if (s.phoneControl) s.setPhoneControl(false);
      expect(await s.runVoiceTool('phone_task', {'goal': 'เปิด Gmail'}), contains('not allowed'));
      expect(await s.runVoiceTool('nope', const {}), 'Unknown tool.');
    });

    test('บทพูดคุยสดลงแชทเหมือนพิมพ์ · โหมดมือว่าง = แผงแชทไม่พับหนี', () async {
      final s = await mind();
      s.noteVoiceLine(fromHer: false, text: 'วันนี้มีนัดอะไรบ้าง');
      s.noteVoiceLine(fromHer: true, text: 'บ่ายสองมีประชุมค่ะ');
      s.noteVoiceLine(fromHer: true, text: '   ');
      expect([for (final m in s.messages.reversed.take(2)) m.fromHer], [true, false]);
      expect(s.messages.last.text, 'บ่ายสองมีประชุมค่ะ');

      s.collapseChat();
      s.setHandsFree(true);
      expect(s.chatOpen, isTrue);
      s.setHandsFree(false);
    });
  });

  group('คุยสด (RealtimeChat)', () {
    test('semantic_vad ใจเย็น · ไม่ตัดเสียงตัวเอง · ส่งเครื่องมือของแชท', () async {
      final sock = _Socket();
      final rt = RealtimeChat(
        apiKey: 'k',
        instructions: 'i',
        tools: chatVoiceTools(web: false, phone: false),
        runChatTool: (_, _) async => '',
        connect: (_, _) async => sock,
      );
      await rt.start();
      final session = sock.of('session.update').single['session'] as Map;
      final td = ((session['audio'] as Map)['input'] as Map)['turn_detection'] as Map;
      expect(td['type'], 'semantic_vad');
      expect(td['eagerness'], 'low');
      expect(td['interrupt_response'], isFalse);
      final names = [for (final t in session['tools'] as List) (t as Map)['name']];
      expect(names, containsAll(['call_someone', 'phone_lookup', 'end_conversation']));
      expect(names, isNot(contains('web_search')));
      expect(names, isNot(contains('phone_task')));
      expect(sock.of('response.create'), isEmpty, reason: 'ไม่ทักก่อน · รอเจ้าของพูด');
      await rt.close();
    });

    test('เรียกเครื่องมือ = ทำแล้วส่งผลกลับ · end_conversation = ไม่ส่งผล (ไม่งั้นเธอพูดต่ออีก) แต่บอกให้ปิด', () async {
      final sock = _Socket();
      final ran = <(String, Map<String, Object?>)>[];
      var ended = false;
      final rt = RealtimeChat(
        apiKey: 'k',
        instructions: 'i',
        tools: chatVoiceTools(web: true, phone: true),
        runChatTool: (n, a) async {
          ran.add((n, a));
          return 'found';
        },
        connect: (_, _) async => sock,
      )..onEndCall = () => ended = true;
      await rt.start();
      rt.debugReceive(jsonEncode({
        'type': 'response.output_item.done',
        'item': {'type': 'function_call', 'name': 'phone_lookup', 'call_id': 'c1', 'arguments': '{"kind":"calls","query":"missed"}'},
      }));
      await _settle();
      expect(ran.single.$1, 'phone_lookup');
      expect(ran.single.$2['query'], 'missed');
      final out = sock.of('conversation.item.create').single['item'] as Map;
      expect(out['call_id'], 'c1');
      expect(out['output'], 'found');

      rt.debugReceive(jsonEncode({
        'type': 'response.output_item.done',
        'item': {'type': 'function_call', 'name': 'end_conversation', 'call_id': 'c2', 'arguments': '{}'},
      }));
      await _settle();
      expect(ended, isTrue);
      expect(ran, hasLength(1));
      expect(sock.of('conversation.item.create'), hasLength(1));
      await rt.close();
    });

    test('เครื่องมือล้ม = บอกตรง ๆ ว่าไม่สำเร็จ ห้ามทำเป็นว่าได้', () async {
      final sock = _Socket();
      final rt = RealtimeChat(
        apiKey: 'k',
        instructions: 'i',
        tools: chatVoiceTools(web: false, phone: false),
        runChatTool: (_, _) async => throw StateError('boom'),
        connect: (_, _) async => sock,
      );
      await rt.start();
      rt.debugReceive(jsonEncode({
        'type': 'response.output_item.done',
        'item': {'type': 'function_call', 'name': 'call_someone', 'call_id': 'c1', 'arguments': 'not json'},
      }));
      await _settle();
      final out = (sock.of('conversation.item.create').single['item'] as Map)['output'] as String;
      expect(out, contains('did not work'));
      await rt.close();
    });
  });

  group('ตัวคุม (VoiceChat)', () {
    late DateTime now;
    late _Mic mic;
    late List<String> sent;

    setUp(() {
      now = DateTime(2026, 11, 1, 9);
      mic = _Mic();
      sent = [];
    });

    VoiceChat chatFor(MindState s, {Future<String> Function(Uint8List)? transcribe}) {
      final c = VoiceChat(
        state: s,
        sendTurn: (t) async => sent.add(t),
        ensureMic: () async => true,
        mic: mic,
        transcribe: transcribe,
        clock: () => now,
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<void> feed(double level, int n) async {
      for (var i = 0; i < n; i++) {
        now = now.add(const Duration(milliseconds: 100));
        // ตัวคุมปิดไมค์ไปแล้ว (คำสั่งปิด / ล้มซ้ำ) = เจ้าของพูดใส่ไมค์ที่ดับอยู่
        if (mic.ctl!.isClosed) return;
        mic.ctl!.add(_pcm(level));
        await _settle(3);
      }
    }

    test('🔴 ทีละตา: พูดแล้วหยุด → ประโยคจบ = ส่งให้เธอเอง ไม่ต้องกดส่ง', () async {
      final s = await mind();
      s.setVoiceChatLive(false);
      var asked = 0;
      final c = chatFor(s, transcribe: (_) async {
        asked++;
        return 'โทรหาบัวหน่อยค่ะ';
      });
      await c.start();
      expect(c.active, isTrue);
      expect(c.engine, VoiceChatEngine.turns);
      expect(s.handsFree, isTrue);

      await feed(.004, 5);
      await feed(.1, 10);
      await feed(.004, 9);
      expect(asked, 1, reason: 'ถอดล่วงหน้าครั้งเดียวตอนหยุด');
      expect(sent, ['โทรหาบัวหน่อยค่ะ']);

      await c.stop();
      expect(c.active, isFalse);
      expect(s.handsFree, isFalse);
      expect(mic.closed, 1);
    });

    test('🔴 หยุดคิดกลางประโยค ("แล้วก็") = รอฟังต่อ ยังไม่ส่ง · เงียบครบ 2.2 วิ ค่อยส่ง', () async {
      final s = await mind();
      s.setVoiceChatLive(false);
      final c = chatFor(s, transcribe: (_) async => 'โทรหาบัว แล้วก็');
      await c.start();
      await feed(.004, 5);
      await feed(.1, 10);
      await feed(.004, 12);
      expect(sent, isEmpty, reason: 'คนที่หยุดคิดต้องไม่โดนตัด');
      await feed(.004, 12);
      expect(sent, ['โทรหาบัว แล้วก็']);
      await c.stop();
    });

    test('"พอแล้วค่ะ" = ปิดไมค์ ไม่ส่งเป็นข้อความ', () async {
      final s = await mind();
      s.setVoiceChatLive(false);
      final c = chatFor(s, transcribe: (_) async => 'พอแล้วค่ะ');
      await c.start();
      await feed(.004, 5);
      await feed(.1, 6);
      await feed(.004, 9);
      expect(sent, isEmpty);
      expect(c.active, isFalse);
      expect(s.handsFree, isFalse);
    });

    test('ถอดเสียงล้มติดกันสามครั้ง = ปิดไมค์พร้อมเหตุผล ไม่วนส่งเสียงไปล้มซ้ำ', () async {
      final s = await mind();
      s.setVoiceChatLive(false);
      final c = chatFor(s, transcribe: (_) async => throw const OpenAiFailure('คีย์ใช้ไม่ได้'));
      await c.start();
      await feed(.004, 5);
      for (var i = 0; i < 3 && c.active; i++) {
        await feed(.1, 6);
        await feed(.004, 24);
      }
      expect(c.active, isFalse);
      expect(s.lastError, 'คีย์ใช้ไม่ได้');
      expect(sent, isEmpty);
    });

    test('คุยสดต่อไม่ได้ = เปลี่ยนเป็นทีละตาเอง และบอกเจ้าของ (ไม่ใช่ไมค์ที่ไม่ทำอะไร)', () async {
      final s = await mind();
      native['liveAudioStart'] = (_) => true;
      s.debugRealtimeConnect = (_, _) async => throw const SocketException('offline');
      final c = chatFor(s, transcribe: (_) async => '');
      await c.start();
      expect(c.active, isTrue);
      expect(c.engine, VoiceChatEngine.turns);
      expect(s.lastError, s.s.voiceChatLiveLost(fallback: true));
      final start = calls.firstWhere((m) => m.method == 'liveAudioStart');
      expect((start.arguments as Map)['usage'], 'media', reason: 'นอกสาย = เสียงสื่อ ออกลำโพงรถ/บลูทูธได้');
      expect(calls.where((m) => m.method == 'liveAudioStop'), isNotEmpty);
      await c.stop();
    });

    test('🔴 ปิดคุยสด/เปลี่ยนสมองกลางทาง = ตัดท่อทันที (เสียงต้องไม่ไหลออกไปต่อ)', () async {
      final s = await mind();
      final sock = _Socket();
      native['liveAudioStart'] = (_) => true;
      s.debugRealtimeConnect = (_, _) async => sock;
      final c = chatFor(s);
      await c.start();
      expect(c.engine, VoiceChatEngine.live);
      s.setVoiceChatLive(false);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(c.active, isFalse);
      expect(sock.closed, isTrue);
    });

    test('🔴 คุยสด: ไมค์ส่งเข้าเซิร์ฟเวอร์ · บทลงแชท · "โทรเลย" จากปากเจ้าของ = โทร · ลาแล้ว = ปิดไมค์เอง', () async {
      phoneWithBua();
      final s = await mind();
      final sock = _Socket();
      native['liveAudioStart'] = (_) => true;
      native['liveAudioPending'] = (_) => 0;
      s.debugRealtimeConnect = (_, _) async => sock;
      final c = chatFor(s);
      await c.start();
      expect(c.engine, VoiceChatEngine.live);
      expect(s.handsFree, isTrue);

      await feed(.1, 2);
      expect(sock.of('input_audio_buffer.append'), isNotEmpty);

      sock.push({'type': 'conversation.item.input_audio_transcription.completed', 'transcript': 'โทรหาบัวบานหน่อย'});
      sock.push({'type': 'response.output_audio_transcript.done', 'transcript': 'ได้ค่ะ แป๊บนึงนะคะ'});
      await _settle();
      expect(s.messages[s.messages.length - 2].text, 'โทรหาบัวบานหน่อย');
      expect(s.messages.last.text, 'ได้ค่ะ แป๊บนึงนะคะ');

      sock.push({
        'type': 'response.output_item.done',
        'item': {
          'type': 'function_call',
          'name': 'call_someone',
          'call_id': 'c1',
          'arguments': jsonEncode({'who': 'บัวบาน', 'task': 'ถามเรื่องของ'}),
        },
      });
      await _settle(12);
      expect(s.pendingCall?.number, '0822222222');
      expect(calls.where((m) => m.method == 'mindPlaceCall'), isEmpty);

      sock.push({'type': 'conversation.item.input_audio_transcription.completed', 'transcript': 'โทรเลยค่ะ'});
      await _settle(12);
      expect(calls.where((m) => m.method == 'mindPlaceCall'), hasLength(1));

      sock.push({
        'type': 'response.output_item.done',
        'item': {'type': 'function_call', 'name': 'end_conversation', 'call_id': 'c2', 'arguments': '{}'},
      });
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(c.active, isFalse, reason: 'ลาแล้วและเสียงลาจบ = ปิดไมค์');
      expect(s.handsFree, isFalse);
      expect(sock.closed, isTrue);
      expect(calls.where((m) => m.method == 'liveAudioStop'), isNotEmpty);
    });
  });
}
