/// ขั้นไหนต้องถามเจ้าของก่อน · ตัดสินด้วยโค้ด ไม่ใช่ด้วยคำสั่งใน prompt
///
/// เจ้าของเลือก (2026-10-31): ก่อนทำสิ่งที่ย้อนกลับไม่ได้ เช่น กดส่ง ชำระเงิน ซื้อ หรือลบ
/// ให้หยุดถามก่อนหนึ่งครั้ง ส่วนขั้นอื่นทำต่อเนื่องเอง
///
/// 🔴 สมองบอกเองได้ (`"risky": true`) แต่ไม่พึ่งแค่นั้น · ถ้าสมองอ่านจอผิดหรือถูกข้อความบนจอ
/// หลอก มันจะไม่ติดธงเอง · โค้ดนี้ดูคำบนปุ่มที่จะกดเอง: ปุ่มที่มีคำว่าส่ง จ่าย ซื้อ ลบ ฯลฯ
/// ถามเสมอ · ปุ่มตกลง/ยืนยันบนจอที่มีคำพวกนั้นก็ถาม · Enter ในช่องที่ไม่ใช่ช่องค้นหาก็ถาม
/// (Enter ในแชทคือส่ง) · สวิตช์ในหน้าตั้งค่าของเครื่องก็ถาม · ถามเกินดีกว่าส่งผิด
///
/// รายการคำเป็นภาษาไทยเพราะต้องเทียบกับปุ่มจริงบนเครื่อง (อยู่ในรายการยกเว้นของ i18n_test)
library;

import 'hands_bridge.dart';
import 'phone_action.dart';

abstract final class PhonePolicy {
  // คำอังกฤษเทียบเป็นคำ (ไม่ใช่ส่วนของคำ) · "send" ไม่ชน "sender"
  static const _riskyEn = [
    'send',
    'pay',
    'payment',
    'purchase',
    'buy',
    'order',
    'checkout',
    'check out',
    'book now',
    'reserve',
    'delete',
    'remove',
    'uninstall',
    'erase',
    'transfer',
    'withdraw',
    'donate',
    'subscribe',
    'post',
    'publish',
    'share',
    'tweet',
    'forward',
    'call',
    'dial',
    'submit',
    'sign out',
    'log out',
    'logout',
    'install',
    'block',
    'report',
    'unfriend',
    'unfollow',
    'reset',
    'clear data',
    'top up',
  ];

  // ภาษาไทยไม่มีช่องว่างระหว่างคำ จึงเทียบแบบมีอยู่ในข้อความ
  static const _riskyTh = [
    'ส่ง',
    'จ่าย',
    'ชำระ',
    'ซื้อ',
    'สั่งซื้อ',
    'สั่งอาหาร',
    'จอง',
    'ลบ',
    'ถอนการติดตั้ง',
    'โอน',
    'ถอนเงิน',
    'บริจาค',
    'สมัครสมาชิก',
    'โพสต์',
    'แชร์',
    'เผยแพร่',
    'โทร',
    'ออกจากระบบ',
    'ติดตั้ง',
    'บล็อก',
    'รายงาน',
    'ล้างข้อมูล',
    'รีเซ็ต',
    'เติมเงิน',
  ];

  // คำที่มีคำเสี่ยงอยู่ข้างในแต่ไม่ได้แปลว่าทำสิ่งนั้น (ชื่อแอปโทรศัพท์ ที่อยู่จัดส่ง)
  static const _harmlessTh = ['โทรศัพท์', 'จัดส่ง'];

  static const _affirmEn = ['ok', 'okay', 'yes', 'confirm', 'continue', 'proceed', 'agree', 'accept', 'allow'];
  static const _affirmTh = ['ตกลง', 'ใช่', 'ยืนยัน', 'ดำเนินการต่อ', 'ยอมรับ', 'อนุญาต'];

  // ช่องที่ Enter แปลว่าค้นหา/ไปที่ลิงก์ ไม่ใช่ส่ง
  static const _searchWords = ['search', 'find', 'url', 'address', 'query', 'ค้นหา', 'ค้น', 'ที่อยู่เว็บ'];

  static const settingsPackage = 'com.android.settings';

  /// ข้อความบนปุ่ม/ช่องรวมกัน (ข้อความ คำอธิบาย คำใบ้ ชื่อ id) ตัวเล็ก
  static String labelOf(ScreenNode n) =>
      [n.text, n.desc, n.hint, n.vid.replaceAll('_', ' ')].where((s) => s.isNotEmpty).join(' ').toLowerCase();

  static bool _hasWord(String text, List<String> words) {
    for (final w in words) {
      final re = RegExp('(^|[^a-z0-9])${RegExp.escape(w)}([^a-z0-9]|\$)');
      if (re.hasMatch(text)) return true;
    }
    return false;
  }

  static bool _hasThai(String text, List<String> words) {
    var t = text;
    for (final h in _harmlessTh) {
      t = t.replaceAll(h, ' ');
    }
    return words.any(t.contains);
  }

  /// ข้อความนี้มีคำที่แปลว่าทำสิ่งที่ย้อนกลับไม่ได้ไหม
  static bool riskyText(String text) {
    final t = text.toLowerCase();
    return _hasWord(t, _riskyEn) || _hasThai(t, _riskyTh);
  }

  static bool _affirm(String text) => _hasWord(text, _affirmEn) || _affirmTh.any(text.contains);

  static bool _isSearchField(ScreenNode n) {
    final l = labelOf(n);
    return _searchWords.any(l.contains);
  }

  /// ขั้นนี้ต้องถามเจ้าของก่อนไหม
  static bool needsOwner(PhoneAction a, PhoneScreen? screen) {
    if (a.risky) return true;
    switch (a.kind) {
      case 'tap':
      case 'long_press':
      case 'submit':
        break;
      default:
        // พิมพ์ เลื่อน ย้อนกลับ เปิดแอป ตั้งปลุก เปิดหน้าเพิ่มนัด/เขียนอีเมล = ยังไม่มีอะไรออกไปไหน
        return false;
    }
    final node = a.id == null ? null : screen?.byId(a.id!);
    if (a.kind == 'submit') {
      // ไม่รู้ว่าช่องไหน = ถามไว้ก่อน
      return node == null || !_isSearchField(node);
    }
    // กดโดยไม่รู้ว่ากดอะไร (id ไม่อยู่ในจอล่าสุด) · ฝั่ง Android จะตอบ stale เอง ไม่ต้องถาม
    if (node == null) return false;
    final label = labelOf(node);
    if (riskyText(label)) return true;
    if (screen != null) {
      if (screen.package == settingsPackage && node.check) return true;
      if (_affirm(label)) {
        for (final other in screen.nodes) {
          if (other.id != node.id && riskyText('${other.text} ${other.desc}')) return true;
        }
      }
    }
    return false;
  }
}
