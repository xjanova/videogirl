import 'strings.dart';

/// ข้อความของหน้าตั้งค่าแบบแบ่งหมวด · ไลเซนส์ · สถานะจริงของสมองในเครื่อง
extension SettingsStrings on S {
  String get directCallSetup => pick('ตั้งค่าเสียงตรงในสาย', 'Set up direct call audio');
  String get directCallSetupHint => pick('เชื่อมต่อกับเครื่องนี้เพื่อให้คู่สายได้ยินชัดขึ้น', 'Connect to this phone for clearer call audio');
  String get directCallTitle => pick('ต่อสายตรง', 'Direct call audio');
  String get directCallChecking => pick('กำลังตรวจ…', 'Checking…');
  String get directCallReady => pick('ต่อติดแล้ว · น้องมายพูดเข้าสายตรง ไม่ผ่านลำโพง', 'Connected · she speaks straight into the call, not through the speaker');
  String get directCallOffline => pick('ยังไม่ได้ต่อ · สายจะใช้ทางลำโพง', 'Not connected · calls use the speaker');
  String get directCallNotPaired => pick('ยังไม่เคยตั้งค่า · สายจะใช้ทางลำโพง', 'Not set up yet · calls use the speaker');
  String get directCallInCall => pick('กำลังใช้อยู่ในสาย', 'In use on the current call');
  String get directCallUnsupported => pick('เครื่องนี้ยังไม่รองรับ · สายใช้ทางลำโพง', 'This phone does not support it · calls use the speaker');
  String get directCallConnect => pick('ต่อสายตรง', 'Connect');
  String get directCallFirstSetup => pick('ตั้งค่าครั้งแรก', 'First-time setup');
  String get directCallNeedsDebugging => pick('ต่อไม่ได้ · เปิด Wi-Fi และ Wireless debugging แล้วกดอีกครั้ง', 'Could not connect · turn on Wi-Fi and Wireless debugging, then try again');
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
}
