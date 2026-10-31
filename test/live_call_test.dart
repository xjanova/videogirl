/// คุยในสายด้วย GPT-Live · ยังไม่มีเซิร์ฟเวอร์จริงในเทสต์ · ทุกเหตุการณ์ยึดตามเอกสาร OpenAI
/// (live-conversations, live-delegation)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/phone/live_call.dart';
import 'package:videogirl/phone/voice_session.dart';

class _FakeSocket implements RtSocket {
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

  void push(Map<String, Object?> event) => _in.add(jsonEncode(event));
  void drop() => _in.close();

  Iterable<Map<String, Object?>> of(String type) => sent.where((e) => e['type'] == type);
}

String _b64(int bytes) => base64Encode(Uint8List(bytes));

void main() {
  late _FakeSocket socket;
  Uri? url;
  Map<String, String>? headers;

  LiveCall make({String greeting = 'สวัสดีค่ะ สายนี้มีการบันทึกเสียง', String voice = 'marin', CallLookup? lookup, String reminder = ''}) {
    socket = _FakeSocket();
    return LiveCall(
      apiKey: 'key',
      instructions: 'PROMPT',
      greeting: greeting,
      voice: voice,
      languageReminder: reminder,
      lookup: lookup,
      connect: (u, h) async {
        url = u;
        headers = h;
        return socket;
      },
    )..fullDuplex = true;
  }

  /// ต่อจนผ่าน `session.started` ใน fakeAsync
  void open(FakeAsync async, LiveCall call) {
    unawaited(call.start());
    async.flushMicrotasks();
    socket.push({'type': 'session.started', 'session': {'id': 's1'}});
    async.flushMicrotasks();
  }

  group('ตั้งเซสชัน', () {
    test('ต่อปลายทางของ GPT-Live ไม่มี query และส่งเครื่องมือไปหลังบ้าน', () {
      fakeAsync((async) {
        final call = make(voice: 'ballad', lookup: (_) async => const []);
        open(async, call);
        expect(url.toString(), 'wss://api.openai.com/v1/live/sessions');
        expect(headers, {'Authorization': 'Bearer key'});
        final session = socket.of('session.start').single['session']! as Map;
        expect(session['model'], 'gpt-live-1');
        expect(session['store'], isFalse, reason: 'เสียงคู่สายไม่ค้างที่ OpenAI');
        expect(session['instructions'], startsWith('PROMPT'));
        expect(session['audio'], {
          'format': {'type': 'audio/pcm', 'rate': 24000},
          // ballad มีใน Realtime แต่ GPT-Live ไม่รู้จัก
          'output': {'voice': 'marin'},
        });
        final responses = ((session['delegation'] as Map)['responses'] as Map);
        expect((session['delegation'] as Map)['type'], 'responses');
        expect(responses['model'], 'gpt-6-luna');
        expect([for (final t in responses['tools'] as List) t['name']], ['end_call', 'alert_owner', 'lookup_info']);
      });
    });

    test('ไม่มีคลังให้ค้น = ไม่มีเครื่องมือค้น', () {
      fakeAsync((async) {
        final call = make();
        open(async, call);
        final session = socket.of('session.start').single['session']! as Map;
        final tools = ((session['delegation'] as Map)['responses'] as Map)['tools'] as List;
        expect([for (final t in tools) t['name']], ['end_call', 'alert_owner']);
      });
    });

    test('เซิร์ฟเวอร์ปฏิเสธก่อนเริ่ม = โยนให้ผู้เรียกตกไป Realtime', () {
      fakeAsync((async) {
        final call = make();
        Object? failed;
        unawaited(call.start().catchError((Object e) => failed = e));
        async.flushMicrotasks();
        socket.push({'type': 'error', 'error': {'type': 'invalid_request_error', 'code': 'model_not_found', 'message': 'no'}});
        async.flushMicrotasks();
        expect(failed, isNotNull);
        expect(socket.of('session.instructions.append'), isEmpty);
      });
    });

    test('ไม่ตอบใน 4 วิ = โยน · ปิดแล้วไม่รอลาเซิร์ฟเวอร์ คู่สายรออยู่', () {
      fakeAsync((async) {
        final call = make();
        Object? failed;
        unawaited(call.start().catchError((Object e) => failed = e));
        async.elapse(const Duration(seconds: 3));
        expect(failed, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(failed, isA<TimeoutException>());
        unawaited(call.close());
        async.flushMicrotasks();
        expect(socket.of('session.close'), isEmpty);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('ท่อหลุดก่อนเริ่ม = โยน', () {
      fakeAsync((async) {
        final call = make();
        Object? failed;
        unawaited(call.start().catchError((Object e) => failed = e));
        async.flushMicrotasks();
        socket.drop();
        async.flushMicrotasks();
        expect(failed, isNotNull);
      });
    });
  });

  group('ทัก', () {
    test('พูดคำทักตรงตามตัว · delegation_id เป็น null · ไม่มีเสียงใน 3 วิ = สั่งซ้ำครั้งเดียว', () {
      fakeAsync((async) {
        final call = make();
        open(async, call);
        final first = socket.of('session.instructions.append').single;
        expect(first['content'], contains('สวัสดีค่ะ สายนี้มีการบันทึกเสียง'));
        expect(first['content'], contains('exactly and in full'));
        expect(first.containsKey('delegation_id'), isTrue);
        expect(first['delegation_id'], isNull);
        async.elapse(const Duration(seconds: 10));
        expect(socket.of('session.instructions.append'), hasLength(2));
      });
    });

    test('เธอเริ่มพูดแล้วไม่สั่งซ้ำ (สั่งซ้ำ = ตัดประโยคตัวเอง)', () {
      fakeAsync((async) {
        final call = make();
        open(async, call);
        socket.push({'type': 'session.output_audio.delta', 'delta': _b64(480)});
        async.elapse(const Duration(seconds: 5));
        expect(socket.of('session.instructions.append'), hasLength(1));
      });
    });

    test('โทรออก (ไม่มีคำทัก) = รอปลายสาย', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        open(async, call);
        async.elapse(const Duration(seconds: 5));
        expect(socket.of('session.instructions.append'), isEmpty);
      });
    });
  });

  group('จังหวะพูด', () {
    test('เสียงชิ้นแรกคือเริ่มตอบ · หยุดมา 400 มิลลิวิ = จบ · ไม่กระพริบระหว่างประโยค', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        var starts = 0, ends = 0, bytes = 0;
        call.onResponseStart = () => starts++;
        call.onResponseDone = () => ends++;
        call.onAudio = (pcm) => bytes += pcm.length;
        open(async, call);
        for (var i = 0; i < 5; i++) {
          socket.push({'type': 'session.output_audio.delta', 'delta': _b64(480)});
          async.elapse(const Duration(milliseconds: 300));
        }
        expect((starts, ends, bytes), (1, 0, 2400));
        async.elapse(const Duration(milliseconds: 200));
        expect((starts, ends), (1, 1));
        socket.push({'type': 'session.output_audio.delta', 'delta': _b64(480)});
        async.flushMicrotasks();
        expect(starts, 2);
      });
    });

    test('ชิ้นเสียงเสียข้ามไป ไม่ล้มทั้งสาย', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        var audio = 0;
        call.onAudio = (_) => audio++;
        open(async, call);
        socket.push({'type': 'session.output_audio.delta', 'delta': '***'});
        socket.push({'type': 'session.output_audio.delta', 'delta': _b64(2)});
        async.flushMicrotasks();
        expect(audio, 1);
      });
    });
  });

  group('บท', () {
    test('ไม่มีขอบประโยค · เงียบ 900 มิลลิวิถึงลงบท', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        final her = <String>[];
        call.onHerText = her.add;
        open(async, call);
        for (final d in ['สวัส', 'ดี', 'ค่ะ']) {
          socket.push({'type': 'session.output_transcript.delta', 'delta': d, 'start_ms': 0, 'end_ms': 10});
          async.elapse(const Duration(milliseconds: 300));
        }
        expect(her, isEmpty);
        async.elapse(const Duration(seconds: 1));
        expect(her, ['สวัสดีค่ะ']);
      });
    });

    test('อีกฝั่งเริ่มพูด = ปิดประโยคที่ค้าง บทเรียงตามจริง', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        final lines = <String>[];
        call
          ..onHerText = ((t) => lines.add('her:$t'))
          ..onCallerText = ((t) => lines.add('them:$t'));
        open(async, call);
        socket.push({'type': 'session.output_transcript.delta', 'delta': 'ค่ะ'});
        socket.push({'type': 'session.input_transcript.delta', 'delta': 'ครับ'});
        socket.push({'type': 'session.output_transcript.delta', 'delta': 'รับทราบ'});
        async.elapse(const Duration(seconds: 2));
        expect(lines, ['her:ค่ะ', 'them:ครับ', 'her:รับทราบ']);
      });
    });

    test('flush ปล่อยบทที่ค้างทันที · ปล่อยซ้ำไม่ลงซ้ำ', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        final caller = <String>[];
        call.onCallerText = caller.add;
        open(async, call);
        socket.push({'type': 'session.input_transcript.delta', 'delta': 'ฝากบอกด้วย'});
        async.flushMicrotasks();
        call.flush();
        call.flush();
        async.elapse(const Duration(seconds: 2));
        expect(caller, ['ฝากบอกด้วย']);
      });
    });
  });

  group('คู่สายแทรก', () {
    test('เสียงเธอหยุดแล้วคู่สายพูด = ล้างคิวครั้งเดียว', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        var flushed = 0;
        call.onInterruption = () async {
          flushed++;
          return 0;
        };
        open(async, call);
        socket.push({'type': 'session.output_audio.delta', 'delta': _b64(480)});
        async.elapse(const Duration(milliseconds: 250));
        socket.push({'type': 'session.input_transcript.delta', 'delta': 'เดี๋ยว'});
        socket.push({'type': 'session.input_transcript.delta', 'delta': 'ก่อน'});
        async.flushMicrotasks();
        expect(flushed, 1);
      });
    });

    test('เสียงเธอยังมาอยู่ = คำรับคำ ไม่ใช่แทรก', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        var flushed = 0;
        call.onInterruption = () async {
          flushed++;
          return 0;
        };
        open(async, call);
        socket.push({'type': 'session.output_audio.delta', 'delta': _b64(480)});
        async.elapse(const Duration(milliseconds: 50));
        socket.push({'type': 'session.input_transcript.delta', 'delta': 'อืม'});
        async.flushMicrotasks();
        expect(flushed, 0);
      });
    });
  });

  group('เครื่องมือ (ซ้อนใน response.event)', () {
    void tool(String name, String callId, [String arguments = '{}']) => socket.push({
          'type': 'response.event',
          'delegation_id': 'd1',
          'event': {
            'type': 'response.output_item.done',
            'item': {'type': 'function_call', 'call_id': callId, 'name': name, 'arguments': arguments},
          },
        });
    void backend(String type) => socket.push({'type': 'response.event', 'delegation_id': 'd1', 'event': {'type': type}});

    test('แจ้งเจ้าของครั้งเดียว · ส่งผลกลับ แล้วรอคำตอบเดิมจบก่อนสั่งต่อ', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        final alerts = <String>[];
        call.onAlertOwner = alerts.add;
        open(async, call);
        backend('response.created');
        tool('alert_owner', 'c1', '{"reason":"ด่วน"}');
        tool('alert_owner', 'c2', '{"reason":"ด่วนอีก"}');
        async.flushMicrotasks();
        expect(alerts, ['ด่วน']);
        expect(socket.of('response.item.create'), hasLength(2));
        final item = socket.of('response.item.create').first['item']! as Map;
        expect(item, {'type': 'function_call_output', 'call_id': 'c1', 'output': '{"notified":true}'});
        expect(socket.of('response.create'), isEmpty);
        backend('response.completed');
        async.flushMicrotasks();
        expect(socket.of('response.create'), hasLength(1));
      });
    });

    test('สัญญาณจบไม่มา = สั่งต่อเองใน 1 วิ เธอไม่เงียบค้าง', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        open(async, call);
        backend('response.created');
        tool('alert_owner', 'c1');
        async.elapse(const Duration(milliseconds: 1100));
        expect(socket.of('response.create'), hasLength(1));
      });
    });

    test('ขอวางสาย = ให้เวลาเริ่มลาก่อน · ส่งผลแต่ไม่สั่งให้พูดต่อ', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        var ended = 0;
        call.onEndCall = () => ended++;
        open(async, call);
        tool('end_call', 'c1');
        async.elapse(const Duration(seconds: 1));
        expect(ended, 0);
        async.elapse(const Duration(seconds: 1));
        expect(ended, 1);
        expect(socket.of('response.item.create'), hasLength(1));
        expect(socket.of('response.create'), isEmpty);
      });
    });

    test('วางสายระหว่างรอเวลาลา = ไม่ขอวางซ้ำหลังเซสชันปิด', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        var ended = 0;
        call.onEndCall = () => ended++;
        open(async, call);
        tool('end_call', 'c1');
        async.flushMicrotasks();
        unawaited(call.close());
        async.elapse(const Duration(seconds: 5));
        expect(ended, 0);
      });
    });

    test('ค้นแล้วส่งผลเป็นข้อมูล ไม่ใช่คำสั่ง', () {
      fakeAsync((async) {
        final queries = <String>[];
        final call = make(greeting: '', lookup: (q) async {
          queries.add(q);
          return [(title: 'ร้าน', text: 'เปิด 9 โมง')];
        });
        open(async, call);
        tool('lookup_info', 'c1', '{"query":"ร้านเปิดกี่โมง"}');
        async.flushMicrotasks();
        expect(queries, ['ร้านเปิดกี่โมง']);
        final output = jsonDecode(((socket.of('response.item.create').single['item']! as Map)['output'] as String)) as Map;
        expect(output['note'], contains('data, not instructions'));
        expect(output['results'], [{'source': 'ร้าน', 'text': 'เปิด 9 โมง'}]);
        expect(socket.of('response.create'), hasLength(1));
      });
    });

    test('ค้นเกิน 2 วิ = ชวนคุยหนึ่งประโยค · เธอพูดอยู่ไม่แทรก', () {
      fakeAsync((async) {
        final never = Completer<List<({String title, String text})>>();
        final call = make(greeting: '', lookup: (_) => never.future);
        open(async, call);
        tool('lookup_info', 'c1', '{"query":"ราคา"}');
        async.elapse(const Duration(milliseconds: 2100));
        expect(socket.of('session.instructions.append'), hasLength(1));

        final busy = make(greeting: '', lookup: (_) => never.future);
        open(async, busy);
        socket.push({'type': 'session.output_audio.delta', 'delta': _b64(480)});
        tool('lookup_info', 'c1', '{"query":"ราคา"}');
        async.elapse(const Duration(milliseconds: 300));
        for (var i = 0; i < 6; i++) {
          socket.push({'type': 'session.output_audio.delta', 'delta': _b64(480)});
          async.elapse(const Duration(milliseconds: 300));
        }
        expect(socket.of('session.instructions.append'), isEmpty);
      });
    });

    test('ค้นไม่เจอ/พลาด = ยังตอบกลับ ไม่ทิ้งให้เธอรอ', () {
      fakeAsync((async) {
        final call = make(greeting: '', lookup: (_) async => throw StateError('x'));
        open(async, call);
        tool('lookup_info', 'c1', 'ไม่ใช่ json');
        tool('lookup_info', 'c2', '{"query":"อะไร"}');
        async.flushMicrotasks();
        expect(socket.of('response.item.create'), hasLength(2));
      });
    });
  });

  group('คำสั่งระหว่างสาย', () {
    test('เตือนเงียบ ๆ ไม่ทำให้พูด · พูดตามเจ้าของพิมพ์สั่งให้พูดทันที', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        open(async, call);
        call.remind('ใกล้หมดเวลา');
        call.say('รอสักครู่นะคะ');
        expect(socket.of('session.thinking.append').single['content'], 'ใกล้หมดเวลา');
        expect(socket.of('session.instructions.append').single['content'], contains('รอสักครู่นะคะ'));
      });
    });

    test('ข้อความยาวถูกตัดไม่ให้เกินเพดาน 500 โทเคน', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        open(async, call);
        call.say('ก' * 5000);
        expect((socket.of('session.instructions.append').single['content']! as String).length, 900);
      });
    });

    test('ปลายสายเพิ่งพูด หรือเธอพูดอยู่ = ไม่สะกิด', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        open(async, call);
        socket.push({'type': 'session.input_transcript.delta', 'delta': 'ฮัล'});
        async.flushMicrotasks();
        call.nudge('ทักเลย');
        expect(socket.of('session.instructions.append'), isEmpty);
        async.elapse(const Duration(seconds: 2));
        call.nudge('ทักเลย');
        expect(socket.of('session.instructions.append'), hasLength(1));
      });
    });

    test('ไมค์ 16 kHz ขึ้นเป็น 24 kHz ก่อนส่ง', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        open(async, call);
        call.sendMic(Uint8List(320));
        final audio = base64Decode(socket.of('session.input_audio.append').single['audio']! as String);
        expect(audio.length, closeTo(480, 4));
      });
    });

    test('คู่สายพูดไทยแต่เธอหลุดอังกฤษ = เตือนเงียบ ๆ ตาถัดไป', () {
      fakeAsync((async) {
        final call = make(greeting: '', reminder: 'ตอบไทย');
        open(async, call);
        socket.push({'type': 'session.input_transcript.delta', 'delta': 'ครับ'});
        async.elapse(const Duration(seconds: 1));
        socket.push({'type': 'session.output_transcript.delta', 'delta': 'Hello, how can I help you?'});
        async.elapse(const Duration(seconds: 1));
        expect(socket.of('session.thinking.append').single['content'], 'ตอบไทย');
        expect(call.languageReminders, 1);
      });
    });
  });

  group('จบเซสชัน', () {
    // ใช้เวลาจริง · ยกเลิก subscription คืน Future ของ root zone ซึ่ง fakeAsync ไม่เดินให้
    Future<LiveCall> opened() async {
      final call = make(greeting: '');
      unawaited(call.start());
      await pumpEventQueue();
      socket.push({'type': 'session.started'});
      await pumpEventQueue();
      return call;
    }

    test('ลาเซิร์ฟเวอร์ · รอ session.closed · ปล่อยบทที่ค้าง · ปิดซ้ำได้', () async {
      final call = await opened();
      final her = <String>[];
      call.onHerText = her.add;
      socket.push({'type': 'session.output_transcript.delta', 'delta': 'ลาก่อนค่ะ'});
      await pumpEventQueue();
      var closed = false;
      final closing = call.close().then((_) => closed = true);
      await pumpEventQueue();
      expect(her, ['ลาก่อนค่ะ']);
      expect(socket.of('session.close'), hasLength(1));
      expect(closed, isFalse);
      expect(call.connected, isFalse);
      socket.push({'type': 'session.closed', 'reason': 'close_requested', 'usage': {'seconds': 42}});
      await closing;
      expect(socket.closed, isTrue);
      await call.close();
      expect(socket.of('session.close'), hasLength(1));
    });

    test('เซิร์ฟเวอร์ไม่ตอบตอนลา = ปิดเองใน 2 วิ', () async {
      final call = await opened();
      final clock = Stopwatch()..start();
      await call.close();
      expect(clock.elapsed, lessThan(const Duration(seconds: 3)));
      expect(socket.closed, isTrue);
    });

    test('ปิดแล้วไม่มีนาฬิกาค้าง · ทั้งที่กำลังพูด ถือบท และรอวางสาย', () {
      fakeAsync((async) {
        final call = make(greeting: 'สวัสดีค่ะ');
        open(async, call);
        socket.push({'type': 'session.output_audio.delta', 'delta': _b64(480)});
        socket.push({'type': 'session.output_transcript.delta', 'delta': 'ลา'});
        socket.push({'type': 'session.input_transcript.delta', 'delta': 'ครับ'});
        socket.push({
          'type': 'response.event',
          'event': {
            'type': 'response.output_item.done',
            'item': {'type': 'function_call', 'call_id': 'c1', 'name': 'end_call'},
          },
        });
        async.flushMicrotasks();
        expect(async.pendingTimers, isNotEmpty);
        unawaited(call.close());
        socket.push({'type': 'session.closed', 'reason': 'close_requested'});
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('เซิร์ฟเวอร์ปิดเองกลางสาย = บอกผู้เรียก ท่อถือว่าหลุด', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        final errors = <String>[];
        call.onError = errors.add;
        open(async, call);
        socket.push({'type': 'session.closed', 'reason': 'expired'});
        async.flushMicrotasks();
        expect(errors, ['session_closed_expired']);
        expect(call.connected, isFalse);
      });
    });

    test('ท่อหลุดกลางสาย = บอกผู้เรียกครั้งเดียว', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        final errors = <String>[];
        call.onError = errors.add;
        open(async, call);
        socket.drop();
        async.flushMicrotasks();
        expect(errors, hasLength(1));
        expect(call.connected, isFalse);
      });
    });

    test('หลังบ้านใช้ไม่ได้ = เธอวางสาย/ค้นไม่ได้ ต้องสลับไป Realtime', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        final errors = <String>[];
        call.onError = errors.add;
        open(async, call);
        socket.push({'type': 'error', 'error': {'code': 'responses_validation_failed', 'message': 'bad model'}});
        async.flushMicrotasks();
        expect(call.connected, isFalse);
        expect(errors.single, startsWith('responses_validation_failed:'));
      });
    });

    test('ตัวกรองเนื้อหาตัดประโยคเดียว = เซสชันยังอยู่', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        final errors = <String>[];
        call.onError = errors.add;
        open(async, call);
        socket.push({'type': 'error', 'error': {'type': 'invalid_request_error', 'code': 'moderation_blocked'}});
        async.flushMicrotasks();
        expect(call.connected, isTrue);
        expect(errors, hasLength(1));
      });
    });

    test('หลังปิดแล้วเงียบสนิท ไม่ส่งอะไรออกไปอีก', () {
      fakeAsync((async) {
        final call = make(greeting: '');
        open(async, call);
        socket.push({'type': 'session.closed', 'reason': 'remote_hangup'});
        async.flushMicrotasks();
        final before = socket.sent.length;
        call
          ..say('x')
          ..remind('x')
          ..nudge('x')
          ..sendMic(Uint8List(320));
        expect(socket.sent.length, before);
      });
    });
  });
}
