/// เสียงตอนคุยต่อเนื่อง = เลือกเอง ไม่ปนกับเสียงโทร
///
/// ที่มา: เจ้าของ: "เธอใช้ เสียงส่วน ไหนในการสังเคราะห์ ต้องมีตัวเลือกด้วย เพราะฉันรู้สึกว่าเธอเลือกใช้เสียง
/// เดียวกับการโทรเข้าหรือออก ซึ่ง เราตั้ง Open ai live แล้วมันเสียเงิน ควรตั้งได้ด้วย"
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/state/mind_state.dart';

class _Speech extends SpeechService {
  final used = <VoiceProfile>[];

  @override
  Future<Utterance> synthesize(String text, {required VoiceProfile profile}) async {
    used.add(profile);
    return (bytes: Uint8List.fromList([1, 2, 3]), mime: 'audio/mpeg');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(MindState, _Speech)> mind() async {
    final speech = _Speech();
    final s = MindState(speech: speech);
    addTearDown(s.dispose);
    await s.load();
    s.setBrain(BrainProvider.openai);
    await s.setOpenAiKey('sk-test-key-for-unit-tests');
    return (s, speech);
  }

  VoiceProfile call(String voice) =>
      VoiceProfile(engine: TtsEngine.openai, voice: voice, model: 'gpt-4o-mini-tts', instructions: '');

  test('🔴 คุยสดไม่หยิบเสียงรับสาย', () async {
    final (s, _) = await mind();
    s.setVoice(VoiceChannel.answer, call('sage'));
    s.setVoice(VoiceChannel.outgoing, call('shimmer'));
    expect(s.voiceChatVoice, 'coral');
  });

  test('เลือกเสียงคุยสดเองแล้วเสียงแชทกับเสียงโทรไม่เปลี่ยน และจำข้ามการเปิดแอป', () async {
    final (s, _) = await mind();
    s.setVoice(VoiceChannel.answer, call('sage'));
    s.setVoiceChatVoice('cedar');
    expect(s.voiceChatVoice, 'cedar');
    expect(s.voiceFor(VoiceChannel.answer).voice, 'sage');
    expect(s.voiceFor(VoiceChannel.chat).voice, 'coral');

    final again = MindState();
    addTearDown(again.dispose);
    await again.load();
    expect(again.voiceChatVoice, 'cedar');
  });

  test('เสียงที่ Realtime ไม่รู้จัก = ไม่รับ', () async {
    final (s, _) = await mind();
    s.setVoiceChatVoice('cedar');
    s.setVoiceChatVoice('nova');
    expect(s.voiceChatVoice, 'cedar');
  });

  test('เสียงแชทที่ Realtime ไม่รู้จัก = ใช้ค่าตั้งต้น ไม่ส่งชื่อแปลกไปเชื่อม', () async {
    final (s, _) = await mind();
    s.setVoice(VoiceChannel.chat, const VoiceProfile(
        engine: TtsEngine.elevenlabs, voice: 'AbCdEfGhIjKlMnOpQrSt', model: 'eleven_v4', instructions: ''));
    expect(s.voiceChatVoice, VoiceProfile.openAiDefaults.voice);
  });

  test('ปิดคุยสด = เสียงขานใช้เสียงแชท · เปิด = เสียงเดียวกับที่จะคุยต่อ', () async {
    final (s, speech) = await mind();
    s.setVoiceChatVoice('ash');

    await s.renderWakeReplies();
    expect(speech.used.first.engine, TtsEngine.openai);
    expect(speech.used.first.voice, 'ash');

    speech.used.clear();
    s.setVoiceChatLive(false);
    await s.renderWakeReplies();
    expect(speech.used.first.engine, TtsEngine.device);
  });

  test('เปลี่ยนเสียงหรือทางคุย = ต้องอัดเสียงขานใหม่ · สิ่งอื่นไม่ต้อง', () async {
    final (s, _) = await mind();
    final start = s.wakeReplyKey;
    s.setVoice(VoiceChannel.answer, call('verse'));
    expect(s.wakeReplyKey, start);
    s.setVoiceChatVoice('ash');
    final picked = s.wakeReplyKey;
    expect(picked, isNot(start));
    s.setVoiceChatLive(false);
    expect(s.wakeReplyKey, isNot(picked));
  });

  test('ลองฟังเสียงคุยสดใช้เสียงที่เลือก ไม่ใช่เสียงแชท', () async {
    final (s, speech) = await mind();
    s.speaker = (_) async => true;
    s.setVoiceChatVoice('verse');
    await s.previewVoice(VoiceChannel.chat, as: s.voiceChatLiveProfile);
    expect(speech.used.single.engine, TtsEngine.openai);
    expect(speech.used.single.voice, 'verse');
  });
}
