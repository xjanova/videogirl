/// สวิตช์เปิดอยู่ต้องเห็นปุ่มกลม
///
/// เจอบนเครื่องจริง (v0.1.63): สวิตช์ "พักสายถามฉันได้" เปิดอยู่เป็นแถบชมพูล้วน ไม่มีปุ่มกลม ·
/// ธีมให้ track ตอนเปิดเป็นสีหลักของโหมด และ thumb ขาว · ใส่ activeThumbColor เป็นสีหลัก =
/// thumb สีเดียวกับ track · ใส่สีที่ activeTrackColor แทน
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('🔴 ไม่มีสวิตช์ไหนเปลี่ยนสี thumb ตอนเปิด (สีไปที่ track)', () {
    final offenders = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && f.readAsStringSync().contains('activeThumbColor')) f.path,
    ];
    expect(offenders, isEmpty);
  });
}
