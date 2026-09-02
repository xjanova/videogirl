/// ที่เก็บค่าตั้งค่าแบบคีย์-ค่า หลังหน้าตาเดียวกัน
///
/// มีสองตัวจริง: [DbKv] ที่เก็บลง SQLite (ของจริง) กับ [PrefsKv] ที่ตกกลับไป
/// ใช้ SharedPreferences
///
/// ## 🔴 ตัวสำรองไม่ใช่ของสำหรับเทสต์ มันคือพฤติกรรมที่ต้องมีจริง
///
/// ฐาน SQLite เปิดไม่ขึ้นได้จริงบนเครื่องผู้ใช้ — ดิสก์เต็ม, ไฟล์เสียจากการ
/// ปิดเครื่องกลางคัน, พื้นที่แอปถูกล็อกโดยระบบกู้คืน · ถ้าไม่มีทางสำรอง
/// แอปจะเปิดไม่ขึ้นเลยเพราะเรื่องที่ผู้ใช้แก้เองไม่ได้ · ตกมาใช้ของเดิม
/// แล้วบอกให้รู้ ดีกว่าจอขาว
///
/// หน้าตาเลียนแบบ [SharedPreferences] โดยตั้งใจ (`getInt`/`setInt`/…)
/// เพื่อให้โค้ดที่เรียกอยู่แล้วสิบกว่าที่ ย้ายมาได้โดยแก้แค่ชนิดของตัวแปร
/// การรื้อ call site ทุกจุดพร้อมกันคือวิธีที่พลาดง่ายที่สุด
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'mind_db.dart';

abstract interface class MindKv {
  String? getString(String key);
  int? getInt(String key);
  double? getDouble(String key);
  bool? getBool(String key);

  Future<bool> setString(String key, String value);
  Future<bool> setInt(String key, int value);
  Future<bool> setDouble(String key, double value);
  Future<bool> setBool(String key, bool value);

  Future<bool> remove(String key);

  Set<String> get keys;

  /// ข้อมูลอยู่ในฐานจริงไหม — false แปลว่าตกมาใช้ตัวสำรองอยู่
  /// หน้าตั้งค่าต้องบอกผู้ใช้ ไม่ใช่เงียบแล้วปล่อยให้สำเนาไม่เคยเกิดขึ้น
  bool get durable;
}

extension MindKvWrite on MindKv {
  /// เขียนค่าโดยดูชนิดให้เอง — ผู้เรียกส่วนใหญ่มีแค่ `Object` อยู่ในมือ
  /// (ค่าที่เพิ่งอ่านมาจาก UI) การให้ทุกที่ switch ชนิดเองคือการก๊อปโค้ด
  /// เดียวกันไปสิบที่ แล้ววันหนึ่งจะมีที่หนึ่งลืมรองรับ bool
  void let(String key, Object value) {
    switch (value) {
      case String v:
        setString(key, v);
      case double v:
        setDouble(key, v);
      case int v:
        setInt(key, v);
      case bool v:
        setBool(key, v);
    }
  }
}

/// ของจริง — ลง SQLite
class DbKv implements MindKv {
  DbKv(this.db);

  final MindDb db;

  @override
  bool get durable => true;

  @override
  String? getString(String key) => db.getString(key);
  @override
  int? getInt(String key) => db.getInt(key);
  @override
  double? getDouble(String key) => db.getDouble(key);
  @override
  bool? getBool(String key) => db.getBool(key);

  @override
  Future<bool> setString(String key, String value) async {
    db.put(key, value);
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    db.put(key, value);
    return true;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    db.put(key, value);
    return true;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    db.put(key, value);
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    db.remove(key);
    return true;
  }

  @override
  Set<String> get keys => db.settingKeys;
}

/// ตัวสำรอง — ของเดิมก่อนย้ายมา SQLite
class PrefsKv implements MindKv {
  PrefsKv(this.prefs);

  final SharedPreferences prefs;

  @override
  bool get durable => false;

  @override
  String? getString(String key) => prefs.getString(key);
  @override
  int? getInt(String key) => prefs.getInt(key);
  @override
  double? getDouble(String key) => prefs.getDouble(key);
  @override
  bool? getBool(String key) => prefs.getBool(key);

  @override
  Future<bool> setString(String key, String value) =>
      prefs.setString(key, value);
  @override
  Future<bool> setInt(String key, int value) => prefs.setInt(key, value);
  @override
  Future<bool> setDouble(String key, double value) =>
      prefs.setDouble(key, value);
  @override
  Future<bool> setBool(String key, bool value) => prefs.setBool(key, value);

  @override
  Future<bool> remove(String key) => prefs.remove(key);

  @override
  Set<String> get keys => prefs.getKeys();
}
