/// ข้อมูลของเจ้าของที่บอกเจ้าหน้าที่ · ว่างได้ทุกช่อง · เก็บเข้ารหัสฝั่ง Android (SosVault.kt)
///
/// 🔒 ข้อมูลสุขภาพไปถึงได้แค่เจ้าหน้าที่กับคนที่เจ้าของตั้งไว้ · ห้ามส่งเข้าสมอง ห้ามลง log
library;

import 'dart:convert';

/// เวอร์ชันข้อความยอมรับข้อจำกัด · เปลี่ยนเนื้อหาแล้วต้องขยับ เจ้าของจะถูกถามใหม่
const int kSosConsentVersion = 2;

class SosContactInfo {
  const SosContactInfo({required this.name, required this.number, this.health = true});

  factory SosContactInfo.fromJson(Map<String, dynamic> j) => SosContactInfo(
        name: (j['name'] as String?) ?? '',
        number: (j['number'] as String?) ?? '',
        health: j['health'] != false,
      );

  final String name;
  final String number;

  /// ส่งข้อมูลสุขภาพให้คนนี้ด้วยไหม
  final bool health;

  Map<String, dynamic> toJson() => {'name': name, 'number': number, 'health': health};
}

class SosProfile {
  const SosProfile({
    this.name = '',
    this.birthYear,
    this.blood = '',
    this.conditions = '',
    this.medicines = '',
    this.allergies = '',
    this.plate = '',
    this.notes = '',
    this.contacts = const [],
    this.testNumber = '',
    this.armed = false,
    this.autoCall = false,
    this.consent = 0,
    this.countdownSec = 30,
    this.sensitivity = 1,
  });

  factory SosProfile.parse(String? raw) {
    if (raw == null || raw.isEmpty) return const SosProfile();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return SosProfile(
        name: (j['name'] as String?) ?? '',
        birthYear: j['birthYear'] as int?,
        blood: (j['blood'] as String?) ?? '',
        conditions: (j['conditions'] as String?) ?? '',
        medicines: (j['medicines'] as String?) ?? '',
        allergies: (j['allergies'] as String?) ?? '',
        plate: (j['plate'] as String?) ?? '',
        notes: (j['notes'] as String?) ?? '',
        contacts: [
          for (final c in (j['contacts'] as List<dynamic>? ?? const []))
            SosContactInfo.fromJson(c as Map<String, dynamic>),
        ],
        testNumber: (j['testNumber'] as String?) ?? '',
        armed: j['armed'] == true,
        autoCall: j['autoCall'] == true,
        consent: (j['consent'] as int?) ?? 0,
        countdownSec: (j['countdownSec'] as int?) ?? 30,
        sensitivity: (j['sensitivity'] as int?) ?? 1,
      );
    } on Object {
      // ไฟล์พัง · เริ่มว่างดีกว่าเปิดหน้าไม่ได้ · ไม่ลงเนื้อหาใน log
      return const SosProfile();
    }
  }

  final String name;
  final int? birthYear;
  final String blood;
  final String conditions;
  final String medicines;
  final String allergies;
  final String plate;
  final String notes;
  final List<SosContactInfo> contacts;
  final String testNumber;
  final bool armed;
  final bool autoCall;
  final int consent;
  final int countdownSec;
  final int sensitivity;

  bool get consented => consent >= kSosConsentVersion;

  int? ageIn(int year) {
    final b = birthYear;
    if (b == null || b < 1900 || b > year) return null;
    return year - b;
  }

  SosProfile copyWith({
    String? name,
    int? birthYear,
    bool clearBirthYear = false,
    String? blood,
    String? conditions,
    String? medicines,
    String? allergies,
    String? plate,
    String? notes,
    List<SosContactInfo>? contacts,
    String? testNumber,
    bool? armed,
    bool? autoCall,
    int? consent,
    int? countdownSec,
    int? sensitivity,
  }) =>
      SosProfile(
        name: name ?? this.name,
        birthYear: clearBirthYear ? null : birthYear ?? this.birthYear,
        blood: blood ?? this.blood,
        conditions: conditions ?? this.conditions,
        medicines: medicines ?? this.medicines,
        allergies: allergies ?? this.allergies,
        plate: plate ?? this.plate,
        notes: notes ?? this.notes,
        contacts: contacts ?? this.contacts,
        testNumber: testNumber ?? this.testNumber,
        armed: armed ?? this.armed,
        autoCall: autoCall ?? this.autoCall,
        consent: consent ?? this.consent,
        countdownSec: countdownSec ?? this.countdownSec,
        sensitivity: sensitivity ?? this.sensitivity,
      );

  String encode() => jsonEncode({
        'name': name,
        'birthYear': birthYear,
        'blood': blood,
        'conditions': conditions,
        'medicines': medicines,
        'allergies': allergies,
        'plate': plate,
        'notes': notes,
        'contacts': [for (final c in contacts) c.toJson()],
        'testNumber': testNumber,
        'armed': armed,
        'autoCall': autoCall,
        'consent': consent,
        'countdownSec': countdownSec,
        'sensitivity': sensitivity,
      });
}
