import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../avatar/avatar_view.dart' show MindMocapShot;
import '../avatar/stage_bridge.dart';
import '../i18n/strings.dart';
import '../i18n/strings_studio.dart';
import '../state/mind_state.dart';
import '../system/permissions.dart';
import 'studio_backdrop.dart';

/// ผลของการย้ายคลิปเข้าแกลเลอรี
class StudioSave {
  const StudioSave({this.path, this.needsPermission = false});

  /// ที่อยู่ที่คนอ่านเข้าใจ (Movies/GigGok/…) · null = ไม่สำเร็จ
  final String? path;

  /// Android 9 ลงมาที่ยังไม่ได้สิทธิ์เขียนไฟล์
  final bool needsPermission;

  bool get ok => path != null;
}

/// สิ่งที่สตูดิโอต้องขอจากเครื่อง — คู่กับ MindStudio.kt
///
/// แยกเป็น interface เพื่อให้เทสต์ได้โดยไม่มี Android
abstract interface class StudioPlatform {
  Future<void> keepScreenOn(bool on);
  Future<bool> enterPip(int w, int h);

  /// ออกจากแอปแล้วเข้าจอลอยเอง · [w]/[h] = สัดส่วนจอลอย
  Future<void> autoPip(bool on, int w, int h);

  Future<StudioSave> saveVideo(String path, String name, String mime);

  /// ซ่อนแถบสถานะและแถบนำทางของระบบ — ไม่งั้นติดไปในภาพที่แชร์
  Future<void> immersive(bool on);

  set onPip(void Function(bool inPip)? listener);
}

class MethodChannelStudio implements StudioPlatform {
  MethodChannelStudio([MethodChannel? channel])
      : _ch = channel ?? const MethodChannel('giggok/studio');

  final MethodChannel _ch;

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null; // ไม่ใช่ Android
    } on PlatformException catch (e) {
      debugPrint('studio: $method ไม่สำเร็จ — ${e.code}');
      return null;
    }
  }

  @override
  Future<void> keepScreenOn(bool on) => _invoke<bool>('keepScreenOn', {'on': on});

  @override
  Future<bool> enterPip(int w, int h) async =>
      await _invoke<bool>('enterPip', {'w': w, 'h': h}) ?? false;

  @override
  Future<void> autoPip(bool on, int w, int h) =>
      _invoke<bool>('autoPip', {'on': on, 'w': w, 'h': h});

  @override
  Future<StudioSave> saveVideo(String path, String name, String mime) async {
    final r = await _invoke<Map<Object?, Object?>>(
        'saveVideo', {'path': path, 'name': name, 'mime': mime});
    final p = r?['path'];
    if (p is String && p.isNotEmpty) return StudioSave(path: p);
    return StudioSave(needsPermission: r?['error'] == 'permission');
  }

  @override
  Future<void> immersive(bool on) async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
          on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
    } on Object catch (e) {
      debugPrint('studio: สลับโหมดเต็มจอไม่ได้ — $e');
    }
  }

  @override
  set onPip(void Function(bool inPip)? listener) {
    _ch.setMethodCallHandler(listener == null
        ? null
        : (call) async {
            if (call.method == 'onPip') {
              final args = call.arguments;
              listener(args is Map && args['on'] == true);
            }
            return null;
          });
  }
}

enum StudioRec { idle, starting, recording, saving }

/// สตูดิโอ — เวทีเต็มจอสำหรับวิดีโอคอล (ผ่านแชร์หน้าจอ) ไลฟ์ (ฉากเขียว) และอัดคลิป
///
/// ## 🔴 ทำไมไม่ใช่กล้องเสมือน
///
/// Android ไม่ให้แอปทั่วไปประกาศตัวเป็นกล้อง (ต้อง root หรือเป็นแอประบบ)
/// แอปวิดีโอคอลจึงเลือกเธอเป็นกล้องไม่ได้ · ทางที่ทำได้จริงกับทุกแอปคือ
/// แชร์หน้าจอ — สตูดิโอจึงทำให้ทั้งจอเป็นเธอล้วน ๆ ไม่มีปุ่มติดไปในภาพ
///
/// ## ถือแค่สถานะตอนรัน
///
/// ค่าที่เจ้าของเลือก (ฉากหลัง ไมค์ ระยะภาพ) อยู่ใน [MindState] เหมือนค่าตั้ง
/// อื่น ๆ · ที่นี่คือ เปิดอยู่ไหม อยู่ในจอลอยไหม กำลังอัดไหม
class MindStudio extends ChangeNotifier
    with WidgetsBindingObserver
    implements MindRecordingSink {
  MindStudio({
    required StudioStage stage,
    required MindState state,
    required MindPermissions permissions,
    StudioPlatform? platform,
    Future<Directory> Function()? tempDir,
    DateTime Function()? clock,
    this.doneTimeout = const Duration(seconds: 12),
    this.maxLength = const Duration(minutes: 30),
  })  : _stage = stage,
        _state = state,
        _perms = permissions,
        _platform = platform ?? MethodChannelStudio(),
        _tempDir = tempDir ?? getTemporaryDirectory,
        _clock = clock ?? DateTime.now {
    _platform.onPip = _onPip;
    WidgetsBinding.instance.addObserver(this);
  }

  final StudioStage _stage;
  final MindState _state;
  final MindPermissions _perms;
  final StudioPlatform _platform;
  final Future<Directory> Function() _tempDir;
  final DateTime Function() _clock;

  /// รอก้อนสุดท้ายจากเวทีนานเท่านี้ · เวทีที่โหลดใหม่กลางคันจะไม่มีวันตอบ
  final Duration doneTimeout;

  /// อัดได้ยาวสุดต่อคลิป · คลิปยาวกว่านี้ใหญ่จนแชร์ต่อไม่ได้อยู่ดี
  final Duration maxLength;

  S get _s => _state.s;
  bool _disposed = false;

  // ── เปิด/ปิด ──────────────────────────────────────────

  bool _active = false;
  bool get active => _active;
  bool _leaving = false;

  bool _inPip = false;

  /// อยู่ในจอลอย — เหลือแต่ตัวเธอ ไม่มีปุ่มใด ๆ
  bool get inPip => _inPip;

  /// เข้าสตูดิโอ · false = เวทียังไม่พร้อม (ยังไม่มีตัวเธอให้ถ่าย)
  Future<bool> enter() async {
    if (_active) return true;
    if (!_stage.ready) {
      _say(_s.studioNoAvatar);
      return false;
    }
    _active = true;
    _notify();
    unawaited(_sweepLeftovers());
    await _stage.syncMocapShot(_state.mocapShot);
    await _stage.setStudio(true);
    await _stage.setBackdrop(StudioBackdrops.toStage(_state.studioBackdrop));
    final (w, h) = _aspect();
    await _platform.keepScreenOn(true);
    await _platform.autoPip(true, w, h);
    await _platform.immersive(true);
    return true;
  }

  /// ออกจากสตูดิโอ · กำลังอัดอยู่ = หยุดแล้วบันทึกให้ก่อนเสมอ ไม่ทิ้ง
  Future<void> exit() async {
    if (!_active || _leaving) return;
    _leaving = true;
    try {
      if (_rec != StudioRec.idle) await stopRecording();
      _active = false;
      _inPip = false;
      _notify();
      await _stage.setStudio(false);
      await _stage.setBackdrop(null);
      await _platform.autoPip(false, 0, 0);
      await _platform.keepScreenOn(false);
      await _platform.immersive(false);
    } finally {
      _leaving = false;
    }
  }

  // ── ค่าที่เจ้าของเลือก ──────────────────────────────────

  Future<void> setBackdrop(String v) async {
    _state.setStudioBackdrop(v);
    if (_active) {
      await _stage.setBackdrop(StudioBackdrops.toStage(_state.studioBackdrop));
    }
    _notify();
  }

  Future<void> setShot(MindMocapShot s) async {
    _state.setMocapShot(s);
    await _stage.syncMocapShot(s);
    if (_active) {
      final (w, h) = _aspect();
      await _platform.autoPip(true, w, h);
    }
    _notify();
  }

  void setMic(bool v) {
    _state.setStudioMic(v);
    _notify();
  }

  /// สัดส่วนจอลอยตามระยะภาพ · เต็มตัวต้องสูง ไม่งั้นหัวกับเท้าโดนตัด
  (int, int) _aspect() =>
      _state.mocapShot == MindMocapShot.full ? (9, 16) : (3, 4);

  // ── จอลอย ──────────────────────────────────────────────

  Future<bool> enterPip() async {
    if (!_active) return false;
    final (w, h) = _aspect();
    final ok = await _platform.enterPip(w, h);
    if (!ok) _say(_s.studioPipUnsupported);
    return ok;
  }

  void _onPip(bool on) {
    if (_inPip == on) return;
    _inPip = on;
    _notify();
  }

  // ── ข้อความถึงผู้ใช้ ────────────────────────────────────

  String? _notice;

  /// ข้อความล่าสุดที่ต้องบอกผู้ใช้ — คู่กับ [noticeSeq]
  String? get notice => _notice;

  int _noticeSeq = 0;

  /// ขยับทุกครั้งที่มีข้อความใหม่ · ข้อความเดิมซ้ำก็ยังต้องขึ้นใหม่
  int get noticeSeq => _noticeSeq;

  void _say(String? text) {
    if (text == null || text.isEmpty) return;
    _notice = text;
    _noticeSeq++;
    _notify();
  }

  // ── อัดคลิป ────────────────────────────────────────────

  StudioRec _rec = StudioRec.idle;
  StudioRec get rec => _rec;

  DateTime? _recSince;
  Duration get recElapsed =>
      _recSince == null ? Duration.zero : _clock().difference(_recSince!);

  /// ที่อยู่ของคลิปล่าสุดที่บันทึกสำเร็จ
  String? lastSaved;

  Timer? _tick;
  IOSink? _sink;
  File? _part;
  int _nextSeq = 0;
  int _bytes = 0;
  bool _gap = false;
  String _mime = '';
  bool _stopAfterStart = false;

  /// เหตุที่หยุดเอง (ครบเวลา / แอปพับลง) — บอกพร้อมผลการบันทึก
  String? _stopReason;

  Completer<String>? _done;

  /// เวทีบอกว่าจบเองก่อนที่เราจะสั่ง (อัดพังกลางทาง)
  String? _earlyDone;

  Future<void>? _stopping;

  Future<void> startRecording() async {
    if (!_active || _rec != StudioRec.idle) return;
    _rec = StudioRec.starting;
    _stopAfterStart = false;
    _stopReason = null;
    _notify();

    var mic = _state.studioMic;
    String? micNote;
    if (mic && !_perms.of(MindPermission.mic)) {
      await _perms.request(MindPermission.mic);
      mic = _perms.of(MindPermission.mic);
      if (!mic) micNote = _s.studioMicDenied;
    }

    try {
      final dir = await _tempDir();
      final part = File('${dir.path}${Platform.pathSeparator}'
          'studio_${_clock().microsecondsSinceEpoch}.part');
      _part = part;
      _sink = part.openWrite();
    } on Object catch (e) {
      debugPrint('studio: เปิดไฟล์ชั่วคราวไม่ได้ — $e');
      await _discard();
      _rec = StudioRec.idle;
      _say(_s.studioRecFailed);
      return;
    }
    _nextSeq = 0;
    _bytes = 0;
    _gap = false;
    _mime = '';
    _done = null;
    _earlyDone = null;
    _stage.recordingSink = this;

    final r = await _stage.startRecording(mic: mic);
    if (!r.ok) {
      debugPrint('studio: เริ่มอัดไม่ได้ — ${r.why}');
      await _discard();
      _rec = StudioRec.idle;
      _say(_s.studioRecFailed);
      return;
    }
    if (mic && !r.mic) micNote = _s.studioMicFailed;
    _mime = r.mime;
    _rec = StudioRec.recording;
    _recSince = _clock();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    if (micNote != null) {
      _say(micNote);
    } else {
      _notify();
    }
    // ระหว่างเริ่มมีคนสั่งหยุด (ออกจากสตูดิโอ / แอปพับลง) — หยุดตอนนี้เลย
    if (_stopAfterStart || !_active) unawaited(stopRecording());
  }

  void _onTick() {
    if (_rec != StudioRec.recording) return;
    if (recElapsed >= maxLength) {
      _stopReason = _s.studioRecLimit;
      unawaited(stopRecording());
    }
    _notify();
  }

  /// หยุดอัดแล้วบันทึกลงแกลเลอรี · เรียกซ้ำได้ ได้งานบันทึกตัวเดียวกัน
  Future<void> stopRecording() {
    switch (_rec) {
      case StudioRec.starting:
        _stopAfterStart = true;
        return Future<void>.value();
      case StudioRec.saving:
        return _stopping ?? Future<void>.value();
      case StudioRec.idle:
        return Future<void>.value();
      case StudioRec.recording:
        return _stopping = _stop();
    }
  }

  Future<void> _stop() async {
    _rec = StudioRec.saving;
    _tick?.cancel();
    _tick = null;
    _notify();

    final done = _done = Completer<String>();
    final early = _earlyDone;
    if (early != null) done.complete(early);
    await _stage.stopRecording();

    String mime;
    try {
      mime = await done.future.timeout(doneTimeout);
    } on TimeoutException {
      // เวทีไม่ตอบ (โหลดใหม่กลางคัน / ตายไปแล้ว) — เก็บเท่าที่ได้
      debugPrint('studio: รอก้อนสุดท้ายไม่ไหว บันทึกเท่าที่ได้');
      _gap = true;
      mime = _mime;
    }
    await _finish(mime.isEmpty ? _mime : mime);
    _stopping = null;
  }

  Future<void> _finish(String mime) async {
    _stage.recordingSink = null;
    final sink = _sink;
    _sink = null;
    try {
      await sink?.flush();
      await sink?.close();
    } on Object catch (e) {
      debugPrint('studio: ปิดไฟล์ชั่วคราวไม่สำเร็จ — $e');
    }
    final part = _part;
    _part = null;

    final lines = <String>[?_stopReason];
    if (part == null || _bytes == 0) {
      lines.add(_s.studioRecEmpty);
    } else {
      final mp4 = mime.contains('mp4');
      final type = mp4 ? 'video/mp4' : 'video/webm';
      final name = 'GigGok_${_stamp(_recSince ?? _clock())}.${mp4 ? 'mp4' : 'webm'}';
      var saved = await _platform.saveVideo(part.path, name, type);
      if (saved.needsPermission) {
        await _perms.request(MindPermission.allFiles);
        saved = await _platform.saveVideo(part.path, name, type);
      }
      if (saved.ok) {
        lastSaved = saved.path;
        lines.add(_s.studioRecSaved(saved.path!));
        if (_gap) lines.add(_s.studioRecGap);
      } else {
        lines.add(saved.needsPermission ? _s.studioSaveNeedsFiles : _s.studioSaveFailed);
      }
    }
    await _delete(part);

    _rec = StudioRec.idle;
    _recSince = null;
    _done = null;
    _earlyDone = null;
    _stopReason = null;
    _say(lines.join('\n'));
  }

  /// ทิ้งการอัดที่เริ่มไม่สำเร็จ
  Future<void> _discard() async {
    _stage.recordingSink = null;
    final sink = _sink;
    _sink = null;
    try {
      await sink?.close();
    } on Object {
      // ไฟล์ชั่วคราวที่ปิดไม่ได้ ไม่ใช่เรื่องที่ต้องบอกผู้ใช้
    }
    await _delete(_part);
    _part = null;
  }

  static Future<void> _delete(File? f) async {
    if (f == null) return;
    try {
      if (await f.exists()) await f.delete();
    } on Object catch (e) {
      debugPrint('studio: ลบไฟล์ชั่วคราวไม่ได้ — $e');
    }
  }

  /// ไฟล์ค้างจากรอบที่แอปตายกลางการอัด · ไม่กวาด = temp โตขึ้นทีละหลายสิบเมก
  Future<void> _sweepLeftovers() async {
    try {
      final dir = await _tempDir();
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!name.startsWith('studio_') || !name.endsWith('.part')) continue;
        if (e.path == _part?.path) continue;
        await _delete(e);
      }
    } on Object catch (e) {
      debugPrint('studio: กวาดไฟล์ค้างไม่ได้ — $e');
    }
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  // ── รับก้อนจากเวที (MindRecordingSink) ──────────────────

  @override
  void recChunk(int seq, Uint8List bytes) {
    final sink = _sink;
    if (sink == null) return;
    if (seq != _nextSeq) _gap = true;
    _nextSeq = seq + 1;
    sink.add(bytes);
    _bytes += bytes.length;
  }

  @override
  void recDone(String mime, int chunks) {
    if (chunks >= 0 && chunks != _nextSeq) _gap = true;
    final d = _done;
    if (d != null) {
      if (!d.isCompleted) d.complete(mime);
      return;
    }
    // เวทีจบเองก่อนเราสั่ง — บันทึกเท่าที่ได้
    if (_rec == StudioRec.recording) {
      _earlyDone = mime;
      unawaited(stopRecording());
    }
  }

  @override
  void recFailed(String why) {
    _gap = true;
    if (_rec == StudioRec.recording) unawaited(stopRecording());
  }

  // ── วงจรชีวิตแอป ───────────────────────────────────────

  /// แอปพับลง (ไม่ใช่จอลอย) = เวทีหยุดวาด ภาพในคลิปจะค้างนิ่ง
  /// หยุดแล้วบันทึกส่วนที่ได้ไว้ ดีกว่าได้คลิปที่ครึ่งหลังเป็นภาพนิ่ง
  ///
  /// จอลอยคือ `inactive` ไม่ใช่ `paused` — เวทียังวาดอยู่ อัดต่อได้
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s != AppLifecycleState.paused) return;
    if (_rec == StudioRec.recording || _rec == StudioRec.starting) {
      _stopReason = _s.studioRecBackground;
      unawaited(stopRecording());
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _platform.onPip = null;
    _tick?.cancel();
    unawaited(_discard());
    super.dispose();
  }
}
