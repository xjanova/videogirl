/// รุ่นของ OpenAI ที่แอปเสนอ — ตรวจกับเอกสาร OpenAI เมื่อ 2026-10-06
///
/// ที่ต้องคุมด้วยเทสต์:
/// 1. ระดับการคิด (`reasoning_effort`) · ไม่ส่ง = รุ่น 5.6/6 คิดระดับ medium
///    ซึ่งกินเพดานคำตอบ 600 จนเธอตอบกลับมาว่างเปล่า · ส่งผิดค่า = 400
/// 2. ค่าที่ผู้ใช้เคยเลือกไว้ (tts-1, gpt-realtime) ต้องย้ายไปรุ่นที่ยังใช้ได้
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/ai/openai_config.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_ai.dart';

void main() {
  group('ระดับการคิดที่ขอ', () {
    test('5.x มีจุด และ 6 Luna = none (คุยเล่นไม่ต้องคิดลึก)', () {
      for (final id in ['gpt-5.6-sol', 'gpt-5.6-terra', 'gpt-5.6-luna', 'gpt-5.5', 'gpt-5.4-mini', 'gpt-6-luna']) {
        expect(OpenAiConfig.effortFor(id), 'none', reason: id);
      }
    });

    test('6 Astra / 6.1 Sol ไม่รับ none — ต่ำสุดคือ low', () {
      expect(OpenAiConfig.effortFor('gpt-6-astra'), 'low');
      expect(OpenAiConfig.effortFor('gpt-6.1-sol'), 'low');
    });

    test('gpt-5 รุ่นแรกไม่มี none — ใช้ minimal', () {
      expect(OpenAiConfig.effortFor('gpt-5'), 'minimal');
      expect(OpenAiConfig.effortFor('gpt-5-mini'), 'minimal');
      expect(OpenAiConfig.effortFor('gpt-5-nano-2025-08-07'), 'minimal');
    });

    test('รุ่นที่ไม่ใช่สาย reasoning = ไม่ส่ง (ส่งไปได้ 400)', () {
      for (final id in ['gpt-4o', 'gpt-4.1-mini', 'gpt-5-chat-latest', 'llama3.2']) {
        expect(OpenAiConfig.effortFor(id), isNull, reason: id);
      }
    });

    test('ทุกตัวในรายการมีคำอธิบายของมันเอง ไม่ตกไปคำว่า "พิมพ์เอง"', () {
      const s = S(AppLang.th);
      for (final m in OpenAiConfig.brainChoices) {
        expect(s.brainModelHint(m.id), isNot(s.modelTypedHint), reason: m.id);
      }
    });
  });

  group('คำขอที่ส่งออกไปจริง', () {
    Future<Map<String, dynamic>> sent(String baseUrl, String model) async {
      Map<String, dynamic>? body;
      final client = MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({
              'choices': [
                {'message': {'role': 'assistant', 'content': 'สวัสดีค่ะ'}}
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });
      final c = OpenAiClient(httpClient: client, baseUrl: baseUrl, apiKey: 'sk-test');
      await c.reply(system: 'x', history: [(fromHer: false, text: 'hi')], model: model);
      return body!;
    }

    test('🔴 OpenAI ตรง: ขอไม่คิดลึก และเพดาน 600 พอสำหรับคำตอบ', () async {
      final b = await sent(OpenAiConfig.baseUrl, 'gpt-5.6-sol');
      expect(b['reasoning_effort'], 'none');
      expect(b['max_completion_tokens'], 600);
    });

    test('รุ่นที่ต้องคิดบ้าง: เผื่อเพดานให้ยังเหลือที่สำหรับคำตอบ', () async {
      final b = await sent(OpenAiConfig.baseUrl, 'gpt-6.1-sol');
      expect(b['reasoning_effort'], 'low');
      expect(b['max_completion_tokens'], greaterThan(600));
    });

    test('พร็อกซีของเรา / เซิร์ฟเวอร์ในบ้าน: ไม่ส่งฟิลด์ที่ปลายทางไม่รู้จัก', () async {
      final b = await sent('https://xman4289.com/api/ai/v1', 'gpt-5.6-sol');
      expect(b.containsKey('reasoning_effort'), isFalse);
      final home = await sent('http://192.168.1.10:11434/v1', 'gpt-5.6-sol');
      expect(home.containsKey('reasoning_effort'), isFalse);
    });
  });

  group('ค่าที่เคยเลือกไว้', () {
    test('tts-1 / tts-1-hd ย้ายไป gpt-4o-mini-tts (ใช้ได้กับทุกเสียง)', () {
      const fallback = VoiceProfile(
          engine: TtsEngine.openai, voice: 'coral', model: 'gpt-4o-mini-tts', instructions: '');
      for (final old in ['tts-1', 'tts-1-hd']) {
        final p = VoiceProfile.fromJson({'engine': 'openai', 'voice': 'ballad', 'model': old}, fallback);
        expect(p.model, 'gpt-4o-mini-tts', reason: old);
        expect(p.voice, 'ballad');
      }
    });

    test('gpt-realtime ย้ายไป 2.1', () {
      expect(OpenAiConfig.migrateRealtime('gpt-realtime'), 'gpt-realtime-2.1');
      expect(OpenAiConfig.migrateRealtime('gpt-realtime-2.1-mini'), 'gpt-realtime-2.1-mini');
    });

    test('รายการเสียงไม่มีรุ่นที่ถูกประกาศเลิกใช้', () {
      expect(OpenAiConfig.ttsChoices, isNot(contains('tts-1')));
      expect(OpenAiConfig.ttsChoices, isNot(contains('tts-1-hd')));
      expect(OpenAiConfig.realtimeChoices.map((r) => r.id), isNot(contains('gpt-realtime')));
    });

    test('เสียงใหม่ marin / cedar มีชื่อที่อ่านออก ไม่ใช่ตกไปเป็นเสียงอื่น', () {
      const s = S(AppLang.th);
      expect(s.voiceLabel('marin'), contains('Marin'));
      expect(s.voiceLabel('cedar'), contains('Cedar'));
    });
  });
}
