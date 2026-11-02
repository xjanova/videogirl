/// แผนที่แอป · อะไรอยู่ตรงไหนในแอปไหน · เธอดูก่อนลงมือ จะได้ไม่เปิดผิดแอปหรือเดินหาเองทุกครั้ง
///
/// เจ้าของ: "ต้องทำแผนที่แอพไงที่บอกไว้ว่าอะไรอยู่ตรงไหน มายด์จะได้ไม่งง"
///
/// เข้ามาสองทาง: เจ้าของบอกเองในแชท (แท็ก `[[แผนที่แอป: …]]`) และเธอจดเองตอนทำงานในเครื่องเสร็จ
/// ("map" ใน done ของ PhoneAgent) · ที่เจ้าของบอกไว้ ที่เธอจดเองทับไม่ได้
///
/// 🔴 ที่เธอจดเองมาจากจอของแอปอื่น · ทุกทางที่ส่งเข้าโมเดลต้องผ่าน [_clean] และบอกว่าเป็นข้อมูล ไม่ใช่คำสั่ง
library;

import 'dart:convert';

/// ที่หนึ่งที่เธอจดมาจากงานในเครื่อง (ยังไม่ผ่าน [AppMap.put])
typedef PlaceNote = ({String app, String what, String where});

class AppPlace {
  const AppPlace({required this.app, required this.what, required this.where, required this.at, this.owner = false});

  /// ชื่อแอปตามที่เห็นใต้ไอคอน หรือที่เจ้าของเรียก
  final String app;

  /// สิ่งที่หา เช่น "ไฟห้องทำงาน"
  final String what;

  /// ทางไป เช่น "หน้าแรก › ห้อง ห้องทำงาน › การ์ด ห้องทำงาน › ปุ่มซ้าย"
  final String where;

  /// เจ้าของบอกเอง · false = เธอจดเองหลังทำงานสำเร็จ
  final bool owner;
  final DateTime at;

  Map<String, Object?> toJson() => {
        'app': app,
        'what': what,
        'where': where,
        if (owner) 'owner': true,
        'at': at.millisecondsSinceEpoch,
      };

  static AppPlace? fromJson(Object? v) {
    if (v is! Map) return null;
    String field(String k, int max) => AppMap._clean(v[k] is String ? v[k] as String : '', max);
    final app = field('app', AppMap.appChars);
    final what = field('what', AppMap.whatChars);
    final where = field('where', AppMap.whereChars);
    if (app.isEmpty || what.isEmpty || where.isEmpty) return null;
    final at = v['at'];
    return AppPlace(
      app: app,
      what: what,
      where: where,
      owner: v['owner'] == true,
      at: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class AppMap {
  AppMap([Iterable<AppPlace> places = const []]) : _places = [...places];

  static const maxPlaces = 150;
  static const appChars = 30;
  static const whatChars = 60;
  static const whereChars = 160;

  /// เธอจดเองได้กี่ที่ต่องาน · งานหนึ่งไม่ควรเขียนแผนที่ใหม่ทั้งแผ่น
  static const learnPerTask = 5;

  /// ใน prompt แชท · ใน prompt ของแต่ละขั้นในเครื่อง
  static const chatMax = 40;
  static const taskMax = 25;

  final List<AppPlace> _places;

  List<AppPlace> get places => List.unmodifiable(_places);
  bool get isEmpty => _places.isEmpty;

  static AppMap decode(String? raw) {
    if (raw == null || raw.isEmpty) return AppMap();
    try {
      final list = jsonDecode(raw);
      if (list is! List) return AppMap();
      return AppMap([for (final v in list) ?AppPlace.fromJson(v)].take(maxPlaces));
    } on FormatException {
      return AppMap();
    }
  }

  String encode() => jsonEncode([for (final p in _places) p.toJson()]);

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  /// บรรทัดเดียว ไม่มีรูปแท็ก ไม่มีตัวคั่นของแท็ก · ยาวไม่เกิน [max]
  static String _clean(String v, int max) {
    final t = v
        .replaceAll(RegExp(r'[\[\]|{}]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t.length <= max ? t : t.substring(0, max).trim();
  }

  bool _same(AppPlace p, String app, String what) => _norm(p.app) == _norm(app) && _norm(p.what) == _norm(what);

  /// จดที่ใหม่ หรือแก้ทางของที่เดิม (แอปกับสิ่งที่หาเดียวกัน) · เธอจดทับที่เจ้าของบอกไม่ได้ ·
  /// false = ไม่ได้เปลี่ยนอะไร
  bool put({
    required String app,
    required String what,
    required String where,
    required bool owner,
    required DateTime at,
  }) {
    final a = _clean(app, appChars), w = _clean(what, whatChars), p = _clean(where, whereChars);
    if (a.isEmpty || w.isEmpty || p.isEmpty) return false;
    final i = _places.indexWhere((x) => _same(x, a, w));
    final fresh = AppPlace(app: a, what: w, where: p, owner: owner, at: at);
    if (i >= 0) {
      final old = _places[i];
      if (old.owner && !owner) return false;
      if (old.where == p && old.owner == owner) return false;
      _places[i] = fresh;
      return true;
    }
    _places.add(fresh);
    // เต็ม = ทิ้งที่เธอจดเองที่เก่าสุดก่อน · ที่เจ้าของบอกทิ้งเมื่อไม่มีอย่างอื่นให้ทิ้งแล้ว
    while (_places.length > maxPlaces) {
      final pool = _places.where((x) => !x.owner).toList();
      final victims = pool.isEmpty ? _places : pool;
      var oldest = victims.first;
      for (final x in victims) {
        if (x.at.isBefore(oldest.at)) oldest = x;
      }
      _places.remove(oldest);
    }
    return true;
  }

  /// ลบ · [what] ว่าง = ทั้งแอป · คืนจำนวนที่ลบ
  int remove(String app, [String what = '']) {
    final a = _norm(_clean(app, appChars));
    final w = _norm(_clean(what, whatChars));
    if (a.isEmpty) return 0;
    final before = _places.length;
    _places.removeWhere((x) => _norm(x.app) == a && (w.isEmpty || _norm(x.what) == w));
    return before - _places.length;
  }

  static String _line(AppPlace p) => '- ${p.app}: ${p.what} → ${p.where}${p.owner ? '' : ' (you noted this)'}';

  /// สำหรับ prompt แชท · ที่เจ้าของบอกมาก่อน แล้วที่เธอจดล่าสุด · จัดกลุ่มตามแอป ·
  /// 🔴 ลำดับเปลี่ยนเฉพาะตอนแผนที่เปลี่ยน · prompt ที่เปลี่ยนทุกตาทำให้สมองในเครื่องเริ่ม session ใหม่
  String render({int max = chatMax}) {
    if (_places.isEmpty) return '';
    final keep = [..._places]..sort((x, y) {
        if (x.owner != y.owner) return x.owner ? -1 : 1;
        return y.at.compareTo(x.at);
      });
    return _grouped(keep.take(max));
  }

  /// สำหรับขั้นหนึ่งของงานในเครื่อง · ที่ของแอปบนจอและที่ตรงกับงานมาก่อน
  String forTask(String goal, String app, {int max = taskMax}) {
    if (_places.isEmpty) return '';
    final g = _norm(goal), on = _norm(app);
    int score(AppPlace p) {
      final a = _norm(p.app);
      var s = 0;
      if (on.isNotEmpty && (on.contains(a) || a.contains(on))) s += 4;
      if (a.isNotEmpty && g.contains(a)) s += 3;
      final w = _norm(p.what);
      if (w.isNotEmpty && g.contains(w)) {
        s += 3;
      } else if (_overlap(w, g) >= .5) {
        s += 2;
      }
      return s + (p.owner ? 1 : 0);
    }

    final ranked = [for (var i = 0; i < _places.length; i++) (i, score(_places[i]))]
      ..sort((x, y) => x.$2 != y.$2 ? y.$2.compareTo(x.$2) : x.$1.compareTo(y.$1));
    return _grouped([for (final r in ranked.take(max)) _places[r.$1]]);
  }

  /// ส่วนของ [w] ที่เจอใน [g] (นับเป็นคู่ตัวอักษร · ภาษาไทยไม่เว้นวรรคระหว่างคำ)
  static double _overlap(String w, String g) {
    if (w.length < 2) return 0;
    var hit = 0;
    for (var i = 0; i + 1 < w.length; i++) {
      if (g.contains(w.substring(i, i + 2))) hit++;
    }
    return hit / (w.length - 1);
  }

  static String _grouped(Iterable<AppPlace> places) {
    final groups = <String, List<AppPlace>>{};
    for (final p in places) {
      groups.putIfAbsent(_norm(p.app), () => []).add(p);
    }
    return [for (final g in groups.values) ...g.map(_line)].join('\n');
  }

  /// ที่เธอจดมาจากงานหนึ่ง · คืนจำนวนที่จดใหม่หรือแก้
  int learn(Iterable<PlaceNote> notes, DateTime at) {
    var n = 0;
    for (final x in notes.take(learnPerTask)) {
      if (put(app: x.app, what: x.what, where: x.where, owner: false, at: at)) n++;
    }
    return n;
  }
}
