/// ทุกอย่างที่ปุ่มรออยู่ต้องมีวันจบ
///
/// ที่มา (2026-10-06): เจ้าของเจอ "เธอไม่พูด · ปุ่มลองฟังเสียงค้าง · เครื่องร้อน
/// มาก ช้าทั้งเครื่อง · กดออกจากแอปก็ค้าง" และระบบรายงานมี 0 ฉบับ — เพราะ
/// ไม่มีอะไร "ล้ม" เลย ทุกอย่างแค่รอ: สมองในเครื่องคิดได้ถึง 8192 token
/// ถ้าโมเดลวนซ้ำ · เสียงเครื่อง/เวที/เครื่องเล่นไม่มีเวลาหมด · ปุ่มออกต่อคิว
/// รอสมองคิดจบก่อน
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/local_brain.dart';
import 'package:videogirl/ai/mind_audio.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_ai.dart';
import 'package:videogirl/state/mind_state.dart';

import 'device_voice_test.dart' show wav;

/// เสียงเครื่องที่ไม่ตอบ — synthesizeToFile ไม่คืนค่าเลย (ของจริงบนเครื่อง:
/// เครื่องยนต์เสียงยังไม่พร้อม / ถูกระบบพัก / ประโยคที่สองเขียนทับตัวแรก)
class _HangTts extends FlutterTts {
  int stopped = 0;
  @override
  Future<dynamic> setLanguage(String language) async => 1;
  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;
  @override
  Future<dynamic> setPitch(double pitch) async => 1;
  @override
  Future<dynamic> awaitSynthCompletion(bool awaitCompletion) async => 1;
  @override
  Future<dynamic> isLanguageAvailable(String language) async => true;
  @override
  Future<dynamic> stop() async {
    stopped++;
    return 1;
  }

  @override
  Future<dynamic> synthesizeToFile(String text, String fileName, [bool isFullPath = false]) =>
      Completer<dynamic>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('🔴 สมองในเครื่องคิดไม่หยุด', () {
    test('ประโยคที่วนซ้ำถูกจับได้ และตัดเหลือรอบแรก', () {
      const once = 'ค่ะ เข้าใจแล้วค่ะ ฉันจะจำไว้นะคะ ว่าคุณชอบกาแฟเย็นไม่หวาน ';
      final looping = 'สวัสดีค่ะ ${once * 6}';
      final at = LocalBrain.loopAt(looping);
      expect(at, isNotNull);
      final kept = looping.substring(0, at);
      expect(kept.length, lessThan(looping.length ~/ 2));
      expect(kept, startsWith('สวัสดีค่ะ'));
    });

    test('ตัวอักษรเดียวซ้ำยาว ๆ (ฮ่าาาา…) ก็นับเป็นวน', () {
      expect(LocalBrain.loopAt('ฮ่า${'า' * 400}'), isNotNull);
    });

    test('ข้อความปกติต้องไม่ถูกตัด', () {
      const normal = 'พรุ่งนี้มีนัดประชุมทีมตอนสิบโมงที่ห้องใหญ่ค่ะ '
          'ต่อด้วยกินข้าวกลางวันกับคุณแม่ตอนเที่ยงครึ่ง แล้วบ่ายสามโมงต้องส่งรายงาน '
          'ประจำเดือนให้หัวหน้า อย่าลืมแนบไฟล์ตัวเลขยอดขายด้วยนะคะ ส่วนตอนเย็น'
          'มีคลาสโยคะหกโมงค่ะ ถ้าเหนื่อยเกินไปบอกได้นะคะ เดี๋ยวช่วยเลื่อนให้';
      expect(LocalBrain.loopAt(normal), isNull);
      expect(LocalBrain.loopAt('สั้น ๆ'), isNull);
    });

    test('เพดานของงานเบื้องหลังเข้มกว่าการคุย · ในสายสั้นที่สุด', () {
      expect(ReplyCap.background.tokens, lessThan(ReplyCap.chat.tokens));
      expect(ReplyCap.call.tokens, lessThan(ReplyCap.background.tokens));
      expect(ReplyCap.chat.tokens, lessThan(8192),
          reason: 'เพดานเท่า context = ไม่มีเพดาน (ตัวที่ทำเครื่องร้อน)');
      for (final c in ReplyCap.values) {
        expect(c.time, lessThanOrEqualTo(const Duration(minutes: 3)));
      }
    });

    test('ต้นทางผูกเพดานไว้จริง ไม่ใช่แค่ประกาศ', () {
      final src = File('lib/ai/local_brain.dart').readAsStringSync();
      expect(src, contains('tokens >= cap.tokens'));
      expect(src, contains('clock.elapsed >= cap.time'));
      expect(src, contains('stopGeneration()'),
          reason: 'เลิกฟังอย่างเดียว เนทีฟยังคิดต่อจนเครื่องร้อน');
      final state = File('lib/state/mind_state.dart').readAsStringSync();
      expect(RegExp(r'cap: ReplyCap\.background').allMatches(state).length, 2,
          reason: 'สกัดความจำ + สรุปสาย = งานเบื้องหลังสองงาน');
      expect(state, contains('cap: ReplyCap.call'));
    });
  });

  group('🔴 เสียงเครื่องไม่ตอบ', () {
    const device = VoiceProfile(
        engine: TtsEngine.device, voice: '', model: '', instructions: '');
    const s = S(AppLang.th);
    const pathCh = MethodChannel('plugins.flutter.io/path_provider');
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('hang_guards');
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

    test('หมดเวลาแล้วบอกเหตุผล ไม่ค้างตลอดกาล', () async {
      final tts = _HangTts();
      final svc = SpeechService(
        deviceTts: tts,
        strings: () => s,
        deviceLimit: (_) => const Duration(milliseconds: 80),
      );
      await expectLater(
        svc.synthesize('สวัสดีค่ะ', profile: device),
        throwsA(isA<OpenAiFailure>().having((e) => e.message, 'message', s.errTtsStuck)),
      );
      expect(tts.stopped, greaterThan(0), reason: 'ต้องสั่งเครื่องยนต์เสียงให้เลิกด้วย');
    });

    test('ประโยคที่สองไม่ค้างตามประโยคแรก (คิวเดินต่อ)', () async {
      final svc = SpeechService(
        deviceTts: _HangTts(),
        strings: () => s,
        deviceLimit: (_) => const Duration(milliseconds: 60),
      );
      final a = svc.synthesize('หนึ่ง', profile: device);
      final b = svc.synthesize('สอง', profile: device);
      await expectLater(a, throwsA(isA<OpenAiFailure>()));
      await expectLater(b, throwsA(isA<OpenAiFailure>()));
    });

    test('เผื่อเวลาตามความยาว แต่มีเพดาน', () {
      expect(SpeechService.deviceLimitFor(''), const Duration(seconds: 12));
      expect(SpeechService.deviceLimitFor('ก' * 100),
          greaterThan(SpeechService.deviceLimitFor('ก')));
      expect(SpeechService.deviceLimitFor('ก' * 100000), const Duration(seconds: 90));
    });
  });

  group('🔴 เล่นเสียงต้องมีเวลาหมด', () {
    test('WAV อ่านความยาวจากหัวไฟล์ได้เป๊ะ', () {
      expect(MindAudio.secondsOf(wav(2), 'audio/wav'), closeTo(2, 0.01));
    });

    test('mp3 ประมาณเกินเสมอ (32 kbps)', () {
      // 128 kbps · 3 วินาที = 48,000 ไบต์ → ประมาณ 12 วิ (ยาวกว่าจริง ไม่ตัดกลางประโยค)
      expect(MindAudio.secondsOf(Uint8List(48000), 'audio/mpeg'), greaterThanOrEqualTo(3));
    });

    test('เวลาที่ยอมรอ = ความยาว × 1.5 + 8 วิ · ไฟล์ยักษ์ไม่ทำให้รอเป็นชั่วโมง', () {
      expect(MindAudio.limitFor(wav(2), 'audio/wav'), const Duration(milliseconds: 11000));
      expect(MindAudio.limitFor(Uint8List(100 * 1024 * 1024), 'audio/mpeg'),
          lessThanOrEqualTo(const Duration(minutes: 16)));
    });

    test('เวทีและทางสำรองผูกเวลาหมดไว้จริง', () {
      final view = File('lib/avatar/avatar_view.dart').readAsStringSync();
      expect(view, contains('MindAudio.limitFor(bytes, mime)'));
      expect(view, contains("why.startsWith('stalled-output')"));
      expect(view, contains("why.startsWith('stage-timeout')"));
      final audio = File('lib/ai/mind_audio.dart').readAsStringSync();
      expect(audio, contains('.timeout(limitFor(bytes, mime)'));
      final lip = File('assets/avatar/lipsync.js').readAsStringSync();
      expect(lip, contains("throw new Error('stalled-output')"));
      expect(lip, contains("throw new Error('play-timeout')"));
      expect(lip, contains('wait(RESUME_LIMIT)'),
          reason: 'resume() ที่ระบบไม่ยอมให้เริ่มค้างเฉย ๆ ไม่ reject');
    });
  });

  group('🔴 ปุ่มออกจากแอปต้องออกได้เสมอ', () {
    test('เครื่องเล่นค้าง → ยังออกได้ภายในเวลา', () async {
      final state = MindState();
      addTearDown(state.dispose);
      state.silencer = () => Completer<void>().future; // ไม่มีวันจบ
      final clock = Stopwatch()..start();
      await state.prepareExit(limit: const Duration(milliseconds: 150));
      expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('hush ไม่ค้างตามเครื่องเล่นที่ค้าง', () async {
      final state = MindState();
      addTearDown(state.dispose);
      state.silencer = () => Completer<void>().future;
      await state.hush().timeout(const Duration(seconds: 4));
    });

    test('ปุ่มออกในหน้าตั้งค่าไม่รอสตูดิโอ/กล้องที่ค้าง', () {
      final src = File('lib/screens/settings_screen.dart').readAsStringSync();
      expect(src, contains('studio.exit().timeout('));
    });
  });

  group('เวทีหยุดวาดตอนไม่มีใครเห็น', () {
    test('มีคำสั่งหลับครบทุกชั้น · ตื่นเองตอนโหลดใหม่ถ้ายังต้องหลับ', () {
      final js = File('assets/avatar/avatar.js').readAsStringSync();
      expect(js, contains('setAsleep(on)'));
      expect(js, contains('if (this._asleep) { this._raf = 0; return; }'));
      final html = File('assets/avatar/index.html').readAsStringSync();
      expect(RegExp(r'^  sleep:', multiLine: true).hasMatch(html), isTrue);
      final view = File('lib/avatar/avatar_view.dart').readAsStringSync();
      expect(view, contains("if (_asleep) unawaited(_call('window.minde.sleep(true)'))"));
      final home = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(home, contains('setAsleep(_hidden || !widget.active)'));
    });
  });
}
