import 'strings.dart';

/// ข้อความเรื่องตอบแชท WhatsApp · เจ้าของ: "ทำให้เธอตอบ what app ได้ด้วย · เมื่อมีคนแชทมา"
extension ChatStrings on S {
  String get chatsCard => pick('ช่วยตอบแชท WhatsApp', 'Help answer WhatsApp chats');
  String get chatsIntro => pick(
        'มีคนทักแชท WhatsApp มา เธอร่างคำตอบให้ แล้วถามคุณก่อนส่งทุกครั้ง (ส่งเลย · แก้แล้วส่ง · ไม่ส่ง) · '
            'แชทกลุ่มไม่ตอบ · ข้อความที่ทักมาส่งไปให้สมองที่คุณเลือกอ่านเพื่อร่างคำตอบ',
        'When someone messages you on WhatsApp she drafts a reply and asks you before every send (Send · Edit and '
            'send · Don\'t send) · group chats are left alone · the message goes to the brain you chose so it can draft',
      );
  String get chatsSwitch => pick('ร่างคำตอบแชท WhatsApp ให้ฉัน', 'Draft WhatsApp replies for me');
  String get chatsSwitchHint => pick(
        'ไม่ส่งเองเด็ดขาด · ถามผ่านแจ้งเตือนเด้ง และกล่องลอยเมื่อเธอกำลังใช้มือถืออยู่',
        'Never sends by herself · asks through a pop-up notification, plus a floating box while her hands are on',
      );
  String get chatsNeedAccess => pick(
        'ต้องให้สิทธิ์ "การเข้าถึงการแจ้งเตือน" กับ GigGok หนึ่งครั้ง เธอถึงจะเห็นข้อความที่เข้ามา',
        'GigGok needs "Notification access" once so she can see incoming messages',
      );
  String get chatsGrant => pick('เปิดหน้าให้สิทธิ์', 'Open the permission page');
  String get chatsReady => pick('พร้อม · มีคนทักมาเมื่อไหร่ เธอจะร่างแล้วถามคุณ', 'Ready · she drafts and asks you when someone writes');
  String get chatsGrantFailed => pick(
        'เปิดหน้าให้สิทธิ์ไม่ได้ · ไปที่ ตั้งค่า › แอป › สิทธิ์พิเศษ › การเข้าถึงการแจ้งเตือน',
        'Could not open it · go to Settings › Apps › Special access › Notification access',
      );

  String chatAskTitle(String who) => pick('ตอบ $who ทาง WhatsApp?', 'Reply to $who on WhatsApp?');
  String chatAskBody(String text, String draft) =>
      pick('เขาพิมพ์มา: "$text"\n\nมายด์จะตอบ: $draft', 'They wrote: "$text"\n\nMind would reply: $draft');
  String chatDrafted(String who, String text, String draft) => pick(
        '$who ทัก WhatsApp มาว่า "$text" · มายด์ร่างคำตอบไว้แล้ว รอคุณกดส่งในแจ้งเตือน:\n$draft',
        '$who wrote on WhatsApp: "$text" · I drafted a reply, waiting for you to tap Send in the notification:\n$draft',
      );
  String chatDraftFailed(String who, String text) => pick(
        '$who ทัก WhatsApp มาว่า "$text" · มายด์ร่างคำตอบไม่สำเร็จ (สมองไม่ตอบ) คุณตอบเองใน WhatsApp นะคะ',
        '$who wrote on WhatsApp: "$text" · I could not draft a reply (the brain did not answer), please reply in WhatsApp',
      );
  String chatSent(String who, String text) =>
      pick('ส่งคำตอบให้ $who ทาง WhatsApp แล้ว: "$text"', 'Sent your reply to $who on WhatsApp: "$text"');
  String get chatExpired => pick(
        'ส่งไม่ได้ค่ะ แจ้งเตือนของแชทนั้นหายไปแล้ว (เปิดอ่านใน WhatsApp หรือเขาทักมาใหม่) ตอบใน WhatsApp เองนะคะ',
        'Could not send: that chat\'s notification is gone (read in WhatsApp, or they wrote again) · reply in WhatsApp',
      );
  String get chatSendFailed => pick('ส่งคำตอบ WhatsApp ไม่สำเร็จ ตอบใน WhatsApp เองนะคะ', 'The WhatsApp reply failed · please reply in WhatsApp');
}
