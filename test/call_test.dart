import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/journal/mind_journal.dart';
import 'package:videogirl/phone/call_watch.dart';
import 'package:videogirl/system/permissions.dart';

/// สายโทรเข้า
///
/// สิ่งที่คุ้มค่าเทสต์ที่สุดคือ **การไม่จดซ้ำ** และ **การแยกเบอร์ว่างออกจาก
/// เบอร์ที่อ่านไม่ได้** เพราะทั้งสองอย่างเกิดจริงบน Android และเงียบทั้งคู่
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late List<MethodCall> sent;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('mind-call-');
    sent = [];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kSystemChannel, null);
    // Windows ล็อกไฟล์ที่ยังเปิดค้าง · เก็บกวาดไม่ได้ไม่ใช่เรื่องที่เทสต์ต้องล้ม
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on FileSystemException {
      // ปล่อยให้ระบบเก็บ temp เอง
    }
  });

  void mock({required bool granted, Object? calls}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kSystemChannel, (call) async {
      sent.add(call);
      if (call.method == 'recentCalls') return calls;
      if (call.method == 'callGranted') return granted;
      if (call.method == 'watchCalls') return true;
      if (call.method == 'answerCall') return true;
      if (call.method == 'hangUp') return true;
      return false;
    });
  }

  Map<String, Object?> logRow(
    String? name,
    String? number,
    int type,
    DateTime at, {
    int id = 1,
    int seconds = 0,
  }) =>
      {
        'id': id,
        'number': number,
        'name': name,
        'type': type,
        'at': at.millisecondsSinceEpoch,
        'seconds': seconds,
      };

  /// ยิงสัญญาณสายจากฝั่ง Android เข้ามาเหมือนของจริง
  Future<void> pushState(int state, {String? number, String? name}) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      kSystemChannel.name,
      kSystemChannel.codec.encodeMethodCall(MethodCall('onCallState', {
        'state': state,
        'number': number,
        'name': name,
      })),
      (_) {},
    );
  }

  group('อ่านประวัติการโทร', () {
    test('ยังไม่ได้ให้สิทธิ์ ต้องเป็น denied ไม่ใช่ ready ที่ว่างเปล่า', () async {
      mock(granted: false);
      final w = CallWatch();

      await w.refresh();

      expect(w.stage, CallStage.denied);
    });

    test('ให้สิทธิ์แล้วแต่ไม่มีประวัติ ต้องเป็น ready', () async {
      mock(granted: true, calls: const []);
      final w = CallWatch();

      await w.refresh();

      expect(w.stage, CallStage.ready);
      expect(w.recent, isEmpty);
    });

    test('null จากฝั่ง Android คือ "อ่านไม่ได้" ไม่ใช่ "ไม่มีสาย"', () async {
      mock(granted: true, calls: null);
      final w = CallWatch();

      await w.refresh();

      expect(w.stage, isNot(CallStage.ready));
    });

    test('แปลงชนิดสายถูกตามรหัสของ CallLog', () async {
      final now = DateTime.now();
      mock(granted: true, calls: [
        logRow('แม่', '0812345678', 1, now, id: 1),
        logRow(null, '021112222', 3, now, id: 2),
        logRow('ต้น', '0899999999', 2, now, id: 3),
        logRow(null, null, 5, now, id: 4),
      ]);
      final w = CallWatch();

      await w.refresh();

      expect(w.recent.map((c) => c.type), [
        CallType.incoming,
        CallType.missed,
        CallType.outgoing,
        CallType.rejected,
      ]);
    });

    test('รหัสชนิดที่ไม่รู้จักตกเป็น unknown ไม่ทำให้ทั้งรายการพัง', () async {
      mock(granted: true,
          calls: [logRow('x', '0812345678', 99, DateTime.now())]);
      final w = CallWatch();

      await w.refresh();

      expect(w.recent.single.type, CallType.unknown);
    });
  });

  group('เบอร์กับชื่อที่หายไป', () {
    test('มีชื่อ ใช้ชื่อ · ไม่มีชื่อ ใช้เบอร์', () async {
      final now = DateTime.now();
      mock(granted: true, calls: [
        logRow('แม่', '0812345678', 1, now, id: 1),
        logRow(null, '021112222', 1, now, id: 2),
      ]);
      final w = CallWatch();

      await w.refresh();

      expect(w.recent[0].who, 'แม่');
      expect(w.recent[1].who, '021112222');
    });

    /// สายที่ซ่อนเบอร์มีจริง · ต้องไม่พังและต้องไม่โชว์คำว่า null
    test('สายที่ไม่มีทั้งชื่อและเบอร์ ยังเป็นสายอยู่', () async {
      mock(granted: true,
          calls: [logRow(null, null, 3, DateTime.now())]);
      final w = CallWatch();

      await w.refresh();

      expect(w.recent, hasLength(1));
      expect(w.recent.single.who, isEmpty);
      expect(w.recent.single.name, isNull);
    });

    test('ชื่อหรือเบอร์ที่เป็นช่องว่างล้วน ถือว่าไม่มี', () async {
      mock(granted: true,
          calls: [logRow('   ', '  ', 1, DateTime.now())]);
      final w = CallWatch();

      await w.refresh();

      expect(w.recent.single.name, isNull);
      expect(w.recent.single.number, isNull);
    });
  });

  group('จดลงสมุดบันทึก', () {
    test('สายวางแล้วถึงจด ไม่ใช่ตอนกำลังดัง', () async {
      final journal = MindJournal(dir: dir);
      await journal.load();
      mock(granted: true, calls: [
        logRow('แม่', '0812345678', 1, DateTime.now(), id: 7),
      ]);
      final w = CallWatch(journal: journal);
      await w.start();

      await pushState(1, number: '0812345678', name: 'แม่');
      expect(journal.isEmpty, isTrue, reason: 'ยังดังอยู่ ยังไม่ควรจด');

      await pushState(0);

      expect(journal.count, 1);
      expect(journal.entries.single.kind, JournalKind.call);
      expect(journal.entries.single.title, 'แม่');
    });

    /// 🔴 รีเฟรชเฉย ๆ ต้องไม่จดซ้ำ ไม่งั้นเปิดแอปทีก็ได้สายเดิมเพิ่มอีกอัน
    test('สายเดิมไม่ถูกจดซ้ำแม้จะมีสัญญาณเข้ามาอีกรอบ', () async {
      final journal = MindJournal(dir: dir);
      await journal.load();
      mock(granted: true, calls: [
        logRow('แม่', '0812345678', 1, DateTime.now(), id: 7),
      ]);
      final w = CallWatch(journal: journal);
      await w.start();

      await pushState(1);
      await pushState(0);
      await pushState(2);
      await pushState(0);

      expect(journal.count, 1);
    });

    /// บันทึกการโทรมีของตั้งแต่ก่อนแอปนี้มีอยู่ · ยัดทั้งกองเข้าสมุดคือ
    /// กลบทุกอย่างที่เธอทำจริงจนหมด
    test('สายเก่าที่จบไปนานแล้วไม่ถูกจด', () async {
      final journal = MindJournal(dir: dir);
      await journal.load();
      mock(granted: true, calls: [
        logRow('เมื่อวาน', '0812345678', 1,
            DateTime.now().subtract(const Duration(days: 1)), id: 9),
      ]);
      final w = CallWatch(journal: journal);
      await w.start();

      await pushState(1);
      await pushState(0);

      expect(journal.isEmpty, isTrue);
    });
  });

  group('สถานะสายและการนับ', () {
    test('รู้ว่ากำลังมีสายเข้าและเป็นใคร', () async {
      mock(granted: true, calls: const []);
      final w = CallWatch();
      await w.start();

      await pushState(1, number: '0812345678', name: 'แม่');

      expect(w.ringing, isTrue);
      expect(w.ringingWho, 'แม่');
    });

    test('ไม่รู้ชื่อ ให้ใช้เบอร์ · วางสายแล้วต้องเคลียร์', () async {
      mock(granted: true, calls: const []);
      final w = CallWatch();
      await w.start();

      await pushState(1, number: '021112222');
      expect(w.ringingWho, '021112222');

      await pushState(0);
      expect(w.ringingWho, isNull);
      expect(w.ringing, isFalse);
    });

    test('นับเฉพาะสายของวันนี้ และแยกสายที่ไม่ได้รับ', () async {
      final now = DateTime.now();
      mock(granted: true, calls: [
        logRow('วันนี้รับ', '1', 1, now, id: 1),
        logRow('วันนี้ไม่ได้รับ', '2', 3, now, id: 2),
        logRow('เมื่อวาน', '3', 1, now.subtract(const Duration(days: 1)), id: 3),
      ]);
      final w = CallWatch();

      await w.refresh();

      expect(w.today, hasLength(2));
      expect(w.missedToday.map((c) => c.who), ['วันนี้ไม่ได้รับ']);
    });
  });

  group('ก้อนข้อความสำหรับ prompt', () {
    test('ไม่มีสายวันนี้ต้องได้ค่าว่าง ไม่ใช่หัวข้อลอย ๆ', () async {
      mock(granted: true, calls: const []);
      final w = CallWatch();

      await w.refresh();

      expect(w.promptBlock(), isEmpty);
    });

    test('บอกเวลา ชนิด และใคร · ตัดตามเพดาน', () async {
      final now = DateTime.now();
      mock(granted: true, calls: [
        for (var i = 0; i < 5; i++)
          logRow('คน$i', '08100000$i', i.isEven ? 1 : 3, now, id: i),
      ]);
      final w = CallWatch();

      await w.refresh();

      final block = w.promptBlock(limit: 3);
      expect(block.split('\n'), hasLength(3));
      expect(block, contains('คน0'));
      expect(block, contains('missed'));
    });
  });
}
