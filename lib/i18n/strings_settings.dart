import 'strings.dart';

/// ข้อความของหน้าตั้งค่าแบบแบ่งหมวด · ไลเซนส์ · สถานะจริงของสมองในเครื่อง
extension SettingsStrings on S {
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
}
