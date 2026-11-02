/// จอไม่ดับระหว่างมายด์ใช้เครื่องแทน
///
/// เจ้าของ (v0.1.64): "ตอนมายด์ทำงาน หน้าจอต้องไม่ดับ" · จอดับเองใน 2 นาที แต่งานที่ต้องดูภาพจอยาวกว่านั้นได้ ·
/// จอดับกลางงาน = เครื่องล็อก เธอแตะต่อไม่ได้ · ตอนทำงานแอปอื่นอยู่หน้าจอ ธงจอค้างของหน้าต่างเราจึงไม่ช่วย ·
/// ต้องเป็น wake lock ระดับจอที่ถือตลอดงาน ต่อเวลาทุกขั้น และปล่อยตอนจบ
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('android/app/src/main/kotlin/com/xjanova/videogirl/hands/HandsService.kt').readAsStringSync();

  String body(String fun) {
    final start = src.indexOf('fun $fun(');
    expect(start, isNonNegative, reason: 'ไม่เจอ fun $fun');
    final open = src.indexOf('{', start);
    var depth = 0;
    for (var i = open; i < src.length; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}' && --depth == 0) return src.substring(open, i + 1);
    }
    fail('fun $fun ไม่ปิดวงเล็บ');
  }

  test('🔴 ถือ wake lock ระดับจอ · ไม่ปลุกจอที่ดับอยู่ · ปล่อยแล้วนับเวลาจอดับใหม่', () {
    final awake = body('keepAwake');
    expect(awake, contains('SCREEN_BRIGHT_WAKE_LOCK'));
    expect(awake, contains('ON_AFTER_RELEASE'));
    expect(awake, isNot(contains('ACQUIRE_CAUSES_WAKEUP')));
    // ไม่นับจำนวน + มีเวลาหมด = เรียกซ้ำคือต่อเวลา · Dart ค้างแล้วจอกลับมาดับเองได้
    expect(awake, contains('setReferenceCounted(false)'));
    expect(awake, contains('acquire(AWAKE_MS)'));
    // จำขั้นตอน = เจ้าของแตะจอเองอยู่แล้ว
    expect(awake, contains('if (!HandsControl.running) return'));
  });

  test('🔴 เริ่มงานถือจอ · ทุกขั้นต่อเวลา · จบงานปล่อย', () {
    expect(body('start'), contains('keepAwake('));
    expect(body('refresh'), contains('keepAwake('));
    expect(body('finish'), contains('letSleep()'));
    // end ทุกทาง (Dart สั่ง / หยุดค้าง 15 วิ) ผ่าน finish
    expect(body('end'), contains('finish(app)'));
  });
}
