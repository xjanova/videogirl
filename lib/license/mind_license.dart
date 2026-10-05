/// ไลเซนส์ของเครื่องนี้จาก xman studio — **ฟรี ออกให้เอง**
///
/// ## ใช้ทำอะไร
///
/// ไลเซนส์เป็นตั๋วผ่านของสองอย่างบนหลังบ้าน: สมองแบบพร็อกซี
/// (`/api/ai/v1/chat/completions`) และร้านชุดตัวมายด์ (`/api/packs*`)
/// · แอปตัวหลัก คุยด้วยสมองในเครื่อง **ใช้ได้โดยไม่ต้องมีไลเซนส์เลย**
///
/// ## ทำไมออกให้เอง
///
/// เจ้าของเลือกแบบ LocalVPN (2026-10-05): ทุกเครื่องได้ FREE key อัตโนมัติจาก
/// `POST /api/v1/product/giggok/check-machine` · ผู้ใช้ไม่ต้องกรอกอะไร
/// และลงแอปใหม่บนเครื่องเดิมได้คีย์เดิมกลับมา (หลังบ้านจับคู่ด้วยรหัสเครื่อง)
///
/// ## 🔴 รหัสเครื่องที่ส่งไปเป็นแฮชเสมอ
///
/// ฝั่ง Kotlin (`MainActivity.deviceIds`) แฮช Widevine id / ANDROID_ID ด้วย
/// SHA-256 ผสมชื่อแอปก่อนส่งข้ามสะพานมา · ค่าดิบไม่เคยถึงฝั่ง Dart และไม่เคย
/// ออกนอกเครื่อง · ไม่มีเนื้อหาการคุยหรือข้อมูลส่วนตัวอื่นในคำขอนี้
///
/// ## ซื้อชุดบนเว็บแล้วไม่เห็นในแอป
///
/// ความเป็นเจ้าของชุดผูกกับ**บัญชีเว็บ** ส่วน FREE key ผูกกับ**เครื่อง** ·
/// ผู้ใช้ต้องผูกสองอย่างเข้าหากันครั้งเดียวที่ `{base}/giggok/link`
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../system/permissions.dart';

/// สินค้าในระบบของ xman studio
const kLicenseProductSlug = 'giggok';

/// รหัสเครื่องที่แฮชแล้ว
typedef DeviceIds = ({String machine, String? drm, String? android});

class MindLicense {
  MindLicense({
    http.Client? httpClient,
    Future<Map<Object?, Object?>?> Function()? readIds,
  })  : _http = httpClient ?? http.Client(),
        _readIds = readIds ?? _nativeIds;

  final http.Client _http;
  final Future<Map<Object?, Object?>?> Function() _readIds;

  static Future<Map<Object?, Object?>?> _nativeIds() =>
      kSystemChannel.invokeMethod<Map<Object?, Object?>>('deviceIds');

  /// รหัสเครื่อง · null = อ่านไม่ได้เลยสักตัว (ขอไลเซนส์ไม่ได้)
  Future<DeviceIds?> deviceIds() async {
    try {
      final m = await _readIds();
      String? hex(Object? v) {
        final s = '${v ?? ''}'.trim().toLowerCase();
        return RegExp(r'^[0-9a-f]{64}$').hasMatch(s) ? s : null;
      }

      final drm = hex(m?['drm']);
      final android = hex(m?['android']);
      // Widevine อยู่รอดการถอนแอป ANDROID_ID ไม่รอดถ้าเปลี่ยนกุญแจเซ็น
      // เลือกตัวที่ทนกว่าเป็นตัวหลัก
      final machine = drm ?? android;
      if (machine == null) return null;
      return (machine: machine, drm: drm, android: android);
    } on Object catch (e) {
      debugPrint('license: อ่านรหัสเครื่องไม่ได้ — ${e.runtimeType}');
      return null;
    }
  }

  /// ขอไลเซนส์ของเครื่องนี้ · หลังบ้านสร้าง FREE ให้ถ้ายังไม่มี
  ///
  /// คืนคีย์ (ตัวพิมพ์ใหญ่) หรือ null ถ้าขอไม่ได้ — **เงียบเสมอ** เพราะแอปใช้
  /// ต่อได้ปกติโดยไม่มีไลเซนส์ จะลองใหม่เองตอนเปิดแอปรอบหน้า
  Future<({String key, String type})?> checkMachine(String baseUrl) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return null;
    final ids = await deviceIds();
    if (ids == null) return null;
    try {
      final res = await _http
          .post(
            Uri.parse('$base/api/v1/product/$kLicenseProductSlug/check-machine'),
            headers: const {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            },
            body: utf8.encode(jsonEncode({
              'machine_id': ids.machine,
              'drm_id': ?ids.drm,
              'android_id': ?ids.android,
            })),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        debugPrint('license: หลังบ้านตอบ ${res.statusCode}');
        return null;
      }
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is! Map || j['has_license'] != true) return null;
      final data = j['data'];
      final key = data is Map ? '${data['license_key'] ?? ''}'.trim() : '';
      if (key.isEmpty) return null;
      final type = data is Map ? '${data['license_type'] ?? ''}'.trim().toLowerCase() : '';
      return (key: key.toUpperCase(), type: type);
    } on Object catch (e) {
      debugPrint('license: ขอไลเซนส์ไม่สำเร็จ — ${e.runtimeType}');
      return null;
    }
  }

  /// หน้าเว็บที่ผูกไลเซนส์ของเครื่องนี้เข้ากับบัญชี (ต้องล็อกอินบนเว็บ)
  ///
  /// 🔴 ไม่ใส่คีย์ลงใน URL · ลิงก์ถูกเก็บในประวัติเบราว์เซอร์และ log ของเซิร์ฟเวอร์
  /// ผู้ใช้คัดลอกคีย์ไปวางเองในฟอร์มที่ส่งแบบ POST
  static Uri linkPage(String baseUrl) => Uri.parse(
      '${baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/$kLicenseProductSlug/link');

  void close() => _http.close();
}
