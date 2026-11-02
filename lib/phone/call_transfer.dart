/// น้องมายโอนสายคนโทรไปหาเจ้าของอีกเบอร์ — ลำดับบทพูด (ฝั่งสายอยู่ที่ CallTransfer.kt)
///
/// เจ้าของ: "สามารถส่งต่อสายไปหาเจ้าของ อีกเบอร์ได้ถ้าคู่สนทนายืนยันว่าจะคุยกับเจ้าของเท่านั้น แต่ มายด์จะทวน
/// ข้อมูลเรื่องชื่อ ที่จะติดต่อก่อน แล้วจะบอกว่า จะไปดูก่อนนะว่าเจ้าของหรือบอส ว่างไหม ... ถ้าเบอร์ที่มายด์โอนให้
/// ไม่ว่าง หรือมายด์พูดแล้วเจ้าของไม่รับ มายด์ต้องกลับมาส่งข่าวได้"
///
/// แยกไฟล์เพราะคำไทยใน [OwnerReply] ต้อง**จับให้ได้**จากคำพูดของเจ้าของ ไม่ใช่ข้อความที่ผู้ใช้เห็น
/// (ดู test/i18n_test.dart) · บทที่เธอพูดมาจาก i18n ([TransferScript])
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// เจ้าของตอบว่าอย่างไร ตอนเธอถามว่าจะรับสายไหม
enum OwnerAnswer { yes, no, unclear }

abstract final class OwnerReply {
  /// "ไม่เป็นไร ต่อเลย" = รับ · ต้องลบออกก่อนหาคำปฏิเสธ ไม่งั้น "ไม่" ในนั้นกลายเป็นไม่รับ
  static const _notNo = ['ไม่เป็นไร', 'ไม่มีปัญหา', 'ไม่ติด'];

  /// ปฏิเสธมาก่อนรับเสมอ · "ไม่ว่าง" มี "ว่าง" · "ไม่ได้" มี "ได้" · "ไม่รับ" มี "รับ"
  static const _noTh = [
    'ไม่', 'ยุ่ง', 'ประชุม', 'ขับรถ', 'ทีหลัง', 'โทรกลับ', 'ฝาก', 'รอก่อน', 'ไว้ก่อน', 'วางก่อน', 'อย่า',
  ];
  static const _yesTh = [
    'ได้', 'โอเค', 'ต่อ', 'คุย', 'สะดวก', 'ว่าง', 'รับ', 'เอา', 'เชิญ', 'ครับ', 'ค่ะ', 'คะ', 'จ้า', 'จ้ะ',
  ];
  static final _noEn = RegExp(
    r"\b(no|nope|not now|busy|later|can't|cannot|can not|don't|call (me |them |him |her )?back|take a message)\b",
    caseSensitive: false,
  );
  static final _yesEn = RegExp(
    r'\b(yes|yeah|yep|sure|ok|okay|go ahead|put (them|him|her) through|connect|fine)\b',
    caseSensitive: false,
  );

  static OwnerAnswer of(String? heard) {
    final said = (heard ?? '').trim();
    if (said.isEmpty) return OwnerAnswer.unclear;
    var rest = said;
    for (final w in _notNo) {
      rest = rest.replaceAll(w, ' ');
    }
    if (_noEn.hasMatch(rest) || _noTh.any(rest.contains)) return OwnerAnswer.no;
    if (rest != said || _yesEn.hasMatch(said) || _yesTh.any(said.contains)) return OwnerAnswer.yes;
    return OwnerAnswer.unclear;
  }
}

/// ผลการโอน · เธอกลับไปบอกคนโทรตามนี้ (ยกเว้น [connected] ที่เธอออกจากสายไปแล้ว)
enum TransferOutcome {
  /// รวมสายแล้ว · คนโทรคุยกับเจ้าของ
  connected,

  /// สายไม่ว่าง / กดตัดสาย
  busy,

  /// ดังจนหมดเวลาไม่มีคนรับ / ติดต่อไม่ได้
  noAnswer,

  /// เจ้าของรับแล้วบอกไม่สะดวก หรือวางไป
  declined,

  /// คนโทรวางไประหว่างรอ
  callerGone,

  /// โทรหาเจ้าของไม่ได้เลย หรือเครือข่ายไม่ให้รวมสาย ([TransferResult.detail] บอกเหตุผล)
  unavailable,
}

class TransferResult {
  const TransferResult(this.outcome, [this.detail]);
  final TransferOutcome outcome;
  final String? detail;

  @override
  String toString() => detail == null ? outcome.name : '${outcome.name}:$detail';
}

/// สถานะจาก CallTransfer.status · leg: dialing/active/held/ended/connected · caller: active/held/ended/none
class TransferState {
  const TransferState({required this.leg, required this.caller, this.ended});

  final String leg;
  final String caller;

  /// สายเจ้าของจบเพราะอะไร: busy / hung_up / cancelled / unreachable
  final String? ended;

  static TransferState? of(Object? raw) {
    if (raw is! Map) return null;
    return TransferState(
      leg: '${raw['leg'] ?? 'none'}',
      caller: '${raw['caller'] ?? 'none'}',
      ended: raw['ended'] as String?,
    );
  }
}

/// ฝั่งสาย · เทสต์ใส่ของปลอมแทน
abstract interface class TransferLine {
  /// null = กดโทรหาเจ้าของแล้ว · สตริง = เหตุผลที่โทรไม่ได้
  Future<String?> start(String number);

  /// null = ไม่มีสายเหลือแล้ว (ทุกสายจบ)
  Future<TransferState?> status();

  /// conference / merge / unsupported
  Future<String> connect({bool retry = false});

  Future<void> cancel();
  Future<void> unhold();

  /// รวมสายเสร็จ · เธอปล่อยสาย
  Future<void> done();

  /// กลับมาคุยกับคนโทรแล้ว · ล้างสถานะฝั่งสาย
  Future<void> end();
}

class NativeTransferLine implements TransferLine {
  const NativeTransferLine(this._ch);
  final MethodChannel _ch;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<String?> start(String number) async {
    try {
      return await _ch.invokeMethod<String>('transferStart', {'number': number});
    } on PlatformException {
      return 'failed';
    } on MissingPluginException {
      return 'not_android';
    }
  }

  @override
  Future<TransferState?> status() async => TransferState.of(await _call<Object>('transferStatus'));

  @override
  Future<String> connect({bool retry = false}) async =>
      await _call<String>('transferConnect', {'retry': retry}) ?? 'unsupported';

  @override
  Future<void> cancel() => _call<void>('transferCancel');

  @override
  Future<void> unhold() => _call<void>('transferUnhold');

  @override
  Future<void> done() => _call<void>('transferDone');

  @override
  Future<void> end() => _call<void>('transferEnd');
}

/// บทที่เธอพูดกับเจ้าของในสายที่สอง · ภาษาของเจ้าของ (มาจาก i18n)
class TransferScript {
  const TransferScript({
    required this.brief,
    required this.askAgain,
    required this.connecting,
    required this.declined,
    required this.cannotJoin,
  });

  /// "มีคุณสมชายโทรมาเรื่องสั่งทำเว็บค่ะ จะรับสายไหมคะ"
  final String brief;
  final String askAgain;
  final String connecting;
  final String declined;
  final String cannotJoin;
}

/// ลำดับการโอน · ไม่ผูกกับ [CallSession] (เสียงพูด/ฟังส่งเข้ามา) เทสต์ได้โดยไม่มีสายจริง
class TransferFlow {
  TransferFlow({
    required this.line,
    required this.say,
    required this.listen,
    required this.alive,
    this.prepare,
    this.ring = const Duration(seconds: 30),
    this.poll = const Duration(milliseconds: 300),
    this.settle = const Duration(milliseconds: 700),
    this.joinWait = const Duration(seconds: 6),
    this.giveBackWait = const Duration(seconds: 4),
  });

  final TransferLine line;

  /// พูดเข้าสายที่คุยอยู่ (สายเจ้าของ) · รอจนพูดจบ
  final Future<void> Function(String text) say;

  /// ฟังเจ้าของหนึ่งประโยค · null = เงียบ / ถอดไม่ได้
  final Future<String?> Function() listen;

  /// สังเคราะห์เสียงล่วงหน้าระหว่างรอสาย · เจ้าของรับแล้วไม่ต้องรอเงียบ
  final void Function(String text)? prepare;

  /// บทสนทนายังอยู่ไหม (ไม่ถูกปิด / เจ้าของไม่ได้แทรกสาย)
  final bool Function() alive;

  /// ดังนานสุดเท่านี้ · ราวเจ็ดแปดครั้ง ก่อนเครือข่ายส่งเข้าฝากข้อความ
  final Duration ring;
  final Duration poll;

  /// เจ้าของรับแล้วรอครู่หนึ่งก่อนพูด · เสียง "ฮัลโหล" กับเสียงเธอไม่ชนกัน
  final Duration settle;
  final Duration joinWait;
  final Duration giveBackWait;

  /// ชื่อ/เรื่องที่คนโทรบอก ก่อนเธออ่านให้เจ้าของฟัง · บรรทัดเดียว ไม่เกิน [max] ตัวอักษร
  /// (คนโทรพูดยาวเหยียดมาเป็น "ชื่อ" = เธอไม่ควรอ่านคำพูดของเขาทั้งหมดใส่หูเจ้าของด้วยเสียงเธอ)
  static String clip(String text, int max) {
    final one = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length <= max ? one : one.substring(0, max).trimRight();
  }

  Future<TransferResult> run(String number, TransferScript script) async {
    final why = await line.start(number);
    if (why != null) return TransferResult(TransferOutcome.unavailable, why);
    prepare?.call(script.brief);
    TransferResult result;
    try {
      result = await _ringAndAsk(script);
    } on Object {
      await line.cancel();
      result = const TransferResult(TransferOutcome.unavailable, 'failed');
    }
    if (result.outcome != TransferOutcome.connected) await _giveBack();
    return result;
  }

  Future<void> _wait(Duration d) => Future<void>.delayed(d);

  Future<TransferResult> _ringAndAsk(TransferScript script) async {
    final until = DateTime.now().add(ring);
    while (true) {
      if (!alive()) return _stop(TransferOutcome.callerGone);
      final s = await line.status();
      if (s == null || s.caller == 'ended') return _stop(TransferOutcome.callerGone);
      if (s.leg == 'active') break;
      if (s.leg == 'ended') return _ended(s.ended);
      if (DateTime.now().isAfter(until)) return _stop(TransferOutcome.noAnswer);
      await _wait(poll);
    }

    await _wait(settle);
    var text = script.brief;
    for (var round = 0;; round++) {
      final before = await _gone();
      if (before != null) return before;
      await say(text);
      final heard = await listen();
      final after = await _gone();
      if (after != null) return after;
      final answer = OwnerReply.of(heard);
      if (answer == OwnerAnswer.no) {
        await say(script.declined);
        return _stop(TransferOutcome.declined);
      }
      // ถามซ้ำแล้วยังฟังไม่ชัด · เจ้าของรับสายอยู่ คนโทรขอคุยกับเจ้าของเอง = ต่อให้ เจ้าของวางเองได้
      if (answer == OwnerAnswer.yes || round >= 1) break;
      text = script.askAgain;
    }

    await say(script.connecting);
    for (final retry in [false, true]) {
      if (!alive()) return _stop(TransferOutcome.callerGone);
      final how = await line.connect(retry: retry);
      if (how == 'unsupported') continue;
      final until = DateTime.now().add(joinWait);
      while (DateTime.now().isBefore(until)) {
        final s = await line.status();
        // ทุกสายหายไปทั้งที่สั่งรวมแล้ว = วงจบ (คนโทรหรือเจ้าของวางระหว่างรวม)
        if (s == null) return const TransferResult(TransferOutcome.callerGone);
        if (s.leg == 'connected') {
          await line.done();
          return const TransferResult(TransferOutcome.connected);
        }
        if (s.caller == 'ended') return _stop(TransferOutcome.callerGone);
        if (s.leg == 'ended') return const TransferResult(TransferOutcome.declined, 'hung_up');
        await _wait(poll);
      }
    }
    await say(script.cannotJoin);
    return _stop(TransferOutcome.unavailable, 'no_merge');
  }

  /// สายเจ้าของจบเอง หรือคนโทรวางไปแล้ว · null = ยังอยู่ครบ
  Future<TransferResult?> _gone() async {
    if (!alive()) return _stop(TransferOutcome.callerGone);
    final s = await line.status();
    if (s == null || s.caller == 'ended') return _stop(TransferOutcome.callerGone);
    if (s.leg == 'ended') return const TransferResult(TransferOutcome.declined, 'hung_up');
    return null;
  }

  Future<TransferResult> _stop(TransferOutcome outcome, [String? detail]) async {
    await line.cancel();
    return TransferResult(outcome, detail);
  }

  TransferResult _ended(String? cause) => switch (cause) {
        'busy' => const TransferResult(TransferOutcome.busy),
        'hung_up' => const TransferResult(TransferOutcome.declined, 'hung_up'),
        'unreachable' => const TransferResult(TransferOutcome.noAnswer, 'unreachable'),
        _ => const TransferResult(TransferOutcome.noAnswer),
      };

  /// รอสายเจ้าของจบจริงก่อน แล้วคืนสายคนโทรจากที่พัก · ล้างสถานะก่อนสายเจ้าของจบ = ฝั่งสายจำไม่ได้ว่า
  /// ต้องคืนสายใคร คนโทรค้างพักสายเงียบ ๆ จนวางเอง
  Future<void> _giveBack() async {
    final until = DateTime.now().add(giveBackWait);
    var nudged = false;
    while (DateTime.now().isBefore(until)) {
      final s = await line.status();
      if (s == null || s.caller == 'ended') break;
      if (s.leg == 'ended' || s.leg == 'none') {
        if (s.caller == 'active') break;
        if (!nudged) {
          nudged = true;
          await line.unhold();
        }
      }
      await _wait(poll);
    }
    await line.end();
  }
}
