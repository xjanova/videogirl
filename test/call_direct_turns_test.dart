/// ทางผลัดกันพูด (เสียงที่ไม่ใช่คุยสด OpenAI) ต้องใช้สายตรงด้วย ไม่ใช่ลำโพงอย่างเดียว
///
/// ที่มา: เจ้าของ "เมื่อเราเลือก เสียงในการตอบรับการโทรที่ไม่ใช่ open ai จะไม่ได้ยินอะไรเลย" ·
/// รายงานสายจริง 0.1.60 (vivo V2144): `audioPath=speaker engine=- silenced=true heard=0` ทั้งที่
/// ตัวช่วยต่อสายตรงรันอยู่ · ของเดิมต่อสายตรงเฉพาะตอนคุยสด เครื่องที่ตั้งตัวช่วยไว้คือเครื่องที่ AEC
/// ลบเสียงลำโพงทิ้ง → ปลายสายไม่ได้ยินเธอ และไมค์ที่ถูกปิดเงียบทำให้เธอไม่ได้ยินปลายสาย
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/phone/call_session.dart';
import 'package:videogirl/phone/call_watch.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';

class _Speech extends SpeechService {
  final used = <VoiceProfile>[];
  @override
  Future<Utterance> synthesize(String text, {required VoiceProfile profile}) async {
    used.add(profile);
    return (bytes: Uint8List.fromList(List.filled(64, 7)), mime: 'audio/mpeg');
  }
}

const _eleven = VoiceProfile(
    engine: TtsEngine.elevenlabs, voice: 'AbCdEfGhIjKlMnOpQrSt', model: 'eleven_v4', instructions: '');

/// เสียงพูดดัง ๆ ของคู่สาย 16 บิต 16 kHz
Uint8List _loud({int samples = 1600, int amp = 12000}) {
  final pcm = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    pcm.setInt16(i * 2, (amp * math.sin(i / 3)).round(), Endian.little);
  }
  return pcm.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const direct = MethodChannel('giggok/direct_audio');
  const events = MethodChannel('giggok/direct_audio_events');
  const record = MethodChannel('com.llfbandit.record/messages');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 400 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(ready(), isTrue, reason: 'ไม่ถึงสถานะที่รอ');
  }

  /// ขึ้นสายที่เธอถือ · [startDirect] = ผลของช่อง `start` (โยน = ตัวช่วยไม่ได้ตั้ง/ไม่อยู่) ·
  /// [decoded] = PCM ที่ตัวถอดคืน (null = ถอดไม่ได้)
  Future<
      ({
        CallSession call,
        _Speech speech,
        Map<String, Object?> info,
        List<String> directCalls,
        List<String> system,
        List<Map<Object?, Object?>> decodes,
        List<Uint8List> written,
        List<String> mic,
      })> dial({FutureOr<String> Function()? startDirect, Uint8List? Function()? decoded}) async {
    final tmp = Directory.systemTemp.createTempSync('call_direct_turns');
    final info = <String, Object?>{'live': true, 'mind': true, 'speaker': true, 'number': '0812345678'};
    final directCalls = <String>[];
    final system = <String>[];
    final decodes = <Map<Object?, Object?>>[];
    final written = <Uint8List>[];
    final mic = <String>[];
    m.setMockMethodCallHandler(paths, (call) async => tmp.path);
    m.setMockMethodCallHandler(record, (call) async {
      mic.add(call.method);
      return null;
    });
    m.setMockMethodCallHandler(events, (call) async => null);
    m.setMockMethodCallHandler(direct, (call) async {
      directCalls.add(call.method);
      switch (call.method) {
        case 'start':
          return startDirect == null ? 'direct:C' : await startDirect();
        case 'write':
          written.add((call.arguments as Map)['pcm'] as Uint8List);
          return true;
        case 'pending':
          return 0;
        case 'takeover':
          return 'stopped:0';
      }
      return 'ok';
    });
    m.setMockMethodCallHandler(kSystemChannel, (call) async {
      system.add(call.method);
      switch (call.method) {
        case 'callInfo':
          return info;
        case 'decodePcm':
          decodes.add(call.arguments as Map<Object?, Object?>);
          return decoded == null ? Uint8List(4800) : decoded();
        case 'mindHandOver':
          info['mind'] = false;
          return true;
        case 'callDisconnect':
          info['live'] = false;
          return true;
      }
      return true;
    });

    final speech = _Speech();
    final s = MindState(speech: speech);
    await s.load();
    s
      ..setRecordCalls(false)
      ..setVoice(VoiceChannel.answer, _eleven);
    final watch = CallWatch();
    final call = CallSession(watch: watch, state: s);
    addTearDown(() async {
      await call.hangUp();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      call.dispose();
      watch.dispose();
      s.dispose();
      // ทางลำโพงเปิดปลั๊กอินไมค์ · ปิดแบบไม่รอ ต้องให้จบก่อนถอดช่องจำลองออก
      await Future<void>.delayed(const Duration(milliseconds: 100));
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
    return (
      call: call,
      speech: speech,
      info: info,
      directCalls: directCalls,
      system: system,
      decodes: decodes,
      written: written,
      mic: mic,
    );
  }

  test('🔴 เสียงรับสาย ElevenLabs เข้าสายตรง ไม่ออกลำโพง (เครื่องที่ AEC ลบเสียงลำโพง)', () async {
    final d = await dial();
    await until(() => d.written.isNotEmpty);
    expect(d.speech.used.first.engine, TtsEngine.elevenlabs, reason: 'เสียงที่เจ้าของเลือก ไม่ถูกแทนด้วย OpenAI');
    expect(d.decodes.single['path'], endsWith('.mp3'), reason: 'mp3 ต้องถอดก่อน · สายตรงรับแต่ PCM');
    expect(d.decodes.single['rate'], 24000);
    expect(d.written.single.length, 4800);
    expect(d.system, isNot(contains('callSpeak')), reason: 'เล่นสองทาง = ก้อง · ทางลำโพงไม่มีใครได้ยินอยู่แล้ว');
    expect(d.call.directMode, isTrue);
    expect(d.call.mute, isFalse);
  });

  test('🔴 ฟังคู่สายจากสายตรง ไม่เปิดไมค์ (ไมค์ถูกปิดเงียบระหว่างสาย)', () async {
    final d = await dial();
    await until(() => d.call.turn == CallTurn.listening);
    const codec = StandardMethodCodec();
    await m.handlePlatformMessage(
        events.name,
        codec.encodeSuccessEnvelope({'source': 'down', 'timeUs': 0, 'rate': 16000, 'pcm': _loud()}),
        (_) {});
    await until(() => d.call.micLevel > .2);
    expect(d.mic, isEmpty, reason: 'ไมค์ที่ถูกปิดเงียบส่งศูนย์มาแทรกกลางประโยคของคู่สาย');
    expect(d.call.error, isNot(const S(AppLang.th).callNeedsA11y));
  });

  test('ตัวช่วยไม่ได้ตั้ง = ทางลำโพงเหมือนเดิม ไม่ถอดไฟล์ ไม่เตือน', () async {
    final d = await dial(
        startDirect: () => throw PlatformException(code: 'direct_unavailable', message: 'not_configured'));
    await until(() => d.system.contains('callSpeak'));
    expect(d.decodes, isEmpty);
    expect(d.written, isEmpty);
    expect(d.call.directMode, isFalse);
    expect(d.call.mute, isFalse);
  });

  test('ไม่มีช่องต่อสายตรงเลย (ไม่ใช่ Android) = ไม่ได้ตั้ง ไม่ใช่ตัวช่วยหลุด', () async {
    final d = await dial(startDirect: () => throw MissingPluginException());
    await until(() => d.system.contains('callSpeak'));
    expect(d.call.mute, isFalse, reason: 'เตือนว่าปลายสายไม่ได้ยินทั้งที่ทางลำโพงใช้ได้ = เตือนผิด');
  });

  test('ถอดไฟล์เสียงไม่ได้ = เตือนว่าปลายสายไม่ได้ยิน ไม่เงียบเฉย ๆ', () async {
    final d = await dial(decoded: () => null);
    await until(() => d.call.mute);
    expect(d.written, isEmpty);
    expect(d.system, isNot(contains('callSpeak')));
  });

  test('🔴 ส่งสายคืนหลังเจ้าของแทรก = เริ่มสายตรงใหม่ เสียงเธอไม่ถูกทิ้งเงียบ ๆ', () async {
    final d = await dial();
    await until(() => d.written.isNotEmpty);
    await d.call.bargeIn();
    expect(d.directCalls, contains('takeover'));
    final before = d.directCalls.length;

    d.info['mind'] = true; // เจ้าของส่งสายคืนจากจอสาย
    await until(() => d.written.length == 2);
    final after = d.directCalls.sublist(before);
    expect(after.indexOf('stop'), lessThan(after.indexOf('start')),
        reason: 'ตัวช่วยหลัง takeover ไม่เล่นเข้าสายแล้ว · ต้องปิดแล้วเริ่มใหม่');
  });
}
