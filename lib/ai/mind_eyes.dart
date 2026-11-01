/// ตาของมายด์ — เห็นเจ้าของผ่านกล้องมือถือระหว่างคุยสด และถ่ายรูปให้
///
/// เจ้าของ: "เปิดกล้อง เพื่อถ่ายรูป และให้เธอมีตา คือเห็นเราผ่านกล้องมือถือได้ ขณะคุยกับเรา"
///
/// ## 🔴 กติกาของกล้อง (ตรวจด้วยโค้ด ไม่ใช่ด้วยคำสั่งในบุคลิก)
///
/// - เปิดเมื่อเจ้าของขอเองเท่านั้น · ตัดสินจากคำของเจ้าของในเครื่อง (MindState.openEyes) ไม่ใช่จากโมเดล ·
///   ข้อความในเว็บหรือ SMS ที่บอกให้เปิดกล้องจึงเปิดไม่ได้
/// - เปิดอยู่ = เห็นภาพตัวเองมุมจอพร้อมจุดแดงและบอกว่าภาพไปที่ไหน มีปุ่มปิดทันที (lib/widgets/eyes_overlay.dart)
/// - แอปลงเบื้องหลัง · ปิดไมค์ · มีสาย · ท่อคุยสดหลุด = ปิดเอง · ไม่เปิดคืนเอง
/// - ภาพไม่ลงแชท ไม่ลงไฟล์ · ไฟล์ชั่วคราวของปลั๊กอินลบทันทีหลังอ่าน · ไปที่ OpenAI ด้วยคีย์ของเจ้าของ
///   ทางเดียวกับเสียงคุยสด · ถ่ายรูปเก็บเฉพาะตอนเจ้าของสั่งถ่าย
/// - ส่งเฉพาะตอนเจ้าของเริ่มพูด ไม่เกินทุก [minGap] · ไม่ใช่วิดีโอ · ไม่ส่งตอนเงียบ
library;

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// กล้องจริงหรือตัวปลอมในเทสต์
abstract class EyeCamera {
  Future<void> open({required bool front});
  Future<Uint8List> snap();
  Future<void> close();
  Widget preview();
}

class PluginEyeCamera implements EyeCamera {
  CameraController? _c;

  @override
  Future<void> open({required bool front}) async {
    final all = await availableCameras();
    final want = front ? CameraLensDirection.front : CameraLensDirection.back;
    final lens = all.firstWhere((c) => c.lensDirection == want, orElse: () => all.first);
    // ไม่เอาเสียง · ไมค์เป็นของคุยสด
    final c = CameraController(lens, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    try {
      await c.initialize();
    } on Object {
      await c.dispose();
      rethrow;
    }
    _c = c;
  }

  @override
  Future<Uint8List> snap() async {
    final c = _c;
    if (c == null) throw StateError('closed');
    final shot = await c.takePicture();
    try {
      return await shot.readAsBytes();
    } finally {
      // ปลั๊กอินเขียนลงแคช · ภาพเจ้าของต้องไม่ค้างในเครื่องโดยไม่มีใครรู้
      unawaited(File(shot.path).delete().then<void>((_) {}, onError: (Object _) {}));
    }
  }

  @override
  Future<void> close() async {
    final c = _c;
    _c = null;
    await c?.dispose();
  }

  @override
  Widget preview() {
    final c = _c;
    return c == null ? const SizedBox.shrink() : CameraPreview(c);
  }
}

class MindEyes extends ChangeNotifier {
  MindEyes({EyeCamera? camera}) : _cam = camera ?? PluginEyeCamera();

  final EyeCamera _cam;

  /// ส่งภาพถี่สุดเท่านี้ · ภาพกินเงินกว่าเสียงมาก และคุยกันไม่ได้ต้องการวิดีโอ
  static const minGap = Duration(seconds: 4);

  bool _on = false;
  bool _opening = false;
  bool _front = true;
  int _seq = 0;

  bool get on => _on;
  bool get opening => _opening;
  bool get front => _front;

  /// แสดงจุดกล้องตั้งแต่เริ่มเปิด ไม่ใช่หลังเปิดเสร็จ
  bool get showing => _on || _opening;

  /// false = เปิดไม่ได้ (ไม่มีกล้อง · แอปอื่นถืออยู่ · ถูกปิดระหว่างเปิด)
  Future<bool> turnOn({bool front = true}) async {
    if (_on && _front == front) return true;
    if (showing) unawaited(turnOff());
    final seq = ++_seq;
    _opening = true;
    _front = front;
    notifyListeners();
    try {
      await _inLane(() async {
        if (seq == _seq) await _cam.open(front: front);
      });
    } on Object catch (e) {
      debugPrint('กล้อง: เปิดไม่ได้ — ${e.runtimeType}');
      if (seq == _seq) {
        _opening = false;
        notifyListeners();
      }
      return false;
    }
    if (seq != _seq) return false; // เจ้าของปิดระหว่างรอ · turnOff เข้าคิวปิดไว้แล้ว
    _opening = false;
    _on = true;
    notifyListeners();
    return true;
  }

  /// สัญญาณหายทันที · ตัวกล้องปิดตามคิว (กำลังเปิดอยู่ก็ปิดหลังเปิดเสร็จ ไม่ค้าง)
  Future<void> turnOff() async {
    final was = showing;
    _seq++;
    _opening = false;
    _on = false;
    if (!was) return;
    notifyListeners();
    try {
      await _inLane(_cam.close);
    } on Object catch (e) {
      debugPrint('กล้อง: ปิดไม่สำเร็จ — ${e.runtimeType}');
    }
  }

  /// ภาพตอนนี้ · null = ปิดอยู่ / ถูกปิดระหว่างถ่าย / ถ่ายไม่ได้
  Future<Uint8List?> look() async {
    if (!_on) return null;
    final seq = _seq;
    try {
      return await _inLane(() async {
        if (seq != _seq) return null;
        final jpeg = await _cam.snap();
        // 🔴 ปิดกล้องระหว่างถ่าย = เจ้าของไม่อยากให้เห็นแล้ว · ภาพนี้ห้ามออกไป
        return seq == _seq ? jpeg : null;
      });
    } on Object catch (e) {
      debugPrint('กล้อง: ถ่ายไม่ได้ — ${e.runtimeType}');
      return null;
    }
  }

  /// กล้องจริงรับคำสั่งทีละอย่าง · เปิด-ปิด-เปิดเร็ว ๆ ซ้อนกันจะทิ้งตัวควบคุมค้างและกล้องไม่ถูกปล่อย
  Future<void> _lane = Future<void>.value();

  Future<T> _inLane<T>(Future<T> Function() job) {
    final run = _lane.then((_) => job());
    _lane = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Widget preview() => _on ? _cam.preview() : const SizedBox.shrink();
}
