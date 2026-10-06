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
        'วางคีย์ Gemini (ขึ้นต้นด้วย AIza) · เก็บในที่เก็บลับของเครื่องนี้เท่านั้น · ดูวิธีเอาคีย์ใต้ช่องคีย์',
        'Paste your Gemini key (starts with AIza) · kept only in this phone\'s secure storage · see "How to get" under the key row',
      );
  String get premiumKeyEditorElevenLabs => pick(
        'วางคีย์ ElevenLabs (ขึ้นต้นด้วย sk_) · เก็บในที่เก็บลับของเครื่องนี้เท่านั้น · ดูวิธีเอาคีย์ใต้ช่องคีย์',
        'Paste your ElevenLabs key (starts with sk_) · kept only in this phone\'s secure storage · see "How to get" under the key row',
      );
  String get premiumKeyEditorAzure => pick(
        'วาง KEY 1 จาก Azure Speech · เก็บในที่เก็บลับของเครื่องนี้เท่านั้น · ดูวิธีเอาคีย์ใต้ช่องคีย์',
        'Paste KEY 1 from Azure Speech · kept only in this phone\'s secure storage · see "How to get" under the key row',
      );
  String get azureRegionTitle => pick('ภูมิภาคของ Azure', 'Azure region');
  String get azureRegionEditor => pick(
        'ภูมิภาคที่สร้าง Speech service ไว้ เช่น southeastasia (ดูได้ในหน้า Keys and Endpoint)',
        'The region of your Speech service, e.g. southeastasia (shown on Keys and Endpoint)',
      );

  // ── วิธีเอาคีย์ ──
  String keyGuideTitle(String provider) =>
      pick('วิธีเอาคีย์ $provider', 'How to get a $provider key');
  String keyGuideOpen(String host) => pick('เปิด $host', 'Open $host');

  List<String> get keyGuideOpenAi => isThai
      ? const [
          'เปิดหน้า API keys ของ OpenAI แล้วล็อกอิน (สมัครด้วยอีเมลหรือบัญชี Google ได้)',
          'เติมเครดิตก่อน: Settings › Billing › เพิ่มบัตรและเติมเงิน (ขั้นต่ำราว 5 ดอลลาร์) — ไม่มีเครดิต คีย์จะใช้ไม่ได้',
          'กลับมาหน้า API keys › กด "Create new secret key" ตั้งชื่อ เช่น GigGok',
          'คัดลอกคีย์ที่ขึ้นต้นด้วย sk- ทันที — เว็บโชว์ให้ดูแค่ครั้งเดียว',
          'กลับมาที่แอป แตะช่อง "คีย์ของคุณเอง" แล้ววาง',
        ]
      : const [
          'Open the OpenAI API keys page and sign in (email or Google account)',
          'Add credit first: Settings › Billing › add a card and top up (about US\$5 minimum) — keys do nothing without credit',
          'Back on API keys › "Create new secret key", name it e.g. GigGok',
          'Copy the key starting with sk- right away — it is shown only once',
          'In the app, tap "Your own key" and paste it',
        ];

  List<String> get keyGuideGemini => isThai
      ? const [
          'เปิดหน้า API key ของ Google AI Studio แล้วล็อกอินด้วยบัญชี Google',
          'กด "Create API key" (ถ้าถามโปรเจกต์ ให้สร้างใหม่หรือเลือกที่มีอยู่)',
          'คัดลอกคีย์ที่ขึ้นต้นด้วย AIza',
          'กลับมาที่แอป แตะช่องคีย์ Gemini แล้ววาง',
          'แผนฟรีใช้ได้ทันที แต่ Google นำข้อมูลไปปรับปรุงบริการ · ไม่ต้องการแบบนั้นให้กด Set up billing ใน AI Studio',
        ]
      : const [
          'Open the Google AI Studio API key page and sign in with Google',
          'Tap "Create API key" (create or pick a project if asked)',
          'Copy the key starting with AIza',
          'In the app, tap the Gemini key row and paste it',
          'The free tier works right away, but Google uses the data to improve its products — set up billing in AI Studio if you do not want that',
        ];

  List<String> get keyGuideElevenLabs => isThai
      ? const [
          'สมัครหรือล็อกอิน elevenlabs.io (แผนฟรี 10,000 ตัวอักษรต่อเดือน ใช้เชิงพาณิชย์ไม่ได้)',
          'เปิดหน้า API Keys (เมนูโปรไฟล์ › API Keys)',
          'กด "Create API Key" ตั้งชื่อ แล้วให้สิทธิ์ Text to Speech และอ่าน Voices เป็นอย่างน้อย',
          'คัดลอกคีย์ที่ขึ้นต้นด้วย sk_ แล้ววางในช่องคีย์ ElevenLabs ในแอป',
          'กด "โหลดเสียงในบัญชีของฉัน" แล้วเลือกเสียง · หาเสียงไทยเพิ่มได้จาก Voice Library บนเว็บ แล้วกดโหลดใหม่',
        ]
      : const [
          'Sign up or sign in at elevenlabs.io (free plan: 10,000 characters a month, non-commercial)',
          'Open the API Keys page (profile menu › API Keys)',
          'Tap "Create API Key", name it, and allow at least Text to Speech and reading Voices',
          'Copy the key starting with sk_ and paste it into the ElevenLabs key row',
          'Tap "Load the voices in my account" and pick one · add Thai voices from the Voice Library on the web, then load again',
        ];

  List<String> get keyGuideAzure => isThai
      ? const [
          'ล็อกอิน portal.azure.com (สมัครต้องยืนยันด้วยบัตร แต่มีแผนฟรี)',
          'สร้าง resource ใหม่ › ค้นหา "Speech" › เลือก Speech service › Create',
          'Region เลือกที่ใกล้ไทย เช่น Southeast Asia · Pricing tier เลือก Free F0 (ฟรี 0.5 ล้านตัวอักษรต่อเดือน) หรือ S0',
          'สร้างเสร็จ › เปิด resource › เมนู "Keys and Endpoint" › คัดลอก KEY 1',
          'ในหน้าเดียวกันดู "Location/Region" (เช่น southeastasia) · ใส่ทั้งคีย์และภูมิภาคในแอป',
        ]
      : const [
          'Sign in to portal.azure.com (sign-up needs a card, but there is a free tier)',
          'Create a resource › search "Speech" › Speech service › Create',
          'Pick a region near you, e.g. Southeast Asia · pricing tier Free F0 (500,000 characters a month) or S0',
          'When it is ready › open the resource › "Keys and Endpoint" › copy KEY 1',
          'On the same page read "Location/Region" (e.g. southeastasia) · enter both the key and the region in the app',
        ];

  // ── เซิร์ฟเวอร์ในบ้าน: ค้นหา · ทดสอบ ──
  String get homeScan => pick('ค้นหาเซิร์ฟเวอร์ในวงไวไฟ', 'Find servers on this Wi-Fi');
  String homeScanning(int pct) => pick('กำลังค้นหา… $pct%', 'Searching… $pct%');
  String homeScanFound(int n) =>
      pick('เจอ $n เซิร์ฟเวอร์ · แตะเพื่อใช้', 'Found $n server(s) · tap one to use it');
  String get homeScanNone => pick(
        'ไม่เจอเซิร์ฟเวอร์ในวงไวไฟนี้ · เช็กว่า มือถืออยู่ไวไฟเดียวกับคอม · Ollama ตั้ง '
            'OLLAMA_HOST=0.0.0.0 แล้วเปิดใหม่ · LM Studio เปิด "Serve on Local Network" · '
            'ไฟร์วอลล์ของคอมยอมพอร์ตนั้น',
        'No server found on this Wi-Fi · check the phone is on the same Wi-Fi as the PC · '
            'Ollama: set OLLAMA_HOST=0.0.0.0 and restart · LM Studio: turn on "Serve on Local Network" · '
            "the PC's firewall allows that port",
      );
  String get homeThisPhone => pick('ในเครื่องนี้ (เช่น Termux)', 'On this phone (e.g. Termux)');
  String homeModelCount(int n) => pick('$n รุ่น', '$n model(s)');
  String get homeModelsHere => pick('รุ่นบนเซิร์ฟเวอร์นี้', 'Models on this server');
  String get homeLoadModels => pick('โหลดรายชื่อรุ่นจากเซิร์ฟเวอร์', 'Load the model list from the server');
  String get homeTest => pick('ทดสอบว่าใช้ได้', 'Test that it works');
  String get homeTesting => pick('กำลังทดสอบ…', 'Testing…');
  String get homeTestSystem =>
      pick('ตอบสั้นที่สุด คำเดียว เป็นภาษาไทย', 'Answer with a single word.');
  String get homeTestQuestion => pick('พร้อมใช้งานไหม', 'Are you ready?');
  String homeTestOk(String sec, String reply) =>
      pick('ใช้ได้ · ตอบใน $sec วิ: "$reply"', 'Works · answered in $sec s: "$reply"');
  String homeUnreachable(String url) => pick(
        'ติดต่อ $url ไม่ได้ · อยู่ไวไฟเดียวกับคอมไหม · โปรแกรมบนคอมเปิดอยู่ไหม · Ollama ต้องตั้ง OLLAMA_HOST=0.0.0.0',
        'Cannot reach $url · same Wi-Fi as the PC? · is the program running? · Ollama needs OLLAMA_HOST=0.0.0.0',
      );
  String homeModelMissing(String model, String have) => pick(
        'ไม่มีรุ่น "$model" บนเซิร์ฟเวอร์นี้ · ที่มีคือ: $have',
        'This server has no model "$model" · it has: $have',
      );

  // ── ตอนอยู่ในสาย ──
  String get inCallTitle => pick('ตอนอยู่ในสาย เธอใช้อะไร', 'What she uses on a call');
  String get inCallListen => pick('ฟังคู่สาย', 'Listens with');
  String get inCallThink => pick('คิดด้วย', 'Thinks with');
  String get inCallSpeak => pick('พูดด้วย', 'Speaks with');
  String get inCallWhere => pick(
        'เปลี่ยนสมองได้ที่ สมองและเสียง › สมองของเธอ · เปลี่ยนเสียงได้ที่ เสียงพูด › แท็บรับสาย',
        'Change the brain under Brain & voice › Her brain · change the voice under Voice › the Answering tab',
      );
  String get callListenOnDevice => pick(
        'ถอดเสียงในเครื่อง (Android 13 ขึ้นไป · เสียงคู่สายไม่ออกนอกเครื่อง)',
        'On-device transcription (Android 13+ · the caller\'s voice never leaves the phone)',
      );
  String get callListenOpenAi =>
      pick('OpenAI whisper-1 ด้วยคีย์ของคุณ', 'OpenAI whisper-1 with your key');
  String get callListenProxy =>
      pick('บริการของเรา (ใช้ไลเซนส์ของเครื่อง)', 'Our service (uses this device\'s license)');
  String get callListenHome => pick('เซิร์ฟเวอร์ในบ้านของคุณ', 'Your home server');

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
