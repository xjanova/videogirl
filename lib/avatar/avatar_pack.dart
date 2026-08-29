/// ชุดตัวมายด์ (avatar pack) — โมเดล VRM กับคลิปท่าทาง ที่โหลดทีหลังไม่ได้ฝังใน APK
///
/// **ทำไมต้องโหลดทีหลัง:** `assets/avatar/model/` ถูก `.gitignore` ทั้งโฟลเดอร์
/// เพราะ repo เป็น public และคลิป Mixamo อนุญาตให้ **ใช้** แต่ไม่อนุญาตให้ **แจกต่อ**
/// (ดู THIRD_PARTY.md) แปลว่า APK ที่ CI build จาก checkout สะอาดจะ**ไม่มีตัวเธอ
/// อยู่ข้างในเลย** ถ้าไม่มีทางโหลดทีหลัง auto-update จะกลายเป็นการทับแอปที่มี
/// อวาตาร์ด้วยแอปที่ไม่มี ซึ่งแย่กว่าไม่อัปเดต
///
/// **ทำไมต้องมีเซิร์ฟเวอร์ตัวที่สอง:** `InAppLocalhostServer` อ่านจาก `rootBundle`
/// เท่านั้น ไฟล์ที่โหลดมาลงดิสก์ทีหลังมันเสิร์ฟให้ไม่ได้ · จึงต้องยกเซิร์ฟเวอร์
/// เล็ก ๆ ของตัวเองขึ้นมาชี้ที่โฟลเดอร์ที่แตกไฟล์ไว้ แล้วบอก URL นั้นให้หน้าเว็บ
/// ผ่าน query `?pack=` · คนละ origin กับหน้าเว็บ จึงต้องมี CORS header ให้ครบ
/// ไม่งั้น GLTFLoader จะโหลดไม่ได้โดยขึ้นเป็น error ที่อ่านไม่ออกว่าเรื่อง CORS
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// พอร์ตของเซิร์ฟเวอร์ที่เสิร์ฟชุดตัวมายด์ — คนละตัวกับ 8747 ที่เสิร์ฟ asset ในแอป
const kAvatarPackPort = 8748;

/// ไฟล์ที่ต้องมีจริงถึงจะถือว่าชุดใช้ได้ ไม่ใช่แค่ "แตกไฟล์แล้ว"
///
/// เช็คไฟล์จริง ไม่ใช่เช็คว่ามีโฟลเดอร์ — zip ที่แตกครึ่งทาง (แบตหมด แอปถูกฆ่า)
/// จะทิ้งโฟลเดอร์ที่มีของไม่ครบไว้ แล้วรอบหน้าจะคิดว่าพร้อมแล้วทั้งที่ยังไม่พร้อม
const _required = 'minde.vrm';

/// บันทึกว่าชุดที่แตกไว้เป็นตัวไหน เขียน**หลัง**แตกเสร็จเท่านั้น
const _stamp = 'pack.json';

/// สาเหตุที่พลาด — เก็บเป็น**รหัส** ไม่ใช่ประโยค
///
/// ชั้นนี้ไม่มี context ของ Flutter จึงแปลภาษาไม่ได้ และไม่ควรแปลด้วย
/// ถ้าเก็บเป็นประโยคไทย ผู้ใช้อังกฤษจะเจอไทยโผล่กลางจอ (เทสต์ i18n จับตรงนี้)
enum AvatarPackError {
  /// ยังไม่ได้ตั้งที่อยู่ของชุด
  noUrl,

  /// โหลดไม่ถึงปลายทาง หรือเน็ตหลุดกลางทาง
  network,

  /// แฮชไม่ตรงกับที่ประกาศไว้ — ไฟล์ขาดหรือถูกสลับ
  hashMismatch,

  /// แตกไฟล์แล้วไม่เจอโมเดล = แพ็กผิดโครง
  badPack,

  /// ยกเซิร์ฟเวอร์ไม่ขึ้น (พอร์ตชนกับโปรแกรมอื่น)
  noServer,
}

enum AvatarPackStage {
  unknown,
  missing,
  downloading,
  verifying,
  unpacking,
  ready,
  failed,
}

class AvatarPack extends ChangeNotifier {
  AvatarPack({http.Client? httpClient, int port = kAvatarPackPort})
      : _http = httpClient ?? http.Client(),
        _port = port;

  final http.Client _http;
  final int _port;

  AvatarPackStage _stage = AvatarPackStage.unknown;
  AvatarPackStage get stage => _stage;

  double _progress = 0;
  double get progress => _progress;

  AvatarPackError? _error;
  AvatarPackError? get error => _error;

  /// รายละเอียดทางเทคนิคสำหรับ log — ไม่ใช่ของผู้ใช้ อย่าเอาไปโชว์
  String? _detail;
  String? get errorDetail => _detail;

  int _bytes = 0;

  /// ขนาดที่โหลดมาแล้ว/ทั้งหมด เป็น MB — ใช้โชว์ตอนกำลังโหลด
  String get sizeLabel => '${(_bytes / 1048576).toStringAsFixed(1)} MB';

  Directory? _dir;
  HttpServer? _server;
  bool _disposed = false;

  /// URL ฐานที่หน้าเว็บต้องใช้แทน `./model/` — null ถ้ายังไม่มีชุดในเครื่อง
  ///
  /// ต้องลงท้ายด้วย `/` เพราะฝั่ง JS ต่อชื่อไฟล์ตรง ๆ (`base + 'minde.vrm'`)
  String? get baseUrl =>
      _stage == AvatarPackStage.ready ? 'http://localhost:$_port/' : null;

  /// ดูว่ามีชุดอยู่ในเครื่องแล้วหรือยัง แล้วยกเซิร์ฟเวอร์ขึ้นถ้ามี
  ///
  /// เรียกตอนเปิดแอป **ก่อน**สร้าง WebView ไม่งั้นหน้าเว็บจะโหลดด้วย base เก่า
  /// แล้วต้องรีโหลดทีหลัง ซึ่งผู้ใช้เห็นเป็นอวาตาร์กะพริบหายไปแล้วกลับมา
  Future<void> restore() async {
    final dir = await _packDir();
    final marker = File('${dir.path}${Platform.pathSeparator}$_required');
    if (!await marker.exists()) {
      _set(AvatarPackStage.missing);
      return;
    }
    _dir = dir;
    if (await _serve(dir)) {
      _set(AvatarPackStage.ready);
    } else {
      _set(AvatarPackStage.failed, error: AvatarPackError.noServer);
    }
  }

  /// โหลดชุดจาก [url] แล้วแตกลงเครื่อง
  ///
  /// [expectedSha256] ถ้าใส่มาจะตรวจก่อนแตกไฟล์เสมอ · ไม่ใส่ = ข้ามการตรวจ
  /// ซึ่งยอมได้เพราะเป็นไฟล์ของเจ้าของเองจากที่ที่เจ้าของตั้ง ไม่ใช่ APK ที่จะ
  /// ถูกส่งเข้าตัวติดตั้งของระบบ — แต่ถ้ามีแฮชก็ควรใส่ ไฟล์ 35MB ที่โหลดขาด
  /// จะกลายเป็น zip เสียที่แตกไม่ออก
  Future<bool> download(String url, {String? expectedSha256}) async {
    if (_stage == AvatarPackStage.downloading ||
        _stage == AvatarPackStage.unpacking) {
      return false;
    }
    final target = url.trim();
    if (target.isEmpty) {
      _set(AvatarPackStage.missing, error: AvatarPackError.noUrl);
      return false;
    }

    _progress = 0;
    _bytes = 0;
    _set(AvatarPackStage.downloading);

    File? zip;
    try {
      final res = await _http
          .send(http.Request('GET', Uri.parse(target)))
          .timeout(const Duration(seconds: 60));
      if (res.statusCode >= 400) {
        _set(AvatarPackStage.failed,
            error: AvatarPackError.network, detail: 'HTTP ${res.statusCode}');
        return false;
      }

      final tmp = await getTemporaryDirectory();
      zip = File('${tmp.path}${Platform.pathSeparator}avatar-pack.zip');
      final sink = zip.openWrite();
      final total = res.contentLength ?? 0;
      var received = 0;

      // สตรีมลงไฟล์ ไม่ buffer ทั้งก้อน — ชุดตัวเธอ ~35MB บนเครื่องแรม 2.5GB
      // การถือทั้งก้อนไว้ในหน่วยความจำพร้อมกับ WebGL ที่รันอยู่คือทางไปสู่ OOM
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        _bytes = received;
        if (total > 0 && !_disposed) {
          _progress = received / total;
          notifyListeners();
        }
      }
      await sink.close();

      if (expectedSha256 != null && expectedSha256.isNotEmpty) {
        _set(AvatarPackStage.verifying);
        final actual = await _hashFile(zip);
        if (actual != expectedSha256.toLowerCase()) {
          await zip.delete();
          _set(AvatarPackStage.failed, error: AvatarPackError.hashMismatch);
          return false;
        }
      }

      _set(AvatarPackStage.unpacking);
      final dir = await _packDir();
      // ล้างของเก่าก่อนเสมอ — แตกทับของเดิมจะเหลือไฟล์ของชุดก่อนหน้าปนอยู่
      // แล้ว clips.json ใหม่จะอ้างถึงคลิปที่ไม่มี หรือแย่กว่านั้นคือเจอคลิปเก่า
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);

      // extractFileToDisk สตรีมทีละรายการ ไม่คลายทั้ง zip ลงหน่วยความจำ
      await extractFileToDisk(zip.path, dir.path);
      await zip.delete();
      zip = null;

      final marker = File('${dir.path}${Platform.pathSeparator}$_required');
      if (!await marker.exists()) {
        _set(AvatarPackStage.failed,
            // detail เป็นของนักพัฒนา เขียนอังกฤษเหมือน debugPrint ที่เหลือ
            error: AvatarPackError.badPack, detail: 'missing $_required');
        return false;
      }

      await File('${dir.path}${Platform.pathSeparator}$_stamp').writeAsString(
        jsonEncode({'url': target, 'sha256': expectedSha256}),
        flush: true,
      );

      _dir = dir;
      if (!await _serve(dir)) {
        _set(AvatarPackStage.failed, error: AvatarPackError.noServer);
        return false;
      }
      _set(AvatarPackStage.ready);
      return true;
    } on Exception catch (e) {
      debugPrint('avatar pack: โหลดไม่สำเร็จ — $e');
      try {
        await zip?.delete();
      } catch (_) {
        // ไฟล์ชั่วคราวลบไม่ได้ ไม่ใช่เรื่องที่ผู้ใช้ต้องรู้
      }
      _set(AvatarPackStage.failed,
          error: AvatarPackError.network, detail: '$e');
      return false;
    }
  }

  /// ลบชุดออกจากเครื่อง — คืนพื้นที่ หรือใช้ตอนอยากโหลดชุดใหม่ทับ
  Future<void> remove() async {
    await _stopServer();
    final dir = _dir ?? await _packDir();
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      debugPrint('avatar pack: ลบไม่สำเร็จ — $e');
    }
    _dir = null;
    _set(AvatarPackStage.missing);
  }

  // ── เซิร์ฟเวอร์เล็ก ๆ ที่เสิร์ฟเฉพาะโฟลเดอร์ชุดตัวมายด์ ────────────

  Future<bool> _serve(Directory dir) async {
    await _stopServer();
    try {
      // ผูกกับ loopback เท่านั้น เครื่องอื่นในวงแลนต้องดึงไฟล์นี้ไม่ได้
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      _server = server;
      server.listen(
        (req) => _handle(req, dir),
        onError: (Object e) => debugPrint('avatar pack: เสิร์ฟพลาด — $e'),
        cancelOnError: false,
      );
      return true;
    } on SocketException catch (e) {
      debugPrint('avatar pack: bind พอร์ต $_port ไม่ได้ — $e');
      return false;
    }
  }

  Future<void> _handle(HttpRequest req, Directory dir) async {
    final res = req.response;
    // หน้าเวทีอยู่คนละพอร์ต = คนละ origin · ไม่มี header นี้ GLTFLoader จะโหลด
    // ไม่ได้ และ error ที่ได้ไม่ได้บอกว่าเป็นเรื่อง CORS
    res.headers.set('Access-Control-Allow-Origin', '*');

    if (req.method == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
      await res.close();
      return;
    }

    final name = _safeName(req.uri.path);
    if (name == null) {
      res.statusCode = HttpStatus.forbidden;
      await res.close();
      return;
    }

    final file = File('${dir.path}${Platform.pathSeparator}$name');
    if (!await file.exists()) {
      // 404 เป็นเรื่องปกติที่นี่ — motion.js อ้างคลิปที่บางชุดไม่ได้ใส่มา
      // และมันข้ามให้เองอยู่แล้ว ไม่ต้อง log ให้รก
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }

    res.headers.contentType = _typeOf(name);
    res.headers.set('Cache-Control', 'no-store');
    try {
      await res.addStream(file.openRead());
    } on Exception catch (e) {
      debugPrint('avatar pack: ส่งไฟล์ $name ไม่จบ — $e');
    }
    await res.close();
  }

  /// กันการเดินออกนอกโฟลเดอร์ชุด
  ///
  /// เซิร์ฟเวอร์นี้ผูกกับ loopback และมีแต่หน้าเว็บของเราเองที่เรียก แต่หน้าเว็บ
  /// นั้นรัน JS และวันหลังอาจมีใครใส่ URL จากที่อื่นเข้าไป — ด่านนี้ราคาถูกมาก
  /// เทียบกับการเปิดให้อ่านไฟล์ทั้งเครื่องผ่าน `../../`
  static String? _safeName(String path) {
    final decoded = Uri.decodeComponent(path);
    final name = decoded.startsWith('/') ? decoded.substring(1) : decoded;
    if (name.isEmpty) return null;
    if (name.contains('..') || name.contains('\\') || name.contains('/')) {
      return null;
    }
    return name;
  }

  static ContentType _typeOf(String name) {
    final dot = name.lastIndexOf('.');
    switch (dot < 0 ? '' : name.substring(dot + 1).toLowerCase()) {
      case 'json':
        return ContentType.json;
      case 'vrm':
      case 'glb':
        return ContentType('model', 'gltf-binary');
      case 'png':
        return ContentType('image', 'png');
      case 'jpg':
      case 'jpeg':
        return ContentType('image', 'jpeg');
      default:
        // fbx และอื่น ๆ — three.js อ่านเป็น ArrayBuffer อยู่แล้ว ชนิดไม่สำคัญ
        return ContentType.binary;
    }
  }

  Future<void> _stopServer() async {
    final s = _server;
    _server = null;
    if (s == null) return;
    try {
      await s.close(force: true);
    } on Exception catch (e) {
      debugPrint('avatar pack: ปิดเซิร์ฟเวอร์ไม่สำเร็จ — $e');
    }
  }

  Future<Directory> _packDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}avatar-pack');
  }

  /// อ่านทีละก้อน ไม่โหลดทั้งไฟล์เข้าหน่วยความจำเพื่อคำนวณแฮช
  static Future<String> _hashFile(File file) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return output.events.single.toString().toLowerCase();
  }

  void _set(AvatarPackStage s, {AvatarPackError? error, String? detail}) {
    _stage = s;
    _error = error;
    _detail = detail;
    if (detail != null) debugPrint('avatar pack: ${error?.name} — $detail');
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_stopServer());
    _http.close();
    super.dispose();
  }
}
