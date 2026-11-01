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
class CallHangUp {
  /// รอหลังเสียงลาจบ · เผื่อคู่สายยังพูดไม่จบ
  static const wait = Duration(seconds: 3);

  /// ห้าวินาทีแรกของสายไม่วาง · โมเดลเรียกพลาดตอนทักได้
  static const guard = Duration(seconds: 5);

  bool _armed = false, _heardCaller = false;
  DateTime? _quietSince;

  bool get armed => _armed;

  /// เธอลาแล้ว · ลาซ้ำไม่นับเวลาใหม่ ไม่ล้างว่าได้ยินคู่สาย
  void arm() {
    if (_armed) return;
    _armed = true;
    _heardCaller = false;
    _quietSince = null;
  }

  void disarm() {
    _armed = false;
    _quietSince = null;
  }

  /// บทของคู่สายมาถึง · 🔴 นับเฉพาะคำที่เริ่มพูดหลังเธอลา ·
  /// บทมาช้ากว่าเสียง คำที่พูดก่อนเธอลาจึงมาถึงหลัง end_call ได้ ถ้าเลิกวางเพราะคำนั้น สายจะค้าง
  void callerSaid() {
    if (_heardCaller) disarm();
  }

  /// [herVoice] เธอพูด/เสียงยังค้าง · [callerTalking] คู่สายกำลังพูด · [held] พักสายรอเจ้าของ
  bool due(
    DateTime now, {
    required Duration age,
    bool herVoice = false,
    bool callerTalking = false,
    bool held = false,
  }) {
    if (!_armed) return false;
    if (callerTalking) _heardCaller = true;
    if (herVoice || callerTalking || held) {
      _quietSince = null;
      return false;
    }
    final since = _quietSince ??= now;
    if (now.difference(since) < wait || age <= guard) return false;
    disarm();
    return true;
  }
}
