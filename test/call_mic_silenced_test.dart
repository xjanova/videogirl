/// ไมค์ของเธอระหว่างสาย — ระบบปิดเงียบ ≠ ปลายสายเงียบ
///
/// ที่มา: เจ้าของ "คนที่โทรมาไม่ได้ยินเสียงที่มายด์พูดเลย และมายด์ก็ไม่ได้ยินเสียงที่พูดมาเลย"
/// · Android ส่งความเงียบให้ไมค์ของแอประหว่างสาย เว้นแต่เป็นบริการการช่วยเหลือพิเศษ **และ**
/// จอแอปอยู่บนสุด · จอดับกลางสาย (ลำโพงเปิด ไม่มีใครแตะจอ) = เธอหูดับโดยไม่มี error
library;

import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:videogirl/theme/tokens.dart';
import 'package:videogirl/widgets/call_panel.dart';

class _Speech extends SpeechService {
  @override
  Future<Utterance> synthesize(String text, {required VoiceProfile profile}) async =>
      (bytes: Uint8List.fromList(List.filled(64, 7)), mime: 'audio/wav');
}

const _record = MethodChannel('com.llfbandit.record/messages');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late CallWatch watch;
  late MindState state;
  late CallSession session;
  var info = <String, Object?>{};
  var micGranted = true;

  setUp(() {
    micGranted = true;
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('call_mic');
    info = {'live': true, 'mind': true, 'speaker': true, 'micSilenced': true, 'number': '0812345678'};

    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (call) async => tmp.path);
    m.setMockMethodCallHandler(_record, (call) async => null);
    m.setMockMethodCallHandler(kSystemChannel, (call) async {
      if (call.method == 'callInfo') return info;
      // แผงสายไม่ต้องเปิดไมค์จริง · ปลั๊กอินไมค์ไม่มีในเทสต์วิดเจ็ต (ช่อง events ล้ม)
      if (call.method == 'micGranted') return micGranted;
      return true;
    });

    watch = CallWatch();
    state = MindState(speech: _Speech());
    session = CallSession(watch: watch, state: state);
  });

  tearDown(() async {
    await session.hangUp();
    session.dispose();
    watch.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(kSystemChannel, null);
    m.setMockMethodCallHandler(_record, null);
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    try {
      tmp.deleteSync(recursive: true);
    } on Object {
      // temp ค้างไม่ใช่เหตุให้เทสต์แดง
    }
  });

  test('🔴 ระบบปิดไมค์เกินสองวิ = เตือนตรงสาเหตุ และลงรายงาน', () async {
    await session.start();
    expect(session.micBlocked, isFalse, reason: 'ช่วงสลับจอตอนสายติด ยังไม่นับ');

    await Future<void>.delayed(const Duration(milliseconds: 2200));
    await session.start(); // ถามสถานะรอบใหม่ (ในแอปคือนาฬิกาหนึ่งวินาที)
    expect(session.micBlocked, isTrue);

    await session.hangUp();
    expect(state.lastIncident, contains('silenced=true'),
        reason: 'สายที่เธอหูดับเพราะระบบปิดไมค์ต้องส่งรายงานเอง ไม่ใช่เงียบหาย');
  });

  test('ระบบเลิกปิดไมค์ (กลับมาที่แอป) = เลิกเตือนเอง ไม่ค้าง', () async {
    await session.start();
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    await session.start();
    expect(session.micBlocked, isTrue);

    info = {...info, 'micSilenced': false};
    await session.start();
    expect(session.micBlocked, isFalse);
  });

  test('เครื่องไม่บอก (Android ต่ำกว่า 10) = ไม่เตือน ไม่ลงรายงานว่าถูกปิด', () async {
    info = {'live': true, 'mind': true, 'speaker': true, 'number': '0812345678'};
    await session.start();
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    await session.start();
    expect(session.micBlocked, isFalse);

    await session.hangUp();
    expect(state.lastIncident ?? '', isNot(contains('silenced=true')));
  });

  test('เจ้าของแทรกสายแล้ว = ไมค์ของเธอปิดเองตั้งใจ ไม่ใช่เรื่องต้องเตือน', () async {
    await session.start();
    await session.bargeIn();
    info = {...info, 'mind': false};
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    await session.start();
    expect(session.micBlocked, isFalse);
  });

  testWidgets('แผงสายบอกว่าระบบปิดไมค์ แทนคำว่า "เครื่องไม่ยอมให้ฟัง" แบบเดา', (tester) async {
    micGranted = false;
    await tester.runAsync(() async {
      await session.start();
      await Future<void>.delayed(const Duration(milliseconds: 2200));
      await session.start();
    });
    expect(session.micBlocked, isTrue);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CallPanel(session: session, mode: MindMode.work)),
    ));
    expect(find.text(const S(AppLang.en).callMicBlocked), findsOneWidget);
    expect(find.text(const S(AppLang.en).callDeaf), findsNothing);
  });

  group('ฝั่งเนทีฟ', () {
    final kotlin = Directory('android/app/src/main/kotlin/com/xjanova/videogirl');
    String src(String name) => File('${kotlin.path}/$name').readAsStringSync();

    test('🔴 จอติดค้างตลอดที่เธอถือสาย — ทั้งจอสายเนทีฟและจอเธอ', () {
      final screen = src('CallScreen.kt');
      expect(screen, contains('MindInCallService.mindLive()'));
      expect(screen, contains('keepScreenOn'));

      final inCall = src('InCallActivity.kt');
      final render = inCall.indexOf('private fun render()');
      expect(inCall.indexOf('CallScreen.apply(this)', render), greaterThan(render),
          reason: 'จอดับ = จอแอปไม่อยู่บนสุด = ระบบส่งความเงียบให้ไมค์ของเธอ');

      final main = src('MainActivity.kt');
      expect(main, contains('fun syncCallScreen()'));
      final resume = main.indexOf('override fun onResume()');
      expect(main.indexOf('CallScreen.apply(this)', resume), greaterThan(resume));

      final service = src('MindInCallService.kt');
      final notify = service.indexOf('private fun notifyChanged()');
      expect(service.indexOf('MainActivity.syncCallScreen()', notify), greaterThan(notify));
    });

    test('จอสายไม่ขอปลดล็อก — แป้น PIN บังจอสายแล้วจอดับในไม่กี่วิ', () {
      expect(src('InCallActivity.kt'), isNot(contains('requestDismissKeyguard(')));
    });

    test('ถามระบบตรง ๆ ว่าไมค์ถูกปิดไหม และส่งให้ Dart ทุกรอบที่ถามสถานะ', () {
      final audio = src('CallAudio.kt');
      expect(audio, contains('isClientSilenced'));
      expect(audio, contains('MediaRecorder.AudioSource.VOICE_RECOGNITION'));
      expect(src('MindInCallService.kt'), contains('"micSilenced" to CallAudio.micSilenced(context)'));
    });

    test('อัตราไมค์ที่ใช้ระบุ "ไมค์ของเธอ" ตรงกับที่ CallSession เปิดจริง', () {
      final rate = RegExp(r'MIC_RATE = (\d+)').firstMatch(src('CallAudio.kt'))?.group(1);
      final dart = File('lib/phone/call_session.dart').readAsStringSync();
      expect(dart, contains('static const _rate = $rate;'));
      expect(dart, contains('AndroidAudioSource.voiceRecognition'));
    });
  });
}
