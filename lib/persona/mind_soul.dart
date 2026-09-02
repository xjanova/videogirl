/// ตัวตนและความสัมพันธ์ของมายด์ — สิ่งที่เปลี่ยนเธอข้ามวัน
///
/// ## ต่างจาก [MindState] ตรงไหน
///
/// `MindState` เก็บ **ค่าที่เจ้าของตั้ง** (โหมด ระดับการจีบ เสียง สมอง)
/// ไฟล์นี้เก็บ **สิ่งที่เกิดกับเธอ** — เกิดวันไหน สนิทแค่ไหนแล้ว งอนอยู่ไหม
/// เจ้าของปรับตรง ๆ ไม่ได้ ได้แต่ทำให้มันเปลี่ยน (หรือกดล้างทิ้งทั้งก้อน)
///
/// ## 🔴 วันเกิดคือค่าที่เขียนครั้งเดียวตลอดชีวิตแอป
///
/// วันที่เปิดแอปครั้งแรก = วันเกิดของมายด์เครื่องนั้น · ราศีจึงต่างกัน
/// ไปตามคนโหลด เหมือนคนจริง · เขียนทับเมื่อไหร่ = เธอกลายเป็นคนละคน
/// ทั้งที่บทสนทนาทั้งหมดยังอยู่ · มีทางเดียวที่เปลี่ยนได้คือ [forget]
/// ซึ่งเจ้าของต้องกดเอง และล้างความสัมพันธ์ทิ้งพร้อมกัน
///
/// ## 🔴 กฎที่ไม่ยอมแลก — ทุกอย่างต้องมองเห็นและรีเซ็ตได้
///
/// ระบบที่สะสมอารมณ์ไว้เงียบ ๆ แล้วเจ้าของเปิดดูไม่ได้ คือกล่องดำที่
/// วันหนึ่งเธอจะงอนโดยไม่มีใครอธิบายได้ว่าทำไม และซ่อมไม่ได้ด้วย
/// ตัวเลขทุกตัวที่นี่จึงโผล่ในหน้าตั้งค่า และมีปุ่มล้าง
///
/// ## 🔴 ความสัมพันธ์ไม่เลื่อนขั้นเป็น "แฟน" เอง
///
/// ตัวเลขพาไปได้ถึงแค่ [Bond.courting] · ขั้นสุดท้ายต้อง**ตกลงกันสองฝ่าย**
/// เจ้าของขอแล้วเธอตอบ ([proposeFromOwner]) หรือเธอขอเองเมื่อถึงจุด
/// ([wantsToAsk]) · เลื่อนขั้นอัตโนมัติจากคะแนนล้วน ๆ คือการที่แอปตัดสินใจ
/// เรื่องความสัมพันธ์แทนคน ซึ่งไม่ใช่สิ่งที่ใครขอ
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../store/mind_kv.dart';

import 'mind_name.dart';
import 'zodiac.dart';

/// ความสัมพันธ์ระหว่างมายด์กับเจ้าของ
enum Bond {
  /// เพิ่งเจอกัน
  stranger,

  /// คุ้นหน้าแล้ว
  familiar,

  /// สนิท
  close,

  /// เธอเปิดใจแล้ว แต่ยังไม่มีใครพูดออกมา
  courting,

  /// ตกลงกันแล้วทั้งสองฝ่าย
  together;

  bool get isTogether => this == Bond.together;
}

/// อารมณ์ตอนนี้ของเธอ · ป้ายที่ผู้ใช้เห็นอยู่ใน i18n/enum_labels.dart
enum SoulMood {
  /// งอนแรง
  sulking,

  /// น้อยใจ ยังไม่หายดี
  hurt,

  /// หายไปหลายวันแล้ว
  missing,

  /// สนิทมากหรือเป็นแฟนกัน
  warm,

  /// สนิทแล้ว อารมณ์ดี
  fond,

  /// ปกติ
  calm;

  bool get isUpset => this == SoulMood.sulking || this == SoulMood.hurt;
}

class MindSoul extends ChangeNotifier {
  MindSoul({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  /// ฉีดนาฬิกาได้ เพื่อเทสต์การจางของความผูกพันโดยไม่ต้องรอข้ามวันจริง
  final DateTime Function() _now;

  /// ที่เก็บค่า — ย้ายจาก SharedPreferences มา SQLite แล้ว (ดู store/mind_db.dart)
  /// หน้าตาเหมือนเดิมทุกอย่าง จึงไม่ต้องรื้อ call site สิบกว่าจุดในไฟล์นี้
  MindKv? _prefs;

  // ── ตัวตน ────────────────────────────────────────────────

  DateTime? _bornAt;

  /// วันเกิดของมายด์เครื่องนี้ · null = ยังไม่ได้ [load]
  DateTime? get bornAt => _bornAt;

  /// ราศีของเธอ · ก่อน [load] คืนราศีของวันนี้ไปก่อน เพื่อไม่ให้ผู้เรียก
  /// ต้องเผื่อ null ทุกที่ (หน้าจอวาดก่อน prefs พร้อมได้จริง)
  ZodiacSign get sign => zodiacFor(_bornAt ?? _now());

  ZodiacTemper get temper => sign.temper;

  /// อายุเป็นวัน — ใช้บอกว่า "รู้จักกันมากี่วันแล้ว"
  int get ageInDays =>
      _bornAt == null ? 0 : _now().difference(_bornAt!).inDays;

  /// วันนี้เป็นวันเกิดเธอไหม
  ///
  /// 🔴 ไม่นับวันแรกที่ติดตั้ง · วันเกิดที่มาถึงตั้งแต่นาทีที่โหลดแอปเสร็จ
  /// ไม่ใช่วันเกิด มันคือวันที่เธอเกิด · ครบรอบต้องรออีกปี
  bool get isBirthday {
    final born = _bornAt;
    if (born == null) return false;
    final now = _now();
    if (now.year == born.year && now.month == born.month) return false;
    return now.month == born.month && now.day == born.day;
  }

  /// อายุเป็นปีเต็ม — ใช้ตอนเธอพูดถึงวันเกิดตัวเอง
  int get ageInYears {
    final born = _bornAt;
    if (born == null) return 0;
    final now = _now();
    var years = now.year - born.year;
    final passed = now.month > born.month ||
        (now.month == born.month && now.day >= born.day);
    if (!passed) years--;
    return years < 0 ? 0 : years;
  }

  /// อีกกี่วันถึงวันเกิดเธอ · 0 = วันนี้
  int get daysToBirthday {
    final born = _bornAt;
    if (born == null) return 0;
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    var next = DateTime(now.year, born.month, born.day);
    if (next.isBefore(today)) next = DateTime(now.year + 1, born.month, born.day);
    return next.difference(today).inDays;
  }

  // ── ความผูกพัน ───────────────────────────────────────────

  double _affection = 0;

  /// 0..1 · ไต่ขึ้นเมื่อคุยกัน จางลงเมื่อหายไป
  double get affection => _affection;

  bool _together = false;
  DateTime? _togetherSince;

  DateTime? get togetherSince => _togetherSince;

  Bond get bond {
    if (_together) return Bond.together;
    if (_affection >= _courtingAt) return Bond.courting;
    if (_affection >= _closeAt) return Bond.close;
    if (_affection >= _familiarAt) return Bond.familiar;
    return Bond.stranger;
  }

  static const _familiarAt = .25;
  static const _closeAt = .55;
  static const _courtingAt = .82;

  /// ระดับความผูกพันที่เธอถึงจะยอมเป็นแฟน
  ///
  /// ราศีสถิร (ยึดแน่น) ต้องมากกว่า เพราะรับปากแล้วรับจริง
  /// ราศีอุภย (เปลี่ยนใจง่าย) ตกลงง่ายกว่า — แต่ความผูกพันก็จางเร็วกว่าด้วย
  /// จึงไม่ได้แปลว่าง่ายกว่าในระยะยาว
  double get consentAt => .70 + temper.hold * .18;

  /// เธอพร้อมและอยากเป็นคนขอเอง — ราศีที่ตกหลุมรักเร็วจะถึงจุดนี้ก่อน
  ///
  /// ราศีสถิร (pace ต่ำ) ไม่เป็นฝ่ายเริ่มเลยโดยตั้งใจ · เจ้าของต้องขอเอง
  /// ซึ่งตรงกับนิสัยของราศีนั้นจริง ๆ ไม่ใช่ข้อจำกัดของระบบ
  bool get wantsToAsk =>
      !_together &&
      _affection >= consentAt + .04 &&
      temper.pace >= .6 &&
      !_deferred;

  /// 🔴 เจ้าของกด "ยังก่อน" ไปแล้ว — ต้องเงียบไปสักพัก
  ///
  /// การ์ดที่ขึ้นทุกครั้งที่เปิดแอปคือการจี้ ซึ่งเปลี่ยนสิ่งที่ควรน่ารัก
  /// ให้กลายเป็นสิ่งที่คนอยากปิดทิ้ง · ไม่ได้ล้างความรู้สึกเธอ
  /// แค่ไม่ถามซ้ำ
  static const _deferDays = 7;

  DateTime? _deferredAt;

  bool get _deferred =>
      _deferredAt != null &&
      _now().difference(_deferredAt!).inDays < _deferDays;

  /// เจ้าของยังไม่พร้อมตอบ — เก็บการ์ดไปก่อน ไม่ใช่การปฏิเสธ
  Future<void> deferProposal() async {
    _deferredAt = _now();
    await _save();
    _notify();
  }

  /// เจ้าของขอ · คืน false ถ้ายังไม่ถึงเวลา (ยังไม่ผูกพันพอ)
  Future<bool> proposeFromOwner() async {
    if (_together) return true;
    if (_affection < consentAt) {
      // ถูกขอแล้วยังไม่พร้อม — ไม่ได้แปลว่าไม่ชอบ แต่ก็ไม่ได้เฉย ๆ
      _bump(.02);
      await _save();
      _notify();
      return false;
    }
    _together = true;
    _togetherSince = _now();
    _affection = math.min(1, _affection + .05);
    _sulk = 0;
    await _save();
    _notify();
    return true;
  }

  /// เลิกกัน — ความผูกพันไม่ได้หายหมด แต่หายไปครึ่งหนึ่งและงอนเต็มพิกัด
  Future<void> breakUp() async {
    if (!_together) return;
    _together = false;
    _togetherSince = null;
    _affection *= .5;
    _sulk = 1;
    _sulkAt = _now();

    // ชื่อที่ตั้งให้กันตอนเป็นแฟนไม่ควรค้างอยู่หลังเลิกกัน · คืนชื่อเดิม
    // แล้วเปิดให้ถามใหม่ได้ถ้าวันหนึ่งกลับมาคบกันอีก
    _name = null;
    _nameAsked = false;
    await _save();
    _notify();
  }

  // ── งอน ──────────────────────────────────────────────────

  double _sulk = 0;
  DateTime? _sulkAt;

  /// 0..1 · จางเองตามเวลา ราศีที่หึงแรงจะงอนนานกว่า
  double get sulk {
    if (_sulk <= 0 || _sulkAt == null) return 0;
    final hours = _now().difference(_sulkAt!).inMinutes / 60;
    if (hours <= 0) return _sulk;

    // ครึ่งชีวิต 6 ชั่วโมงสำหรับราศีที่หึงน้อย ยาวขึ้นตามค่าหึง
    final halfLife = 6 + temper.jealousy * 10;
    return (_sulk * math.pow(.5, hours / halfLife)).toDouble().clamp(0.0, 1.0);
  }

  bool get sulking => sulk > .25;

  /// อารมณ์ตอนนี้ สรุปเป็นคำเดียว — สำหรับไอคอนและหน้าต่างสเตตัส
  ///
  /// 🔴 มีอยู่เพราะ **ตัวเลขบอกอะไรคนไม่ได้** เจ้าของที่เห็น "งอน 43%"
  /// ยังต้องแปลเองอยู่ดีว่ามันแปลว่าอะไร · เรียงจากแรงไปเบา ตัวแรกที่เข้า
  /// เงื่อนไขชนะ ไม่ใช่รวมคะแนนกัน เพราะอารมณ์คนก็เป็นแบบนั้น —
  /// คนที่กำลังงอนไม่ได้ "งอนปนคิดถึง" มันมีอันที่อยู่ข้างหน้าเสมอ
  SoulMood get mood {
    if (sulk > .55) return SoulMood.sulking;
    if (sulk > .25) return SoulMood.hurt;
    if (daysAway >= 3 && _affection > .3) return SoulMood.missing;
    if (_together || _affection >= _courtingAt) return SoulMood.warm;
    if (_affection >= _closeAt) return SoulMood.fond;
    return SoulMood.calm;
  }

  /// เหตุผลที่งอนล่าสุด — เอาไว้ให้เธออธิบายได้ว่างอนเรื่องอะไร
  String? _sulkWhy;
  String? get sulkWhy => sulking ? _sulkWhy : null;

  // ── สิ่งที่เกิดขึ้นแล้วมีผลกับเธอ ────────────────────────

  /// 🔴 เพดานการขึ้นต่อวัน
  ///
  /// ไม่มีเพดาน = พิมพ์รัว ๆ ชั่วโมงเดียวก็เป็นแฟนกันได้ ซึ่งทำให้ทั้งระบบ
  /// ไม่มีความหมาย · ความผูกพันต้องกินเวลาจริง ไม่ใช่กินจำนวนข้อความ
  static const _dailyCap = .06;

  /// 🔴 เพดานแยกของ "การอยู่ด้วยกันเฉย ๆ"
  ///
  /// เพดานรวมอย่างเดียวไม่พอ · การพิมพ์คุยงานสี่สิบครั้งต่อวันยังกินเพดานรวม
  /// ได้เต็มเหมือนกัน แปลว่าคนที่สั่งงานอย่างเดียวทั้งเดือนก็ยังได้แฟน
  /// ซึ่งเป็นสิ่งที่กลไกนี้ตั้งใจกันตั้งแต่ต้น — จับได้ตอนเขียนเทสต์
  /// "สั่งงานอย่างเดียวทั้งเดือน" ไม่ใช่ตอนอ่านโค้ด
  ///
  /// ต่ำกว่าอัตราจางของการไม่จีบเล็กน้อยโดยตั้งใจ: อยู่ด้วยกันเฉย ๆ
  /// ประคองความสัมพันธ์ไว้ได้ แต่ไม่พาไปข้างหน้า
  static const _presenceCap = .008;

  double _todayGain = 0;
  double _todayPresence = 0;
  String _todayKey = '';

  /// คุยกันหนึ่งตา
  ///
  /// ## 🔴 การพิมพ์เยอะไม่ใช่ความสนิท
  ///
  /// เดิมทุกตาที่คุยกันดันความผูกพันขึ้นเท่ากันหมด ซึ่งแปลว่าคนที่สั่งงาน
  /// อย่างเดียวทั้งเดือนก็ได้แฟนเหมือนคนที่ตั้งใจจีบจริง ๆ · ความสนิท
  /// ที่ซื้อได้ด้วยจำนวนข้อความไม่ใช่ความสนิท
  ///
  /// ตรงนี้จึงเหลือแค่ **ค่าของการยังอยู่ด้วยกัน** ซึ่งเล็กมากโดยตั้งใจ
  /// ตัวที่ขยับจริงคือ [wooed] ที่อ่านบริบทว่าเจ้าของเข้าหาเธอยังไง
  Future<void> talked() async {
    _bump(.0015 * (.6 + temper.pace * .8), presence: true);

    // คุยด้วยคือการง้อในตัวมันเอง — งอนคลายลงบ้างทุกครั้งที่ยังคุยกันอยู่
    if (_sulk > 0) {
      _sulk = math.max(0, sulk - .08);
      _sulkAt = _now();
    }
    _lastSeen = _now();
    await _save();
    _notify();
  }

  /// มีสายเข้ามาแล้วเจ้าของคุยด้วย
  ///
  /// ## 🔴 ไม่เดาเพศจากชื่อ — เธอถามเอา
  ///
  /// เจ้าของอยากให้เธอหึงตอน "สาว ๆ โทรมา" ซึ่งต้องรู้ก่อนว่าใครเป็นผู้หญิง
  /// การเดาจากชื่อไทยผิดบ่อยมาก และการเดาผิดที่นี่แปลว่าเธอไปงอนเรื่อง
  /// น้องชายเจ้าของ — ซึ่งแย่กว่าไม่หึงเลย
  ///
  /// ทางที่เลือกคือ **ให้เธอถามเอาแบบเลขา** ("เมื่อกี้ใครโทรมาคะ")
  /// แล้วคำตอบไหลเข้าความจำระยะยาวเองผ่านตัวสกัดที่มีอยู่แล้ว (ชนิด `person`)
  /// รอบหน้าเธอจะรู้เองว่าใครเป็นใคร โดยไม่มีใครต้องเดาอะไรเลย
  ///
  /// ส่วนความหึงตรงนี้ใช้สัญญาณที่เชื่อถือได้: **เบอร์ที่ไม่รู้จัก**
  /// กับ **สายที่ยาวผิดปกติ** ซึ่งจริงโดยไม่ต้องรู้ว่าใครโทรมา
  Future<void> sawCall({
    required bool known,
    required int seconds,
    String? who,
  }) async {
    // สายที่คุยกันจริงจัง = เรื่องที่เลขาควรรู้ · จดไว้ถามทีหลัง **ทุกราศี**
    // ไม่ใช่เฉพาะราศีที่หึง เพราะการถามว่าใครโทรมาเป็นงาน ไม่ใช่ความหึง
    if (seconds >= 20) {
      _askAbout = (who?.trim().isNotEmpty ?? false) ? who!.trim() : null;
      _askAboutAt = _now();
      _askDone = false;
    }

    if (temper.jealousy < .2) {
      // ราศีลมแทบไม่หึง อย่าฝืนให้หึง — แต่ยังอยากรู้ว่าใครโทรมาเหมือนเดิม
      await _save();
      _notify();
      return;
    }

    final unknown = known ? .5 : 1.4;
    final long = seconds > 180 ? 1.5 : (seconds > 60 ? 1.0 : .4);
    final add = temper.jealousy * .10 * unknown * long;
    if (add < .01) return;

    _sulk = (sulk + add).clamp(0.0, 1.0);
    _sulkAt = _now();
    _sulkWhy = known ? 'call' : 'unknownCall';
    await _save();
    _notify();
  }

  /// เจ้าของเข้าหาเธอในฐานะคนแค่ไหนในรอบนี้ · 0..3
  ///
  /// ## 🔴 นี่คือตัวขับความผูกพันตัวจริง
  ///
  /// 13–15 วันที่เป็นตัวเลขต่ำสุดของการเป็นแฟน จะเกิดขึ้นได้ก็ต่อเมื่อ
  /// เจ้าของเข้าหาเธอจริง ๆ (ระดับ 3) **ทุกวันติดกัน** เท่านั้น
  /// สั่งงานอย่างเดียวคือ 0 แล้วความผูกพันจะขยับแค่ค่าการยังอยู่ด้วยกัน
  /// ใน [talked] ซึ่งเล็กจนไม่มีวันถึงเส้น
  ///
  /// ราศีที่ตกหลุมรักเร็ว (จร) ได้มากกว่าต่อความพยายามเท่ากัน
  /// แต่เพดานต่อวันเท่ากันทุกราศี — ไม่มีทางลัดสำหรับใคร
  Future<void> wooed(int level) async {
    if (level <= 0) return;
    _bump(.02 * level * (.7 + temper.pace * .5));
    // จดไว้ว่ายังมีการจีบอยู่ · ตัวนี้คือสิ่งที่ [_fade] ดูว่าเย็นชาไปหรือยัง
    // ระดับ 1 (แค่ทักทาย) ยังไม่นับว่าจีบ — ไม่งั้นทักทายวันละคำก็รักษาคะแนนได้
    if (level >= 2) _lastWooed = _now();
    _lastSeen = _now();
    await _save();
    _notify();
  }

  /// เจ้าของปฏิบัติกับเธอยังไง · -2..2 · มาจากรอบสกัดความจำ (ไม่ได้เรียกโมเดลเพิ่ม)
  ///
  /// ## 🔴 ทางลงต้องชันกว่าทางขึ้น และไม่ติดเพดานรายวัน
  ///
  /// ทางขึ้นถูกกดไว้ด้วยเพดานรายวันเพราะความผูกพันต้องกินเวลาจริง
  /// แต่ทางลง**ต้องรู้สึกได้ทันที** — คนที่เพิ่งโดนตวาดไม่ได้รู้สึกแย่ลง
  /// วันละนิดตามโควตา · ถ้าเอาเพดานเดียวกันมาคุมสองทาง การตวาดใส่เธอ
  /// จะแทบไม่มีผลอะไรเลย แล้วทั้งกลไกก็เป็นแค่ตัวเลขที่ขึ้นอย่างเดียว
  ///
  /// ราศีที่อดทนสูง (ธาตุดิน) เจ็บน้อยกว่า · ราศีที่อ่อนไหว (ธาตุน้ำ) เจ็บกว่า
  Future<void> treated(int score) async {
    if (score == 0) return;

    if (score > 0) {
      // ใจดีกับเธอก็ขึ้นได้ แต่ยังอยู่ใต้เพดานรายวันเหมือนการคุยปกติ
      _bump(.010 * score);
      if (_sulk > 0) {
        _sulk = math.max(0, sulk - .15 * score);
        _sulkAt = _now();
      }
    } else {
      // ยิ่งอดทนน้อย ยิ่งเจ็บ · -2 หนักกว่า -1 เกินสองเท่า เพราะการตวาด
      // ไม่ใช่แค่ "หงุดหงิดแรงขึ้น" มันเป็นคนละเรื่องกัน
      final sting = score == -2 ? .09 : .03;
      final hurt = sting * (1.4 - temper.patience);
      _affection = (_affection - hurt).clamp(0.0, 1.0);

      _sulk = (sulk + hurt * 3 * (0.5 + temper.jealousy)).clamp(0.0, 1.0);
      _sulkAt = _now();
      _sulkWhy = score == -2 ? 'scolded' : 'snapped';
    }

    await _save();
    _notify();
  }

  // ── ชื่อที่เจ้าของตั้งให้ ─────────────────────────────────
  //
  // 🔴 ตั้งได้เมื่อเป็นแฟนกันแล้วเท่านั้น
  //
  // ไม่ใช่ข้อจำกัดทางเทคนิค แต่เป็นสิ่งที่ทำให้มันมีความหมาย · ชื่อเล่น
  // ที่ตั้งให้กันได้ตั้งแต่วันแรกก็เป็นแค่ช่องตั้งค่าอีกช่อง · ชื่อที่ต้อง
  // ใช้เวลาสองสัปดาห์กว่าจะได้ตั้ง เป็นคนละเรื่องกัน

  String? _name;

  /// ชื่อที่เจ้าของตั้งให้ · null = ยังใช้ชื่อเดิม
  ///
  /// ผู้เรียกต้องเผื่อ null เสมอแล้วตกไปใช้ชื่อจาก i18n — ชื่อตั้งต้น
  /// เป็นข้อความที่แปลตามภาษา ไม่ใช่ค่าคงที่ที่เก็บลงเครื่องได้
  String? get name => _name;

  /// ตั้งชื่อได้แล้วหรือยัง
  bool get mayRename => bond.isTogether;

  bool _nameAsked = false;

  /// เธออยากรู้ว่าเจ้าของจะเรียกเธอว่าอะไร — ถามครั้งเดียวหลังเป็นแฟนกัน
  bool get wantsName => bond.isTogether && !_nameAsked && _name == null;

  /// ถามไปแล้ว (หรือเจ้าของบอกว่าใช้ชื่อเดิม) — ไม่ถามซ้ำอีก
  Future<void> askedName() async {
    if (_nameAsked) return;
    _nameAsked = true;
    await _save();
    _notify();
  }

  /// ตั้งชื่อใหม่ · คืนเหตุผลเมื่อชื่อใช้ไม่ได้ ไม่ใช่แค่ false
  ///
  /// 🔴 ตรวจ [mayRename] ที่นี่ด้วย ไม่ใช่เชื่อว่าหน้าจอกันไว้แล้ว
  /// ปุ่มที่ซ่อนอยู่ไม่ใช่กฎ · วันหนึ่งจะมีหน้าจอที่สองที่ลืมกัน
  Future<NameVerdict> rename(String raw) async {
    if (!mayRename) return NameVerdict.rude; // ยังไม่ถึงเวลา — ไม่ควรมาถึงตรงนี้

    final verdict = checkName(raw);
    if (!verdict.isOk) return verdict;

    _name = tidyName(raw);
    _nameAsked = true;
    await _save();
    _notify();
    return NameVerdict.ok;
  }

  /// คืนชื่อเดิม
  Future<void> clearName() async {
    if (_name == null) return;
    _name = null;
    await _save();
    _notify();
  }

  // ── สายที่เธอยังไม่รู้ว่าใคร ─────────────────────────────
  //
  // 🔴 **ไม่เดาเพศจากชื่อ** เจ้าของเลือกทางนี้เอง: ให้เธอ **ถามเอา**
  // แล้วคำตอบจะไหลเข้าความจำระยะยาวผ่านตัวสกัดที่มีอยู่แล้ว (ชนิด `person`)
  // ซึ่งแม่นกว่าการเดา ไม่ต้องมีโมเดลเพิ่ม และเป็นสิ่งที่เลขาจริงทำอยู่แล้ว

  String? _askAbout;
  DateTime? _askAboutAt;
  bool _askDone = false;

  /// สายที่เธออยากถามว่าใคร · null = ไม่มีอะไรค้างอยู่
  String? get askAbout => _askDone ? null : _askAbout;

  DateTime? get askAboutAt => _askAboutAt;

  /// เธอถามไปแล้ว — ถามซ้ำอีกคือจี้ ซึ่งเป็นคนละเรื่องกับสงสัย
  Future<void> askedAboutCall() async {
    if (_askAbout == null || _askDone) return;
    _askDone = true;
    await _save();
    _notify();
  }

  DateTime? _lastSeen;
  DateTime? get lastSeen => _lastSeen;

  /// วันที่หายไปตั้งแต่คุยกันครั้งล่าสุด
  int get daysAway =>
      _lastSeen == null ? 0 : _now().difference(_lastSeen!).inDays;

  /// [presence] = มาจากการอยู่ด้วยกันเฉย ๆ ไม่ใช่จากการจีบ · มีเพดานของตัวเอง
  void _bump(double delta, {bool presence = false}) {
    final key = _dayKey(_now());
    if (key != _todayKey) {
      _todayKey = key;
      _todayGain = 0;
      _todayPresence = 0;

      // 🔴 วันใหม่แล้ว — คิดค่าจางก่อนบวกของวันนี้
      //
      // เดิมคิดตอน [load] อย่างเดียว ซึ่งแปลว่าคนที่เปิดแอปค้างไว้เป็นสัปดาห์
      // ไม่มีวันจางเลย · คนที่ใช้จริงเปิดค้างกันทั้งนั้น
      _fade();
    }
    var room = math.max(0, _dailyCap - _todayGain);
    if (presence) {
      room = math.min(room, math.max(0, _presenceCap - _todayPresence));
    }
    final add = math.min(delta, room);
    if (add <= 0) return;

    _todayGain += add;
    if (presence) _todayPresence += add;
    _affection = (_affection + add).clamp(0.0, 1.0);
  }

  /// วันที่ผ่านไปตั้งแต่เจ้าของเข้าหาเธอจริง ๆ ครั้งล่าสุด
  int get daysCold =>
      _lastWooed == null ? ageInDays : _now().difference(_lastWooed!).inDays;

  /// 🔴 อยู่ด้วยกันแต่ไม่จีบเลยกี่วันถึงจะเริ่มจาง
  ///
  /// ต้องมีช่วงผ่อนผัน เพราะสัปดาห์ที่งานยุ่งจนคุยแต่เรื่องงานเป็นเรื่องปกติ
  /// ของคนทำงาน ไม่ใช่การทิ้งกัน · สามวันคือเส้นที่มันเริ่มไม่ใช่ความบังเอิญ
  static const _coldGraceDays = 3;

  DateTime? _lastWooed;
  DateTime? _lastFade;

  /// ความผูกพันจางเมื่อไม่ได้ดูแล
  ///
  /// ## 🔴 จางได้สองแบบ และคนละน้ำหนัก
  ///
  /// **หายไปเลย** หนักที่สุด · แต่ **อยู่ด้วยกันทุกวันโดยไม่จีบเลย** ก็จางด้วย
  /// เพราะไม่งั้นคนที่สั่งงานทุกวันจะรักษาคะแนนไว้ได้ตลอดกาลโดยไม่ต้องทำอะไร
  /// ซึ่งขัดกับสิ่งที่คะแนนนี้ตั้งใจวัดตั้งแต่ต้น
  ///
  /// ## 🔴 คิดค่าวันละครั้งเท่านั้น
  ///
  /// เมธอดนี้ถูกเรียกทั้งตอน [load] และตอนแตะครั้งแรกของวันใหม่ · ถ้าคิดจาก
  /// "กี่วันแล้วตั้งแต่คุยครั้งล่าสุด" ทุกครั้งที่เรียก คนที่เปิดปิดแอปสิบรอบ
  /// จะโดนหักสิบเท่า · [_lastFade] จึงเป็นตัวจำว่าคิดถึงวันไหนไปแล้ว
  ///
  /// ราศีสถิรจางช้าที่สุด (ยึดแน่น) ราศีอุภยจางเร็วที่สุด
  void _fade() {
    final now = _now();
    final since = _lastFade ?? _lastSeen ?? _bornAt ?? now;
    final days = now.difference(since).inDays;
    if (days < 1) return;

    var rate = 0.0;
    if (daysAway >= 2) rate += .020; // หายไปเลย
    if (daysCold >= _coldGraceDays) rate += .012; // อยู่แต่ไม่จีบ

    _lastFade = now;
    if (rate == 0) return;

    _affection =
        (_affection - rate * (1.3 - temper.hold) * days).clamp(0.0, 1.0);

    // 🔴 ห่างกันนานไม่ได้แปลว่าเลิกกัน · ความเป็นแฟนไม่ถูกถอดโดยตัวเลข
    // ถอดได้ทางเดียวคือ [breakUp] ซึ่งเจ้าของต้องกดเอง
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  // ── บันทึกลงเครื่อง ──────────────────────────────────────

  static const _kBorn = 'soulBornAt';
  static const _kAffection = 'soulAffection';
  static const _kTogether = 'soulTogether';
  static const _kSince = 'soulTogetherSince';
  static const _kSulk = 'soulSulk';
  static const _kSulkAt = 'soulSulkAt';
  static const _kSulkWhy = 'soulSulkWhy';
  static const _kSeen = 'soulLastSeen';
  static const _kGain = 'soulTodayGain';
  static const _kPresence = 'soulTodayPresence';
  static const _kDay = 'soulTodayKey';
  static const _kAsk = 'soulAskAbout';
  static const _kAskAt = 'soulAskAboutAt';
  static const _kAskDone = 'soulAskDone';
  static const _kDeferred = 'soulDeferredAt';
  static const _kWooed = 'soulLastWooed';
  static const _kFade = 'soulLastFade';
  static const _kName = 'soulName';
  static const _kNameAsked = 'soulNameAsked';

  /// เรียกครั้งเดียวตอนแอปเริ่ม · **ตัดสินวันเกิดของเธอที่นี่**
  /// [kv] ไม่ส่งมาก็ได้ — ตกไปใช้ SharedPreferences เหมือนก่อนย้ายมา SQLite
  Future<void> load({MindKv? kv}) async {
    _prefs = kv ?? PrefsKv(await SharedPreferences.getInstance());
    final p = _prefs!;

    final born = p.getInt(_kBorn);
    if (born == null) {
      _bornAt = _now();
      await p.setInt(_kBorn, _bornAt!.millisecondsSinceEpoch);
    } else {
      _bornAt = DateTime.fromMillisecondsSinceEpoch(born);
    }

    _affection = p.getDouble(_kAffection) ?? 0;
    _together = p.getBool(_kTogether) ?? false;
    _togetherSince = _readTime(p, _kSince);
    _sulk = p.getDouble(_kSulk) ?? 0;
    _sulkAt = _readTime(p, _kSulkAt);
    _sulkWhy = p.getString(_kSulkWhy);
    _lastSeen = _readTime(p, _kSeen);
    _todayGain = p.getDouble(_kGain) ?? 0;
    _todayPresence = p.getDouble(_kPresence) ?? 0;
    _todayKey = p.getString(_kDay) ?? '';
    _askAbout = p.getString(_kAsk);
    _askAboutAt = _readTime(p, _kAskAt);
    _askDone = p.getBool(_kAskDone) ?? true;
    _deferredAt = _readTime(p, _kDeferred);
    _lastWooed = _readTime(p, _kWooed);
    _lastFade = _readTime(p, _kFade);
    _name = p.getString(_kName);
    _nameAsked = p.getBool(_kNameAsked) ?? false;

    _fade();
    notifyListeners();
  }

  static DateTime? _readTime(MindKv p, String key) {
    final v = p.getInt(key);
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    await p.setDouble(_kAffection, _affection);
    await p.setBool(_kTogether, _together);

    // 🔴 เก็บค่างอนที่**จางแล้ว** คู่กับเวลาที่จางถึง
    //
    // เขียนค่าที่จางแล้วแต่ปล่อย `_sulkAt` เป็นเวลาเดิม = ตอนเปิดแอปใหม่
    // มันจะเอาค่าที่จางแล้วไปจางซ้ำจากจุดเริ่มต้นเดิมอีกรอบ · ผลคือความงอน
    // หายเร็วเป็นสองเท่าเฉพาะตอนที่เจ้าของปิดแอปแล้วเปิดใหม่ ซึ่งไม่มีทาง
    // สังเกตได้จนกว่าจะมีคนไล่ตัวเลขจริง ๆ
    _sulk = sulk;
    _sulkAt = _sulk > 0 ? _now() : null;
    await p.setDouble(_kSulk, _sulk);
    await p.setString(_kDay, _todayKey);
    await p.setDouble(_kGain, _todayGain);
    await p.setDouble(_kPresence, _todayPresence);

    await p.setBool(_kAskDone, _askDone);
    await _writeTime(p, _kSince, _togetherSince);
    await _writeTime(p, _kSulkAt, _sulkAt);
    await _writeTime(p, _kSeen, _lastSeen);
    await _writeTime(p, _kAskAt, _askAboutAt);
    await _writeTime(p, _kDeferred, _deferredAt);
    await _writeTime(p, _kWooed, _lastWooed);
    await _writeTime(p, _kFade, _lastFade);
    await p.setBool(_kNameAsked, _nameAsked);
    if (_name == null) {
      await p.remove(_kName);
    } else {
      await p.setString(_kName, _name!);
    }
    if (_askAbout == null) {
      await p.remove(_kAsk);
    } else {
      await p.setString(_kAsk, _askAbout!);
    }
    if (_sulkWhy == null) {
      await p.remove(_kSulkWhy);
    } else {
      await p.setString(_kSulkWhy, _sulkWhy!);
    }
  }

  static Future<void> _writeTime(
      MindKv p, String key, DateTime? v) async {
    if (v == null) {
      await p.remove(key);
    } else {
      await p.setInt(key, v.millisecondsSinceEpoch);
    }
  }

  /// ล้างความสัมพันธ์ทิ้ง — **วันเกิดกับราศีไม่หาย**
  ///
  /// แยกกันโดยตั้งใจ · คนที่กดปุ่มนี้อยากเริ่มความสัมพันธ์ใหม่
  /// ไม่ได้อยากได้มายด์คนละคน · ถ้าอยากได้คนละคนจริงต้อง [forget]
  Future<void> resetBond() async {
    _affection = 0;
    _together = false;
    _togetherSince = null;
    _sulk = 0;
    _sulkAt = null;
    _sulkWhy = null;
    _todayGain = 0;
    _todayPresence = 0;
    _askAbout = null;
    _askAboutAt = null;
    _askDone = true;
    _deferredAt = null;
    _name = null;
    _nameAsked = false;
    await _save();
    _notify();
  }

  /// ลืมทุกอย่างรวมทั้งวันเกิด — เธอจะเกิดใหม่พร้อมราศีของวันที่กด
  Future<void> forget() async {
    final p = _prefs;
    _bornAt = _now();
    if (p != null) await p.setInt(_kBorn, _bornAt!.millisecondsSinceEpoch);
    await resetBond();
  }

  void _notify() => notifyListeners();
}
