import '../phone/call_transfer.dart';
import '../phone/hold_audio.dart';
import 'strings.dart';

/// ข้อความเรื่องพักสาย · โอนสายหาเจ้าของ · ช่วยปิดการขาย
///
/// เจ้าของ: "แก้เรื่องให้เธอ พักสายได้ เพื่อถามเรา ... มายด์สามารถโอนสาย ได้ ตั้งเบอร์ที่โอนสายได้"
extension HoldStrings on S {
  // ═══ หน้าตั้งค่า ══════════════════════════════════════
  String get holdCardTitle => pick('พักสาย โอนสาย และการขาย', 'Hold, transfer and sales');
  String get holdCardIntro => pick(
        'เธอพักสายคนโทรไปถามคุณได้ คนโทรได้ยินเพลงระหว่างรอ และโอนสายมาหาคุณอีกเบอร์เมื่อคนโทรขอคุยกับคุณเท่านั้น',
        'She can put callers on hold to ask you, play music while they wait, and put the call through to your '
            'other number when a caller insists on you',
      );

  String get holdAskIncoming => pick('พักสายถามฉันได้ระหว่างรับสาย', 'May put callers on hold to ask me');
  String get holdAskIncomingHint => pick(
        'คุยสดเท่านั้น · ถามผ่านแจ้งเตือน ตอบได้ 45 วินาที · จอดับหรือล็อกอยู่ เธอรับเรื่องไว้เองไม่พักสาย',
        'Live talk only · she asks through a notification you have 45 seconds to answer · with the screen off or '
            'locked she takes a message instead',
      );

  String get holdSoundLabel => pick('เสียงที่คนโทรได้ยินระหว่างพักสาย', 'What callers hear on hold');
  String holdSoundName(HoldSound s) => switch (s) {
        HoldSound.builtin => pick('เพลงในแอป', 'Built-in music'),
        HoldSound.file => pick('ไฟล์ของฉัน', 'My file'),
        HoldSound.none => pick('เงียบ', 'Silence'),
      };
  String get holdPick => pick('เลือกไฟล์เสียงจากเครื่อง', 'Pick an audio file');
  String get holdPickHint => pick(
        'เพลงหรือโฆษณา (mp3 m4a aac wav ogg opus flac) ไม่เกิน 12 MB · เล่นวนช่วงสองนาทีแรก เสียงเบากว่าเสียงเธอ',
        'Music or an ad (mp3 m4a aac wav ogg opus flac) up to 12 MB · the first two minutes loop, quieter than her voice',
      );
  String holdFileNow(String name) => pick('ไฟล์ที่ใช้: $name', 'Using: $name');
  String get holdPreview => pick('ลองฟัง', 'Preview');
  String get holdPreviewStop => pick('หยุดฟัง', 'Stop');
  String get holdClear => pick('ลบไฟล์', 'Remove file');
  String holdClearAsk(String name) => pick(
        'ลบ "$name" แล้วกลับไปใช้เพลงในแอปไหม',
        'Remove "$name" and go back to the built-in music?',
      );
  String get holdNotAudio => pick(
        'ไฟล์นี้ไม่ใช่ไฟล์เสียงที่รองรับ · ใช้ mp3 m4a aac wav ogg opus flac amr',
        'That is not a supported audio file · use mp3 m4a aac wav ogg opus flac amr',
      );
  String get holdTooLarge => pick('ไฟล์ใหญ่เกิน 12 MB', 'The file is over 12 MB');
  String get holdReadFailed => pick('อ่านไฟล์ไม่ได้ ลองเลือกใหม่อีกครั้ง', 'Could not read the file, try picking it again');
  String get holdCannotPlay => pick('เล่นไฟล์นี้ไม่ได้ ลองไฟล์อื่น', 'This file will not play, try another');
  String get holdLimit => pick(
        'เพลงเล่นตอนเธอพักสายถามคุณ · ตอนโอนสาย ระบบพักสายคนโทรในเครือข่าย เสียงจากแอปไปไม่ถึง คนโทรจะได้ยินเสียงรอของเครือข่ายแทน',
        'Music plays while she holds the caller to ask you · while she puts a call through, the network holds the '
            'caller and no app audio reaches them, so they hear the network hold tone instead',
      );

  String get transferSwitch => pick('โอนสายมาหาฉันได้', 'May put calls through to me');
  String get transferHint => pick(
        'เมื่อคนโทรยืนยันจะคุยกับคุณเท่านั้น เธอทวนชื่อกับเรื่อง ขอไปดูก่อนว่าคุณว่างไหม โทรหาคุณ บอกว่าใครโทรมาเรื่องอะไร '
            'แล้วรวมสายให้ · คุณไม่ว่างหรือไม่รับ เธอกลับไปบอกคนโทรและรับเรื่องไว้',
        'When a caller insists on you, she reads back their name and topic, says she will check if you are free, '
            'calls you, tells you who it is and why, then joins the calls · if you are busy or do not answer, she goes '
            'back and takes a message',
      );
  String get transferNumber => pick('เบอร์ที่ให้โอนมา', 'Number to put calls through to');
  String get transferNumberHint => pick('เช่น 0812345678', 'e.g. +66812345678');
  String get transferBadNumber => pick('เบอร์นี้ไม่ถูกรูปแบบ', 'That does not look like a phone number');
  String get transferBlocked =>
      pick('โอนไปเบอร์ฉุกเฉินหรือเบอร์ 1900 ไม่ได้', 'Calls cannot go to emergency or premium (1900) numbers');
  String get transferNeedsNumber => pick('ใส่เบอร์ก่อนเปิด', 'Add a number first');
  String get transferLimits => pick(
        'ต้องเป็นแอปโทรศัพท์หลัก และเครือข่ายต้องให้รวมสาย (ประชุมสาย) · รวมแล้วเครื่องนี้ยังอยู่ในสายแบบปิดไมค์ '
            'อย่ากดวางจากเครื่องนี้ บางเครือข่ายจะตัดทั้งวง',
        'GigGok must be the default phone app and your network must allow joining calls (conference) · after joining, '
            'this phone stays on the call with its mic off; do not hang up here, some networks end the whole call',
      );

  String get salesSwitch => pick('ช่วยปิดการขาย', 'Help close sales');
  String get salesHint => pick(
        'คนโทรสนใจสินค้าหรือบริการ เธอถามความต้องการ เสนอตัวเลือกที่ตรง แล้วจดชื่อ เบอร์ และเวลานัด · ราคามาจากคลังความรู้ของคุณเท่านั้น '
            'ไม่มีในคลัง เธอไม่เดา',
        'When a caller is interested in a product or service she asks what they need, suggests what fits, and takes '
            'their name, number and a time · prices come only from your call knowledge; she never guesses',
      );
  String get salesNote => pick('สั่งเรื่องการขายเพิ่ม (ไม่บังคับ)', 'Extra sales instructions (optional)');
  String get salesNoteHint =>
      pick('เช่น เน้นแพ็กเกจรายปี ลดได้ไม่เกิน 5% ต้องให้ฉันยืนยันก่อน', 'e.g. push yearly plans · any discount needs my OK');
  String get salesNeedsKnowledge => pick(
        'ยังไม่มีข้อมูลสินค้าหรือราคาในคลังความรู้ · ใส่ไว้ที่ "ข้อมูลสำหรับคนโทร" ก่อน',
        'There are no products or prices in your call knowledge yet · add them under call knowledge first',
      );

  // ═══ บทที่เธอพูดกับเจ้าของในสายที่สอง ══════════════════════
  //
  // คนโทรถูกพักสายในเครือข่าย ไม่ได้ยินส่วนนี้ · เจ้าของรับสายจากเบอร์ของเครื่องนี้

  TransferScript transferScript({required String me, required bool male, String name = '', String reason = ''}) {
    final end = male ? 'ครับ' : 'ค่ะ';
    final ask = male ? 'ครับ' : 'คะ';
    final who = name.trim().isEmpty ? pick('มีสายโทรมา', 'There is a call') : pick('คุณ${name.trim()} โทรมา', '${name.trim()} is calling');
    final about = reason.trim().isEmpty ? '' : pick('เรื่อง${reason.trim()}', ' about ${reason.trim()}');
    return TransferScript(
      brief: pick(
        'สวัสดี$end $me เอง$end $who$about$end จะรับสายเลยไหม$ask',
        "Hi, it's $me. $who$about. Will you take the call?",
      ),
      askAgain: pick('จะรับสายเลยไหม$ask ถ้ารับบอกว่าได้เลย ถ้าไม่สะดวกบอกว่าไม่สะดวก$end',
          'Will you take it now? Say yes to take it, or not now.'),
      connecting: pick('ต่อสายให้เลยนะ$ask', 'Putting them through now.'),
      declined: pick('รับทราบ$end เดี๋ยวรับเรื่องไว้ให้นะ$ask', 'Got it, I will take a message.'),
      cannotJoin: pick('ขอโทษ$end เครือข่ายไม่ให้รวมสาย เดี๋ยวรับเรื่องไว้ให้นะ$ask',
          'Sorry, the network will not join the calls. I will take a message.'),
    );
  }

  // ═══ จอสาย ═══════════════════════════════════════════
  String get transferRinging => pick('กำลังโทรหาเจ้าของ · คนโทรถูกพักสายไว้', 'Calling the owner · caller on hold');
  String get transferTalking => pick('กำลังคุยกับเจ้าของ', 'Talking to the owner');
  String get transferDoneLine => pick('(โอนสายให้เจ้าของแล้ว)', '(Put through to the owner)');
}
