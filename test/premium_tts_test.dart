/// เสียงพรีเมียม (Gemini · ElevenLabs · Azure) — คำขอที่ส่งออกไปต้องตรงสเปก
/// ที่ตรวจกับเอกสารทางการเมื่อ 2026-10-06 และข้อผิดพลาดต้องเป็นภาษาคน
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/ai/premium_catalog.dart';
import 'package:videogirl/ai/premium_tts.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_voice.dart';

const s = S(AppLang.th);

VoiceProfile _p(TtsEngine e, {String voice = '', String model = '', String style = ''}) =>
    VoiceProfile(engine: e, voice: voice, model: model, instructions: style);

void main() {
  late http.Request? sent;

  PremiumTts tts(http.Response Function(http.Request) answer,
      {Map<TtsEngine, String>? keys, String region = 'southeastasia'}) {
    sent = null;
    return PremiumTts(
      httpClient: MockClient((req) async {
        sent = req;
        return answer(req);
      }),
      keyOf: (e) => (keys ?? const {
            TtsEngine.gemini: 'g-key',
            TtsEngine.elevenlabs: 'e-key',
            TtsEngine.azure: 'a-key',
          })[e] ??
          '',
      azureRegion: () => region,
      strings: () => s,
    );
  }

  http.Response audio(List<int> bytes) => http.Response.bytes(bytes, 200);

  group('Gemini', () {
    http.Response geminiJson(List<int> audio, {String mime = 'audio/L16;codec=pcm;rate=24000'}) =>
        http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {
                        'inlineData': {'mimeType': mime, 'data': base64Encode(audio)}
                      }
                    ]
                  }
                }
              ]
            }),
            200);

    test('คำขอ: รุ่น 3.8 · คีย์ใน header · คำสั่งน้ำเสียงอยู่ช่องแยก ไม่ปนในข้อความ', () async {
      final c = tts((_) => geminiJson([1, 0, 2, 0]));
      await c.speak(TtsEngine.gemini, 'สวัสดีค่ะ',
          _p(TtsEngine.gemini, voice: 'Sulafat', model: 'gemini-3.8-flash-tts', style: 'อบอุ่น'),
          thai: true);
      final r = sent!;
      expect(r.url.toString(),
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash-tts:generateContent');
      expect(r.headers['x-goog-api-key'], 'g-key');
      expect(r.url.queryParameters, isEmpty, reason: 'คีย์ห้ามอยู่ใน URL — ไปโผล่ใน log ของ proxy ได้');
      final b = jsonDecode(r.body) as Map;
      final part = (((b['contents'] as List).first as Map)['parts'] as List).first as Map;
      expect(part['text'], 'สวัสดีค่ะ');
      expect(part['speech_metadata'], {'style': 'อบอุ่น'});
      expect(b['generationConfig']['responseModalities'], ['AUDIO']);
      expect(b['generationConfig']['speechConfig']['voiceConfig']['prebuiltVoiceConfig']['voiceName'],
          'Sulafat');
    });

    test('ได้ PCM ดิบ = ห่อหัว WAV ตาม rate ที่บอกมา', () async {
      final c = tts((_) => geminiJson(List.filled(48000, 0), mime: 'audio/L16;codec=pcm;rate=24000'));
      final u = await c.speak(TtsEngine.gemini, 'ทดสอบ', _p(TtsEngine.gemini), thai: true);
      expect(u.mime, 'audio/wav');
      expect(SpeechService.wavSeconds(u.bytes), closeTo(1.0, 0.001));
    });

    test('ได้ WAV ที่มีหัวแล้ว (รุ่นใหม่) = ใช้ตามนั้น ไม่ห่อซ้ำ', () async {
      final wav = PremiumTts.pcmToWav(Uint8List.fromList(List.filled(24000, 0)), 24000);
      final c = tts((_) => geminiJson(wav, mime: 'audio/wav'));
      final u = await c.speak(TtsEngine.gemini, 'ทดสอบ', _p(TtsEngine.gemini), thai: true);
      expect(u.bytes, wav);
    });
  });

  group('ElevenLabs', () {
    test('v4 ไปทาง text-to-dialogue · บอกภาษาไทย · ส่งรุ่นทุกครั้ง', () async {
      final c = tts((_) => audio([0xff, 0xfb]));
      final u = await c.speak(TtsEngine.elevenlabs, 'สวัสดี',
          _p(TtsEngine.elevenlabs, voice: 'AbCdEfGhIjKlMnOpQrSt', model: 'eleven_v4'),
          thai: true);
      expect(u.mime, 'audio/mpeg');
      final r = sent!;
      expect(r.url.path, '/v1/text-to-dialogue');
      expect(r.url.queryParameters['output_format'], 'mp3_44100_128');
      expect(r.headers['xi-api-key'], 'e-key');
      final b = jsonDecode(r.body) as Map;
      expect(b['model_id'], 'eleven_v4');
      expect(b['language_code'], 'th');
      expect(b['inputs'], [
        {'text': 'สวัสดี', 'voice_id': 'AbCdEfGhIjKlMnOpQrSt'}
      ]);
    });

    test('v3 ไปทาง text-to-speech ของเสียงนั้น', () async {
      final c = tts((_) => audio([1]));
      await c.speak(TtsEngine.elevenlabs, 'hi',
          _p(TtsEngine.elevenlabs, voice: 'AbCdEfGhIjKlMnOpQrSt', model: 'eleven_v3'),
          thai: false);
      expect(sent!.url.path, '/v1/text-to-speech/AbCdEfGhIjKlMnOpQrSt');
      final b = jsonDecode(sent!.body) as Map;
      expect(b['model_id'], 'eleven_v3', reason: 'ไม่ส่ง = multilingual_v2 ที่ไม่มีภาษาไทย');
      expect(b['language_code'], 'en');
    });

    test('ยังไม่ได้เลือกเสียง = บอกให้ไปโหลดเสียง ไม่ยิงออกไปเปล่า ๆ', () async {
      final c = tts((_) => audio([1]));
      await expectLater(
        c.speak(TtsEngine.elevenlabs, 'x', _p(TtsEngine.elevenlabs), thai: true),
        throwsA(isA<OpenAiFailure>().having((e) => e.message, 'm', s.elevenPickVoice)),
      );
      expect(sent, isNull);
    });

    test('รายชื่อเสียงในบัญชี: ชื่อ + เพศ/สำเนียง', () async {
      final c = tts((_) => http.Response(
          jsonEncode({
            'voices': [
              {
                'voice_id': 'AbCdEfGhIjKlMnOpQrSt',
                'name': 'Mali',
                'labels': {'gender': 'female', 'accent': 'thai'},
                'category': 'professional'
              }
            ]
          }),
          200));
      final list = await c.elevenVoices();
      expect(list.single.id, 'AbCdEfGhIjKlMnOpQrSt');
      expect(list.single.name, 'Mali');
      expect(list.single.detail, 'female · thai · professional');
      expect(sent!.url.toString(), 'https://api.elevenlabs.io/v2/voices?page_size=100');
    });
  });

  group('Azure', () {
    test('ปลายทางตามภูมิภาค · SSML ภาษาไทย · mp3', () async {
      final c = tts((_) => audio([1, 2]));
      await c.speak(TtsEngine.azure, 'สวัสดี',
          _p(TtsEngine.azure, voice: 'th-TH-PremwadeeNeural'), thai: true);
      final r = sent!;
      expect(r.url.toString(),
          'https://southeastasia.tts.speech.microsoft.com/cognitiveservices/v1');
      expect(r.headers['Ocp-Apim-Subscription-Key'], 'a-key');
      expect(r.headers['X-Microsoft-OutputFormat'], 'audio-24khz-96kbitrate-mono-mp3');
      expect(r.body, contains('xml:lang="th-TH"'));
      expect(r.body, contains('<voice name="th-TH-PremwadeeNeural">สวัสดี</voice>'));
    });

    test('🔴 ข้อความมี & < > ต้องไม่ทำ SSML พัง', () {
      final x = PremiumTts.azureSsml('A&B <ราคา> "ok"', 'th-TH-AcharaNeural', thai: true);
      expect(x, contains('A&amp;B &lt;ราคา&gt; &quot;ok&quot;'));
      expect(x, isNot(contains('<ราคา>')));
    });

    test('เสียงหลายภาษาพูดไทย = ห่อ <lang> ให้ชัด', () {
      final x = PremiumTts.azureSsml('สวัสดี', 'en-US-AvaMultilingualNeural', thai: true);
      expect(x, contains('<lang xml:lang="th-TH">สวัสดี</lang>'));
    });

    test('ยังไม่ใส่ภูมิภาค = บอกตรง ๆ', () async {
      final c = tts((_) => audio([1]), region: '');
      await expectLater(
        c.speak(TtsEngine.azure, 'x', _p(TtsEngine.azure), thai: true),
        throwsA(isA<OpenAiFailure>().having((e) => e.message, 'm', s.azureNeedsRegion)),
      );
    });
  });

  group('ข้อผิดพลาดเป็นภาษาคน', () {
    test('ไม่มีคีย์ = บอกว่าต้องใส่คีย์เจ้าไหน', () async {
      final c = tts((_) => audio([1]), keys: const {});
      await expectLater(
        c.speak(TtsEngine.gemini, 'x', _p(TtsEngine.gemini), thai: true),
        throwsA(isA<OpenAiFailure>().having((e) => e.message, 'm', s.premiumKeyNeeded('Gemini'))),
      );
    });

    test('401 = คีย์ใช้ไม่ได้ · 429 = โควตา/เครดิต', () async {
      final bad = tts((_) => http.Response('{"detail":"invalid"}', 401));
      await expectLater(
        bad.speak(TtsEngine.azure, 'x', _p(TtsEngine.azure), thai: true),
        throwsA(isA<OpenAiFailure>().having((e) => e.message, 'm', s.premiumBadKey('Azure'))),
      );
      final quota = tts((_) => http.Response('{}', 429));
      await expectLater(
        quota.speak(TtsEngine.elevenlabs, 'x',
            _p(TtsEngine.elevenlabs, voice: 'AbCdEfGhIjKlMnOpQrSt'), thai: true),
        throwsA(isA<OpenAiFailure>().having((e) => e.message, 'm', s.premiumQuota('ElevenLabs'))),
      );
    });
  });

  group('สลับเจ้าเสียง', () {
    const openai = VoiceProfile(
        engine: TtsEngine.openai, voice: 'coral', model: 'gpt-4o-mini-tts', instructions: 'อบอุ่น');

    test('🔴 OpenAI → Gemini ได้รุ่นและเสียงของ Gemini ไม่ใช่ coral', () {
      final g = PremiumCatalog.adapt(openai, TtsEngine.gemini, thai: true);
      expect(g.model, 'gemini-3.8-flash-tts');
      expect(g.voice, PremiumCatalog.geminiDefaultVoice);
      expect(g.instructions, 'อบอุ่น', reason: 'คำสั่งน้ำเสียงใช้ต่อได้กับ Gemini');
    });

    test('→ ElevenLabs เสียงว่าง (ต้องเลือกจากบัญชี) · → Azure ได้เสียงไทย', () {
      expect(PremiumCatalog.adapt(openai, TtsEngine.elevenlabs, thai: true).voice, '');
      expect(PremiumCatalog.adapt(openai, TtsEngine.azure, thai: true).voice,
          'th-TH-PremwadeeNeural');
    });

    test('กลับมา OpenAI ได้ค่าของ OpenAI คืน', () {
      final g = PremiumCatalog.adapt(openai, TtsEngine.gemini, thai: true);
      final back = PremiumCatalog.adapt(g, TtsEngine.openai, thai: true);
      expect(back.model, 'gpt-4o-mini-tts');
      expect(back.voice, 'coral');
    });

    test('รายการรุ่นมีแต่ตัวที่พูดไทยได้ (คุณภาพสูง)', () {
      expect(PremiumCatalog.geminiModels, isNot(contains(contains('lite'))));
      expect(PremiumCatalog.elevenModels, isNot(contains('eleven_multilingual_v2')));
      expect(PremiumCatalog.elevenModels, isNot(contains('eleven_flash_v2_5')));
    });
  });
}
