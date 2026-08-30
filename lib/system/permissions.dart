/// สิทธิ์ทั้งหมดที่แอปต้องใช้ รวมไว้ที่เดียว
///
/// **ทำไมต้องรวม:** ก่อนหน้านี้แต่ละสิทธิ์ถูกขอตอนที่จะใช้จริง ซึ่งฟังดูสุภาพ
/// แต่ผลคือเจ้าของค้นพบว่า "ยังไม่ได้ให้สิทธิ์" ตอนที่กำลังจะใช้งานพอดี
/// และบางตัวแย่กว่านั้น —
///
/// 🔴 สิทธิ์ติดตั้งแอปที่ไม่รู้จัก ถ้าไม่ได้ให้ไว้ก่อน auto-update จะโหลด APK
/// **จนจบทั้งไฟล์** แล้วค่อยล้มตรงขั้นเปิดตัวติดตั้ง · เสียทั้งเน็ตทั้งเวลา
/// แล้วข้อความที่ได้ก็ไม่ได้บอกว่าต้องไปกดอะไรที่ไหน
///
/// การ์ดเดียวที่บอกครบว่าต้องใช้อะไรบ้าง เพื่ออะไร และยังขาดตัวไหน
/// แก้ปัญหานี้ทั้งกอง — และทำให้เห็นด้วยว่าแอปขออะไรไปแล้วบ้าง
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ช่องคุยกับฝั่ง Android — คู่กับ MainActivity.kt
///
/// ชื่อ `system` ไม่ใช่ `camera` เพราะไม่ได้มีแค่กล้องแล้ว
const MethodChannel kSystemChannel = MethodChannel('giggok/system');

/// สิทธิ์หนึ่งตัวที่แอปต้องใช้
enum MindPermission {
  /// กล้องหน้า — โหมดหุ่นเชิด
  camera(check: 'status', ask: 'request', inApp: true),

  /// ไมค์ — พูดกับเธอ และอัดเสียงตอนโคลนเสียง
  mic(check: 'micGranted', ask: 'requestMic', inApp: true),

  /// การแจ้งเตือน — บริการเบื้องหลังต้องมี ไม่งั้น Android ไม่ให้รัน
  notify(check: 'notifyGranted', ask: 'requestNotify', inApp: true),

  /// ยกเว้นการประหยัดแบต — บริการเบื้องหลังถึงจะไม่โดนหรี่หรือฆ่า
  battery(check: 'batteryExempt', ask: 'requestBatteryExempt', inApp: false),

  /// ปฏิทินของเครื่อง — เธอเป็นเลขา ต้องรู้ตารางจริงถึงจะช่วยอะไรได้
  ///
  /// อ่านอย่างเดียว ไม่ขอสิทธิ์เขียน · สิทธิ์ที่ขอไปโดยไม่ได้ใช้
  /// คือสิ่งที่ผู้ใช้จำได้ตอนกดปฏิเสธ
  calendar(check: 'calendarGranted', ask: 'requestCalendar', inApp: true),

  /// ติดตั้งแอปที่ไม่รู้จัก — auto-update ถึงจะติดตั้งได้จริง
  install(check: 'canInstall', ask: 'requestInstall', inApp: false);

  const MindPermission({
    required this.check,
    required this.ask,
    required this.inApp,
  });

  final String check;
  final String ask;

  /// ขอผ่านกล่องในแอปได้ไหม
  ///
  /// `false` = ต้องพาไปหน้าตั้งค่าของระบบ ซึ่งแปลว่า**รู้ผลทันทีไม่ได้**
  /// ผู้ใช้ออกไปแล้วค่อยกลับมา ผู้เรียกต้อง [MindPermissions.refresh] อีกที
  final bool inApp;
}

class MindPermissions extends ChangeNotifier {
  MindPermissions({MethodChannel? channel})
      : _ch = channel ?? kSystemChannel;

  final MethodChannel _ch;

  final Map<MindPermission, bool> _granted = {
    for (final p in MindPermission.values) p: false,
  };

  bool of(MindPermission p) => _granted[p] ?? false;

  /// ให้ครบทุกตัวแล้วหรือยัง
  bool get allGranted => _granted.values.every((v) => v);

  int get missing => _granted.values.where((v) => !v).length;

  /// ตัวที่ผู้ใช้ปฏิเสธถาวรจนกล่องขอไม่ขึ้นอีกแล้ว
  final Set<MindPermission> _blocked = {};
  bool isBlocked(MindPermission p) => _blocked.contains(p);

  bool _busy = false;
  bool get busy => _busy;

  /// อ่านสถานะทุกตัวใหม่
  ///
  /// เรียกตอนเปิดหน้าตั้งค่า **และตอนแอปกลับมา foreground** เพราะสิทธิ์ที่ต้อง
  /// ไปกดในหน้าตั้งค่าของระบบ เปลี่ยนค่าตอนที่แอปเราไม่ได้อยู่หน้าจอ
  Future<void> refresh() async {
    for (final p in MindPermission.values) {
      _granted[p] = await _boolCall(p.check);
      // ให้แล้วก็ไม่ใช่ปฏิเสธถาวรอีกต่อไป — คนไปเปิดในตั้งค่ามาแล้ว
      if (_granted[p] == true) _blocked.remove(p);
    }
    notifyListeners();
  }

  /// ขอสิทธิ์หนึ่งตัว
  ///
  /// ตัวที่ [MindPermission.inApp] เป็น false จะพาไปหน้าตั้งค่าแล้วคืนค่าเดิม
  /// ทันที — ยังไม่รู้ผล ต้องรอ [refresh] ตอนกลับมา
  Future<void> request(MindPermission p) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      final answer = await _call(p.ask);
      if (p.inApp) {
        _granted[p] = answer == 'granted' || answer == 'true';
        if (answer == 'blocked') {
          _blocked.add(p);
        } else {
          _blocked.remove(p);
        }
      }
    } finally {
      _busy = false;
      await refresh();
    }
  }

  /// ขอทุกตัวที่ยังขาด เรียงทีละตัว
  ///
  /// หยุดที่ตัวแรกที่ต้องออกไปหน้าตั้งค่าของระบบ — ยิงทุกตัวรวดเดียวจะทำให้
  /// หน้าตั้งค่าซ้อนกันหลายชั้น แล้วผู้ใช้กดย้อนกลับหลงทาง
  Future<void> requestAllMissing() async {
    for (final p in MindPermission.values) {
      if (of(p) || isBlocked(p)) continue;
      await request(p);
      if (!p.inApp) return;
    }
  }

  Future<bool> _boolCall(String method) async {
    final v = await _call(method);
    return v == 'true' || v == 'granted';
  }

  /// ฝั่ง native ตอบมาสองแบบ — bool สำหรับตัวที่ถามสถานะ
  /// และ String (granted/denied/blocked) สำหรับตัวที่ขอ · รวบเป็นสตริงเดียว
  /// เพื่อไม่ต้องมีสองทางแยกที่ผู้เรียกต้องจำว่าตัวไหนคืนอะไร
  Future<String> _call(String method) async {
    try {
      final v = await _ch.invokeMethod<Object?>(method);
      if (v is bool) return v ? 'true' : 'false';
      return '$v';
    } catch (e) {
      // ไม่มีฝั่ง native (เทสต์ / เดสก์ท็อป) — ถือว่ายังไม่ได้ ไม่ใช่ได้แล้ว
      // เดาว่า "ได้" จะทำให้ UI บอกว่าครบทั้งที่จริง ๆ ยังไม่ได้ขออะไรเลย
      debugPrint('perm: ถาม $method ไม่ได้ — $e');
      return 'false';
    }
  }
}
