/// แพ็กความรู้ของมายด์ — ความรู้เสริมที่ซื้อในร้าน แล้วติดตั้งลงเครื่อง
///
/// ## ทำไม
///
/// เจ้าของ (2026-11-02): "ทำให้แอพมีความสามารถเสริมได้ เป็น plugins ซื้อได้ใน shop ของมายด์
/// คือความรู้ของเธอ เช่นเรื่องการเทรดหุ้น คริปโต ทำอาหาร เครื่องยนต์ เอาตัวรอดในป่า" ·
/// คุณค่าไม่ได้อยู่ที่รู้มากกว่าโมเดลใหญ่ แต่อยู่ที่ใช้ได้ออฟไลน์กับสมองในเครื่อง ·
/// เนื้อหาไทยที่ตรวจแล้วมีที่มา · และกฎความปลอดภัยของแต่ละเรื่องที่แอปใส่เอง
///
/// ## แพ็ก = ข้อมูลล้วน ไม่มีโค้ด
///
/// zip = `manifest.json` + `content/*.md` · 🔴 ไม่โหลดโค้ดจากแพ็กเด็ดขาด (นโยบาย Play + ความปลอดภัย)
/// · ไฟล์นามสกุลนอกรายการ = ปฏิเสธทั้งแพ็ก · เครื่องมือคอมไพล์อยู่ในแอปแล้ว แพ็กแค่ระบุชื่อ (`tools`)
/// · รูปยังไม่ใช้ในเฟสนี้ (รับไว้ใน zip ได้ แต่ไม่ติดตั้ง) · รูปแบบเต็มดู docs/knowledge-packs.md
///
/// ## ในแชท
///
/// ทุกข้อความ ค้นแพ็กที่เปิดอยู่ในเครื่องก่อน ([KnowledgeIndex]) แล้วแนบท่อนที่ตรงที่สุดไว้หน้าข้อความ
/// เป็น "ข้อมูล ไม่ใช่คำสั่ง" · ใช้ได้กับทุกสมองรวมทั้งในเครื่องตอนออฟไลน์ ·
/// 🔒 ไม่เข้าสายโทรศัพท์ (คลังของสายแยกไว้โดยตั้งใจ ดู CallKnowledge)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, AssetManifest;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../avatar/avatar_pack.dart';
import '../memory/knowledge_index.dart';
import '../memory/recall.dart';
import '../update/updater.dart';

/// ทำไมติดตั้งไม่ได้ · เก็บเป็นรหัส หน้าร้านแปลเป็นข้อความ (ชั้นนี้ไม่มี context ของภาษา)
enum KnowledgePackError {
  /// โหลดไม่ถึงปลายทาง หรือเน็ตหลุดกลางทาง
  network,

  /// แฮชไม่ตรงกับที่ร้านประกาศ — ไฟล์ขาดหรือถูกสลับ
  hashMismatch,

  /// zip เสีย · manifest ใช้ไม่ได้ · มีไฟล์ชนิดที่ไม่รับ · id ไม่ตรงกับที่ซื้อ · ไม่มีเนื้อหา
  badPack,

  /// ไม่ใช่แพ็กความรู้ (เช่น zip ชุดตัวละคร)
  notKnowledge,

  /// ใหญ่เกินเพดาน
  tooLarge,

  /// แพ็กต้องการแอปรุ่นใหม่กว่านี้ (minAppVersion)
  needsUpdate,

  /// กำลังติดตั้งแพ็กอื่นอยู่
  busy,
}

class KnowledgePackFailure implements Exception {
  const KnowledgePackFailure(this.error, [this.detail]);
  final KnowledgePackError error;

  /// รายละเอียดสำหรับ log เท่านั้น — ไม่ใช่ของผู้ใช้
  final String? detail;

  @override
  String toString() => 'KnowledgePackFailure(${error.name}${detail == null ? '' : ': $detail'})';
}

/// หมวดของแพ็ก · มีผลกับกฎความปลอดภัยที่**แอปใส่เอง** (ดู MindPersona.knowledgeBlock)
///
/// 🔴 แพ็กลบกฎพวกนี้ไม่ได้ เพราะกฎอยู่ในแอป ไม่ได้อยู่ในแพ็ก · หลังบ้านต้องตรวจตอนอัปโหลดว่า
/// แพ็กเทรดประกาศหมวด `trading` จริง (ดู docs/pack-store.md)
enum PackCategory {
  general,
  cooking,
  survival,
  firstAid,
  engine,
  trading;

  static PackCategory parse(Object? v) => switch ('${v ?? ''}'.trim().toLowerCase()) {
        'cooking' => cooking,
        'survival' => survival,
        'first_aid' || 'firstaid' => firstAid,
        'engine' || 'mechanic' => engine,
        'trading' || 'finance' || 'investing' => trading,
        _ => general,
      };

  String get code => switch (this) {
        firstAid => 'first_aid',
        _ => name,
      };
}

/// ข้อความสองภาษาในแพ็ก · ภาษาที่ขาดใช้อีกภาษาแทน (แพ็กไทยล้วนยังใช้ได้บนแอปอังกฤษ)
@immutable
class PackText {
  const PackText(this.th, this.en);
  final String th;
  final String en;

  bool get isEmpty => th.isEmpty && en.isEmpty;
  String of(bool thai) => thai ? (th.isNotEmpty ? th : en) : (en.isNotEmpty ? en : th);

  /// รับทั้ง `"ข้อความ"` และ `{"th": …, "en": …}` · ยาวเกิน [max] ตัดทิ้ง
  static PackText parse(Object? v, {required int max}) {
    String clip(Object? s) {
      final t = s is String ? s.trim().replaceAll(RegExp(r'\s+'), ' ') : '';
      return t.length <= max ? t : t.substring(0, max);
    }

    if (v is Map) return PackText(clip(v['th']), clip(v['en']));
    final one = clip(v);
    return PackText(one, one);
  }

  Map<String, String> toJson() => {'th': th, 'en': en};
}

/// รายการสองภาษา (ตัวอย่างคำถาม กฎความปลอดภัย) · แต่ละภาษามีกี่ข้อก็ได้
@immutable
class PackList {
  const PackList(this.th, this.en);
  final List<String> th;
  final List<String> en;

  static const empty = PackList([], []);

  List<String> of(bool thai) => thai ? (th.isNotEmpty ? th : en) : (en.isNotEmpty ? en : th);

  /// รับทั้ง `["…"]` และ `{"th": [...], "en": [...]}` · เกิน [count] ข้อหรือยาวเกิน [max] ตัดทิ้ง
  static PackList parse(Object? v, {required int count, required int max}) {
    List<String> list(Object? raw) => raw is List
        ? [
            for (final e in raw)
              if (e is String && e.trim().isNotEmpty)
                e.trim().length <= max ? e.trim() : e.trim().substring(0, max),
          ].take(count).toList(growable: false)
        : const [];
    if (v is Map) return PackList(list(v['th']), list(v['en']));
    final one = list(v);
    return PackList(one, one);
  }

  Map<String, List<String>> toJson() => {'th': th, 'en': en};
}

/// `manifest.json` ของแพ็ก (ผ่านด่านแล้ว)
@immutable
class KnowledgeManifest {
  const KnowledgeManifest({
    required this.id,
    required this.version,
    required this.name,
    required this.category,
    this.persona = const PackText('', ''),
    this.starters = PackList.empty,
    this.safety = PackList.empty,
    this.tools = const [],
    this.minAppVersion = '',
  });

  /// เพดาน · persona กับ safety เข้า system prompt ทุกตา ต้องสั้น (สมองในเครื่องมีหน้าต่างเล็ก)
  static const maxName = 60, maxPersona = 300, maxRule = 160, maxRules = 4, maxStarter = 120, maxStarters = 6;

  /// เครื่องมือที่มีในแอปอยู่แล้วและแพ็กขอใช้ได้ · ชื่ออื่น = ทิ้ง (แพ็กสร้างความสามารถใหม่ไม่ได้)
  ///
  /// `web_search` = เรื่องที่เปลี่ยนตลอด (ราคา ข่าว) ให้ค้นเว็บแทนเดา (เมื่อเจ้าของเปิดค้นเว็บไว้) ·
  /// `sos` = ชี้ไปที่ระบบแจ้งเหตุของแอป
  static const knownTools = {'web_search', 'sos'};

  final String id;
  final String version;
  final PackText name;
  final PackCategory category;
  final PackText persona;
  final PackList starters;
  final PackList safety;
  final List<String> tools;
  final String minAppVersion;

  /// อ่านแบบทนความไม่เนี้ยบ แต่ช่องที่ขาดไม่ได้ (id ชนิด ชื่อ) ขาด = ปฏิเสธ
  ///
  /// 🔴 เช็กชนิดก่อนทุกช่อง ไม่ cast · `"id": 3` จะโยน TypeError ซึ่งไม่ใช่ Exception
  /// แล้วการติดตั้งค้าง (บทเรียนจาก AvatarPackInfo.read)
  static KnowledgeManifest parse(Object? j) {
    if (j is! Map) throw const KnowledgePackFailure(KnowledgePackError.badPack, 'manifest is not an object');
    if ('${j['kind'] ?? ''}'.trim() != 'knowledge') {
      throw const KnowledgePackFailure(KnowledgePackError.notKnowledge);
    }
    final rawId = j['id'];
    final id = rawId is String ? AvatarPacks.safeId(rawId) : null;
    // 🔴 ขึ้นต้นด้วย _ = ชื่อไฟล์ของแอปเอง (`_state.json`) · แพ็กชื่อ "_state" จะเขียนทับสวิตช์ทุกแพ็ก
    if (id == null || id.startsWith('_')) throw const KnowledgePackFailure(KnowledgePackError.badPack, 'no usable id');
    final name = PackText.parse(j['name'], max: maxName);
    final v = j['version'];
    final min = j['minAppVersion'];
    final tools = j['tools'];
    return KnowledgeManifest(
      id: id,
      version: v is String || v is num ? '$v'.trim() : '1',
      name: name.isEmpty ? PackText(id, id) : name,
      category: PackCategory.parse(j['category']),
      persona: PackText.parse(j['persona'], max: maxPersona),
      starters: PackList.parse(j['starters'], count: maxStarters, max: maxStarter),
      safety: PackList.parse(j['safety'], count: maxRules, max: maxRule),
      tools: tools is List
          ? [for (final t in tools) if (t is String && knownTools.contains(t.trim())) t.trim()]
          : const [],
      minAppVersion: min is String ? min.trim() : '',
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': 'knowledge',
        'version': version,
        'name': name.toJson(),
        'category': category.code,
        'persona': persona.toJson(),
        'starters': starters.toJson(),
        'safety': safety.toJson(),
        'tools': tools,
        'minAppVersion': minAppVersion,
      };
}

/// หัวข้อหนึ่งหัวข้อ · [lang] มาจากโฟลเดอร์ (`content/th/` `content/en/`) · ว่าง = ใช้ได้ทุกภาษา
typedef PackSection = ({String title, String text, String lang});

/// ผลแตก zip (ข้ามเธรดได้) · ล้ม = [error] คือชื่อของ [KnowledgePackError]
typedef UnpackedPack = ({
  String? error,
  String? detail,
  Object? manifest,
  List<PackSection> sections,
  List<(String, Uint8List)> images,
});

/// แพ็กหนึ่งแพ็กที่ติดตั้งอยู่ในเครื่อง
@immutable
class KnowledgePack {
  const KnowledgePack({
    required this.manifest,
    required this.sections,
    required this.enabled,
    required this.installedAt,
    this.images = const [],
  });

  final KnowledgeManifest manifest;
  final List<PackSection> sections;
  final bool enabled;
  final DateTime installedAt;

  /// path ของรูปในแพ็ก (จากราก zip เช่น `images/knot.png`) · ไฟล์จริงดู [KnowledgePacks.imagesOf]
  final List<String> images;

  String get id => manifest.id;
  int get chars => sections.fold(0, (n, s) => n + s.title.length + s.text.length);

  /// หัวข้อในภาษาของแอป + หัวข้อที่ไม่ระบุภาษา · แพ็กที่ไม่มีภาษานั้นเลย = ทุกหัวข้อ (ดีกว่าหน้าว่าง)
  List<PackSection> sectionsFor(bool thai) {
    final lang = thai ? 'th' : 'en';
    final mine = [for (final s in sections) if (s.lang == lang || s.lang.isEmpty) s];
    return mine.any((s) => s.lang == lang) ? mine : sections;
  }

  KnowledgePack withEnabled(bool v) =>
      KnowledgePack(manifest: manifest, sections: sections, enabled: v, installedAt: installedAt, images: images);
}

/// สิ่งที่แพ็กที่เปิดอยู่ใส่ใน system prompt ของแชท (ภาษาเลือกแล้ว)
typedef PackBrief = ({String name, PackCategory category, String persona, List<String> safety, List<String> tools});

enum KnowledgeInstallStage { idle, downloading, verifying, unpacking }

/// ทะเบียนแพ็กความรู้ในเครื่อง + ตัวติดตั้ง + ตัวค้น
class KnowledgePacks extends ChangeNotifier {
  KnowledgePacks({
    http.Client? client,
    Future<Directory> Function()? root,
    Future<String> Function()? appVersion,
    DateTime Function()? clock,
  })  : _http = client ?? http.Client(),
        _root = root ?? _defaultRoot,
        _appVersion = appVersion ?? _defaultVersion,
        _clock = clock ?? DateTime.now;

  /// zip ที่โหลด · ความรู้เป็นข้อความ ไม่กี่ร้อย KB · เพดานนี้เหลือที่ให้รูปในเฟสหน้า
  static const maxZipBytes = 8 * 1024 * 1024;

  /// ขนาดที่ zip ประกาศว่าแตกแล้วได้ (รวม) · กัน zip ระเบิด (ไฟล์เล็กที่แตกแล้วเป็นกิกะไบต์)
  static const maxUnpackedBytes = 24 * 1024 * 1024;

  /// ต่อไฟล์ข้อความ (แตกจริง ไม่ใช่ตัวเลขที่ zip อ้าง) · manifest
  static const maxTextFileBytes = 512 * 1024, maxManifestBytes = 64 * 1024;

  /// รูป: ต่อรูป (แตกจริง) · จำนวน · ด้านยาวสุด (พิกเซล) · ภาพประกอบในหน้าอ่าน ไม่ใช่คลังรูป
  ///
  /// 🔴 ด้านยาวสุดสำคัญกว่าขนาดไฟล์ · PNG สีเรียบ 2 MB ประกาศ 30000×30000 ได้ = แตกเป็นภาพ 3.6 GB ตอนแสดง
  static const maxImageBytes = 2 * 1024 * 1024, maxImages = 120, maxImageSide = 4096;

  /// เนื้อหาต่อแพ็ก (ตัวอักษร) · ทั้งเครื่อง · เท่าคลังของสาย ดัชนียังสร้างไม่ถึงวินาที
  static const maxPackChars = 400000, maxTotalChars = 1500000;

  /// เกณฑ์ของแชท (ดู KnowledgeIndex.search) · วัดกับแพ็กตัวอย่าง 2026-11-02: คำถามตัวอย่างทุกข้อผ่าน
  /// คุยเล่นผ่านข้อเดียว ("วันนี้เหนื่อยจัง" ตรงคำว่า "เหนื่อย" ในเรื่องหลงป่า) · หลุดมาก็แค่ข้อมูลอ้างอิง
  /// หัวบล็อกบอกให้ใช้เฉพาะที่เกี่ยว · chatRun เพิ่มตอนใส่เนื้อหาอังกฤษ ("คิดถึงจังเลย" เริ่มหลุด)
  static const chatShare = 0.25, chatEvidence = 2.5, chatRun = 3;

  /// ท่อนต่อข้อความ · ท่อนละ ~600 ตัว สมองในเครื่องมีที่ 8k token ใช้ร่วมกับความจำ
  static const chatHits = 2;

  /// เกณฑ์ตอนเธอค้นเอง (เครื่องมือ `knowledge_lookup` ในคุยสด) · เธอค้นเพราะเรื่องตรงหัวข้อของแพ็กแล้ว
  /// ไม่ใช่ทุกประโยคที่พูด จึงหลวมกว่าแชท
  static const lookupShare = 0.15, lookupEvidence = 1.5, lookupHits = 3;

  /// ไฟล์ที่ยอมให้อยู่ใน zip · อย่างอื่น (โค้ด สคริปต์ html ไบนารี) = ปฏิเสธทั้งแพ็ก
  static final _textFile = RegExp(r'\.(md|markdown|txt)$', caseSensitive: false);
  static final _imageFile = RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false);

  /// แพ็กฟรีที่มากับแอป · อ่านจาก `assets/knowledge/{id}/` ติดตั้งได้โดยไม่ต้องมีร้าน
  static const bundled = ['survival-basic'];
  static const bundledRoot = 'assets/knowledge';

  final http.Client _http;
  final Future<Directory> Function() _root;
  final Future<String> Function() _appVersion;
  final DateTime Function() _clock;

  List<KnowledgePack> _packs = const [];
  Set<String> _off = const {};
  Future<void>? _loading;
  Future<KnowledgeIndex>? _index;
  bool _disposed = false;

  /// งานที่เขียนไฟล์ทีละงาน · สองงานพร้อมกันเขียน .tmp ตัวเดียวกัน = ไฟล์เสีย
  Future<void> _tail = Future.value();

  KnowledgeInstallStage _stage = KnowledgeInstallStage.idle;
  KnowledgeInstallStage get stage => _stage;
  bool get busy => _stage != KnowledgeInstallStage.idle;

  /// 0..1 ระหว่างโหลด · null = ไม่รู้ขนาด (แถบวิ่งไปเรื่อย ๆ ดีกว่าแถบ 0% ที่ค้างนิ่ง)
  double? _progress;
  double? get progress => _progress;

  List<KnowledgePack> get installed => _packs;
  List<KnowledgePack> get enabled => [for (final p in _packs) if (p.enabled) p];
  KnowledgePack? byId(String id) {
    for (final p in _packs) {
      if (p.id == id) return p;
    }
    return null;
  }

  int get totalChars => _packs.fold(0, (n, p) => n + p.chars);

  static Future<Directory> _defaultRoot() async =>
      Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}knowledge-packs');

  static Future<String> _defaultVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } on Object {
      return '';
    }
  }

  File _fileOf(Directory root, String id) => File('${root.path}${Platform.pathSeparator}$id.json');

  /// รูปของแพ็ก · โฟลเดอร์ข้างไฟล์ json (ชื่อไม่ลงท้าย .json · ตัวอ่านทะเบียนข้ามโฟลเดอร์อยู่แล้ว)
  Directory _imagesDirOf(Directory root, String id) => Directory('${root.path}${Platform.pathSeparator}$id.img');

  /// ชื่อไฟล์ของรูปในโฟลเดอร์ · แฮชของ path ในแพ็ก ไม่ใช่แทน `/` ด้วยตัวอื่น ("a/b.png" กับ "a__b.png"
  /// จะได้ชื่อเดียวกัน รูปหนึ่งทับอีกรูป) · ยาวคงที่ path ลึกแค่ไหนก็ไม่ชนเพดานชื่อไฟล์ของระบบ
  static String _flat(String ref) =>
      '${sha256.convert(utf8.encode(ref)).toString().substring(0, 32)}${ref.substring(ref.lastIndexOf('.')).toLowerCase()}';
  File _stateOf(Directory root) => File('${root.path}${Platform.pathSeparator}_state.json');

  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      final root = await _root();
      if (!await root.exists()) return;
      final state = _stateOf(root);
      if (await state.exists()) {
        final j = jsonDecode(await state.readAsString());
        final off = j is Map ? j['off'] : null;
        if (off is List) _off = Set.unmodifiable(off.whereType<String>());
      }
      final packs = <KnowledgePack>[];
      await for (final f in root.list()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        if (f.uri.pathSegments.last.startsWith('_')) continue;
        final p = _decode(await f.readAsString());
        if (p != null) packs.add(p);
      }
      _packs = _sorted(packs);
      _changed();
    } on Object catch (e) {
      // ไฟล์เสีย/ไม่มีที่เก็บ (เทสต์) = เริ่มว่าง ดีกว่าแอปค้าง
      debugPrint('แพ็กความรู้: อ่านไม่ได้ — ${e.runtimeType}');
    }
  }

  KnowledgePack? _decode(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final m = KnowledgeManifest.parse(j['manifest']);
      final secs = j['sections'];
      if (secs is! List) return null;
      final imgs = j['images'];
      return KnowledgePack(
        manifest: m,
        sections: [
          for (final s in secs)
            if (s is Map && s['text'] is String)
              (title: '${s['title'] ?? ''}', text: s['text'] as String, lang: _langOf(s['lang'])),
        ],
        enabled: !_off.contains(m.id),
        installedAt: DateTime.tryParse('${j['installedAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        images: imgs is List ? [for (final i in imgs) if (i is String && imageRef(i) == i) i] : const [],
      );
    } on Object catch (e) {
      debugPrint('แพ็กความรู้: แพ็กหนึ่งอ่านไม่ได้ ข้ามไป — ${e.runtimeType}');
      return null;
    }
  }

  List<KnowledgePack> _sorted(List<KnowledgePack> l) =>
      List.unmodifiable(l..sort((a, b) => a.id.compareTo(b.id)));

  Future<T> _serial<T>(Future<T> Function() job) {
    final run = _tail.then((_) => job());
    _tail = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  /// เขียนไฟล์ชั่วคราวแล้วค่อยแทน · ไฟดับกลางทางต้องไม่เหลือไฟล์ครึ่งเดียว
  static Future<void> _write(File f, String body) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(f.path);
  }

  void _changed() {
    _index = null;
    if (!_disposed) notifyListeners();
  }

  void _stageTo(KnowledgeInstallStage s, {double? progress}) {
    _stage = s;
    _progress = progress;
    if (!_disposed) notifyListeners();
  }

  // ── ติดตั้ง ─────────────────────────────────────────

  /// โหลดจากลิงก์ที่มีลายเซ็น (ร้าน) แล้วติดตั้ง · [expectId] = รหัสในแค็ตตาล็อกที่กดซื้อ
  ///
  /// 🔴 รหัสใน manifest ต้องตรงกับที่ซื้อ · ไม่ตรง = ลูกค้าจ่ายเงิน โหลดสำเร็จ แล้วหน้าร้าน
  /// จำไม่ได้ว่าติดตั้งอะไรลงไป (เหตุผลเดียวกับด่านของหลังบ้าน ดู docs/pack-store.md)
  Future<KnowledgePack> install(String url, {String? sha256Hex, String? expectId}) async {
    if (busy) throw const KnowledgePackFailure(KnowledgePackError.busy);
    _stageTo(KnowledgeInstallStage.downloading, progress: 0);
    try {
      final bytes = await _download(url.trim());
      if (sha256Hex != null && sha256Hex.isNotEmpty) {
        _stageTo(KnowledgeInstallStage.verifying);
        if (sha256.convert(bytes).toString() != sha256Hex.trim().toLowerCase()) {
          throw const KnowledgePackFailure(KnowledgePackError.hashMismatch);
        }
      }
      return await _installZip(bytes, expectId: expectId);
    } finally {
      _stageTo(KnowledgeInstallStage.idle);
    }
  }

  /// ติดตั้งจาก zip ในหน่วยความจำ (แพ็กที่มากับแอป · เทสต์)
  Future<KnowledgePack> installZip(List<int> bytes, {String? expectId}) async {
    if (busy) throw const KnowledgePackFailure(KnowledgePackError.busy);
    try {
      return await _installZip(bytes, expectId: expectId);
    } finally {
      _stageTo(KnowledgeInstallStage.idle);
    }
  }

  /// แพ็กฟรีที่มากับแอป · อ่านไฟล์ทั้งโฟลเดอร์จาก asset แล้วผ่านด่านเดียวกับของจากร้านทุกข้อ
  Future<KnowledgePack> installBundled(AssetBundle bundle, String id) async {
    if (busy) throw const KnowledgePackFailure(KnowledgePackError.busy);
    final prefix = '$bundledRoot/$id/';
    final assets = (await AssetManifest.loadFromAssetBundle(bundle)).listAssets().where((a) => a.startsWith(prefix));
    final archive = Archive();
    for (final a in assets) {
      final data = await bundle.load(a);
      archive.add(ArchiveFile.bytes(a.substring(prefix.length), data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
    }
    return installZip(ZipEncoder().encodeBytes(archive), expectId: id);
  }

  Future<List<int>> _download(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      throw const KnowledgePackFailure(KnowledgePackError.network, 'bad url');
    }
    final http.StreamedResponse res;
    try {
      res = await _http.send(http.Request('GET', uri)).timeout(const Duration(seconds: 60));
    } on Object catch (e) {
      throw KnowledgePackFailure(KnowledgePackError.network, '${e.runtimeType}');
    }
    if (res.statusCode >= 400) throw KnowledgePackFailure(KnowledgePackError.network, 'HTTP ${res.statusCode}');
    final total = res.contentLength ?? 0;
    if (total > maxZipBytes) throw const KnowledgePackFailure(KnowledgePackError.tooLarge);
    final out = BytesBuilder(copy: false);
    try {
      // timeout ต่อก้อน · timeout ของ send() คุมแค่ตอนรอหัว เน็ตค้างกลางทาง = ค้างที่ "กำลังโหลด" ตลอดไป
      await for (final chunk in res.stream.timeout(const Duration(seconds: 45))) {
        out.add(chunk);
        if (out.length > maxZipBytes) throw const KnowledgePackFailure(KnowledgePackError.tooLarge);
        if (total > 0) _stageTo(KnowledgeInstallStage.downloading, progress: out.length / total);
      }
    } on KnowledgePackFailure {
      rethrow;
    } on Object catch (e) {
      throw KnowledgePackFailure(KnowledgePackError.network, '${e.runtimeType}');
    }
    return out.takeBytes();
  }

  Future<KnowledgePack> _installZip(List<int> bytes, {String? expectId}) async {
    _stageTo(KnowledgeInstallStage.unpacking);
    if (bytes.length > maxZipBytes) throw const KnowledgePackFailure(KnowledgePackError.tooLarge);
    final got = await _unpackInBackground(Uint8List.fromList(bytes));
    if (got.error != null) {
      throw KnowledgePackFailure(
          KnowledgePackError.values.firstWhere((e) => e.name == got.error, orElse: () => KnowledgePackError.badPack),
          got.detail);
    }
    final manifest = KnowledgeManifest.parse(got.manifest);
    if (expectId != null && AvatarPacks.safeId(expectId) != manifest.id) {
      throw KnowledgePackFailure(KnowledgePackError.badPack, 'id ${manifest.id} != $expectId');
    }
    final current = await _appVersion();
    if (manifest.minAppVersion.isNotEmpty && current.isNotEmpty && Updater.isNewer(manifest.minAppVersion, current)) {
      throw KnowledgePackFailure(KnowledgePackError.needsUpdate, '${manifest.minAppVersion} > $current');
    }
    final sections = got.sections;
    if (sections.isEmpty) throw const KnowledgePackFailure(KnowledgePackError.badPack, 'no content');
    final images = got.images;

    await load();
    return _serial(() async {
      final pack = KnowledgePack(
        manifest: manifest,
        sections: List.unmodifiable(sections),
        // ติดตั้งรุ่นใหม่ทับ = สวิตช์คงเดิม · แพ็กใหม่ = เปิดเลย (ซื้อมาเพื่อใช้)
        enabled: !_off.contains(manifest.id),
        installedAt: _clock(),
        images: [for (final (ref, _) in images) ref],
      );
      if (pack.chars > maxPackChars) throw const KnowledgePackFailure(KnowledgePackError.tooLarge);
      final rest = [for (final p in _packs) if (p.id != pack.id) p];
      if (rest.fold<int>(0, (n, p) => n + p.chars) + pack.chars > maxTotalChars) {
        throw const KnowledgePackFailure(KnowledgePackError.tooLarge, 'device total');
      }
      final root = await _root();
      await _writeImages(_imagesDirOf(root, pack.id), images);
      await _write(
        _fileOf(root, pack.id),
        jsonEncode({
          'manifest': manifest.toJson(),
          'sections': [
            for (final s in sections) {'title': s.title, 'text': s.text, if (s.lang.isNotEmpty) 'lang': s.lang},
          ],
          'images': pack.images,
          'sha256': sha256.convert(bytes).toString(),
          'installedAt': pack.installedAt.toIso8601String(),
        }),
      );
      _packs = _sorted([...rest, pack]);
      _changed();
      return pack;
    });
  }

  /// รูปลงโฟลเดอร์ชั่วคราวก่อน แล้วค่อยสลับกับของเดิม · ล้มกลางทาง = รูปชุดเก่ายังอยู่ครบ
  static Future<void> _writeImages(Directory dir, List<(String, Uint8List)> images) async {
    final tmp = Directory('${dir.path}.tmp');
    if (await tmp.exists()) await tmp.delete(recursive: true);
    if (images.isNotEmpty) {
      await tmp.create(recursive: true);
      for (final (ref, data) in images) {
        await File('${tmp.path}${Platform.pathSeparator}${_flat(ref)}').writeAsBytes(data, flush: true);
      }
    }
    if (await dir.exists()) await dir.delete(recursive: true);
    if (images.isNotEmpty) await tmp.rename(dir.path);
  }

  /// แตกในเธรดแยก · zip หลายเมกะไบต์บนเธรดหลัก = จอค้างระหว่างแถบความคืบหน้า ·
  /// static = closure ไม่ติด `this` (ตัวต่อเน็ตส่งข้ามเธรดไม่ได้)
  static Future<UnpackedPack> _unpackInBackground(Uint8List data) => Isolate.run(() => unpack(data));

  /// zip → manifest + หัวข้อ + รูป · ฟังก์ชันล้วน รันในเธรดแยก · คืนผลแทนการโยน (ข้ามเธรดง่ายกว่า)
  @visibleForTesting
  static UnpackedPack unpack(List<int> bytes) {
    UnpackedPack fail(KnowledgePackError e, String detail) =>
        (error: e.name, detail: detail, manifest: null, sections: const [], images: const []);

    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } on Object catch (e) {
      return fail(KnowledgePackError.badPack, 'not a zip (${e.runtimeType})');
    }

    var entries = <String, ArchiveFile>{};
    var declared = 0;
    for (final f in zip.files) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll(r'\', '/');
      // ขยะที่ macOS/Windows แถมมาตอนบีบไฟล์ ไม่ใช่ความผิดของคนทำแพ็ก
      if (name.startsWith('__MACOSX/') || name.endsWith('.DS_Store') || name.endsWith('Thumbs.db')) continue;
      // 🔴 ลิงก์ · path ออกนอกราก · path เต็ม = ปฏิเสธทั้งแพ็ก ไม่ใช่ข้ามเงียบ ๆ
      if (f.isSymbolicLink || name.startsWith('/') || name.contains(':') || name.split('/').contains('..')) {
        return fail(KnowledgePackError.badPack, 'unsafe path $name');
      }
      declared += f.size;
      entries[name] = f;
    }
    if (declared > maxUnpackedBytes) return fail(KnowledgePackError.tooLarge, 'declared $declared');

    // โฟลเดอร์ครอบชั้นเดียว (บีบด้วยคลิกขวาบน Windows) = ถือว่าข้างในคือตัวแพ็ก
    if (!entries.containsKey('manifest.json')) {
      final tops = {for (final n in entries.keys) n.contains('/') ? n.substring(0, n.indexOf('/') + 1) : ''};
      if (tops.length == 1 && tops.single.isNotEmpty) {
        final cut = tops.single.length;
        entries = {for (final e in entries.entries) e.key.substring(cut): e.value};
      }
    }

    final texts = <String, ArchiveFile>{};
    final pictures = <String, ArchiveFile>{};
    for (final e in entries.entries) {
      final name = e.key;
      if (name == 'manifest.json') continue;
      if (_imageFile.hasMatch(name)) {
        pictures[name] = e.value;
        continue;
      }
      if (!_textFile.hasMatch(name)) return fail(KnowledgePackError.badPack, 'file type $name');
      if (name.startsWith('content/')) texts[name] = e.value;
    }
    if (pictures.length > maxImages) return fail(KnowledgePackError.tooLarge, '${pictures.length} images');

    final man = entries['manifest.json'];
    if (man == null) return fail(KnowledgePackError.badPack, 'no manifest.json');
    final manText = _text(man, maxManifestBytes);
    if (manText == null) return fail(KnowledgePackError.tooLarge, 'manifest');
    final Object? manifest;
    try {
      manifest = jsonDecode(manText);
    } on FormatException {
      return fail(KnowledgePackError.badPack, 'manifest is not json');
    }

    final sections = <PackSection>[];
    final names = texts.keys.toList()..sort();
    for (final n in names) {
      final body = _text(texts[n]!, maxTextFileBytes);
      if (body == null) return fail(KnowledgePackError.tooLarge, n);
      final base = n.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
      sections.addAll(markdownSections(base, body, lang: _langOf(n.split('/').elementAtOrNull(1))));
    }

    // 🔴 รูปต้องเป็นรูปจริง (อ่านหัวไฟล์ ไม่ใช่นามสกุล) · ไฟล์อื่นที่ตั้งชื่อเป็น .png = ปฏิเสธทั้งแพ็ก
    final images = <(String, Uint8List)>[];
    for (final n in pictures.keys.toList()..sort()) {
      final data = _bytes(pictures[n]!, maxImageBytes);
      if (data == null) return fail(KnowledgePackError.tooLarge, n);
      final size = imageSize(data);
      if (size == null) return fail(KnowledgePackError.badPack, 'not an image $n');
      if (size.$1 > maxImageSide || size.$2 > maxImageSide) return fail(KnowledgePackError.tooLarge, '$n $size');
      images.add((n, data));
    }
    return (error: null, detail: null, manifest: manifest, sections: sections, images: images);
  }

  static String _langOf(Object? folder) => switch ('$folder'.toLowerCase()) {
        'th' => 'th',
        'en' => 'en',
        _ => '',
      };

  /// (กว้าง, สูง) จากหัวไฟล์ PNG · JPEG · WebP โดยไม่แตกภาพ · null = ไม่ใช่รูปที่รู้จัก
  @visibleForTesting
  static (int, int)? imageSize(Uint8List b) {
    bool at(int i, List<int> sig) {
      if (b.length < i + sig.length) return false;
      for (var k = 0; k < sig.length; k++) {
        if (b[i + k] != sig[k]) return false;
      }
      return true;
    }

    int be16(int i) => b[i] << 8 | b[i + 1];
    int le16(int i) => b[i] | b[i + 1] << 8;
    int le24(int i) => b[i] | b[i + 1] << 8 | b[i + 2] << 16;

    // PNG: กว้าง/สูงอยู่ใน IHDR ซึ่งต้องเป็นก้อนแรก
    if (at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) && at(12, const [0x49, 0x48, 0x44, 0x52])) {
      if (b.length < 24) return null;
      return (be16(16) << 16 | be16(18), be16(20) << 16 | be16(22));
    }
    // JPEG: ไล่ก้อนจนเจอ SOF (C0–CF ยกเว้น C4 DHT · C8 · CC DAC)
    if (at(0, const [0xFF, 0xD8])) {
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) return null;
        final marker = b[i + 1];
        if (marker == 0xFF) {
          i++;
          continue;
        }
        if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
          return (be16(i + 7), be16(i + 5));
        }
        i += 2 + be16(i + 2);
      }
      return null;
    }
    // WebP: RIFF....WEBP แล้วก้อนแรกบอกขนาดตามชนิด
    if (at(0, const [0x52, 0x49, 0x46, 0x46]) && at(8, const [0x57, 0x45, 0x42, 0x50]) && b.length >= 30) {
      if (at(12, const [0x56, 0x50, 0x38, 0x20])) return (le16(26) & 0x3FFF, le16(28) & 0x3FFF); // VP8
      if (at(12, const [0x56, 0x50, 0x38, 0x4C])) {
        // VP8L: ความกว้าง-1 14 บิต แล้วความสูง-1 14 บิต เริ่มที่ไบต์ 21
        final bits = b[21] | b[22] << 8 | b[23] << 16 | b[24] << 24;
        return ((bits & 0x3FFF) + 1, (bits >> 14 & 0x3FFF) + 1);
      }
      if (at(12, const [0x56, 0x50, 0x38, 0x58])) return (le24(24) + 1, le24(27) + 1); // VP8X
    }
    return null;
  }

  /// แตกไฟล์ข้อความหนึ่งไฟล์ ไม่เกิน [cap] ไบต์ **ของจริง** · null = เกิน
  ///
  /// 🔴 ขนาดที่ zip ประกาศโกหกได้ · ไฟล์ 50KB ที่ประกาศว่าแตกได้ 1KB แต่แตกจริงได้ 5GB
  /// = แอปตายเพราะหน่วยความจำ · จึงนับไบต์ระหว่างแตกแล้วหยุดทันทีที่เกิน
  static String? _text(ArchiveFile f, int cap) {
    final data = _bytes(f, cap);
    if (data == null) return null;
    var s = utf8.decode(data, allowMalformed: true);
    if (s.startsWith('﻿')) s = s.substring(1);
    return s.replaceAll('\r\n', '\n');
  }

  /// แตกไฟล์หนึ่งไฟล์ ไม่เกิน [cap] ไบต์ของจริง · null = เกิน (ดู [_text])
  static Uint8List? _bytes(ArchiveFile f, int cap) {
    if (f.size > cap) return null;
    final out = _CappedOutput(cap);
    try {
      f.decompress(out);
    } on _TooBig {
      return null;
    }
    return out.getBytes();
  }

  /// markdown → หัวข้อละท่อน · หัวข้อ (#, ##, ###) เป็นชื่อท่อน
  ///
  /// คนทำแพ็กใส่ "ที่มา:" ไว้ท้ายหัวข้อ → ติดไปกับท่อนที่ค้นเจอ เธอจึงบอกที่มาได้ทุกครั้ง ·
  /// ข้อความก่อนหัวข้อแรกใช้ชื่อไฟล์เป็นชื่อ
  @visibleForTesting
  static List<PackSection> markdownSections(String fallbackTitle, String md, {String lang = ''}) {
    final out = <PackSection>[];
    var title = fallbackTitle;
    final buf = StringBuffer();
    void flush() {
      final t = buf.toString().trim();
      if (t.isNotEmpty) out.add((title: title, text: t, lang: lang));
      buf.clear();
    }

    final heading = RegExp(r'^#{1,3}\s+(.+?)\s*#*\s*$');
    for (final line in md.split('\n')) {
      final h = heading.firstMatch(line);
      if (h != null) {
        flush();
        title = h.group(1)!.trim();
        continue;
      }
      buf.writeln(line);
    }
    flush();
    return out;
  }

  // ── เปิด/ปิด/ลบ ───────────────────────────────────────

  Future<void> setEnabled(String id, bool on) async {
    await load();
    await _serial(() async {
      final next = {..._off};
      on ? next.remove(id) : next.add(id);
      if (setEquals(next, _off)) return;
      final root = await _root();
      await _write(_stateOf(root), jsonEncode({'off': (next.toList()..sort())}));
      _off = Set.unmodifiable(next);
      _packs = List.unmodifiable([for (final p in _packs) p.id == id ? p.withEnabled(on) : p]);
      _changed();
    });
  }

  Future<void> remove(String id) async {
    await load();
    await _serial(() async {
      final root = await _root();
      final f = _fileOf(root, id);
      if (await f.exists()) await f.delete();
      final img = _imagesDirOf(root, id);
      if (await img.exists()) await img.delete(recursive: true);
      if (_off.contains(id)) {
        _off = Set.unmodifiable({..._off}..remove(id));
        await _write(_stateOf(root), jsonEncode({'off': (_off.toList()..sort())}));
      }
      _packs = List.unmodifiable([for (final p in _packs) if (p.id != id) p]);
      _changed();
    });
  }

  // ── ค้น ─────────────────────────────────────────────

  /// สร้างดัชนีไว้ก่อน (ตอนเปิดแอป) · ข้อความแรกในแชทจะได้ไม่ต้องรอ
  Future<void> warm() async {
    await load();
    if (enabled.isNotEmpty) await _indexed();
  }

  Future<KnowledgeIndex> _indexed() {
    final cached = _index;
    if (cached != null) return cached;
    final f = KnowledgeIndex.buildInBackground([
      for (final p in enabled)
        for (final s in p.sections) (title: s.title, text: plain(s.text), tag: p.id),
    ]);
    _index = f;
    f.then((_) {}, onError: (Object _) {
      if (identical(_index, f)) _index = null;
    });
    return f;
  }

  /// ท่อนที่ตรงข้อความของเจ้าของที่สุด จากแพ็กที่เปิดอยู่ · `tag` = รหัสแพ็ก · ว่าง = ไม่เกี่ยว
  ///
  /// ตัดคำลงท้าย/คำถาม (ค่ะ ไหม ยังไง) และคำเชื่อมอังกฤษก่อน · ชิ้นพวกนี้มีในทุกเรื่อง ทำให้คุยเล่นดูเหมือนถาม
  Future<List<KnowledgeHit>> search(String query,
      {int limit = chatHits, double share = chatShare, double evidence = chatEvidence, int run = chatRun}) async {
    await load();
    final q = RecallIndex.stripChatter(query.replaceAll(_englishFiller, ' '));
    if (enabled.isEmpty || KnowledgeIndex.grams(q).isEmpty) return const [];
    final hits = (await _indexed())
        .search(q, limit: limit, minCover: 0, minShare: share, minEvidence: evidence, minRun: run);
    // ปิด/ลบแพ็กระหว่างดัชนีเก่ายังสร้างอยู่ = ท่อนของแพ็กนั้นยังมีในดัชนีชุดนี้ · กรองตามสวิตช์ตอนนี้
    return [for (final h in hits) if (byId(h.tag)?.enabled ?? false) h];
  }

  /// คำเชื่อมอังกฤษ ตัดทั้งคำ (ตัดกลางคำแบบ stripChatter จะทำ "with" เหลือ "w") · แพ็กเล็กมีคำพวกนี้
  /// ไม่กี่ท่อน idf จึงสูงเกินจริง ("play some music please" เคยไปตรงท่อนที่มีคำว่า "some")
  static final _englishFiller = RegExp(
      r"\b(?:a|an|the|and|or|but|if|so|to|of|in|on|at|by|for|from|with|about|into|is|am|are|was|were|be|been|"
      r"it|its|this|that|these|those|there|here|i|me|my|we|us|our|you|your|he|she|they|them|his|her|their|"
      r"some|any|all|can|could|would|should|will|may|might|must|do|does|did|have|has|had|how|why|when|where|"
      r"which|who|what|not|no|yes|ok|okay|just|very|really|much|many|lot|lots|get|got|please|thanks|thank|"
      r"hi|hello|hey)\b",
      caseSensitive: false);

  // ── รูป ─────────────────────────────────────────────

  /// รูปในเนื้อหา markdown: `![คำบรรยาย](images/knot.png)`
  static final imageMarkdown = RegExp(r'!\[([^\]]*)\]\(\s*([^)\s]+)(?:\s+"[^"]*")?\s*\)');

  /// ข้อความที่ส่งให้สมอง/เข้าดัชนี · รูปเหลือแค่คำบรรยาย (path ของรูปเป็นแค่เสียงรบกวนของตัวค้น)
  static String plain(String md) => md.replaceAllMapped(imageMarkdown, (m) => m.group(1)!.trim());

  /// path ที่คนทำแพ็กเขียน → path จากรากแพ็ก · `./` `../` นำหน้า (เขียนจาก content/) ตัดออก ·
  /// null = ไม่ใช่ path รูปที่ใช้ได้
  static String? imageRef(String raw) {
    var r = raw.trim().replaceAll(r'\', '/');
    while (r.startsWith('./') || r.startsWith('../')) {
      r = r.substring(r.indexOf('/') + 1);
    }
    if (r.isEmpty || r.startsWith('/') || r.contains(':') || r.split('/').contains('..')) return null;
    return _imageFile.hasMatch(r) ? r : null;
  }

  /// path ในแพ็ก → ไฟล์รูปในเครื่อง · เฉพาะรูปที่ติดตั้งจริง (หน้าอ่านขอรูปที่ไม่มี = ไม่แสดง ไม่ใช่จอแดง)
  Future<Map<String, File>> imagesOf(String id) async {
    final pack = byId(id);
    if (pack == null || pack.images.isEmpty) return const {};
    final dir = _imagesDirOf(await _root(), id);
    return {for (final ref in pack.images) ref: File('${dir.path}${Platform.pathSeparator}${_flat(ref)}')};
  }

  /// เธอค้นเองระหว่างคุยสด (เครื่องมือ `knowledge_lookup`) · เกณฑ์หลวมกว่าแชท ดู [lookupShare]
  Future<List<KnowledgeHit>> lookup(String query) =>
      search(query, limit: lookupHits, share: lookupShare, evidence: lookupEvidence, run: 1);

  /// สิ่งที่แพ็กที่เปิดอยู่ใส่ใน system prompt · เปลี่ยนเฉพาะตอนเปิด/ปิด/ติดตั้ง
  ///
  /// 🔴 ห้ามใส่อะไรที่เปลี่ยนทุกตา · สมองในเครื่องใช้ session เดิมต่อเมื่อ system prompt ไม่เปลี่ยน
  List<PackBrief> briefs({required bool thai}) => [
        for (final p in enabled)
          (
            name: p.manifest.name.of(thai),
            category: p.manifest.category,
            persona: p.manifest.persona.of(thai),
            safety: p.manifest.safety.of(thai),
            tools: p.manifest.tools,
          ),
      ];

  /// ปิดซ้ำได้ · MindState ปิดตัวที่ได้รับมาตอนตัวเองปิด (เหมือนตัวต่อเน็ตอื่น ๆ)
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _http.close();
    super.dispose();
  }
}

class _TooBig implements Exception {
  const _TooBig();
}

/// ที่รับไบต์ที่แตกออกมา · เกินเพดานเมื่อไรหยุดทันที (ดู [KnowledgePacks._text])
class _CappedOutput extends OutputMemoryStream {
  _CappedOutput(this.cap);
  final int cap;

  void _room(int more) {
    if (length + more > cap) throw const _TooBig();
  }

  @override
  void writeByte(int value) {
    _room(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _room(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _room(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _room(count);
    super.writeBackReference(distance, count);
  }
}
