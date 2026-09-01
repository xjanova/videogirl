import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/ai/local_brain.dart';

/// สิ่งที่ผู้ใช้เห็นตอนโมเดลในเครื่องมีปัญหา
///
/// ที่มา: หน้าตั้งค่าเคยขึ้นข้อความข้อผิดพลาดของปลั๊กอินทั้งดุ้น — สิบกว่าบรรทัด
/// มี `void main() async {...}` กับลิงก์ pub.dev ติดมาด้วย ผู้ใช้ทำอะไรกับมัน
/// ไม่ได้เลยนอกจากตกใจ
void main() {
  group('ย่อข้อความข้อผิดพลาดก่อนเอาไปโชว์', () {
    test('ข้อผิดพลาดหลายบรรทัด เหลือแค่บรรทัดแรก', () {
      // นี่คือของจริงที่เคยขึ้นบนหน้าจอ ย่อมาเล็กน้อย
      const real = 'ModelDownloadException: Failed to download model: '
          'gemma-4-e4b-gpu (location: unknown)\n\n'
          'You must call FlutterGemma.initialize() in main() before using '
          'the plugin.\n\n'
          'Example:\n'
          '  void main() async {\n'
          '    WidgetsFlutterBinding.ensureInitialized();\n'
          '    await FlutterGemma.initialize();\n'
          '    runApp(MyApp());\n'
          '  }\n';

      final short = LocalBrain.shortenError(real);

      expect(short, isNot(contains('void main')));
      expect(short, isNot(contains('runApp')));
      expect(short, isNot(contains('\n')));
      // ยังต้องบอกได้ว่าเกิดอะไรขึ้น ไม่ใช่ย่อจนไม่เหลือความหมาย
      expect(short, contains('Failed to download model'));
    });

    test('คำนำหน้าชนิดข้อผิดพลาดถูกตัดออก ไม่ให้โผล่ถึงผู้ใช้', () {
      expect(LocalBrain.shortenError(Exception('เน็ตหลุด')), 'เน็ตหลุด');
      expect(LocalBrain.shortenError(StateError('ยังไม่พร้อม')), 'ยังไม่พร้อม');
    });

    test('ข้อความยาวมากถูกตัด ไม่ดันจอจนอ่านอย่างอื่นไม่ได้', () {
      final short = LocalBrain.shortenError('x' * 500);

      expect(short.length, lessThanOrEqualTo(140));
      expect(short, endsWith('…'));
    });

    test('ข้อผิดพลาดที่ไม่มีข้อความ ต้องไม่กลายเป็นช่องว่างเปล่า', () {
      // ช่องว่างเปล่าบนหน้าจอ = ผู้ใช้ไม่รู้ว่าพังหรือไม่พัง
      final short = LocalBrain.shortenError(Exception(''));

      expect(short.trim(), isNotEmpty);
    });
  });

  group('ที่อยู่ไฟล์โมเดลทุกรุ่น', () {
    test('ประกอบเป็น URL ของ HuggingFace ที่ถูกต้อง และไม่ซ้ำกัน', () {
      final urls = <String>{};

      for (final v in GemmaVariant.values) {
        expect(v.url, startsWith('https://huggingface.co/'));
        expect(v.url, contains('/resolve/main/'));
        expect(v.url, endsWith('.litertlm'),
            reason: 'ใส่ .task แทน .litertlm = เทมเพลตซ้อนสองชั้น คำตอบเพี้ยน');
        expect(v.bytes, greaterThan(1000000000), reason: 'โมเดลพวกนี้เป็น GB');
        urls.add(v.url);
      }

      expect(urls.length, GemmaVariant.values.length,
          reason: 'สองรุ่นชี้ไฟล์เดียวกัน = เลือกรุ่นแล้วได้ของเดิม');
    });
  });
}
