/// ขั้นตอนที่เจ้าของสอนให้ดูหนึ่งรอบ แล้วเธอทำซ้ำได้ (แบบ "มาโคร")
///
/// เจ้าของเลือก (2026-10-31): ทำทั้งแบบสั่งด้วยคำพูดและแบบสอนให้ดู โดยเริ่มจากแบบสั่งด้วยคำพูด
///
/// ## ทำไมเป็นแบบนี้
/// - จำเป็น "ปุ่มอะไร" (ข้อความ คำอธิบาย ชื่อ id) ไม่ใช่ "พิกัดบนจอ" · หน้าแอปขยับนิดหน่อยก็ยังหาเจอ
/// - หาไม่เจอ (แอปอัปเดตหน้าตาเปลี่ยน) ไม่กดมั่ว · หยุดแล้วส่งขั้นที่เหลือให้ [PhoneAgent] ทำต่อด้วยการอ่านจอ
/// - ทุกขั้นที่กดผ่าน [PhonePolicy] ชุดเดียวกับงานที่สั่งด้วยคำพูด · ปุ่มส่ง/จ่าย/ลบ ถามเจ้าของก่อนเสมอ
/// - ช่องรหัสผ่าน: Android ไม่จำตัวอักษร · เล่นซ้ำถึงขั้นนั้นจะหยุดให้เจ้าของใส่เอง
library;

import 'dart:convert';

import 'hands_bridge.dart';
import 'phone_action.dart';
import 'phone_policy.dart';
import 'phone_task.dart';

/// หนึ่งขั้นที่จำไว้ · [kind] = tap / long / type / scroll / app
class MacroStep {
  const MacroStep({
    required this.kind,
    this.package = '',
    this.app = '',
    this.text = '',
    this.desc = '',
    this.vid = '',
    this.cls = '',
    this.typed = '',
    this.pwd = false,
    this.dir = '',
  });

  /// จากฝั่ง Android (recordStop) หรือจากที่เก็บ
  static MacroStep? fromMap(Map<Object?, Object?> m) {
    String str(String k) => m[k] is String ? (m[k] as String).trim() : '';
    final kind = str('kind');
    if (!const {'tap', 'long', 'type', 'scroll', 'app'}.contains(kind)) return null;
    return MacroStep(
      kind: kind,
      package: str('package'),
      app: str('app'),
      text: str('text'),
      desc: str('desc'),
      vid: str('vid'),
      cls: str('cls'),
      typed: m['typed'] is String ? m['typed'] as String : '',
      pwd: m['pwd'] == true,
      dir: str('dir'),
    );
  }

  final String kind;
  final String package;
  final String app;
  final String text;
  final String desc;
  final String vid;
  final String cls;

  /// ข้อความที่เจ้าของพิมพ์ (ขั้น type) · ว่างเสมอถ้าเป็นช่องรหัสผ่าน
  final String typed;
  final bool pwd;
  final String dir;

  String get label => text.isNotEmpty ? text : (desc.isNotEmpty ? desc : vid);

  Map<String, Object?> toJson() => {
        'kind': kind,
        if (package.isNotEmpty) 'package': package,
        if (app.isNotEmpty) 'app': app,
        if (text.isNotEmpty) 'text': text,
        if (desc.isNotEmpty) 'desc': desc,
        if (vid.isNotEmpty) 'vid': vid,
        if (cls.isNotEmpty) 'cls': cls,
        if (typed.isNotEmpty && !pwd) 'typed': typed,
        if (pwd) 'pwd': true,
        if (dir.isNotEmpty) 'dir': dir,
      };

  /// บรรทัดที่บอกสมองตอนต้องทำต่อเอง
  String describe() => switch (kind) {
        'app' => 'open the app "${app.isNotEmpty ? app : package}"',
        'tap' => 'tap "$label"${app.isNotEmpty ? ' in $app' : ''}',
        'long' => 'long-press "$label"${app.isNotEmpty ? ' in $app' : ''}',
        'type' => pwd ? 'the owner types a password themselves' : 'type "$typed" into the field "$label"',
        'scroll' => 'scroll ${dir.isEmpty ? 'down' : dir}',
        _ => kind,
      };
}

class PhoneMacro {
  const PhoneMacro({required this.name, required this.steps, required this.created});

  static const maxSteps = 200;
  static const maxNameLength = 60;

  final String name;
  final List<MacroStep> steps;
  final DateTime created;

  Map<String, Object?> toJson() => {
        'name': name,
        'created': created.millisecondsSinceEpoch,
        'steps': [for (final s in steps) s.toJson()],
      };

  static PhoneMacro? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'] is String ? (raw['name'] as String).trim() : '';
    final steps = raw['steps'];
    if (name.isEmpty || steps is! List) return null;
    final parsed = [for (final s in steps) if (s is Map) MacroStep.fromMap(s)].whereType<MacroStep>().toList();
    if (parsed.isEmpty) return null;
    final at = raw['created'];
    return PhoneMacro(
      name: name,
      steps: parsed.take(maxSteps).toList(),
      created: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static List<PhoneMacro> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final m in list) PhoneMacro.fromJson(m)].whereType<PhoneMacro>().toList();
    } on FormatException {
      return const [];
    }
  }

  static String encodeAll(List<PhoneMacro> all) => jsonEncode([for (final m in all) m.toJson()]);

  /// ขั้นที่จำมาจาก Android · ทิ้งขั้นที่ไม่รู้จัก · พิมพ์ซ้ำในช่องเดิมติดกันเหลืออันสุดท้าย
  static List<MacroStep> clean(List<Map<Object?, Object?>> raw) {
    final out = <MacroStep>[];
    for (final m in raw) {
      final s = MacroStep.fromMap(m);
      if (s == null) continue;
      final last = out.isEmpty ? null : out.last;
      if (last != null && s.kind == 'type' && last.kind == 'type' && last.vid == s.vid && last.package == s.package) {
        out[out.length - 1] = s;
        continue;
      }
      // เปิดแอปเดิมซ้ำติดกัน (กลับมาหน้าเดิม) ไม่ต้องจำสองครั้ง
      if (last != null && s.kind == 'app' && last.kind == 'app' && last.package == s.package) continue;
      out.add(s);
      if (out.length >= maxSteps) break;
    }
    return out;
  }
}

/// ผลของการเล่นซ้ำ
class MacroRun {
  const MacroRun({required this.done, this.error, this.remaining = const []});

  /// ทำไปกี่ขั้น
  final int done;

  /// null = ครบทุกขั้น · 'stopped' / 'declined' / 'not_found' / 'password' / 'blocked' / อื่น ๆ จาก Android
  final String? error;

  /// ขั้นที่ยังไม่ได้ทำ (ให้ [PhoneAgent] ทำต่อ)
  final List<MacroStep> remaining;

  bool get ok => error == null;
}

/// เล่นขั้นตอนที่จำไว้ทีละขั้น · ใช้ภายในงานที่ [Hands.begin] แล้วเท่านั้น
class MacroPlayer {
  MacroPlayer({required this.hands, this.settle = const Duration(milliseconds: 700), this.findTries = 3});

  final Hands hands;
  final Duration settle;

  /// อ่านจอหาปุ่มกี่รอบ (รอแอปโหลด) ก่อนยอมแพ้
  final int findTries;

  Future<MacroRun> play(
    PhoneMacro macro, {
    required String goal,
    required PhoneConfirm confirm,
    required int Function() nextAskId,
    required void Function(String what) onStep,
    required bool Function() stopped,
    required String Function(MacroStep step) describe,
  }) async {
    final steps = macro.steps;
    for (var i = 0; i < steps.length; i++) {
      if (stopped()) return MacroRun(done: i, error: 'stopped', remaining: steps.sublist(i));
      final step = steps[i];
      onStep(describe(step));
      HandsReply r;
      switch (step.kind) {
        case 'app':
          r = await hands.openApp(step.package.isNotEmpty ? step.package : step.app);
          if (r.ok) await Future<void>.delayed(settle);
        case 'scroll':
          r = await hands.act('scroll', dir: step.dir.isEmpty ? 'down' : step.dir);
        case 'type':
          if (step.pwd) return MacroRun(done: i, error: 'password', remaining: steps.sublist(i));
          final found = await _find(step, editable: true);
          if (found == null) return MacroRun(done: i, error: 'not_found', remaining: steps.sublist(i));
          r = await hands.act('type', id: found.$1.id, text: step.typed);
        default: // tap / long
          final found = await _find(step, editable: false);
          if (found == null) return MacroRun(done: i, error: 'not_found', remaining: steps.sublist(i));
          final (node, screen) = found;
          final action = PhoneAction(step.kind == 'long' ? 'long_press' : 'tap', id: node.id);
          if (PhonePolicy.needsOwner(action, screen)) {
            final ok = await confirm(PhoneStepAsk(
              id: nextAskId(),
              goal: goal,
              action: describe(step),
              app: screen.appName,
            ));
            if (stopped()) return MacroRun(done: i, error: 'stopped', remaining: steps.sublist(i));
            if (!ok) return MacroRun(done: i, error: 'declined', remaining: steps.sublist(i));
          }
          r = await hands.act(action.kind, id: node.id);
      }
      if (!r.ok) return MacroRun(done: i, error: r.error ?? 'failed', remaining: steps.sublist(i));
    }
    return MacroRun(done: steps.length);
  }

  /// หาปุ่ม/ช่องที่ตรงกับขั้นที่จำไว้ · ให้คะแนนจาก id > ข้อความ > คำอธิบาย > ชนิด · ไม่พอ = ไม่เจอ
  Future<(ScreenNode, PhoneScreen)?> _find(MacroStep step, {required bool editable}) async {
    for (var attempt = 0; attempt < findTries; attempt++) {
      if (attempt > 0) await Future<void>.delayed(settle);
      final (r, screen) = await hands.snapshot();
      if (!r.ok || screen == null || screen.blocked) continue;
      if (step.package.isNotEmpty && screen.package.isNotEmpty && screen.package != step.package) continue;
      final best = bestMatch(step, screen, editable: editable);
      if (best != null) return (best, screen);
    }
    return null;
  }

  static String _norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  /// ปุ่มบนจอที่ตรงกับขั้นที่สุด (null = ไม่มีตัวไหนตรงพอ)
  static ScreenNode? bestMatch(MacroStep step, PhoneScreen screen, {required bool editable}) {
    final edits = screen.nodes.where((n) => n.edit).toList();
    ScreenNode? best;
    var bestScore = 0;
    for (final n in screen.nodes) {
      if (editable && !n.edit) continue;
      var score = 0;
      if (step.vid.isNotEmpty && n.vid == step.vid) score += 4;
      // ช่องพิมพ์: ข้อความในช่องเปลี่ยนตามที่พิมพ์ · เทียบคำใบ้แทน
      if (!editable && step.text.isNotEmpty && _norm(n.text) == _norm(step.text)) score += 3;
      if (step.desc.isNotEmpty && _norm(n.desc) == _norm(step.desc)) score += 3;
      if (editable && step.text.isNotEmpty && _norm(n.hint) == _norm(step.text)) score += 2;
      if (step.cls.isNotEmpty && n.cls == step.cls) score += 1;
      if (score > bestScore) {
        best = n;
        bestScore = score;
      }
    }
    if (bestScore >= 3) return best;
    // ช่องพิมพ์ช่องเดียวบนจอ = ช่องนั้นแหละ
    if (editable && edits.length == 1) return edits.single;
    return null;
  }
}
