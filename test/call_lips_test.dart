/// ปากของเธอตอนพูดในสาย
///
/// ที่มา: ของเดิมปาก "พึมพำ" แบบสุ่มตลอดทั้งสาย รวมทั้งตอนที่คู่สายพูดและเธอ
/// ควรเงียบฟัง · ตอนนี้เวทีเล่นไฟล์เสียงเดียวกันแบบปิดเสียงแล้วอ่านคลื่น
/// ลำดับต้องถูก: เตรียม → ปล่อยพร้อมเสียงจริง → ปิดปากเมื่อจบ **ทุกครั้ง**
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/avatar/stage_bridge.dart';
import 'package:videogirl/phone/call_session.dart';
import 'package:videogirl/phone/call_watch.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';

class _Speech extends SpeechService {
  @override
  Future<Utterance> synthesize(String text, {required VoiceProfile profile}) async =>
      (bytes: Uint8List.fromList(List.filled(64, 7)), mime: 'audio/wav');
}

class _Lips implements MindLips {
  _Lips(this.log);

  final List<String> log;
  bool ready = true;

  /// ค้างการเตรียมไว้จนกว่าเทสต์จะปล่อย — จำลองเวทีที่ถอดไฟล์ช้า
  Completer<void>? hold;

  @override
  Future<bool> prepareLips(Uint8List bytes, {required String mime}) async {
    log.add('prepare:${bytes.length}:$mime');
    await hold?.future;
    return ready;
  }

  @override
  Future<void> startLips({Duration lead = Duration.zero}) async =>
      log.add('start:${lead.inMilliseconds}');

  @override
  Future<void> restLips() async => log.add('rest');
}

const _record = MethodChannel('com.llfbandit.record/messages');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late List<String> log;
  late _Lips lips;
  late CallWatch watch;
  late CallSession session;
  var info = <String, Object?>{};

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('call_lips');
    log = [];
    lips = _Lips(log);
    info = {'live': true, 'mind': true, 'number': '0812345678', 'name': 'คุณต้น'};

    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (call) async => tmp.path);
    // ไมค์ของสาย — ในเทสต์ไม่มีปลั๊กอิน ตอบเฉย ๆ ให้วงฟังจบเงียบ ๆ
    m.setMockMethodCallHandler(_record, (call) async => null);
    m.setMockMethodCallHandler(kSystemChannel, (call) async {
      if (call.method == 'callInfo') return info;
      if (call.method == 'callSpeak') log.add('callSpeak');
      if (call.method == 'callStopSpeak') log.add('callStopSpeak');
      return true;
    });

    watch = CallWatch();
    session = CallSession(
      watch: watch,
      state: MindState(speech: _Speech()),
      lips: lips,
    );
  });

  tearDown(() async {
    // วางสายก่อน ให้วงฟังของสายจบเอง · แล้วรอให้งานปิดตัวของไมค์ (async)
    // วิ่งจบก่อนถอดตัวจำลองช่อง ไม่งั้นมันไปพังใส่เทสต์ถัดไป
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

  Future<void> until(bool Function() ok) async {
    for (var i = 0; i < 200 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('ประโยคทักของเธอ: เตรียมปาก → ปล่อยพร้อมเสียงจริง → ปิดปาก', () async {
    await session.start();
    await until(() => log.contains('rest'));

    expect(log.first, 'prepare:64:audio/wav',
        reason: 'ปากต้องอ่านจากไบต์ชุดเดียวกับที่ส่งเข้าสาย');
    final start = log.indexWhere((l) => l.startsWith('start:'));
    expect(start, greaterThan(0));
    expect(start, lessThan(log.indexOf('callSpeak')),
        reason: 'ปล่อยปากหลังเสียงเริ่ม = ปากตามหลังเสียงทุกประโยค');
    expect(log.indexOf('rest'), greaterThan(log.indexOf('callSpeak')));
    expect(log[start], 'start:${CallSession.lipLead.inMilliseconds}');
  });

  test('เวทีรับไฟล์ไม่ได้ = ไม่ปล่อยปาก แต่ยังปิดปากตอนจบเสมอ', () async {
    lips.ready = false;
    await session.start();
    await until(() => log.contains('rest'));

    expect(log.where((l) => l.startsWith('start:')), isEmpty);
    expect(log, contains('callSpeak'), reason: 'ปากพังต้องไม่ทำให้เสียงในสายเงียบ');
    expect(log.indexOf('rest'), greaterThan(log.indexOf('callSpeak')),
        reason: 'เวทีตกไปพึมพำแทน — ไม่ปิด = ปากพึมพำค้างหลังเธอเงียบแล้ว');
  });

  test('🔴 เจ้าของแทรกสายระหว่างเตรียมปาก = ไม่พูด และปิดปาก', () async {
    lips.hold = Completer<void>();
    await session.start();
    await until(() => log.any((l) => l.startsWith('prepare:')));

    await session.bargeIn();
    lips.hold!.complete();
    await until(() => log.contains('rest'));

    expect(log, isNot(contains('callSpeak')),
        reason: 'เสียงเธอจะดังใส่หูเจ้าของที่เพิ่งยกเครื่องขึ้นแนบ');
    expect(log, contains('rest'));
  });
}
