import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/i18n/strings.dart';

/// สิ่งที่ต้องจริงเกี่ยวกับ "ทางออกเสียง" ก่อนจะเอาไปโชว์ให้ผู้ใช้เลือก
///
/// ที่มา: ตรวจแล้วพบว่าหน้าตั้งค่าโชว์เครื่องสังเคราะห์เสียงสามทาง แต่ทางที่สาม
/// (เสียงโคลน) **ไม่เคยถูกต่อสายเลย** — `VoiceCloneService` ไม่เคยถูกสร้างที่ไหน
/// ในแอป และไม่มีหน้าจอให้ตั้งค่าด้วย เลือกแล้วตกไปเป็นเสียงเครื่องเงียบ ๆ
/// ผู้ใช้อ่านได้อย่างเดียวว่าฟีเจอร์นี้พัง
void main() {
  group('ทางออกเสียงที่เอาไปโชว์ได้', () {
    test('โชว์เฉพาะทางที่ต่อสายไว้จริง ไม่ใช่ทุกค่าใน enum', () {
      expect(TtsEngine.wired, isNot(contains(TtsEngine.clone)),
          reason: 'VoiceCloneService ไม่เคยถูกสร้าง เลือกแล้วได้เสียงเครื่อง');
      expect(TtsEngine.wired, contains(TtsEngine.device));
      expect(TtsEngine.wired, contains(TtsEngine.openai));
    });

    test('ทุกทางที่โชว์ ต้องเป็นค่าจริงใน enum', () {
      for (final e in TtsEngine.wired) {
        expect(TtsEngine.values, contains(e));
      }
    });

    test('มีแค่ทาง OpenAI ที่ต้องใช้คีย์', () {
      expect(TtsEngine.openai.needsOpenAiKey, isTrue);
      expect(TtsEngine.device.needsOpenAiKey, isFalse);
    });
  });

  group('ค่าที่เคยบันทึกไว้ ตอนโหลดกลับมา', () {
    final fallback = VoiceProfile.defaultFor(VoiceChannel.chat, AppLang.th);

    test('ทางที่ถูกถอดออกจากรายการ ต้องตกกลับไปค่าตั้งต้น', () {
      // เครื่องที่เคยเลือก "เสียงโคลน" ไว้ตอนที่มันยังโผล่ในรายการ
      // ถ้าโหลดกลับมาตรง ๆ หน้าตั้งค่าจะดูเหมือนไม่ได้เลือกอะไรเลย
      final p = VoiceProfile.fromJson({'engine': 'clone'}, fallback);

      expect(TtsEngine.wired, contains(p.engine));
      expect(p.engine, fallback.engine);
    });

    test('ทางที่ยังใช้ได้ ต้องคงไว้ ไม่ใช่รีเซ็ตทิ้งหมด', () {
      final p = VoiceProfile.fromJson({'engine': 'openai'}, fallback);

      expect(p.engine, TtsEngine.openai);
    });

    test('ชื่อ engine ที่ไม่รู้จักเลย ก็ต้องไม่พัง', () {
      final p = VoiceProfile.fromJson({'engine': 'ไม่เคยมี'}, fallback);

      expect(p.engine, fallback.engine);
    });
  });
}
