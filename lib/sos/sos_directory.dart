/// เบอร์ฉุกเฉินของไทย · เธอรู้ว่าเหตุแบบไหนต้องโทรเบอร์ไหน
///
/// 🔴 ทุกเบอร์มาจากแหล่งทางการ ตรวจเมื่อ 2026-11-01 · แหล่งอยู่ใน docs/sos.md · ห้ามเติมจากความจำ
/// เบอร์ฉุกเฉินที่ผิดเบอร์เดียวคือคนรอรถพยาบาลที่ไม่มีวันมา
library;

/// ชนิดเหตุ · ชื่อต้องตรงกับ SosKind ใน SosPlan.kt
enum SosKindName { crash, medical, fire, crime, other }

extension SosKindWire on SosKindName {
  String get wire => name.toUpperCase();
}

class SosNumber {
  const SosNumber(this.number, this.th, this.en);

  final String number;
  final String th;
  final String en;
}

abstract final class SosDirectory {
  static const police = SosNumber('191', 'ตำรวจ เหตุด่วนเหตุร้าย', 'Police, urgent incidents');
  static const medical = SosNumber('1669', 'เจ็บป่วยฉุกเฉิน รถพยาบาล', 'Medical emergency, ambulance');
  static const fire = SosNumber('199', 'ดับเพลิง สัตว์ร้ายเข้าบ้าน', 'Fire, dangerous animals');
  static const highway = SosNumber('1193', 'ตำรวจทางหลวง', 'Highway police');

  /// เบอร์หลักที่แอปโทรเองเมื่อเจ้าของไม่ตอบ · เรียงตามลำดับที่โทร
  /// อุบัติเหตุบนถนนเริ่มที่ 1669 · คนเจ็บมาก่อน ตำรวจตามทีหลัง
  static const routes = <SosKindName, List<SosNumber>>{
    SosKindName.crash: [medical, police],
    SosKindName.medical: [medical, police],
    SosKindName.fire: [fire, police],
    SosKindName.crime: [police],
    SosKindName.other: [police],
  };

  /// เบอร์สากลของเครือข่าย GSM · ใช้ตอนซิมอยู่นอกไทยเท่านั้น
  /// 🔴 ไม่มีแหล่งทางการยืนยันว่า 112 ในไทยเข้าศูนย์ไหน จึงไม่ใช้ในประเทศ
  /// ต่างประเทศบางแห่งเบอร์หลักเป็นเบอร์อื่น · หน้าตั้งค่าบอกข้อจำกัดนี้
  static const abroad = ['112'];

  /// รายการให้อ่าน · แอปไม่โทรอัตโนมัติ · เจ้าของหรือเธอบอกต่อได้
  static const reference = <SosNumber>[
    police,
    medical,
    fire,
    SosNumber('1554', 'หน่วยแพทย์กู้ชีวิต', 'Rescue medical unit'),
    SosNumber('1155', 'ตำรวจท่องเที่ยว', 'Tourist police'),
    highway,
    SosNumber('1586', 'กรมทางหลวง 24 ชั่วโมง', 'Department of Highways, 24 hours'),
    SosNumber('1543', 'ทางพิเศษ', 'Expressway authority'),
    SosNumber('1690', 'การรถไฟ', 'State Railway'),
    SosNumber('1196', 'อุบัติเหตุทางน้ำ', 'Water accidents'),
    SosNumber('1784', 'ปภ. สายด่วนนิรภัย 24 ชั่วโมง (LINE @1784DDPM)', 'Disaster prevention, 24 hours (LINE @1784DDPM)'),
    SosNumber('1192', 'รถหาย', 'Stolen vehicles'),
    SosNumber('1300', 'แจ้งคนหาย', 'Missing persons'),
    SosNumber('1137', 'จส.100 ข่าวจราจร', 'JS100 traffic radio'),
  ];

  static Map<String, List<String>> get wireRoutes => {
        for (final e in routes.entries) e.key.wire: [for (final n in e.value) n.number],
      };
}
