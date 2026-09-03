/// รายงานดีบัค — ด่านที่กันข้อมูลของเจ้าของไม่ให้ติดไปด้วย
///
/// 🔴 นี่คือฟีเจอร์ที่ทำลายคำสัญญาของแอปได้ง่ายที่สุด และเป็นแบบที่**ไม่มีใคร
/// เห็นตอนมันพัง** — รายงานที่พาคีย์ติดไปด้วยหน้าตาเหมือนรายงานปกติทุกประการ
/// เทสต์คือที่เดียวที่จับได้
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/diagnostics/debug_report.dart';
import 'package:videogirl/diagnostics/debug_reporter.dart';
import 'package:videogirl/diagnostics/mind_log.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  _autoSendGroup();
  _bugReportShapeGroup();

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

/// 🔴 รูปที่ส่งเข้าระบบรายงานของบ้าน — ผิดฟิลด์เดียว = ถูกปฏิเสธเงียบ ๆ
///
/// ยิงจริงไปแล้วครั้งหนึ่งได้ 422 เพราะ `report_type: diagnostic` ซึ่งมีอยู่
/// 3,520 แถวในฐาน แต่ validator ที่ deploy อยู่ไม่รับ · เทสต์นี้ล็อกค่าที่
/// **ยิงผ่านจริงแล้ว** ไว้ ไม่ใช่ค่าที่อนุมานจากข้อมูลเก่าในฐาน
void _bugReportShapeGroup() {
  group('รูปที่ส่งเข้าระบบรายงานของ xman studio', () {
    ReportFacts facts({List<String> errors = const []}) => DebugReport.build(
          app: const {'version': '0.1.10', 'build': '11'},
          device: const {'os': 'android', 'osVersion': 'Android 16 (API 36)'},
          settings: const {'brain': 'onDevice'},
          status: const {'localStage': 'missing'},
          counts: const {'messages': 12},
          errors: errors,
        );

    test('ปลายทางคือระบบเดิมของบ้าน ไม่ใช่ของที่ทำขึ้นใหม่', () {
      expect(DebugReporter.endpointOf('https://xman4289.com'),
          'https://xman4289.com/api/v1/bug-reports');
      // ขีดท้ายเกินมาต้องไม่กลายเป็น //api
      expect(DebugReporter.endpointOf('https://xman4289.com/'),
          'https://xman4289.com/api/v1/bug-reports');
    });

    test('🔴 report_type ต้องเป็นค่าที่ validator รับจริง', () {
      const allowed = {
        'bug',
        'misclassification',
        'feature_request',
        'crash',
        'performance',
      };
      for (final errs in [<String>[], <String>['state: พัง']]) {
        final body = DebugReporter.asBugReport(facts(errors: errs),
            installId: 'abc123');
        expect(allowed, contains(body['report_type']),
            reason: 'ค่านอกรายการได้ 422 แล้วรายงานหายเงียบ ๆ');
      }
    });

    test('ฟิลด์ที่ระบบบังคับต้องมีครบ', () {
      final body =
          DebugReporter.asBugReport(facts(), installId: 'abc123');
      for (final k in ['product_name', 'report_type', 'title', 'description']) {
        expect(body[k], isNotNull, reason: '$k เป็นฟิลด์บังคับของหลังบ้าน');
        expect('${body[k]}', isNotEmpty);
      }
      expect(body['product_name'], DebugReporter.product);
    });

    test('หัวข้อบอกได้ว่าเกิดอะไร ตอนมีข้อผิดพลาด', () {
      final body = DebugReporter.asBugReport(
          facts(errors: const ['state: ยังไม่ได้โหลดโมเดลลงเครื่อง']),
          installId: 'abc123');
      expect('${body['title']}', contains('ยังไม่ได้โหลดโมเดล'));
    });

    test('หัวข้อยาวเกินถูกตัด — หลังบ้านจำกัด 255 ตัวอักษร', () {
      final body = DebugReporter.asBugReport(
          facts(errors: ['state: ${'ก' * 500}']), installId: 'abc123');
      expect('${body['title']}'.length, lessThanOrEqualTo(255));
    });

    test('🔴 device_id ต้องไม่ใช่รหัสฮาร์ดแวร์', () {
      final body =
          DebugReporter.asBugReport(facts(), installId: 'สุ่มมาเอง');
      expect(body['device_id'], 'สุ่มมาเอง',
          reason: 'แอปอื่นในบ้านส่ง hardware hash · แอปนี้สัญญาไว้แคบกว่านั้น');
    });

    test('ไม่ส่งฟิลด์ที่ระบบมีแต่เราไม่ควรกรอก', () {
      final body =
          DebugReporter.asBugReport(facts(), installId: 'abc123');
      // อีเมลผู้ใช้กับ stack trace ดิบ — ไม่กรอกโดยตั้งใจ ไม่ใช่เพราะลืม
      expect(body.containsKey('user_email'), isFalse);
      expect(body.containsKey('stack_trace'), isFalse);
    });
  });
}

/// 🔴 ส่งเองต้องไม่กลายเป็นเครื่องยิงขยะ
///
/// ระบบรายงานของบ้านมี 3,520 แถวจากแอปตัวเดียวที่ยิงทุกเหตุการณ์ — กองนั้น
/// ไม่มีใครอ่านเพราะอ่านไม่ไหว · สี่ด่านนี้คือสิ่งที่กันไม่ให้ซ้ำรอย
/// และทุกด่านล้มแบบ**เงียบ**ได้ (ยิงเกินไม่มีอะไรเตือน) เทสต์จึงเป็นที่เดียวที่จับได้
class _FakeHttp extends http.BaseClient {
  final posts = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    posts.add(request.url.toString());
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"success":true,"data":{"id":1}}')),
      201,
    );
  }
}

void _autoSendGroup() {
  group('🔴 ส่งเองเมื่อมีข้อผิดพลาด', () {
    late _FakeHttp http_;
    late DebugReporter reporter;
    late MindState state;

    Future<void> setUpAll_() async {
      http_ = _FakeHttp();
      reporter = DebugReporter(
        httpClient: http_,
        settle: const Duration(milliseconds: 20),
        repeatAfter: const Duration(seconds: 30),
      );
      state = MindState();
      await state.load();
      reporter.watch(state: state);
    }

    /// รอให้เลยหน้าต่างหน่วง แล้วปล่อยให้งานเบื้องหลังเดินจนจบ
    Future<void> letItSend() async {
      await Future<void>.delayed(
          reporter.settle + const Duration(milliseconds: 120));
    }

    tearDown(() {
      reporter.dispose();
      state.dispose();
    });

    test('มีข้อผิดพลาดใหม่ = ส่งเอง ไม่ต้องรอใครกด', () async {
      await setUpAll_();
      state.reportError('สมองล้ม');
      await letItSend();

      expect(http_.posts, hasLength(1));
      expect(http_.posts.single, endsWith('/api/v1/bug-reports'));
      expect(reporter.autoSentAt, isNotNull);
    });

    test('🔴 ข้อความเดิมไม่ยิงซ้ำ', () async {
      await setUpAll_();
      state.reportError('เน็ตหลุด');
      await letItSend();
      state.clearError();
      state.reportError('เน็ตหลุด');
      await letItSend();

      expect(http_.posts, hasLength(1),
          reason: 'เน็ตหลุดครั้งเดียวทำให้เกิด error เดิมสิบรอบได้ง่าย ๆ');
    });

    test('ข้อความคนละอันยิงแยกกัน', () async {
      await setUpAll_();
      state.reportError('อันแรก');
      await letItSend();
      state.reportError('อันที่สอง');
      await letItSend();

      expect(http_.posts, hasLength(2));
    });

    test('🔴 ปิดสวิตช์แล้วต้องไม่ส่งเลย', () async {
      await setUpAll_();
      state.setAutoReport(false);
      state.reportError('พังแต่ห้ามบอกใคร');
      await letItSend();

      expect(http_.posts, isEmpty,
          reason: 'ของที่ส่งออกเน็ตเองโดยปิดไม่ได้ = ผู้ใช้ไม่มีทางเลือก');
    });

    test('🔴 เพดานต่อการเปิดแอปหนึ่งครั้ง', () async {
      await setUpAll_();
      for (var i = 0; i <= reporter.maxPerRun + 3; i++) {
        state.reportError('ล้มรอบที่ $i');
        await letItSend();
      }
      expect(http_.posts, hasLength(reporter.maxPerRun),
          reason: 'ลูปที่ล้มซ้ำต้องไม่ยิงจนหน้าแอดมินจม');
      expect(reporter.sentThisRun, reporter.maxPerRun);
    });

    test('🔴 ข้อผิดพลาดที่มาเป็นพวงถูกยุบเหลือฉบับเดียว', () async {
      await setUpAll_();
      // สมองล้ม → เสียงล้มตาม → สำเนาล้มตาม · สามอย่างในไม่กี่มิลลิวินาที
      // เป็นเหตุการณ์เดียว ไม่ใช่สามเหตุการณ์
      state.reportError('สมองล้ม');
      state.reportError('เสียงล้ม');
      state.reportError('สำเนาล้ม');
      await letItSend();

      expect(http_.posts, hasLength(1));
    });

    test('เคลียร์ข้อผิดพลาดไม่ใช่เหตุการณ์ใหม่ ต้องไม่ยิง', () async {
      await setUpAll_();
      state.reportError('อะไรสักอย่าง');
      await letItSend();
      final before = http_.posts.length;

      state.clearError();
      await letItSend();
      expect(http_.posts, hasLength(before));
    });

    test('🔴 ส่งเองต้องไม่ไปทับสถานะของปุ่มที่ผู้ใช้กด', () async {
      await setUpAll_();
      state.reportError('พัง');
      await letItSend();

      expect(reporter.stage, ReportStage.idle,
          reason: 'จอเปลี่ยนเองกลางคันโดยไม่มีสาเหตุ = ผู้ใช้งง');
      expect(reporter.error, isNull);
    });
  });
}
