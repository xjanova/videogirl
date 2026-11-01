/// ไมค์เบื้องหลังของมายด์ — ฝั่ง Dart ของ listen/ListenService.kt
///
/// เจ้าของ: "เธอต้องยังคงตอบพูดคุยกับฉันได้อยู่แม้หน้าจอจะไม่ใช่แอพแล้ว"
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/ai/mind_listen.dart';
import 'package:videogirl/ai/voice_chat.dart';

class _Fallback implements ChatMic {
  int opened = 0, closed = 0, disposed = 0;
  final ctl = StreamController<Uint8List>.broadcast();
  @override
  bool get survivesBackground => false;
  @override
  Future<Stream<Uint8List>> open() async {
    opened++;
    return ctl.stream;
  }

  @override
  Future<void> close() async => closed++;
  @override
  void dispose() => disposed++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('giggok/listen');
  late List<MethodCall> calls;
  late Object? Function(MethodCall) answer;

  setUp(() {
    calls = [];
    answer = (_) => true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (c) async {
      calls.add(c);
      return answer(c);
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  Future<void> fromAndroid(String method, [Object? args]) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  test('สถานะ: แปลงจาก Android ครบ · ไม่มีช่อง (เครื่องที่ไม่ใช่ Android) = ปิด ไม่ล้ม', () async {
    answer = (_) => {
          'running': true,
          'wake': true,
          'taught': true,
          'word': 'น้องมายด์',
          'sensitivity': 2,
          'paused': true,
          'replies': 3,
        };
    final st = await MindListen().status();
    expect(st.running && st.wake && st.taught && st.paused, isTrue);
    expect(st.word, 'น้องมายด์');
    expect(st.sensitivity, 2);
    expect(st.replies, 3);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    final off = await MindListen().status();
    expect(off.running, isFalse);
    expect(off.taught, isFalse);
  });

  test('🔴 Android ปฏิเสธ (ไม่มีสิทธิ์ไมค์ · เปิดบริการตอนไม่มีจอไม่ได้) = false ไม่ใช่ Exception', () async {
    answer = (_) => throw PlatformException(code: 'denied');
    final l = MindListen();
    expect(await l.open(), isFalse);
    expect(await l.teachStart(), isFalse);
    expect((await l.status()).running, isFalse);
  });

  test('เหตุการณ์จาก Android ถึงผู้ฟังถูกตัว', () async {
    final l = MindListen();
    var woke = 0, stopped = 0, changed = 0, lost = 0;
    final taught = <TeachEvent>[];
    l.onWake = () => woke++;
    l.onStop = () => stopped++;
    l.onChanged = () => changed++;
    l.onMicLost = () => lost++;
    l.onTeach = taught.add;
    await fromAndroid('wake');
    await fromAndroid('stop');
    await fromAndroid('wakeOff');
    await fromAndroid('micLost');
    await fromAndroid('teach', {'ok': false, 'count': 1, 'why': 'unlike'});
    await fromAndroid('teach', {'ok': true, 'count': 4, 'done': true});
    expect((woke, stopped, changed, lost), (1, 1, 2, 1));
    expect(taught.first.why, 'unlike');
    expect(taught.first.done, isFalse);
    expect(taught.last.done, isTrue);
  });

  test('🔴 ถามเครื่องล็อกไม่ได้ = นับว่าล็อก', () async {
    answer = (_) => false;
    expect(await MindListen().locked(), isFalse);
    answer = (_) => null;
    expect(await MindListen().locked(), isTrue);
  });

  test('เสียงขาน: นามสกุลตามชนิดไฟล์จริง', () async {
    await MindListen().setReplies([
      (bytes: Uint8List(3), mime: 'audio/wav'),
      (bytes: Uint8List(4), mime: 'audio/mpeg'),
    ]);
    final clips = (calls.single.arguments as Map)['clips'] as List;
    expect(clips.map((c) => (c as Map)['ext']), ['wav', 'mp3']);
  });

  group('ServiceChatMic', () {
    test('บริการขึ้น = อยู่เบื้องหลังได้ · ไม่แตะไมค์สำรอง', () async {
      final fb = _Fallback();
      final m = ServiceChatMic(listen: MindListen(), fallback: fb);
      expect(m.survivesBackground, isFalse);
      await m.open();
      expect(m.survivesBackground, isTrue);
      expect(fb.opened, 0);
      await m.close();
      expect(m.survivesBackground, isFalse);
      expect(fb.closed, 0);
      expect(calls.map((c) => c.method), ['open', 'close']);
    });

    test('🔴 บริการไม่ขึ้น = ใช้ไมค์สำรอง · ยังคุยบนจอได้ · ปิดครบทั้งสองฝั่ง', () async {
      answer = (c) => c.method == 'open' ? false : true;
      final fb = _Fallback();
      final m = ServiceChatMic(listen: MindListen(), fallback: fb);
      await m.open();
      expect(fb.opened, 1);
      expect(m.survivesBackground, isFalse);
      await m.close();
      expect(fb.closed, 1);
      expect(calls.last.method, 'close');
    });

    test('🔴 ถูกปลุกแล้วต่อเซิร์ฟเวอร์ไม่ติด (ยังไม่เคย open) · ปิดต้องคืนไมค์ให้บริการ', () async {
      final m = ServiceChatMic(listen: MindListen(), fallback: _Fallback());
      await m.close();
      expect(calls.single.method, 'close');
    });

    test('ปล่อยตัวสำรองตอน dispose', () {
      final fb = _Fallback();
      ServiceChatMic(listen: MindListen(), fallback: fb).dispose();
      expect(fb.disposed, 1);
    });
  });
}
