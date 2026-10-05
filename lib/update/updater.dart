/// อัปเดตตัวเอง — ถาม xman studio ก่อน ถ้าไม่ได้ค่อยถอยไปอ่าน GitHub Releases
///
/// ## ทำไมถาม xman studio
///
/// กฎของบ้าน (2026-09-24): ลูกค้าต้องไม่เห็น GitHub หรือ repo เลย · หลังบ้าน
/// sync release เองทุก 10 นาที (`products:sync-releases`) แล้วเสิร์ฟ APK ผ่าน
/// xman4289.com พร้อม sha256 · แอปพี่น้อง (Tping, NetX) ใช้ปลายทางเดียวกัน
/// `GET /api/v1/product/{slug}/update/check?current_version=X.Y.Z`
///
/// ## ทำไมยังมี GitHub เป็นทางสำรอง
///
/// วันที่หลังบ้านล่ม หรือสินค้ายังไม่ได้ลงทะเบียน (ตอบ 404) เครื่องที่ลงแอปไปแล้ว
/// ต้องยังอัปเดตได้ ไม่งั้นบั๊กที่ทำให้หลังบ้านเรียกไม่ติดจะถูกแช่แข็งไว้ในเครื่อง
/// ผู้ใช้ตลอดไป · repo เป็น public จึงอ่าน API ได้โดยไม่ต้องมี token
/// อย่าใส่ GitHub token ลง APK เด็ดขาด — APK แกะได้ ใครก็อ่าน token เจอ
///
/// ทั้งสองทาง: **ไม่มี sha256 = ไม่ติดตั้ง** เหมือนเดิมทุกประการ
library;

import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';

import '../system/permissions.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';

const _repo = 'xjanova/videogirl';
const _releaseApi = 'https://api.github.com/repos/$_repo/releases/latest';

/// ไฟล์ผลรวมแฮชที่ต้องแนบไปกับ release ทุกครั้ง
/// รูปแบบเหมือน sha256sum: `<hex>  <ชื่อไฟล์>` บรรทัดละไฟล์
const _sumsAsset = 'SHA256SUMS.txt';

@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.apkUrl,
    required this.apkName,
    required this.sizeBytes,
    required this.sha256,
  });

  final String version;
  final String notes;
  final String apkUrl;
  final String apkName;
  final int sizeBytes;

  /// แฮชที่คาดหวัง — null แปลว่า release นั้นไม่ได้แนบ SHA256SUMS.txt มา
  final String? sha256;

  String get sizeLabel => '${(sizeBytes / 1048576).toStringAsFixed(1)} MB';
}

enum UpdateStage { idle, checking, available, downloading, verifying, ready, failed }

/// สินค้าในระบบของ xman studio
const kStoreProductSlug = 'giggok';

/// ที่อยู่หลังบ้านตั้งต้น — ตัวเดียวกับ MindState._storeDefault
const kUpdateStoreDefault = String.fromEnvironment(
  'STORE_BASE_URL',
  defaultValue: 'https://xman4289.com',
);

class Updater extends ChangeNotifier {
  Updater({
    http.Client? httpClient,
    S Function()? strings,
    String Function()? storeBaseOf,
  })  : _s = strings ?? _thai,
        _storeBaseOf = storeBaseOf ?? (() => kUpdateStoreDefault),
        _http = httpClient ?? http.Client();

  /// อ่านตอนใช้จริง · ผู้ใช้/การตั้งค่าเปลี่ยนที่อยู่หลังบ้านได้ระหว่างแอปเปิด
  final String Function() _storeBaseOf;

  final S Function() _s;
  static S _thai() => const S(AppLang.th);

  final http.Client _http;
  bool _disposed = false;

  UpdateStage _stage = UpdateStage.idle;
  UpdateStage get stage => _stage;

  UpdateInfo? _pending;
  UpdateInfo? get pending => _pending;

  double _progress = 0;
  double get progress => _progress;

  int _received = 0;
  int _total = 0;

  /// "12.4 / 80.0 MB" — ผู้ใช้ต้องเห็นว่าเหลืออีกเท่าไหร่ ไม่ใช่เปอร์เซ็นต์ลอย ๆ
  /// (หลักเดียวกับตัวโหลดโมเดลใน local_brain.dart)
  String get progressLabel =>
      '${_mb(_received)} / ${_mb(_total)} MB';

  static String _mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

  String? _error;
  String? get error => _error;

  String _current = '';
  String get currentVersion => _current;

  void _set(UpdateStage s, {String? error}) {
    if (_disposed) return;
    _stage = s;
    _error = error;
    notifyListeners();
  }

  /// เช็คว่ามีรุ่นใหม่ไหม — เงียบเสมอถ้าไม่มี ไม่รบกวนผู้ใช้
  Future<UpdateInfo?> check() async {
    // 🔴 กำลังโหลด/ตรวจ/พร้อมติดตั้งอยู่ = ห้ามเช็คทับ · การ์ดอัปเดตอยู่ใน
    // ListView ซึ่งสร้าง state ใหม่ทุกครั้งที่เลื่อนผ่าน แล้วเรียก check() ซ้ำ
    // ของเดิมจึงเปลี่ยนสถานะกลางการโหลดเป็น available ปุ่มติดตั้งโผล่กลับมา
    // กดซ้ำ = โหลดสองตัวเขียนไฟล์เดียวกัน แล้วจบที่ hash ไม่ตรง
    if (_stage == UpdateStage.downloading ||
        _stage == UpdateStage.verifying ||
        _stage == UpdateStage.ready) {
      return _pending;
    }
    _set(UpdateStage.checking);
    try {
      final info = await PackageInfo.fromPlatform();
      _current = info.version;

      // ── ทางหลัก: xman studio ──
      final fromStore = await _checkStore(_current);
      if (fromStore != null) {
        if (fromStore.version.isEmpty) {
          _set(UpdateStage.idle); // หลังบ้านตอบชัดว่าไม่มีรุ่นใหม่
          return null;
        }
        _pending = fromStore;
        _set(UpdateStage.available);
        return _pending;
      }

      // ── ทางสำรอง: GitHub Releases ──
      final res = await _http.get(
        Uri.parse(_releaseApi),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 404) {
        _set(UpdateStage.idle);
        return null; // ยังไม่เคยออก release เลย ไม่ใช่ error
      }
      if (res.statusCode >= 400) {
        _set(UpdateStage.failed, error: _s().updateCheckFailed(res.statusCode));
        return null;
      }

      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (json['draft'] == true || json['prerelease'] == true) {
        _set(UpdateStage.idle);
        return null;
      }

      final latest = _normalize('${json['tag_name']}');
      if (!_isNewer(latest, _current)) {
        _set(UpdateStage.idle);
        return null;
      }

      final assets = (json['assets'] as List?) ?? const [];
      final apk = assets.cast<Map<String, dynamic>>().firstWhere(
            (a) => '${a['name']}'.toLowerCase().endsWith('.apk'),
            orElse: () => <String, dynamic>{},
          );
      if (apk.isEmpty) {
        _set(UpdateStage.failed, error: _s().updateNoApk);
        return null;
      }

      final apkName = '${apk['name']}';
      _pending = UpdateInfo(
        version: latest,
        notes: cleanNotes('${json['body'] ?? ''}'),
        apkUrl: '${apk['browser_download_url']}',
        apkName: apkName,
        sizeBytes: (apk['size'] as num?)?.toInt() ?? 0,
        sha256: await _fetchExpectedHash(assets, apkName),
      );

      _set(UpdateStage.available);
      return _pending;
    } on Object {
      _set(UpdateStage.failed, error: _s().updateNoConnection);
      return null;
    }
  }

  /// ถาม xman studio · คืน
  /// - `UpdateInfo` ที่ version ว่าง = ตอบชัดว่าไม่มีรุ่นใหม่
  /// - `UpdateInfo` ปกติ = มีรุ่นใหม่ พร้อมลิงก์ที่เสิร์ฟผ่านหลังบ้านและ sha256
  /// - `null` = ถามไม่สำเร็จ (ล่ม/ยังไม่ลงทะเบียน/ตอบหน้าตาแปลก) → ไปทางสำรอง
  @visibleForTesting
  Future<UpdateInfo?> checkStoreForTest(String current) => _checkStore(current);

  Future<UpdateInfo?> _checkStore(String current) async {
    final base = _storeBaseOf().trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return null;
    try {
      final res = await _http.get(
        Uri.parse('$base/api/v1/product/$kStoreProductSlug/update/check')
            .replace(queryParameters: {'current_version': current}),
        headers: const {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        debugPrint('update: หลังบ้านตอบ ${res.statusCode} — ลองทางสำรอง');
        return null;
      }
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      if (j is! Map) return null;
      // บางปลายทางของบ้านห่อด้วย {success, data:{…}} · รับทั้งสองแบบ
      final m = j['data'] is Map ? j['data'] as Map : j;
      if (m['has_update'] != true) {
        return const UpdateInfo(
            version: '', notes: '', apkUrl: '', apkName: '', sizeBytes: 0,
            sha256: null);
      }
      final version = _normalize('${m['latest_version'] ?? ''}');
      final url = '${m['download_url'] ?? ''}';
      // ตรวจซ้ำฝั่งเราด้วย · ตัวเลขที่หลังบ้านบอกว่าใหม่ แต่ไม่ใหม่กว่าจริง
      // (เช่นแคชเก่า) ต้องไม่พาไปติดตั้งรุ่นเดิมทับ
      if (version.isEmpty || url.isEmpty || !_isNewer(version, current)) {
        return null;
      }
      final sha = '${m['sha256'] ?? ''}'.trim().toLowerCase();
      return UpdateInfo(
        version: version,
        notes: cleanNotes('${m['changelog'] ?? ''}'),
        apkUrl: url,
        apkName: _safeApkName('${m['filename'] ?? ''}', version),
        sizeBytes: (m['file_size'] is num) ? (m['file_size'] as num).toInt() : 0,
        sha256: RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ? sha : null,
      );
    } on Object catch (e) {
      debugPrint('update: ถามหลังบ้านไม่ได้ — ${e.runtimeType}');
      return null;
    }
  }

  /// ชื่อไฟล์ที่ปลอดภัยสำหรับเขียนลงแคช · ชื่อจากเซิร์ฟเวอร์ห้ามมี path
  static String _safeApkName(String raw, String version) {
    final base = raw.split(RegExp(r'[\\/]')).last.trim();
    if (RegExp(r'^[A-Za-z0-9._-]+\.apk$').hasMatch(base)) return base;
    return 'giggok-$version.apk';
  }

  Future<String?> _fetchExpectedHash(List<dynamic> assets, String apkName) async {
    final sums = assets.cast<Map<String, dynamic>>().firstWhere(
          (a) => '${a['name']}' == _sumsAsset,
          orElse: () => <String, dynamic>{},
        );
    if (sums.isEmpty) return null;

    try {
      final res = await _http
          .get(Uri.parse('${sums['browser_download_url']}'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode >= 400) return null;

      for (final line in utf8.decode(res.bodyBytes).split('\n')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2 && parts.last.replaceAll('*', '') == apkName) {
          return parts.first.toLowerCase();
        }
      }
    } on Exception {
      return null;
    }
    return null;
  }

  /// โหลด APK แล้ว **ตรวจแฮชก่อนเปิดตัวติดตั้งเสมอ**
  ///
  /// ถ้าไม่ตรวจ ไฟล์ที่โหลดมาครึ่ง ๆ หรือถูกสลับระหว่างทางจะถูกส่งเข้า installer
  /// ทันที — นี่คือช่องทางลงมัลแวร์ที่ตรงที่สุดเท่าที่แอปหนึ่งจะเปิดให้ได้
  Future<bool> downloadAndInstall() async {
    final info = _pending;
    if (info == null) return false;
    // แตะปุ่มซ้ำระหว่างรอเช็คสิทธิ์ติดตั้ง = สองตัวโหลดเขียนไฟล์เดียวกัน
    if (_installing) return false;
    _installing = true;
    try {
      return await _downloadAndInstall(info);
    } finally {
      _installing = false;
    }
  }

  bool _installing = false;

  /// ไม่มีข้อมูลไหลเข้ามานานเท่านี้ = เน็ตค้าง ไม่ใช่เน็ตช้า
  ///
  /// timeout ของ `send()` คุมแค่ตอนรอหัวตอบกลับ ไม่คุมเนื้อไฟล์ · เน็ตที่ค้าง
  /// กลางทางทำให้ "กำลังดาวน์โหลด" ค้างตลอดกาล และปุ่มโหลดใหม่ก็ถูกซ่อนไว้
  static const _stallAfter = Duration(seconds: 45);

  Future<bool> _downloadAndInstall(UpdateInfo info) async {
    // เก็บกวาด APK ของรุ่นก่อน ๆ ที่โหลดค้างไว้ในแคช · ไฟล์ละราว 80 MB
    // และชื่อไม่ซ้ำกันทุกรุ่น จึงไม่เคยถูกเขียนทับเอง
    await _sweepOldApks(keep: info.apkName);

    // 🔴 เช็คสิทธิ์ติดตั้ง **ก่อน** เริ่มโหลด ไม่ใช่ตอนจะเปิดตัวติดตั้ง
    //
    // ของเดิมโหลด APK จนจบทั้งไฟล์ (หลายร้อยเมก) แล้วค่อยพบว่าเปิดตัวติดตั้ง
    // ไม่ได้ — เสียทั้งเน็ตทั้งเวลาทั้งพื้นที่ แล้วต้องเริ่มใหม่หมดหลังไปกดอนุญาต
    // ค่าที่ใช้เช็คเป็นแค่ boolean ตัวเดียว ถามก่อนแทบไม่มีต้นทุน
    if (!await _canInstall()) {
      _set(UpdateStage.failed, error: _s().updateInstallerBlocked);
      return false;
    }

    _progress = 0;
    _set(UpdateStage.downloading);

    try {
      final req = http.Request('GET', Uri.parse(info.apkUrl));
      final res = await _http.send(req).timeout(const Duration(seconds: 60));
      if (res.statusCode >= 400) {
        _set(UpdateStage.failed, error: _s().updateDownloadFailed(res.statusCode));
        return false;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}${info.apkName}');
      final sink = file.openWrite();
      final total = res.contentLength ?? info.sizeBytes;
      var received = 0;
      _total = total;
      _received = 0;

      // สตรีมลงไฟล์ ไม่ buffer ทั้งก้อนในหน่วยความจำ APK หลายสิบเมกจะทำให้แอปตาย
      try {
        await for (final chunk in res.stream.timeout(_stallAfter)) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0 && !_disposed) {
            _received = received;
            _progress = received / total;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }

      if (info.sha256 == null) {
        await file.delete();
        _set(UpdateStage.failed, error: _s().updateNoHash(_sumsAsset));
        return false;
      }

      _set(UpdateStage.verifying);
      final actual = await _hashFile(file);
      if (actual != info.sha256) {
        await file.delete();
        _set(UpdateStage.failed, error: _s().updateHashMismatch);
        return false;
      }

      _set(UpdateStage.ready);
      final opened = await OpenFilex.open(file.path,
          type: 'application/vnd.android.package-archive');
      if (opened.type != ResultType.done) {
        _set(UpdateStage.failed, error: _s().updateInstallerBlocked);
        return false;
      }
      return true;
    } on Object catch (e) {
      // TimeoutException จากเน็ตค้าง / ไฟล์เขียนไม่ได้ / Error จากปลั๊กอิน
      debugPrint('update: โหลดไม่สำเร็จ — $e');
      _set(UpdateStage.failed, error: _s().updateRetry);
      return false;
    }
  }

  Future<void> _sweepOldApks({required String keep}) async {
    try {
      final dir = await getTemporaryDirectory();
      await for (final f in dir.list()) {
        final name = f.uri.pathSegments.isEmpty ? '' : f.uri.pathSegments.last;
        if (f is File &&
            name.startsWith('giggok-') &&
            name.endsWith('.apk') &&
            name != keep) {
          await f.delete();
        }
      }
    } on Object catch (e) {
      debugPrint('update: เก็บกวาด APK เก่าไม่สำเร็จ — $e');
    }
  }

  /// เครื่องนี้ยอมให้แอปเปิดตัวติดตั้ง APK ไหม
  ///
  /// ไม่มีฝั่ง native (เทสต์ / เดสก์ท็อป) ให้ถือว่า**ได้** แล้วไปตายที่ขั้นเปิด
  /// ตัวติดตั้งแทน — เดาว่าไม่ได้จะทำให้เทสต์ที่มีอยู่ล้มโดยไม่ได้มีอะไรพังจริง
  Future<bool> _canInstall() async {
    try {
      return await kSystemChannel.invokeMethod<bool>('canInstall') ?? true;
    } catch (e) {
      debugPrint('update: ถามสิทธิ์ติดตั้งไม่ได้ — $e');
      return true;
    }
  }

  /// อ่านทีละก้อน ไม่โหลดทั้งไฟล์เข้าหน่วยความจำเพื่อคำนวณแฮช
  Future<String> _hashFile(File file) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return output.events.single.toString().toLowerCase();
  }

  /// ล้างบันทึกรุ่นก่อนเอาไปขึ้นจอ
  ///
  /// เนื้อที่ระบบปล่อยไฟล์สร้างให้อัตโนมัติจะมีลิงก์กับชื่อบัญชีของระบบนั้น
  /// ปนมาเสมอ เช่นบรรทัด "Full Changelog: https://…/commits/v0.1.0"
  /// ซึ่งบอกผู้ใช้ตรง ๆ ว่าไฟล์มาจากไหน — และลิงก์ในการ์ดนี้ก็กดไม่ได้อยู่ดี
  ///
  /// 🔴 **ต้องล้างที่ฝั่งแอป ไม่ใช่แค่ฝั่ง CI** — รุ่นที่ปล่อยไปแล้วแก้เนื้อ
  /// ย้อนหลังไม่ได้ และเนื้อ release แก้ด้วยมือทีหลังได้เสมอ ด่านสุดท้าย
  /// จึงต้องอยู่ตรงที่กำลังจะวาดลงจอ
  @visibleForTesting
  static String cleanNotes(String raw) {
    final out = <String>[];

    for (final original in raw.split('\n')) {
      final hadLink = RegExp('https?://').hasMatch(original);

      var line = original
          .replaceAll(RegExp(r'https?://\S+'), '')
          // ชื่อบัญชีของระบบต้นทาง ไม่ใช่ข้อมูลที่ผู้ใช้ต้องรู้
          .replaceAll(RegExp(r'(^|\s)@[\w.-]+'), ' ')
          // มาร์กดาวน์ที่ Text ธรรมดาเรนเดอร์ไม่ได้ จะโผล่เป็นดอกจันเปล่า ๆ
          .replaceAll('**', '')
          .replaceFirst(RegExp(r'^#+\s*'), '')
          .replaceFirst(RegExp(r'^[*-]\s+'), '· ')
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .trim();

      // บรรทัดที่เหลือแต่หัวข้อหลังตัดลิงก์ออก ("Full Changelog:") ไม่ต้องเก็บ
      if (hadLink && (line.isEmpty || line.endsWith(':'))) continue;
      // เหลือแต่เครื่องหมายวรรคตอน ไม่ใช่ข้อความ
      if (line.isEmpty || !RegExp(r'[\w\u0E00-\u0E7F]').hasMatch(line)) {
        continue;
      }
      out.add(line);
    }

    return out.join('\n').trim();
  }

  static String _normalize(String tag) =>
      tag.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '');

  /// เทียบเวอร์ชันแบบตัวเลขทีละส่วน ไม่ใช่เทียบสตริง
  /// ("1.10.0" > "1.9.0" ซึ่งเทียบเป็นสตริงจะได้ผลกลับกัน)
  @visibleForTesting
  static bool isNewer(String candidate, String current) =>
      _isNewer(candidate, current);

  static bool _isNewer(String candidate, String current) {
    if (current.isEmpty) return true;
    final a = _parts(candidate);
    final b = _parts(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static List<int> _parts(String v) {
    // ตัด build metadata ทิ้ง: 1.2.3+45 และ 1.2.3-beta.1 ให้เหลือ 1.2.3
    final core = v.split(RegExp(r'[+\-]')).first;
    final nums = core.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    while (nums.length < 3) {
      nums.add(0);
    }
    return nums;
  }

  @override
  void dispose() {
    _disposed = true;
    _http.close();
    super.dispose();
  }
}
