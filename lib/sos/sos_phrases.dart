/// เจ้าของพูดขอความช่วยเหลือ · จับจากคำพูดตรง ๆ ไม่ผ่านสมอง
///
/// 🔴 ไม่ให้โมเดลตัดสินเรื่องนี้ · โมเดลถูกหลอกได้ด้วยข้อความจากคนอื่น แต่นี่อ่านเฉพาะคำของเจ้าของเอง
/// และผลสูงสุดคือเริ่มนับถอยหลังที่กดหยุดได้ · ไม่มีทางโทรทันที
///
/// ต้องเป็นทั้งประโยคสั้น ๆ · "วิธีแจ้งเหตุฉุกเฉินทำยังไง" เป็นคำถาม ไม่ใช่เหตุ
/// และประโยคปฏิเสธ ("ไม่ต้องเรียกรถพยาบาล") ต้องไม่ติด
library;

import 'sos_directory.dart';

const int _maxChars = 40;

final RegExp _noise = RegExp(r'[\s!?.,…~ๆ"]+');
const _names = ['น้องมายด์', 'มายด์'];
const _polite = ['ค่ะ', 'คะ', 'ครับ', 'จ้า', 'หน่อย', 'ที', 'ด่วน', 'เลย', ..._names];

const Map<String, SosKindName> _exact = {
  'ช่วยด้วย': SosKindName.other,
  'เอสโอเอส': SosKindName.other,
  'sos': SosKindName.other,
  'แจ้งเหตุฉุกเฉิน': SosKindName.other,
  'helpme': SosKindName.other,
  'เรียกรถพยาบาล': SosKindName.medical,
  'โทรเรียกรถพยาบาล': SosKindName.medical,
  'callanambulance': SosKindName.medical,
  'ไฟไหม้': SosKindName.fire,
  'เรียกดับเพลิง': SosKindName.fire,
  'เรียกตำรวจ': SosKindName.crime,
  'โทรหาตำรวจ': SosKindName.crime,
  'callthepolice': SosKindName.crime,
  'รถชน': SosKindName.crash,
  'เกิดอุบัติเหตุ': SosKindName.crash,
};

/// เจ้าของ: "ถ้าบอกช่วยด้วยไม่ต้องถาม ไม่ต้องพูดอะไร ไม่ต้องเปิดเสียง ให้มายด์ทำเงียบๆ เพื่อแจ้งเหตุเพราะบางที อยู่กับโจร"
const Set<String> _silent = {'ช่วยด้วย', 'helpme'};

/// ปากบอกยกเลิกการแจ้งเงียบ · ระหว่างนั้นไม่มีจอให้กด
const Set<String> _standDown = {'ยกเลิก', 'ไม่เป็นไร', 'cancel'};

abstract final class SosPhrases {
  /// null = ไม่ใช่การขอความช่วยเหลือ
  static SosKindName? match(String raw) => raw.length > _maxChars ? null : _exact[_clean(raw)];

  /// แจ้งแบบเงียบ · ไม่ถาม ไม่นับถอยหลังบนจอ ไม่มีเสียง
  static bool silent(String raw) => raw.length <= _maxChars && _silent.contains(_clean(raw));

  static bool standDown(String raw) => raw.length <= _maxChars && _standDown.contains(_clean(raw));

  static String _clean(String raw) {
    var s = raw.toLowerCase().replaceAll(_noise, '');
    // เรียกชื่อเธอก่อนแล้วค่อยขอ · "น้องมายด์ ช่วยด้วย"
    for (final n in _names) {
      if (s.length > n.length && s.startsWith(n)) {
        s = s.substring(n.length);
        break;
      }
    }
    // ลอกคำลงท้ายจนหมด · "ช่วยด้วยค่ะน้องมายด์" เหลือ "ช่วยด้วย"
    for (var again = true; again;) {
      again = false;
      for (final p in _polite) {
        if (s.length > p.length && s.endsWith(p)) {
          s = s.substring(0, s.length - p.length);
          again = true;
          break; // เริ่มรายการใหม่ · "น้องมายด์" ต้องได้ลองก่อน "มายด์" ทุกรอบ
        }
      }
    }
    return s;
  }
}
