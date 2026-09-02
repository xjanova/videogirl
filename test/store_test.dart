/// ที่เก็บข้อมูล — SQLite + สำเนาที่รอดจากการถอนแอป
///
/// สามข้อที่เทสต์นี้คุมไว้ เป็นสามข้อที่ถ้าพลาดแล้ว**ข้อมูลของผู้ใช้หายจริง**
/// และไม่มีทางกู้:
///
/// 1. บทสนทนาต้องไม่ถูกตัดทิ้งที่ 16 ตาอีกต่อไป
/// 2. การกู้จากสำเนาต้องเกิด**เฉพาะตอนเครื่องยังไม่มีฐาน** ไม่งั้นสำเนาเก่า
///    จะทับสิ่งที่เพิ่งคุยกัน
/// 3. ติ๊ก "ลบเมื่อถอนแอป" ต้องลบสำเนาทิ้ง**เดี๋ยวนี้** เพราะวันที่ถอนแอปจริง
///    ไม่มีโค้ดของเราวิ่งอยู่เลยที่จะไปลบให้ได้
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:videogirl/store/mind_db.dart';
import 'package:videogirl/store/mind_kv.dart';
import 'package:videogirl/store/mind_store.dart';
import 'package:videogirl/store/mind_vault.dart';

late Directory _tmp;

String _path(String name) => '${_tmp.path}${Platform.pathSeparator}$name';

void main() {
  setUpAll(() {
    // SQLite จริงบน VM ของเทสต์ · ไม่ใช่ของปลอม — ตรรกะที่คุมอยู่ตรงนี้
    // คือ SQL ล้วน ๆ การ mock มันทิ้งไปจะเหลือแค่เทสต์ที่ทดสอบ mock
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    _tmp = Directory.systemTemp.createTempSync('mind_store_test');
  });

  tearDown(() {
    try {
      _tmp.deleteSync(recursive: true);
    } on Object {
      // ไฟล์ค้างในเทมป์ไม่ใช่เรื่องที่ต้องทำให้เทสต์แดง
    }
  });

  group('ค่าตั้งค่า', () {
    test('เขียนแล้วอ่านกลับได้ตรงชนิดเดิม', () async {
      final db = await MindDb.openIn(_path('a.db'));
      db
        ..put('s', 'ข้อความ')
        ..put('i', 42)
        ..put('d', 1.5)
        ..put('b', true);
      await db.close();

      final again = await MindDb.openIn(_path('a.db'));
      await again.warm();

      // 🔴 ถ้าไม่จำชนิดไว้ ตอนอ่านกลับจะแยกไม่ออกว่า "0" คือเลข สตริง
      // หรือ false — บั๊กที่เงียบและโผล่ทีหลังไกลจากจุดที่ผิด
      expect(again.getString('s'), 'ข้อความ');
      expect(again.getInt('i'), 42);
      expect(again.getDouble('d'), 1.5);
      expect(again.getBool('b'), isTrue);
      await again.close();
    });

    test('ลบแล้วหายจริง', () async {
      final db = await MindDb.openIn(_path('b.db'));
      db.put('ทิ้ง', 'ค่า');
      db.remove('ทิ้ง');
      await db.close();

      final again = await MindDb.openIn(_path('b.db'));
      await again.warm();
      expect(again.getString('ทิ้ง'), isNull);
      await again.close();
    });

    test('ย้ายค่าเก่าจาก SharedPreferences เข้ามาครั้งเดียว', () async {
      SharedPreferences.setMockInitialValues({
        'lang': 'en',
        'flirt': 0.9,
        'ringSeconds': 30,
        'voiceEnabled': false,
      });

      final db = await MindDb.openIn(_path('c.db'));
      expect(await db.importSettings(), 4);
      expect(db.getString('lang'), 'en');
      expect(db.getDouble('flirt'), 0.9);
      expect(db.getInt('ringSeconds'), 30);
      expect(db.getBool('voiceEnabled'), isFalse);

      // 🔴 วิ่งซ้ำ = ของที่ผู้ใช้ลบไปแล้วกลับมาเองทุกครั้งที่เปิดแอป
      // ซึ่งน่ากลัวกว่าข้อมูลหาย
      expect(await db.importSettings(), 0);
      await db.close();
    });
  });

  group('บทสนทนา', () {
    test('🔴 เก็บได้เกิน 16 ตา — เพดานเดิมคือเหตุผลทั้งหมดที่ย้ายมา SQLite',
        () async {
      final db = await MindDb.openIn(_path('chat.db'));
      for (var i = 0; i < 120; i++) {
        await db.addMessage(fromHer: i.isOdd, text: 'ตาที่ $i');
      }
      expect(await db.countMessages(), 120,
          reason: 'ของเดิมตัดเหลือ 16 แล้วลบตาเก่าทิ้งถาวร');
      await db.close();
    });

    test('อ่านกลับมาเรียงเก่า→ใหม่ ตามที่โมเดลกับหน้าจอต้องการ', () async {
      final db = await MindDb.openIn(_path('order.db'));
      for (var i = 0; i < 30; i++) {
        await db.addMessage(fromHer: false, text: 'ตาที่ $i');
      }

      final last = await db.lastMessages(5);
      expect(last.map((m) => m.text).toList(),
          ['ตาที่ 25', 'ตาที่ 26', 'ตาที่ 27', 'ตาที่ 28', 'ตาที่ 29']);
      await db.close();
    });

    test('จำได้ว่าใครพูด', () async {
      final db = await MindDb.openIn(_path('who.db'));
      await db.addMessage(fromHer: false, text: 'ถาม');
      await db.addMessage(fromHer: true, text: 'ตอบ');

      final rows = await db.lastMessages(2);
      expect(rows.first.fromHer, isFalse);
      expect(rows.last.fromHer, isTrue);
      await db.close();
    });
  });

  group('สำเนาที่รอดจากการถอนแอป', () {
    MindVault vaultAt(String root, {bool granted = true}) =>
        MindVault(hasAllFiles: () => granted, root: root);

    test('ยังไม่ได้สิทธิ์ = ไม่มีสำเนา และบอกให้รู้', () async {
      final v = vaultAt(_tmp.path, granted: false);
      expect(await v.check(), VaultStage.needsPermission);
      expect(await v.hasCopy(), isFalse);
      v.dispose();
    });

    test('สำเนาแล้วกู้กลับได้ครบ', () async {
      final dbPath = _path('live.db');
      final db = await MindDb.openIn(dbPath);
      db.put('lang', 'th');
      await db.addMessage(fromHer: false, text: 'เรื่องที่คุยไว้');
      await db.close();

      final v = vaultAt(_tmp.path);
      final live = await MindDb.openIn(dbPath);
      expect(await v.saveNow(live), isTrue);
      await live.close();

      // จำลองการถอนแอป: พื้นที่แอปหายไปทั้งก้อน สำเนายังอยู่
      File(dbPath).deleteSync();

      expect(await v.restoreIfFresh(dbPath), isTrue);
      final back = await MindDb.openIn(dbPath);
      await back.warm();
      expect(back.getString('lang'), 'th');
      expect((await back.lastMessages(10)).single.text, 'เรื่องที่คุยไว้');
      await back.close();
      v.dispose();
    });

    test('🔴 มีฐานอยู่แล้วห้ามกู้ทับ — นั่นคือการลบสิ่งที่เพิ่งคุยกัน', () async {
      final dbPath = _path('has.db');
      final db = await MindDb.openIn(dbPath);
      await db.addMessage(fromHer: false, text: 'ของเก่าในสำเนา');
      final v = vaultAt(_tmp.path);
      await v.saveNow(db);

      await db.addMessage(fromHer: false, text: 'ที่เพิ่งคุยกันเมื่อกี้');
      await db.close();

      expect(await v.restoreIfFresh(dbPath), isFalse,
          reason: 'กู้ทับ = สำเนาเก่าลบสิ่งที่ผู้ใช้เพิ่งพิมพ์ทิ้ง');

      final still = await MindDb.openIn(dbPath);
      expect(await still.countMessages(), 2);
      await still.close();
      v.dispose();
    });

    test('🔴 ติ๊กลบเมื่อถอนแอป = สำเนาหายเดี๋ยวนี้ ไม่ใช่รอถึงวันนั้น', () async {
      final dbPath = _path('wipe.db');
      final db = await MindDb.openIn(dbPath);
      db.put('lang', 'th');
      final v = vaultAt(_tmp.path);
      expect(await v.saveNow(db), isTrue);
      expect(await v.hasCopy(), isTrue);

      await v.setWipeOnUninstall(true);
      expect(await v.hasCopy(), isFalse,
          reason: 'วันที่ถอนแอปจริงไม่มีโค้ดของเราวิ่งอยู่เลยที่จะไปลบให้ได้');
      expect(v.stage, VaultStage.off);

      // ปิดไว้แล้วต้องไม่แอบสำเนาต่อ
      expect(await v.saveNow(db), isFalse);
      await db.close();
      v.dispose();
    });

    test('ปิดสวิตช์ไว้ก็ต้องไม่กู้อะไรกลับมา', () async {
      final dbPath = _path('nores.db');
      final db = await MindDb.openIn(dbPath);
      final v = vaultAt(_tmp.path);
      await v.saveNow(db);
      await db.close();
      File(dbPath).deleteSync();

      await v.setWipeOnUninstall(true);
      expect(await v.restoreIfFresh(dbPath), isFalse);
      v.dispose();
    });

    test('สำเนาเขียนผ่านชื่อชั่วคราวก่อน ไม่ทิ้งไฟล์ค้าง', () async {
      final db = await MindDb.openIn(_path('tmp.db'));
      final v = vaultAt(_tmp.path);
      await v.saveNow(db);

      expect(File(v.filePath).existsSync(), isTrue);
      expect(File('${v.filePath}.tmp').existsSync(), isFalse,
          reason: 'ไฟล์ครึ่งเดียวที่ค้างอยู่ทำให้คนเข้าใจผิดว่ามีสำเนาสองชุด');
      await db.close();
      v.dispose();
    });
  });

  group('เปิดที่เก็บทั้งชุด', () {
    test('เปิดได้ = ใช้ฐานจริง', () async {
      final v = MindVault(hasAllFiles: () => false, root: _tmp.path);
      final store = await MindStore.open(vault: v, pathOverride: _path('s.db'));

      expect(store.durable, isTrue);
      expect(store.kv, isA<DbKv>());
      expect(store.kv.durable, isTrue);
      await store.db!.close();
      v.dispose();
    });

    test('🔴 เปิดฐานไม่ขึ้นต้องไม่ทำให้แอปตาย — ตกไปใช้ของเดิม', () async {
      final v = MindVault(hasAllFiles: () => false, root: _tmp.path);

      // จำลองไฟล์ฐานที่เปิดไม่ได้จริง ๆ ด้วยการเอา**โฟลเดอร์**ไปวางตรงที่
      // ไฟล์ควรอยู่ · sqflite สร้างโฟลเดอร์แม่ให้เองอยู่แล้ว การชี้ไปพาธที่
      // ยังไม่มีจึงไม่ทำให้ล้ม (เจอตอนเขียนเทสต์นี้)
      final blocked = _path('blocked.db');
      Directory(blocked).createSync(recursive: true);

      final store = await MindStore.open(vault: v, pathOverride: blocked);

      expect(store.durable, isFalse);
      expect(store.kv, isA<PrefsKv>(),
          reason: 'ฐานเปิดไม่ขึ้นเป็นเรื่องที่ผู้ใช้แก้เองไม่ได้ '
              'จอขาวจึงเป็นคำตอบที่ผิดเสมอ');
      v.dispose();
    });

    test('กู้จากสำเนาแล้วบอกว่ากู้จริง', () async {
      final dbPath = _path('boot.db');
      final seed = await MindDb.openIn(dbPath);
      seed.put('lang', 'en');
      final v = MindVault(hasAllFiles: () => true, root: _tmp.path);
      await v.saveNow(seed);
      await seed.close();
      File(dbPath).deleteSync();

      final store = await MindStore.open(vault: v, pathOverride: dbPath);
      expect(store.restored, isTrue,
          reason: 'ผู้ใช้ต้องรู้ว่าของที่โผล่มาเองมาจากไหน');
      expect(store.kv.getString('lang'), 'en');
      await store.db!.close();
      v.dispose();
    });
  });
}
