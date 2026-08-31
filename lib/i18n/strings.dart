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
  List<String> get workChips => isThai
      ? const ['สรุปเมลเช้านี้', 'นัดรีวิวบ่ายนี้', 'โทรหาคุณต้น']
      : const ['Summarise my inbox', 'Book the review', 'Call Ton for me'];

  List<String> get loveChips => isThai
      ? const ['วันนี้เป็นไงบ้าง', 'เล่าอะไรให้ฟังหน่อย', 'คิดถึงไหม']
      : const ['How was your day', 'Tell me something', 'Did you miss me'];

  /// ปุ่มบนจอที่ยังเป็นข้อมูลตัวอย่าง — ต้องตอบอะไรที่จริง
  /// ดีกว่าเงียบ และดีกว่าแกล้งทำเป็นทำงานได้
  String get demoAction => _(
        'หน้านี้ยังเป็นข้อมูลตัวอย่างค่ะ ยังไม่ได้ต่อของจริง',
        'This screen is still sample data — not wired up yet',
      );

  // ═══ หน้าเปิดแอป ═══════════════════════════════════════
  String get splashSkip => _('แตะเพื่อข้าม', 'Tap to skip');

  /// ขึ้นหลังวิดีโอจบ ถ้าตัวเธอยังโหลดไม่เสร็จ
  /// เปอร์เซ็นต์เป็นของจริงจากไบต์ที่โหลดมาแล้ว ไม่ใช่แถบที่วิ่งเองตามเวลา
  String splashLoading(int pct) => _('กำลังโหลด $pct%', 'Loading $pct%');

  // ═══ หน้าหลัก ══════════════════════════════════════════
  String get composerHint => _('พิมพ์ หรือกดไมค์…', 'Type, or tap the mic…');

  /// แผงแชทพับแล้ว — ปุ่มที่เหลืออยู่ต้องบอกให้ชัดว่ากดแล้วได้อะไร
  /// "แตะ" เฉย ๆ ไม่พอ คนไม่รู้ว่าแตะแล้วจะเปิดอะไรขึ้นมา
  String get chatTapToOpen => _('แตะเพื่อคุยกับมายด์', 'Tap to talk to Mind');
  String get chatCollapse => _('พับแผงแชท', 'Collapse the chat');
  /// ข้อความตอนเธอยังไม่ขึ้นเวที — เขียนด้วยภาษาคน ไม่ใช่ศัพท์ของนักพัฒนา
  /// "VRM avatar · full body" ที่เคยขึ้นตรงนี้คือชื่อรูปแบบไฟล์ ผู้ใช้ไม่ต้องรู้
  String get avatarPlaceholder => _('มายด์กำลังมา…', 'Mind is on her way…');
  String get avatarMissing =>
      _('ยังไม่ได้โหลดตัวมายด์', "Mind's pack is not downloaded yet");

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
  String get shopUrlLabel => _('ที่อยู่ร้าน', 'Shop address');

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
  String get permContactsWhy => _(
        'เปลี่ยนเบอร์เป็นชื่อคน · อ่านอย่างเดียว ไม่แก้ ไม่ส่งออกจากเครื่อง',
        'Turns numbers into names — read-only, never edited, never leaves this device',
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
        'สลับลำโพงได้ · เธอยังพูดในสายไม่ได้ Android ไม่เปิดทางให้แอปไหนทำ '
        'ถอนคืนได้ตลอดจากหน้าตั้งค่าของเครื่อง',
        'Every call on this phone goes through this app — Mind owns the call '
        'screen and can answer, hang up, mute and switch to speaker. She still '
        'cannot talk on the line; Android allows no app to do that. '
        'Reversible any time from system settings.',
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
  String get seedGreeting => _(
        'อรุณสวัสดิ์ค่ะ เช้านี้มีเมล 24 ฉบับ มายด์คัดให้เหลือ 3 ที่ต้องตอบนะคะ',
        'Good morning. 24 emails came in — I narrowed it to 3 that need you.',
      );
  String get seedAsk => _('บ่ายนี้ว่างไหม', 'Am I free this afternoon?');
  String get seedAnswer => _(
        'บ่ายว่างตั้งแต่ 14:00 ค่ะ แต่คุณต้นขอเลื่อนรีวิวมาบ่ายสาม จะให้มายด์โทรไปคุยให้ไหมคะ',
        'Free from 2pm, but Ton asked to move the review to 3. Shall I call and sort it out?',
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
  String get voiceEngine => _('เครื่องเสียง', 'Voice engine');
  String get voiceModel => _('โมเดลเสียง', 'Voice model');
  String get voicePick => _('เสียง', 'Voice');
  String get voiceInstructions => _('น้ำเสียงที่สั่งไว้', 'Tone instructions');
  String get realtimeModel =>
      _('โมเดลคุยสดตอนอยู่ในสาย', 'Live conversation model for calls');
  String get realtimeNote => _(
        'ใช้ตอนต่อสายจริงเท่านั้น ยังไม่ได้ต่อ — ดู docs/telephony.md',
        'Only used on real calls, not wired up yet — see docs/telephony.md',
      );
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
        'เฉพาะเบอร์ในสมุดโทรศัพท์ · สายแปลกให้คัดกรองก่อน',
        'Contacts only · unknown numbers get screened first',
      );
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
  String get callGreeting => _(
        'สวัสดีค่ะ มายด์เป็นผู้ช่วยของเจ้าของเบอร์นี้นะคะ '
            'ตอนนี้เขาไม่สะดวกรับสาย ไม่ทราบว่าติดต่อเรื่องอะไรคะ',
        'Hello, this is Mind, assistant to the owner of this number. '
            'They cannot take the call right now — may I ask what it is about?',
      );
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
  String get callMuteWarn => _(
        'เปิดลำโพงเข้าสายไม่ได้ ปลายสายจะไม่ได้ยินเธอ ลองสลับช่องเสียงในหน้าตั้งค่า',
        'Speakerphone was refused — the caller will not hear her. '
            'Try the other audio path in Settings.',
      );

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

  // ═══ ช่องเสียงเข้าสาย ═══════════════════════════════════
  String get callStreamTitle => _('ทางที่เสียงเธอวิ่งเข้าสาย', 'How her voice reaches the call');
  String get callStreamWhy => _(
        'เธอพูดออกลำโพงแล้วให้ไมค์ของเครื่องรับเข้าไปในสาย เพราะ Android '
            'ไม่มีทางป้อนเสียงเข้าสายตรง ๆ · บางเครื่องตัดเสียงก้องแรงจนลบเสียงเธอทิ้ง '
            'ถ้าปลายสายไม่ได้ยิน ให้สลับมาอีกทางแล้วลองใหม่',
        'She speaks out the loudspeaker and the phone mic carries it into the call — '
            'Android has no way to inject audio directly. Some phones cancel it as echo. '
            'If the caller cannot hear her, switch to the other path and try again.',
      );
  String get callStreamCall => _('ช่องเสียงสาย', 'Call stream');
  String get callStreamCallHint =>
      _('ค่าตั้งต้น · ดังตามระดับเสียงสาย', 'Default — follows the in-call volume');
  String get callStreamMedia => _('ช่องเสียงสื่อ', 'Media stream');
  String get callStreamMediaHint => _(
        'ลองทางนี้ถ้าปลายสายไม่ได้ยิน',
        'Try this one if the caller hears nothing',
      );

  // ═══ อัปเดต ════════════════════════════════════════════
  String get updateChecking => _('กำลังเช็ครุ่นใหม่…', 'Checking for updates…');
  String updateAvailable(String v) => _('มีรุ่นใหม่ $v', 'Version $v available');
  String get updateReady => _('พร้อมติดตั้งแล้ว', 'Ready to install');
  String updateCurrent(String v) =>
      _('รุ่นปัจจุบัน $v — ใหม่ล่าสุดแล้ว', 'Version $v — up to date');
  String get updateSource => _(
        'อ่านจาก GitHub Releases · ตรวจ SHA-256 ก่อนติดตั้งทุกครั้ง',
        'Read from GitHub Releases · SHA-256 verified before every install',
      );
  String get updateRecheck => _('เช็คใหม่', 'Check again');
  String get updateVerifying => _(
        'กำลังตรวจว่าไฟล์ตรงกับที่ประกาศไว้…',
        'Verifying the file matches what was published…',
      );
  String updateProgress(int pct) => _('ดาวน์โหลดแล้ว $pct%', 'Downloaded $pct%');
  String updateInstall(String size) =>
      _('ดาวน์โหลดและติดตั้ง · $size', 'Download and install · $size');

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

  // ═══ สวิตช์ความสามารถ ══════════════════════════════════
  String get featMorningMail => _('สรุปเมลตอนเช้า 08:00', 'Morning inbox summary at 08:00');
  String get featMorningMailHint =>
      _('อ่านให้ฟังตอนคุณขึ้นรถได้', 'She can read it aloud on your commute');
  String get featSendMail => _('ให้เธอส่งเมลเองได้', 'Let her send emails herself');
  String get featSendMailHint => _(
        'เฉพาะที่ตอบตามแม่แบบ · เรื่องเงินต้องขออนุมัติเสมอ',
        'Template replies only · anything about money always needs approval',
      );
  String get featAlwaysOn => _('Always-on (ทำงานเบื้องหลัง)', 'Always-on (background)');
  String get featAlwaysOnHint => _(
        'ต้องปิด battery optimization ให้แอปนี้',
        'Battery optimisation must be turned off for this app',
      );
  String get featBubbleOverlay => _('ฟองลอยบนหน้าจออื่น', 'Floating bubble over other apps');
  String get featBubbleOverlayHint => _(
        'ต้องให้สิทธิ์ Display over other apps',
        'Needs the "display over other apps" permission',
      );

  String get somethingWrong => _('มีบางอย่างผิดพลาด', 'Something went wrong');
  String downloadingPct(int pct, String size) =>
      _('กำลังโหลด $pct% · $size', 'Downloading $pct% · $size');
  String etaWithNote(String eta) => _(
        '$eta · ใช้ไวไฟและอย่าปิดแอประหว่างโหลด',
        '$eta · use wifi and keep the app open',
      );
  String toneFor(String channel) => _('น้ำเสียง — $channel', 'Tone — $channel');

  // ═══ หน้าเมล (ข้อมูลตัวอย่าง) ═══════════════════════════
  String get mailTitle => _('กล่องเมลเช้านี้', 'Your inbox this morning');
  String get mailSubtitle =>
      _('24 ฉบับ · เธอคัดให้เหลือ 3 ที่ต้องตอบ', '24 messages · she narrowed it to 3');
  String get mail1Title =>
      _('สยามเทค — ขอต่อรองราคา QT-2609', 'Siamtech — asking to negotiate QT-2609');
  String get mail1Body => _(
        'ขอส่วนลด 7% แลกกับสั่งเพิ่มเป็น 500 ชุด · ต้องการคำตอบก่อนศุกร์',
        'Wants 7% off for a 500-unit order · needs an answer before Friday',
      );
  String get mail2Title =>
      _('คุณนภา — เลื่อนส่งไฟล์อาร์ตเวิร์ก', 'Napa — pushing back the artwork');
  String get mail2Body => _(
        'ขอเลื่อนจากศุกร์เป็นจันทร์ เพราะรอไฟล์จากลูกค้า',
        'Friday to Monday, waiting on files from the client',
      );
  String get mailDraftLabel => _('ร่างคำตอบของเธอ', 'Her draft reply');
  String get mailDraftBody => _(
        'สวัสดีค่ะคุณนภา\n'
            'เลื่อนเป็นวันจันทร์ได้ค่ะ แต่รบกวนส่งภายในเช้าวันจันทร์นะคะ '
            'เพราะทีมต้องรีวิวก่อนส่งโรงพิมพ์บ่ายวันเดียวกัน\n'
            'ขอบคุณค่ะ',
        'Hi Napa,\n'
            'Monday works. Please send it by Monday morning though - '
            'the team reviews before it goes to print that same afternoon.\n'
            'Thank you.',
      );
  String get mailSendNow => _('ส่งเลย', 'Send it');
  String get mailEditFirst => _('แก้ก่อน', 'Edit first');
  String get mail3Title => _('HR — ยืนยันวันลาพักร้อน', 'HR — confirm your leave dates');
  String get mail3Body => _(
        'รอกดยืนยัน 12–14 ก.ย. เธอกดให้ได้ถ้าคุณสั่ง',
        'Waiting on 12–14 Sep. She can confirm if you say so',
      );
  String get mailLaterNote1 => _('อีก 21 ฉบับเธอจัดเป็น ', 'She filed the other 21 as ');
  String get mailLaterNote2 => _('อ่านทีหลัง', 'read later');
  String get mailLaterNote3 =>
      _(' — ข่าวสาร 12 · ใบเสร็จ 6 · สแปม 3', ' — 12 newsletters · 6 receipts · 3 spam');
  String get mailReadAloud => _('ให้เธออ่านสรุปให้ฟัง', 'Have her read the summary aloud');
  String get mailCompose => _('เขียนเมลใหม่', 'Write a new email');

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
