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
  final List<MemoryFact> _facts = [];
  bool _loaded = false;

  List<MemoryFact> get facts => List.unmodifiable(_facts);
  bool get isEmpty => _facts.isEmpty;
  int get count => _facts.length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
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

  /// จำเรื่องใหม่ · คืน false ถ้าไม่ได้จำ (ซ้ำ ว่าง ยาวเกิน หรือดูเป็นความลับ)
  Future<bool> remember(String text, {MemoryKind kind = MemoryKind.fact}) async {
    final t = text.trim();
    if (t.isEmpty || t.length > kMemoryMaxChars) return false;
    if (looksLikeSecret(t)) {
      debugPrint('memory: ไม่จำ — เข้าข่ายความลับ');
      return false;
    }
    if (_facts.any((f) => _same(f.text, t))) return false;

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

  /// เทียบว่าเป็นเรื่องเดียวกันไหม — ตัดช่องว่างและตัวพิมพ์ออกก่อน
  /// ไม่งั้นจะจำ "ชอบกาแฟดำ" กับ "ชอบกาแฟดำ " เป็นคนละเรื่อง
  static bool _same(String a, String b) =>
      a.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ') ==
      b.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _save() async {
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
