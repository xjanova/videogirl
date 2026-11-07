import 'strings.dart';

/// ข้อความเรื่องตอบแชท · เจ้าของ: "ทำให้เธอตอบ what app ได้ด้วย" → "เธอตอบแทนเราได้เอง ทุกแชท เหมือนรับโทรศัพท์"
extension ChatStrings on S {
  String get chatsCard => pick('ช่วยตอบแชท (WhatsApp · LINE · Messenger …)', 'Help answer chats (WhatsApp · LINE · Messenger …)');
  String get chatsIntro => pick(
        'มีคนทักแชทมา เธอตอบในฐานะเลขาของคุณ แนะนำตัวก่อนเมื่อคุยกับใครครั้งแรก และตอบภาษาเดียวกับที่เขาพิมพ์มา · '
            'ตั้งต้นเธอถามคุณก่อนส่งทุกครั้ง (ส่งเลย · แก้แล้วส่ง · ไม่ส่ง) · แชทกลุ่มและ SMS ไม่ตอบ · '
            'ข้อความที่ทักมาส่งไปให้สมองที่คุณเลือกอ่านเพื่อร่างคำตอบ',
        'When someone messages you she answers as your secretary, introduces herself the first time, and replies in '
            'their language · by default she asks you before every send (Send · Edit and send · Don\'t send) · group '
            'chats and SMS are left alone · the message goes to the brain you chose so it can draft',
      );
  String get chatsSwitch => pick('ร่างคำตอบแชทให้ฉัน', 'Draft chat replies for me');
  String get chatsSwitchHint => pick(
        'ถามผ่านแจ้งเตือนเด้ง และกล่องลอยเมื่อเธอกำลังใช้มือถืออยู่',
        'Asks through a pop-up notification, plus a floating box while her hands are on',
      );
  String get chatsAuto => pick('ตอบเองทุกแชท ไม่ต้องถาม', 'Answer every chat herself, without asking');
  String get chatsAutoHint => pick(
        'เหมือนรับโทรศัพท์แทน: คุยได้ทุกเรื่อง แต่ไม่รับปากแทนคุณ · ยังถามคุณก่อนเมื่อข้อความเกี่ยวกับรหัส/เงิน · '
            'เมื่อคุณเข้าไปพิมพ์ในห้องนั้นเอง · หรือตอบคนเดิมถี่เกินไป',
        'Like answering the phone for you: chats about anything but never commits for you · still asks you first when '
            'the message is about codes or money, when you typed in that chat yourself, or when one person gets too many replies',
      );
  String get chatsAutoWarnTitle => pick('ให้มายด์ตอบแชทเองทุกแชท?', 'Let Mind answer every chat herself?');
  String get chatsAutoWarnBody => pick(
        'เธอจะส่งข้อความจากบัญชีของคุณเองโดยไม่ถามก่อน ใครทักมาก็ตอบ (ยกเว้นกลุ่ม) · สมองอาจตอบผิดหรือไม่ตรงใจได้ · '
            'คุณดูทุกข้อความที่เธอส่งได้ในแชทกับเธอ และปิดสวิตช์นี้ได้ทุกเมื่อ',
        'She will send messages from your accounts without asking first, to anyone who writes (except groups) · the '
            'brain can get things wrong · every message she sends shows up in your chat with her, and you can turn this '
            'off at any time',
      );
  String get chatsAutoWarnOk => pick('เปิดเลย', 'Turn it on');
  String get chatsTrusted => pick('คนที่ส่งได้เลยไม่ต้องถาม', 'People she replies to without asking');
  String get chatsTrustedNone => pick(
        'ยังไม่มี · ติ๊ก "คนนี้ส่งได้เลย" ในกล่องถาม แล้วคนนั้นจะมาอยู่ที่นี่',
        'Nobody yet · tick "Send to this person without asking" in the ask box and they show up here',
      );
  String get chatsUntrust => pick('เลิกอนุญาต', 'Remove');
  String get chatsNeedAccess => pick(
        'ต้องให้สิทธิ์ "การเข้าถึงการแจ้งเตือน" กับ GigGok หนึ่งครั้ง เธอถึงจะเห็นข้อความที่เข้ามา',
        'GigGok needs "Notification access" once so she can see incoming messages',
      );
  String get chatsGrant => pick('เปิดหน้าให้สิทธิ์', 'Open the permission page');
  String get chatsReady => pick('พร้อม · มีคนทักมาเมื่อไหร่ เธอจะตอบแทนคุณ', 'Ready · she answers for you when someone writes');
  String get chatsGrantFailed => pick(
        'เปิดหน้าให้สิทธิ์ไม่ได้ · ไปที่ ตั้งค่า › แอป › สิทธิ์พิเศษ › การเข้าถึงการแจ้งเตือน',
        'Could not open it · go to Settings › Apps › Special access › Notification access',
      );

  String chatAskTitle(String who, String app) => pick('ตอบ $who ทาง $app?', 'Reply to $who on $app?');
  String chatAskBody(String text, String draft) =>
      pick('เขาพิมพ์มา: "$text"\n\nมายด์จะตอบ: $draft', 'They wrote: "$text"\n\nMind would reply: $draft');
  String chatDrafted(String who, String app, String text, String draft) => pick(
        '$who ทัก $app มาว่า "$text" · มายด์ร่างคำตอบไว้แล้ว รอคุณกดส่งในแจ้งเตือน:\n$draft',
        '$who wrote on $app: "$text" · I drafted a reply, waiting for you to tap Send in the notification:\n$draft',
      );
  String chatDraftFailed(String who, String app, String text) => pick(
        '$who ทัก $app มาว่า "$text" · มายด์ร่างคำตอบไม่สำเร็จ (สมองไม่ตอบ) คุณตอบเองนะคะ',
        '$who wrote on $app: "$text" · I could not draft a reply (the brain did not answer), please reply yourself',
      );
  String chatSent(String who, String text) => pick('ส่งคำตอบให้ $who แล้ว: "$text"', 'Sent your reply to $who: "$text"');
  String chatAutoSent(String who, String said, String text) =>
      pick('$who ทักมาว่า "$said" · มายด์ตอบแทนไปแล้ว: "$text"', '$who wrote "$said" · I answered for you: "$text"');
  String get chatExpired => pick(
        'ส่งไม่ได้ค่ะ แจ้งเตือนของแชทนั้นหายไปแล้ว (เปิดอ่านในแอปแชท หรือเขาทักมาใหม่) ตอบเองในแอปนะคะ',
        'Could not send: that chat\'s notification is gone (read in the chat app, or they wrote again) · reply there',
      );
  String get chatSendFailed => pick('ส่งคำตอบไม่สำเร็จ ตอบเองในแอปแชทนะคะ', 'The reply failed · please reply in the chat app');
}
