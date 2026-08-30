/// ชุดตัวมายด์ — โมเดล VRM กับคลิปท่าทาง ที่โหลดทีหลัง ไม่ได้ฝังใน APK
///
/// **ทำไมต้องโหลดทีหลัง:** `assets/avatar/model/` ถูก `.gitignore` ทั้งโฟลเดอร์
/// เพราะ repo เป็น public และคลิป Mixamo อนุญาตให้ **ใช้** แต่ไม่อนุญาตให้ **แจกต่อ**
/// (ดู THIRD_PARTY.md) แปลว่า APK ที่ CI build จาก checkout สะอาดจะ**ไม่มีตัวเธอ
/// อยู่ข้างในเลย** ถ้าไม่มีทางโหลดทีหลัง auto-update จะกลายเป็นการทับแอปที่มี
/// อวาตาร์ด้วยแอปที่ไม่มี ซึ่งแย่กว่าไม่อัปเดต
///
/// **หลายชุดในเครื่องพร้อมกัน:** เจ้าของจะขายชุดเพิ่ม (ชุดอื่น ทรงอื่น เลขาคนอื่น)
/// แต่ละชุดจึงอยู่คนละโฟลเดอร์ และสลับได้โดยไม่ต้องโหลดใหม่
///
/// 🔴 **คลิปท่าทางใช้ร่วมกัน** — คลิป 20 กว่าไฟล์หนักกว่าตัวโมเดลรวมกันอีก
/// ถ้าทุกชุดต้องแบกคลิปมาเอง ซื้อชุดที่สองก็เท่ากับโหลดของเดิมซ้ำทั้งกอง
/// เซิร์ฟเวอร์จึงหาไฟล์ใน**ชุดที่เลือกอยู่ก่อน แล้วค่อยตกไปที่กองกลาง**
/// ชุดเสื้อผ้าจึงมีแค่ไฟล์ .vrm ไฟล์เดียวก็พอ
///
/// **ทำไมต้องมีเซิร์ฟเวอร์ตัวที่สอง:** `InAppLocalhostServer` อ่านจาก `rootBundle`
/// เท่านั้น ไฟล์ที่โหลดมาลงดิสก์ทีหลังมันเสิร์ฟให้ไม่ได้ · จึงต้องยกเซิร์ฟเวอร์
/// เล็ก ๆ ของตัวเองขึ้นมา แล้วบอก URL นั้นให้หน้าเว็บผ่าน query `?pack=`
/// คนละ origin กับหน้าเว็บ จึงต้องมี CORS header ให้ครบ ไม่งั้น GLTFLoader
/// จะโหลดไม่ได้โดยขึ้นเป็น error ที่อ่านไม่ออกว่าเรื่อง CORS
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

/// พอร์ตของเซิร์ฟเวอร์ที่เสิร์ฟชุด — คนละตัวกับ 8747 ที่เสิร์ฟ asset ในแอป
const kAvatarPackPort = 8748;

/// ชื่อไฟล์รายละเอียดชุด ที่ผู้ทำชุดต้องใส่มาใน zip
const kPackManifest = 'pack.json';

/// โฟลเดอร์กองกลาง — คลิปท่าทางที่ทุกชุดใช้ร่วมกันอยู่ที่นี่
const _sharedDir = '_shared';

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

  /// แตกไฟล์แล้วไม่เจอโมเดล หรือ pack.json ใช้ไม่ได้
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

/// ประเภทของชุด — มีผลต่อสิ่งที่ต้องมีในไฟล์ และวิธีที่ UI จัดกลุ่ม
enum AvatarPackKind {
  /// ตัวละครเต็มตัว (มายด์ หรือเลขาคนอื่น) — มักมาพร้อมคลิปท่าทาง
  character,

  /// เฉพาะชุดเสื้อผ้า/ทรงผม ของตัวละครเดิม — มีแค่ .vrm ก็พอ
  outfit,

  /// ของประดับบนเวที — โมเดล 3D ที่ไม่ใช่ตัวละคร (โซฟา ต้นไม้ ไฟ ป้าย)
  ///
  /// ต่างจากสองอันบนตรงที่**ไม่ได้แทนที่ตัวเธอ** แต่วางเพิ่มเข้าไปในฉาก
  /// จึงใส่พร้อมกันได้หลายชิ้น ต่างจากชุดที่ใส่ได้ทีละชุด
  prop;

  static AvatarPackKind parse(Object? v) => switch ('$v') {
        'outfit' => AvatarPackKind.outfit,
        'prop' => AvatarPackKind.prop,
        _ => AvatarPackKind.character,
      };
}

/// ชุดหนึ่งชุดที่ติดตั้งอยู่ในเครื่อง
@immutable
class AvatarPackInfo {
  const AvatarPackInfo({
    required this.id,
    required this.dir,
    required this.model,
    required this.kind,
    required this.nameTh,
    required this.nameEn,
    required this.providesClips,
  });

  /// รหัสชุด — เป็นชื่อโฟลเดอร์ด้วย จึงต้องปลอดภัยกับระบบไฟล์
  final String id;

  final Directory dir;

  /// ชื่อไฟล์ .vrm ในชุด
  final String model;

  final AvatarPackKind kind;
  final String nameTh;
  final String nameEn;

  /// ชุดนี้มีคลิปท่าทางที่ให้ชุดอื่นยืมใช้ได้ไหม
  final bool providesClips;

  String nameFor(bool thai) => thai ? nameTh : nameEn;

  /// อ่านรายละเอียดจากโฟลเดอร์ที่แตกไฟล์ไว้
  ///
  /// ยอมรับชุดที่ **ไม่มี pack.json** ด้วย — ชุดแรกที่ทำก่อนจะมีระบบหลายชุด
  /// เป็นแบบนั้น ถ้าไม่ยอมรับ ของที่โหลดไว้แล้วจะหายไปเฉย ๆ ตอนอัปเดตแอป
  static Future<AvatarPackInfo?> read(Directory dir, String id) async {
    String? model;
    var kind = AvatarPackKind.character;
    var nameTh = id, nameEn = id;
    var providesClips = false;

    final manifest = File('${dir.path}${Platform.pathSeparator}$kPackManifest');
    if (await manifest.exists()) {
      try {
        final j = jsonDecode(await manifest.readAsString());
        if (j is Map) {
          model = j['model'] as String?;
          kind = AvatarPackKind.parse(j['kind']);
          final name = j['name'];
          if (name is Map) {
            nameTh = '${name['th'] ?? id}';
            nameEn = '${name['en'] ?? name['th'] ?? id}';
          } else if (name is String) {
            nameTh = nameEn = name;
          }
          providesClips = j['providesClips'] == true;
        }
      } on FormatException catch (e) {
        debugPrint('avatar pack: $kPackManifest ของ $id อ่านไม่ออก — $e');
      }
    }

    // ไม่ระบุ model มา (หรือระบุมาแล้วไม่มีไฟล์จริง) ให้หา .vrm ตัวแรกในโฟลเดอร์
    // ผู้ทำชุดพิมพ์ชื่อไฟล์ผิดเป็นเรื่องปกติ และการเดาให้ถูกดีกว่าปฏิเสธทั้งชุด
    if (model == null ||
        !await File('${dir.path}${Platform.pathSeparator}$model').exists()) {
      model = await _firstVrm(dir);
    }
    if (model == null) return null;

    // ไม่ได้ประกาศว่ามีคลิป ก็ดูจากของจริงว่ามี clips.json ไหม
    if (!providesClips) {
      providesClips =
          await File('${dir.path}${Platform.pathSeparator}clips.json').exists();
    }

    return AvatarPackInfo(
      id: id,
      dir: dir,
      model: model,
      kind: kind,
      nameTh: nameTh,
      nameEn: nameEn,
      providesClips: providesClips,
    );
  }

  static Future<String?> _firstVrm(Directory dir) async {
    await for (final f in dir.list()) {
      if (f is File && f.path.toLowerCase().endsWith('.vrm')) {
        return f.uri.pathSegments.last;
      }
    }
    return null;
  }
}

/// ทะเบียนชุดทั้งหมดในเครื่อง + เซิร์ฟเวอร์ที่เสิร์ฟชุดที่เลือกอยู่
class AvatarPacks extends ChangeNotifier {
  AvatarPacks({http.Client? httpClient, int port = kAvatarPackPort})
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
  String get sizeLabel => '${(_bytes / 1048576).toStringAsFixed(1)} MB';

  final List<AvatarPackInfo> _installed = [];
  List<AvatarPackInfo> get installed => List.unmodifiable(_installed);

  String? _selectedId;
  String? get selectedId => _selectedId;

  AvatarPackInfo? get selected {
    if (_installed.isEmpty) return null;
    for (final p in _installed) {
      if (p.id == _selectedId) return p;
    }
    return _installed.first;
  }

  HttpServer? _server;
  bool _disposed = false;

  /// URL ฐานที่หน้าเว็บต้องใช้แทน `./model/` — null ถ้ายังไม่มีชุดพร้อมใช้
  ///
  /// ต้องลงท้ายด้วย `/` เพราะฝั่ง JS ต่อชื่อไฟล์ตรง ๆ (`base + model`)
  String? get baseUrl =>
      _stage == AvatarPackStage.ready ? 'http://localhost:$_port/' : null;

  /// ชื่อไฟล์ .vrm ของชุดที่เลือก — หน้าเว็บต้องรู้ เพราะไม่ได้ชื่อ minde.vrm เสมอไป
  String? get modelFile => _stage == AvatarPackStage.ready ? selected?.model : null;

  /// สแกนชุดที่มีอยู่แล้วยกเซิร์ฟเวอร์
  ///
  /// เรียกตอนเปิดแอป **ก่อน**สร้าง WebView ไม่งั้นหน้าเว็บจะโหลดด้วย base เก่า
  /// แล้วต้องรีโหลดทีหลัง ซึ่งผู้ใช้เห็นเป็นอวาตาร์โผล่แล้วหายแล้วโผล่ใหม่
  Future<void> restore({String? preferId}) async {
    await _rescan();
    if (preferId != null && _installed.any((p) => p.id == preferId)) {
      _selectedId = preferId;
    }
    if (_installed.isEmpty) {
      _set(AvatarPackStage.missing);
      return;
    }
    _set(await _serve()
        ? AvatarPackStage.ready
        : AvatarPackStage.failed,
        error: _server == null ? AvatarPackError.noServer : null);
  }

  Future<void> _rescan() async {
    _installed.clear();
    final root = await _rootDir();
    if (!await root.exists()) return;

    await for (final entry in root.list()) {
      if (entry is! Directory) continue;
      final id = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (id == _sharedDir) continue;
      final info = await AvatarPackInfo.read(entry, id);
      if (info != null) _installed.add(info);
    }
    // เรียงให้คงที่ ไม่งั้นลำดับในหน้าตั้งค่าสลับไปมาทุกครั้งที่เปิด
    _installed.sort((a, b) => a.id.compareTo(b.id));
  }

  /// เลือกชุดที่จะใส่ — เปลี่ยนแล้วผู้เรียกต้องสั่งเวทีโหลดใหม่
  void select(String id) {
    if (!_installed.any((p) => p.id == id)) return;
    _selectedId = id;
    notifyListeners();
  }

  /// โหลดชุดจาก [url] แล้วติดตั้ง
  ///
  /// [expectedSha256] ถ้าใส่มาจะตรวจก่อนแตกไฟล์เสมอ · ไฟล์ 35MB ที่โหลดขาด
  /// จะกลายเป็น zip เสียที่แตกไม่ออก การตรวจแฮชบอกได้ตรง ๆ ว่าเป็นเพราะอะไร
  /// เรียกเมื่อติดตั้งชุดสำเร็จ · ผู้เรียกเอาไปลงสมุดบันทึกได้
  ///
  /// เป็น callback ไม่ใช่การถือ [MindJournal] ไว้เอง เพราะคลาสนี้ไม่ควรรู้จัก
  /// สมุดบันทึก — มันมีหน้าที่เดียวคือจัดการชุด ไม่ใช่เล่าเรื่อง
  void Function(AvatarPackInfo pack)? onInstalled;

  Future<bool> install(String url, {String? expectedSha256}) async {
    if (_stage == AvatarPackStage.downloading ||
        _stage == AvatarPackStage.unpacking) {
      return false;
    }
    final target = url.trim();
    if (target.isEmpty) {
      _set(_installed.isEmpty ? AvatarPackStage.missing : AvatarPackStage.ready,
          error: AvatarPackError.noUrl);
      return false;
    }

    _progress = 0;
    _bytes = 0;
    _set(AvatarPackStage.downloading);

    File? zip;
    Directory? staging;
    try {
      final res = await _http
          .send(http.Request('GET', Uri.parse(target)))
          .timeout(const Duration(seconds: 60));
      if (res.statusCode >= 400) {
        return _fail(AvatarPackError.network, 'HTTP ${res.statusCode}');
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
        if (await _hashFile(zip) != expectedSha256.toLowerCase()) {
          await zip.delete();
          return _fail(AvatarPackError.hashMismatch, null);
        }
      }

      _set(AvatarPackStage.unpacking);

      // แตกลงที่พักก่อน แล้วค่อยย้ายเข้าที่จริงเมื่อรู้ว่าใช้ได้
      //
      // ถ้าแตกลงที่จริงเลย แล้วในไฟล์ไม่มี .vrm หรือ pack.json พัง เราจะเหลือ
      // โฟลเดอร์เสีย ๆ ในทะเบียนที่ผู้ใช้ต้องมาลบเอง · และถ้ามันบังเอิญมี id
      // ตรงกับชุดที่ใช้อยู่ ก็เท่ากับทำลายของเดิมทิ้งเพื่อของที่ใช้ไม่ได้
      final root = await _rootDir();
      await root.create(recursive: true);
      staging = Directory('${root.path}${Platform.pathSeparator}.staging');
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);

      // extractFileToDisk สตรีมทีละรายการ ไม่คลายทั้ง zip ลงหน่วยความจำ
      await extractFileToDisk(zip.path, staging.path);
      await zip.delete();
      zip = null;

      final flat = await _flatten(staging);
      final id = await _idOf(flat);
      final info = await AvatarPackInfo.read(flat, id);
      if (info == null) {
        await staging.delete(recursive: true);
        return _fail(AvatarPackError.badPack, 'no .vrm inside');
      }

      final dest = Directory('${root.path}${Platform.pathSeparator}$id');
      if (await dest.exists()) await dest.delete(recursive: true);
      await flat.rename(dest.path);
      if (await staging.exists()) await staging.delete(recursive: true);
      staging = null;

      // ชุดที่มีคลิปมาด้วย ให้ก๊อปคลิปขึ้นกองกลาง ชุดเสื้อผ้าที่โหลดทีหลัง
      // จะได้ยืมใช้โดยไม่ต้องแบกมาเอง
      final placed = await AvatarPackInfo.read(dest, id);
      if (placed != null && placed.providesClips) await _publishClips(dest);

      await _rescan();
      _selectedId = id;
      _set(await _serve() ? AvatarPackStage.ready : AvatarPackStage.failed,
          error: _server == null ? AvatarPackError.noServer : null);
      if (_stage == AvatarPackStage.ready && placed != null) {
        onInstalled?.call(placed);
      }
      return _stage == AvatarPackStage.ready;
    } on Exception catch (e) {
      debugPrint('avatar pack: โหลดไม่สำเร็จ — $e');
      try {
        await zip?.delete();
        if (staging != null && await staging.exists()) {
          await staging.delete(recursive: true);
        }
      } catch (_) {
        // เก็บกวาดไม่สำเร็จ ไม่ใช่เรื่องที่ผู้ใช้ต้องรู้
      }
      return _fail(AvatarPackError.network, '$e');
    }
  }

  /// zip ที่มีโฟลเดอร์ครอบชั้นเดียว ให้ถือว่าข้างในคือตัวชุด
  ///
  /// คนบีบไฟล์ด้วยคลิกขวาบน Windows จะได้โฟลเดอร์ครอบเสมอ ถ้าไม่รับกรณีนี้
  /// ชุดที่แพ็กถูกต้องทุกอย่างจะถูกปฏิเสธด้วยเหตุผลที่ผู้ใช้แก้เองไม่ถูก
  static Future<Directory> _flatten(Directory staging) async {
    final entries = await staging.list().toList();
    if (entries.length == 1 && entries.first is Directory) {
      return entries.first as Directory;
    }
    return staging;
  }

  /// รหัสชุด — เอาจาก pack.json ถ้ามี ไม่งั้นตั้งจากชื่อไฟล์ .vrm
  static Future<String> _idOf(Directory dir) async {
    final manifest = File('${dir.path}${Platform.pathSeparator}$kPackManifest');
    if (await manifest.exists()) {
      try {
        final j = jsonDecode(await manifest.readAsString());
        final raw = j is Map ? '${j['id'] ?? ''}' : '';
        final safe = _safeId(raw);
        if (safe != null) return safe;
      } on FormatException {
        // ไม่มี id ที่ใช้ได้ ตกไปใช้ชื่อไฟล์แทน
      }
    }
    final vrm = await AvatarPackInfo._firstVrm(dir);
    return _safeId(vrm?.replaceAll(RegExp(r'\.vrm$', caseSensitive: false), ''))
        ?? 'pack';
  }

  /// รหัสชุดกลายเป็นชื่อโฟลเดอร์ ห้ามมีอะไรที่เดินออกนอกรากได้
  ///
  /// รหัสนี้มาจาก `pack.json` ใน zip ที่โหลดมาจากอินเทอร์เน็ต = ข้อมูลที่
  /// ไม่ควรเชื่อ · ถ้าปล่อยให้เป็น `../../` ได้ การติดตั้งชุดจะกลายเป็นการ
  /// เขียนทับไฟล์ที่ไหนก็ได้ในพื้นที่ของแอป
  @visibleForTesting
  static String? safeId(String? raw) => _safeId(raw);

  static String? _safeId(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    if (v.isEmpty) return null;
    final cleaned = v.replaceAll(RegExp(r'[^a-z0-9._-]'), '-');
    if (cleaned.replaceAll(RegExp(r'[.\-_]'), '').isEmpty) return null;
    if (cleaned.startsWith('.')) return null;
    return cleaned.substring(0, cleaned.length.clamp(0, 48));
  }

  /// ก๊อปคลิปขึ้นกองกลาง — ไม่ทับของเดิมที่ชื่อเดียวกัน
  Future<void> _publishClips(Directory pack) async {
    final root = await _rootDir();
    final shared = Directory('${root.path}${Platform.pathSeparator}$_sharedDir');
    await shared.create(recursive: true);
    await for (final f in pack.list()) {
      if (f is! File) continue;
      final name = f.uri.pathSegments.last;
      final lower = name.toLowerCase();
      if (!lower.endsWith('.fbx') && lower != 'clips.json') continue;
      final dst = File('${shared.path}${Platform.pathSeparator}$name');
      if (await dst.exists()) continue;
      try {
        await f.copy(dst.path);
      } on FileSystemException catch (e) {
        debugPrint('avatar pack: ก๊อป $name ขึ้นกองกลางไม่ได้ — $e');
      }
    }
  }

  /// ลบชุดหนึ่งชุดออกจากเครื่อง
  Future<void> remove(String id) async {
    final root = await _rootDir();
    final dir = Directory('${root.path}${Platform.pathSeparator}$id');
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      debugPrint('avatar pack: ลบ $id ไม่สำเร็จ — $e');
    }
    await _rescan();
    if (_selectedId == id) _selectedId = null;
    if (_installed.isEmpty) {
      await _stopServer();
      _set(AvatarPackStage.missing);
    } else {
      _set(AvatarPackStage.ready);
    }
  }

  // ── เซิร์ฟเวอร์ ─────────────────────────────────────────

  Future<bool> _serve() async {
    await _stopServer();
    try {
      // ผูกกับ loopback เท่านั้น เครื่องอื่นในวงแลนต้องดึงไฟล์นี้ไม่ได้
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      _server = server;
      server.listen(
        _handle,
        onError: (Object e) => debugPrint('avatar pack: เสิร์ฟพลาด — $e'),
        cancelOnError: false,
      );
      return true;
    } on SocketException catch (e) {
      debugPrint('avatar pack: bind พอร์ต $_port ไม่ได้ — $e');
      return false;
    }
  }

  Future<void> _handle(HttpRequest req) async {
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

    final file = await _resolve(name);
    if (file == null) {
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

  /// หาไฟล์ในชุดที่เลือกก่อน แล้วค่อยตกไปที่กองกลาง
  ///
  /// ลำดับนี้สำคัญ: ชุดที่มีคลิปของตัวเองต้องได้ใช้ของตัวเอง ไม่ใช่ของกองกลาง
  /// ที่อาจเป็นของตัวละครอื่นซึ่งสัดส่วนกระดูกไม่เหมือนกัน
  Future<File?> _resolve(String name) async {
    final pack = selected;
    if (pack != null) {
      final f = File('${pack.dir.path}${Platform.pathSeparator}$name');
      if (await f.exists()) return f;
    }
    final root = await _rootDir();
    final s = File(
        '${root.path}${Platform.pathSeparator}$_sharedDir${Platform.pathSeparator}$name');
    if (await s.exists()) return s;
    return null;
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

  Future<Directory> _rootDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}avatar-packs');
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

  bool _fail(AvatarPackError e, String? detail) {
    _set(_installed.isEmpty ? AvatarPackStage.failed : AvatarPackStage.ready,
        error: e, detail: detail);
    return false;
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
