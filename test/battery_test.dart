import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ประหยัดแบต — ของที่ทำงานตลอดเวลาที่แอปเปิดหรือรอฟังอยู่
void main() {
  final avatar = File('assets/avatar/avatar.js').readAsStringSync();
  final page = File('assets/avatar/index.html').readAsStringSync();
  final listen = File(
          'android/app/src/main/kotlin/com/xjanova/videogirl/listen/ListenService.kt')
      .readAsStringSync();

  group('เวทีวาดช้าลงตอนเธอยืนเฉย ๆ', () {
    test('ข้าม vsync ก่อนวาด · นับ vsync ไม่ใช่สะสมเวลา', () {
      final loop = avatar.substring(avatar.indexOf('    _loop(now'));
      final body = loop.substring(0, loop.indexOf('\n    }\n'));
      expect(body.indexOf('if (this._skip(now)) return;'),
          lessThan(body.indexOf('this._frame()')));
      // rAF ต้องต่อคิวก่อนข้าม ไม่งั้นลูปหยุดตายตั้งแต่เฟรมแรกที่ข้าม
      expect(body.indexOf('requestAnimationFrame(this._loop)'),
          lessThan(body.indexOf('this._skip(now)')));
      expect(avatar, contains('if (++this._vCount < every) return true;'));
    });

    test('ตอนพูด ทำท่า เชิดหุ่น อัดคลิป สตูดิโอ ตกใจ = วาดเต็ม', () {
      final busy = avatar.substring(avatar.indexOf('    _busy(now) {'));
      final body = busy.substring(0, busy.indexOf('\n    }\n'));
      for (final need in [
        'this.speaking',
        'this.lip.speaking',
        'this.lip.babble',
        'this.puppet',
        'this.studio',
        'this._recording',
        'this.startled?.active',
        'this.motion?.gesture',
        'now - this._wakeAt < IDLE_AFTER_MS',
      ]) {
        expect(body, contains(need), reason: need);
      }
    });

    test('อัตราพักไม่ต่ำจนท่าหายใจกระตุก', () {
      final idle = double.parse(RegExp(r'const IDLE_FPS = (\d+);').firstMatch(avatar)!.group(1)!);
      final busy = double.parse(RegExp(r'const BUSY_FPS = (\d+);').firstMatch(avatar)!.group(1)!);
      expect(idle, inInclusiveRange(24, 30));
      expect(busy, greaterThanOrEqualTo(50));
    });

    test('แตะจอหรือแอปสั่งอะไรมา = ตื่นเต็มอัตรา', () {
      expect(avatar, contains("for (const ev of ['pointerdown', 'pointermove', 'touchstart', 'wheel'])"));
      expect(page, contains('window.minde[name] = (...args) => { avatar?.wake?.(); return fn(...args); };'));
      final setMood = avatar.substring(avatar.indexOf('    setMood(m) {'));
      expect(setMood.substring(0, setMood.indexOf('\n    }')), contains('this.wake();'));
    });

    test('จอความละเอียดสูงไม่เปิด MSAA', () {
      expect(avatar, contains('antialias: dpr < 1.75'));
    });
  });

  test('ถามสถานะกล้องเชิดหุ่นถี่เฉพาะตอนกล้องทำงาน', () {
    expect(page, isNot(contains('}, 150);')));
    expect(page, contains("setTimeout(watchMocap, busy ? 150 : 1000);"));
  });

  test('รอคำเรียกอ่านไมค์ทีละ 100ms · คุยสดยังทีละ 20ms', () {
    expect(listen, contains('private const val READ_WATCH = RATE / 10'));
    expect(listen, contains('rec!!.read(buf, 0, if (m == Mode.STREAM) READ else READ_WATCH)'));
    expect(listen, contains('val buf = ShortArray(READ_WATCH)'));
  });
}
