import 'package:flutter/foundation.dart';

import 'mind_persona.dart';
import 'speech_service.dart';

/// ช่องทางที่เธอเปล่งเสียง — แต่ละช่องตั้งเสียงและโมเดลแยกกันได้
///
/// แยกเพราะบริบทต่างกันจริง: คุยในแอปคือคุยกับเจ้าของ จะหวานแค่ไหนก็ได้
/// แต่ตอนรับสายคนปลายทางเป็นคนแปลกหน้า ต้องเป็นทางการและฟังชัดเป็นหลัก
enum VoiceChannel {
  chat('พูดในแชท', 'ตอนคุยกับเราในแอป'),
  answer('เสียงตอบรับ', 'ตอนเธอรับสายแทนเรา'),
  outgoing('โทรออก', 'ตอนเธอโทรหาคนอื่นแทนเรา');

  const VoiceChannel(this.label, this.hint);
  final String label, hint;
}

/// เสียงหนึ่งชุดของหนึ่งช่องทาง
@immutable
class VoiceProfile {
  const VoiceProfile({
    required this.engine,
    required this.voice,
    required this.model,
    required this.instructions,
  });

  final TtsEngine engine;

  /// ชื่อเสียงของ OpenAI (coral, shimmer, …) — ไม่มีผลกับเสียงเครื่อง Android
  final String voice;

  /// โมเดลเสียง เช่น gpt-4o-mini-tts, tts-1-hd
  final String model;

  /// คำสั่งน้ำเสียง — เฉพาะ gpt-4o-mini-tts ที่รับพารามิเตอร์นี้
  final String instructions;

  VoiceProfile copyWith({
    TtsEngine? engine,
    String? voice,
    String? model,
    String? instructions,
  }) =>
      VoiceProfile(
        engine: engine ?? this.engine,
        voice: voice ?? this.voice,
        model: model ?? this.model,
        instructions: instructions ?? this.instructions,
      );

  Map<String, Object> toJson() => {
        'engine': engine.name,
        'voice': voice,
        'model': model,
        'instructions': instructions,
      };

  static VoiceProfile fromJson(Map<String, dynamic> j, VoiceProfile fallback) =>
      VoiceProfile(
        engine: TtsEngine.values.firstWhere(
          (e) => e.name == j['engine'],
          orElse: () => fallback.engine,
        ),
        voice: j['voice'] as String? ?? fallback.voice,
        model: j['model'] as String? ?? fallback.model,
        instructions: j['instructions'] as String? ?? fallback.instructions,
      );

  /// ค่าตั้งต้นของแต่ละช่อง — ต่างกันโดยตั้งใจ ไม่ใช่ก๊อปกัน
  static VoiceProfile defaultFor(VoiceChannel c) => switch (c) {
        // คุยกับเจ้าของ: นุ่ม อบอุ่น เป็นตัวเธอ
        VoiceChannel.chat => const VoiceProfile(
            engine: TtsEngine.openai,
            voice: 'coral',
            model: 'gpt-4o-mini-tts',
            instructions: MindPersona.defaultVoiceInstructions,
          ),

        // รับสายแทน: คนปลายสายเป็นคนแปลกหน้า ต้องสุภาพ ชัด ไม่หวาน
        VoiceChannel.answer => const VoiceProfile(
            engine: TtsEngine.openai,
            voice: 'sage',
            model: 'gpt-4o-mini-tts',
            instructions: 'พูดภาษาไทยแบบเลขานุการมืออาชีพ สุภาพ ชัดถ้อยชัดคำ '
                'น้ำเสียงเป็นมิตรแต่ไม่สนิทสนม ความเร็วปกติ ไม่แซว ไม่ทอดเสียง',
          ),

        // โทรออก: ต้องฟังชัดที่สุดเพราะสายโทรศัพท์บีบเสียงอยู่แล้ว
        VoiceChannel.outgoing => const VoiceProfile(
            engine: TtsEngine.openai,
            voice: 'shimmer',
            model: 'gpt-4o-mini-tts',
            instructions: 'พูดภาษาไทยให้ชัดเจนที่สุด ออกเสียงเต็มคำ '
                'ช้ากว่าปกติเล็กน้อย น้ำเสียงสุภาพและมั่นใจ '
                'เพราะสายโทรศัพท์บีบคุณภาพเสียงอยู่แล้ว',
          ),
      };
}
