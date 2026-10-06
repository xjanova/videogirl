/// คนนอกล้วงข้อมูลผ่านสายโทรศัพท์ไม่ได้ — เพราะข้อมูลไม่อยู่ตรงหน้าเธอเลย
///
/// ที่มา: เจ้าของถาม "ป้องกันการล้วงข้อมูลแล้วใช่ไหม มายไม่หลงกลนะ ไปบอกข้อมูลใน
/// สมอง สำหรับคนนอก" · ตรวจแล้วพบว่าของเดิมส่งโปรไฟล์ ความจำ ตารางนัดเต็ม และรายชื่อ
/// คนที่โทรมาเข้า prompt ของสาย แล้วกันด้วยคำสั่ง "ห้ามบอก" อย่างเดียว · คำสั่งถูกหลอก
/// ได้ ของที่ไม่อยู่ใน context หลุดไม่ได้
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/calendar/device_calendar.dart';
import 'package:videogirl/memory/mind_memory.dart';
import 'package:videogirl/state/mind_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('🔴 prompt ตอนรับสายไม่มีข้อมูลส่วนตัวของเจ้าของเลย แม้จะมีครบในเครื่อง', () async {
    final tmp = Directory.systemTemp.createTempSync('call_privacy');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final s = MindState(memory: MindMemory(dir: tmp), clock: () => DateTime(2026, 10, 6, 10));
    addTearDown(s.dispose);
    await s.load();

    s.setOwnerProfile('ชื่อต้น บ้านเลขที่ 99/12 ซอยลับ เบอร์ส่วนตัว 0899999999');
    await s.memory.remember('เจ้าของเก็บกุญแจสำรองไว้ใต้กระถางหน้าบ้าน');
    final cal = DeviceCalendar()
      ..debugSetEvents([
        CalendarEvent(
          id: 1,
          title: 'นัดหมอจิตเวช',
          begin: DateTime(2026, 10, 6, 13),
          end: DateTime(2026, 10, 6, 14),
          allDay: false,
          location: 'โรงพยาบาลลับ',
        ),
      ]);
    s.attachCalendar(cal);

    final sys = s.callPrompt();
    for (final secret in ['99/12', '0899999999', 'กุญแจสำรอง', 'นัดหมอจิตเวช', 'โรงพยาบาลลับ']) {
      expect(sys, isNot(contains(secret)), reason: 'หลุดเข้า prompt ของสาย: $secret');
    }
    expect(sys, contains('13:00-14:00 busy'), reason: 'ยังบอกได้ว่าไม่ว่างช่วงไหน');
    // แท็กวางสาย/แจ้งด่วนมีได้ (น้องมายวางสายเอง) · แท็กค้นข้อมูลออกเน็ตต้องไม่มี
    for (final tag in ['[[ค้นหา', '[[เว็บ', '[[อากาศ', '[[ค่าเงิน', '[[search', '[[web']) {
      expect(sys, isNot(contains(tag)), reason: 'ไม่มีเครื่องมือค้นในสาย: $tag');
    }
    expect(sys, isNot(contains('BrainX')), reason: 'ไม่มีอะไรจากสมอง BrainX ในสาย');
  });

  test('ในแชทของเจ้าของ ข้อมูลยังอยู่ครบเหมือนเดิม (ไม่ได้ตัดผิดที่)', () async {
    final cal = DeviceCalendar()
      ..debugSetEvents([
        CalendarEvent(
          id: 1,
          title: 'ประชุมทีม',
          begin: DateTime.now().add(const Duration(hours: 1)),
          end: DateTime.now().add(const Duration(hours: 2)),
          allDay: false,
          location: 'ห้อง Orchid',
        ),
      ]);
    expect(cal.promptBlock(), contains('ประชุมทีม'));
    expect(cal.promptBlock(), contains('ห้อง Orchid'));
    expect(cal.busyBlock(), isNot(contains('ประชุมทีม')));
    expect(cal.busyBlock(), isNot(contains('Orchid')));
  });

  test('🔴 เส้นทางสายไม่เรียกสมอง BrainX / บันทึกช่วยจำ / เครื่องมือค้น (ตรวจที่ต้นทาง)', () {
    final src = File('lib/state/mind_state.dart').readAsStringSync();
    final start = src.indexOf('String callPrompt(');
    expect(start, greaterThan(0), reason: 'หา callPrompt ไม่เจอ — รูปแบบเปลี่ยน ต้องแก้เทสต์นี้');
    final end = src.indexOf(');', src.indexOf('now: _clock(),', start));
    final body = src.substring(start, end);
    for (final banned in ['memory.', 'brainx', 'recall', 'tools:', 'pcProfile', '_calls', 'promptBlock()', '_ownerProfile']) {
      expect(body, isNot(contains(banned)), reason: 'callPrompt แตะ $banned');
    }
    final reply = src.substring(src.indexOf('Future<String> replyOnCall('), start);
    expect(reply, isNot(contains('recall')));
    expect(reply, isNot(contains('brainx')));
  });
}
