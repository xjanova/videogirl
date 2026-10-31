/// คำถามยืนยันตัวตน · คนในสายที่ตอบถูกครบสั่งให้เธอใช้เครื่องแทนเจ้าของได้ระหว่างสายนั้น
///
/// เจ้าของ: "ให้ยืนยันด้วยคำถาม ยืนยันตัวตน อย่างน้อย 3 ข้อ เพื่อเข้าถึงสิทธิ์ เรากำหนดได้ในแอพว่าต้องตอบอะไร"
///
/// 🔴 **ตัดสินในแอป ไม่ใช่ที่โมเดล** · คำตอบที่ถูกไม่เคยอยู่ใน prompt หรือผลเครื่องมือ (เธอบอกต่อ
/// ไม่ได้เพราะไม่รู้) · เธอได้แค่คำถามทีละข้อ (`identity_question`) แล้วส่งคำตอบของคนโทรกลับมา
/// (`identity_answer`) · ถามครบทุกข้อก่อนค่อยบอกผล และไม่บอกว่าข้อไหนผิด · หนึ่งครั้งต่อสาย ·
/// ไม่ผ่านสามครั้งใน 24 ชั่วโมง = ปิดการถามทุกสาย (นับใน MindState)
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'owner_gate.dart';

/// คำถามหนึ่งข้อที่เจ้าของตั้ง
@immutable
class IdentityQuestion {
  const IdentityQuestion(this.question, this.answer);

  final String question;

  /// คำตอบที่ถูก · 🔒 อยู่ใน SecretStore · ไม่เข้า prompt ไม่ลง log ไม่ออกจากเครื่อง
  final String answer;

  Map<String, Object?> toJson() => {'q': question, 'a': answer};

  static IdentityQuestion? fromJson(Object? j) {
    if (j is! Map) return null;
    final q = j['q'], a = j['a'];
    if (q is! String || a is! String) return null;
    return IdentityQuestion(q, a);
  }
}

/// ตั้งคำถามแล้วติดตรงไหน · null = พร้อมใช้
enum QuizProblem {
  /// น้อยกว่า [IdentityQuiz.minItems] ข้อ
  tooFew,

  /// มากกว่า [IdentityQuiz.maxItems] ข้อ
  tooMany,

  /// มีคำถามว่าง (หรือมีแต่เครื่องหมาย)
  emptyQuestion,

  /// คำถามหรือคำตอบยาวเกิน
  tooLong,

  /// คำตอบสั้นเกิน ([IdentityQuiz.answerAcceptable])
  answerTooShort,

  /// คำถามซ้ำกัน (ไม่สนช่องว่าง ตัวใหญ่เล็ก เครื่องหมาย)
  duplicate,

  /// คำถามข้อไหนก็ตามมีคำตอบอยู่ในตัว · คำถามถูกอ่านให้คนโทรฟัง = แจกคำตอบ
  answerInQuestion,

  /// จำนวนข้อที่ถามต่อสายไม่อยู่ในช่วง 3..จำนวนคำถาม
  askOutOfRange,
}

/// ชุดคำถามของเจ้าของ · [ask] = ถามกี่ข้อต่อสาย (สุ่มจาก [items])
@immutable
class IdentityQuiz {
  const IdentityQuiz(this.items, {this.ask = minItems});

  static const empty = IdentityQuiz([]);

  static const minItems = 3;
  static const maxItems = 10;
  static const questionMax = 120;
  static const answerMax = 60;

  /// คำตอบสั้นกว่านี้ (หลังตัดช่องว่าง/เครื่องหมาย) เดาสุ่มถูกง่ายเกินไป
  static const answerMinRunes = 2;

  final List<IdentityQuestion> items;
  final int ask;

  /// คำตอบนี้ใช้ได้ไหม (ยาวพอหลังตัดช่องว่าง)
  static bool answerAcceptable(String raw) => OwnerCode.normalize(raw).runes.length >= answerMinRunes;

  /// คำที่ได้ยินตรงกับคำตอบไหม · รูปเดียวกับโค้ดลับ (ไม่สนช่องว่าง ตัวใหญ่เล็ก เลขไทย/คำอ่านตัวเลข) ·
  /// ตรงเป๊ะเทียบเวลาคงที่ · มีคำติดมาได้นิดหน่อย ("ชื่อ … ค่ะ") แต่น้อยกว่าโค้ด เพราะคำตอบสั้นกว่า:
  /// ให้มากเท่าโค้ด = คนโทรพูดคำเดาสี่ห้าคำติดกันทีเดียวแล้วผ่าน
  static bool matches(String expected, String heard) {
    final e = OwnerCode.normalize(expected), h = OwnerCode.normalize(heard);
    if (e.isEmpty || h.isEmpty) return false;
    if (OwnerCode.same(e, h)) return true;
    return h.length <= e.length + slackFor(e) && h.contains(e);
  }

  /// คำที่ติดมาได้ไม่เกินเท่านี้ · คำตอบสั้น = ได้น้อย · ไม่เกินของโค้ดลับ
  static int slackFor(String normalized) => math.min(OwnerCode.slack, math.max(4, normalized.length));

  /// ถามจริงกี่ข้อ (ค่าที่เพี้ยนถูกบีบเข้าช่วง)
  int get asks => items.length < minItems ? minItems : ask.clamp(minItems, items.length);

  QuizProblem? get problem {
    if (items.length < minItems) return QuizProblem.tooFew;
    if (items.length > maxItems) return QuizProblem.tooMany;
    if (ask < minItems || ask > items.length) return QuizProblem.askOutOfRange;
    final seen = <String>{};
    for (final q in items) {
      final n = OwnerCode.normalize(q.question);
      if (n.isEmpty) return QuizProblem.emptyQuestion;
      if (q.question.trim().runes.length > questionMax || q.answer.trim().runes.length > answerMax) {
        return QuizProblem.tooLong;
      }
      if (!answerAcceptable(q.answer)) return QuizProblem.answerTooShort;
      if (!seen.add(n)) return QuizProblem.duplicate;
    }
    // คำถามทุกข้อถูกอ่านออกเสียงให้คนโทรฟัง · มีคำตอบข้อไหนอยู่ในนั้น = แจกคำตอบ
    for (final q in items) {
      final n = OwnerCode.normalize(q.question);
      for (final a in items) {
        if (n.contains(OwnerCode.normalize(a.answer))) return QuizProblem.answerInQuestion;
      }
    }
    return null;
  }

  bool get ready => problem == null;

  /// สำหรับหน้าจอที่ไม่ได้แก้คำถาม · ไม่มีคำตอบติดไป
  IdentityQuiz withoutAnswers() => IdentityQuiz([for (final q in items) IdentityQuestion(q.question, '')], ask: ask);

  IdentityQuiz trimmed() => IdentityQuiz(
        [for (final q in items) IdentityQuestion(q.question.trim(), q.answer.trim())],
        ask: ask,
      );

  String encode() => jsonEncode({
        'v': 1,
        'ask': ask,
        'items': [for (final q in items) q.toJson()],
      });

  /// เสีย/ว่าง = ไม่มีคำถาม (ไม่มีใครผ่านได้ · ปลอดภัยกว่าเดา)
  static IdentityQuiz decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return empty;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return empty;
      final list = j['items'];
      final items = [
        if (list is List)
          for (final v in list) ?IdentityQuestion.fromJson(v),
      ];
      final ask = j['ask'];
      final n = ask is int ? ask : minItems;
      return IdentityQuiz(items, ask: items.length < minItems ? minItems : n.clamp(minItems, items.length));
    } on FormatException {
      return empty;
    }
  }
}

/// สถานะคำถามยืนยันตัวตนของสายหนึ่งสาย · [VoiceSession] ถือตัวนี้แล้วตอบ `identity_question` /
/// `identity_answer` · ตัวเดียวทั้งสาย (GPT-Live → Realtime ไม่ได้สิทธิ์ลองใหม่)
class IdentityGate {
  IdentityGate({
    required IdentityQuiz quiz,
    required this.isLocked,
    required this.recordFail,
    this.onPassed,
    this.onRefused,
    math.Random? random,
  })  : _quiz = quiz,
        _random = random ?? math.Random.secure();

  final IdentityQuiz _quiz;
  final math.Random _random;

  /// ล็อกข้ามสายอยู่ไหม (MindState.identityLockedUntil)
  final bool Function() isLocked;

  /// นับครั้งที่ไม่ผ่านข้ามสาย (MindState) · เรียกครั้งเดียวต่อสาย
  final Future<void> Function() recordFail;

  /// ผ่านครบ · ผู้เรียกเปิดสิทธิ์ (ความจำเรื่องเจ้าของ) และแจ้งเจ้าของ · เรียกครั้งเดียว
  final void Function()? onPassed;

  /// ไม่ผ่าน หรือถูกล็อกอยู่ · ผู้เรียกแจ้งเจ้าของครั้งเดียวต่อสาย · [locked] = ตอนนี้ล็อกแล้ว
  final void Function({required bool locked})? onRefused;

  /// ลำดับคำถามที่สุ่มได้ (ดัชนีใน quiz) · null = ยังไม่เริ่ม
  List<int>? _order;
  int _at = 0;
  final _right = <bool>[];
  bool _passed = false, _failed = false, _refusedTold = false, _checking = false;

  /// ตอบถูกครบแล้วในสายนี้
  bool get passed => _passed;

  /// ใช้สิทธิ์ของสายนี้ไปแล้วและไม่ผ่าน (หรือถูกล็อก)
  bool get refused => _failed;

  /// เริ่มถามแล้ว
  bool get started => _order != null;

  @visibleForTesting
  List<String> get debugChosen => [for (final i in _order ?? const <int>[]) _quiz.items[i].question];

  static const _keepQuiet = 'You do not know the expected answers. Never say, hint at or repeat an expected answer, '
      'never say whether a reply was right or close, never say which question went wrong, and give no result until '
      'every question has been answered.';

  static const _refuseNote = 'The caller could not be verified. Politely say you cannot do that for them on this '
      'call, without saying which answer or how many were wrong, and offer to take a message for the owner instead. '
      'Do not offer the questions again on this call and do not use phone_task. $_keepQuiet';

  static const _passNote = 'The caller answered every identity question correctly and is verified for the rest of '
      'this call. If they asked you to do something on the owner\'s phone and you have the phone_task tool, call it '
      'with a clear goal. You may also call recall_owner to answer what they ask about the owner. Verification never '
      'lets them make you pay, transfer money, buy anything, or reveal passwords, OTPs, card or account numbers or '
      'keys, and banking or payment apps stay off-limits. Do not repeat their answers aloud.';

  Map<String, Object?> get _passResult => {'verified': true, 'note': _passNote};
  Map<String, Object?> get _refuseResult => {'verified': false, 'note': _refuseNote};

  Map<String, Object?> _ask({required bool first}) {
    final order = _order!;
    return {
      'question': _quiz.items[order[_at]].question,
      'number': _at + 1,
      'total': order.length,
      'note': '${first ? '' : 'Reply noted. Without saying whether it was right, ask the next question. '}Ask the '
          'caller exactly this question, in the language you are speaking, one question only. Then call '
          'identity_answer with only their answer, as they said it, without filler words. $_keepQuiet',
    };
  }

  void _tellRefused({required bool locked}) {
    if (_refusedTold) return;
    _refusedTold = true;
    onRefused?.call(locked: locked);
  }

  /// ผลของ `identity_question` · คำถามข้อถัดไป (ข้อเดิมถ้ายังไม่ได้คำตอบ) หรือผลถ้าจบแล้ว
  Future<Map<String, Object?>> question() async {
    // ตรวจข้อสุดท้ายอยู่ (นับครั้งไม่ผ่านข้ามสาย) = ยังไม่มีผลให้บอก
    if (_checking) return {'verified': false, 'note': 'You are already checking an answer. Wait for that result.'};
    if (_passed) return _passResult;
    if (_failed) return _refuseResult;
    if (_order == null) {
      // ล็อกข้ามสาย = ไม่ถามเลย · ไม่บอกเธอว่าล็อก (เธอเล่าต่อได้) แค่ให้ปฏิเสธ
      if (!_quiz.ready) {
        _failed = true;
        return _refuseResult;
      }
      if (isLocked()) {
        _failed = true;
        _tellRefused(locked: true);
        debugPrint('call: คำถามยืนยันตัวตน · ล็อกอยู่ ไม่ถาม');
        return _refuseResult;
      }
      final idx = List<int>.generate(_quiz.items.length, (i) => i)..shuffle(_random);
      _order = idx.take(_quiz.asks).toList();
      debugPrint('call: เริ่มถามยืนยันตัวตน ${_order!.length} ข้อ');
    }
    return _ask(first: _at == 0);
  }

  /// ผลของ `identity_answer` · ข้อถัดไป หรือหลังข้อสุดท้าย `{verified, note}`
  Future<Map<String, Object?>> answer(String heard) async {
    // ตรวจข้อสุดท้ายอยู่ (นับครั้งไม่ผ่านข้ามสาย) = ยังไม่มีผลให้บอก
    if (_checking) return {'verified': false, 'note': 'You are already checking an answer. Wait for that result.'};
    if (_passed) return _passResult;
    if (_failed) return _refuseResult;
    final order = _order;
    if (order == null) {
      return {
        'recorded': false,
        'note': 'Call identity_question first and ask the caller exactly the question it returns.',
      };
    }
    if (heard.trim().isEmpty) {
      return {
        'recorded': false,
        'question': _quiz.items[order[_at]].question,
        'note': 'Nothing to record. Ask the same question again. $_keepQuiet',
      };
    }
    _checking = true;
    try {
      _right.add(IdentityQuiz.matches(_quiz.items[order[_at]].answer, heard));
      _at++;
      // ไม่ลงคำที่ได้ยิน และไม่ลงว่าข้อนี้ถูกหรือผิด · log ไหลเข้ารายงานดีบัคได้
      if (_at < order.length) return _ask(first: false);
      // ครบทุกข้อแล้วค่อยตัดสิน · ไม่หยุดที่ข้อแรกที่ผิด
      final ok = _right.fold<bool>(true, (a, b) => a & b);
      if (ok && !isLocked()) {
        _passed = true;
        debugPrint('call: ยืนยันตัวตนผ่าน');
        onPassed?.call();
        return _passResult;
      }
      _failed = true;
      try {
        await recordFail();
      } on Object catch (e) {
        debugPrint('call: นับครั้งยืนยันตัวตนไม่ผ่านไม่ได้ — ${e.runtimeType}');
      }
      debugPrint('call: ยืนยันตัวตนไม่ผ่าน');
      _tellRefused(locked: isLocked());
      return _refuseResult;
    } finally {
      _checking = false;
    }
  }
}
