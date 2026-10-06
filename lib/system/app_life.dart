import 'package:flutter/foundation.dart';

import 'permissions.dart';

/// พักแอป / ปิดแอปจริง — คู่กับ MainActivity.kt (`moveToBack` · `exitApp`)
///
/// ## 🔴 ทำไมปุ่มย้อนกลับต้องไม่ปิดแอป
///
/// ของเดิมกดย้อนกลับจนสุดแล้ว Android ปิดหน้าแอปทิ้ง (FlutterActivity จบตัวเอง)
/// · เปิดใหม่ = โหลดตัวเธอ 33 MB กับสมอง 2–3 GB ใหม่ทั้งหมดทุกครั้ง และระหว่างที่
/// แอปไม่อยู่ เธอรับสายแทนไม่ได้ (ไม่มี Dart ให้คุย) · เจ้าของกำหนดว่าแอปปิดได้
/// ทางเดียวคือปุ่ม "ออกจากแอป" ของแอปเอง
abstract final class AppLife {
  /// ย่อแอปไปเบื้องหลัง เหมือนกด Home · ทุกอย่างยังอยู่ กลับมาไม่ต้องโหลดใหม่
  static Future<void> moveToBack() async {
    try {
      await kSystemChannel.invokeMethod<bool>('moveToBack');
    } on Object catch (e) {
      debugPrint('แอป: ย่อไปเบื้องหลังไม่ได้ — ${e.runtimeType}');
    }
  }

  /// ปิดแอปจริง (จบโปรเซส) · ผู้เรียกต้องเก็บกวาดก่อน (บันทึกคลิป ปล่อยสมอง)
  static Future<void> exit() async {
    try {
      await kSystemChannel.invokeMethod<bool>('exitApp');
    } on Object catch (e) {
      debugPrint('แอป: ปิดแอปไม่ได้ — ${e.runtimeType}');
    }
  }
}
