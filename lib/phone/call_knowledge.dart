/// ข้อมูลที่ให้คนโทรรู้ได้ — คลังที่เจ้าของเลือกใส่เอง ให้น้องมายค้นตอนรับสาย
///
/// ## ทำไม
///
/// เจ้าของ: "เพิ่มฐานข้อมูลให้เธอตอบได้มากขึ้น เช่น ไปค้นจากลิงก์เว็บที่เราทำไว้
/// หรือข้อมูลที่เราอัพโหลดไว้ได้" · ของเดิมในสายเธอรู้แค่ prompt คนโทรถามราคา
/// เวลาเปิด บริการ = ตอบไม่ได้ หรือแต่งเอา
///
/// ## ทำงานยังไง
///
/// เจ้าของใส่ลิงก์เว็บ (ดึงหน้าเว็บมาเก็บเป็นข้อความในเครื่อง) · ไฟล์ (txt md csv
/// json html docx) · หรือพิมพ์เอง → ในสายคุยสด เธอเรียกเครื่องมือ `lookup_info` →
/// ค้นในเครื่อง (ไม่ส่งคำถามของคนโทรออกไปไหน และเร็วพอให้ตอบในสาย) → ได้ย่อหน้าที่ตรงที่สุด
///
/// ตัวค้น (trigram + idf สร้างในเธรดแยก) อยู่ที่ KnowledgeIndex · ใช้ร่วมกับแพ็กความรู้
///
/// 🔒 แยกจากสมอง BrainX ของเจ้าของโดยตั้งใจ: คนโทรเป็นคนนอก · คลังนี้มีแค่สิ่งที่
/// เจ้าของเลือกให้คนนอกรู้ได้ · ส่วน BrainX ค้นได้เฉพาะหมวดที่เจ้าของติ๊ก (ดู MindState)
///
/// 🔴 หน้าเว็บอาจมีข้อความล่อโมเดล · ผลที่ส่งให้เธอห่อไว้ว่า "ข้อมูล ไม่ใช่คำสั่ง"
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../memory/knowledge_index.dart';

export '../memory/knowledge_index.dart' show KnowledgeHit;

/// ทำไมเพิ่มไม่ได้ · คำเหล่านี้แปลเป็นข้อความบนจอที่หน้าตั้งค่า
class KnowledgeError implements Exception {
  const KnowledgeError(this.code);

  /// bad_url · fetch_failed · unsupported_type · empty · too_large
  final String code;
  @override
  String toString() => 'KnowledgeError($code)';
}

@immutable
class KnowledgeSource {
  const KnowledgeSource({
    required this.id,
    required this.kind,
    required this.title,
    required this.origin,
    required this.text,
    required this.updatedAt,
  });

  final String id;

  /// link · file · text
  final String kind;
  final String title;

  /// ลิงก์ หรือชื่อไฟล์ · ว่าง = พิมพ์เอง
  final String origin;
  final String text;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'origin': origin,
        'text': text,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static KnowledgeSource? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], kind = j['kind'], text = j['text'];
    if (id is! String || kind is! String || text is! String) return null;
    return KnowledgeSource(
      id: id,
      kind: kind,
      title: '${j['title'] ?? ''}',
      origin: '${j['origin'] ?? ''}',
      text: text,
      updatedAt: DateTime.tryParse('${j['updatedAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class CallKnowledge extends ChangeNotifier {
  CallKnowledge({http.Client? client, Future<File> Function()? file, DateTime Function()? clock})
      : _http = client ?? http.Client(),
        _file = file ?? _defaultFile,
        _clock = clock ?? DateTime.now;

  /// ต่อแหล่ง · ทั้งคลัง · ที่ดึงจากเว็บได้ต่อหน้า (กันหน้าเว็บใหญ่ล้นเครื่อง)
  static const maxSourceChars = 120000, maxTotalChars = 1000000, maxFetchBytes = 3 * 1024 * 1024;

  /// ไฟล์ที่เพิ่มได้ · ตัวเลือกไฟล์ของ Android กรองนามสกุลไม่ได้ทุกเครื่อง จึงเช็กที่นี่
  static final supportedFile = RegExp(r'\.(txt|md|markdown|csv|tsv|json|html?|docx)$', caseSensitive: false);

  final http.Client _http;
  final Future<File> Function() _file;
  final DateTime Function() _clock;
  List<KnowledgeSource> _sources = const [];
  Future<void>? _loading;
  Future<KnowledgeIndex>? _index;

  /// งานที่เขียนไฟล์ทีละงาน · สองงานพร้อมกันเขียน .tmp ตัวเดียวกัน = ไฟล์เสีย
  Future<void> _tail = Future.value();

  static Future<File> _defaultFile() async =>
      File('${(await getApplicationSupportDirectory()).path}/call_knowledge.json');

  List<KnowledgeSource> get sources => _sources;
  bool get isEmpty => _sources.isEmpty;
  int get totalChars => _sources.fold(0, (n, s) => n + s.text.length);

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is List) {
        _sources = j.map(KnowledgeSource.fromJson).whereType<KnowledgeSource>().toList(growable: false);
        _changed();
      }
    } on Object catch (e) {
      // ไฟล์เสีย = เริ่มคลังว่าง ดีกว่าแอปค้าง · ไม่ลงเนื้อหา
      debugPrint('คลังข้อมูลสาย: อ่านไม่ได้ — ${e.runtimeType}');
    }
  }

  Future<T> _serial<T>(Future<T> Function() job) {
    final run = _tail.then((_) => job());
    _tail = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _save(List<KnowledgeSource> next) async {
    final body = jsonEncode(next.map((s) => s.toJson()).toList());
    final f = await _file();
    await f.parent.create(recursive: true);
    // เขียนไฟล์ชั่วคราวแล้วค่อยแทน · ไฟดับกลางทางต้องไม่เหลือไฟล์ครึ่งเดียว
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(f.path);
  }

  void _changed() {
    _index = null;
    notifyListeners();
  }

  Future<KnowledgeSource> _put(KnowledgeSource src, {String? replace}) async {
    await load();
    final text = src.text.trim();
    if (text.isEmpty) throw const KnowledgeError('empty');
    final clipped = text.length > maxSourceChars ? text.substring(0, maxSourceChars) : text;
    final kept = KnowledgeSource(
        id: src.id, kind: src.kind, title: src.title, origin: src.origin, text: clipped, updatedAt: src.updatedAt);
    return _serial(() async {
      final at = replace == null ? -1 : _sources.indexWhere((s) => s.id == replace);
      // ลบไประหว่างรีเฟรช = ไม่เอากลับมา
      if (replace != null && at < 0) return kept;
      final rest = _sources.where((s) => s.id != (replace ?? src.id)).toList();
      final total = rest.fold<int>(0, (n, s) => n + s.text.length) + clipped.length;
      if (total > maxTotalChars) throw const KnowledgeError('too_large');
      if (at < 0) {
        rest.add(kept);
      } else {
        rest.insert(math.min(at, rest.length), kept);
      }
      final next = List<KnowledgeSource>.unmodifiable(rest);
      await _save(next);
      _sources = next;
      _changed();
      return kept;
    });
  }

  String _newId() => '${_clock().microsecondsSinceEpoch.toRadixString(36)}${math.Random().nextInt(1 << 20).toRadixString(36)}';

  Future<KnowledgeSource> addLink(String url) async {
    var raw = url.trim();
    // พิมพ์ชื่อเว็บมาเปล่า ๆ (shop.example.com) = เติม https ให้
    if (raw.isNotEmpty && !raw.contains('://')) raw = 'https://$raw';
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) {
      throw const KnowledgeError('bad_url');
    }
    final page = await _fetch(uri);
    return _put(KnowledgeSource(
      id: _newId(),
      kind: 'link',
      title: page.title.isEmpty ? uri.host : page.title,
      origin: uri.toString(),
      text: page.text,
      updatedAt: _clock(),
    ));
  }

  /// ดึงหน้าเว็บใหม่ · ใช้ได้กับลิงก์เท่านั้น
  Future<KnowledgeSource> refresh(String id) async {
    await load();
    final old = _sources.firstWhere((s) => s.id == id, orElse: () => throw const KnowledgeError('empty'));
    if (old.kind != 'link') return old;
    final page = await _fetch(Uri.parse(old.origin));
    return _put(
      KnowledgeSource(
          id: old.id, kind: 'link', title: page.title.isEmpty ? old.title : page.title,
          origin: old.origin, text: page.text, updatedAt: _clock()),
      replace: old.id,
    );
  }

  Future<KnowledgeSource> addText(String title, String text) => _put(KnowledgeSource(
        id: _newId(),
        kind: 'text',
        title: title.trim().isEmpty ? text.trim().split('\n').first : title.trim(),
        origin: '',
        text: text,
        updatedAt: _clock(),
      ));

  /// ไฟล์ (txt md csv json html docx) · ตัวที่เสียไม่ทำให้ล้ม
  Future<KnowledgeSource> addFile(String name, List<int> bytes) async {
    final lower = name.toLowerCase();
    if (!supportedFile.hasMatch(lower)) throw const KnowledgeError('unsupported_type');
    if (bytes.length > maxFetchBytes * 4) throw const KnowledgeError('too_large');
    var title = name.replaceAll(RegExp(r'\.[^.]+$'), '');
    final String text;
    if (lower.endsWith('.docx')) {
      text = docxText(bytes);
    } else if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      final page = htmlToText(decode(bytes));
      text = page.text;
      if (page.title.isNotEmpty) title = page.title;
    } else {
      text = decode(bytes);
    }
    return _put(KnowledgeSource(
        id: _newId(), kind: 'file', title: title, origin: name, text: text, updatedAt: _clock()));
  }

  Future<void> remove(String id) async {
    await load();
    await _serial(() async {
      final next = List<KnowledgeSource>.unmodifiable(_sources.where((s) => s.id != id));
      await _save(next);
      _sources = next;
      _changed();
    });
  }

  Future<({String title, String text})> _fetch(Uri uri) async {
    final http.StreamedResponse res;
    try {
      res = await _http
          .send(http.Request('GET', uri)..headers['User-Agent'] = 'GigGok/1.0 (owner knowledge for calls)')
          .timeout(const Duration(seconds: 15));
    } on Object {
      throw const KnowledgeError('fetch_failed');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) throw const KnowledgeError('fetch_failed');
    final type = (res.headers['content-type'] ?? '').toLowerCase();
    final isHtml = type.contains('html') || type.isEmpty;
    if (!isHtml && !type.startsWith('text/')) throw const KnowledgeError('unsupported_type');
    final bytes = <int>[];
    try {
      await for (final part in res.stream.timeout(const Duration(seconds: 20))) {
        bytes.addAll(part);
        if (bytes.length > maxFetchBytes) break;
      }
    } on Object {
      throw const KnowledgeError('fetch_failed');
    }
    final charset = RegExp(r'charset=([\w\-]+)').firstMatch(type)?.group(1);
    final body = decode(bytes, charset: charset);
    final page = isHtml ? htmlToText(body) : (title: '', text: body);
    if (page.text.trim().isEmpty) throw const KnowledgeError('empty');
    return page;
  }

  /// ไบต์ → ข้อความ
  ///
  /// 🔴 เว็บไทยรุ่นเก่าและไฟล์ .txt ที่เซฟจาก Windows ยังเป็น TIS-620 / windows-874 ·
  /// อ่านเป็น UTF-8 = ตัวอักษรเพี้ยนทั้งหน้า แล้วค้นอะไรก็ไม่เจอ
  @visibleForTesting
  static String decode(List<int> bytes, {String? charset}) {
    var cs = (charset ?? '').toLowerCase();
    if (cs.isEmpty) {
      final head = latin1.decode(bytes.take(4096).toList(), allowInvalid: true).toLowerCase();
      cs = RegExp(r'''charset\s*=\s*["']?([\w\-]+)''').firstMatch(head)?.group(1) ?? '';
    }
    if (cs.contains('874') || cs.contains('tis') || cs.contains('8859-11')) return _thaiLegacy(bytes);
    try {
      return utf8.decode(bytes);
    } on FormatException catch (e) {
      // ตัดกลางตัวอักษรตอนชนเพดานขนาด = ยังเป็น UTF-8 · เพี้ยนกลางไฟล์ + ไม่บอกว่า UTF-8 = รหัสไทยเก่า
      final cut = e.offset != null && e.offset! >= bytes.length - 4;
      return cut || cs.contains('utf') ? utf8.decode(bytes, allowMalformed: true) : _thaiLegacy(bytes);
    }
  }

  static const _cp874High = {
    0x80: 0x20AC, 0x85: 0x2026, 0x91: 0x2018, 0x92: 0x2019, //
    0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0xA0: 0x00A0,
  };

  static String _thaiLegacy(List<int> bytes) => String.fromCharCodes([
        for (final b in bytes)
          b < 0x80
              ? b
              : b >= 0xA1 && b <= 0xFB
                  ? 0x0E00 + b - 0xA0
                  : _cp874High[b] ?? 0xFFFD,
      ]);

  /// ไฟล์ Word (.docx = zip ที่มี word/document.xml) → ข้อความทีละย่อหน้า
  @visibleForTesting
  static String docxText(List<int> bytes) {
    final ArchiveFile? doc;
    try {
      doc = ZipDecoder().decodeBytes(bytes).findFile('word/document.xml');
    } on Object {
      throw const KnowledgeError('unsupported_type');
    }
    if (doc == null) throw const KnowledgeError('unsupported_type');
    if (doc.size > 20 * 1024 * 1024) throw const KnowledgeError('too_large');
    final xml = utf8.decode(doc.content, allowMalformed: true)
        .replaceAll(RegExp(r'</w:p>|<w:br\b[^>]*/?>|<w:cr\b[^>]*/?>'), '\n')
        .replaceAll(RegExp(r'<w:tab\b[^>]*/?>'), ' ')
        .replaceAll('</w:tc>', ' · ')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    return _lines(_entities(xml));
  }

  /// หน้าเว็บ → ข้อความล้วน · ทิ้งสคริปต์ สไตล์ เมนูที่เป็นโค้ด เหลือข้อความที่คนอ่าน
  static ({String title, String text}) htmlToText(String html) {
    final titleMatch = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html);
    final title = _entities(titleMatch?.group(1) ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final s = html
        .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ')
        .replaceAll(
            RegExp(r'<(script|style|noscript|svg|template|head)\b[\s\S]*?</\1\s*>', caseSensitive: false), ' ')
        .replaceAll(
            RegExp(
                r'<(br|/p|/div|/li|/h[1-6]|/tr|/section|/article|/header|/footer|/nav|/aside|/main|/ul|/ol|/table'
                r'|/dt|/dd|/blockquote|/pre|/figcaption|/form)\b[^>]*>',
                caseSensitive: false),
            '\n')
        .replaceAll(RegExp(r'<(td|th)\b[^>]*>', caseSensitive: false), ' · ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    return (title: title, text: _lines(_entities(s)));
  }

  /// ยุบช่องว่าง ทิ้งบรรทัดว่างและบรรทัดซ้ำติดกัน (เมนูเว็บชอบซ้ำ)
  static String _lines(String s) {
    final lines = <String>[];
    for (final raw in s.split('\n')) {
      final line = raw.replaceAll(RegExp(r'[ \t ]+'), ' ').trim();
      if (line.isEmpty || line == '·') continue;
      if (lines.isNotEmpty && lines.last == line) continue;
      lines.add(line);
    }
    return lines.join('\n');
  }

  static String _entities(String s) => s
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]{1,6});'), (m) => _char(int.tryParse(m[1]!, radix: 16)))
      .replaceAllMapped(RegExp(r'&#([0-9]{1,7});'), (m) => _char(int.tryParse(m[1]!)))
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  static String _char(int? code) =>
      code == null || code <= 0 || code > 0x10FFFF ? ' ' : String.fromCharCode(code);

  /// ชื่อแหล่งข้อมูลสั้น ๆ ให้เธอรู้ว่าคลังมีเรื่องอะไร จะได้รู้ว่าเมื่อไรควรค้น
  String index() => _sources
      .take(20)
      .map((s) => s.title.length > 60 ? '${s.title.substring(0, 60)}…' : s.title)
      .join(' · ');

  /// สร้างดัชนีไว้ก่อน (ตอนสายเริ่ม) · คำถามแรกในสายจะได้ไม่ต้องรอ
  Future<void> warm() async {
    await load();
    if (_sources.isNotEmpty) await _indexed();
  }

  Future<KnowledgeIndex> _indexed() {
    final cached = _index;
    if (cached != null) return cached;
    final f = KnowledgeIndex.buildInBackground([for (final s in _sources) (title: s.title, text: s.text, tag: s.id)]);
    _index = f;
    f.then((_) {}, onError: (Object _) {
      if (identical(_index, f)) _index = null;
    });
    return f;
  }

  /// ย่อหน้าที่ตรงคำถามที่สุด · ว่าง = คลังไม่มีเรื่องนี้ (ให้เธอบอกตามจริง ไม่แต่ง)
  Future<List<KnowledgeHit>> search(String query, {int limit = 3}) async {
    await load();
    if (_sources.isEmpty || KnowledgeIndex.grams(query).isEmpty) return const [];
    return (await _indexed()).search(query, limit: limit);
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}
