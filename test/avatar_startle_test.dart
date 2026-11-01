import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/avatar/startle_cue.dart';

void main() {
  group('คำตอบแบบไหนทำให้เธอสะดุ้ง', () {
    test('ขึ้นต้นด้วยคำอุทาน', () {
      for (final reply in [
        'ว้าย! เกิดอะไรขึ้นคะ',
        'ว้ายยย ตกใจหมดเลย',
        '  อุ๊ย เมื่อกี้อะไรคะ',
        'อุ๊ยตาย! จริงเหรอคะ',
        'ตายแล้ว ลืมไปเลย',
        'แย่แล้วค่ะ',
        'Whoa, really?',
        'Oh no!',
      ]) {
        expect(startsStartled(reply), isTrue, reason: reply);
      }
    });

    test('แค่มีคำนี้กลางประโยค หรือกำลังปลอบ ไม่สะดุ้ง', () {
      for (final reply in [
        'ไม่ต้องตกใจนะคะ',
        'พี่บอกว่า ว้าย! แล้วหัวเราะ',
        'ตายแล้วเกิดใหม่ เป็นความเชื่อค่ะ',
        'Oh nothing, just checking.',
        'ได้เลยค่ะ',
        '',
      ]) {
        expect(startsStartled(reply), isFalse, reason: reply);
      }
    });
  });

  group('ท่าตกใจต่อครบทุกชั้น', () {
    final startle = File('assets/avatar/startle.js').readAsStringSync();
    final avatar = File('assets/avatar/avatar.js').readAsStringSync();

    test('ทำงานทับท่าเดิมหลัง idle ไม่ใช่คลิปที่ต้องมีไฟล์ .fbx', () {
      expect(startle, isNot(contains('.fbx\'')));
      final idleAt = avatar.indexOf('this.idle.apply(');
      final flinchAt = avatar.indexOf('this.startled.apply(');
      expect(idleAt, isNonNegative);
      expect(flinchAt, greaterThan(idleAt));
      // ก่อน vrm.update ไม่งั้นผมกับกระโปรงไม่สะบัดตาม
      expect(flinchAt, lessThan(avatar.indexOf('vrm.update(dt)')));
    });

    test('นั่งหรือถือโทรศัพท์อยู่ แขนต้องเบาลง ไม่งั้นมือไขว้หน้า', () {
      expect(avatar, contains('this.startled.apply(dt, armsFree ?'));
    });

    test('รอยยิ้มอัตโนมัติไม่ทับหน้าตกใจ · VRoid ยิ้มแล้วตาหรี่', () {
      expect(avatar, contains('!this.startled.active'));
    });

    test('สะดุ้งแค่ตอนเริ่ม alert ไม่ใช่ทุกครั้งที่สั่งอารมณ์ซ้ำ', () {
      expect(avatar, contains("this.mood === 'alert' && was !== 'alert'"));
    });

    test('Flutter เรียกได้', () {
      final html = File('assets/avatar/index.html').readAsStringSync();
      expect(RegExp(r'^  startle:', multiLine: true).hasMatch(html), isTrue);
      final view = File('lib/avatar/avatar_view.dart').readAsStringSync();
      expect(view, contains("_call('window.minde.startle()')"));
    });
  });
}
