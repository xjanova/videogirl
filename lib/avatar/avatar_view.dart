import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

import '../i18n/strings.dart';
import '../theme/tokens.dart';

/// อารมณ์ที่มายด์แสดงได้ — ตรงกับ MOOD_EXPRESSION ใน avatar.js
/// ถ้าเพิ่มที่นี่ต้องไปเพิ่มใน BrainX ด้วย ไม่งั้นจะตกกลับเป็น neutral เงียบ ๆ
/// อารมณ์ที่ฝั่ง JS รู้จัก — ต้องตรงกับ MOOD_EXPRESSION ใน avatar.js
///
/// 🔴 ชื่อที่ไม่มีในนั้นจะถูกปัดกลับเป็น neutral **เงียบ ๆ** ไม่มี error
/// เพิ่มที่นี่แล้วต้องเพิ่มที่โน่นด้วยเสมอ (มีเทสต์คุมอยู่)
enum MindMood {
  neutral,
  happy,
  pleased,
  concerned,
  thinking,
  sorry,
  alert,
  angry,

  /// ถูกทิ้งไว้นานจนเบื่อ — ฝั่ง JS ตั้งเองเมื่อเงียบครบสองนาที
  waiting,

  /// กำลังมีสายโทรศัพท์ — ฝั่ง Dart ตั้งจาก [CallWatch]
  calling,
}

/// ระยะกล้อง — 'bust' ตอนคุย, 'full' ตอนยืนเฉย, 'face' ตอนเชิดหุ่นเฉพาะหน้า
///
/// 🔴 `face` มีอยู่ใน framing.js มาตั้งแต่ต้น (fit 0.34) แต่**ไม่มีทางเรียก
/// จากฝั่ง Dart เลย** เพราะ enum นี้มีแค่สองตัว — ช็อตที่เขียนไว้แล้วแต่ไม่มี
/// ใครไปถึงได้ คือของที่มีต้นทุนแล้วไม่เคยได้ใช้
enum MindFraming { face, bust, full }

/// ระยะกล้องที่โหมดเชิดหุ่นล็อกไว้
///
/// 🔴 **จับได้แค่ใบหน้าเท่านั้น ทั้งสามโหมด**
///
/// mocap ที่มีอยู่คือ FaceLandmarker ล้วน (ปาก ตา สายตา อารมณ์ ท่าหัว/คอ)
/// ไม่มี PoseLandmarker เลย → ไหล่ แขน ลำตัว ขา **ไม่ได้ตามตัวจริง**
/// สามโหมดนี้จึงต่างกันที่ **ระยะกล้อง** ไม่ใช่ที่ปริมาณสิ่งที่จับได้
///
/// เขียนไว้ตรงนี้เพราะชื่อ `full` ชวนให้เข้าใจว่าจับทั้งตัว · ป้ายในหน้าจอ
/// ต้องบอกความจริงข้อนี้ด้วย ไม่ใช่ปล่อยให้ชื่อโหมดพูดแทน
enum MindMocapShot {
  /// ใกล้ที่สุด — เห็นสีหน้าที่เชิดอยู่ชัดที่สุด
  face,

  /// ครึ่งตัว — เห็นท่าหัวกับไหล่ในกรอบเดียวกัน
  bust,

  /// เต็มตัว — เห็นท่าที่คลิปเล่นอยู่ด้วย
  full;

  MindFraming get framing => switch (this) {
        MindMocapShot.face => MindFraming.face,
        MindMocapShot.bust => MindFraming.bust,
        MindMocapShot.full => MindFraming.full,
      };

  static MindMocapShot parse(Object? v) => MindMocapShot.values.firstWhere(
        (s) => s.name == '$v',
        orElse: () => MindMocapShot.face,
      );
}

/// สะพานขอสิทธิ์กล้องระดับระบบ — คู่กับ MainActivity.kt
///
/// เขียนเองแทน permission_handler เพราะเวอร์ชันล่าสุดของแพ็กเกจนั้น build ไม่ผ่าน
/// กับชุด AGP 8.11 / Kotlin 2.2.20 ของโปรเจกต์นี้ · เหตุผลเต็มอยู่ใน MainActivity.kt
abstract final class MindCameraPermission {
  static const _ch = MethodChannel('giggok/system');

  /// 'granted' · 'denied' · 'blocked' (ปฏิเสธถาวร ต้องไปเปิดในตั้งค่าเครื่อง)
  static Future<String> status() => _ask('status');
  static Future<String> request() => _ask('request');

  static Future<void> openSettings() async {
    try {
      await _ch.invokeMethod<void>('openSettings');
    } catch (e) {
      debugPrint('camera: เปิดหน้าตั้งค่าไม่ได้ — $e');
    }
  }

  static Future<String> _ask(String method) async {
    try {
      return await _ch.invokeMethod<String>(method) ?? 'denied';
    } catch (e) {
      // ไม่มีฝั่ง native (เทสต์ / เดสก์ท็อป) — ปล่อยผ่านไปตายที่ getUserMedia
      // ซึ่งบอกสาเหตุได้ตรงกว่าการเดาแทนมันตรงนี้
      debugPrint('camera: ถามสิทธิ์ไม่ได้ ($method) — $e');
      return 'granted';
    }
  }
}

/// สถานะกล้องเชิดหุ่น — ชื่อตรงกับ `phase` ใน mocap.js
///
/// `calibrating` ไม่ใช่แค่การโหลด — เป็นช่วงที่คนเชิด**ต้องนั่งนิ่ง**
/// ให้เก็บค่าฐานของหน้าตัวเอง UI ต้องบอกให้ชัด ไม่ใช่ขึ้นวงกลมหมุนเฉย ๆ
enum MindMocapPhase { off, starting, calibrating, live, failed }

/// รีโมตของอวาตาร์ ส่งคำสั่งข้ามไปฝั่ง WebView
///
/// ทุกคำสั่งเงียบไว้ถ้าเวทียังไม่พร้อม เพราะ UI เรียกได้ตลอดเวลา
/// (ผู้ใช้กดส่งข้อความได้ตั้งแต่วินาทีแรก แต่ VRM 33MB ยังโหลดไม่เสร็จ)
class MindAvatarController extends ChangeNotifier {
  InAppWebViewController? _web;
  bool _ready = false;
  String? _error;

  /// โมเดลโหลดขึ้นเวทีแล้วหรือยัง (รวมคลิปท่าทางครบแล้ว)
  bool get ready => _ready;

  /// **ตัวเธอขึ้นจอแล้ว** — มาก่อน [ready] หลายวินาที เพราะคลิปท่าทาง
  /// ยังทยอยโหลดอยู่ แต่คนดูเห็นเธอยืนอยู่แล้ว
  ///
  /// หน้าเปิดแอปรอสัญญาณนี้ ไม่ใช่รอ [ready] — รอจนคลิปครบแปลว่าให้คนนั่ง
  /// มองโลโก้ต่ออีกหลายวินาทีทั้งที่เธอพร้อมให้เห็นแล้ว
  bool _visible = false;
  bool get visible => _visible;

  /// ความคืบหน้าการโหลดจริง 0–100 — นับจากไบต์ที่โหลดมาแล้ว ไม่ใช่แถบที่วิ่งเอง
  int _loadPercent = 0;
  int get loadPercent => _loadPercent;

  /// ข้อความผิดพลาดจากฝั่ง WebView — ปกติคือหาไฟล์โมเดลอวาตาร์ไม่เจอ
  String? get error => _error;

  void _attach(InAppWebViewController web) => _web = web;

  void _onReady() {
    if (_ready) return;
    _ready = true;
    _visible = true;
    _loadPercent = 100;
    _error = null;
    notifyListeners();
  }

  void _onVisible() {
    if (_visible) return;
    _visible = true;
    notifyListeners();
  }

  void _onProgress(int pct) {
    if (pct == _loadPercent) return;
    _loadPercent = pct.clamp(0, 100);
    notifyListeners();
  }

  void _onError(String message) {
    _ready = false;
    // เวทีพัง = ไม่มีทางเห็นเธอ · ต้องปลดธงนี้ด้วย ไม่งั้นหน้าเปิดแอปจะรอ
    // สัญญาณที่ไม่มีวันมา แล้วค้างอยู่บนโลโก้ตลอดกาล
    _visible = false;
    _error = message;
    notifyListeners();
  }

  /// เสียงพูดพังไม่ใช่เรื่องเดียวกับเวทีพัง — เธอยังยืนอยู่ได้
  /// จึงไม่แตะ `_ready` ไม่งั้นจะไปซ่อนตัวเธอทั้งที่ภาพไม่ได้มีปัญหา
  String? _speakError;
  String? get speakError => _speakError;

  void _onSpeakFailed(String why) {
    _speakError = why;
    notifyListeners();
  }

  Future<void> setMood(MindMood mood) => _call("window.minde.mood('${mood.name}')");

  /// เล่นไฟล์เสียงพร้อมขยับปาก — url ต้องเข้าถึงได้จากฝั่ง WebView
  Future<void> speak(String url) =>
      _call("window.minde.speak(${_jsString(url)})");

  /// เล่นเสียงจากไบต์ที่สังเคราะห์มา (OpenAI หรือเครื่อง Android ก็ได้)
  ///
  /// ส่งผ่าน callAsyncJavaScript พร้อม arguments ไม่ใช่ต่อสตริงเข้า JS
  /// เพราะ base64 ของ mp3 ยาวเป็นแสนตัวอักษร การต่อสตริงขนาดนั้นทั้งช้า
  /// และเสี่ยงพังถ้ามีอักขระหลุด · รอจนเล่นจบเพื่อให้ผู้เรียกรู้จังหวะ
  Future<void> speakBytes(Uint8List bytes, {String mime = 'audio/mpeg'}) async {
    final web = _web;
    if (web == null || !_ready) return;
    try {
      await web.callAsyncJavaScript(
        functionBody: 'return await window.minde.speakBytes(b64, mime);',
        arguments: {'b64': base64Encode(bytes), 'mime': mime},
      );
    } catch (e) {
      debugPrint('avatar: เล่นเสียงไม่สำเร็จ — $e');
    }
  }

  // ── รูปหน้าเธอ สำหรับปุ่มกลางแถบนำทาง ────────────────────
  Uint8List? _faceBytes;

  /// รูปหน้าเธอ — null ถ้ายังถ่ายไม่สำเร็จ ปุ่มจะใช้ไอคอนสำรองแทน
  ImageProvider? get faceImage =>
      _faceBytes == null ? null : MemoryImage(_faceBytes!);

  bool _faceTried = false;

  /// ถ่ายรูปหน้าเธอครั้งเดียวแล้วเก็บไว้ในเครื่อง
  ///
  /// เก็บลงดิสก์เพราะการถ่ายต้องดึงกล้องเข้ามาเป็นระยะ bust ชั่วขณะ
  /// ถ้าถ่ายใหม่ทุกครั้งที่เปิดแอป ผู้ใช้จะเห็นกล้องกระตุกโดยไม่รู้สาเหตุ
  Future<void> ensureFace() async {
    if (_faceTried || _faceBytes != null) return;
    _faceTried = true;

    // มีของเก่าอยู่แล้วก็ใช้เลย
    final cached = await _faceFile();
    if (await cached.exists()) {
      final bytes = await cached.readAsBytes();
      if (bytes.isNotEmpty) {
        _faceBytes = bytes;
        notifyListeners();
        return;
      }
    }

    final web = _web;
    if (web == null || !_ready) {
      _faceTried = false; // เวทียังไม่พร้อม ไว้ลองใหม่รอบหน้า
      return;
    }

    try {
      final result = await web.callAsyncJavaScript(
        functionBody: 'return await window.minde.snapshotFace(256);',
      );
      final dataUrl = result?.value as String?;
      if (dataUrl == null || !dataUrl.startsWith('data:image')) return;

      final b64 = dataUrl.substring(dataUrl.indexOf(',') + 1);
      final bytes = base64Decode(b64);
      if (bytes.isEmpty) return;

      _faceBytes = bytes;
      await cached.writeAsBytes(bytes, flush: true);
      notifyListeners();
    } catch (e) {
      debugPrint('avatar: ถ่ายรูปหน้าไม่สำเร็จ — $e');
    }
  }

  Future<File> _faceFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}mind_face.png');
  }

  // ── กล้องเชิดหุ่น (motion capture ใบหน้า) ─────────────────

  MindMocapPhase _mocapPhase = MindMocapPhase.off;
  bool _mocapTracking = false;
  double _mocapProgress = 0;
  String? _mocapError;
  bool _mocapDenied = false;
  bool _mocapBlocked = false;

  MindMocapPhase get mocapPhase => _mocapPhase;

  /// กำลังใช้กล้องอยู่ (รวมช่วงกำลังเปิดและกำลังคาลิเบรต)
  bool get mocapOn =>
      _mocapPhase == MindMocapPhase.starting ||
      _mocapPhase == MindMocapPhase.calibrating ||
      _mocapPhase == MindMocapPhase.live;

  /// เจอหน้าในเฟรมล่าสุดไหม — คนอาจลุกออกจากกล้องโดยที่โหมดยังเปิดอยู่
  bool get mocapTracking => _mocapTracking;

  /// ความคืบหน้าการเก็บค่าฐาน 0..1
  double get mocapProgress => _mocapProgress;

  /// ข้อความดิบจากฝั่งเว็บ — ของนักพัฒนา ไม่ใช่ของผู้ใช้ อย่าเอาไปโชว์ตรง ๆ
  String? get mocapError => _mocapError;

  /// ผู้ใช้กดไม่อนุญาตกล้อง
  bool get mocapDenied => _mocapDenied;

  /// ปฏิเสธถาวร — ขอซ้ำไม่ขึ้นแล้ว ต้องไปเปิดในตั้งค่าของเครื่อง
  bool get mocapBlocked => _mocapBlocked;

  /// เปิดโหมดหุ่นเชิด
  ///
  /// 🔴 ต้องขอสิทธิ์กล้อง**ระดับระบบ**ก่อนเสมอ ปลั๊กอิน WebView ไม่ได้ขอให้
  /// `onPermissionRequest` ของมันเรียกแค่ `request.grant()` ซึ่งเป็นการอนุญาต
  /// ในชั้นของเว็บเท่านั้น ถ้าแอปยังไม่มีสิทธิ์จริง `getUserMedia` จะถูกปฏิเสธ
  /// และฝั่งเว็บเห็นแค่ NotAllowedError ที่อ่านไม่ออกว่าเป็นความผิดของใคร
  Future<bool> startMocap() async {
    final web = _web;
    if (web == null || !_ready) return false;
    if (mocapOn) return true;

    _mocapError = null;
    _mocapDenied = false;
    _mocapBlocked = false;
    _mocapPhase = MindMocapPhase.starting;
    notifyListeners();

    if (!await _grantCamera()) {
      _mocapPhase = MindMocapPhase.off;
      notifyListeners();
      return false;
    }

    try {
      final result = await web.callAsyncJavaScript(
        functionBody: 'return await window.minde.mocapStart();',
      );
      _readMocap(result?.value);
      return _mocapPhase != MindMocapPhase.failed;
    } catch (e) {
      debugPrint('avatar: เปิดกล้องเชิดหุ่นไม่สำเร็จ — $e');
      _mocapPhase = MindMocapPhase.failed;
      _mocapError = '$e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> _grantCamera() async {
    if (await MindCameraPermission.status() == 'granted') return true;

    final answer = await MindCameraPermission.request();
    if (answer == 'granted') return true;

    _mocapDenied = true;
    _mocapBlocked = answer == 'blocked';
    return false;
  }

  /// พาผู้ใช้ไปหน้าตั้งค่าของแอปเอง — ใช้ตอนปฏิเสธถาวรจนขอซ้ำไม่ขึ้นแล้ว
  Future<void> openCameraSettings() => MindCameraPermission.openSettings();

  Future<void> stopMocap() async {
    await _call('window.minde.mocapStop()');
    _mocapPhase = MindMocapPhase.off;
    _mocapTracking = false;
    _mocapProgress = 0;
    notifyListeners();
  }

  /// เก็บค่าฐานใหม่ — เปลี่ยนคนเชิด เปลี่ยนที่นั่ง หรือหน้าเริ่มเพี้ยน
  Future<void> recalibrateMocap() => _call('window.minde.mocapCalibrate()');

  /// อ่านสถานะที่ฝั่งเว็บส่งมา ทั้งจากค่าที่คืนกลับและจากข้อความ 'mocap'
  void _readMocap(Object? raw) {
    if (raw is! Map) return;
    final phase = '${raw['phase']}';
    _mocapPhase = MindMocapPhase.values.firstWhere(
      (p) => p.name == phase,
      orElse: () => MindMocapPhase.off,
    );
    _mocapTracking = raw['tracking'] == true;
    _mocapProgress = (raw['progress'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0;
    final err = raw['error'];
    _mocapError = err == null ? null : '$err';
    notifyListeners();
  }

  Future<void> stop() => _call('window.minde.stop()');

  /// โหลดเวทีใหม่ — ใช้ตอนชุดตัวเธอเพิ่งโหลดเสร็จ ทางไปหาโมเดลจึงเปลี่ยน
  ///
  /// รีเซ็ต `_ready` ก่อน เพราะหน้าเก่ากำลังจะหายไป ถ้าไม่รีเซ็ต คำสั่งที่ยิง
  /// ระหว่างที่หน้าใหม่ยังโหลดไม่เสร็จจะหายเงียบ ๆ โดยผู้เรียกคิดว่าสำเร็จ
  Future<void> _reload(Uri url) async {
    final web = _web;
    if (web == null) return;
    _ready = false;
    _visible = false;
    _loadPercent = 0;
    _faceTried = false;
    notifyListeners();
    try {
      await web.loadUrl(urlRequest: URLRequest(url: WebUri('$url')));
    } catch (e) {
      debugPrint('avatar: โหลดเวทีใหม่ไม่สำเร็จ — $e');
    }
  }

  /// คำขอของตัวจัดฉากอัตโนมัติ — **ถูกล็อกทับได้** ระหว่างเชิดหุ่น
  Future<void> setFraming(MindFraming f) =>
      _call("window.minde.frame('${f.name}')");

  /// ระยะกล้องที่โหมดเชิดหุ่นล็อกไว้ · null = ยังไม่ได้ตั้ง (ใช้ค่าตั้งต้น)
  MindMocapShot _mocapShot = MindMocapShot.face;
  MindMocapShot get mocapShot => _mocapShot;

  /// เลือกระยะกล้องของโหมดเชิดหุ่น
  ///
  /// 🔴 ไม่ผ่าน [setFraming] โดยตั้งใจ · ตัวนั้นเป็น**คำขอ**ของตัวจัดฉาก
  /// ซึ่งถูกทับได้ตอนเธอพูดหรือตอนส่งข้อความ · ตัวนี้เป็น**คำสั่ง**ของเจ้าของ
  /// ที่ไม่มีอะไรมาทับ ตราบใดที่ยังเชิดอยู่
  Future<void> setMocapShot(MindMocapShot s) async {
    if (_mocapShot == s) return;
    _mocapShot = s;
    notifyListeners();
    await _call("window.minde.mocapShot('${s.name}')");
  }

  Future<void> _call(String js) async {
    final web = _web;
    if (web == null || !_ready) return;
    try {
      await web.evaluateJavascript(source: js);
    } catch (e) {
      debugPrint('avatar: สั่ง "$js" ไม่สำเร็จ — $e');
    }
  }

  /// escape ให้ปลอดภัยก่อนยัดเข้า JS — url อาจมาจากเซิร์ฟเวอร์ ไม่ควรเชื่อ
  static String _jsString(String v) =>
      '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll(r'$', r'\$')}"';

  @override
  void dispose() {
    _web = null;
    super.dispose();
  }
}

/// เวทีของมายด์ — WebView โปร่งใสที่มี three-vrm อยู่ข้างใน
///
/// ถ้าโมเดลยังไม่มีในเครื่อง จะขึ้นกรอบ placeholder แบบเดียวกับใน artboard
/// ไม่ใช่จอว่าง เพราะจอว่างทำให้แยกไม่ออกว่า "ยังโหลด" กับ "พัง"
class MindAvatarView extends StatefulWidget {
  const MindAvatarView({
    super.key,
    required this.controller,
    required this.mode,
    this.packBase,
    this.packModel,
    this.serverPort = 8747,
  });

  final MindAvatarController controller;

  /// ใช้กับสีวงแหวนรอบตัวเธอตอนยังไม่มีโมเดล
  final MindMode mode;

  /// ที่อยู่ของชุดตัวเธอที่โหลดมาทีหลัง — null = ใช้ไฟล์ที่ฝังมาในแอป
  final String? packBase;

  /// ชื่อไฟล์ .vrm ในชุดที่เลือก — ชุดของเลขาคนอื่นไม่ได้ชื่อ minde.vrm
  final String? packModel;

  final int serverPort;

  @override
  State<MindAvatarView> createState() => _MindAvatarViewState();
}

class _MindAvatarViewState extends State<MindAvatarView> {
  /// ทางที่หน้าเว็บกำลังใช้อยู่จริง ณ ตอนนี้
  ///
  /// `initialUrlRequest` ถูกอ่านครั้งเดียวตอนสร้าง WebView — พอชุดตัวเธอโหลด
  /// เสร็จทีหลัง ต้องสั่งโหลดใหม่เอง ไม่งั้นเธอจะไม่โผล่จนกว่าจะปิดเปิดแอป
  String? _loadedKey;

  /// ทางที่หน้าเว็บควรใช้ — รวมทั้ง base และชื่อไฟล์ เพราะเปลี่ยนชุดคือเปลี่ยนทั้งคู่
  String get _packKey => '${widget.packBase}|${widget.packModel}';

  Uri _stageUrl() {
    final base = 'http://localhost:${widget.serverPort}/assets/avatar/index.html';
    final pack = widget.packBase;
    if (pack == null || pack.isEmpty) return Uri.parse(base);
    final model = widget.packModel;
    final q = StringBuffer('?pack=${Uri.encodeQueryComponent(pack)}');
    if (model != null && model.isNotEmpty) {
      q.write('&model=${Uri.encodeQueryComponent(model)}');
    }
    return Uri.parse('$base$q');
  }

  @override
  void didUpdateWidget(MindAvatarView old) {
    super.didUpdateWidget(old);
    if (_packKey == _loadedKey) return;
    _loadedKey = _packKey;
    unawaited(widget.controller._reload(_stageUrl()));
  }

  @override
  Widget build(BuildContext context) {
    _loadedKey ??= _packKey;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final failed = widget.controller.error != null;
        return Stack(
          fit: StackFit.expand,
          children: [
            // WebView ยังอยู่แม้ตอน error เพื่อให้ hot reload หรือการวางไฟล์โมเดล
            // ทีหลังแล้ว reload กลับมาทำงานได้โดยไม่ต้องสร้างใหม่ทั้งก้อน
            Opacity(
              // ผูกกับ `visible` ไม่ใช่ `ready`
              //
              // `ready` มาหลังคลิปท่าทางโหลดครบ ซึ่งช้ากว่าตัวเธอขึ้นจอ
              // หลายวินาที · ถ้าใช้ `ready` ผู้ใช้จะเห็นกรอบแทนตัวเธอค้าง
              // อยู่ทั้งที่เธอยืนพร้อมอยู่ข้างหลังแล้ว
              opacity: widget.controller.visible ? 1 : 0,
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri('${_stageUrl()}')),
                initialSettings: InAppWebViewSettings(
                  transparentBackground: true,
                  supportZoom: false,
                  disableVerticalScroll: true,
                  disableHorizontalScroll: true,
                  // เวทีนี้เสิร์ฟจาก localhost ของตัวเอง ไม่เปิดทางให้หน้าอื่น
                  javaScriptCanOpenWindowsAutomatically: false,
                  useHybridComposition: true,

                  // ปุ่มส่งอยู่ฝั่ง Flutter WebView จึงไม่เคยเห็น user gesture
                  // ถ้าไม่ปลดตรงนี้ AudioContext จะค้างสถานะ suspended ตลอด
                  // อาการคือเสียงไม่ออกและปากไม่ขยับ โดยไม่มี error ที่ไหนเลย
                  mediaPlaybackRequiresUserGesture: false,
                ),
                onWebViewCreated: (web) {
                  widget.controller._attach(web);
                  web.addJavaScriptHandler(
                    handlerName: 'minde',
                    callback: (args) {
                      final msg = args.isEmpty ? null : args.first;
                      if (msg is! Map) return null;
                      switch (msg['type']) {
                        case 'progress':
                          widget.controller
                              ._onProgress((msg['pct'] as num?)?.toInt() ?? 0);
                        case 'visible':
                          widget.controller._onVisible();
                        case 'ready':
                          widget.controller._onReady();
                          // ถ่ายรูปหน้าไว้ใช้เป็นไอคอนปุ่มกลาง หน่วงให้กล้อง
                          // เข้าที่ก่อน ไม่งั้นจะได้ภาพตอนยังเลื่อนอยู่
                          Future<void>.delayed(const Duration(seconds: 2),
                              widget.controller.ensureFace);
                        case 'error':
                          widget.controller._onError('${msg['message']}');

                        // ท่อเสียงพังได้หลายจุดโดยไม่มี error ที่ไหนเลย
                        // จึงให้ฝั่ง JS รายงานกลับมาทุกครั้ง โดยเฉพาะสถานะ
                        // AudioContext ซึ่งถ้าเป็น suspended เสียงจะถูกกลืนหาย
                        case 'speak-start':
                          debugPrint('avatar: เริ่มพูด ${msg['bytes']} ไบต์ '
                              '(${msg['mime']}) · AudioContext=${msg['ctx']}');
                        case 'speak-done':
                          debugPrint('avatar: พูดจบ done=${msg['done']} '
                              'AudioContext=${msg['ctx']} level=${msg['level']}');
                        case 'speak-failed':
                          debugPrint('avatar: พูดไม่ได้ — ${msg['why']} '
                              '(AudioContext=${msg['ctx']})');
                          widget.controller._onSpeakFailed('${msg['why']}');

                        // หน้าเว็บเป็นคนบอกเมื่อสถานะกล้อง**เปลี่ยน**
                        // ฝั่งนี้จึงไม่ต้องยิงถามรัว ๆ ข้ามสะพานเอง
                        case 'mocap':
                          widget.controller._readMocap(msg);
                      }
                      return null;
                    },
                  );
                },
                // กล้องเชิดหุ่นขอ getUserMedia — อนุญาตเฉพาะกล้องเท่านั้น
                //
                // สิทธิ์ระดับระบบถูกขอไปแล้วใน startMocap() ตรงนี้เป็นชั้นของ
                // WebView ล้วน ๆ · กรองให้เหลือเฉพาะกล้องแทนที่จะ grant ทุกอย่าง
                // ที่ขอมา ไม่ใช่เพราะไม่ไว้ใจหน้านี้ (เสิร์ฟจาก localhost ของเราเอง)
                // แต่เพราะวันหลังถ้ามีใครเผลอเรียกไมค์ในหน้านั้น มันจะไม่ได้ไมค์ไป
                // เงียบ ๆ โดยไม่มีใครสังเกต
                onPermissionRequest: (_, request) async {
                  final wanted = request.resources
                      .where((r) => r == PermissionResourceType.CAMERA)
                      .toList();
                  return PermissionResponse(
                    resources: wanted,
                    action: wanted.isEmpty
                        ? PermissionResponseAction.DENY
                        : PermissionResponseAction.GRANT,
                  );
                },

                // เฉพาะ main frame เท่านั้นที่ถือว่าพัง
                //
                // clips.json อ้างถึง Bored.fbx / Waiting.fbx ที่ไม่เคยโหลดมาจาก
                // Mixamo — motion.js ข้ามให้อยู่แล้ว แต่ WebView ยิง callback นี้
                // ทุก subresource ที่พลาด ถ้าไม่กรอง เธอจะโดนซ่อนหลัง placeholder
                // ทั้งที่ยืนอยู่บนเวทีเรียบร้อยแล้ว
                onReceivedError: (_, request, err) {
                  if (request.isForMainFrame ?? false) {
                    widget.controller._onError(err.description);
                  }
                },
                onReceivedHttpError: (_, request, response) {
                  if (request.isForMainFrame ?? false) {
                    widget.controller._onError('HTTP ${response.statusCode}');
                  }
                },
              ),
            ),
            if (!widget.controller.visible)
              _AvatarPlaceholder(mode: widget.mode, failed: failed),
          ],
        );
      },
    );
  }
}

/// ที่ยืนของเธอตอนยังไม่มีโมเดลในเครื่อง
///
/// เดิมเป็นกรอบเส้นประลายทแยงตาม artboard ซึ่งเป็นภาษาของ **wireframe**
/// ไม่ใช่ของแอปที่ปล่อยจริง · และนี่คือสิ่งแรกที่คนเห็นเมื่อลง APK จาก release
/// เพราะชุดตัวเธอไม่ได้ฝังมาใน APK (ดู avatar_pack.dart)
///
/// ภาพออร่าเจนจาก Magnific (0 เครดิต) แล้วคีย์พื้นขาวออกด้วย ffmpeg ให้เป็น
/// alpha จริง — `mix-blend-mode` หรือปล่อยพื้นขาวไว้จะเห็นเป็นกล่องสี่เหลี่ยม
/// ทับพื้นไล่สีของจอ
class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.mode, required this.failed});

  final MindMode mode;

  /// พังจริง (หาไฟล์ไม่เจอ) ต่างจาก "กำลังโหลดอยู่" — ต้องบอกคนละอย่าง
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Opacity(
              opacity: .78,
              child: Image.asset(
                'assets/brand/avatar-aura.png',
                fit: BoxFit.contain,
                // ไฟล์หายก็ต้องไม่พังทั้งจอ — เหลือแค่ข้อความข้างล่างก็ยังสื่อได้
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            failed ? s.avatarMissing : s.avatarPlaceholder,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: MindColors.ink60,
            ),
          ),
          if (failed) ...[
            const SizedBox(height: 4),
            Text(
              s.packMissingHint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: MindColors.ink45),
            ),
          ],
        ],
      ),
    );
  }
}
