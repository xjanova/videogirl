import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// เซิร์ฟเวอร์โมเดลที่เจอในวงไวไฟ (หรือในเครื่องเองผ่าน Termux)
class LocalServer {
  const LocalServer({
    required this.host,
    required this.port,
    required this.kind,
    required this.models,
  });

  final String host;
  final int port;

  /// โปรแกรมที่น่าจะเป็น (เดาจากพอร์ตมาตรฐาน) · ไว้โชว์ให้คนอ่านรู้เรื่อง
  final String kind;

  /// รุ่นที่เซิร์ฟเวอร์บอกว่ามี (`GET /v1/models`)
  final List<String> models;

  /// ที่อยู่แบบที่แอปใช้ (เข้ากันได้กับ OpenAI)
  String get baseUrl => 'http://$host:$port/v1';
}

/// หาเซิร์ฟเวอร์โมเดลในวงไวไฟเดียวกัน — Ollama · LM Studio · llama.cpp · vLLM · Jan
///
/// ## ทำงานยังไง
///
/// 1. อ่าน IPv4 ของเครื่องเอง (เฉพาะวงส่วนตัว 10.x / 172.16–31.x / 192.168.x)
///    แล้วไล่ทั้งวง /24 (254 เครื่อง) + 127.0.0.1 (Ollama ใน Termux บนมือถือเอง)
/// 2. ลองเปิดพอร์ตมาตรฐานของแต่ละโปรแกรมแบบสั้น ๆ (ไม่ส่งข้อมูลอะไรเลย)
/// 3. พอร์ตที่เปิด → ถาม `GET /v1/models` ยืนยันว่าเป็นเซิร์ฟเวอร์โมเดลจริง
///    และได้รายชื่อรุ่นมาให้แตะเลือก ไม่ต้องพิมพ์
///
/// ไม่ส่งบทสนทนาหรือข้อมูลของผู้ใช้ออกไประหว่างค้นหา · ไม่แตะวงที่ไม่ใช่วงส่วนตัว
class LocalServerScanner {
  LocalServerScanner({
    http.Client? client,
    Future<List<String>> Function()? localIps,
    Future<bool> Function(String host, int port)? probe,
    this.connectTimeout = const Duration(milliseconds: 400),
    this.parallel = 96,
  })  : _http = client ?? http.Client(),
        _localIps = localIps ?? _ownIps,
        _probe = probe;

  final http.Client _http;
  final Future<List<String>> Function() _localIps;
  final Future<bool> Function(String host, int port)? _probe;
  final Duration connectTimeout;

  /// เปิดพร้อมกันได้กี่ช่อง · มากไปเราเตอร์บางรุ่นตัดทิ้ง น้อยไปช้า
  final int parallel;

  /// พอร์ตมาตรฐาน → ชื่อโปรแกรม
  static const ports = {
    11434: 'Ollama',
    1234: 'LM Studio',
    8080: 'llama.cpp',
    8000: 'vLLM',
    1337: 'Jan',
  };

  /// วงส่วนตัวเท่านั้น · ไม่ไล่ IP สาธารณะของใครเด็ดขาด
  @visibleForTesting
  static bool isPrivate(String ip) {
    final p = ip.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.any((e) => e == null)) return false;
    final a = p[0]!, b = p[1]!;
    return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
  }

  /// ที่อยู่ที่จะไล่ทั้งหมด · วง /24 ของทุก IP ส่วนตัวของเครื่อง + 127.0.0.1
  @visibleForTesting
  static List<String> targets(List<String> own) {
    final out = <String>{'127.0.0.1'};
    for (final ip in own.where(isPrivate)) {
      final base = ip.substring(0, ip.lastIndexOf('.'));
      for (var i = 1; i < 255; i++) {
        final h = '$base.$i';
        if (h != ip) out.add(h);
      }
    }
    return out.toList();
  }

  /// การ์ดเครือข่ายที่เป็นวงในบ้านจริง (ไวไฟ · สาย LAN · ฮอตสปอต · USB)
  ///
  /// 🔴 **ไม่ไล่วงของเน็ตมือถือ** · ค่ายมือถือแจก 10.x ให้เครื่อง (CGNAT) ซึ่งดู
  /// เป็นวงส่วนตัว แต่เพื่อนบ้านในวงนั้นคือลูกค้าคนอื่นของค่าย ไม่ใช่คอมของเรา
  /// · VPN (tun) ก็เช่นกัน · ใช้รายชื่อที่อนุญาต ไม่ใช่รายชื่อที่ห้าม
  /// เพราะชื่อการ์ดเน็ตมือถือมีหลายสิบแบบตามผู้ผลิต
  @visibleForTesting
  static bool isLanInterface(String name) {
    final n = name.toLowerCase();
    const lan = ['wlan', 'swlan', 'ap', 'eth', 'en', 'wl', 'wifi', 'wi-fi', 'ethernet', 'rndis', 'bt-pan'];
    const notLan = ['rmnet', 'ccmni', 'pdp', 'tun', 'ppp', 'wwan', 'clat', 'v4-', 'dummy', 'ipsec'];
    if (notLan.any(n.contains)) return false;
    return lan.any(n.startsWith);
  }

  static Future<List<String>> _ownIps() async {
    try {
      final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return [
        for (final i in list)
          if (isLanInterface(i.name))
            for (final a in i.addresses)
              if (!a.isLoopback) a.address,
      ];
    } on Object catch (e) {
      debugPrint('ค้นเซิร์ฟเวอร์: อ่าน IP ของเครื่องไม่ได้ — ${e.runtimeType}');
      return const [];
    }
  }

  Future<bool> _open(String host, int port) async {
    final p = _probe;
    if (p != null) return p(host, port);
    try {
      final s = await Socket.connect(host, port, timeout: connectTimeout);
      s.destroy();
      return true;
    } on Object {
      return false;
    }
  }

  /// ไล่หา · [onProgress] 0..1 · คืนรายการที่ยืนยันแล้วว่าเป็นเซิร์ฟเวอร์โมเดลจริง
  Future<List<LocalServer>> scan({void Function(double)? onProgress}) async {
    final hosts = targets(await _localIps());
    final jobs = [
      for (final h in hosts)
        for (final port in ports.keys) (h, port),
    ];
    final open = <(String, int)>[];
    var done = 0;
    for (var i = 0; i < jobs.length; i += parallel) {
      final batch = jobs.sublist(i, (i + parallel).clamp(0, jobs.length));
      final hits = await Future.wait(batch.map((j) async => await _open(j.$1, j.$2) ? j : null));
      open.addAll(hits.whereType<(String, int)>());
      done += batch.length;
      onProgress?.call(done / jobs.length);
    }

    final found = <LocalServer>[];
    for (final (host, port) in open) {
      final models = await this.models('http://$host:$port/v1');
      if (models == null) continue; // พอร์ตเปิดแต่ไม่ใช่เซิร์ฟเวอร์โมเดล
      found.add(LocalServer(host: host, port: port, kind: ports[port]!, models: models));
    }
    found.sort((a, b) => a.host == '127.0.0.1' ? -1 : b.host == '127.0.0.1' ? 1 : a.host.compareTo(b.host));
    return found;
  }

  /// รายชื่อรุ่นบนเซิร์ฟเวอร์ · null = ไม่ใช่เซิร์ฟเวอร์โมเดล / ติดต่อไม่ได้
  Future<List<String>?> models(String baseUrl) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final res = await _http
          .get(Uri.parse('$base/models'), headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      final data = j is Map ? j['data'] : null;
      if (data is! List) return null;
      return [
        for (final m in data)
          if (m is Map && m['id'] is String && (m['id'] as String).isNotEmpty) m['id'] as String,
      ];
    } on Object {
      return null;
    }
  }

  void close() => _http.close();
}
