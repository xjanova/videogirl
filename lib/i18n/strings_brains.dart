import 'strings.dart';

/// ข้อความของหน้า "สมองและเสียง" — สามกรอบ: สมองเอไอ · ตัวถอดเสียง · โมเดลสังเคราะห์เสียง
/// รวมถึงเจ้าสมองใหม่ (Grok · Claude · Gemini) และการปรับแต่ง/โคลนเสียง ElevenLabs
extension BrainStrings on S {
  // ═══ สามกรอบ ════════════════════════════════════════════
  String get frameBrainTitle => pick('สมองเอไอ', 'AI brain');
  String get frameBrainWhat => pick(
        'ใครเป็นคนคิดคำตอบให้เธอ — เลือกเจ้าก่อน แล้วค่อยเลือกรุ่น',
        'Who thinks up her answers — pick a provider first, then a model',
      );
  String get frameSttTitle => pick('ตัวถอดเสียง', 'Speech-to-text');
  String get frameSttWhat => pick(
        'ฟังเสียงพูดของคุณ (ไมค์ในแชท · คู่สายตอนรับสาย) แล้วแปลงเป็นข้อความส่งให้สมอง',
        'Hears your voice (chat mic · the caller on a call) and turns it into text for the brain',
      );
  String get frameTtsTitle => pick('โมเดลสังเคราะห์เสียง', 'Voice synthesis model');
  String get frameTtsWhat => pick(
        'เปลี่ยนคำตอบที่เป็นข้อความให้เป็นเสียงพูดของเธอ',
        'Turns her written answer into her speaking voice',
      );
  String frameStep(int n) => pick('ขั้นที่ $n', 'Step $n');
  String get stepPickProvider => pick('เลือกเจ้าที่จะใช้', 'Pick a provider');
  String get stepPickModel => pick('เลือกรุ่น', 'Pick a model');
  String get stepKey => pick('ใส่คีย์ของเจ้านี้', "Enter this provider's key");
  String get nowUsing => pick('ใช้อยู่', 'In use');

  // ═══ เจ้าสมองใหม่ ══════════════════════════════════════════
  String get brainGrok => pick('xAI Grok', 'xAI Grok');
  String get brainGrokSummary => pick(
        'คีย์ xAI ของคุณ · ตอบไว ราคาย่อมเยา มีรุ่นเรือธง Grok 4.7',
        'Your xAI key · quick and affordable, flagship Grok 4.7',
      );
  String get brainGrokTradeoff => pick(
        'ข้อความไปที่ xAI · จ่ายตามใช้กับบัญชี xAI ของคุณ · ถอดเสียงด้วย Grok ได้ในคีย์เดียว',
        'Messages go to xAI · pay as you go on your xAI account · Grok can also transcribe with the same key',
      );
  String get brainClaude => pick('Anthropic Claude', 'Anthropic Claude');
  String get brainClaudeSummary => pick(
        'คีย์ Anthropic ของคุณ · เขียนเป็นธรรมชาติ คิดรอบคอบ',
        'Your Anthropic key · natural writing, careful thinking',
      );
  String get brainClaudeTradeoff => pick(
        'ข้อความไปที่ Anthropic · Claude ไม่มีบริการถอดเสียง จึงถอดเสียงในเครื่อง (หรือเลือกเจ้าอื่นในกรอบตัวถอดเสียง)',
        'Messages go to Anthropic · Claude has no speech-to-text, so your voice is transcribed on the phone (or pick another in the speech-to-text box)',
      );
  String get brainGemini => pick('Google Gemini', 'Google Gemini');
  String get brainGeminiSummary => pick(
        'คีย์ AI Studio ของคุณ (ตัวเดียวกับเสียง Gemini) · มีแผนฟรีให้ลอง',
        'Your AI Studio key (same as the Gemini voice) · free tier to try',
      );
  String get brainGeminiTradeoff => pick(
        'ข้อความไปที่ Google · แผนฟรี Google นำข้อมูลไปปรับปรุงบริการ ถ้าไม่ต้องการให้เปิด billing',
        'Messages go to Google · on the free tier Google may use the data to improve services; turn on billing to avoid that',
      );
  String brainKeyNeeded(String who) => pick(
        'ยังไม่ได้ใส่คีย์ $who — ใส่ได้ในหน้าตั้งค่า › สมองเอไอ',
        'No $who key yet — add it in Settings › AI brain',
      );
  String brainKeyTitle(String who) => pick('คีย์ $who', '$who key');
  String brainKeyLooksWrong(String who) => pick(
        'คีย์นี้หน้าตาไม่เหมือนคีย์ของ $who — ตรวจอีกทีนะคะ',
        "This doesn't look like a $who key — please check it",
      );
  String get brainKeyShared => pick(
        'คีย์นี้ใช้ร่วมกับเสียง Gemini ในกรอบโมเดลสังเคราะห์เสียง',
        'This key is shared with the Gemini voice below',
      );

  /// คำอธิบายรุ่นสมอง (CloudBrains) · ตามหน้าทางการของแต่ละเจ้า
  String brainModelHintOf(String id) => switch (id) {
        'gpt-5.6-sol' => pick('ฉลาดที่สุดของรุ่น 5.6 ตอบไว · ค่าเริ่มต้นของแอป', 'Smartest of 5.6, quick to answer · app default'),
        'gpt-6.1-sol' => pick('รุ่นใหม่ล่าสุด คิดละเอียดกว่า ตอบช้ากว่าเล็กน้อย', 'Newest, more careful, a little slower to answer'),
        'gpt-6.1-terra' => pick('เร็วและถูก ฉลาดพอสำหรับคุยทั่วไป', 'Fast and cheap, smart enough for everyday chat'),
        'gpt-5.6-terra' => pick('รุ่นกลางของ 5.6 สมดุลระหว่างความฉลาดกับราคา', 'Middle of 5.6, balances smarts and cost'),
        'gpt-6-luna' => pick('ถูกที่สุด ตอบไวมาก คิดตื้นกว่า เหมาะคุยเล่น', 'Cheapest and very fast, shallower thinking — fine for small talk'),
        'gpt-6-astra' => pick('ฉลาดที่สุดของ OpenAI สำหรับงานยาก ช้าและแพง', "OpenAI's most capable, for hard work — slow and pricey"),
        'grok-4.3' => pick('ตอบไว ราคาย่อมเยา ปิดการคิดยาวได้ · เหมาะคุยทั่วไป', 'Quick and affordable, long thinking can be switched off · good for chat'),
        'grok-4.7' => pick('รุ่นเรือธงล่าสุดของ xAI ฉลาดที่สุด เก่งงานหลายขั้นและโค้ด', "xAI's newest flagship, its most capable — strong at multi-step work and code"),
        'claude-haiku-5-5' => pick('เร็วที่สุดและถูกที่สุดของ Claude เหมาะคุยเล่นและตอบสั้น', "Claude's fastest and cheapest — good for chat and short answers"),
        'claude-sonnet-5-5' => pick('สมดุลที่สุดระหว่างความเร็วกับความฉลาด ภาษาไทยเป็นธรรมชาติ', 'Best balance of speed and intelligence, natural writing'),
        'claude-opus-5-5' => pick('คิดลึก เหมาะงานยาวและงานที่ต้องใช้ความรู้ ตอบช้ากว่า', 'Deep thinker for long, knowledge-heavy work — slower to answer'),
        'claude-fable-5-1' => pick('ฉลาดที่สุดของ Anthropic สำหรับงานคิดหนักมาก ช้าและแพงที่สุด', "Anthropic's most capable for very demanding reasoning — slowest and priciest"),
        'gemini-3.5-flash-lite' => pick('ถูกและไว เหมาะงานเยอะ ๆ และคุยทั่วไป · มีแผนฟรีให้ลอง', 'Cheap and quick for high volume and everyday chat · free tier available'),
        'gemini-3.8-flash' => pick('Flash ที่ฉลาดที่สุด เก่งงานหลายขั้น · มีแผนฟรีให้ลอง', 'The smartest Flash, strong at multi-step work · free tier available'),
        'gemini-4-argon' => pick('รุ่นเรือธงของ Google คิดลึกที่สุด · ไม่มีแผนฟรี', "Google's flagship, deepest reasoning · no free tier"),
        _ => '',
      };

  String brainModelPriceNote(String id) => switch (id) {
        'claude-haiku-5-5' => pick('ราคานี้เมื่อข้อความเข้าไม่เกิน 100,000 โทเคน (เกินนั้น \$0.50 / \$2.50)', 'For prompts up to 100,000 tokens (above that \$0.50 / \$2.50)'),
        'gemini-3.8-flash' => pick('ราคานี้ถึง 31 ธ.ค. 2026 · ตั้งแต่ 1 ม.ค. 2027 เป็น \$1.50 / \$7.50', 'Until Dec 31, 2026 · from Jan 1, 2027: \$1.50 / \$7.50'),
        'gemini-4-argon' => pick('ราคานี้ถึง 30 พ.ย. 2026 · ตั้งแต่ 1 ธ.ค. 2026 เป็น \$4 / \$20', 'Until Nov 30, 2026 · from Dec 1, 2026: \$4 / \$20'),
        _ => '',
      };

  // ═══ ราคา / ความสามารถ ═══════════════════════════════════════
  String brainPrice(String inUsd, String outUsd) => pick(
        'เข้า \$$inUsd · ออก \$$outUsd ต่อล้านโทเคน',
        'In \$$inUsd · out \$$outUsd per 1M tokens',
      );
  String brainPer1k(String usd) => pick(
        '≈ \$$usd ต่อ 1,000 ข้อความ',
        '≈ \$$usd per 1,000 messages',
      );
  String get brainFreeTier => pick('มีแผนฟรี', 'Free tier');
  String brainContext(int k) => pick(
        'จำบทสนทนาได้ ${k >= 1000 ? '${k ~/ 1000} ล้าน' : '$k พัน'} โทเคน',
        'Context ${k >= 1000 ? '${k ~/ 1000}M' : '${k}K'} tokens',
      );
  String get tierCheap => pick('ประหยัด', 'Budget');
  String get tierBalanced => pick('สมดุล', 'Balanced');
  String get tierSmart => pick('ฉลาด', 'Smart');
  String get tierTop => pick('ฉลาดสุด', 'Top');
  String get brainPriceFootnote => pick(
        'ราคาจากหน้าราคาทางการ ตรวจ 2 พ.ย. 2026 · ต่อ 1,000 ข้อความคิดจากข้อความเข้า ~3,000 และออก ~250 โทเคน ไว้เทียบรุ่นกันเท่านั้น · จ่ายตรงกับเจ้านั้นด้วยบัญชีของคุณ',
        'Prices from the official pricing pages, checked Nov 2, 2026 · per-1,000-messages assumes ~3,000 in and ~250 out tokens, for comparing models only · billed directly by the provider to your account',
      );

  // ═══ คู่มือเอาคีย์ ═══════════════════════════════════════════
  List<String> get keyGuideGrok => isThai
      ? const [
          'เปิดหน้า xAI Console แล้วล็อกอิน (บัญชี X หรืออีเมล)',
          'เติมเครดิตในเมนู Billing ก่อน — ไม่มีเครดิตจะเรียกใช้ไม่ได้',
          'ไปที่ API Keys แล้วกด Create API key',
          'คัดลอกคีย์ที่ขึ้นต้นด้วย xai-',
          'กลับมาที่แอป แตะช่องคีย์ Grok แล้ววาง',
        ]
      : const [
          'Open the xAI Console and sign in (X account or email)',
          'Add credits under Billing first — calls fail without credit',
          'Go to API Keys and tap Create API key',
          'Copy the key starting with xai-',
          'In the app, tap the Grok key row and paste it',
        ];
  List<String> get keyGuideClaude => isThai
      ? const [
          'เปิดหน้า Claude Console (console.anthropic.com) แล้วล็อกอิน',
          'เติมเครดิตในเมนู Billing ก่อน — ไม่มีเครดิตจะเรียกใช้ไม่ได้',
          'ไปที่ API Keys แล้วกด Create Key',
          'คัดลอกคีย์ที่ขึ้นต้นด้วย sk-ant-',
          'กลับมาที่แอป แตะช่องคีย์ Claude แล้ววาง',
        ]
      : const [
          'Open the Claude Console (console.anthropic.com) and sign in',
          'Add credits under Billing first — calls fail without credit',
          'Go to API Keys and tap Create Key',
          'Copy the key starting with sk-ant-',
          'In the app, tap the Claude key row and paste it',
        ];

  // ═══ ตัวถอดเสียง ═══════════════════════════════════════════
  String get sttAuto => pick('ตามสมองที่เลือก', 'Follow the brain');
  String sttAutoHint(String now) => pick(
        'เลือกให้อัตโนมัติ · ตอนนี้คือ: $now',
        'Chosen for you · right now: $now',
      );
  String get sttDevice => pick('ในเครื่อง (Android)', 'On the phone (Android)');
  String get sttDeviceHint => pick(
        'ฟรี เสียงไม่ออกนอกเครื่อง · ต้องมีชุดภาษาไทยในเครื่อง · แม่นน้อยกว่าบนคลาวด์',
        'Free, audio never leaves the phone · needs the language pack · less accurate than cloud',
      );
  String get sttOpenAi => pick('OpenAI gpt-transcribe', 'OpenAI gpt-transcribe');
  String get sttOpenAiHint => pick(
        'แม่นและไว · ใช้คีย์ OpenAI · คิดตามเวลาเสียง',
        'Accurate and quick · uses your OpenAI key · billed per audio time',
      );
  String get sttEleven => pick('ElevenLabs Scribe v2', 'ElevenLabs Scribe v2');
  String get sttElevenHint => pick(
        'แม่นสูง 90+ ภาษารวมไทย · ใช้คีย์ ElevenLabs · \$0.22 ต่อชั่วโมงเสียง',
        'Highly accurate, 90+ languages incl. Thai · ElevenLabs key · \$0.22 per audio hour',
      );
  String get sttGrok => pick('xAI Grok Transcribe 2.0', 'xAI Grok Transcribe 2.0');
  String get sttGrokHint => pick(
        'รองรับไทย ตรวจภาษาเอง · ใช้คีย์ xAI',
        'Supports Thai, detects language itself · uses your xAI key',
      );
  String get sttViaBrain => pick('ทางเดียวกับสมอง', 'Same route as the brain');
  String get sttReady => pick('พร้อมใช้', 'Ready');
  String get sttNotReady => pick('ยังใช้ไม่ได้', 'Not ready');
  String get sttGoesOut => pick(
        'เสียงพูดของคุณจะถูกส่งไปถอดที่เจ้านี้',
        'Your voice is sent to this provider to transcribe',
      );
  String get sttStaysHere => pick(
        'เสียงพูดของคุณไม่ออกนอกเครื่อง',
        'Your voice never leaves the phone',
      );

  // ═══ ElevenLabs: ปรับแต่ง ═══════════════════════════════════
  String get elTuneTitle => pick('ปรับแต่งเสียง ElevenLabs', 'ElevenLabs voice tuning');
  String get elTuneWhat => pick(
        'ทุกค่าที่ ElevenLabs เปิดให้ปรับ · ไม่แตะอะไร = ค่าตั้งต้นของ ElevenLabs',
        'Every setting ElevenLabs exposes · leave them = ElevenLabs defaults',
      );
  String get elStability => pick('ความนิ่งของเสียง', 'Stability');
  String get elStabilityHint => pick(
        'ต่ำ = อารมณ์กว้าง มีชีวิตชีวา · สูง = นิ่ง สม่ำเสมอ (อาจแบน)',
        'Low = wider emotion, livelier · high = steady and consistent (can sound flat)',
      );
  String get elSimilarity => pick('ความเหมือนเสียงต้นฉบับ', 'Similarity');
  String get elSimilarityHint => pick(
        'สูง = ยึดเสียงต้นฉบับมาก เหมาะกับเสียงโคลน · สูงเกินอาจติดเสียงรบกวนจากต้นฉบับ',
        'High = sticks closely to the original, good for clones · too high can copy noise',
      );
  String get elStyle => pick('ขยายสไตล์การพูด', 'Style exaggeration');
  String get elStyleHint => pick(
        'ดึงลีลาเฉพาะตัวของเสียงนั้นออกมาให้ชัดขึ้น · 0 = ปิด (เร็วสุด)',
        "Brings out the voice's own manner more · 0 = off (fastest)",
      );
  String get elSpeed => pick('ความเร็วการพูด', 'Speaking speed');
  String get elSpeakerBoost => pick('เพิ่มความเหมือนผู้พูด (Speaker boost)', 'Speaker boost');
  String get elSpeakerBoostHint => pick(
        'เสียงเหมือนต้นฉบับขึ้นอีกนิด แลกกับหน่วงขึ้นเล็กน้อย',
        'A little closer to the original, at a small latency cost',
      );
  String get elV3Only => pick(
        'ใช้ได้กับรุ่น Eleven v3 · รุ่น v4 ปรับได้แค่ความนิ่งกับความเหมือน',
        'Eleven v3 only · v4 accepts stability and similarity only',
      );
  String get elMood => pick('อารมณ์ตั้งต้น (แท็กเสียง)', 'Default mood (audio tag)');
  String get elMoodHint => pick(
        'ใส่แท็กอย่าง [warmly] นำหน้าทุกประโยค ให้เธอพูดด้วยอารมณ์นั้นเสมอ',
        'Prefixes every line with a tag like [warmly] so she always speaks in that mood',
      );
  String get elMoodNone => pick('ไม่ใส่', 'None');
  String elMoodName(String tag) => switch (tag) {
        'warmly' => pick('อบอุ่น', 'Warm'),
        'happy' => pick('สดใส', 'Happy'),
        'excited' => pick('ตื่นเต้น', 'Excited'),
        'calm' => pick('ใจเย็น', 'Calm'),
        'whispers' => pick('กระซิบ', 'Whisper'),
        'professional' => pick('มืออาชีพ', 'Professional'),
        'reassuring' => pick('ปลอบใจ', 'Reassuring'),
        'sympathetic' => pick('เห็นใจ', 'Sympathetic'),
        'curious' => pick('อยากรู้', 'Curious'),
        'playfully' => pick('ขี้เล่น', 'Playful'),
        _ => tag,
      };
  String get elEffects => pick('เอฟเฟกต์เสียง', 'Audio effects');
  String get elEffectsHint => pick(
        'ฟิลเตอร์ · ห้อง · เสียงพื้นหลัง · ระยะห่างไมค์ — ไม่มีค่าใช้จ่ายเพิ่ม',
        'Filter · room · background · mic distance — no extra cost',
      );
  String get elFilter => pick('ฟิลเตอร์', 'Filter');
  String get elRoom => pick('ห้อง / เสียงก้อง', 'Room / reverb');
  String get elNoise => pick('เสียงพื้นหลัง', 'Background noise');
  String get elDistance => pick('ระยะห่างจากไมค์', 'Distance from mic');
  String get elOff => pick('ไม่ใช้', 'Off');
  String get elLoadEffects => pick('โหลดรายการเอฟเฟกต์', 'Load effects list');
  String get elNormalize => pick('อ่านตัวเลขและคำย่อเป็นคำพูด', 'Read numbers & abbreviations aloud');
  String get elNormAuto => pick('อัตโนมัติ', 'Auto');
  String get elNormOn => pick('เปิด', 'On');
  String get elNormOff => pick('ปิด', 'Off');
  String get elSeed => pick('ล็อกผลให้ออกมาเหมือนเดิม (seed)', 'Lock the result (seed)');
  String get elSeedHint => pick(
        'เปิด = ประโยคเดิมได้เสียงใกล้เคียงเดิมทุกครั้ง · ปิด = สุ่มใหม่ทุกครั้ง',
        'On = the same line sounds about the same every time · off = fresh each time',
      );
  String get elResetTuning => pick('คืนค่าตั้งต้นของ ElevenLabs', 'Back to ElevenLabs defaults');
  String get elTest => pick('ลองฟัง', 'Listen');

  // ═══ ElevenLabs: บัญชี ═══════════════════════════════════════
  String get elAccount => pick('บัญชี ElevenLabs', 'ElevenLabs account');
  String get elAccountLoad => pick('ดูแผนและเครดิตที่เหลือ', 'Check plan and credits');
  String elAccountLine(String tier, int left, int limit) => pick(
        'แผน $tier · เครดิตเหลือ $left จาก $limit',
        '$tier plan · $left of $limit credits left',
      );
  String elVoiceSlots(int used, int limit) => pick(
        'ช่องเก็บเสียง $used/$limit',
        'Voice slots $used/$limit',
      );

  // ═══ ElevenLabs: โคลนเสียงเจ้าของ ═════════════════════════════
  String get elCloneTitle => pick('โคลนเสียงของคุณ', 'Clone your voice');
  String get elCloneWhat => pick(
        'อัดเสียงตัวเองราว 1–2 นาที ElevenLabs จะสร้างเสียงเหมือนคุณ แล้วตั้งให้เธอใช้ตอนคุยหรือตอนรับสายได้',
        'Record yourself for about 1–2 minutes; ElevenLabs builds a voice like yours that she can use in chat or on calls',
      );
  String get elClonePlan => pick(
        'ต้องเป็นแผน Starter ขึ้นไป (แผนฟรีโคลนไม่ได้) · โคลนแบบทันที (Instant Voice Clone) เสร็จในไม่กี่วินาที',
        'Needs the Starter plan or above (free plan cannot clone) · Instant Voice Clone, ready in seconds',
      );
  String get elCloneNoPlan => pick(
        'แผนนี้ยังโคลนเสียงไม่ได้ — อัปเกรดเป็น Starter ขึ้นไปที่ elevenlabs.io',
        'This plan cannot clone yet — upgrade to Starter or above at elevenlabs.io',
      );
  String get elCloneConsent => pick(
        'ฉันยืนยันว่าเป็นเสียงของฉันเอง และยินยอมให้ใช้สร้างเสียงสังเคราะห์',
        'I confirm this is my own voice and I consent to it being used to make a synthetic voice',
      );
  String get elCloneRead => pick('อ่านบทนี้ช้า ๆ ชัด ๆ ในที่เงียบ', 'Read this slowly and clearly somewhere quiet');
  String get elCloneRecord => pick('เริ่มอัด', 'Start recording');
  String get elCloneStop => pick('หยุดอัด', 'Stop');
  String elCloneTake(int n, int secs) => pick('ไฟล์ที่ $n · $secs วินาที', 'Take $n · ${secs}s');
  String elCloneTotal(int secs) => pick(
        'รวม $secs วินาที · แนะนำ 60–120 วินาที',
        'Total ${secs}s · 60–120s recommended',
      );
  String get elCloneName => pick('ตั้งชื่อเสียง', 'Name the voice');
  String get elCloneNameDefault => pick('เสียงของฉัน', 'My voice');
  String get elCloneNoise => pick('ลบเสียงรบกวนในไฟล์ก่อนโคลน', 'Remove background noise first');
  String get elCloneGo => pick('สร้างเสียงโคลน', 'Create the clone');
  String get elCloneBusy => pick('กำลังโคลน…', 'Cloning…');
  String get elCloneDone => pick('โคลนเสร็จแล้ว — เลือกใช้ได้เลย', 'Clone ready — pick where to use it');
  String get elCloneUseChat => pick('ใช้ตอนคุยในแอป', 'Use in chat');
  String get elCloneUseAnswer => pick('ใช้ตอนรับสาย', 'Use on calls');
  String get elCloneTooShort => pick(
        'เสียงยังสั้นไป — อัดรวมอย่างน้อย 20 วินาที',
        'Too short — record at least 20 seconds in total',
      );
  String get elCloneNoMic => pick('แอปยังไม่ได้สิทธิ์ใช้ไมค์', 'The app has no microphone permission');
  String get elCloneMine => pick('เสียงโคลนในบัญชี', 'Cloned voices in your account');
  String get elCloneDelete => pick('ลบเสียงนี้', 'Delete this voice');
  String elCloneDeleteAsk(String name) => pick(
        'ลบเสียง "$name" ออกจากบัญชี ElevenLabs ถาวร?',
        'Permanently delete "$name" from your ElevenLabs account?',
      );
  String get elCloneDeleted => pick('ลบเสียงแล้ว', 'Voice deleted');
  String get elCloneRedo => pick('เริ่มใหม่', 'Start over');
  String get elCloneScript => pick(
        'สวัสดีค่ะ ตอนนี้กำลังอัดเสียงเพื่อใช้เป็นเสียงของผู้ช่วยส่วนตัว\n'
            'วันนี้อากาศดีมาก ท้องฟ้าแจ่มใส ไม่มีเมฆเลยสักก้อน\n'
            'ช่วงบ่ายมีนัดประชุมกับลูกค้าเรื่องใบเสนอราคา ถ้าใครโทรมาช่วยจดเรื่องไว้ให้ด้วยนะ\n'
            'หนึ่ง สอง สาม สี่ ห้า หก เจ็ด แปด เก้า สิบ\n'
            'ไก่ ไข่ ขวด ควาย ระฆัง งู จาน ฉิ่ง ช้าง โซ่\n'
            'ขอบคุณมาก แล้วเจอกันใหม่พรุ่งนี้เช้านะ',
        'Hi, I am recording my voice so my personal assistant can speak like me.\n'
            'The weather is lovely today, not a single cloud in the sky.\n'
            'This afternoon I have a meeting with a client about a quote; if anyone calls, please take a message.\n'
            'One, two, three, four, five, six, seven, eight, nine, ten.\n'
            'Thank you so much, and see you again tomorrow morning.',
      );

  // ═══ ตัวละครในสาย ═══════════════════════════════════════════
  String characterGreeting(String name, String role, {required bool male}) {
    final end = male ? 'ครับ' : 'ค่ะ';
    final end2 = male ? 'ครับ' : 'คะ';
    final r = role.trim().isEmpty ? 'เลขา' : role.trim();
    final rEn = role.trim().isEmpty ? 'the secretary' : role.trim();
    return pick(
      'สวัสดี$end $name$end $rของเจ้าของเบอร์นี้ '
          'ตอนนี้เขาไม่สะดวกรับสาย มีอะไรคุยหรือฝากเรื่องไว้กับ$nameได้เลยนะ$end2',
      "Hi, this is $name, $rEn for this number. "
          "They can't take the call right now — you can talk to me or leave a message.",
    );
  }

  String get chCard => pick('ตัวละครในสาย (โปรไฟล์บุคลิก)', 'Call characters (personas)');
  String get chWhat => pick(
        'ใครเป็นคนพูดกับปลายสาย — ตั้งชื่อ เพศ บทบาท นิสัยได้ สร้างได้หลายตัว แล้วเลือกว่าจะใช้ตัวไหนตอนรับสายหรือโทรออก',
        'Who talks to callers — set a name, gender, role and personality; make several, then pick one for answering and one for calling out',
      );
  String get chNow => pick('ตอนนี้ในสาย', 'On calls right now');
  String get chNowAnswer => pick('รับสาย', 'Answering');
  String get chNowOutgoing => pick('โทรออก', 'Calling out');
  String chBecauseVoice(String engine) => pick(
        'เพราะเสียง $engine ผูกกับตัวนี้',
        'because the $engine voice is linked to this one',
      );
  String get chBecausePicked => pick('ตามที่เลือกไว้', 'as picked');
  String get chLive => pick('คุยสด (เสียง OpenAI)', 'Live talk (OpenAI voice)');
  String get chList => pick('ตัวละครทั้งหมด', 'All characters');
  String get chAdd => pick('เพิ่มตัวละคร', 'Add a character');
  String get chEdit => pick('แก้ไข', 'Edit');
  String get chDelete => pick('ลบ', 'Delete');
  String chDeleteAsk(String name) => pick('ลบตัวละคร "$name"?', 'Delete "$name"?');
  String get chBuiltIn => pick('ตัวตั้งต้น', 'Default');
  String get chUseAnswer => pick('ใช้รับสาย', 'Use for answering');
  String get chUseOutgoing => pick('ใช้โทรออก', 'Use for calling out');
  String get chFemale => pick('ผู้หญิง', 'Female');
  String get chMale => pick('ผู้ชาย', 'Male');
  String get chName => pick('ชื่อที่ใช้แนะนำตัว', 'Name she/he gives');
  String get chGender => pick('เพศ (กำหนดคำลงท้าย ค่ะ/ครับ)', 'Gender (sets polite endings in Thai)');
  String get chRole => pick('บทบาท', 'Role');
  String get chRoleHint => pick('เช่น เลขา · ผู้ช่วย · พนักงานต้อนรับ', 'e.g. secretary · assistant · receptionist');
  String get chTraits => pick('นิสัยและวิธีพูด', 'Personality and manner');
  String get chTraitsHint => pick(
        'เช่น สุภาพ ใจเย็น พูดสั้น ชัดเจน ไม่เล่นมุก',
        'e.g. polite, calm, short and clear, no jokes',
      );
  String get chTraitsQuick => pick('เลือกเร็ว', 'Quick picks');
  List<String> get chTraitPresets => isThai
      ? const ['สุภาพ มืออาชีพ', 'อบอุ่น เป็นกันเอง', 'สดใส ขี้เล่น', 'ใจเย็น พูดช้า ชัดเจน', 'พูดสั้น ตรงประเด็น', 'มีอารมณ์ขันนิด ๆ']
      : const ['Polite, professional', 'Warm, friendly', 'Bright, playful', 'Calm, slow and clear', 'Short and to the point', 'A little humour'];
  String get chGreeting => pick('คำทักตอนรับสาย (ไม่ใส่ = แต่งให้จากชื่อ)', 'Greeting when answering (blank = made from the name)');
  String get chSave => pick('บันทึกตัวละคร', 'Save character');
  String get chNameNeeded => pick('ใส่ชื่อก่อนนะ', 'Enter a name first');
  String get chBindTitle => pick('ผูกกับโมเดลเสียง', 'Link to a voice model');
  String get chBindWhat => pick(
        'ถ้าเสียงตอนรับสายเป็นเจ้านี้ ให้ใช้ตัวละครนี้อัตโนมัติ — เช่น OpenAI ใช้ตัว A · ElevenLabs ใช้ตัว B',
        'When the call voice is from this provider, use this character automatically — e.g. OpenAI → A · ElevenLabs → B',
      );
  String get chBindNone => pick('ไม่ผูก (ใช้ตามที่เลือกข้างบน)', 'Not linked (use the pick above)');
  String get chBindTip => pick(
        'เสียงผู้ชายต้องเลือกเองในกรอบโมเดลสังเคราะห์เสียง (หมวดสมองและเสียง › ช่องรับสาย)',
        'Pick a male-sounding voice yourself in the voice synthesis box (Brain & voice › Answer tab)',
      );
}
