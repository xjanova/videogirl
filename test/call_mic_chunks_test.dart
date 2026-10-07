/// ก้อนเสียงจากไมค์จริงไม่ได้เริ่มที่ไบต์คู่เสมอ — เธอต้องได้ยินทุกก้อน
///
/// ที่มา: รายงาน #3681 (0.1.45, vivo Android 15) · ในสาย `RangeError` ที่ไม่มีใครดักขึ้น
/// ทุก ~0.1 วิตลอดสาย · `peak=0.000` ทั้งที่ไฟล์บันทึกสายได้ยินเสียงคู่สายชัด
///
/// ไบต์จากช่องสื่อสารของ Flutter เป็น **view ซ้อนในก้อนข้อความ** · ตำแหน่งเริ่มขึ้นกับหัวข้อความ
/// (สถานะ 1 + ชนิด 1 + ขนาด 1/3/5 ไบต์) จึงเป็นเลขคี่ได้ · `asInt16List` บนตำแหน่งคี่ = RangeError ·
/// ก้อนถูกเขียนลงไฟล์บันทึก**ก่อน**วัดระดับ แต่ส่งให้เธอฟัง**หลัง** → บันทึกได้ยิน เธอไม่ได้ยิน ·
/// เทสต์เดิมสร้างก้อนเองที่ตำแหน่ง 0 จึงไม่เคยเจอ
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
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

/// ไมค์ปลอมที่ส่งก้อนแบบที่ช่องสื่อสารส่งจริง (ตำแหน่งเริ่มคี่)
class _Mic implements AudioRecorder {
  final chunks = StreamController<Uint8List>();

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async => chunks.stream;
  @override
  Future<bool> isRecording() async => true;
  @override
  Future<String?> stop() async => null;
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// เสียงพูดดัง ๆ 16 บิต · ห่อผ่านช่องสื่อสารจริงของ Flutter (StandardMethodCodec ของ EventChannel)
Uint8List _viaChannel({int samples = 1600, int amp = 12000}) {
  final pcm = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    pcm.setInt16(i * 2, (amp * math.sin(i / 3)).round(), Endian.little);
  }
  const codec = StandardMethodCodec();
  return codec.decodeEnvelope(codec.encodeSuccessEnvelope(pcm.buffer.asUint8List())) as Uint8List;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('วัดระดับเสียง', () {
    test('🔴 ก้อนที่มาจากช่องสื่อสารจริงเริ่มที่ไบต์คี่ได้ — ต้องไม่ล้ม', () {
      final chunk = _viaChannel();
      expect(chunk.offsetInBytes.isOdd, isTrue,
          reason: 'กรณีจริงบนเครื่อง · ถ้าวันหนึ่งช่องสื่อสารจัดตำแหน่งให้แล้ว เทสต์นี้ต้องหากรณีคี่ใหม่');
      final level = CallSession.levelOf(chunk);
      expect(level, greaterThan(.2));
      expect(level, closeTo(CallSession.levelOf(Uint8List.fromList(chunk)), 1e-9),
          reason: 'ตำแหน่งเริ่มไม่ควรเปลี่ยนค่าที่วัดได้');
    });

    test('ความยาวคี่ (ครึ่งตัวอย่างค้างท้าย) = ไม่นับไบต์สุดท้าย ไม่ล้ม', () {
      final backing = Uint8List(1 + 2 * 100 + 1);
      final chunk = Uint8List.sublistView(backing, 1);
      expect(CallSession.levelOf(chunk), 0);
    });
  });

  group('ในสาย', () {
    late Directory tmp;
    late CallWatch watch;
    late CallSession session;
    late _Mic mic;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      tmp = Directory.systemTemp.createTempSync('call_chunks');
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), (call) async => tmp.path);
      m.setMockMethodCallHandler(kSystemChannel, (call) async {
        if (call.method == 'callInfo') {
          return {'live': true, 'mind': true, 'speaker': true, 'number': '0812345678'};
        }
        return true;
      });
      mic = _Mic();
      watch = CallWatch();
      session = CallSession(watch: watch, state: MindState(speech: _Speech()), recorder: mic);
    });

    tearDown(() async {
      await session.hangUp();
      session.dispose();
      watch.dispose();
      await mic.chunks.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(kSystemChannel, null);
      m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
      try {
        tmp.deleteSync(recursive: true);
      } on Object {
        // temp ค้างไม่ใช่เหตุให้เทสต์แดง
      }
    });

    test('🔴 เสียงคู่สายถึงตัวเธอ ไม่ใช่แค่ถึงไฟล์บันทึก', () async {
      await session.start();
      for (var i = 0; i < 400 && session.turn != CallTurn.listening; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(session.turn, CallTurn.listening);

      mic.chunks.add(_viaChannel());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.micLevel, greaterThan(.2),
          reason: 'ก้อนเสียงต้องไปถึงตัวฟังของเธอ · 0 = ล้มก่อนถึง (เหมือนรายงาน #3681)');
    });
  });
}
