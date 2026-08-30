import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/journal/mind_journal.dart';

/// สมุดบันทึกของมายด์
///
/// สิ่งที่คุ้มค่าเทสต์ที่สุดคือ **ของที่ต้องรอดจากการปิดแอป** เพราะนั่นคือ
/// เหตุผลเดียวที่คลาสนี้มีอยู่ — ก่อนหน้านี้แอปไม่ได้เก็บประวัติอะไรเลย
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mind-journal-');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  MindJournal make({DateTime Function()? clock}) =>
      MindJournal(dir: dir, clock: clock);

  group('บันทึกและอ่านกลับ', () {
    test('เขียนแล้วอ่านกลับได้หลังเปิดใหม่', () async {
      final a = make();
      await a.load();
      await a.record(JournalKind.asked, 'พรุ่งนี้ว่างไหม');
      await a.record(JournalKind.replied, 'ว่างค่ะ');

      // 🔴 นี่คือทั้งหมดที่คลาสนี้มีไว้ทำ — ของเดิมหายหมดตอนปิดแอป
      final b = make();
      await b.load();

      expect(b.count, 2);
      expect(b.entries.first.title, 'ว่างค่ะ');
    });

    test('ใหม่สุดอยู่บนสุดเสมอ', () async {
      final j = make();
      await j.load();
      await j.record(JournalKind.asked, 'เรื่องแรก');
      await j.record(JournalKind.asked, 'เรื่องที่สอง');

      expect(j.entries.map((e) => e.title), ['เรื่องที่สอง', 'เรื่องแรก']);
    });

    test('เรียงใหม่หลังโหลด แม้ไฟล์ถูกแก้มือให้สลับลำดับ', () async {
      final old = DateTime(2026, 1, 1);
      final recent = DateTime(2026, 8, 1);
      File('${dir.path}${Platform.pathSeparator}journal.json').writeAsStringSync(
        jsonEncode([
          {
            'id': 'a',
            'at': old.millisecondsSinceEpoch,
            'kind': 'asked',
            'title': 'เก่า'
          },
          {
            'id': 'b',
            'at': recent.millisecondsSinceEpoch,
            'kind': 'asked',
            'title': 'ใหม่'
          },
        ]),
      );

      final j = make();
      await j.load();

      expect(j.entries.first.title, 'ใหม่');
    });

    test('ไฟล์เสียต้องไม่ทำให้เปิดไม่ได้ เริ่มจากสมุดว่างแทน', () async {
      File('${dir.path}${Platform.pathSeparator}journal.json')
          .writeAsStringSync('{{{ ไม่ใช่ json');

      final j = make();
      await j.load();

      expect(j.isEmpty, isTrue);
    });

    test('หัวข้อว่างไม่บันทึก', () async {
      final j = make();
      await j.load();

      expect(await j.record(JournalKind.asked, '   '), isFalse);
      expect(j.isEmpty, isTrue);
    });
  });

  group('ห้ามบันทึกความลับ', () {
    test('หัวข้อที่เข้าข่ายความลับถูกปฏิเสธ', () async {
      final j = make();
      await j.load();

      // ไฟล์นี้อยู่บนดิสก์ ใครถอด backup ออกมาก็อ่านได้ ด่านเดียวกับความจำ
      expect(await j.record(JournalKind.asked, 'รหัสผ่าน: hunter2'), isFalse);
      expect(await j.record(JournalKind.asked, 'บัตร 4111111111111111'), isFalse);
      expect(j.isEmpty, isTrue);
    });

    test('ความลับที่ซ่อนอยู่ในรายละเอียด ก็ต้องไม่ผ่าน', () async {
      final j = make();
      await j.load();

      final ok = await j.record(JournalKind.replied, 'จดไว้ให้แล้ว',
          detail: 'otp 883921 ค่ะ');

      expect(ok, isFalse);
      expect(j.isEmpty, isTrue);
    });
  });

  group('เพดานและการตัด', () {
    test('ข้อความยาวถูกตัด ไม่ใช่เก็บทั้งบทสนทนา', () async {
      final j = make();
      await j.load();
      await j.record(JournalKind.replied, 'ก' * 400);

      expect(j.entries.single.title.length, kJournalMaxChars);
      expect(j.entries.single.title, endsWith('…'));
    });

    test('เกินเพดานแล้วตัดตัวเก่าสุดทิ้ง', () async {
      final j = make();
      await j.load();
      for (var i = 0; i < kJournalLimit + 12; i++) {
        await j.record(JournalKind.asked, 'เรื่องที่ $i');
      }

      expect(j.count, kJournalLimit);
      expect(j.entries.last.title, 'เรื่องที่ 12');
    });
  });

  group('การนับและจัดกลุ่ม', () {
    test('countToday นับเฉพาะวันนี้และเฉพาะชนิดที่ขอ', () async {
      final now = DateTime.now();
      var clock = now.subtract(const Duration(days: 2));
      final j = make(clock: () => clock);
      await j.load();

      await j.record(JournalKind.asked, 'เมื่อสองวันก่อน');
      clock = now;
      await j.record(JournalKind.asked, 'วันนี้ถาม');
      await j.record(JournalKind.replied, 'วันนี้ตอบ');
      await j.record(JournalKind.learned, 'วันนี้จำได้');

      expect(j.countToday({JournalKind.asked, JournalKind.replied}), 2);
      expect(j.countToday({JournalKind.learned}), 1);
      expect(j.countToday({JournalKind.pack}), 0);
      expect(j.today, hasLength(3));
    });

    test('byDay แยกวันถูก และมีครบทุกวันที่มีบันทึก', () async {
      final now = DateTime.now();
      var clock = now.subtract(const Duration(days: 1));
      final j = make(clock: () => clock);
      await j.load();

      await j.record(JournalKind.asked, 'เมื่อวาน');
      clock = now;
      await j.record(JournalKind.asked, 'วันนี้');

      expect(j.byDay.keys, hasLength(2));
    });
  });

  group('เจ้าของลบได้', () {
    test('ลบทีละรายการ', () async {
      final j = make();
      await j.load();
      await j.record(JournalKind.asked, 'อันแรก');
      await j.record(JournalKind.asked, 'อันสอง');

      await j.forget(j.entries.first.id);

      expect(j.entries.map((e) => e.title), ['อันแรก']);
    });

    test('ล้างทั้งหมดแล้วต้องไม่กลับมาหลังเปิดใหม่', () async {
      final a = make();
      await a.load();
      await a.record(JournalKind.asked, 'อะไรสักอย่าง');
      await a.clear();

      // ล้างแล้วแต่ไฟล์ยังมีของเก่า = ลบหลอก ซึ่งแย่กว่าไม่มีปุ่มลบ
      final b = make();
      await b.load();

      expect(b.isEmpty, isTrue);
    });
  });

  group('ชนิดที่ไม่รู้จัก', () {
    test('kind แปลก ๆ ในไฟล์ตกมาเป็น system ไม่ใช่ทำให้ทั้งไฟล์พัง', () async {
      File('${dir.path}${Platform.pathSeparator}journal.json').writeAsStringSync(
        jsonEncode([
          {
            'id': 'a',
            'at': DateTime.now().millisecondsSinceEpoch,
            'kind': 'ชนิดที่ไม่มีอยู่',
            'title': 'ยังอ่านได้'
          },
        ]),
      );

      final j = make();
      await j.load();

      expect(j.entries.single.kind, JournalKind.system);
    });

    test('แถวที่ขาดช่องจำเป็นถูกทิ้ง แต่แถวอื่นยังอยู่', () async {
      File('${dir.path}${Platform.pathSeparator}journal.json').writeAsStringSync(
        jsonEncode([
          {'id': 'a', 'kind': 'asked'},
          {
            'id': 'b',
            'at': DateTime.now().millisecondsSinceEpoch,
            'kind': 'asked',
            'title': 'ใช้ได้'
          },
        ]),
      );

      final j = make();
      await j.load();

      expect(j.count, 1);
      expect(j.entries.single.title, 'ใช้ได้');
    });
  });
}
