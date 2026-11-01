/// หาว่าเจ้าของหมายถึงใครตอนสั่งให้โทร — ชื่อใกล้เคียง · เบอร์ที่ยังไม่ได้บันทึก · ถามก่อนถ้าไม่ชัด
///
/// ## ทำไม
///
/// เจ้าของ: "ตอนฉันสั่งให้เธอโทรออกหาลูกค้าชื่อบัว เธอบอกไม่มี แทนที่จะค้นรายชื่อที่ใกล้เคียงมาและถามฉัน
/// ก่อนว่าคนไหน หรือเบอร์โทรเข้ามาล่าสุดที่ไม่ได้บันทึกไว้ ก็ต้องเข้าใจ ต้องฉลาดมากขึ้นกว่านี้" ·
/// ของเดิมค้น `LIKE %ชื่อ%` ครั้งเดียวแล้วเอาคนแรก:
/// - เธอเขียน "ลูกค้าบัว" / "คุณบัว" → ไม่เจอ "บัว"
/// - สมุดเขียน "บัวร์" / "Bua" → ไม่เจอ
/// - ลูกค้าที่ยังไม่ได้บันทึกเบอร์ → ไม่มีทางเจอ
/// - "แม่" เจอ "คุณแม่" กับ "แม่บ้าน" → เลือกคนแรกเงียบ ๆ
///
/// ## ทำงานยังไง (ทั้งหมดในเครื่อง · สมุดทั้งเล่มไม่ออกไปไหน)
///
/// 1. ค้นตรงตามที่เขียน (`findContacts`) · คนเดียว = ไปกล่องยืนยันเลยเหมือนเดิม
/// 2. ไม่เจอ / เจอหลายคน → เทียบทั้งสมุด (`contactIndex`): ตัดคำนำหน้า (ลูกค้า คุณ พี่ …) ตัดวรรณยุกต์
///    และตัวการันต์ เทียบคำอ่านกับชื่อที่เขียนเป็นอังกฤษ ยอมพิมพ์ผิดเล็กน้อย
/// 3. เบอร์ที่โทรเข้ามา [unsavedDays] วันล่าสุดที่ยังไม่ได้บันทึก · บันทึกสายที่เธอรับเองหรือ SMS ของเบอร์นั้น
///    เอ่ยชื่อนี้ = ขึ้นก่อน (คนโทรมาบอกว่า "บัวนะคะ")
/// 4. ชัดคนเดียว = กล่องยืนยัน · นอกนั้นเธอถามเจ้าของ ตอบด้วยลำดับ ชื่อ เลขท้าย หรือแตะเลือก ([CallReply])
///
/// ## 🔴 กติกา
///
/// - ไม่โทรเอง · ทุกทางจบที่กล่องยืนยันของเจ้าของ (MindState.pendingCall)
/// - ห้าม log ชื่อ เบอร์ หรือเนื้อ SMS
/// - คำไทยในไฟล์นี้คือ**คำที่ต้องจับให้ได้** (คำนำหน้า ลำดับ คำตอบใช่/ไม่) ไม่ใช่ข้อความที่ผู้ใช้เห็น ·
///   ข้อความที่ผู้ใช้เห็นอยู่ใน lib/i18n
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../system/permissions.dart';
import 'call_notes.dart';
import 'call_watch.dart';

/// คนที่อาจเป็นคนที่เจ้าของหมายถึง
@immutable
class CallCandidate {
  const CallCandidate({
    required this.number,
    this.name,
    this.at,
    this.missed = false,
    this.calls = 0,
    this.saidName = false,
    this.score = 0,
  });

  final String number;

  /// ชื่อในสมุด · null = เบอร์ที่ยังไม่ได้บันทึก (มาจากสายล่าสุด)
  final String? name;

  /// สายล่าสุดของเบอร์นี้ (เบอร์ที่ยังไม่ได้บันทึกเท่านั้น)
  final DateTime? at;

  /// สายล่าสุดไม่ได้รับ / ถูกปฏิเสธ
  final bool missed;

  /// โทรเข้ามากี่ครั้งในช่วงที่ดู
  final int calls;

  /// บันทึกสายที่เธอรับ หรือ SMS จากเบอร์นี้ เอ่ยชื่อที่เจ้าของสั่ง
  final bool saidName;

  /// ใกล้กับชื่อที่สั่งแค่ไหน 0..1 (รายชื่อในสมุด)
  final double score;

  bool get unsaved => name == null;
  String get digits => number.replaceAll(RegExp(r'[^0-9]'), '');

  /// เลขท้ายเก้าหลัก · เบอร์เดียวกันเขียนได้หลายแบบ (+66… / 0… / มีขีด)
  String get key => digits.length > 9 ? digits.substring(digits.length - 9) : digits;

  /// เลขท้ายสี่ตัว ที่เธอพูดให้เจ้าของจำได้
  String get tail => digits.length > 4 ? digits.substring(digits.length - 4) : digits;

  String get who => name ?? number;

  CallCandidate copyWith({bool? saidName, DateTime? at}) => CallCandidate(
        number: number,
        name: name,
        at: at ?? this.at,
        missed: missed,
        calls: calls,
        saidName: saidName ?? this.saidName,
        score: score,
      );
}

/// ผลการหา · [pick] = ชัดคนเดียว · [choices] = ต้องถามเจ้าของ · ว่างทั้งคู่ = ไม่เจอเลย
@immutable
class CallTargetResult {
  const CallTargetResult({this.pick, this.choices = const [], this.noContacts = false});

  final CallCandidate? pick;
  final List<CallCandidate> choices;

  /// เปิดสมุดไม่ได้ (ยังไม่ให้สิทธิ์) · ยังอาจมีเบอร์จากสายล่าสุดให้เลือก
  final bool noContacts;

  /// มีชื่อในสมุดอยู่ในตัวเลือกไหม · ไม่มี = "ในสมุดไม่มีชื่อนี้ แต่มีเบอร์ที่โทรเข้ามา…"
  bool get anyContact => choices.any((c) => !c.unsaved);
}

/// คำถาม "หมายถึงคนไหน" ที่รอเจ้าของตอบ
@immutable
class CallChoice {
  const CallChoice({required this.target, required this.task, required this.choices, required this.id, required this.at});

  /// ชื่อที่เจ้าของ (ผ่านเธอ) สั่ง
  final String target;

  /// เรื่องที่จะคุย · ใช้ต่อเมื่อเจ้าของเลือกแล้ว
  final String task;
  final List<CallCandidate> choices;
  final int id;
  final DateTime at;

  /// เกินนี้ถือว่าคุยเรื่องอื่นไปแล้ว · "คนที่สอง" ตอนนั้นไม่ได้หมายถึงรายการนี้
  static const lifetime = Duration(minutes: 10);

  bool expired(DateTime now) => now.difference(at) > lifetime;
}

class CallTargetResolver {
  CallTargetResolver({MethodChannel? channel, DateTime Function()? clock, this.notes})
      : _ch = channel ?? kSystemChannel,
        _clock = clock ?? DateTime.now;

  final MethodChannel _ch;
  final DateTime Function() _clock;

  /// บันทึกสายที่เธอรับเอง · null = ไม่ดู
  final List<CallNote> Function()? notes;

  /// ดูสายเข้าย้อนหลังเท่านี้
  static const unsavedDays = 14;

  /// ชื่อใกล้เคียงไม่เกินเท่านี้ · เบอร์ที่ยังไม่ได้บันทึกไม่เกิน [maxUnsaved] · พูดออกเสียงแล้วยังจำได้
  static const maxContacts = 4;
  static const maxUnsaved = 3;

  /// ใกล้แค่ไหนถึงนับว่า "ใช่แน่" / "พอเป็นไปได้"
  static const strong = .85;
  static const loose = .6;

  Future<Object?> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<Object?>(method, args);
    } on Object catch (e) {
      debugPrint('call target: $method — ${e.runtimeType}');
      return null;
    }
  }

  Future<CallTargetResult> resolve(String target) async {
    final t = target.trim();
    // 1. ตรงตามที่เขียน (ทางเดิม) · ติดอันดับต้นเสมอ เพราะสมุดมีคำนี้อยู่จริง
    final exact = await _invoke('findContacts', {'name': t});
    final direct = [
      for (final m in (exact is List ? exact : const []).whereType<Map>())
        if (m['number'] is String)
          CallCandidate(
            number: m['number'] as String,
            name: '${m['name'] ?? t}',
            score: math.max(CallNameMatch.score(t, '${m['name'] ?? t}'), .88),
          ),
    ];
    final people = _distinctPeople(direct);

    // 2. ทั้งสมุด
    final index = await _invoke('contactIndex');
    final noContacts = index == null;
    final scored = <CallCandidate>[];
    if (index is List) {
      final rows = index.whereType<Map>().toList();
      for (var i = 0; i < rows.length; i++) {
        final name = rows[i]['name'];
        final number = rows[i]['number'];
        if (name is! String || number is! String) continue;
        final s = CallNameMatch.score(t, name);
        if (s >= loose) scored.add(CallCandidate(number: number, name: name, score: s));
      }
    }
    // เรียงคะแนน · เท่ากันคงลำดับเดิม (สมุดเรียงคนที่ติดต่อบ่อยก่อน)
    final contacts = _byScore(_distinctPeople([...people, ..._byScore(scored)]).take(maxContacts).toList());
    final saved = {
      for (final r in (index is List ? index : const []).whereType<Map>())
        if (r['number'] is String) CallCandidate(number: r['number'] as String).key,
    };

    // 3. เบอร์ที่โทรเข้ามาแต่ยังไม่ได้บันทึก
    final unsaved = await _unsaved(t, saved);

    // 4. ชัดคนเดียวไหม · คนโทรมาบอกชื่อนี้ไว้ (ยังไม่ได้บันทึก) = ไม่ชัด ต้องถาม ("ลูกค้าชื่อบัว"
    // อาจเป็นคนนั้น ไม่ใช่บัวในสมุด)
    final said = unsaved.any((c) => c.saidName);
    if (!said && contacts.isNotEmpty) {
      final top = contacts.first;
      final second = contacts.length > 1 ? contacts[1].score : 0.0;
      // ชื่อตรงตัว (ตัดคำนำหน้าแล้ว) และคนถัดไปห่างพอ · หรือมีคนเดียวที่ใกล้จริง
      if ((top.score >= .97 && second < .95) || (contacts.length == 1 && top.score >= strong)) {
        return CallTargetResult(pick: top, noContacts: noContacts);
      }
    }
    return CallTargetResult(choices: [...contacts, ...unsaved], noContacts: noContacts);
  }

  /// คะแนนมากก่อน · เท่ากันคงลำดับเดิม (List.sort ของ Dart ไม่รับประกันลำดับของตัวที่เท่ากัน)
  static List<CallCandidate> _byScore(List<CallCandidate> all) {
    final idx = [for (var i = 0; i < all.length; i++) i]..sort((a, b) {
        final d = all[b].score.compareTo(all[a].score);
        return d != 0 ? d : a.compareTo(b);
      });
    return [for (final i in idx) all[i]];
  }

  /// คนเดียวกันมีหลายเบอร์ (มือถือ/ที่ทำงาน) ยังนับเป็นหลายตัวเลือก · เบอร์ซ้ำนับครั้งเดียว
  static List<CallCandidate> _distinctPeople(List<CallCandidate> all) {
    final seen = <String>{};
    return [
      for (final c in all)
        if (c.key.isNotEmpty && seen.add(c.key)) c,
    ];
  }

  Future<List<CallCandidate>> _unsaved(String target, Set<String> saved) async {
    final raw = await _invoke('recentCalls', {'limit': 150});
    if (raw is! List) return const [];
    final now = _clock();
    final since = now.subtract(const Duration(days: unsavedDays));
    final byKey = <String, CallCandidate>{};
    for (final e in raw) {
      final c = CallEvent.fromMap(e);
      if (c == null || c.number == null || c.name != null || c.at.isBefore(since)) continue;
      if (c.type == CallType.outgoing || c.type == CallType.unknown) continue;
      final cand = CallCandidate(number: c.number!);
      if (cand.digits.length < 6 || saved.contains(cand.key)) continue;
      final had = byKey[cand.key];
      if (had == null) {
        byKey[cand.key] = CallCandidate(
          number: c.number!,
          at: c.at,
          missed: c.type == CallType.missed || c.type == CallType.rejected,
          calls: 1,
        );
      } else {
        final newer = c.at.isAfter(had.at!);
        byKey[cand.key] = CallCandidate(
          number: had.number,
          at: newer ? c.at : had.at,
          missed: newer ? (c.type == CallType.missed || c.type == CallType.rejected) : had.missed,
          calls: had.calls + 1,
        );
      }
    }
    if (byKey.isEmpty) return const [];

    // คนโทรบอกชื่อไว้ในสายที่เธอรับ · หรือส่ง SMS ลงชื่อไว้
    final said = <String>{};
    final variants = CallNameMatch.variants(target).map(CallNameMatch.norm).where((v) => v.length >= 2).toList();
    if (variants.isNotEmpty) {
      for (final n in notes?.call() ?? const <CallNote>[]) {
        final k = CallCandidate(number: n.who).key;
        if (!byKey.containsKey(k)) continue;
        final heard = CallNameMatch.norm([n.summary, for (final l in n.lines) if (!l.fromHer) l.text].join(' '));
        if (variants.any(heard.contains)) said.add(k);
      }
      final sms = await _invoke('recentSms', {'query': CallNameMatch.core(target), 'limit': 20});
      for (final m in (sms is List ? sms : const []).whereType<Map>()) {
        if ((m['type'] as num?)?.toInt() != 1 || m['name'] != null) continue;
        final k = CallCandidate(number: '${m['address'] ?? ''}').key;
        if (byKey.containsKey(k)) said.add(k);
      }
    }
    final list = [
      for (final e in byKey.entries) said.contains(e.key) ? e.value.copyWith(saidName: true) : e.value,
    ]..sort((a, b) {
        if (a.saidName != b.saidName) return a.saidName ? -1 : 1;
        return b.at!.compareTo(a.at!);
      });
    return list.take(maxUnsaved).toList();
  }
}

/// เทียบชื่อที่สั่งกับชื่อในสมุด · ไทยไม่มีช่องว่าง ชื่อเล่นสั้น และสมุดเขียนได้ทั้งไทยและอังกฤษ
abstract final class CallNameMatch {
  /// คำนำหน้าที่เธอหรือเจ้าของพูดติดมา แต่ไม่อยู่ในสมุด · ยาวก่อนสั้น ("ลูกค้าชื่อ" ก่อน "ลูกค้า")
  static const _prefixes = [
    'ลูกค้าชื่อ', 'ลูกค้า', 'คนชื่อ', 'ชื่อ', 'เบอร์', 'คุณ', 'คุน', 'พี่', 'น้อง', 'เจ๊', 'เฮีย', 'เสี่ย',
    'ป้า', 'ลุง', 'น้า', 'ครู', 'อาจารย์', 'หมอ', 'ช่าง',
  ];
  static final _latinPrefix = RegExp(r"^(mr|mrs|ms|miss|khun|nong|dr|k|p)[.'’\s]+", caseSensitive: false);

  /// ชื่อจากสมุด/คำสั่งที่จะขึ้นในข้อความของเธอ · บรรทัดเดียว ไม่ยาวเกิน ·
  /// 🔴 วงเล็บเหลี่ยมคู่เป็นตัวเดียว · ชื่อที่คนอื่นตั้งว่า "[[ทำในเครื่อง: …]]" ต้องไม่กลายเป็นแท็กที่เธอลอกตาม
  static String display(String s) {
    final t = s
        .replaceAll(RegExp(r'\[{2,}'), '[')
        .replaceAll(RegExp(r'\]{2,}'), ']')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t.length > 60 ? '${t.substring(0, 59)}…' : t;
  }

  /// ชื่อที่เหลือหลังตัดคำนำหน้า (ทั้งก้อน) · ใช้ค้น SMS
  static String core(String target) {
    final v = variants(target);
    return v.isEmpty ? target.trim() : v.first;
  }

  /// แบบต่าง ๆ ของชื่อที่สั่ง · ตัดคำนำหน้าก่อน แล้วค่อยแยกคำ · แบบที่สั้นเกิน (ตัวเดียว) ทิ้ง
  @visibleForTesting
  static List<String> variants(String target) {
    final out = <String>[];
    void add(String s) {
      final v = s.trim();
      if (norm(v).length >= 2 && !out.contains(v) && !_prefixes.contains(v)) out.add(v);
    }

    final plain = target.replaceAll(RegExp(r'[()\[\]{}"“”]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final noParen = target.replaceAll(RegExp(r'\([^)]*\)'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    add(_strip(noParen));
    add(_strip(plain));
    for (final tok in plain.split(RegExp(r'[\s,·/|]+'))) {
      add(_strip(tok));
    }
    add(plain);
    return out;
  }

  static String _strip(String s) {
    var t = s.trim();
    for (var guard = 0; guard < 4; guard++) {
      final before = t;
      t = t.replaceFirst(_latinPrefix, '').trim();
      for (final p in _prefixes) {
        // เหลือให้เทียบอย่างน้อยสองตัว · "น้าน" ไม่ใช่ "น้า" + "น"
        if (t.startsWith(p) && norm(t.substring(p.length)).length >= 2) {
          t = t.substring(p.length).trim();
          break;
        }
      }
      if (t == before) break;
    }
    return t;
  }

  /// ตัวเล็ก · ตัดตัวที่มีการันต์ (บัวร์ → บัว · มิ้นท์ → มิน) · ตัดวรรณยุกต์ ไม้ไต่คู้ ไม้ยมก ช่องว่าง เครื่องหมาย
  @visibleForTesting
  static String norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[ก-ฮ][ิ-ู]?์'), '')
      .replaceAll(RegExp('[็-๋์ๆฯ]'), '')
      .replaceAll(RegExp(r"[\s.\-_'’,·()]"), '');

  static final _thai = RegExp('[฀-๿]');
  static final _latin = RegExp('[a-z]');

  /// ชื่อในสมุด [name] ใกล้กับชื่อที่สั่ง [target] แค่ไหน · 0..1
  static double score(String target, String name) {
    final full = norm(name);
    if (full.isEmpty) return 0;
    // สมุดก็มีคำนำหน้า ("คุณแม่" "พี่บัว ร้านดอกไม้") · เทียบทั้งแบบมีและไม่มี
    final tokens = {
      full,
      norm(_strip(name)),
      for (final t in name.toLowerCase().split(RegExp(r'[\s,./()\-]+'))) ...[norm(t), norm(_strip(t))],
    }..removeWhere((t) => t.length < 2);
    var best = 0.0;
    for (final v in variants(target)) {
      final q = norm(v);
      if (q.length < 2) continue;
      for (final n in tokens) {
        best = math.max(best, _pair(q, n, whole: n == full));
        if (best >= 1) return 1;
      }
    }
    return best;
  }

  static double _pair(String q, String n, {required bool whole}) {
    if (q == n) return whole ? 1 : .97;
    if (n.startsWith(q)) return .9;
    if (n.contains(q)) return q.length >= 3 ? .88 : .8;
    final qThai = _thai.hasMatch(q), nThai = _thai.hasMatch(n);
    if (qThai != nThai) {
      // ไทยกับอังกฤษ · เทียบคำอ่านคร่าว ๆ
      final a = latinKey(qThai ? roman(q) : q);
      final b = latinKey(nThai ? roman(n) : n);
      if (a.length < 2 || b.length < 2) return 0;
      if (a == b) return .86;
      if (a.length >= 3 && b.startsWith(a)) return .8;
      if (math.min(a.length, b.length) >= 3 && _lev(a, b) <= 1) return .72;
      return 0;
    }
    if (!_latin.hasMatch(q) && !qThai) return 0; // ตัวเลขล้วน ไม่ใช่ชื่อ
    if (q.length < 3) return 0;
    final d = _lev(q, n);
    final allowed = q.length >= 5 ? 2 : 1;
    if (d > allowed) return 0;
    return .6 + .25 * (1 - d / math.max(q.length, n.length));
  }

  static int _lev(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// รูปอังกฤษที่เทียบกันได้ · ph=p th=t kh=k ch=j=c g=k v=w r=l (คนไทยออกเสียงปนกัน) ตัดตัวซ้ำ
  @visibleForTesting
  static String latinKey(String s) {
    var t = s.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
    t = t
        .replaceAll('ng', 'N')
        .replaceAll('ph', 'p')
        .replaceAll('th', 't')
        .replaceAll('kh', 'k')
        .replaceAll('ch', 'c')
        .replaceAll('j', 'c')
        .replaceAll('g', 'k')
        .replaceAll('q', 'k')
        .replaceAll('v', 'w')
        .replaceAll(RegExp('[zx]'), 's')
        .replaceAll('r', 'l')
        .replaceAll('ee', 'i')
        .replaceAll('oo', 'u')
        .replaceAll('h', '');
    if (t.endsWith('y')) t = '${t.substring(0, t.length - 1)}i';
    if (t.length > 3 && t.endsWith('e')) t = t.substring(0, t.length - 1);
    return t.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
  }

  static const _init = {
    'ก': 'k', 'ข': 'kh', 'ฃ': 'kh', 'ค': 'kh', 'ฅ': 'kh', 'ฆ': 'kh', 'ง': 'ng', 'จ': 'ch', 'ฉ': 'ch',
    'ช': 'ch', 'ซ': 's', 'ฌ': 'ch', 'ญ': 'y', 'ฎ': 'd', 'ฏ': 't', 'ฐ': 'th', 'ฑ': 'th', 'ฒ': 'th',
    'ณ': 'n', 'ด': 'd', 'ต': 't', 'ถ': 'th', 'ท': 'th', 'ธ': 'th', 'น': 'n', 'บ': 'b', 'ป': 'p',
    'ผ': 'ph', 'ฝ': 'f', 'พ': 'ph', 'ฟ': 'f', 'ภ': 'ph', 'ม': 'm', 'ย': 'y', 'ร': 'r', 'ล': 'l',
    'ว': 'w', 'ศ': 's', 'ษ': 's', 'ส': 's', 'ห': 'h', 'ฬ': 'l', 'อ': '', 'ฮ': 'h',
  };
  static const _fin = {
    'ก': 'k', 'ข': 'k', 'ค': 'k', 'ฆ': 'k', 'ง': 'ng', 'จ': 't', 'ช': 't', 'ซ': 't', 'ฎ': 't', 'ฏ': 't',
    'ฐ': 't', 'ฑ': 't', 'ฒ': 't', 'ด': 't', 'ต': 't', 'ถ': 't', 'ท': 't', 'ธ': 't', 'ศ': 't', 'ษ': 't',
    'ส': 't', 'ณ': 'n', 'ญ': 'n', 'น': 'n', 'ร': 'n', 'ล': 'n', 'ฬ': 'n', 'บ': 'p', 'ป': 'p', 'พ': 'p',
    'ฟ': 'p', 'ภ': 'p', 'ม': 'm', 'ย': 'i', 'ว': 'o',
  };
  static const _after = {
    'ะ': 'a', 'ั': 'a', 'า': 'a', 'ำ': 'am', 'ิ': 'i', 'ี': 'i', 'ึ': 'ue', 'ื': 'ue', 'ุ': 'u', 'ู': 'u',
  };
  static const _lead = {'เ': 'e', 'แ': 'ae', 'โ': 'o', 'ใ': 'ai', 'ไ': 'ai'};

  static bool _cons(String c) => _init.containsKey(c);

  /// คำอ่านอังกฤษคร่าว ๆ ของชื่อไทย (หลัง [norm]) · ไว้เทียบเท่านั้น ไม่ได้แสดง ·
  /// บัว → bua · ฝน → fon · แบม → baem · มิ้นท์ → min
  @visibleForTesting
  static String roman(String thai) {
    final s = norm(thai).split('');
    final out = StringBuffer();
    var i = 0;
    String? at(int k) => k < s.length ? s[k] : null;
    void finalAt() {
      final c = at(i);
      if (c != null && _cons(c) && (at(i + 1) == null || _cons(at(i + 1)!) || _lead.containsKey(at(i + 1)))) {
        out.write(_fin[c] ?? _init[c]);
        i++;
      }
    }

    while (i < s.length) {
      final c = s[i];
      if (_lead.containsKey(c)) {
        final init = at(i + 1);
        if (init == null || !_cons(init)) {
          out.write(_lead[c]);
          i++;
          continue;
        }
        out.write(_init[init]);
        i += 2;
        var v = _lead[c]!;
        if (c == 'เ') {
          if (at(i) == 'ี' && at(i + 1) == 'ย') {
            v = 'ia';
            i += 2;
          } else if (at(i) == 'ื' && at(i + 1) == 'อ') {
            v = 'uea';
            i += 2;
          } else if (at(i) == 'า') {
            v = 'ao';
            i++;
          } else if (at(i) == 'อ' || at(i) == 'ิ') {
            v = 'oe';
            i++;
          }
        }
        out.write(v);
        finalAt();
        continue;
      }
      if (_cons(c)) {
        out.write(_init[c]);
        i++;
        final v = at(i);
        if (v == 'ั' && at(i + 1) == 'ว') {
          out.write('ua');
          i += 2;
        } else if (v != null && _after.containsKey(v)) {
          out.write(_after[v]);
          i++;
          if (v == 'ื' && at(i) == 'อ') i++;
        } else if (v == 'ว' && at(i + 1) != null && _cons(at(i + 1)!)) {
          out.write('ua');
          i++;
        } else if (v == 'อ' && c != 'อ' && (at(i + 1) == null || _cons(at(i + 1)!))) {
          out.write('o');
          i++;
        } else if (v != null && _cons(v)) {
          // สระเสียงสั้นที่ไม่ได้เขียน · ฝน → fon · สม → som · ถ้าตัวถัดไปขึ้นพยางค์ใหม่ = อะ
          final third = at(i + 1);
          out.write(third == null || _cons(third) || _lead.containsKey(third) ? 'o' : 'a');
        }
        finalAt();
        continue;
      }
      out.write(_after[c] ?? c);
      i++;
    }
    return out.toString();
  }
}

/// เจ้าของตอบคำถามเรื่องโทร (พิมพ์หรือพูด) · ตัดสินในเครื่อง ไม่ถามสมอง
abstract final class CallReply {
  static const cancel = -1;

  static const _thaiDigits = {'๐': '0', '๑': '1', '๒': '2', '๓': '3', '๔': '4', '๕': '5', '๖': '6', '๗': '7', '๘': '8', '๙': '9'};

  /// คำลงท้าย/คำประกอบที่ไม่บอกว่าเลือกอะไร · ยาวก่อนสั้น
  static const _fillers = [
    'ครับผม', 'ค่ะ', 'คะ', 'ค่า', 'ครับ', 'คับ', 'จ้ะ', 'จ้า', 'จ๊ะ', 'น่ะ', 'นะ', 'เลย', 'หน่อย', 'ด้วย',
    'หมายเลข', 'ลำดับ', 'อันที่', 'คนที่', 'เบอร์ที่', 'ข้อที่', 'ที่', 'อัน', 'คน', 'เบอร์', 'ข้อ', 'ตัว',
    'เอา', 'โทรหา', 'โทร', 'หา', 'ไป', 'ให้', 'number', 'please',
  ];

  /// 🔴 ห้ามใส่คำสั้นอย่าง "one" ใน [_fillers] · ตัดกลางคำแล้ว "none" เหลือ "n" ไม่ถูกนับว่ายกเลิก ·
  /// ใส่รูปที่มี one ไว้ตรงนี้แทน
  static const _ordinals = {
    'หนึ่ง': 0, 'แรก': 0, 'สอง': 1, 'สาม': 2, 'สี่': 3, 'ห้า': 4, 'หก': 5,
    'first': 0, 'firstone': 0, 'one': 0, 'second': 1, 'secondone': 1, 'two': 1, 'third': 2, 'thirdone': 2,
    'three': 2, 'fourth': 3, 'four': 3, 'fifth': 4, 'five': 4, 'sixth': 5, 'six': 5,
  };

  static const _lastWords = {'สุดท้าย', 'last', 'lastone'};

  static const _noneWords = {
    'ไม่', 'ไม่ใช่', 'ไม่ใช่ทั้งหมด', 'ไม่ใช่สักคน', 'ไม่ใช่เลย', 'ไม่มี', 'ไม่ต้อง', 'ไม่ต้องแล้ว', 'ยกเลิก',
    'ช่างมัน', 'ไม่แล้ว', 'none', 'no', 'nope', 'cancel', 'noneofthem', 'nevermind',
  };

  static final _unsavedWords = RegExp(r'ไม่ได้บันทึก|ไม่ได้เซฟ|ยังไม่บันทึก|ไม่มีชื่อ|โทรมา|โทรเข้า|ไม่ได้รับ|unsaved|not saved|called|missed', caseSensitive: false);
  static final _latestWords = RegExp(r'ล่าสุด|เมื่อกี้|latest|last call|most recent', caseSensitive: false);

  static String _digits(String s) => s.split('').map((c) => _thaiDigits[c] ?? c).join();

  static String _squash(String text) {
    var t = _digits(text.toLowerCase()).replaceAll(RegExp(r"[\s.,!?'’\-:;()]+"), '');
    for (var guard = 0; guard < 8; guard++) {
      final before = t;
      for (final f in _fillers) {
        t = t.replaceAll(f, '');
      }
      if (t == before) break;
    }
    return t;
  }

  /// เลือกคนไหน (0..) · [cancel] = ไม่ใช่ทั้งหมด · null = ข้อความนี้ไม่ได้ตอบเรื่องนี้ (ส่งให้สมองคิดตามปกติ)
  static int? choice(String text, List<CallCandidate> choices) {
    if (choices.isEmpty || text.trim().isEmpty) return null;
    final t = _digits(text.toLowerCase());

    // เลขท้าย / เบอร์เต็ม
    final runs = RegExp(r'[0-9]+').allMatches(t.replaceAll(RegExp(r'(?<=[0-9])[\s\-](?=[0-9])'), '')).map((m) => m.group(0)!);
    for (final r in runs) {
      if (r.length < 3) continue;
      final hits = [
        for (var i = 0; i < choices.length; i++)
          if (choices[i].digits.endsWith(r) || (r.length >= 9 && r.endsWith(choices[i].key))) i,
      ];
      if (hits.length == 1) return hits.single;
      // เบอร์ใหม่ทั้งเบอร์ที่ไม่อยู่ในรายการ = ให้สมองรับไปทำต่อ
      if (r.length >= 9) return null;
    }

    // ตัวเลือกเดียว = เธอถามว่า "ใช่คนนี้ไหมคะ" · "ใช่" / "ไม่ใช่" ตอบตรงนั้นเลย
    if (choices.length == 1) {
      final yn = confirm(text);
      if (yn != null) return yn ? 0 : cancel;
    }
    final rest = _squash(text);
    if (_noneWords.contains(rest)) return cancel;
    if (RegExp(r'^[1-9]$').hasMatch(rest)) {
      final i = int.parse(rest) - 1;
      return i < choices.length ? i : null;
    }
    final ord = _ordinals[rest];
    if (ord != null) return ord < choices.length ? ord : null;
    if (_lastWords.contains(rest)) return choices.length - 1;

    // เอ่ยชื่อ · ต้องตรงคนเดียว
    final said = CallNameMatch.norm(text);
    final named = <int>{};
    for (var i = 0; i < choices.length; i++) {
      final name = choices[i].name;
      if (name == null) continue;
      final full = CallNameMatch.norm(name);
      final parts = [
        full,
        for (final p in name.split(RegExp(r'[\s,./()\-]+'))) CallNameMatch.norm(p),
      ].where((p) => p.length >= 3);
      if (parts.any(said.contains)) named.add(i);
    }
    if (named.length == 1) return named.single;

    // "เบอร์ที่โทรมา" · "ที่ไม่ได้บันทึก" · "ล่าสุด"
    final unsaved = [
      for (var i = 0; i < choices.length; i++)
        if (choices[i].unsaved) i,
    ];
    if (unsaved.isNotEmpty && (_unsavedWords.hasMatch(text) || _latestWords.hasMatch(text))) {
      if (unsaved.length == 1) return unsaved.single;
      if (_latestWords.hasMatch(text)) {
        var best = unsaved.first;
        for (final i in unsaved) {
          if (choices[i].at != null && choices[best].at != null && choices[i].at!.isAfter(choices[best].at!)) best = i;
        }
        return best;
      }
    }
    return null;
  }

  static const _yes = {
    'ใช่', 'ใช่เลย', 'ใช่แล้ว', 'โทร', 'โทรเลย', 'โทรได้', 'โทรได้เลย', 'โทรไปเลย', 'โทรเลยจ้า', 'ตกลง', 'ได้',
    'ได้เลย', 'โอเค', 'โอเคโทรเลย', 'เอา', 'เอาเลย', 'จัดไป', 'ยืนยัน', 'ok', 'okay', 'yes', 'yeah', 'yep', 'sure',
    'callnow', 'call', 'goahead', 'doit',
  };
  static const _no = {
    'ไม่', 'ไม่ใช่', 'ไม่โทร', 'ไม่ต้อง', 'ไม่ต้องโทร', 'ยกเลิก', 'ไม่เอา', 'เดี๋ยวก่อน', 'รอก่อน', 'ยังไม่โทร',
    'ยังก่อน', 'ยังไม่ต้อง', 'no', 'nope', 'cancel', 'stop', 'wait', 'dont', 'notnow',
  };
  static const _polite = ['ครับผม', 'ค่ะ', 'คะ', 'ค่า', 'ครับ', 'คับ', 'จ้ะ', 'จ้า', 'จ๊ะ', 'น่ะ', 'นะ', 'please'];

  /// ตอบ "โทร" ชัด ๆ ("โทรเลย" "call now" "ยืนยัน") · คุยด้วยเสียงต้องใช้ตัวนี้ ไม่ใช่แค่ "ได้" "โอเค" "ใช่"
  ///
  /// 🔴 คุยด้วยเสียง เธอถามเรื่องอื่นต่อได้ขณะกล่องยืนยันยังเปิดอยู่ ("บอกเขาว่าบ่ายสองใช่ไหมคะ") แล้วเจ้าของ
  /// ตอบ "ใช่" = ตอบคำถามนั้น ไม่ใช่สั่งให้กดโทรตอนนี้ · คำปฏิเสธไม่ต้องเข้มขนาดนี้ (ไม่โทร = ปลอดภัย)
  static bool saysCall(String text) =>
      confirm(text) == true && RegExp(r'โทร|call|ยืนยัน|go\s*ahead|do\s*it', caseSensitive: false).hasMatch(text);

  /// ตอบกล่องยืนยันการโทรด้วยคำสั้น ๆ · true = โทร · false = ไม่โทร · null = ไม่ใช่คำตอบ
  ///
  /// 🔴 ทั้งประโยคต้องเป็นคำตอบ ไม่ใช่แค่มีคำว่า "ได้" อยู่ข้างใน · "ได้ยินไหม" "ไม่รู้สิ" ต้องไม่โทร
  static bool? confirm(String text) {
    var t = text.toLowerCase().replaceAll(RegExp(r"[\s.,!?'’\-]+"), '');
    for (var guard = 0; guard < 3; guard++) {
      final before = t;
      for (final p in _polite) {
        if (t.endsWith(p) && t.length > p.length) t = t.substring(0, t.length - p.length);
      }
      if (t == before) break;
    }
    if (_yes.contains(t)) return true;
    if (_no.contains(t)) return false;
    return null;
  }
}
