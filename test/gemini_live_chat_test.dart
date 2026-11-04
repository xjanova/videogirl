/// Gemini Live ในแชท · คู่ของคุยสด OpenAI ฝั่ง Google
///
/// เจ้าของ (2026-11-04): "และ google clound live" แล้วเลือก "Gemini Live ในแชท" · ทุกข้อความยึดเอกสาร Gemini API
/// (live-api/tools: Google Search ใช้ร่วมกับ function calling ได้ · live-api/capabilities: ภาพเข้าทาง `video`)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/gemini_live_chat.dart';
import 'package:videogirl/ai/realtime_chat.dart';
import 'package:videogirl/ai/speech_service.dart';
import 'package:videogirl/phone/voice_session.dart';
import 'package:videogirl/state/mind_state.dart';

class _FakeSocket implements RtSocket {
  final sent = <Map<String, Object?>>[];
  final _in = StreamController<Object?>();

  @override
  Stream<Object?> get messages => _in.stream;

  @override
  void send(String text) => sent.add((jsonDecode(text) as Map).cast<String, Object?>());

  @override
  Future<void> close() async {
    if (!_in.isClosed) await _in.close();
  }

  void push(Map<String, Object?> msg) => _in.add(jsonEncode(msg));

  Map<String, Object?> get setup => sent.first['setup']! as Map<String, Object?>;
  Iterable<Map<String, Object?>> of(String key) => sent.where((m) => m.containsKey(key));
}

Map<String, Object?> _audio(int bytes) => {
      'serverContent': {
        'modelTurn': {
          'parts': [
            {
              'inlineData': {'mimeType': 'audio/pcm;rate=24000', 'data': base64Encode(Uint8List(bytes))},
            },
          ],
        },
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _FakeSocket socket;
  final ran = <String>[];

  GeminiLiveChat make({bool web = true}) {
    ran.clear();
    return GeminiLiveChat(
      apiKey: 'gkey',
      instructions: 'PROMPT',
      tools: chatVoiceTools(web: false, phone: false, pages: true),
      runChatTool: (name, _) async {
        ran.add(name);
        return 'ok';
      },
      webSearch: web,
      voice: 'Sulafat',
      connect: (_, _) async => socket = _FakeSocket(),
    );
  }

  void open(FakeAsync async, GeminiLiveChat chat) {
    unawaited(chat.start());
    async.flushMicrotasks();
    socket.push({'setupComplete': <String, Object?>{}});
    async.flushMicrotasks();
  }

  test('🔴 setup: เครื่องมือของแชท + Google Search · ไม่ทักก่อน · รอเงียบนานกว่าในสาย', () {
    fakeAsync((async) {
      final chat = make();
      open(async, chat);
      final tools = socket.setup['tools']! as List;
      final names = [for (final d in (tools.first as Map)['functionDeclarations'] as List) (d as Map)['name']];
      expect(names, containsAll(['call_someone', 'end_conversation', 'read_url']));
      expect(names, isNot(contains('web_search')), reason: 'Gemini ค้นด้วย Google Search เอง ไม่ยืมคีย์ OpenAI');
      expect(names, isNot(contains('end_call')), reason: 'เครื่องมือในสายไม่มาในแชท');
      expect(tools, anyElement(equals({'googleSearch': <String, Object?>{}})));
      final vad = ((socket.setup['realtimeInputConfig']! as Map)['automaticActivityDetection']! as Map);
      expect(vad['silenceDurationMs'], 1100);
      expect(socket.of('clientContent'), isEmpty, reason: 'คุยกับเจ้าของ = รอเจ้าของพูดก่อน');
    });
  });

  test('ปิดหาข้อมูลจากอินเทอร์เน็ต = ไม่มี Google Search', () {
    fakeAsync((async) {
      open(async, make(web: false));
      expect(socket.setup['tools'], hasLength(1));
    });
  });

  test('🔴 end_conversation = ไม่รอผล ผลกลับแบบเงียบ แล้วปิดไมค์ · ไม่ไปถึงตัวทำเครื่องมือ', () {
    fakeAsync((async) {
      final chat = make();
      var ended = false;
      chat.onEndCall = () => ended = true;
      open(async, chat);
      final decl = [
        for (final d in ((socket.setup['tools']! as List).first as Map)['functionDeclarations'] as List) d as Map
      ].firstWhere((d) => d['name'] == 'end_conversation');
      expect(decl['behavior'], 'NON_BLOCKING');
      socket.push({
        'toolCall': {
          'functionCalls': [
            {'id': 'e1', 'name': 'end_conversation', 'args': <String, Object?>{}},
          ],
        },
      });
      async.flushMicrotasks();
      expect(ended, isTrue);
      expect(ran, isEmpty);
      final r = ((socket.of('toolResponse').single['toolResponse']! as Map)['functionResponses']! as List).single as Map;
      expect((r['response'] as Map)['scheduling'], 'SILENT');
    });
  });

  test('เครื่องมือของแชทวิ่งผ่าน runChatTool แล้วผลกลับไปหาเธอ', () {
    fakeAsync((async) {
      open(async, make());
      socket.push({
        'toolCall': {
          'functionCalls': [
            {'id': 't1', 'name': 'read_url', 'args': {'url': 'https://example.com'}},
          ],
        },
      });
      async.flushMicrotasks();
      expect(ran, ['read_url']);
      expect(socket.of('toolResponse'), hasLength(1));
    });
  });

  test('ภาพจากกล้องเข้าทาง realtimeInput.video เป็น JPEG', () {
    fakeAsync((async) {
      final chat = make();
      open(async, chat);
      chat.sendImage(Uint8List.fromList([1, 2, 3]));
      final v = (socket.of('realtimeInput').single['realtimeInput']! as Map)['video'] as Map;
      expect(v['mimeType'], 'image/jpeg');
      expect(v['data'], base64Encode([1, 2, 3]));
    });
  });

  test('🔴 เจ้าของแตะให้หยุด = ทิ้งเสียงที่เหลือของตานั้น · ตาถัดไปได้ยินตามปกติ · บอกเธอว่าเจ้าของไม่ได้ยินที่เหลือ', () {
    fakeAsync((async) {
      final chat = make();
      final heard = <int>[];
      chat.onAudio = (pcm) => heard.add(pcm.length);
      var flushed = 0;
      chat.onInterruption = () async {
        flushed++;
        return 0;
      };
      open(async, chat);
      socket.push(_audio(4));
      async.flushMicrotasks();
      unawaited(chat.interrupt());
      async.flushMicrotasks();
      socket.push(_audio(6));
      socket.push({
        'serverContent': {'turnComplete': true},
      });
      async.flushMicrotasks();
      expect(heard, [4], reason: 'เสียงหลังแตะหยุดไม่ออกลำโพง');
      expect(flushed, 1);
      socket.push(_audio(8));
      async.flushMicrotasks();
      expect(heard, [4, 8]);
      final notes = socket.of('clientContent').map((m) => jsonEncode(m)).join();
      expect(notes, contains('did not hear the rest'));
      expect(notes, contains('not words the owner said'));
    });
  });

  test('เจ้าของเริ่มพูด (บทชิ้นแรกของตา) = onSpeechStart · ใช้เป็นจังหวะส่งภาพเหมือน Realtime', () {
    fakeAsync((async) {
      final chat = make();
      var starts = 0;
      chat.onSpeechStart = () => starts++;
      open(async, chat);
      for (final t in ['สวัส', 'ดีค่ะ']) {
        socket.push({
          'serverContent': {
            'inputTranscription': {'text': t},
          },
        });
      }
      async.flushMicrotasks();
      expect(starts, 1);
    });
  });

  group('MindState เลือกเจ้าคุยสด', () {
    Future<MindState> mind() async {
      final s = MindState();
      addTearDown(s.dispose);
      await s.load();
      return s;
    }

    test('🔴 สมอง Gemini + คีย์ = คุยสดด้วย Gemini Live · ไม่มีคีย์ = ทีละตา', () async {
      final s = await mind();
      s.setBrain(BrainProvider.gemini);
      expect(s.voiceChatLiveEngine, isNull);
      await s.setPremiumKey(TtsEngine.gemini, 'gm-test-key');
      expect(s.voiceChatLiveEngine, CallLiveEngine.gemini);
      expect(s.voiceChatLiveReady, isTrue);
      expect(s.openVoiceChat(tools: (_, _) async => ''), isA<GeminiLiveChat>());
    });

    test('🔴 สมอง Gemini ไม่ยืม OpenAI เอง แม้มีคีย์ OpenAI', () async {
      final s = await mind();
      s.setBrain(BrainProvider.gemini);
      await s.setOpenAiKey('sk-test-key-for-unit-tests');
      s.setVoiceChatBorrow(CallLiveEngine.openai);
      expect(s.voiceChatLiveEngine, isNull, reason: 'สมองมีคุยสดของตัวเอง · ไม่มีคีย์ = ทีละตา ไม่ไปยืมเจ้าอื่น');
    });

    test('🔴 สมอง Claude ยืม Gemini Live ได้เมื่อเลือกเอง · prompt บอก Google Search ไม่ใช่ web_search', () async {
      final s = await mind();
      s.setBrain(BrainProvider.claude);
      await s.setPremiumKey(TtsEngine.gemini, 'gm-test-key');
      expect(s.voiceChatLiveEngine, isNull, reason: 'ค่าตั้งต้นไม่ยืม');
      s.setVoiceChatBorrow(CallLiveEngine.gemini);
      expect(s.voiceChatLiveEngine, CallLiveEngine.gemini);
      final p = s.voiceChatPrompt();
      if (s.webSearch) {
        expect(p, contains('Google Search'));
        expect(p, isNot(contains('web_search')));
      }
      expect(s.debugLiveWebSearcher, isNull, reason: 'คุยสด Gemini ไม่ยืมคีย์ OpenAI ไปค้น');
    });

    test('เสียงคุยสด Gemini เลือกแยก · ชื่อที่ Live ไม่รู้จัก = ไม่รับ · ขานด้วยเสียงเดียวกัน', () async {
      final s = await mind();
      s.setBrain(BrainProvider.gemini);
      await s.setPremiumKey(TtsEngine.gemini, 'gm-test-key');
      s.setVoiceChatGeminiVoice('Kore');
      s.setVoiceChatGeminiVoice('marin');
      expect(s.voiceChatGeminiVoice, 'Kore');
      expect(s.voiceChatLiveProfile.engine, TtsEngine.gemini);
      expect(s.voiceChatLiveProfile.voice, 'Kore');
    });

    test('ค่าสวิตช์ "คุยสดด้วย OpenAI" ของ v0.1.72 = ยืม OpenAI ต่อ', () async {
      SharedPreferences.setMockInitialValues({'voiceChatLiveAnyBrain': true});
      final s = await mind();
      expect(s.voiceChatBorrow, CallLiveEngine.openai);
    });
  });
}
