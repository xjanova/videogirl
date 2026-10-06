/// สแกนข้อความ**ทุกคู่**ในตารางแปล ว่าฝั่งอังกฤษไม่มีภาษาไทยหลุด
///
/// เทสต์ i18n เดิมเช็กเป็นรายตัวที่ระบุชื่อไว้ · ไฟล์ข้อความใหม่ (สตูดิโอ ตั้งค่า
/// เสียงพรีเมียม คู่มือเอาคีย์) เพิ่มมาหลายร้อยคู่โดยไม่มีใครเข้าไปเพิ่มชื่อในรายการ
/// · ตัวนี้อ่านซอร์สของ `pick('ไทย', 'อังกฤษ')` / `_('ไทย', 'อังกฤษ')` ทั้งหมดเอง
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_voice.dart';

final _thai = RegExp(r'[฀-๿]');

/// อาร์กิวเมนต์ของการเรียกที่เริ่มหลังวงเล็บเปิดตำแหน่ง [start] · แยกด้วยจุลภาค
/// ที่อยู่นอกสตริงและนอกวงเล็บ
List<String> _args(String src, int start) {
  final args = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  var i = start;
  String? quote;
  while (i < src.length) {
    final c = src[i];
    if (quote != null) {
      buf.write(c);
      if (c == r'\' && i + 1 < src.length) {
        buf.write(src[i + 1]);
        i += 2;
        continue;
      }
      if (c == quote) quote = null;
      i++;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      buf.write(c);
    } else if (c == '(' || c == '[' || c == '{') {
      depth++;
      buf.write(c);
    } else if (c == ')' || c == ']' || c == '}') {
      if (depth == 0) {
        args.add(buf.toString());
        return args;
      }
      depth--;
      buf.write(c);
    } else if (c == ',' && depth == 0) {
      args.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
    i++;
  }
  return args;
}

/// เนื้อหาของสตริงทุกก้อนในอาร์กิวเมนต์ (ต่อกัน)
String _literal(String arg) {
  final out = StringBuffer();
  final lit = RegExp(r"'((?:[^'\\]|\\.)*)'|" r'"((?:[^"\\]|\\.)*)"');
  for (final m in lit.allMatches(arg)) {
    out.write(m.group(1) ?? m.group(2) ?? '');
  }
  return out.toString();
}

void main() {
  test('🔴 ทุกคู่ในตารางแปล: ฝั่งอังกฤษไม่มีอักษรไทย', () {
    final offenders = <String>[];
    var pairs = 0;
    for (final f in Directory('lib/i18n').listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      final call = RegExp(r"(?:\bpick|=>\s*_|\?\s*_|:\s*_)\(");
      for (final m in call.allMatches(src)) {
        final args = _args(src, m.end);
        if (args.length < 2) continue;
        final th = _literal(args[0]);
        final en = _literal(args[1]);
        if (th.isEmpty && en.isEmpty) continue;
        pairs++;
        if (_thai.hasMatch(en)) {
          final line = src.substring(0, m.start).split('\n').length;
          offenders.add('${f.uri.pathSegments.last}:$line  $en');
        }
      }
    }
    expect(pairs, greaterThan(500), reason: 'ตัวสแกนหาคู่ข้อความไม่เจอ — รูปแบบซอร์สเปลี่ยน');
    expect(offenders, isEmpty, reason: 'ฝั่งอังกฤษมีภาษาไทยหลุด:\n${offenders.join('\n')}');
  });

  test('คู่มือเอาคีย์: ภาษาอังกฤษไม่มีไทย และฝั่งไทยเป็นไทยจริง · จำนวนขั้นเท่ากัน', () {
    const th = S(AppLang.th);
    const en = S(AppLang.en);
    final guides = {
      'OpenAI': (th.keyGuideOpenAi, en.keyGuideOpenAi),
      'Gemini': (th.keyGuideGemini, en.keyGuideGemini),
      'ElevenLabs': (th.keyGuideElevenLabs, en.keyGuideElevenLabs),
      'Azure': (th.keyGuideAzure, en.keyGuideAzure),
    };
    for (final g in guides.entries) {
      final (t, e) = g.value;
      expect(t.length, e.length, reason: '${g.key}: สองภาษามีจำนวนขั้นไม่เท่ากัน');
      expect(t.every(_thai.hasMatch), isTrue, reason: '${g.key}: ฝั่งไทยมีขั้นที่ลืมแปล');
      expect(e.any(_thai.hasMatch), isFalse, reason: '${g.key}: ฝั่งอังกฤษมีไทยหลุด');
    }
  });
}
