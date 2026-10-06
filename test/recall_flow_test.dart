/// ระบบนึกออกต่อกับเธอจริง — ความจำ บทสนทนาเก่า และการสกัดที่แก้ข้อเดิม
///
/// ที่มา: เจ้าของถาม "ระบบ RAG ของเธอ ความทรงจำของเธอ ใช้งานได้ดีหรือยัง" ·
/// คำตอบตอนนั้นคือยัง: ความจำเกิน 60 ข้อแล้วเรื่องเก่าหลุดถาวร บทสนทนาเก่า
/// ค้นไม่ได้ และเรื่องที่ขัดกันถูกเก็บไว้ทั้งคู่
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/memory/chat_recall.dart';
import 'package:videogirl/memory/distiller.dart';
import 'package:videogirl/memory/mind_memory.dart';
import 'package:videogirl/state/mind_state.dart';

/// เรื่องจริงที่หลากหลาย (ไม่ใช่ประโยคเดิมเปลี่ยนเลข ซึ่งตัวกันจำซ้ำจะตัดทิ้ง)
List<String> _filler(int n) {
  const places = ['สยาม', 'บางนา', 'สีลม', 'อารีย์', 'ทองหล่อ', 'เอกมัย', 'ลาดพร้าว', 'รังสิต', 'นนทบุรี', 'บางแสน'];
  const doing = ['วิ่งออกกำลังกาย', 'ซื้อหนังสือการ์ตูน', 'ทานอาหารญี่ปุ่น', 'เรียนว่ายน้ำ', 'พบลูกค้าองค์กร', 'ตัดผมร้านประจำ'];
  return [
    for (var i = 0; i < n; i++) 'เจ้าของไป${places[i % places.length]}เพื่อ${doing[(i ~/ places.length) % doing.length]}',
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('🔴 เรื่องเก่าที่หลุดจากแกนต้องถูกนึกออก', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('recall_flow'));
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } on Object {
        // ไม่ใช่เรื่องที่ต้องแดง
      }
    });

    test('แพ้กุ้ง (จำไว้ก่อนอีก 60 เรื่อง) → ถามเรื่องต้มยำกุ้งแล้วนึกออก', () async {
      final state = MindState(memory: MindMemory(dir: tmp));
      addTearDown(state.dispose);
      await state.memory.remember('เจ้าของแพ้กุ้ง กินแล้วผื่นขึ้น');
      for (final f in _filler(60)) {
        expect(await state.memory.remember(f), isTrue, reason: f);
      }
      final core = state.memory.promptBlock(limit: MindState.coreMemories);
      expect(core, isNot(contains('แพ้กุ้ง')),
          reason: 'สมมติฐานของเทสต์: เรื่องนี้หลุดจากแกนแล้ว (ของเดิมจะหายไปเลย)');

      final recall = state.recallFor([
        (fromHer: false, text: 'เย็นนี้สั่งต้มยำกุ้งมากินดีไหม'),
      ]);
      expect(recall, contains('แพ้กุ้ง'));
    });

    test('ทักทายเฉย ๆ = ไม่แนบอะไร (ไม่เปลือง token ไม่ชวนเธอพูดนอกเรื่อง)', () async {
      final state = MindState(memory: MindMemory(dir: tmp));
      addTearDown(state.dispose);
      for (final f in _filler(40)) {
        await state.memory.remember(f);
      }
      expect(state.recallFor([(fromHer: false, text: 'สวัสดีค่ะ')]), isEmpty);
    });

    test('ข้อความสั้นแบบถามต่อ ใช้ข้อความก่อนหน้าช่วยบอกเรื่อง', () async {
      final state = MindState(memory: MindMemory(dir: tmp));
      addTearDown(state.dispose);
      await state.memory.remember('หมาของเจ้าของชื่อโบโบ้ พันธุ์ชิวาว่า');
      for (final f in _filler(40)) {
        await state.memory.remember(f);
      }
      final recall = state.recallFor([
        (fromHer: false, text: 'โบโบ้ไม่ยอมกินข้าวเลย'),
        (fromHer: true, text: 'ตั้งแต่เมื่อไหร่คะ'),
        (fromHer: false, text: 'สองวันแล้ว'),
      ]);
      expect(recall, contains('โบโบ้'));
    });
  });

  group('แนบหน้าข้อความล่าสุดเท่านั้น', () {
    test('ไม่แตะบรรทัดก่อนหน้า · ไม่มีอะไรนึกออก = เหมือนเดิมทุกตัวอักษร', () {
      final h = [
        (fromHer: false, text: 'ก'),
        (fromHer: true, text: 'ข'),
        (fromHer: false, text: 'ค'),
      ];
      final out = MindState.withRecall(h, 'NOTE');
      expect(out[0].text, 'ก');
      expect(out[1].text, 'ข');
      expect(out.last.text, 'NOTE\n\nค');
      expect(identical(MindState.withRecall(h, ''), h), isTrue);
    });

    test('🔴 สมองในเครื่อง: บันทึกช่วยจำไม่ลงสิ่งที่ session จำ (ไม่งั้นเปิด session ใหม่ทุกตา)', () {
      final src = File('lib/ai/local_brain.dart').readAsStringSync();
      expect(src, contains(r"recall.isEmpty ? said : '$recall\n\n$said'"));
      expect(src, contains('_fed = [for (final t in history) t.text, text.trim()]'));
      final state = File('lib/state/mind_state.dart').readAsStringSync();
      expect(state, contains('memories: memory.promptBlock(limit: coreMemories)'),
          reason: 'system prompt ต้องนิ่ง ไม่เปลี่ยนตามคำถาม');
    });
  });

  group('บทสนทนาเก่า', () {
    ChatRecall seeded() {
      final r = ChatRecall();
      var id = 1;
      final day = DateTime(2026, 9, 1);
      void say(bool her, String t) =>
          r.add((id: id++, fromHer: her, text: t, at: day.add(Duration(minutes: id))));
      say(false, 'ช่วยจำไว้ว่ารหัสห้องประชุมใหญ่ชั้นเจ็ดคือห้อง Orchid');
      say(true, 'จำไว้แล้วค่ะ ห้อง Orchid ชั้นเจ็ด');
      for (var i = 0; i < 40; i++) {
        say(false, 'วันนี้งานเยอะมาก เรื่องที่ $i');
        say(true, 'สู้ ๆ นะคะ พักบ้างนะ ($i)');
      }
      return r;
    }

    test('ถามเรื่องที่เคยคุย → ได้คู่ "เจ้าของพูด → เธอตอบ" กลับมา', () {
      final hits = seeded().search('ห้องประชุมใหญ่ชื่ออะไรนะ');
      expect(hits, isNotEmpty);
      expect(hits.first.ask, contains('Orchid'));
      expect(hits.first.answer, contains('ชั้นเจ็ด'));
    });

    test('บรรทัดที่อยู่ในหน้าต่างบทสนทนาแล้วไม่นึกซ้ำ', () {
      final r = ChatRecall()
        ..add((id: 1, fromHer: false, text: 'ห้อง Orchid ชั้นเจ็ด', at: DateTime(2026)))
        ..add((id: 2, fromHer: true, text: 'รับทราบค่ะ', at: DateTime(2026)));
      expect(r.search('ห้อง Orchid', skipNewest: 16), isEmpty);
      expect(r.search('ห้อง Orchid', skipNewest: 0), isNotEmpty);
    });

    test('เกินเพดานทิ้งบรรทัดเก่าสุด', () {
      final r = ChatRecall(maxLines: 10);
      for (var i = 1; i <= 25; i++) {
        r.add((id: i, fromHer: false, text: 'ข้อความทดสอบที่ $i', at: DateTime(2026)));
      }
      expect(r.size, 10);
    });
  });

  group('🔴 ความจำไม่พอกด้วยเรื่องเดิม และเรื่องใหม่แทนเรื่องเก่า', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('recall_mem'));
    tearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } on Object {
        // ไม่ใช่เรื่องที่ต้องแดง
      }
    });

    test('🔴 ตัวเลขต่างกัน = คนละเรื่อง ไม่ว่าจะเขียนใกล้กันแค่ไหน', () {
      expect(MindMemory.sameFact('ลูกคนโตอายุ 5 ขวบ', 'ลูกคนโตอายุ 7 ขวบ'), isFalse);
      expect(MindMemory.sameFact('จอดรถชั้น 3 ช่อง 12', 'จอดรถชั้น 3 ช่อง 12 ค่ะ'), isTrue);
      expect(MindMemory.sameFact('เจ้าของประชุมทีมทุกวันจันทร์', 'เจ้าของประชุมทีมทุกวันพุธ'),
          isFalse);
    });

    test('เรื่องเดิมที่เขียนต่างนิดเดียว = ไม่จำซ้ำ', () async {
      final m = MindMemory(dir: tmp);
      expect(await m.remember('เจ้าของแพ้กุ้ง'), isTrue);
      expect(await m.remember('เจ้าของแพ้กุ้งค่ะ'), isFalse);
      expect(await m.remember('เจ้าของชอบแมว'), isTrue);
      expect(m.count, 2);
    });

    test('ย้ายบ้าน → แก้ข้อเดิม ไม่เก็บทั้งเก่าและใหม่ · ปักหมุดยังอยู่', () async {
      final m = MindMemory(dir: tmp);
      await m.remember('เจ้าของอยู่คอนโดย่านอโศก กรุงเทพ');
      await m.setPinned(m.facts.single.id, true);
      await m.remember('เจ้าของชอบแมว');

      final raw = 'replace|เจ้าของอยู่คอนโดย่านอโศก กรุงเทพ|เจ้าของย้ายไปอยู่บ้านที่เชียงใหม่แล้ว\n'
          'TREAT|0\nWOO|1';
      final facts = parseDistilled(raw);
      expect(facts.single.replaces, isNotNull);
      await m.replace(facts.single.replaces!, facts.single.text);

      expect(m.count, 2);
      final home = m.facts.firstWhere((f) => f.text.contains('เชียงใหม่'));
      expect(home.pinned, isTrue);
      expect(m.facts.any((f) => f.text.contains('อโศก')), isFalse);
    });

    test('replace ที่หาข้อเดิมไม่เจอ = จำเป็นเรื่องใหม่ (ไม่ทิ้งของ)', () async {
      final m = MindMemory(dir: tmp);
      await m.remember('เจ้าของชอบแมว');
      await m.replace('เจ้าของทำงานที่ธนาคาร', 'เจ้าของย้ายไปทำงานสตาร์ทอัพ');
      expect(m.count, 2);
      expect(m.facts.any((f) => f.text.contains('แมว')), isTrue);
    });

    test('replace ที่มีความลับ = ทิ้ง', () {
      expect(parseDistilled('replace|รหัสเก่า|password: hunter2xyz'), isEmpty);
    });

    test('ข้อที่แก้แล้วค้นด้วยข้อความใหม่เจอ (ดัชนีไม่ค้างของเก่า)', () async {
      final m = MindMemory(dir: tmp);
      await m.remember('เจ้าของอยู่กรุงเทพ');
      for (var i = 0; i < 10; i++) {
        await m.remember('เรื่องอื่นหมายเลข $i ที่ไม่เกี่ยวกัน');
      }
      expect(m.recall('กรุงเทพ'), isNotEmpty);
      await m.replace('เจ้าของอยู่กรุงเทพ', 'เจ้าของย้ายไปเชียงใหม่');
      expect(m.recall('เชียงใหม่').single.text, 'เจ้าของย้ายไปเชียงใหม่');
      expect(m.recall('กรุงเทพ'), isEmpty);
    });
  });
}
