/// น้องมายโทรออกไปคุยงานแทนเจ้าของ — โต้ตอบ รับข้อมูล ถามเจ้าของกลางสาย
///
/// ที่มา: เจ้าของ — "ให้เธอโทรออก ในหัวข้อที่เราต้องการให้เธอสื่อสาร กับปลายทาง เธอต้องฉลาด
/// มีการโต้ตอบ รับเรื่องราวได้ คุยงานแทนเราได้จริง"
library;

import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/mind_persona.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/phone/call_session.dart';
import 'package:videogirl/phone/call_tags.dart';
import 'package:videogirl/phone/call_watch.dart';
import 'package:videogirl/phone/outgoing_call.dart';
import 'package:videogirl/phone/realtime_call.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';
import 'package:videogirl/theme/tokens.dart';

class _Socket implements RtSocket {
  final sent = <Map<String, Object?>>[];
  final _in = StreamController<Object?>();
  @override
  Stream<Object?> get messages => _in.stream;
  @override
  void send(String text) => sent.add((jsonDecode(text) as Map).cast<String, Object?>());
  @override
  Future<void> close() => _in.close();
  void push(Map<String, Object?> e) => _in.add(jsonEncode(e));

  List<Map<String, Object?>> get outputs => [
        for (final e in sent)
          if (e['type'] == 'conversation.item.create' && (e['item'] as Map)['type'] == 'function_call_output')
            (jsonDecode((e['item'] as Map)['output'] as String) as Map).cast<String, Object?>(),
      ];
}

class _Brain extends OpenAiClient {
  _Brain(this.answer);
  final String answer;
  @override
  bool get usable => true;
  @override
  void close() {}
  @override
  Future<String> reply({required String system, required List<Turn> history, String? model}) async => answer;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<MindState> loaded([String answer = 'x']) async {
    final s = MindState(openai: _Brain(answer));
    addTearDown(s.dispose);
    await s.load();
    s.setBrain(BrainProvider.openai);
    await s.setOpenAiKey('sk-test-key-for-unit-tests');
    return s;
  }

  group('ask_owner ในเซสชันคุยสด', () {
    late _Socket socket;
    late RealtimeCall rt;

    Future<void> open({AskOwner? ask}) async {
      socket = _Socket();
      rt = RealtimeCall(apiKey: 'k', instructions: 'i', greeting: '', connect: (_, _) async => socket);
      rt.onAskOwner = ask;
      await rt.start();
      addTearDown(rt.close);
    }

    List<Object?> toolNames() => [
          for (final t in ((socket.sent.first['session'] as Map)['tools'] as List).cast<Map>()) t['name'],
        ];

    void ask(String id, String question) => socket.push({
          'type': 'response.output_item.done',
          'item': {
            'type': 'function_call',
            'name': 'ask_owner',
            'call_id': id,
            'arguments': jsonEncode({'question': question}),
          },
        });

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('🔴 สายเข้าไม่มีเครื่องมือนี้ · คนนอกสั่งให้เธอสะกิดเจ้าของไม่ได้', () async {
      await open();
      expect(toolNames(), isNot(contains('ask_owner')));
    });

    test('โทรออก = มีเครื่องมือ · เจ้าของตอบ = คำตอบเข้าสายพร้อมบอกว่าห้ามแต่งเพิ่ม', () async {
      final asked = <String>[];
      await open(ask: (q) async {
        asked.add(q);
        return 'สองทุ่มได้ครับ';
      });
      expect(toolNames(), contains('ask_owner'));
      ask('c1', 'ร้านว่างสองทุ่มแทนทุ่มนึง ได้ไหมคะ');
      await settle();
      expect(asked, ['ร้านว่างสองทุ่มแทนทุ่มนึง ได้ไหมคะ']);
      final out = socket.outputs.single;
      expect(out['answered'], isTrue);
      expect(out['boss_reply'], 'สองทุ่มได้ครับ');
      expect('${out['note']}', contains('Do not add or promise'));
      expect(socket.sent.last['type'], 'response.create', reason: 'ได้คำตอบแล้วเธอต้องพูดต่อทันที');
    });

    test('เจ้าของไม่ตอบ = บอกให้เธอแจ้งว่าจะยืนยันแล้วติดต่อกลับ ไม่เดา', () async {
      await open(ask: (q) async => null);
      ask('c1', 'ราคานี้รับได้ไหม');
      await settle();
      final out = socket.outputs.single;
      expect(out['answered'], isFalse);
      expect('${out['note']}', contains('Do not guess'));
    });

    test('🔴 ถามซ้อนระหว่างรอ = ไม่ส่งคำถามที่สอง · ถามเกินสามครั้ง = ไม่ถามอีก', () async {
      final asked = <String>[];
      final waiting = Completer<String?>();
      await open(ask: (q) {
        asked.add(q);
        return asked.length == 1 ? waiting.future : Future.value('ได้');
      });
      ask('c1', 'หนึ่ง');
      await settle();
      ask('c2', 'สอง');
      await settle();
      expect(asked, ['หนึ่ง'], reason: 'คำถามแรกยังไม่ได้คำตอบ');
      expect(socket.outputs.single['answered'], isFalse);
      waiting.complete('ได้');
      await settle();
      for (final id in ['c3', 'c4', 'c5']) {
        ask(id, 'อีก $id');
        await settle();
      }
      expect(asked, hasLength(VoiceSession.maxOwnerQuestions));
      expect(socket.outputs.last['answered'], isFalse);
    });

    test('🔴 เจ้าของไม่อยู่ = ไม่ถาม ไม่พักสาย · บอกให้ใช้ไหวพริบ ไม่นับเป็นคำถาม', () async {
      var asked = 0;
      await open(ask: (q) async {
        asked++;
        return 'x';
      });
      rt.ownerAvailable = false;
      ask('c1', 'ราคานี้รับได้ไหม');
      await settle();
      expect(asked, 0);
      final out = socket.outputs.single;
      expect(out['answered'], isFalse);
      expect('${out['note']}', contains('Do not put them on hold'));
      expect('${out['note']}', contains('Do not guess'));
      expect(socket.sent.last['type'], 'response.create', reason: 'เธอต้องพูดต่อทันที ไม่เงียบรอ');
    });

    test('เจ้าของไม่ตอบแล้วผู้เรียกถือว่าไม่อยู่ = ได้คำสั่งแบบไม่อยู่ ไม่ใช่ "รอก่อน"', () async {
      await open(ask: (q) async {
        rt.ownerAvailable = false; // CallSession ทำแบบนี้ตอนหมดเวลา
        return null;
      });
      ask('c1', 'q');
      await settle();
      expect('${socket.outputs.single['note']}', VoiceSession.ownerAwayNote);
    });

    test('อาร์กิวเมนต์เสีย = ยังตอบกลับ ไม่ปล่อยเธอค้างรอ', () async {
      var asked = 0;
      await open(ask: (q) async {
        asked++;
        return 'x';
      });
      socket.push({
        'type': 'response.output_item.done',
        'item': {'type': 'function_call', 'name': 'ask_owner', 'call_id': 'c1', 'arguments': 'ไม่ใช่ json'},
      });
      await settle();
      expect(asked, 0);
      expect(socket.outputs.single['answered'], isFalse);
    });
  });

  group('prompt ของสายโทรออก', () {
    test('🔴 คุยสดโทรออก: สอน ask_owner · รับข้อมูลแล้วทวน · ตกลงได้เฉพาะในขอบเขต · ไม่จีบ', () async {
      final s = await loaded();
      s.setCallPlay(1);
      s.debugSetOutgoing((who: 'ร้านส้มตำ', number: '021234567', task: 'เป้าหมาย: จองโต๊ะ 2 ที่ ทุ่มนึง'));
      final p = s.callPrompt(live: true, outgoing: true);
      for (final want in ['ask_owner', 'ขอเช็กกับเจ้านายสักครู่', 'ทวนทีละเรื่อง', 'เฉพาะในขอบเขตที่เจ้าของสั่ง', 'บุคลิกตอนโทรออก']) {
        expect(p, contains(want), reason: 'ขาด: $want');
      }
      expect(p, isNot(contains('จีบเล่น')), reason: 'ความขี้เล่นที่ตั้งให้คนโทรเข้าไม่ใช้กับสายงาน');
      expect(p, isNot(contains('[[')), reason: 'แท็กในโหมดสดจะถูกอ่านออกเสียง');
    });

    test('ทางเดิม (ไม่มีเครื่องมือ) ไม่สัญญาว่าจะถามเจ้าของกลางสาย · สายเข้าไม่มี ask_owner', () async {
      final s = await loaded();
      s.debugSetOutgoing((who: 'ร้าน', number: '02', task: 'จอง'));
      expect(s.callPrompt(outgoing: true), isNot(contains('ask_owner')));
      expect(s.callPrompt(outgoing: true), contains('จะเช็กกับเจ้านายแล้วติดต่อกลับ'));
      s.debugSetOutgoing(null);
      expect(s.callPrompt(live: true), isNot(contains('ask_owner')));
    });

    test('แชทสอนให้เขียนเรื่องแบบมีหัวข้อ: เป้าหมาย · บอกได้ · ยืดหยุ่นได้ · ขอกลับมา', () {
      final chat = MindPersona.system(
          mode: MindMode.work, flirt: 0, ownerProfile: '', boundaries: '', lang: AppLang.th, callOut: true);
      for (final want in ['เป้าหมาย:', 'บอกได้:', 'ยืดหยุ่นได้:', 'ขอกลับมา:']) {
        expect(chat, contains(want), reason: 'ขาด: $want');
      }
    });

    test('ถามได้ = สอนว่าถามเฉพาะเรื่องที่ตัดสินแทนไม่ได้จริง ๆ และบอกว่าไมค์ฝั่งเจ้าของปิด · มีไหวพริบเสมอ', () async {
      final s = await loaded();
      s.debugSetOutgoing((who: 'ร้าน', number: '02', task: 'จองโต๊ะ'));
      final p = s.callPrompt(live: true, outgoing: true);
      for (final want in ['ตัดสินใจเองก่อนเสมอ', 'ตัดสินแทนไม่ได้จริง ๆ', 'ไมค์ฝั่งเจ้าของถูกปิด', 'ห้ามพักสายถามอีก', 'ไหวพริบ', 'กันไว้ให้ก่อน']) {
        expect(p, contains(want), reason: 'ขาด: $want');
      }
    });

    test('🔴 เจ้าของสั่ง "ห้ามถามฉัน" = ไม่สอน ask_owner · ห้ามพักสาย · รับเรื่องไว้ด้วยไหวพริบ', () async {
      final s = await loaded();
      s.debugSetOutgoing((who: 'ร้าน', number: '02', task: 'ถามราคาส่ง ห้ามถามฉันนะ รับเรื่องไว้'));
      expect(s.outgoingMayAskOwner, isFalse);
      final p = s.callPrompt(live: true, outgoing: true);
      expect(p, isNot(contains('ask_owner')));
      for (final want in ['ถามเจ้าของระหว่างสายไม่ได้', 'ห้ามพักสาย', 'ไหวพริบ', 'นัดเวลาติดต่อกลับ']) {
        expect(p, contains(want), reason: 'ขาด: $want');
      }
      // สวิตช์ในกล่องยืนยันชนะคำในเรื่อง
      s.debugSetOutgoing((who: 'ร้าน', number: '02', task: 'ห้ามถามฉัน'), askOwner: true);
      expect(s.outgoingMayAskOwner, isTrue);
    });

    test('จับคำสั่งห้ามถามเจ้าของ · ไม่จับคำสั่งเรื่องปลายสาย', () {
      for (final yes in [
        'ห้ามถามฉัน คุณรับเรื่องไว้',
        'อย่าโทรมาถามฉันนะ',
        'ไม่ต้องถามเรา ตัดสินตามนี้',
        'ฉันไม่ว่างทั้งวัน',
        "Don't ask me, just take a message",
        'I am busy all afternoon',
      ]) {
        expect(OutgoingRules.noAsking(yes), isTrue, reason: yes);
      }
      for (final no in ['ไม่ต้องถามเขาเรื่องราคา', 'ถามราคาส่งให้หน่อย', 'ask them for the price']) {
        expect(OutgoingRules.noAsking(no), isFalse, reason: no);
      }
    });

    test('สายงานได้เวลาอย่างน้อยหกนาที · ไม่จำกัด = ไม่จำกัดเหมือนเดิม', () {
      expect(MindState.outgoingWrapMinutes(3), 6);
      expect(MindState.outgoingWrapMinutes(10), 10);
      expect(MindState.outgoingWrapMinutes(0), 0);
    });
  });

  test('🔴 แท็กสั่งโทรที่ยาวแบบมีหัวข้อยังอ่านได้ (เพดานเดิม 400 = ไม่มีกล่องยืนยัน)', () {
    final task = 'เป้าหมาย: จองโต๊ะ 4 ที่ วันเสาร์ทุ่มนึง ในชื่อคุณต้น · '
        'บอกได้: มีเด็กหนึ่งคน ขอเก้าอี้เด็ก ${'รายละเอียด ' * 40}· ขอกลับมา: ค่ามัดจำ';
    expect(task.length, greaterThan(400));
    final r = CallOutTag.parse('ได้ค่ะ\n[[โทร: 021234567 | $task]]');
    expect(r.target, '021234567');
    expect(r.task, task.trim());
  });

  test('เจ้าของแก้เรื่องในกล่องยืนยัน = เธอคุยตามที่แก้ · ว่าง = ใช้ของเธอ', () async {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(kSystemChannel, (c) async => null);
    addTearDown(() => m.setMockMethodCallHandler(kSystemChannel, null));
    final s = await loaded('ได้ค่ะ [[โทร: 021234567 | จองโต๊ะ]]');
    await s.send('โทรจอง');
    await Future<void>.delayed(Duration.zero);
    await s.confirmPendingCall(task: '  จองโต๊ะ 3 ที่ สองทุ่ม  ');
    expect(s.outgoing?.task, 'จองโต๊ะ 3 ที่ สองทุ่ม');

    final s2 = await loaded('ได้ค่ะ [[โทร: 021234567 | จองโต๊ะ]]');
    await s2.send('โทรจอง');
    await Future<void>.delayed(Duration.zero);
    await s2.confirmPendingCall(task: '   ');
    expect(s2.outgoing?.task, 'จองโต๊ะ');
  });

  group('คำถามกลางสายบนจอและแถบแจ้งเตือน', () {
    late List<MethodCall> calls;
    late Map<String, Object?> info;
    late CallSession call;
    late CallWatch watch;

    setUp(() async {
      calls = [];
      info = {'live': false};
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(kSystemChannel, (c) async {
        calls.add(c);
        return c.method == 'callInfo' ? info : true;
      });
      final s = await loaded();
      watch = CallWatch();
      call = CallSession(watch: watch, state: s);
      addTearDown(() {
        call.dispose();
        watch.dispose();
        m.setMockMethodCallHandler(kSystemChannel, null);
      });
    });

    test('เจ้าของตอบบนจอสาย = เธอได้คำตอบ · ช่องตอบกับแจ้งเตือนหายไป', () async {
      final answer = call.debugAskOwner('สองทุ่มแทนได้ไหมคะ');
      expect(call.ownerQuestion, 'สองทุ่มแทนได้ไหมคะ');
      await Future<void>.delayed(Duration.zero);
      final posted = calls.singleWhere((c) => c.method == 'askOwner');
      expect((posted.arguments as Map)['body'], 'สองทุ่มแทนได้ไหมคะ');
      expect((posted.arguments as Map)['choices'], isNotEmpty);
      call.answerOwner('  ได้ ตกลงตามนั้น ');
      expect(await answer, 'ได้ ตกลงตามนั้น');
      expect(call.ownerQuestion, isNull);
      expect(calls.where((c) => c.method == 'askOwnerDone'), isNotEmpty);
    });

    test('เจ้าของตอบจากแถบแจ้งเตือน = มาทาง callInfo · คำตอบของคำถามเก่าไม่นับ', () async {
      final answer = call.debugAskOwner('ราคานี้รับได้ไหม');
      info = {
        'live': false,
        'ownerReply': {'id': 99, 'text': 'ของคำถามเก่า'},
      };
      await call.start();
      expect(call.ownerQuestion, 'ราคานี้รับได้ไหม', reason: 'เลขคำถามไม่ตรง');
      info = {
        'live': false,
        'ownerReply': {'id': 1, 'text': 'รับได้'},
      };
      await call.start();
      expect(await answer, 'รับได้');
    });

    test('🔴 จอดับ/ล็อก = ไม่ถาม ไม่เด้งแจ้งเตือน · ถือว่าไม่อยู่ทั้งสาย', () async {
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(kSystemChannel, (c) async {
        calls.add(c);
        return c.method == 'ownerPresent' ? false : true;
      });
      expect(await call.debugAskOwner('q'), isNull);
      expect(call.ownerAway, isTrue);
      expect(call.ownerQuestion, isNull);
      expect(calls.where((c) => c.method == 'askOwner'), isEmpty);
      calls.clear();
      expect(await call.debugAskOwner('q2'), isNull, reason: 'ไม่อยู่แล้ว = ไม่ถามซ้ำ');
      expect(calls.where((c) => c.method == 'ownerPresent'), isEmpty);
    });

    test('เจ้าของกด "ไม่ว่าง" = คำถามที่ค้างจบทันที และไม่ถามอีก · ไมค์ไม่ค้างปิด', () async {
      call.debugCanAskOwner = true;
      final answer = call.debugAskOwner('สองทุ่มได้ไหม');
      await Future<void>.delayed(Duration.zero);
      call.setOwnerAway(true);
      expect(await answer, isNull);
      expect(call.ownerAway, isTrue);
      expect(call.ownerQuestion, isNull);
      expect(call.holdMuted, isFalse);
      call.setOwnerAway(false);
      expect(call.ownerAway, isFalse);
    });

    test('ไม่ตอบใน ${CallSession.ownerAnswerWait.inSeconds} วิ = ถือว่าไม่อยู่', () {
      fakeAsync((async) {
        String? got = 'pending';
        call.debugAskOwner('q').then((v) => got = v);
        async.flushMicrotasks();
        async.elapse(CallSession.ownerAnswerWait + const Duration(seconds: 1));
        expect(got, isNull);
        expect(call.ownerAway, isTrue);
      });
    });

    test('ตอบว่าง ๆ ไม่นับเป็นคำตอบ', () async {
      unawaited(call.debugAskOwner('q'));
      call.answerOwner('   ');
      expect(call.ownerQuestion, 'q');
    });
  });
}
