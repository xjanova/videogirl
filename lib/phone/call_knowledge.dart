/// ข้อมูลที่เจ้าของให้น้องมายใช้ตอบคนโทร — พิมพ์เอง หรือนำเข้าจากไฟล์
///
/// เจ้าของ: "ให้พร้อมข้อมูลหรืออัพโหลดไฟล์ที่มายด์จะใช้ตอบ ได้แค่ไหนไว้ ห้ามตอบอะไรไว้ได้"
///
/// 🔴 ทุกอย่างในนี้**คนโทรอาจได้ยิน** · ไม่ใช่ความจำส่วนตัว · เจ้าของเลือกเองว่าจะให้คนนอกรู้อะไร
/// (prompt ของสายยังไม่มีข้อมูลส่วนตัวอื่นของเจ้าของเหมือนเดิม — ดู MindState.callPrompt)
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

import '../system/permissions.dart';

abstract final class CallKnowledge {
  /// เพดานข้อความที่ส่งเข้า prompt ของสาย · ยาวกว่านี้คุยสดช้าลงและแพงขึ้นทุกตา
  static const maxChars = 8000;

  /// เพดานรายการ "ห้ามตอบ"
  static const maxNoGoChars = 1500;

  /// ไฟล์ที่อ่านได้ · PDF ไม่รองรับ (ต้องใช้ตัวอ่าน PDF ทั้งก้อน) — คัดลอกข้อความมาวางแทน
  static const _textExt = {'txt', 'md', 'markdown', 'csv', 'tsv', 'json', 'text'};

  /// ยุบบรรทัดว่างซ้อน ตัดหัวท้าย และตัดที่เพดาน
  static String clean(String v, {int max = maxChars}) {
    final t = v
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return t.length > max ? t.substring(0, max) : t;
  }

  /// ไบต์ของไฟล์ → ข้อความ · null = ไม่ใช่ไฟล์ที่อ่านได้
  static String? textOf(String name, Uint8List bytes) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (ext == 'docx') return _docx(bytes);
    if (ext.isNotEmpty && !_textExt.contains(ext)) return null;
    var t = utf8.decode(bytes, allowMalformed: true);
    if (t.startsWith('﻿')) t = t.substring(1);
    // ไฟล์ที่ไม่ใช่ข้อความจริง (ไบนารีที่ตั้งชื่อ .txt) มีตัวอักษรที่ถอดไม่ได้เต็มไปหมด
    final bad = '�'.allMatches(t).length;
    if (t.isNotEmpty && bad > t.length ~/ 20) return null;
    return t;
  }

  /// Word (.docx) = zip ของ XML · ข้อความอยู่ใน `<w:t>` ของ word/document.xml · ย่อหน้า = `</w:p>`
  static String? _docx(Uint8List bytes) {
    try {
      final zip = ZipDecoder().decodeBytes(bytes);
      final doc = zip.findFile('word/document.xml');
      if (doc == null) return null;
      final xml = utf8.decode(doc.content as List<int>, allowMalformed: true);
      final text = xml
          .replaceAll(RegExp(r'</w:p>'), '\n')
          .replaceAll(RegExp(r'<w:tab/>'), '\t')
          .replaceAll(RegExp(r'<w:br/>'), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&apos;', "'")
          .replaceAll('&amp;', '&');
      return text;
    } on Object {
      return null;
    }
  }

  /// เปิดตัวเลือกไฟล์ของระบบ · null = ยกเลิก · '' = อ่านไม่ได้ (ชนิดไฟล์ไม่รองรับ / ใหญ่เกิน / ว่าง)
  static Future<String?> pick({MethodChannel? channel}) async {
    final Map<Object?, Object?>? got;
    try {
      got = await (channel ?? kSystemChannel).invokeMethod<Map<Object?, Object?>>('pickTextFile');
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return null;
    }
    if (got == null) return null;
    final bytes = got['bytes'];
    if (bytes is! Uint8List) return '';
    final text = textOf('${got['name'] ?? ''}', bytes);
    return text == null ? '' : clean(text);
  }
}
