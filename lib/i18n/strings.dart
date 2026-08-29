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

  // ═══ หน้าหลัก ══════════════════════════════════════════
  String get composerHint => _('พิมพ์ หรือกดไมค์…', 'Type, or tap the mic…');
  String get avatarPlaceholder =>
      _('VRM avatar · full body', 'VRM avatar · full body');
  String get avatarMissing =>
      _('ยังไม่มีโมเดลอวาตาร์ในเครื่อง', 'Avatar model not on this device yet');

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

  // ═══ หน้าปฏิทิน (ข้อมูลตัวอย่าง) ════════════════════════
  String get calDate => _('พฤหัสบดี 3 ก.ย.', 'Thursday 3 Sep');
  String get calSubtitle => _(
        'เธอเช็กปฏิทินคุณ + คุณต้น + คุณนภา แล้ว',
        'She checked your calendar plus Ton and Napa',
      );
  String get calStandup => _('Daily standup', 'Daily standup');
  String get calClient => _('ลูกค้า สยามเทค', 'Client: Siamtech');
  String get calProposedBadge => _('เธอเสนอ', 'She suggests');
  String get calReview => _('รีวิวงานออกแบบ', 'Design review');
  String get calAddPerson => _('+ เพิ่มคน', '+ Add someone');
  String calFree(String name) => _('$name ว่าง', '$name is free');
  String get nameTon => _('คุณต้น', 'Ton');
  String get nameNapa => _('คุณนภา', 'Napa');
  String get calNext => _('เธอจะทำต่อ', 'What she will do next');
  String get calConfirm => _('ยืนยันและส่งคำเชิญ', 'Confirm and send invites');
  String get calFindAnother => _('หาเวลาอื่น', 'Find another time');

  // ═══ หน้าไทม์ไลน์ (ข้อมูลตัวอย่าง) ══════════════════════
  String get tlTitle => _('วันนี้เธอทำให้ 14 อย่าง', 'She did 14 things for you today');
  String get tlCalls => _('รับสาย', 'Calls');
  String get tlMails => _('ส่งเมล', 'Emails');
  String get tlMeetings => _('นัด', 'Meetings');
  String get tlWaiting => _('รอคุณ', 'Waiting on you');
  String get tl1Title => _('สรุปกล่องเมลเช้า', 'Summarised the morning inbox');
  String get tl1Detail => _('24 ฉบับ → 3 ที่ต้องตอบ · ร่างคำตอบไว้ 2',
      '24 messages → 3 need you · 2 replies drafted');
  String get tl1Action => _('ดูร่าง', 'See drafts');
  String get tl2Title => _('รับสายแทน — คุณวิชัย', 'Answered for you — Wichai');
  String get tl2Detail => _('ใบเสนอราคา QT-2609 ขอต่อรอง 7% · จดไว้แล้ว',
      'Quote QT-2609, asked for 7% off · noted');
  String get tl2Action => _('ฟังเสียง · อ่านสรุป', 'Listen · read summary');
  String get tl3Title => _('ส่งเมลตอบคุณนภา', 'Replied to Napa');
  String get tl3Detail => _('อนุมัติเลื่อนอาร์ตเวิร์กเป็นวันจันทร์เช้า',
      'Approved moving the artwork to Monday morning');
  String get tl3Action => _('ย้อนกลับ (เหลือ 23 ชม.)', 'Undo (23h left)');
  String get tl4Title => _('โทรออก — คุณต้น', 'Called out — Ton');
  String get tl4Detail => _('เลื่อนรีวิวเป็นพฤหัส 15:00 · เขาตอบตกลง',
      'Moved the review to Thursday 15:00 · he agreed');
  String get tl4Action => _('ดูบทสนทนา', 'See transcript');
  String get tl5Title => _('รอคุณอนุมัติ', 'Waiting on your approval');
  String get tl5Detail => _('ส่วนลด QT-2609 เกินอำนาจที่ตั้งไว้ (สูงสุด 5%)',
      'QT-2609 discount is above your limit (5% max)');
  String get tl5Action => _('ตัดสินใจตอนนี้', 'Decide now');
  String get tl6Title => _('เตือนกินข้าว', 'Reminded you to eat');
  String get tl6Detail =>
      _('เธอปิดแจ้งเตือนงานให้ 45 นาที', 'She muted work alerts for 45 minutes');
}
