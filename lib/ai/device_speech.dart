/// ถอดเสียงในเครื่อง — คู่กับ MindSpeech.kt
///
/// ## 🔴 ทางเดียวที่ไมค์ใช้ได้กับ "สมองในเครื่อง"
///
/// การถอดเสียงทางอื่นทั้งหมดในแอปนี้ส่งไฟล์เสียงออกไปที่บริการภายนอก
/// (ดู [MindState.transcribeChat]) ซึ่งขัดกับสัญญาข้อเดียวที่สมองในเครื่อง
/// ให้ไว้ · ผลคือปุ่มไมค์เคยใช้ไม่ได้เลยกับ**ค่าตั้งต้นของแอป**
///
/// ตัวนี้ใช้ `createOnDeviceSpeechRecognizer` ของแอนดรอยด์ ซึ่งรับประกันว่า
/// เสียงไม่ออกจากเครื่อง · ไม่ใช่ `EXTRA_PREFER_OFFLINE` ที่เป็นแค่คำขอ
/// และตกไปใช้ทางออนไลน์เงียบ ๆ เมื่อเครื่องไม่มีชุดภาษา (ดูเหตุผลเต็มใน .kt)
///
/// ## 🔴 ตัวเดียวทั้งแอป
///
/// `setMethodCallHandler` มีได้ตัวเดียวต่อหนึ่งช่อง · สร้างสองตัวแล้วตัวหลัง
/// จะทับ handler ของตัวแรกเงียบ ๆ แล้วผลการถอดเสียงจะหายไปโดยไม่มี error
/// (บทเรียนเดียวกับที่ CallWatch เจอกับช่อง giggok/system)
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ช่องแยกจาก `giggok/system` โดยตั้งใจ — ช่องนั้นมี CallWatch เป็นเจ้าของ
const kSttChannel = MethodChannel('giggok/stt');

/// สาเหตุที่ถอดเสียงไม่สำเร็จ · ส่งมาเป็น**ชื่อ** ไม่ใช่ข้อความภาษาคน
/// เพราะข้อความต้องแปลสองภาษาและตารางแปลอยู่ฝั่ง Dart ที่เดียว
enum SttFault {
  /// เครื่องนี้ถอดเสียงในเครื่องไม่ได้ (แอนดรอยด์เก่ากว่า 12)
  unavailable,

  /// ยังไม่ได้โหลดชุดภาษาลงเครื่อง — พบบ่อยกว่าเครื่องเก่าเสียอีก
  language,

  /// ไม่ได้ยินคำพูด
  noMatch,
  mic,
  permission,
  busy,
  failed;

  static SttFault parse(Object? v) => switch ('$v') {
        'unavailable' => SttFault.unavailable,
        'language' => SttFault.language,
        'noMatch' => SttFault.noMatch,
        'mic' => SttFault.mic,
        'permission' => SttFault.permission,
        'busy' => SttFault.busy,
        _ => SttFault.failed,
      };
}

class DeviceSpeech {
  DeviceSpeech._(this._ch) {
    _ch.setMethodCallHandler(_onNative);
  }

  /// ตัวเดียวทั้งแอป — ดูเหตุผลหัวไฟล์
  static DeviceSpeech? _only;
  static DeviceSpeech get instance => _only ??= DeviceSpeech._(kSttChannel);

  /// สร้างตัวใหม่ชี้ไปช่องปลอม — สำหรับเทสต์เท่านั้น
  @visibleForTesting
  factory DeviceSpeech.forTest(MethodChannel channel) => DeviceSpeech._(channel);

  final MethodChannel _ch;

  /// เทิร์นที่กำลังฟังอยู่ · null = ไม่ได้ฟัง
  Completer<String?>? _turn;

  /// สาเหตุที่เทิร์นล่าสุดจบแบบไม่ได้ข้อความ
  SttFault? _fault;
  SttFault? get fault => _fault;

  bool get listening => _turn != null;

  /// ระดับเสียง 0..1 · แปลงจากเดซิเบลคร่าว ๆ ที่ระบบส่งมา
  void Function(double level)? onLevel;

  /// ข้อความระหว่างพูด — ให้ผู้ใช้เห็นว่ามันได้ยินอยู่จริง
  void Function(String text)? onPartial;

  bool? _cachedAvailable;

  /// เครื่องนี้ถอดเสียงในเครื่องได้ไหม
  ///
  /// จำคำตอบไว้ — มันไม่เปลี่ยนระหว่างแอปเปิดอยู่ (ยกเว้นผู้ใช้ไปโหลดชุดภาษา
  /// มาระหว่างนั้น ซึ่ง [forget] มีไว้สำหรับกรณีนั้น)
  Future<bool> available() async {
    if (_cachedAvailable != null) return _cachedAvailable!;
    try {
      _cachedAvailable = await _ch.invokeMethod<bool>('available') ?? false;
    } on Object catch (e) {
      debugPrint('stt: ถามความพร้อมไม่ได้ — $e');
      _cachedAvailable = false;
    }
    return _cachedAvailable!;
  }

  /// ลืมคำตอบเดิม — เรียกตอนกลับเข้าแอปหลังผู้ใช้ไปโหลดชุดภาษามา
  void forget() => _cachedAvailable = null;

  /// เริ่มฟัง · คืนข้อความที่ได้ (null = ไม่ได้อะไร ดูสาเหตุที่ [fault])
  Future<String?> listen({required String locale}) {
    final running = _turn;
    if (running != null) return running.future;

    _fault = null;
    final turn = _turn = Completer<String?>();
    unawaited(_ch.invokeMethod<bool>('start', {'locale': locale}).catchError(
      (Object e) {
        debugPrint('stt: เริ่มฟังไม่ได้ — $e');
        _finish(null, SttFault.failed);
        return false;
      },
    ));
    return turn.future;
  }

  /// บอกให้สรุปผลจากที่ได้ยินมาแล้ว — ผู้ใช้กดหยุดเอง
  Future<void> stop() async {
    if (_turn == null) return;
    try {
      await _ch.invokeMethod<bool>('stop');
    } on Object catch (e) {
      debugPrint('stt: สั่งหยุดไม่ได้ — $e');
      _finish(null, SttFault.failed);
    }
  }

  /// ทิ้งรอบนี้ไปเลย ไม่เอาผล
  Future<void> cancel() async {
    if (_turn == null) return;
    try {
      await _ch.invokeMethod<bool>('cancel');
    } on Object {
      // ยกเลิกไม่สำเร็จก็ปิดเทิร์นฝั่งเราเอง ไม่ค้างรอสัญญาณที่อาจไม่มา
    }
    _finish(null, null);
  }

  Future<void> _onNative(MethodCall call) async {
    if (call.method != 'onStt') return;
    final m = (call.arguments as Map?) ?? const {};

    switch ('${m['event']}') {
      case 'level':
        // ระบบส่งมาเป็นเดซิเบลคร่าว ๆ ราว -2..10 ไม่ใช่ 0..1
        final db = (m['rms'] as num?)?.toDouble() ?? 0;
        onLevel?.call(((db + 2) / 12).clamp(0.0, 1.0));
      case 'partial':
        final t = '${m['text'] ?? ''}';
        if (t.isNotEmpty) onPartial?.call(t);
      case 'result':
        final t = '${m['text'] ?? ''}'.trim();
        _finish(t.isEmpty ? null : t, t.isEmpty ? SttFault.noMatch : null);
      case 'error':
        _finish(null, SttFault.parse(m['code']));
      case 'cancelled':
        _finish(null, null);
    }
  }

  void _finish(String? text, SttFault? fault) {
    final turn = _turn;
    _turn = null;
    _fault = fault;
    // 🔴 เช็ค isCompleted เสมอ · ระบบส่ง error ตามหลัง result ได้ในบางเครื่อง
    // เติม future ซ้ำจะโยน StateError ที่ไม่มีใครรับ = จอแดง
    if (turn != null && !turn.isCompleted) turn.complete(text);
  }
}
