import '../hands/phone_task.dart';
import 'strings.dart';

/// อนุญาตถาวร · เจ้าของ: "ให้อนุญาตถาวรได้หมด แต่อันไหนเสี่ยง เพียงขั้นเตือนก่อนอนุญาต
/// เพราะบางคนต้องการเอาไว้รันเรื่องเงินอย่างเดียว"
extension TrustStrings on S {
  String handsKindLabel(PhoneStepKind k) => switch (k) {
        PhoneStepKind.money => pick('เรื่องเงิน (จ่าย ซื้อ โอน จอง)', 'money (pay, buy, transfer, book)'),
        PhoneStepKind.erase => pick('ลบ / ออกจากระบบ / บล็อก', 'deleting, signing out, blocking'),
        PhoneStepKind.settings => pick('สวิตช์ในตั้งค่าเครื่อง', 'phone settings switches'),
        PhoneStepKind.send => pick('ส่ง / โพสต์ / แชร์ / โทร', 'sending, posting, sharing, calling'),
        PhoneStepKind.unknown => pick('ปุ่มที่ดูไม่ออกว่าทำอะไร', 'buttons she cannot read'),
      };

  String get handsAlwaysCheck => pick('เรื่องแบบนี้ในแอปนี้ ทำได้เลย ไม่ต้องถามอีก', 'Do this kind of step in this app without asking again');
  String get handsAlwaysWarnTitle => pick('อนุญาตถาวรเรื่องเสี่ยง?', 'Allow a risky step for good?');
  String handsAlwaysWarnBody(String kind, String app) => pick(
        'ขั้นนี้เป็น$kind ใน $app · ถ้าอนุญาตถาวร มายด์จะทำเรื่องแบบนี้ในแอปนี้เองทุกครั้งโดยไม่ถาม '
            'รวมถึงตอนที่สมองอ่านจอผิด · ยกเลิกได้ที่ ตั้งค่า › สิ่งที่อนุญาตถาวร',
        'This step is $kind in $app · if you allow it for good, Mind will do this kind of step in this app every time '
            'without asking, even when the brain misreads the screen · undo it in Settings › Allowed for good',
      );
  String get handsAlwaysConfirm => pick('ยืนยันอนุญาตถาวร', 'Allow for good');
  String handsTrustGranted(String app, String kind) =>
      pick('จำไว้แล้วค่ะ: $kind ใน $app ต่อไปทำได้เลยไม่ถาม', 'Got it: $kind in $app, from now on without asking');
  String handsTrustedDid(String action, String app) =>
      pick('$action ใน $app ให้เลยนะคะ (คุณอนุญาตไว้ถาวร)', 'Did "$action" in $app (you allowed this for good)');

  String get trustCard => pick('สิ่งที่อนุญาตถาวร', 'Allowed for good');
  String get trustIntro => pick(
        'งานในเครื่องที่มายด์ทำได้เลยไม่ต้องถาม (ติ๊กในกล่องถาม) · เรื่องเสี่ยงมีขั้นเตือนก่อนเสมอ',
        'Phone steps Mind does without asking (ticked in the ask box) · risky ones always warn first',
      );
  String get trustNone => pick('ยังไม่มี · มายด์ถามก่อนทุกขั้นที่ย้อนกลับไม่ได้', 'Nothing yet · Mind asks before every step that cannot be undone');
  String get trustRemove => pick('เลิกอนุญาต', 'Remove');
  String get trustRemoveAll => pick('เลิกอนุญาตทั้งหมด', 'Remove all');
  String get trustRemoveAllAsk => pick('เลิกอนุญาตทั้งหมด? มายด์จะกลับมาถามก่อนทุกขั้น', 'Remove all? Mind will ask before every step again');
}
