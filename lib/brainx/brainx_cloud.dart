/// สมองก้อนเดียวกับมายด์บนคอม — BrainX Cloud
///
/// ## ทำไม
///
/// เจ้าของสั่ง: มายด์ของ BrainX บนคอมที่ขึ้นคลาวด์แล้ว ต้องเชื่อมกับแอปนี้ด้วย
/// "จะคุยเรื่องเดียวกันจำได้หมด" · และ "ไม่ต้องกลัวว่าถอนแล้วจะลืมที่คุยกัน
/// จีบกันไว้" · บัญชี xman เดียวกัน = คีย์เดียวกัน = ที่เก็บเดียวกัน จึงไม่ต้อง
/// จ่ายซ้ำ (หลังบ้านส่งคีย์ BrainX ของบัญชีที่ผูกเครื่องให้เอง — `GET /api/ai/v1/brainx`)
///
/// ## ใช้อะไรของคลาวด์ (BrainX.Server · สัญญา cloud v1)
///
/// - `POST /api/cloud/login {licenseKey, deviceName}` → token `bxc_…` ของเครื่องนี้
///   (คลาวด์รับเฉพาะคีย์แบบจ่ายเงิน รายเดือน/รายปี/ตลอดชีพ)
/// - `POST /mcp` (MCP ผ่าน HTTP) → `brain_search` ค้นทั้งสมอง ทั้งโน้ตของเจ้าของ
///   และบทสนทนากับมายด์บนคอม · ตัวจัดอันดับของ BrainX เอง ไม่ใช่ของแอป
/// - `POST /api/cloud/notes` → ส่งความจำ/บทสนทนา/ความสัมพันธ์ของมือถือขึ้นไป
/// - `POST /api/cloud/notes/fetch` → ดึงกลับ (ลงแอปใหม่ · สิ่งที่มายด์บนคอมจดไว้)
///
/// 🔴 token อยู่แค่ใน header · ไม่ลง log ไม่ลงข้อความผิดพลาด (เหมือน CloudApiClient ของ BrainX)
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// ที่ตั้งของคลาวด์ (ตายตัว เหมือนในโปรแกรม BrainX · บริการที่เก็บเงินต้องรู้ที่อยู่ตัวเอง)
const kBrainXCloudUrl = 'https://serverbrain.xman4289.com';

/// โฟลเดอร์ในสมองที่มายด์สองฝั่งใช้ร่วมกัน · ต้องตรงกับฝั่ง BrainX (AssistantService)
abstract final class MindPaths {
  /// สิ่งที่มายด์บนคอมสังเกตเห็นเกี่ยวกับเจ้าของ (เขียนโดยฝั่งคอม)
  static const ownerProfile = 'Mind/owner-profile.md';

  /// ความจำที่มือถือสกัดได้ (เขียนทับทั้งไฟล์ทุกครั้ง)
  static const phoneMemory = 'Mind/Phone/memory.md';

  /// ความสัมพันธ์ (ความผูกพัน คบกันไหม งอนอยู่ไหม ชื่อที่ตั้งให้เธอ)
  static const phoneSoul = 'Mind/Phone/relationship.md';

  /// บทสนทนาบนมือถือ วันละไฟล์
  static String phoneDay(DateTime d) => 'Mind/Conversations/${day(d)} phone.md';

  /// บทสนทนาบนคอม วันละไฟล์ (เขียนโดยฝั่งคอม)
  static String pcDay(DateTime d) => 'Mind/Conversations/${day(d)} pc.md';

  static String day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// บัญชีคลาวด์ (จาก /api/cloud/account)
@immutable
class BrainXAccount {
  const BrainXAccount({
    required this.licenseType,
    required this.isValid,
    required this.daysRemaining,
    required this.usedBytes,
    required this.quotaBytes,
    required this.noteCount,
  });

  final String licenseType;
  final bool isValid;
  final int? daysRemaining;
  final int usedBytes;
  final int quotaBytes;
  final int noteCount;

  static BrainXAccount fromJson(Map<String, Object?> j) => BrainXAccount(
        licenseType: '${j['licenseType'] ?? ''}',
        isValid: j['isValid'] == true,
        daysRemaining: (j['daysRemaining'] as num?)?.toInt(),
        usedBytes: (j['usedBytes'] as num?)?.toInt() ?? 0,
        quotaBytes: (j['quotaBytes'] as num?)?.toInt() ?? 0,
        noteCount: (j['noteCount'] as num?)?.toInt() ?? 0,
      );
}

/// หนึ่งผลค้นจากสมอง
@immutable
class BrainXHit {
  const BrainXHit({required this.title, required this.text, this.path});
  final String title;

  /// ข้อความรอบจุดที่ตรง (matchContext) หรือต้นโน้ต (preview)
  final String text;
  final String? path;
}

/// เหตุที่คลาวด์ปฏิเสธ · รหัสตรงกับ error.code ของสัญญา cloud v1
class BrainXCloudError implements Exception {
  const BrainXCloudError(this.code, {this.status});
  final String code;
  final int? status;

  /// token ใช้ไม่ได้แล้ว (ถูกเพิกถอน · ออกจากระบบที่อื่น) → ต้องล็อกอินใหม่
  bool get needsLogin => code == 'UNAUTHORIZED';

  /// ไลเซนส์หมดอายุ → ต่ออายุ (โน้ตยังอ่านได้ แต่เขียน/ค้นผ่าน /mcp ไม่ได้)
  bool get expired => code == 'LICENSE_EXPIRED';

  @override
  String toString() => 'BrainXCloudError($code, $status)';
}

class BrainXCloud {
  BrainXCloud({http.Client? client, String baseUrl = kBrainXCloudUrl})
      : _http = client ?? http.Client(),
        _base = baseUrl.replaceAll(RegExp(r'/+$'), '');

  final http.Client _http;
  final String _base;

  static const _timeout = Duration(seconds: 20);

  Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        'User-Agent': 'GigGok-BrainX/1',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, Object?>> _send(String method, String path,
      {String? token, Object? body, Duration timeout = _timeout}) async {
    final uri = Uri.parse('$_base$path');
    final http.Response res;
    try {
      res = await (method == 'GET'
              ? _http.get(uri, headers: _headers(token))
              : _http.post(uri,
                  headers: _headers(token), body: body == null ? null : utf8.encode(jsonEncode(body))))
          .timeout(timeout);
    } on Object {
      throw const BrainXCloudError('OFFLINE');
    }
    Object? j;
    try {
      j = res.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      j = null;
    }
    if (res.statusCode >= 400) {
      final code = j is Map && j['code'] is String ? j['code'] as String : 'HTTP_${res.statusCode}';
      throw BrainXCloudError(code, status: res.statusCode);
    }
    return j is Map ? j.cast<String, Object?>() : const {};
  }

  /// แลกคีย์ BrainX เป็น token ของเครื่องนี้
  Future<({String token, BrainXAccount account})> login(String key, {required String device}) async {
    final j = await _send('POST', '/api/cloud/login', body: {'licenseKey': key.trim(), 'deviceName': device});
    final token = j['token'];
    if (token is! String || token.isEmpty) throw const BrainXCloudError('BAD_RESPONSE');
    final acct = j['account'];
    return (
      token: token,
      account: BrainXAccount.fromJson(acct is Map ? acct.cast<String, Object?>() : const {}),
    );
  }

  Future<BrainXAccount> account(String token) async =>
      BrainXAccount.fromJson(await _send('GET', '/api/cloud/account', token: token));

  Future<void> logout(String token) async {
    try {
      await _send('POST', '/api/cloud/logout', token: token, body: const {});
    } on BrainXCloudError {
      // ออกจากระบบไม่สำเร็จฝั่งคลาวด์ ก็ยังลบ token ในเครื่องทิ้งอยู่ดี
    }
  }

  /// sha256 ตามสัญญา: ฐานสิบหกตัวเล็กของไบต์ UTF-8 ของข้อความตรงตัว
  static String sha(String content) => sha256.convert(utf8.encode(content)).toString();

  /// เขียนโน้ตขึ้นสมอง (ทับของเดิมที่ path เดียวกัน)
  Future<void> upload(String token, Map<String, String> files) async {
    if (files.isEmpty) return;
    await _send('POST', '/api/cloud/notes', token: token, timeout: const Duration(seconds: 45), body: {
      'files': [
        for (final e in files.entries) {'path': e.key, 'content': e.value, 'sha256': sha(e.value)},
      ],
    });
  }

  /// อ่านโน้ตตาม path · ที่ไม่มีอยู่จะไม่อยู่ในผลลัพธ์
  Future<Map<String, String>> fetch(String token, List<String> paths) async {
    if (paths.isEmpty) return const {};
    final j = await _send('POST', '/api/cloud/notes/fetch', token: token, body: {'paths': paths});
    final out = <String, String>{};
    for (final f in (j['files'] is List ? j['files'] as List : const [])) {
      if (f is Map && f['path'] is String && f['content'] is String) {
        out[f['path'] as String] = f['content'] as String;
      }
    }
    return out;
  }

  /// path ทั้งหมดในสมอง (ใช้หาบทสนทนาย้อนหลังตอนกู้คืน)
  Future<List<String>> manifest(String token) async {
    final j = await _send('GET', '/api/cloud/manifest', token: token, timeout: const Duration(seconds: 30));
    return [
      for (final f in (j['files'] is List ? j['files'] as List : const []))
        if (f is Map && f['path'] is String) f['path'] as String,
    ];
  }

  // ── ค้นสมองผ่าน /mcp ─────────────────────────────────────

  String? _session;
  String? _sessionToken;
  int _rpc = 0;

  Future<(Map<String, Object?>, String?)> _mcp(String token, Map<String, Object?> msg,
      {String? session, Duration timeout = const Duration(seconds: 8)}) async {
    final http.Response res;
    try {
      res = await _http
          .post(Uri.parse('$_base/mcp'),
              headers: {
                ..._headers(token),
                'Accept': 'application/json, text/event-stream',
                'Mcp-Session-Id': ?session,
              },
              body: utf8.encode(jsonEncode(msg)))
          .timeout(timeout);
    } on Object {
      throw const BrainXCloudError('OFFLINE');
    }
    Object? j;
    try {
      j = res.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      j = null;
    }
    if (res.statusCode >= 400) {
      // /mcp ส่งรหัสของคลาวด์มาใน error.data.code (LICENSE_EXPIRED ฯลฯ)
      final err = j is Map ? j['error'] : null;
      final data = err is Map ? err['data'] : null;
      final code = data is Map && data['code'] is String
          ? data['code'] as String
          : switch (res.statusCode) {
              401 => 'UNAUTHORIZED',
              402 => 'LICENSE_EXPIRED',
              404 => 'SESSION_GONE',
              _ => 'HTTP_${res.statusCode}',
            };
      throw BrainXCloudError(code, status: res.statusCode);
    }
    return (j is Map ? j.cast<String, Object?>() : <String, Object?>{}, res.headers['mcp-session-id']);
  }

  Future<String> _openSession(String token) async {
    if (_session != null && _sessionToken == token) return _session!;
    final (_, sid) = await _mcp(token, {
      'jsonrpc': '2.0',
      'id': ++_rpc,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2025-06-18',
        'capabilities': <String, Object?>{},
        'clientInfo': {'name': 'giggok', 'version': '1'},
      },
    });
    if (sid == null || sid.isEmpty) throw const BrainXCloudError('NO_SESSION');
    // แจ้งว่าพร้อมแล้ว (ตอบ 202 ไม่มีเนื้อ)
    await _mcp(token, {'jsonrpc': '2.0', 'method': 'notifications/initialized'}, session: sid);
    _session = sid;
    _sessionToken = token;
    return sid;
  }

  /// ค้นสมอง · เวลาจำกัดสั้นโดยตั้งใจ — เธอรอคำตอบอยู่ ค้นไม่ทันก็ตอบจากที่มี
  Future<List<BrainXHit>> search(String token, String query, {int limit = 4}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final sid = await _openSession(token);
      try {
        final (j, _) = await _mcp(
          token,
          {
            'jsonrpc': '2.0',
            'id': ++_rpc,
            'method': 'tools/call',
            'params': {
              'name': 'brain_search',
              'arguments': {'query': query, 'limit': limit, 'preview_chars': 400},
            },
          },
          session: sid,
        );
        return parseSearch(j);
      } on BrainXCloudError catch (e) {
        // session หมดอายุ/ถูกปิด → เปิดใหม่หนึ่งรอบ
        if (e.code == 'SESSION_GONE' && attempt == 0) {
          _session = null;
          continue;
        }
        rethrow;
      }
    }
    return const [];
  }

  /// ผลของ tools/call brain_search → รายการอ่านง่าย · ผลเป็น JSON ใน content[0].text
  @visibleForTesting
  static List<BrainXHit> parseSearch(Map<String, Object?> rpc) {
    final result = rpc['result'];
    final content = result is Map ? result['content'] : null;
    if (content is! List || content.isEmpty) return const [];
    final text = (content.first as Map?)?['text'];
    if (text is! String) return const [];
    Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      return const [];
    }
    final rows = j is Map ? j['results'] : null;
    if (rows is! List) return const [];
    return [
      for (final r in rows.whereType<Map>())
        if ('${r['title'] ?? ''}'.isNotEmpty)
          BrainXHit(
            title: '${r['title']}',
            text: '${r['matchContext'] ?? r['preview'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim(),
            path: r['path'] as String?,
          ),
    ];
  }

  void close() => _http.close();
}
