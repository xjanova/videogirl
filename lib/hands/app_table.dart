/// ตารางแอปในเครื่องของเธอ · หมวด ลำดับ ชื่อเรียก และรู้เองว่าอะไรเข้าอะไรออก
///
/// เจ้าของ: "ทำตารางไว้ในฐานข้อมูลได้เพื่อใช้ เรียกแอพที่ต้องการได้ไวขึ้น การเอาเข้าเอาออกเธอต้องรู้ได้เอง"
///
/// แอปหลังบ้านรับข่าวติดตั้ง/ถอนไม่ได้ (Android ตัด manifest receiver ของเรื่องนี้) ·
/// รู้จากการเทียบรายการในเครื่องกับตารางตอนเปิดแอปและระหว่างคุย ([sync])
///
/// 🔴 ชื่อแอปคือข้อความจากคนอื่น · ใครตั้งชื่อแอปว่า `[[ทำในเครื่อง: …]]` ก็ได้ ·
/// ทุกทางที่ส่งชื่อเข้าโมเดลต้องผ่าน [_one]
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../store/mind_db.dart';
import '../system/permissions.dart';
import 'hands_tag.dart';

/// หนึ่งแถวของตาราง `apps`
class AppRow {
  AppRow({
    required this.pkg,
    required this.label,
    required this.category,
    required this.addedAt,
    this.ownCategory = false,
    this.rank,
    this.aliases = const [],
    this.opens = 0,
    this.lastOpen,
    this.noticedAt,
    this.removedAt,
  });

  final String pkg;
  String label;
  String category;

  /// เจ้าของ (หรือเธอตามคำสั่ง) ตั้งเอง · เดาใหม่ทับไม่ได้
  bool ownCategory;
  int? rank;
  List<String> aliases;
  int opens;
  DateTime? lastOpen;
  final DateTime addedAt;

  /// เห็นว่าเพิ่งเข้าหรือเพิ่งออกตอนไหน · ติดตั้งมาก่อนรู้จักกัน = null
  DateTime? noticedAt;
  DateTime? removedAt;

  bool get gone => removedAt != null;

  Map<String, Object?> toDb() => {
        'pkg': pkg,
        'label': label,
        'category': category,
        'own_category': ownCategory ? 1 : 0,
        'rank': rank,
        'aliases': aliases.join('\n'),
        'opens': opens,
        'last_open': lastOpen?.millisecondsSinceEpoch,
        'added_at': addedAt.millisecondsSinceEpoch,
        'noticed_at': noticedAt?.millisecondsSinceEpoch,
        'removed_at': removedAt?.millisecondsSinceEpoch,
      };

  static AppRow fromDb(Map<String, Object?> m) {
    DateTime? at(String k) {
      final v = m[k];
      return v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    }

    final aliases = (m['aliases'] as String? ?? '').split('\n').where((a) => a.isNotEmpty).toList();
    return AppRow(
      pkg: m['pkg']! as String,
      label: m['label']! as String,
      category: m['category']! as String,
      ownCategory: m['own_category'] == 1,
      rank: m['rank'] as int?,
      aliases: aliases,
      opens: m['opens'] as int? ?? 0,
      lastOpen: at('last_open'),
      addedAt: at('added_at') ?? DateTime.fromMillisecondsSinceEpoch(0),
      noticedAt: at('noticed_at'),
      removedAt: at('removed_at'),
    );
  }
}

typedef AppChanges = ({List<AppRow> added, List<AppRow> removed});

class AppTable {
  AppTable({MethodChannel? channel, DateTime Function()? clock, MindDb? Function()? db})
      : _ch = channel ?? kSystemChannel,
        _clock = clock ?? DateTime.now,
        _db = db ?? (() => MindDb.current);

  final MethodChannel _ch;
  final DateTime Function() _clock;
  final MindDb? Function() _db;

  final _rows = <String, AppRow>{};
  bool _loaded = false;
  Future<AppChanges>? _syncing;

  static const maxAliases = 8;
  static const nameChars = 30;

  /// ข่าวแอปเข้าออกอยู่ใน prompt นานเท่านี้
  static const newsFor = Duration(days: 7);

  /// ดึงจากฐานเมื่อฐานเปิดแล้วเท่านั้น · เปิดแอปครั้งแรกตารางอาจมาก่อนฐาน
  Future<void> _load() async {
    final db = _db();
    if (_loaded || db == null) return;
    try {
      final saved = await db.allApps();
      if (_rows.isEmpty) {
        for (final m in saved) {
          final r = AppRow.fromDb(m);
          _rows[r.pkg] = r;
        }
      }
      _loaded = true;
    } on Object catch (e) {
      debugPrint('ตารางแอป: อ่านจากฐานไม่ได้ — ${e.runtimeType}');
    }
  }

  Future<void> _save(Iterable<AppRow> rows) async {
    final list = [for (final r in rows) r.toDb()];
    if (list.isEmpty) return;
    try {
      await _db()?.putApps(list);
    } on Object catch (e) {
      debugPrint('ตารางแอป: เก็บลงฐานไม่ได้ — ${e.runtimeType}');
    }
  }

  /// เทียบรายการในเครื่องกับตาราง · เรียกซ้อนกันได้ ใช้รอบเดียวกัน
  Future<AppChanges> sync() => _syncing ??= _sync().whenComplete(() => _syncing = null);

  Future<AppChanges> _sync() async {
    final AppChanges none = (added: const [], removed: const []);
    await _load();
    Object? raw;
    try {
      raw = await _ch.invokeMethod<Object?>('installedApps');
    } on Object catch (e) {
      debugPrint('ตารางแอป: อ่านรายการแอปไม่ได้ — ${e.runtimeType}');
    }
    // 🔴 รายการว่าง = อ่านไม่ได้ ไม่ใช่ถอดทุกแอป · ไม่กันคือหมวดและชื่อเรียกหายทั้งตาราง
    final list = raw is List ? raw.whereType<Map>().toList() : const <Map>[];
    if (list.isEmpty) return none;
    final now = _clock();
    // ตารางเปล่า = เพิ่งรู้จักเครื่องนี้ · ทุกแอปไม่ใช่ของใหม่
    final firstLook = _rows.isEmpty;
    final added = <AppRow>[], removed = <AppRow>[], changed = <AppRow>[];
    final seen = <String>{};
    for (final m in list) {
      final pkg = m['pkg'];
      if (pkg is! String || pkg.isEmpty) continue;
      seen.add(pkg);
      final label = m['label'] is String && (m['label'] as String).isNotEmpty ? m['label'] as String : pkg;
      final guess = AppWords.guess(pkg, label, m['category'] is String ? m['category'] as String : '',
          blocked: m['blocked'] == true);
      final row = _rows[pkg];
      if (row == null) {
        final installed = m['installed'];
        final fresh = AppRow(
          pkg: pkg,
          label: label,
          category: guess,
          addedAt: installed is int && installed > 0 ? DateTime.fromMillisecondsSinceEpoch(installed) : now,
          noticedAt: firstLook ? null : now,
        );
        _rows[pkg] = fresh;
        changed.add(fresh);
        if (!firstLook) added.add(fresh);
        continue;
      }
      var touched = false;
      if (row.gone) {
        // ลงกลับมา · หมวดและชื่อเรียกที่ตั้งไว้ยังอยู่
        row
          ..removedAt = null
          ..noticedAt = now;
        added.add(row);
        touched = true;
      }
      if (row.label != label) {
        row.label = label;
        touched = true;
      }
      if (!row.ownCategory && row.category != guess) {
        row.category = guess;
        touched = true;
      }
      if (touched) changed.add(row);
    }
    for (final row in _rows.values) {
      if (seen.contains(row.pkg) || row.gone) continue;
      row
        ..removedAt = now
        ..noticedAt = now;
      removed.add(row);
      changed.add(row);
    }
    await _save(changed);
    return (added: added, removed: removed);
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  /// แถวที่ชื่อนี้หมายถึง · ไม่แน่ใจ = null แล้วให้ตัวหาแอปฝั่ง Android ตอบพร้อมตัวเลือก
  AppRow? find(String name) {
    final q = _norm(name);
    if (q.isEmpty) return null;
    final live = [for (final r in _rows.values) if (!r.gone) r];
    bool named(AppRow r, bool Function(String) test) => test(_norm(r.label)) || r.aliases.any((a) => test(_norm(a)));
    final exact = live.where((r) => r.pkg == name.trim() || named(r, (n) => n == q)).toList();
    final pools = [
      exact,
      live.where((r) => named(r, (n) => n.startsWith(q))).toList(),
      if (q.length >= 3) live.where((r) => named(r, (n) => n.contains(q))).toList(),
    ];
    for (final pool in pools) {
      if (pool.isEmpty) continue;
      pool.sort((a, b) => b.opens.compareTo(a.opens));
      // เท่ากันทุกแถว = เดา · เปิดผิดแอปแย่กว่าถามกลับ
      return pool.length == 1 || pool[0].opens > pool[1].opens ? pool[0] : null;
    }
    return null;
  }

  /// เปิดสำเร็จ · นับไว้เรียงลำดับ และจำคำที่เจ้าของเรียกแอปนี้
  Future<void> noteOpened(String pkg, {String said = ''}) async {
    await _load();
    final row = _rows[pkg];
    if (row == null) return;
    row
      ..opens += 1
      ..lastOpen = _clock();
    final word = _clean(said);
    if (word.isNotEmpty && word != pkg && _norm(word) != _norm(row.label)) _addAlias(row, word);
    await _save([row]);
  }

  void _addAlias(AppRow row, String word) {
    if (row.aliases.any((a) => _norm(a) == _norm(word))) return;
    row.aliases = [word, ...row.aliases].take(maxAliases).toList();
  }

  Future<void> setCategory(String pkg, String category) async {
    final row = _rows[pkg];
    if (row == null) return;
    row
      ..category = category
      ..ownCategory = true;
    await _save([row]);
  }

  /// ลำดับภายในหมวด · ที่นั่งซ้ำ = แถวเดิมและแถวหลังจากนั้นขยับลงหนึ่ง
  Future<void> setRank(String pkg, int rank) async {
    final row = _rows[pkg];
    if (row == null) return;
    final peers = [for (final r in _rows.values) if (r.pkg != pkg && r.category == row.category && r.rank != null) r];
    final changed = [row];
    if (peers.any((r) => r.rank == rank)) {
      for (final r in peers.where((r) => r.rank! >= rank)) {
        r.rank = r.rank! + 1;
        changed.add(r);
      }
    }
    row.rank = rank;
    await _save(changed);
  }

  Future<void> addAlias(String pkg, String alias) async {
    final row = _rows[pkg];
    final word = _clean(alias);
    if (row == null || word.isEmpty) return;
    _addAlias(row, word);
    await _save([row]);
  }

  /// ลำดับที่ตั้งไว้ก่อน แล้วที่เปิดบ่อย แล้วตามชื่อ
  static int _order(AppRow a, AppRow b) {
    if (a.rank != b.rank) {
      if (a.rank == null) return 1;
      if (b.rank == null) return -1;
      return a.rank!.compareTo(b.rank!);
    }
    final o = b.opens.compareTo(a.opens);
    return o != 0 ? o : a.label.toLowerCase().compareTo(b.label.toLowerCase());
  }

  /// ข้อความจากคนอื่นบรรทัดเดียว · แท็กปลอมในชื่อต้องไม่เหลือรูปแท็ก
  static String _one(String v) => v
      .replaceAll(RegExp(r'\[{2,}'), '[')
      .replaceAll(RegExp(r'\]{2,}'), ']')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _clean(String v) {
    final t = _one(v).replaceAll(RegExp(r'[\[\]|]'), '').trim();
    return t.length <= nameChars ? t : t.substring(0, nameChars).trim();
  }

  static String _line(AppRow r) => [
        _one(r.label),
        if (r.rank != null) 'order ${r.rank}',
        if (r.opens > 0) 'opened ${r.opens}x',
        if (r.aliases.isNotEmpty) 'also called ${r.aliases.map(_one).join(', ')}',
      ].join(' · ');

  /// บันทึกส่งกลับเข้าโมเดล · [arg] ว่าง = ทุกหมวด · new = ที่เพิ่งเข้าออก · อย่างอื่น = หมวดหรือชื่อแอป
  String render(String arg) {
    final live = [for (final r in _rows.values) if (!r.gone) r]..sort(_order);
    if (live.isEmpty) return 'The app table is empty right now. Tell the owner you could not read the app list.';
    final q = arg.trim();
    if (AppWords.isNew(q)) return _renderChanges();
    if (AppWords.isAll(q)) {
      final groups = <String, List<AppRow>>{};
      for (final r in live) {
        groups.putIfAbsent(r.category, () => []).add(r);
      }
      final names = groups.keys.toList()..sort();
      return [
        '${live.length} apps, grouped, most used first:',
        for (final c in names) '$c: ${groups[c]!.map((r) => _one(r.label)).join(', ')}',
      ].join('\n');
    }
    final category = AppWords.category(q);
    final inGroup = live.where((r) => r.category == category).toList();
    if (inGroup.isNotEmpty) {
      return ['Category $category, ${inGroup.length} apps in order:', for (final r in inGroup) '- ${_line(r)}'].join('\n');
    }
    final hit = find(q);
    if (hit != null) return 'App: ${_line(hit)} · category ${hit.category}';
    return 'No app or category called "${_one(q)}". Categories: ${live.map((r) => r.category).toSet().join(', ')}.';
  }

  String _renderChanges() {
    final since = _clock().subtract(const Duration(days: 30));
    final recent = [for (final r in _rows.values) if (r.noticedAt?.isAfter(since) ?? false) r]
      ..sort((a, b) => b.noticedAt!.compareTo(a.noticedAt!));
    if (recent.isEmpty) return 'No app was installed or removed in the last 30 days.';
    return [
      for (final r in recent.take(30)) '- ${r.gone ? 'removed' : 'installed'}: ${_one(r.label)} (${r.category})',
    ].join('\n');
  }

  /// แอปที่เพิ่งเข้าออก สำหรับ prompt · 🔴 ไม่มีคำบอกเวลาสัมพัทธ์ · prompt ที่เปลี่ยนทุกตาทำให้สมองในเครื่องเริ่ม session ใหม่
  String newsLine() {
    final since = _clock().subtract(newsFor);
    final recent = [for (final r in _rows.values) if (r.noticedAt?.isAfter(since) ?? false) r]
      ..sort((a, b) => b.noticedAt!.compareTo(a.noticedAt!));
    if (recent.isEmpty) return '';
    String names(Iterable<AppRow> rows) {
      final list = rows.toList();
      final shown = list.take(8).map((r) => '"${_clean(r.label)}"').join(', ');
      return list.length > 8 ? '$shown and ${list.length - 8} more' : shown;
    }

    final added = recent.where((r) => !r.gone), gone = recent.where((r) => r.gone);
    return [
      if (added.isNotEmpty) 'Recently installed: ${names(added)}.',
      if (gone.isNotEmpty) 'Recently removed: ${names(gone)}.',
    ].join(' ');
  }
}
