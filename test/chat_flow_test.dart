/// ด่านกันแชท "ดูเหมือนทำงาน แต่ไม่ทำงาน"
///
/// สามอย่างที่คุมไว้ที่นี่ เป็นสามอย่างที่ผู้ใช้เจอแล้วอ่านว่า **แอปพัง**
/// ไม่ใช่ "ตั้งค่าไม่ครบ" — และไม่มีอันไหนที่การแคปหน้าจอจะจับได้:
///
/// 1. ปุ่มส่งตายค้าง เพราะข้อผิดพลาดที่ไม่ได้เตรียมรับหลุดออกมากลางทาง
/// 2. สมองในเครื่องบอกว่ายังไม่ได้โหลดโมเดล ทั้งที่โหลดไว้แล้ว
/// 3. เธอลืมบทสนทนากลางคัน เพราะ session ฝั่งเนทีฟถูกสร้างใหม่เงียบ ๆ
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/local_brain.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_ai.dart';
import 'package:videogirl/state/mind_state.dart';

/// สมองปลอมที่ล้มได้ตามสั่ง
class _FakeBrain extends OpenAiClient {
  _FakeBrain(this.thrown);

  /// สิ่งที่จะโยนออกมาแทนคำตอบ · null = ตอบปกติ
  final Object? thrown;

  int calls = 0;

  @override
  bool get usable => true;

  @override
  Future<String> reply({
    required String system,
    required List<Turn> history,
    String? model,
  }) async {
    calls++;
    if (thrown != null) throw thrown!;
    return 'ค่ะ';
  }

  @override
  void close() {}
}

Future<MindState> _stateWith(Object? thrown) async {
  final s = MindState(openai: _FakeBrain(thrown));
  await s.load();
  s.setBrain(BrainProvider.openai);
  await s.setOpenAiKey('sk-test-key-for-unit-tests');
  return s;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('ปุ่มส่งต้องไม่ตายค้าง', () {
    test('ตอบปกติแล้วธงกำลังส่งต้องถูกปลด', () async {
      final s = await _stateWith(null);
      await s.send('สวัสดี');
      expect(s.sending, isFalse);
      s.dispose();
    });

    test('สมองล้มแบบที่เตรียมรับไว้ ธงก็ต้องถูกปลด', () async {
      final s = await _stateWith(const OpenAiFailure('คีย์ใช้ไม่ได้'));
      await s.send('สวัสดี');
      expect(s.sending, isFalse);
      expect(s.lastError, 'คีย์ใช้ไม่ได้');
      s.dispose();
    });

    // 🔴 ตัวจริงของบั๊กนี้ · ปุ่มส่งอ่าน `sending` เพื่อปิดตัวเอง
    // ธงที่ค้าง = ปุ่มส่งตายไปทั้งรอบการใช้งาน แก้ได้ทางเดียวคือปิดแอปเปิดใหม่
    test('🔴 ข้อผิดพลาดที่ไม่ได้เตรียมรับ ก็ยังต้องปลดธง', () async {
      // เกิดจริงเมื่อพร็อกซีหรือเซิร์ฟเวอร์ในบ้านตอบ HTML กลับมาแทน JSON
      final s = await _stateWith(const FormatException('ไม่ใช่ JSON'));
      await s.send('สวัสดี');
      expect(s.sending, isFalse,
          reason: 'ธงค้าง = ปุ่มส่งตายถาวรจนกว่าจะปิดแอป');
      s.dispose();
    });

    test('🔴 Error (ไม่ใช่ Exception) ก็ต้องไม่หลุดออกไปเป็นจอแดง', () async {
      // ปลั๊กอินในเครื่องล้มด้วย StateError ได้จริง — เคยเจอมาแล้วกับ
      // "Bad state: FlutterGemma not initialized!"
      final s = await _stateWith(StateError('ยังไม่ได้ initialize'));
      await s.send('สวัสดี');
      expect(s.sending, isFalse);
      s.dispose();
    });

    test('ล้มแล้วยังต้องมีคำตอบขึ้นจอ และต้องไม่หน้าตาเหมือนตอบสำเร็จ',
        () async {
      final s = await _stateWith(const FormatException('ไม่ใช่ JSON'));
      await s.send('ช่วยสรุปเมลให้หน่อย');

      final last = s.messages.last;
      expect(last.fromHer, isTrue, reason: 'ต้องมีคำตอบ ไม่ใช่เงียบหาย');
      expect(last.text, contains(const S(AppLang.th).errBrainUnexpected));
      expect(last.text, isNot(contains(const S(AppLang.th).cannedWork)),
          reason: 'ตอบ "จัดการให้แล้ว" ทั้งที่ไม่มีอะไรถูกส่งออกไป = โกหก');
      s.dispose();
    });

    test('ข้อผิดพลาดดิบต้องไม่หลุดถึงผู้ใช้', () async {
      final s = await _stateWith(
          const FormatException('https://api.example.com/v1 ตอบ <html>'));
      await s.send('สวัสดี');

      expect(s.lastError, isNotNull);
      expect(s.lastError, isNot(contains('http')),
          reason: 'ข้อความดิบมี URL ปลายทางติดมาด้วย');
      expect(s.lastError, isNot(contains('FormatException')));
      s.dispose();
    });

    test('ล้มไปแล้วยังส่งใหม่ได้ ไม่ใช่ตายไปเลย', () async {
      final brain = _FakeBrain(const FormatException('พัง'));
      final s = MindState(openai: brain);
      await s.load();
      s.setBrain(BrainProvider.openai);
      await s.setOpenAiKey('sk-test-key-for-unit-tests');

      await s.send('ครั้งแรก');
      await s.send('ครั้งที่สอง');
      expect(brain.calls, 2, reason: 'ครั้งที่สองต้องถูกส่งจริง');
      s.dispose();
    });
  });

  group('ภาษาของข้อความผิดพลาด', () {
    test('สลับเป็นอังกฤษแล้วข้อความจากสมองต้องเป็นอังกฤษด้วย', () async {
      final s = await _stateWith(const FormatException('พัง'));
      s.setLang(AppLang.en);
      await s.send('hello');

      expect(s.lastError, const S(AppLang.en).errBrainUnexpected,
          reason: 'client ที่ไม่ได้รับตารางภาษา จะตกไปใช้ไทยตายตัว');
      s.dispose();
    });
  });

  group('สมองในเครื่องต้องจำบทสนทนาได้ข้าม session', () {
    // เนทีฟลืมทุกอย่างเมื่อ session ถูกสร้างใหม่ ซึ่งเกิดทุกครั้งที่
    // system prompt ขยับ (ความผูกพันเป็น % · ระดับงอน · ตารางนัด)
    // และทุกครั้งที่การสกัดความจำยิงเข้ามาด้วย prompt คนละตัว
    List<Turn> turns(List<String> texts) => [
          for (var i = 0; i < texts.length; i++)
            (fromHer: i.isOdd, text: texts[i]),
        ];

    test('ต่อจากของเดิมพอดี = ส่งแค่คำล่าสุด', () {
      expect(
        LocalBrain.continues(
          ['ทักครั้งแรก', 'สวัสดีค่ะ'],
          turns(['ทักครั้งแรก', 'สวัสดีค่ะ', 'วันนี้มีนัดไหม']),
        ),
        isTrue,
      );
    });

    test('session ว่างเปล่า = ต้องเล่าย้อนให้ฟังก่อน', () {
      expect(
        LocalBrain.continues(
          const [],
          turns(['ทักครั้งแรก', 'สวัสดีค่ะ', 'วันนี้มีนัดไหม']),
        ),
        isFalse,
      );
    });

    // 🔴 ฝั่งเรียกตัดบทสนทนาเก่าทิ้งเมื่อเกิน 16 ตา ถ้าเทียบจากหัว
    // ทุกตาหลังจากนั้นจะ "ไม่ตรง" แล้วเธอจะโดนเล่าย้อนทั้งบทใหม่ทุกครั้ง
    test('🔴 หัวบทสนทนาถูกตัดทิ้งไปแล้ว ยังต้องนับว่าต่อกันได้', () {
      expect(
        LocalBrain.continues(
          ['ตาที่หนึ่ง', 'ตอบหนึ่ง', 'ตาที่สอง', 'ตอบสอง'],
          turns(['ตาที่สอง', 'ตอบสอง', 'ตาที่สาม']),
        ),
        isTrue,
      );
    });

    test('บทสนทนาไม่ตรงกัน = ต้องเริ่มเล่าใหม่', () {
      expect(
        LocalBrain.continues(
          ['ตาที่หนึ่ง', 'ตอบหนึ่ง'],
          turns(['คนละเรื่องเลย', 'ตอบอื่น', 'ตาที่สาม']),
        ),
        isFalse,
      );
    });

    test('บทที่เล่าย้อนต้องติดป้ายว่าใครพูด และจบด้วยคำที่เพิ่งถาม', () {
      const s = S(AppLang.th);
      final text = LocalBrain.transcriptFor(
        turns(['เมื่อวานเหนื่อยมาก', 'พักบ้างนะคะ', 'วันนี้มีนัดไหม']),
        s,
      );

      // 🔴 ถ้าไม่ติดป้าย เนทีฟจะถือว่าทุกบรรทัดคือคำที่เจ้าของพูด
      // แล้วคำตอบเก่าของเธอจะกลายเป็นคำของเจ้าของ
      expect(text, contains('${s.speakerMe}: เมื่อวานเหนื่อยมาก'));
      expect(text, contains('${s.speakerHer}: พักบ้างนะคะ'));
      expect(text.trim(), endsWith('วันนี้มีนัดไหม'));
    });

    test('ยังไม่มีบทเก่า = ส่งคำถามเปล่า ๆ ไม่ต้องมีหัวข้อเกริ่น', () {
      const s = S(AppLang.th);
      final text = LocalBrain.transcriptFor(turns(['สวัสดี']), s);
      expect(text, 'สวัสดี');
      expect(text, isNot(contains(s.localRecap)));
    });

    test('บทที่เล่าย้อนตามภาษาที่ผู้ใช้เลือก', () {
      final text = LocalBrain.transcriptFor(
        turns(['tired yesterday', 'get some rest', 'am I free today?']),
        const S(AppLang.en),
      );
      expect(text, contains(const S(AppLang.en).localRecap));
      expect(text, contains('Owner: tired yesterday'));
      expect(text, contains('Mind: get some rest'));
    });
  });
}
