import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/phone/call_session.dart';
import 'package:videogirl/phone/call_watch.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';

/// ตัวอย่างเสียง 16 บิตของคลื่นสี่เหลี่ยมที่แอมพลิจูดตามสั่ง
Uint8List _tone(double amplitude, {int samples = 800}) {
  final data = Int16List(samples);
  final peak = (amplitude * 32767).round();
  for (var i = 0; i < samples; i++) {
    data[i] = i.isEven ? peak : -peak;
  }
  return data.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('วัดระดับเสียง — ตัวชี้ขาดว่าเครื่องนี้ให้เธอฟังสายไหม', () {
    test('ความเงียบสนิทได้ศูนย์', () {
      expect(CallSession.levelOf(Uint8List(1024)), 0);
    });

    test('คลื่นเต็มสเกลได้ประมาณหนึ่ง', () {
      expect(CallSession.levelOf(_tone(1)), closeTo(1, .01));
    });

    test('ครึ่งสเกลได้ประมาณครึ่ง — ไม่ใช่ค่าที่ปัดจนแยกไม่ออกจากความเงียบ', () {
      expect(CallSession.levelOf(_tone(.5)), closeTo(.5, .01));
    });

    /// 🔴 นี่คือเส้นแบ่งจริงของทั้งฟีเจอร์
    ///
    /// เครื่องที่ไม่ยอมให้อัดเสียงระหว่างมีสายคืนไฟล์ที่ขนาดถูกต้องทุกประการ
    /// แต่ทุกตัวอย่างเป็นศูนย์ · ถ้าเส้นนี้ต่ำเกินไป สัญญาณรบกวนระดับ
    /// บิตสุดท้ายจะถูกนับเป็น "ได้ยินแล้ว" แล้วเราจะยิงค่าถอดเสียงทิ้ง
    /// ไปเรื่อย ๆ ตลอดสายโดยไม่มีวันได้อะไรกลับมา
    test('สัญญาณรบกวนระดับบิตสุดท้ายต้องต่ำกว่าเส้นเสียงพูด', () {
      final noise = Uint8List.fromList(
        List<int>.generate(1024, (i) => i.isEven ? 1 : 0),
      );
      expect(CallSession.levelOf(noise), lessThan(.012));
    });
  });

  group('ห่อ PCM เป็นไฟล์ WAV', () {
    final wav = CallSession.wavOf(_tone(.5, samples: 1600));

    test('มีหัว RIFF/WAVE ที่ปลายทางอ่านออก', () {
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    });

    test('ความยาวในหัวไฟล์ตรงกับข้อมูลจริง', () {
      final data = ByteData.sublistView(wav);
      // 3200 ไบต์ของตัวอย่าง + หัวไฟล์ 44 ไบต์
      expect(wav.length, 3244);
      expect(data.getUint32(4, Endian.little), wav.length - 8);
      expect(data.getUint32(40, Endian.little), 3200);
    });

    test('ประกาศเป็น PCM ช่องเดียว 16 บิต 16 kHz', () {
      final data = ByteData.sublistView(wav);
      expect(data.getUint16(20, Endian.little), 1, reason: 'PCM ไม่บีบอัด');
      expect(data.getUint16(22, Endian.little), 1, reason: 'ช่องเดียว');
      expect(data.getUint32(24, Endian.little), 16000);
      expect(data.getUint16(34, Endian.little), 16, reason: 'บิตต่อตัวอย่าง');
    });
  });

  group('หน้าจอสายขึ้นเมื่อไหร่', () {
    late List<MethodCall> calls;
    late Map<String, Object?> info;
    late CallWatch watch;
    late CallSession session;

    setUp(() {
      calls = [];
      info = {'live': false, 'mind': false, 'number': null, 'name': null};

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kSystemChannel, (call) async {
        calls.add(call);
        if (call.method == 'callInfo') return info;
        return true;
      });

      watch = CallWatch();
      session = CallSession(watch: watch, state: MindState());
    });

    tearDown(() {
      session.dispose();
      watch.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kSystemChannel, null);
    });

    test('ไม่มีสาย = ไม่ตัดหน้าจอ', () async {
      await session.start();
      expect(session.onStage, isFalse);
    });

    /// สายที่เจ้าของรับเองต้องไม่ถูกยึดจอ · เขากำลังคุยอยู่ ไม่ได้อยากดู
    /// ตัวเธอยกโทรศัพท์
    test('สายที่เจ้าของรับเอง = ไม่ตัดหน้าจอ', () async {
      info = {'live': true, 'mind': false, 'number': '0812345678'};
      await session.start();
      expect(session.live, isTrue);
      expect(session.onStage, isFalse);
    });

    test('สายที่เธอถือเอง = ตัดหน้าจอ พร้อมชื่อคนโทร', () async {
      info = {
        'live': true,
        'mind': true,
        'number': '0812345678',
        'name': 'คุณต้น',
      };
      await session.start();
      expect(session.onStage, isTrue);
      expect(session.who, 'คุณต้น');
    });

    /// 🔴 แทรกสายต้องหยุดเธอ**ทันที** ไม่ใช่รอให้ประโยคที่ค้างพูดจบ
    ///
    /// เจ้าของกดปุ่มนี้ตอนกำลังยกเครื่องขึ้นแนบหูพอดี · ถ้าเสียงเธอยังดัง
    /// ต่อได้อีกสองวินาที มันจะดังใส่หูเขาที่ระดับเสียงลำโพงเปิด
    test('แทรกสายแล้วสั่งหยุดเสียงก่อนโอนสายคืน', () async {
      info = {'live': true, 'mind': true, 'number': '0812345678'};
      await session.start();
      calls.clear();

      await session.bargeIn();

      final order = calls.map((c) => c.method).toList();
      expect(order, contains('callStopSpeak'));
      expect(order, contains('mindHandOver'));
      expect(order.indexOf('callStopSpeak'),
          lessThan(order.indexOf('mindHandOver')),
          reason: 'โอนสายคืนก่อนหยุดเสียง = เสียงเธอไปโผล่ที่หูฟัง');

      // จอยังเป็นจอสายอยู่ เพราะสายยังไม่วาง เจ้าของแค่ขอคุยเอง
      expect(session.onStage, isTrue);
      expect(session.turn, CallTurn.handedOver);
    });

    test('วางสายแล้วคืนเสียงให้เครื่อง ไม่ปล่อยค้าง', () async {
      info = {'live': true, 'mind': true, 'number': '0812345678'};
      await session.start();
      calls.clear();

      await session.hangUp();

      expect(calls.map((c) => c.method), contains('callDisconnect'));
      expect(calls.map((c) => c.method), contains('callEndAudio'),
          reason: 'ไม่คืนระดับเสียงที่เร่งไว้ = สายถัดไปดังสุดโดยไม่มีใครรู้');
      expect(session.onStage, isFalse);
    });

    test('พิมพ์ตอนไม่มีสาย ต้องไม่ยิงอะไรออกไป', () async {
      await session.start();
      calls.clear();
      await session.say('สวัสดีค่ะ');
      expect(calls, isEmpty);
    });
  });

  group('เสียงที่ไม่มีทางเกิดขึ้น', () {
    test('ก้อนข้อมูลสั้นกว่าหนึ่งตัวอย่างต้องไม่พัง', () {
      expect(CallSession.levelOf(Uint8List(1)), 0);
      expect(CallSession.levelOf(Uint8List(0)), 0);
    });

    test('WAV ของข้อมูลเปล่ายังเป็นไฟล์ที่ถูกต้อง', () {
      final wav = CallSession.wavOf(Uint8List(0));
      expect(wav.length, 44);
      expect(ByteData.sublistView(wav).getUint32(40, Endian.little), 0);
    });
  });
}
