/// เจ้าของพูดจบตาแล้วหรือยัง — ความเงียบ + ประโยคฟังดูจบไหม
///
/// ## ทำไม
///
/// เจ้าของ: "การกดไมค์พูดกับเธอควรพูดโต้ตอบได้เรียลไทม์ เหมือนที่เราทำกับการรับสาย และต้องเข้าใจว่า
/// บริบทไหนที่เราหยุดให้เธอปฏิบัติได้ เช่นพูดแล้วหยุดเว้นให้เธอคิดได้เลย ไม่ต้องมากดส่งอีก เพราะเรา
/// ออกแบบให้แอพนี้ใช้งานแม้ในขับรถได้"
///
/// ดูความเงียบอย่างเดียวผิดได้สองทาง: รอนานไป = ช้าเหมือนวิทยุสื่อสาร · ตัดไว = คนที่หยุดคิด
/// ("โทรหาบัว แล้วก็… บอกว่า…") โดนตัดกลางประโยค · ตัวนี้จึงฟังสองชั้น:
///
/// 1. เงียบ [TurnTaker.pause] → ส่งเสียงช่วงนี้ไปถอดก่อน (ไม่รอ)
/// 2. ถอดได้แล้วประโยคฟังจบ ([TurnEnd.looksUnfinished] = false) และยังเงียบอยู่ → ส่งให้เธอเลย
/// 3. ฟังยังไม่จบ ("แล้วก็" "เอ่อ" "เพราะว่า") → รอต่อจนเงียบครบ [TurnTaker.hold] · พูดต่อ = ฟังต่อ
///
/// คำไทยในไฟล์นี้คือ**คำที่ต้องจับให้ได้** ไม่ใช่ข้อความที่ผู้ใช้เห็น
library;

import 'dart:math' as math;

/// ประโยคที่ฟังดูยังพูดไม่จบ
abstract final class TurnEnd {
  /// คำเชื่อม/คำลังเลที่คนไทยพูดค้างไว้ตอนหยุดคิด · ยาวก่อนสั้น
  static const _thaiTails = [
    'เพราะว่า', 'แล้วก็', 'แบบว่า', 'เกี่ยวกับ', 'สำหรับ', 'หลังจาก', 'นอกจาก', 'ระหว่าง', 'เพราะ', 'เอิ่ม',
    'เอ่อ', 'อ่า', 'อืม', 'และ', 'หรือ', 'แต่', 'ว่า', 'ที่', 'คือ', 'ก็', 'ถ้า', 'ซึ่ง', 'แบบ', 'ของ',
    'กับ', 'จะ', 'เช่น', 'อย่าง', 'ตอน', 'ตรง', 'ใน', 'บน', 'จาก', 'ถึง', 'โดย', 'เพื่อ',
  ];
  // ไม่มี "อ่ะ" "พอ" · คนพูดปิดประโยคด้วยคำพวกนี้บ่อย ("ไปกันอ่ะ" "แค่นี้ก็พอ") ·
  // เดาว่ายังไม่จบผิด = รอเพิ่มวินาทีครึ่ง · เดาว่าจบผิด = ตัดกลางประโยค ซึ่งแย่กว่า จึงเอียงไปทางรอ

  /// คำลงท้ายที่บอกว่าจบประโยคแล้ว · มาก่อนเสมอ ("ช่วยดูให้หน่อยนะคะ")
  static const _thaiDone = ['ค่ะ', 'คะ', 'ครับ', 'คับ', 'จ้ะ', 'จ้า', 'นะ', 'ไหม', 'มั้ย', 'หน่อย', 'ด้วย', 'เลย', 'ล่ะ', 'เหรอ'];

  static final _enTail = RegExp(
    r"\b(and|or|but|because|so|the|a|an|to|with|of|for|if|um+|uh+|er+|like|that|which|when|about|my|your)$",
    caseSensitive: false,
  );

  static bool looksUnfinished(String text) {
    final t = text.trim().replaceAll(RegExp(r'[\s.,!?…\-–—"“”]+$'), '').toLowerCase();
    if (t.isEmpty) return false;
    if (_thaiDone.any(t.endsWith)) return false;
    if (_thaiTails.any(t.endsWith)) return true;
    // ...คนตัดประโยคด้วยจุดไข่ปลาเอง = ยังคิดอยู่
    if (RegExp(r'(\.\.\.|…)\s*$').hasMatch(text.trim())) return true;
    return _enTail.hasMatch(t);
  }
}

/// คำสั่งปิดโหมดคุยต่อเนื่องด้วยเสียง · ทั้งประโยคต้องเป็นคำสั่ง ("พอแล้ว" ไม่ใช่ "พอแล้วไปไหนต่อ")
abstract final class VoiceStop {
  static const _words = {
    'พอแล้ว', 'พอก่อน', 'แค่นี้ก่อน', 'แค่นี้', 'จบ', 'จบแล้ว', 'ปิดไมค์', 'หยุดฟัง', 'เลิกฟัง', 'ไม่คุยแล้ว',
    'ไว้คุยกันใหม่', 'บาย', 'บ๊ายบาย', 'stop', 'stoplistening', 'thatsall', 'goodbye', 'bye', 'byebye',
  };
  static const _polite = ['ครับผม', 'ค่ะ', 'คะ', 'ครับ', 'คับ', 'จ้ะ', 'จ้า', 'นะ', 'น่ะ', 'มายด์', 'please'];

  static bool matches(String text) {
    var t = text.toLowerCase().replaceAll(RegExp(r"[\s.,!?'’\-]+"), '');
    for (var guard = 0; guard < 3; guard++) {
      final before = t;
      for (final p in _polite) {
        if (t.endsWith(p) && t.length > p.length) t = t.substring(0, t.length - p.length);
        if (t.startsWith(p) && t.length > p.length) t = t.substring(p.length);
      }
      if (t == before) break;
    }
    return _words.contains(t);
  }
}

/// ขั้นถัดไปที่ผู้ใช้ [TurnTaker] ต้องทำหลังป้อนเสียงหนึ่งก้อน
enum TurnStep {
  none,

  /// เพิ่งหยุดพูด · ส่งเสียงที่อัดไว้ทั้งหมดไปถอด แล้วบอกผลกลับที่ [TurnTaker.heard]
  transcribe,

  /// จบตาแล้ว · ใช้ผลถอดล่าสุด ([TurnTaker.text]) หรือรอผลที่ยังค้างอยู่
  done,

  /// มีแต่เสียงรบกวนสั้น ๆ ไม่ใช่คำพูด · ทิ้งเสียงที่อัดไว้แล้วฟังใหม่
  noise,
}

/// ตัดสินจบตาจากระดับเสียงทีละก้อน · ไม่รู้จักไมค์ ไม่รู้จักนาฬิกา (ผู้เรียกส่งเวลามาเอง) จึงเทสต์ได้
class TurnTaker {
  TurnTaker({
    this.pause = const Duration(milliseconds: 700),
    this.hold = const Duration(milliseconds: 2200),
    this.maxTurn = const Duration(seconds: 30),
    this.floorMin = .012,
  });

  /// เงียบเท่านี้ = ส่งไปถอดก่อน · ถ้าประโยคฟังจบก็ตอบเลย
  final Duration pause;

  /// เงียบเท่านี้ = จบตาแน่ ๆ แม้ประโยคฟังยังไม่จบ (คนลืมพูดต่อ)
  final Duration hold;

  /// พูดยาวกว่านี้ = ตัดให้เธอตอบ
  final Duration maxTurn;

  /// ระดับต่ำสุดที่นับเป็นเสียงพูด · พื้นเสียงห้อง/รถสูงกว่านี้ก็ปรับขึ้นเอง (เหมือนในสาย)
  final double floorMin;

  /// ก้อนที่ดังกว่าพื้นเสียงน้อยกว่านี้ = เสียงคลิก/ไอ ไม่ใช่คำพูด
  static const minLoudChunks = 3;

  double _quiet = 0;
  bool _started = false;
  int _loudChunks = 0;
  int? _firstMs, _lastLoudMs;

  /// ขอถอดไว้ที่ความยาวเสียงเท่าไหร่ (ไบต์) · -1 = ยังไม่ได้ขอ หรือเจ้าของพูดต่อหลังขอแล้ว
  int _askedAt = -1;
  String? _text;
  int _textFor = -1;

  bool get started => _started;

  /// ผลถอดของเสียงทั้งหมดที่ฟังอยู่ · null = ยังไม่มี / เจ้าของพูดต่อหลังจากนั้น
  String? get text => _textFor == _askedAt && _askedAt >= 0 ? _text : null;

  /// ขอถอดไว้ที่ความยาวนี้ · -1 = ไม่มีคำขอที่ยังใช้ได้
  int get askedAt => _askedAt;

  /// เริ่มตาใหม่ · **จำพื้นเสียงไว้** (เสียงรถ/ห้องไม่เปลี่ยนระหว่างตา) · ลืมแล้วเจ้าของพูดทันทีที่เธอพูดจบ
  /// ก้อนแรกเป็นเสียงพูด กลายเป็นพื้นเสียง แล้วตานั้นไม่เคยนับว่าเริ่ม
  void reset() {
    _started = false;
    _loudChunks = 0;
    _firstMs = null;
    _lastLoudMs = null;
    _askedAt = -1;
    _text = null;
    _textFor = -1;
  }

  /// จบตาตอนที่ยังไม่มีคำขอที่ใช้ได้ (พูดยาวจนครบ [maxTurn] · พูดต่อหลังขอแล้วเงียบจนครบ [hold]) ·
  /// ขอถอดเสียงทั้งหมดตอนนี้ · คืน true = ต้องส่งไปถอด · false = ขอไว้ที่ความยาวนี้อยู่แล้ว รอผลเดิม
  bool askNow(int bytes) {
    if (_askedAt == bytes) return false;
    _askedAt = bytes;
    _text = null;
    _textFor = -1;
    return true;
  }

  /// ผลถอดของเสียงยาว [forBytes] · ผลของคำขอเก่า (เจ้าของพูดต่อไปแล้ว) ถูกทิ้ง
  void heard(String text, int forBytes) {
    if (forBytes != _askedAt) return;
    _text = text.trim();
    _textFor = forBytes;
  }

  /// ป้อนเสียงหนึ่งก้อน · [bytes] = ความยาวเสียงที่อัดไว้ทั้งหมดหลังใส่ก้อนนี้
  TurnStep feed(double level, int nowMs, int bytes) {
    _quiet = _quiet == 0 ? level : math.min(_quiet * 1.02, level);
    final loud = math.max(floorMin, _quiet * 3.5);
    if (level > loud) {
      // 🔴 เพดาน [maxTurn] นับจากคำแรก ไม่ใช่จากตอนเปิดไมค์ · นับจากเปิดไมค์ = เงียบรอเกิน 30 วิ
      // แล้วพูด ตานั้นโดนตัดตั้งแต่พยางค์แรก
      if (!_started) _firstMs = nowMs;
      _started = true;
      _loudChunks++;
      _lastLoudMs = nowMs;
      // พูดต่อหลังส่งไปถอดแล้ว = ผลนั้นเก่าแล้ว รอหยุดรอบใหม่
      if (_askedAt >= 0) {
        _askedAt = -1;
        _text = null;
        _textFor = -1;
      }
    }
    if (!_started) return TurnStep.none;
    final silent = nowMs - _lastLoudMs!;
    if (nowMs - _firstMs! >= maxTurn.inMilliseconds) {
      return _loudChunks < minLoudChunks ? TurnStep.noise : TurnStep.done;
    }
    if (silent >= hold.inMilliseconds) {
      return _loudChunks < minLoudChunks ? TurnStep.noise : TurnStep.done;
    }
    if (silent < pause.inMilliseconds) return TurnStep.none;
    if (_loudChunks < minLoudChunks) return TurnStep.none;
    if (_askedAt < 0) {
      _askedAt = bytes;
      return TurnStep.transcribe;
    }
    final t = text;
    if (t == null) return TurnStep.none;
    // ถอดแล้วว่างเปล่า = เสียงรบกวน · ประโยคฟังจบ = ตอบเลย · ฟังยังไม่จบ = รอจนครบ [hold]
    if (t.isEmpty) return TurnStep.noise;
    return TurnEnd.looksUnfinished(t) ? TurnStep.none : TurnStep.done;
  }
}
