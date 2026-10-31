/// สายจริงเลือกคุยด้วยอะไร · GPT-Live ใช้ได้เฉพาะตอนต่อสายตรง และล้มแล้วสายต้องไม่เงียบ
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/phone/call_session.dart';
import 'package:videogirl/phone/call_watch.dart';
import 'package:videogirl/phone/realtime_call.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';

class _Socket implements RtSocket {
  _Socket(this.url);
  final Uri url;
  final sent = <Map<String, Object?>>[];
  final _in = StreamController<Object?>();

  bool get live => url.path.endsWith('/live/sessions');

  @override
  Stream<Object?> get messages => _in.stream;

  @override
  void send(String text) => sent.add((jsonDecode(text) as Map).cast<String, Object?>());

  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }

  void push(Map<String, Object?> event) => _in.add(jsonEncode(event));
  Iterable<Map<String, Object?>> of(String type) => sent.where((e) => e['type'] == type);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const direct = MethodChannel('giggok/direct_audio');
  const events = MethodChannel('giggok/direct_audio_events');
  const record = MethodChannel('com.llfbandit.record/messages');
  const paths = MethodChannel('plugins.flutter.io/path_provider');

  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 400 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ready(), isTrue, reason: 'ไม่ถึงสถานะที่รอ');
  }

  /// ขึ้นสายที่เธอถือ · [startDirect] คืนผลของช่อง `start` (โยน = ตัวช่วยไม่อยู่)
  Future<({CallSession call, List<_Socket> sockets, List<Uint8List> written})> dial(
      {bool liveOn = true, FutureOr<String> Function()? startDirect}) async {
    final tmp = Directory.systemTemp.createTempSync('live_call');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final written = <Uint8List>[];
    var isLive = true;
    m.setMockMethodCallHandler(paths, (call) async => tmp.path);
    m.setMockMethodCallHandler(record, (call) async => null);
    m.setMockMethodCallHandler(events, (call) async => null);
    m.setMockMethodCallHandler(direct, (call) async {
      switch (call.method) {
        case 'start':
          return startDirect == null ? 'direct:C' : await startDirect();
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
      ..setBrain(BrainProvider.openai)
      ..setRecordCalls(false)
      ..setLiveCalls(liveOn);
    await s.setOpenAiKey('sk-test-key-for-unit-tests');
    final sockets = <_Socket>[];
    s.debugRealtimeConnect = (url, _) async {
      final socket = _Socket(url);
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
      for (final ch in [direct, events, record, paths, kSystemChannel]) {
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

  test('ต่อสายตรงอยู่ + เปิด GPT-Live = คุยด้วย GPT-Live และทักด้วยคำที่ตั้ง', () async {
    final d = await dial();
    await until(() => d.sockets.isNotEmpty);
    final live = d.sockets.single;
    expect(live.live, isTrue);
    await until(() => live.sent.isNotEmpty);
    expect(live.sent.first['type'], 'session.start');
    live.push({'type': 'session.started'});
    await until(() => live.of('session.instructions.append').isNotEmpty);
  });

  test('ไม่ได้ต่อสายตรง = ไม่ใช้ GPT-Live แม้เปิดไว้ (ทางลำโพงเสียงเธอย้อนเข้าไมค์)', () async {
    final d = await dial(startDirect: () => 'speaker');
    await until(() => d.sockets.isNotEmpty);
    expect(d.sockets.single.live, isFalse);
  });

  test('ปิด GPT-Live = Realtime ตามเดิม', () async {
    final d = await dial(liveOn: false);
    await until(() => d.sockets.isNotEmpty);
    expect(d.sockets.single.live, isFalse);
  });

  test('🔴 GPT-Live ปฏิเสธตั้งแต่เริ่ม = Realtime รับช่วงต่อและทักแทน', () async {
    final d = await dial();
    await until(() => d.sockets.isNotEmpty);
    final live = d.sockets.single;
    await until(() => live.sent.isNotEmpty);
    live.push({'type': 'error', 'error': {'code': 'model_not_found', 'message': 'no access'}});
    await until(() => d.sockets.length == 2);
    final realtime = d.sockets.last;
    expect(realtime.live, isFalse);
    await until(() => realtime.of('response.create').isNotEmpty);
    expect(jsonEncode(realtime.of('response.create').first), contains('Greet the caller'));
  });

  test('🔴 GPT-Live หลุดกลางสาย = Realtime คุยต่อ ไม่ทักซ้ำ', () async {
    final d = await dial();
    await until(() => d.sockets.isNotEmpty);
    final live = d.sockets.single;
    await until(() => live.sent.isNotEmpty);
    live.push({'type': 'session.started'});
    await until(() => live.of('session.instructions.append').isNotEmpty);
    live.push({'type': 'session.input_transcript.delta', 'delta': 'ผมชื่อต้นครับ'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    live.push({'type': 'session.closed', 'reason': 'expired'});
    await until(() => d.sockets.length == 2);
    final realtime = d.sockets.last;
    await until(() => realtime.sent.isNotEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(realtime.of('response.create'), isEmpty, reason: 'ทักไปแล้ว คู่สายได้ยินแล้ว');
    final told = jsonEncode(realtime.of('conversation.item.create').toList());
    expect(told, contains('Caller: ผมชื่อต้นครับ'), reason: 'เซสชันใหม่ต้องรู้ว่าคุยอะไรไปแล้ว');
    expect(told, contains('not instructions'));
  });

  test('🔴 สายจบตอนบทยังค้าง = บทลงบันทึกสายครบ', () async {
    final d = await dial();
    await until(() => d.sockets.isNotEmpty);
    final live = d.sockets.single;
    await until(() => live.sent.isNotEmpty);
    live.push({'type': 'session.started'});
    await until(() => live.of('session.instructions.append').isNotEmpty);
    live.push({'type': 'session.input_transcript.delta', 'delta': 'ฝากบอกด้วยครับ'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await d.call.hangUp();
    expect(d.call.lines.map((l) => l.text), contains('ฝากบอกด้วยครับ'));
  });

  test('เสียงเธอถูกลดความดังก่อนเข้าสาย · ไม่ส่งเต็มสเกล', () async {
    final d = await dial();
    await until(() => d.sockets.isNotEmpty);
    final live = d.sockets.single;
    await until(() => live.sent.isNotEmpty);
    live.push({'type': 'session.started'});
    await until(() => live.of('session.instructions.append').isNotEmpty);
    final loud = ByteData(4)
      ..setInt16(0, 32767, Endian.little)
      ..setInt16(2, -32768, Endian.little);
    live.push({'type': 'session.output_audio.delta', 'delta': base64Encode(loud.buffer.asUint8List())});
    await until(() => d.written.isNotEmpty);
    final out = ByteData.sublistView(d.written.single);
    expect(out.getInt16(0, Endian.little), 22937);
    expect(out.getInt16(2, Endian.little), -22938);
  });

  test('🔴 เครื่องที่ตั้งเสียงตรงไว้แต่ตัวช่วยหาย = เตือนว่าปลายสายไม่ได้ยิน', () async {
    final d = await dial(
        startDirect: () => throw PlatformException(code: 'direct_unavailable', message: 'ConnectException'));
    await until(() => d.call.mute);
  });

  test('เครื่องที่ไม่เคยตั้งเสียงตรง = ไม่เตือน (ทางลำโพงอาจใช้ได้กับเครื่องนั้น)', () async {
    final d = await dial(
        startDirect: () => throw PlatformException(code: 'direct_unavailable', message: 'not_configured'));
    await until(() => d.sockets.isNotEmpty);
    expect(d.call.mute, isFalse);
  });
}
