/// ปรับแต่งเสียง ElevenLabs ทุกอย่างที่ API เปิดให้ — ต่อช่องทาง (คุย / รับสาย)
///
/// ตรวจกับเอกสารทางการ 2026-11-02:
/// - text-to-dialogue (Eleven v4): `settings.stability` · `settings.similarity`
///   · `audio_effects` · `apply_text_normalization` · `seed`
/// - text-to-speech (Eleven v3): `voice_settings` (stability · similarity_boost
///   · style · use_speaker_boost · speed) · `audio_effects` · ฯลฯ
/// - แท็กเสียง `[warmly]` `[whispers]` ฯลฯ นำหน้าข้อความ ใช้ได้ทั้ง v3 / v4
///
/// ค่าตั้งต้นทุกตัว = ค่าตั้งต้นของ ElevenLabs เอง · ไม่แตะอะไร = เสียงเหมือนเดิมทุกประการ
library;

import 'package:flutter/foundation.dart';

@immutable
class ElevenTuning {
  const ElevenTuning({
    this.stability = 0.5,
    this.similarity = 0.75,
    this.style = 0,
    this.speed = 1,
    this.speakerBoost = true,
    this.mood = '',
    this.filter = '',
    this.environment = '',
    this.noise = '',
    this.distance = 0,
    this.normalize = 'auto',
    this.seed = 0,
  });

  /// 0 = อารมณ์กว้าง (Creative) · 0.5 = ธรรมชาติ · 1 = นิ่งเสถียร (Robust)
  final double stability;

  /// ยึดเสียงต้นฉบับแค่ไหน · สูง = เหมือนต้นฉบับมาก (ดีกับเสียงโคลน)
  final double similarity;

  /// ขยายสไตล์การพูดของเสียงนั้น (v3) · 0 = ปิด
  final double style;

  /// ความเร็ว 0.7–1.2 (v3)
  final double speed;

  /// เพิ่มความเหมือนผู้พูด แลกกับหน่วงขึ้นนิดหน่อย (v3)
  final bool speakerBoost;

  /// แท็กอารมณ์ที่ใส่นำหน้าทุกประโยค (ไม่รวมวงเล็บ) · ว่าง = ไม่ใส่
  final String mood;

  /// เอฟเฟกต์จาก /v1/audio-effects/catalog · ว่าง = ไม่ใช้
  final String filter;
  final String environment;
  final String noise;

  /// ระยะห่างจากไมค์ 0 (ใกล้) – 1 (ไกล)
  final double distance;

  /// อ่านตัวเลข/คำย่อเป็นคำพูด: auto · on · off
  final String normalize;

  /// 0 = สุ่มทุกครั้ง · อื่น ๆ = พยายามให้ออกมาเหมือนเดิมทุกครั้ง
  final int seed;

  static const moods = [
    'warmly', 'happy', 'excited', 'calm', 'whispers', 'professional',
    'reassuring', 'sympathetic', 'curious', 'playfully',
  ];

  bool get hasEffects =>
      filter.isNotEmpty || environment.isNotEmpty || noise.isNotEmpty || distance > 0;

  /// ข้อความที่ส่งจริง · ใส่แท็กอารมณ์นำหน้าถ้าเลือกไว้และข้อความยังไม่มีแท็กเอง
  String tagged(String text) {
    final m = mood.trim();
    if (m.isEmpty || text.trimLeft().startsWith('[')) return text;
    return '[$m] $text';
  }

  Map<String, Object> effectsJson() => {
        if (filter.isNotEmpty) 'filter_preset_id': filter,
        if (environment.isNotEmpty) 'environment_id': environment,
        if (noise.isNotEmpty) 'background_noise_id': noise,
        if (distance > 0) 'distance': _r(distance),
      };

  static double _r(double v) => (v * 100).roundToDouble() / 100;

  ElevenTuning copyWith({
    double? stability,
    double? similarity,
    double? style,
    double? speed,
    bool? speakerBoost,
    String? mood,
    String? filter,
    String? environment,
    String? noise,
    double? distance,
    String? normalize,
    int? seed,
  }) =>
      ElevenTuning(
        stability: stability ?? this.stability,
        similarity: similarity ?? this.similarity,
        style: style ?? this.style,
        speed: speed ?? this.speed,
        speakerBoost: speakerBoost ?? this.speakerBoost,
        mood: mood ?? this.mood,
        filter: filter ?? this.filter,
        environment: environment ?? this.environment,
        noise: noise ?? this.noise,
        distance: distance ?? this.distance,
        normalize: normalize ?? this.normalize,
        seed: seed ?? this.seed,
      );

  Map<String, Object> toJson() => {
        'stability': stability,
        'similarity': similarity,
        'style': style,
        'speed': speed,
        'speakerBoost': speakerBoost,
        'mood': mood,
        'filter': filter,
        'environment': environment,
        'noise': noise,
        'distance': distance,
        'normalize': normalize,
        'seed': seed,
      };

  static double _d(Object? v, double def, double lo, double hi) =>
      v is num ? v.toDouble().clamp(lo, hi) : def;

  static ElevenTuning fromJson(Object? j) {
    if (j is! Map) return const ElevenTuning();
    String s(String k) => j[k] is String ? j[k] as String : '';
    final norm = s('normalize');
    return ElevenTuning(
      stability: _d(j['stability'], 0.5, 0, 1),
      similarity: _d(j['similarity'], 0.75, 0, 1),
      style: _d(j['style'], 0, 0, 1),
      speed: _d(j['speed'], 1, 0.7, 1.2),
      speakerBoost: j['speakerBoost'] is bool ? j['speakerBoost'] as bool : true,
      mood: s('mood'),
      filter: s('filter'),
      environment: s('environment'),
      noise: s('noise'),
      distance: _d(j['distance'], 0, 0, 1),
      normalize: const ['auto', 'on', 'off'].contains(norm) ? norm : 'auto',
      seed: j['seed'] is int ? (j['seed'] as int).clamp(0, 4294967295) : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ElevenTuning &&
      other.stability == stability &&
      other.similarity == similarity &&
      other.style == style &&
      other.speed == speed &&
      other.speakerBoost == speakerBoost &&
      other.mood == mood &&
      other.filter == filter &&
      other.environment == environment &&
      other.noise == noise &&
      other.distance == distance &&
      other.normalize == normalize &&
      other.seed == seed;

  @override
  int get hashCode => Object.hash(stability, similarity, style, speed, speakerBoost,
      mood, filter, environment, noise, distance, normalize, seed);
}

/// ตัวเลือกเอฟเฟกต์หนึ่งตัวจากแคตตาล็อกของ ElevenLabs
@immutable
class ElevenEffect {
  const ElevenEffect(this.id, this.name, [this.detail = '']);
  final String id;
  final String name;
  final String detail;

  Map<String, String> toJson() => {'id': id, 'name': name, 'detail': detail};

  static ElevenEffect? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return ElevenEffect(j['id'] as String, '${j['name'] ?? j['id']}', '${j['detail'] ?? ''}');
  }
}

/// แคตตาล็อกเอฟเฟกต์ (GET /v1/audio-effects/catalog)
@immutable
class ElevenEffects {
  const ElevenEffects({this.filters = const [], this.environments = const [], this.noises = const []});
  final List<ElevenEffect> filters;
  final List<ElevenEffect> environments;
  final List<ElevenEffect> noises;

  bool get isEmpty => filters.isEmpty && environments.isEmpty && noises.isEmpty;

  static ElevenEffects parse(Object? j) {
    if (j is! Map) return const ElevenEffects();
    List<ElevenEffect> read(String list, String idKey) => [
          if (j[list] is List)
            for (final e in j[list] as List)
              if (e is Map && e[idKey] is String)
                ElevenEffect(e[idKey] as String, '${e['name'] ?? e[idKey]}',
                    e['description'] is String ? e['description'] as String : ''),
        ];
    return ElevenEffects(
      filters: read('filter_presets', 'filter_preset_id'),
      environments: read('environments', 'environment_id'),
      noises: read('background_noises', 'background_noise_id'),
    );
  }

  Map<String, Object> toJson() => {
        'f': [for (final e in filters) e.toJson()],
        'e': [for (final e in environments) e.toJson()],
        'n': [for (final e in noises) e.toJson()],
      };

  static ElevenEffects fromJson(Object? j) {
    if (j is! Map) return const ElevenEffects();
    List<ElevenEffect> read(String k) => [
          if (j[k] is List)
            for (final e in j[k] as List) ?ElevenEffect.fromJson(e),
        ];
    return ElevenEffects(filters: read('f'), environments: read('e'), noises: read('n'));
  }
}
