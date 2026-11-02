/// แพ็กความรู้ (lib/store/knowledge_pack.dart) · ด่านที่ถ้าหลุด ผู้ใช้เสียเงินหรือเสียความปลอดภัย
///
/// 1. zip จากร้านเป็นของที่เราไม่ได้เขียนเอง · path ออกนอกที่ ไฟล์โค้ด zip ระเบิด = ปฏิเสธทั้งแพ็ก
/// 2. ซื้อแล้วต้องอยู่ในเครื่องจริง เปิด/ปิด/ลบแล้วจำได้หลังปิดแอป
/// 3. ถามเรื่องในแพ็ก = ท่อนที่ตรงติดไปกับข้อความ · คุยเล่น = ไม่ดึงอะไรเข้า prompt
/// 4. กฎความปลอดภัยของแต่ละเรื่องมาจากแอป ไม่ใช่จากแพ็ก · ไม่เข้าสายโทรศัพท์
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/mind_persona.dart';
import 'package:videogirl/ai/realtime_chat.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/avatar/avatar_pack.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_ai.dart';
import 'package:videogirl/memory/knowledge_index.dart';
import 'package:videogirl/memory/mind_memory.dart';
import 'package:videogirl/screens/knowledge_reader_screen.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/store/knowledge_pack.dart';
import 'package:videogirl/store/pack_catalogue.dart';
import 'package:videogirl/theme/tokens.dart';

const _sampleDir = 'assets/knowledge/survival-basic';

/// แพ็กตัวอย่างที่มากับแอป บีบเป็น zip แบบที่ร้านจะส่งมา
List<int> _sampleZip() {
  final archive = Archive();
  for (final f in Directory(_sampleDir).listSync(recursive: true).whereType<File>()) {
    final rel = f.path.replaceAll(r'\', '/').substring(_sampleDir.length + 1);
    archive.add(ArchiveFile.bytes(rel, f.readAsBytesSync()));
  }
  return ZipEncoder().encodeBytes(archive);
}

Map<String, Object?> _manifest({String id = 'demo', String kind = 'knowledge', Map<String, Object?> extra = const {}}) =>
    {'id': id, 'kind': kind, 'version': '1.0.0', 'name': 'ทดสอบ', 'category': 'survival', ...extra};

List<int> _zip(Map<String, Object> files) {
  final archive = Archive();
  for (final e in files.entries) {
    final v = e.value;
    archive.add(ArchiveFile.bytes(e.key, v is List<int> ? v : utf8.encode(v is String ? v : jsonEncode(v))));
  }
  return ZipEncoder().encodeBytes(archive);
}

List<int> _pack({Map<String, Object?>? manifest, Map<String, Object> more = const {}}) => _zip({
      'manifest.json': manifest ?? _manifest(),
      'content/01.md': '# หัวข้อแรก\nเนื้อหาทดสอบเรื่องการต้มน้ำให้เดือดหนึ่งนาที\nที่มา: ทดสอบ',
      ...more,
    });

/// PNG ที่มีแค่หัวไฟล์ (พอให้ตัวอ่านขนาดอ่านได้ · ไม่ต้องแสดงได้จริง)
List<int> _png(int w, int h) {
  final b = ByteData(33);
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < 8; i++) {
    b.setUint8(i, sig[i]);
  }
  b.setUint32(8, 13);
  b.setUint32(12, 0x49484452); // IHDR
  b.setUint32(16, w);
  b.setUint32(20, h);
  b.setUint8(24, 8);
  b.setUint8(25, 6);
  return b.buffer.asUint8List();
}

/// JPEG: SOI · APP0 สั้น ๆ · SOF0 ที่บอกขนาด
List<int> _jpeg(int w, int h) => [
      0xFF, 0xD8, //
      0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00,
      0xFF, 0xC0, 0x00, 0x11, 0x08, h >> 8, h & 0xFF, w >> 8, w & 0xFF, 0x03,
      ...List.filled(9, 0),
    ];

/// WebP แบบ VP8X (ขนาดผืนภาพ -1 แบบ 24 บิต)
List<int> _webpX(int w, int h) => [
      ...ascii.encode('RIFF'), 0, 0, 0, 0, ...ascii.encode('WEBP'), ...ascii.encode('VP8X'), 10, 0, 0, 0,
      0, 0, 0, 0, //
      (w - 1) & 0xFF, (w - 1) >> 8 & 0xFF, (w - 1) >> 16,
      (h - 1) & 0xFF, (h - 1) >> 8 & 0xFF, (h - 1) >> 16,
    ];

Future<KnowledgePackError?> _errorOf(Future<Object?> f) async {
  try {
    await f;
    return null;
  } on KnowledgePackFailure catch (e) {
    return e.error;
  }
}

void main() {
  late Directory tmp;
  late List<KnowledgePacks> opened;

  KnowledgePacks packs({http.Client? client, String appVersion = '0.1.60'}) {
    final p = KnowledgePacks(
      client: client ?? MockClient((_) async => http.Response('', 404)),
      root: () async => Directory('${tmp.path}/knowledge-packs'),
      appVersion: () async => appVersion,
    );
    opened.add(p);
    return p;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('kp_test');
    opened = [];
  });

  tearDown(() {
    for (final p in opened) {
      p.dispose();
    }
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows ยังถือไฟล์ไว้ครู่หนึ่ง · โฟลเดอร์ชั่วคราว ไม่ต้องลบก็ได้
    }
  });

  group('ติดตั้ง เปิด/ปิด ลบ แล้วจำได้หลังปิดแอป', () {
    test('แพ็กตัวอย่างติดตั้งได้ เปิดใช้ทันที และอ่านช่องต่าง ๆ ถูก', () async {
      final kp = packs();
      final p = await kp.installZip(_sampleZip(), expectId: 'survival-basic');
      expect(p.id, 'survival-basic');
      expect(p.enabled, isTrue, reason: 'ซื้อมาเพื่อใช้ · ติดตั้งแล้วต้องเปิดเลย');
      expect(p.manifest.category, PackCategory.survival);
      expect(p.manifest.name.th, 'เอาตัวรอดในป่าเบื้องต้น');
      expect(p.manifest.tools, ['sos']);
      expect(p.manifest.starters.th, isNotEmpty);
      // ไทยกับอังกฤษอย่างละชุด แยกตามโฟลเดอร์ · หน้าอ่านเห็นเฉพาะภาษาของแอป
      expect(p.sectionsFor(true).length, greaterThanOrEqualTo(9));
      expect(p.sectionsFor(true).every((s) => s.lang == 'th'), isTrue);
      expect(p.sectionsFor(false).length, p.sectionsFor(true).length, reason: 'อังกฤษต้องครบทุกหัวข้อเท่าไทย');
      expect(p.sectionsFor(false).every((s) => s.lang == 'en'), isTrue);
      // ทุกหัวข้อมีที่มา · ท่อนที่ค้นเจอจึงบอกที่มาได้ทุกครั้ง
      for (final s in p.sections) {
        expect(s.text, contains(s.lang == 'en' ? 'Source:' : 'ที่มา'), reason: s.title);
        expect(s.text.length, lessThan(KnowledgeIndex.chunkChars), reason: 'ท่อนเกินถูกตัดกลาง ที่มาจะหลุดไปอีกท่อน: ${s.title}');
      }
      expect(kp.stage, KnowledgeInstallStage.idle);
    });

    test('ปิดแอปเปิดใหม่ แพ็กกับสวิตช์ยังอยู่ · ลบแล้วหายจริง', () async {
      final first = packs();
      await first.installZip(_sampleZip());
      await first.setEnabled('survival-basic', false);

      final second = packs();
      await second.load();
      expect(second.installed.single.id, 'survival-basic');
      expect(second.installed.single.enabled, isFalse);
      expect(second.enabled, isEmpty);

      await second.setEnabled('survival-basic', true);
      await second.remove('survival-basic');
      expect(second.installed, isEmpty);

      final third = packs();
      await third.load();
      expect(third.installed, isEmpty);
      expect(File('${tmp.path}/knowledge-packs/survival-basic.json').existsSync(), isFalse);
    });

    test('ติดตั้งรุ่นใหม่ทับ สวิตช์ที่ปิดไว้ต้องคงเดิม', () async {
      final kp = packs();
      await kp.installZip(_pack());
      await kp.setEnabled('demo', false);
      await kp.installZip(_pack(manifest: _manifest(extra: {'version': '1.1.0'})));
      expect(kp.byId('demo')!.manifest.version, '1.1.0');
      expect(kp.byId('demo')!.enabled, isFalse);
      expect(kp.installed, hasLength(1));
    });

    test('ไฟล์แพ็กในเครื่องเสีย = ข้ามแพ็กนั้น ไม่ใช่แอปค้าง', () async {
      final kp = packs();
      await kp.installZip(_pack());
      File('${tmp.path}/knowledge-packs/broken.json').writeAsStringSync('{not json');
      final again = packs();
      await again.load();
      expect(again.installed.map((p) => p.id), ['demo']);
    });

    test('กดติดตั้งซ้อนระหว่างอีกแพ็กยังโหลดอยู่ = บอกว่ากำลังติดตั้ง ไม่ใช่เขียนไฟล์ชนกัน', () async {
      final gate = Completer<void>();
      final zip = _pack();
      final kp = packs(
        client: MockClient((_) async {
          await gate.future;
          return http.Response.bytes(zip, 200);
        }),
      );
      final first = kp.install('https://shop.test/a.zip');
      expect(kp.busy, isTrue);
      expect(await _errorOf(kp.install('https://shop.test/b.zip')), KnowledgePackError.busy);
      expect(await _errorOf(kp.installZip(zip)), KnowledgePackError.busy);
      gate.complete();
      await first;
      expect(kp.busy, isFalse);
    });
  });

  group('โหลดจากร้าน', () {
    test('ไฟล์ตรงกับลายนิ้วมือ = ติดตั้ง · ไม่ตรง = ไม่ติดตั้งอะไรเลย', () async {
      final zip = _sampleZip();
      final kp = packs(client: MockClient((_) async => http.Response.bytes(zip, 200)));
      expect(
        await _errorOf(kp.install('https://shop.test/p.zip', sha256Hex: 'ab' * 32)),
        KnowledgePackError.hashMismatch,
      );
      expect(kp.installed, isEmpty);
      expect(kp.busy, isFalse, reason: 'ล้มแล้วแถบความคืบหน้าต้องหาย ไม่ค้าง');

      await kp.install('https://shop.test/p.zip', sha256Hex: sha256.convert(zip).toString().toUpperCase(),
          expectId: 'survival-basic');
      expect(kp.byId('survival-basic'), isNotNull);
    });

    test('ร้านไม่ให้โหลด (403) · ลิงก์ไม่ใช่เว็บ = เน็ต ไม่ใช่แพ็กเสีย', () async {
      final kp = packs(client: MockClient((_) async => http.Response('no', 403)));
      expect(await _errorOf(kp.install('https://shop.test/p.zip')), KnowledgePackError.network);
      expect(await _errorOf(kp.install('file:///etc/passwd')), KnowledgePackError.network);
      expect(await _errorOf(kp.install('not a url')), KnowledgePackError.network);
    });

    test('ร้านบอกขนาดเกินเพดาน = หยุดก่อนโหลด', () async {
      final kp = packs(
        client: MockClient.streaming((req, body) async => http.StreamedResponse(
              Stream.value([1, 2, 3]),
              200,
              contentLength: KnowledgePacks.maxZipBytes + 1,
            )),
      );
      expect(await _errorOf(kp.install('https://shop.test/p.zip')), KnowledgePackError.tooLarge);
    });

    test('ไม่บอกขนาด แต่ส่งมาเรื่อย ๆ = หยุดทันทีที่เกินเพดาน', () async {
      final chunk = List<int>.filled(1024 * 1024, 0);
      final kp = packs(
        client: MockClient.streaming((req, body) async => http.StreamedResponse(
              Stream.fromIterable(List.filled(20, chunk)),
              200,
            )),
      );
      expect(await _errorOf(kp.install('https://shop.test/p.zip')), KnowledgePackError.tooLarge);
    });

    test('ซื้อแพ็กหนึ่ง แต่ไฟล์ข้างในเป็นอีกแพ็ก = ปฏิเสธ', () async {
      final kp = packs();
      expect(await _errorOf(kp.installZip(_pack(), expectId: 'cooking-thai')), KnowledgePackError.badPack);
      expect(kp.installed, isEmpty);
    });

    test('แพ็กต้องการแอปรุ่นใหม่กว่า = บอกให้อัปเดต', () async {
      final kp = packs(appVersion: '0.1.60');
      expect(
        await _errorOf(kp.installZip(_pack(manifest: _manifest(extra: {'minAppVersion': '99.0.0'})))),
        KnowledgePackError.needsUpdate,
      );
      await kp.installZip(_pack(manifest: _manifest(extra: {'minAppVersion': '0.1.0'})));
      expect(kp.installed, hasLength(1));
    });
  });

  group('🔴 ด่าน zip ที่เราไม่ได้เขียนเอง', () {
    test('path ออกนอกที่ หรือ path เต็ม = ปฏิเสธทั้งแพ็ก', () {
      for (final bad in ['../evil.md', 'content/../../evil.md', '/etc/evil.md', 'C:/evil.md']) {
        final got = KnowledgePacks.unpack(_pack(more: {bad: 'x'}));
        expect(got.error, KnowledgePackError.badPack.name, reason: bad);
      }
    });

    test('ไฟล์โค้ดหรือไบนารีในแพ็ก = ปฏิเสธทั้งแพ็ก ไม่ใช่ข้ามเงียบ ๆ', () {
      for (final bad in ['content/run.js', 'lib/arm64/libx.so', 'classes.dex', 'content/page.html', 'tool.py']) {
        final got = KnowledgePacks.unpack(_pack(more: {bad: 'x'}));
        expect(got.error, KnowledgePackError.badPack.name, reason: bad);
      }
    });

    test('ไม่มี manifest · manifest ไม่ใช่ JSON · ไม่ใช่ zip = แพ็กเสีย', () {
      expect(KnowledgePacks.unpack(_zip({'content/a.md': 'x'})).error, KnowledgePackError.badPack.name);
      expect(KnowledgePacks.unpack(_zip({'manifest.json': '{oops', 'content/a.md': 'x'})).error,
          KnowledgePackError.badPack.name);
      expect(KnowledgePacks.unpack(utf8.encode('hello')).error, KnowledgePackError.badPack.name);
    });

    test('แพ็กชุดตัวละครหรือชนิดอื่น = ไม่ใช่แพ็กความรู้', () async {
      final kp = packs();
      expect(await _errorOf(kp.installZip(_pack(manifest: _manifest(kind: 'character')))),
          KnowledgePackError.notKnowledge);
    });

    test('รหัสที่ชนชื่อไฟล์ของแอปเอง (_state) = ปฏิเสธ', () async {
      final kp = packs();
      await kp.installZip(_pack());
      await kp.setEnabled('demo', false);
      expect(await _errorOf(kp.installZip(_pack(manifest: _manifest(id: '_state')))), KnowledgePackError.badPack);
      final again = packs();
      await again.load();
      expect(again.byId('demo')!.enabled, isFalse, reason: 'สวิตช์ของแพ็กอื่นต้องไม่ถูกเขียนทับ');
    });

    test('รหัสที่มี / หรือ .. ถูกล้างเป็นชื่อไฟล์ที่ปลอดภัย ไม่หลุดออกนอกโฟลเดอร์', () async {
      final kp = packs();
      expect(await _errorOf(kp.installZip(_pack(manifest: _manifest(id: '../../evil/x')))), KnowledgePackError.badPack);
      final p = await kp.installZip(_pack(manifest: _manifest(id: 'evil/../x')));
      expect(p.id, isNot(contains('/')));
      expect(Directory('${tmp.path}/knowledge-packs').listSync().whereType<File>().every((f) {
        return f.parent.path.replaceAll(r'\', '/').endsWith('knowledge-packs');
      }), isTrue);
    });

    test('ไฟล์ข้อความใหญ่เกินเพดาน = ใหญ่เกิน', () {
      final big = 'ก' * (KnowledgePacks.maxTextFileBytes ~/ 3 + 10);
      expect(KnowledgePacks.unpack(_pack(more: {'content/big.md': big})).error, KnowledgePackError.tooLarge.name);
    });

    test('zip ประกาศขนาดรวมเกินเพดาน (zip ระเบิด) = ใหญ่เกิน ก่อนแตกสักไบต์', () {
      final zeros = List<int>.filled(KnowledgePacks.maxUnpackedBytes + 1, 0);
      expect(KnowledgePacks.unpack(_pack(more: {'images/a.png': zeros})).error, KnowledgePackError.tooLarge.name);
    });

    test('🔴 zip โกหกขนาด (บอกว่าเล็ก แตกจริงใหญ่) = หยุดระหว่างแตก', () {
      final real = utf8.encode('a' * (KnowledgePacks.maxTextFileBytes + 4096));
      final bytes = _zip({'manifest.json': _manifest(), 'content/bomb.md': real});
      // แก้ช่อง "ขนาดหลังแตก" ทั้งหัวไฟล์และสารบัญท้าย zip ให้บอกว่าแค่ 100 ไบต์
      final data = ByteData.sublistView(Uint8List.fromList(bytes));
      var patched = 0;
      for (var i = 0; i + 30 < data.lengthInBytes; i++) {
        final sig = data.getUint32(i, Endian.little);
        if (sig == 0x04034b50 && data.getUint32(i + 22, Endian.little) == real.length) {
          data.setUint32(i + 22, 100, Endian.little);
          patched++;
        } else if (sig == 0x02014b50 && data.getUint32(i + 24, Endian.little) == real.length) {
          data.setUint32(i + 24, 100, Endian.little);
          patched++;
        }
      }
      expect(patched, 2, reason: 'ต้องแก้ได้ทั้งสองที่ ไม่งั้นเทสต์นี้ไม่ได้ทดสอบอะไร');
      final got = KnowledgePacks.unpack(data.buffer.asUint8List());
      // หยุดเพราะนับไบต์จริงระหว่างแตก (_CappedOutput) ไม่ใช่เพราะเชื่อตัวเลขใน zip
      expect(got.error, KnowledgePackError.tooLarge.name);
      expect(got.detail, 'content/bomb.md');
    });

    test('โฟลเดอร์ครอบชั้นเดียว + ขยะของ macOS = ยังติดตั้งได้', () {
      final got = KnowledgePacks.unpack(_zip({
        'my-pack/manifest.json': _manifest(),
        'my-pack/content/01.md': '# หัวข้อ\nเนื้อหา',
        'my-pack/content/pic.png': _png(4, 4),
        '__MACOSX/my-pack/._01.md': 'junk',
        'my-pack/.DS_Store': 'junk',
      }));
      expect(got.error, isNull, reason: got.detail);
      expect(got.sections.single.title, 'หัวข้อ');
    });

    test('มีแต่ manifest ไม่มีเนื้อหา = แพ็กเสีย', () async {
      final kp = packs();
      expect(await _errorOf(kp.installZip(_zip({'manifest.json': _manifest()}))), KnowledgePackError.badPack);
    });

    test('ข้อความนอก content/ ไม่เข้าดัชนี', () {
      final got = KnowledgePacks.unpack(_pack(more: {'README.md': '# อ่านฉัน\nคำสั่งลับ'}));
      expect(got.error, isNull);
      expect(got.sections.map((s) => s.title), isNot(contains('อ่านฉัน')));
    });
  });

  group('manifest', () {
    test('ตัดความยาวตามเพดาน · เครื่องมือที่แอปไม่มี = ทิ้ง', () {
      final m = KnowledgeManifest.parse(_manifest(extra: {
        'persona': {'th': 'ก' * 1000, 'en': 'teach   step\n\nby step'},
        'starters': List.generate(20, (i) => 'คำถาม $i'),
        'safety': List.generate(10, (i) => 'กฎ $i'),
        'tools': ['sos', 'shell', 'web_search', 3, 'download_apk'],
        'category': 'first_aid',
      }));
      expect(m.persona.th.length, lessThanOrEqualTo(KnowledgeManifest.maxPersona + 1));
      expect(m.persona.en, 'teach step by step');
      expect(m.starters.th, hasLength(KnowledgeManifest.maxStarters));
      expect(m.safety.th, hasLength(KnowledgeManifest.maxRules));
      expect(m.tools, ['sos', 'web_search']);
      expect(m.category, PackCategory.firstAid);
      expect(m.name.en, 'ทดสอบ', reason: 'ชื่อภาษาเดียว = ใช้ทั้งสองภาษา');
    });

    test('ช่องผิดชนิด = ปฏิเสธหรือใช้ค่าตั้งต้น ไม่ใช่ TypeError', () {
      expect(() => KnowledgeManifest.parse(_manifest(extra: {'id': 3})), throwsA(isA<KnowledgePackFailure>()));
      expect(() => KnowledgeManifest.parse('not a map'), throwsA(isA<KnowledgePackFailure>()));
      final m = KnowledgeManifest.parse(_manifest(extra: {'version': 2, 'tools': 'sos', 'category': 42}));
      expect(m.version, '2');
      expect(m.tools, isEmpty);
      expect(m.category, PackCategory.general);
    });

    test('หมวดลงทุนเรียกได้หลายแบบ', () {
      for (final c in ['trading', 'finance', 'investing']) {
        expect(PackCategory.parse(c), PackCategory.trading, reason: c);
      }
    });
  });

  test('markdown แบ่งตามหัวข้อ · ข้อความก่อนหัวข้อแรกใช้ชื่อไฟล์', () {
    final s = KnowledgePacks.markdownSections('01-lost', 'นำ\n# หนึ่ง\nก\n## สอง ##\nข\n#### ไม่ใช่หัวข้อ\nค');
    expect(s.map((e) => e.title), ['01-lost', 'หนึ่ง', 'สอง']);
    expect(s.last.text, contains('ไม่ใช่หัวข้อ'));
  });

  group('ค้นในแชท', () {
    test('คำถามตัวอย่างของแพ็กทุกข้อเจอท่อนที่ตรง · ท่อนบอกว่ามาจากแพ็กไหน', () async {
      final kp = packs();
      final p = await kp.installZip(_sampleZip());
      for (final q in p.manifest.starters.th) {
        final hits = await kp.search(q);
        expect(hits, isNotEmpty, reason: q);
        expect(hits.first.tag, 'survival-basic');
        expect(hits.length, lessThanOrEqualTo(KnowledgePacks.chatHits));
      }
      for (final q in p.manifest.starters.en) {
        final hits = await kp.search(q);
        expect(hits, isNotEmpty, reason: q);
        expect(RegExp('[\u0E00-\u0E7F]').hasMatch(hits.first.title), isFalse, reason: 'ถามอังกฤษ ต้องได้หัวข้ออังกฤษ: $q');
      }
      expect((await kp.search('โดนงูกัดต้องทำยังไง')).first.title, contains('งูกัด'));
      expect((await kp.search('ต้มน้ำกี่นาทีถึงจะดื่มได้')).first.text, contains('1 นาที'));
    });

    test('คุยเล่นทั่วไป = ไม่ดึงแพ็กเข้า prompt', () async {
      final kp = packs();
      await kp.installZip(_sampleZip());
      for (final q in [
        'สวัสดีค่ะ',
        'ช่วยตั้งนาฬิกาปลุกตีห้าหน่อย',
        'พรุ่งนี้มีนัดกี่โมง',
        'เล่าเรื่องตลกให้ฟังหน่อย',
        'คิดถึงจังเลย',
        'โทรหาแม่ให้หน่อย',
        'ขอบคุณมากนะ',
        'กินข้าวยัง',
        'ส่งไลน์หาพี่ต้นว่าเลื่อนประชุม',
        'เปิดเพลงให้หน่อย',
        'hello',
        'thanks a lot',
        'what time is it',
        'play some music please',
        'remind me to call mom tomorrow',
      ]) {
        expect(await kp.search(q), isEmpty, reason: q);
      }
    });

    test('ปิดแพ็กแล้วค้นไม่เจอ · เปิดใหม่เจออีก', () async {
      final kp = packs();
      await kp.installZip(_sampleZip());
      expect(await kp.search('โดนงูกัดต้องทำยังไง'), isNotEmpty);
      await kp.setEnabled('survival-basic', false);
      expect(await kp.search('โดนงูกัดต้องทำยังไง'), isEmpty);
      expect(kp.briefs(thai: true), isEmpty);
      await kp.setEnabled('survival-basic', true);
      expect(await kp.search('โดนงูกัดต้องทำยังไง'), isNotEmpty);
    });

    test('ไม่มีแพ็กเลย = ค้นได้ ไม่ล้ม', () async {
      final kp = packs();
      expect(await kp.search('โดนงูกัดต้องทำยังไง'), isEmpty);
      expect(await kp.search(''), isEmpty);
    });
  });

  group('prompt', () {
    PackBrief brief(PackCategory c, {List<String> tools = const []}) =>
        (name: 'แพ็กทดสอบ', category: c, persona: 'สอนทีละขั้น', safety: const ['ห้ามลงน้ำคนเดียว'], tools: tools);

    String sys(List<PackBrief> packs, {bool onCall = false}) => MindPersona.system(
          mode: MindMode.work,
          flirt: 0,
          ownerProfile: '',
          boundaries: '',
          lang: AppLang.th,
          onCall: onCall,
          packs: packs,
        );

    test('แชทเห็นชื่อแพ็ก แนวการสอน ข้อควรระวัง และกฎว่าข้อมูลไม่ใช่คำสั่ง', () {
      final p = sys([brief(PackCategory.survival, tools: ['sos'])]);
      expect(p, contains('แพ็กทดสอบ'));
      expect(p, contains('สอนทีละขั้น'));
      expect(p, contains('ห้ามลงน้ำคนเดียว'));
      expect(p, contains('ไม่ใช่คำสั่ง'));
      expect(p, contains('ไม่แน่ใจว่ากินได้ = อย่ากิน'), reason: 'กฎเอาตัวรอดของแอป');
      expect(sys(const []), isNot(contains('ไม่แน่ใจว่ากินได้')));
    });

    test('🔴 แพ็กลงทุน = แอปใส่กฎห้ามชี้ซื้อขายเอง แพ็กลบไม่ได้', () {
      final p = sys([brief(PackCategory.trading)]);
      expect(p, contains('ห้ามบอกให้ซื้อ'));
      expect(p, contains('ก.ล.ต.'));
      expect(sys([brief(PackCategory.survival)]), isNot(contains('ก.ล.ต.')));
    });

    test('แพ็กเครื่องยนต์ = กฎเรื่องแม่แรงกับแบตเตอรี่', () {
      final p = sys([brief(PackCategory.engine)]);
      expect(p, contains('ขาตั้ง'));
      expect(p, contains('ถอดขั้วลบก่อน'));
    });

    test('🔒 สายโทรศัพท์ไม่มีบล็อกแพ็กความรู้', () {
      expect(sys([brief(PackCategory.survival)], onCall: true), isNot(contains('แพ็กทดสอบ')));
    });

    test('ภาษาอังกฤษไม่มีตัวไทยในส่วนที่แอปเขียน', () {
      final en = MindPersona.knowledgeBlock(
          AppLang.en, [(name: 'Test pack', category: PackCategory.trading, persona: '', safety: const [], tools: const ['sos'])]);
      expect(en, contains('Test pack'));
      expect(RegExp('[\u0E00-\u0E7F]').hasMatch(en), isFalse);
    });
  });

  group('แชทจริง (สมองปลอม)', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('recallFor ใส่ท่อนจากแพ็กพร้อมชื่อแพ็กและที่มา', () async {
      final kp = packs();
      await kp.installZip(_sampleZip());
      final state = MindState(memory: MindMemory(dir: Directory('${tmp.path}/mem')), knowledgePacks: kp);
      final hits = await kp.search('โดนงูกัดต้องทำยังไง');
      final r = state.recallFor([(fromHer: false, text: 'โดนงูกัดต้องทำยังไง')], packs: hits);
      expect(r, contains(S(AppLang.th).recallPacks));
      expect(r, contains('เอาตัวรอดในป่าเบื้องต้น'));
      expect(r, contains('ที่มา'));
      expect(state.recallFor([(fromHer: false, text: 'โดนงูกัดต้องทำยังไง')]), isNot(contains(S(AppLang.th).recallPacks)));
    });

    test('ถามเรื่องในแพ็ก = ท่อนติดไปกับข้อความ · คุยเล่น = ไม่ติด · system prompt มีชื่อแพ็ก', () async {
      final kp = packs();
      await kp.installZip(_sampleZip());
      await kp.warm();
      final brain = _CapturingBrain();
      final s = MindState(
        openai: brain,
        memory: MindMemory(dir: Directory('${tmp.path}/mem')),
        knowledgePacks: kp,
      );
      await s.load();
      s.setBrain(BrainProvider.openai);
      await s.setOpenAiKey('sk-test-key-for-unit-tests');

      await s.send('โดนงูกัดต้องทำยังไง');
      expect(brain.systems.last, contains('เอาตัวรอดในป่าเบื้องต้น'));
      expect(brain.histories.last.last.text, contains(S(AppLang.th).recallPacks));
      expect(brain.histories.last.last.text, contains('งูกัด'));

      // ข้อความสั้น ("ขอบคุณ") ใช้ข้อความก่อนหน้าช่วยค้น (ดู recallQuery) = ท่อนเดิมติดมาได้ ·
      // ทดสอบด้วยเรื่องอื่นที่ยาวพอจะยืนเอง
      await s.send('ช่วยตั้งนาฬิกาปลุกตีห้าพรุ่งนี้หน่อยนะ');
      expect(brain.histories.last.last.text, isNot(contains(S(AppLang.th).recallPacks)));

      await kp.setEnabled('survival-basic', false);
      await s.send('โดนงูกัดต้องทำยังไง');
      expect(brain.systems.last, isNot(contains('เอาตัวรอดในป่าเบื้องต้น')));
      expect(brain.histories.last.last.text, isNot(contains(S(AppLang.th).recallPacks)));
      s.dispose();
    });
  });

  group('รูปในแพ็ก', () {
    test('รูปจริงติดตั้งลงเครื่อง หน้าอ่านหาไฟล์เจอ · ลบแพ็กแล้วรูปหายด้วย', () async {
      final kp = packs();
      final p = await kp.installZip(_pack(more: {
        'content/02.md': '# ปมเชือก\n![ปมพิรอด](../images/knot.png)\nผูกแบบนี้',
        'images/knot.png': _png(64, 48),
        'images/cover.jpg': _jpeg(800, 600),
      }));
      expect(p.images, ['images/cover.jpg', 'images/knot.png']);
      final files = await kp.imagesOf('demo');
      expect(files.keys, containsAll(['images/knot.png', 'images/cover.jpg']));
      expect(files['images/knot.png']!.readAsBytesSync(), _png(64, 48));

      final again = packs();
      await again.load();
      expect(again.byId('demo')!.images, hasLength(2), reason: 'ปิดแอปเปิดใหม่ รูปยังอยู่');

      await again.remove('demo');
      expect(files['images/knot.png']!.existsSync(), isFalse);
      expect(Directory('${tmp.path}/knowledge-packs/demo.img').existsSync(), isFalse);
    });

    test('path ต่างกันแต่หน้าตาคล้ายกัน = คนละไฟล์ ไม่ทับกัน', () async {
      final kp = packs();
      await kp.installZip(_pack(more: {'images/a/b.png': _png(10, 10), 'images__a/b.png': _png(20, 20)}));
      final files = await kp.imagesOf('demo');
      expect(files['images/a/b.png']!.readAsBytesSync(), _png(10, 10));
      expect(files['images__a/b.png']!.readAsBytesSync(), _png(20, 20));
    });

    test('ติดตั้งรุ่นใหม่ที่ไม่มีรูปแล้ว = รูปเก่าหายด้วย ไม่ค้างกินที่', () async {
      final kp = packs();
      await kp.installZip(_pack(more: {'images/a.png': _png(10, 10)}));
      await kp.installZip(_pack(manifest: _manifest(extra: {'version': '2'})));
      expect(kp.byId('demo')!.images, isEmpty);
      expect(Directory('${tmp.path}/knowledge-packs/demo.img').existsSync(), isFalse);
    });

    test('🔴 ไฟล์อื่นที่ตั้งชื่อเป็นรูป = ปฏิเสธทั้งแพ็ก', () {
      final got = KnowledgePacks.unpack(_pack(more: {'images/x.png': '<script>alert(1)</script>'}));
      expect(got.error, KnowledgePackError.badPack.name);
    });

    test('🔴 รูปที่ประกาศขนาดมหึมา (แตกแล้วกินแรมเป็นกิกะไบต์) = ใหญ่เกิน', () {
      expect(KnowledgePacks.unpack(_pack(more: {'images/x.png': _png(30000, 30000)})).error,
          KnowledgePackError.tooLarge.name);
      expect(KnowledgePacks.unpack(_pack(more: {'images/x.jpg': _jpeg(5000, 100)})).error,
          KnowledgePackError.tooLarge.name);
    });

    test('รูปไฟล์ใหญ่เกิน · รูปเยอะเกิน = ใหญ่เกิน', () {
      final big = [..._png(100, 100), ...List.filled(KnowledgePacks.maxImageBytes, 0)];
      expect(KnowledgePacks.unpack(_pack(more: {'images/big.png': big})).error, KnowledgePackError.tooLarge.name);
      final many = {for (var i = 0; i <= KnowledgePacks.maxImages; i++) 'images/$i.png': _png(4, 4) as Object};
      expect(KnowledgePacks.unpack(_pack(more: many)).error, KnowledgePackError.tooLarge.name);
    });

    test('อ่านขนาดจากหัวไฟล์ PNG · JPEG · WebP', () {
      expect(KnowledgePacks.imageSize(Uint8List.fromList(_png(640, 480))), (640, 480));
      expect(KnowledgePacks.imageSize(Uint8List.fromList(_jpeg(1024, 768))), (1024, 768));
      expect(KnowledgePacks.imageSize(Uint8List.fromList(_webpX(300, 200))), (300, 200));
      expect(KnowledgePacks.imageSize(Uint8List.fromList(utf8.encode('GIF89a......'))), isNull);
    });

    test('path รูปที่คนทำแพ็กเขียน → path จากรากแพ็ก · path อันตราย = ไม่ใช้', () {
      expect(KnowledgePacks.imageRef('../images/a.png'), 'images/a.png');
      expect(KnowledgePacks.imageRef('./images/a.png'), 'images/a.png');
      expect(KnowledgePacks.imageRef('images/a.PNG'), 'images/a.PNG');
      expect(KnowledgePacks.imageRef('/etc/a.png'), isNull);
      expect(KnowledgePacks.imageRef('images/../../a.png'), isNull);
      expect(KnowledgePacks.imageRef('C:/a.png'), isNull);
      expect(KnowledgePacks.imageRef('images/a.svg'), isNull);
    });

    test('สมองกับตัวค้นเห็นแค่คำบรรยายรูป ไม่เห็น path', () async {
      expect(KnowledgePacks.plain('ก่อน ![ปมพิรอด](images/knot.png "x") หลัง'), 'ก่อน ปมพิรอด หลัง');
      final kp = packs();
      await kp.installZip(_pack(more: {
        'content/02.md': '# ผูกปมพิรอดยังไง\n![ปมพิรอด](images/knot.png)\nไขว้ขวาทับซ้าย แล้วซ้ายทับขวา\nที่มา: ทดสอบ',
        'images/knot.png': _png(10, 10),
      }));
      final hits = await kp.search('ผูกปมพิรอดยังไง');
      expect(hits.first.text, isNot(contains('images/')));
      expect(hits.first.text, contains('ปมพิรอด'));
    });
  });

  group('คุยสดด้วยเสียง (Realtime)', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('มีแพ็กเปิดอยู่ = มีเครื่องมือค้นแพ็ก และ prompt สอนให้เรียกก่อนตอบ', () async {
      expect(chatVoiceTools(web: false, phone: false).map((t) => t['name']), isNot(contains('knowledge_lookup')));
      expect(chatVoiceTools(web: false, phone: false, knowledge: true).map((t) => t['name']), contains('knowledge_lookup'));

      final kp = packs();
      final s = MindState(memory: MindMemory(dir: Directory('${tmp.path}/mem')), knowledgePacks: kp);
      expect(s.voiceChatPrompt(), isNot(contains('knowledge_lookup')));
      await kp.installZip(_sampleZip());
      final p = s.voiceChatPrompt();
      expect(p, contains('knowledge_lookup'));
      expect(p, contains('เอาตัวรอดในป่าเบื้องต้น'));
      expect(p, isNot(contains('ระบบจะแนบ')), reason: 'คุยสดไม่มีการแนบท่อนทีละตา ห้ามบอกเธอว่ามี');
    });

    test('เธอเรียกค้น = ได้ท่อนพร้อมชื่อแพ็ก · ไม่มีในแพ็ก = บอกให้ตอบตามจริง', () async {
      final kp = packs();
      await kp.installZip(_sampleZip());
      final s = MindState(memory: MindMemory(dir: Directory('${tmp.path}/mem')), knowledgePacks: kp);
      final hit = await s.runVoiceTool('knowledge_lookup', {'query': 'งูกัด'});
      expect(hit, contains('เอาตัวรอดในป่าเบื้องต้น'));
      expect(hit, contains('1669'));
      final en = await s.runVoiceTool('knowledge_lookup', {'query': 'snake bite first aid'});
      expect(en, contains('Antivenom'));
      final none = await s.runVoiceTool('knowledge_lookup', {'query': 'สูตรแกงเขียวหวาน'});
      expect(none, contains('nothing on this'));
      expect(await s.runVoiceTool('knowledge_lookup', {}), contains('Ask the owner'));
    });
  });

  group('หน้าอ่านแพ็ก', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    const twoLang = {
      'content/th/01.md': '# ต้มน้ำ\nต้มให้เดือดหนึ่งนาที\n![หม้อบนไฟ](../../images/pot.png)\n- ใช้ภาชนะโลหะ\nที่มา: ทดสอบ',
      'content/en/01.md': '# Boiling water\nBoil for one minute\n![A pot on the fire](../../images/pot.png)\nSource: test',
    };

    Future<KnowledgePacks> mount(WidgetTester t, {String lang = 'th', ValueChanged<String>? onAsk}) async {
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      // สร้างนอกเวลาเทียมของ widget test · คิวงานของแพ็ก (_serial) ผูกกับ zone ที่สร้าง
      // สร้างในเวลาเทียม = งานติดตั้งใน runAsync รอ microtask ที่ไม่มีใคร pump (ค้างจนหมดเวลา)
      final kp = (await t.runAsync(() async => packs()))!;
      await t.runAsync(() => kp.installZip(_zip({
            'manifest.json': _manifest(),
            ...twoLang,
            'images/pot.png': _png(40, 30),
          })));
      final state = MindState(memory: MindMemory(dir: Directory('${tmp.path}/mem')), knowledgePacks: kp);
      await t.pumpWidget(ChangeNotifierProvider<MindState>.value(
        value: state,
        child: MaterialApp(
          locale: Locale(lang),
          supportedLocales: const [Locale('en'), Locale('th')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: KnowledgeReaderScreen(packId: 'demo', onAsk: onAsk),
        ),
      ));
      // รายชื่อรูปอ่านจากดิสก์จริง · ต้องให้ IO จริงได้วิ่งก่อน
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pump();
      return kp;
    }

    testWidgets('เห็นหัวข้อภาษาของแอป รายการ และรูปพร้อมคำบรรยาย · ไม่เห็น markdown ดิบ', (t) async {
      await mount(t);
      expect(find.text('ต้มน้ำ'), findsOneWidget);
      expect(find.text('Boiling water'), findsNothing);
      expect(find.textContaining('• ใช้ภาชนะโลหะ'), findsOneWidget);
      expect(find.text('หม้อบนไฟ'), findsOneWidget, reason: 'คำบรรยายใต้รูป');
      expect(find.byType(Image), findsOneWidget);
      expect(find.textContaining('images/'), findsNothing);
      expect(find.textContaining('!['), findsNothing);
    });

    testWidgets('แอปภาษาอังกฤษ = หัวข้ออังกฤษ', (t) async {
      await mount(t, lang: 'en');
      expect(find.text('Boiling water'), findsOneWidget);
      expect(find.text('ต้มน้ำ'), findsNothing);
      expect(find.text('A pot on the fire'), findsOneWidget);
    });

    testWidgets('ถามมายด์เรื่องนี้ = ส่งชื่อหัวข้อกลับไป · เปิดจากที่ไม่มีแชท = ไม่มีปุ่ม', (t) async {
      final asked = <String>[];
      await mount(t, onAsk: asked.add);
      await t.tap(find.text('ถามมายด์เรื่องนี้'));
      await t.tap(find.text('ถามมายด์เรื่องนี้'));
      await t.pump();
      expect(asked, ['ต้มน้ำ'], reason: 'กดซ้ำระหว่างหน้าปิด = ไม่ส่งคำถามซ้ำ');
    });

    testWidgets('🔴 เปิดจากร้าน: ถามแล้วหน้าอ่านและร้านปิดทั้งคู่ เห็นแชทที่เพิ่งถาม', (t) async {
      // เจอบนเครื่องจริง (v0.1.63): หน้าอ่านปิดด้วย maybePop แล้วร้านปิดตามทันที ·
      // maybePop รอหนึ่งจังหวะ ร้านจึงยังเห็นหน้าอ่านอยู่บนสุด Flutter ทิ้งการปิดร้าน = ร้านค้างบังแชท
      await mount(t);
      final asked = <String>[];
      final home = t.element(find.byType(KnowledgeReaderScreen));
      Navigator.of(home).pushReplacement(MaterialPageRoute<void>(builder: (_) => const Text('แชท')));
      await t.pumpAndSettle();
      Navigator.of(t.element(find.text('แชท'))).push(MaterialPageRoute<void>(
        builder: (shop) => Scaffold(
          body: TextButton(
            child: const Text('อ่าน'),
            // เหมือน ShopScreen._read/_ask: ร้านปิดตัวเองด้วย maybePop แล้วส่งคำถามไปแชท
            onPressed: () => Navigator.of(shop).push(MaterialPageRoute<void>(
              builder: (_) => KnowledgeReaderScreen(
                packId: 'demo',
                onAsk: (q) {
                  Navigator.of(shop).maybePop();
                  asked.add(q);
                },
              ),
            )),
          ),
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('อ่าน'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await t.pumpAndSettle();
      await t.tap(find.text('ถามมายด์เรื่องนี้'));
      await t.pumpAndSettle();
      expect(asked, ['ต้มน้ำ']);
      expect(find.byType(KnowledgeReaderScreen), findsNothing);
      expect(find.text('อ่าน'), findsNothing, reason: 'ร้านต้องปิดตาม');
      expect(find.text('แชท'), findsOneWidget);
    });

    testWidgets('ไม่มีปุ่มถามเมื่อไม่มีที่ให้ถาม', (t) async {
      await mount(t);
      expect(find.text('ถามมายด์เรื่องนี้'), findsNothing);
    });

    testWidgets('🔴 ลบแพ็กระหว่างเปิดอ่าน = บอกว่าแพ็กหายไปแล้ว ไม่ใช่จอแดง', (t) async {
      final kp = await mount(t);
      await t.runAsync(() => kp.remove('demo'));
      await t.pump();
      expect(find.text('แพ็กนี้ถูกลบออกจากเครื่องแล้ว'), findsOneWidget);
      expect(find.text('ต้มน้ำ'), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('ร้าน', () {
    test('รายการในร้านชนิดแพ็กความรู้ พร้อมรุ่นและคำอธิบายสองภาษา', () {
      final item = ShopItem.fromJson({
        'id': 'survival-basic',
        'name': {'th': 'เอาตัวรอด', 'en': 'Survival'},
        'kind': 'knowledge',
        'price': '0.00',
        'version': 1.1,
        'summary': {'th': 'สรุป', 'en': 'Summary'},
      })!;
      expect(item.kind, AvatarPackKind.knowledge);
      expect(item.version, '1.1');
      expect(item.summaryFor(true), 'สรุป');
      expect(item.summaryFor(false), 'Summary');
      expect(ShopItem.fromJson({'id': 'x', 'summary': 'เดียว'})!.summaryFor(false), 'เดียว');
      expect(AvatarPackKind.parse('knowledge'), AvatarPackKind.knowledge);
    });

    test('🔴 ขอรายการร้านพร้อม with=knowledge · หลังบ้านซ่อนแพ็กความรู้จากแอปรุ่นเก่าได้', () async {
      final seen = <Uri>[];
      final shop = PackCatalogue(
        httpClient: MockClient((req) async {
          seen.add(req.url);
          return http.Response(jsonEncode({'packs': []}), 200);
        }),
      );
      await shop.load('https://shop.test/');
      expect(seen.single.path, '/api/packs');
      expect(seen.single.queryParameters['with'], 'knowledge');
      shop.dispose();
    });
  });
}

/// สมองปลอมที่จด system prompt กับประวัติที่ได้รับทุกครั้ง
class _CapturingBrain extends OpenAiClient {
  final systems = <String>[];
  final histories = <List<Turn>>[];

  @override
  bool get usable => true;

  @override
  Future<String> reply({required String system, required List<Turn> history, String? model}) async {
    systems.add(system);
    histories.add(history);
    return 'ค่ะ';
  }

  @override
  void close() {}
}
