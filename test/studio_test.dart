/// สตูดิโอ — เวทีเต็มจอ จอลอย และอัดคลิปลงแกลเลอรี
///
/// ที่ต้องคุมด้วยเทสต์คือเรื่องที่ "ดูเหมือนทำงาน" แต่เสียของจริง:
/// คลิปที่อัดแล้วหายตอนออกจากสตูดิโอ, ก้อนที่หายกลางทางแล้วได้ไฟล์เปิดไม่ขึ้น
/// โดยไม่มีใครบอก, และไฟล์ชั่วคราวหลายสิบเมกที่ค้างอยู่ในเครื่อง
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/avatar/avatar_view.dart';
import 'package:videogirl/avatar/stage_bridge.dart';
import 'package:videogirl/i18n/strings_studio.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/studio/mind_studio.dart';
import 'package:videogirl/studio/studio_backdrop.dart';
import 'package:videogirl/system/permissions.dart';

class _Stage implements StudioStage {
  _Stage(this.log);

  final List<String> log;
  bool isReady = true;
  MindRecStart startResult =
      const MindRecStart(ok: true, mime: 'video/mp4;codecs=avc1', mic: false);

  /// เวทีตอบ "จบแล้ว" หลังสั่งหยุด · false = เวทีตายไปแล้ว ไม่มีวันตอบ
  bool answersStop = true;
  int sent = 0;

  @override
  bool get ready => isReady;

  @override
  MindRecordingSink? recordingSink;

  @override
  Future<void> setStudio(bool on) async => log.add('stage.studio:$on');

  @override
  Future<void> setBackdrop(String? hex) async => log.add('stage.backdrop:$hex');

  @override
  Future<void> syncMocapShot(MindMocapShot s) async => log.add('stage.shot:${s.name}');

  @override
  Future<MindRecStart> startRecording({required bool mic}) async {
    log.add('stage.rec:$mic');
    return startResult;
  }

  @override
  Future<void> stopRecording() async {
    log.add('stage.stop');
    if (answersStop) {
      final sink = recordingSink;
      scheduleMicrotask(() => sink?.recDone('video/mp4', sent));
    }
  }

  void feed(List<int> bytes, {int? seq}) {
    recordingSink!.recChunk(seq ?? sent, Uint8List.fromList(bytes));
    sent++;
  }
}

class _Platform implements StudioPlatform {
  _Platform(this.log);

  final List<String> log;
  bool pipOk = true;
  final List<StudioSave> answers = [];
  List<int>? savedBytes;
  void Function(bool)? pip;

  @override
  Future<void> keepScreenOn(bool on) async => log.add('screen:$on');

  @override
  Future<bool> enterPip(int w, int h) async {
    log.add('pip:$w:$h');
    return pipOk;
  }

  @override
  Future<void> autoPip(bool on, int w, int h) async => log.add('autoPip:$on');

  @override
  Future<void> immersive(bool on) async => log.add('immersive:$on');

  @override
  Future<StudioSave> saveVideo(String path, String name, String mime) async {
    log.add('save:$name:$mime');
    savedBytes = File(path).readAsBytesSync();
    return answers.isEmpty
        ? StudioSave(path: 'Movies/GigGok/$name')
        : answers.removeAt(0);
  }

  @override
  set onPip(void Function(bool inPip)? listener) => pip = listener;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const permCh = MethodChannel('giggok/studio_test_perms');
  late Directory tmp;
  late List<String> log;
  late _Stage stage;
  late _Platform platform;
  late MindState state;
  late MindStudio studio;

  MindStudio make({Duration doneTimeout = const Duration(seconds: 2)}) => MindStudio(
        stage: stage,
        state: state,
        permissions: MindPermissions(channel: permCh),
        platform: platform,
        tempDir: () async => tmp,
        clock: () => DateTime(2026, 10, 5, 14, 22, 33),
        doneTimeout: doneTimeout,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permCh, (call) async => 'true');
    tmp = Directory.systemTemp.createTempSync('studio_test');
    log = [];
    stage = _Stage(log);
    platform = _Platform(log);
    state = MindState();
    studio = make();
  });

  tearDown(() {
    studio.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permCh, null);
    try {
      tmp.deleteSync(recursive: true);
    } on Object {
      // temp ค้างไม่ใช่เหตุให้เทสต์แดง
    }
  });

  List<File> parts() => tmp
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.part'))
      .toList();

  group('เข้า/ออก', () {
    test('ยังไม่มีตัวเธอบนเวที = ไม่เข้า และบอกเหตุผล', () async {
      stage.isReady = false;
      expect(await studio.enter(), isFalse);
      expect(studio.active, isFalse);
      expect(studio.notice, state.s.studioNoAvatar);
      expect(log, isEmpty, reason: 'ไม่มีอะไรให้ถ่าย ก็ไม่ควรล็อกจอหรือซ่อนแถบระบบ');
    });

    test('เข้าแล้วล็อกจอ ซ่อนแถบระบบ เปิดจอลอยอัตโนมัติ · ออกแล้วคืนครบทุกอย่าง', () async {
      await studio.enter();
      expect(studio.active, isTrue);
      expect(log, containsAll(<String>[
        'stage.shot:face',
        'stage.studio:true',
        'stage.backdrop:null',
        'screen:true',
        'autoPip:true',
        'immersive:true',
      ]));

      log.clear();
      await studio.exit();
      expect(studio.active, isFalse);
      expect(log, containsAll(<String>[
        'stage.studio:false',
        'stage.backdrop:null',
        'autoPip:false',
        'screen:false',
        'immersive:false',
      ]), reason: 'จอที่ไม่ยอมดับหลังออกจากสตูดิโอ = แบตหมดโดยไม่รู้ตัว');
    });

    test('ฉากเขียวถูกจำไว้ และใช้ทันทีถ้าอยู่ในสตูดิโอ', () async {
      await studio.enter();
      log.clear();
      await studio.setBackdrop(StudioBackdrops.green);
      expect(state.studioBackdrop, StudioBackdrops.green);
      expect(log, contains('stage.backdrop:#00b140'));

      await studio.exit();
      log.clear();
      await studio.enter();
      expect(log, contains('stage.backdrop:#00b140'), reason: 'เข้ารอบหน้าต้องได้ฉากเดิม');
    });
  });

  group('จอลอย', () {
    test('เครื่องไม่ยอม = บอกผู้ใช้ ไม่เงียบ', () async {
      await studio.enter();
      platform.pipOk = false;
      expect(await studio.enterPip(), isFalse);
      expect(studio.notice, state.s.studioPipUnsupported);
    });

    test('ระยะเต็มตัวขอจอลอยแนวตั้งสูง ไม่งั้นหัวกับเท้าโดนตัด', () async {
      await studio.enter();
      await studio.setShot(MindMocapShot.full);
      await studio.enterPip();
      expect(log, contains('pip:9:16'));
    });

    test('ระบบบอกเข้า/ออกจอลอย แล้วสถานะตามทัน', () async {
      await studio.enter();
      platform.pip!(true);
      expect(studio.inPip, isTrue);
      platform.pip!(false);
      expect(studio.inPip, isFalse);
    });
  });

  group('อัดคลิป', () {
    test('ก้อนเรียงครบ = ไฟล์เดียวต่อกันถูกลำดับ ชื่อมีเวลา และไม่เหลือไฟล์ชั่วคราว', () async {
      await studio.enter();
      await studio.startRecording();
      expect(studio.rec, StudioRec.recording);

      stage.feed([1, 2]);
      stage.feed([3]);
      await studio.stopRecording();

      expect(platform.savedBytes, [1, 2, 3]);
      expect(log, contains('save:GigGok_20261005_142233.mp4:video/mp4'));
      expect(studio.rec, StudioRec.idle);
      expect(studio.notice, contains('Movies/GigGok/GigGok_20261005_142233.mp4'));
      expect(studio.notice, isNot(contains(state.s.studioRecGap)));
      expect(parts(), isEmpty, reason: 'คลิปหลายสิบเมกค้างใน temp ทุกครั้งที่อัด');
    });

    test('🔴 ออกจากสตูดิโอกลางการอัด = บันทึกก่อนออกเสมอ ไม่ทิ้งคลิป', () async {
      await studio.enter();
      await studio.startRecording();
      stage.feed([9, 9, 9]);

      await studio.exit();

      expect(platform.savedBytes, [9, 9, 9]);
      final saved = log.indexWhere((l) => l.startsWith('save:'));
      expect(saved, lessThan(log.indexOf('stage.studio:false')),
          reason: 'ปิดเวทีก่อนบันทึก = ก้อนสุดท้ายไม่มีวันมาถึง');
    });

    test('เวทีไม่ตอบตอนสั่งหยุด = ยังบันทึกเท่าที่ได้ และบอกว่าอาจขาด', () async {
      studio.dispose();
      studio = make(doneTimeout: const Duration(milliseconds: 50));
      stage.answersStop = false;
      await studio.enter();
      await studio.startRecording();
      stage.feed([4, 5]);
      await studio.stopRecording();

      expect(platform.savedBytes, [4, 5]);
      expect(studio.notice, contains(state.s.studioRecGap));
      expect(studio.rec, StudioRec.idle, reason: 'ค้างที่ "กำลังบันทึก" = ปุ่มอัดตายถาวร');
    });

    test('ก้อนข้ามลำดับ = บอกผู้ใช้ว่าคลิปอาจสะดุด', () async {
      await studio.enter();
      await studio.startRecording();
      stage.feed([1], seq: 0);
      stage.feed([2], seq: 2);
      await studio.stopRecording();
      expect(studio.notice, contains(state.s.studioRecGap));
    });

    test('ไม่ได้ภาพอะไรเลย = ไม่บันทึกไฟล์เปล่าลงแกลเลอรี', () async {
      await studio.enter();
      await studio.startRecording();
      await studio.stopRecording();
      expect(log.where((l) => l.startsWith('save:')), isEmpty);
      expect(studio.notice, contains(state.s.studioRecEmpty));
    });

    test('เครื่องอัดไม่ได้ = กลับไปพร้อมอัดใหม่ ไม่ค้าง และไม่เหลือไฟล์ชั่วคราว', () async {
      stage.startResult = const MindRecStart.failed('no-recorder');
      await studio.enter();
      await studio.startRecording();
      expect(studio.rec, StudioRec.idle);
      expect(studio.notice, state.s.studioRecFailed);
      expect(parts(), isEmpty);
      expect(stage.recordingSink, isNull);
    });

    test('กดอัดรัวสองครั้ง = เริ่มอัดครั้งเดียว', () async {
      await studio.enter();
      await Future.wait([studio.startRecording(), studio.startRecording()]);
      expect(log.where((l) => l.startsWith('stage.rec')), hasLength(1));
      await studio.stopRecording();
    });

    test('Android 9 ลงมายังไม่ได้สิทธิ์ไฟล์ = ขอแล้วลองบันทึกใหม่', () async {
      platform.answers.add(const StudioSave(needsPermission: true));
      await studio.enter();
      await studio.startRecording();
      stage.feed([7]);
      await studio.stopRecording();
      expect(log.where((l) => l.startsWith('save:')), hasLength(2));
      expect(studio.notice, contains('Movies/GigGok/'));
    });

    test('แอปพับลงกลางการอัด = หยุดแล้วบันทึก พร้อมบอกเหตุผล', () async {
      await studio.enter();
      await studio.startRecording();
      stage.feed([1]);
      studio.didChangeAppLifecycleState(AppLifecycleState.paused);
      for (var i = 0; i < 50 && studio.rec != StudioRec.idle; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(platform.savedBytes, [1]);
      expect(studio.notice, contains(state.s.studioRecBackground));
    });

    test('จอลอย (inactive) ไม่หยุดอัด — เวทียังวาดอยู่', () async {
      await studio.enter();
      await studio.startRecording();
      studio.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(studio.rec, StudioRec.recording);
      await studio.stopRecording();
    });

    test('ไฟล์ค้างจากรอบที่แอปตายกลางการอัด ถูกกวาดตอนเข้าสตูดิโอ', () async {
      File('${tmp.path}${Platform.pathSeparator}studio_1.part').writeAsBytesSync([1]);
      await studio.enter();
      for (var i = 0; i < 50 && parts().isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(parts(), isEmpty);
    });
  });

  group('รหัสสีฉากหลัง', () {
    test('ค่าเพี้ยนจากที่เก็บ = พื้นของแอป', () {
      expect(StudioBackdrops.parse(null), StudioBackdrops.app);
      expect(StudioBackdrops.parse('green'), StudioBackdrops.app);
      expect(StudioBackdrops.parse('#00B140'), '#00b140');
    });

    test('พิมพ์เองได้ทั้งมีและไม่มี # · ผิดรูปแบบ = null', () {
      expect(StudioBackdrops.fromInput('00ff00'), '#00ff00');
      expect(StudioBackdrops.fromInput(' #ABCDEF '), '#abcdef');
      expect(StudioBackdrops.fromInput('#12345'), isNull);
      expect(StudioBackdrops.fromInput('red'), isNull);
    });

    test('ส่งให้เวที: พื้นแอป = null (โปร่ง)', () {
      expect(StudioBackdrops.toStage(StudioBackdrops.app), isNull);
      expect(StudioBackdrops.toStage('#0047bb'), '#0047bb');
    });
  });
}
