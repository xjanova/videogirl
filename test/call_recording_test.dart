/// บันทึกเสียงสนทนาในสายที่เธอรับแทน + ให้เธอได้ยินปลายสาย
///
/// ที่มา: เจ้าของ — "รับแล้ว แต่ไม่ยอมพูดตอบโต้อะไรเลย" (Android 10+ ให้ความเงียบ
/// กับแอปที่อัดเสียงระหว่างสาย เว้นแต่เปิดบริการการช่วยเหลือพิเศษ) และ "ทำให้บันทึก
/// เสียงสนทนาไว้ได้ด้วย"
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/phone/call_notes.dart';
import 'package:videogirl/phone/call_session.dart';
import 'package:videogirl/phone/call_watch.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('call_rec');
    CallRecordings.debugDir = tmp;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kSystemChannel, (call) async => null);
  });

  tearDown(() {
    CallRecordings.debugDir = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kSystemChannel, null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Uint8List second(int value) {
    final b = ByteData(32000);
    for (var i = 0; i < 16000; i++) {
      b.setInt16(i * 2, value, Endian.little);
    }
    return b.buffer.asUint8List();
  }

  int u32(Uint8List b, int at) => ByteData.sublistView(b).getUint32(at, Endian.little);

  group('ไฟล์เสียงสนทนา', () {
    test('ได้ WAV ที่หัวไฟล์บอกขนาดตรงกับเสียงจริง และไม่เหลือไฟล์ดิบค้าง', () async {
      final s = CallSession(watch: CallWatch(), state: MindState());
      addTearDown(s.dispose);
      final f = (await s.debugRecord([second(1000), second(-1000), second(500)]))!;
      final bytes = f.readAsBytesSync();
      expect(f.path, endsWith('.wav'));
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(u32(bytes, 40), 96000, reason: 'ขนาดก้อนเสียง = สามวินาที');
      expect(u32(bytes, 4), 36 + 96000);
      expect(bytes.length, 44 + 96000);
      expect(tmp.listSync().whereType<File>().where((e) => e.path.endsWith('.pcm')), isEmpty);
    });

    test('สายสั้นกว่าวินาทีไม่เก็บ', () async {
      final s = CallSession(watch: CallWatch(), state: MindState());
      addTearDown(s.dispose);
      expect(await s.debugRecord([Uint8List(1000)]), isNull);
      expect(tmp.listSync(), isEmpty);
    });

    test('ปิดการบันทึก = ไม่มีไฟล์', () async {
      final st = MindState();
      await st.load();
      st.setRecordCalls(false);
      final s = CallSession(watch: CallWatch(), state: st);
      addTearDown(s.dispose);
      expect(await s.debugRecord([second(1000), second(1000)]), isNull);
      expect(tmp.listSync(), isEmpty);
    });

    test('ผูกกับบันทึกสาย แล้วลบไปพร้อมกันเมื่อเจ้าของลบบันทึก', () async {
      final st = MindState();
      await st.load();
      final notes = CallNotes();
      st.attachCallNotes(notes);
      final s = CallSession(watch: CallWatch(), state: st);
      addTearDown(s.dispose);
      final rec = await s.debugRecord([second(1000), second(1000)]);

      final note = (await st.takeCallNote(
        who: 'คุณนภา',
        lines: [(fromHer: true, text: 'สวัสดีค่ะ'), (fromHer: false, text: 'ฝากบอกว่าโทรกลับด้วย')],
        audio: rec,
      ))!;
      final mine = await CallRecordings.forNote(note.id);
      expect(mine, isNotNull, reason: 'ไฟล์เสียงต้องหาเจอจากบันทึกสาย');
      expect(rec!.existsSync(), isFalse, reason: 'ย้ายมาแล้ว ไม่ใช่สำเนา');

      await notes.remove(note.id);
      expect(await CallRecordings.forNote(note.id), isNull, reason: 'ลบบันทึก = ลบเสียงคนอื่นไปด้วย');
    });
  });

  group('คนที่ถูกบันทึกต้องรู้ตัว', () {
    test('บันทึกอยู่ = คำทักบอกคู่สาย · ปิดบันทึก = ไม่บอก', () async {
      final st = MindState();
      await st.load();
      expect(st.recordCalls, isTrue, reason: 'เจ้าของขอให้บันทึกได้ · เปิดเป็นค่าตั้งต้น');
      expect(st.callGreeting(), contains('บันทึกเสียง'));
      st.setRecordCalls(false);
      expect(st.callGreeting(), isNot(contains('บันทึกเสียง')));
    });
  });

  test('ขอสิทธิ์ให้เธอได้ยินสาย (การช่วยเหลือพิเศษ) ผ่านช่องที่มีอยู่จริง', () {
    expect(MindPermission.accessibility.check, 'accessibilityOn');
    expect(MindPermission.accessibility.ask, 'openAccessibility');
    expect(MindPermission.accessibility.inApp, isFalse, reason: 'เปิดได้จากหน้าตั้งค่าของระบบเท่านั้น');
  });
}
