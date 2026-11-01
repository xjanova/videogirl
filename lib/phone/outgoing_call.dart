/// น้องมายโทรออกแทนเจ้าของ — สั่งในแชท ยืนยันก่อนโทร คุยให้ แล้วรายงานผลกลับ
///
/// ## ทำไม
///
/// เจ้าของ: "ทำส่วน โทรออกต่อ" · เช่น "โทรจองโต๊ะร้านนี้ 2 ที่ทุ่มนึง" · เธอเขียนแท็ก
/// `[[โทร: … | …]]` ในคำตอบ (CallOutTag) → แอปขึ้นกล่องยืนยัน → เจ้าของกด → โทร
///
/// ## 🔴 ด่านที่ข้ามไม่ได้
///
/// - **เจ้าของกดยืนยันทุกสาย** · คำสั่งในแชทอาจตีความผิด และการโทรคือการกระทำต่อคนอื่น
///   ที่ย้อนกลับไม่ได้ (มีค่าโทร คนรับสายเสียเวลา)
/// - **เบอร์ฉุกเฉิน/1900 ไม่โทร** — ด่านซ้ำกับฝั่งเนทีฟ (OutgoingRules.kt) ที่นี่แค่บอกก่อนกด
/// - ในสายเธอบอกว่าเป็นเลขา AI ที่โทรแทน (MindPersona.outgoingBlock)
library;

import 'package:flutter/foundation.dart';

@immutable
class PendingCall {
  const PendingCall({required this.number, required this.task, this.name, this.id = 0, this.at, this.askOwner});

  /// ขึ้น/แก้กล่องล่าสุดเมื่อไหร่ · คำถาม "โทรเลยไหมคะ" ต้องมาหลังเวลานี้ถึงนับ (ดู CallReply.asksToDial)
  final DateTime? at;

  /// สวิตช์ "ถามฉันได้ระหว่างสาย" ที่เจ้าของเปลี่ยนในกล่อง · null = ดูจากเรื่องที่สั่ง
  final bool? askOwner;

  PendingCall copyWith({String? task, bool? askOwner}) => PendingCall(
        number: number,
        name: name,
        id: id,
        at: at,
        task: task ?? this.task,
        askOwner: askOwner ?? this.askOwner,
      );

  /// เบอร์ที่จะโทร (ตามที่อ่านได้ ยังไม่ตัดขีด)
  final String number;

  /// ชื่อในสมุดโทรศัพท์ · null = เจ้าของบอกเบอร์ตรง ๆ
  final String? name;

  /// เรื่องที่เจ้าของสั่งให้คุย — ไปอยู่ใน prompt ของสายนั้น
  final String task;

  /// เลขลำดับ · จอใช้ดูว่าเป็นคำขอใหม่หรือคำขอเดิมที่โชว์ไปแล้ว
  final int id;

  String get who => name ?? number;
}

/// สายที่น้องมายกำลังโทรออก (หลังเจ้าของยืนยัน) · ใช้ทำ prompt ของสายและรายงานผล
typedef OutgoingTask = ({String who, String number, String task});

/// กฎเดียวกับ android OutgoingRules.kt · ฝั่งนี้ใช้บอกเจ้าของก่อนกด
abstract final class OutgoingRules {
  static const emergency = {
    '191', '199', '1669', '1155', '1554', '1784', '1300', '1192', '1193', '1196', '1690',
    '911', '112', '999', '000', '110', '119',
  };

  /// ตัวเลขล้วน (คง + นำหน้า) · null = ไม่ใช่เบอร์
  static String? normalize(String raw) {
    final plus = raw.trim().startsWith('+');
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 3 || digits.length > 15) return null;
    return plus ? '+$digits' : digits;
  }

  /// ดูเป็นเบอร์โทร (ไม่ใช่ชื่อคน) ไหม
  static bool looksLikeNumber(String raw) =>
      RegExp(r'^[+0-9\s\-().]+$').hasMatch(raw.trim()) && normalize(raw) != null;

  /// เจ้าของสั่งในเรื่องที่ให้โทรว่าไม่ต้องถามกลางสาย ("ห้ามถามฉัน รับเรื่องไว้") ·
  /// ใช้ตั้งค่าเริ่มของสวิตช์ในกล่องยืนยัน เจ้าของเห็นและเปลี่ยนได้ก่อนกดโทร
  ///
  /// ต้องมีคำที่หมายถึงเจ้าของด้วย · "ไม่ต้องถามเขาเรื่องราคา" คือสั่งเรื่องปลายสาย ไม่ใช่ห้ามถามเจ้าของ
  static bool noAsking(String task) => _noAsk.any((r) => r.hasMatch(task));

  static final _noAsk = [
    RegExp('(\u0e2b\u0e49\u0e32\u0e21|\u0e44\u0e21\u0e48\u0e15\u0e49\u0e2d\u0e07|\u0e2d\u0e22\u0e48\u0e32|\u0e07\u0e14)'
        '\\s*(\u0e21\u0e32|\u0e42\u0e17\u0e23)*\\s*(\u0e16\u0e32\u0e21|\u0e1b\u0e23\u0e36\u0e01\u0e29\u0e32|\u0e23\u0e1a\u0e01\u0e27\u0e19|\u0e01\u0e27\u0e19)'
        '\\s*(\u0e09\u0e31\u0e19|\u0e40\u0e23\u0e32|\u0e1c\u0e21|\u0e1e\u0e35\u0e48|\u0e40\u0e08\u0e49\u0e32\u0e19\u0e32\u0e22|\u0e40\u0e08\u0e49\u0e32\u0e02\u0e2d\u0e07|\u0e23\u0e30\u0e2b\u0e27\u0e48\u0e32\u0e07\u0e2a\u0e32\u0e22)'),
    RegExp('(\u0e09\u0e31\u0e19|\u0e40\u0e23\u0e32|\u0e1c\u0e21)\\s*\u0e44\u0e21\u0e48(\u0e2d\u0e22\u0e39\u0e48|\u0e27\u0e48\u0e32\u0e07)'),
    RegExp(r"\b(don'?t|do not|never|no need to)\s+(ask|bother|check with|disturb)\s+(me|the owner|your boss)\b",
        caseSensitive: false),
    RegExp(r"\bi('m| am)\s+(away|busy|not available|unavailable)\b", caseSensitive: false),
  ];

  static bool blocked(String number) {
    final d = (normalize(number) ?? number).replaceFirst('+', '');
    return emergency.contains(d) || d.startsWith('1900');
  }
}
