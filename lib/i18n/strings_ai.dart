import 'strings.dart';

/// ข้อความฝั่ง AI — สมอง, แรม, บุคลิก, ข้อผิดพลาด
///
/// แยกไฟล์เพราะสองกลุ่มนี้เปลี่ยนคนละจังหวะกัน: ข้อความ UI เปลี่ยนตอนแก้หน้าจอ
/// ส่วนข้อความพวกนี้เปลี่ยนตอนแก้ตรรกะของโมเดล เอาไว้ไฟล์เดียวกันแล้วจะชนกันบ่อย
extension AiStrings on S {
  // ═══ ผู้ให้บริการสมอง ══════════════════════════════════
  String get brainProxy => pick('ผ่านบริการของเรา', 'Through our service');
  String get brainProxySummary => pick(
        'ใช้ได้เลย ไม่ต้องมีคีย์ของตัวเอง',
        'Works right away — no key of your own needed',
      );
  String get brainProxyTradeoff => pick(
        'ข้อความถูกส่งผ่านเซิร์ฟเวอร์ของเรา · ต้องมีเน็ต · มีโควตาต่อวัน',
        'Messages pass through our server · needs internet · has a daily quota',
      );

  // ── พิมพ์ชื่อรุ่นเอง ──
  String get modelCustom => pick('พิมพ์ชื่อรุ่นเอง', 'Type a model name');
  String get modelCustomHint => pick(
        'ใช้รุ่นที่ไม่มีในรายการได้',
        'Use a model that is not in the list',
      );
  String get modelCustomEditor => pick(
        'ใส่ชื่อรุ่นให้ตรงกับที่ผู้ให้บริการใช้ เช่น gpt-5.6-sol\n'
        'พิมพ์ผิดจะเรียกไม่ได้ และจะรู้ตอนทักเธอครั้งถัดไป',
        'Type the model id exactly as the provider spells it, e.g. gpt-5.6-sol\n'
        'A typo will simply fail, and you will find out on your next message',
      );
  String get voiceModelCustomEditor => pick(
        'ใส่ชื่อรุ่นเสียงให้ตรงกับที่ผู้ให้บริการใช้ เช่น gpt-4o-mini-tts\n'
        'ถ้ารุ่นนั้นไม่รับคำสั่งน้ำเสียง ช่องน้ำเสียงจะหายไปเอง',
        'Type the voice model id as the provider spells it, e.g. gpt-4o-mini-tts\n'
        'If it does not accept tone instructions, that field disappears on its own',
      );
  String get voiceNameCustomEditor => pick(
        'ใส่ชื่อเสียงให้ตรงกับที่ผู้ให้บริการใช้ เช่น coral',
        'Type the voice name as the provider spells it, e.g. coral',
      );

  // ── รหัสสิทธิ์ (license) ──
  //
  // ตัวเดียวกับที่ร้านใช้ยืนยันว่าซื้ออะไรไปแล้ว · เดิมไม่มีช่องกรอกเลย
  // แปลว่า /api/packs/mine ไม่เคยใช้ได้จริงสักครั้ง และพร็อกซีก็จะใช้ไม่ได้ด้วย
  String get licenseTitle => pick('รหัสสิทธิ์', 'License code');
  String get licenseNotSet => pick('ยังไม่ได้ใส่รหัส', 'No code entered');
  String get licenseHint => pick(
        'รหัสที่ได้ตอนซื้อ ใช้ยืนยันว่าเครื่องนี้เป็นของคุณ\n'
        'ใช้ทั้งกับบริการสมองของเรา และกับของที่ซื้อในร้าน',
        'The code you got when you bought it, proving this phone is yours\n'
        'Used both for our assistant service and for what you own in the shop',
      );
  String get licenseNeeded => pick(
        'ยังไม่ได้รหัสสิทธิ์ของเครื่องนี้ — แอปจะขอให้เองเมื่อต่อเน็ต ลองเปิดแอปใหม่อีกครั้ง',
        "This phone has no licence yet — the app requests one by itself when "
            "it's online. Try reopening the app.",
      );
  String get licenseLinkAccount => pick(
        'ซื้อชุดบนเว็บแล้วไม่เห็น? ผูกเครื่องนี้กับบัญชีเว็บ',
        'Bought something on the web? Link this phone to your account',
      );
  String get licenseLinkCopied => pick(
        'คัดลอกรหัสของเครื่องนี้แล้ว — วางในช่องบนหน้าเว็บที่เปิดขึ้นมา',
        "This phone's code is copied — paste it into the box on the page that opened",
      );
  String get proxyModelNote => pick(
        'ถ้าบริการยังไม่เปิดรุ่นที่เลือกไว้ จะใช้รุ่นที่เราตั้งไว้ให้แทน',
        'If the service does not offer the model you picked, ours is used instead',
      );

  // ── คีย์ของผู้ใช้เอง ──
  String get ownKeyTitle => pick('คีย์ของคุณเอง', 'Your own key');
  String get ownKeyHint => pick(
        'วางคีย์ที่ขึ้นต้นด้วย sk- จาก platform.openai.com\n'
        'เก็บไว้ในเครื่องนี้เท่านั้น เข้ารหัสด้วย Keystore ของ Android',
        'Paste a key starting with sk- from platform.openai.com\n'
        'Kept on this phone only, encrypted by the Android Keystore',
      );
  String get ownKeyNotSet => pick('ยังไม่ได้ใส่คีย์', 'No key set');
  String get ownKeyClear => pick('ลบคีย์', 'Remove key');
  String get ownKeySaved => pick('เก็บคีย์แล้ว', 'Key saved');
  String get ownKeyRemoved => pick('ลบคีย์แล้ว', 'Key removed');
  String get ownKeyLooksWrong => pick(
        'คีย์ของ OpenAI ขึ้นต้นด้วย sk- — ตรวจอีกทีนะคะ',
        'OpenAI keys start with sk- — please check it again',
      );
  String get voiceNeedsKey => pick(
        'เสียงของ OpenAI ต้องมีคีย์ ยังไม่ใส่จะได้เสียงของเครื่องแทน',
        'The OpenAI voice needs a key — without one you get the device voice',
      );
  String get ownKeyNeeded => pick(
        'เลือก "คีย์ของคุณเอง" แล้วแต่ยังไม่ได้ใส่คีย์',
        'You picked your own key but have not entered one yet',
      );

  String get brainOpenAi => pick('คีย์ของคุณเอง', 'Your own key');
  String get brainOpenAiSummary => pick(
        'ต่อ OpenAI ตรงด้วยคีย์ที่คุณกรอกเอง',
        'Straight to OpenAI with a key you enter yourself',
      );
  String get brainOpenAiTradeoff => pick(
        'ฉลาดที่สุด · ไม่มีโควตาจำกัด · แต่ค่าใช้จ่ายเข้าบัญชีของคุณเอง',
        'The smartest · no quota · but the bill lands on your own account',
      );

  String get brainHome => pick('เซิร์ฟเวอร์ในบ้าน', 'Home server');
  String get brainHomeSummary => pick(
        'Ollama / LM Studio / llama.cpp บนคอมที่บ้าน',
        'Ollama / LM Studio / llama.cpp on your own PC',
      );
  String get brainHomeTradeoff => pick(
        'ข้อมูลไม่ออกนอกบ้าน · ฟรี · แต่ต้องอยู่วงไวไฟเดียวกับคอม และคอมต้องเปิด',
        'Nothing leaves your home · free · but you must be on the same wifi and the PC must be on',
      );

  String get brainOnDevice => pick('ในเครื่อง', 'On this phone');
  String get brainOnDeviceSummary =>
      pick('Gemma 4 รันบนมือถือเลย', 'Gemma 4 running on the phone itself');
  String get brainOnDeviceTradeoff => pick(
        'ออฟไลน์จริง ไม่ต้องมีเน็ตเลย · ฟรี · แต่ต้องโหลดโมเดล 2–3 GB และตอบช้ากว่า',
        'Truly offline, no internet at all · free · but a 2–3 GB download and slower replies',
      );

  String get homeServerAddress => pick('ที่อยู่เซิร์ฟเวอร์', 'Server address');
  String get homeServerModel => pick('ชื่อโมเดลบนเซิร์ฟเวอร์', 'Model name on the server');
  String get homeServerHint => pick(
        'ใส่ IP ของคอมที่รัน Ollama เช่น http://192.168.1.100:11434/v1\n'
            'บนคอมต้องตั้ง OLLAMA_HOST=0.0.0.0 ก่อน ไม่งั้นมันรับเฉพาะ localhost',
        'Enter the IP of the PC running Ollama, e.g. http://192.168.1.100:11434/v1\n'
            'Set OLLAMA_HOST=0.0.0.0 on that PC first, or it only listens on localhost',
      );
  String get homeServerModelHint => pick(
        'ชื่อที่เซิร์ฟเวอร์รู้จัก เช่น gemma4:latest ดูรายชื่อได้ด้วยคำสั่ง ollama list บนคอม',
        'The name the server knows it by, e.g. gemma4:latest — run `ollama list` on the PC to see them',
      );

  // ═══ โมเดลของ OpenAI ═══════════════════════════════════
  String get modelSolHint => pick('ฉลาดที่สุดของรุ่น 5.6 ตอบไว · ค่าเริ่มต้น',
      'Smartest of 5.6 and quick to answer · default');
  String get modelSol61Hint => pick('รุ่นใหม่ล่าสุด คิดละเอียดกว่า แต่ตอบช้ากว่าเล็กน้อย',
      'Newest, more careful, a little slower to answer');
  String get modelTerraHint =>
      pick('ระดับกลาง ราคาราวครึ่งของ Sol', 'Mid tier, about half the price of Sol');
  String get modelLunaHint => pick('เร็วและถูกที่สุด', 'Fastest and cheapest');
  String get modelAstraHint => pick('ตัวท็อปของ OpenAI แพงที่สุด ตอบช้าที่สุด',
      "OpenAI's top model — most expensive and slowest");
  String get modelTypedHint => pick('รุ่นที่พิมพ์เอง', 'A model you typed in');

  String get ttsSteerable =>
      pick('สั่งอารมณ์เสียงได้ · สมจริงที่สุด', 'Tone can be steered · most lifelike');
  String get ttsSharper =>
      pick('คมกว่า แต่สั่งอารมณ์ไม่ได้', 'Sharper, but tone cannot be steered');
  String get ttsCheapest => pick(
      'เร็วและถูกที่สุด · สั่งอารมณ์ไม่ได้', 'Fastest and cheapest · no tone control');


  // ═══ เสียงของ OpenAI ═══════════════════════════════════
  String get voiceCoral => pick('Coral — นุ่ม อบอุ่น', 'Coral — soft and warm');
  String get voiceShimmer => pick('Shimmer — ใส ฟังชัด', 'Shimmer — bright and clear');
  String get voiceSage => pick('Sage — สุขุม เป็นทางการ', 'Sage — composed and formal');
  String get voiceNova => pick('Nova — สดใส กระฉับกระเฉง', 'Nova — bright and brisk');
  String get voiceBallad => pick('Ballad — ช้า อ่อนโยน', 'Ballad — slow and gentle');
  String get voiceMarin =>
      pick('Marin — เป็นธรรมชาติที่สุด (OpenAI แนะนำ)', 'Marin — most natural (recommended by OpenAI)');
  String get voiceCedar =>
      pick('Cedar — เป็นธรรมชาติ โทนทุ้ม (OpenAI แนะนำ)', 'Cedar — natural, deeper tone (recommended by OpenAI)');

  // ═══ Gemma ในเครื่อง ═══════════════════════════════════
  String get gemmaVariant => pick('รุ่นที่ใช้', 'Model variant');

  /// ป้ายบอกว่ารุ่นนี้อยู่ในเครื่องแล้ว กดใช้ได้เลย ไม่ต้องโหลดซ้ำ
  String get gemmaInstalledTag => pick('โหลดแล้ว', 'Installed');

  /// เครื่องเล็กเกินจะรันโมเดลในเครื่องได้เลยสักรุ่น
  String gemmaDeviceTooSmall(String has, String need) => pick(
        'เครื่องนี้แรม $has GB ซึ่งไม่พอสำหรับโมเดลในเครื่อง (ต้องการอย่างน้อย $need GB)\n'
        'ใช้ "ผ่านบริการของเรา" หรือ "คีย์ของคุณเอง" แทนได้นะคะ',
        'This phone has $has GB of RAM, not enough for an on-device model '
        '(at least $need GB needed)\n'
        'You can use "Through our service" or "Your own key" instead',
      );
  String get gemmaE2bCpuHint => pick('เร็วกว่า ใช้ได้ทุกเครื่อง · แนะนำ',
      'Faster, works on any phone · recommended');
  String get gemmaE4bHint => pick('ฉลาดกว่า แต่ช้ากว่าและกินพื้นที่มากกว่า',
      'Smarter, but slower and needs more storage');

  String gemmaDownload(String size) =>
      pick('โหลดโมเดลลงเครื่อง · $size', 'Download to this phone · $size');
  String get gemmaReady => pick(
      'โหลดลงเครื่องแล้ว พร้อมใช้แบบออฟไลน์', 'Downloaded — ready to use offline');
  String get gemmaRemove => pick('ลบออก', 'Remove');
  /// หัวก้อน "สิ่งที่รู้แล้ว" ที่ส่งไปพร้อมรอบสกัดความจำ
  String get distillKnown => pick(
        'สิ่งที่รู้อยู่แล้ว (ห้ามตอบซ้ำ แม้จะเขียนต่างกัน):',
        'Already known (do not repeat these, even reworded):',
      );

  String get errKeyNotSaved => pick(
        'บันทึกคีย์ลงที่เก็บที่ปลอดภัยของเครื่องไม่ได้ — ใช้ได้รอบนี้ แต่ปิดแอปแล้วต้องใส่ใหม่',
        "Couldn't store the key in the phone's secure storage — it works for now, "
            'but you will need to enter it again after closing the app.',
      );
  String gemmaRemoveConfirm(String size) => pick(
        'ลบโมเดลออกจากเครื่อง? ถ้าจะใช้อีกต้องโหลดใหม่ $size',
        'Remove the model from this phone? Using it again means '
            'downloading $size again.',
      );
  String get gemmaRetry => pick('ลองโหลดอีกครั้ง', 'Try the download again');

  String get gemmaUseGpu => pick('คิดด้วย GPU ของเครื่อง', "Think on the phone's GPU");
  String get gemmaUseGpuWhy => pick(
        'อ่านข้อความเร็วกว่า CPU หลายเท่า และกินแรมน้อยกว่า · '
            'ครั้งแรกที่เปิดอาจรอนานหน่อย เครื่องกำลังเตรียม GPU',
        'Reads your messages several times faster than the CPU and uses '
            'less memory. The very first start can take a little longer.',
      );
  String get gemmaOnGpu => pick('ตอนนี้คิดด้วย GPU', 'Thinking on the GPU now');
  String get gemmaOnCpu => pick('ตอนนี้คิดด้วย CPU', 'Thinking on the CPU now');
  String get gemmaGpuBroken => pick(
        'GPU ของเครื่องนี้ใช้ไม่ได้ เลยคิดด้วย CPU แทน · แตะสวิตช์เพื่อลองอีกครั้ง',
        "This phone's GPU didn't work, so she thinks on the CPU. "
            'Tap the switch to try again.',
      );
  String get gemmaKeepOpen => pick(
        'ใช้ไวไฟและอย่าปิดแอประหว่างโหลด',
        'Use wifi and keep the app open while it downloads',
      );
  String gemmaSpeed(String mbps) => pick('$mbps MB/วิ', '$mbps MB/s');
  String gemmaEtaSeconds(int s) => pick('เหลืออีก ~$s วิ', '~${s}s left');
  String gemmaEtaMinutes(int m) => pick('เหลืออีก ~$m นาที', '~${m}m left');

  // ═══ ผลตรวจแรม ═════════════════════════════════════════
  String get ramUnknown => pick('อ่านแรมเครื่องไม่ได้', 'Could not read this phone\'s memory');
  String get ramUnknownDetail => pick(
        'เลือกรุ่นเองได้ แต่ถ้าเครื่องแรมน้อยกว่า 6 GB '
            'แนะนำให้ใช้ OpenAI หรือเซิร์ฟเวอร์ในบ้านแทน',
        'You can still pick a variant, but under 6 GB of memory '
            'OpenAI or a home server is the better choice.',
      );

  String get ramTooSmall =>
      pick('เครื่องนี้แรมไม่พอสำหรับสมองในเครื่อง', 'Not enough memory to run a brain here');
  String ramTooSmallDetail(String gb) => pick(
        'ระบบรายงานแรม $gb GB ซึ่งไม่พอจะแบกทั้งอวาตาร์ 3D และโมเดลภาษาพร้อมกัน\n'
            'แนะนำให้ใช้ OpenAI หรือเซิร์ฟเวอร์ในบ้านแทน '
            'จะได้ไม่เสียเน็ตโหลด 2 GB ฟรี ๆ แล้วแอปเด้งกลางทาง',
        'The system reports $gb GB, not enough to hold the 3D avatar and a language model at once.\n'
            'Use OpenAI or a home server instead, rather than spending 2 GB of data '
            'on a download that will crash the app anyway.',
      );

  // ═══ หน้ากั้นตอนเปิดแอปบนเครื่องที่สเปคไม่ถึง ═══════════
  //
  // ต่างจาก ramTooSmall* ข้างบนโดยตั้งใจ: ชุดนั้นอยู่ในหน้าตั้งค่าและ**แนะนำ
  // ทางเลือกอื่น** ส่วนชุดนี้เป็นกำแพงตอนเปิดแอป ต้องบอกข้อเท็จจริงตรง ๆ
  String get ramBlockedTitle =>
      pick('เครื่องนี้สเปคไม่ถึง', 'This phone is below spec');
  String ramBlockedDetail(String gb, String need) => pick(
        'ระบบรายงานแรม $gb GB แต่ต้องมีอย่างน้อย $need GB\n'
            'เธอต้องแบกทั้งอวาตาร์ 3D และโมเดลภาษาไว้ในแรมพร้อมกัน '
            'เครื่องนี้จะถูกระบบฆ่าทิ้งกลางบทสนทนา หลังเสียเน็ตโหลดโมเดลไป 2 GB แล้ว',
        'The system reports $gb GB, but at least $need GB is needed.\n'
            'She has to hold the 3D avatar and a language model in memory at once. '
            'This phone would be killed mid-conversation, after spending 2 GB of data on the model.',
      );
  String get ramBlockedHint => pick(
        'เข้าไปได้อยู่ แต่เธอจะคุยได้ต่อเมื่อไปตั้งเซิร์ฟเวอร์ในบ้านในหน้าตั้งค่าก่อน',
        'You can still go in, but she can only talk once you set up a home server in Settings.',
      );
  String get ramBlockedAnyway =>
      pick('เข้าใช้ต่อทั้งที่รู้', 'Continue anyway');

  String get ramTight => pick('ไหว แต่ตึงมือ', 'Workable, but tight');
  String ramTightDetail(String gb) => pick(
        'ระบบรายงานแรม $gb GB ใช้ E2B แบบ GPU ได้ (ไฟล์เล็กที่สุด 2.0 GB)\n'
            'ปิดแอปอื่นก่อนคุยจะลื่นกว่า และอาจสะดุดบ้างตอนอวาตาร์ขยับพร้อมกัน',
        'The system reports $gb GB. E2B on GPU will run (smallest file, 2.0 GB).\n'
            'Close other apps first for smoother replies — it may stutter while the avatar moves.',
      );

  String get ramComfortable => pick('ไหวสบาย', 'Comfortable');
  String ramComfortableDetail(String gb) => pick(
        'ระบบรายงานแรม $gb GB ใช้ E2B ได้ทั้งแบบ GPU และ CPU\n'
            'E4B ยังไม่แนะนำสำหรับเครื่องนี้ เพราะต้องแบกอวาตาร์ 3D ไปพร้อมกัน',
        'The system reports $gb GB. Both E2B GPU and CPU will run.\n'
            'E4B is not recommended here — the 3D avatar has to fit alongside it.',
      );

  String get ramRoomy => pick('เครื่องแรง ใช้รุ่นใหญ่ได้', 'Plenty of room for the big model');
  String ramRoomyDetail(String gb) => pick(
        'ระบบรายงานแรม $gb GB ใช้ E4B ได้ ซึ่งฉลาดกว่า E2B ชัดเจน\n'
            'ถ้าอยากให้ตอบไวกว่าโดยยอมลดความฉลาดลงหน่อย เลือก E2B แทนได้',
        'The system reports $gb GB. E4B will run, and it is clearly smarter than E2B.\n'
            'Pick E2B instead if you would rather trade some of that for speed.',
      );

  // ═══ ข้อผิดพลาดที่ผู้ใช้เห็น ═══════════════════════════
  String get errNoKey =>
      pick('ยังไม่ได้ใส่คีย์ OpenAI ตอน build', 'No OpenAI key was built into this app');
  String get errNoReply => pick('โมเดลไม่ได้ตอบอะไรกลับมา', 'The model returned nothing');
  String get errEmptyReply => pick('โมเดลตอบกลับมาว่าง', 'The model returned an empty reply');
  String get errNothingToSay => pick('ไม่มีข้อความให้พูด', 'Nothing to say');
  String get errOffline =>
      pick('ต่อเน็ตไม่ได้ ลองใหม่อีกครั้งนะคะ', 'Cannot reach the internet — please try again');
  String get errBadKey => pick('คีย์ OpenAI ใช้ไม่ได้แล้ว', 'That OpenAI key no longer works');
  String get errRateLimited =>
      pick('เรียกถี่เกินไป รอสักครู่นะคะ', 'Too many requests — give it a moment');
  String get errUpstream =>
      pick('ฝั่ง OpenAI ขัดข้อง ลองใหม่อีกครั้งนะคะ', 'OpenAI is having trouble — try again');
  String errRequestFailed(int code) =>
      pick('เรียก OpenAI ไม่สำเร็จ ($code)', 'OpenAI request failed ($code)');

  // ── ข้อความของทางพร็อกซี / เซิร์ฟเวอร์ในบ้าน ──
  //
  // 🔴 คนที่เลือกสองทางนี้ถูกบอกว่า "ไม่ต้องมีคีย์ OpenAI" · ข้อความที่พูดถึง
  // คีย์ OpenAI พาเขาไปไล่หาของที่ไม่มีอยู่
  String get errLicenseRejected => pick(
        'รหัสสิทธิ์ใช้ไม่ได้หรือหมดอายุ — เช็คในหน้าตั้งค่า',
        'The licence key was not accepted or has expired — check it in Settings',
      );
  String get errProxyDown => pick(
        'ระบบหลังบ้านขัดข้อง ลองใหม่อีกครั้งนะคะ',
        'The service is having trouble — try again',
      );
  String errProxyFailed(int code) => pick(
        'ระบบหลังบ้านตอบไม่สำเร็จ ($code)',
        'The service request failed ($code)',
      );
  String get errHomeDown => pick(
        'เซิร์ฟเวอร์ในบ้านขัดข้อง — เช็คว่าโปรแกรมบนเครื่องนั้นยังเปิดอยู่',
        'The home server is having trouble — check the program on it is still running',
      );
  String errHomeFailed(int code) => pick(
        'เซิร์ฟเวอร์ในบ้านตอบไม่สำเร็จ ($code)',
        'The home server request failed ($code)',
      );
  String get errHomeNoStt => pick(
        'เซิร์ฟเวอร์ในบ้านถอดเสียงไม่ได้ (Ollama ไม่มีบริการนี้) — ใช้การพิมพ์แทนนะคะ',
        "The home server can't transcribe speech (Ollama has no such service) — "
            'type instead',
      );

  /// สมองล้มด้วยเหตุที่เราไม่ได้เตรียมข้อความไว้ให้
  ///
  /// ห้ามเอาข้อความดิบของ error มาโชว์แทน — ในนั้นมีทั้ง URL ปลายทาง
  /// ชื่อคลาสภายใน และบางครั้งมี header ติดมาด้วย · ผู้ใช้เอาไปทำอะไรไม่ได้
  /// สิ่งที่เขาทำได้จริงคือลองใหม่ ข้อความจึงพาไปตรงนั้น (ของเต็มอยู่ใน log)
  String get errBrainUnexpected => pick(
        'สมองของมายด์สะดุดกลางทาง ลองส่งใหม่อีกครั้งนะคะ',
        'Her train of thought broke off — please send that again',
      );

  /// ไฟล์โมเดลไม่ครบ — คนละเรื่องกับยังไม่ได้โหลด และแก้คนละแบบ
  ///
  /// ไฟล์ครึ่งเดียวยังนับว่า "ติดตั้งแล้ว" ในสายตาปลั๊กอิน (มันดูแค่ว่ามีไฟล์อยู่)
  /// ปุ่มโหลดจึงหายไปทั้งที่ของยังใช้ไม่ได้ · ผู้ใช้ต้องได้ยินสิ่งที่เขาทำได้จริง
  /// ไม่ใช่ข้อความจาก engine ที่แปลไม่ออก
  String get errModelIncomplete => pick(
        'ไฟล์โมเดลโหลดมาไม่ครบ (เน็ตหลุดกลางทาง) · ลบให้แล้ว กดโหลดใหม่ได้เลย',
        'The model file did not download completely — it has been removed, '
        'just download it again',
      );

  /// เสียงสังเคราะห์เสร็จแล้วแต่ไม่มีทางไหนเล่นได้เลย
  ///
  /// เงียบเฉย ๆ อ่านออกมาเป็น "เธอไม่ยอมพูดกับเรา" ซึ่งคนละเรื่องกับของจริง
  String get errVoiceNoOutput => pick(
        'เสียงของเธอออกลำโพงไม่ได้ · ปิดเสียงในหน้าตั้งค่าไว้ก่อนก็ได้ ข้อความยังอ่านได้ครบ',
        'Her voice could not reach the speaker — the text is still all here',
      );

  String get errModelNotDownloaded =>
      pick('ยังไม่ได้โหลดโมเดลลงเครื่อง', 'The model is not downloaded yet');

  /// กำลังโหลดอยู่ — คนละเรื่องกับยังไม่ได้โหลด
  ///
  /// บอกให้ไปโหลดของที่กำลังโหลดอยู่ 60% คือการบอกให้ทำสิ่งที่ทำอยู่แล้ว
  /// สิ่งที่เขาต้องรู้จริงคือ **รออีกเท่าไหร่** ไม่ใช่ต้องไปกดอะไรเพิ่ม
  String errModelDownloading(int pct) => pick(
        'กำลังโหลดสมองลงเครื่องอยู่ $pct% · รออีกสักครู่แล้วทักใหม่นะคะ',
        'Her brain is still downloading — $pct% · try again in a moment',
      );

  /// เครื่องนี้รันโมเดลในเครื่องไม่ไหวเลยสักรุ่น
  ///
  /// บอกให้ไปโหลดคือการให้เขาเสียเน็ตหลาย GB ไปกับของที่ระบบจะฆ่าทิ้งตอนรัน
  /// ทางออกจริงของเขาคือเปลี่ยนไปใช้สมองทางอื่น
  String get errDeviceTooSmallForLocal => pick(
        'เครื่องนี้แรมไม่พอจะรันสมองในเครื่อง · เลือกสมองทางอื่นในหน้าตั้งค่านะคะ',
        "This phone hasn't the memory to run her brain locally — pick another brain in settings",
      );
  String get errNothingToAnswer => pick('ไม่มีข้อความให้ตอบ', 'Nothing to reply to');

  // ═══ พูดใส่ไมค์แทนการพิมพ์ ═════════════════════════════
  //
  // 🔴 เสียงไปที่เดียวกับที่ข้อความไป · สมองในเครื่องจึงใช้ไมค์ไม่ได้
  // เพราะการถอดเสียงต้องมีบริการนอกเครื่อง ซึ่งขัดกับสัญญาข้อเดียว
  // ที่ทางนั้นให้ไว้ · บอกตรง ๆ ดีกว่าแอบส่งออกไปให้มันทำงาน

  /// เสียงถูกกันไม่ให้ออกนอกเครื่อง เพราะผู้ใช้เลือกสมองในเครื่องไว้
  ///
  /// 🔴 นี่คือ**ด่านกัน ไม่ใช่ข้อความบอกความล้มเหลว** · ทางปกติจะไม่มีวัน
  /// มาถึงตรงนี้ (ปุ่มไมค์ใช้ทางในเครื่องอยู่แล้ว — ดู device_speech.dart)
  /// ถ้าผู้ใช้เห็นข้อความนี้ แปลว่ามีทางใหม่ที่ลืมกัน ซึ่งต้องดังตอนนั้นเลย
  /// ไม่ใช่เงียบแล้วยิงเสียงเขาออกเน็ตไป
  String get micNeedsCloudBrain => pick(
        'เลือกสมองในเครื่องไว้ เสียงจึงไม่ถูกส่งออกนอกเครื่อง',
        'The on-device brain is selected, so audio never leaves this phone',
      );

  String get homeServerNoUrl => pick(
        'ยังไม่ได้ใส่ที่อยู่เซิร์ฟเวอร์ในบ้าน',
        'No address set for your home server',
      );

  String get micDenied => pick(
        'ยังไม่ได้อนุญาตให้ใช้ไมค์',
        'Microphone permission has not been given',
      );
  String get micFailed => pick(
        'เปิดไมค์ไม่สำเร็จ',
        'Could not open the microphone',
      );

  /// อัดแล้วแต่ไม่มีเสียงพูดอยู่ในนั้น
  ///
  /// **ไม่ใช่ความผิดพลาด** — คนกดค้างแล้วไม่ทันพูดก็เจอ · ห้ามพูดเหมือน
  /// ระบบพัง ไม่งั้นเขาจะไปไล่หาสาเหตุที่ไม่มีอยู่จริง
  String get micHeardNothing => pick(
        'ไม่ได้ยินเสียงพูดเลย ลองพูดใกล้ ๆ ไมค์อีกครั้งนะคะ',
        'Did not catch anything — try again a little closer to the mic',
      );

  /// เครื่องนี้ถอดเสียงในเครื่องไม่ได้ (แอนดรอยด์เก่ากว่า 12)
  ///
  /// 🔴 ห้ามแอบตกไปใช้ทางข้างนอกแทน · คนที่เลือกสมองในเครื่องเลือกเพราะ
  /// ไม่อยากให้อะไรออกนอกเครื่อง การส่งเสียงเขาออกไปเพราะ "ทางในเครื่อง
  /// ทำไม่ได้" คือการผิดสัญญาในจังหวะที่เขาไม่มีทางรู้เลย
  String get micNoOnDevice => pick(
        'เครื่องนี้ถอดเสียงในเครื่องไม่ได้ · พิมพ์แทนได้ '
        'หรือเปลี่ยนสมองเป็นทางที่ใช้เน็ตในหน้าตั้งค่า',
        'This phone cannot transcribe on-device — type instead, '
        'or switch to a brain that uses the internet in settings',
      );

  /// ยังไม่ได้โหลดชุดภาษาลงเครื่อง — พบบ่อยกว่าเครื่องเก่าเสียอีก
  /// และเป็นกรณีที่**ผู้ใช้แก้เองได้** จึงต้องบอกว่าไปแก้ที่ไหน
  // ── บันทึกสายที่รับแทน ──
  String callNoteTitle(String who) => pick(
        'มายด์รับสายแทน · ${who.isEmpty ? 'เบอร์ที่ไม่แสดง' : who}',
        'Mind took a call · ${who.isEmpty ? 'hidden number' : who}',
      );
  String get callNoteSilent => pick(
        'คู่สายไม่ได้พูดอะไร หรือวางสายไปก่อน',
        'The caller said nothing, or hung up first',
      );
  String callNoteFallback(String firstWords) => pick(
        'คู่สายบอกว่า: "$firstWords" (สรุปอัตโนมัติไม่สำเร็จ เปิดดูบทสนทนาเต็มได้)',
        'The caller said: "$firstWords" (couldn\'t summarise — open the full conversation)',
      );
  String get callNotesPromptHeader => pick(
        '=== ข้อความที่มายด์รับฝากไว้ทางโทรศัพท์ (บอกเจ้าของได้) ===',
        '=== Messages Mind took on the phone (tell the owner) ===',
      );
  String get callNoteUnseenTag =>
      pick('(เจ้าของยังไม่ได้อ่าน)', '(not read by the owner yet)');
  String get speakerCaller => pick('คู่สาย', 'Caller');
  String get callNoteSheetTitle => pick('บันทึกสาย', 'Call note');
  String get callNoteConversation => pick('บทสนทนาเต็ม', 'Full conversation');
  String get callNoteDelete => pick('ลบบันทึกนี้', 'Delete this note');
  String get callNoteDeleteConfirm => pick(
        'ลบบันทึกสายนี้ทั้งสรุปและบทสนทนา? ย้อนกลับไม่ได้',
        'Delete this call note and its conversation? This cannot be undone.',
      );

  String get callNoOnDeviceStt => pick(
        'เครื่องนี้ถอดเสียงคู่สายในเครื่องไม่ได้ (ต้อง Android 13 ขึ้นไป) — '
            'มายด์ยังพูดแทนได้ พิมพ์ข้อความให้เธอพูดเข้าสายได้เลย',
        "This phone can't transcribe the caller on-device (needs Android 13+) — "
            'she can still speak for you; type what she should say.',
      );

  String get micNoLanguagePack => pick(
        'ยังไม่ได้โหลดชุดภาษาสำหรับถอดเสียงในเครื่อง · '
        'โหลดได้ที่ตั้งค่าเครื่อง → ระบบ → ภาษาและการป้อนข้อมูล',
        'The offline speech language pack is not installed — '
        'get it from Settings → System → Languages & input',
      );

  String get micBusy => pick(
        'ตัวถอดเสียงของเครื่องกำลังถูกใช้อยู่ ลองใหม่อีกครั้งนะคะ',
        "The phone's recogniser is busy — try again in a moment",
      );

  String get micListening => pick('กำลังฟังอยู่…', 'Listening…');
  String get micWorking => pick('กำลังถอดเสียง…', 'Writing it down…');
  String get micStart => pick('พูดแทนการพิมพ์', 'Speak instead of typing');
  String get micStop => pick('หยุดฟัง', 'Stop listening');

  /// หัวข้อของบทสนทนาย้อนหลังที่แนบไปให้สมองในเครื่องอ่าน
  ///
  /// ผู้ใช้ไม่เห็นข้อความนี้ แต่ต้องตามภาษาที่เขาเลือก — โมเดลอ่าน prompt
  /// ที่ปนสองภาษาแล้วมีโอกาสตอบผิดภาษามากขึ้น
  String get localRecap => pick(
        'นี่คือบทสนทนาก่อนหน้าระหว่างเรา (อ่านเพื่อจำบริบท ไม่ต้องตอบซ้ำ):',
        'Here is our conversation so far — for context, not to answer again:',
      );
  String get errLocalEmpty =>
      pick('โมเดลในเครื่องตอบกลับมาว่าง', 'The on-device model returned nothing');

  String get errTtsFailed =>
      pick('เครื่องนี้สังเคราะห์เสียงไม่สำเร็จ', 'This phone could not synthesise speech');
  String get errTtsNoFile => pick('เครื่องนี้ไม่รองรับการบันทึกเสียงเป็นไฟล์',
      'This phone cannot write speech to a file');
  String get errTtsEmpty => pick(
        'เสียงของเครื่องไม่ได้อ่านอะไรออกมา · ลองเปลี่ยนเสียงในหน้าตั้งค่า › สมองและเสียง',
        "The phone's voice produced no speech — try another voice in Settings › Brain & voice",
      );
  String get errTtsNoVoice => pick(
        'เครื่องนี้ยังไม่มีเสียงภาษาไทย เธอจึงพูดไม่ออก · ไปที่ตั้งค่าเครื่อง › '
            'การจัดการทั่วไป/ภาษา › แปลงข้อความเป็นเสียง แล้วโหลดเสียงภาษาไทย',
        'This phone has no voice for this language installed, so she cannot speak — '
            'open phone Settings › Language › Text-to-speech and download the voice',
      );
  String get errMediaMuted => pick(
        'เสียงสื่อของเครื่องปิดอยู่ เลยไม่ได้ยินเธอ · กดปุ่มเพิ่มเสียงข้างเครื่อง',
        "The phone's media volume is at zero, so you can't hear her — press volume up",
      );

  // ═══ อัปเดต ════════════════════════════════════════════
  String updateCheckFailed(int code) =>
      pick('เช็ครุ่นใหม่ไม่ได้ ($code)', 'Could not check for updates ($code)');
  String get updateNoApk =>
      pick('release นี้ไม่มีไฟล์ APK แนบมา', 'That release has no APK attached');
  /// ห้ามเอ่ยชื่อบริการที่เราไปฝากไฟล์ไว้ — ผู้ใช้แก้อะไรจากข้อมูลนั้นไม่ได้
  /// สิ่งที่เขาทำได้จริงคือเช็คเน็ตตัวเอง ข้อความจึงควรพาไปตรงนั้น
  String get updateNoConnection => pick(
        'เช็ครุ่นใหม่ไม่ได้ตอนนี้ · ลองใหม่เมื่อเน็ตกลับมา',
        'Cannot check for updates right now · try again when you are back online',
      );
  String updateDownloadFailed(int code) =>
      pick('ดาวน์โหลดไม่สำเร็จ ($code)', 'Download failed ($code)');
  String updateNoHash(String asset) => pick(
        'release นี้ไม่มี $asset จึงตรวจไฟล์ไม่ได้ ยกเลิกเพื่อความปลอดภัย',
        'That release has no $asset so the file cannot be verified — cancelled for safety',
      );
  String get updateHashMismatch => pick(
        'ไฟล์ที่โหลดมาไม่ตรงกับที่ประกาศไว้ ยกเลิกแล้ว',
        'The downloaded file does not match what was published — cancelled',
      );
  String get updateInstallerBlocked => pick(
        'เปิดตัวติดตั้งไม่ได้ — ต้องอนุญาต "ติดตั้งแอปที่ไม่รู้จัก" ให้แอปนี้ก่อน',
        'Could not open the installer — allow "install unknown apps" for GigGok first',
      );
  String get updateRetry =>
      pick('ดาวน์โหลดไม่สำเร็จ ลองใหม่อีกครั้งนะคะ', 'Download failed — please try again');

  // ═══ เพิ่มเติมสำหรับ service ═══════════════════════════
  String get errCloneNotSet =>
      pick('ยังไม่ได้ตั้งเซิร์ฟเวอร์เสียงโคลน', 'No voice-clone server configured yet');
  String errCheckModel(String e) =>
      pick('เช็คโมเดลไม่ได้ — $e', 'Could not check the model — $e');
  String errDownloadModel(String e) =>
      pick('โหลดโมเดลไม่สำเร็จ — $e', 'Model download failed — $e');
  String errLocalFailed(String e) => pick(
      'โมเดลในเครื่องทำงานไม่สำเร็จ — $e', 'The on-device model failed — $e');
  String get errNeedMic =>
      pick('ต้องอนุญาตให้ใช้ไมโครโฟนก่อน', 'Microphone permission is needed first');
  String get errNoSample => pick('ยังไม่มีตัวอย่างเสียง', 'No voice sample recorded yet');
  String get errNoServer =>
      pick('ยังไม่ได้ตั้งที่อยู่เซิร์ฟเวอร์', 'No server address configured');
  String get errUploadFailed =>
      pick('ส่งตัวอย่างเสียงไม่สำเร็จ', 'Could not upload the voice sample');
  String get errServerEmptyAudio =>
      pick('เซิร์ฟเวอร์ส่งเสียงเปล่ากลับมา', 'The server returned empty audio');
  String get errCloneUnreachable =>
      pick('ต่อเซิร์ฟเวอร์เสียงโคลนไม่ได้', 'Cannot reach the voice-clone server');
  String get errNoPermission => pick(
      'ไม่มีสิทธิ์ใช้บริการนี้ ลองล็อกอินใหม่', 'Not allowed — try signing in again');
  String get errQuotaGone => pick('โควตาหมดแล้ว', 'Quota used up');
  String get errFileTooBig => pick('ไฟล์เสียงใหญ่เกินไป', 'That audio file is too large');
  String get errServerDown => pick(
      'เซิร์ฟเวอร์ขัดข้อง ลองใหม่อีกครั้งนะคะ', 'The server is having trouble — try again');

  // ═══ คำอธิบายที่หาจาก id ═══════════════════════════════
  String brainModelHint(String id) => switch (id) {
        'gpt-5.6-sol' => modelSolHint,
        'gpt-6.1-sol' => modelSol61Hint,
        'gpt-5.6-terra' => modelTerraHint,
        'gpt-6-luna' => modelLunaHint,
        'gpt-6-astra' => modelAstraHint,
        _ => modelTypedHint,
      };

  String voiceLabel(String id) => switch (id) {
        'coral' => voiceCoral,
        'shimmer' => voiceShimmer,
        'sage' => voiceSage,
        'nova' => voiceNova,
        'ballad' => voiceBallad,
        'marin' => voiceMarin,
        'cedar' => voiceCedar,
        _ => id,
      };

  String ttsModelHint(String id) => switch (id) {
        'gpt-4o-mini-tts' => ttsSteerable,
        'tts-1-hd' => ttsSharper,
        _ => ttsCheapest,
      };

}
