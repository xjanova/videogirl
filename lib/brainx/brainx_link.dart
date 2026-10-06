/// การเชื่อมสมองก้อนเดียวกับมายด์บนคอม — สถานะ · ค้น · ทยอยส่งขึ้น · กู้คืน
///
/// ดู [BrainXCloud] ว่าทำไมและใช้อะไรของคลาวด์ · ตัวนี้คือส่วนที่แอปจับต้อง:
///
/// - **เชื่อม** ด้วยบัญชี xman ที่ผูกเครื่องไว้ (หลังบ้านส่งคีย์ BrainX ของบัญชีมาให้)
///   หรือใส่คีย์เอง · ไม่มี BrainX Cloud = บอกให้สมัคร (มือถือเชื่อมฟรีเมื่อจ่ายฝั่งคอมแล้ว)
/// - **ค้น** ทุกครั้งที่ตอบ — เวลาจำกัดสั้น ค้นไม่ทันก็ตอบจากที่มี
/// - **ส่งขึ้น** ความจำ บทสนทนา (วันละไฟล์) และความสัมพันธ์ · รวมเป็นชุดแล้วค่อยส่ง
///   ไม่ยิงทุกข้อความ
/// - **กู้คืน** ลงแอปใหม่ → ดึงทั้งหมดกลับ
///
/// 🔴 **สายโทรศัพท์ไม่แตะตัวนี้เลย** (บังคับด้วยโค้ด ไม่ใช่ prompt) · คนแปลกหน้า
/// ในสายต้องไม่มีทางทำให้เธอค้นหรืออ่านสมองของเจ้าของ
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../ai/secret_store.dart';
import '../memory/mind_memory.dart';
import 'brainx_cloud.dart';

enum BrainXState {
  /// ยังไม่ได้เชื่อม
  off,
  connecting,
  connected,

  /// เครื่องยังไม่ได้ผูกบัญชี xman
  notLinked,

  /// บัญชีนี้ยังไม่มี BrainX Cloud ที่ใช้งานอยู่
  notSubscribed,

  /// BrainX Cloud หมดอายุ (โน้ตยังอยู่ ต่ออายุแล้วกลับมาเหมือนเดิม)
  expired,

  /// เชื่อมไม่สำเร็จด้วยเหตุอื่น (เน็ต · คลาวด์ขัดข้อง) · ดู [BrainXLink.error]
  failed,
}

/// หนึ่งบรรทัดของบทสนทนาที่ส่งขึ้น/กู้กลับ
typedef DayLine = ({DateTime at, bool fromHer, String text});

/// ความจำหนึ่งข้อที่ส่งขึ้น/กู้กลับ
typedef CloudFact = ({MemoryKind kind, String text, bool pinned});

/// ของที่กู้กลับมาได้จากสมอง
typedef BrainXBackup = ({
  List<CloudFact> facts,
  Map<String, Object?>? soul,
  List<DayLine> lines,
});

class BrainXLink extends ChangeNotifier {
  BrainXLink({
    BrainXCloud? cloud,
    http.Client? xman,
    Future<String> Function(String key)? readSecret,
    Future<bool> Function(String key, String value)? writeSecret,
    DateTime Function()? clock,
    this.deviceName = 'GigGok (Android)',
    this.flushDelay = const Duration(seconds: 20),
  })  : _cloud = cloud ?? BrainXCloud(),
        _xman = xman ?? http.Client(),
        _read = readSecret ?? SecretStore.read,
        _write = writeSecret ?? SecretStore.write,
        _clock = clock ?? DateTime.now;

  final BrainXCloud _cloud;
  final http.Client _xman;
  final Future<String> Function(String) _read;
  final Future<bool> Function(String, String) _write;
  final DateTime Function() _clock;
  final String deviceName;
  final Duration flushDelay;

  BrainXState _state = BrainXState.off;
  BrainXState get state => _state;

  bool get connected => _state == BrainXState.connected && _token.isNotEmpty;

  BrainXAccount? _account;
  BrainXAccount? get account => _account;

  /// รหัสเหตุผลล่าสุด (สำหรับ [BrainXState.failed]) · หน้าจอแปลเป็นภาษาคนเอง
  String? _error;
  String? get error => _error;

  String _buyUrl = 'https://xman4289.com/products/brainx';
  String get buyUrl => _buyUrl;

  String _token = '';
  String _key = '';
  bool _disposed = false;

  void _set(BrainXState s, {String? error}) {
    _state = s;
    _error = error;
    if (!_disposed) notifyListeners();
  }

  /// อ่าน token ที่เคยได้ · ไม่ยิงเน็ต (ตรวจกับคลาวด์ทีหลังใน [refreshAccount])
  Future<void> load() async {
    _token = await _read(SecretStore.kBrainXToken);
    _key = await _read(SecretStore.kBrainXKey);
    if (_token.isNotEmpty) _set(BrainXState.connected);
  }

  /// เชื่อมด้วยบัญชี xman ที่ผูกเครื่องนี้ไว้ — ไม่ต้องพิมพ์คีย์
  Future<void> connectViaXman({required String storeBase, required String license}) async {
    if (_state == BrainXState.connecting) return;
    _set(BrainXState.connecting);
    final base = storeBase.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty || license.trim().isEmpty) {
      _set(BrainXState.notLinked);
      return;
    }
    Map<String, Object?> j;
    try {
      final res = await _xman.get(Uri.parse('$base/api/ai/v1/brainx'), headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${license.trim()}',
      }).timeout(const Duration(seconds: 15));
      if (res.statusCode == 401) {
        _set(BrainXState.failed, error: 'LICENSE');
        return;
      }
      if (res.statusCode != 200) {
        _set(BrainXState.failed, error: 'HTTP_${res.statusCode}');
        return;
      }
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      j = d is Map ? d.cast<String, Object?>() : const {};
    } on Object {
      _set(BrainXState.failed, error: 'OFFLINE');
      return;
    }
    if (j['buy_url'] is String) _buyUrl = j['buy_url'] as String;
    if (j['linked'] != true) {
      _set(BrainXState.notLinked);
      return;
    }
    final key = j['key'];
    if (j['active'] != true || key is! String || key.isEmpty) {
      _set(BrainXState.notSubscribed);
      return;
    }
    await connectWithKey(key);
  }

  /// เชื่อมด้วยคีย์ BrainX (มาจากหลังบ้าน หรือผู้ใช้ใส่เอง)
  Future<void> connectWithKey(String key) async {
    _set(BrainXState.connecting);
    try {
      final r = await _cloud.login(key, device: deviceName);
      _token = r.token;
      _key = key.trim();
      _account = r.account;
      await _write(SecretStore.kBrainXToken, _token);
      await _write(SecretStore.kBrainXKey, _key);
      _set(r.account.isValid ? BrainXState.connected : BrainXState.expired);
    } on BrainXCloudError catch (e) {
      _set(switch (e.code) {
        'LICENSE_EXPIRED' => BrainXState.expired,
        'INVALID_LICENSE' => BrainXState.notSubscribed,
        _ => BrainXState.failed,
      }, error: e.code);
    }
  }

  Future<void> disconnect() async {
    final t = _token;
    _token = '';
    _key = '';
    _account = null;
    _pending.clear();
    _flushTimer?.cancel();
    await _write(SecretStore.kBrainXToken, '');
    await _write(SecretStore.kBrainXKey, '');
    _set(BrainXState.off);
    if (t.isNotEmpty) unawaited(_cloud.logout(t));
  }

  /// token ถูกเพิกถอน (ออกจากระบบจากคอม · ครบจำนวนเครื่อง) → ล็อกอินใหม่เองด้วยคีย์เดิม
  Future<bool> _relogin() async {
    if (_key.isEmpty) return false;
    try {
      final r = await _cloud.login(_key, device: deviceName);
      _token = r.token;
      _account = r.account;
      await _write(SecretStore.kBrainXToken, _token);
      return true;
    } on BrainXCloudError catch (e) {
      if (e.expired) _set(BrainXState.expired, error: e.code);
      return false;
    }
  }

  /// เรียกงานกับคลาวด์ · token หลุด = ล็อกอินใหม่หนึ่งรอบแล้วลองซ้ำ
  Future<T?> _guard<T>(Future<T> Function(String token) job) async {
    if (_token.isEmpty) return null;
    try {
      return await job(_token);
    } on BrainXCloudError catch (e) {
      if (e.needsLogin && await _relogin()) {
        try {
          return await job(_token);
        } on BrainXCloudError catch (e2) {
          _onError(e2);
          return null;
        }
      }
      _onError(e);
      return null;
    }
  }

  void _onError(BrainXCloudError e) {
    if (e.expired) {
      _set(BrainXState.expired, error: e.code);
    } else if (e.needsLogin) {
      _set(BrainXState.failed, error: e.code);
    }
    // อย่างอื่น (เน็ตหลุดชั่วคราว) ไม่เปลี่ยนสถานะ · ครั้งหน้าลองใหม่เอง
  }

  Future<void> refreshAccount() async {
    final a = await _guard(_cloud.account);
    if (a == null) return;
    _account = a;
    _set(a.isValid ? BrainXState.connected : BrainXState.expired);
  }

  // ── ค้น ───────────────────────────────────────────────

  /// ค้นสมองสำหรับคำตอบตานี้ · เกิน [limit] = ตอบจากที่มีไปก่อน
  Future<List<BrainXHit>> recall(String query,
      {Duration limit = const Duration(seconds: 3)}) async {
    if (!connected || query.trim().isEmpty) return const [];
    try {
      return await (_guard((t) => _cloud.search(t, query)).then((v) => v ?? const <BrainXHit>[]))
          .timeout(limit, onTimeout: () => const <BrainXHit>[]);
    } on Object catch (e) {
      debugPrint('brainx: ค้นไม่สำเร็จ — ${e.runtimeType}');
      return const [];
    }
  }

  /// สิ่งที่มายด์บนคอมสังเกตเห็นเกี่ยวกับเจ้าของ (`Mind/owner-profile.md`)
  String _ownerProfile = '';
  String get ownerProfile => _ownerProfile;
  DateTime? _profileAt;

  /// ดึงใหม่ไม่บ่อยกว่าทุก 30 นาที · เปลี่ยน system prompt บ่อย = สมองในเครื่องช้า
  Future<void> refreshOwnerProfile({bool force = false}) async {
    if (!connected) return;
    final now = _clock();
    if (!force && _profileAt != null && now.difference(_profileAt!) < const Duration(minutes: 30)) return;
    _profileAt = now;
    final got = await _guard((t) => _cloud.fetch(t, const [MindPaths.ownerProfile]));
    final text = got?[MindPaths.ownerProfile]?.trim() ?? '';
    if (text != _ownerProfile) {
      _ownerProfile = text;
      if (!_disposed) notifyListeners();
    }
  }

  // ── ส่งขึ้น (รวมเป็นชุด) ───────────────────────────────

  final Map<String, String> _pending = {};
  Timer? _flushTimer;

  /// ไฟล์นี้จะถูกส่งขึ้นในรอบถัดไป · ส่งไฟล์เดิมซ้ำก่อนรอบ = เอาเวอร์ชันล่าสุด
  void queue(String path, String content) {
    if (!connected) return;
    _pending[path] = content;
    _flushTimer?.cancel();
    _flushTimer = Timer(flushDelay, () => unawaited(flush()));
  }

  @visibleForTesting
  Map<String, String> get debugPending => Map.unmodifiable(_pending);

  Future<void> flush() async {
    if (_pending.isEmpty || !connected) return;
    final batch = Map<String, String>.of(_pending);
    _pending.clear();
    final ok = await _guard((t) => _cloud.upload(t, batch).then((_) => true));
    if (ok != true) {
      // ส่งไม่ผ่าน = คืนเข้าคิว (เวอร์ชันใหม่กว่าที่เข้ามาระหว่างนั้นชนะ)
      for (final e in batch.entries) {
        _pending.putIfAbsent(e.key, () => e.value);
      }
    }
  }

  // ── กู้คืน ─────────────────────────────────────────────

  /// ดึงของมือถือกลับจากสมอง · [days] = บทสนทนาย้อนหลังกี่วัน
  Future<BrainXBackup?> fetchBackup({int days = 60}) async {
    return _guard((t) async {
      final all = await _cloud.manifest(t);
      final since = _clock().subtract(Duration(days: days));
      final dayFiles = [
        for (final p in all)
          if (_phoneDayDate(p) case final d? when !d.isBefore(DateTime(since.year, since.month, since.day))) p,
      ]..sort();
      final want = [
        if (all.contains(MindPaths.phoneMemory)) MindPaths.phoneMemory,
        if (all.contains(MindPaths.phoneSoul)) MindPaths.phoneSoul,
        ...dayFiles,
      ];
      final got = <String, String>{};
      for (var i = 0; i < want.length; i += 150) {
        got.addAll(await _cloud.fetch(t, want.sublist(i, (i + 150).clamp(0, want.length))));
      }
      final lines = <DayLine>[];
      for (final p in dayFiles) {
        final d = _phoneDayDate(p)!;
        lines.addAll(parseDay(got[p] ?? '', d));
      }
      return (
        facts: parseMemory(got[MindPaths.phoneMemory] ?? ''),
        soul: parseSoul(got[MindPaths.phoneSoul] ?? ''),
        lines: lines,
      );
    });
  }

  static final _phoneDay = RegExp(r'^Mind/Conversations/(\d{4})-(\d{2})-(\d{2}) phone\.md$');

  static DateTime? _phoneDayDate(String path) {
    final m = _phoneDay.firstMatch(path);
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  // ── รูปแบบไฟล์ (อ่านได้ทั้งคน ทั้ง Obsidian และมายด์บนคอม · แยกกลับได้) ──

  static String renderMemory(Iterable<MemoryFact> facts) {
    final b = StringBuffer()
      ..writeln("# Mind's memory — phone")
      ..writeln()
      ..writeln('_Written by the GigGok app every time she learns something. '
          'Edit or delete in the app (Settings > Memory), not here — the app rewrites this file._')
      ..writeln();
    for (final f in facts) {
      b.writeln('- [${f.kind.name}] ${f.text.replaceAll('\n', ' ')}${f.pinned ? ' 📌' : ''}');
    }
    return b.toString();
  }

  static final _factLine = RegExp(r'^- \[(\w+)\] (.+?)( 📌)?$');

  static List<CloudFact> parseMemory(String md) => [
        for (final l in const LineSplitter().convert(md))
          if (_factLine.firstMatch(l.trimRight()) case final m?)
            (kind: MemoryKind.parse(m[1]), text: m[2]!.trim(), pinned: m[3] != null),
      ];

  static String renderSoul(Map<String, Object?> snapshot) =>
      '# Relationship — phone\n\n'
      "_How Mind and the owner stand with each other, kept so she does not forget it "
      'when the app is reinstalled. Written by the GigGok app._\n\n'
      '```json\n${const JsonEncoder.withIndent('  ').convert(snapshot)}\n```\n';

  static Map<String, Object?>? parseSoul(String md) {
    final m = RegExp(r'```json\s*([\s\S]*?)```').firstMatch(md);
    if (m == null) return null;
    try {
      final j = jsonDecode(m[1]!);
      return j is Map ? j.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String renderDay(DateTime day, Iterable<DayLine> lines, {required String her}) {
    final b = StringBuffer()
      ..writeln('# ${MindPaths.day(day)} — talking with $her on the phone')
      ..writeln();
    for (final l in lines) {
      final who = l.fromHer ? 'Mind' : 'Owner';
      final parts = l.text.trim().split('\n');
      b.writeln('- ${_two(l.at.hour)}:${_two(l.at.minute)} **$who:** ${parts.first}');
      for (final p in parts.skip(1)) {
        b.writeln('  $p');
      }
    }
    return b.toString();
  }

  static final _dayLine = RegExp(r'^- (\d{2}):(\d{2}) \*\*(Mind|Owner):\*\* (.*)$');

  static List<DayLine> parseDay(String md, DateTime day) {
    final out = <DayLine>[];
    for (final raw in const LineSplitter().convert(md)) {
      final m = _dayLine.firstMatch(raw);
      if (m != null) {
        out.add((
          at: DateTime(day.year, day.month, day.day, int.parse(m[1]!), int.parse(m[2]!)),
          fromHer: m[3] == 'Mind',
          text: m[4]!,
        ));
      } else if (raw.startsWith('  ') && out.isNotEmpty) {
        final last = out.removeLast();
        out.add((at: last.at, fromHer: last.fromHer, text: '${last.text}\n${raw.substring(2)}'));
      }
    }
    return out;
  }

  @override
  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _cloud.close();
    _xman.close();
    super.dispose();
  }
}
