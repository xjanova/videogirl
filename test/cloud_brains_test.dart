import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/cloud_brains.dart';
import 'package:videogirl/ai/eleven_tuning.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/ai/premium_tts.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/i18n/strings.dart';

VoiceProfile _el(String model, [ElevenTuning tune = const ElevenTuning()]) => VoiceProfile(
      engine: TtsEngine.elevenlabs,
      voice: 'abcdefghijklmnopqrst',
      model: model,
      instructions: '',
      eleven: tune,
    );

void main() {
  group('รายการรุ่นสมอง', () {
    test('ทุกเจ้าคลาวด์มีรุ่น และรุ่นตั้งต้นอยู่ในรายการ', () {
      for (final b in BrainProvider.values.where((b) => b.isCloudKey)) {
        final ids = CloudBrains.modelsOf(b).map((m) => m.id);
        expect(ids, isNotEmpty, reason: b.name);
        expect(ids, contains(CloudBrains.defaultModel(b)), reason: b.name);
      }
    });

    test('ไม่มีรุ่นที่ประกาศเลิกหรือถูกแทนแล้วในรายการ', () {
      const retired = ['grok-4.5', 'grok-4.6', 'grok-4.20', 'gemini-3.5-flash', 'gemini-3.7-flash', 'gemini-3.6-flash'];
      for (final b in BrainProvider.values) {
        for (final m in CloudBrains.modelsOf(b)) {
          expect(retired.contains(m.id), isFalse, reason: m.id);
        }
      }
    });

    test('ทุกรุ่นมีราคาและคำอธิบายครบสองภาษา', () {
      for (final b in BrainProvider.values) {
        for (final m in CloudBrains.modelsOf(b)) {
          expect(m.inUsd, greaterThan(0), reason: m.id);
          expect(m.outUsd, greaterThan(0), reason: m.id);
          expect(m.hintOf(const S(AppLang.th)), isNotEmpty, reason: m.id);
          expect(m.hintOf(const S(AppLang.en)), isNot(matches(RegExp(r'[฀-๿]'))), reason: m.id);
        }
      }
    });

    test('effort: Grok 4.3 ปิดการคิด · Grok 4.7 ไม่ส่ง · Gemini minimal', () {
      expect(CloudBrains.effortFor(BrainProvider.grok, 'grok-4.3'), 'none');
      expect(CloudBrains.effortFor(BrainProvider.grok, 'grok-4.7'), isNull);
      expect(CloudBrains.effortFor(BrainProvider.gemini, 'gemini-3.8-flash'), 'minimal');
    });

    test('ตรวจหน้าตาคีย์', () {
      expect(CloudBrains.keyLooksRight(BrainProvider.grok, 'xai-123'), isTrue);
      expect(CloudBrains.keyLooksRight(BrainProvider.claude, 'sk-ant-1'), isTrue);
      expect(CloudBrains.keyLooksRight(BrainProvider.claude, 'sk-1'), isFalse);
      expect(CloudBrains.keyLooksRight(BrainProvider.gemini, 'AIza1'), isTrue);
    });
  });

  group('Claude', () {
    test('ข้อความแรกต้องเป็น user · ฝั่งเดียวกันติดกันรวมเป็นอันเดียว', () {
      final body = ClaudeClient.buildBody(
        system: 'sys',
        model: 'claude-sonnet-5-5',
        history: const [
          (fromHer: true, text: 'สวัสดีค่ะ'),
          (fromHer: false, text: 'a'),
          (fromHer: false, text: 'b'),
          (fromHer: true, text: 'c'),
          (fromHer: false, text: 'd'),
        ],
      );
      expect(body['system'], 'sys');
      final msgs = body['messages']! as List;
      expect(msgs.map((m) => (m as Map)['role']), ['user', 'assistant', 'user']);
      expect((msgs.first as Map)['content'], 'a\n\nb');
    });

    test('อ่านเฉพาะบล็อก text ไม่เอา thinking', () {
      final raw = jsonEncode({
        'content': [
          {'type': 'thinking', 'thinking': 'ลับ'},
          {'type': 'text', 'text': 'คำตอบ'},
        ]
      });
      expect(ClaudeClient.readText(raw), 'คำตอบ');
    });

    test('ยิง Messages API ด้วย x-api-key และ anthropic-version', () async {
      late http.Request seen;
      final c = ClaudeClient(
        apiKeyOf: () => 'sk-ant-x',
        httpClient: MockClient((r) async {
          seen = r;
          return http.Response(
              jsonEncode({
                'content': [
                  {'type': 'text', 'text': 'hi'}
                ]
              }),
              200);
        }),
      );
      final out = await c.reply(system: 's', history: const [(fromHer: false, text: 'q')]);
      expect(out, 'hi');
      expect(seen.url.toString(), CloudBrains.claudeUrl);
      expect(seen.headers['x-api-key'], 'sk-ant-x');
      expect(seen.headers['anthropic-version'], CloudBrains.claudeVersion);
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test('401 = บอกว่าคีย์ Claude ผิด ไม่ใช่ข้อความของ OpenAI', () async {
      final c = ClaudeClient(
        apiKeyOf: () => 'sk-ant-x',
        strings: () => const S(AppLang.en),
        httpClient: MockClient((_) async => http.Response('{}', 401)),
      );
      await expectLater(
        c.reply(system: 's', history: const [(fromHer: false, text: 'q')]),
        throwsA(isA<OpenAiFailure>().having((e) => e.message, 'message', contains('Claude'))),
      );
    });
  });

  group('ElevenLabs ปรับแต่ง', () {
    test('ค่าตั้งต้น = ไม่ส่งของเสริม · v4 ส่งแค่ stability/similarity', () {
      final b = PremiumTts.elevenBody('สวัสดี', _el('eleven_v4'), thai: true);
      expect(b['settings'], {'stability': 0.5, 'similarity': 0.75});
      expect(b.containsKey('audio_effects'), isFalse);
      expect(b.containsKey('voice_settings'), isFalse);
      expect(b.containsKey('seed'), isFalse);
      expect(((b['inputs']! as List).first as Map)['text'], 'สวัสดี');
    });

    test('v3 ส่ง voice_settings ครบ + แท็กอารมณ์ + เอฟเฟกต์ + seed', () {
      final b = PremiumTts.elevenBody(
        'hello',
        _el(
          'eleven_v3',
          const ElevenTuning(
            stability: 0.3,
            style: 0.4,
            speed: 1.1,
            speakerBoost: false,
            mood: 'warmly',
            filter: 'phone',
            distance: 0.25,
            normalize: 'on',
            seed: 42,
          ),
        ),
        thai: false,
      );
      expect(b['text'], '[warmly] hello');
      expect(b['voice_settings'], {
        'stability': 0.3,
        'similarity_boost': 0.75,
        'style': 0.4,
        'use_speaker_boost': false,
        'speed': 1.1,
      });
      expect(b['audio_effects'], {'filter_preset_id': 'phone', 'distance': 0.25});
      expect(b['apply_text_normalization'], 'on');
      expect(b['seed'], 42);
      expect(b['language_code'], 'en');
    });

    test('ข้อความที่มีแท็กเองอยู่แล้วไม่ใส่แท็กซ้ำ', () {
      expect(const ElevenTuning(mood: 'calm').tagged('[laughs] ok'), '[laughs] ok');
    });

    test('บันทึก/โหลดกลับได้ และค่าแปลก ๆ ถูกบีบให้อยู่ในช่วง', () {
      const t = ElevenTuning(stability: 0.2, mood: 'happy', environment: 'hall', seed: 7);
      expect(ElevenTuning.fromJson(jsonDecode(jsonEncode(t.toJson()))), t);
      final bad = ElevenTuning.fromJson({'speed': 9, 'normalize': 'x', 'stability': -1});
      expect(bad.speed, 1.2);
      expect(bad.normalize, 'auto');
      expect(bad.stability, 0);
    });

    test('โปรไฟล์เสียงเก่าที่ไม่มี eleven โหลดได้ด้วยค่าตั้งต้น', () {
      final fb = VoiceProfile.defaultFor(VoiceChannel.chat, AppLang.th);
      final p = VoiceProfile.fromJson({'engine': 'openai', 'voice': 'coral', 'model': 'm', 'instructions': ''}, fb);
      expect(p.eleven, const ElevenTuning());
      final round = VoiceProfile.fromJson(_el('eleven_v3', const ElevenTuning(style: .5)).toJson(), fb);
      expect(round.eleven.style, .5);
    });

    test('แคตตาล็อกเอฟเฟกต์อ่านตามสเปก', () {
      final fx = ElevenEffects.parse({
        'filter_presets': [
          {'filter_preset_id': 'phone', 'name': 'Phone', 'description': 'tinny'}
        ],
        'environments': [
          {'environment_id': 'hall', 'name': 'Hall'}
        ],
        'background_noises': <Object>[],
      });
      expect(fx.filters.single.id, 'phone');
      expect(fx.environments.single.name, 'Hall');
      expect(ElevenEffects.fromJson(fx.toJson()).filters.single.detail, 'tinny');
    });

    test('ข้อมูลบัญชี: บอกได้ว่าโคลนได้ไหม และเครดิตเหลือ', () {
      final a = ElevenAccount.parse({
        'tier': 'starter',
        'character_count': 1000,
        'character_limit': 30000,
        'can_use_instant_voice_cloning': true,
        'voice_limit': 10,
        'voice_slots_used': 2,
      });
      expect(a.canClone, isTrue);
      expect(a.left, 29000);
      expect(a.voiceLimit, 10);
    });
  });
}
