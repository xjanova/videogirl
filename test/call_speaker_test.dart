/// ลำโพงตอนเธอถือสาย — ทางเดียวที่เสียงเธอไปถึงปลายสาย
///
/// ที่มา: เจ้าของ "ปลายสายหรือคนโทร ไม่ได้ยินเสียงน้องมาย" · ของเดิมสั่งลำโพงครั้งเดียว
/// ตอนกริ่งยังดัง แล้วระบบย้ายเสียงกลับหูฟังตอนสายต่อติด ไม่มีใครเปิดคืน ไม่มีใครบอก
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/phone/call_session.dart';
import 'package:videogirl/phone/call_watch.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';

class _Speech extends SpeechService {
  @override
  Future<Utterance> synthesize(String text, {required VoiceProfile profile}) async =>
      (bytes: Uint8List.fromList(List.filled(64, 7)), mime: 'audio/wav');
}

const _record = MethodChannel('com.llfbandit.record/messages');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late List<String> log;
  late CallWatch watch;
  late CallSession session;
  var info = <String, Object?>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('call_speaker');
    log = [];
    info = {'live': true, 'mind': true, 'speaker': false, 'number': '0812345678'};

    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (call) async => tmp.path);
    m.setMockMethodCallHandler(_record, (call) async => null);
    m.setMockMethodCallHandler(kSystemChannel, (call) async {
      if (call.method == 'callInfo') return info;
      if (call.method == 'callSpeak') log.add('callSpeak:speaker=${info['speaker']}');
      if (call.method == 'callSpeakerOn') {
        log.add('callSpeakerOn');
        info = {...info, 'speaker': true};
      }
      return true;
    });

    watch = CallWatch();
    session = CallSession(watch: watch, state: MindState(speech: _Speech()));
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

  Future<void> until(bool Function() ok, {int tries = 400}) async {
    for (var i = 0; i < tries && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('🔴 คำทักรอจนลำโพงติดจริง ไม่พูดใส่หูฟัง', () async {
    await session.start();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(log.where((l) => l.startsWith('callSpeak')), isEmpty,
        reason: 'ลำโพงยังไม่ติด = คำทักไปออกหูฟัง ปลายสายได้ยินแต่ความเงียบ');

    info = {...info, 'speaker': true};
    await until(() => log.any((l) => l.startsWith('callSpeak')));
    expect(log.first, 'callSpeak:speaker=true');
  });

  test('ลำโพงไม่ติดเลย = รอไม่เกินสามวิแล้วพูดต่อ ไม่ค้างทั้งสาย', () async {
    await session.start();
    await until(() => log.any((l) => l.startsWith('callSpeak')), tries: 600);
    expect(log, contains('callSpeak:speaker=false'));
  });

  test('ลำโพงปิดเกินสามวิระหว่างเธอถือสาย = เตือน · แตะแล้วเปิดคืน', () async {
    await session.start();
    expect(session.speakerOff, isFalse, reason: 'ช่วงสลับเส้นทางตอนสายติด ยังไม่นับ');

    await Future<void>.delayed(const Duration(milliseconds: 3300));
    await session.start(); // ถามสถานะรอบใหม่ (ในแอปคือนาฬิกาหนึ่งวินาที)
    expect(session.speakerOff, isTrue);

    await session.speakerOn();
    expect(log, contains('callSpeakerOn'));
    expect(session.speakerOff, isFalse);
  });

  test('เครื่องไม่บอกสถานะลำโพง = ไม่รอ ไม่เตือน (ไม่รู้ ≠ ปิด)', () async {
    info = {'live': true, 'mind': true, 'number': '0812345678'};
    await session.start();
    await until(() => log.any((l) => l.startsWith('callSpeak')), tries: 100);
    expect(log, isNotEmpty);
    expect(session.speakerOff, isFalse);
  });

  group('ฝั่งเนทีฟ', () {
    final kotlin = Directory('android/app/src/main/kotlin/com/xjanova/videogirl');
    String src(String name) => File('${kotlin.path}/$name').readAsStringSync();

    test('ปุ่มเปิดลำโพงคืนมีที่รับจริง', () {
      expect(src('SystemBridge.kt'), contains('"callSpeakerOn" ->'));
    });

    test('🔴 เปิดลำโพงคืนตอนสายติด และทุกครั้งที่ระบบย้ายเส้นทางเสียง', () {
      final service = src('MindInCallService.kt');
      final onAudio = service.indexOf('override fun onCallAudioStateChanged');
      expect(onAudio, greaterThan(-1));
      expect(service.indexOf('CallAudio.keepSpeaker', onAudio), greaterThan(onAudio),
          reason: 'สั่งครั้งเดียวตอนกริ่งดังไม่พอ — ระบบรีเซ็ตเป็นหูฟังตอนสายติด');
      expect(service, contains('Call.STATE_ACTIVE && mindHandling'));
    });

    test('เจ้าของปิดลำโพงเอง = ไม่เปิดทับ', () {
      expect(src('InCallActivity.kt'), contains('CallAudio.ownerRouted = !on'));
      expect(src('CallAudio.kt'), contains('if (!open || ownerRouted) return'));
    });
  });
}
