import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/update/updater.dart';

void main() {
  group('เทียบเวอร์ชัน', () {
    // เทียบเป็นตัวเลขทีละส่วน ไม่ใช่เทียบสตริง
    test('1.10.0 ใหม่กว่า 1.9.0 (จุดที่เทียบสตริงแล้วพลาด)', () {
      expect(Updater.isNewer('1.10.0', '1.9.0'), isTrue);
      expect(Updater.isNewer('1.9.0', '1.10.0'), isFalse);
    });

    test('เวอร์ชันเท่ากันไม่ถือว่าใหม่กว่า', () {
      expect(Updater.isNewer('1.2.3', '1.2.3'), isFalse);
    });

    test('ขยับ major/minor/patch ทีละชั้น', () {
      expect(Updater.isNewer('2.0.0', '1.99.99'), isTrue);
      expect(Updater.isNewer('1.3.0', '1.2.99'), isTrue);
      expect(Updater.isNewer('1.2.4', '1.2.3'), isTrue);
      expect(Updater.isNewer('1.2.3', '1.2.4'), isFalse);
    });

    test('ตัด build metadata และ pre-release ทิ้งก่อนเทียบ', () {
      // pubspec ของ Flutter เขียน 1.2.3+45 เป็นปกติ
      expect(Updater.isNewer('1.2.4+9', '1.2.3+120'), isTrue);
      expect(Updater.isNewer('1.2.3+2', '1.2.3+1'), isFalse);
      expect(Updater.isNewer('1.3.0-beta.1', '1.2.9'), isTrue);
    });

    test('เวอร์ชันสั้นกว่าสามส่วนก็เทียบได้', () {
      expect(Updater.isNewer('2', '1.9.9'), isTrue);
      expect(Updater.isNewer('1.2', '1.2.0'), isFalse);
    });

    test('ยังไม่รู้เวอร์ชันปัจจุบัน ให้ถือว่ามีของใหม่เสมอ', () {
      // กันกรณี PackageInfo อ่านไม่ได้ ดีกว่าเงียบแล้วไม่มีวันอัปเดต
      expect(Updater.isNewer('1.0.0', ''), isTrue);
    });
  });
}
