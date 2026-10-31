import 'strings.dart';

/// ข้อความของหน้าตั้งค่าแบบแบ่งหมวด · ไลเซนส์ · สถานะจริงของสมองในเครื่อง
extension SettingsStrings on S {
  String get directCallSetup => pick('ตั้งค่าเสียงตรงในสาย', 'Set up direct call audio');
  String get directCallSetupHint => pick('เชื่อมต่อกับเครื่องนี้เพื่อให้คู่สายได้ยินชัดขึ้น', 'Connect to this phone for clearer call audio');
  String get directCallTitle => pick('ต่อสายตรง', 'Direct call audio');
  String get directCallChecking => pick('กำลังตรวจ…', 'Checking…');
  String get directCallReady => pick('ต่อติดแล้ว · น้องมายพูดเข้าสายตรง ไม่ผ่านลำโพง', 'Connected · she speaks straight into the call, not through the speaker');
  String get directCallOffline => pick('ยังไม่ได้ต่อ · จะลองใหม่เองเมื่อ Wi-Fi พร้อม ระหว่างนี้เธอไม่รับสายเอง', 'Offline · will retry when Wi-Fi is available; she will not auto-answer meanwhile');
  String get directCallNotPaired => pick('ยังไม่เคยตั้งค่า · ถ้าคู่สายไม่ได้ยินเธอ ให้ตั้งค่าตรงนี้', 'Not set up yet · set this up if callers cannot hear her');
  String get directCallInCall => pick('กำลังใช้อยู่ในสาย', 'In use on the current call');
  String get directCallUnsupported => pick('เครื่องนี้ยังไม่รองรับ', 'This phone does not support it');
  String get directCallConnect => pick('ต่อสายตรง', 'Connect');
  String get directCallFirstSetup => pick('ตั้งค่าครั้งแรก', 'First-time setup');
  String get directCallNeedsDebugging => pick('ต่อไม่ได้ · จะลองเองเมื่อ Wi-Fi พร้อม', 'Could not connect · will retry when Wi-Fi is available');
  String get directCallKeyRejected => pick('กุญแจเดิมถูกปฏิเสธ · ต้องจับคู่ใหม่', 'Saved key rejected · pair again');
  String directPauseMinutes(int minutes) => pick('$minutes นาที', '$minutes min');
  String get directCallPaused => pick('พักชั่วคราว · เสียงตรงจะกลับมาเมื่อคืนค่า', 'Paused · direct audio returns after restoration');
  String get directPauseButton => pick('พักสำหรับแอปการเงิน', 'Pause for finance apps');
  String get directPauseTitle => pick('พักชั่วคราว', 'Temporary pause');
  String get directPauseConfirm => pick(
      'GigGok จะปิด Wireless debugging, USB debugging, ตัวเลือกนักพัฒนา และบริการช่วยเหลือพิเศษของ GigGok เท่านั้น แล้วคืนค่าเดิมหลังเวลาที่เลือก ระหว่างพักเสียงตรงอาจหยุด และน้องมายจะไม่รับสายเองถ้าเสียงตรงไม่พร้อม',
      'GigGok will turn off Wireless debugging, USB debugging, Developer options, and only GigGok’s accessibility service, then restore their previous values after the selected time. Direct call audio may stop during the pause; Mind will not auto-answer when direct audio is unavailable.');
  String get directPauseNeedsSetup => pick('ต้องต่อเสียงตรงก่อนเพื่อเปิดสิทธิ์ควบคุมชั่วคราว', 'Connect direct audio first to enable temporary control');
  String get directStatusNotificationsOff => pick('ไอคอนสถานะไม่ขึ้นจนกว่าจะอนุญาตการแจ้งเตือนของ GigGok', 'The status icon needs GigGok notifications enabled');
  String get directPauseFailed => pick('พักไม่สำเร็จ · ตรวจสิทธิ์และลองอีกครั้ง', 'Could not pause · check permissions and try again');
  String get directPauseRestoreFailed => pick('ยังคืนค่าไม่ได้ · จะลองอีกเมื่อสายจบหรือเปิดแอป', 'Could not restore yet · will retry after the call or when the app opens');
  String get directPauseRemaining => pick('พักอยู่ · คืนค่าใน', 'Paused · restoring in');
  String get directPauseWaiting => pick('พักอยู่ · รอจบสายเพื่อคืนค่า', 'Paused · waiting for the call to end');
  String get directPauseExtend => pick('เพิ่ม 5 นาที', 'Add 5 min');
  String get directPauseRestore => pick('คืนค่าตอนนี้', 'Restore now');
  String get directPauseCancel => pick('ยกเลิก', 'Cancel');
  String get directPauseConfirmButton => pick('พักตอนนี้', 'Pause now');
  String get liveTalkCard => pick('คุยสดในสาย', 'Live talk on calls');
  String get liveCalls => pick('คุยด้วย GPT-Live (ทดลอง)', 'Talk with GPT-Live (trial)');
  String get liveCallsHint => pick(
      'ฟังพร้อมพูด คู่สายแทรกเธอได้เหมือนคุยกับคนจริง · ใช้ตอนต่อสายตรงอยู่เท่านั้น · คิดเงินราว \$0.05 ต่อนาทีจากคีย์ของคุณ · '
          'OpenAI ยังไม่ระบุว่ารองรับภาษาไทย · ต่อไม่ได้หรือหลุด จะใช้คุยสดแบบเดิมต่อให้เอง',
      'Listens while she talks, so callers can cut in like with a real person · only with direct call audio connected · about \$0.05 a minute on your key · '
          'OpenAI does not list Thai as supported yet · falls back to the usual live talk if it cannot connect or drops');
  // ── ความรู้ที่ให้น้องมายตอบคนโทร ──
  String get kbCard => pick('ความรู้ที่น้องมายใช้ตอบคนโทร', 'What she can tell callers');
  String get kbTitle => pick('คลังความรู้ตอบคนโทร', 'Caller knowledge');
  String kbReady(int sources, int scopes) => pick(
      'พร้อม · ข้อมูลของคุณ $sources แหล่ง${scopes > 0 ? ' · BrainX $scopes หมวด' : ''} · คนโทรถาม เธอค้นก่อนตอบ',
      'Ready · $sources of your sources${scopes > 0 ? ' · $scopes BrainX folders' : ''} · she looks it up before answering');
  String get kbEmpty => pick('ยังว่าง · คนโทรถามราคา บริการ เวลาเปิด เธอจะบอกว่าไม่ทราบแล้วรับเรื่องไว้',
      'Empty · asked about prices, services or hours, she says she does not know and takes a message');
  String get kbNeedsLive => pick('ใช้ได้ตอนคุยสด (สมอง OpenAI ด้วยคีย์ของคุณ + เปิดคุยสดในสาย)',
      'Works on live calls only (OpenAI brain with your own key + live calls on)');
  String get kbMine => pick('ข้อมูลของคุณ', 'Your information');
  String get kbAddLink => pick('ลิงก์เว็บ', 'Web link');
  String get kbAddFile => pick('ไฟล์', 'File');
  String get kbAddText => pick('พิมพ์เอง', 'Type it');
  String get kbNone => pick('ยังไม่มี · เพิ่มเว็บของร้าน ไฟล์ราคา หรือพิมพ์คำถามที่คนโทรถามบ่อย',
      'Nothing yet · add your shop website, a price list, or type the questions callers often ask');
  String kbUsage(String used, String max) => pick('ใช้ไป $used / $max ตัวอักษร', '$used / $max characters used');
  String kbChars(String n) => pick('$n ตัวอักษร', '$n characters');
  String kbUpdated(String when) => pick('อัปเดต $when', 'updated $when');
  String get kbTyped => pick('พิมพ์เอง', 'typed');
  String get kbLinkTitle => pick('เพิ่มลิงก์เว็บ', 'Add a web link');
  String get kbLinkHint => pick('หน้าเว็บของคุณ เช่น หน้าราคา หน้าบริการ · แอปดึงข้อความมาเก็บในเครื่อง กดรีเฟรชเมื่อเว็บเปลี่ยน',
      'A page of yours, e.g. prices or services · the text is saved on this phone; refresh it when the site changes');
  String get kbTextTitle => pick('พิมพ์ข้อมูลให้คนโทร', 'Type information for callers');
  String get kbTextName => pick('หัวข้อ (เช่น ราคา เวลาเปิด)', 'Topic (e.g. prices, hours)');
  String get kbTextBody => pick('ข้อมูล · เขียนแบบที่อยากให้เธอตอบ', 'Information · write it the way you want her to answer');
  String get kbAdd => pick('เพิ่ม', 'Add');
  String get kbRefresh => pick('ดึงหน้าเว็บใหม่', 'Fetch the page again');
  String get kbDelete => pick('ลบ', 'Delete');
  String kbDeleteAsk(String title) => pick('ลบ "$title" ออกจากคลัง? เธอจะตอบเรื่องนี้ไม่ได้อีก',
      'Remove "$title"? She will no longer be able to answer from it.');
  String get kbPreviewNote => pick('นี่คือข้อความที่เธออ่านได้ทั้งหมดจากแหล่งนี้', 'This is all the text she can read from this source');
  String get kbClose => pick('ปิด', 'Close');
  String get kbAdded => pick('เพิ่มแล้ว · เธอค้นเจอตั้งแต่สายถัดไป', 'Added · she can find it from the next call');
  String get kbErrBadUrl => pick('ลิงก์ไม่ถูกต้อง · ต้องขึ้นต้นด้วย https://', 'That link is not valid · it must start with https://');
  String get kbErrFetch => pick('เปิดหน้าเว็บไม่ได้ · ดูว่าเน็ตต่ออยู่และลิงก์เปิดได้ในเบราว์เซอร์', 'Could not open the page · check the connection and that the link opens in a browser');
  String get kbErrType => pick('ยังอ่านไฟล์ชนิดนี้ไม่ได้ · ใช้ txt md csv json html หรือ docx (PDF ให้คัดลอกข้อความมาพิมพ์เอง)',
      'This file type is not supported · use txt, md, csv, json, html or docx (for a PDF, copy the text into "Type it")');
  String get kbErrEmpty => pick('ไม่มีข้อความให้เก็บ', 'There is no text to keep');
  String get kbErrTooLarge => pick('ใหญ่เกินคลัง · ลบแหล่งที่ไม่ใช้แล้วก่อน หรือแบ่งไฟล์', 'Too large for the store · remove unused sources or split the file');
  String get kbErrRead => pick('อ่านไฟล์ไม่ได้ · ลองเลือกใหม่', 'Could not read the file · try again');
  String get kbErrOther => pick('ทำไม่สำเร็จ · ลองอีกครั้ง', 'That did not work · try again');
  String get kbBrainx => pick('เรื่องใน BrainX ที่ให้ตอบได้', 'BrainX folders she may answer from');
  String get kbBrainxWarn => pick('🔒 คนโทรเป็นคนนอก · ติ๊กเฉพาะหมวดที่ไม่มีเรื่องส่วนตัว รหัส หรืองานลูกค้า · หมวดที่ไม่ติ๊ก เธอมองไม่เห็นเลย',
      '🔒 Callers are outsiders · tick only folders without private notes, passwords or client work · she cannot see anything unticked');
  String get kbBrainxOff => pick('ยังไม่ได้เชื่อม BrainX · เชื่อมได้ที่ ตั้งค่า › สมองและเสียง', 'BrainX is not connected · connect it in Settings › Brain & voice');
  String get kbBrainxLoading => pick('กำลังโหลดหมวดจากสมอง…', 'Loading folders from the brain…');
  String get kbBrainxFailed => pick('โหลดหมวดไม่ได้ · ดูว่าเน็ตต่ออยู่', 'Could not load folders · check the connection');
  String get kbBrainxRetry => pick('โหลดอีกครั้ง', 'Try again');
  String get kbBrainxFilter => pick('ค้นชื่อหมวด', 'Find a folder');
  String get kbBrainxNoneTicked => pick('ยังไม่ได้ติ๊กสักหมวด · เธอไม่แตะ BrainX ในสาย', 'Nothing ticked · she does not touch BrainX on calls');
  String kbNotes(int n) => pick('$n โน้ต', '$n notes');
  String get kbIncluded => pick('รวมอยู่ในหมวดแม่แล้ว', 'included by the parent folder');
  String kbBigAsk(String scope, int notes) => pick(
      'เปิดให้คนโทรรู้ทั้งหมวด "$scope" ($notes โน้ต)? หมวดใหญ่มักมีเรื่องส่วนตัวปนอยู่ · ติ๊กหมวดย่อยที่ต้องการแทนจะปลอดภัยกว่า',
      'Let callers know everything in "$scope" ($notes notes)? Big folders usually mix in private notes · ticking just the subfolders you need is safer.');
  String get kbBigYes => pick('เปิดทั้งหมวด', 'Open the whole folder');
  String get kbTry => pick('ลองถามแบบคนโทร', 'Ask like a caller');
  String get kbTryHint => pick('เช่น ร้านเปิดกี่โมง · ส่งต่างจังหวัดไหม', 'e.g. what time do you open · do you ship');
  String get kbTryNone => pick('ไม่เจอ · ในสายเธอจะบอกว่าไม่ทราบ แล้วรับเรื่องไว้ให้คุณ', 'Nothing found · on a call she would say she does not know and take a message');
  String get kbFromMine => pick('ข้อมูลของคุณ', 'yours');
  // ── บุคลิกตอนรับสาย ──
  String get cpCard => pick('บุคลิกตอนรับสาย', 'Her manner on calls');
  String get cpPlay => pick('ความขี้เล่นกับคนโทร', 'How playful with callers');
  String cpPlayWord(double v) => v < 0.25
      ? pick('สุภาพเรียบร้อย · ไม่แซว ไม่เล่นมุก', 'Polite · no teasing or jokes')
      : v < 0.6
          ? pick('อบอุ่น มีอารมณ์ขัน · หัวเราะได้ แซวนิด ๆ', 'Warm, with humour · laughs, light teasing')
          : pick('ขี้เล่น คุยสนุก · แซว/จีบเล่นได้ถ้าเขาเล่นด้วย', 'Playful · teases and flirts lightly if they play along');
  String get cpMinutes => pick('คุยนานสุดแล้วเธอหาทางลงเอง', 'Longest chat before she wraps up herself');
  String get cpMinutesHint => pick('ธุระจบเมื่อไร เธอลาแล้ววางสายเองทันที · ตัวเลขนี้คือเพดานตอนคนโทรชวนคุยเล่น',
      'She says goodbye and hangs up as soon as the business is done · this is the cap when a caller just wants to chat');
  String cpMinutesValue(int m) => m == 0 ? pick('ไม่จำกัด', 'No limit') : pick('$m นาที', '$m min');
  String get cpStyle => pick('บุคลิกที่อยากให้เป็น (เขียนเอง)', 'The manner you want (your words)');
  String get cpStyleEmpty => pick('ยังไม่ได้เขียน · เช่น เรียกคนโทรว่าพี่ พูดหวาน ๆ ชอบหัวเราะ ลงท้ายด้วย "นะคะ"',
      'Not written yet · e.g. call people "dear", sweet voice, laughs easily');
  String get cpStyleHint => pick('เขียนสั้น ๆ ว่าอยากให้เธอพูดกับคนโทรแบบไหน · ใช้ทุกสายตั้งแต่สายถัดไป',
      'Describe briefly how she should talk to callers · applies from the next call');
  // ── หมวด ──
  String get settingsMenuTitle => pick('ตั้งค่า', 'Settings');
  String get settingsBack => pick('กลับไปหน้าตั้งค่า', 'Back to settings');

  String get settingsSecAccount => pick('บัญชีและไลเซนส์', 'Account & license');
  String get settingsSecHer => pick('ตัวเธอ', 'Her');
  String get settingsSecBrain => pick('สมองและเสียง', 'Brain & voice');
  String get settingsSecYou => pick('เกี่ยวกับคุณ', 'About you');
  String get settingsSecCalls => pick('รับสายแทน', 'Answering calls');
  String get settingsSecGeneral => pick('ทั่วไป', 'General');
  String get settingsSecData => pick('ข้อมูลและความเป็นส่วนตัว', 'Data & privacy');

  String get settingsSecHerHint =>
      pick('ชุด ตัวตน โหมด การจีบ ฟองคำพูด', 'Outfit, identity, mode, flirting, speech bubble');
  String get settingsSecYouHint => pick(
      'ข้อมูลเกี่ยวกับคุณ ขอบเขต และสิ่งที่เธอจำได้', 'About you, boundaries, and what she remembers');
  String get settingsSecCallsHint =>
      pick('รับสายอัตโนมัติ เสียงตอบรับ ทางเสียงเข้าสาย', 'Auto-answer, answering voice, call audio path');
  String get settingsSecGeneralHint => pick(
      'ภาษา สิทธิ์ของแอป การทำงานเบื้องหลัง', 'Language, app permissions, background work');
  String get settingsSecDataHint => pick(
      'สำเนาข้อมูล ลบข้อมูล รายงานปัญหา', 'Backup copy, erase data, problem reports');
  String get settingsSecAccountHint => pick('ซีเรียลของเครื่องนี้ ผูกบัญชีเว็บ อัปเดตแอป',
      "This device's serial, web account link, app updates");

  // ── ไลเซนส์ ──
  String get licenseSection => pick('ไลเซนส์ของเครื่องนี้', "This device's license");
  String get licenseSerial => pick('ซีเรียล (รหัสไลเซนส์)', 'Serial (license key)');
  String get licenseTypeFree => pick('ไลเซนส์ฟรี', 'Free license');
  String licenseTypeOf(String type) => pick('ไลเซนส์ $type', '$type license');
  String get licenseManual => pick('ใส่ซีเรียลเอง', 'Entered by hand');
  String licenseRegistered(String type) =>
      pick('ลงทะเบียนเครื่องนี้แล้ว · $type', 'This device is registered · $type');
  String get licenseRegistering =>
      pick('กำลังลงทะเบียนเครื่องนี้อัตโนมัติ…', 'Registering this device automatically…');
  String get licenseRegisterFailed => pick(
        'ลงทะเบียนอัตโนมัติไม่สำเร็จ — ต่อเน็ตแล้วกดลองใหม่',
        'Automatic registration failed — get online and try again',
      );
  String get licenseNone => pick('ยังไม่มีซีเรียล', 'No serial yet');
  String get licenseRetry => pick('ลองใหม่', 'Try again');
  String get licenseShow => pick('แสดง', 'Show');
  String get licenseHide => pick('ซ่อน', 'Hide');
  String get licenseCopy => pick('คัดลอก', 'Copy');
  String get licenseCopied => pick('คัดลอกซีเรียลแล้ว', 'Serial copied');
  String get licenseEnter => pick('ใส่ซีเรียลเอง', 'Enter a serial');
  String get licenseEnterHint => pick(
        'ซีเรียลที่ได้จากการซื้อบน xman4289.com\n'
            'เว้นว่างแล้วบันทึก = กลับไปใช้ไลเซนส์ฟรีที่แอปลงทะเบียนให้เอง',
        'The serial from your purchase on xman4289.com\n'
            'Save it empty to go back to the free license the app registers for you',
      );
  String get licenseWhy => pick(
        'ทุกเครื่องได้ไลเซนส์ฟรีอัตโนมัติตอนเปิดแอปครั้งแรก ไม่ต้องสมัคร · ใช้ยืนยัน'
            'เครื่องนี้กับร้านชุดและบริการของเรา · ซื้อบนเว็บแล้ว ผูกเครื่องกับบัญชี '
            'หรือใส่ซีเรียลที่ได้มา',
        'Every device gets a free license automatically on first launch — no sign-up. '
            'It identifies this device to the outfit shop and our services. Bought '
            'something on the web? Link this device to your account, or enter the serial you got.',
      );

  // ── สมองในเครื่อง: ของจริงตอนนี้ ──
  String get gemmaNow => pick('ตอนนี้ใช้อยู่จริง', 'What is actually running');
  String gemmaOnDisk(String file, String gb) =>
      pick('ไฟล์ $file · $gb GB อยู่ในเครื่องครบ', 'File $file · $gb GB, complete on this device');
  String get gemmaNotOnDisk => pick('ยังไม่มีไฟล์ของรุ่นนี้ในเครื่อง', 'This model is not on the device yet');
  String gemmaOpen(String backend, String sec) =>
      pick('เปิดสมองแล้ว · คิดด้วย $backend · เปิดใช้เวลา $sec วิ',
          'Brain is open · thinking on the $backend · took $sec s to open');
  String get gemmaClosed => pick(
        'ยังไม่ได้เปิดสมอง — แอปเปิดรอไว้เองไม่กี่วินาทีหลังเปิดแอป หรือตอนทักครั้งแรก',
        'Brain not opened yet — the app opens it a few seconds after launch, or on your first message',
      );
  String gemmaLastReply(String wait, String total, String cps) => pick(
        'คำตอบล่าสุด: เห็นคำแรกใน $wait วิ · ตอบจบใน $total วิ · $cps ตัวอักษร/วิ',
        'Last reply: first words after $wait s · done in $total s · $cps chars/s',
      );
  String get gemmaLastReplyReread => pick(
        'ตานั้นต้องอ่านบทสนทนาใหม่ทั้งหมด จึงช้ากว่าปกติ',
        'That turn had to re-read the whole conversation, so it was slower than usual',
      );
  String gemmaLastReplyLoad(String sec) =>
      pick('รวมเวลาเปิดสมอง $sec วิ', 'including $sec s to open the brain');
  String get gemmaSameFile => pick(
        'รุ่นเดียวกันรันได้ทั้ง CPU และ GPU ไฟล์จึงไม่เปลี่ยนชื่อ · ที่ทำให้เร็วขึ้นคือสวิตช์ GPU ข้างล่าง',
        'The same model runs on both CPU and GPU, so the file name does not change — '
            'the GPU switch below is what makes it faster',
      );
  String get gemmaBench => pick('ทดสอบความเร็ว', 'Speed test');
  String get gemmaBenching => pick('กำลังทดสอบ…', 'Testing…');
  String get gemmaBenchSystem =>
      pick('ตอบสั้นที่สุด ประโยคเดียว เป็นภาษาไทย', 'Answer in one short sentence.');
  String get gemmaBenchQuestion => pick('สวัสดี วันนี้เป็นยังไงบ้าง', 'Hi, how is your day going?');

  // ── ออกจากแอป ──
  String get exitApp => pick('ออกจากแอป', 'Quit the app');
  String get exitTitle => pick('ปิดแอปและคืนหน่วยความจำ?', 'Close the app and free its memory?');
  String get exitBody => pick(
        'สมองในเครื่องกับตัวเธอจะถูกปล่อยออกจากหน่วยความจำ · ระหว่างที่ปิดอยู่ เธอรับสายแทนไม่ได้'
            'จนกว่าจะเปิดแอปใหม่\n\nถ้าแค่อยากออกไปใช้แอปอื่น กดย้อนกลับก็พอ — แอปจะพักอยู่เบื้องหลัง'
            'และพร้อมใช้ต่อทันที',
        'The on-device brain and her stage will be released from memory. While closed, she cannot '
            'answer calls until you open the app again.\n\nIf you only want to use another app, press '
            'Back — the app stays ready in the background.',
      );
  String get exitOk => pick('ปิดแอป', 'Quit');
  String get exitDuringCall =>
      pick('มีสายอยู่ — วางสายก่อนค่อยปิดแอป', 'A call is in progress — hang up before quitting');
  String get exitCardHint => pick(
        'ปุ่มย้อนกลับไม่ปิดแอป แอปจะพักอยู่เบื้องหลังให้เธอพร้อมรับสาย · ปิดจริงได้ที่ปุ่มนี้เท่านั้น',
        'Back does not close the app — it waits in the background so she can answer calls. '
            'Only this button really closes it',
      );

  // ── เปิดสมองล่วงหน้า ──
  String get preloadBrain => pick('เปิดสมองรอไว้ตั้งแต่เปิดแอป', 'Open the brain as soon as the app starts');
  String get preloadBrainHint => pick(
        'คำแรกตอบเร็วขึ้น แต่กินหน่วยความจำ 2–3 GB ทันทีที่เปิดแอป · ถ้าตัวเธอหายบ่อยให้ปิดไว้',
        'First reply comes faster, but takes 2–3 GB of memory right away — turn off if she keeps disappearing',
      );

  // ── รับสายตอนแอปอยู่เบื้องหลัง ──
  String get callBackgroundHint => pick(
        'แอปอยู่เบื้องหลังนาน ๆ ระบบอาจปิดแอปเอง แล้วเธอจะรับสายไม่ได้ · เปิด "เฝ้างาน" ในหมวดทั่วไป'
            'ให้แอปถูกปิดยากขึ้น',
        'If the app sits in the background for long, the system may close it and she cannot answer — '
            'turn on "Watch" under General to keep it alive',
      );

  // ── สิ่งที่น้องมายเรียนรู้จากสาย · โค้ดลับ ──
  String get clCard => pick('สิ่งที่น้องมายเรียนรู้จากสาย และโค้ดลับ', 'What she learns from calls, and the secret code');
  String get clIntro => pick(
      'หลังจบสาย เธอสรุปบทเรียนสั้น ๆ ไว้ใช้ในสายต่อไป และจำสิ่งที่บอสสั่งในแชทเรื่องการคุยโทรศัพท์ · '
          'เธอใช้เงียบ ๆ ไม่เล่าให้คนโทรฟัง · บทเรียนช่วยให้คุยเก่งขึ้นเท่านั้น ให้สิทธิ์เธอทำอะไรเพิ่มไม่ได้',
      'After each call she keeps short lessons for the next one, and remembers what you tell her in chat about '
          'handling calls · she uses them quietly and never reads them to callers · lessons only make her better '
          'at talking; they never give her permission to do more');
  String get clEmpty => pick('ยังไม่มีบทเรียน · คุยสายจริง หรือบอกในแชท เช่น "โทรหาร้านให้ถามราคาก่อน"',
      'No lessons yet · they come from real calls, or tell her in chat, e.g. "when calling a shop, ask the price first"');
  String get clKindOwner => pick('บอสสั่ง', 'From you');
  String get clKindContact => pick('เบอร์นี้', 'This number');
  String get clKindHow => pick('วิธีคุย', 'How to talk');
  String clDeleteAsk(String text) => pick('ลบบทเรียนนี้?\n"$text"', 'Delete this lesson?\n"$text"');
  String get clDelete => pick('ลบ', 'Delete');
  String get clClearAll => pick('ลบทั้งหมด', 'Delete all');
  String clClearAllAsk(int n) => pick('ลบบทเรียนทั้ง $n ข้อ? เธอจะเริ่มเรียนใหม่จากศูนย์',
      'Delete all $n lessons? She will start learning again from nothing');
  String clCount(int n) => pick('$n ข้อ', n == 1 ? '1 lesson' : '$n lessons');
  String get clCodeTitle => pick('โค้ดลับสำหรับคนที่บอสไว้ใจ', 'Secret code for people you trust');
  String get clCodeHint => pick(
      'คนที่พูดโค้ดนี้ในสายได้ฟังความจำของน้องมายเรื่องบอส (ความจำในเครื่อง และโฟลเดอร์ Mind ใน BrainX) · '
          'คนอื่นจะอ้างว่าเป็นใครหรือหลอกถามยังไง เธอก็ไม่บอก · ใช้ได้เฉพาะคุยสด · โค้ดไม่ให้สิทธิ์สั่งให้เธอจ่ายเงิน '
          'รับปาก หรือทำอะไรแทนบอส · บอสได้รับแจ้งทุกครั้งที่มีคนใช้โค้ดหรือพยายามเดา',
      'Someone who says this code on a call can hear what she remembers about you (her phone memory and the Mind '
          'folder in BrainX) · nobody else can, whoever they claim to be or however they ask · live talk only · '
          'the code never lets anyone make her pay, promise or act for you · you are notified every time someone '
          'uses it or tries to guess it');
  String get clCodeOn => pick('ตั้งโค้ดแล้ว', 'Code is set');
  String get clCodeOff => pick('ยังไม่ได้ตั้ง · ไม่มีใครฟังความจำของเธอในสายได้', 'Not set · nobody can hear her memory on a call');
  String clCodeLocked(String time) => pick('มีคนใส่ผิดหลายครั้ง · ปิดการตรวจโค้ดถึง $time (ตั้งโค้ดใหม่เพื่อเปิดทันที)',
      'Several wrong tries · code checks are off until $time (set a new code to reopen now)');
  String get clCodeSet => pick('ตั้งโค้ด', 'Set code');
  String get clCodeChange => pick('เปลี่ยนโค้ด', 'Change code');
  String get clCodeRemove => pick('ลบโค้ด', 'Remove code');
  String get clCodeRemoveAsk => pick('ลบโค้ดลับ? หลังจากนี้ไม่มีใครฟังความจำของเธอในสายได้',
      'Remove the secret code? After this nobody can hear her memory on a call');
  String get clCodeField => pick('โค้ดลับ', 'Secret code');
  String get clCodeAgain => pick('พิมพ์อีกครั้ง', 'Type it again');
  String get clCodeHelper => pick(
      'อย่างน้อย 6 ตัวอักษร ไม่นับช่องว่าง · คำที่พูดออกเสียงชัด เช่น ม้าลายสีชมพูสี่สิบสอง · อย่าใช้รหัสธนาคารหรือรหัสผ่านจริง',
      'At least 6 characters, spaces not counted · words that are easy to say aloud, like pink zebra forty two · '
          'never a real bank PIN or password');
  String get clCodeTooShort => pick('สั้นเกินไป · อย่างน้อย 6 ตัวอักษร', 'Too short · at least 6 characters');
  String get clCodeMismatch => pick('สองช่องไม่ตรงกัน', 'The two entries do not match');
  String get clCodeSaveFailed => pick('บันทึกโค้ดไม่ได้ · ลองอีกครั้ง', 'Could not save the code · try again');
  String get clCodeSaved => pick('บันทึกโค้ดแล้ว', 'Code saved');
  String get clCodeRemoved => pick('ลบโค้ดแล้ว', 'Code removed');
  String get clSave => pick('บันทึก', 'Save');
  String callCodeOpenedTitle(String who) =>
      pick('${who.isEmpty ? 'คนในสาย' : who} บอกโค้ดลับถูก', '${who.isEmpty ? 'The caller' : who} gave the secret code');
  String get callCodeOpenedBody => pick(
      'น้องมายตอบเรื่องของบอสให้คนในสายนี้ได้ · ถ้าไม่ใช่คนที่บอสให้โค้ดไว้ เปลี่ยนโค้ดในตั้งค่า › รับสายแทน',
      'She may tell this caller about you · if you did not give them the code, change it in Settings › Answering calls');
  String callCodeRefusedTitle(String who) =>
      pick('${who.isEmpty ? 'คนในสาย' : who} ใส่โค้ดลับไม่ถูก', '${who.isEmpty ? 'The caller' : who} got the secret code wrong');
  String get callCodeRefusedBody => pick(
      'น้องมายไม่ได้บอกอะไร · ถ้ามีคนเดาผิดหลายครั้ง ระบบปิดการตรวจโค้ดเอง 24 ชั่วโมง',
      'She told them nothing · after several wrong guesses, code checks switch off by themselves for 24 hours');

  // ── คำถามยืนยันตัวตน (สั่งให้น้องมายใช้เครื่องจากในสาย) ──
  String get clIdTitle => pick('คำถามยืนยันตัวตน', 'Identity questions');
  String get clIdHint => pick(
      'คนในสายที่ตอบคำถามเหล่านี้ถูกครบ สั่งให้น้องมายใช้เครื่องแทนบอสได้ระหว่างสายนั้น และได้ฟังความจำของเธอเรื่องบอส · '
          'แอปธนาคารและแอปจ่ายเงินห้ามแตะเสมอ · ก่อนส่ง จ่าย หรือลบอะไร เธอถามคนในสายก่อนทุกครั้ง · '
          'เธอไม่รู้คำตอบ แอปเป็นคนตรวจ · ใช้ได้เฉพาะคุยสด · บอสได้รับแจ้งทุกครั้งที่มีคนผ่านหรือไม่ผ่าน',
      'Someone who answers all of these correctly on a call can have her use your phone during that call, and can '
          'hear what she remembers about you · banking and payment apps stay off-limits · she asks the caller before '
          'sending, paying or deleting anything · she never knows the answers, the app checks them · live talk only · '
          'you are notified every time someone passes or fails');
  String clIdReady(int n, int ask) => pick('พร้อมใช้ · $n คำถาม · ถามสายละ $ask ข้อ', 'Ready · $n questions · asks $ask per call');
  String get clIdOff =>
      pick('ยังไม่ได้ตั้ง · ไม่มีใครในสายสั่งให้เธอใช้เครื่องได้', 'Not set · nobody on a call can have her use the phone');
  String clIdLocked(String time) => pick('มีคนตอบไม่ผ่านหลายครั้ง · ปิดการถามถึง $time (เปลี่ยนคำถามเพื่อเปิดทันที)',
      'Several failed tries · the questions are off until $time (change the questions to reopen now)');
  String get clIdSetUp => pick('ตั้งคำถาม', 'Set up');
  String get clIdEdit => pick('แก้คำถาม', 'Edit');
  String get clIdRemove => pick('ลบคำถามทั้งหมด', 'Remove questions');
  String get clIdRemoveAsk => pick('ลบคำถามยืนยันตัวตนทั้งหมด? หลังจากนี้ไม่มีใครในสายสั่งให้เธอใช้เครื่องได้',
      'Remove all identity questions? After this nobody on a call can have her use the phone');
  String clIdQuestion(int n) => pick('คำถามที่ $n', 'Question $n');
  String get clIdAnswer => pick('คำตอบที่ถูก', 'Expected answer');
  String get clIdShowAnswers => pick('แสดงคำตอบ', 'Show answers');
  String get clIdHideAnswers => pick('ซ่อนคำตอบ', 'Hide answers');
  String get clIdAdd => pick('เพิ่มคำถาม', 'Add question');
  String get clIdRemoveOne => pick('เอาข้อนี้ออก', 'Remove this question');
  String get clIdAskLabel => pick('ถามสายละ', 'Ask per call');
  String clIdAskCount(int n) => pick('$n ข้อ', '$n questions');
  String get clIdHelper => pick(
      'ตั้งคำถามที่คนนอกเดาไม่ได้ และคำตอบสั้น พูดง่าย ฟังชัด เช่น ชื่อเล่นของคนในบ้าน · อย่าใช้รหัสผ่านหรือข้อมูลธนาคาร · '
          'เธอสุ่มถามทีละข้อ ผิดข้อเดียวก็ไม่ผ่าน และไม่บอกว่าข้อไหนผิด · ตอบไม่ผ่าน 3 ครั้งใน 24 ชั่วโมง ปิดการถามเอง',
      'Pick questions outsiders cannot guess, with short answers that are easy to say and hear, like a family '
          'nickname · never a password or bank detail · she asks them one at a time in random order; one wrong answer '
          'fails, and she never says which one · 3 failed tries in 24 hours switch the questions off');
  String get clIdReplaceNote => pick('บันทึกแล้วจะแทนชุดเดิมทั้งหมด', 'Saving replaces the current questions');
  String get clIdTooFew => pick('ต้องมีอย่างน้อย 3 คำถาม', 'At least 3 questions are needed');
  String get clIdTooMany => pick('ได้ไม่เกิน 10 คำถาม', 'No more than 10 questions');
  String get clIdEmptyQuestion => pick('มีคำถามที่ยังว่าง', 'A question is empty');
  String get clIdTooLong => pick('คำถามหรือคำตอบยาวเกินไป', 'A question or answer is too long');
  String get clIdAnswerShort => pick('คำตอบสั้นเกินไป · อย่างน้อย 2 ตัวอักษร ไม่นับช่องว่าง',
      'An answer is too short · at least 2 characters, spaces not counted');
  String get clIdDuplicate => pick('มีคำถามซ้ำกัน', 'Two questions are the same');
  String get clIdAnswerInQuestion => pick('มีคำถามที่มีคำตอบอยู่ในตัว · คนโทรได้ยินคำถาม จึงรู้คำตอบไปด้วย',
      'A question contains an answer · callers hear the questions, so they would hear the answer too');
  String get clIdAskRange => pick('จำนวนข้อที่ถามต้องอยู่ระหว่าง 3 ถึงจำนวนคำถาม',
      'Questions asked per call must be between 3 and the number of questions');
  String get clIdSaved => pick('บันทึกคำถามแล้ว', 'Questions saved');
  String get clIdRemoved => pick('ลบคำถามแล้ว', 'Questions removed');
  String get clIdSaveFailed => pick('บันทึกคำถามไม่ได้ · ลองอีกครั้ง', 'Could not save the questions · try again');
  String callIdPassedTitle(String who) => pick('${who.isEmpty ? 'คนในสาย' : who} ตอบคำถามยืนยันตัวตนผ่าน',
      '${who.isEmpty ? 'The caller' : who} passed the identity questions');
  String callIdPassedBody({required bool phone}) => phone
      ? pick(
          'ระหว่างสายนี้ เขาสั่งให้น้องมายใช้เครื่องแทนบอสได้ และฟังเรื่องของบอสได้ · ถ้าไม่ใช่คนที่บอสไว้ใจ '
              'หยุดงานในแอป แล้วเปลี่ยนคำถามในตั้งค่า › รับสายแทน',
          'During this call they may have her use your phone and hear about you · if this is not someone you trust, '
              'stop the task in the app and change the questions in Settings › Answering calls')
      : pick(
          'ระหว่างสายนี้ น้องมายตอบเรื่องของบอสให้เขาได้ · ถ้าไม่ใช่คนที่บอสไว้ใจ เปลี่ยนคำถามในตั้งค่า › รับสายแทน',
          'During this call she may tell them about you · if this is not someone you trust, change the questions in '
              'Settings › Answering calls');
  String callIdRefusedTitle(String who) => pick('${who.isEmpty ? 'คนในสาย' : who} ตอบคำถามยืนยันตัวตนไม่ผ่าน',
      '${who.isEmpty ? 'The caller' : who} did not pass the identity questions');
  String get callIdRefusedBody => pick(
      'น้องมายไม่ได้ทำอะไรให้ และไม่ได้บอกว่าข้อไหนผิด · ไม่ผ่าน 3 ครั้งใน 24 ชั่วโมง ระบบปิดการถามเอง',
      'She did nothing for them and did not say which answer was wrong · after 3 failed tries in 24 hours the '
          'questions switch off by themselves');
  String callIdLockedBody(String time) => pick(
      'น้องมายไม่ได้ทำอะไรให้ · ไม่ผ่านหลายครั้ง ปิดการถามยืนยันตัวตนถึง $time (เปลี่ยนคำถามเพื่อเปิดทันที)',
      'She did nothing for them · after several failed tries the identity questions are off until $time (change the '
          'questions to reopen now)');
}
