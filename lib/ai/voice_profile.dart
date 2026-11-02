import 'package:flutter/foundation.dart';

import '../i18n/strings.dart';
import 'eleven_tuning.dart';
import 'mind_persona.dart';
import 'openai_config.dart';
import 'speech_service.dart';

/// ช่องทางที่เธอเปล่งเสียง — แต่ละช่องตั้งเสียงและโมเดลแยกกันได้
///
/// แยกเพราะบริบทต่างกันจริง: คุยในแอปคือคุยกับเจ้าของ จะหวานแค่ไหนก็ได้
/// แต่ตอนรับสายคนปลายทางเป็นคนแปลกหน้า ต้องเป็นทางการและฟังชัดเป็นหลัก
/// ป้ายที่ผู้ใช้เห็นอยู่ใน i18n/enum_labels.dart — enum เก็บแค่ตัวตน
///
/// 🔴 เคยมีช่อง "โทรออก" แยก แต่ไม่มีทางไหนอ่านค่ามันเลย สายออกใช้เสียงเดียวกับรับสาย
/// (speakForCall · Realtime · GPT-Live) · แท็บที่ตั้งแล้วไม่มีผลคือของปลอม จึงถอด
enum VoiceChannel { chat, answer }

/// เสียงหนึ่งชุดของหนึ่งช่องทาง
@immutable
class VoiceProfile {
  const VoiceProfile({
    required this.engine,
    required this.voice,
    required this.model,
    required this.instructions,
    this.eleven = const ElevenTuning(),
  });

  final TtsEngine engine;

  /// ชื่อเสียงของ OpenAI (coral, shimmer, …) — ไม่มีผลกับเสียงเครื่อง Android
  final String voice;

  /// โมเดลเสียง เช่น gpt-realtime-2.1-mini
  final String model;

  /// คำสั่งน้ำเสียง — ดู [OpenAiConfig.supportsInstructions]
  final String instructions;

  /// ปรับแต่งของ ElevenLabs (ความนิ่ง · ความเหมือน · สไตล์ · ความเร็ว · อารมณ์ · เอฟเฟกต์)
  /// · ไม่มีผลกับเจ้าอื่น · ค่าตั้งต้น = ค่าตั้งต้นของ ElevenLabs
  final ElevenTuning eleven;

  VoiceProfile copyWith({
    TtsEngine? engine,
    String? voice,
    String? model,
    String? instructions,
    ElevenTuning? eleven,
  }) =>
      VoiceProfile(
        engine: engine ?? this.engine,
        voice: voice ?? this.voice,
        model: model ?? this.model,
        instructions: instructions ?? this.instructions,
        eleven: eleven ?? this.eleven,
      );

  /// 🔴 ต้องเทียบด้วยค่า · `setLang` ถามว่า "ยังเป็นค่าตั้งต้นของภาษาเดิมไหม"
  /// ถ้าเทียบด้วยตัวตน คำตอบคือ "ไม่" เสมอ แล้วคำสั่งน้ำเสียงไม่เคยเปลี่ยน
  /// ภาษาตามแอปเลย
  @override
  bool operator ==(Object other) =>
      other is VoiceProfile &&
      other.engine == engine &&
      other.voice == voice &&
      other.model == model &&
      other.instructions == instructions &&
      other.eleven == eleven;

  @override
  int get hashCode => Object.hash(engine, voice, model, instructions, eleven);

  Map<String, Object> toJson() => {
        'engine': engine.name,
        'voice': voice,
        'model': model,
        'instructions': instructions,
        'eleven': eleven.toJson(),
      };

  static VoiceProfile fromJson(Map<String, dynamic> j, VoiceProfile fallback) =>
      VoiceProfile(
        // 🔴 ต้องอยู่ใน `wired` ไม่ใช่แค่ `values`
        //
        // เครื่องที่เคยเลือก "เสียงโคลน" ไว้ตอนที่มันยังโผล่ในรายการ จะโหลด
        // ค่านั้นกลับมาได้ปกติ แต่หน้าตั้งค่าไม่แสดงตัวเลือกนั้นแล้ว → เห็นเป็น
        // "ไม่ได้เลือกอะไรเลย" และกดอะไรก็ไม่ตรง จนกว่าจะบังเอิญกดทับ
        // ตกกลับไปที่ค่าตั้งต้นแทน ซึ่งเป็นทางที่ใช้งานได้จริง
        engine: TtsEngine.wired.firstWhere(
          (e) => e.name == j['engine'],
          orElse: () => fallback.engine,
        ),
        // รุ่นที่ปิดแล้ว (tts-1 · gpt-4o-mini-tts) ย้ายมารุ่นปัจจุบัน และรุ่นนั้นไม่มีบางเสียง
        // · MindState บอกเจ้าของตอนโหลด (ดู _voiceMoved)
        voice: OpenAiConfig.migrateVoice(j['voice'] as String? ?? fallback.voice),
        model: OpenAiConfig.migrateTts(j['model'] as String? ?? fallback.model),
        instructions: j['instructions'] as String? ?? fallback.instructions,
        eleven: j.containsKey('eleven') ? ElevenTuning.fromJson(j['eleven']) : fallback.eleven,
      );

  /// ค่าตั้งต้นของแต่ละช่อง — ต่างกันโดยตั้งใจ ไม่ใช่ก๊อปกัน
  /// และผูกกับภาษา เพราะคำสั่งน้ำเสียงต้องเขียนด้วยภาษาที่เธอจะพูด
  ///
  /// `engine` ตั้งต้นเป็น [TtsEngine.device] (Google TTS ที่ติดมากับ Android)
  /// เพราะแอปนี้ตั้งใจให้ใช้ได้**ออฟไลน์และไม่มีค่าใช้จ่าย**ตั้งแต่เปิดครั้งแรก
  /// ตั้งเป็น openai ไว้จะเงียบสนิทในเครื่องที่ไม่มีคีย์ ซึ่งผู้ใช้อ่านว่าแอปพัง
  ///
  /// ส่วน voice/model/instructions ยังคงค่า OpenAI ที่เลือกมาแล้วไว้เหมือนเดิม
  /// ทั้งที่เสียงเครื่องไม่ได้ใช้ — เพื่อให้วันที่สลับไป openai ได้ของที่ตั้งไว้ดี
  /// อยู่แล้วทันที ไม่ใช่ค่าว่างที่ต้องมานั่งกรอกใหม่
  /// รุ่น/เสียงตั้งต้นของ OpenAI — ใช้ตอนสลับกลับมาจากเจ้าอื่น (ดู PremiumCatalog.adapt)
  static const openAiDefaults = VoiceProfile(
    engine: TtsEngine.openai,
    voice: 'coral',
    model: OpenAiConfig.ttsModel,
    instructions: '',
  );

  static VoiceProfile defaultFor(VoiceChannel c, AppLang lang) => switch (c) {
        // คุยกับเจ้าของ: นุ่ม อบอุ่น เป็นตัวเธอ
        VoiceChannel.chat => VoiceProfile(
            engine: TtsEngine.device,
            voice: 'coral',
            model: OpenAiConfig.ttsModel,
            instructions: MindPersona.defaultVoiceInstructions(lang),
          ),

        // ในสาย ทั้งรับและโทรออก: คนปลายสายเป็นคนแปลกหน้า ต้องสุภาพ ชัด ไม่หวาน
        VoiceChannel.answer => VoiceProfile(
            engine: TtsEngine.device,
            voice: 'sage',
            model: OpenAiConfig.ttsModel,
            instructions: MindPersona.answerVoiceInstructions(lang),
          ),
      };
}
