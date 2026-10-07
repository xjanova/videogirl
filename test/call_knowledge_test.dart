/// ข้อมูลที่น้องมายใช้ตอบสาย · ตอบได้แค่ไหน · ห้ามตอบอะไร · นำเข้าจากไฟล์
///
/// ที่มา: เจ้าของ "ให้พร้อมข้อมูลหรืออัพโหลดไฟล์ที่มายด์จะใช้ตอบได้แค่ไหนไว้ ห้ามตอบอะไรไว้ได้"
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/mind_persona.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/phone/call_knowledge.dart';
import 'package:videogirl/screens/text_editor_screen.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';
import 'package:videogirl/theme/tokens.dart';

Uint8List _docx(List<String> paragraphs) {
  final body = paragraphs.map((p) => '<w:p><w:r><w:t>$p</w:t></w:r></w:p>').join();
  final xml = '<?xml version="1.0"?><w:document><w:body>$body</w:body></w:document>';
  final a = Archive()..addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(xml)));
  return ZipEncoder().encodeBytes(a);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('อ่านไฟล์', () {
    test('txt / md / csv = ข้อความตรง ๆ · ตัด BOM', () {
      final bom = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('เปิด 9 โมง')]);
      expect(CallKnowledge.textOf('hours.txt', bom), 'เปิด 9 โมง');
      expect(CallKnowledge.textOf('faq.md', utf8.encode('# ราคา')), '# ราคา');
      expect(CallKnowledge.textOf('price.csv', utf8.encode('a,b')), 'a,b');
    });

    test('Word .docx = ข้อความทีละย่อหน้า · แปลง &amp; กลับ', () {
      final t = CallKnowledge.textOf('info.docx', _docx(['ร้านเปิด 9 โมง', 'ส่งฟรี &amp; เก็บเงินปลายทาง']));
      expect(t, contains('ร้านเปิด 9 โมง\n'));
      expect(t, contains('ส่งฟรี & เก็บเงินปลายทาง'));
    });

    test('PDF / ไฟล์อื่น / ไบนารีที่ตั้งชื่อ .txt = อ่านไม่ได้ (ไม่เอาขยะเข้า prompt)', () {
      expect(CallKnowledge.textOf('a.pdf', utf8.encode('%PDF-1.7')), isNull);
      expect(CallKnowledge.textOf('a.docx', utf8.encode('not a zip')), isNull);
      final junk = Uint8List.fromList(List.generate(400, (i) => 0x80 + i % 60));
      expect(CallKnowledge.textOf('a.txt', junk), isNull);
    });

    test('ยุบบรรทัดว่างซ้อน · ตัดที่เพดาน', () {
      expect(CallKnowledge.clean('a\r\n\r\n\r\n\r\nb  \n'), 'a\n\nb');
      expect(CallKnowledge.clean('ก' * 9000).length, CallKnowledge.maxChars);
    });

    group('ตัวเลือกไฟล์ของระบบ', () {
      Object? reply;
      setUp(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(kSystemChannel, (call) async => call.method == 'pickTextFile' ? reply : null);
      });
      tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kSystemChannel, null));

      test('เลือกไฟล์ข้อความ = ได้ข้อความ · ยกเลิก = null · อ่านไม่ได้/ใหญ่เกิน = ""', () async {
        reply = {'name': 'faq.txt', 'bytes': Uint8List.fromList(utf8.encode('ส่งฟรี\n\n\n\nทุกวัน'))};
        expect(await CallKnowledge.pick(), 'ส่งฟรี\n\nทุกวัน');
        reply = null;
        expect(await CallKnowledge.pick(), isNull);
        reply = {'name': 'scan.pdf', 'bytes': Uint8List.fromList(utf8.encode('%PDF'))};
        expect(await CallKnowledge.pick(), '');
        reply = {'name': 'huge.txt'};
        expect(await CallKnowledge.pick(), '');
      });
    });
  });

  group('ค่าตั้ง', () {
    Future<MindState> loaded() async {
      final s = MindState();
      addTearDown(s.dispose);
      await s.load();
      return s;
    }

    test('เก็บข้ามการเปิดแอปใหม่ · ตัดที่เพดาน', () async {
      final a = await loaded();
      a
        ..setCallKnowledge('เปิด 9 โมงถึง 6 โมงเย็น')
        ..setCallOnlyKnowledge(true)
        ..setCallNoGo('ราคาส่ง\nเบอร์มือถือเจ้าของ');
      final b = await loaded();
      expect(b.callKnowledge, 'เปิด 9 โมงถึง 6 โมงเย็น');
      expect(b.callOnlyKnowledge, isTrue);
      expect(b.callNoGo, 'ราคาส่ง\nเบอร์มือถือเจ้าของ');

      b.setCallNoGo('x' * 5000);
      expect(b.callNoGo.length, CallKnowledge.maxNoGoChars);
    });

    test('🔴 prompt ของสายมีข้อมูล ขอบเขต และข้อห้ามที่เจ้าของตั้ง', () async {
      final s = await loaded();
      s
        ..setCallKnowledge('ร้านเปิด 9 โมง')
        ..setCallNoGo('ราคาส่ง');
      final p = s.callPrompt(live: true);
      expect(p, contains('=== ข้อมูลที่เจ้าของให้ใช้ตอบคนโทร ==='));
      expect(p, contains('ร้านเปิด 9 โมง'));
      expect(p, contains('ห้ามแต่งเพิ่มสิ่งที่ไม่มีในนี้'));
      expect(p, contains('=== ห้ามตอบหรือห้ามบอกคนโทร ==='));
      expect(p, contains('ราคาส่ง'));
      expect(p, isNot(contains('=== ตอบได้แค่ไหน ===')), reason: 'ยังไม่ได้เปิด "ตอบเฉพาะเรื่องในข้อมูล"');

      s.setCallOnlyKnowledge(true);
      expect(s.callPrompt(), contains('ตอบได้เฉพาะเรื่องที่อยู่ในข้อมูลข้างบนเท่านั้น'));
    });

    test('ไม่ได้ตั้งอะไร = ไม่มีบล็อกเปล่า ๆ ใน prompt', () async {
      final s = await loaded();
      final p = s.callPrompt();
      expect(p, isNot(contains('ข้อมูลที่เจ้าของให้ใช้ตอบคนโทร')));
      expect(p, isNot(contains('ห้ามตอบหรือห้ามบอกคนโทร')));
    });

    test('เปิด "ตอบเฉพาะข้อมูล" แต่ไม่มีข้อมูล = ไม่ตอบอะไรเอง รับฝากอย่างเดียว', () async {
      final s = await loaded();
      s.setCallOnlyKnowledge(true);
      expect(s.callPrompt(), contains('ห้ามตอบคำถามเรื่องใดเองเลย'));
    });
  });

  group('prompt', () {
    String sys({required bool onCall, OutgoingLike? outgoing}) => MindPersona.system(
          mode: MindMode.work,
          flirt: 0,
          ownerProfile: '',
          boundaries: '',
          lang: AppLang.th,
          onCall: onCall,
          outgoing: outgoing,
          callKnowledge: 'ร้านเปิด 9 โมง',
          callOnlyKnowledge: true,
          callNoGo: 'ราคาส่ง',
        );

    test('แชทของเจ้าของไม่มีบล็อกนี้ (ของสำหรับคนโทรเท่านั้น)', () {
      final p = sys(onCall: false);
      expect(p, isNot(contains('ร้านเปิด 9 โมง')));
      expect(p, isNot(contains('ราคาส่ง')));
    });

    test('สายออก: ใช้ข้อมูลและข้อห้ามได้ แต่ไม่จำกัด "ตอบเฉพาะข้อมูล" (มีเรื่องที่เจ้าของสั่งอยู่แล้ว)', () {
      final p = sys(onCall: true, outgoing: (who: 'ร้านดอกไม้', number: '021234567', task: 'สั่งดอกไม้'));
      expect(p, contains('ร้านเปิด 9 โมง'));
      expect(p, contains('ราคาส่ง'));
      expect(p, isNot(contains('=== ตอบได้แค่ไหน ===')));
    });
  });

  test('🔴 ภาษาไทยเสมอ เปลี่ยนภาษาเฉพาะเมื่อคนโทรขอ (ไม่สลับตามเองแค่เพราะเขาพูดภาษาอื่น)', () async {
    // เจ้าของ: "ให้มายด์ตอบเป็นภาษาไทย นอกจากปลายสายจะขอให้พูดภาษาอื่น"
    final s = MindState();
    addTearDown(s.dispose);
    await s.load();
    final p = s.callPrompt(live: true);
    expect(p, contains('พูดภาษาไทยเสมอ'));
    expect(p, contains('เฉพาะเมื่อคนปลายสายขอให้พูดภาษานั้น'));
    expect(p, isNot(contains('ตอบเป็นภาษาเดียวกับที่คนปลายสายพูดเสมอ')));
  });

  testWidgets('หน้าแก้ข้อความ: ปุ่มนำเข้าจากไฟล์ต่อท้ายข้อความเดิม · อ่านไม่ได้ = บอก', (tester) async {
    var next = 'ส่งฟรีทุกวัน';
    await tester.pumpWidget(MaterialApp(
      home: TextEditorScreen(
        title: 'ข้อมูล',
        hint: '',
        initial: 'เปิด 9 โมง',
        mode: MindMode.work,
        onReset: () => '',
        onImport: () async => next,
      ),
    ));
    final t = const S(AppLang.en);
    await tester.tap(find.text(t.importFromFile));
    await tester.pump();
    expect(find.text('เปิด 9 โมง\n\nส่งฟรีทุกวัน'), findsOneWidget);

    next = '';
    await tester.tap(find.text(t.importFromFile));
    await tester.pump();
    expect(find.text(t.importFailed), findsOneWidget);
  });

  test('ฝั่งเนทีฟ: ตัวเลือกไฟล์ของระบบมีที่รับจริง และตอบทุกทาง (เลือก/ยกเลิก)', () {
    final main = File('android/app/src/main/kotlin/com/xjanova/videogirl/MainActivity.kt').readAsStringSync();
    expect(main, contains('"pickTextFile" -> pickTextFile(result)'));
    expect(main, contains('Intent.ACTION_OPEN_DOCUMENT'));
    expect(main, contains('if (requestCode != REQ_PICK_TEXT) return'));
  });
}

typedef OutgoingLike = ({String who, String number, String task});
