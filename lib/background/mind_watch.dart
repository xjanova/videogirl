import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mind_background.dart';

/// รีโมตของงานเบื้องหลัง ฝั่งที่ผู้ใช้เห็น
///
/// 🔴 **ตัวนี้ไม่ได้รู้เองว่าบริการยังไม่ตาย** — มันอ่าน "รอยเท้า" ที่ isolate
/// เบื้องหลังเขียนทิ้งไว้ใน SharedPreferences เท่านั้น · บริการเบื้องหลังบน
/// Android ตายเงียบเป็นเรื่องปกติและไม่มี callback มาบอก การถามว่า
/// `isRunning()` จึงตอบได้แค่ "ตอนนี้ยังอยู่ไหม" ไม่ได้ตอบว่า "ทำงานจริงไหม"
/// เวลาตื่นครั้งล่าสุดคือหลักฐานเดียวที่แยกสองอย่างนี้ออกจากกัน
class MindWatch extends ChangeNotifier {
  MindWatch({FlutterBackgroundService? service})
      : _service = service ?? FlutterBackgroundService();

  final FlutterBackgroundService _service;
  static const _ch = MethodChannel('giggok/system');

  bool _on = false;
  bool get on => _on;

  bool _busy = false;
  bool get busy => _busy;

  bool _batteryExempt = false;
  bool get batteryExempt => _batteryExempt;

  DateTime? _lastBeat;
  DateTime? get lastBeat => _lastBeat;

  int _beats = 0;
  int get beats => _beats;

  /// รุ่นใหม่ที่เธอเจอตอนอยู่เบื้องหลัง — null ถ้าไม่เจอ
  String? _found;
  String? get found => _found;

  StreamSubscription<Map<String, dynamic>?>? _beatSub;

  /// อ่านสถานะทั้งหมดใหม่ · เรียกตอนเปิดหน้าตั้งค่า และหลังกลับจากหน้าตั้งค่าระบบ
  Future<void> refresh() async {
    _on = await _service.isRunning();
    _batteryExempt = await _ask('batteryExempt');

    final prefs = await SharedPreferences.getInstance();
    // ค่าถูกเขียนโดย isolate อีกตัว ไม่ reload ก่อนจะได้ของเก่าที่ cache ไว้
    await prefs.reload();
    final at = prefs.getInt(kPrefLastBeat);
    _lastBeat = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
    _beats = prefs.getInt(kPrefBeats) ?? 0;
    _found = prefs.getString(kPrefBgUpdate);

    // ฟังจังหวะสด ๆ ระหว่างที่หน้าตั้งค่าเปิดอยู่ จะได้เห็นเลขขยับจริง
    // ไม่ต้องปิดเปิดหน้าเพื่อพิสูจน์ว่ามันทำงาน
    _beatSub ??= _service.on('beat').listen((d) {
      if (d == null) return;
      final at = d['at'];
      if (at is int) _lastBeat = DateTime.fromMillisecondsSinceEpoch(at);
      final n = d['beats'];
      if (n is int) _beats = n;
      _found = d['found'] as String?;
      notifyListeners();
    });

    notifyListeners();
  }

  /// เปิดสวิตช์ให้เธอเฝ้างาน
  ///
  /// ขอสิทธิ์แจ้งเตือน**ก่อน**สตาร์ต — บริการที่รันอยู่แต่ไม่มีการแจ้งเตือน
  /// ให้เห็น คือบริการที่ผู้ใช้เข้าใจว่าไม่ทำงาน แล้วจะไปกดปิดทิ้ง
  Future<void> start() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await _ask('requestNotify');
      await _service.startService();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kPrefWatchEnabled, true);
    } catch (e) {
      debugPrint('watch: เปิดไม่สำเร็จ — $e');
    } finally {
      _busy = false;
      await refresh();
    }
  }

  Future<void> stop() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      _service.invoke('stop');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kPrefWatchEnabled, false);
    } catch (e) {
      debugPrint('watch: ปิดไม่สำเร็จ — $e');
    } finally {
      _busy = false;
      // ให้ระบบเก็บบริการก่อนค่อยถามว่ายังรันอยู่ไหม ไม่งั้นได้คำตอบเก่า
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await refresh();
    }
  }

  /// พาไปกล่องขอยกเว้นการประหยัดแบตของระบบ
  ///
  /// ผลลัพธ์รู้ไม่ได้ทันที เพราะผู้ใช้ออกไปหน้าอื่นแล้วค่อยกลับมา
  /// ผู้เรียกต้อง [refresh] อีกทีตอนแอปกลับมา foreground
  Future<void> askBatteryExempt() async {
    await _ask('requestBatteryExempt');
  }

  Future<bool> _ask(String method) async {
    try {
      return await _ch.invokeMethod<bool>(method) ?? false;
    } catch (e) {
      // ไม่มีฝั่ง native (เทสต์ / เดสก์ท็อป) — ถือว่ายังไม่ได้ ไม่ใช่ได้แล้ว
      debugPrint('watch: ถาม $method ไม่ได้ — $e');
      return false;
    }
  }

  @override
  void dispose() {
    unawaited(_beatSub?.cancel());
    super.dispose();
  }
}
