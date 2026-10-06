/// เครื่องสองซิม — ต้องบอกว่าโทรเข้ามาทางซิมไหน
///
/// ที่มา: เจ้าของใช้เครื่องสองซิม (เบอร์งาน/เบอร์ส่วนตัว) · "มีสายจากคนนี้"
/// ไม่พอ ต้องรู้ว่าโทรเข้าเบอร์ไหน ทั้งในบันทึกสายที่เธอรับแทน แจ้งเตือน
/// ไทม์ไลน์ และที่เธอเล่าให้ฟัง
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_ai.dart';
import 'package:videogirl/phone/call_notes.dart';
import 'package:videogirl/phone/call_watch.dart';
import 'package:videogirl/store/mind_db.dart';

late Directory _tmp;
String _path(String name) => '${_tmp.path}${Platform.pathSeparator}$name';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _tmp = Directory.systemTemp.createTempSync('dual_sim_test');
  });

  tearDown(() {
    try {
      _tmp.deleteSync(recursive: true);
    } on Object {
      // ไฟล์ค้างในเทมป์ไม่ใช่เรื่องที่ต้องทำให้เทสต์แดง
    }
  });

  group('อ่านซิมจากฝั่งเนทีฟ', () {
    test('เครื่องสองซิม = ได้ช่องและชื่อ', () {
      expect(CallSim.fromMap({'simSlot': 2, 'simLabel': 'AIS', 'simCount': 2}),
          const CallSim(slot: 2, label: 'AIS'));
    });

    test('🔴 เครื่องซิมเดียว = ไม่บอก (ไม่ใช่ "ทางซิม 1" ทุกสาย)', () {
      expect(CallSim.fromMap({'simSlot': 1, 'simLabel': 'AIS', 'simCount': 1}), isNull);
      expect(CallSim.fromMap({'simSlot': 1, 'simLabel': 'AIS'}), isNull,
          reason: 'ถามจำนวนซิมไม่ได้ (ไม่มีสิทธิ์) = ไม่เดา');
    });

    test('ไม่รู้ช่อง แต่รู้ชื่อค่าย = บอกชื่อค่าย', () {
      expect(CallSim.fromMap({'simLabel': 'True', 'simCount': 2}),
          const CallSim(label: 'True'));
      expect(CallSim.fromMap({'simCount': 2}), isNull);
    });

    test('บันทึกการโทรของเครื่องสองซิม', () {
      final e = CallEvent.fromMap({
        'id': 7,
        'at': DateTime(2026, 10, 6, 9).millisecondsSinceEpoch,
        'type': 3,
        'number': '0812345678',
        'simSlot': 1,
        'simLabel': 'งาน',
        'simCount': 2,
      })!;
      expect(e.sim, const CallSim(slot: 1, label: 'งาน'));
      expect(e.journalDetail, 'missed@1|งาน');
    });
  });

  group('เก็บและแปลกลับ', () {
    test('เข้ารหัสแล้วถอดกลับได้เหมือนเดิม · ชื่อที่มี | ไม่ทำให้แตก', () {
      const a = CallSim(slot: 2, label: 'AIS');
      expect(CallSim.decode(a.encode()), a);
      expect(CallSim.decode(const CallSim(label: 'A|B').encode()), const CallSim(label: 'A/B'));
      expect(CallSim.decode(null), isNull);
      expect(CallSim.decode('|'), isNull);
    });

    test('🔴 รายละเอียดในสมุดแบบเก่า (ก่อนมีซิม) ยังอ่านได้', () {
      final old = CallEvent.parseJournalDetail('missed');
      expect(old.type, 'missed');
      expect(old.sim, isNull);
      final now = CallEvent.parseJournalDetail('incoming@2|DTAC');
      expect(now.type, 'incoming');
      expect(now.sim, const CallSim(slot: 2, label: 'DTAC'));
    });

    test('ข้อความภาษาคน ไทย/อังกฤษ', () {
      const th = S(AppLang.th);
      const en = S(AppLang.en);
      expect(th.viaSim(2, 'AIS'), 'ทางซิม 2 · AIS');
      expect(th.viaSim(1, null), 'ทางซิม 1');
      expect(th.viaSim(null, 'True'), 'ทาง True');
      expect(en.viaSim(2, 'AIS'), 'via SIM 2 · AIS');
    });
  });

  test('เธอรู้ว่าโทรเข้าซิมไหน (ก้อนสายใน prompt)', () {
    final w = CallWatch();
    addTearDown(w.dispose);
    // ใส่ของเข้าไปตรง ๆ ผ่าน fromMap · ทางจริงมาจาก recentCalls
    final now = DateTime.now();
    final e = CallEvent.fromMap({
      'id': 1,
      'at': now.millisecondsSinceEpoch,
      'type': 3,
      'name': 'คุณนภา',
      'simSlot': 2,
      'simLabel': 'ส่วนตัว',
      'simCount': 2,
    })!;
    expect(e.sim!.promptTag, 'sim2 ส่วนตัว');
  });

  test('🔴 ฐานรุ่น 2 (มีบันทึกสายอยู่แล้ว) อัปเกรดแล้วบันทึกเดิมไม่หาย และเก็บซิมได้', () async {
    final path = _path('v2.db');
    final old = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (d, _) async {
            await d.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
            await d.execute(
                'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, kind TEXT NOT NULL)');
            await d.execute('''
              CREATE TABLE call_notes (
                id TEXT PRIMARY KEY, at INTEGER NOT NULL, who TEXT NOT NULL,
                summary TEXT NOT NULL, transcript TEXT NOT NULL,
                seen INTEGER NOT NULL DEFAULT 0)
            ''');
            await d.insert('call_notes', {
              'id': 'old',
              'at': DateTime(2026, 10, 1).millisecondsSinceEpoch,
              'who': 'คุณเก่า',
              'summary': 'ฝากโทรกลับ',
              'transcript': '[]',
            });
          },
        ));
    await old.close();

    final db = await MindDb.openIn(path);
    final notes = CallNotes()..attachDb(db);
    await notes.load();
    expect(notes.notes.single.summary, 'ฝากโทรกลับ', reason: 'อัปเกรดต้องไม่ลบบันทึกเดิม');
    expect(notes.notes.single.sim, isNull);

    await notes.add(CallNote(
      id: 'new',
      at: DateTime(2026, 10, 6, 9),
      who: 'คุณใหม่',
      summary: 'นัดประชุม',
      lines: const [(fromHer: false, text: 'สวัสดีครับ')],
      sim: const CallSim(slot: 2, label: 'AIS'),
    ));
    await db.close();

    final again = await MindDb.openIn(path);
    final reloaded = CallNotes()..attachDb(again);
    await reloaded.load();
    expect(reloaded.notes.firstWhere((n) => n.id == 'new').sim,
        const CallSim(slot: 2, label: 'AIS'));
    await again.close();
  });

  test('ฐานใหม่เกิดมาพร้อมช่องซิมเลย', () async {
    final db = await MindDb.openIn(_path('fresh.db'));
    final notes = CallNotes()..attachDb(db);
    await notes.add(CallNote(
      id: 'x',
      at: DateTime(2026, 10, 6),
      who: '',
      summary: '-',
      lines: const [],
      sim: const CallSim(slot: 1),
    ));
    await db.close();
    final again = await MindDb.openIn(_path('fresh.db'));
    final r = CallNotes()..attachDb(again);
    await r.load();
    expect(r.notes.single.sim, const CallSim(slot: 1));
    await again.close();
  });

  test('ฝั่งเนทีฟส่งซิมมาทั้งสายที่คุยอยู่และบันทึกการโทร · จอสายมีบรรทัดซิม', () {
    final svc = File('android/app/src/main/kotlin/com/xjanova/videogirl/MindInCallService.kt')
        .readAsStringSync();
    expect(svc, contains('SimInfo.of(context, call)?.toMap()'));
    final bridge = File('android/app/src/main/kotlin/com/xjanova/videogirl/CallBridge.kt')
        .readAsStringSync();
    expect(bridge, contains('CallLog.Calls.PHONE_ACCOUNT_ID'));
    final screen = File('android/app/src/main/kotlin/com/xjanova/videogirl/InCallActivity.kt')
        .readAsStringSync();
    expect(screen, contains('R.string.call_sim_label'));
    for (final res in ['values', 'values-en']) {
      final xml = File('android/app/src/main/res/$res/strings.xml').readAsStringSync();
      expect(xml, contains('name="call_sim"'), reason: res);
      expect(xml, contains('name="call_sim_label"'), reason: res);
    }
  });
}
