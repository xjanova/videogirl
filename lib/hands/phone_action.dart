/// หนึ่งขั้นที่เธอเลือกทำ · อ่านจาก JSON บรรทัดเดียวที่สมองตอบมา
library;

import 'dart:convert';

import 'app_map.dart';

class PhoneAction {
  const PhoneAction(
    this.kind, {
    this.id,
    this.text = '',
    this.dir = '',
    this.name = '',
    this.why = '',
    this.risky = false,
    this.summary = '',
    this.time = '',
    this.title = '',
    this.start = '',
    this.end = '',
    this.location = '',
    this.to = '',
    this.subject = '',
    this.body = '',
    this.x,
    this.y,
    this.what = '',
    this.places = const [],
  });

  /// ชนิดที่รู้จัก · อย่างอื่น = อ่านไม่ออก
  static const kinds = {
    'tap',
    'long_press',
    'drag',
    'type',
    'submit',
    'scroll',
    'back',
    'home',
    'recents',
    'notifications',
    'open_app',
    'wait',
    'set_alarm',
    'add_event',
    'email',
    'ask_owner',
    'routine',
    'look',
    'tap_at',
    'done',
    'fail',
  };

  // คำที่สมองบางตัวใช้แทนชื่อจริง
  static const _alias = {
    'click': 'tap',
    'press': 'tap',
    'touch': 'tap',
    'longpress': 'long_press',
    'long_click': 'long_press',
    'move': 'drag',
    'drag_and_drop': 'drag',
    'input': 'type',
    'type_text': 'type',
    'write': 'type',
    'enter': 'submit',
    'search': 'submit',
    'swipe': 'scroll',
    'open': 'open_app',
    'launch': 'open_app',
    'alarm': 'set_alarm',
    'event': 'add_event',
    'compose_email': 'email',
    'ask': 'ask_owner',
    'macro': 'routine',
    'replay': 'routine',
    'screenshot': 'look',
    'see': 'look',
    'look_at_screen': 'look',
    'tap_xy': 'tap_at',
    'click_at': 'tap_at',
    'tap_point': 'tap_at',
    'finish': 'done',
    'complete': 'done',
    'finished': 'done',
    'give_up': 'fail',
    'failed': 'fail',
    'stop': 'fail',
  };

  final String kind;
  final int? id;
  final String text;
  final String dir;
  final String name;
  final String why;
  final bool risky;

  /// done / fail = สรุปถึงเจ้าของ · ask_owner = คำถามถึงเจ้าของ
  final String summary;
  final String time;
  final String title;
  final String start;
  final String end;
  final String location;
  final String to;
  final String subject;
  final String body;

  /// tap_at · จุดบนภาพจอที่แนบไป (พิกเซลของภาพ) · [PhoneAgent] แปลงเป็นพิกเซลจริงบนจอก่อนส่งต่อ
  final int? x;
  final int? y;

  /// tap_at · เธอบอกว่าจุดนั้นคืออะไร · ใช้ถามเจ้าของและให้ [PhonePolicy] ดูคำเสี่ยง
  final String what;

  /// done · ที่ที่เธอจดไว้ในแผนที่แอป ("map") · ใช้เมื่องานจบสำเร็จเท่านั้น
  final List<PlaceNote> places;

  /// ลายเซ็นไว้จับว่าเธอทำขั้นเดิมซ้ำ ๆ
  String get signature => '$kind|${id ?? ''}|$text|$dir|$name|$to|${x ?? ''},${y ?? ''}';

  /// ขั้นเดิมที่จุดใหม่ (แปลงจากพิกเซลของภาพเป็นพิกเซลของจอ)
  PhoneAction at(int nx, int ny) => PhoneAction(kind, why: why, risky: risky, x: nx, y: ny, what: what);

  /// อ่านวัตถุ JSON ก้อนแรกในคำตอบ · รับ ```json …``` และข้อความนำหน้า · ไม่ได้ = null
  static PhoneAction? parse(String reply) {
    final raw = _firstObject(reply);
    if (raw == null) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final Map<Object?, Object?> m = decoded;
    String str(String k) {
      final v = m[k];
      if (v == null) return '';
      return (v is String ? v : '$v').trim();
    }

    var kind = (str('do').isNotEmpty ? str('do') : str('action')).toLowerCase().replaceAll(' ', '_');
    kind = _alias[kind] ?? kind;
    if (!kinds.contains(kind)) return null;
    // 1e400 / "Infinity" / "NaN" = ไม่ใช่ตัวเลข (round/toInt โยน error ทำงานพัง)
    int? whole(String k) {
      final v = m[k] is num ? m[k]! as num : double.tryParse(str(k));
      return v != null && v.isFinite ? v.round() : null;
    }

    final idRaw = m['id'];
    final id = idRaw is num ? (idRaw.isFinite ? idRaw.toInt() : null) : int.tryParse(str('id'));
    final riskyRaw = m['risky'];
    String first(List<String> keys) {
      for (final k in keys) {
        final v = str(k);
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    return PhoneAction(
      kind,
      id: id,
      text: str('text'),
      dir: str('dir').toLowerCase(),
      name: first(const ['name', 'app', 'routine']),
      why: str('why'),
      risky: riskyRaw == true || '$riskyRaw'.toLowerCase() == 'true',
      summary: first(const ['summary', 'question', 'message', 'reason']),
      time: str('time'),
      title: str('title'),
      start: str('start'),
      end: str('end'),
      location: str('location'),
      to: str('to'),
      subject: str('subject'),
      body: str('body'),
      x: whole('x'),
      y: whole('y'),
      what: first(const ['what', 'target', 'label']),
      places: kind == 'done' ? _places(m['map']) : const [],
    );
  }

  static List<PlaceNote> _places(Object? raw) {
    if (raw is! List) return const [];
    String field(Map<Object?, Object?> v, String k) => v[k] is String ? (v[k]! as String).trim() : '';
    return [
      for (final v in raw.take(AppMap.learnPerTask))
        if (v is Map) (app: field(v, 'app'), what: field(v, 'what'), where: field(v, 'where')),
    ];
  }

  /// ก้อน `{…}` แรกที่ปีกกาครบคู่ (ไม่นับปีกกาในสตริง)
  static String? _firstObject(String s) {
    final start = s.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
        continue;
      }
      if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return s.substring(start, i + 1);
      }
    }
    return null;
  }
}
