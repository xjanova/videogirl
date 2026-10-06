import 'strings.dart';

/// ข้อความของเจ้าเสียงพรีเมียม (Gemini · ElevenLabs · Azure)
extension VoiceStrings on S {
  String get ttsGemini => pick('Google Gemini', 'Google Gemini');
  String get ttsGeminiHint => pick(
        'พูดไทยเป็นธรรมชาติ สั่งอารมณ์เสียงด้วยข้อความได้ · ใช้คีย์ Google AI Studio ของคุณ',
        'Natural Thai, tone steered with plain words · uses your Google AI Studio key',
      );
  String get ttsElevenLabs => pick('ElevenLabs', 'ElevenLabs');
  String get ttsElevenLabsHint => pick(
        'เสียงเหมือนคนที่สุด ใช้เสียงในบัญชีของคุณได้ · ใช้คีย์ ElevenLabs ของคุณ · แพงกว่าเจ้าอื่น',
        'Most human-sounding, can use the voices in your account · your ElevenLabs key · costs more',
      );
  String get ttsAzure => pick('Microsoft Azure', 'Microsoft Azure');
  String get ttsAzureHint => pick(
        'มีเสียงไทยโดยเฉพาะ ชัด นิ่ง · ใช้คีย์ Azure Speech และภูมิภาคของคุณ',
        'Dedicated Thai voices, clear and steady · your Azure Speech key and region',
      );

  // ── คีย์ ──
  String premiumKeyTitle(String provider) => pick('คีย์ $provider', '$provider key');
  String get premiumKeyNotSet => pick('ยังไม่ได้ใส่คีย์', 'No key yet');
  String premiumKeyNeeded(String provider) => pick(
        'ยังไม่มีคีย์ $provider — เธอจะพูดด้วยเสียงเครื่องไปก่อน',
        'No $provider key yet — she will use the phone voice until you add one',
      );
  String get premiumKeyEditorGemini => pick(
        'คีย์จาก aistudio.google.com › Get API key · เก็บในที่เก็บลับของเครื่องนี้เท่านั้น',
        'A key from aistudio.google.com › Get API key · stored only in this phone\'s secure storage',
      );
  String get premiumKeyEditorElevenLabs => pick(
        'คีย์จาก elevenlabs.io › Profile › API keys · เก็บในที่เก็บลับของเครื่องนี้เท่านั้น',
        'A key from elevenlabs.io › Profile › API keys · stored only in this phone\'s secure storage',
      );
  String get premiumKeyEditorAzure => pick(
        'คีย์จาก Azure portal › Speech service › Keys and Endpoint · เก็บในที่เก็บลับของเครื่องนี้เท่านั้น',
        'A key from Azure portal › Speech service › Keys and Endpoint · stored only in this phone\'s secure storage',
      );
  String get azureRegionTitle => pick('ภูมิภาคของ Azure', 'Azure region');
  String get azureRegionEditor => pick(
        'ภูมิภาคที่สร้าง Speech service ไว้ เช่น southeastasia (ดูได้ในหน้า Keys and Endpoint)',
        'The region of your Speech service, e.g. southeastasia (shown on Keys and Endpoint)',
      );

  // ── รุ่น / เสียง / สไตล์ ──
  String get premiumModel => pick('รุ่นเสียง', 'Voice model');
  String get premiumVoice => pick('เสียง', 'Voice');
  String get premiumStyle => pick('สั่งน้ำเสียง', 'Tone direction');
  String get premiumStyleEditor => pick(
        'บอกเป็นคำธรรมดาว่าอยากให้พูดแบบไหน เช่น "พูดอบอุ่น ยิ้ม ๆ ไม่เร็วเกินไป"',
        'Say in plain words how she should sound, e.g. "warm, smiling, not too fast"',
      );
  String get premiumNoStyle => pick(
        'เจ้านี้สั่งน้ำเสียงด้วยข้อความไม่ได้ — น้ำเสียงมากับตัวเสียงที่เลือก',
        'This provider does not take tone directions — the tone comes with the voice you pick',
      );
  String get elevenVoicesLoad => pick('โหลดเสียงในบัญชีของฉัน', 'Load the voices in my account');
  String get elevenVoicesLoading => pick('กำลังโหลดรายชื่อเสียง…', 'Loading voices…');
  String elevenVoicesLoaded(int n) =>
      pick('เจอ $n เสียงในบัญชี', 'Found $n voices in your account');

  // ── ข้อผิดพลาด ──
  String get elevenPickVoice => pick(
        'ยังไม่ได้เลือกเสียง ElevenLabs — กด "โหลดเสียงในบัญชีของฉัน" แล้วเลือกหนึ่งเสียง',
        'No ElevenLabs voice picked — tap "Load the voices in my account" and choose one',
      );
  String get azureNeedsRegion => pick(
        'ยังไม่ได้ใส่ภูมิภาคของ Azure (เช่น southeastasia)',
        'No Azure region set yet (e.g. southeastasia)',
      );
  String premiumBadKey(String provider) =>
      pick('คีย์ $provider ใช้ไม่ได้ ตรวจคีย์อีกครั้ง', 'The $provider key was rejected — check it again');
  String premiumQuota(String provider) => pick(
        '$provider ปฏิเสธเพราะโควตา/เครดิตหมด หรือเรียกถี่เกินไป',
        '$provider refused: quota or credit used up, or too many requests',
      );
  String premiumFailed(String provider) =>
      pick('$provider สร้างเสียงไม่สำเร็จ', '$provider could not make the audio');

  // ── ลองฟังเสียง ──
  String previewMaking(String what) =>
      pick('กำลังสร้างเสียงจาก $what…', 'Making the sample with $what…');
  String previewPlaying(String what) => pick('กำลังเล่น: $what', 'Playing: $what');
  String previewPlayed(String what) => pick('ได้ยินเสียงจริงของ $what', 'That was really $what');
  /// [fallback] = ตอนคุยจริงมีเสียงเครื่องรับแทน (ไม่จริงเมื่อเสียงเครื่องเองที่ล้ม)
  String previewFailed(String what, String why, {bool fallback = true}) => fallback
      ? pick(
          'ลองฟัง $what ไม่ได้ — $why\nตอนคุยจริง เธอจะใช้เสียงเครื่องแทนจนกว่าจะแก้',
          'Could not play $what — $why\nIn real chats she uses the phone voice until this is fixed',
        )
      : pick('ลองฟัง $what ไม่ได้ — $why', 'Could not play $what — $why');
}
