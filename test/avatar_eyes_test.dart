import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// เธอยืนหลับตาหลังคุยไปสักพัก
///
/// แอปตั้งอารมณ์ `happy` หลังทุกคำตอบแล้วไม่เคยคืน · `happy` ของ VRoid
/// (Fcl_ALL_Joy) ปิดตา · ฝั่ง avatar.js จึงต้องคลายอารมณ์เอง และยิ้มแบบตาเปิด
void main() {
  final avatar = File('assets/avatar/avatar.js').readAsStringSync();

  Map<String, double> linger() {
    final m = RegExp(r'const MOOD_LINGER = \{([^}]*)\}').firstMatch(avatar);
    expect(m, isNotNull, reason: 'หา MOOD_LINGER ใน avatar.js ไม่เจอ');
    return {
      for (final e in RegExp(r'(\w+):\s*([\d.]+)').allMatches(m!.group(1)!))
        e.group(1)!: double.parse(e.group(2)!),
    };
  }

  test('อารมณ์จากคำตอบคลายกลับเอง ส่วนอารมณ์ที่แอปถือเองไม่แตะ', () {
    final l = linger();
    expect(l.keys, containsAll(['happy', 'pleased']));
    for (final held in ['neutral', 'thinking', 'alert', 'calling', 'waiting']) {
      expect(l.containsKey(held), isFalse, reason: held);
    }
    // สั้นพอที่จะไม่ยืนหลับตา แต่ไม่หายทันทีที่พูดจบ
    expect(l['happy'], inInclusiveRange(3, 15));
  });

  test('นับเวลาเฉพาะตอนเงียบ แล้วคืนเป็น neutral', () {
    expect(avatar, contains('this.speaking || this.lip.speaking ? 0 : this._moodFor + dt'));
    expect(avatar, contains("if (this._moodFor > linger) this.setMood('neutral');"));
    // ตั้งอารมณ์ใหม่ = เริ่มนับใหม่
    final setMood = avatar.substring(avatar.indexOf('    setMood(m) {'));
    expect(setMood.substring(0, setMood.indexOf('\n    }')), contains('this._moodFor = 0;'));
  });

  test('ยิ้ม happy ไปลง relaxed ที่ตาเปิด · รุ่นที่ไม่มีก็ไม่ปิดตาสนิท', () {
    expect(avatar, contains('moodRelaxed = moodAmt;'));
    expect(avatar, contains("Math.max(warmName === 'relaxed' ? warmAmt : 0, moodRelaxed)"));
    expect(avatar, contains('Math.min(moodAmt, HAPPY_MAX)'));
    final share = double.parse(RegExp(r'const HAPPY_SHARE = ([\d.]+);').firstMatch(avatar)!.group(1)!);
    final max = double.parse(RegExp(r'const HAPPY_MAX = ([\d.]+);').firstMatch(avatar)!.group(1)!);
    expect(share, lessThan(0.5));
    expect(max, lessThan(0.75));
  });

  test('blink ยังเขียนหลังสุด ชนะทุกสีหน้า', () {
    final face = avatar.substring(avatar.indexOf('    _face(dt'));
    expect(face.indexOf("em.setValue('blink', this.idle.blink)"),
        greaterThan(face.indexOf('moodRelaxed)')));
  });
}
