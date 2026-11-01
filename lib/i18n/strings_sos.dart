import 'strings.dart';

/// ข้อความของระบบแจ้งเหตุฉุกเฉิน (lib/sos/)
extension SosStrings on S {
  String get sosSection => pick('ฉุกเฉิน', 'Emergency');
  String get sosSectionHint => pick('แจ้งเหตุ ข้อมูลสำหรับเจ้าหน้าที่ ตำแหน่ง', 'Alerts, details for responders, location');

  String get sosWatchCard => pick('ระบบแจ้งเหตุ', 'Emergency alert');
  String get sosWatchOn => pick('เปิดระบบแจ้งเหตุ', 'Turn on emergency alert');
  String get sosWatchHint => pick(
        'มายด์จับแรงกระแทก เรียกคุณ และแจ้งเหตุเมื่อคุณไม่ตอบ',
        'Mind detects hard impacts, calls out to you, and alerts when you do not answer',
      );
  String get sosRunning => pick('กำลังเฝ้าอยู่', 'Watching');
  String get sosNotRunning => pick('ตั้งเปิดไว้ แต่ตัวเฝ้าไม่ได้ทำงาน · ระบบอาจปิดแอป', 'Switched on, but the watcher is not running · The system may have closed the app');
  String get sosManualButton => pick('ขอความช่วยเหลือตอนนี้', 'Get help now');
  String get sosTestButton => pick('ลองกดขอความช่วยเหลือ (ทดสอบ)', 'Try asking for help (test)');
  String get sosTestMode => pick('โหมดทดสอบ ยังไม่แจ้งจริง', 'Test mode, nobody is alerted');
  String get sosTestModeOn => pick(
        'มายด์เรียกและนับถอยหลังตามปกติ แต่ไม่ส่ง SMS ไม่โทรหาใคร ทั้งแรงกระแทก ปุ่ม และคำพูด · '
            '🔴 เกิดเหตุจริงตอนนี้ต้องโทรเอง · ใช้จูนความไวจากบันทึกแรงกระแทกหลาย ๆ วัน พร้อมแล้วค่อยปิดโหมดนี้',
        'Mind calls out and counts down as usual, but texts and calls nobody, for impacts, the button and your voice. '
            '🔴 In a real emergency now, call for help yourself. Tune the sensitivity from the impact log over a few days, then turn this off',
      );
  String get sosTestModeOff => pick(
        '🔴 แจ้งจริงอยู่ · ขอความช่วยเหลือด้วยปุ่มหรือคำพูดแล้วไม่ตอบ = ส่ง SMS และโทรจริง',
        '🔴 Live · asking for help by button or voice and not answering sends real texts and calls',
      );
  String get sosRealTitle => pick('เปิดแจ้งจริง', 'Turn on real alerts');
  String get sosRealAsk => pick(
        'จากนี้มายด์จะส่ง SMS และโทรหาผู้ติดต่อกับเจ้าหน้าที่จริง · แจ้งเหตุเท็จมีผลจริง · จูนความไวจนพอใจแล้วใช่ไหมคะ',
        'From now on Mind will really text and call your contacts and responders. False alerts have real consequences. Are you happy with the tuning?',
      );
  String get sosRealYes => pick('พร้อมแล้ว เปิดแจ้งจริง', 'Ready, turn on real alerts');
  String get sosAutoCallTesting => pick('ใช้ได้เมื่อปิดโหมดทดสอบ', 'Available once test mode is off');
  String get sosTriggerFailed => pick('เริ่มไม่ได้ · โทรเองทันทีค่ะ', 'Could not start · Call for help yourself now');
  String get sosManualHint => pick(
        'มีเวลา 5 วินาทีให้กดหยุด · พูดว่า "SOS" กับมายด์ก็ได้ มีเวลา 10 วินาที\n'
            'พูดว่า "ช่วยด้วย" = แจ้งเงียบทันที ไม่ถาม ไม่มีเสียง ไม่มีจอ · ส่ง SMS ทันที โทรเจ้าหน้าที่ใน 20 วินาที · พูดว่า "ยกเลิก" หรือกดหยุดที่นี่เพื่อหยุด',
        'You get 5 seconds to stop it · You can also say "SOS" to Mind, with 10 seconds to stop\n'
            'Saying "help me" alerts silently at once, with no questions, sound or screen · Texts go now, responders are called in 20 seconds · Say "cancel" or stop it here',
      );
  String get sosSilentRunning => pick('กำลังแจ้งเหตุแบบเงียบ', 'Silent alert in progress');
  String get sosStopNow => pick('หยุดการแจ้งเหตุ', 'Stop the alert');

  String get sosConsentTitle => pick('อ่านก่อนเปิดใช้', 'Read before turning this on');
  String get sosConsentBody => pick(
        'ระบบนี้ช่วยได้ แต่ไม่รับประกันและไม่ทดแทนหน่วยฉุกเฉิน\n\n'
            '• อาจจับเหตุไม่ได้ หรือจับผิดว่าเกิดเหตุ\n'
            '• ถ้าระบบปิดแอป แบตหมด ไม่มีสัญญาณ หรือกดออกจากแอป ระบบนี้จะไม่ทำงาน\n'
            '• แจ้งเหตุเท็จมีผลจริง กินเวลาเจ้าหน้าที่ และอาจมีความผิดตามกฎหมาย\n'
            '• คำว่า "ช่วยด้วย" แจ้งเงียบทันทีโดยไม่ถาม ถ้าเครื่องได้ยินผิดก็จะแจ้งเหตุจริง\n'
            '• เมื่อเปิด มายด์จะส่งตำแหน่งและข้อมูลที่กรอกไว้ให้เจ้าหน้าที่และคนที่คุณตั้งไว้เมื่อเกิดเหตุ\n'
            '• ค่าแรงกระแทกยังไม่ได้วัดกับอุบัติเหตุจริง\n\n'
            'เกิดเหตุแล้วโทรเองได้ ให้โทรเองก่อนเสมอ',
        'This can help, but it is not guaranteed and does not replace emergency services.\n\n'
            '• It can miss an incident, or raise a false alarm\n'
            '• If the system closes the app, the battery dies, there is no signal, or you exit the app, it stops working\n'
            '• False reports have real consequences and may be an offence\n'
            '• Saying "help me" alerts silently at once with no question, so a misheard phrase is a real alert\n'
            '• When it runs, Mind sends your location and the details you enter to responders and the people you set\n'
            '• The impact thresholds have not been measured against real crashes\n\n'
            'If you can call for yourself, always do that first.',
      );
  String get sosConsentYes => pick('เข้าใจแล้ว เปิดใช้', 'I understand, turn it on');

  String get sosReadyCard => pick('ความพร้อม', 'Readiness');
  String get sosFix => pick('แก้', 'Fix');
  String get sosReadyLocation => pick('ตำแหน่ง', 'Location');
  String get sosReadyBackground => pick('ตำแหน่งตลอดเวลา (ตอนจอล็อก)', 'Location all the time (while locked)');
  String get sosReadySms => pick('ส่ง SMS', 'Send SMS');
  String get sosReadyCall => pick('โทรออก', 'Phone calls');
  String get sosReadyMic => pick('ไมค์ ฟังคำตอบตอนเรียก', 'Microphone, to hear your answer');
  String get sosReadyNotify => pick('แจ้งเตือน', 'Notifications');
  String get sosReadyFullScreen => pick('ขึ้นเต็มจอบนจอล็อก', 'Full screen on the lock screen');
  String get sosReadyBattery => pick('ยกเว้นประหยัดแบต', 'Battery optimisation exempt');
  String get sosReadyDialer => pick('เป็นแอปโทรศัพท์หลัก (จำเป็นสำหรับโทรเบอร์ฉุกเฉินเอง)', 'Default phone app (needed to place emergency calls)');
  String get sosReadyThaiVoice => pick('เสียงพูดภาษาไทยในเครื่อง (ไม่มีจะพูดบทอังกฤษกับเจ้าหน้าที่)', 'Thai text-to-speech voice (without it she reads the English script)');
  String get sosDialerWarn => pick(
        '🔴 ยังไม่ได้เป็นแอปโทรศัพท์หลัก · Android ไม่ให้แอปโทรเบอร์ฉุกเฉินเอง จะได้แค่ SMS ถึงผู้ติดต่อและโทรหาผู้ติดต่อ',
        '🔴 Not the default phone app · Android will not let it call emergency numbers, so only your contacts get texts and calls',
      );
  String get sosReadySensor => pick('เซ็นเซอร์ความเร่ง', 'Accelerometer');
  String get sosVivoNote => pick(
        'เครื่อง vivo: เปิด "เริ่มอัตโนมัติ" และ "แสดงหน้าต่างแบบป๊อปอัปในเบื้องหลัง" ให้แอปนี้ในการตั้งค่าของเครื่องด้วย ไม่งั้นระบบปิดแอปและจอฉุกเฉินจะไม่ขึ้น',
        'vivo phones: also allow Autostart and background pop-ups for this app in the phone settings, or the system will close it and the alert screen will not appear',
      );
  String sosNotEcc(String list) => pick(
        'ซิมนี้ไม่ได้ระบุ $list เป็นเบอร์ฉุกเฉิน · ยังโทรได้แต่จะเข้าทางสายปกติ',
        'This SIM does not list $list as emergency numbers · They still dial, as ordinary calls',
      );

  String get sosYouCard => pick('ข้อมูลสำหรับเจ้าหน้าที่', 'Details for responders');
  String get sosYouHint => pick(
        'ว่างได้ทุกช่อง · มายด์พูดเฉพาะที่กรอก ไม่เดา · เข้ารหัสในเครื่อง ไม่ส่งเข้าสมองของมายด์',
        'Every field is optional · Mind only says what is here and never guesses · Encrypted on this phone, never sent to her brain',
      );
  String get sosName => pick('ชื่อ-นามสกุล', 'Full name');
  String get sosBirthYear => pick('ปีเกิด ค.ศ.', 'Birth year');
  String get sosBlood => pick('กรุ๊ปเลือด', 'Blood group');
  String get sosConditions => pick('โรคประจำตัว', 'Medical conditions');
  String get sosMedicines => pick('ยาที่ใช้ประจำ', 'Regular medication');
  String get sosAllergies => pick('แพ้ยา', 'Drug allergies');
  String get sosPlate => pick('ทะเบียนรถ', 'Vehicle plate');
  String get sosNotes => pick('อื่น ๆ ที่เจ้าหน้าที่ควรรู้', 'Anything else responders should know');
  String get sosBirthYearBad => pick('ปีเกิดไม่ถูกต้อง ใส่เป็น ค.ศ. เช่น 1990', 'Enter a valid birth year, such as 1990');

  String get sosContactsCard => pick('ผู้ติดต่อฉุกเฉิน', 'Emergency contacts');
  String get sosContactsHint => pick(
        'ได้ SMS พร้อมตำแหน่งตามลำดับ และโทรหาเมื่อเจ้าหน้าที่ไม่รับ',
        'They get a text with your location, in order, and a call if responders do not pick up',
      );
  String get sosContactAdd => pick('เพิ่มผู้ติดต่อ', 'Add contact');
  String get sosContactName => pick('ชื่อ', 'Name');
  String get sosContactNumber => pick('เบอร์มือถือ', 'Mobile number');
  String get sosContactHealth => pick('ส่งข้อมูลสุขภาพให้คนนี้ด้วย', 'Include health details for this person');
  String get sosContactBad => pick('ต้องเป็นเบอร์มือถือเต็ม ไม่ใช่เบอร์สั้นหรือ 1900', 'Must be a full mobile number, not a short code or 1900');
  String sosContactDeleteAsk(String name) => pick('ลบ $name ออกจากผู้ติดต่อฉุกเฉินไหมคะ', 'Remove $name from your emergency contacts?');
  String get sosDelete => pick('ลบ', 'Delete');

  String get sosDrillCard => pick('ซ้อมและโทรอัตโนมัติ', 'Drills and automatic calling');
  String get sosDrillHint => pick(
        'ซ้อมส่ง SMS และโทรเข้าเบอร์ทดสอบเท่านั้น ไม่แตะเจ้าหน้าที่หรือญาติ และไม่นับเป็นเหตุจริง',
        'A drill only texts and calls your test number, never responders or contacts, and does not count as an incident',
      );
  String get sosTestNumber => pick('เบอร์ทดสอบ (เบอร์ของคุณอีกเบอร์ หรือคนที่รู้ว่ากำลังซ้อม)', 'Test number (your other phone, or someone who knows it is a drill)');
  String get sosTestBad => pick('เบอร์ทดสอบต้องเป็นเบอร์มือถือเต็ม และห้ามเป็นเบอร์ฉุกเฉิน', 'The test number must be a full mobile number and never an emergency number');
  String get sosDrillRun => pick('เริ่มซ้อม', 'Run a drill');
  String sosDrillAsk(String number) => pick(
        'มายด์จะเรียกเสียงดัง นับถอยหลัง แล้วส่ง SMS และโทรหา $number จริง · ดำเนินการไหมคะ',
        'Mind will call out loudly, count down, then really text and call $number. Go ahead?',
      );
  String get sosDrillSilentRun => pick('ซ้อมแจ้งเงียบ', 'Silent drill');
  String sosDrillSilentAsk(String number) => pick(
        'มายด์จะไม่มีเสียงและไม่ขึ้นจอ แต่ส่ง SMS และโทรหา $number จริงทันที · ดำเนินการไหมคะ',
        'Mind stays silent and off screen, but really texts and calls $number at once. Go ahead?',
      );
  String sosDrillCount(int n) => pick('ซ้อมสำเร็จแล้ว $n ครั้ง', '$n drills completed');
  String get sosDrillFailed => pick('เริ่มซ้อมไม่ได้ · ต้องเปิดระบบและบันทึกก่อน', 'Could not start · Turn the system on and save first');
  String get sosAutoCall => pick('โทรแจ้งเจ้าหน้าที่เองเมื่อเกิดแรงกระแทก', 'Call responders automatically after an impact');
  String get sosAutoCallHint => pick(
        'ปิดอยู่ = โหมดซ้อม มายด์เรียกและนับถอยหลังเหมือนจริง แต่ไม่แจ้งใคร ใช้ดูว่าเครื่องจับผิดบ่อยแค่ไหนก่อนเปิด',
        'Off = rehearsal. Mind calls out and counts down as usual but alerts nobody, so you can see how often it misfires first',
      );
  String get sosAutoCallLocked => pick('ต้องซ้อมสำเร็จอย่างน้อย 1 ครั้งก่อน', 'Complete at least one drill first');
  String sosCountdown(int s) => pick('เวลาให้ตอบก่อนแจ้งเหตุ: $s วินาที', 'Time to answer before the alert: $s seconds');
  String get sosSensitivity => pick('ความไวต่อแรงกระแทก', 'Impact sensitivity');
  String get sosSensLow => pick('น้อย', 'Low');
  String get sosSensMid => pick('ปกติ', 'Normal');
  String get sosSensHigh => pick('มาก', 'High');

  String get sosPlaceCard => pick('ตำแหน่งตอนนี้', 'Current location');
  String get sosPlaceNone => pick('ยังไม่มีตำแหน่ง · ตรวจสิทธิ์และเปิด GPS', 'No location yet · Check the permission and turn on GPS');
  String sosPlaceAge(int min) => min < 1 ? pick('เมื่อสักครู่', 'just now') : pick('เมื่อ $min นาทีก่อน', '$min minutes ago');
  String get sosPlaceRefresh => pick('อ่านใหม่', 'Refresh');
  String get sosShareCopy => pick('คัดลอก', 'Copy');
  String get sosShareSms => pick('SMS', 'SMS');
  String get sosShareLine => pick('LINE', 'LINE');
  String get sosShareAny => pick('แอปอื่น', 'Other apps');
  String get sosShareFailed => pick('แชร์ไม่ได้ · แอปนี้อาจไม่ได้ติดตั้ง', 'Could not share · That app may not be installed');
  String get sosShareNote => pick(
        'LINE และแอปแชทไม่มีทางให้ส่งอัตโนมัติ ต้องเลือกห้องแล้วกดส่งเอง · ตอนเกิดเหตุมายด์จึงใช้ SMS',
        'LINE and chat apps cannot send by themselves, you pick the chat and tap send · So in an incident Mind uses SMS',
      );

  String get sosLogCard => pick('บันทึกแรงกระแทกและแบต', 'Impact log and battery');
  String get sosLogEmpty => pick('ยังไม่มีแรงกระแทกที่นับ', 'No impacts recorded yet');
  String sosLogBattery(int armed, int trip, int drop) => pick(
        'เปิดรวม $armed นาที · เปิดเซ็นเซอร์เต็ม $trip นาที · แบตลด $drop%',
        'On for $armed min · Full sensors $trip min · Battery down $drop%',
      );
  String get sosLowPowerMissing => pick('เครื่องนี้ไม่มีตัวจับการเคลื่อนไหวกินไฟน้อย จึงกินแบตมากกว่า', 'This phone has no low-power motion sensor, so it uses more battery');

  String get sosLastCard => pick('เหตุล่าสุด', 'Last incident');
  String get sosLastCancelled => pick('หยุดระหว่างทาง', 'Stopped part way');
  String sosOutcome(String who, String outcome) {
    final what = switch (outcome) {
      'sent' => pick('สั่งส่ง SMS แล้ว', 'text handed to the network'),
      'failed' => pick('ส่งไม่สำเร็จ', 'could not send'),
      'reached' => pick('โทรติด', 'call connected'),
      'no_answer' => pick('ไม่มีคนรับ', 'no answer'),
      'unsure' => pick('โทรแล้ว ไม่แน่ใจว่ามีคนรับ', 'called, not sure anyone answered'),
      'stopped' => pick('หยุดกลางสาย สายอาจยังอยู่', 'stopped mid call, it may still be live'),
      'not_dialer' => pick('โทรเองไม่ได้ ต้องเป็นแอปโทรศัพท์หลัก', 'could not call, not the default phone app'),
      'simulated' => pick('จำลอง ไม่ได้ส่งจริง', 'simulated, nothing sent'),
      'no_permission' => pick('ไม่มีสิทธิ์โทร', 'no call permission'),
      'no_telecom' => pick('โทรไม่ได้', 'could not place the call'),
      _ => outcome,
    };
    return '$who: $what';
  }

  /// ผลตัดสินแรงกระแทกแต่ละครั้ง · รหัสจาก ImpactDetector.kt
  String sosVerdict(String code) => switch (code) {
        'crash' => pick('น่าจะชน', 'likely crash'),
        'fast_unsure' => pick('เร็วแต่ไม่แน่ใจ', 'fast, unsure'),
        'hard_hit' => pick('แรงกระแทกหนัก', 'hard hit'),
        'kept_moving' => pick('ยังไปต่อ ไม่นับ', 'kept moving, ignored'),
        'dropped' => pick('เครื่องตก ไม่นับ', 'dropped, ignored'),
        'handled' => pick('อยู่ในมือ ไม่นับ', 'in hand, ignored'),
        'weak' => pick('เบา ไม่นับ', 'light, ignored'),
        _ => code,
      };

  String get sosNumbersCard => pick('เบอร์ฉุกเฉินไทย', 'Thai emergency numbers');
  String get sosNumbersHint => pick(
        'ต่างประเทศใช้ 112 และพูดภาษาอังกฤษ · บางประเทศเบอร์หลักเป็นเบอร์อื่น · SMS เข้า 1669 และ 191 ไม่ใช่ช่องทางที่ยืนยันได้ จึงส่งให้ผู้ติดต่อเท่านั้น',
        'Abroad it uses 112 in English · Some countries use another main number · Texting 1669 or 191 is not a confirmed channel, so texts go to your contacts only',
      );

  String get sosSave => pick('บันทึก', 'Save');
  String get sosSaved => pick('บันทึกแล้ว', 'Saved');
  String get sosSaveFailed => pick('บันทึกไม่สำเร็จ', 'Could not save');
  String get sosCancel => pick('ยกเลิก', 'Cancel');
  String get sosWipe => pick('ลบข้อมูลฉุกเฉินทั้งหมด', 'Delete all emergency data');
  String get sosWipeAsk => pick(
        'ลบข้อมูล ผู้ติดต่อ และประวัติการซ้อม แล้วปิดระบบแจ้งเหตุไหมคะ · กู้คืนไม่ได้',
        'Delete your details, contacts and drill history and turn the system off? This cannot be undone.',
      );
  String get sosPermsDenied => pick('ยังไม่ได้รับสิทธิ์บางตัว ดูที่รายการความพร้อมค่ะ', 'Some permissions are still missing, see Readiness');
}
