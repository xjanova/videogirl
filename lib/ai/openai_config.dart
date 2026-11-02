/// ตั้งค่าการต่อ OpenAI
///
/// คีย์ **ไม่เคย** อยู่ในซอร์ส — repo นี้เป็น public การฝังคีย์ลงไปคือการแจกคีย์
/// ส่งเข้ามาตอน build แทน:
///
///   flutter run --dart-define=OPENAI_API_KEY=sk-...
///   flutter build apk --dart-define-from-file=secrets.json
///
/// ถ้าไม่ได้ส่งเข้ามา แอปยังเปิดได้ปกติ แต่มายด์จะตอบด้วยประโยคสำเร็จรูป
/// และไม่มีเสียง (ดู [configured])
library;

abstract final class OpenAiConfig {
  static const apiKey = String.fromEnvironment('OPENAI_API_KEY');

  /// สมองของเธอ — ค่าเริ่มต้นคือรุ่นที่เจ้าของเลือก
  static const brainModel =
      String.fromEnvironment('OPENAI_MODEL', defaultValue: 'gpt-5.6-sol');

  /// 🔴 ไม่มีรุ่นไหนเหลือบน /v1/audio/speech หลัง 2027-01-06 · ตัวแทนที่ OpenAI
  /// ประกาศคือรุ่นนี้ ซึ่งเรียกได้ทาง Realtime เท่านั้น ([speaksOverRealtime])
  static const ttsModel = String.fromEnvironment('OPENAI_TTS_MODEL',
      defaultValue: 'gpt-realtime-2.1-mini');

  /// ถอดเสียงปลายสายเป็นข้อความ
  ///
  /// `whisper-1` และตระกูล gpt-4o-transcribe ปิด 2027-02-26 · ตัวแทนคือรุ่นนี้
  /// แต่เอกสาร OpenAI ไม่ได้ระบุว่ารับภาษาไทย (ตรวจ 2026-11-02) · เรียกไม่ได้จะได้
  /// 400/404 ตอนสายจริง ซึ่งผู้ใช้เห็นเป็น "เธอฟังไม่ออก" จึงต้องมี [sttLadder]
  ///
  /// เปลี่ยนได้ตอน build: --dart-define=OPENAI_STT_MODEL=whisper-1
  static const sttModel =
      String.fromEnvironment('OPENAI_STT_MODEL', defaultValue: 'gpt-transcribe');

  /// รุ่นเดิมที่รู้แน่ว่าฟังไทยได้ · ใช้ได้ถึง 2027-02-26 แล้วขั้นนี้ถูกปฏิเสธเอง
  /// (ซึ่งบันไดรับได้ ไม่ต้องกลับมาแก้ตรงนี้วันนั้น)
  ///
  /// พร็อกซีกับเซิร์ฟเวอร์ในบ้านยังส่งรุ่นนี้ · ปลายทางพวกนั้นเลียนแบบ API ของ
  /// whisper-1 และเลือกรุ่นจริงเอง ไม่รู้จัก `languages`
  static const legacySttModel = 'whisper-1';

  /// รุ่นถอดเสียงเดิมในเซสชัน Realtime · ปิด 2027-02-26 เช่นกัน
  static const legacyRealtimeSttModel = 'gpt-4o-mini-transcribe';

  /// ลำดับที่ลองถอดเสียง · [hint] = บอกภาษาไปด้วย ·
  /// ขั้นสุดท้ายให้เดาภาษาเอง สำหรับวันที่รุ่นเก่าปิดแล้วและ OpenAI ยังไม่รับ `th`
  static List<SttRung> sttLadder({String legacy = legacySttModel}) => [
        (model: sttModel, hint: true),
        (model: legacy, hint: true),
        (model: sttModel, hint: false),
      ];

  /// รุ่นตระกูลใหม่ใช้ `languages` แทน `language` · ส่งผิดชื่อ = 400 · ส่งทั้งคู่ก็ไม่ได้
  static bool usesLanguages(String sttModel) =>
      sttModel == 'gpt-transcribe' || sttModel == 'gpt-live-transcribe';

  static const baseUrl = 'https://api.openai.com/v1';

  static bool get configured => apiKey.isNotEmpty;

  /// รายการที่ให้เลือกในหน้าตั้งค่า — ยืนยันแล้วว่าบัญชีเรียกได้จริง
  /// (ดึงจาก GET /v1/models เมื่อ 2026-08-29 ไม่ได้เดาชื่อ)
  /// ชื่อรุ่นเป็นวิสามานยนาม ไม่ต้องแปล · คำอธิบายอยู่ใน i18n/enum_labels.dart
  /// ตรวจกับเอกสาร OpenAI เมื่อ 2026-11-02 (developers.openai.com/api/docs/models)
  /// · ทุกตัวใช้กับ /v1/chat/completions ได้ · เรียงจากค่าตั้งต้น → ใหม่ → ถูก → แพง
  ///
  /// ถอดออก: `gpt-5.5` (เก่ากว่าและแพงกว่า 5.6 Sol) · `gpt-5.4-mini` และ
  /// `gpt-5.6-luna` (มี 6 Luna ที่ถูกกว่าแทน) · ใครเลือกไว้แล้วยังใช้ต่อได้
  /// ผ่านช่อง "พิมพ์ชื่อรุ่นเอง" เพราะ OpenAI ยังไม่ได้ปิดรุ่นพวกนั้น
  static const brainChoices = <({String id, String label})>[
    (id: 'gpt-5.6-sol', label: '5.6 Sol'),
    (id: 'gpt-6.1-sol', label: '6.1 Sol'),
    (id: 'gpt-6.1-terra', label: '6.1 Terra'),
    (id: 'gpt-5.6-terra', label: '5.6 Terra'),
    (id: 'gpt-6-luna', label: '6 Luna'),
    (id: 'gpt-6-astra', label: '6 Astra'),
  ];

  /// ระดับการคิดภายใน (`reasoning_effort`) ที่จะขอ · null = ไม่ส่ง
  ///
  /// 🔴 ต้องส่งเอง · ไม่ส่ง = รุ่น 5.6/6 คิดภายในระดับ medium ซึ่งกินโควตา
  /// `max_completion_tokens` เดียวกับคำตอบ (เอกสาร: นับรวม reasoning tokens)
  /// · เพดานคำตอบ 600 ของแอปจึงหมดไปกับการคิดได้ แล้วเธอตอบกลับมาว่างเปล่า
  /// และงานคุยเล่นไม่ต้องคิดลึก การคิดยิ่งมากยิ่งรอนาน
  ///
  /// - 6 Astra / 6.1 Sol ไม่รับ `none` (ตอบ 400) → ต่ำสุดคือ `low` · 6.1 Terra รับ `none` (เอกสารรุ่น 2026-11-02)
  /// - 5.x ที่มีจุด (5.1 ขึ้นไป) และ 6 อื่น ๆ → `none`
  /// - `gpt-5` / `gpt-5-mini` / `gpt-5-nano` รุ่นแรกไม่มี `none` → `minimal`
  /// - รุ่นอื่น (gpt-4o, รุ่นที่พิมพ์เอง) → ไม่ส่ง ไม่งั้นรุ่นที่ไม่ใช่สาย
  ///   reasoning ตอบ 400 "Unsupported parameter"
  static String? effortFor(String model) {
    final id = model.trim().toLowerCase();
    if (id.contains('-chat')) return null;
    if (id.startsWith('gpt-6-astra') || id.startsWith('gpt-6.1-sol')) return 'low';
    if (RegExp(r'^gpt-5\.\d').hasMatch(id) || id.startsWith('gpt-6')) return 'none';
    if (RegExp(r'^gpt-5(-mini|-nano)?(-\d{4}-\d{2}-\d{2})?$').hasMatch(id)) {
      return 'minimal';
    }
    return null;
  }

  /// เสียงทั้งหมดที่ Realtime รู้จัก (ตรวจ 2026-11-02) · ไม่มี fable/nova/onyx ของ TTS เดิม
  static const realtimeVoices = {
    'alloy',
    'ash',
    'ballad',
    'coral',
    'echo',
    'sage',
    'shimmer',
    'verse',
    'marin',
    'cedar',
  };

  /// เสียงที่เข้ากับบุคลิกมายด์ · ทุกตัวต้องอยู่ใน [realtimeVoices]
  /// marin กับ cedar มาก่อน — เอกสาร OpenAI แนะนำสองตัวนี้ว่าคุณภาพดีที่สุด
  /// (ตรวจ 2026-11-02)
  static const voiceChoices = <String>[
    'marin',
    'cedar',
    'coral',
    'shimmer',
    'sage',
    'ballad',
  ];

  /// โมเดลเสียงที่เสนอ
  ///
  /// 🔴 เหลือตัวเดียวโดยตั้งใจ · `tts-1` / `tts-1-hd` / `gpt-4o-mini-tts` ปิด
  /// 2027-01-06 พร้อมกัน และ `/v1/audio/speech` ไม่เหลือรุ่นแทน · ค่าที่เคยเลือกไว้
  /// ถูกย้ายมาตัวนี้ตอนโหลด ([migrateTts])
  static const ttsChoices = <String>[ttsModel];

  /// รุ่นเสียงที่ปิด/ใกล้ปิดแล้ว → รุ่นที่ใช้แทน · รวม snapshot มีวันที่ท้ายชื่อ
  static String migrateTts(String model) =>
      model.startsWith('tts-1') || model.startsWith('gpt-4o-mini-tts')
          ? ttsModel
          : model;

  /// เสียงของ TTS เดิมที่ไม่มีใน Realtime → ตัวที่ OpenAI แนะนำ · ไม่ย้าย = error ทุกประโยค
  static String migrateVoice(String voice) =>
      const {'fable', 'nova', 'onyx'}.contains(voice) ? 'marin' : voice;

  /// รุ่นนี้ต้องสังเคราะห์ผ่าน Realtime ไม่ใช่ /v1/audio/speech (ดู RealtimeSpeech)
  static bool speaksOverRealtime(String ttsModel) =>
      ttsModel.startsWith('gpt-realtime');

  /// โมเดลที่รับพารามิเตอร์ `instructions` — ตัวอื่นส่งไปก็ไม่มีผล
  static bool supportsInstructions(String ttsModel) =>
      speaksOverRealtime(ttsModel) ||
      ttsModel.startsWith('gpt-4o') ||
      ttsModel.startsWith('gpt-audio');
}

/// หนึ่งขั้นของ [OpenAiConfig.sttLadder]
typedef SttRung = ({String model, bool hint});
