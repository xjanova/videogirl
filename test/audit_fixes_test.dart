/// บั๊กจากการตรวจทั้งแอปรอบ 2026-10-05 — ทุกตัวในนี้คือของที่ผู้ใช้เจอจริง
/// ถ้ามันกลับมา: ข้อความหาย · เธอพูดทั้งที่สั่งเงียบ · เบอร์โทรหลุดออกนอกเครื่อง
/// · สำเนาที่รอดการถอนแอปถูกฐานเปล่าเขียนทับ
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:videogirl/ai/local_brain.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/diagnostics/debug_report.dart';
import 'package:videogirl/diagnostics/debug_reporter.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/store/mind_store.dart';
import 'package:videogirl/store/mind_vault.dart';

/// เสียงปลอมที่สังเคราะห์ได้เสมอ — เทสต์นี้สนใจจังหวะการพูด ไม่ใช่ตัวเสียง
class _Speech extends SpeechService {
  @override
  Future<Utterance> synthesize(String text,
          {required VoiceProfile profile}) async =>
      (bytes: Uint8List.fromList(const [1, 2, 3]), mime: 'audio/wav');
}

Future<void> _until(bool Function() ok) async {
  for (var i = 0; i < 200 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ok(), isTrue, reason: 'รอแล้วสถานะไม่มาถึงสักที');
}

late Directory _tmp;
String _path(String name) => '${_tmp.path}${Platform.pathSeparator}$name';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('แชท', () {
    test('พิมพ์แทรกตอนเธอยังพูดอยู่ ข้อความต้องไม่หาย และเธอต้องหยุดพูด', () async {
      final s = MindState(speech: _Speech());
      final playing = Completer<bool>();
      var hushed = 0;
      s.speaker = (_) => playing.future;
      s.silencer = () async {
        hushed++;
        if (!playing.isCompleted) playing.complete(true);
      };

      final first = s.send('ครั้งแรก');
      await _until(() => s.speaking);

      // ปุ่มส่งกลับมากดได้แล้วตอนเธอพูด — ต้องรับข้อความจริง ไม่ใช่กลืนทิ้ง
      expect(s.canSend, isTrue);
      await s.send('ครั้งที่สอง');

      expect(
        s.messages.where((m) => !m.fromHer).map((m) => m.text),
        contains('ครั้งที่สอง'),
        reason: 'ช่องพิมพ์ถูกล้างไปแล้ว ถ้าไม่ถูกส่ง ข้อความหายไปเฉย ๆ',
      );
      expect(hushed, greaterThan(0), reason: 'เจ้าของพิมพ์แทรก = เธอหยุดฟัง');
      await first;
    });

    test('กดปิดเสียงตอนเธอพูด ต้องเงียบประโยคนี้ทันที', () async {
      final s = MindState(speech: _Speech());
      final playing = Completer<bool>();
      var hushed = 0;
      s.speaker = (_) => playing.future;
      s.silencer = () async {
        hushed++;
        if (!playing.isCompleted) playing.complete(true);
      };

      final f = s.send('สวัสดี');
      await _until(() => s.speaking);
      s.setVoiceEnabled(false);
      await f;

      expect(hushed, 1);
      expect(s.speaking, isFalse);
    });

    test('ประโยค "คิดไม่ได้" ตอนสมองล้ม ต้องไม่ลงความจำ', () async {
      // ในเทสต์ไม่มีโมเดลและไม่มีคีย์ → สมองล้มเสมอ
      final s = MindState();
      await s.send('ช่วยหน่อย');

      expect(s.messages.last.fromHer, isTrue, reason: 'ยังต้องขึ้นจอให้เห็น');
      // เหลือแค่ข้อความของเรา · ถ้านับได้ 2 แปลว่าประโยคล้มถูกเก็บเป็นคำพูดเธอ
      // แล้วจะถูกส่งกลับเข้าโมเดลในตาถัดไป
      expect(await s.storedMessageCount(), 1);
    });

    test('สลับภาษาแล้วเสียงที่ยังเป็นค่าตั้งต้นต้องเปลี่ยนตาม', () {
      final s = MindState()..setLang(AppLang.en);
      expect(
        s.voiceFor(VoiceChannel.chat),
        VoiceProfile.defaultFor(VoiceChannel.chat, AppLang.en),
        reason: 'คำสั่งน้ำเสียงยังเป็น "พูดไทย…" ทั้งที่แอปเป็นอังกฤษ',
      );
    });
  });

  group('สมองในเครื่องใช้ session เดิมต่อ', () {
    test('ตัวเลขที่ขยับทุกตาไม่นับว่า prompt เปลี่ยน', () {
      const a = 'ความผูกพัน 41/100 · ตอนนี้: 5/10/2026 ช่วงเวลา 14:00 น.';
      const b = 'ความผูกพัน 42/100 · ตอนนี้: 5/10/2026 ช่วงเวลา 15:00 น.';
      expect(LocalBrain.sessionKeyOf(a), LocalBrain.sessionKeyOf(b),
          reason: 'สร้าง session ใหม่ทุกตา = อ่าน prompt ทั้งก้อนใหม่ทุกตา ช้ามาก');
    });

    test('มีเรื่องใหม่เข้ามา (บรรทัดใหม่) ต้องนับว่าเปลี่ยน', () {
      const a = 'สิ่งที่จำได้\n- ชอบกาแฟ';
      const b = 'สิ่งที่จำได้\n- ชอบกาแฟ\n- แพ้กุ้ง';
      expect(LocalBrain.sessionKeyOf(a), isNot(LocalBrain.sessionKeyOf(b)));
    });

    test('ป้ายในบทที่เล่าย้อนใช้ชื่อที่เจ้าของตั้งให้', () {
      final out = LocalBrain.transcriptFor(
        const [
          (fromHer: false, text: 'สวัสดี'),
          (fromHer: true, text: 'ค่ะ'),
          (fromHer: false, text: 'ทำอะไรอยู่'),
        ],
        const S(AppLang.th),
        her: 'น้องมิ้น',
      );
      expect(out, contains('น้องมิ้น: ค่ะ'));
      expect(out, isNot(contains('มายด์:')));
    });
  });

  group('รายงาน crash', () {
    test('หัวข้อกับ stack ผ่านตัวล้างความลับแล้ว', () {
      final title = DebugReporter.crashTitle(
          const FormatException('โทรหา 0812345678 ไม่ได้\nบรรทัดสอง'));
      expect(title, startsWith('FormatException'));
      expect(title, isNot(contains('0812345678')));
      expect(title, isNot(contains('บรรทัดสอง')));

      final stack = DebugReporter.crashStack(
          StackTrace.fromString('#0 a (x.dart:1)\n#1 b sk-abcdefghijklmnopqrstu'));
      expect(stack, contains('#0 a'));
      expect(stack, isNot(contains('sk-abcdefghijklmnopqrstu')));
    });

    test('รายงาน crash เป็นชนิด crash พร้อม stack_trace ส่วนรายงานปกติไม่มี', () {
      final r = DebugReport.build(
        app: const {'version': '0.1.24'},
        device: const {'osVersion': 'Android 15'},
        settings: const {},
        status: const {},
        counts: const {},
        errors: const [],
        logLines: const [],
      );
      final crash = DebugReporter.asBugReport(r,
          installId: 'x', crash: (title: 'StateError: x', stack: '#0 a'));
      expect(crash['report_type'], 'crash');
      expect(crash['stack_trace'], '#0 a');
      expect(crash.containsKey('user_email'), isFalse);

      final normal = DebugReporter.asBugReport(r, installId: 'x');
      expect(normal['report_type'], 'bug');
      expect(normal.containsKey('stack_trace'), isFalse);
    });

    test('ข้อผิดพลาดก่อนมีคนรับ ถูกเก็บไว้แล้วส่งต่อตอนต่อสาย', () {
      CrashSink.reset();
      CrashSink.report(StateError('ตอนเปิดแอป'), null);
      final got = <Object>[];
      CrashSink.attach((e, _) => got.add(e));
      expect(got, hasLength(1));
      CrashSink.reset();
    });
  });

  group('รายงานดีบัค', () {
    test('เบอร์โทรถูกปิดก่อนออกนอกเครื่อง', () {
      for (final raw in [
        'call: 0812345678 โทรมา',
        'call: +66 81 234 5678',
        'call: 02-123-4567',
      ]) {
        final out = DebugReport.redact(raw);
        expect(out, contains(DebugReport.phoneMark), reason: raw);
        expect(RegExp(r'\d{4}').hasMatch(out), isFalse, reason: out);
      }
    });

    test('ตัวเลขสั้น ๆ ที่ใช้ไล่บั๊กยังอยู่', () {
      expect(DebugReport.redact('เสียง: ได้ 48000 ไบต์'), contains('48000'));
    });
  });

  group('สำเนาที่รอดการถอนแอป', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      _tmp = Directory.systemTemp.createTempSync('mind_vault_audit');
    });

    tearDown(() {
      try {
        _tmp.deleteSync(recursive: true);
      } on Object {
        // ไฟล์ค้างในเทมป์ไม่ใช่เรื่องที่ต้องทำให้เทสต์แดง
      }
    });

    /// ติดตั้งครั้งแรก คุยไปแล้ว มีสำเนาข้างนอก
    Future<String> firstInstall() async {
      final root = _path('shared');
      final v = MindVault(hasAllFiles: () => true, root: root);
      final st = await MindStore.open(vault: v, pathOverride: _path('one.db'));
      st.db!.put('who', 'ของเก่า');
      expect(await v.saveNow(st.db!), isTrue);
      await st.db!.close();
      return root;
    }

    test('ลงใหม่โดยยังไม่ให้สิทธิ์ แล้วค่อยให้ทีหลัง — ห้ามเขียนทับของเก่า', () async {
      final root = await firstInstall();

      var granted = false;
      final v = MindVault(hasAllFiles: () => granted, root: root);
      final st = await MindStore.open(vault: v, pathOverride: _path('two.db'));
      expect(st.restored, isFalse, reason: 'ไม่มีสิทธิ์ = กู้ไม่ได้');

      granted = true;
      expect(await v.check(), VaultStage.foreign);
      expect(await v.saveNow(st.db!), isFalse,
          reason: 'ฐานเปล่าเขียนทับสำเนาเก่า = ข้อมูลเดิมหายถาวร');
      await st.db!.close();

      final copy = await MindStore.open(
          vault: MindVault(hasAllFiles: () => false, root: _path('x')),
          pathOverride: v.filePath);
      expect(copy.db!.getString('who'), 'ของเก่า');
      await copy.db!.close();
    });

    test('เลือกกู้ของเก่า — เปิดแอปรอบหน้าได้ของเก่ากลับมา', () async {
      final root = await firstInstall();

      var granted = false;
      final v = MindVault(hasAllFiles: () => granted, root: root);
      final st = await MindStore.open(vault: v, pathOverride: _path('two.db'));
      granted = true;
      await v.requestRestore();
      await st.db!.close();

      final again = MindVault(hasAllFiles: () => true, root: root);
      final st2 =
          await MindStore.open(vault: again, pathOverride: _path('two.db'));
      expect(st2.restored, isTrue);
      expect(st2.db!.getString('who'), 'ของเก่า');
      expect(await again.check(), VaultStage.ready);
      await st2.db!.close();
    });

    test('เลือกใช้ของตอนนี้ — ของเก่าถูกเก็บไว้ ไม่ถูกลบ', () async {
      final root = await firstInstall();

      var granted = false;
      final v = MindVault(hasAllFiles: () => granted, root: root);
      final st = await MindStore.open(vault: v, pathOverride: _path('two.db'));
      granted = true;
      expect(await v.check(), VaultStage.foreign);

      expect(await v.adopt(st.db!), isTrue);
      expect(File(v.previousPath).existsSync(), isTrue);
      expect(await v.check(), VaultStage.ready);
      await st.db!.close();
    });

    test('ผู้ใช้เดิมที่อัปเดตแอป (สำเนายังไม่มีป้าย) ต้องสำเนาต่อได้ตามปกติ', () async {
      final root = _path('shared');
      final v = MindVault(hasAllFiles: () => true, root: root);
      final st = await MindStore.open(vault: v, pathOverride: _path('one.db'));
      expect(await v.saveNow(st.db!), isTrue);
      // จำลองฐานของรุ่นก่อน: ป้ายเพิ่งติดตอนอัปเดต และสำเนาไม่มีไฟล์ป้าย
      await st.db!.setMeta('lineage_origin', 'migrated');
      await st.db!.close();
      File(v.idPath).deleteSync();

      final again = MindVault(hasAllFiles: () => true, root: root);
      final st2 =
          await MindStore.open(vault: again, pathOverride: _path('one.db'));
      expect(await again.check(), VaultStage.ready);
      await st2.db!.close();
    });
  });
}
