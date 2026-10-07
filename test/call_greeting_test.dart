/// คำทักตอนรับสายที่เจ้าของตั้งเอง — เธอพูดตามนั้นคำต่อคำ ไม่แต่งเพิ่ม
///
/// ที่มา: เจ้าของ "มายด์พูดเยอะไปตอนรับสาย สอนให้พูดแค่คำที่เราตั้ง (ตั้งค่าได้ เมื่อรับสาย
/// ให้พูดว่าอะไร เหมือนตอนโทรออกที่ตั้งได้)" · รายงาน 0.1.47: สาย 52 วิ เธอพูด 42.7 วิ
library;

import 'dart:io';

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

const _mine = 'สวัสดีค่ะ ฝากเรื่องไว้ได้เลยค่ะ';

class _Speech extends SpeechService {
  final said = <String>[];
  @override
  Future<Utterance> synthesize(String text, {required VoiceProfile profile}) async {
    said.add(text);
    return (bytes: Uint8List.fromList(List.filled(64, 7)), mime: 'audio/wav');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<MindState> loaded({_Speech? speech}) async {
    final s = MindState(speech: speech);
    addTearDown(s.dispose);
    await s.load();
    return s;
  }

  const th = S(AppLang.th);

  test('ไม่ได้ตั้ง = คำทักตั้งต้น (+ บอกว่าบันทึกเสียง)', () async {
    final s = await loaded();
    expect(s.callGreetingText, isEmpty);
    expect(s.callGreeting(), '${th.callGreeting} ${th.callRecordingNotice}');
  });

  test('🔴 ตั้งเองแล้ว = พูดตามนั้นคำต่อคำ · บันทึกเสียงอยู่ยังบอกคู่สายเสมอ', () async {
    final s = await loaded();
    s.setCallGreetingText(_mine);
    expect(s.callGreeting(), '$_mine ${th.callRecordingNotice}');

    s.setRecordCalls(false);
    expect(s.callGreeting(), _mine, reason: 'ปิดบันทึก = เหลือแค่คำที่เจ้าของตั้ง ไม่มีอะไรเติม');
  });

  test('คำทักพูดถึงการบันทึกเองแล้ว = ไม่ต่อประโยคบันทึกซ้ำ', () async {
    final s = await loaded();
    s.setCallGreetingText('สวัสดีค่ะ สายนี้มีการบันทึกนะคะ');
    expect(s.callGreeting(), 'สวัสดีค่ะ สายนี้มีการบันทึกนะคะ');
  });

  test('ช่องว่าง/ขึ้นบรรทัดถูกยุบ · ยาวเกินถูกตัด · ลบหมด = กลับไปคำทักตั้งต้น', () async {
    final s = await loaded();
    s.setCallGreetingText('  สวัสดีค่ะ\n\n  ฝากเรื่องได้ค่ะ  ');
    expect(s.callGreetingText, 'สวัสดีค่ะ ฝากเรื่องได้ค่ะ');

    s.setCallGreetingText('ก' * 500);
    expect(s.callGreetingText.length, MindState.callGreetingMax);

    s.setCallGreetingText('   ');
    expect(s.callGreetingText, isEmpty);
    expect(s.callGreeting(), startsWith(th.callGreeting));
  });

  test('จำไว้ข้ามการเปิดแอปใหม่', () async {
    final a = await loaded();
    a.setCallGreetingText(_mine);
    final b = await loaded();
    expect(b.callGreetingText, _mine);
  });

  test('คุยสด (Realtime) ทักด้วยคำที่ตั้ง', () async {
    final s = await loaded();
    s
      ..setCallGreetingText(_mine)
      ..setRecordCalls(false);
    expect(s.openRealtimeCall().greeting, _mine);
    expect(s.openRealtimeCall(outgoing: true).greeting, isEmpty, reason: 'โทรออก = รอปลายสายพูดก่อน');
  });

  test('ทางเดิมพูดคำที่ตั้งเข้าสายเป็นประโยคแรก', () async {
    final tmp = Directory.systemTemp.createTempSync('call_greet');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (call) async => tmp.path);
    m.setMockMethodCallHandler(const MethodChannel('com.llfbandit.record/messages'), (call) async => null);
    m.setMockMethodCallHandler(kSystemChannel, (call) async {
      if (call.method == 'callInfo') {
        return {'live': true, 'mind': true, 'speaker': true, 'number': '0812345678'};
      }
      // ไม่เปิดไมค์จริงในเทสต์นี้ · สนใจแค่ประโยคแรก
      if (call.method == 'micGranted') return false;
      return true;
    });
    final speech = _Speech();
    final s = await loaded(speech: speech);
    s
      ..setCallGreetingText(_mine)
      ..setRecordCalls(false);
    final watch = CallWatch();
    final call = CallSession(watch: watch, state: s);
    addTearDown(() async {
      await call.hangUp();
      call.dispose();
      watch.dispose();
      m.setMockMethodCallHandler(kSystemChannel, null);
      m.setMockMethodCallHandler(const MethodChannel('com.llfbandit.record/messages'), null);
      m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
      try {
        tmp.deleteSync(recursive: true);
      } on Object {
        // temp ค้างไม่ใช่เหตุให้เทสต์แดง
      }
    });

    await call.start();
    for (var i = 0; i < 300 && speech.said.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(speech.said.first, _mine);
  });

  test('prompt ของสายเข้าสั่งห้ามทัก/แนะนำตัวซ้ำ และให้ตอบทีละประโยคสั้น · สายออกไม่มีข้อห้ามทัก', () async {
    final s = await loaded();
    final incoming = s.callPrompt();
    expect(incoming, contains('ห้ามทักซ้ำหรือแนะนำตัวซ้ำ'));
    expect(incoming, contains('ประโยคเดียว'));
    expect(s.callPrompt(live: true), contains('ห้ามทักซ้ำหรือแนะนำตัวซ้ำ'));
  });
}
