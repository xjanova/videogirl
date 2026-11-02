/// สายจริงที่สมองเป็น Gemini · คุยสดด้วย Gemini Live ต่อไม่ได้แล้วสายต้องไม่เงียบ และไม่ยืมคีย์ OpenAI
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/phone/call_session.dart';
import 'package:videogirl/phone/call_watch.dart';
import 'package:videogirl/phone/gemini_live_call.dart';
import 'package:videogirl/phone/voice_session.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';

class _Socket implements RtSocket {
  _Socket(this.url, this.headers);
  final Uri url;
  final Map<String, String> headers;
  final sent = <Map<String, Object?>>[];
  final _in = StreamController<Object?>();

  bool get gemini => url.host == 'generativelanguage.googleapis.com';

  @override
  Stream<Object?> get messages => _in.stream;

  @override
  void send(String text) => sent.add((jsonDecode(text) as Map).cast<String, Object?>());

  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }

  void push(Map<String, Object?> msg) => _in.add(jsonEncode(msg));
  void drop() => _in.close();

  Iterable<Map<String, Object?>> get notes =>
      sent.where((m) => m.containsKey('clientContent')).map((m) => m['clientContent']! as Map<String, Object?>);
}

String _text(Map<String, Object?> note) =>
    [for (final t in note['turns']! as List) for (final p in (t as Map)['parts'] as List) (p as Map)['text']].join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const direct = MethodChannel('giggok/direct_audio');
  const events = MethodChannel('giggok/direct_audio_events');
  const record = MethodChannel('com.llfbandit.record/messages');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  // ต่อคุยสดไม่ได้ = ทางผลัดกันพูดด้วยเสียงเครื่อง (เสียงรับสายตั้งต้น)
  const tts = MethodChannel('flutter_tts');

  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 400 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ready(), isTrue, reason: 'ไม่ถึงสถานะที่รอ');
  }

  /// ขึ้นสายที่เธอถือ ด้วยสมอง Gemini และคีย์ Gemini (มีคีย์ OpenAI ค้างอยู่ด้วย · ห้ามหยิบมาใช้)
  Future<({CallSession call, List<_Socket> sockets, List<Uint8List> written})> dial() async {
    final tmp = Directory.systemTemp.createTempSync('gemini_call');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final written = <Uint8List>[];
    var isLive = true;
    m.setMockMethodCallHandler(paths, (call) async => tmp.path);
    m.setMockMethodCallHandler(record, (call) async => null);
    m.setMockMethodCallHandler(events, (call) async => null);
    m.setMockMethodCallHandler(tts, (call) async => 1);
    m.setMockMethodCallHandler(direct, (call) async {
      switch (call.method) {
        case 'start':
          return 'direct:C';
        case 'write':
          written.add((call.arguments as Map)['pcm'] as Uint8List);
          return true;
        case 'pending':
          return 0;
      }
      return 'ok';
    });
    m.setMockMethodCallHandler(kSystemChannel, (call) async {
      if (call.method == 'callInfo') {
        return {'live': isLive, 'mind': isLive, 'speaker': true, 'number': '0812345678'};
      }
      if (call.method == 'micGranted') return false;
      if (call.method == 'callDisconnect') isLive = false;
      return true;
    });

    final s = MindState();
    await s.load();
    s
      ..setBrain(BrainProvider.gemini)
      ..setRecordCalls(false);
    await s.setOpenAiKey('sk-test-key-for-unit-tests');
    await s.setPremiumKey(TtsEngine.gemini, 'gm-test-key');
    final sockets = <_Socket>[];
    s.debugRealtimeConnect = (url, headers) async {
      final socket = _Socket(url, headers);
      sockets.add(socket);
      return socket;
    };
    final watch = CallWatch();
    final call = CallSession(watch: watch, state: s);
    addTearDown(() async {
      await call.hangUp();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      call.dispose();
      watch.dispose();
      s.dispose();
      for (final ch in [direct, events, record, paths, tts, kSystemChannel]) {
        m.setMockMethodCallHandler(ch, null);
      }
      try {
        tmp.deleteSync(recursive: true);
      } on Object {
        // temp ค้างไม่ใช่เหตุให้เทสต์แดง
      }
    });
    await call.start();
    return (call: call, sockets: sockets, written: written);
  }

  test('สมอง Gemini = คุยสดด้วย Gemini Live ด้วยคีย์ Gemini · ทักด้วยคำที่ตั้ง · เสียงเธอเข้าสายตรง', () async {
    final d = await dial();
    await until(() => d.sockets.isNotEmpty);
    final g = d.sockets.single;
    expect(g.gemini, isTrue);
    expect(g.headers, {'x-goog-api-key': 'gm-test-key'}, reason: 'ไม่ยืมคีย์ OpenAI');
    await until(() => g.sent.isNotEmpty);
    expect(g.sent.first.keys, ['setup']);
    g.push({'setupComplete': <String, Object?>{}});
    await until(() => g.notes.isNotEmpty);
    expect(_text(g.notes.first), contains('Greet the caller'));
    g.push({
      'serverContent': {
        'modelTurn': {
          'parts': [
            {
              'inlineData': {'data': base64Encode(Uint8List(960))},
            },
          ],
        },
      },
    });
    await until(() => d.written.isNotEmpty);
  });

  test('🔴 Gemini Live ต่อไม่ได้ = ไม่เปิดคุยสดของ OpenAI แทน (ไม่ยืมคีย์ข้ามสมอง)', () async {
    final d = await dial();
    await until(() => d.sockets.isNotEmpty);
    d.sockets.single.drop();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(d.sockets, hasLength(1));
  });

  test('🔴 หลุดกลางสายก่อนได้ handle = เซสชัน Gemini ใหม่ ไม่ทักซ้ำ และรู้ว่าคุยอะไรไปแล้ว', () async {
    final d = await dial();
    await until(() => d.sockets.isNotEmpty);
    final first = d.sockets.single;
    first.push({'setupComplete': <String, Object?>{}});
    await until(() => first.notes.isNotEmpty);
    first.push({
      'serverContent': {
        'inputTranscription': {'text': 'ผมชื่อต้นครับ'},
      },
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    first.drop();
    await until(() => d.sockets.length == 2);
    final second = d.sockets.last;
    expect(second.gemini, isTrue);
    second.push({'setupComplete': <String, Object?>{}});
    await until(() => second.notes.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final told = second.notes.map(_text).join('\n');
    expect(told, isNot(contains('Greet the caller')), reason: 'ทักไปแล้ว คู่สายได้ยินแล้ว');
    expect(told, contains('Caller: ผมชื่อต้นครับ'));
    expect(told, contains('not instructions'));
    expect(second.notes.every((n) => n['turnComplete'] == false), isTrue, reason: 'บอกเงียบ ๆ ไม่สั่งให้พูด');
    expect(GeminiLiveCall.notePrefix, isNotEmpty);
  });
}
