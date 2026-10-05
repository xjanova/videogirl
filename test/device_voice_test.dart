/// เสียงฟรีของเครื่อง (Android TTS) ต้องไม่ "เงียบโดยบอกว่าสำเร็จ"
///
/// ที่มา: เจ้าของเจอ "ไม่มีเสียงเฉยเลย" กับเสียงของเครื่อง · เครื่องที่ยังไม่มี
/// เสียงภาษาไทยคืนไฟล์ WAV ที่มีแต่หัวไฟล์ (ไม่มีเสียงพูดเลย) แล้วทุกทางเล่นได้
/// "สำเร็จ" · ไม่มีอะไรบอกเจ้าของเลยว่าต้องไปโหลดเสียงภาษาไทย
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_ai.dart';

/// WAV 16 บิต ช่องเดียว · [seconds] ของคลื่นจริง (0 = มีแต่หัวไฟล์)
Uint8List wav(double seconds, {int rate = 16000, bool listChunk = false, bool streaming = false}) {
  final samples = (rate * seconds).round();
  final data = BytesBuilder();
  for (var i = 0; i < samples; i++) {
    final v = (8000 * ((i % 40) < 20 ? 1 : -1));
    data.add([v & 0xff, (v >> 8) & 0xff]);
  }
  final body = data.toBytes();
  final list = listChunk ? [...'LIST'.codeUnits, 4, 0, 0, 0, ...'INFO'.codeUnits] : <int>[];
  final h = ByteData(44);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + list.length + body.length, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, 1, Endian.little);
  h.setUint32(24, rate, Endian.little);
  h.setUint32(28, rate * 2, Endian.little);
  h.setUint16(32, 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, streaming ? 0 : body.length, Endian.little);
  final head = h.buffer.asUint8List();
  // LIST อยู่ก่อน data · ย้าย data header ไปต่อท้าย LIST
  return Uint8List.fromList([...head.sublist(0, 36), ...list, ...head.sublist(36), ...body]);
}

class _FakeTts extends FlutterTts {
  _FakeTts(this.out, {this.hasVoice = true});

  final Uint8List out;
  final bool hasVoice;

  @override
  Future<dynamic> setLanguage(String language) async => 1;
  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;
  @override
  Future<dynamic> setPitch(double pitch) async => 1;
  @override
  Future<dynamic> awaitSynthCompletion(bool awaitCompletion) async => 1;
  @override
  Future<dynamic> isLanguageAvailable(String language) async => hasVoice;
  @override
  Future<dynamic> synthesizeToFile(String text, String fileName, [bool isFullPath = false]) async {
    File(fileName).writeAsBytesSync(out);
    return 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  const pathCh = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('device_voice');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathCh, (_) async => tmp.path);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathCh, null);
    try {
      tmp.deleteSync(recursive: true);
    } on Object {
      // temp ค้างไม่ใช่เหตุให้เทสต์แดง
    }
  });

  group('อ่านความยาวเสียงจากหัว WAV', () {
    test('หนึ่งวินาทีได้หนึ่งวินาที', () {
      expect(SpeechService.wavSeconds(wav(1)), closeTo(1, 0.001));
    });
    test('มีแต่หัวไฟล์ = ศูนย์วินาที', () {
      expect(SpeechService.wavSeconds(wav(0)), 0);
    });
    test('มี chunk LIST แทรกก่อน data ก็ยังอ่านถูก', () {
      expect(SpeechService.wavSeconds(wav(0.5, listChunk: true)), closeTo(0.5, 0.001));
    });
    test('ขนาด data เป็นศูนย์ (เขียนแบบสตรีม) ใช้ขนาดจริงของไฟล์', () {
      expect(SpeechService.wavSeconds(wav(0.5, streaming: true)), closeTo(0.5, 0.001));
    });
    test('ไม่ใช่ WAV = ไม่ตัดสิน', () {
      expect(SpeechService.wavSeconds(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13])), isNull);
    });
  });

  const s = S(AppLang.th);
  const device = VoiceProfile(
      engine: TtsEngine.device, voice: '', model: '', instructions: '');

  test('🔴 เครื่องไม่มีเสียงไทย = บอกให้ไปโหลดเสียง ไม่ใช่เล่นไฟล์เงียบแล้วบอกว่าสำเร็จ', () async {
    final svc = SpeechService(deviceTts: _FakeTts(wav(0), hasVoice: false), strings: () => s);
    await expectLater(
      svc.synthesize('สวัสดีค่ะ', profile: device),
      throwsA(isA<OpenAiFailure>().having((e) => e.message, 'message', s.errTtsNoVoice)),
    );
  });

  test('มีเสียงไทยแต่ยังได้ไฟล์เงียบ = บอกว่าเสียงเครื่องไม่ได้อ่านอะไรออกมา', () async {
    final svc = SpeechService(deviceTts: _FakeTts(wav(0)), strings: () => s);
    await expectLater(
      svc.synthesize('สวัสดีค่ะ', profile: device),
      throwsA(isA<OpenAiFailure>().having((e) => e.message, 'message', s.errTtsEmpty)),
    );
  });

  test('เสียงปกติผ่านไปเล่นได้', () async {
    final svc = SpeechService(deviceTts: _FakeTts(wav(1.2)), strings: () => s);
    final u = await svc.synthesize('สวัสดีค่ะ', profile: device);
    expect(u.mime, 'audio/wav');
    expect(SpeechService.wavSeconds(u.bytes), closeTo(1.2, 0.001));
  });
}
