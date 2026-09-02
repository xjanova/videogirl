/// ฐานข้อมูลของมายด์ — ที่เดียวที่เก็บทุกอย่างที่ต้องอยู่ข้ามการเปิดปิดแอป
///
/// ## ทำไมต้องเปลี่ยนจากของเดิม
///
/// ของเดิมกระจายอยู่สามที่ และทุกที่มีปัญหาเดียวกัน:
/// - ค่าตั้งค่า → `SharedPreferences` (XML ทั้งไฟล์ เขียนใหม่ทุกครั้ง)
/// - บทสนทนา → JSON ก้อนเดียวใน SharedPreferences **เพดาน 16 ตา** แล้วทิ้งถาวร
/// - ความจำ/ไทม์ไลน์ → `memory.json` / `journal.json` เขียนทับทั้งไฟล์ทุกบรรทัด
///
/// เพิ่มบรรทัดเดียว = เขียนใหม่ทั้งไฟล์ · ค้นย้อนหลังไม่ได้ · และของเก่าถูก
/// ตัดทิ้งถาวรโดยไม่มีอะไรบอก — 16 ตาคือประมาณ 8 คำถาม เจ้าของถามเรื่องเดิม
/// ซ้ำในวันเดียวกันก็เจอแล้วว่าเธอจำไม่ได้
///
/// ## 🔴 ฐานจริงอยู่ในพื้นที่แอป ไม่ใช่ในโฟลเดอร์ที่รอด uninstall
///
/// SQLite ที่รันสดบน `/storage/emulated/0` **ไม่ปลอดภัย** — ชั้น FUSE ของ
/// Android ทำ POSIX advisory lock ไม่ครบ เจอ `SQLITE_IOERR` และไฟล์เสียได้จริง
/// ฐานจริงจึงอยู่ในพื้นที่แอป (เร็ว ล็อกได้ ใช้ WAL ได้) แล้วส่ง**สำเนา**
/// ออกไปข้างนอกให้รอดจากการถอนแอป — ดู [MindVault]
///
/// ## 🔴 ความลับไม่อยู่ที่นี่
///
/// คีย์ OpenAI ของผู้ใช้อยู่ใน Keystore ([SecretStore]) และ**ห้ามย้ายมา**
/// เพราะไฟล์นี้ถูกก๊อปออกไปไว้ในที่ที่แอปอื่นอ่านได้ · กฎเดียวกับที่เขียนไว้
/// แล้วใน secret_store.dart — ที่เก็บที่ถูกก๊อปออกนอกเครื่องได้ ไม่ใช่ที่เก็บความลับ
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// รุ่นของโครงตาราง — ขึ้นทีละหนึ่งเมื่อเพิ่ม/แก้ตาราง แล้วเขียนทางอัปเกรดไว้
const _schemaVersion = 1;

/// ชื่อไฟล์ฐาน · ใช้ชื่อเดียวกันทั้งในพื้นที่แอปและในสำเนาข้างนอก
/// จะได้ไม่ต้องเดาว่าไฟล์ไหนคู่กับไฟล์ไหนตอนไปส่องด้วยตัวจัดการไฟล์
const kDbFileName = 'mind.db';

/// ค่าตั้งค่าหนึ่งตัว — เก็บชนิดไว้ด้วยเพื่อคืนค่าออกมาให้ตรงชนิดเดิม
///
/// SQLite เก็บอะไรลงคอลัมน์ไหนก็ได้ก็จริง แต่ถ้าไม่จำชนิดไว้ ตอนอ่านกลับ
/// จะแยกไม่ออกว่า `"0"` คือเลขศูนย์ สตริง หรือ false — ซึ่งเป็นบั๊กที่เงียบ
/// และโผล่ทีหลังไกลจากจุดที่ผิด
enum _Kind { s, i, d, b }

/// ทุกอย่างที่ต้องรอดข้ามการเปิดปิดแอป
class MindDb {
  MindDb._(this._db);

  final Database _db;

  static MindDb? _open;

  /// ฐานที่เปิดอยู่ — null ถ้ายังไม่ได้เรียก [openIn]
  static MindDb? get current => _open;

  /// ที่อยู่ของไฟล์ฐานในพื้นที่แอป
  static Future<String> defaultPath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}${Platform.pathSeparator}$kDbFileName';
  }

  /// เปิดฐาน สร้างตารางถ้ายังไม่มี แล้วดูดของเก่าเข้ามาครั้งเดียว
  ///
  /// [path] แยกออกมาเป็นพารามิเตอร์เพื่อให้เทสต์ชี้ไปไฟล์ชั่วคราวได้
  /// (`:memory:` ก็ได้ แต่เทสต์การกู้คืนต้องมีไฟล์จริง)
  static Future<MindDb> openIn(String path) async {
    final db = await openDatabase(
      path,
      version: _schemaVersion,
      onConfigure: (d) async {
        // ลูกกำพร้าต้องหายไปพร้อมพ่อแม่ · ไม่เปิดไว้ SQLite จะยอมให้มี
        // แถวที่ชี้ไปหาของที่ถูกลบไปแล้วเงียบ ๆ
        await d.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (d, _) async => _createAll(d),
      onUpgrade: (d, from, to) async {
        // ยังไม่มีรุ่นเก่าให้อัปเกรด · เมื่อถึงวันนั้นเขียนทีละขั้นที่นี่
        // อย่า drop แล้วสร้างใหม่ นั่นคือการลบข้อมูลของผู้ใช้ทิ้ง
        debugPrint('db: อัปเกรดโครงตาราง $from → $to');
      },
    );
    final mind = MindDb._(db);
    _open = mind;
    return mind;
  }

  static Future<void> _createAll(Database d) async {
    await d.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        kind  TEXT NOT NULL
      )
    ''');

    // บทสนทนา — **ไม่มีเพดาน** นั่นคือเหตุผลทั้งหมดที่ย้ายมาที่นี่
    await d.execute('''
      CREATE TABLE messages (
        id       INTEGER PRIMARY KEY AUTOINCREMENT,
        from_her INTEGER NOT NULL,
        text     TEXT NOT NULL,
        at       INTEGER NOT NULL
      )
    ''');
    await d.execute('CREATE INDEX idx_messages_at ON messages(at)');

    await d.execute('''
      CREATE TABLE memories (
        id         TEXT PRIMARY KEY,
        text       TEXT NOT NULL,
        kind       TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        pinned     INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await d.execute('''
      CREATE TABLE journal (
        id     TEXT PRIMARY KEY,
        kind   TEXT NOT NULL,
        text   TEXT NOT NULL,
        detail TEXT,
        at     INTEGER NOT NULL
      )
    ''');
    await d.execute('CREATE INDEX idx_journal_at ON journal(at)');

    // ธงภายในของฐานเอง (เช่น "ดูดของเก่าเข้ามาแล้ว") แยกจาก settings
    // เพราะ settings เป็นของผู้ใช้ ส่วนตารางนี้เป็นของระบบ · ปนกันแล้ว
    // หน้าจอ "ล้างข้อมูล" จะเผลอลบธงพวกนี้ไปด้วย แล้วการดูดของเก่าจะวิ่งซ้ำ
    await d.execute('''
      CREATE TABLE meta (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  // ═══ ค่าตั้งค่า ════════════════════════════════════════
  //
  // อ่านทั้งก้อนเข้าหน่วยความจำตอนเปิดแอปครั้งเดียว แล้วอ่านจากตรงนั้นต่อ
  // ค่าตั้งค่ามีไม่กี่สิบตัวและถูกอ่านทุกเฟรมตอนวาดจอ · ยิง SELECT ทุกครั้ง
  // ที่วาดคือการทำให้ทุกอย่างช้าลงเพื่อความบริสุทธิ์ที่ไม่มีใครได้ประโยชน์
  final Map<String, Object> _settings = {};

  Future<void> _loadSettings() async {
    _settings.clear();
    for (final row in await _db.query('settings')) {
      final key = row['key']! as String;
      final raw = row['value']! as String;
      _settings[key] = switch (row['kind']) {
        'i' => int.tryParse(raw) ?? 0,
        'd' => double.tryParse(raw) ?? 0.0,
        'b' => raw == '1',
        _ => raw,
      };
    }
  }

  String? getString(String key) => _settings[key] as String?;
  int? getInt(String key) => _settings[key] as int?;
  double? getDouble(String key) => _settings[key] as double?;
  bool? getBool(String key) => _settings[key] as bool?;

  /// เขียนค่าหนึ่งตัว
  ///
  /// อัปเดตในหน่วยความจำ**ก่อน** แล้วค่อยลงดิสก์แบบไม่รอ — ผู้ใช้เลื่อนแถบ
  /// ปรับค่าแล้วต้องเห็นผลทันที ไม่ใช่รอดิสก์ตอบ · ถ้าเขียนดิสก์พลาด
  /// อย่างแย่ที่สุดคือค่านั้นไม่รอดการปิดแอป ซึ่งดีกว่าจอที่กระตุกทุกครั้ง
  void put(String key, Object value) {
    final (kind, text) = switch (value) {
      final int v => (_Kind.i, '$v'),
      final double v => (_Kind.d, '$v'),
      final bool v => (_Kind.b, v ? '1' : '0'),
      _ => (_Kind.s, '$value'),
    };
    _settings[key] = value;
    _track(_write(key, text, kind));
  }

  /// งานเขียนที่ยังไม่จบ
  ///
  /// 🔴 การเขียนแบบไม่รอทำให้จอไม่กระตุก แต่ก็แปลว่า**ค่าที่เพิ่งตั้งอาจยัง
  /// ไม่ถึงดิสก์ตอนแอปถูกปิด** · ผู้ใช้กดสวิตช์แล้วปิดแอปทันทีเป็นเรื่องปกติ
  /// ไม่ใช่กรณีพิเศษ · [close] และ [snapshotTo] จึงต้องรอคิวนี้ให้ว่างก่อน
  /// ไม่งั้นสำเนาที่ได้จะเป็นภาพก่อนหน้าค่าที่เพิ่งเปลี่ยน
  final Set<Future<void>> _pending = {};

  void _track(Future<void> f) {
    _pending.add(f);
    unawaited(f.whenComplete(() => _pending.remove(f)));
  }

  /// รอให้ทุกอย่างที่ค้างอยู่ลงดิสก์
  Future<void> flush() async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }

  /// ลบค่าหนึ่งตัว
  void remove(String key) {
    _settings.remove(key);
    _track(_db
        .delete('settings', where: 'key = ?', whereArgs: [key])
        .then((_) {}, onError: (Object e) {
      debugPrint('db: ลบค่า $key ไม่ได้ — $e');
    }));
  }

  /// คีย์ทั้งหมดที่มีอยู่ — ใช้ตอนย้ายข้อมูลและตอนแสดงให้เจ้าของตรวจ
  Set<String> get settingKeys => _settings.keys.toSet();

  Future<void> _write(String key, String value, _Kind kind) async {
    try {
      await _db.insert(
        'settings',
        {'key': key, 'value': value, 'kind': kind.name},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } on Object catch (e) {
      debugPrint('db: เขียนค่า $key ไม่ได้ — $e');
    }
  }

  // ═══ บทสนทนา ═══════════════════════════════════════════

  /// เก็บข้อความหนึ่งบรรทัด · คืน id ที่ได้
  Future<int> addMessage({required bool fromHer, required String text}) =>
      _db.insert('messages', {
        'from_her': fromHer ? 1 : 0,
        'text': text,
        'at': DateTime.now().millisecondsSinceEpoch,
      });

  /// [limit] ตาล่าสุด เรียงเก่า→ใหม่ (ลำดับที่โมเดลกับหน้าจอต้องการ)
  Future<List<({bool fromHer, String text})>> lastMessages(int limit) async {
    final rows = await _db.query(
      'messages',
      orderBy: 'id DESC',
      limit: limit,
    );
    return [
      for (final r in rows.reversed)
        (fromHer: r['from_her'] == 1, text: r['text']! as String),
    ];
  }

  Future<int> countMessages() async =>
      Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM messages')) ??
      0;

  Future<void> clearMessages() => _db.delete('messages');

  // ═══ ความจำ ════════════════════════════════════════════

  Future<List<Map<String, Object?>>> allMemories() =>
      _db.query('memories', orderBy: 'created_at DESC');

  Future<void> putMemory(Map<String, Object?> row) => _db.insert(
        'memories',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> deleteMemory(String id) =>
      _db.delete('memories', where: 'id = ?', whereArgs: [id]);

  Future<void> clearMemories() => _db.delete('memories');

  // ═══ ไทม์ไลน์ ══════════════════════════════════════════

  Future<List<Map<String, Object?>>> allJournal({int limit = 300}) =>
      _db.query('journal', orderBy: 'at DESC', limit: limit);

  Future<void> putJournal(Map<String, Object?> row) => _db.insert(
        'journal',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> deleteJournal(String id) =>
      _db.delete('journal', where: 'id = ?', whereArgs: [id]);

  Future<void> clearJournal() => _db.delete('journal');

  /// ตัดของเก่าทิ้งเมื่อเกินเพดาน — ไทม์ไลน์เป็นบันทึกเหตุการณ์ ไม่ใช่ความจำ
  /// เก็บไว้ทั้งหมดก็ไม่มีใครเลื่อนไปดูปีที่แล้ว
  Future<void> trimJournal(int keep) => _db.rawDelete(
        'DELETE FROM journal WHERE id NOT IN '
        '(SELECT id FROM journal ORDER BY at DESC LIMIT ?)',
        [keep],
      );

  // ═══ ธงของระบบ ═════════════════════════════════════════

  Future<String?> meta(String key) async {
    final rows =
        await _db.query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setMeta(String key, String value) => _db.insert(
        'meta',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  // ═══ ดูดของเก่าเข้ามาครั้งเดียว ═════════════════════════

  /// ธงว่าดูดของเก่าเข้ามาแล้ว — ต้องมี ไม่งั้นการดูดจะวิ่งทุกครั้งที่เปิดแอป
  /// แล้วของที่ผู้ใช้ลบไปแล้วจะกลับมาเองทุกรอบ ซึ่งน่ากลัวกว่าข้อมูลหาย
  static const _kImported = 'imported_v1';

  /// ย้ายค่าตั้งค่าจาก SharedPreferences เข้ามา ครั้งเดียวตลอดอายุแอป
  ///
  /// เอาทุกคีย์ที่มี ไม่ได้ไล่ชื่อทีละตัว — เพราะคีย์ไม่ได้อยู่ที่เดียว
  /// ([MindState] มีชุดหนึ่ง [MindSoul] มีอีกชุด และชื่อ `voice_*` สร้างจาก
  /// enum ตอนรัน) การไล่รายชื่อคือการลืมบางตัวแน่นอน แล้วผู้ใช้จะเสียค่าที่
  /// ตั้งไว้ไปบางส่วนโดยไม่มีอะไรบอกว่าหายไปตัวไหน
  ///
  /// ความจำกับไทม์ไลน์ **ย้ายตัวเอง** ใน `load()` ของแต่ละคลาส เพราะมันรู้
  /// รูปแบบไฟล์ของตัวเองดีที่สุด · ที่นี่ทำแค่ค่าตั้งค่า
  ///
  /// 🔴 **ไม่ลบของเก่าทิ้ง** · ผู้ใช้ที่อัปเดตแล้วเจอปัญหาต้องถอยกลับไปรุ่นก่อนได้
  /// ถ้าลบต้นทางตั้งแต่รอบแรก การถอยกลับจะเจอแอปเปล่า · ของเก่ากินที่ไม่กี่ร้อย
  /// KB ปล่อยไว้ถูกกว่าเสี่ยง
  Future<int> importSettings() async {
    if (await meta(_kImported) == '1') return 0;

    var moved = 0;
    try {
      final p = await SharedPreferences.getInstance();
      await _db.transaction((txn) async {
        for (final key in p.getKeys()) {
          final v = p.get(key);
          if (v == null) continue;
          final (kind, text) = switch (v) {
            final int x => (_Kind.i, '$x'),
            final double x => (_Kind.d, '$x'),
            final bool x => (_Kind.b, x ? '1' : '0'),
            final String x => (_Kind.s, x),
            // `setStringList` ไม่ได้ถูกใช้ในแอปนี้เลย · ข้ามดีกว่าเดารูปแบบ
            // แล้วเก็บผิด เพราะค่าที่เก็บผิดจะพังตอนอ่านกลับ ไกลจากจุดนี้มาก
            _ => (_Kind.s, ''),
          };
          if (v is! String && text.isEmpty) continue;
          await txn.insert(
            'settings',
            {'key': key, 'value': text, 'kind': kind.name},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          moved++;
        }
      });
    } on Object catch (e) {
      debugPrint('db: ดูดค่าตั้งค่าเก่าไม่สำเร็จ — $e');
      return 0;
    }

    await setMeta(_kImported, '1');
    await _loadSettings();
    if (moved > 0) debugPrint('db: ย้ายค่าตั้งค่าเก่าเข้ามา $moved ตัว');
    return moved;
  }

  /// อ่านค่าตั้งค่าทั้งก้อนขึ้นหน่วยความจำ · เรียกหลังเปิดฐานเสมอ
  Future<void> warm() => _loadSettings();

  /// ล้างทุกอย่างที่เป็นของผู้ใช้ — ไม่แตะ [meta] (ดูเหตุผลที่ตาราง meta)
  Future<void> wipeUserData() async {
    await _db.transaction((txn) async {
      await txn.delete('settings');
      await txn.delete('messages');
      await txn.delete('memories');
      await txn.delete('journal');
    });
    _settings.clear();
  }

  /// สำเนาที่อ่านได้แน่นอน แม้มีคนกำลังเขียนอยู่
  ///
  /// `VACUUM INTO` ทำสำเนาที่ **สอดคล้องกันทั้งไฟล์** โดยไม่ต้องหยุดฐาน
  /// ต่างจากการก๊อปไฟล์ดิบ ซึ่งได้ครึ่งธุรกรรมติดมาด้วยถ้าจังหวะไม่ดี
  /// (ยิ่งเปิด WAL ยิ่งพัง เพราะข้อมูลจริงบางส่วนอยู่ในไฟล์ -wal คนละไฟล์)
  Future<void> snapshotTo(String path) async {
    await flush();
    final f = File(path);
    // VACUUM INTO ปฏิเสธถ้าไฟล์ปลายทางมีอยู่แล้ว
    if (await f.exists()) await f.delete();
    await _db.execute('VACUUM INTO ?', [path]);
  }

  Future<void> close() async {
    await flush();
    await _db.close();
    if (identical(_open, this)) _open = null;
  }
}
