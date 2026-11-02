/// ตัวละครที่ใช้คุยในสาย (รับสายแทน · โทรออกแทน)
///
/// เจ้าของ: "เพิ่มระบบโปรไฟล์ ตัวตนสำหรับโต้ตอบ รับสายพูดสาย … เลือกเป็นเพศชาย ชื่อ นิสัย ได้
/// … ตั้งผูกกับโมเดลเสียงได้ด้วย เช่น OpenAI ใช้โปรไฟล์ A · ElevenLabs ใช้โปรไฟล์ B · อย่าให้งง"
///
/// กฎเลือกตัวมีข้อเดียว: **ตัวที่ผูกกับเจ้าเสียงที่กำลังใช้มาก่อน ไม่ได้ผูก = ตัวที่เลือกไว้ของสายนั้น**
/// · "น้องมาย" เป็นตัวตั้งต้น ลบไม่ได้ จึงมีตัวให้ใช้เสมอ
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../ai/speech_service.dart';

enum CharacterGender { female, male }

@immutable
class CallCharacter {
  const CallCharacter({
    required this.id,
    required this.name,
    this.gender = CharacterGender.female,
    this.role = '',
    this.traits = '',
    this.greeting = '',
  });

  /// ตัวตั้งต้น — น้องมาย เลขาผู้หญิง
  static const maiId = 'mai';

  static const nameMax = 24;
  static const roleMax = 40;
  static const traitsMax = 400;
  static const greetingMax = 300;

  final String id;
  final String name;
  final CharacterGender gender;

  /// เป็นใครของเจ้าของ เช่น เลขา · ผู้ช่วย · พนักงานต้อนรับ · ว่าง = เลขา
  final String role;

  /// นิสัย / วิธีพูด ที่เจ้าของเขียนเอง
  final String traits;

  /// คำทักตอนรับสาย · ว่าง = แอปแต่งให้จากชื่อ บทบาท และเพศ
  final String greeting;

  bool get male => gender == CharacterGender.male;
  bool get isBuiltIn => id == maiId;

  CallCharacter copyWith({String? name, CharacterGender? gender, String? role, String? traits, String? greeting}) =>
      CallCharacter(
        id: id,
        name: name ?? this.name,
        gender: gender ?? this.gender,
        role: role ?? this.role,
        traits: traits ?? this.traits,
        greeting: greeting ?? this.greeting,
      );

  /// ตัดความยาวให้อยู่ในเพดาน · ชื่อว่าง = ใช้ชื่อเดิม (ไม่ให้มีตัวละครไร้ชื่อ)
  CallCharacter tidy({String fallbackName = ''}) {
    String cut(String v, int max) {
      final t = v.trim().replaceAll(RegExp(r'\s+'), ' ');
      return t.length > max ? t.substring(0, max) : t;
    }

    String cutLines(String v, int max) {
      final t = v.trim();
      return t.length > max ? t.substring(0, max) : t;
    }

    final n = cut(name, nameMax);
    return CallCharacter(
      id: id,
      name: n.isEmpty ? fallbackName : n,
      gender: gender,
      role: cut(role, roleMax),
      traits: cutLines(traits, traitsMax),
      greeting: cutLines(greeting, greetingMax),
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'gender': gender.name,
    'role': role,
    'traits': traits,
    'greeting': greeting,
  };

  static CallCharacter? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final name = j['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) return null;
    String s(String k) => j[k] is String ? j[k] as String : '';
    return CallCharacter(
      id: id,
      name: name,
      gender: CharacterGender.values.firstWhere((g) => g.name == j['gender'], orElse: () => CharacterGender.female),
      role: s('role'),
      traits: s('traits'),
      greeting: s('greeting'),
    ).tidy(fallbackName: name);
  }

  @override
  bool operator ==(Object other) =>
      other is CallCharacter &&
      other.id == id &&
      other.name == name &&
      other.gender == gender &&
      other.role == role &&
      other.traits == traits &&
      other.greeting == greeting;

  @override
  int get hashCode => Object.hash(id, name, gender, role, traits, greeting);
}

/// ตัวละครทั้งหมด + ตัวที่เลือกใช้ + การผูกกับเจ้าเสียง
@immutable
class CallCast {
  const CallCast({
    required this.characters,
    this.answerId = CallCharacter.maiId,
    this.outgoingId = CallCharacter.maiId,
    this.byEngine = const {},
  });

  final List<CallCharacter> characters;

  /// ตัวที่ใช้ตอนรับสาย / โทรออก (เมื่อเจ้าเสียงไม่ได้ผูกไว้)
  final String answerId;
  final String outgoingId;

  /// เจ้าเสียง → ตัวละคร · ไม่มีในนี้ = ไม่ได้ผูก
  final Map<TtsEngine, String> byEngine;

  static CallCast initial(CallCharacter mai) => CallCast(characters: [mai]);

  CallCharacter? byId(String id) {
    for (final c in characters) {
      if (c.id == id) return c;
    }
    return null;
  }

  CallCharacter get mai => byId(CallCharacter.maiId) ?? characters.first;

  /// ตัวที่ใช้จริงในสาย · [engine] = เจ้าเสียงของช่อง "รับสาย" ที่ใช้อยู่ตอนนี้
  CallCharacter active({required bool outgoing, required TtsEngine engine}) {
    final bound = byEngine[engine];
    if (bound != null) {
      final c = byId(bound);
      if (c != null) return c;
    }
    return byId(outgoing ? outgoingId : answerId) ?? mai;
  }

  /// มาจากการผูกกับเจ้าเสียงไหม (หน้าจอบอกเหตุผลว่าทำไมได้ตัวนี้)
  bool boundFor(TtsEngine engine) => byId(byEngine[engine] ?? '') != null;

  CallCast copyWith({
    List<CallCharacter>? characters,
    String? answerId,
    String? outgoingId,
    Map<TtsEngine, String>? byEngine,
  }) => CallCast(
    characters: characters ?? this.characters,
    answerId: answerId ?? this.answerId,
    outgoingId: outgoingId ?? this.outgoingId,
    byEngine: byEngine ?? this.byEngine,
  );

  /// เพิ่มหรือแทนที่ตัวที่ id ตรงกัน
  CallCast upsert(CallCharacter c) {
    final i = characters.indexWhere((x) => x.id == c.id);
    final next = [...characters];
    if (i < 0) {
      next.add(c);
    } else {
      next[i] = c;
    }
    return copyWith(characters: next);
  }

  /// ลบตัวละคร · ตัวตั้งต้นลบไม่ได้ · ที่ที่เคยใช้ตัวนี้กลับไปใช้ตัวตั้งต้น
  CallCast remove(String id) {
    if (id == CallCharacter.maiId) return this;
    return CallCast(
      characters: [
        for (final c in characters)
          if (c.id != id) c,
      ],
      answerId: answerId == id ? CallCharacter.maiId : answerId,
      outgoingId: outgoingId == id ? CallCharacter.maiId : outgoingId,
      byEngine: {
        for (final e in byEngine.entries)
          if (e.value != id) e.key: e.value,
      },
    );
  }

  String encode() => jsonEncode({
    'characters': [for (final c in characters) c.toJson()],
    'answer': answerId,
    'outgoing': outgoingId,
    'byEngine': {for (final e in byEngine.entries) e.key.name: e.value},
  });

  /// อ่านของที่บันทึกไว้ · เสีย/ว่าง = เริ่มใหม่ด้วยตัวตั้งต้น · ตัวตั้งต้นมีเสมอ
  static CallCast decode(String? raw, CallCharacter mai) {
    if (raw == null || raw.isEmpty) return initial(mai);
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return initial(mai);
      final list = <CallCharacter>[];
      final seen = <String>{};
      if (j['characters'] is List) {
        for (final x in j['characters'] as List) {
          final c = CallCharacter.fromJson(x);
          if (c != null && seen.add(c.id)) list.add(c);
        }
      }
      if (!seen.contains(CallCharacter.maiId)) list.insert(0, mai);
      final ids = {for (final c in list) c.id};
      String pickId(Object? v) => v is String && ids.contains(v) ? v : CallCharacter.maiId;
      final map = <TtsEngine, String>{};
      if (j['byEngine'] is Map) {
        for (final e in (j['byEngine'] as Map).entries) {
          final engine = TtsEngine.values.where((t) => t.name == e.key).firstOrNull;
          if (engine != null && e.value is String && ids.contains(e.value)) {
            map[engine] = e.value as String;
          }
        }
      }
      return CallCast(
        characters: list,
        answerId: pickId(j['answer']),
        outgoingId: pickId(j['outgoing']),
        byEngine: map,
      );
    } on Object {
      return initial(mai);
    }
  }
}
