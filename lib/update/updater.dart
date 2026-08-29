/// อัปเดตตัวเองจาก GitHub Releases ของ xjanova/videogirl
///
/// repo เป็น **public** จึงอ่าน API ได้ตรงโดยไม่ต้องมี token
/// อย่าใส่ GitHub token ลง APK เด็ดขาด — APK แกะได้ ใครก็อ่าน token เจอ
/// ถ้าวันหนึ่งเปลี่ยน repo เป็น private ต้องย้ายไปให้เซิร์ฟเวอร์อ่านแทน
/// แล้วให้แอปคุยกับเซิร์ฟเวอร์ ไม่ใช่ยัด token ลงเครื่องผู้ใช้
library;

import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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

class Updater extends ChangeNotifier {
  Updater({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;
  bool _disposed = false;

  UpdateStage _stage = UpdateStage.idle;
  UpdateStage get stage => _stage;

  UpdateInfo? _pending;
  UpdateInfo? get pending => _pending;

  double _progress = 0;
  double get progress => _progress;

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
    _set(UpdateStage.checking);
    try {
      final info = await PackageInfo.fromPlatform();
      _current = info.version;

      final res = await _http.get(
        Uri.parse(_releaseApi),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 404) {
        _set(UpdateStage.idle);
        return null; // ยังไม่เคยออก release เลย ไม่ใช่ error
      }
      if (res.statusCode >= 400) {
        _set(UpdateStage.failed, error: 'เช็ครุ่นใหม่ไม่ได้ (${res.statusCode})');
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
        _set(UpdateStage.failed, error: 'release นี้ไม่มีไฟล์ APK แนบมา');
        return null;
      }

      final apkName = '${apk['name']}';
      _pending = UpdateInfo(
        version: latest,
        notes: '${json['body'] ?? ''}'.trim(),
        apkUrl: '${apk['browser_download_url']}',
        apkName: apkName,
        sizeBytes: (apk['size'] as num?)?.toInt() ?? 0,
        sha256: await _fetchExpectedHash(assets, apkName),
      );

      _set(UpdateStage.available);
      return _pending;
    } on Exception {
      _set(UpdateStage.failed, error: 'ต่อ GitHub ไม่ได้');
      return null;
    }
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

    _progress = 0;
    _set(UpdateStage.downloading);

    try {
      final req = http.Request('GET', Uri.parse(info.apkUrl));
      final res = await _http.send(req).timeout(const Duration(seconds: 60));
      if (res.statusCode >= 400) {
        _set(UpdateStage.failed, error: 'ดาวน์โหลดไม่สำเร็จ (${res.statusCode})');
        return false;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}${info.apkName}');
      final sink = file.openWrite();
      final total = res.contentLength ?? info.sizeBytes;
      var received = 0;

      // สตรีมลงไฟล์ ไม่ buffer ทั้งก้อนในหน่วยความจำ APK หลายสิบเมกจะทำให้แอปตาย
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0 && !_disposed) {
          _progress = received / total;
          notifyListeners();
        }
      }
      await sink.close();

      if (info.sha256 == null) {
        await file.delete();
        _set(UpdateStage.failed,
            error: 'release นี้ไม่มี $_sumsAsset จึงตรวจไฟล์ไม่ได้ ยกเลิกเพื่อความปลอดภัย');
        return false;
      }

      _set(UpdateStage.verifying);
      final actual = await _hashFile(file);
      if (actual != info.sha256) {
        await file.delete();
        _set(UpdateStage.failed, error: 'ไฟล์ที่โหลดมาไม่ตรงกับที่ประกาศไว้ ยกเลิกแล้ว');
        return false;
      }

      _set(UpdateStage.ready);
      final opened = await OpenFilex.open(file.path,
          type: 'application/vnd.android.package-archive');
      if (opened.type != ResultType.done) {
        _set(UpdateStage.failed,
            error: 'เปิดตัวติดตั้งไม่ได้ — ต้องอนุญาต "ติดตั้งแอปที่ไม่รู้จัก" ให้แอปนี้ก่อน');
        return false;
      }
      return true;
    } on Exception {
      _set(UpdateStage.failed, error: 'ดาวน์โหลดไม่สำเร็จ ลองใหม่อีกครั้งนะคะ');
      return false;
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
