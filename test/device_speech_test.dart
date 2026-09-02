/// ถอดเสียงในเครื่อง — ทางเดียวที่ไมค์ใช้ได้กับสมองในเครื่อง
///
/// จำลองฝั่งเนทีฟด้วยช่องปลอม จึงทดสอบได้ครบทุกเส้นทางโดยไม่ต้องมีเครื่อง
/// รวมถึงเส้นทางที่**เกิดยากบนเครื่องจริงแต่พังหนัก** เช่นระบบส่ง error
/// ตามหลังผลลัพธ์ ซึ่งจะเติม future ซ้ำแล้วกลายเป็นจอแดง
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/ai/device_speech.dart';

const _ch = MethodChannel('giggok/stt_test');

/// ฝั่งเนทีฟปลอม — จำคำสั่งที่ได้รับ และยิงเหตุการณ์กลับได้ตามสั่ง
class _FakeNative {
  _FakeNative({this.available = true});

  final bool available;
  final calls = <String>[];

  late DeviceSpeech speech;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ch, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'available' => available,
        _ => true,
      };
    });
    speech = DeviceSpeech.forTest(_ch);
  }

  /// ยิงเหตุการณ์จากเนทีฟกลับเข้า Dart เหมือนของจริง
  Future<void> emit(String event, [Map<String, Object?> data = const {}]) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        _ch.name,
        _ch.codec.encodeMethodCall(
          MethodCall('onStt', {...data, 'event': event}),
        ),
        (_) {},
      );

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ch, null);
  }
}

void main() {
  late _FakeNative native;

  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());
  tearDown(() => native.remove());

  test('เครื่องที่ทำได้ ตอบว่าทำได้ และจำคำตอบไว้', () async {
    native = _FakeNative()..install();

    expect(await native.speech.available(), isTrue);
    expect(await native.speech.available(), isTrue);
    expect(native.calls.where((c) => c == 'available').length, 1,
        reason: 'ค่านี้ไม่เปลี่ยนระหว่างแอปเปิดอยู่ ถามซ้ำทุกครั้งที่วาดจอ '
            'คือการยิงข้ามแพลตฟอร์มเปล่า ๆ');
  });

  test('ลืมคำตอบเดิมได้ ตอนผู้ใช้เพิ่งไปโหลดชุดภาษามา', () async {
    native = _FakeNative()..install();
    await native.speech.available();
    native.speech.forget();
    await native.speech.available();

    expect(native.calls.where((c) => c == 'available').length, 2);
  });

  test('เครื่องที่ทำไม่ได้ ตอบว่าทำไม่ได้', () async {
    native = _FakeNative(available: false)..install();
    expect(await native.speech.available(), isFalse);
  });

  test('ฟังแล้วได้ข้อความกลับมา', () async {
    native = _FakeNative()..install();

    final turn = native.speech.listen(locale: 'th-TH');
    await native.emit('listening');
    await native.emit('result', {'text': 'วันนี้มีนัดไหม'});

    expect(await turn, 'วันนี้มีนัดไหม');
    expect(native.speech.listening, isFalse);
  });

  test('ได้ยินระหว่างพูด ส่งต่อให้จอเห็นทันที', () async {
    native = _FakeNative()..install();
    final seen = <String>[];
    native.speech.onPartial = seen.add;

    final turn = native.speech.listen(locale: 'th-TH');
    await native.emit('partial', {'text': 'วันนี้'});
    await native.emit('partial', {'text': 'วันนี้มีนัด'});
    await native.emit('result', {'text': 'วันนี้มีนัดไหม'});
    await turn;

    expect(seen, ['วันนี้', 'วันนี้มีนัด'],
        reason: 'นี่คือสิ่งเดียวที่พิสูจน์ว่าไมค์ฟังออกจริงระหว่างยังพูดไม่จบ');
  });

  test('ระดับเสียงแปลงจากเดซิเบลเป็น 0..1', () async {
    native = _FakeNative()..install();
    final levels = <double>[];
    native.speech.onLevel = levels.add;

    final turn = native.speech.listen(locale: 'th-TH');
    await native.emit('level', {'rms': -2.0});
    await native.emit('level', {'rms': 10.0});
    await native.emit('level', {'rms': 4.0});
    await native.emit('result', {'text': 'ok'});
    await turn;

    expect(levels.first, 0.0);
    expect(levels[1], 1.0);
    expect(levels[2], closeTo(0.5, 0.01));
  });

  test('ค่าที่หลุดขอบต้องถูกบีบกลับเข้าช่วง ไม่ใช่ล้นออกไป', () async {
    native = _FakeNative()..install();
    final levels = <double>[];
    native.speech.onLevel = levels.add;

    final turn = native.speech.listen(locale: 'th-TH');
    await native.emit('level', {'rms': -50.0});
    await native.emit('level', {'rms': 99.0});
    await native.emit('result', {'text': 'ok'});
    await turn;

    expect(levels, [0.0, 1.0]);
  });

  test('ไม่ได้ยินอะไรเลย = ไม่ใช่ความผิดพลาดของระบบ', () async {
    native = _FakeNative()..install();

    final turn = native.speech.listen(locale: 'th-TH');
    await native.emit('result', {'text': '   '});

    expect(await turn, isNull);
    expect(native.speech.fault, SttFault.noMatch);
  });

  test('ยังไม่ได้โหลดชุดภาษา ต้องแยกออกจากความล้มเหลวอื่น', () async {
    native = _FakeNative()..install();

    final turn = native.speech.listen(locale: 'th-TH');
    await native.emit('error', {'code': 'language'});

    expect(await turn, isNull);
    expect(native.speech.fault, SttFault.language,
        reason: 'เป็นกรณีที่ผู้ใช้แก้เองได้ จึงต้องบอกให้ตรงว่าไปแก้ที่ไหน');
  });

  test('รหัสที่ไม่รู้จักตกเป็น failed ไม่ใช่พัง', () async {
    native = _FakeNative()..install();

    final turn = native.speech.listen(locale: 'th-TH');
    await native.emit('error', {'code': 'อะไรสักอย่างที่ยังไม่มีในวันนี้'});

    expect(await turn, isNull);
    expect(native.speech.fault, SttFault.failed);
  });

  test('🔴 error ที่มาตามหลัง result ต้องไม่ทำให้จอแดง', () async {
    native = _FakeNative()..install();

    final turn = native.speech.listen(locale: 'th-TH');
    await native.emit('result', {'text': 'ได้แล้ว'});
    // เครื่องบางรุ่นยิง error ตามมาทีหลัง · เติม future ซ้ำ = StateError
    // ที่ไม่มีใครรับ
    await native.emit('error', {'code': 'noMatch'});

    expect(await turn, 'ได้แล้ว');
  });

  test('กดฟังซ้ำระหว่างที่ยังฟังอยู่ ได้เทิร์นเดิม ไม่ใช่เทิร์นใหม่', () async {
    native = _FakeNative()..install();

    final first = native.speech.listen(locale: 'th-TH');
    final second = native.speech.listen(locale: 'th-TH');
    await native.emit('result', {'text': 'ครั้งเดียว'});

    expect(await first, 'ครั้งเดียว');
    expect(await second, 'ครั้งเดียว');
    expect(native.calls.where((c) => c == 'start').length, 1);
  });

  test('ยกเลิกแล้วเทิร์นต้องจบ ไม่ค้างรอสัญญาณที่ไม่มีวันมา', () async {
    native = _FakeNative()..install();

    final turn = native.speech.listen(locale: 'th-TH');
    await native.speech.cancel();

    expect(await turn, isNull);
    expect(native.speech.listening, isFalse);
  });

  test('ยังไม่ได้ฟัง สั่งหยุดต้องไม่ยิงอะไรลงเนทีฟ', () async {
    native = _FakeNative()..install();
    await native.speech.stop();
    expect(native.calls.contains('stop'), isFalse);
  });
}
