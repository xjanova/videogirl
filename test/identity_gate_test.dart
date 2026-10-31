/// คำถามยืนยันตัวตน — ตอบถูกครบถึงสั่งให้เธอใช้เครื่องในสายได้ · ตัดสินในแอป ไม่ใช่ที่โมเดล
///
/// ที่มา: เจ้าของ — "ให้ยืนยันด้วยคำถาม ยืนยันตัวตน อย่างน้อย 3 ข้อ เพื่อเข้าถึงสิทธิ์ เรากำหนดได้ในแอพว่าต้องตอบอะไร"
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/hands/phone_task.dart';
import 'package:videogirl/phone/call_phone.dart';
import 'package:videogirl/phone/identity_gate.dart';
import 'package:videogirl/phone/live_call.dart';
import 'package:videogirl/phone/owner_gate.dart';
import 'package:videogirl/phone/realtime_call.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';

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

  /// ข้อความระบบที่แอปส่งเข้าเซสชันกลางสาย (remind / announce)
  List<String> get systemNotes => [
        for (final e in sent)
          if (e['type'] == 'conversation.item.create' && (e['item'] as Map)['role'] == 'system')
            '${(((e['item'] as Map)['content'] as List).first as Map)['text']}',
      ];
}

// คำตอบที่ไม่มีทางโผล่ในข้อความอื่นโดยบังเอิญ · ใช้เช็กว่าไม่หลุดออกไปไหน
const _qa = [
  IdentityQuestion('แมวตัวแรกที่บ้านชื่ออะไร', 'ส้มโอหวาน'),
  IdentityQuestion('ซอยบ้านเก่าเลขอะไร', 'ซอยเจ็ดสิบสาม'),
  IdentityQuestion('ครูประจำชั้นตอน ป.6 ชื่ออะไร', 'ครูมาลัยทอง'),
  IdentityQuestion('What was the name of the first boat?', 'Blue Heron'),
  IdentityQuestion('อาหารที่แม่ทำวันเกิดทุกปี', 'แกงฮังเลหมู'),
];

String _answerOf(String question) => _qa.firstWhere((q) => q.question == question).answer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('IdentityQuiz', () {
    test('ต้องมี 3–10 ข้อ · ถามต่อสาย 3..จำนวนข้อ · ครบเงื่อนไขถึงพร้อมใช้', () {
      expect(const IdentityQuiz([]).problem, QuizProblem.tooFew);
      expect(IdentityQuiz(_qa.take(2).toList()).problem, QuizProblem.tooFew);
      expect(IdentityQuiz(_qa.take(3).toList()).ready, isTrue);
      expect(IdentityQuiz(_qa, ask: 5).ready, isTrue);
      expect(IdentityQuiz(_qa, ask: 6).problem, QuizProblem.askOutOfRange);
      expect(IdentityQuiz(_qa, ask: 2).problem, QuizProblem.askOutOfRange);
      final many = [for (var i = 0; i < 11; i++) IdentityQuestion('question number $i', 'answer$i')];
      expect(IdentityQuiz(many).problem, QuizProblem.tooMany);
    });

    test('คำตอบสั้นเกิน · คำถามซ้ำ · คำถามว่าง · ยาวเกิน · คำถามที่มีคำตอบอยู่ในตัว', () {
      IdentityQuiz with3(IdentityQuestion third) => IdentityQuiz([_qa[0], _qa[1], third]);
      expect(with3(const IdentityQuestion('สีโปรด', 'ก')).problem, QuizProblem.answerTooShort);
      expect(with3(const IdentityQuestion('เลขนำโชค', 'หก')).problem, QuizProblem.answerTooShort,
          reason: 'คำอ่านตัวเลขกลายเป็นเลขตัวเดียว');
      expect(with3(const IdentityQuestion('สีโปรด', ' - ')).problem, QuizProblem.answerTooShort);
      expect(with3(const IdentityQuestion('แมว ตัวแรก ที่บ้านชื่ออะไร?', 'อื่น ๆ')).problem, QuizProblem.duplicate);
      expect(with3(const IdentityQuestion('???', 'ตอบ')).problem, QuizProblem.emptyQuestion);
      expect(with3(IdentityQuestion('ถาม' * 41, 'ตอบได้')).problem, QuizProblem.tooLong);
      expect(with3(IdentityQuestion('สีโปรด', 'ก' * 61)).problem, QuizProblem.tooLong);
      expect(with3(const IdentityQuestion('ชื่อ ส้มโอหวาน เป็นของใคร', 'น้องหมา')).problem, QuizProblem.answerInQuestion,
          reason: 'คำถามถูกอ่านให้คนโทรฟัง · มีคำตอบข้ออื่นอยู่ในนั้น = แจกคำตอบ');
    });

    test('เก็บแล้วอ่านกลับได้เหมือนเดิม · ข้อมูลเสีย = ไม่มีคำถาม · จำนวนข้อที่ถามถูกบีบเข้าช่วง', () {
      final q = IdentityQuiz(_qa, ask: 4);
      final back = IdentityQuiz.decode(q.encode());
      expect(back.ready, isTrue);
      expect(back.asks, 4);
      expect([for (final x in back.items) x.answer], [for (final x in _qa) x.answer]);
      expect(IdentityQuiz.decode('not json').items, isEmpty);
      expect(IdentityQuiz.decode(null).ready, isFalse);
      final odd = jsonDecode(q.encode()) as Map<String, Object?>..['ask'] = 99;
      expect(IdentityQuiz.decode(jsonEncode(odd)).asks, 5);
      expect(q.withoutAnswers().items.every((x) => x.answer.isEmpty), isTrue);
    });

    test('เทียบคำตอบ: ไม่สนช่องว่าง ตัวใหญ่เล็ก คำอ่านตัวเลข · คำติดมานิดหน่อยได้ · คำเดาหลายคำทีเดียวไม่ได้', () {
      expect(IdentityQuiz.matches('ซอย 73', 'ซอยเจ็ดสาม'), isTrue);
      expect(IdentityQuiz.matches('Blue Heron', 'blue heron.'), isTrue);
      expect(IdentityQuiz.matches('Blue Heron', "it's blue heron"), isTrue);
      expect(IdentityQuiz.matches('แมว', 'แมวค่ะ'), isTrue);
      expect(IdentityQuiz.matches('แมว', 'หมา แมว นก ปลา หนู'), isFalse, reason: 'คำตอบสั้น = ยอมคำติดมาน้อย');
      expect(IdentityQuiz.matches('แกงฮังเลหมู', 'แกงเขียวหวาน'), isFalse);
      expect(IdentityQuiz.matches('แกงฮังเลหมู', ''), isFalse);
    });
  });

  group('IdentityGate', () {
    IdentityGate gate({
      IdentityQuiz? quiz,
      bool Function()? locked,
      Future<void> Function()? fail,
      void Function()? onPassed,
      void Function({required bool locked})? onRefused,
      int seed = 7,
    }) =>
        IdentityGate(
          quiz: quiz ?? IdentityQuiz(_qa, ask: 3),
          isLocked: locked ?? () => false,
          recordFail: fail ?? () async {},
          onPassed: onPassed,
          onRefused: onRefused,
          random: math.Random(seed),
        );

    test('ถามครบจำนวนที่ตั้ง · ไม่ซ้ำข้อ · ข้อเดิมซ้ำได้ถ้ายังไม่ได้คำตอบ', () async {
      final g = gate(quiz: IdentityQuiz(_qa, ask: 4));
      final asked = <String>[];
      var r = await g.question();
      expect((await g.question())['question'], r['question'], reason: 'เรียกซ้ำก่อนตอบ = ข้อเดิม');
      while (r.containsKey('question')) {
        asked.add('${r['question']}');
        r = await g.answer(_answerOf('${r['question']}'));
      }
      expect(asked.length, 4);
      expect(asked.toSet().length, 4);
      expect(r['verified'], isTrue);
    });

    test('ตอบถูกครบ = ผ่าน · onPassed ครั้งเดียว · เปิดความจำเรื่องเจ้าของ', () async {
      var passed = 0;
      final owner = OwnerGate(check: (_) async => CodeCheck.wrong, recall: (_) async => const [], hasCode: false);
      final g = gate(onPassed: () {
        passed++;
        owner.grant();
      });
      var r = await g.question();
      while (r.containsKey('question')) {
        r = await g.answer('คือ ${_answerOf('${r['question']}')}');
      }
      expect(r['verified'], isTrue);
      expect(g.passed, isTrue);
      expect((await g.question())['verified'], isTrue);
      expect((await g.answer('อะไรก็ได้'))['verified'], isTrue);
      expect(passed, 1);
      expect(owner.open, isTrue);
      expect((await owner.lookup('เจ้าของชอบอะไร'))['allowed'], isTrue);
    });

    test('🔴 ผิดข้อเดียว = ไม่ผ่าน แต่บอกผลหลังถามครบเท่านั้น · ไม่มีคำตอบหรือเลขข้อที่ผิดหลุดออกไป', () async {
      var fails = 0;
      final refused = <bool>[];
      final g = gate(
        fail: () async => fails++,
        onRefused: ({required bool locked}) => refused.add(locked),
        onPassed: () => fail('ต้องไม่ผ่าน'),
      );
      final outs = <Map<String, Object?>>[await g.question()];
      // ข้อแรกตอบผิด ที่เหลือถูก
      outs.add(await g.answer('ไม่รู้เหมือนกัน'));
      expect(outs.last.containsKey('verified'), isFalse, reason: 'ยังไม่บอกผลก่อนถามครบ');
      expect(outs.last['question'], isNotNull);
      outs.add(await g.answer(_answerOf('${outs.last['question']}')));
      expect(outs.last.containsKey('verified'), isFalse);
      outs.add(await g.answer(_answerOf('${outs.last['question']}')));
      expect(outs.last['verified'], isFalse);
      expect(g.passed, isFalse);
      expect(fails, 1);
      expect(refused, [false]);

      final all = jsonEncode(outs);
      for (final q in _qa) {
        expect(all, isNot(contains(q.answer)), reason: 'คำตอบหลุด: ${q.answer}');
      }
      final last = '${outs.last['note']}'.toLowerCase();
      for (final hint in ['first', 'question 1', 'number 1', 'second', 'third']) {
        expect(last, isNot(contains(hint)), reason: 'บอกใบ้ว่าข้อไหนผิด: $hint');
      }
      expect(outs.last.keys, unorderedEquals(['verified', 'note']), reason: 'ผลสุดท้ายไม่มีอะไรรายข้อ');

      // ครั้งเดียวต่อสาย · ไม่ถามใหม่ ไม่นับซ้ำ ไม่แจ้งซ้ำ
      final again = await g.question();
      expect(again['verified'], isFalse);
      expect(again.containsKey('question'), isFalse);
      expect((await g.answer(_answerOf(_qa.first.question)))['verified'], isFalse);
      expect(fails, 1);
      expect(refused, [false]);
    });

    test('ตอบก่อนถาม = ไม่นับ · คำตอบว่าง = ถามข้อเดิมใหม่', () async {
      final g = gate();
      expect((await g.answer('ส้มโอหวาน'))['recorded'], isFalse);
      expect(g.started, isFalse);
      final q = await g.question();
      final empty = await g.answer('  ');
      expect(empty['recorded'], isFalse);
      expect(empty['question'], q['question']);
    });

    test('ล็อกอยู่ = ไม่ถามเลย แจ้งเจ้าของว่าล็อก', () async {
      final refused = <bool>[];
      final g = gate(locked: () => true, onRefused: ({required bool locked}) => refused.add(locked));
      final r = await g.question();
      expect(r['verified'], isFalse);
      expect(r.containsKey('question'), isFalse);
      expect(refused, [true]);
    });

    test('ระหว่างนับครั้งที่ไม่ผ่าน เรียกซ้อนไม่ได้', () async {
      final hold = Completer<void>();
      final g = gate(fail: () => hold.future);
      await g.question();
      await g.answer('ผิด');
      await g.answer('ผิด');
      final last = g.answer('ผิด');
      final busy = await g.question();
      expect('${busy['note']}', contains('already checking'));
      hold.complete();
      expect((await last)['verified'], isFalse);
    });
  });

  group('เครื่องมือในสาย', () {
    late _Socket socket;
    late RealtimeCall rt;

    Future<void> open({OwnerGate? owner, IdentityGate? ids, CallPhone? phone}) async {
      socket = _Socket();
      rt = RealtimeCall(apiKey: 'k', instructions: 'i', greeting: '', connect: (_, _) async => socket);
      rt.ownerGate = owner;
      rt.identityGate = ids;
      rt.phone = phone;
      await rt.start();
      phone?.sink = rt.announce;
      addTearDown(rt.close);
    }

    List<Object?> toolNames() => [
          for (final t in ((socket.sent.first['session'] as Map)['tools'] as List).cast<Map>()) t['name'],
        ];

    void call(String id, String name, Map<String, Object?> args) => socket.push({
          'type': 'response.output_item.done',
          'item': {'type': 'function_call', 'name': name, 'call_id': id, 'arguments': jsonEncode(args)},
        });

    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    IdentityGate ids({void Function()? onPassed}) => IdentityGate(
          quiz: IdentityQuiz(_qa.take(3).toList()),
          isLocked: () => false,
          recordFail: () async {},
          onPassed: onPassed,
          random: math.Random(1),
        );

    Future<void> pass() async {
      call('q', 'identity_question', const {});
      await settle();
      var out = socket.outputs.last;
      var n = 0;
      while (out.containsKey('question')) {
        call('a${n++}', 'identity_answer', {'answer': _answerOf('${out['question']}')});
        await settle();
        out = socket.outputs.last;
      }
      expect(out['verified'], isTrue);
    }

    test('ค่าตั้งต้นไม่เปลี่ยน · ไม่มีเครื่องมือยืนยันตัวหรือใช้เครื่อง', () {
      List<Object?> names(List<Map<String, Object?>> t) => [for (final x in t) x['name']];
      expect(names(callTools(lookup: true)), ['end_call', 'alert_owner', 'lookup_info']);
      expect(names(callTools(lookup: false, gate: true)), ['end_call', 'alert_owner', 'check_code', 'recall_owner']);
      expect(names(callTools(lookup: false, gate: true, code: false)), ['end_call', 'alert_owner', 'recall_owner']);
      expect(names(callTools(lookup: false, identity: true)),
          ['end_call', 'alert_owner', 'identity_question', 'identity_answer']);
      expect(names(callTools(lookup: false, identity: true, phone: true)), [
        'end_call', 'alert_owner', 'identity_question', 'identity_answer', //
        'phone_task', 'phone_task_status', 'phone_task_stop', 'phone_task_confirm',
      ]);
    });

    test('มีคำถามแต่ไม่มีโค้ด = มี recall_owner และ identity_* · ไม่มี check_code', () async {
      await open(
        owner: OwnerGate(check: (_) async => CodeCheck.wrong, recall: (_) async => const [], hasCode: false),
        ids: ids(),
      );
      expect(toolNames(), containsAll(['recall_owner', 'identity_question', 'identity_answer']));
      expect(toolNames(), isNot(contains('check_code')));
      expect(toolNames(), isNot(contains('phone_task')));
    });

    test('🔴 phone_task ก่อนยืนยันตัว = ไม่ทำ (ไม่เรียกงานเลย) · ผ่านแล้วเริ่มทันทีและรายงานผลทีหลัง', () async {
      var runs = 0;
      final done = Completer<PhoneTaskResult>();
      final g = ids();
      final phone = CallPhone(
        identity: g,
        run: (goal, confirm) {
          runs++;
          return done.future;
        },
        view: () => null,
        stop: () {},
      );
      await open(ids: g, phone: phone);
      expect(toolNames(), containsAll(['phone_task', 'phone_task_status', 'phone_task_stop', 'phone_task_confirm']));

      call('p0', 'phone_task', {'goal': 'เปิด LINE ส่งหาแม่ว่าถึงแล้ว'});
      await settle();
      expect(socket.outputs.last['allowed'], isFalse);
      call('p1', 'phone_task_status', const {});
      await settle();
      expect(socket.outputs.last['allowed'], isFalse);
      expect(runs, 0, reason: 'ยังไม่ยืนยันตัว ต้องไม่แตะเครื่องเลย');

      await pass();
      call('p2', 'phone_task', {'goal': 'เปิด LINE ส่งหาแม่ว่าถึงแล้ว'});
      await settle();
      expect(socket.outputs.last['started'], isTrue);
      expect(runs, 1);
      call('p3', 'phone_task', {'goal': 'อีกงาน'});
      await settle();
      expect(socket.outputs.last['started'], isFalse, reason: 'ทำทีละงาน');

      final creates = socket.sent.where((e) => e['type'] == 'response.create').length;
      done.complete(const PhoneTaskResult(PhoneOutcome.done, 'ส่งข้อความหาแม่แล้ว'));
      await settle();
      expect(socket.systemNotes.last, contains('is done'));
      expect(socket.systemNotes.last, contains('ส่งข้อความหาแม่แล้ว'));
      expect(socket.sent.where((e) => e['type'] == 'response.create').length, greaterThan(creates),
          reason: 'ผลมาทีหลัง ต้องให้เธอพูดบอกคนในสาย');
      expect(jsonEncode(socket.sent), isNot(contains(_qa.first.answer)));
    });

    test('ขั้นที่ต้องยืนยัน: ถามคนในสายผ่านเซสชัน · ตอบผ่าน phone_task_confirm · ไม่มีอะไรรอ = บอกว่าไม่มี', () async {
      final asked = Completer<bool>();
      final g = ids();
      final phone = CallPhone(
        identity: g,
        run: (goal, confirm) async {
          final ok = await confirm(const PhoneStepAsk(id: 1, goal: 'g', action: 'กด «ส่ง»', app: 'LINE'));
          asked.complete(ok);
          return PhoneTaskResult(ok ? PhoneOutcome.done : PhoneOutcome.stopped, '');
        },
        view: () => null,
        stop: () {},
      );
      await open(ids: g, phone: phone);
      call('c0', 'phone_task_confirm', {'approve': true});
      await settle();
      expect(socket.outputs.last['allowed'], isFalse, reason: 'ยังไม่ยืนยันตัว');
      await pass();
      call('c1', 'phone_task_confirm', {'approve': true});
      await settle();
      expect('${socket.outputs.last['note']}', contains('Nothing is waiting'));

      call('c2', 'phone_task', {'goal': 'ส่ง LINE'});
      await settle();
      expect(socket.systemNotes.last, contains('กด «ส่ง»'));
      expect(socket.systemNotes.last, contains('phone_task_confirm'));
      call('c3', 'phone_task_confirm', {'approve': true});
      await settle();
      expect(await asked.future, isTrue);
    });

    test('ไม่ตอบยืนยันในเวลา = ไม่ทำ · สายจบระหว่างทำ = หยุดงานที่สั่งจากสายนี้', () async {
      final g = ids();
      final result = Completer<bool>();
      var stopped = 0;
      final hang = Completer<PhoneTaskResult>();
      final phone = CallPhone(
        identity: g,
        confirmWait: const Duration(milliseconds: 20),
        run: (goal, confirm) async {
          result.complete(await confirm(const PhoneStepAsk(id: 1, goal: 'g', action: 'ลบ', app: 'Files')));
          return hang.future;
        },
        view: () => null,
        stop: () => stopped++,
      );
      await open(ids: g, phone: phone);
      await pass();
      call('t1', 'phone_task', {'goal': 'ลบไฟล์เก่า'});
      await settle();
      expect(await result.future.timeout(const Duration(seconds: 2)), isFalse);
      expect(phone.running, isTrue);
      phone.endOfCall();
      expect(stopped, 1);
      hang.complete(const PhoneTaskResult(PhoneOutcome.stopped, ''));
    });

    test('GPT-Live: ข้อความที่มาทีหลังต่อท้ายคำสั่งเซสชัน (ให้เธอพูด) ไม่ใช่ความคิดเงียบ', () async {
      final s = _Socket();
      final live = LiveCall(apiKey: 'k', instructions: 'i', greeting: '', connect: (_, _) async => s);
      final started = live.start();
      await Future<void>.delayed(Duration.zero);
      s.push({'type': 'session.started', 'session': {'id': 'x'}});
      await started;
      addTearDown(live.close);
      live.announce('Update on the phone task');
      expect(s.sent.last['type'], 'session.instructions.append');
      expect('${s.sent.last['content']}', contains('Update on the phone task'));
    });
  });

  group('MindState', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(kSystemChannel, (c) async {
        calls.add(c);
        return true;
      });
      addTearDown(() => m.setMockMethodCallHandler(kSystemChannel, null));
    });

    Future<MindState> loaded(DateTime Function() clock) async {
      final s = MindState(clock: clock);
      addTearDown(s.dispose);
      await s.load();
      return s;
    }

    Future<Map<String, Object?>> attempt(IdentityGate g, {required bool right}) async {
      var r = await g.question();
      while (r.containsKey('question')) {
        r = await g.answer(right ? _answerOf('${r['question']}') : 'ผิดแน่นอน');
      }
      return r;
    }

    test('🔴 คำตอบไม่อยู่ใน prompt ของสาย · กฎยืนยันตัวมีเฉพาะคุยสดที่ตั้งคำถามแล้ว', () async {
      final s = await loaded(() => DateTime(2026, 10, 31, 10));
      expect(s.callPrompt(live: true), isNot(contains('identity_question')));
      s.debugSetCallQuiz(IdentityQuiz(_qa));
      for (final p in [s.callPrompt(), s.callPrompt(live: true), s.callPrompt(live: true, outgoing: true)]) {
        for (final q in _qa) {
          expect(p, isNot(contains(q.answer)));
          expect(p, isNot(contains(q.question)), reason: 'คำถามก็ไม่อยู่ใน prompt · มาทีละข้อจากเครื่องมือ');
        }
      }
      expect(s.callPrompt(live: true), contains('identity_question'));
      expect(s.callPrompt(), isNot(contains('identity_question')), reason: 'ทางเดิมไม่มีเครื่องมือ');
      expect(s.callQuiz.items.every((q) => q.answer.isEmpty), isTrue, reason: 'หน้าจอทั่วไปไม่ได้คำตอบ');
      expect(s.ownerGateForCall(who: 'x')?.hasCode, isFalse, reason: 'มีคำถามอย่างเดียว = ไม่มี check_code');
    });

    test('ไม่ผ่านสามครั้งใน 24 ชั่วโมง = ล็อก (ตอบถูกก็ไม่ถาม) · ผ่านไม่ล้างตัวนับ · พ้น 25 ชั่วโมงเปิดเอง', () async {
      var now = DateTime(2026, 10, 31, 10);
      final s = await loaded(() => now);
      s.debugSetCallQuiz(IdentityQuiz(_qa));
      expect((await attempt(s.identityGateForCall(who: 'ก')!, right: false))['verified'], isFalse);
      expect((await attempt(s.identityGateForCall(who: 'ข')!, right: true))['verified'], isTrue);
      expect(s.identityLockedUntil, isNull);
      expect((await attempt(s.identityGateForCall(who: 'ค')!, right: false))['verified'], isFalse);
      expect((await attempt(s.identityGateForCall(who: 'ง')!, right: false))['verified'], isFalse);
      expect(s.identityLockedUntil, isNotNull, reason: 'ผ่านคั่นกลางไม่ล้างตัวนับ');

      final locked = s.identityGateForCall(who: 'จ')!;
      final r = await locked.question();
      expect(r['verified'], isFalse);
      expect(r.containsKey('question'), isFalse, reason: 'ล็อกแล้วไม่ถามเลย');

      now = now.add(const Duration(hours: 25));
      expect(s.identityLockedUntil, isNull);
      expect((await attempt(s.identityGateForCall(who: 'ฉ')!, right: true))['verified'], isTrue);
    });

    test('เปลี่ยนคำถาม = ล้างตัวนับ · ประตูของสายที่เปิดอยู่ใช้ชุดเก่าไม่ได้อีก', () async {
      final s = await loaded(() => DateTime(2026, 10, 31, 10));
      expect(await s.setCallQuiz(IdentityQuiz(_qa)), isTrue);
      for (var i = 0; i < MindState.identityFailLimit; i++) {
        await attempt(s.identityGateForCall(who: 'x')!, right: false);
      }
      expect(s.identityLockedUntil, isNotNull);
      final open = s.identityGateForCall(who: 'y')!;
      expect(await s.setCallQuiz(IdentityQuiz(_qa.reversed.toList(), ask: 4)), isTrue);
      expect(s.identityLockedUntil, isNull);
      expect((await attempt(open, right: true))['verified'], isFalse, reason: 'ชุดเก่าที่อาจหลุดไปแล้ว');
      expect(s.identityLockedUntil, isNull, reason: 'ไม่นับของชุดเก่า');
      expect(await s.setCallQuiz(IdentityQuiz(_qa.take(2).toList())), isFalse, reason: 'ไม่ครบสามข้อ');
      expect(await s.clearCallQuiz(), isTrue);
      expect(s.callQuizReady, isFalse);
      expect(s.identityGateForCall(who: 'z'), isNull);
    });

    test('🔴 บันทึกสายไม่มีคำตอบที่คนโทรพูด', () async {
      final s = await loaded(() => DateTime(2026, 10, 31, 10));
      s.debugSetCallQuiz(IdentityQuiz(_qa));
      final note = await s.takeCallNote(who: 'คุณเอ', lines: const [
        (fromHer: true, text: 'แมวตัวแรกที่บ้านชื่ออะไรคะ'),
        (fromHer: false, text: 'ส้มโอ หวาน ครับ'),
        (fromHer: false, text: 'ซอย เจ็ดสิบ สาม · blue heron'),
      ]);
      expect(note, isNotNull);
      final text = jsonEncode([for (final l in note!.lines) l.text]);
      for (final a in ['ส้มโอ', 'เจ็ดสิบ', 'blue heron', 'Blue Heron']) {
        expect(text, isNot(contains(a)));
      }
      expect(text, contains('[answer]'));
      expect(s.scrubCallCode('ครูมาลัยทอง ใจดีมาก'), '[answer] ใจดีมาก');
      expect(s.callAnswersForReport, containsAll(['ส้มโอหวาน', 'Blue Heron']));
    });

    test('ผ่านแล้วเจ้าของได้แจ้งเตือน (ใคร) และความจำเรื่องเจ้าของเปิดให้สายนี้ · ไม่มีคำตอบในแจ้งเตือน', () async {
      final s = await loaded(() => DateTime(2026, 10, 31, 10));
      s.debugSetCallQuiz(IdentityQuiz(_qa));
      final owner = s.ownerGateForCall(who: 'คุณเอ')!;
      final g = s.identityGateForCall(who: 'คุณเอ', unlocks: owner)!;
      expect(owner.open, isFalse);
      expect((await attempt(g, right: true))['verified'], isTrue);
      expect(owner.open, isTrue);
      await Future<void>.delayed(Duration.zero);
      final n = calls.where((c) => c.method == 'notifyCallNote').single;
      expect('${(n.arguments as Map)['title']}', contains('คุณเอ'));
      for (final q in _qa) {
        expect(jsonEncode(n.arguments), isNot(contains(q.answer)));
      }
    });
  });
}
