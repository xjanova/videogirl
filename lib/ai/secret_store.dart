/// ที่เก็บความลับของผู้ใช้ — แยกจาก SharedPreferences โดยตั้งใจ
///
/// `SharedPreferences` เป็นไฟล์ XML ธรรมดาในโฟลเดอร์แอป อ่านได้ทันทีถ้าเครื่อง
/// root และหลุดออกไปกับ backup ของ Android ได้ด้วย · คีย์ OpenAI ของผู้ใช้
/// ไม่ควรอยู่ตรงนั้น จึงใช้ตัวนี้ซึ่งเข้ารหัสด้วยกุญแจที่อยู่ใน Android Keystore
///
/// 🔴 **ที่นี่เก็บได้เฉพาะความลับ "ของผู้ใช้เอง"** เช่นคีย์ที่เขากรอกมาเอง
/// ห้ามเอาคีย์ของเราลงมาเก็บที่เครื่องผู้ใช้ไม่ว่าจะเข้ารหัสแค่ไหน — กุญแจถอด
/// ต้องอยู่ในแอป ใครแกะ APK ก็ได้ไปพร้อมกัน และต่อให้ถอดไม่ได้ก็ยังดักอ่าน
/// ตอนแอปยิงออกไปได้อยู่ดี · คีย์ของเราต้องอยู่หลังบ้านและไม่ออกมาเลย
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract final class SecretStore {
  /// ค่าเริ่มต้นของ v11 แข็งพออยู่แล้ว — AES-GCM หุ้มด้วย RSA-OAEP
  /// ที่กุญแจอยู่ใน Keystore · `resetOnError` เป็น true มาเอง ซึ่งจำเป็น
  /// เพราะกุญแจใน Keystore หายได้จริง (ย้ายเครื่อง/กู้คืน) ถ้าไม่รีเซ็ต
  /// ผู้ใช้จะติดอยู่กับข้อผิดพลาดที่แก้เองไม่ได้ตลอดไป
  static const _box = FlutterSecureStorage();

  /// คีย์ OpenAI ที่ผู้ใช้กรอกเอง
  static const kOpenAiKey = 'openai_api_key';

  /// อ่านค่า — คืนค่าว่างถ้าไม่มีหรืออ่านไม่ได้
  ///
  /// อ่านไม่ได้ไม่ควรทำให้แอปพัง · เครื่องบางรุ่นมี Keystore ที่มีปัญหาจริง
  /// ผลที่ควรได้คือ "เหมือนยังไม่ได้ตั้งคีย์" ไม่ใช่แอปเปิดไม่ขึ้น
  static Future<String> read(String key) async {
    try {
      return await _box.read(key: key) ?? '';
    } on Object catch (e) {
      // ห้าม log ค่า · log ได้แค่ว่าอ่านไม่ผ่าน
      debugPrint('secret store: อ่าน $key ไม่ได้ — ${e.runtimeType}');
      return '';
    }
  }

  /// เขียนค่า — ค่าว่างคือลบทิ้ง ไม่ใช่เก็บสตริงว่างไว้
  static Future<void> write(String key, String value) async {
    try {
      final v = value.trim();
      if (v.isEmpty) {
        await _box.delete(key: key);
      } else {
        await _box.write(key: key, value: v);
      }
    } on Object catch (e) {
      debugPrint('secret store: เขียน $key ไม่ได้ — ${e.runtimeType}');
    }
  }

  /// ย่อคีย์ให้พอยืนยันว่าใส่ถูกตัว แต่เอาไปใช้ต่อไม่ได้
  ///
  /// `sk-proj-abc...wxyz` · ไม่โชว์เต็มเพราะหน้าจอถูกแคปได้ และคนข้าง ๆ
  /// ก็อ่านได้ · สั้นกว่า 12 ตัวถือว่าไม่ใช่คีย์จริง ปิดทั้งหมดไปเลย
  static String mask(String key) {
    final k = key.trim();
    if (k.isEmpty) return '';
    if (k.length < 12) return '•' * k.length;
    return '${k.substring(0, 7)}…${k.substring(k.length - 4)}';
  }
}
