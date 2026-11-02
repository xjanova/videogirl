/// ป้ายตัวถ่างกับอักษรไทย
///
/// เจอบนเครื่องจริง (v0.1.63): ป้ายในร้านและหัวการ์ดตั้งค่าที่ถ่างตัว สระบน สระล่าง และวรรณยุกต์
/// หลุดไปข้างหลังพยัญชนะ เพราะ Flutter ถ่างทีละ glyph
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/theme/tokens.dart';

void main() {
  test('ป้ายที่มีอักษรไทยไม่ถ่างตัว · ป้ายอังกฤษถ่างเหมือนเดิม · ตัวที่ไม่ได้ถ่างไม่แตะ', () {
    expect(MindType.fit(MindType.overline, 'ติดตั้งในเครื่อง').letterSpacing, 0);
    expect(MindType.fit(MindType.overline, 'แพ็กฟรีที่มากับแอป · FREE').letterSpacing, 0);
    expect(MindType.fit(MindType.overline, 'INSTALLED').letterSpacing, MindType.overline.letterSpacing);
    expect(MindType.fit(MindType.title, 'หัวข้อ'), same(MindType.title));
    expect(MindType.fit(MindType.overline, 'ร้าน').fontSize, MindType.overline.fontSize, reason: 'เปลี่ยนแค่ระยะถ่าง');
  });

  test('🔴 ป้ายตัวถ่างที่แสดงข้อความแปล ผ่าน MindType.fit ทุกที่', () {
    // Text(t.xxx / S.of(context).xxx, style: mindMono(...) หรือ MindType.overline...) ที่ไม่ผ่าน fit
    final bare = RegExp(r'Text\(\s*(t\.|S\.of\(context\)\.)[^;]*?style:\s*(mindMono\(|MindType\.overline)');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final m in bare.allMatches(f.readAsStringSync())) {
        // style ของ Text ตัวถัดไป ไม่ใช่ของตัวนี้
        if (m.group(0)!.indexOf('Text(', 5) >= 0) continue;
        offenders.add('${f.path}: ${m.group(0)!.split('\n').first.trim()}');
      }
    }
    expect(offenders, isEmpty);
  });
}
