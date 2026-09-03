/// ไมค์ในช่องแชท — ของจริง ไม่ใช่ปุ่มที่กดแล้วเปลี่ยนสีตัวเอง
///
/// สองเรื่องที่เทสต์นี้คุมไว้ เป็นเรื่องที่ถ้าพลาดแล้วไม่มีอะไรฟ้อง:
///
/// 1. **เสียงต้องไปที่เดียวกับที่ข้อความไป** — คนที่เลือกสมองในเครื่องเลือก
///    เพราะไม่อยากให้อะไรออกนอกเครื่อง การแอบส่งเสียงเขาไปถอดที่ OpenAI
///    เพราะ "บังเอิญมีคีย์อยู่" คือการผิดสัญญาข้อเดียวที่ทางนั้นให้ไว้
/// 2. **ข้อความที่ถอดได้ต้องไม่ถูกส่งทันที** — ถอดผิดได้เสมอ โดยเฉพาะไทย
///    ผ่านไมค์มือถือ · ส่งเลยแปลว่าเธอตอบคำที่เจ้าของไม่ได้พูด
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/ai/device_speech.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/ai/voice_input.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_ai.dart';
import 'package:videogirl/state/mind_state.dart';

const _th = S(AppLang.th);

VoiceInput _voice({
  bool micOk = true,
  Future<String> Function(Uint8List)? transcribe,
}) =>
    VoiceInput(
      ensureMic: () async => micOk,
      transcribe: transcribe ?? (_) async => '',
      strings: () => _th,
    );

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  _endpointGroup();

  group('🔴 เสียงไปที่เดียวกับที่ข้อความไป', () {
    Future<MindState> stateOn(BrainProvider b) async {
      final s = MindState();
      await s.load();
      s.setBrain(b);
      return s;
    }

    test('สมองในเครื่อง + เครื่องถอดเสียงเองไม่ได้ = ใช้ไมค์ไม่ได้ และบอกว่าทำไม',
        () async {
      final s = await stateOn(BrainProvider.onDevice);
      // ไม่ได้ต่อตัวถอดเสียงในเครื่อง = เหมือนเครื่องที่ทำไม่ได้
      expect(s.canTranscribe, isFalse);
      expect(s.whyNoMic, _th.micNoOnDevice);
      s.dispose();
    });

    test('🔴 สมองในเครื่องยิงเสียงออกเน็ตไม่ได้ ไม่ว่ากรณีใด', () async {
      final s = await stateOn(BrainProvider.onDevice);
      await expectLater(
        s.transcribeChat(Uint8List.fromList(const [1, 2, 3])),
        throwsA(isA<OpenAiFailure>()),
        reason: 'ทางนี้สัญญาว่าไม่มีอะไรออกนอกเครื่อง '
            'เสียงพูดยิ่งเป็นข้อมูลที่อ่อนไหวกว่าข้อความ',
      );
      s.dispose();
    });

    test('🔴 มีคีย์ตัวเองอยู่ ก็ยังห้ามส่งเสียงออก ถ้าเลือกสมองในเครื่องไว้',
        () async {
      final s = await stateOn(BrainProvider.onDevice);
      await s.setOpenAiKey('sk-มีคีย์อยู่จริง-แต่ไม่เกี่ยว');

      await expectLater(
        s.transcribeChat(Uint8List.fromList(const [1, 2, 3])),
        throwsA(isA<OpenAiFailure>()),
        reason: '"บังเอิญมีคีย์" ไม่ใช่เหตุผลให้ส่งเสียงเขาออกไป',
      );
      s.dispose();
    });

    test('สมองในเครื่องต้องถอดเสียง**ในเครื่อง** ไม่ใช่ส่งออกไป', () async {
      final s = await stateOn(BrainProvider.onDevice);
      expect(s.transcribesOnDevice, isTrue);

      s.setBrain(BrainProvider.openai);
      expect(s.transcribesOnDevice, isFalse);
      s.dispose();
    });

    test('พร็อกซีของเรา ต้องมีรหัสสิทธิ์ก่อน', () async {
      final s = await stateOn(BrainProvider.mindProxy);
      expect(s.canTranscribe, isFalse);
      expect(s.whyNoMic, _th.licenseNeeded);

      s.setLicenseKey('LICENSE-1234');
      expect(s.canTranscribe, isTrue);
      expect(s.whyNoMic, isEmpty);
      s.dispose();
    });

    test('คีย์ของตัวเอง ต้องกรอกคีย์ก่อน', () async {
      final s = await stateOn(BrainProvider.openai);
      expect(s.canTranscribe, isFalse);
      expect(s.whyNoMic, _th.ownKeyNeeded);

      await s.setOpenAiKey('sk-test-key-for-unit-tests');
      expect(s.canTranscribe, isTrue);
      s.dispose();
    });

    test('เซิร์ฟเวอร์ในบ้าน ที่อยู่ว่างต้องบอกตรง ๆ ไม่ใช่ "ต่อเน็ตไม่ได้"',
        () async {
      final s = await stateOn(BrainProvider.homeServer);
      s.setHomeServerUrl('');
      expect(s.canTranscribe, isFalse);
      expect(s.whyNoMic, _th.homeServerNoUrl);
      s.dispose();
    });
  });

  group('อัดแล้วถอดเสียง', () {
    test('ยังไม่ได้อนุญาตไมค์ = บอกเหตุผล ไม่ใช่เงียบ', () async {
      final v = _voice(micOk: false);
      expect(await v.start(), isFalse);
      expect(v.stage, VoiceInputStage.failed);
      expect(v.error, _th.micDenied);
      v.dispose();
    });

    test('เริ่มไม่สำเร็จแล้วต้องไม่ค้างอยู่ในสถานะกำลังทำงาน', () async {
      final v = _voice(micOk: false);
      await v.start();
      expect(v.busy, isFalse,
          reason: 'ค้าง = ปุ่มไมค์กดไม่ได้อีกเลยจนกว่าจะปิดแอป');
      v.dispose();
    });

    test('ยังไม่ได้เริ่มฟัง กดหยุดต้องไม่ทำอะไร', () async {
      final v = _voice();
      expect(await v.stop(), isNull);
      expect(v.stage, VoiceInputStage.idle);
      v.dispose();
    });

    test('ล้างข้อผิดพลาดแล้วกลับมาว่าง พร้อมให้กดใหม่', () async {
      final v = _voice(micOk: false);
      await v.start();
      expect(v.stage, VoiceInputStage.failed);

      v.clearError();
      expect(v.error, isNull);
      expect(v.stage, VoiceInputStage.idle);
      v.dispose();
    });

    test('เพดานการอัดต้องมีอยู่จริง', () {
      expect(VoiceInput.maxTake.inSeconds, greaterThan(0),
          reason: 'ไมค์ที่เปิดค้างทั้งวันคือทั้งแบตและเสียงในห้องที่ถูกอัด');
      expect(VoiceInput.maxTake.inMinutes, lessThanOrEqualTo(2));
    });
  });
}

/// 🔴 ระบบตัดจบการฟังเอง แล้วข้อความหายไปทั้งประโยค
///
/// ตัวถอดเสียงของแอนดรอยด์จบเทิร์นเองทันทีที่ได้ยินว่าเงียบลง (endpointing)
/// ซึ่งเป็น**ทางที่เกิดบ่อยที่สุด** — คนพูดจบก็หยุดพูด ไม่ได้รีบไปกดปุ่ม
///
/// ของเดิมเก็บผลไว้ใน `_pending` แล้วล้างทิ้งในบรรทัดถัดไปเมื่อไม่มีใครรอ
/// อยู่ · สถานะกลับไปเป็น `idle` การกดปุ่มทีหลังจึงไม่ใช่ "หยุดแล้วเอาผล"
/// แต่กลายเป็น **"เริ่มฟังรอบใหม่"** · อาการที่ผู้ใช้เห็นคือพูดใส่ไมค์แล้ว
/// ไม่มีอะไรเกิดขึ้นเลย ไม่ว่าจะลองกี่รอบ
void _endpointGroup() {
  group('🔴 ระบบตัดจบการฟังเอง ข้อความต้องไม่หาย', () {
    late _FakeStt native;
    late VoiceInput voice;
    final heard = <String>[];

    setUp(() {
      heard.clear();
      native = _FakeStt()..install();
      voice = VoiceInput(
        ensureMic: () async => true,
        transcribe: (_) async => '',
        strings: () => _th,
        device: native.speech,
        preferDevice: () => true,
      )..onHeard = heard.add;
    });

    tearDown(() => voice.dispose());

    test('พูดจบแล้วปล่อยให้ระบบตัดเอง ข้อความต้องมาถึงช่องพิมพ์', () async {
      await voice.start();
      expect(voice.stage, VoiceInputStage.listening);

      // ผู้ใช้ไม่ได้กดอะไรเลย · ระบบได้ยินว่าเงียบแล้วสรุปผลเอง
      await native.emit('result', {'text': 'สวัสดีมายด์ วันนี้เป็นไงบ้าง'});
      await Future<void>.delayed(Duration.zero);

      expect(heard, ['สวัสดีมายด์ วันนี้เป็นไงบ้าง'],
          reason: 'ไม่มีใครรออยู่ = ต้องออกทาง onHeard ไม่ใช่ถูกทิ้ง');
      expect(voice.stage, VoiceInputStage.idle);
    });

    test('กดหยุดเอง ผลต้องกลับทาง stop() ทางเดียว ไม่ซ้ำสองทาง', () async {
      await voice.start();
      final waiting = voice.stop();
      await native.emit('result', {'text': 'ทดสอบ'});

      expect(await waiting, 'ทดสอบ');
      expect(heard, isEmpty,
          reason: 'ส่งสองทาง = ข้อความถูกยัดลงช่องพิมพ์สองครั้ง');
    });

    test('ระบบตัดจบแต่ไม่ได้ยินอะไร ต้องไม่ยิงข้อความเปล่าออกไป', () async {
      await voice.start();
      await native.emit('result', {'text': '   '});
      await Future<void>.delayed(Duration.zero);

      expect(heard, isEmpty);
      expect(voice.stage, VoiceInputStage.failed);
    });
  });
}

/// ฝั่งเนทีฟปลอมของช่องถอดเสียงในเครื่อง
class _FakeStt {
  static const _ch = MethodChannel('giggok/stt_voiceinput_test');

  late DeviceSpeech speech;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ch, (call) async => true);
    speech = DeviceSpeech.forTest(_ch);
  }

  Future<void> emit(String event, [Map<String, Object?> data = const {}]) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        _ch.name,
        _ch.codec.encodeMethodCall(MethodCall('onStt', {...data, 'event': event})),
        (_) {},
      );
}
