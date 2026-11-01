import 'package:flutter/foundation.dart';

import '../system/permissions.dart';

/// แป้นโทรของ GigGok (DialerActivity) — คู่กับ MainActivity.kt (`openDialer`)
///
/// แป้นโทรเป็นจอเนทีฟคนละงานกับหน้าแอป (taskAffinity แยก) · แท็บ "โทรศัพท์"
/// ในแถบล่างจึงไม่มีหน้าใน IndexedStack แค่สั่งเปิดจอนั้น · Back จากแป้นโทร
/// กลับมาหน้าแอปที่ค้างไว้เอง
abstract final class PhoneDialer {
  /// true = เปิดแล้ว · false = ระบบไม่ยอมเปิด หรือไม่มีจอ (เธอถูกปลุกมาคุยในสายเบื้องหลัง)
  static Future<bool> open() async {
    try {
      return await kSystemChannel.invokeMethod<bool>('openDialer') ?? false;
    } on Object catch (e) {
      debugPrint('แป้นโทร: เปิดไม่ได้ — ${e.runtimeType}');
      return false;
    }
  }
}
