import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/calendar/device_calendar.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/system/permissions.dart';

/// ปฏิทินของเครื่อง
///
/// สิ่งที่คุ้มค่าเทสต์ที่สุดตรงนี้คือ **การแยก "ไม่มีนัด" ออกจาก
/// "อ่านไม่ได้"** เพราะทั้งสองอย่างทำให้จอว่างเหมือนกันเป๊ะ แต่คนละวิธีแก้
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// ปลอมฝั่ง Android — เทสต์ต้องไม่ต้องมีเครื่องจริง
  void mock({
    required bool granted,
    Object? events,
    bool throwOnRead = false,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kSystemChannel, (call) async {
      if (call.method == 'readCalendar') {
        if (throwOnRead) {
          throw PlatformException(code: 'ERR', message: 'provider หาย');
        }
        return events;
      }
      if (call.method == 'calendarGranted') return granted;
      // สิทธิ์อื่น ๆ ที่ refresh() ถามมา
      return false;
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kSystemChannel, null);
  });

  Map<String, Object?> event(
    String title,
    DateTime begin,
    DateTime end, {
    bool allDay = false,
    String? location,
    int color = 0,
  }) =>
      {
        'id': begin.millisecondsSinceEpoch,
        'title': title,
        'begin': begin.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
        'allDay': allDay,
        'location': location,
        'calendar': 'งาน',
        'color': color,
      };

  DateTime todayAt(int h, [int m = 0]) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, h, m);
  }

  group('อ่านปฏิทิน', () {
    test('ยังไม่ได้ให้สิทธิ์ ต้องเป็น denied ไม่ใช่ ready ที่ว่างเปล่า', () async {
      mock(granted: false);
      final cal = DeviceCalendar();

      await cal.load();

      expect(cal.stage, CalendarStage.denied);
      expect(cal.events, isEmpty);
    });

    test('ให้สิทธิ์แล้วแต่ไม่มีนัด ต้องเป็น ready ไม่ใช่ denied', () async {
      // 🔴 จอว่างเหมือนกันทั้งสองแบบ แต่แบบนี้คือข่าวดี ไม่ใช่ปัญหา
      // สลับกันเมื่อไหร่ = ขึ้นปุ่มขอสิทธิ์ให้คนที่ให้สิทธิ์ไปแล้ว
      mock(granted: true, events: const []);
      final cal = DeviceCalendar();

      await cal.load();

      expect(cal.stage, CalendarStage.ready);
      expect(cal.events, isEmpty);
    });

    test('ฝั่ง Android คืน null (อ่านไม่สำเร็จ) ต้องไม่กลายเป็นไม่มีนัด', () async {
      mock(granted: true, events: null);
      final cal = DeviceCalendar();

      await cal.load();

      expect(cal.stage, isNot(CalendarStage.ready));
    });

    test('อ่านแล้วระเบิด ต้องเป็น failed ไม่ใช่ค้างที่ loading', () async {
      mock(granted: true, throwOnRead: true);
      final cal = DeviceCalendar();

      await cal.load();

      expect(cal.stage, CalendarStage.failed);
    });

    test('แปลงนัดจากฝั่ง Android ครบทุกช่อง', () async {
      final begin = todayAt(9);
      final end = todayAt(9, 30);
      mock(granted: true, events: [
        event('ประชุมเช้า', begin, end, location: 'ห้อง A', color: 0xFF2196F3),
      ]);
      final cal = DeviceCalendar();

      await cal.load();

      expect(cal.events, hasLength(1));
      final e = cal.events.single;
      expect(e.title, 'ประชุมเช้า');
      expect(e.begin, begin);
      expect(e.end, end);
      expect(e.location, 'ห้อง A');
      expect(e.color, 0xFF2196F3);
      expect(e.length, const Duration(minutes: 30));
    });
  });

  group('ความทนต่อข้อมูลไม่เนี้ยบ', () {
    test('นัดไม่มีชื่อยังเป็นนัด ห้ามทิ้งทั้งแถว', () async {
      // ปฏิทินบางบัญชีไม่ส่งชื่อมา · ทิ้งไปคือตารางขาดโดยไม่มีใครรู้
      mock(granted: true, events: [
        {
          'begin': todayAt(10).millisecondsSinceEpoch,
          'end': todayAt(11).millisecondsSinceEpoch,
        },
      ]);
      final cal = DeviceCalendar();

      await cal.load();

      expect(cal.events, hasLength(1));
      expect(cal.events.single.title, isEmpty);
    });

    test('นัดที่จบก่อนเริ่ม ต้องถูกยืดให้ยาวหนึ่งชั่วโมง ไม่ใช่ติดลบ', () async {
      final begin = todayAt(14);
      mock(granted: true, events: [
        {'begin': begin.millisecondsSinceEpoch, 'end': 0},
      ]);
      final cal = DeviceCalendar();

      await cal.load();

      expect(cal.events.single.length, const Duration(hours: 1));
      expect(cal.events.single.end.isAfter(begin), isTrue);
    });

    test('แถวที่ไม่มีเวลาเลย ใช้ไม่ได้จริง ต้องทิ้ง', () async {
      mock(granted: true, events: [
        {'title': 'ไม่มีเวลา'},
        event('ใช้ได้', todayAt(8), todayAt(9)),
      ]);
      final cal = DeviceCalendar();

      await cal.load();

      expect(cal.events, hasLength(1));
      expect(cal.events.single.title, 'ใช้ได้');
    });

    test('สี 0 คือไม่ได้ตั้งสี ไม่ใช่สีดำทึบ', () async {
      mock(granted: true, events: [event('x', todayAt(8), todayAt(9))]);
      final cal = DeviceCalendar();

      await cal.load();

      expect(cal.events.single.color, isNull);
    });
  });

  group('การจัดกลุ่มและการนับ', () {
    test('today เอาเฉพาะนัดที่คาบเกี่ยววันนี้', () async {
      final n = DateTime.now();
      final tomorrow = DateTime(n.year, n.month, n.day + 1, 10);
      mock(granted: true, events: [
        event('วันนี้', todayAt(9), todayAt(10)),
        event('พรุ่งนี้', tomorrow, tomorrow.add(const Duration(hours: 1))),
      ]);
      final cal = DeviceCalendar();

      await cal.load();

      expect(cal.today.map((e) => e.title), ['วันนี้']);
      expect(cal.byDay.keys, hasLength(2));
    });

    test('next คือนัดแรกที่ยังไม่จบ ไม่ใช่นัดแรกของวัน', () async {
      final n = DateTime.now();
      mock(granted: true, events: [
        event('ผ่านไปแล้ว', n.subtract(const Duration(hours: 3)),
            n.subtract(const Duration(hours: 2))),
        event('ถัดไป', n.add(const Duration(hours: 1)),
            n.add(const Duration(hours: 2))),
      ]);
      final cal = DeviceCalendar();

      await cal.load();

      expect(cal.next?.title, 'ถัดไป');
    });

    test('นัดผ่านไปหมดแล้ว next ต้องเป็น null ไม่ใช่นัดสุดท้าย', () async {
      final n = DateTime.now();
      mock(granted: true, events: [
        event('จบแล้ว', n.subtract(const Duration(hours: 2)),
            n.subtract(const Duration(hours: 1))),
      ]);
      final cal = DeviceCalendar();

      await cal.load();

      expect(cal.next, isNull);
    });
  });

  group('ก้อนข้อความสำหรับ prompt', () {
    test('ไม่มีนัดต้องได้ค่าว่าง ไม่ใช่หัวข้อลอย ๆ', () async {
      mock(granted: true, events: const []);
      final cal = DeviceCalendar();

      await cal.load();

      expect(cal.promptBlock(), isEmpty);
    });

    test('เอาเฉพาะนัดที่ยังไม่จบ และตัดตามเพดาน', () async {
      final n = DateTime.now();
      mock(granted: true, events: [
        event('ผ่านแล้ว', n.subtract(const Duration(hours: 3)),
            n.subtract(const Duration(hours: 2))),
        for (var i = 1; i <= 5; i++)
          event('นัด$i', n.add(Duration(hours: i)),
              n.add(Duration(hours: i, minutes: 30))),
      ]);
      final cal = DeviceCalendar();

      await cal.load();

      final block = cal.promptBlock(limit: 3);
      expect(block, isNot(contains('ผ่านแล้ว')));
      expect(block.split('\n'), hasLength(3));
    });

    test('นัดทั้งวันเขียนแค่วันที่ ไม่มีช่วงเวลาปลอม', () async {
      final n = DateTime.now();
      final start = DateTime(n.year, n.month, n.day);
      mock(granted: true, events: [
        event('ลาพักร้อน', start, start.add(const Duration(days: 1)),
            allDay: true),
      ]);
      final cal = DeviceCalendar();

      await cal.load();

      final block = cal.promptBlock();
      expect(block, contains('ลาพักร้อน'));
      expect(block, isNot(contains(':')));
    });
  });

  group('ชื่อวันและเดือนในสองภาษา', () {
    test('มีครบ 7 วัน 12 เดือน ทั้งสองภาษา', () {
      for (final lang in AppLang.values) {
        final s = S(lang);
        expect(s.weekdayNames, hasLength(7), reason: '${lang.code} วันไม่ครบ');
        expect(s.monthShort, hasLength(12), reason: '${lang.code} เดือนไม่ครบ');
      }
    });

    test('dayLabel เรียงดัชนีถูก — จันทร์คือ weekday 1 ไม่ใช่ 0', () {
      // 🔴 พลาดตรงนี้ = ทุกวันเลื่อนไปหนึ่ง ซึ่งดูปกติจนกว่าจะมีคนทัก
      final monday = DateTime(2026, 8, 31);
      expect(monday.weekday, DateTime.monday);

      final th = S(AppLang.th).dayLabel(monday);
      final en = S(AppLang.en).dayLabel(monday);

      expect(th, contains('จันทร์'));
      expect(en, contains('Monday'));
      expect(en, contains('Aug'));
      expect(en, contains('31'));
    });
  });
}
