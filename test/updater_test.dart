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

  // ผู้ใช้ต้องไม่มีทางรู้ว่าไฟล์อัปเดตมาจากบริการไหน · ด่านนี้อยู่ฝั่งแอป
  // เพราะรุ่นที่ปล่อยไปแล้วแก้เนื้อย้อนหลังไม่ได้ (v0.1.0-v0.1.2 มีลิงก์ติดมา)
  // และเนื้อ release แก้ด้วยมือทีหลังได้เสมอ
  group('ล้างบันทึกรุ่นก่อนขึ้นจอ', () {
    test('บรรทัด Full Changelog ที่มีลิงก์ต้องหายทั้งบรรทัด', () {
      // นี่คือเนื้อจริงของ v0.1.0 ที่ปล่อยไปแล้ว
      const raw = '**Full Changelog**: https://github.com/xjanova/videogirl'
          '/commits/v0.1.0';
      expect(Updater.cleanNotes(raw), isEmpty);
    });

    test('ไม่ว่าเนื้อจะเป็นยังไง ต้องไม่มีลิงก์หลุดออกไป', () {
      const raw = 'ซ่อมเสียง see https://example.com/a?b=1 แล้ว';
      final out = Updater.cleanNotes(raw);
      expect(out, isNot(contains('http')));
      expect(out, contains('ซ่อมเสียง'));
    });

    test('ชื่อบัญชีของระบบต้นทางต้องไม่หลุดไปด้วย', () {
      expect(Updater.cleanNotes('ซ่อมโดย @xjanova แล้ว'), isNot(contains('@')));
    });

    test('มาร์กดาวน์ที่ Text เรนเดอร์ไม่ได้ต้องไม่โผล่เป็นสัญลักษณ์เปล่า', () {
      final out = Updater.cleanNotes('## What \n* ซ่อมเสียงแล้ว');
      expect(out, isNot(contains('#')));
      expect(out, isNot(contains('*')));
      expect(out, contains('ซ่อมเสียงแล้ว'));
    });

    test('ข้อความปกติต้องอยู่ครบ ไม่ใช่ล้างจนหมด', () {
      const raw = '· ซ่อมเสียง\n· กันเครื่องสเปคไม่ถึง';
      final out = Updater.cleanNotes(raw);
      expect(out.split('\n').length, 2);
      expect(out, contains('กันเครื่องสเปคไม่ถึง'));
    });

    test('เนื้อว่างต้องไม่พัง', () {
      expect(Updater.cleanNotes(''), isEmpty);
      expect(Updater.cleanNotes('\n\n  \n'), isEmpty);
    });
  });
}
