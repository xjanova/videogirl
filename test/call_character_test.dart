/// ตัวละครในสาย — ชื่อ เพศ นิสัย · เลือกตัวรับสาย/โทรออก · ผูกกับเจ้าเสียง
///
/// ที่มา: เจ้าของ "เลือกเป็นเพศชาย ชื่อ นิสัย … ผูกกับโมเดลเสียงได้ เช่น OpenAI ใช้โปรไฟล์ A
/// ElevenLabs ใช้โปรไฟล์ B ทำให้ใช้ง่ายอย่าให้งง"
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/mind_persona.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/persona/call_character.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/theme/tokens.dart';

const _tom = CallCharacter(
  id: 'tom',
  name: 'คุณต้น',
  gender: CharacterGender.male,
  role: 'ผู้ช่วย',
  traits: 'สุภาพ พูดสั้น',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<MindState> loaded() async {
    final s = MindState();
    addTearDown(s.dispose);
    await s.load();
    return s;
  }

  test('ตั้งต้น = น้องมาย ผู้หญิง และคำทักเดิมทุกตัวอักษร', () async {
    final s = await loaded();
    expect(s.callCharacter().name, 'น้องมาย');
    expect(s.callCharacter().male, isFalse);
    expect(s.callGreeting(), startsWith(const S(AppLang.th).callGreeting));
  });

  test('ตัวผู้ชาย: prompt สั่ง "ครับ" ห้าม "ค่ะ" · ชื่อ บทบาท นิสัย เข้าไปครบ', () async {
    final s = await loaded();
    s.saveCharacter(_tom);
    s.setAnswerCharacter('tom');
    final p = s.callPrompt();
    expect(p, contains('คุณต้น'));
    expect(p, contains('ลงท้าย "ครับ"'));
    expect(p, contains('ห้ามพูด "ค่ะ"'));
    expect(p, contains('สุภาพ พูดสั้น'));
    expect(p, isNot(contains('เลขาผู้หญิง')));
    expect(p, isNot(contains('"น้องมาย"')));
    final g = s.callGreeting();
    expect(g, contains('คุณต้น'));
    expect(g, contains('ครับ'));
    expect(g, isNot(contains('ค่ะ')));
  });

  test('ผูกเจ้าเสียง: OpenAI → ตัว A · ElevenLabs → ตัว B', () async {
    final s = await loaded();
    s.saveCharacter(_tom);
    s.saveCharacter(const CallCharacter(id: 'b', name: 'บีม'));
    s.bindCharacter(TtsEngine.openai, 'tom');
    s.bindCharacter(TtsEngine.elevenlabs, 'b');

    s.setVoice(VoiceChannel.answer, s.voiceFor(VoiceChannel.answer).copyWith(engine: TtsEngine.openai));
    expect(s.callCharacter().id, 'tom');
    s.setVoice(VoiceChannel.answer, s.voiceFor(VoiceChannel.answer).copyWith(engine: TtsEngine.elevenlabs));
    expect(s.callCharacter().id, 'b');
    expect(s.callCharacter(outgoing: true).id, 'b', reason: 'ผูกกับเสียง = ใช้ทั้งรับสายและโทรออก');
    // คุยสดพูดด้วยเสียง OpenAI เสมอ → ได้ตัวที่ผูกกับ OpenAI
    expect(s.callCharacter(live: true).id, 'tom');

    s.bindCharacter(TtsEngine.elevenlabs, null);
    expect(s.callCharacter().id, CallCharacter.maiId, reason: 'เลิกผูก = กลับไปใช้ตัวที่เลือกไว้');
  });

  test('ลบตัวที่ใช้อยู่ = กลับไปน้องมาย · น้องมายลบไม่ได้', () async {
    final s = await loaded();
    s.saveCharacter(_tom);
    s.setAnswerCharacter('tom');
    s.bindCharacter(TtsEngine.openai, 'tom');
    s.deleteCharacter('tom');
    expect(s.cast.byId('tom'), isNull);
    expect(s.cast.answerId, CallCharacter.maiId);
    expect(s.cast.byEngine, isEmpty);
    s.deleteCharacter(CallCharacter.maiId);
    expect(s.cast.byId(CallCharacter.maiId), isNotNull);
  });

  test('บันทึกแล้วเปิดแอปใหม่ ยังอยู่ครบ', () async {
    final a = await loaded();
    a.saveCharacter(_tom);
    a.setOutgoingCharacter('tom');
    a.bindCharacter(TtsEngine.gemini, 'tom');
    final b = await loaded();
    expect(b.cast.byId('tom'), _tom);
    expect(b.cast.outgoingId, 'tom');
    expect(b.cast.byEngine[TtsEngine.gemini], 'tom');
  });

  test('ข้อมูลเสีย/อ้างถึงตัวที่ไม่มี = ไม่ล้ม และยังมีน้องมาย', () {
    const mai = CallCharacter(id: CallCharacter.maiId, name: 'น้องมาย');
    expect(CallCast.decode('{bad', mai).characters.single.id, CallCharacter.maiId);
    final c = CallCast.decode(
        '{"characters":[{"id":"x","name":"X"}],"answer":"ghost","byEngine":{"openai":"ghost","nope":"x"}}', mai);
    expect(c.characters.map((e) => e.id), [CallCharacter.maiId, 'x']);
    expect(c.answerId, CallCharacter.maiId);
    expect(c.byEngine, isEmpty);
  });

  test('ชื่อน้องมายตั้งต้นเปลี่ยนตามภาษา · ชื่อที่เจ้าของแก้แล้วไม่เปลี่ยน', () async {
    final s = await loaded();
    s.setLang(AppLang.en);
    expect(s.callCharacter().name, 'Mai');
    s.saveCharacter(s.cast.mai.copyWith(name: 'Mimi'));
    s.setLang(AppLang.th);
    expect(s.callCharacter().name, 'Mimi');
  });

  test('ในแอป (ไม่ใช่สาย) ตัวละครไม่มีผล', () {
    final p = MindPersona.system(
      mode: MindMode.work,
      flirt: 0,
      ownerProfile: '',
      boundaries: '',
      lang: AppLang.th,
      character: _tom,
    );
    expect(p, isNot(contains('คุณต้น')));
  });
}
