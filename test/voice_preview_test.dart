/// ลองฟังเสียง = เสียงจริงของเจ้า/รุ่น/เสียงที่เลือก ไม่ใช่เสียงเครื่องที่แอบมาแทน
///
/// ที่มา: เจ้าของกดลองฟังเสียงพรีเมียมแล้วได้ยินเสียงเครื่อง (ทางสำรองตอนคุย)
/// โดยไม่มีอะไรบอกว่าตัวที่เลือกใช้ไม่ได้ และไม่รู้ว่าทำไม
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/ai/voice_profile.dart';
import 'package:videogirl/i18n/strings_ai.dart';
import 'package:videogirl/state/mind_state.dart';

class _Speech extends SpeechService {
  _Speech({this.failWith});

  final String? failWith;
  final engines = <TtsEngine>[];

  @override
  Future<Utterance> synthesize(String text, {required VoiceProfile profile}) async {
    engines.add(profile.engine);
    if (failWith != null && profile.engine != TtsEngine.device) {
      throw OpenAiFailure(failWith!);
    }
    return (bytes: Uint8List.fromList([1, 2, 3]), mime: 'audio/mpeg');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  MindState make(_Speech speech, {TtsEngine engine = TtsEngine.elevenlabs}) {
    final s = MindState(speech: speech);
    s.setVoice(
      VoiceChannel.chat,
      VoiceProfile(engine: engine, voice: 'AbCdEfGhIjKlMnOpQrSt', model: 'eleven_v4', instructions: ''),
    );
    return s;
  }

  test('🔴 ตัวที่เลือกใช้ไม่ได้ = บอกเหตุผล และไม่แอบเล่นเสียงเครื่องแทน', () async {
    final speech = _Speech(failWith: 'คีย์ ElevenLabs ใช้ไม่ได้ ตรวจคีย์อีกครั้ง');
    final s = make(speech);
    var played = 0;
    s.speaker = (_) async {
      played++;
      return true;
    };

    final why = await s.previewVoice(VoiceChannel.chat);

    expect(why, 'คีย์ ElevenLabs ใช้ไม่ได้ ตรวจคีย์อีกครั้ง');
    expect(played, 0, reason: 'เล่นเสียงเครื่องแทน = เจ้าของคิดว่าได้ยินตัวที่เลือก');
    expect(speech.engines, [TtsEngine.elevenlabs], reason: 'ห้ามลองเสียงเครื่องต่อ');
    s.dispose();
  });

  test('ใช้ได้ = เล่นเสียงจากเจ้าที่เลือกจริง และบอกตอนเริ่มเล่น', () async {
    final speech = _Speech();
    final s = make(speech);
    Uint8List? got;
    s.speaker = (u) async {
      got = u.bytes;
      return true;
    };
    var playing = false;

    final why = await s.previewVoice(VoiceChannel.chat, onPlaying: () => playing = true);

    expect(why, isNull);
    expect(playing, isTrue);
    expect(got, [1, 2, 3]);
    expect(speech.engines, [TtsEngine.elevenlabs]);
    expect(s.speaking, isFalse, reason: 'เล่นจบแล้วต้องปลดธงพูด');
    s.dispose();
  });

  test('สร้างเสียงได้แต่ออกลำโพงไม่ได้ = บอกตรง ๆ', () async {
    final s = make(_Speech());
    s.speaker = (_) async => false;
    expect(await s.previewVoice(VoiceChannel.chat), s.s.errVoiceNoOutput);
    s.dispose();
  });
}
