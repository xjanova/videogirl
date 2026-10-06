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
  const PendingCall({required this.number, required this.task, this.name, this.id = 0});

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

  static bool blocked(String number) {
    final d = (normalize(number) ?? number).replaceFirst('+', '');
    return emergency.contains(d) || d.startsWith('1900');
  }
}
