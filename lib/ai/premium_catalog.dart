import 'speech_service.dart';
import 'voice_profile.dart';

/// เสียงหนึ่งตัวในรายการให้เลือก
class PremiumVoice {
  const PremiumVoice(this.id, this.name, [this.detail = '']);

  /// ค่าที่ส่งไปให้เจ้าเสียง (ชื่อเสียง / voice_id / ชื่อเต็มของ Azure)
  final String id;
  final String name;

  /// ลักษณะเสียงตามเอกสารของเจ้านั้น (ไม่แปล — เป็นคำของเขา)
  final String detail;

  Map<String, String> toJson() => {'id': id, 'name': name, 'detail': detail};

  static PremiumVoice? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = '${j['id'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    return PremiumVoice(id, '${j['name'] ?? id}', '${j['detail'] ?? ''}');
  }
}

/// รุ่นและเสียงของเจ้าเสียงพรีเมียม — **เฉพาะตัวคุณภาพสูงที่พูดไทยได้**
///
/// ตรวจกับเอกสารทางการ 2026-10-06 · เจ้าของสั่งไว้ว่า "ที่คุณภาพดี ๆ เท่านั้น"
/// รุ่นที่ถูกกว่าแต่ไม่มีภาษาไทย (Gemini Flash Lite TTS, ElevenLabs Multilingual
/// v2 / Flash v2.5) จึงไม่อยู่ในรายการโดยตั้งใจ · ดู docs/premium-voices.md
abstract final class PremiumCatalog {
  // ── Gemini ──
  /// GA 2026-09-22 · ตารางภาษาในเอกสารให้ Thai ✔️ (รุ่น Lite ให้ "—")
  static const geminiModels = ['gemini-3.8-flash-tts'];
  static const geminiDefaultVoice = 'Sulafat';

  /// เสียงสำเร็จรูปที่เข้ากับผู้ช่วยหญิง · คำอธิบายเป็นของเอกสาร Google
  static const geminiVoices = [
    PremiumVoice('Sulafat', 'Sulafat', 'Warm'),
    PremiumVoice('Despina', 'Despina', 'Smooth'),
    PremiumVoice('Aoede', 'Aoede', 'Breezy'),
    PremiumVoice('Leda', 'Leda', 'Youthful'),
    PremiumVoice('Vindemiatrix', 'Vindemiatrix', 'Gentle'),
    PremiumVoice('Achernar', 'Achernar', 'Soft'),
    PremiumVoice('Kore', 'Kore', 'Firm'),
    PremiumVoice('Zephyr', 'Zephyr', 'Bright'),
  ];

  // ── ElevenLabs ──
  /// พูดไทยได้เฉพาะตระกูล v3/v4 · v4 = คุณภาพสูงสุด (ผ่าน text-to-dialogue)
  static const elevenModels = ['eleven_v4', 'eleven_v3'];

  /// ไม่มีเสียงตั้งต้นโดยตั้งใจ · เสียง default ของ ElevenLabs หมดอายุ
  /// 2026-12-31 และ ID ใหม่ไม่ได้อยู่ในเอกสาร — ต้องดึงจากบัญชีของผู้ใช้
  static const elevenDefaultVoice = '';

  // ── Azure ──
  /// เสียงไทย GA ทั้งหมด + เสียงหลายภาษาที่พูดไทยได้ (สำหรับโหมดภาษาอังกฤษ)
  /// · เสียง MAI ยังเป็น preview และชื่อในเอกสารขัดกันเอง จึงไม่ฝังไว้ —
  /// โหลดจากบัญชีได้ถ้าภูมิภาคนั้นมี
  static const azureVoicesThai = [
    PremiumVoice('th-TH-PremwadeeNeural', 'Premwadee', 'Female · Thai'),
    PremiumVoice('th-TH-AcharaNeural', 'Achara', 'Female · Thai'),
    PremiumVoice('th-TH-NiwatNeural', 'Niwat', 'Male · Thai'),
  ];
  static const azureVoicesEnglish = [
    PremiumVoice('en-US-AvaMultilingualNeural', 'Ava', 'Female · multilingual'),
    PremiumVoice('en-US-EmmaMultilingualNeural', 'Emma', 'Female · multilingual'),
  ];

  static List<PremiumVoice> azureVoices({required bool thai}) =>
      thai ? azureVoicesThai : azureVoicesEnglish;

  /// รุ่นของเจ้านั้น · ว่าง = เจ้านั้นไม่มีให้เลือกรุ่น (Azure เลือกที่ตัวเสียง)
  static List<String> modelsOf(TtsEngine e) => switch (e) {
        TtsEngine.gemini => geminiModels,
        TtsEngine.elevenlabs => elevenModels,
        _ => const [],
      };

  /// สลับเจ้าเสียง = ปรับรุ่นกับเสียงให้เป็นของเจ้าใหม่
  ///
  /// 🔴 ไม่ปรับ = ส่ง `coral` ของ OpenAI ไปให้ Gemini หรือ `gpt-4o-mini-tts`
  /// ไปให้ ElevenLabs แล้วได้ error ทุกประโยคทั้งที่ผู้ใช้แค่กดเปลี่ยนเจ้า
  /// · ค่าที่เป็นของเจ้านั้นอยู่แล้วเก็บไว้ (กลับมาเจ้าเดิมแล้วไม่ต้องเลือกใหม่)
  static VoiceProfile adapt(VoiceProfile p, TtsEngine to, {required bool thai}) {
    final def = VoiceProfile.openAiDefaults;
    return switch (to) {
      TtsEngine.gemini => p.copyWith(
          engine: to,
          model: p.model.startsWith('gemini-') ? p.model : geminiModels.first,
          voice: geminiVoices.any((v) => v.id == p.voice) || _looksGemini(p.voice)
              ? p.voice
              : geminiDefaultVoice,
        ),
      TtsEngine.elevenlabs => p.copyWith(
          engine: to,
          model: p.model.startsWith('eleven_') ? p.model : elevenModels.first,
          voice: _looksEleven(p.voice) ? p.voice : elevenDefaultVoice,
        ),
      TtsEngine.azure => p.copyWith(
          engine: to,
          model: '',
          voice: p.voice.contains('Neural') || p.voice.contains(':')
              ? p.voice
              : azureVoices(thai: thai).first.id,
        ),
      TtsEngine.openai => p.copyWith(
          engine: to,
          model: p.model.startsWith('gpt-') ? p.model : def.model,
          voice: _looksOpenAi(p.voice) ? p.voice : def.voice,
        ),
      _ => p.copyWith(engine: to),
    };
  }

  /// voice_id ของ ElevenLabs เป็นตัวอักษร/ตัวเลข 20 ตัว
  static bool _looksEleven(String v) => RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(v);

  /// ชื่อเสียง Gemini ขึ้นต้นตัวใหญ่ ไม่มีขีด (Kore, Sulafat …)
  static bool _looksGemini(String v) => RegExp(r'^[A-Z][a-z]+$').hasMatch(v);

  /// ชื่อเสียง OpenAI เป็นตัวเล็กล้วน (coral, marin …)
  static bool _looksOpenAi(String v) => RegExp(r'^[a-z]+$').hasMatch(v);
}
