/// ข้อความทั้งแอป เก็บไทย-อังกฤษ **คู่กันในบรรทัดเดียว**
///
/// ทำไมไม่ใช้ ARB + gen-l10n:
/// ARB แยกภาษาเป็นคนละไฟล์ ถ้าเพิ่มคีย์แล้วลืมแปลอีกภาษา โปรแกรมยัง build ผ่าน
/// แล้วผู้ใช้อังกฤษจะเจอข้อความไทยโผล่กลางจอโดยไม่มีใครรู้จนกว่าจะมีคนทัก
/// แบบนี้ `_('ไทย','English')` บังคับให้เขียนครบสองภาษาตั้งแต่ตอนพิมพ์
/// ลืมเมื่อไหร่คอมไพล์ไม่ผ่านทันที และรีวิวเห็นทั้งคู่พร้อมกัน
///
/// ข้อความที่เป็น `debugPrint` **ไม่ต้องแปล** — เป็นบันทึกของนักพัฒนา
/// ไม่ใช่ของผู้ใช้ แปลไปก็ไม่มีใครอ่าน แถมทำให้ค้น log ยากขึ้น
library;
import 'package:flutter/widgets.dart';


enum AppLang {
  th('ไทย', 'Thai', 'th'),
  en('อังกฤษ', 'English', 'en');

  const AppLang(this.thName, this.enName, this.code);

  final String thName, enName, code;

  Locale get locale => Locale(code);

  /// ชื่อภาษาในภาษาของตัวเอง — ปุ่มเลือกภาษาต้องอ่านออกไม่ว่าตอนนี้ตั้งอะไรไว้
  String get nativeName => this == AppLang.th ? 'ไทย' : 'English';

  static AppLang fromCode(String? code) =>
      code == 'en' ? AppLang.en : AppLang.th;
}

/// ตัวช่วยหยิบข้อความตามภาษาที่ใช้อยู่
///
/// ใช้ `S.of(context)` ในวิดเจ็ต และ `S(lang)` ในที่ที่ไม่มี context
/// (เช่น ตอนประกอบ system prompt ให้โมเดล)
@immutable
class S {
  const S(this.lang);

  final AppLang lang;

  static S of(BuildContext context) =>
      S(AppLang.fromCode(Localizations.localeOf(context).languageCode));

  String _(String th, String en) => lang == AppLang.th ? th : en;

  /// แบบสาธารณะของ [_] — ให้ extension ในไฟล์อื่นเรียกได้
  /// (Dart ไม่ให้ extension แตะสมาชิก private ข้ามไลบรารี)
  String pick(String th, String en) => _(th, en);

  bool get isThai => lang == AppLang.th;

  // ═══ ทั่วไป ════════════════════════════════════════════
  String get cancel => _('ยกเลิก', 'Cancel');
  String get save => _('บันทึก', 'Save');
  String get reset => _('คืนค่า', 'Reset');
  String voiceResetConfirm(String channel) => _(
        'คืนเสียงของช่อง "$channel" เป็นค่าตั้งต้น? ทั้งเสียง รุ่น และคำสั่งน้ำเสียงที่เขียนไว้จะหายไป',
        'Reset the "$channel" voice? The voice, model and tone instructions you set will be lost.',
      );
  String get resetToDefault => _('คืนค่าตั้งต้น', 'Reset to default');
  String get tapToEdit => _('แตะเพื่อแก้', 'Tap to edit');
  String get typeHere => _('พิมพ์ที่นี่…', 'Type here…');
  String lines(int n) => _('$n บรรทัด', '$n line${n == 1 ? '' : 's'}');

  // ═══ แถบนำทาง ══════════════════════════════════════════
  String get tabMind => _('มายด์', 'Mind');
  String get tabMail => _('เมล', 'Mail');
  String get tabCalendar => _('ปฏิทิน', 'Calendar');
  String get tabTimeline => _('ไทม์ไลน์', 'Timeline');
  String get tabSettings => _('ตั้งค่า', 'Settings');
  String get tabPhone => _('โทรศัพท์', 'Phone');
  String get phoneOpenFailed => _(
        'เปิดแป้นโทรไม่ได้ค่ะ ลองแตะไอคอน "โทรศัพท์" บนหน้าจอหลักของเครื่องแทนนะคะ',
        'Could not open the dialer. Try the Phone icon on your home screen instead.',
      );

  // ═══ โหมด ══════════════════════════════════════════════
  String get modeWork => _('งาน', 'Work');
  String get modeLove => _('ส่วนตัว', 'Personal');
  String get modeAuto => _('อัตโนมัติ', 'Automatic');

  String get statusWork =>
      _('ออนไลน์ · โหมดงาน · ฟังอยู่', 'Online · Work mode · Listening');
  String get statusLove =>
      _('ออนไลน์ · โหมดส่วนตัว · ฟังอยู่', 'Online · Personal mode · Listening');

  String toggleModeHint(String current) => _(
        'สลับโหมด ตอนนี้โหมด$current',
        'Switch mode, currently $current',
      );

  String get autoModeExplained => _(
        'อัตโนมัติ = ในเวลางานเธอเป็นเลขาฯ หลังสองทุ่มและวันหยุดเธอเป็นตัวเอง',
        'Automatic = a secretary during work hours, herself after 8pm and at weekends',
      );

  String nowInMode(String m) => _('ตอนนี้กำลังอยู่โหมด$m', 'Currently in $m mode');

  // ═══ ชิปคำถามลัด ═══════════════════════════════════════
  /// 🔴 ต้องเป็นสิ่งที่เธอ**ทำได้จริง**ตอนนี้ · ของเดิมคือ "สรุปเมล" (ยังไม่ได้
  /// ต่อเมล) "นัดรีวิว" (จองปฏิทินไม่ได้) "โทรหาคุณต้น" (คนสมมติ) — กดแล้ว
  /// โมเดลจะแต่งเรื่องว่าทำให้แล้ว
  List<String> get workChips => isThai
      ? const ['วันนี้มีนัดอะไรบ้าง', 'บ่ายนี้ว่างไหม', 'วันนี้ใครโทรมาบ้าง']
      : const ["What's on today", 'Am I free this afternoon', 'Who called today'];

  List<String> get loveChips => isThai
      ? const ['วันนี้เป็นไงบ้าง', 'เล่าอะไรให้ฟังหน่อย', 'คิดถึงไหม']
      : const ['How was your day', 'Tell me something', 'Did you miss me'];


  // ═══ หน้าเปิดแอป ═══════════════════════════════════════
  String get splashSkip => _('แตะเพื่อข้าม', 'Tap to skip');

  /// ขึ้นหลังวิดีโอจบ ถ้าตัวเธอยังโหลดไม่เสร็จ
  /// เปอร์เซ็นต์เป็นของจริงจากไบต์ที่โหลดมาแล้ว ไม่ใช่แถบที่วิ่งเองตามเวลา
  String splashLoading(int pct) => _('กำลังโหลด $pct%', 'Loading $pct%');

  // ═══ หน้าหลัก ══════════════════════════════════════════
  /// 🔴 ชวนกดไมค์เฉพาะตอนที่ไมค์**ใช้ได้จริง**
  ///
  /// สมองในเครื่อง (ค่าตั้งต้น) ใช้ตัวถอดเสียงในเครื่องของแอนดรอยด์ ซึ่ง
  /// เครื่องเก่ากว่า Android 12 ไม่มี และเครื่องที่ยังไม่ได้โหลดชุดภาษาก็ยัง
  /// ใช้ไม่ได้ · ชวนให้กดของที่กดแล้วไม่ได้ผล คือการพาไปเจอทางตันตั้งแต่
  /// ประโยคแรกที่เขาอ่านบนจอ
  String composerHint({required bool canSpeak}) => canSpeak
      ? _('พิมพ์ หรือกดไมค์…', 'Type, or tap the mic…')
      : _('พิมพ์ข้อความ…', 'Type a message…');

  /// แผงแชทพับแล้ว — ปุ่มที่เหลืออยู่ต้องบอกให้ชัดว่ากดแล้วได้อะไร
  /// "แตะ" เฉย ๆ ไม่พอ คนไม่รู้ว่าแตะแล้วจะเปิดอะไรขึ้นมา
  String get chatTapToOpen => _('แตะเพื่อคุยกับมายด์', 'Tap to talk to Mind');
  String get chatCollapse => _('พับแผงแชท', 'Collapse the chat');

  /// ป้ายปุ่มส่ง — ปุ่มเป็นไอคอนล้วน ตัวอ่านหน้าจอจึงไม่มีอะไรให้อ่านเลย
  String get send => _('ส่ง', 'Send');

  /// ป้ายของอนิเมชั่นตอนเธอกำลังคิด
  ///
  /// จุดสามจุดไม่มีความหมายกับคนที่ใช้ตัวอ่านหน้าจอ — ป้ายนี้คือสิ่งเดียว
  /// ที่บอกเขาว่าตอนนี้กำลังรออะไรอยู่ · และเป็นข้อความที่โผล่ในปุ่มพับด้วย
  /// ตอนแผงแชทหุบไปแล้ว ซึ่งเป็นที่เดียวที่เหลือให้เห็นในตอนนั้น
  String get thinkingLabel => _('มายด์กำลังคิด…', 'Mind is thinking…');
  /// ข้อความตอนเธอยังไม่ขึ้นเวที — เขียนด้วยภาษาคน ไม่ใช่ศัพท์ของนักพัฒนา
  /// "VRM avatar · full body" ที่เคยขึ้นตรงนี้คือชื่อรูปแบบไฟล์ ผู้ใช้ไม่ต้องรู้
  String get avatarPlaceholder => _('มายด์กำลังมา…', 'Mind is on her way…');
  String get avatarMissing =>
      _('ยังไม่ได้โหลดตัวมายด์', "Mind's pack is not downloaded yet");
  String get avatarBroken => _('ตัวมายด์โหลดไม่ขึ้นรอบนี้ — ชุดยังอยู่ในเครื่อง ไม่ต้องโหลดใหม่',
      "Mind's stage failed this time — her pack is still on the phone, no need to download it again");
  String get avatarLowMemory => _(
      'เครื่องปิดตัวมายด์ทิ้งซ้ำ ๆ เพราะหน่วยความจำไม่พอ · ปิดแอปอื่นที่เปิดค้าง หรือปิด "เปิดสมองรอไว้" แล้วลองใหม่',
      'The phone keeps closing Mind for lack of memory — close other apps or turn off "open the brain early", then retry');
  String get avatarRetry => _('ลองโหลดตัวมายด์ใหม่', 'Load Mind again');

  // ═══ ร้านของมายด์ ══════════════════════════════════════
  String get shopTitle => _('ร้านของมายด์', "Mind's shop");
  String get shopSubtitle => _(
        'ชุด ตัวละครใหม่ และของประดับเวที',
        'Outfits, new characters and stage props',
      );
  String get shopOpen => _('เปิดร้าน', 'Open shop');
  String get refresh => _('รีเฟรช', 'Refresh');

  /// ร้านยังไม่เปิด ต้องบอกให้ต่างจาก "ไม่มีของขาย" — คนละเรื่องกัน
  String get shopUnreachable => _('ยังต่อร้านไม่ได้', "Can't reach the shop");
  String get shopUnreachableWhy => _(
        'ร้านอาจยังไม่เปิด หรือยังไม่ได้ตั้งที่อยู่ร้านในหน้าตั้งค่า',
        'The shop may not be open yet, or its address is not set in Settings',
      );
  String get shopNoUrl => _('ยังไม่ได้ตั้งที่อยู่ร้าน', 'No shop address set');
  String get shopEmpty => _('ยังไม่มีของขาย', 'Nothing on sale yet');

  String get shopOwned => _('มีแล้ว', 'Owned');
  String get shopFree => _('ฟรี', 'Free');
  String get shopBuy => _('ซื้อ', 'Buy');
  String get shopGet => _('โหลดลงเครื่อง', 'Download');
  String shopPrice(String amount, String currency) => _(
        '$amount $currency',
        '$currency $amount',
      );

  /// จ่ายเงินบนเว็บ ไม่ใช่ในแอป — ต้องบอกล่วงหน้าว่าจะเด้งออกไป
  String get shopBuyOnWeb => _(
        'จ่ายเงินบนเว็บ แล้วกลับมากดรีเฟรช',
        'Pay on the web, then come back and refresh',
      );
  String get shopBuyFailed => _(
        'เปิดหน้าซื้อไม่ได้ — ลองเช็คว่ามีเบราว์เซอร์ในเครื่องและต่อเน็ตอยู่',
        "Couldn't open the shop page — check there is a browser and you're online",
      );

  String shopKind(String kind) => switch (kind) {
        'outfit' => _('ชุดแต่งตัว', 'Outfit'),
        'prop' => _('ของประดับเวที', 'Stage prop'),
        _ => _('ตัวละคร', 'Character'),
      };

  // ═══ ความจำ ════════════════════════════════════════════
  /// ป้ายชื่อผู้พูดตอนประกอบบทสนทนาให้โมเดลอ่านตอนสกัดความจำ
  /// อยู่ที่นี่เพราะโมเดลอ่านภาษาที่ผู้ใช้ตั้งไว้ ไม่ใช่ไทยเสมอ
  String get speakerMe => _('เจ้าของ', 'Owner');
  String get speakerHer => _('มายด์', 'Mind');

  String get memTitle => _('สิ่งที่มายด์จำได้', 'What Mind remembers');
  String memCount(int n) => _('จำไว้ $n เรื่อง', '$n things remembered');
  String get memEmpty => _(
        'ยังไม่ได้จำอะไร — คุยกันสักพักแล้วเธอจะเริ่มจำเอง',
        'Nothing yet — talk for a while and she will start remembering',
      );

  /// ต้องบอกให้ชัดว่าเธอสรุปเอง ไม่ใช่ของที่เจ้าของยืนยัน
  String get memWhy => _(
        'เธอสรุปเองจากที่เคยคุยกัน แก้หรือลบได้ทุกข้อ '
        'รหัสผ่าน เลขบัตร และ OTP จะไม่ถูกจำ',
        'Her own summaries from past conversations — edit or delete any of them. '
        'Passwords, card numbers and OTPs are never remembered.',
      );
  String get memPin => _('ปักหมุด', 'Pin');
  String get memPinned => _('ปักหมุดแล้ว', 'Pinned');
  String get memPinWhy =>
      _('ปักหมุดแล้วจะไม่ถูกตัดทิ้งตอนความจำเต็ม', 'Pinned items are never evicted');
  String get memForget => _('ลืมเรื่องนี้', 'Forget this');
  String get memForgetAll => _('ลืมทั้งหมด', 'Forget everything');
  String get memForgetAllConfirm => _(
        'ให้มายด์ลืมทุกอย่างที่จำมาเลยไหมคะ กู้คืนไม่ได้นะ',
        'Make Mind forget everything she has learned? This cannot be undone.',
      );
  String get memEdit => _('แก้ข้อความ', 'Edit');

  String memKind(String kind) => switch (kind) {
        'preference' => _('รสนิยม', 'Preference'),
        'routine' => _('กิจวัตร', 'Routine'),
        'person' => _('คนรอบตัว', 'People'),
        _ => _('ข้อเท็จจริง', 'Fact'),
      };

  // ═══ สิทธิ์ ════════════════════════════════════════════
  String get permTitle => _('สิทธิ์ที่มายด์ต้องใช้', 'Permissions Mind needs');
  String get permAllSet => _('ให้ครบแล้ว ขอบคุณค่ะ', 'All set — thank you');
  String permMissing(int n) =>
      _('ยังขาดอีก $n อย่าง', '$n still missing');
  String get permGrant => _('อนุญาต', 'Allow');
  String get permGrantAll => _('อนุญาตทั้งหมด', 'Allow everything');
  String get permOk => _('ให้แล้ว', 'Granted');
  String get permNo => _('ยังไม่ได้ให้', 'Not granted');

  /// ปฏิเสธถาวรแล้ว กล่องขอไม่ขึ้นอีก — ต้องบอกทางไปให้ชัด
  /// ไม่งั้นผู้ใช้จะกดปุ่มอนุญาตซ้ำ ๆ แล้วงงว่าทำไมไม่มีอะไรเกิดขึ้น
  String get permBlocked => _(
        'ปฏิเสธถาวรไปแล้ว กล่องขอจะไม่ขึ้นอีก ต้องไปเปิดในตั้งค่าของเครื่อง',
        'Permanently denied — the prompt will not appear again. '
        'Turn it on in system settings.',
      );

  /// ตัวที่ต้องออกไปหน้าตั้งค่าของระบบ ไม่ใช่กล่องในแอป — บอกล่วงหน้า
  /// ไม่งั้นคนจะตกใจว่าทำไมแอปเด้งออกไปที่อื่น
  String get permGoesToSettings =>
      _('จะพาไปหน้าตั้งค่าของเครื่อง', 'Opens system settings');

  String get permCamera => _('กล้องหน้า', 'Front camera');
  String get permCameraWhy => _(
        'โหมดหุ่นเชิด — ภาพไม่ออกจากเครื่อง',
        'Puppet mode — video never leaves this device',
      );
  String get permMic => _('ไมโครโฟน', 'Microphone');
  String get permMicWhy =>
      _('พูดกับเธอ และอัดเสียงตอนโคลนเสียง', 'Talk to her, and record for voice cloning');
  String get permNotify => _('การแจ้งเตือน', 'Notifications');
  String get permNotifyWhy => _(
        'Android บังคับว่าบริการเบื้องหลังต้องมีการแจ้งเตือน ไม่ให้ = เธอเฝ้างานไม่ได้',
        'Android requires a notification for background work — without it she cannot watch',
      );
  String get permBattery => _('ยกเว้นการประหยัดแบต', 'Exempt from battery saver');
  String get permPhone => _('สายโทรเข้า', 'Phone calls');
  String get permPhoneWhy => _(
        'รู้ว่าใครโทรมาและอ่านประวัติการโทร · ต้องได้ทั้งสองอย่างคู่กัน '
        'ไม่งั้น Android จะไม่บอกเบอร์ผู้โทรเลย',
        'See who is calling and read call history — both are needed together, '
        'or Android hides the caller number entirely',
      );
  String get permContacts => _('สมุดโทรศัพท์', 'Contacts');
  /// 🔴 เดิมเขียนว่า "ไม่ส่งออกจากเครื่อง" · ตอนนี้เธอเปิดสมุดให้ตอนถามในแชท และถ้าใช้
  /// สมองบนคลาวด์ บรรทัดที่เปิดดูไปกับข้อความนั้น · ต้องบอกตรง ๆ ไม่ใช่สัญญาที่ไม่จริง
  String get permContactsWhy => _(
        'เปลี่ยนเบอร์เป็นชื่อคน และให้เธอหาเบอร์ให้ตอนถาม · อ่านอย่างเดียว ไม่แก้ · '
        'ถ้าใช้สมองบนคลาวด์ จะส่งไปเฉพาะรายชื่อที่เธอเปิดดูในคำถามนั้น',
        'Turns numbers into names and lets her find a number when you ask — read-only, never edited · '
        'with a cloud brain, only the entries she looks up go out with that message',
      );
  String get permSms => _('ข้อความ SMS', 'Text messages (SMS)');
  String get permSmsWhy => _(
        'ให้เธอเล่า SMS ที่เข้ามาหรือส่งออกตอนคุณถาม · อ่านอย่างเดียว ไม่ส่ง ไม่ลบ · '
        'ซ่อนรหัส OTP ไว้เสมอ · ถ้าใช้สมองบนคลาวด์ จะส่งไปเฉพาะข้อความที่เธอเปิดดูในคำถามนั้น',
        'Lets her tell you about texts you got or sent when you ask — read-only, never sends or deletes · '
        'one-time codes always hidden · with a cloud brain, only the texts she looks up go out with that message',
      );
  String get permAnswer => _('รับสายแทน', 'Answer calls');
  String get permAnswerWhy => _(
        'รับหรือวางสายให้ได้ · เธอยังพูดในสายไม่ได้ ต้องตั้งแอปนี้เป็น '
        'แอปโทรศัพท์หลักก่อน ซึ่งยังไม่ได้ทำ',
        'Lets her pick up or hang up. She cannot speak on the line yet — '
        'that needs this app set as the default phone app, which is not built.',
      );
  String get permDialer => _('เป็นแอปโทรศัพท์หลัก', 'Be the phone app');

  /// 🔴 ต้องบอกให้ครบว่า**เปลี่ยนทั้งเครื่อง** ไม่ใช่แค่เปิดฟีเจอร์
  /// และต้องบอกด้วยว่าสิ่งที่คนคาดหวังที่สุด (เธอคุยแทน) ยังทำไม่ได้
  String get permDialerWhy => _(
        'ทุกสายของเครื่องจะผ่านแอปนี้ — จอสายเป็นของมายด์ รับ วาง ปิดไมค์ '
        'สลับลำโพงได้ · เธอพูดเข้าสายด้วยการต่อสายตรงในหน้าตั้งค่า · '
        'ถอนคืนได้ตลอดจากหน้าตั้งค่าของเครื่อง',
        'Every call on this phone goes through this app — Mind owns the call '
        'screen and can answer, hang up, mute and switch to speaker. She talks '
        'into the call through direct call audio in Settings. '
        'You can undo this any time in the phone settings.',
      );
  String get permA11y => _('ให้มายด์ได้ยินสาย (การช่วยเหลือพิเศษ)', 'Let Mind hear calls (Accessibility)');

  /// 🔴 ต้องบอกให้ตรงว่าเปิดไปได้อะไร และ**ไม่ได้**อะไร · คำว่า "การช่วยเหลือพิเศษ"
  /// ทำให้คนกลัวว่าแอปจะอ่านจอ ซึ่งตัวนี้ไม่ทำ
  String get permA11yWhy => _(
        'Android ให้แอปได้ยินแต่ความเงียบระหว่างมีสาย ยกเว้นแอปที่เปิดบริการนี้ · ไม่เปิด = เธอรับสายทักได้ '
        'แต่ไม่ได้ยินคนโทรมาเลย · เปิดที่ การช่วยเหลือพิเศษ → แอปที่ดาวน์โหลด → GigGok · '
        'ไม่อ่านหน้าจอ ไม่กดอะไรแทนคุณ',
        'Android gives apps only silence during a call unless they run this service · without it she can greet '
        'but never hears the caller · turn it on in Accessibility → Downloaded apps → GigGok · '
        'it does not read your screen or act for you',
      );
  String get permCalendar => _('ปฏิทิน', 'Calendar');
  String get permCalendarWhy => _(
        'อ่านตารางนัดของคุณ อ่านอย่างเดียว ไม่แก้ไม่ลบ และไม่ส่งออกจากเครื่อง',
        'Reads your schedule — read-only, never edited, never leaves this device',
      );
  String get permInstall => _('ติดตั้งแอปที่ไม่รู้จัก', 'Install unknown apps');

  /// ต้องอธิบายว่าทำไมต้องให้**ก่อน** ไม่ใช่ตอนจะติดตั้ง
  String get permInstallWhy => _(
        'อัปเดตในตัวต้องใช้ ไม่ให้ไว้ก่อน = โหลดไฟล์จนจบแล้วค่อยล้มตอนติดตั้ง',
        'The built-in updater needs this — without it the download finishes '
        'and only then fails at the install step',
      );

  String get permAllFiles => _('ไฟล์ทั้งเครื่อง', 'All files on this phone');

  /// 🔴 ต้องบอกให้ชัดว่าขอไปทำอะไร **และไม่ได้ทำอะไร**
  ///
  /// สิทธิ์นี้ฟังดูน่ากลัวกว่าทุกตัวในรายการ (มันแรงจริง) คนที่อ่านแล้วไม่รู้ว่า
  /// เอาไปทำอะไรจะกดปฏิเสธ ซึ่งถูกต้องแล้ว · หน้าที่ของข้อความนี้คือบอกว่า
  /// แลกอะไรกับอะไร ไม่ใช่กล่อมให้กด
  String get permAllFilesWhy => _(
        'เก็บสำเนาข้อมูลไว้นอกพื้นที่แอป ลงแอปใหม่แล้วทุกอย่างกลับมาเอง\n'
        'ของในเครื่องทั้งหมดถูกล้างตอนถอนแอป ไม่มีทางอื่นที่รอดได้\n'
        'เขียนแค่โฟลเดอร์ GigGok ของตัวเอง ไม่ไปยุ่งกับไฟล์ของใคร',
        'Keeps a copy outside the app so a reinstall brings everything back.\n'
        'Everything inside the app is wiped on uninstall — there is no other way.\n'
        'It only writes its own GigGok folder, and touches nobody else’s files.',
      );

  // ═══ ข้อมูลกับการสำรอง ══════════════════════════════════
  String get dataTitle => _('ข้อมูลของมายด์', "Mind's data");
  String get dataSubtitle => _(
        'บทสนทนา ความจำ ไทม์ไลน์ และค่าที่ตั้งไว้ทั้งหมด',
        'Conversations, memories, timeline and every setting',
      );

  /// สวิตช์ที่เจ้าของสั่งไว้ — ค่าตั้งต้นคือ **ไม่ติ๊ก** = ข้อมูลรอด
  String get wipeOnUninstall =>
      _('ลบข้อมูลทั้งหมดเมื่อถอนแอป', 'Delete everything when the app is uninstalled');
  String get wipeOnUninstallWhy => _(
        'ติ๊กแล้วสำเนาข้างนอกถูกลบทันที ไม่ใช่รอถึงวันถอนแอป — '
        'เพราะวันนั้นไม่มีโค้ดของเราวิ่งอยู่แล้วที่จะไปลบให้ได้',
        'Ticking this deletes the outside copy right away, not on the day you '
        'uninstall — by then none of our code is running to do it.',
      );

  String get vaultReady => _('สำเนาพร้อม ลงใหม่แล้วข้อมูลกลับมาเอง',
      'Copy is in place — a reinstall brings everything back');
  String vaultSavedAt(String when) =>
      _('สำเนาล่าสุด $when', 'Last copied $when');
  String get vaultNeedsPermission => _(
        'ยังไม่ได้ให้สิทธิ์ไฟล์ทั้งเครื่อง — ตอนนี้ถอนแอปแล้วข้อมูลหายหมด',
        'No all-files permission yet — right now an uninstall loses everything',
      );
  String get vaultOff => _(
        'ปิดไว้ตามที่เลือก — ถอนแอปแล้วข้อมูลหายหมด',
        'Off, as you chose — an uninstall loses everything',
      );
  String get vaultFailed => _(
        'เขียนสำเนาไม่สำเร็จ · ลองเช็คพื้นที่ว่างในเครื่อง',
        'Could not write the copy — check the free space on this phone',
      );
  String get vaultSaveNow => _('สำเนาเดี๋ยวนี้', 'Copy now');
  String get vaultForeign => _(
        'เจอข้อมูลของการติดตั้งครั้งก่อนในเครื่อง — ยังไม่ได้เขียนทับ '
            'เลือกก่อนว่าจะเอาอันไหน',
        'Found the data from a previous install on this phone — nothing has '
            'been overwritten. Choose which one to keep.',
      );
  String get vaultRestoreOld =>
      _('กู้ข้อมูลเก่ากลับมา', 'Bring back the old data');
  String get vaultKeepCurrent =>
      _('ใช้ข้อมูลตอนนี้แทน', 'Keep what is here now');
  String get vaultRestoreTitle =>
      _('กู้ข้อมูลเก่ากลับมา?', 'Bring back the old data?');
  String get vaultRestoreBody => _(
        'บทสนทนา ความจำ และค่าที่ตั้งไว้ตอนนี้จะถูกแทนด้วยของเก่าทั้งหมด '
            'แอปจะปิดตัว — เปิดใหม่อีกครั้งเพื่อให้กู้เสร็จ',
        'The chats, memories and settings here now will be replaced by the old '
            'ones. The app will close — open it again to finish restoring.',
      );
  String get vaultKeepTitle =>
      _('ใช้ข้อมูลตอนนี้แทน?', 'Keep what is here now?');
  String get vaultKeepBody => _(
        'สำเนาจะเป็นของตอนนี้แทน · ของเก่าไม่ถูกลบ ย้ายไปเก็บเป็นไฟล์ '
            'mind.db.previous ในโฟลเดอร์ GigGok',
        'The copy will hold what is here now. The old one is not deleted — '
            'it is kept as mind.db.previous in the GigGok folder.',
      );
  String get vaultRestored => _(
        'กู้ข้อมูลกลับมาจากสำเนาแล้ว',
        'Restored everything from the outside copy',
      );

  String messagesKept(int n) =>
      _('เก็บบทสนทนาไว้ $n ข้อความ', '$n messages kept');

  // ═══ รายงานดีบัคให้ผู้พัฒนา ══════════════════════════════
  String get debugTitle => _('ส่งข้อมูลให้ผู้พัฒนา', 'Send data to the developer');
  String get debugSubtitle => _(
        'ช่วยหาสาเหตุตอนมีอะไรไม่ทำงาน',
        'Helps track down what is not working',
      );

  /// 🔴 บอกว่า **ไม่ส่ง**อะไร ก่อนบอกว่าส่งอะไร
  ///
  /// คนที่ลังเลกับปุ่มนี้ลังเลเพราะกลัวว่าบทสนทนาจะหลุด ไม่ใช่เพราะอยากรู้ว่า
  /// เราเก็บรุ่นแอปไปด้วยไหม · ตอบคำถามที่เขาถามจริงก่อน
  String get debugWhat => _(
        'ไม่ส่ง: บทสนทนา ความจำ ไทม์ไลน์ คีย์ รหัสสิทธิ์ เบอร์โทร ชื่อคน\n'
        'ส่ง: รุ่นแอป รุ่นแอนดรอยด์ แรม ตัวเลือกที่ตั้งไว้ ข้อความผิดพลาด '
        'จำนวน (ไม่ใช่เนื้อหา) และบันทึกการทำงานล่าสุดที่ล้างความลับแล้ว',
        'Never sent: conversations, memories, timeline, keys, license code, '
        'phone numbers, names\n'
        'Sent: app version, Android version, RAM, the options you picked, '
        'error messages, counts (not content), and recent logs with secrets '
        'stripped out',
      );

  /// ย้ำว่าเห็นก่อนเสมอ — เป็นข้อที่ทำให้คนกล้ากดจริง
  String get debugPreviewFirst => _(
        'กดดูได้ทั้งฉบับก่อนส่ง · ที่เห็นคือสิ่งที่ส่งจริง ไม่ใช่ตัวอย่าง',
        'You can read the whole thing first — what you see is exactly what is sent',
      );

  // ── ส่งเอง ──
  String get debugAuto =>
      _('ส่งรายงานเองเมื่อมีข้อผิดพลาด', 'Send a report automatically on errors');

  /// 🔴 บอกให้ครบว่ามันทำอะไร **และไม่ทำอะไร**
  ///
  /// ของที่ส่งออกเน็ตเองต้องอธิบายตัวเองให้ชัดกว่าของที่ผู้ใช้กดเอง เพราะ
  /// เขาไม่ได้อยู่ตรงนั้นตอนมันทำงาน
  String get debugAutoWhy => _(
        'ส่งเฉพาะตอนมีอะไรพังจริง ไม่ใช่ตลอดเวลา · ข้อความเดิมไม่ส่งซ้ำ '
        'และส่งได้มากสุด 5 ฉบับต่อการเปิดแอปหนึ่งครั้ง\n'
        'เนื้อรายงานเหมือนกับที่กดดูได้ด้านล่างทุกอย่าง',
        'Only when something actually breaks — not continuously. The same '
        'error is never sent twice, and at most 5 reports per app run.\n'
        'The contents are exactly what you can read below.',
      );

  String debugAutoSentAt(String when) =>
      _('ส่งเองล่าสุด $when', 'Last auto-sent $when');
  String get debugAutoNever =>
      _('ยังไม่ได้ส่งเอง (ยังไม่มีอะไรพัง)', 'Nothing auto-sent yet — nothing has broken');

  String get debugBuild => _('เตรียมรายงาน', 'Prepare a report');
  String get debugPreview => _('ดูก่อนส่ง', 'Read it first');
  String get debugSend => _('ส่งให้ผู้พัฒนา', 'Send to the developer');
  String get debugSave => _('บันทึกเป็นไฟล์', 'Save as a file');
  String get debugSending => _('กำลังส่ง…', 'Sending…');
  String get debugSent => _('ส่งแล้ว ขอบคุณค่ะ', 'Sent — thank you');
  String debugSaved(String path) => _('บันทึกไว้ที่ $path', 'Saved to $path');
  String get debugNoBase =>
      _('ยังไม่ได้ตั้งที่อยู่หลังบ้าน', 'No server address is set');
  String debugSendFailed(int code) =>
      _('ส่งไม่สำเร็จ ($code)', 'Sending failed ($code)');
  String get debugOffline =>
      _('ส่งไม่สำเร็จ · ต่อเน็ตไม่ได้', 'Sending failed — cannot reach the internet');

  String get debugNoReport =>
      _('ยังไม่ได้เตรียมรายงาน', 'No report prepared yet');

  /// หลังบ้านยังไม่มีปลายทางนี้ — คนละเรื่องกับ "ส่งไม่ผ่าน"
  String get debugNoEndpoint => _(
        'หลังบ้านยังไม่เปิดรับรายงาน · บันทึกเป็นไฟล์แล้วส่งทางอื่นได้',
        'The server is not accepting reports yet — save the file and send it another way',
      );

  // ═══ เฝ้างานเบื้องหลัง ══════════════════════════════════
  String get bgTitle => _('ให้เธอเฝ้างานตอนปิดแอป', 'Let her watch while the app is closed');

  /// ต้องบอกตรง ๆ ว่าแลกอะไร — การแจ้งเตือนค้างจอเป็นสิ่งที่ Android บังคับ
  /// ไม่ใช่สิ่งที่เราเลือกใส่ ถ้าไม่อธิบายผู้ใช้จะคิดว่าแอปหน้าด้าน
  String get bgWhy => _(
        'Android บังคับให้บริการที่ไม่ถูกฆ่าต้องมีการแจ้งเตือนค้างไว้ '
        'ปิดสวิตช์นี้แล้วเธอจะทำงานเฉพาะตอนเปิดแอปเท่านั้น',
        'Android requires a permanent notification for a service it will not kill. '
        'Turn this off and she only works while the app is open.',
      );
  String get bgWatching => _('กำลังเฝ้างานให้', 'Watching things for you');
  String bgUpdateFound(String v) => _('มีรุ่นใหม่ $v', 'Version $v is out');
  String get bgNeverRan => _('ยังไม่เคยตื่นมาทำงาน', 'Has not run yet');
  String bgLastBeat(String ago) => _('ตื่นมาดูงานล่าสุด $ago', 'Last check $ago');
  String bgBeats(int n) => _('รวม $n ครั้ง', '$n checks so far');

  /// ต้องพูดให้ชัดว่าถ้าไม่ยกเว้น ระบบจะหรี่ให้เอง ไม่งั้นผู้ใช้จะโทษแอป
  String get bgBatteryTitle => _('ยกเว้นการประหยัดแบต', 'Exempt from battery saver');
  String get bgBatteryWhy => _(
        'ถ้าไม่ยกเว้น Android จะหรี่ให้เธอตื่นทุก 9–15 นาทีแทนที่จะเป็น 5 '
        'และบางรุ่น (Xiaomi Huawei OPPO) ฆ่าทิ้งเลย',
        'Without this, Android throttles her to every 9–15 minutes instead of 5 — '
        'and some phones (Xiaomi, Huawei, OPPO) kill her outright.',
      );
  String get bgBatteryOn => _('ยกเว้นแล้ว', 'Exempted');
  String get bgBatteryOff => _('ยังไม่ได้ยกเว้น', 'Not exempted yet');
  String get bgBatteryAsk => _('ขอยกเว้น', 'Ask for exemption');

  String agoMinutes(int m) => _('$m นาทีที่แล้ว', '$m min ago');
  String agoHours(int h) => _('$h ชั่วโมงที่แล้ว', '$h hr ago');
  String get agoJustNow => _('เมื่อครู่นี้', 'just now');

  // ═══ ชุดตัวมายด์ (โหลดทีหลัง) ══════════════════════════
  String get packTitle => _('ชุดตัวมายด์', "Mind's outfits");

  /// ต้องอธิบายว่าทำไมไม่ฝังมาให้เลย ไม่งั้นดูเหมือนแอปโหลดไม่ครบ
  String get packWhy => _(
        'โมเดลกับคลิปท่าทางไม่ได้ฝังมาในแอป เพราะคลิปเป็นของ Mixamo ที่แจกต่อไม่ได้ '
        'โหลดครั้งเดียวแล้วอยู่ในเครื่องเลย',
        'The model and motion clips are not bundled — the clips belong to Mixamo '
        'and cannot be redistributed. Download once and it stays on this device.',
      );
  String get packMissing =>
      _('ยังไม่มีในเครื่อง เธอจะขึ้นเป็นกรอบแทน', 'Not here yet — she shows as a placeholder');
  String get packReady => _('พร้อมใช้แล้ว', 'Ready');
  String get packInstalled => _('ชุดที่มีในเครื่อง', 'Installed');
  String get packAdd => _('เพิ่มชุดใหม่', 'Add a pack');
  String get packWearing => _('ใส่อยู่', 'Wearing');
  String get packKindCharacter => _('ตัวละคร', 'Character');
  String get packKindOutfit => _('ชุดแต่งตัว', 'Outfit');
  String packRemoveConfirm(String name) =>
      _('ลบ "$name" ออกจากเครื่องไหมคะ', 'Remove "$name" from this device?');

  String get packMissingHint =>
      _('ไปที่ตั้งค่า → ชุดตัวมายด์ เพื่อโหลด',
        "Settings → Mind's outfits to download");
  String get packDownload => _('โหลดชุด', 'Download pack');
  String get packRemove => _('ลบออกจากเครื่อง', 'Remove from device');
  String get packUrlLabel => _('ที่อยู่ไฟล์ .zip ของชุด', 'URL of the pack .zip');
  String get packDownloading => _('กำลังโหลด', 'Downloading');
  String get packVerifying => _('กำลังตรวจไฟล์', 'Checking the file');
  String get packUnpacking => _('กำลังแตกไฟล์', 'Unpacking');

  String get packErrNoUrl =>
      _('ยังไม่ได้ตั้งที่อยู่ของชุด', 'No pack address set yet');
  String get packErrNetwork =>
      _('โหลดไม่สำเร็จ ลองใหม่อีกครั้งนะคะ', "Download failed — please try again");
  String get packErrHash => _(
        'ไฟล์ไม่ตรงกับที่ประกาศไว้ อาจโหลดมาไม่ครบ',
        "The file does not match its checksum — it may be incomplete",
      );
  String get packErrBadPack =>
      _('ในไฟล์ไม่มีโมเดล น่าจะแพ็กผิดโครง', 'No model inside — the pack looks wrong');
  String get packErrServer =>
      _('เปิดที่เก็บชุดในเครื่องไม่ได้', "Could not open the local pack store");

  // ═══ กล้องเชิดหุ่น ═════════════════════════════════════
  String get puppetMode => _('โหมดหุ่นเชิด', 'Puppet mode');
  String get puppetStart => _('เชิดมายด์ด้วยหน้าคุณ', 'Puppet Mind with your face');
  String get puppetStop => _('เลิกเชิด', 'Stop puppeteering');

  /// ช่วงเก็บค่าฐาน — ต้องบอกให้ชัดว่า "นิ่ง" ไม่ใช่แค่ "รอ"
  /// ถ้าขึ้นแค่วงกลมหมุน คนจะขยับหน้าไปเรื่อย แล้วค่าฐานจะเพี้ยนทั้งเซสชัน
  String get puppetCalibrating =>
      _('นั่งนิ่ง ๆ หน้าตรงแป๊บนึงนะคะ มายด์กำลังจำหน้าปกติของคุณ',
        'Hold still and look straight ahead — learning your resting face');
  String get puppetRecalibrate => _('จำหน้าใหม่', 'Re-learn my face');

  // ── ระยะกล้องตอนเชิดหุ่น ──
  //
  // 🔴 ป้ายต้องไม่ทำให้เข้าใจว่า "เต็มตัว" = จับทั้งตัว
  //
  // ที่จับได้จริงคือ**ใบหน้าเท่านั้น** ทั้งสามโหมด (FaceLandmarker ล้วน
  // ไม่มี PoseLandmarker) สามโหมดต่างกันที่ระยะกล้อง · ชื่อโหมดพูดแทน
  // ความจริงข้อนี้ไม่ได้ จึงต้องมีบรรทัดบอกใต้ปุ่ม
  String get puppetShot => _('ระยะกล้องตอนเชิด', 'Shot while puppeteering');
  String get puppetShotFace => _('หน้า', 'Face');
  String get puppetShotBust => _('ครึ่งตัว', 'Half');
  String get puppetShotFull => _('เต็มตัว', 'Full');

  /// บอกความจริงว่าจับอะไรได้จริง — ก่อนที่เขาจะเลือกเต็มตัวแล้วผิดหวัง
  String get puppetShotNote => _(
        'ทั้งสามโหมดจับใบหน้าอย่างเดียว (ปาก ตา สายตา อารมณ์ ท่าหัว) '
        'ต่างกันที่ระยะกล้อง · ลำตัวกับแขนเล่นท่าของเธอเอง',
        'All three capture the face only — mouth, eyes, gaze, mood, head pose. '
        'They differ in how close the camera sits; her body and arms keep '
        'playing her own clips.',
      );

  /// ล็อกกล้องไว้ระหว่างเชิด
  String get puppetShotLocked => _(
        'กล้องล็อกไว้ระหว่างเชิด จะได้ไม่ถูกดึงออกตอนเธอพูด',
        'The camera is pinned while you puppet her, so speaking cannot pull it away',
      );
  String get puppetNoFace =>
      _('มายด์ไม่เห็นหน้าคุณในกล้องค่ะ', "I can't see your face");
  String get puppetStarting => _('กำลังเปิดกล้อง…', 'Starting the camera…');
  String get puppetDenied =>
      _('ต้องอนุญาตให้ใช้กล้องก่อนนะคะ', 'Camera permission is needed');
  String get puppetBlocked => _(
        'กล้องถูกปิดไว้ ต้องไปเปิดในตั้งค่าของเครื่องก่อน',
        'Camera is blocked — turn it on in system settings',
      );
  String get puppetFailed =>
      _('เปิดกล้องไม่สำเร็จค่ะ', "Couldn't start the camera");
  String get openSettings => _('เปิดตั้งค่า', 'Open settings');

  /// ต้องบอกเสมอที่จุดที่ขอกล้อง ไม่ใช่ซ่อนไว้ในหน้า privacy ที่ไม่มีใครเปิด
  String get puppetPrivacy => _(
        'ภาพจากกล้องไม่ออกจากเครื่องนี้ ประมวลผลในแอปแล้วเหลือแค่ค่าการขยับหน้า',
        'Video never leaves this device — it becomes face movement numbers here',
      );

  // ═══ บทสนทนาตัวอย่าง ═══════════════════════════════════
  // 🔴 ต้องเป็นเรื่องจริง · ของเดิมคือ "เมล 24 ฉบับ" กับ "คุณต้นขอเลื่อนรีวิว"
  // ซึ่งผู้ใช้ใหม่อ่านว่าเธอรู้เมลและนัดของเขาแล้ว ทั้งที่ไม่มีสักอย่างจริง
  String get seedGreeting => _(
        'สวัสดีค่ะ มายด์เองนะคะ ยินดีที่ได้รู้จักค่ะ',
        "Hi, I'm Mind. Nice to meet you.",
      );
  String get seedAsk => _('ช่วยอะไรได้บ้าง', 'What can you help with?');
  String get seedAnswer => _(
        'ถามเรื่องนัดในปฏิทิน สายที่โทรเข้ามา หรือคุยเล่นกันก็ได้ค่ะ '
            'เล่าเรื่องตัวเองไว้ในหน้าตั้งค่า มายด์จะช่วยได้ตรงขึ้นนะคะ',
        'Ask me about your calendar or the calls you get, or just chat. '
            'Tell me about yourself in Settings and I can help better.',
      );

  /// คำตอบตอนสมองล้มจริง — **ห้ามหน้าตาเหมือนตอบสำเร็จ**
  ///
  /// เธอต้องบอกว่าไม่ได้คิดให้จริง ๆ พร้อมเหตุผลที่พอเอาไปแก้ได้
  /// ไม่ใช่ตอบ "จัดการให้แล้ว" ทั้งที่ไม่มีอะไรถูกส่งออกไปเลย
  String brainFailedReply(String why) => _(
        'ขอโทษค่ะ มายด์คิดให้ไม่ได้ตอนนี้ — $why',
        "Sorry, I couldn't think that through right now — $why",
      );

  String get cannedWork => _(
        'รับทราบค่ะ มายด์จัดการให้แล้วจะสรุปกลับมานะคะ',
        'On it. I will take care of it and report back.',
      );
  String get cannedLove => _(
        'ได้เลยค่ะ… แต่ขอค่าจ้างเป็นคำชมสักคำนะคะ',
        'Of course… but I want a compliment as payment.',
      );

  // ═══ ระดับการจีบ ═══════════════════════════════════════
  String get flirtTitle => _('ระดับการแซว / จีบ', 'Teasing / flirting level');
  String get flirtLow => _('ทางการล้วน', 'Strictly formal');
  String get flirtHigh => _('หวานจัด', 'Very sweet');
  String get flirtNote => _(
        'ตัวอย่างน้ำเสียงที่ระดับนี้ · ในโหมดงานจะลดลงอัตโนมัติ',
        'How she sounds at this level · automatically toned down in work mode',
      );

  String flirtSample(double level) {
    if (level < .2) {
      return _('ประชุมบ่ายสามค่ะ', 'Your meeting is at 3pm.');
    }
    if (level < .45) {
      return _('ประชุมบ่ายสามนะคะ อย่าลืมเตรียมสไลด์ด้วยค่ะ',
          'Meeting at 3pm — do not forget the slides.');
    }
    if (level < .75) {
      return _('ประชุมบ่ายสามนะคะ… อย่าลืมกินข้าวก่อนด้วยล่ะ',
          'Meeting at 3pm… and please eat something first.');
    }
    return _('ประชุมบ่ายสามนะคะ… อย่าลืมกินข้าวก่อนด้วยล่ะ เดี๋ยวมายด์งอน',
        'Meeting at 3pm… eat something first, or I will sulk.');
  }

  // ═══ ฟองคำพูด ══════════════════════════════════════════
  String get bubbleTitle => _('ฟองคำพูดเหนือหัวเธอ', 'Speech bubble');

  // ═══ ระยะกล้องบนเวที ═══════════════════════════════════
  String get stageShotTitle => _('ระยะกล้องบนเวที', 'Camera on the stage');
  String stageShotLabel(String shot) => switch (shot) {
        'face' => _('ใกล้หน้า', 'Face'),
        'bust' => _('ครึ่งตัว', 'Half body'),
        'full' => _('เต็มตัว', 'Full body'),
        _ => _('อัตโนมัติ', 'Automatic'),
      };
  String get stageShotNote => _(
        'ขนาดเธอคงที่ตลอด · แผงแชทหรือคีย์บอร์ดขึ้นจะบังส่วนล่างแทนการย่อตัวเธอ · '
            '"อัตโนมัติ" = ซูมเข้าตอนเธอพูด ถอยออกตอนเงียบ',
        'She stays the same size · the chat panel or keyboard covers her lower half instead of shrinking her · '
            '"Automatic" = zooms in while she talks, out when she is quiet',
      );
  String get bubbleEnabled => _('ให้มีฟองคำพูด', 'Show the speech bubble');
  String get bubbleHint => _(
        'ฟองลอยทับตัวเธอ ถ้าค้างไว้ตลอดก็บังหน้าเธอตลอด',
        'It floats over her — left up permanently, it covers her face permanently',
      );
  String get bubbleDuration => _('จางหายหลังจาก', 'Fade out after');
  String get bubbleStay => _('ค้างไว้', 'Keep it');
  String bubbleSeconds(int s) => _('$s วิ', '${s}s');
  String get bubbleStayNote => _(
        'ฟองจะค้างอยู่จนกว่าเธอจะพูดใหม่ — บังหน้าเธอตลอดเวลา',
        'The bubble stays until she speaks again — covering her face the whole time',
      );
  String bubbleFadeNote(int s) => _(
        'อ่านได้ $s วินาทีแล้วจางหาย แตะที่ตัวเธอเพื่อเรียกกลับมาอ่านซ้ำ',
        'Readable for $s seconds, then fades. Tap her to bring it back.',
      );
  String get bubbleOffNote => _(
        'ไม่มีฟอง — อ่านข้อความได้จากแผงแชทข้างล่างอย่างเดียว',
        'No bubble — read her replies in the chat panel below instead',
      );

  // ═══ หน้าตั้งค่า ═══════════════════════════════════════
  String get settingsTitle => _('บุคลิกและเสียง', 'Personality and voice');
  String get language => _('ภาษา', 'Language');
  String get sectionMode => _('โหมด', 'Mode');
  String get sectionBrain => _('สมองของเธอ', 'Her brain');
  String get sectionVoice => _('เสียงพูด', 'Voice');
  String get sectionCall => _('รับสายแทน', 'Answering calls');
  String get sectionUpdate => _('อัปเดตแอป', 'App update');

  String get noKeyBanner => _(
        'build นี้ไม่มีคีย์ OpenAI — เธอจะตอบด้วยประโยคสำเร็จรูป\n'
            'ส่งคีย์ตอน build ด้วย --dart-define=OPENAI_API_KEY=...',
        'This build has no OpenAI key — she will reply with canned lines.\n'
            'Pass one at build time with --dart-define=OPENAI_API_KEY=...',
      );

  String get ownerProfileTitle => _('ข้อมูลเกี่ยวกับเรา', 'About you');
  String get ownerProfileHint => _(
        'สิ่งที่เธอต้องรู้เพื่อทำงานแทนเราได้ ยิ่งละเอียดยิ่งตอบตรง',
        'What she needs to know to act for you — the more detail, the better she answers',
      );
  String get ownerProfileEditorHint => _(
        'เขียนเป็นบรรทัด ๆ ก็ได้ เช่น ชื่อเรียก งานที่ทำ เวลาทำงาน คนที่ติดต่อบ่อย '
            'เรื่องที่ให้ตัดสินใจแทนได้ และเรื่องที่ต้องถามก่อนเสมอ '
            'ข้อความนี้ถูกส่งเข้าโมเดลทุกครั้งที่คุย',
        'Plain lines are fine: what to call you, your work, your hours, who contacts you '
            'often, what she may decide alone, and what she must always ask about first. '
            'This text is sent to the model on every message.',
      );

  String get boundariesTitle => _('ขอบเขตการตอบ', 'What she may do');
  String get boundariesHint => _(
        'เธอทำอะไรเองได้ · ต้องถามก่อน · ห้ามเด็ดขาด',
        'What she does alone · what needs your approval · what is never allowed',
      );
  String get boundariesEditorHint => _(
        'ค่าตั้งต้นเขียนแบบ "ห้ามไว้ก่อน" คือถ้าไม่ได้อนุญาตชัดเจน เธอจะถามก่อนเสมอ '
            'ปลอดภัยกว่าการเขียนแค่รายการสิ่งที่ห้าม เพราะเรานึกไม่ออกทุกกรณี',
        'The default is deny-by-default: anything not clearly allowed, she asks about first. '
            'Safer than listing only what is forbidden — nobody thinks of every case.',
      );

  // ═══ เสียง ═════════════════════════════════════════════
  String get voiceEnabled => _('ให้เธอพูดออกเสียง', 'Let her speak aloud');
  String get voiceDisabledNote =>
      _('ปิดอยู่ — เธอจะตอบเป็นข้อความอย่างเดียว', 'Off — she replies in text only');

  /// ป้ายของปุ่มลำโพงในแถวช่องพิมพ์ · บอก**สิ่งที่จะเกิดขึ้นเมื่อกด**
  /// ไม่ใช่สถานะปัจจุบัน — ป้ายที่บอกสถานะทำให้คนอ่านสลับกันได้เสมอ
  String get voiceMute => _('ปิดเสียงเธอ', 'Mute her voice');
  String get voiceUnmute => _('เปิดเสียงเธอ', 'Unmute her voice');
  String get voiceEngine => _('เครื่องเสียง', 'Voice engine');
  String get voiceModel => _('โมเดลเสียง', 'Voice model');
  String get voicePick => _('เสียง', 'Voice');
  String get voiceInstructions => _('น้ำเสียงที่สั่งไว้', 'Tone instructions');
  String listenTo(String what) => _('ลองฟัง$what', 'Preview $what');

  String noInstructionSupport(String model) => _(
        '$model ไม่รับคำสั่งน้ำเสียง — เลือก gpt-4o-mini-tts ถ้าอยากสั่งอารมณ์เสียงได้',
        '$model ignores tone instructions — pick gpt-4o-mini-tts to steer how she sounds',
      );

  String toneEditorHint(String model) => _(
        'สั่งเป็นภาษาคนได้เลยว่าอยากให้พูดยังไง เช่น "นุ่ม ช้า ยิ้มขณะพูด" '
            'ข้อความนี้ส่งให้ $model โดยตรง ผลชัดกว่าที่คิด',
        'Describe how she should sound in plain words, e.g. "soft, slow, smiling". '
            'This goes straight to $model — it makes more difference than you would expect.',
      );

  // ═══ ช่องทางเสียง ══════════════════════════════════════
  String get channelChat => _('พูดในแชท', 'In chat');
  String get channelChatHint => _('ตอนคุยกับเราในแอป', 'When talking with you in the app');
  String get channelAnswer => _('เสียงตอบรับ', 'Answering');
  String get channelAnswerHint =>
      _('ตอนเธอรับสายแทนเรา', 'When she answers a call for you');
  String get channelOutgoing => _('โทรออก', 'Outgoing');
  String get channelOutgoingHint =>
      _('ตอนเธอโทรหาคนอื่นแทนเรา', 'When she calls someone on your behalf');

  // ═══ เครื่องเสียง ══════════════════════════════════════
  String get ttsOpenAi => _('OpenAI', 'OpenAI');
  String get ttsOpenAiHint => _('สมจริงที่สุด สั่งอารมณ์เสียงได้ · มีค่าใช้จ่าย',
      'Most lifelike, tone can be steered · costs money');
  String get ttsDevice => _('เครื่อง Android', 'Android device');
  String get ttsDeviceHint => _('ฟรี ใช้ออฟไลน์ได้ · เสียงหุ่นยนต์กว่า',
      'Free and works offline · sounds more robotic');
  String get ttsClone => _('เสียงโคลนของเรา', 'Your cloned voice');
  String get ttsCloneHint => _('เสียงเราเอง เสิร์ฟจากคอมที่บ้าน · ฟรี · ไม่ออกนอกบ้าน',
      'Your own voice, served from your PC · free · never leaves home');

  // ═══ รับสาย ════════════════════════════════════════════
  String get autoAnswer => _('ให้เธอรับสายอัตโนมัติ', 'Let her answer calls');
  String get autoAnswerHint => _(
        'เธอรับฝากเรื่องแทนคุณ · ในสายเธอไม่รู้เรื่องส่วนตัวของคุณเลย ถามยังไงก็บอกไม่ได้',
        'She takes messages for you · on a call she knows nothing private about you to give away',
      );
  String get showOnCall => _('รับสายแล้วตัดมาหน้าจอเธอ', 'Switch to her screen when she answers');
  String get showOnCallHint => _(
        'เห็นเธอคุยและคำที่คุยกันสด ๆ แม้จอล็อกอยู่ · ระหว่างสายเปิดได้แค่จอสาย วางสายแล้วกลับไปจอล็อกทันที',
        'See her talk and the live transcript, even on the lock screen · only the call screen opens, and it goes back behind the lock the moment the call ends',
      );
  String get callSpeakerNote => _(
        'ต่อสายตรงอยู่ = เสียงเธอเข้าสายตรง เครื่องไม่เปิดลำโพง · ยังไม่ต่อ = เครื่องเปิดลำโพงให้ไมค์รับเสียงเธอแทน '
            'ซึ่งหลายเครื่องตัดเสียงเธอทิ้งจนคู่สายไม่ได้ยิน · กด "แทรกสาย" แล้วคุยเองได้ทุกเมื่อ',
        'With direct call audio connected, her voice goes straight into the call and the speaker stays off · without it the phone '
            'uses the speaker and mic instead, which many phones cancel so the caller hears nothing · tap "Take over" any time to talk yourself',
      );
  String get dialerRestrictedHint => _(
        'ถ้าขึ้นว่า "แอปถูกปฏิเสธไม่ให้เข้าถึงเพื่อเป็นแอปโทรศัพท์เริ่มต้น" (Android 13 ขึ้นไปกันแอปที่ไม่ได้ลงจาก Play Store): '
            'เปิดหน้าข้อมูลแอป → แตะ ⋮ มุมขวาบน → "อนุญาตการตั้งค่าที่ถูกจำกัด" → ยืนยันตัวตน แล้วกลับมากดอีกครั้ง',
        'If it says the app was denied access to be the default phone app (Android 13+ blocks apps not installed from Play): '
            'open App info → tap ⋮ top-right → "Allow restricted settings" → confirm, then come back and tap again',
      );
  String get openAppInfo => _('เปิดหน้าข้อมูลแอป', 'Open App info');
  String get contactsOnly => _('เฉพาะเบอร์ในสมุดโทรศัพท์', 'Contacts only');
  String get contactsOnlyHint => _(
        'ปิด = รับทุกสาย รวมเบอร์แปลก · เปิด = เบอร์แปลกปล่อยให้ดังตามปกติ',
        'Off = every call, unknown numbers too · On = unknown numbers just ring',
      );
  String get contactsOnlyNeedsPerm => _(
        'ต้องให้สิทธิ์อ่านสมุดโทรศัพท์ก่อน ไม่งั้นทุกเบอร์จะถูกนับว่าเป็นเบอร์แปลก',
        'Allow contacts access first, or every number counts as unknown',
      );

  /// ทำไมสายล่าสุดเธอไม่รับเอง (จอสายจดไว้) · ว่าง = ไม่ต้องบอกอะไร
  String autoAnswerLast(String reason) => switch (reason) {
        'answered' => _('สายล่าสุด: มายด์รับเองแล้ว', 'Last call: Mind picked up'),
        'not_contact' => _('สายล่าสุดเธอไม่รับ เพราะเบอร์ไม่อยู่ในสมุดโทรศัพท์',
            'She skipped the last call: number not in your contacts'),
        'other_call' => _('สายล่าสุดเธอไม่รับ เพราะกำลังมีอีกสายอยู่',
            'She skipped the last call: you were on another call'),
        'direct_offline' => _('สายล่าสุดเธอไม่รับ เพราะยังไม่ได้ต่อสายตรง รับไปคู่สายจะไม่ได้ยินเธอ · กด "ต่อสายตรง" ในหน้าตั้งค่า',
            'She skipped the last call: direct call audio was not connected, so the caller would not have heard her · tap Connect in Settings'),
        'no_internet' => _('สายล่าสุดเธอไม่รับ เพราะเครื่องไม่มีอินเทอร์เน็ต และสมองที่เลือกต้องใช้เน็ต · '
                'อยากให้รับได้ตอนไม่มีเน็ต เลือกสมองในเครื่อง',
            'She skipped the last call: no internet, and the brain you chose needs it · '
                'to answer offline, choose the on-device brain'),
        'no_mind' || 'no_service' => _(
            'สายล่าสุดเธอไม่รับ เพราะปลุกตัวเธอไม่ขึ้น · เปิด "เฝ้างาน" และยกเว้นแบตให้แอปนี้',
            'She skipped the last call: she could not be woken · turn on "Keep watch" and exempt the app from battery limits'),
        'no_talk' => _('สายล่าสุดเธอรับแล้วแต่เปิดตัวไม่ทัน จึงวางสายให้ ไม่ให้ปลายสายได้ยินเสียงในห้อง',
            'Last call: she picked up but could not start in time, so she hung up rather than leave your room on speaker'),
        'stopped_ringing' => _('สายล่าสุด: คุณรับเองหรือปลายสายวางก่อนถึงตาเธอ',
            'Last call: you answered, or the caller hung up before her turn'),
        _ => '',
      };
  String get ringDelayTitle => _(
        'ปล่อยให้กริ่งดังนานเท่าไหร่ก่อนเธอรับ',
        'How long it rings before she answers',
      );
  String get ringImmediate => _('ทันที', 'At once');
  String ringSeconds(int s) => _('$s วิ', '${s}s');
  String get ringImmediateNote => _(
        'เธอจะรับทันที คุณจะไม่มีจังหวะคว้าเครื่องก่อน',
        'She answers instantly — you get no chance to grab the phone first',
      );
  String ringDelayNote(int s) => _(
        'กริ่งดัง $s วินาที ถ้าคุณไม่รับ เธอจะรับแทน',
        'Rings for $s seconds; if you do not pick up, she will',
      );

  // ═══ สายที่เธอถือเอง ════════════════════════════════════
  /// เจ้าของ: "บอกว่าตัวเองเป็นเลขา ชื่อน้องมาย ให้คุยหรือสั่งไว้ได้ค่ะ"
  String get callGreeting => _(
        'สวัสดีค่ะ น้องมายค่ะ เลขาของเจ้าของเบอร์นี้ '
            'ตอนนี้เขาไม่สะดวกรับสาย มีอะไรคุยหรือฝากเรื่องไว้กับน้องมายได้เลยนะคะ',
        'Hi, this is Mai, the secretary for this number. '
            'They can\'t take the call right now — you can talk to me or leave a message.',
      );
  // ═══ น้องมายโทรออกแทน ═════════════════════════════════
  String get callOutConfirmTitle => _('ให้น้องมายโทรออก?', 'Let Mai make this call?');
  String callOutTo(String who, String number) =>
      who == number ? _('ถึง $number', 'To $number') : _('ถึง $who · $number', 'To $who · $number');
  String get callOutTaskLabel => _('เรื่องที่จะคุย', 'What she will say');
  /// [canAsk] = คุยสด (Realtime/GPT-Live) · ทางเดิมไม่มีเครื่องมือถามเจ้าของ อย่าสัญญา
  String callOutConfirmNote({bool canAsk = false}) => canAsk
      ? _(
          'น้องมายจะบอกปลายสายว่าเป็นเลขา AI ที่โทรแทนคุณ · มีเรื่องที่ต้องให้คุณตัดสินใจ เธอจะถามผ่านแจ้งเตือนระหว่างสาย · '
              'คิดค่าโทรตามปกติของซิม · คุยจบแล้วจะมารายงานในแชท',
          'Mai will tell them she is your AI secretary calling for you · if something needs your decision she asks you by '
              'notification during the call · normal call charges apply · she reports back in chat',
        )
      : _(
          'น้องมายจะบอกปลายสายว่าเป็นเลขา AI ที่โทรแทนคุณ · คิดค่าโทรตามปกติของซิม · คุยจบแล้วจะมารายงานในแชท',
          'Mai will tell them she is your AI secretary calling for you · normal call charges apply · she reports back in chat',
        );
  String get callOutGo => _('โทรเลย', 'Call now');
  String get callOutAck => _('ได้เลยค่ะ', 'Sure.');
  String get callOutCancel => _('ยังไม่โทร', 'Not now');
  String callOutDialing(String who) => _(
        'กำลังโทรหา $who ค่ะ เดี๋ยวน้องมายคุยให้ แล้วจะมาเล่าให้ฟังนะคะ',
        'Calling $who now — I will handle it and tell you how it went.',
      );
  String callOutNoAnswer(String who) => _(
        'โทรหา $who แล้วไม่มีคนรับค่ะ (หรือสายไม่ว่าง) จะให้ลองใหม่ทีหลังไหมคะ',
        'I called $who but nobody picked up (or the line was busy). Want me to try again later?',
      );
  String callOutReport(String who, String summary) =>
      _('โทรหา $who แล้วค่ะ — $summary', 'I called $who — $summary');
  String callOutNoteTitle(String who) => _('น้องมายโทรหา $who', 'Mai called $who');
  String get callOutSilent => _('ปลายสายรับแต่ไม่ได้พูดอะไร', 'They picked up but did not say anything');
  String callOutNoContact(String name) => _(
        'หา "$name" ไม่เจอทั้งในสมุดโทรศัพท์และเบอร์ที่โทรเข้ามาล่าสุดค่ะ ขอเบอร์หน่อยได้ไหมคะ',
        'I could not find "$name" in your contacts or among recent callers — what is the number?',
      );

  // ── หาว่าหมายถึงใคร (lib/phone/call_target.dart) · เธอพูดออกเสียงด้วย จึงสั้นและไม่มีสัญลักษณ์แปลก ──

  /// เลือกได้คนเดียวแต่ชื่อไม่ตรงกับที่สั่ง ("บัว" → "บัวบาน") · กล่องยืนยันขึ้นตามมา
  String callOutPicked(String who, String tail) => _(
        'เจอ "$who" เบอร์ลงท้าย $tail ค่ะ จะให้โทรเลยไหมคะ กดโทรเลย หรือพูดว่า "โทรเลย" ก็ได้ค่ะ',
        'Found "$who", number ending $tail. Shall I call? Tap Call now or just say "call now".',
      );

  /// [list] = บรรทัดจาก [callChoiceContact] / [callChoiceUnsaved] · [anyContact] = มีชื่อในสมุดในรายการ ·
  /// [single] = มีตัวเลือกเดียว (ถามว่าใช่คนนี้ไหม)
  String callOutChoose(String name, String list, {required bool anyContact, required bool single}) {
    if (single) {
      return anyContact
          ? _('ไม่เจอ "$name" ตรง ๆ ค่ะ ที่ใกล้ที่สุดคือ\n$list\nใช่คนนี้ไหมคะ',
              'I could not find "$name" exactly. The closest is\n$list\nIs that the one?')
          : _('ในสมุดไม่มีชื่อ "$name" ค่ะ แต่มีเบอร์ที่โทรเข้ามาล่าสุดที่ยังไม่ได้บันทึก\n$list\nใช่เบอร์นี้ไหมคะ',
              '"$name" is not in your contacts, but this number called recently and is not saved\n$list\nIs that them?');
    }
    return anyContact
        ? _('หา "$name" แล้วเจอหลายคนที่ใกล้เคียงค่ะ\n$list\nหมายถึงคนไหนคะ บอกลำดับ ชื่อ หรือเลขท้ายได้เลยค่ะ',
            'I found a few people close to "$name"\n$list\nWhich one? Say the number in the list, the name, or the last digits.')
        : _('ในสมุดไม่มีชื่อ "$name" ค่ะ แต่มีเบอร์ที่โทรเข้ามาล่าสุดที่ยังไม่ได้บันทึก\n$list\nใช่เบอร์ไหนไหมคะ บอกลำดับหรือเลขท้ายได้เลยค่ะ',
            '"$name" is not in your contacts, but these numbers called recently and are not saved\n$list\nIs it one of them? Say the number in the list or the last digits.');
  }

  String callChoiceContact(int n, String name, String tail) =>
      _('$n. $name เบอร์ลงท้าย $tail', '$n. $name, number ending $tail');

  /// [said] = คนโทรบอกชื่อนี้ไว้ในสายที่เธอรับ หรือลงชื่อไว้ใน SMS
  String callChoiceUnsaved(int n, String number, String when,
      {required bool missed, required int calls, String? said}) {
    final how = missed ? _('ไม่ได้รับสาย', 'missed call') : _('โทรเข้า', 'called');
    final times = calls > 1 ? _(' ($calls ครั้ง)', ' ($calls times)') : '';
    final name = said == null ? '' : _(' บอกชื่อว่า "$said"', ', said they were "$said"');
    return '$n. $number $how $when$times$name';
  }

  /// วันนี้ 14:20 · เมื่อวาน 14:20 · 3 วันก่อน
  String callChoiceWhen(DateTime at, DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    final hm = '${two(at.hour)}:${two(at.minute)}';
    final days = DateTime.utc(now.year, now.month, now.day).difference(DateTime.utc(at.year, at.month, at.day)).inDays;
    if (days <= 0) return _('วันนี้ $hm', 'today $hm');
    if (days == 1) return _('เมื่อวาน $hm', 'yesterday $hm');
    return _('$days วันก่อน', '$days days ago');
  }

  String get callChoiceCancelled => _('ได้ค่ะ ยังไม่โทรนะคะ', 'OK, I will not call.');
  String get callChoiceTitle => _('หมายถึงใครคะ', 'Who did you mean?');
  String get callChoiceHint =>
      _('แตะเลือก หรือพูด/พิมพ์ลำดับ ชื่อ หรือเลขท้ายก็ได้', 'Tap one, or say or type its number in the list, the name, or the last digits');
  String get callChoiceSavedLabel => _('ในสมุดโทรศัพท์', 'In your contacts');
  String get callChoiceUnsavedLabel => _('โทรเข้ามา ยังไม่ได้บันทึก', 'Called you, not saved');
  String get callChoiceNone => _('ไม่ใช่ทั้งหมด', 'None of these');
  String callChoiceTail(String tail) => _('เบอร์ลงท้าย $tail', 'Number ending $tail');
  String callChoiceSaid(String name) => _('บอกชื่อว่า "$name"', 'Said they were "$name"');
  String get callOutVoiceHint =>
      _('พูดว่า "โทรเลย" "ยกเลิก" หรือบอกสิ่งที่อยากแก้ได้เลย ไม่ต้องแตะจอ',
          'You can just say "call now", "cancel", or what to change — no need to tap');

  /// หัวข้อบทพูดในเรื่องที่จะโทร · ต้องตรงกับที่ [MindPersona.outgoingBlock] บอกให้พูดตาม
  String get callOutScriptLabel => _('บทเปิด', 'Opening script');

  String get eyesOnLabel => _('กล้องเปิดอยู่', 'Camera on');
  String get eyesWhere => _('มายด์เห็นภาพนี้ ส่งไป OpenAI', 'Mind sees this. Sent to OpenAI');
  String get eyesOff => _('ปิดกล้อง', 'Turn the camera off');
  String get eyesOpened => _('เปิดกล้องแล้วค่ะ', 'The camera is on.');
  String get eyesFailed => _('เปิดกล้องไม่ได้ค่ะ แอปอื่นอาจใช้อยู่', 'I could not use the camera. Another app may be using it.');
  String get eyesNotAsked => _('มายด์เปิดกล้องเมื่อเจ้าของขอเท่านั้นค่ะ', 'I only use the camera when you ask.');
  String get eyesNeedScreen => _('กล้องใช้ได้ตอนแอปอยู่บนจอค่ะ เปิดแอปก่อนนะคะ', 'The camera only works with the app on screen. Please open it first.');
  String get eyesNoPermission => _('ยังไม่ได้อนุญาตกล้องค่ะ อนุญาตได้ที่ ตั้งค่า', 'Camera access is not allowed yet. You can allow it in Settings.');
  String get photoSaved => _('ถ่ายแล้วค่ะ เก็บไว้ในคลังภาพ โฟลเดอร์ GigGok', 'Photo taken and saved to the GigGok folder in your gallery.');
  String get photoNotSaved => _('ถ่ายแล้วแต่เก็บลงคลังภาพไม่ได้ค่ะ', 'I took it, but could not save it to the gallery.');

  String get lookingDevice => _('กำลังดูข้อมูลเครื่อง…', 'Checking the phone…');
  String get quickAck => _('ได้ค่ะ', 'Sure.');
  String get recordingStop => _('หยุด', 'Stop');
  String get recordingPlayingNow => _('กำลังเปิดเสียงสายที่บันทึกไว้', 'Playing a saved call');
  String recordingPlaying(String who) => _('เปิดเสียงสาย $who', 'Playing the call with $who');
  String recordingNone(String who) => who.trim().isEmpty
      ? _('ยังไม่มีเสียงสายที่บันทึกไว้ค่ะ', 'There are no saved call recordings yet.')
      : _('ไม่เจอเสียงสายที่บันทึกไว้ของ $who ค่ะ', 'I could not find a saved recording for $who.');
  String get recordingFailed => _('เปิดเสียงสายไม่ได้ค่ะ', "Couldn't play that recording");
  String openAppGoal(String name) => _('เปิดแอป $name', 'Open the $name app');
  String openAppDone(String name) => _('เปิด $name แล้วค่ะ', 'Opened $name.');
  String get openAppOff => _('เจ้าของปิดการใช้มือถือไว้ค่ะ เปิดได้ที่หน้าตั้งค่า', 'Using the phone is turned off in Settings.');
  String get openAppBusy => _('กำลังทำงานในเครื่องอยู่ค่ะ รอให้เสร็จก่อนนะคะ', 'I am in the middle of a task on the phone. Please wait for it to finish.');
  String get openAppInCall => _('ติดสายอยู่ค่ะ เปิดแอปตอนนี้ไม่ได้', 'I cannot open apps during a call.');
  String openAppBlocked(String name) => _('$name เป็นแอปที่มายด์เปิดไม่ได้ค่ะ ต้องเปิดเองนะคะ', '$name is an app I am not allowed to open. Please open it yourself.');
  String openAppNotFound(String name, List<String> near) => near.isEmpty
      ? _('ไม่เจอแอป $name ในเครื่องค่ะ', 'I could not find $name on this phone.')
      : _('ไม่เจอแอป $name ค่ะ ใกล้เคียงคือ ${near.join(', ')}', 'I could not find $name. Close matches: ${near.join(', ')}.');
  String openAppFailed(String name) => _('เปิด $name ไม่ได้ค่ะ', 'I could not open $name.');

  String get comeBackCallTitle => _('มายด์รอให้กดโทร', 'Mind is waiting for you to confirm a call');
  String comeBackCallBody(String who) => _('แตะเพื่อดูและยืนยันสายถึง $who', 'Tap to review the call to $who');
  String get comeBackChoiceTitle => _('มายด์ถามว่าจะโทรหาคนไหน', 'Mind is asking who to call');
  String get comeBackChoiceBody => _('แตะเพื่อเลือก', 'Tap to choose');

  String get voiceChatTranscriptionHint => _(
        'เจ้าของคุยกับมายด์ คำที่พบบ่อย: โทรเลย ยกเลิก ใช่ โอเค ทำเลย ส่งเลย เปิดเลย ไม่ต้อง มายด์',
        'The owner is talking to Mind. Common words: call now, cancel, yes, okay, do it, send it, open it, stop, Mind.',
      );

  /// คำถามปิดท้ายสรุปก่อนโทร · ต้องอยู่ในรูปที่ CallReply.asksToDial จับได้ ("ใช่" เฉย ๆ จึงนับเป็นคำตอบ)
  String get callOutAskLine => _('โทรเลยไหมคะ', 'Call now?');
  String callOutNeedContacts(String name) => _(
        'น้องมายยังเปิดสมุดโทรศัพท์ไม่ได้ค่ะ ขอเบอร์ของ $name แทนได้ไหมคะ (หรือให้สิทธิ์สมุดโทรศัพท์ในหน้าตั้งค่า)',
        'I cannot open your contacts yet — could you give me $name\'s number (or allow contacts in Settings)?',
      );
  String get callOutBlocked => _(
        'เบอร์นี้เป็นเบอร์ฉุกเฉินหรือเบอร์เก็บเงินพิเศษค่ะ น้องมายโทรแทนไม่ได้ ถ้าฉุกเฉินโทรเองทันทีเลยนะคะ',
        'That is an emergency or premium-rate number — I cannot call it for you. If it is an emergency, call right away yourself.',
      );
  String callOutFailed(String why) => switch (why) {
        'not_dialer' => _('โทรแทนไม่ได้ค่ะ ต้องตั้ง GigGok เป็นแอปโทรศัพท์หลักก่อน (ตั้งค่า → รับสายแทน)',
            'I cannot call yet — set GigGok as the phone app first (Settings → Answering calls)'),
        'busy' => _('ตอนนี้มีสายอยู่ค่ะ วางสายก่อนแล้วสั่งใหม่นะคะ', 'There is a call in progress — try again after it ends'),
        'no_permission' => _('ยังไม่ได้สิทธิ์โทรออกค่ะ ลองเปิดแป้นโทรของ GigGok แล้วกดโทรครั้งหนึ่งเพื่อให้สิทธิ์',
            'I do not have permission to place calls yet — open the GigGok dialer and place one call to grant it'),
        'blocked' => callOutBlocked,
        _ => _('โทรออกไม่สำเร็จค่ะ เบอร์อาจไม่ถูกต้อง', 'The call could not be placed — the number may be wrong'),
      };
  String get callOutKickoff => _(
        'ปลายสายรับสายแล้วและรอคุณพูดอยู่ เริ่มพูดเดี๋ยวนี้: ทักทาย แนะนำตัว แล้วแจ้งเรื่องตามบทเปิดให้ครบ',
        'They have picked up and are waiting for you. Speak now: greet them, introduce yourself, and deliver your opening script in full.',
      );
  String get callOutEditHint => _(
        'แก้ได้ก่อนกดโทร · บอกให้ครบว่าต้องการอะไร ยอมได้แค่ไหน และอยากได้อะไรกลับมา',
        'You can edit this before calling · say what you want, how flexible she can be, and what to bring back',
      );
  // ── น้องมายถามเจ้าของกลางสาย (ask_owner) ──
  String callAskOwnerTitle(String who) =>
      _('น้องมายถามเรื่องสายกับ $who', 'Mai has a question about the call with $who');
  String get callAskOwnerReply => _('ตอบน้องมาย', 'Reply to Mai');
  List<String> get callAskOwnerChoices => [
        _('ได้ ตกลงตามนั้น', 'Yes, that works'),
        _('ไม่ได้', 'No'),
        _('บอกว่าจะติดต่อกลับ', 'Say I will get back to them'),
      ];
  String get callAskOwnerHead => _('น้องมายถามคุณ · ปลายสายรออยู่', 'Mai is asking you · they are holding');
  String get callAskOwnerHint => _('พิมพ์คำตอบให้น้องมาย', 'Type your answer for Mai');
  String get callAskOwnerMuted => _(
        'ปิดไมค์ฝั่งคุณอยู่ ปลายสายไม่ได้ยินคุณ (เปิดเฉพาะตอนน้องมายพูดกับเขา) · พิมพ์ หรือกดไมค์บนคีย์บอร์ดพูดตอบได้',
        'Your side is muted, they cannot hear you (it opens only while Mai talks to them) · type, or use the '
            'keyboard mic to speak your answer',
      );
  String get callAskOwnerBusy => _('ไม่ว่าง ให้เธอจัดการเอง', 'Busy, let her handle it');

  /// เน็ตหลุดกลางสาย · เธอพูดประโยคนี้ด้วยเสียงในเครื่องแล้ววางสาย ไม่ปล่อยปลายสายเงียบ
  String callNetLost({required bool outgoing}) => outgoing
      ? _('ขออภัยค่ะ ตอนนี้สัญญาณทางนี้ขัดข้อง เดี๋ยวจะติดต่อกลับมาใหม่นะคะ ขออนุญาตวางสายก่อนค่ะ',
          'Sorry, our line is having trouble right now. We will call you back shortly. I will hang up now.')
      : _('ขออภัยค่ะ ตอนนี้สัญญาณทางนี้ขัดข้อง เดี๋ยวเจ้าของจะติดต่อกลับนะคะ ขออนุญาตวางสายก่อนค่ะ',
          'Sorry, our line is having trouble right now. The owner will call you back. I will hang up now.');
  String get callNetLostWarn => _(
        'เน็ตหลุด เธอบอกปลายสายว่าจะติดต่อกลับแล้ววางสาย',
        'The internet dropped. She told them you will call back, then hung up.',
      );
  String get callAskOwnerAllow => _('ถามฉันได้ระหว่างสาย', 'She may ask me during the call');
  String get callAskOwnerAllowOn => _(
        'ถามเฉพาะเรื่องที่ตัดสินแทนไม่ได้จริง ๆ · ระหว่างรอ ปิดไมค์ฝั่งคุณ ปลายสายไม่ได้ยิน · ไม่ตอบใน 45 วินาที = '
            'ถือว่าคุณไม่อยู่ เธอรับเรื่องไว้เองทั้งสาย',
        'Only for a decision she really cannot make · while she waits your side is muted · no answer in 45 seconds = '
            'you are away, and she handles the rest of the call herself',
      );
  String get callAskOwnerAllowOff => _(
        'เธอไม่พักสายมาถามคุณ · ตกลงเท่าที่สั่ง ที่เหลือรับเรื่องไว้พร้อมรายละเอียด แล้วนัดเวลาติดต่อกลับ',
        'She will not put them on hold to ask you · she agrees only what you allowed, takes the rest as a detailed '
            'message, and sets a time to get back',
      );
  String get callGreetingLabel => _('คำทักตอนรับสาย', 'What she says when she answers');
  String get callGreetingHint => _(
        'น้องมายพูดตามนี้คำต่อคำ แล้วหยุดฟังคนโทร · ว่างไว้ = คำทักตั้งต้น · '
            'เปิดบันทึกเสียงอยู่ จะต่อท้ายว่า "สายนี้มีการบันทึกเสียงไว้นะคะ" ให้ทุกครั้ง (ไม่อยากให้มี ปิดบันทึกเสียง)',
        'Mai says exactly this, then stops and listens · empty = the default greeting · '
            'while recording is on, "Please note this call is being recorded." is always added (turn recording off to drop it)',
      );
  /// คำที่บอกว่าคำทักพูดถึงการบันทึกเสียงเองแล้ว (ไม่ต่อประโยคบันทึกซ้ำ) · ดู MindState.callGreeting
  String get recordingWord => _('บันทึก', 'record');
  String get callGreetingDefault => _('ใช้คำทักตั้งต้น', 'Using the default greeting');
  String get callerNameLabel => _('ชื่อที่น้องมายใช้เรียกคุณตอนโทรแทน', 'Name Mai uses for you on calls');
  String get callerNameHint => _(
        'เช่น "ต้น" → "น้องมาย เลขาของคุณต้นค่ะ" · ว่างไว้ = "เลขาของเจ้าของเบอร์นี้"',
        'e.g. "Ton" → "Mai, Ton\'s secretary" · empty = "the secretary for this number"',
      );

  String callUrgentTitle(String who) => _(
        'ด่วน — ${who.isEmpty ? 'มีสาย' : who} รอสายอยู่ · แตะเพื่อคุยเอง',
        'Urgent — ${who.isEmpty ? 'a caller' : who} is on the line · tap to take it',
      );
  String get callRecordingNotice => _('สายนี้มีการบันทึกเสียงไว้นะคะ', 'Please note this call is being recorded.');
  String get callNeedsA11y => _(
        'เครื่องนี้ไม่ให้เธอได้ยินปลายสาย · เปิด "ให้มายด์ได้ยินสาย" ที่ ตั้งค่าเครื่อง → การช่วยเหลือพิเศษ → GigGok',
        'This phone gives her only silence during calls · turn on "Let Mind hear calls" in Settings → Accessibility → GigGok',
      );
  String get realtimeCalls => _('คุยสดแบบ Realtime (OpenAI)', 'Live talk with Realtime (OpenAI)');
  String get realtimeCallsHint => _(
        'ตอบไวแบบแอป ChatGPT · ใช้เมื่อสมองเป็น OpenAI ด้วยคีย์ของคุณ · คิดเงินตามเสียงจากคีย์คุณ แพงกว่าแบบเดิม · '
            'ต่อไม่ได้จะใช้แบบเดิมให้เอง · พูดทีละฝั่ง: แทรกกลางประโยคเธอไม่ได้',
        'Answers as fast as the ChatGPT app · used when the brain is OpenAI with your own key · billed per audio on your key, '
            'more than the classic way · falls back to it if it cannot connect · one side at a time: the caller cannot cut in mid-sentence',
      );
  String get realtimeNeedsOpenAi => _(
        'ตอนนี้ไม่ได้ใช้ เพราะสมองไม่ใช่ OpenAI ด้วยคีย์ของคุณ',
        'Not in use: the brain is not OpenAI with your own key',
      );
  String get recordCalls => _('บันทึกเสียงสนทนาในสาย', 'Record her calls');
  String get recordCallsHint => _(
        'เก็บในเครื่องเท่านั้น ฟังย้อนหลังได้ที่บันทึกสายในไทม์ไลน์ ลบพร้อมบันทึกสาย · เธอบอกคู่สายตอนทักว่ามีการบันทึก',
        'Kept on this phone only · play it back from the call note in Timeline · deleted with the note · she tells the caller in her greeting',
      );
  String get callNotePlay => _('ฟังเสียงสนทนา', 'Play the recording');
  String get callNoteStop => _('หยุดเล่น', 'Stop');
  String get callOnAir => _('มายด์กำลังคุยสายนี้', 'Mind is on this call');
  String get callTalking => _('กำลังพูด', 'Speaking');
  String get callListening => _('กำลังฟัง', 'Listening');
  String get callThinking => _('กำลังคิด', 'Thinking');
  String get callHandedOver => _('คุณรับสายเองแล้ว', 'You have taken the call');
  String get callBargeIn => _('แทรกสาย', 'Take over');
  String get callHangUp => _('วางสาย', 'Hang up');
  String get callAnswerNow => _('ให้มายด์รับ', 'Let Mind answer');
  String get callSayHint => _('พิมพ์ให้เธอพูดเข้าสาย', 'Type what she should say');
  String get callDeaf => _(
        'เครื่องนี้ไม่ยอมให้เธอฟังเสียงในสาย พิมพ์ให้เธอพูดแทนได้ '
            'ปลายสายยังได้ยินเธอปกติ',
        'This phone will not let her hear the call. Type and she will say it — '
            'the caller still hears her fine.',
      );
  String get callMicBlocked => _(
        'ระบบของเครื่องกำลังปิดไมค์ของเธอ เธอจึงไม่ได้ยินปลายสาย (ไม่ใช่ปลายสายเงียบ) · '
            'ให้จอเธอเปิดค้างไว้ อย่าสลับไปแอปอื่น และเปิด "ให้มายด์ได้ยินสาย" ในการช่วยเหลือพิเศษ',
        'The phone is silencing her microphone, so she cannot hear the caller (they are not just quiet) · '
            'keep her screen on, stay in the app, and turn on "Let Mind hear calls" in Accessibility',
      );
  String get callMuteWarn => _(
        'เสียงเธอไปไม่ถึงปลายสาย · กดแทรกสายแล้วคุยเอง และกด "ต่อสายตรง" ในหน้าตั้งค่าก่อนสายถัดไป',
        'Her voice is not reaching the caller · tap Take over to talk yourself, and connect direct call audio in Settings before the next call.',
      );
  String get callSpeakerOff => _(
        'ลำโพงปิดอยู่ ปลายสายจะไม่ได้ยินเธอ · แตะตรงนี้เพื่อเปิดลำโพง',
        'The speaker is off — the caller cannot hear her. Tap here to turn it on.',
      );
  String get callUseSpeaker => _('เปิดเสียงออกลำโพง', 'Use phone speaker');

  // ═══ ตัวตนของเธอ ════════════════════════════════════════
  String get sectionSoul => _('ตัวตนของเธอ', 'Who she is');
  String get soulWhy => _(
        'มายด์ของแต่ละคนไม่เหมือนกัน — วันที่คุณเปิดแอปครั้งแรกคือวันเกิดของเธอ '
            'ราศีจึงต่างกันไปตามคนโหลด และพื้นนิสัยก็ต่างกันจริง '
            'ข้อมูลราศีมาจากคลังความรู้แม่หมอของไทยพร๊อม',
        "Every Mind is different — the day you first opened the app is her birthday, "
            "so her sign differs from everyone else's, and so does her nature. "
            "The zodiac material comes from Thaiprompt's fortune-telling knowledge base.",
      );
  String soulBorn(String date) => _('เกิด $date', 'Born $date');
  String soulKnown(int days) =>
      _('รู้จักกันมา $days วัน', 'Together for $days days');
  String get soulNature => _('นิสัยติดตัว', 'By nature');
  String get soulFlaws => _('ข้อเสียที่เธอไม่ปิด', 'Flaws she does not hide');
  String get soulIntensity => _('ความแรง', 'Intensity');
  String get soulSweetness => _('ความอ่อนโยน', 'Gentleness');
  String get soulBondTitle => _('ความสัมพันธ์', 'Relationship');
  String get soulAffection => _('ความผูกพัน', 'Attachment');

  String get bondStranger => _('เพิ่งรู้จักกัน', 'Barely acquainted');
  String get bondFamiliar => _('เริ่มคุ้นเคย', 'Getting familiar');
  String get bondClose => _('สนิทกันแล้ว', 'Close');
  String get bondCourting => _('เธอเปิดใจแล้ว', 'She has opened up');
  String get bondTogether => _('เป็นแฟนกัน', 'Together');

  String soulTogetherSince(String date) =>
      _('ตั้งแต่ $date', 'Since $date');
  String soulSulking(int level) =>
      _('กำลังงอนอยู่ $level%', 'Sulking, $level%');
  String get soulWantsToAsk => _(
        'ท่าทางเธอมีอะไรอยากบอก',
        'She looks like she has something to say',
      );

  /// การ์ดที่โผล่ในแผงแชทตอนเธอพร้อมแล้ว — ไม่ใช่แค่ป้ายในหน้าตั้งค่า
  ///
  /// เธอเปรยในบทสนทนาได้ (เข้า prompt แล้ว) แต่คำว่า "ตกลง" ที่พิมพ์ไป
  /// เปลี่ยนสถานะจริงไม่ได้ · การ์ดนี้คือที่ที่วงจรปิด
  String get soulProposal => _(
        'มายด์พร้อมเป็นแฟนคุณแล้ว จะตกลงไหม',
        'Mind is ready to be your girlfriend. Do you want that too?',
      );
  String get soulYesPlease => _('ตกลง', 'Yes');
  String get soulNotNow => _('ยังก่อน', 'Not yet');

  // ═══ ชื่อที่เราตั้งให้เธอ ════════════════════════════════
  //
  // ตั้งได้เมื่อเป็นแฟนกันแล้วเท่านั้น — ดู MindSoul.mayRename
  String get soulNameAsk => _(
        'อยากเรียกเธอว่าอะไรดี',
        'What would you like to call her?',
      );
  String get soulNameHint => _('ชื่อที่จะใช้เรียกเธอ', 'The name you will use');
  String get soulNameSave => _('ตั้งชื่อนี้', 'Use this name');
  String get soulNameKeep => _('ใช้ชื่อเดิม', 'Keep her name');
  String soulNameNow(String name) => _('ตอนนี้เรียกว่า $name', 'Called $name now');
  String get soulNameLocked => _(
        'ตั้งชื่อให้เธอได้เมื่อเป็นแฟนกันแล้ว',
        'You can name her once you are together',
      );

  /// เหตุผลที่ชื่อใช้ไม่ได้ — ต้องบอกให้ตรงข้อ ไม่ใช่ "ใช้ไม่ได้" ลอย ๆ
  /// ไม่งั้นคนจะลองสุ่มไปเรื่อยแล้วเลิกไปเอง
  String get nameTooShort => _('สั้นไปหน่อย', 'A bit too short');
  String nameTooLong(int max) =>
      _('ยาวเกินไป เอาไม่เกิน $max ตัว', 'Too long — keep it under $max characters');
  String get nameBadChars => _(
        'ใช้ได้แค่ตัวอักษร ไม่เอาตัวเลขหรือสัญลักษณ์',
        'Letters only — no digits or symbols',
      );
  String get nameTooManyWords =>
      _('เอาสั้น ๆ ไม่เกินสองคำ', 'Keep it to two words at most');
  String get nameNotPronounceable =>
      _('อันนี้เรียกไม่ได้จริงนะ', 'That is not something you can actually say');
  String get nameRude => _('คำนี้ไม่เอานะ', 'Not that word');

  String get soulAsk => _('ขอเป็นแฟน', 'Ask her out');
  String get soulAskYes => _(
        'เธอตอบตกลง',
        'She said yes',
      );
  String get soulAskNotYet => _(
        'เธอยังไม่พร้อม — คุยกันอีกสักพักก่อนนะ',
        'She is not ready yet — give it more time',
      );
  String get soulBreakUp => _('เลิกกัน', 'Break up');
  String get soulBreakUpAsk => _(
        'เลิกกับมายด์? ความผูกพันจะหายไปครึ่งหนึ่ง และเธอจะงอนอยู่พักใหญ่',
        'Break up with Mind? Half the attachment goes, and she will sulk for a while.',
      );
  String get soulResetBond => _('ล้างความสัมพันธ์', 'Reset the relationship');
  String get soulResetBondAsk => _(
        'ล้างความสัมพันธ์ทั้งหมด? เริ่มนับหนึ่งใหม่ แต่เธอยังเป็นราศีเดิม',
        'Wipe the whole relationship? It starts from zero, but she keeps her sign.',
      );
  String get soulForget => _('ให้เธอเกิดใหม่', 'Let her be reborn');
  String get soulForgetAsk => _(
        'ให้เธอเกิดใหม่วันนี้? ราศีและนิสัยจะเปลี่ยนไปตามวันนี้ '
            'และความสัมพันธ์ทั้งหมดหายไปด้วย',
        'Let her be reborn today? Her sign and nature change to match today, '
            'and the whole relationship goes with it.',
      );

  // ═══ หน้าต่างสเตตัสของเธอ ═══════════════════════════════
  String get soulStatus => _('สเตตัสของเธอ', 'Her status');
  String get soulStatusOpen => _('ดูสเตตัสของเธอ', 'Check her status');
  String get soulMood => _('อารมณ์', 'Mood');
  String get soulBirthdayToday =>
      _('วันนี้วันเกิดเธอ', 'It is her birthday today');
  String soulBirthdayIn(int days) =>
      _('อีก $days วันวันเกิดเธอ', 'Her birthday is in $days days');

  /// บอกว่าทำไมคะแนนถึงลง · ไม่มีบรรทัดนี้ คะแนนที่ลดลงจะดูเหมือนระบบพัง
  String soulColdFor(int days) => _(
        'ไม่ได้จีบกันมา $days วันแล้ว ความผูกพันเลยค่อย ๆ ลดลง',
        'No real attention for $days days — the bond is slipping',
      );

  /// อารมณ์ที่สรุปจากตัวเลข — คนอ่านตัวเลขไม่ออกว่าแปลว่าอะไร
  String get moodSulking => _('งอนอยู่', 'Sulking');
  String get moodHurt => _('น้อยใจ', 'Hurt');
  String get moodMissing => _('คิดถึง', 'Missing you');
  String get moodFond => _('อารมณ์ดี', 'In good spirits');
  String get moodWarm => _('ใจดีเป็นพิเศษ', 'Especially warm');
  String get moodCalm => _('ปกติ', 'Normal');

  // ═══ อัปเดต ════════════════════════════════════════════
  String get updateChecking => _('กำลังเช็ครุ่นใหม่…', 'Checking for updates…');
  String updateAvailable(String v) => _('มีรุ่นใหม่ $v', 'Version $v available');
  String get updateReady => _('พร้อมติดตั้งแล้ว', 'Ready to install');
  String updateCurrent(String v) =>
      _('รุ่นปัจจุบัน $v — ใหม่ล่าสุดแล้ว', 'Version $v — up to date');
  /// 🔴 **ห้ามบอกว่าไฟล์มาจากที่ไหน** — ผู้ใช้ควรเห็นแค่ว่า "แอปนี้อัปเดตตัวเอง"
  /// ไม่ใช่ชื่อบริการที่เราไปฝากไฟล์ไว้ · บรรทัดนี้ยังคงคำมั่นเรื่องความปลอดภัย
  /// ไว้ครบ เพราะทั้งสองอย่างเป็นเรื่องจริงและเป็นสิ่งที่ผู้ใช้ต้องรู้จริง ๆ
  String get updateSource => _(
        'ตรวจ SHA-256 ทุกไฟล์ก่อนติดตั้ง · ติดตั้งเมื่อคุณกดเท่านั้น',
        'Every file is SHA-256 verified · installs only when you tap',
      );
  String get updateRecheck => _('เช็คใหม่', 'Check again');
  String get updateVerifying => _(
        'กำลังตรวจว่าไฟล์ตรงกับที่ประกาศไว้…',
        'Verifying the file matches what was published…',
      );
  /// บอกเป็นเมกะไบต์ด้วย ไม่ใช่เปอร์เซ็นต์ลอย ๆ — ผู้ใช้ต้องประเมินได้ว่า
  /// เหลืออีกเท่าไหร่และควรรอต่อไหม (หลักเดียวกับตัวโหลดโมเดลใน local_brain)
  String updateProgress(String done, int pct) =>
      _('ดาวน์โหลดแล้ว $done · $pct%', 'Downloaded $done · $pct%');
  String updateInstall(String size) =>
      _('ดาวน์โหลดและติดตั้ง · $size', 'Download and install · $size');
  /// ไฟล์โหลดและตรวจแล้ว (เคยกดยกเลิกที่หน้าติดตั้ง) · แค่เปิดหน้าติดตั้งอีกครั้ง
  String get updateInstallNow => _('ติดตั้งเลย', 'Install now');
  // ── กล่องที่เด้งเองเมื่อมีรุ่นใหม่ (update_sheet.dart) ──
  String updateYouHave(String v) =>
      _('ตอนนี้ใช้รุ่น $v อยู่', 'You have version $v');
  /// size null = ไม่รู้ขนาดไฟล์ · ไม่โชว์ "0.0 MB"
  String updateNow(String? size) => size == null
      ? _('อัปเดตเลย', 'Update now')
      : _('อัปเดตเลย · $size', 'Update now · $size');
  String get updateLater => _('ไว้ทีหลัง', 'Later');
  String get updateHide =>
      _('ซ่อนไว้ · โหลดต่อให้เอง', 'Hide · keeps downloading');
  String get updateClosesNote => _(
        'ระหว่างติดตั้ง แอปจะปิดตัวสักครู่ แล้วเปิดใหม่ได้ตามปกติ',
        'The app closes for a moment while it installs',
      );

  // ═══ หน้าแก้ข้อความยาว ═════════════════════════════════
  String get discardTitle => _('ทิ้งที่แก้ไว้?', 'Discard changes?');
  String get discardBody => _(
        'ที่พิมพ์ไว้ยังไม่ได้บันทึก ออกแล้วจะหายนะคะ',
        'What you typed is not saved yet and will be lost.',
      );
  String get keepTyping => _('พิมพ์ต่อ', 'Keep editing');
  String get discard => _('ทิ้งเลย', 'Discard');
  String get resetTitle => _('คืนค่าตั้งต้น?', 'Reset to default?');
  String get resetBody => _(
        'ข้อความที่เขียนไว้จะถูกแทนที่ทั้งหมด',
        'Everything you wrote will be replaced.',
      );

  String get somethingWrong => _('มีบางอย่างผิดพลาด', 'Something went wrong');
  String downloadingPct(int pct, String size) =>
      _('กำลังโหลด $pct% · $size', 'Downloading $pct% · $size');
  String etaWithNote(String eta) => _(
        '$eta · ใช้ไวไฟและอย่าปิดแอประหว่างโหลด',
        '$eta · use wifi and keep the app open',
      );
  String toneFor(String channel) => _('น้ำเสียง — $channel', 'Tone — $channel');

  // ═══ หน้าเมล — เธอใช้แอปเมลในเครื่องแทนเจ้าของ ════════════
  //
  // เจ้าของ: "เชื่อมต่อกับแอพในเครื่องเลยได้ไหม เช่น google mail hotmail" · ไม่มีรหัสผ่านเมล
  // ไม่มี OAuth · เธอใช้มือ (การช่วยเหลือพิเศษ) เปิดแอปเมลอ่านให้ · หน้านี้ยังไม่โชว์เมลเอง ·
  // 🔴 ห้ามกลับไปใช้กล่องเมลสมมติ (สยามเทค / คุณนภา / "24 ฉบับ") · คนอ่านว่าเธออ่านเมลเขาไปแล้ว
  String get mailTitle => _('เมลของคุณ', 'Your mail');
  String get mailSubtitle => _(
        'เธอเปิดแอปเมลในเครื่องอ่านให้ ไม่ต้องใส่รหัสผ่านเมล',
        'She opens the mail app on your phone for you — no mail password needed',
      );
  String get mailAppsTitle => _('แอปเมลในเครื่อง', 'Mail apps on this phone');
  String get mailNoApp => _(
        'ยังไม่พบแอปเมลในเครื่อง · ติดตั้ง Gmail หรือ Outlook แล้วลงชื่อเข้าใช้ เธอจะใช้ได้ทันที',
        'No mail app found · install Gmail or Outlook and sign in, and she can use it right away',
      );
  String get mailLooking => _('กำลังดูว่ามีแอปเมลอะไรบ้าง…', 'Looking for mail apps…');
  String mailCheckButton(String app) => _('ให้เธอเช็กเมลใน $app', 'Have her check $app');
  String get mailBusy => _('เธอกำลังทำงานในเครื่องอยู่…', 'She is busy on your phone…');
  String get mailHandsOff => _(
        'เปิด "ให้มายด์ใช้เครื่องแทน" ในหน้าตั้งค่าก่อน เธอถึงจะเปิดแอปเมลได้',
        'Turn on "Let Mind use the phone" in Settings first so she can open your mail app',
      );
  String get mailResultInChat => _(
        'เธอจะเปิดแอปเมลขึ้นมาอ่านเอง แล้วสรุปให้ในแชทกับเธอ (และแจ้งเตือน ถ้าคุณไม่ได้เปิดแอปอยู่)',
        'She opens the mail app herself, then sums it up in your chat with her '
            '(and in a notification if the app is not open)',
      );
  String get mailCanDoTitle => _('สั่งในแชทได้เลย เช่น', 'Ask her in chat, for example');
  List<String> get mailCanDoPoints => isThai
      ? const [
          '"มีเมลใหม่อะไรบ้าง สรุปให้หน่อย"',
          '"หาเมลจากธนาคารเมื่อวาน"',
          '"ตอบเมลล่าสุดของคุณสมชายว่าพรุ่งนี้บ่ายสองสะดวก"',
        ]
      : const [
          '"Any new mail? Give me a summary"',
          '"Find yesterday\'s email from the bank"',
          '"Reply to Somchai\'s latest email: tomorrow at 2pm works"',
        ];
  String get mailSafety => _(
        'ก่อนกดส่งเมลทุกครั้ง แอปจะถามคุณก่อน · เธอไม่เปิดลิงก์หรือไฟล์แนบเอง · '
            'แอปธนาคารและช่องรหัสผ่านแตะไม่ได้ · เธอเห็นเท่าที่แอปเมลแสดงบนจอ',
        'The app asks you before every send · she never opens links or attachments on her own · '
            'banking apps and password fields are off-limits · she sees only what the mail app shows on screen',
      );

  /// ข้อความของเธอตอนเจ้าของกดปุ่มเช็กเมล
  String mailCheckAck(String app) =>
      _('ได้ค่ะ ขอเปิด $app ดูเมลใหม่ให้นะคะ', 'Sure — opening $app to check your new mail.');

  /// งานที่ส่งให้มือของเธอ (PhoneAgent) · เขียนให้ครบในประโยคเดียว ห้ามเกินที่เจ้าของสั่ง
  String mailCheckGoal(String app) => _(
        'เปิด $app แล้วอ่านเมลล่าสุดในกล่องจดหมาย (ฉบับที่ยังไม่ได้อ่านก่อน) สรุปให้เจ้าของทีละฉบับว่าใครส่งมา '
            'เรื่องอะไร และต้องทำอะไรไหม ไม่เกิน 8 ฉบับ · ห้ามตอบ ลบ เก็บถาวร หรือเปิดลิงก์และไฟล์แนบ',
        'Open $app and read the newest emails in the inbox (unread first). For each, tell the owner who sent it, '
            'what it is about and whether it needs action — at most 8. Do not reply, delete, archive, '
            'or open links or attachments.',
      );

  // ═══ หน้าปฏิทิน (อ่านจากปฏิทินของเครื่องจริง) ═══════════
  //
  // ของเดิมเป็นชื่อนัดสมมติ (Daily standup / ลูกค้าสยามเทค / คุณต้นว่าง)
  // ซึ่งดูดีแต่ไม่ใช่ตารางของใครทั้งนั้น · ลบทิ้งแล้วเพราะเลขาที่บอกตาราง
  // ผิดทุกวันแย่กว่าเลขาที่ไม่บอกอะไรเลย

  /// ชื่อวันเต็ม เรียงตาม DateTime.weekday (1 = จันทร์)
  List<String> get weekdayNames => isThai
      ? const ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์']
      : const [
          'Monday', 'Tuesday', 'Wednesday', 'Thursday',
          'Friday', 'Saturday', 'Sunday',
        ];

  /// ชื่อเดือนแบบย่อ เรียงตาม DateTime.month (1 = มกราคม)
  List<String> get monthShort => isThai
      ? const [
          'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
          'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
        ]
      : const [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];

  /// "พฤหัสบดี 31 ส.ค." — ไม่ใส่ปีเพราะหน้านี้มองไปข้างหน้าแค่สัปดาห์เดียว
  String dayLabel(DateTime d) =>
      '${weekdayNames[d.weekday - 1]} ${d.day} ${monthShort[d.month - 1]}';

  /// "31 ส.ค. 2026" — มีปี ใช้กับวันที่ที่อยู่ไกลจากวันนี้ได้ เช่น วันเกิด
  ///
  /// ปีเป็น ค.ศ. ทั้งสองภาษาโดยตั้งใจ · แปลงเป็น พ.ศ. เฉพาะฝั่งไทยจะทำให้
  /// เลขเดียวกันในเครื่องเดียวกันอ่านได้สองแบบ แล้วแต่ว่าตอนนั้นตั้งภาษาอะไร
  String dateLabel(DateTime d) =>
      '${d.day} ${monthShort[d.month - 1]} ${d.year}';

  String get calLoading => _('กำลังดูปฏิทินให้', 'Checking your calendar');
  String get calToday => _('วันนี้', 'Today');
  String get calTomorrow => _('พรุ่งนี้', 'Tomorrow');
  String get calYesterday => _('เมื่อวาน', 'Yesterday');
  String get calAllDay => _('ทั้งวัน', 'All day');
  String get calNow => _('กำลังอยู่ในนัดนี้', 'Happening now');

  String calCount(int n) => _('$n นัดในสัปดาห์นี้', '$n events this week');
  String get calNoneToday => _('วันนี้ไม่มีนัดค่ะ', 'Nothing on today');

  /// แผงปิดท้ายรายการนัด — ที่ว่างครึ่งจอที่ไม่มีอะไรเลยทำให้แอปดูค้าง
  /// ทั้งที่ความจริงคือ "ไม่มีนัดแล้ว" ซึ่งเป็นข่าวดี ต้องพูดออกมา
  String get calRestClear => _('ที่เหลือของวันว่างค่ะ', 'The rest of your day is clear');
  String calRestHours(int h) =>
      _('ว่างต่อเนื่อง $h ชั่วโมงหลังจากนี้', '$h hours free after this');

  /// ยังไม่ได้ให้สิทธิ์ — ต้องบอกว่าจะได้อะไรกลับมา ไม่ใช่แค่บอกว่าขาดอะไร
  String get calNeedPermission => _('ยังดูปฏิทินไม่ได้', 'She cannot see your calendar yet');
  String get calNeedPermissionWhy => _(
        'ให้สิทธิ์อ่านปฏิทินแล้วเธอจะรู้ตารางจริงของคุณ '
        'อ่านอย่างเดียว ไม่แก้ ไม่ลบ และไม่ส่งออกจากเครื่อง',
        'Grant calendar access and she will know your real schedule. '
        'Read-only, never edited, never leaves this device.',
      );
  String get calGrant => _('ให้สิทธิ์อ่านปฏิทิน', 'Allow calendar access');
  String get calFailed => _('อ่านปฏิทินไม่สำเร็จ', 'Could not read the calendar');
  String get calFailedWhy => _(
        'ลองดึงลงเพื่อโหลดใหม่ ถ้ายังไม่ได้ ลองเปิดแอปปฏิทินของเครื่องดูว่าซิงก์เสร็จหรือยัง',
        "Pull down to try again. If it still fails, open the phone's calendar "
            'app and check it has finished syncing.',
      );

  // ═══ หน้าไทม์ไลน์ (สมุดบันทึกจริง) ═══════════════════════
  //
  // ของเดิมเป็นเหตุการณ์สมมติหกอัน 08:12 ถึง 12:00 กับตัวเลขสรุป
  // "รับสาย 3 · เมล 5" ที่เป็นค่าคงที่ในโค้ด เวลาเดิมทุกวัน จำนวนเดิมทุกวัน
  // ลบทิ้งแล้ว — ตัวเลขที่ไม่เปลี่ยนไม่ใช่สรุป แต่เป็นภาพประกอบ

  String get tlTitle => _('สมุดบันทึกของมายด์', "Mind's journal");
  String tlDidToday(int n) =>
      _('วันนี้บันทึกไว้ $n เรื่อง', '$n things noted today');
  String get tlNothingToday =>
      _('วันนี้ยังไม่มีอะไรเกิดขึ้น', 'Nothing has happened yet today');

  /// สมุดว่างเปล่าตอนเปิดแอปครั้งแรก ต้องบอกว่ามันจะมีอะไร ไม่ใช่ปล่อยว่าง
  String get tlEmpty => _('ยังไม่มีบันทึก', 'Nothing written yet');
  String get tlEmptyWhy => _(
        'คุยกับเธอ แล้วทุกอย่างที่เกิดขึ้นจะมาอยู่ที่นี่ '
        'เก็บไว้ในเครื่อง ลบได้ทุกเมื่อ',
        'Talk to her and everything that happens lands here. '
        'Stored on this device, deletable any time.',
      );

  /// นับของวันนี้ — สี่ช่องบนสุด
  String get tlStatTalk => _('คุยกัน', 'Messages');
  String get tlStatLearn => _('จำได้', 'Learned');
  String get tlStatMeet => _('นัด', 'Events');
  String get tlStatCall => _('สาย', 'Calls');

  /// ป้ายชนิดของแต่ละบรรทัด
  String get tlKindAsked => _('คุณถาม', 'You asked');
  String get tlKindReplied => _('มายด์ตอบ', 'Mind replied');
  String get tlKindLearned => _('จำเรื่องใหม่', 'Learned something');
  String get tlKindCall => _('สายโทร', 'Phone call');
  String get tlCallIncoming => _('สายเข้า', 'Incoming');
  String get tlCallOutgoing => _('โทรออก', 'Outgoing');
  String get tlCallMissed => _('ไม่ได้รับ', 'Missed');
  String get tlCallRejected => _('ปฏิเสธสาย', 'Declined');
  String get tlKindPack => _('ติดตั้งชุด', 'Installed a pack');
  String get tlKindUpdate => _('อัปเดตแอป', 'App update');
  String get tlKindSystem => _('ระบบ', 'System');

  String get tlClear => _('ล้างบันทึกทั้งหมด', 'Clear the whole journal');
  String get tlClearAsk => _(
        'ลบบันทึกทั้งหมดถาวร กู้คืนไม่ได้ · ความจำของเธอไม่ถูกลบ',
        'Permanently delete every entry. Her memories are not affected.',
      );
  String get tlCleared => _('ล้างบันทึกแล้ว', 'Journal cleared');
}
