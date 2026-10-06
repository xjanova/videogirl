/// ความจำระยะยาวของมายด์
///
/// **ของเดิมไม่มีความจำเลย** — `ownerProfile` กับ `boundaries` คือช่องข้อความ
/// ที่เจ้าของพิมพ์เอง ไม่ใช่สิ่งที่เธอสรุปมา · บทสนทนาเก็บในหน่วยความจำ 16 ตา
/// แล้ว**หายหมดเมื่อปิดแอป** · เธอจึงเริ่มจากศูนย์ทุกครั้งที่เปิด
///
/// ไฟล์นี้เก็บ "ข้อเท็จจริงที่อยู่ทน" แยกจากบทสนทนา เพราะสองอย่างนี้มีอายุ
/// ไม่เท่ากัน: บทสนทนาหมดความหมายในไม่กี่ชั่วโมง แต่ "เจ้าของแพ้กุ้ง"
/// ต้องอยู่ตลอดไป · ยัดรวมกันแล้วตัดตามอายุ = ตัดของสำคัญทิ้งไปพร้อมกัน
///
/// ## กฎที่ไม่ยอมแลก
///
/// 🔴 **เจ้าของต้องเห็นและลบได้ทุกอย่าง** ระบบที่สะสมโปรไฟล์ของคนไว้เงียบ ๆ
/// โดยเจ้าตัวเปิดดูไม่ได้ ไม่ใช่ผู้ช่วย · เก็บเป็น JSON ที่คนอ่านออก
/// ไม่ใช่ embedding ที่เปิดมาแล้วเห็นแต่ตัวเลข
///
/// 🔴 **ห้ามจำความลับ** รหัสผ่าน เลขบัตร OTP — สิ่งที่เผลอพิมพ์มาครั้งเดียว
/// ต้องไม่กลายเป็นของที่ติดตัวแอปไปตลอด ดู [looksLikeSecret]
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../store/mind_db.dart';
import 'recall.dart';

/// ชนิดของสิ่งที่จำ — มีผลกับการเรียงและการตัดทิ้ง
enum MemoryKind {
  /// ข้อเท็จจริงที่ไม่เปลี่ยน — ชื่อ อาชีพ ที่อยู่ แพ้อะไร
  fact,

  /// รสนิยม — ชอบ/ไม่ชอบ วิธีที่อยากให้ตอบ
  preference,

  /// สิ่งที่ทำซ้ำ ๆ — ประชุมทุกอังคาร ตื่นตีห้า
  routine,

  /// คนรอบตัว — ใครเป็นใคร
  person;

  static MemoryKind parse(Object? v) => MemoryKind.values.firstWhere(
        (k) => k.name == '$v',
        orElse: () => MemoryKind.fact,
      );
}

@immutable
class MemoryFact {
  const MemoryFact({
    required this.id,
    required this.text,
    required this.kind,
    required this.createdAt,
    this.pinned = false,
  });

  final String id;
  final String text;
  final MemoryKind kind;
  final DateTime createdAt;

  /// ปักหมุด = ห้ามตัดทิ้งตอนความจำเต็ม
  final bool pinned;

  MemoryFact copyWith({bool? pinned, String? text}) => MemoryFact(
        id: id,
        text: text ?? this.text,
        kind: kind,
        createdAt: createdAt,
        pinned: pinned ?? this.pinned,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'text': text,
        'kind': kind.name,
        'at': createdAt.millisecondsSinceEpoch,
        'pin': pinned,
      };

  static MemoryFact? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final text = '${raw['text'] ?? ''}'.trim();
    final id = '${raw['id'] ?? ''}'.trim();
    if (text.isEmpty || id.isEmpty) return null;
    final at = raw['at'];
    return MemoryFact(
      id: id,
      text: text,
      kind: MemoryKind.parse(raw['kind']),
      createdAt: at is int
          ? DateTime.fromMillisecondsSinceEpoch(at)
          : DateTime.fromMillisecondsSinceEpoch(0),
      pinned: raw['pin'] == true,
    );
  }
}

/// เก็บได้มากสุดกี่ข้อ
///
/// ไม่ใช่เพราะดิสก์ไม่พอ แต่เพราะ**ทุกข้อถูกยัดเข้า system prompt ทุกครั้งที่คุย**
/// ยิ่งเยอะยิ่งแพงและยิ่งกลบสิ่งที่สำคัญจริง · เกินแล้วตัดตัวเก่าสุดที่ไม่ได้ปักหมุด
const kMemoryLimit = 200;

/// ใกล้กันเท่านี้ขึ้นไป = เรื่องเดียวกัน ไม่จำซ้ำ (ดู [MindMemory.sameFact])
/// · สูงโดยตั้งใจ: ประโยคยาวที่ต่างกันคำเดียวมีสัดส่วนตรงกันสูงได้ทั้งที่เป็นคนละเรื่อง
/// · ตัวเลขต่างกัน ("ห้อง 5" / "ห้อง 7") ไม่นับว่าเรื่องเดียวกันเลย ไม่ว่าจะใกล้แค่ไหน
const kSameThreshold = 0.9;

/// เรื่องใหม่ที่แทนเรื่องเดิม ต้องใกล้ข้อเดิมอย่างน้อยเท่านี้ถึงจะแก้ข้อนั้น
/// · โมเดลมักลอกข้อเดิมมาไม่ตรงทุกตัว จึงต่ำกว่าเกณฑ์จำซ้ำ
const kReplaceThreshold = 0.45;

/// อย่าจำอะไรที่ยาวเกินนี้ — ความจำคือ "ข้อเท็จจริงหนึ่งบรรทัด"
/// ไม่ใช่ที่เก็บบทสนทนาทั้งท่อน ถ้ายาวกว่านี้แปลว่าสกัดมาไม่ดี
const kMemoryMaxChars = 240;

/// รูปแบบของสิ่งที่**ห้ามจำเด็ดขาด**
///
/// สิ่งที่เผลอพิมพ์มาครั้งเดียวต้องไม่กลายเป็นของที่ติดตัวแอปไปตลอด
/// และไฟล์ความจำอยู่บนดิสก์ ใครถอด backup ออกมาก็อ่านได้
///
/// ตั้งใจให้**กว้างเกินจริงเล็กน้อย** — พลาดจำของไม่สำคัญไปบ้างยังดีกว่า
/// เก็บรหัสผ่านของเจ้าของไว้ในไฟล์ธรรมดา
final List<RegExp> _secretPatterns = [
  // เลขยาว 12–19 หลัก (บัตรเครดิต/บัญชี) มีหรือไม่มีขีดคั่นก็จับ
  RegExp(r'(?:\d[ -]?){12,19}'),
  // คีย์ของผู้ให้บริการที่เจอบ่อย
  RegExp(r'\b(?:sk|pk|ghp|gho|xox[baprs])[-_][A-Za-z0-9_-]{16,}'),
  // คำที่อยู่ติดกับค่าที่ตามมา
  RegExp(
      r'(รหัสผ่าน|รหัส ?otp|otp|password|passcode|pin ?code|api ?key|secret|token)\s*[:=]?\s*\S+',
      caseSensitive: false),
  // เลขบัตรประชาชนไทย 13 หลัก
  RegExp(r'\b\d{13}\b'),
];

/// ข้อความนี้หน้าตาเหมือนความลับไหม
///
/// แยกออกมาเป็นฟังก์ชันบริสุทธิ์เพราะเป็นด่านความปลอดภัยที่ต้องเทสต์ได้
/// โดยไม่ต้องมีดิสก์ ไม่ต้องมีโมเดล
bool looksLikeSecret(String text) =>
    _secretPatterns.any((r) => r.hasMatch(text));

class MindMemory extends ChangeNotifier {
  MindMemory({Directory? dir}) : _injectedDir = dir;

  final Directory? _injectedDir;

  /// ฐานข้อมูล — ต่อเข้ามาทีหลัง เพราะมันเกิดตอน boot คนละจังหวะกับตัวนี้
  ///
  /// null = ยังไม่ได้ต่อ หรือเปิดฐานไม่ขึ้น → ตกกลับไปใช้ `memory.json`
  /// เหมือนก่อนย้ายมา SQLite ซึ่งยังทำงานได้ครบทุกอย่าง แค่ไม่ได้สำเนา
  MindDb? _db;

  void attachDb(MindDb? db) => _db = db;
  final List<MemoryFact> _facts = [];
  bool _loaded = false;

  List<MemoryFact> get facts => List.unmodifiable(_facts);
  bool get isEmpty => _facts.isEmpty;
  int get count => _facts.length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _index = null;

    final db = _db;
    if (db != null) {
      try {
        _facts
          ..clear()
          ..addAll(
              (await db.allMemories()).map(_fromRow).whereType<MemoryFact>());

        // ครั้งแรกหลังอัปเดตแอป ฐานยังว่างแต่ไฟล์เก่ายังอยู่ · ย้ายเข้ามา
        // ไม่งั้นเจ้าของกดอัปเดตแล้วเธอลืมทุกอย่างที่เคยจำได้
        if (_facts.isEmpty) await _absorbLegacyFile();
        notifyListeners();
        return;
      } on Object catch (e) {
        debugPrint('memory: อ่านจากฐานไม่ได้ ตกไปใช้ไฟล์ — $e');
      }
    }

    try {
      final f = await _file();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return;
      _facts
        ..clear()
        ..addAll(raw.map(MemoryFact.fromJson).whereType<MemoryFact>());
      notifyListeners();
    } catch (e) {
      // ไฟล์เสียไม่ควรทำให้แอปเปิดไม่ได้ — เริ่มจากความจำว่างดีกว่าค้าง
      debugPrint('memory: อ่านไฟล์ไม่ได้ — $e');
    }
  }

  /// ย้าย `memory.json` เข้าฐาน ครั้งเดียว · **ไม่ลบไฟล์เก่าทิ้ง**
  /// (ผู้ใช้ที่ถอยกลับไปแอปรุ่นก่อนต้องยังมีความจำอยู่)
  Future<void> _absorbLegacyFile() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return;
      final old = raw.map(MemoryFact.fromJson).whereType<MemoryFact>().toList();
      if (old.isEmpty) return;

      _facts.addAll(old);
      for (final m in old) {
        await _db!.putMemory(_toRow(m));
      }
      debugPrint('memory: ย้ายความจำเก่าเข้าฐาน ${old.length} เรื่อง');
    } on Object catch (e) {
      debugPrint('memory: ย้ายความจำเก่าไม่สำเร็จ — $e');
    }
  }

  static Map<String, Object?> _toRow(MemoryFact f) => {
        'id': f.id,
        'text': f.text,
        'kind': f.kind.name,
        'created_at': f.createdAt.millisecondsSinceEpoch,
        'pinned': f.pinned ? 1 : 0,
      };

  static MemoryFact? _fromRow(Map<String, Object?> r) {
    final text = r['text'] as String?;
    if (text == null || text.isEmpty) return null;
    return MemoryFact(
      id: '${r['id']}',
      text: text,
      kind: MemoryKind.parse(r['kind']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          (r['created_at'] as int?) ?? 0),
      pinned: r['pinned'] == 1,
    );
  }

  /// จำเรื่องใหม่ · คืน false ถ้าไม่ได้จำ (ซ้ำ ว่าง ยาวเกิน หรือดูเป็นความลับ)
  Future<bool> remember(String text, {MemoryKind kind = MemoryKind.fact}) async {
    final t = text.trim();
    if (t.isEmpty || t.length > kMemoryMaxChars) return false;
    if (looksLikeSecret(t)) {
      debugPrint('memory: ไม่จำ — เข้าข่ายความลับ');
      return false;
    }
    if (_facts.any((f) => _same(f.text, t))) return false;
    // 🔴 เรื่องเดิมที่เขียนต่างนิดเดียว ("แพ้กุ้ง" / "แพ้กุ้งค่ะ") = ไม่จำซ้ำ
    // ของเดิมเทียบตัวอักษรตรงเป๊ะอย่างเดียว ความจำจึงพอกด้วยเรื่องเดิมหลายถ้อยคำ
    if (_facts.any((f) => sameFact(f.text, t))) return false;

    _facts.add(MemoryFact(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      text: t,
      kind: kind,
      createdAt: DateTime.now(),
    ));
    _evict();
    await _save();
    notifyListeners();
    return true;
  }

  /// เรื่องใหม่ที่**แทน**เรื่องเดิม (ย้ายบ้าน เปลี่ยนงาน เลิกกาแฟ)
  ///
  /// 🔴 ของเดิมเก็บทั้งเก่าและใหม่ไว้คู่กัน "อยู่กรุงเทพ" กับ "ย้ายไปเชียงใหม่"
  /// · เธอได้ทั้งสองข้อแล้วเลือกผิดข้อได้ทุกเมื่อ · แก้ข้อเดิม (คงปักหมุดไว้)
  /// แทนการเพิ่มข้อใหม่ · หาข้อเดิมไม่เจอ = จำเป็นเรื่องใหม่ธรรมดา
  Future<bool> replace(String oldText, String newText,
      {MemoryKind kind = MemoryKind.fact}) async {
    final t = newText.trim();
    if (t.isEmpty || t.length > kMemoryMaxChars || looksLikeSecret(t)) return false;
    MemoryFact? best;
    var score = 0.0;
    for (final f in _facts) {
      final s = RecallIndex.similarity(f.text, oldText);
      if (s > score) {
        score = s;
        best = f;
      }
    }
    if (best == null || score < kReplaceThreshold) return remember(t, kind: kind);
    final i = _facts.indexWhere((f) => f.id == best!.id);
    _facts[i] = _facts[i].copyWith(text: t);
    await _save();
    notifyListeners();
    return true;
  }

  // ═══ นึกออก — ดู recall.dart ════════════════════════════

  /// ดัชนีของความจำ · สร้างใหม่เมื่อความจำเปลี่ยน (ไม่เกิน 200 ข้อ สร้างใหม่ถูกกว่าตามแก้)
  RecallIndex? _index;

  RecallIndex get _recall {
    final have = _index;
    if (have != null) return have;
    final idx = RecallIndex();
    for (final f in _facts) {
      idx.put(f.id, f.text);
    }
    return _index = idx;
  }

  /// ข้อที่เกี่ยวกับ [query] ที่ยังไม่อยู่ใน [skip] (ส่วนใหญ่คือข้อที่อยู่ใน
  /// system prompt แล้ว) · ว่าง = ไม่มีอะไรเกี่ยวพอ ไม่ต้องยัดอะไรเพิ่ม
  List<MemoryFact> recall(String query, {Set<String> skip = const {}, int limit = 6}) {
    if (_facts.isEmpty || query.trim().isEmpty) return const [];
    final hits = _recall.search(query, limit: limit, exclude: skip);
    final byId = {for (final f in _facts) f.id: f};
    return [for (final h in hits) ?byId[h.id]];
  }

  Future<void> forget(String id) async {
    _facts.removeWhere((f) => f.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> forgetAll() async {
    _facts.clear();
    await _save();
    notifyListeners();
  }

  Future<void> setPinned(String id, bool pinned) async {
    final i = _facts.indexWhere((f) => f.id == id);
    if (i < 0) return;
    _facts[i] = _facts[i].copyWith(pinned: pinned);
    await _save();
    notifyListeners();
  }

  Future<void> edit(String id, String text) async {
    final t = text.trim();
    if (t.isEmpty || t.length > kMemoryMaxChars || looksLikeSecret(t)) return;
    final i = _facts.indexWhere((f) => f.id == id);
    if (i < 0) return;
    _facts[i] = _facts[i].copyWith(text: t);
    await _save();
    notifyListeners();
  }

  /// ส่วนที่จะยัดเข้า system prompt — ปักหมุดก่อน แล้วใหม่สุดก่อน
  ///
  /// ตัดที่ [limit] เพราะทุกบรรทัดคือ token ที่จ่ายทุกครั้งที่คุย
  /// ปักหมุดมาก่อนเสมอ ไม่งั้นเรื่องสำคัญที่จำไว้นานแล้วจะถูกเรื่องใหม่ ๆ เบียดออก
  List<MemoryFact> forPrompt({int limit = 60}) {
    final sorted = [..._facts]..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    return sorted.take(limit).toList();
  }

  /// ก้อนข้อความพร้อมใส่ prompt — ว่างเปล่าถ้ายังไม่จำอะไร
  String promptBlock({int limit = 60}) {
    final chosen = forPrompt(limit: limit);
    if (chosen.isEmpty) return '';
    return chosen.map((f) => '- ${f.text}').join('\n');
  }

  /// ตัดตัวเก่าสุดที่ไม่ได้ปักหมุดออก จนเหลือตามเพดาน
  void _evict() {
    if (_facts.length <= kMemoryLimit) return;
    final unpinned = _facts.where((f) => !f.pinned).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var over = _facts.length - kMemoryLimit;
    for (final f in unpinned) {
      if (over <= 0) break;
      _facts.remove(f);
      over--;
    }
  }

  /// เรื่องเดียวกันที่เขียนต่างกันนิดหน่อยไหม
  ///
  /// 🔴 ตัวเลขต้องตรงกันทุกตัว · "ลูกอายุ 5 ขวบ" กับ "ลูกอายุ 7 ขวบ" ใกล้กันมาก
  /// ถ้าดูแค่ตัวอักษร แต่เป็นคนละเรื่อง (หรือเรื่องที่อัปเดต) · ทิ้งข้อใหม่ = เธอ
  /// จำตัวเลขเก่าผิดไปตลอด
  @visibleForTesting
  static bool sameFact(String a, String b) {
    if (_same(a, b)) return true;
    final na = _digits.allMatches(a).map((m) => m[0]).toList();
    final nb = _digits.allMatches(b).map((m) => m[0]).toList();
    if (!listEquals(na, nb)) return false;
    final c = RecallIndex.compare(a, b);
    // ต่างแค่คำลงท้าย ("ค่ะ" "นะ") = ไม่กี่ชิ้น · ต่างที่เนื้อ (สยาม/สีลม) = หลายชิ้น
    return c.diff <= 4 || c.jaccard >= kSameThreshold;
  }

  static final _digits = RegExp(r'[0-9๐-๙]+');

  /// เทียบว่าเป็นเรื่องเดียวกันไหม — ตัดช่องว่างและตัวพิมพ์ออกก่อน
  /// ไม่งั้นจะจำ "ชอบกาแฟดำ" กับ "ชอบกาแฟดำ " เป็นคนละเรื่อง
  static bool _same(String a, String b) =>
      a.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') ==
      b.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _save() async {
    _index = null; // ทุกทางที่แก้ความจำผ่านตรงนี้ · ดัชนีเก่าใช้ไม่ได้แล้ว
    final db = _db;
    if (db != null) {
      try {
        // เขียนทับทั้งชุด · ความจำมีไม่เกิน 200 เรื่องตามเพดาน การไล่หา
        // ว่าอะไรเปลี่ยนบ้างแล้วเขียนเฉพาะตัวนั้น ซับซ้อนกว่าที่ได้คืน
        // 🔴 ในธุรกรรมเดียว + จากสำเนา · ล้างแล้วใส่ทีละแถวนอกธุรกรรม แล้วแอป
        // ถูกฆ่ากลางทาง = ความจำหายทั้งหมด
        await db.replaceMemories([for (final f in List.of(_facts)) _toRow(f)]);
        return;
      } on Object catch (e) {
        debugPrint('memory: เขียนลงฐานไม่ได้ ตกไปใช้ไฟล์ — $e');
      }
    }
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(
        jsonEncode(_facts.map((f) => f.toJson()).toList()),
        flush: true,
      );
    } catch (e) {
      debugPrint('memory: บันทึกไม่ได้ — $e');
    }
  }

  Future<File> _file() async {
    final dir = _injectedDir ?? await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}memory.json');
  }
}
