/// คุยสดในสายผ่าน OpenAI Realtime
///
/// ที่มา: เจ้าของ — "มันควรฟังแล้วโต้ตอบได้เหมือนแอป ChatGPT โต้ตอบสดๆ" · "ต้องทำ
/// real time พูดคุยเลย ถ้าตั้งค่าเป็น open ai"
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/phone/realtime_call.dart';
import 'package:videogirl/state/mind_state.dart';

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
    await _in.close();
  }

  void push(Map<String, Object?> event) => _in.add(jsonEncode(event));
}

Uint8List _pcm(List<int> samples) {
  final b = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(i * 2, samples[i], Endian.little);
  }
  return b.buffer.asUint8List();
}

List<int> _samples(Uint8List b) {
  final d = ByteData.sublistView(b);
  return [for (var i = 0; i < b.length ~/ 2; i++) d.getInt16(i * 2, Endian.little)];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('แปลงเสียงไมค์ 16 kHz → 24 kHz', () {
    test('ยาวขึ้นครึ่งหนึ่ง และเสียงคงที่ยังคงที่', () {
      final out = _samples(Resampler16to24().convert(_pcm(List.filled(1600, 1000))));
      expect(out.length, closeTo(2400, 2));
      expect(out.every((s) => s == 1000), isTrue);
    });

    test('🔴 หั่นเป็นก้อนแล้วได้เท่ากับทั้งก้อน · รอยต่อไม่แตก', () {
      final src = [for (var i = 0; i < 4000; i++) (8000 * (i % 50 < 25 ? 1 : -1) * (i % 7) / 7).round()];
      final whole = _samples(Resampler16to24().convert(_pcm(src)));
      final r = Resampler16to24();
      final pieces = <int>[];
      var at = 0;
      for (final n in [320, 17, 960, 1, 640, 2062]) {
        pieces.addAll(_samples(r.convert(_pcm(src.sublist(at, at + n)))));
        at += n;
      }
      expect(pieces.length, whole.length);
      for (var i = 0; i < whole.length; i++) {
        expect((pieces[i] - whole[i]).abs(), lessThanOrEqualTo(1), reason: 'ตัวอย่างที่ $i');
      }
    });
  });

  group('คุยกับ OpenAI Realtime', () {
    late _FakeSocket socket;
    late RealtimeCall rt;
    Uri? url;
    Map<String, String>? headers;

    setUp(() async {
      socket = _FakeSocket();
      rt = RealtimeCall(
        apiKey: 'sk-test',
        instructions: 'คุณคือผู้ช่วยรับสาย',
        greeting: 'สวัสดีค่ะ มายด์รับสายแทนค่ะ',
        voice: 'shimmer',
        connect: (u, h) async {
          url = u;
          headers = h;
          return socket;
        },
      );
      await rt.start();
    });

    tearDown(() => rt.close());

    test('ต่อด้วยคีย์ของเจ้าของ · ตั้งเสียง 24 kHz · ถอดเสียงภาษาไทย · แล้วทักด้วยประโยคที่กำหนด', () {
      expect(url!.scheme, 'wss');
      expect(url!.queryParameters['model'], RealtimeCall.defaultModel);
      expect(headers!['Authorization'], 'Bearer sk-test');
      final session = socket.sent.first;
      expect(session['type'], 'session.update');
      final s = session['session'] as Map;
      expect(s['instructions'], 'คุณคือผู้ช่วยรับสาย');
      final audio = s['audio'] as Map;
      expect(((audio['input'] as Map)['format'] as Map)['rate'], 24000);
      expect(((audio['input'] as Map)['transcription'] as Map)['language'], 'th');
      expect(((audio['output'] as Map)['voice']), 'shimmer');
      final greet = socket.sent[1];
      expect(greet['type'], 'response.create');
      expect('${(greet['response'] as Map)['instructions']}', contains('สวัสดีค่ะ มายด์รับสายแทนค่ะ'));
    });

    test('เสียงเธอ · บทของเธอ · บทของคู่สาย · ข้อผิดพลาด ไปถึงผู้เรียกครบ', () async {
      final audio = <Uint8List>[];
      final her = <String>[];
      final caller = <String>[];
      final errors = <String>[];
      var started = 0, done = 0;
      rt
        ..onAudio = audio.add
        ..onHerText = her.add
        ..onCallerText = caller.add
        ..onError = errors.add
        ..onResponseStart = (() => started++)
        ..onResponseDone = (() => done++);

      socket
        ..push({'type': 'response.created'})
        ..push({'type': 'response.output_audio.delta', 'delta': base64Encode([1, 2, 3, 4])})
        ..push({'type': 'response.output_audio_transcript.delta', 'delta': 'สวัส'})
        ..push({'type': 'response.output_audio_transcript.done', 'transcript': 'สวัสดีค่ะ'})
        ..push({'type': 'response.done'})
        ..push({'type': 'conversation.item.input_audio_transcription.completed', 'transcript': 'ขอสายคุณต้นครับ'})
        ..push({'type': 'error', 'error': {'code': 'x', 'message': 'บางอย่างผิด'}});
      await Future<void>.delayed(Duration.zero);

      expect(started, 1);
      expect(done, 1);
      expect(audio.single, [1, 2, 3, 4]);
      expect(her, ['สวัสดีค่ะ']);
      expect(caller, ['ขอสายคุณต้นครับ']);
      expect(errors.single, contains('บางอย่างผิด'));
    });

    test('ไมค์ถูกแปลงเป็น 24 kHz ก่อนส่ง', () {
      rt.sendMic(_pcm(List.filled(320, 500)));
      final append = socket.sent.last;
      expect(append['type'], 'input_audio_buffer.append');
      expect(base64Decode('${append['audio']}').length, closeTo(960, 4));
    });

    test('เจ้าของพิมพ์ให้พูด = เธอพูดตรงตามนั้นผ่านเซสชันเดียวกัน', () {
      rt.say('คุณต้นจะโทรกลับภายในบ่ายนี้ค่ะ');
      final e = socket.sent.last;
      expect(e['type'], 'response.create');
      expect('${(e['response'] as Map)['instructions']}', contains('คุณต้นจะโทรกลับภายในบ่ายนี้ค่ะ'));
    });

    test('เสียงที่ Realtime ไม่รู้จัก = ใช้ marin', () async {
      final s2 = _FakeSocket();
      final r2 = RealtimeCall(
          apiKey: 'k', instructions: 'i', greeting: 'g', voice: 'nova', connect: (_, _) async => s2);
      await r2.start();
      expect((((s2.sent.first['session'] as Map)['audio'] as Map)['output'] as Map)['voice'], 'marin');
      await r2.close();
    });
  });

  group('ใช้คุยสดเมื่อไหร่', () {
    test('เฉพาะสมอง OpenAI ด้วยคีย์ของเจ้าของ และไม่ได้ปิดสวิตช์', () async {
      final s = MindState();
      addTearDown(s.dispose);
      await s.load();
      expect(s.realtimeCallsReady, isFalse, reason: 'ค่าตั้งต้นไม่ใช่ OpenAI');
      s.setBrain(BrainProvider.openai);
      await s.setOpenAiKey('sk-test-key-for-unit-tests');
      expect(s.realtimeCallsReady, isTrue);
      s.setRealtimeCalls(false);
      expect(s.realtimeCallsReady, isFalse);
      s
        ..setRealtimeCalls(true)
        ..setBrain(BrainProvider.mindProxy);
      expect(s.realtimeCallsReady, isFalse, reason: 'ไม่ยืมคีย์ข้ามสมอง');
    });

    test('🔴 เซสชันคุยสดใช้ prompt ของสาย (ไม่มีข้อมูลส่วนตัว) และคำทักที่บอกเรื่องบันทึกเสียง', () async {
      final s = MindState();
      addTearDown(s.dispose);
      await s.load();
      s.setBrain(BrainProvider.openai);
      await s.setOpenAiKey('sk-test-key-for-unit-tests');
      s.setOwnerProfile('บ้านเลขที่ 99/12 ซอยลับ');
      final rt = s.openRealtimeCall();
      expect(rt.instructions, s.callPrompt());
      expect(rt.instructions, isNot(contains('99/12')));
      expect(rt.greeting, s.callGreeting());
      expect(rt.apiKey, 'sk-test-key-for-unit-tests');
    });
  });
}
