/// บันทึกสายที่มายด์รับแทน — รับฝากเรื่องแล้วต้องไม่หาย
///
/// ที่มา: ของเดิมพอวางสาย บทสนทนาทั้งหมดหายไปกับหน่วยความจำ เจ้าของไม่มีทาง
/// รู้ว่าใครฝากอะไรไว้
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:videogirl/i18n/strings_ai.dart';
import 'package:videogirl/phone/call_notes.dart';
import 'package:videogirl/state/mind_state.dart';
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
    _tmp = Directory.systemTemp.createTempSync('call_notes_test');
  });

  tearDown(() {
    try {
      _tmp.deleteSync(recursive: true);
    } on Object {
      // ไฟล์ค้างในเทมป์ไม่ใช่เรื่องที่ต้องทำให้เทสต์แดง
    }
  });

  test('🔴 ฐานรุ่นเก่า (v1) อัปเกรดแล้วได้ตารางบันทึกสาย โดยข้อมูลเดิมไม่หาย', () async {
    final path = _path('old.db');
    final old = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, _) async {
            await d.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
            await d.execute(
                'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, kind TEXT NOT NULL)');
            await d.insert('settings', {'key': 'lang', 'value': 'en', 'kind': 's'});
          },
        ));
    await old.close();

    final db = await MindDb.openIn(path);
    await db.warm();
    expect(db.getString('lang'), 'en', reason: 'อัปเกรดต้องไม่ลบค่าที่ผู้ใช้ตั้งไว้');

    final notes = CallNotes()..attachDb(db);
    await notes.add(CallNote(
      id: 'a',
      at: _at,
      who: 'คุณนภา',
      summary: 'ขอเลื่อนส่งงานเป็นวันจันทร์',
      lines: [(fromHer: false, text: 'ขอเลื่อนเป็นวันจันทร์ได้ไหมคะ')],
    ));
    await db.close();

    final again = await MindDb.openIn(path);
    final reloaded = CallNotes()..attachDb(again);
    await reloaded.load();
    expect(reloaded.notes.single.summary, 'ขอเลื่อนส่งงานเป็นวันจันทร์');
    expect(reloaded.notes.single.lines.single.text, 'ขอเลื่อนเป็นวันจันทร์ได้ไหมคะ');
    await again.close();
  });

  test('เปิดอ่านแล้วนับว่าเจ้าของรู้แล้ว และจำข้ามการเปิดแอป', () async {
    final db = await MindDb.openIn(_path('seen.db'));
    final notes = CallNotes()..attachDb(db);
    await notes.add(CallNote(
        id: 'x', at: _at, who: 'A', summary: 's', lines: []));
    expect(notes.unseen, 1);

    await notes.markSeen('x');
    final again = CallNotes()..attachDb(db);
    await again.load();
    expect(again.unseen, 0);
    await db.close();
  });

  test('ก้อน prompt มีเฉพาะสองวันล่าสุด และบอกว่าเรื่องไหนยังไม่ได้แจ้ง', () async {
    final now = DateTime(2026, 10, 5, 15);
    final notes = CallNotes(clock: () => now);
    await notes.add(CallNote(
        id: 'old',
        at: now.subtract(const Duration(days: 5)),
        who: 'เก่า',
        summary: 'เรื่องเก่า',
        lines: const []));
    await notes.add(CallNote(
        id: 'new',
        at: now.subtract(const Duration(hours: 1)),
        who: 'คุณต้น',
        summary: 'ให้โทรกลับ',
        lines: const []));

    final block = notes.promptBlock(unseenTag: '(ยังไม่ได้แจ้ง)');
    expect(block, contains('คุณต้น: ให้โทรกลับ (ยังไม่ได้แจ้ง)'));
    expect(block, isNot(contains('เรื่องเก่า')));
  });

  test('วางสายแล้ว state จดบันทึก · สรุปไม่ได้ก็ยังเก็บสิ่งที่คู่สายพูด', () async {
    // ในเทสต์ไม่มีโมเดล สมองล้มเสมอ = ทางสำรองของสรุป
    final state = MindState();
    final notes = CallNotes();
    state.attachCallNotes(notes);

    final note = await state.takeCallNote(
      who: 'คุณนภา',
      lines: const [
        (fromHer: true, text: 'สวัสดีค่ะ ติดต่อเรื่องอะไรคะ'),
        (fromHer: false, text: 'ฝากบอกว่าพรุ่งนี้ประชุมเลื่อนเป็นบ่ายสอง'),
      ],
    );

    expect(note, isNotNull);
    expect(notes.notes.single.summary, contains('พรุ่งนี้ประชุมเลื่อนเป็นบ่ายสอง'));
    expect(notes.notes.single.lines, hasLength(2),
        reason: 'บทสนทนาเต็มต้องอยู่ครบให้เปิดอ่าน');
  });

  test('คู่สายไม่ได้พูดอะไร ยังจดว่ามีสาย แต่ไม่เรียกสมองมาแต่งเรื่อง', () async {
    final state = MindState();
    final notes = CallNotes();
    state.attachCallNotes(notes);

    await state.takeCallNote(
      who: '',
      lines: const [(fromHer: true, text: 'สวัสดีค่ะ')],
    );
    expect(notes.notes.single.summary, state.s.callNoteSilent);
  });
}

final _at = DateTime(2026, 10, 5, 9);
