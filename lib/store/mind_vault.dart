/// สำเนาที่รอดจากการถอนแอป
///
/// ## 🔴 ไม่มีอะไรใน "พื้นที่ของแอป" ที่รอด uninstall ได้เลย
///
/// Android ล้าง `/data/data/<pkg>/` ทั้งก้อนตอนถอนแอป — ทั้งฐาน SQLite,
/// SharedPreferences และไฟล์ JSON · ย้ายไป SQLite เฉย ๆ ข้อมูลจึงยังหาย
/// เหมือนเดิมทุกประการ · "ลงใหม่แล้วไม่หาย" ต้องมีสำเนาอยู่**นอกพื้นที่แอป**
///
/// ที่นี่เก็บที่ `/storage/emulated/0/GigGok/` ซึ่งอยู่นอกขอบเขตที่ระบบล้าง
/// แลกมาด้วยสิทธิ์ `MANAGE_EXTERNAL_STORAGE` — แอปนี้แจก APK เอง
/// (ดู updater.dart) จึงไม่ติดเงื่อนไขรีวิวของ Play Store
///
/// ## ทำไมเป็น "สำเนา" ไม่ใช่ "ฐานจริงที่อยู่ตรงนั้นเลย"
///
/// SQLite ที่รันสดบนพื้นที่เก็บร่วมของ Android **ไม่ปลอดภัย** ชั้น FUSE
/// ทำ POSIX advisory lock ไม่ครบ ผลคือ `SQLITE_IOERR` และไฟล์เสียได้จริง
/// ฐานจริงจึงอยู่ในพื้นที่แอป แล้วส่งสำเนาออกมาที่นี่เป็นระยะ
/// ผลที่ผู้ใช้เห็นเหมือนกันเป๊ะ แต่ไม่เสี่ยงฐานพัง
///
/// ## 🔴 ไฟล์นี้แอปอื่นอ่านได้
///
/// อยู่ในพื้นที่เก็บร่วม แปลว่าแอปที่มีสิทธิ์อ่านไฟล์ และตัวจัดการไฟล์ของ
/// ผู้ใช้เอง เปิดดูได้ · **คีย์ OpenAI ของผู้ใช้จึงห้ามอยู่ในฐานเด็ดขาด**
/// มันอยู่ใน Keystore ([SecretStore]) และไม่เคยถูกเขียนลง SQLite เลย
/// รหัสสิทธิ์ (license) อยู่ในนี้ด้วยโดยตั้งใจ เพราะมันคือค่าที่เจ้าของ
/// ต้องการให้กลับมาเองตอนลงใหม่ และหลุดไปก็ทำได้แค่กินโควตาของไลเซนส์นั้น
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mind_db.dart';

/// คีย์ของสวิตช์ในที่เก็บค่า
///
/// อยู่ที่นี่ไม่ใช่ใน [MindState] เพราะมันต้องถูกอ่าน **ก่อน** ที่เก็บค่าจะเปิด
/// (ต้องรู้ว่าจะกู้ข้อมูลหรือไม่ ตั้งแต่ก่อนมีฐานให้อ่าน) — ไก่กับไข่ที่แก้ด้วย
/// การอ่านจาก SharedPreferences ตรง ๆ ซึ่งเป็นที่เดียวที่พร้อมใช้ตั้งแต่วินาทีแรก
abstract final class MindVaultKeys {
  static const wipeOnUninstall = 'wipeOnUninstall';

  /// ผู้ใช้สั่งให้กู้สำเนาเก่าในการเปิดแอปรอบหน้า — ดู [MindVault.requestRestore]
  static const restorePending = 'vaultRestorePending';
}

/// โฟลเดอร์ที่สำเนาไปอยู่ · ชื่อเป็นชื่อแอปเพื่อให้คนที่เปิดดูด้วยตัวจัดการ
/// ไฟล์รู้ว่าของใคร ไม่ใช่โฟลเดอร์ปริศนาที่ไม่มีใครกล้าลบ
const kVaultDirName = 'GigGok';

/// รากของพื้นที่เก็บร่วมบนแอนดรอยด์
///
/// เขียนตรง ๆ ไม่ผ่าน path_provider เพราะ `getExternalStorageDirectory()`
/// คืน `Android/data/<pkg>/` ซึ่ง **ถูกล้างตอนถอนแอปเหมือนกัน** — เป็นกับดัก
/// ที่ดูเหมือนใช้ได้ตอนทดสอบ (ไฟล์เขียนได้จริง) แล้วพังตอนที่สำคัญที่สุด
const _sharedRoot = '/storage/emulated/0';

enum VaultStage {
  /// ยังไม่ได้ตรวจ
  unknown,

  /// เขียนได้จริง สำเนาปลอดภัย
  ready,

  /// ยังไม่ได้สิทธิ์เข้าถึงไฟล์ทั้งเครื่อง
  needsPermission,

  /// ผู้ใช้เลือกให้ลบทุกอย่างตอนถอนแอป — ตั้งใจไม่มีสำเนา
  off,

  /// มีสิทธิ์แล้วแต่เขียนไม่ได้จริง (พื้นที่เต็ม, เครื่องแปลก)
  failed,

  /// 🔴 ข้างนอกมีสำเนาของ**การติดตั้งครั้งก่อน** ที่ไม่ใช่ของฐานนี้
  ///
  /// เกิดเมื่อลงแอปใหม่แล้วยังไม่ได้ให้สิทธิ์ไฟล์ตอนเปิดครั้งแรก — การกู้
  /// จึงไม่ได้วิ่ง และได้ฐานเปล่ามาแทน · **ห้ามเขียนทับจนกว่าเจ้าของจะเลือก**
  /// ว่ากู้ของเก่า หรือใช้ของตอนนี้แทน
  foreign,
}

/// จัดการสำเนาข้างนอก · ไม่รู้จัก UI และไม่รู้จักระบบสิทธิ์
/// รับความสามารถที่ต้องใช้เข้ามาเป็นฟังก์ชัน จึงทดสอบได้โดยไม่ต้องมีเครื่องจริง
class MindVault extends ChangeNotifier {
  MindVault({
    required this.hasAllFiles,
    String root = _sharedRoot,
  }) : _root = root;

  /// ได้สิทธิ์เข้าถึงไฟล์ทั้งเครื่องแล้วหรือยัง
  final bool Function() hasAllFiles;

  final String _root;

  String get dirPath => '$_root${Platform.pathSeparator}$kVaultDirName';
  String get filePath => '$dirPath${Platform.pathSeparator}$kDbFileName';

  /// ป้ายของฐานที่เขียนสำเนานี้ — ไฟล์ข้อความข้าง ๆ สำเนา
  ///
  /// แยกเป็นไฟล์ ไม่เปิดสำเนาเพื่ออ่าน meta เพราะ SQLite บนพื้นที่เก็บร่วม
  /// เชื่อไม่ได้ (ดูหัวไฟล์) แม้แต่แค่เปิดอ่าน
  String get idPath => '$filePath.id';

  /// สำเนาเก่าที่ถูกเก็บไว้ตอนเจ้าของเลือก "ใช้ข้อมูลตอนนี้" — ไม่ลบทิ้งเลย
  String get previousPath => '$filePath.previous';

  /// ป้ายของฐานที่เปิดอยู่ · null = ยังไม่ได้ต่อ (เทสต์บางตัว) → ไม่ตรวจ
  String? _lineage;
  bool _bornNew = false;
  bool _restored = false;

  /// ต่อกับฐานที่เพิ่งเปิด · เรียกจาก [MindStore.open]
  void attach({
    required String lineage,
    required bool bornNew,
    required bool restored,
  }) {
    _lineage = lineage;
    _bornNew = bornNew;
    _restored = restored;
  }

  /// สำเนาข้างนอกเป็นของการติดตั้งอื่นไหม
  Future<bool> _isForeign() async {
    final mine = _lineage;
    if (mine == null || _restored) return false;
    if (!await File(filePath).exists()) return false;
    final id = File(idPath);
    if (await id.exists()) {
      return (await id.readAsString()).trim() != mine;
    }
    // สำเนาจากรุ่นก่อนที่ยังไม่มีป้าย · ฐานเก่าที่เพิ่งได้ป้ายคือเจ้าของเดิม
    // ของมัน (พฤติกรรมเดิม) ส่วนฐานที่เกิดเปล่า ๆ ไม่ใช่
    return _bornNew;
  }

  VaultStage _stage = VaultStage.unknown;
  VaultStage get stage => _stage;

  /// ผู้ใช้ติ๊ก "ลบข้อมูลทั้งหมดเมื่อถอนแอป" ไว้ไหม
  ///
  /// ค่าตั้งต้นคือ **ไม่ติ๊ก** = ข้อมูลรอด · ค่าตั้งต้นที่ทำให้ของหายเป็น
  /// ค่าตั้งต้นที่ผิด เพราะคนที่อยากให้หายรู้ตัวว่าอยากให้หาย ส่วนคนที่ไม่รู้
  /// ว่ามีสวิตช์นี้อยู่จะเสียข้อมูลไปโดยไม่เคยเลือกอะไรเลย
  bool _wipeOnUninstall = false;
  bool get wipeOnUninstall => _wipeOnUninstall;

  DateTime? _savedAt;

  /// สำเนาล่าสุดเมื่อไหร่ — null ถ้ายังไม่เคยสำเร็จในรอบนี้
  DateTime? get savedAt => _savedAt;

  String? _error;
  String? get error => _error;

  void _set(VaultStage s, {String? error}) {
    _stage = s;
    _error = error;
    notifyListeners();
  }

  /// ตรวจว่าตอนนี้สำเนาได้ไหม
  Future<VaultStage> check() async {
    if (_wipeOnUninstall) {
      _set(VaultStage.off);
      return _stage;
    }
    if (!hasAllFiles()) {
      _set(VaultStage.needsPermission);
      return _stage;
    }
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) await dir.create(recursive: true);
      _set(await _isForeign() ? VaultStage.foreign : VaultStage.ready);
    } on Object catch (e) {
      debugPrint('vault: เขียนโฟลเดอร์ไม่ได้ — $e');
      _set(VaultStage.failed, error: '$e');
    }
    return _stage;
  }

  /// เปลี่ยนสวิตช์ "ลบทุกอย่างเมื่อถอนแอป"
  ///
  /// 🔴 เปิดสวิตช์ = **ลบสำเนาทิ้งเดี๋ยวนี้** ไม่ใช่รอถึงวันถอนแอป
  ///
  /// สวิตช์ที่บอกว่า "จะลบตอนถอนแอป" แล้วปล่อยไฟล์ทิ้งไว้จนถึงวันนั้น
  /// คือสวิตช์ที่โกหก — และวันที่ถอนแอปจริง ๆ ไม่มีโค้ดของเราวิ่งอยู่แล้ว
  /// ที่จะไปลบให้ได้ (Android ไม่มี hook ตอน uninstall ที่เชื่อถือได้)
  /// ทางเดียวที่คำสัญญานี้เป็นจริงคือไม่ทิ้งอะไรไว้ข้างนอกตั้งแต่แรก
  Future<void> setWipeOnUninstall(bool v) async {
    if (_wipeOnUninstall == v) return;
    _wipeOnUninstall = v;
    if (v) {
      await removeCopy();
    }
    await check();
  }

  /// อ่านค่าสวิตช์กลับมาตอนเปิดแอป
  void restoreSwitch(bool v) {
    _wipeOnUninstall = v;
    _stage = VaultStage.unknown;
  }

  /// 🔴 อ่านสวิตช์จาก SharedPreferences **ไม่ใช่จากฐาน**
  ///
  /// ค่านี้ต้องรู้ก่อนที่ฐานจะเปิด เพราะมันตัดสินว่าจะกู้ข้อมูลกลับมาไหม
  /// ซึ่งเป็นขั้นที่เกิดก่อนการเปิดฐาน · อ่านจากฐานคือการถามคำถามกับของ
  /// ที่ยังไม่มีอยู่ · จึงเก็บไว้สองที่โดยตั้งใจ ([MindState] เขียนทั้งคู่)
  static Future<bool> readSwitch() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(MindVaultKeys.wipeOnUninstall) ?? false;
    } on Object catch (e) {
      debugPrint('vault: อ่านสวิตช์ไม่ได้ — $e');
      return false;
    }
  }

  static Future<void> writeSwitch(bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(MindVaultKeys.wipeOnUninstall, v);
    } on Object catch (e) {
      debugPrint('vault: เขียนสวิตช์ไม่ได้ — $e');
    }
  }

  Timer? _debounce;

  /// สำเนาลงข้างนอก · หน่วงไว้เพราะการคุยหนึ่งตาเขียนฐานหลายครั้ง
  ///
  /// การสำเนาคือการเขียนไฟล์ทั้งก้อน ทำทุกครั้งที่ฐานขยับ = เขียนเมกะไบต์
  /// ทุกตัวอักษรที่พิมพ์ · หน่วง 20 วินาทีแล้วเขียนทีเดียวก็พอ ข้อมูลที่
  /// เสี่ยงหายคือ 20 วินาทีสุดท้าย ซึ่งแลกกับแบตและอายุหน่วยความจำแล้วคุ้ม
  static const saveDelay = Duration(seconds: 20);

  void scheduleSave(MindDb db) {
    if (_wipeOnUninstall) return;
    _debounce?.cancel();
    _debounce = Timer(saveDelay, () => unawaited(saveNow(db)));
  }

  /// สำเนาที่กำลังเขียนอยู่ · ตัวที่สองต้องรอตัวแรก ไม่ใช่เขียนไฟล์ .tmp ตัวเดียวกัน
  /// พร้อมกัน (นาฬิกาหน่วง 20 วิ กับตอนแอปลงพื้นหลังชนกันได้จริง) ซึ่งจบที่
  /// ตัวหนึ่ง rename ไฟล์ที่อีกตัวกำลังเขียน แล้วขึ้นว่าสำเนาไม่สำเร็จ
  Future<bool>? _saving;

  /// สำเนาเดี๋ยวนี้ · ใช้ตอนแอปกำลังจะถูกพับลงพื้นหลัง และตอนผู้ใช้กดเอง
  Future<bool> saveNow(MindDb db) async {
    final running = _saving;
    if (running != null) {
      await running;
    }
    final mine = _saveNow(db);
    _saving = mine;
    try {
      return await mine;
    } finally {
      if (identical(_saving, mine)) _saving = null;
    }
  }

  Future<bool> _saveNow(MindDb db) async {
    _debounce?.cancel();
    if (_wipeOnUninstall) return false;
    if (await check() != VaultStage.ready) return false;

    try {
      // เขียนลงชื่อชั่วคราวก่อนแล้วค่อยเปลี่ยนชื่อทับ — ไฟล์ปลายทางจึงไม่เคย
      // อยู่ในสภาพเขียนค้าง · ถ้าแบตหมดกลางคัน สำเนาเดิมยังใช้ได้อยู่
      // ซึ่งดีกว่ามีไฟล์ครึ่งเดียวที่กู้อะไรไม่ได้เลย
      final tmp = '$filePath.tmp';
      await db.snapshotTo(tmp);
      await File(tmp).rename(filePath);
      // ป้ายต้องตามสำเนาไปเสมอ · ไม่งั้นการเปิดครั้งหน้าจะคิดว่าเป็นของคนอื่น
      if (db.lineage.isNotEmpty) {
        await File(idPath).writeAsString(db.lineage, flush: true);
      }
      _savedAt = DateTime.now();
      notifyListeners();
      return true;
    } on Object catch (e) {
      debugPrint('vault: สำเนาไม่สำเร็จ — $e');
      _set(VaultStage.failed, error: '$e');
      return false;
    }
  }

  /// มีสำเนาให้กู้ไหม
  Future<bool> hasCopy() async {
    if (!hasAllFiles()) return false;
    try {
      return await File(filePath).exists();
    } on Object {
      return false;
    }
  }

  /// ลบสำเนาข้างนอกทิ้ง
  Future<void> removeCopy() async {
    try {
      final f = File(filePath);
      if (await f.exists()) await f.delete();
      final tmp = File('$filePath.tmp');
      if (await tmp.exists()) await tmp.delete();
    } on Object catch (e) {
      debugPrint('vault: ลบสำเนาไม่สำเร็จ — $e');
    }
  }

  /// กู้สำเนากลับเข้าพื้นที่แอป · คืน true เมื่อกู้จริง
  ///
  /// 🔴 **กู้เฉพาะตอนที่ในเครื่องยังไม่มีฐาน** — คือกรณี "เพิ่งลงแอปใหม่"
  /// ถ้ากู้ทับของที่มีอยู่ จะกลายเป็นการเอาสำเนาเก่ามาลบสิ่งที่เพิ่งคุยกัน
  /// ซึ่งเป็นการทำลายข้อมูลที่ผู้ใช้ไม่ได้สั่งและกู้คืนไม่ได้
  ///
  /// เรียก **ก่อน** เปิดฐาน — ไฟล์ที่กำลังถูกเปิดอยู่เขียนทับไม่ได้
  Future<bool> restoreIfFresh(String dbPath) async {
    if (_wipeOnUninstall) return false;
    final pending = await _takePending();
    final tmp = File('$dbPath.restore');
    try {
      if (!await hasCopy()) return false;
      if (await File(dbPath).exists()) {
        // ฐานมีอยู่แล้ว = ห้ามแตะ · ยกเว้นเจ้าของเพิ่งสั่งกู้เองจาก [foreign]
        if (!pending) return false;
        for (final suffix in const ['', '-wal', '-shm', '-journal']) {
          final f = File('$dbPath$suffix');
          if (await f.exists()) await f.delete();
        }
      }

      // ก๊อปลงชื่อชั่วคราวก่อนแล้วค่อยเปลี่ยนชื่อ · ก๊อปไม่จบ (แบตหมด/ที่เต็ม)
      // จะไม่ทิ้งไฟล์ครึ่งเดียวไว้ในชื่อจริง ซึ่งจะทำให้การกู้ไม่วิ่งอีกเลย
      await File(filePath).copy(tmp.path);
      await tmp.rename(dbPath);
      debugPrint('vault: กู้ข้อมูลกลับจากสำเนาข้างนอกแล้ว');
      return true;
    } on Object catch (e) {
      debugPrint('vault: กู้คืนไม่สำเร็จ — $e');
      try {
        if (await tmp.exists()) await tmp.delete();
      } on Object {
        // เก็บกวาดไม่ได้ก็ปล่อย
      }
      return false;
    }
  }

  /// อ่านแล้วล้างธง "กู้รอบหน้า" · ล้างก่อนกู้เสมอ — กู้พังแล้วธงค้าง
  /// = ลบฐานทิ้งทุกครั้งที่เปิดแอป
  static Future<bool> _takePending() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getBool(MindVaultKeys.restorePending) ?? false;
      if (v) await p.remove(MindVaultKeys.restorePending);
      return v;
    } on Object {
      return false;
    }
  }

  /// เจ้าของเลือก "กู้ข้อมูลเก่า" ตอน [VaultStage.foreign]
  ///
  /// กู้ตอนนี้เลยไม่ได้ เพราะทุกส่วนของแอปถือฐานที่เปิดอยู่ไว้ · ตั้งธงไว้แล้ว
  /// ให้การเปิดแอปรอบหน้าเป็นคนกู้ ก่อนที่ใครจะได้เปิดฐาน
  Future<void> requestRestore() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(MindVaultKeys.restorePending, true);
  }

  /// เจ้าของเลือก "ใช้ข้อมูลตอนนี้" ตอน [VaultStage.foreign]
  ///
  /// สำเนาเก่าไม่ถูกลบ แค่ย้ายไปชื่อ `.previous` · เผื่อเปลี่ยนใจ ก็ยังเอา
  /// กลับมาได้ด้วยตัวจัดการไฟล์
  Future<bool> adopt(MindDb db) async {
    try {
      final prev = File(previousPath);
      if (await prev.exists()) await prev.delete();
      final copy = File(filePath);
      if (await copy.exists()) await copy.rename(previousPath);
      final id = File(idPath);
      if (await id.exists()) await id.delete();
    } on Object catch (e) {
      debugPrint('vault: ย้ายสำเนาเก่าไม่สำเร็จ — $e');
      _set(VaultStage.failed, error: '$e');
      return false;
    }
    return saveNow(db);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
