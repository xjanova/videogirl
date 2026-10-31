/// งานที่เธอทำในเครื่องแทนเจ้าของ · ชนิดข้อมูลที่แชทและสายใช้ร่วมกัน
///
/// เจ้าของ: "ต้องทำให้ มายด์ คอนโทรลเครื่องได้หมด เปิดได้ได้ทุกแอพ ทำแทนเราได้"
/// · ก่อนทำสิ่งที่ย้อนกลับไม่ได้ (ส่ง จ่าย ซื้อ ลบ) เธอต้องหยุดถามก่อนหนึ่งครั้ง
library;

/// งานจบแบบไหน
enum PhoneOutcome {
  /// ทำเสร็จตามที่สั่ง
  done,

  /// ทำต่อไม่ได้ (หาไม่เจอ แอปไม่ตอบ ครบจำนวนขั้น)
  failed,

  /// เจ้าของ (หรือคนในสายที่ยืนยันตัวแล้ว) สั่งหยุด หรือไม่อนุญาตขั้นที่ต้องถาม
  stopped,

  /// ต้องได้ข้อมูลจากเจ้าของก่อน (ส่งหาใคร รหัสผ่าน ฯลฯ) · [PhoneTaskResult.summary] คือคำถาม
  needsOwner,

  /// เริ่มไม่ได้เลย · [PhoneTaskResult.reason] บอกว่าเพราะอะไร
  unavailable,
}

/// เหตุที่เริ่มงานไม่ได้ ([PhoneOutcome.unavailable]) · ตรงกับรหัสที่ฝั่ง Android ส่งมา
abstract final class PhoneUnavailable {
  /// เครื่องนี้ไม่รองรับ (Android เก่าเกิน / ไม่มีช่องทาง)
  static const unsupported = 'unsupported';

  /// บริการใช้เครื่องแทนยังไม่ได้เปิด และแอปเปิดเองไม่ได้ (ไม่มีสิทธิ์เขียนค่าระบบ)
  static const notEnabled = 'not_enabled';

  /// พักไว้ให้แอปธนาคารอยู่
  static const paused = 'paused';

  /// มีงานอื่นทำอยู่
  static const busy = 'busy';

  /// เจ้าของปิดสวิตช์ "ให้เธอใช้เครื่องแทน" ไว้
  static const off = 'off';
}

class PhoneTaskResult {
  const PhoneTaskResult(this.outcome, this.summary, {this.steps = 0, this.reason});

  final PhoneOutcome outcome;

  /// สิ่งที่เธอรายงาน (ภาษาของแอป) · [PhoneOutcome.needsOwner] = คำถามถึงเจ้าของ
  final String summary;

  /// ทำไปกี่ขั้น
  final int steps;

  /// รหัสเหตุผลสำหรับโค้ด ([PhoneUnavailable] หรือ 'step_cap' / 'brain' / 'stale')
  final String? reason;

  @override
  String toString() => 'PhoneTaskResult(${outcome.name}, steps: $steps, reason: $reason)';
}

/// ขั้นที่ต้องถามก่อนทำ
class PhoneStepAsk {
  const PhoneStepAsk({
    required this.id,
    required this.goal,
    required this.action,
    required this.app,
    this.why = '',
  });

  /// เลขของคำถาม · ใช้จับคู่คำตอบจากแจ้งเตือนกับคำถามที่ถามอยู่
  final int id;

  /// งานที่สั่งไว้
  final String goal;

  /// ขั้นที่จะทำ เป็นคำที่คนอ่านเข้าใจ เช่น กด «ส่ง»
  final String action;

  /// แอปที่อยู่ตอนนั้น (ชื่อที่เห็นบนเครื่อง)
  final String app;

  /// เหตุผลที่เธอให้ (อาจว่าง)
  final String why;
}

/// ถามก่อนทำขั้นที่ย้อนกลับไม่ได้ · true = ทำได้ · false / หมดเวลา = ไม่ทำ แล้วหยุดงาน
typedef PhoneConfirm = Future<bool> Function(PhoneStepAsk ask);

/// สิ่งที่หน้าจอแสดงระหว่างเธอทำงาน
class PhoneTaskView {
  const PhoneTaskView({
    required this.goal,
    required this.step,
    required this.maxSteps,
    required this.line,
    this.asking,
    this.inCall = false,
  });

  final String goal;
  final int step;
  final int maxSteps;

  /// ขั้นล่าสุดเป็นคำ (กำลังเปิด LINE / กำลังพิมพ์ …)
  final String line;

  /// ไม่ว่าง = รอเจ้าของตอบว่าให้ทำขั้นนี้ไหม
  final PhoneStepAsk? asking;

  /// สั่งมาจากคนในสายที่ยืนยันตัวแล้ว
  final bool inCall;

  PhoneTaskView copyWith({int? step, String? line, PhoneStepAsk? asking, bool clearAsking = false}) => PhoneTaskView(
        goal: goal,
        step: step ?? this.step,
        maxSteps: maxSteps,
        line: line ?? this.line,
        asking: clearAsking ? null : (asking ?? this.asking),
        inCall: inCall,
      );
}
