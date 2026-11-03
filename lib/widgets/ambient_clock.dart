import 'dart:async';

import 'package:flutter/widgets.dart';

/// นาฬิกาของแอนิเมชันประดับที่วนไม่รู้จบ (ก้อนแสงลอย วงแหวนรอบตัวเธอ)
///
/// 🔴 ทำไมไม่ใช้ AnimationController.repeat()
///
/// ticker ขอเฟรมใหม่ทุก vsync ตลอดชีพหน้าจอ · ทุกเฟรมคือ Flutter ประกอบภาพใหม่
/// ทั้งจอ รวมเบลอแผงกระจก (BackdropFilter) ทับเวทีใหม่ทุกครั้ง · ของที่ขยับช้า
/// ขนาดนี้ตาแยก 15–30 เฟรมกับ 60 ไม่ออก แต่ GPU ทำงานต่างกันหลายเท่า
///
/// Timer ขอเฟรมเฉพาะตอนค่าเปลี่ยน · หยุดเองตอนแอปไม่อยู่บนจอ ([AppLifecycleState]
/// paused/hidden) เพราะ Timer ไม่หยุดตามแอปแบบ ticker · จอลอย (inactive) ยังเดิน
class AmbientClock extends ChangeNotifier with WidgetsBindingObserver {
  AmbientClock({required this.fps}) {
    WidgetsBinding.instance.addObserver(this);
  }

  /// กี่ครั้งต่อวินาที
  final double fps;

  final _watch = Stopwatch();
  Timer? _timer;
  bool _wanted = false;
  bool _onScreen = true;
  bool _disposed = false;

  /// วินาทีที่เดินมาแล้ว (ไม่นับช่วงที่หยุด)
  double get seconds => _watch.elapsedMicroseconds / 1e6;

  bool get running => _timer != null;

  /// เดินหรือหยุด — เช่นหยุดตอนแท็บนี้ไม่ได้อยู่บนจอ
  void setRunning(bool on) {
    _wanted = on;
    _apply();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _onScreen = state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached;
    _apply();
  }

  void _apply() {
    if (_disposed) return;
    final go = _wanted && _onScreen;
    if (go == running) return;
    if (go) {
      _watch.start();
      _timer = Timer.periodic(
          Duration(microseconds: (1e6 / fps).round()), (_) => notifyListeners());
    } else {
      _watch.stop();
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
