/// ลำดับการเปิดที่เก็บข้อมูลทั้งหมด — เรียกครั้งเดียวตอนแอปเริ่ม
///
/// ## 🔴 ลำดับสำคัญ และสลับไม่ได้
///
/// 1. **กู้สำเนากลับก่อน** ถ้าในเครื่องยังไม่มีฐาน (= เพิ่งลงแอปใหม่)
///    ต้องทำ**ก่อน**เปิดฐาน เพราะไฟล์ที่กำลังถูกเปิดอยู่เขียนทับไม่ได้
///    สลับลำดับแล้วจะได้ฐานเปล่าที่เปิดค้างไว้ แล้วการกู้จะล้มเงียบ ๆ
/// 2. เปิดฐาน
/// 3. ย้ายค่าตั้งค่าเก่าจาก SharedPreferences เข้ามา (ครั้งเดียว)
/// 4. อ่านค่าขึ้นหน่วยความจำ
///
/// ล้มขั้นไหนก็ตกไปใช้ [PrefsKv] ทั้งหมด — แอปยังเปิดได้ แค่ไม่มีสำเนา
/// และบทสนทนากลับไปมีเพดานเหมือนเดิม · หน้าตั้งค่าบอกผู้ใช้ว่าอยู่โหมดไหน
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mind_db.dart';
import 'mind_kv.dart';
import 'mind_vault.dart';

/// ผลของการเปิดที่เก็บข้อมูล
class MindStore {
  const MindStore({
    required this.kv,
    required this.db,
    required this.vault,
    required this.restored,
  });

  /// ค่าตั้งค่า — เป็น [DbKv] เมื่อฐานเปิดได้ ไม่งั้นเป็น [PrefsKv]
  final MindKv kv;

  /// ฐานจริง — null เมื่อเปิดไม่ขึ้น (แล้ว [kv] จะเป็นตัวสำรอง)
  final MindDb? db;

  final MindVault vault;

  /// เพิ่งกู้ข้อมูลกลับมาจากสำเนาข้างนอกในรอบนี้ไหม
  ///
  /// ต้องบอกผู้ใช้ ไม่งั้นเขาลงแอปใหม่แล้วเห็นบทสนทนาเก่าโผล่มาเองโดยไม่รู้
  /// ว่ามาจากไหน — ซึ่งอ่านว่า "แอปเก็บข้อมูลเราไว้ที่ไหนไม่รู้"
  final bool restored;

  bool get durable => db != null;

  /// เปิดทุกอย่างตามลำดับข้างบน
  static Future<MindStore> open({
    required MindVault vault,
    String? pathOverride,
  }) async {
    var restored = false;
    MindDb? db;

    try {
      final path = pathOverride ?? await MindDb.defaultPath();
      restored = await vault.restoreIfFresh(path);
      db = await MindDb.openIn(path);
      await db.importSettings();
      await db.warm();
    } on Object catch (e, st) {
      debugPrint('store: เปิดฐานไม่สำเร็จ ตกไปใช้ของเดิม — $e\n$st');
      db = null;
    }

    if (db != null) {
      return MindStore(
        kv: DbKv(db),
        db: db,
        vault: vault,
        restored: restored,
      );
    }

    // ตัวสำรอง · ถึงตรงนี้แปลว่า SQLite ใช้ไม่ได้บนเครื่องนี้จริง ๆ
    return MindStore(
      kv: PrefsKv(await SharedPreferences.getInstance()),
      db: null,
      vault: vault,
      restored: false,
    );
  }
}
