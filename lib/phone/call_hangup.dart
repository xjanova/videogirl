/// เธอลาแล้วต้องวางจริง · แต่เผื่อคู่สายยังพูดไม่จบ
///
/// เจ้าของ: "เธอพูดว่าขออนุญาติ วางสายนะคะ ก็ควรวางสายเลย ดีเลย์ไว้สัก 3 วินาที พอเผือ อีกฝ่ายยังพูดไม่จบ"
///
/// ใช้ทุกทาง: Realtime · GPT-Live · ทางเดิมที่วางจากแท็ก
library;

/// คำในบทของเธอที่บอกว่าจะวาง · ทางสำรองเมื่อโมเดลลาแล้วลืมเรียก end_call
abstract final class CallGoodbye {
  static final _says = RegExp(
    r'(ขออนุญาต|ขอ)(ตัว)?(วางสาย|วางก่อน)|จะวางสาย(แล้ว|นะ|เลย|ค่ะ|คะ)|วางสาย(ก่อน|เลย|แล้ว)?(นะ|ค่ะ|คะ)|'
    r"\b(i'?ll|i will|i'?m going to|going to|let me)\s+(now\s+)?(hang up|end (the|this) call)|\bhanging up\b",
    caseSensitive: false,
  );

  /// "อย่าเพิ่งวางสายนะคะ" "ก่อนวางสาย ขอทวน" "คุณจะวางสาย…" มีคำว่าวางสายแต่เธอยังไม่ไป
  static final _notLeaving = RegExp(r'(อย่า(เพิ่ง)?|ห้าม|ไม่|ก่อน(ที่)?(จะ)?|ค่อย|พอ|เมื่อ|คุณ)\s*(จะ|ขอ)?\s*วางสาย');

  /// ถามอยู่ = รอคำตอบ ไม่ใช่จะวาง · "ขอวางสายได้ไหมคะ" ไม่นับ
  static final _asks = RegExp(r'[?？]|ไหม|มั้ย|ไม๊|หรือเปล่า|รึเปล่า|หรือยัง|หรือไม่');

  static bool says(String line) => _says.hasMatch(line) && !_notLeaving.hasMatch(line) && !_asks.hasMatch(line);
}

/// นับเวลาหลังเสียงลาจบ · ไม่มีนาฬิกาของตัวเอง ผู้เรียกถาม [due] ทุกจังหวะ
///
/// 🔴 เจ้าของ (2026-11-03): "เรื่องวางสาย เธอต้องวางสายเลยไม่ต้อง รอฟัง แล้ว เพราะ เธอไม่ยอมวางสักที" ·
/// ของเดิมรอคู่สายเงียบสามวินาที และเลิกวางเมื่อคู่สายพูดต่อ ("ค่ะ สวัสดีค่ะ") = เธอตอบ ลาใหม่ วนไม่จบ ·
/// ตอนนี้ลาแล้ววางเมื่อเสียงลาของเธอออกลำโพงหมด ไม่ฟังคู่สายอีก
class CallHangUp {
  /// เผื่อหลังเสียงลาจบ · ให้ท้ายเสียงออกสายครบ ไม่ใช่รอฟัง
  static const wait = Duration(seconds: 1);

  /// เสียงเธอค้างไม่จบ (ทางเสียงพัง) = วางอยู่ดีเมื่อครบเวลานี้หลังลา
  static const cap = Duration(seconds: 20);

  /// ห้าวินาทีแรกของสายไม่วาง · โมเดลเรียกพลาดตอนทักได้
  static const guard = Duration(seconds: 5);

  bool _armed = false;
  DateTime? _armedAt, _quietSince;

  bool get armed => _armed;

  /// เธอลาแล้ว · ลาซ้ำไม่นับเวลาใหม่
  void arm() {
    if (_armed) return;
    _armed = true;
    _armedAt = null;
    _quietSince = null;
  }

  void disarm() {
    _armed = false;
    _armedAt = null;
    _quietSince = null;
  }

  /// [herVoice] เธอพูด/เสียงยังค้าง · [held] พักสายรอเจ้าของ
  bool due(
    DateTime now, {
    required Duration age,
    bool herVoice = false,
    bool held = false,
  }) {
    if (!_armed || age <= guard) return false;
    if (held) {
      _armedAt = null;
      _quietSince = null;
      return false;
    }
    final armedAt = _armedAt ??= now;
    if (herVoice && now.difference(armedAt) < cap) {
      _quietSince = null;
      return false;
    }
    final since = _quietSince ??= now;
    if (!herVoice && now.difference(since) < wait) return false;
    disarm();
    return true;
  }
}
