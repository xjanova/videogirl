/// ElevenLabs รุ่นครึ่งราคาที่พูดไทยได้
///
/// เจ้าของ (2026-11-04): "eleven lab มันมีอย่างครึ่งราคาด้วยนี่เพิ่มให้หน่อย" · v4 Turbo กับ v3 Conversational
/// ราคา 0.04 ดอลลาร์ต่อพันตัวอักษร (ครึ่งของ v4 / v3) แต่เรียกได้ทาง WebSocket ของ text-to-dialogue เท่านั้น
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videogirl/ai/eleven_tuning.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/ai/premium_catalog.dart';
import 'package:videogirl/ai/premium_tts.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_ai.dart';
import 'package:videogirl/i18n/strings_voice.dart';
import 'package:videogirl/phone/voice_session.dart';

/// ท่อปลอม · [reply] ตอบกลับทุกข้อความที่ส่งมา
class _Socket implements RtSocket {
  _Socket(this.reply);
  final List<Object?> Function(Map<String, Object?> sent) reply;
  final _in = StreamController<Object?>();
  final sent = <Map<String, Object?>>[];
  bool closed = false;

  @override
  Stream<Object?> get messages => _in.stream;

  @override
  void send(String text) {
    final m = (jsonDecode(text) as Map).cast<String, Object?>();
    sent.add(m);
    for (final r in reply(m)) {
      scheduleMicrotask(() => _in.add(r is String ? r : jsonEncode(r)));
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    await _in.close();
  }
}

void main() {
  const s = S(AppLang.th);
  const voice = 'AbCdEfGhIjKlMnOpQrSt';
  VoiceProfile p(String model, [ElevenTuning tune = const ElevenTuning()]) => VoiceProfile.openAiDefaults
      .copyWith(engine: TtsEngine.elevenlabs, model: model, voice: voice, instructions: '', eleven: tune);

  Uri? url;
  Map<String, String>? headers;
  PremiumTts tts(_Socket socket) => PremiumTts(
        httpClient: MockClient((_) async => throw StateError('ห้ามไปทาง HTTP')),
        keyOf: (_) => 'e-key',
        azureRegion: () => '',
        strings: () => s,
        timeout: const Duration(seconds: 2),
        connect: (u, h) async {
          url = u;
          headers = h;
          return socket;
        },
      );

  test('🔴 รุ่นครึ่งราคาที่พูดไทยได้อยู่ในรายการ · Flash v2.5 ยังไม่อยู่ (ไม่มีภาษาไทย)', () {
    expect(PremiumCatalog.elevenModels, containsAll(['eleven_v4_turbo', 'eleven_v3_conversational']));
    expect(PremiumCatalog.elevenModels.first, 'eleven_v4', reason: 'ค่าตั้งต้นยังเป็นรุ่นคุณภาพสูงสุด');
    expect(PremiumCatalog.elevenModels, isNot(contains('eleven_flash_v2_5')));
    expect(PremiumCatalog.elevenDialogueOnly('eleven_v4_turbo'), isTrue);
    expect(PremiumCatalog.elevenDialogueOnly('eleven_v3_conversational'), isTrue);
    expect(PremiumCatalog.elevenDialogueOnly('eleven_v3'), isFalse);
  });

  test('🔴 v4 Turbo ไปทาง WebSocket ของ text-to-dialogue · คีย์อยู่ที่ header · รวมเสียงทุกชิ้น', () async {
    final sock = _Socket((m) => m['close_socket'] == true
        ? [
            {'audio': base64Encode([1, 2])},
            {'audio': base64Encode([3])},
            {'is_final': true},
          ]
        : const []);
    final u = await tts(sock).speak(TtsEngine.elevenlabs, 'สวัสดีค่ะ', p('eleven_v4_turbo'), thai: true);
    expect(u.bytes, [1, 2, 3]);
    expect(u.mime, 'audio/mpeg');
    expect(url!.scheme, 'wss');
    expect(url!.host, 'api.elevenlabs.io');
    expect(url!.path, '/v1/text-to-dialogue/stream-input');
    expect(url!.queryParameters['model_id'], 'eleven_v4_turbo');
    expect(url!.queryParameters['language_code'], 'th');
    expect(url!.queryParameters['output_format'], 'mp3_44100_128');
    expect(url!.query, isNot(contains('e-key')), reason: 'คีย์ห้ามอยู่ในที่อยู่ · ลงล็อกได้');
    expect(headers, {'xi-api-key': 'e-key'});
    final first = sock.sent.first;
    expect(first['voices'], [voice]);
    expect(first['inputs'], [
      {'text': 'สวัสดีค่ะ', 'voice_id': voice}
    ]);
    expect((first['voice_settings'] as Map).keys, ['stability'], reason: 'ท่อนี้รับแค่ stability');
    expect(sock.sent.last, {'close_socket': true});
    expect(sock.closed, isTrue);
  });

  test('v3 Conversational ก็ไปทางเดียวกัน · ภาษาอังกฤษ = en', () async {
    final sock = _Socket((m) => m['close_socket'] == true
        ? [
            {'audio': base64Encode([9])},
            {'is_final': true},
          ]
        : const []);
    await tts(sock).speak(TtsEngine.elevenlabs, 'hi', p('eleven_v3_conversational'), thai: false);
    expect(url!.queryParameters['model_id'], 'eleven_v3_conversational');
    expect(url!.queryParameters['language_code'], 'en');
  });

  test('🔴 เซิร์ฟเวอร์ปฏิเสธ = OpenAiFailure ภาษาคน · ไม่ใช่ข้อความดิบของเซิร์ฟเวอร์', () async {
    final sock = _Socket((m) => [
          {'error': 'invalid_api_key', 'code': 'invalid_api_key', 'message': 'secret echo สวัสดี'}
        ]);
    await expectLater(
      tts(sock).speak(TtsEngine.elevenlabs, 'สวัสดี', p('eleven_v4_turbo'), thai: true),
      throwsA(isA<OpenAiFailure>().having((e) => e.message, 'm', s.premiumBadKey('ElevenLabs'))),
    );
    expect(sock.closed, isTrue);
  });

  test('🔴 ปิดท่อโดยไม่ให้เสียง = ล้มเป็นข้อความ ไม่ค้าง', () async {
    final sock = _Socket((m) => m['close_socket'] == true ? [<String, Object?>{'is_final': true}] : const []);
    await expectLater(
      tts(sock).speak(TtsEngine.elevenlabs, 'สวัสดี', p('eleven_v4_turbo'), thai: true),
      throwsA(isA<OpenAiFailure>().having((e) => e.message, 'm', s.premiumFailed('ElevenLabs'))),
    );
  });

  test('ต่อไม่ติด = ออฟไลน์ ตกไปเสียงเครื่องได้', () async {
    final c = PremiumTts(
      httpClient: MockClient((_) async => http.Response('', 500)),
      keyOf: (_) => 'e-key',
      azureRegion: () => '',
      strings: () => s,
      connect: (_, _) async => throw const FormatException('no network'),
    );
    await expectLater(
      c.speak(TtsEngine.elevenlabs, 'สวัสดี', p('eleven_v4_turbo'), thai: true),
      throwsA(isA<OpenAiFailure>().having((e) => e.message, 'm', s.errOffline)),
    );
  });

  test('ตั้งค่าแท็กอารมณ์ · normalize · seed ไปกับท่อนี้ด้วย', () {
    final r = PremiumTts.elevenSocketRequest(
        'ดีค่ะ', p('eleven_v4_turbo', const ElevenTuning(mood: 'warmly', normalize: 'on', seed: 7)), 'eleven_v4_turbo',
        thai: true);
    expect(r.url.queryParameters['apply_text_normalization'], 'on');
    expect(r.url.queryParameters['seed'], '7');
    final text = ((r.first['inputs'] as List).single as Map)['text'] as String;
    expect(text, contains('[warmly]'));
  });
}
