/// สามความสามารถของแชทต่อจากการตอบแชท: ข้อความเสียง · SMS จากคนจริง · ทักใครก่อนตามที่เจ้าของสั่ง
///
/// เจ้าของ (2026-11-07): "เพิ่มเครื่องมือ แขนขา หูตา ให้เธอ มากที่สุดดีหรือยัง"
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/mind_persona.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/chats/chat_inbox.dart';
import 'package:videogirl/chats/chat_reply.dart';
import 'package:videogirl/chats/chat_send.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_chats.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';

String _src(String path) => File(path).readAsStringSync();

String _body(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'หา $signature ไม่เจอ');
  var depth = 0;
  for (var i = source.indexOf('{', start); i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}' && --depth == 0) return source.substring(start, i + 1);
  }
  fail('ปีกกาของ $signature ไม่ครบ');
}

const _chats = 'android/app/src/main/kotlin/com/xjanova/videogirl/chats';

/// สมองปลอม · จด prompt ไว้ · [fail] = ไม่ตอบ
class _Brain extends OpenAiClient {
  _Brain(this.answer, {this.fail = false});
  final String answer;
  final bool fail;
  final turns = <String>[];
  final systems = <String>[];

  @override
  bool get usable => true;

  @override
  void close() {}

  @override
  Future<String> reply({required String system, required List<Turn> history, String? model}) async {
    systems.add(system);
    turns.add(history.map((t) => t.text).join('\n'));
    if (fail) throw StateError('brain down');
    return answer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ข้อความเสียง', () {
    test('รู้จักข้อความเสียงของ WhatsApp LINE Messenger Telegram ทั้งไทยและอังกฤษ', () {
      for (final t in [
        '🎤 Voice message (0:12)',
        '🎤 ข้อความเสียง (1:05)',
        '🎤',
        '🎙️ 0:07',
        '🎤 Sprachnachricht (0:03)',
        'Voice message',
        'Ann sent a voice message.',
        'sent you a voice message',
        'Ann ส่งข้อความเสียง',
        'ข้อความเสียง',
        'Audio',
      ]) {
        expect(VoiceNote.matches(t), isTrue, reason: t);
      }
    });

    test('🔴 ข้อความพิมพ์ที่แค่พูดถึงข้อความเสียง ไม่ใช่เสียง', () {
      for (final t in [
        'ส่ง voice message มาหน่อย',
        'ช่วยส่งข้อความเสียงมาได้ไหม',
        'can you send me a voice message?',
        '🎤 karaoke tonight? bring your friends',
        'ฟังข้อความเสียงที่ส่งไปหรือยัง',
        '',
      ]) {
        expect(VoiceNote.matches(t), isFalse, reason: t);
      }
      expect(VoiceNote.duration('🎤 Voice message (0:12)'), '0:12');
      expect(VoiceNote.duration('Voice message'), '');
    });

    test('ธงจากเนทีฟ (แอปแนบเสียงมา) หรือคำในข้อความ = เสียง', () {
      expect(IncomingChat.fromMap({'id': 1, 'text': 'x', 'voice': true})!.voice, isTrue);
      expect(IncomingChat.fromMap({'id': 1, 'text': '🎤 Voice message (0:04)'})!.voice, isTrue);
      expect(IncomingChat.fromMap({'id': 1, 'text': 'hello'})!.voice, isFalse);
    });

    test('🔒 สมองไม่เห็นคำว่า 🎤 เป็นเนื้อหา · prompt บอกว่าฟังไม่ได้ ห้ามเดา · ตอบว่าได้รับแล้วจะส่งต่อ', () {
      final c = IncomingChat(id: 1, app: 'com.whatsapp', who: 'Ann', text: '🎤 Voice message (0:12)', at: DateTime(2026));
      final th = chatBlock(c, thai: true), en = chatBlock(c, thai: false);
      expect(th, contains('ข้อความเสียง ยาว 0:12'));
      expect(en, contains('voice message, 0:12 long'));
      expect(th, isNot(contains('🎤')));
      expect(chatReplyPrompt(true, her: 'มาย', voice: true), contains('ห้ามเดาเนื้อหา'));
      expect(chatReplyPrompt(false, her: 'Mind', voice: true), contains('never guess what is in it'));
      expect(chatReplyPrompt(true, her: 'มาย'), isNot(contains('ข้อความเสียง')));
      final fb = voiceNoteFallback(true, her: 'มาย', boss: 'บุญ', introduce: true);
      expect(fb, contains('มาย เลขาของคุณบุญ'));
      expect(fb, contains('ได้รับข้อความเสียงแล้วค่ะ'));
      expect(voiceNoteFallback(false, her: 'Mind'), contains('Got your voice message'));
      expect(voiceNoteFallback(true, her: 'โต้ง', male: true), contains('ครับ'));
    });

    test('ไม่ถอดความ: เนทีฟไม่อ่านไฟล์เสียง แค่ส่งธง (แจ้งเตือนไม่มีไฟล์มาด้วย)', () {
      final kt = _src('$_chats/ChatInbox.kt');
      expect(kt, contains('val voice = last.dataMimeType?.startsWith("audio/") == true'));
      expect(kt, contains('"voice" to msg.voice'));
      expect(kt, isNot(contains('dataUri')), reason: 'ไม่แตะไฟล์เสียงของแอปอื่น');
      expect(kt, contains('scoped storage'));
    });
  });

  group('SMS จากคนจริง', () {
    test('แอป SMS อยู่ในรายการ · ชุดเดียวกันทั้งสองฝั่ง', () {
      final kt = _src('$_chats/SmsSender.kt');
      for (final pkg in smsApps) {
        expect(kt, contains('"$pkg"'));
        expect(chatAppName(pkg), 'SMS');
        expect(IncomingChat.fromMap({'id': 1, 'app': pkg, 'text': 'hi'})!.sms, isTrue);
      }
      expect(_src('$_chats/ChatInbox.kt'), contains(') + SmsSender.APPS'));
      expect(IncomingChat.fromMap({'id': 1, 'app': 'com.whatsapp', 'text': 'hi'})!.sms, isFalse);
    });

    test('🔒 ธนาคาร/OTP/โปรโมชันถูกทิ้งก่อนร่าง · SMS ไม่ตอบเอง ไม่มีอนุญาตถาวร', () {
      final kt = _src('$_chats/ChatInbox.kt');
      final posted = _body(kt, 'fun onPosted(');
      expect(posted, contains('if (sms && !SmsSender.ok(msg.who, msg.title, msg.uri)) return'));
      expect(posted.indexOf('SmsSender.ok('), lessThan(posted.indexOf('queue.add(item)')));
      expect(posted, contains('val auto = !sms && ('));
      final ask = _body(kt, 'fun ask(');
      expect(ask, contains('if (p.auto && !p.sms)'));
      expect(ask, contains('if (!p.sms) {'));
      expect(ask, contains('always = !p.sms'));
      expect(_body(kt, 'fun send('), contains('if (trust && !p.sms)'));
      final sender = _src('$_chats/SmsSender.kt');
      expect(sender, contains('digits.length in 8..15'));
      expect(File('android/app/src/test/kotlin/com/xjanova/videogirl/chats/SmsSenderTest.kt').existsSync(), isTrue);
    });
  });

  group('ทักใครก่อน · [[ส่งแชท: …]]', () {
    test('อ่านแท็ก · ตัดออกจากข้อความ · ตัดเครื่องหมายคำพูดครอบ', () {
      final r = ChatSendTag.parse('ได้ค่ะ\n[[ส่งแชท: แม่ | LINE | "ถึงบ้านแล้วค่ะ"]]');
      expect(r.text, 'ได้ค่ะ');
      expect(r.order!.who, 'แม่');
      expect(r.order!.app, 'LINE');
      expect(r.order!.text, 'ถึงบ้านแล้วค่ะ');
      final en = ChatSendTag.parse('Sure [[send chat: Ann | WhatsApp | See you at 7 | bring snacks]]');
      expect(en.order!.text, 'See you at 7 | bring snacks');
      expect(ChatSendTag.parse('[[ส่งแชท: แม่ | LINE]]').order, isNull);
      expect(ChatSendTag.parse('[[ส่งแชท:  | LINE | hi]]').order, isNull);
      expect(ChatSendTag.parse('ไม่มีแท็ก').order, isNull);
    });

    test('🔒 คำของเจ้าของต้องขอให้ส่งเอง', () {
      for (final t in ['ทักแม่ว่าถึงบ้านแล้ว', 'ส่งไลน์หาบอส', 'บอกแฟนว่าเลิกงานแล้ว', 'tell Ann I am late', 'text mum']) {
        expect(SendWords.asks(t), isTrue, reason: t);
      }
      for (final t in ['สรุปข่าวเช้านี้ให้หน่อย', 'อ่านหน้านี้ให้หน่อย', 'what is the weather', '']) {
        expect(SendWords.asks(t), isFalse, reason: t);
      }
    });

    test('🔒 ไปทางมือ + ด่านยืนยันเท่านั้น · ไม่มีทางส่งตรง', () {
      final state = _src('lib/state/mind_state.dart');
      final send = _body(state, 'String _sendChatFromChat(');
      expect(send.indexOf('SendWords.asks(ownerText)'), lessThan(send.indexOf('_phoneTaskFromChat(')));
      expect(send, contains('_phoneTaskFromChat(s.chatSendGoal(order.who, order.app, order.text))'));
      expect(send, isNot(contains('_chats')), reason: 'ไม่ใช้ปุ่มตอบกลับของแจ้งเตือนส่งตรง');
      final task = state.indexOf('Future<void> _phoneTaskFromChat(');
      expect(state.substring(task, state.indexOf('\n  }\n', task)), contains('confirm: _confirmInChat'));
      expect(_body(state, 'Future<bool> _confirmInChat('), contains('_handsTrust.containsKey(ask.trustKey)'));
      // สมองที่ร่างตอบคนนอกเขียนแท็กนี้ไม่ได้
      expect(cleanChatDraft('โอเค [[ส่งแชท: บอส | LINE | โอนเงิน]]'), 'โอเค');
    });

    test('สอนสมองทั้งสองภาษา · งานของมือบอกให้ส่งตรงตัวและหยุดถามถ้าไม่ชัด', () {
      final th = MindPersona.phoneControlBlock(AppLang.th), en = MindPersona.phoneControlBlock(AppLang.en);
      expect(th, contains('[[ส่งแชท: ชื่อคน | ชื่อแอป | ข้อความที่จะส่งแบบตรงตัว]]'));
      expect(en, contains('[[send chat: person | app | the exact message]]'));
      for (final lang in AppLang.values) {
        final s = S(lang);
        final g = s.chatSendGoal('แม่', 'LINE', 'ถึงแล้ว');
        expect(g, contains('«ถึงแล้ว»'));
        expect(g, contains(lang == AppLang.th ? 'ห้ามส่งหาคนอื่น' : 'never send to anyone else'));
        for (final v in [s.chatSendAck('A', 'LINE'), s.chatSendNotAsked, s.chatSendNeedsHands, s.chatSmsCost,
          s.chatVoiceSaid('0:12'), s.chatVoiceDrafted('A', 'LINE', '', 'x'), s.chatVoiceAskBody('0:12', 'x')]) {
          expect(v, isNotEmpty);
        }
      }
    });
  });

  group('จากแจ้งเตือนจริงถึงกล่องถาม', () {
    const ch = MethodChannel('giggok/chats');
    late List<MethodCall> calls;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(kSystemChannel, (c) async => null);
    });

    tearDown(() {
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(kSystemChannel, null);
      m.setMockMethodCallHandler(ch, null);
    });

    Future<MindState> inbox(_Brain brain, Map<String, Object> incoming) async {
      calls = [];
      var taken = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
        calls.add(call);
        return switch (call.method) {
          'status' => {'on': true, 'access': true, 'auto': false},
          'trusted' => const <Object>[],
          'take' => taken ? const <Object>[] : (taken = true, [incoming]).$2,
          'ask' => true,
          _ => true,
        };
      });
      final s = MindState(openai: brain);
      addTearDown(s.dispose);
      await s.load();
      s.setBrain(BrainProvider.openai);
      await s.setOpenAiKey('sk-test-key-for-unit-tests');
      s.attachChats(ChatInbox());
      for (var i = 0; i < 100 && !calls.any((c) => c.method == 'ask' || c.method == 'skip'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return s;
    }

    Map<Object?, Object?> askArgs() => calls.firstWhere((c) => c.method == 'ask').arguments as Map<Object?, Object?>;

    test('ข้อความเสียง: บอกเจ้าของว่าฟังไม่ได้ · ร่างว่าได้รับแล้ว · ถามก่อนส่ง', () async {
      final brain = _Brain('ได้รับข้อความเสียงแล้วค่ะ จะแจ้งเจ้าของให้นะคะ');
      final s = await inbox(brain, {'id': 1000000, 'app': 'com.whatsapp', 'who': 'Ann', 'text': '🎤 Voice message (0:12)', 'at': DateTime.now().millisecondsSinceEpoch});
      expect(brain.systems.single, contains('ห้ามเดาเนื้อหา'));
      expect(brain.turns.single, isNot(contains('🎤')));
      final a = askArgs();
      expect(a['draft'], 'ได้รับข้อความเสียงแล้วค่ะ จะแจ้งเจ้าของให้นะคะ');
      expect(a['body'], s.s.chatVoiceAskBody('0:12', 'ได้รับข้อความเสียงแล้วค่ะ จะแจ้งเจ้าของให้นะคะ'));
      expect(s.messages.last.text, s.s.chatVoiceDrafted('Ann', 'WhatsApp', '0:12', a['draft'] as String));
    });

    test('ข้อความเสียง: สมองล่ม = ยังมีคำตอบที่ซื่อตรงให้กดส่ง', () async {
      final s = await inbox(_Brain('', fail: true), {'id': 1000001, 'app': 'jp.naver.line.android', 'who': 'Bee', 'text': 'Bee sent a voice message.', 'at': DateTime.now().millisecondsSinceEpoch});
      final a = askArgs();
      expect(a['draft'], contains('ข้อความเสียง'));
      expect(calls.any((c) => c.method == 'skip'), isFalse);
      expect(s.messages.last.text, contains('Bee'));
    });

    test('SMS: กล่องถามบอกว่าส่งแล้วเสียเงิน', () async {
      final s = await inbox(_Brain('สวัสดีค่ะ'), {'id': 1000002, 'app': 'com.google.android.apps.messaging', 'who': '0812345678', 'text': 'อยู่ไหม', 'at': DateTime.now().millisecondsSinceEpoch, 'sms': true});
      final a = askArgs();
      expect(a['body'], endsWith(s.s.chatSmsCost));
      expect(a['title'], s.s.chatAskTitle('0812345678', 'SMS'));
    });
  });
}
