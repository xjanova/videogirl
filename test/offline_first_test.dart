/// ด่านกันแอปหลุดกลับไปพึ่งของนอกเครื่อง
///
/// แอปนี้ตั้งใจให้ใช้ได้**ออฟไลน์ตั้งแต่เปิดครั้งแรก** — build สาธารณะไม่มีคีย์
/// ของใครติดมาด้วยโดยตั้งใจ (ดู docs/security.md) ถ้าค่าตั้งต้นเผลอชี้ไปทาง
/// ที่ต้องมีคีย์เมื่อไหร่ เครื่องที่เพิ่งลง APK จะเงียบสนิทและคุยไม่ได้เลย
/// โดยไม่มีอะไรพัง ไม่มี error ให้เห็น — เป็นบั๊กที่เทสต์แบบอื่นจับไม่ได้
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/device_capability.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/state/mind_state.dart';

/// เสียงปลอม — จำไว้ว่าถูกเรียกด้วย engine อะไรบ้าง ตามลำดับ
class _FakeSpeech extends SpeechService {
  _FakeSpeech({this.failing = const {}});

  /// engine ที่ให้ล้ม เพื่อจำลองไม่มีคีย์ / เน็ตหลุด / เซิร์ฟเวอร์ไม่ตอบ
  final Set<TtsEngine> failing;

  final calls = <TtsEngine>[];

  @override
  Future<Utterance> synthesize(String text,
      {required VoiceProfile profile}) async {
    calls.add(profile.engine);
    if (failing.contains(profile.engine)) {
      throw const OpenAiFailure('จำลองว่าทางนี้ใช้ไม่ได้');
    }
    return (bytes: Uint8List.fromList(const [1, 2, 3]), mime: 'audio/wav');
  }
}

void main() {
  group('ค่าตั้งต้นต้องทำงานได้โดยไม่มีคีย์ของใคร', () {
    test('สมองตั้งต้นคิดเองบนเครื่อง ไม่ใช่ส่งออกไปข้างนอก', () {
      expect(MindState().brain, BrainProvider.onDevice);
    });

    test('สมองตั้งต้นต้องไม่ต้องใช้เน็ตและข้อความต้องไม่ออกนอกเครื่อง', () {
      final b = MindState().brain;
      expect(b.needsInternet, isFalse);
      expect(b.leavesDevice, isFalse);
    });

    test('เสียงตั้งต้นทุกช่องใช้เสียงของเครื่อง', () {
      for (final c in VoiceChannel.values) {
        expect(
          VoiceProfile.defaultFor(c, AppLang.th).engine,
          TtsEngine.device,
          reason: 'ช่อง ${c.name} ตั้งต้นเป็นทางที่ต้องมีคีย์ '
              'เครื่องที่ไม่มีคีย์จะเงียบสนิท',
        );
      }
    });
  });

  group('ตาข่ายรับเสียง', () {
    final profileOpenAi =
        VoiceProfile.defaultFor(VoiceChannel.chat, AppLang.th)
            .copyWith(engine: TtsEngine.openai);

    test('ทางที่เลือกล้ม ต้องตกมาที่เสียงเครื่อง ไม่ใช่เงียบ', () async {
      final speech = _FakeSpeech(failing: const {TtsEngine.openai});
      final state = MindState(speech: speech);

      final out = await state.synthesizeWithFallback('สวัสดี', profileOpenAi);

      expect(out.bytes, isNotEmpty);
      expect(speech.calls, [TtsEngine.openai, TtsEngine.device]);
    });

    test('ทางที่เลือกใช้ได้ ต้องไม่แตะเสียงเครื่องเลย', () async {
      final speech = _FakeSpeech();
      final state = MindState(speech: speech);

      await state.synthesizeWithFallback('สวัสดี', profileOpenAi);

      expect(speech.calls, [TtsEngine.openai]);
    });

    test('เลือกเสียงเครื่องอยู่แล้ว ต้องไม่ยิงซ้ำสองรอบ', () async {
      final speech = _FakeSpeech();
      final state = MindState(speech: speech);

      await state.synthesizeWithFallback(
        'สวัสดี',
        profileOpenAi.copyWith(engine: TtsEngine.device),
      );

      expect(speech.calls, [TtsEngine.device]);
    });

    test('เสียงเครื่องล้มด้วย ต้องปล่อย error ขึ้นไปให้คนเรียกจัดการ', () {
      final speech = _FakeSpeech(
        failing: const {TtsEngine.openai, TtsEngine.device},
      );
      final state = MindState(speech: speech);

      expect(
        state.synthesizeWithFallback('สวัสดี', profileOpenAi),
        throwsA(isA<OpenAiFailure>()),
      );
    });
  });

  group('ด่านสเปคเครื่องตอนเปิดแอป', () {
    // main.dart กั้นเฉพาะ tooSmall เท่านั้น เกณฑ์พวกนี้จึงเป็นตัวตัดสินว่า
    // ใครถูกกั้นไม่ให้เข้าแอปเลย ขยับเลขเมื่อไหร่ต้องรู้ตัว
    test('ต่ำกว่าเกณฑ์ = tooSmall และห้ามใช้สมองในเครื่อง', () {
      final v = DeviceCapability.verdictFor(3600); // ชั้น 4GB จริง
      expect(v.tier, RamTier.tooSmall);
      expect(v.canRunLocal, isFalse);
      expect(v.allowed, isEmpty);
    });

    test('เหนือเกณฑ์ขึ้นมานิดเดียวต้องไม่ถูกกั้น', () {
      final v = DeviceCapability.verdictFor(4600);
      expect(v.tier, isNot(RamTier.tooSmall));
      expect(v.canRunLocal, isTrue);
    });

    test('อ่านแรมไม่ได้ต้องไม่ถูกกั้น — ไม่รู้ ไม่ใช่หลักฐานว่าไม่ไหว', () {
      for (final ram in [null, 0]) {
        expect(DeviceCapability.verdictFor(ram).tier, RamTier.unknown);
      }
    });

    test('เลขที่เอาไปโชว์ต้องมาจากเกณฑ์จริง ไม่ใช่พิมพ์ซ้ำในข้อความ', () {
      // 4600 MB -> "4.5 GB" · ถ้าใครขยับเกณฑ์แล้วลืมแก้ข้อความ เทสต์นี้จะจับได้
      expect(DeviceCapability.minLocalGb, '4.5');
      expect(DeviceCapability.verdictFor(4599).tier, RamTier.tooSmall);
    });
  });
}
