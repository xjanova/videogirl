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

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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

  group('🔴 เสียงไปที่เดียวกับที่ข้อความไป', () {
    Future<MindState> stateOn(BrainProvider b) async {
      final s = MindState();
      await s.load();
      s.setBrain(b);
      return s;
    }

    test('สมองในเครื่อง = ใช้ไมค์ไม่ได้ และต้องบอกว่าทำไม', () async {
      final s = await stateOn(BrainProvider.onDevice);
      expect(s.canTranscribe, isFalse,
          reason: 'ทางนี้สัญญาว่าไม่มีอะไรออกนอกเครื่อง '
              'เสียงพูดยิ่งเป็นข้อมูลที่อ่อนไหวกว่าข้อความ');
      expect(s.whyNoMic, _th.micNeedsCloudBrain);
      s.dispose();
    });

    test('เลือกสมองในเครื่องแล้วยิงเสียงออกไป ต้องถูกปฏิเสธที่ต้นทาง',
        () async {
      final s = await stateOn(BrainProvider.onDevice);
      await expectLater(
        s.transcribeChat(Uint8List.fromList(const [1, 2, 3])),
        throwsA(isA<OpenAiFailure>()),
      );
      s.dispose();
    });

    test('มีคีย์ตัวเองอยู่ ก็ยังห้ามส่งออกถ้าเลือกสมองในเครื่องไว้', () async {
      final s = await stateOn(BrainProvider.onDevice);
      await s.setOpenAiKey('sk-มีคีย์อยู่จริง-แต่ไม่เกี่ยว');

      expect(s.canTranscribe, isFalse,
          reason: '🔴 "บังเอิญมีคีย์" ไม่ใช่เหตุผลให้ส่งเสียงเขาออกไป');
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
