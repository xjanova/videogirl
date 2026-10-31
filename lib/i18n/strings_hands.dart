import 'strings.dart';

/// ข้อความของงานที่เธอทำในเครื่องแทนเจ้าของ (lib/hands/)
extension HandsStrings on S {
  String get handsAck => pick('ได้ค่ะ กำลังทำให้ในเครื่องนะคะ', 'On it — doing it on your phone now.');
  String get handsDefaultWho => pick('น้องมาย', 'Mind');
  String handsTitle(String who) => pick('$who กำลังทำในเครื่องแทนคุณ', '$who is using your phone for you');
  String get handsStarting => pick('กำลังเริ่ม…', 'Starting…');
  String handsStepLine(int step, int max, String what) => pick('ขั้น $step/$max · $what', 'Step $step/$max · $what');
  String handsStepTap(String label) => pick('กด «$label»', 'Tap “$label”');
  String get handsStepTapUnnamed => pick('กดปุ่มที่ไม่มีชื่อ', 'Tap an unlabelled button');
  String handsStepLong(String label) => pick('กดค้าง «$label»', 'Long-press “$label”');
  String get handsStepType => pick('พิมพ์ข้อความ', 'Type text');
  String get handsStepSubmit => pick('กด Enter บนแป้นพิมพ์', 'Press Enter on the keyboard');
  String get handsStepScroll => pick('เลื่อนจอ', 'Scroll');
  String get handsStepBack => pick('ย้อนกลับ', 'Go back');
  String get handsStepHome => pick('กลับหน้าหลัก', 'Go home');
  String get handsStepRecents => pick('เปิดแอปล่าสุด', 'Open recent apps');
  String get handsStepNotifications => pick('เปิดแถบแจ้งเตือน', 'Open notifications');
  String handsStepOpen(String app) => pick('เปิด $app', 'Open $app');
  String get handsStepWait => pick('รอจอโหลด', 'Wait for the screen');
  String handsStepAlarm(String time) => pick('ตั้งปลุก $time', 'Set an alarm for $time');
  String get handsStepEvent => pick('เปิดหน้าเพิ่มนัดในปฏิทิน', 'Open the add-event screen');
  String get handsStepEmail => pick('เปิดหน้าเขียนอีเมล', 'Open an email draft');

  // ── ถามก่อนทำ ──
  String get handsAskTitle => pick('ให้ทำขั้นนี้ไหมคะ?', 'OK to do this?');
  String handsAskBody(String action, String app) =>
      pick('$action ใน $app', '$action in $app');
  String handsAskWhy(String why) => pick('เหตุผล: $why', 'Why: $why');
  String handsAskGoal(String goal) => pick('งานที่สั่ง: $goal', 'Task: $goal');
  String get handsAllow => pick('ทำเลย', 'Do it');
  String get handsDeny => pick('ไม่ต้อง', "Don't");

  // ── ผล ──
  String get handsDoneDefault => pick('เสร็จแล้วค่ะ', 'Done.');
  String handsFailed(String why) => why.trim().isEmpty
      ? pick('ทำไม่สำเร็จค่ะ', "I couldn't finish it.")
      : pick('ทำไม่สำเร็จค่ะ · ${why.trim()}', "I couldn't finish it · ${why.trim()}");
  String get handsStoppedMsg => pick('หยุดแล้วค่ะ ไม่ได้ทำต่อ', 'Stopped — I did not continue.');
  String handsDeclined(String action) =>
      pick('ไม่ได้ทำขั้น «$action» ตามที่บอกค่ะ หยุดงานไว้ตรงนี้', 'I did not do “$action”, as you said, and stopped there.');
  String handsStepCap(int n) =>
      pick('ทำครบ $n ขั้นแล้วยังไม่เสร็จ เลยหยุดไว้ก่อนค่ะ', 'Still not finished after $n steps, so I stopped.');
  String get handsStuck => pick('จอไม่เปลี่ยนเลย ทำต่อไม่ได้ค่ะ', 'The screen stopped changing, so I could not go on.');
  String get handsBrainFailed =>
      pick('สมองตอบไม่ได้ระหว่างทำงาน เลยหยุดไว้ค่ะ', 'My brain stopped answering mid-task, so I stopped.');
  String get handsCallCameIn => pick('มีสายเข้า เลยหยุดงานในเครื่องไว้ก่อนค่ะ ไม่ได้แตะจอรับสาย',
      'A call came in, so I stopped working on the phone and left the call screen alone.');
  String get handsNeedsPassword => pick('ขั้นนี้ต้องใส่รหัสผ่านเอง เลยหยุดไว้ให้บอสใส่ค่ะ',
      'This step needs a password, so I stopped for you to type it yourself.');
  String get handsLost =>
      pick('บริการใช้เครื่องแทนหยุดทำงานกลางทางค่ะ', 'The phone-control service stopped in the middle of the task.');

  /// เริ่มงานไม่ได้ · [reason] = รหัสจาก Android / MindState (PhoneUnavailable)
  String handsUnavailable(String reason) {
    switch (reason) {
      case 'not_enabled':
        return pick(
            'ยังใช้เครื่องแทนไม่ได้ค่ะ · ต้องเปิดบริการ "GigGok — ให้มายด์ใช้เครื่องแทน" ในหน้าการช่วยเหลือพิเศษก่อน '
                '(ตั้งค่า › ทั่วไป › ใช้เครื่องแทน) · ถ้าต่อเสียงตรงไว้แล้ว แอปจะเปิด-ปิดบริการนี้ให้เองตอนทำงาน',
            'I can\'t use the phone yet · turn on "GigGok — let Mind use the phone for you" in Accessibility first '
                '(Settings › General › Use the phone for me) · once direct call audio is connected, the app turns it on '
                'and off by itself while I work');
      case 'paused':
        return pick('ตอนนี้พักไว้ให้แอปธนาคารอยู่ค่ะ ใช้เครื่องแทนได้อีกเมื่อพักเสร็จ',
            'Paused for banking apps right now · I can use the phone again when the pause ends');
      case 'busy':
        return pick('กำลังทำงานอื่นในเครื่องอยู่ค่ะ รอเสร็จก่อนนะคะ', 'I am already doing something on the phone — wait for it to finish.');
      case 'off':
        return pick('บอสปิด "ให้ใช้เครื่องแทน" ไว้ในตั้งค่าค่ะ', '"Use the phone for me" is turned off in Settings.');
      default:
        return pick('เครื่องนี้ยังใช้เครื่องแทนไม่ได้ค่ะ', 'This phone cannot do that yet.');
    }
  }

  // ── ขั้นตอนที่สอนให้ดู (มาโคร) ──
  String macroRecordTitle(String name) => pick('น้องมายกำลังจำขั้นตอน "$name"', 'She is learning "$name"');
  String get macroSavedTitle => pick('จำขั้นตอนไว้แล้ว', 'Routine saved');
  String macroSaved(String name, int n) =>
      pick('จำขั้นตอน "$name" ไว้แล้วค่ะ ($n ขั้น) · สั่งให้ทำซ้ำได้เลย', 'Saved "$name" ($n steps) · ask me to do it any time');
  String macroEmpty(String name) => pick('ไม่ได้จำอะไรไว้สำหรับ "$name" ค่ะ ไม่มีขั้นที่ทำในแอปอื่นให้ดู',
      'Nothing was saved for "$name" — no steps were shown in another app');
  String macroGoal(String name) => pick('ทำตามขั้นตอนที่สอนไว้ "$name"', 'Do the taught routine "$name"');
  String get macroNameEmpty => pick('ตั้งชื่อขั้นตอนก่อนค่ะ', 'Give the routine a name first');
  String get macroSection => pick('ขั้นตอนที่สอนให้ดูไว้', 'Routines you showed her');
  String get macroSectionHint => pick(
      'ทำให้ดูหนึ่งรอบ แล้วสั่งให้ทำซ้ำได้ (ในแชทหรือกดทำที่นี่) · ถ้าหน้าแอปเปลี่ยนจนหาปุ่มไม่เจอ เธอจะอ่านจอทำต่อเอง · '
          'ไม่จำรหัสผ่าน และไม่จำอะไรในแอปธนาคาร',
      'Show her once, then ask her to repeat it (in chat or with Run here) · if the app changed and a button is gone, '
          'she reads the screen and carries on · passwords and banking apps are never recorded');
  String get macroNone => pick('ยังไม่ได้สอน', 'None yet');
  String get macroTeach => pick('สอนขั้นตอนใหม่', 'Teach a routine');
  String get macroNameLabel => pick('ชื่อขั้นตอน', 'Routine name');
  String get macroNameHint => pick('เช่น ส่งรายงานเช้าใน LINE', 'e.g. Morning report in LINE');
  String get macroStart => pick('เริ่มจำ', 'Start');
  String macroOverwrite(String name) => pick('มีขั้นตอน "$name" อยู่แล้ว · สอนใหม่จะทับของเดิม', '"$name" already exists · teaching again replaces it');
  String get macroOverwriteYes => pick('สอนทับ', 'Replace');
  String macroTeaching(String name) => pick(
      'กำลังจำ "$name" · ไปทำให้ดูในแอปอื่นได้เลย เสร็จแล้วกด "จำแล้ว" ในแจ้งเตือนหรือที่นี่',
      'Learning "$name" · go and do it in the other app, then tap "Done" in the notification or here');
  String get macroDone => pick('จำแล้ว', 'Done');
  String get macroCancel => pick('ยกเลิก', 'Cancel');
  String macroSteps(int n) => pick('$n ขั้น', '$n steps');
  String get macroRun => pick('ทำ', 'Run');
  String get macroDelete => pick('ลบ', 'Delete');
  String macroDeleteAsk(String name) => pick('ลบขั้นตอน "$name" ไหมคะ? ลบแล้วต้องสอนใหม่', 'Delete "$name"? You would have to teach it again.');

  // ── แชท / แถบระหว่างทำ ──
  String get handsWorking => pick('กำลังทำในเครื่อง', 'Working on your phone');
  String get handsStop => pick('หยุด', 'Stop');
  String get handsDoneNotice => pick('น้องมายทำในเครื่องเสร็จแล้ว', 'She finished on your phone');

  // ── ตั้งค่า ──
  String get handsCard => pick('ใช้เครื่องแทน', 'Use the phone for me');
  String get handsSwitch => pick('ให้น้องมายใช้เครื่องแทน', 'Let her use the phone for me');
  String get handsSwitchHint => pick(
      'สั่งในแชท เช่น "เปิด LINE ส่งหาแม่ว่าถึงบ้านแล้ว" เธอจะอ่านจอ กด และพิมพ์ให้ทีละขั้น · '
          'ก่อนส่ง จ่าย ซื้อ หรือลบ เธอถามก่อนทุกครั้ง · กดหยุดได้จากแจ้งเตือน · แอปธนาคาร แอปการเงิน และช่องรหัสผ่านแตะไม่ได้',
      'Ask in chat, e.g. "open LINE and tell Mum I am home" — she reads the screen, taps and types step by step · '
          'she always asks before sending, paying, buying or deleting · stop her any time from the notification · '
          'banking apps, finance apps and password fields are off-limits');
  String get handsStatusAuto => pick('พร้อม · แอปเปิดบริการเองตอนเธอทำงาน แล้วปิดเมื่อเสร็จ',
      'Ready · the app turns the service on while she works and off when she is done');
  String get handsStatusManual => pick('พร้อม · บริการเปิดค้างไว้ (เปิดเองในหน้าการช่วยเหลือพิเศษ)',
      'Ready · the service is left on (turned on in Accessibility)');
  String get handsStatusNeedsSetup => pick(
      'ยังไม่พร้อม · เปิดบริการ "ให้มายด์ใช้เครื่องแทน" ในหน้าการช่วยเหลือพิเศษ หรือต่อเสียงตรงครั้งหนึ่ง แล้วแอปจะเปิด-ปิดให้เอง',
      'Not ready · turn on "let Mind use the phone" in Accessibility, or connect direct call audio once and the app will turn it on and off by itself');
  String get handsStatusPaused => pick('พักอยู่ให้แอปธนาคาร', 'Paused for banking apps');
  String get handsStatusUnsupported => pick('เครื่องนี้ไม่รองรับ', 'Not supported on this phone');
  String get handsOpenA11y => pick('เปิดหน้าการช่วยเหลือพิเศษ', 'Open Accessibility');
  String get handsNotificationsOff =>
      pick('ปุ่มหยุดอยู่ในแจ้งเตือน · อนุญาตการแจ้งเตือนของ GigGok ก่อน', 'The stop button lives in a notification · allow GigGok notifications');
}
