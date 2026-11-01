/// หาว่าเจ้าของหมายถึงใครตอนสั่งโทร — ชื่อใกล้เคียง · เบอร์ที่ยังไม่ได้บันทึก · ถามก่อนถ้าไม่ชัด
///
/// ที่มา: เจ้าของ — "ตอนฉันสั่งให้เธอโทรออกหาลูกค้าชื่อบัว เธอบอกไม่มี แทนที่จะค้นรายชื่อที่ใกล้เคียงมา
/// และถามฉันก่อนว่าคนไหน หรือเบอร์โทรเข้ามาล่าสุดที่ไม่ได้บันทึกไว้"
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/phone/call_notes.dart';
import 'package:videogirl/phone/call_target.dart';
import 'package:videogirl/phone/phone_lookup.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';

class _Brain extends OpenAiClient {
  _Brain(this.answer);
  String answer;
  int asked = 0;
  @override
  bool get usable => true;
  @override
  void close() {}
  @override
  Future<String> reply({required String system, required List<Turn> history, String? model}) async {
    asked++;
    return answer;
  }
}

final _now = DateTime(2026, 11, 1, 15, 0);

Map<String, Object?> _call(String number, DateTime at, {int type = 1, String? name}) => {
      'id': at.millisecondsSinceEpoch,
      'at': at.millisecondsSinceEpoch,
      'type': type,
      'number': number,
      'name': name,
      'seconds': 0,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late Map<String, Object? Function(MethodCall)> native;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    native = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kSystemChannel, (c) async {
      calls.add(c);
      return native[c.method]?.call(c);
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(kSystemChannel, null));

  group('เทียบชื่อ', () {
    test('ตัดวรรณยุกต์และตัวการันต์ · บัวร์ = บัว · มิ้นท์ = มิน', () {
      expect(CallNameMatch.norm('บัวร์'), CallNameMatch.norm('บัว'));
      expect(CallNameMatch.norm('มิ้นท์'), 'มิน');
      expect(CallNameMatch.norm('คุณ แม่'), 'คุณแม');
    });

    test('ตัดคำนำหน้าที่เธอพูดติดมา · "ลูกค้าบัว" "คุณบัว (ลูกค้า)" = บัว', () {
      expect(CallNameMatch.variants('ลูกค้าบัว'), contains('บัว'));
      expect(CallNameMatch.variants('คุณบัว (ลูกค้า)').first, 'บัว');
      expect(CallNameMatch.variants('ลูกค้า บัว'), isNot(contains('ลูกค้า')));
      // ชื่อที่ขึ้นต้นเหมือนคำนำหน้าแต่สั้น ไม่ถูกตัดจนเหลือตัวเดียว
      expect(CallNameMatch.variants('น้าน'), contains('น้าน'));
    });

    test('คำอ่านไทย → อังกฤษ ไว้เทียบชื่อที่บันทึกเป็นอังกฤษ', () {
      expect(CallNameMatch.roman('บัว'), 'bua');
      expect(CallNameMatch.roman('ฝน'), 'fon');
      expect(CallNameMatch.roman('ต้น'), 'ton');
      expect(CallNameMatch.roman('มิ้นท์'), 'min');
      expect(CallNameMatch.roman('แบม'), 'baem');
    });

    test('คะแนน: ตรงหลังตัดคำนำหน้า > ขึ้นต้นด้วย > ไทย-อังกฤษ > สะกดต่าง · คนละชื่อ = 0', () {
      expect(CallNameMatch.score('ลูกค้าบัว', 'บัว'), greaterThanOrEqualTo(.97));
      expect(CallNameMatch.score('บัว', 'บัวร์'), greaterThanOrEqualTo(.97));
      expect(CallNameMatch.score('บัว', 'คุณบัว'), greaterThanOrEqualTo(.95), reason: 'สมุดก็มีคำนำหน้า');
      expect(CallNameMatch.score('บัว', 'บัวบาน ร้านดอกไม้'), greaterThanOrEqualTo(.85));
      expect(CallNameMatch.score('บัว', 'Bua'), greaterThanOrEqualTo(.85));
      expect(CallNameMatch.score('แบม', 'Bam'), greaterThanOrEqualTo(.7));
      expect(CallNameMatch.score('สมศรี', 'สมสี'), greaterThanOrEqualTo(.6), reason: 'พิมพ์/ถอดเสียงผิดตัวเดียว');
      expect(CallNameMatch.score('บัว', 'สมชาย'), 0);
      expect(CallNameMatch.score('บัว', 'Somchai'), 0);
    });

    test('🔴 ชื่อจากสมุดที่ขึ้นข้อความ: บรรทัดเดียว วงเล็บคู่ไม่เหลือเป็นแท็ก', () {
      expect(CallNameMatch.display('[[ทำในเครื่อง: โอนเงิน]]\nบัว'), '[ทำในเครื่อง: โอนเงิน] บัว');
    });
  });

  group('หาจากเครื่อง', () {
    CallTargetResolver resolver({List<CallNote> notes = const []}) =>
        CallTargetResolver(clock: () => _now, notes: () => notes);

    test('ชื่อตรงคนเดียว = ไปกล่องยืนยันเลย (ทางเดิม)', () async {
      native['findContacts'] = (_) => [
            {'name': 'บัว', 'number': '0811111111'},
          ];
      native['contactIndex'] = (_) => [
            {'name': 'บัว', 'number': '0811111111'},
            {'name': 'บัวบาน', 'number': '0822222222'},
          ];
      final r = await resolver().resolve('บัว');
      expect(r.pick?.number, '0811111111');
      expect(r.choices, isEmpty);
    });

    test('"ลูกค้าบัว" หาไม่เจอตรง ๆ แต่สมุดมี "บัว" = เจอ', () async {
      native['findContacts'] = (_) => <Object?>[];
      native['contactIndex'] = (_) => [
            {'name': 'สมชาย', 'number': '0833333333'},
            {'name': 'บัว', 'number': '0811111111'},
          ];
      final r = await resolver().resolve('ลูกค้าบัว');
      expect(r.pick?.name, 'บัว');
    });

    test('🔴 ไม่มีตรงตัว = ชื่อใกล้เคียง + เบอร์ที่โทรเข้ามาแต่ยังไม่ได้บันทึก ให้เจ้าของเลือก', () async {
      native['findContacts'] = (_) => <Object?>[];
      native['contactIndex'] = (_) => [
            {'name': 'บัวบาน', 'number': '0822222222'},
            {'name': 'Bua Flower', 'number': '0844444444'},
            {'name': 'สมชาย', 'number': '0833333333'},
          ];
      native['recentCalls'] = (_) => [
            _call('086-123-4567', _now.subtract(const Duration(hours: 20)), type: 3),
            _call('0861234567', _now.subtract(const Duration(days: 2))),
            _call('0833333333', _now.subtract(const Duration(hours: 1)), name: 'สมชาย'),
            _call('0899999999', _now.subtract(const Duration(days: 30)), type: 3),
            _call('0877777777', _now.subtract(const Duration(hours: 2)), type: 2),
          ];
      final r = await resolver().resolve('บัว');
      expect(r.pick, isNull, reason: 'สองคนใกล้พอกัน ต้องถาม');
      final names = r.choices.map((c) => c.name).toList();
      expect(names, containsAll(['บัวบาน', 'Bua Flower']));
      expect(names, isNot(contains('สมชาย')));
      final unsaved = r.choices.where((c) => c.unsaved).toList();
      expect(unsaved, hasLength(1), reason: 'เบอร์เดียวกันสองสายนับครั้งเดียว · เก่ากว่า 14 วัน/โทรออก ไม่นับ');
      expect(unsaved.single.calls, 2);
      expect(unsaved.single.missed, isTrue, reason: 'สายล่าสุดไม่ได้รับ');
      expect(unsaved.single.tail, '4567');
      expect(r.anyContact, isTrue);
    });

    test('ไม่มีในสมุดเลย = เสนอเบอร์ที่โทรเข้ามาแต่ยังไม่ได้บันทึก', () async {
      native['findContacts'] = (_) => <Object?>[];
      native['contactIndex'] = (_) => [
            {'name': 'สมชาย', 'number': '0833333333'},
          ];
      native['recentCalls'] = (_) => [_call('0861234567', _now.subtract(const Duration(hours: 3)))];
      final r = await resolver().resolve('บัว');
      expect(r.pick, isNull);
      expect(r.choices.single.number, '0861234567');
      expect(r.anyContact, isFalse);
    });

    test('🔴 คนโทรมาบอกชื่อนี้ไว้ในสายที่เธอรับ = ขึ้นก่อน และไม่เลือกคนในสมุดเงียบ ๆ', () async {
      native['findContacts'] = (_) => [
            {'name': 'บัว', 'number': '0811111111'},
          ];
      native['contactIndex'] = (_) => [
            {'name': 'บัว', 'number': '0811111111'},
          ];
      native['recentCalls'] = (_) => [
            _call('0869999999', _now.subtract(const Duration(hours: 5))),
            _call('0861234567', _now.subtract(const Duration(hours: 20))),
          ];
      final note = CallNote(
        id: 'n1',
        at: _now.subtract(const Duration(hours: 20)),
        who: '0861234567',
        summary: 'ลูกค้าโทรมาถามเรื่องส่งของ',
        lines: const [(fromHer: false, text: 'สวัสดีค่ะ บัวนะคะ ลูกค้าร้านเสื้อ')],
      );
      final r = await resolver(notes: [note]).resolve('ลูกค้าบัว');
      expect(r.pick, isNull);
      final unsaved = r.choices.where((c) => c.unsaved).toList();
      expect(unsaved.first.number, '0861234567');
      expect(unsaved.first.saidName, isTrue);
    });

    test('ไม่เจออะไรเลย = ไม่มีตัวเลือก (เธอขอเบอร์) · อ่านสมุดไม่ได้ = บอกว่าไม่มีสิทธิ์', () async {
      native['findContacts'] = (_) => <Object?>[];
      native['contactIndex'] = (_) => <Object?>[];
      final r = await resolver().resolve('ร้านป้าแดง');
      expect(r.pick, isNull);
      expect(r.choices, isEmpty);
      expect(r.noContacts, isFalse);

      native.clear();
      final r2 = await resolver().resolve('ร้านป้าแดง');
      expect(r2.noContacts, isTrue);
    });
  });

  group('คำตอบของเจ้าของ (ในเครื่อง)', () {
    final choices = [
      const CallCandidate(number: '0822222222', name: 'บัวบาน', score: .9),
      const CallCandidate(number: '0844444444', name: 'Bua Flower', score: .86),
      CallCandidate(number: '086-123-4567', at: _now.subtract(const Duration(hours: 20)), missed: true, calls: 2),
    ];

    test('ลำดับ · ชื่อ · เลขท้าย · คำบอกลักษณะ', () {
      expect(CallReply.stepConfirm('ทำเลยค่ะ'), isTrue);
      expect(CallReply.stepConfirm('ส่งได้เลย'), isTrue);
      expect(CallReply.stepConfirm('ไม่ต้องค่ะ'), isFalse);
      expect(CallReply.stepConfirm('ใช่ค่ะ'), isNull, reason: 'เธออาจถามเรื่องอื่นอยู่');
      expect(CallReply.stepConfirm('โอเค'), isNull);
      expect(CallReply.stepConfirm('ได้'), isNull);
      expect(CallReply.choice('คนที่สองค่ะ', choices), 1);
      expect(CallReply.choice('อันแรก', choices), 0);
      expect(CallReply.choice('เบอร์ 3', choices), 2);
      expect(CallReply.choice('๓', choices), 2);
      expect(CallReply.choice('อันสุดท้าย', choices), 2);
      expect(CallReply.choice('บัวบานค่ะ', choices), 0);
      expect(CallReply.choice('Bua Flower', choices), 1);
      expect(CallReply.choice('ลงท้าย 4567', choices), 2);
      expect(CallReply.choice('086 123 4567', choices), 2);
      expect(CallReply.choice('เบอร์ที่โทรมาเมื่อวาน', choices), 2);
      expect(CallReply.choice('second one', choices), 1);
    });

    test('ไม่ใช่ทั้งหมด = ยกเลิก · เรื่องอื่น / เบอร์ใหม่ = ไม่ตัดสิน (ให้สมองคิด)', () {
      expect(CallReply.choice('ไม่ใช่ทั้งหมด', choices), CallReply.cancel);
      expect(CallReply.choice('ไม่โทรแล้ว', choices), CallReply.cancel);
      expect(CallReply.choice('none', choices), CallReply.cancel);
      expect(CallReply.choice('อืม เดี๋ยวนะ ขอคิดก่อน', choices), isNull);
      expect(CallReply.choice('โทรหา 0899999999 แทน', choices), isNull);
      expect(CallReply.choice('9', choices), isNull, reason: 'ไม่มีลำดับที่ 9');
    });

    test('ตัวเลือกเดียว: "ใช่" = คนนั้น · "ไม่ใช่" = ยกเลิก', () {
      expect(CallReply.choice('ใช่ค่ะ', [choices.first]), 0);
      expect(CallReply.choice('ไม่ใช่', [choices.first]), CallReply.cancel);
    });

    test('🔴 ยืนยันโทรด้วยเสียง: ทั้งประโยคต้องเป็นคำตอบ', () {
      // เจ้าของ: "เธอให้ยืนยันซ้ำๆ ไม่โทรให้สักที" · พูดธรรมชาติแบบนี้เคยตกหมด
      for (final s in ['ใช่ โทรเลย', 'โทรเลยมายด์', 'โทรออกเลย', 'ตกลงโทรเลย', 'โอเค โทรได้เลยค่ะ', 'โทรไปเลยครับ', 'ใช่แล้วโทรเลย']) {
        expect(CallReply.confirm(s), isTrue, reason: s);
        expect(CallReply.saysCall(s), isTrue, reason: s);
      }
      expect(CallReply.confirm('โทรหาบัวเลย', names: ['บัว']), isTrue);
      expect(CallReply.saysCall('โทรหาบัวเลย', names: ['บัว']), isTrue);
      expect(CallReply.confirm('โทรหาบัวเลย'), isNull, reason: 'ไม่ใช่คนในกล่อง = อาจเป็นสายใหม่');
      // 🔴 มีคำนอกเหนือจากคำตอบ = ไม่ใช่คำตอบ
      for (final s in ['โทรไปแล้ว', 'โทรแล้ว', 'ได้ยินไหม', 'โทรไหม', 'ไม่รู้สิ', 'โทรหาแม่ด้วย', 'ยังไม่ได้โทร', 'ตอนนี้ไม่ได้']) {
        expect(CallReply.confirm(s), isNull, reason: s);
      }
      for (final s in ['ไม่โทรแล้ว', 'อย่าเพิ่งโทร', 'พอแล้ว', 'ไม่เอาแล้วค่ะ', 'ยกเลิกเลย']) {
        expect(CallReply.confirm(s), isFalse, reason: s);
      }
      expect(CallReply.confirm('ไม่เอาแบบนี้ แก้ก่อน'), isNull, reason: 'ขอแก้ = ให้เธอแก้ ไม่ใช่ยกเลิก');

      expect(CallReply.asksToDial('จะโทรหาบัวแจ้งว่าเลื่อนนัดเป็นบ่ายสอง โทรเลยไหมคะ'), isTrue);
      expect(CallReply.asksToDial('โทรเลยมั้ยคะ'), isTrue);
      expect(CallReply.asksToDial('Shall I? Call now?'), isTrue);
      expect(CallReply.asksToDial('ตอนโทรให้บอกเรื่องราคาด้วยไหมคะ'), isFalse);
      expect(CallReply.asksToDial('บอกเขาว่าบ่ายสองใช่ไหมคะ'), isFalse);
      expect(CallReply.asksToDial('โทรเลยไหมคะ เอ๊ะ อีกอย่าง จะให้แจ้งราคาที่คุยกันไว้เมื่อวานนี้ด้วยหรือเปล่า ถ้าใช่ก็บอกมานะคะ มายด์จะเขียนลงบท'), isFalse,
          reason: 'คำถามสุดท้ายไม่ใช่เรื่องกดโทร');

      expect(CallReply.confirm('โทรเลยค่ะ'), isTrue);
      expect(CallReply.confirm('โอเค'), isTrue);
      expect(CallReply.confirm('Call now'), isTrue);
      expect(CallReply.confirm('ยกเลิก'), isFalse);
      expect(CallReply.confirm('ไม่ต้องโทรครับ'), isFalse);
      expect(CallReply.confirm('ได้ยินไหม'), isNull);
      expect(CallReply.confirm('ไม่รู้สิ'), isNull);
      expect(CallReply.confirm('โทรหาแม่ด้วย'), isNull);
    });
  });

  group('ในแชท', () {
    Future<(MindState, _Brain)> chatWith(String answer) async {
      final brain = _Brain(answer);
      final s = MindState(openai: brain);
      addTearDown(s.dispose);
      await s.load();
      s.setBrain(BrainProvider.openai);
      await s.setOpenAiKey('sk-test-key-for-unit-tests');
      s.debugCallTargets = CallTargetResolver(clock: () => DateTime.now());
      return (s, brain);
    }

    void phoneWithBua() {
      native['findContacts'] = (_) => <Object?>[];
      native['contactIndex'] = (_) => [
            {'name': 'บัวบาน', 'number': '0822222222'},
            {'name': 'Bua Flower', 'number': '0844444444'},
          ];
      native['recentCalls'] = (_) => [_call('0861234567', DateTime.now().subtract(const Duration(hours: 2)), type: 3)];
    }

    test('🔴 ไม่ชัด = เธอถามว่าคนไหน (แทน "ไม่มี") · ตอบ "คนที่สาม" = กล่องยืนยัน · "โทรเลย" = โทร', () async {
      phoneWithBua();
      final (s, brain) = await chatWith('ได้ค่ะ จะโทรให้นะคะ [[โทร: ลูกค้าบัว | ถามว่าได้รับของหรือยัง]]');
      await s.send('โทรหาลูกค้าชื่อบัวถามว่าได้รับของหรือยัง');
      expect(s.pendingCall, isNull);
      expect(s.callChoice?.choices, hasLength(3));
      final asked = s.messages.last.text;
      expect(asked, contains('บัวบาน'));
      expect(asked, contains('0861234567'));
      expect(asked, isNot(contains('[[')));
      expect(brain.asked, 1);

      await s.send('คนที่สามค่ะ');
      await Future<void>.delayed(Duration.zero);
      expect(brain.asked, 1, reason: 'ตอบในเครื่อง ไม่ต้องถามสมอง');
      expect(s.callChoice, isNull);
      expect(s.pendingCall?.number, '0861234567');
      expect(s.pendingCall?.task, 'ถามว่าได้รับของหรือยัง');
      expect(calls.where((c) => c.method == 'mindPlaceCall'), isEmpty, reason: 'ยังไม่ยืนยัน ห้ามโทร');

      await s.send('โทรเลย');
      final place = calls.singleWhere((c) => c.method == 'mindPlaceCall');
      expect((place.arguments as Map)['number'], '0861234567');
      expect(s.pendingCall, isNull);
      expect(brain.asked, 1);
    });

    test('"ไม่ใช่ทั้งหมด" = ไม่โทร · กล่องยืนยันแล้วตอบ "ยกเลิก" = ไม่โทร', () async {
      phoneWithBua();
      final (s, _) = await chatWith('ได้ค่ะ [[โทร: บัว | ถามเรื่องของ]]');
      await s.send('โทรหาบัว');
      await s.send('ไม่ใช่ทั้งหมด');
      expect(s.callChoice, isNull);
      expect(s.pendingCall, isNull);

      await s.send('โทรหาบัว');
      await s.send('บัวบาน');
      await Future<void>.delayed(Duration.zero);
      expect(s.pendingCall?.name, 'บัวบาน');
      await s.send('ยกเลิก');
      expect(s.pendingCall, isNull);
      expect(calls.where((c) => c.method == 'mindPlaceCall'), isEmpty);
    });

    test('เธอเขียนแท็กด้วยเลขท้ายจากรายการ = คนในรายการ ไม่ใช่โทรเลขสี่ตัว', () async {
      phoneWithBua();
      final (s, brain) = await chatWith('ได้ค่ะ [[โทร: บัว | ถามเรื่องของ]]');
      await s.send('โทรหาบัว');
      expect(s.callChoice, isNotNull);
      // เจ้าของตอบแบบที่ตัวตัดสินในเครื่องไม่เข้าใจ → สมองเขียนแท็กด้วยเลขท้าย
      brain.answer = 'ได้ค่ะ [[โทร: 4567 | ถามเรื่องของ]]';
      await s.send('เอาอันที่ลงท้ายสี่ห้าหกเจ็ดนั่นแหละ');
      await Future<void>.delayed(Duration.zero);
      expect(s.pendingCall?.number, '0861234567');
    });

    test('ผลค้นสมุดที่ไม่เจอ แนบชื่อใกล้เคียงและเบอร์ที่ยังไม่ได้บันทึก', () async {
      phoneWithBua();
      native['searchContacts'] = (_) => {'total': 3, 'items': <Object?>[]};
      final l = PhoneLookup(targets: CallTargetResolver(clock: () => DateTime.now()));
      final out = await l.run(const PhoneLookupCall(PhoneLookupKind.contacts, 'บัว'));
      expect(out, contains('close name: บัวบาน'));
      expect(out, contains('not saved: 0861234567'));
      expect(out, contains('ask which one'));
    });
  });
}
