/// ประกอบแผนที่ฝั่งเนทีฟใช้ตอนเกิดเหตุ · Dart อาจตายไปแล้วตอนนั้น จึงต้องเตรียมข้อความทุกคำไว้ล่วงหน้า
///
/// คู่กับ SosPlan.kt และ SosStore.parse · ชื่อคีย์ต้องตรงกัน
///
/// 🔴 ทุกคำในบทมาจากข้อมูลที่เจ้าของกรอกเท่านั้น · ช่องว่าง = ไม่พูดถึง ห้ามเดาหรือใส่ค่าสมมติ ·
/// เจ้าหน้าที่จะเชื่อสิ่งที่เธอพูด ข้อมูลแพ้ยาผิดคือทำร้ายคน
library;

import 'dart:convert';

import 'sos_directory.dart';
import 'sos_profile.dart';

abstract final class SosPlanBuilder {
  /// ด่านนี้ซ้ำกับหน้าตั้งค่าโดยตั้งใจ · แผนที่ไม่เคยยอมรับข้อจำกัดต้องไม่เปิดระบบ
  static String build(SosProfile p, {required int year}) => jsonEncode({
        'armed': p.armed && p.consented,
        'autoCall': p.autoCall && p.consented,
        'countdownSec': p.countdownSec,
        'manualCountdownSec': 5,
        'routes': SosDirectory.wireRoutes,
        'abroad': SosDirectory.abroad,
        'contacts': [for (final c in p.contacts) c.toJson()],
        'testNumber': p.testNumber,
        'sensitivity': p.sensitivity,
        'th': _th(p, year),
        'en': _en(p, year),
      });

  static String _join(List<String> parts, String sep) => parts.where((s) => s.isNotEmpty).join(sep);

  static Map<String, Object> _th(SosProfile p, int year) {
    final age = p.ageIn(year);
    final who = p.name.isEmpty ? 'เจ้าของโทรศัพท์เครื่องนี้' : 'คุณ${p.name}';
    return {
      // 🔴 ห้ามมีคำว่า "ไม่เป็นไร" · ไมค์ได้ยินเสียงเธอเองแล้วจะยกเลิกเหตุแทนเจ้าของ
      'alertPrompt': 'เป็นอะไรไหมคะ ได้ยินไหมคะ ตอบมายด์หน่อยค่ะ หรือแตะปุ่มหยุดนะคะ',
      'sms': '🆘 มายด์ ผู้ช่วยอัตโนมัติของ$who แจ้งเหตุฉุกเฉิน เจ้าของไม่ตอบหลังเกิดเหตุ\n{loc}',
      'smsHealth': _join([
        if (p.blood.isNotEmpty) 'กรุ๊ปเลือด ${p.blood}',
        if (p.allergies.isNotEmpty) 'แพ้ยา ${p.allergies}',
        if (p.conditions.isNotEmpty) 'โรคประจำตัว ${p.conditions}',
        if (p.medicines.isNotEmpty) 'ยาที่ใช้ ${p.medicines}',
      ], ' · '),
      // 🔴 ห้ามโทรกลับ · เสียงเรียกเข้าคือสิ่งที่จะทำให้คนร้ายรู้
      'smsSilent': '🆘 มายด์ ผู้ช่วยอัตโนมัติของ$who ขอความช่วยเหลือแบบเงียบ อาจอยู่กับคนร้าย '
          'ห้ามโทรกลับ กรุณาแจ้งตำรวจ 191\n{loc}',
      'smsLow': '⚠️ มายด์ ผู้ช่วยอัตโนมัติของ$who: เครื่องถูกกระแทกแรงและเจ้าของไม่ตอบ '
          'อาจเป็นแค่เครื่องตก กรุณาลองติดต่อ\n{loc}',
      'smsCancel': 'มายด์ ผู้ช่วยอัตโนมัติของ$who: ยกเลิกการแจ้งเหตุแล้ว เจ้าของยืนยันว่าปลอดภัย',
      'smsDrillPrefix': '[ทดสอบระบบ ไม่ใช่เหตุจริง]',
      'scriptOpen': {
        for (final k in SosKindName.values) k.wire: '$_thOpen แจ้งเหตุแทน$who ${_thWhat(k)}',
        'SILENT': '$_thOpen แจ้งเหตุแทน$who เจ้าของขอความช่วยเหลือแบบเงียบ อาจอยู่กับคนร้าย พูดไม่ได้ ห้ามโทรกลับ',
      },
      'scriptWho': _join([
        'ผู้ประสบเหตุ $who',
        if (age != null) 'อายุ $age ปี',
        if (p.blood.isNotEmpty) 'กรุ๊ปเลือด ${p.blood}',
        if (p.allergies.isNotEmpty) 'แพ้ยา ${p.allergies}',
        if (p.conditions.isNotEmpty) 'โรคประจำตัว ${p.conditions}',
        if (p.medicines.isNotEmpty) 'ยาที่ใช้ ${p.medicines}',
        if (p.plate.isNotEmpty) 'ทะเบียนรถ ${p.plate}',
        if (p.notes.isNotEmpty) p.notes,
      ], ' '),
      'scriptWhere': 'พิกัดจีพีเอส ละติจูด {lat} ลองจิจูด {lng} {age} คลาดเคลื่อนประมาณ {acc} เมตร',
      'scriptNoFix': 'ยังไม่ทราบพิกัด กรุณาติดตามจากหมายเลขที่โทรเข้า',
      'scriptClose': 'เจ้าของไม่ตอบหลังเกิดเหตุ ไม่ทราบอาการ และระบบนี้ตอบคำถามไม่ได้ จะพูดซ้ำอีกครั้ง',
      'scriptCloseSilent': 'เจ้าของพูดไม่ได้ และระบบนี้ตอบคำถามไม่ได้ กรุณาส่งเจ้าหน้าที่ไปตามพิกัด จะพูดซ้ำอีกครั้ง',
      'ageNow': 'เมื่อสักครู่',
      'ageOld': 'เมื่อ {min} นาทีก่อน',
      'noFix': 'ยังไม่ทราบตำแหน่ง',
    };
  }

  /// เจ้าของ: "แจ้งให้เจ้าหน้าที่ฟัง ว่าเป็นระบบช่วยแจ้งเหตุ ต่อไปจะปิดไมค์ให้เจ้าหน้าที่ตั้งใจฟัง"
  static const _thOpen = 'นี่คือระบบช่วยแจ้งเหตุอัตโนมัติ ไม่ใช่คนจริง ต่อไปจะปิดไมค์เพื่อให้เจ้าหน้าที่ตั้งใจฟัง';
  static const _enOpen = 'This is an automated emergency alert system, not a person. '
      'The microphone will now be turned off so you can listen.';

  static String _thWhat(SosKindName k) => switch (k) {
        SosKindName.crash => 'สงสัยเกิดอุบัติเหตุ เครื่องจับแรงกระแทกรุนแรง เจ้าของไม่ตอบ',
        SosKindName.medical => 'เจ็บป่วยฉุกเฉิน',
        SosKindName.fire => 'เกิดเพลิงไหม้',
        SosKindName.crime => 'เกิดเหตุร้าย ต้องการตำรวจ',
        SosKindName.other => 'ต้องการความช่วยเหลือฉุกเฉิน',
      };

  static Map<String, Object> _en(SosProfile p, int year) {
    final age = p.ageIn(year);
    final who = p.name.isEmpty ? 'the owner of this phone' : p.name;
    return {
      'alertPrompt': 'Can you hear me? Please answer me, or tap the stop button.',
      'sms': '🆘 Mind, the automated assistant of $who: emergency. The owner did not respond.\n{loc}',
      'smsHealth': _join([
        if (p.blood.isNotEmpty) 'Blood group ${p.blood}',
        if (p.allergies.isNotEmpty) 'Drug allergies ${p.allergies}',
        if (p.conditions.isNotEmpty) 'Conditions ${p.conditions}',
        if (p.medicines.isNotEmpty) 'Medication ${p.medicines}',
      ], ' · '),
      'smsSilent': '🆘 Mind, the automated assistant of $who: a silent call for help. They may be with an attacker. '
          'DO NOT call back. Please call the police.\n{loc}',
      'smsLow': '⚠️ Mind, the automated assistant of $who: the phone took a hard hit and the owner '
          'did not respond. It may only be a drop. Please try to reach them.\n{loc}',
      'smsCancel': 'Mind, the automated assistant of $who: alert cancelled. The owner confirmed they are safe.',
      'smsDrillPrefix': '[SYSTEM TEST, NOT A REAL EMERGENCY]',
      'scriptOpen': {
        for (final k in SosKindName.values) k.wire: '$_enOpen Calling for $who. ${_enWhat(k)}',
        'SILENT': '$_enOpen Calling for $who. A silent call for help. They may be with an attacker '
            'and cannot speak. Do not call back.',
      },
      'scriptWho': _join([
        'The person is $who.',
        if (age != null) 'Age $age.',
        if (p.blood.isNotEmpty) 'Blood group ${p.blood}.',
        if (p.allergies.isNotEmpty) 'Drug allergies ${p.allergies}.',
        if (p.conditions.isNotEmpty) 'Conditions ${p.conditions}.',
        if (p.medicines.isNotEmpty) 'Medication ${p.medicines}.',
        if (p.plate.isNotEmpty) 'Vehicle plate ${p.plate}.',
        if (p.notes.isNotEmpty) p.notes,
      ], ' '),
      'scriptWhere': 'GPS latitude {lat}, longitude {lng}, {age}, accurate to about {acc} metres.',
      'scriptNoFix': 'The location is not known. Please trace this call.',
      'scriptClose': 'The owner did not respond and their condition is unknown. '
          'This system cannot answer questions. Repeating.',
      'scriptCloseSilent': 'The owner cannot speak and this system cannot answer questions. '
          'Please send help to these coordinates. Repeating.',
      'ageNow': 'just now',
      'ageOld': '{min} minutes ago',
      'noFix': 'Location not known yet',
    };
  }

  static String _enWhat(SosKindName k) => switch (k) {
        SosKindName.crash => 'A suspected accident. The phone detected a severe impact and the owner did not respond.',
        SosKindName.medical => 'A medical emergency.',
        SosKindName.fire => 'A fire.',
        SosKindName.crime => 'A crime in progress. Police are needed.',
        SosKindName.other => 'Emergency help is needed.',
      };
}
