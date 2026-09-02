/// สมุดบันทึกของมายด์ — เรื่องที่เกิดขึ้นจริง เรียงตามเวลา
///
/// **ของเดิมเป็นภาพนิ่ง** แท็บไทม์ไลน์โชว์หกเหตุการณ์ตั้งแต่ 08:12 ถึง 12:00
/// พร้อมตัวเลขสรุป "รับสาย 3 · เมล 5 · ประชุม 2" ซึ่งเป็นค่าคงที่ในโค้ด
/// เวลาเดิมทุกวัน จำนวนเดิมทุกวัน ไม่ว่าใครใช้หรือใช้เมื่อไหร่
///
/// ที่แย่กว่าคือ**แอปไม่ได้เก็บประวัติอะไรเลยจริง ๆ** บทสนทนาอยู่ในหน่วยความจำ
/// แล้วหายตอนปิดแอป · ไฟล์นี้คือที่แรกที่บันทึกว่าอะไรเกิดขึ้นบ้าง
///
/// ## กฎที่ไม่ยอมแลก
///
/// 🔴 **เจ้าของต้องเห็นและลบได้ทุกอย่าง** เหมือน [MindMemory] · บันทึกที่
/// เจ้าตัวเปิดดูไม่ได้ไม่ใช่บันทึก แต่เป็นการสอดส่อง
///
/// 🔴 **ห้ามบันทึกความลับ** ใช้ด่านกรองตัวเดียวกับความจำ — สิ่งที่เผลอพิมพ์
/// มาครั้งเดียวต้องไม่กลายเป็นของที่ติดดิสก์ไปตลอด
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../store/mind_db.dart';

import '../memory/mind_memory.dart' show looksLikeSecret;

/// ชนิดของเรื่องที่บันทึก — มีผลกับสีจุดบนเส้นเวลาและการนับสรุป
enum JournalKind {
  /// เจ้าของพิมพ์อะไรมา
  asked,

  /// มายด์ตอบ
  replied,

  /// เธอจำเรื่องใหม่ได้
  learned,

  /// สายโทรเข้า/ออก
  call,

  /// ติดตั้งชุดตัวละคร/เสื้อผ้า
  pack,

  /// อัปเดตแอป
  update,

  /// เรื่องของระบบ — สิทธิ์ บริการเบื้องหลัง
  system;

  static JournalKind parse(Object? v) => JournalKind.values.firstWhere(
        (k) => k.name == '$v',
        orElse: () => JournalKind.system,
      );
}

@immutable
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.at,
    required this.kind,
    required this.title,
    this.detail = '',
  });

  final String id;
  final DateTime at;
  final JournalKind kind;
  final String title;
  final String detail;

  Map<String, Object?> toJson() => {
        'id': id,
        'at': at.millisecondsSinceEpoch,
        'kind': kind.name,
        'title': title,
        if (detail.isNotEmpty) 'detail': detail,
      };

  static JournalEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}'.trim();
    final title = '${raw['title'] ?? ''}'.trim();
    final at = raw['at'];
    if (id.isEmpty || title.isEmpty || at is! int) return null;

    return JournalEntry(
      id: id,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      kind: JournalKind.parse(raw['kind']),
      title: title,
      detail: '${raw['detail'] ?? ''}',
    );
  }
}

/// เก็บได้มากสุดกี่รายการ
///
/// ต่างจากความจำตรงที่**ไม่ได้เข้า prompt** จึงไม่ได้เสียเงินต่อรายการ
/// เพดานมีไว้กันไฟล์โตไม่มีที่สิ้นสุดเท่านั้น เกินแล้วตัดตัวเก่าสุดทิ้ง
const kJournalLimit = 300;

/// ข้อความยาวกว่านี้ถูกตัด — บันทึกคือ "เกิดอะไรขึ้น" ไม่ใช่สำเนาบทสนทนา
const kJournalMaxChars = 160;

class MindJournal extends ChangeNotifier {
  MindJournal({Directory? dir, DateTime Function()? clock})
      : _injectedDir = dir,
        _clock = clock ?? DateTime.now;

  final Directory? _injectedDir;
  final DateTime Function() _clock;

  /// ฐานข้อมูล — ต่อเข้ามาทีหลัง เหมือน [MindMemory]
  /// null = ตกกลับไปใช้ `journal.json` เหมือนก่อนย้ายมา SQLite
  MindDb? _db;

  void attachDb(MindDb? db) => _db = db;

  final List<JournalEntry> _entries = [];
  bool _loaded = false;

  /// ใหม่สุดอยู่บนสุด — คนเปิดแท็บนี้อยากรู้ว่า "เมื่อกี้เกิดอะไรขึ้น"
  /// ไม่ใช่ "เมื่อวานเริ่มต้นยังไง"
  List<JournalEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;
  int get count => _entries.length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    final db = _db;
    if (db != null) {
      try {
        _entries
          ..clear()
          ..addAll((await db.allJournal(limit: kJournalLimit))
              .map(_fromRow)
              .whereType<JournalEntry>());
        _sort();
        if (_entries.isEmpty) await _absorbLegacyFile();
        notifyListeners();
        return;
      } on Object catch (e) {
        debugPrint('journal: อ่านจากฐานไม่ได้ ตกไปใช้ไฟล์ — $e');
      }
    }

    try {
      final f = await _file();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return;
      _entries
        ..clear()
        ..addAll(raw.map(JournalEntry.fromJson).whereType<JournalEntry>());
      _sort();
      notifyListeners();
    } catch (e) {
      // ไฟล์เสียไม่ควรทำให้แอปเปิดไม่ได้ — เริ่มจากสมุดว่างดีกว่าค้าง
      debugPrint('journal: อ่านไฟล์ไม่ได้ — $e');
    }
  }

  /// ย้าย `journal.json` เข้าฐาน ครั้งเดียว · ไม่ลบไฟล์เก่าทิ้ง
  Future<void> _absorbLegacyFile() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return;
      final old =
          raw.map(JournalEntry.fromJson).whereType<JournalEntry>().toList();
      if (old.isEmpty) return;

      _entries.addAll(old);
      _sort();
      for (final e in old) {
        await _db!.putJournal(_toRow(e));
      }
      debugPrint('journal: ย้ายไทม์ไลน์เก่าเข้าฐาน ${old.length} รายการ');
    } on Object catch (e) {
      debugPrint('journal: ย้ายไทม์ไลน์เก่าไม่สำเร็จ — $e');
    }
  }

  static Map<String, Object?> _toRow(JournalEntry e) => {
        'id': e.id,
        'kind': e.kind.name,
        'text': e.title,
        'detail': e.detail,
        'at': e.at.millisecondsSinceEpoch,
      };

  static JournalEntry? _fromRow(Map<String, Object?> r) {
    final title = r['text'] as String?;
    if (title == null || title.isEmpty) return null;
    return JournalEntry(
      id: '${r['id']}',
      at: DateTime.fromMillisecondsSinceEpoch((r['at'] as int?) ?? 0),
      kind: JournalKind.parse(r['kind']),
      title: title,
      detail: (r['detail'] as String?) ?? '',
    );
  }

  /// บันทึกหนึ่งเรื่อง · คืน false ถ้าไม่ได้บันทึก
  ///
  /// ไม่ await การเขียนไฟล์ในผู้เรียกส่วนใหญ่ — การบันทึกต้องไม่ทำให้
  /// สิ่งที่กำลังเกิดขึ้นช้าลง ถ้าเขียนดิสก์ไม่ทันก็ยังเห็นบนจอทันทีอยู่ดี
  Future<bool> record(
    JournalKind kind,
    String title, {
    String detail = '',
  }) async {
    final t = title.trim();
    if (t.isEmpty) return false;

    // ด่านเดียวกับความจำ — ที่นี่ก็อยู่บนดิสก์ ใครถอด backup ออกมาก็อ่านได้
    if (looksLikeSecret(t) || looksLikeSecret(detail)) {
      debugPrint('journal: ไม่บันทึก — เข้าข่ายความลับ');
      return false;
    }

    _entries.insert(
      0,
      JournalEntry(
        id: '${_clock().microsecondsSinceEpoch}',
        at: _clock(),
        kind: kind,
        title: _clip(t),
        detail: _clip(detail.trim()),
      ),
    );

    if (_entries.length > kJournalLimit) {
      _entries.removeRange(kJournalLimit, _entries.length);
    }

    notifyListeners();
    await _save();
    return true;
  }

  Future<void> forget(String id) async {
    _entries.removeWhere((e) => e.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    await _save();
  }

  /// รายการของวันนี้ — ใช้ทั้งบนจอและในการนับสรุป
  List<JournalEntry> get today {
    final now = _clock();
    final start = DateTime(now.year, now.month, now.day);
    return _entries.where((e) => e.at.isAfter(start)).toList();
  }

  /// นับของวันนี้ตามชนิด · ใช้กับแถวตัวเลขสรุป
  int countToday(Set<JournalKind> kinds) =>
      today.where((e) => kinds.contains(e.kind)).length;

  /// จัดกลุ่มตามวัน สำหรับหัวข้อคั่นบนเส้นเวลา
  Map<DateTime, List<JournalEntry>> get byDay {
    final out = <DateTime, List<JournalEntry>>{};
    for (final e in _entries) {
      final day = DateTime(e.at.year, e.at.month, e.at.day);
      (out[day] ??= []).add(e);
    }
    return out;
  }

  String _clip(String s) =>
      s.length <= kJournalMaxChars ? s : '${s.substring(0, kJournalMaxChars - 1)}…';

  /// ใหม่สุดก่อนเสมอ · เรียงหลังโหลดเพราะไฟล์อาจถูกแก้มือ
  void _sort() => _entries.sort((a, b) => b.at.compareTo(a.at));

  Future<void> _save() async {
    final db = _db;
    if (db != null) {
      try {
        await db.clearJournal();
        for (final e in _entries) {
          await db.putJournal(_toRow(e));
        }
        await db.trimJournal(kJournalLimit);
        return;
      } on Object catch (e) {
        debugPrint('journal: เขียนลงฐานไม่ได้ ตกไปใช้ไฟล์ — $e');
      }
    }
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(
        jsonEncode(_entries.map((e) => e.toJson()).toList()),
        flush: true,
      );
    } catch (e) {
      debugPrint('journal: บันทึกไม่ได้ — $e');
    }
  }

  Future<File> _file() async {
    final dir = _injectedDir ?? await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}journal.json');
  }
}
