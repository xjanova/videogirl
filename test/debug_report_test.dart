/// รายงานดีบัค — ด่านที่กันข้อมูลของเจ้าของไม่ให้ติดไปด้วย
///
/// 🔴 นี่คือฟีเจอร์ที่ทำลายคำสัญญาของแอปได้ง่ายที่สุด และเป็นแบบที่**ไม่มีใคร
/// เห็นตอนมันพัง** — รายงานที่พาคีย์ติดไปด้วยหน้าตาเหมือนรายงานปกติทุกประการ
/// เทสต์คือที่เดียวที่จับได้
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/diagnostics/debug_report.dart';
import 'package:videogirl/diagnostics/mind_log.dart';

void main() {
  group('🔴 ล้างความลับ', () {
    test('คีย์ที่เรารู้ค่า ต้องหายจากบรรทัด', () {
      const key = 'sk-proj-AbCd1234EfGh5678IjKl';
      final out = DebugReport.redact(
        'สมอง: ยิงด้วยคีย์ $key แล้วได้ 401',
        secrets: const [key],
      );
      expect(out, isNot(contains(key)));
      expect(out, contains('••••'));
    });

    test('รหัสสิทธิ์ก็ต้องหาย', () {
      const lic = 'GIGGOK-ABCD-1234-WXYZ';
      final out = DebugReport.redact('ร้าน: bearer $lic', secrets: const [lic]);
      expect(out, isNot(contains(lic)));
    });

    test('โผล่หลายครั้งในบรรทัดเดียว ต้องหายทุกครั้ง', () {
      const key = 'sk-proj-AbCd1234EfGh5678IjKl';
      final out = DebugReport.redact('$key และอีกที $key',
          secrets: const [key]);
      expect(out, isNot(contains(key)));
    });

    // 🔴 ด่านที่สอง — จับของที่เรา**ไม่รู้ค่า** เช่นเลขบัตรที่ผู้ใช้เผลอพิมพ์
    // แล้วมันไปโผล่ใน log · ด่านแรกช่วยไม่ได้เพราะเราไม่มีค่านั้นในมือ
    test('เลขบัตรที่หลุดเข้ามาเอง ต้องถูกตัดทั้งบรรทัด', () {
      final out = DebugReport.redact('ผู้ใช้พิมพ์ 4539 1488 0343 6467 มา');
      expect(out, isNot(contains('4539')));
      expect(out, DebugReport.redactedMark);
    });

    test('คีย์รูปแบบที่รู้จัก แม้ไม่ได้บอกค่า ก็ต้องถูกตัด', () {
      final out = DebugReport.redact('เจอ sk-abcdefghijklmnop1234567890 ใน log');
      expect(out, isNot(contains('abcdefghijklmnop')));
    });

    test('รหัสผ่านที่ติดมากับข้อความ ต้องถูกตัด', () {
      final out = DebugReport.redact('รหัสผ่าน: hunter2xyz');
      expect(out, DebugReport.redactedMark);
    });

    test('บรรทัดปกติต้องรอด ไม่ใช่ตัดทิ้งทุกอย่างเพื่อความปลอดภัย', () {
      const line = 'สมอง: ในเครื่อง Gemma 4 E2B (GPU)';
      expect(DebugReport.redact(line), line,
          reason: 'รายงานที่ตัดทุกบรรทัดทิ้ง ไม่ช่วยใครไล่บั๊กได้เลย');
    });

    // ค่าสั้น ๆ เอาไปแทนที่ไม่ได้ · 'th' จะกลืนตัวอักษรทุกที่ในบรรทัด
    test('ความลับที่สั้นเกินไป ต้องไม่ถูกเอาไปกวาดทั้งบรรทัด', () {
      const line = 'lang: th · brain: onDevice';
      expect(DebugReport.redact(line, secrets: const ['th']), line);
    });

    test('บรรทัดยาวเกินถูกตัด', () {
      final long = 'x' * 900;
      final out = DebugReport.redact(long);
      expect(out.length, lessThanOrEqualTo(DebugReport.maxLineChars));
      expect(out, endsWith('…'));
    });
  });

  test('เครื่องหมายที่ตัดออกต้องไม่เปลี่ยนตามภาษา', () {
    // รายงานถูกอ่านโดยคนไล่บั๊ก · เครื่องหมายที่เปลี่ยนภาษาไปตามเครื่อง
    // ที่ส่งมา ทำให้ค้นรายงานทั้งกองด้วยคำเดียวไม่ได้
    expect(DebugReport.redactedMark, matches(RegExp(r'^[ -~]+$')));
  });

  group('รูปทรงของรายงาน', () {
    ReportFacts sample({List<String> log = const []}) => DebugReport.build(
          app: const {'version': '0.1.0'},
          device: const {'os': 'android'},
          settings: const {'brain': 'onDevice'},
          status: const {'hasOwnKey': false},
          counts: const {'messages': 42},
          errors: const ['state: ต่อเน็ตไม่ได้'],
          logLines: log,
        );

    test('มีเลขรุ่นของรูปแบบไว้ให้หลังบ้านอ่าน', () {
      expect(sample()['report'], DebugReport.version);
    });

    test('🔴 นับข้อความ ไม่ได้เอาข้อความไป', () {
      final json = DebugReport.pretty(sample());
      expect(json, contains('"messages": 42'));
      // ไม่มีที่ทางให้เนื้อหาบทสนทนาอยู่เลยในโครงนี้
      expect(json, isNot(contains('"conversation"')));
      expect(json, isNot(contains('"memories":')));
    });

    test('ล้างความลับใน log ด้วย ไม่ใช่เฉพาะใน errors', () {
      const key = 'sk-proj-AbCd1234EfGh5678IjKl';
      final r = DebugReport.build(
        app: const {},
        device: const {},
        settings: const {},
        status: const {},
        counts: const {},
        errors: const [],
        secrets: const [key],
        logLines: const ['สมอง: ใช้ $key'],
      );
      expect(DebugReport.pretty(r), isNot(contains('AbCd1234')));
    });

    test('ชื่อไฟล์ใช้เวลา UTC — เวลาท้องถิ่นคือการบอกโซนเวลาโดยไม่ตั้งใจ', () {
      final name = DebugReport.fileName(DateTime.utc(2026, 9, 2, 7, 5, 3));
      expect(name, 'giggok-debug-20260902-070503.json');
    });
  });

  group('บันทึกล่าสุด', () {
    setUp(MindLog.clear);

    test('เก็บได้ไม่เกินเพดาน และเก็บของใหม่ไว้', () {
      for (var i = 0; i < MindLog.capacity + 50; i++) {
        MindLog.add('บรรทัดที่ $i');
      }
      expect(MindLog.count, MindLog.capacity);
      expect(MindLog.lines.last, contains('บรรทัดที่ ${MindLog.capacity + 49}'));
      expect(MindLog.lines.first, isNot(contains('บรรทัดที่ 0')));
    });

    test('มีเวลาสัมพัทธ์นำหน้า ไม่ใช่เวลาจริงของเครื่อง', () {
      MindLog.add('ทดสอบ');
      expect(MindLog.lines.single, matches(RegExp(r'^\[\s*\d+\.\d\] ทดสอบ$')));
    });

    // 🔴 ตัวดักต้องเป็นการ**แยกสำเนา** ไม่ใช่การเปลี่ยนทาง
    // กลืนไปเมื่อไหร่ การไล่บั๊กด้วย logcat พังทั้งแอปทันที
    test('ดักแล้วยังพิมพ์ออกเหมือนเดิม', () {
      final printed = <String>[];
      final original = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => printed.add('$m');
      addTearDown(() => debugPrint = original);

      MindLog.install();
      debugPrint('ข้อความทดสอบ');

      expect(printed, contains('ข้อความทดสอบ'),
          reason: 'ถ้ากลืนไป logcat จะว่างเปล่าทั้งแอป');
    });
  });
}
