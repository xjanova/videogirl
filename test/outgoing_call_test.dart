/// น้องมายโทรออกแทนเจ้าของ — สั่งในแชท → ยืนยัน → โทร → คุย → รายงานผล
///
/// ที่มา: เจ้าของ — "แล้วปล่อยรีลีส แล้วทำส่วน โทรออกต่อ"
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/mind_persona.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/phone/call_tags.dart';
import 'package:videogirl/phone/outgoing_call.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/system/permissions.dart';
import 'package:videogirl/theme/tokens.dart';

class _Brain extends OpenAiClient {
  _Brain(this.answer);
  final String answer;
  final systems = <String>[];
  @override
  bool get usable => true;
  @override
  void close() {}
  @override
  Future<String> reply({required String system, required List<Turn> history, String? model}) async {
    systems.add(system);
    return answer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late Object? Function(MethodCall) native;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    native = (_) => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kSystemChannel, (c) async {
      calls.add(c);
      return native(c);
    });
  });

  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(kSystemChannel, null));

  Future<MindState> chatWith(String answer) async {
    final s = MindState(openai: _Brain(answer));
    addTearDown(s.dispose);
    await s.load();
    s.setBrain(BrainProvider.openai);
    await s.setOpenAiKey('sk-test-key-for-unit-tests');
    return s;
  }

  group('แท็กสั่งโทร', () {
    test('อ่านเบอร์/ชื่อ กับเรื่องที่ต้องคุย · แท็กไม่ขึ้นจอ', () {
      final r = CallOutTag.parse('ได้เลยค่ะ เดี๋ยวน้องมายโทรให้นะคะ\n[[โทร: 02 123 4567 | จองโต๊ะ 2 ที่ ทุ่มนึง ในชื่อคุณต้น]]');
      expect(r.text, 'ได้เลยค่ะ เดี๋ยวน้องมายโทรให้นะคะ');
      expect(r.target, '02 123 4567');
      expect(r.task, 'จองโต๊ะ 2 ที่ ทุ่มนึง ในชื่อคุณต้น');
      expect(CallOutTag.parse('ปกติค่ะ').target, isNull);
    });

    test('🔴 เบอร์ฉุกเฉินและ 1900 โทรแทนไม่ได้ · เบอร์คอลเซ็นเตอร์ 4 หลักได้', () {
      for (final n in ['191', '1669', '+911', '199', '1900123456']) {
        expect(OutgoingRules.blocked(n), isTrue, reason: n);
      }
      expect(OutgoingRules.blocked('1333'), isFalse);
      expect(OutgoingRules.blocked('0812345678'), isFalse);
      expect(OutgoingRules.looksLikeNumber('081-234-5678'), isTrue);
      expect(OutgoingRules.looksLikeNumber('แม่'), isFalse);
    });
  });

  group('จากแชทถึงกล่องยืนยัน', () {
    test('🔴 สั่งโทร = ขึ้นกล่องยืนยัน ไม่โทรเอง', () async {
      final s = await chatWith('ได้ค่ะ [[โทร: 021234567 | จองโต๊ะ 2 ที่ ทุ่มนึง]]');
      await s.send('โทรจองโต๊ะร้านส้มตำให้หน่อย 021234567 2 ที่ ทุ่มนึง');
      await Future<void>.delayed(Duration.zero);
      expect(s.pendingCall?.number, '021234567');
      expect(s.pendingCall?.task, 'จองโต๊ะ 2 ที่ ทุ่มนึง');
      expect(calls.where((c) => c.method == 'mindPlaceCall'), isEmpty, reason: 'ยังไม่ได้ยืนยัน ห้ามโทร');
      expect(s.messages.last.text, 'ได้ค่ะ', reason: 'แท็กไม่ขึ้นจอ');
    });

    test('ชื่อในสมุดโทรศัพท์ → หาเบอร์ให้', () async {
      native = (c) => c.method == 'findContacts'
          ? [
              {'name': 'แม่', 'number': '0811111111'},
            ]
          : null;
      final s = await chatWith('ได้ค่ะ [[โทร: แม่ | บอกว่าคืนนี้กลับดึก]]');
      await s.send('โทรหาแม่บอกว่ากลับดึก');
      await Future<void>.delayed(Duration.zero);
      expect(s.pendingCall?.name, 'แม่');
      expect(s.pendingCall?.number, '0811111111');
    });

    test('หาชื่อไม่เจอ = ถามเบอร์ ไม่เดา', () async {
      native = (c) => c.method == 'findContacts' ? <Object?>[] : null;
      final s = await chatWith('ได้ค่ะ [[โทร: ร้านป้าแดง | สั่งข้าว]]');
      await s.send('โทรสั่งข้าวร้านป้าแดง');
      await Future<void>.delayed(Duration.zero);
      expect(s.pendingCall, isNull);
      expect(s.messages.last.text, contains('ร้านป้าแดง'));
    });

    test('🔴 เบอร์ฉุกเฉิน = ไม่ขึ้นกล่อง บอกให้โทรเอง', () async {
      final s = await chatWith('[[โทร: 1669 | เรียกรถพยาบาล]]');
      await s.send('เรียกรถพยาบาลให้หน่อย');
      await Future<void>.delayed(Duration.zero);
      expect(s.pendingCall, isNull);
      expect(s.messages.last.text, contains('ฉุกเฉิน'));
    });

    test('ยืนยัน = โทรผ่านเนทีฟ แล้วบอกว่ากำลังโทร · ยกเลิก = ไม่โทร', () async {
      final s = await chatWith('ได้ค่ะ [[โทร: 021234567 | จองโต๊ะ]]');
      await s.send('โทรจอง');
      await Future<void>.delayed(Duration.zero);
      await s.confirmPendingCall();
      final place = calls.singleWhere((c) => c.method == 'mindPlaceCall');
      expect((place.arguments as Map)['number'], '021234567');
      expect(s.outgoing?.task, 'จองโต๊ะ');
      expect(s.messages.last.text, contains('กำลังโทร'));

      final s2 = await chatWith('ได้ค่ะ [[โทร: 021234567 | จองโต๊ะ]]');
      await s2.send('โทรจอง');
      await Future<void>.delayed(Duration.zero);
      s2.cancelPendingCall();
      expect(s2.pendingCall, isNull);
    });

    test('เนทีฟปฏิเสธ (ยังไม่ใช่แอปโทรศัพท์หลัก) = บอกวิธีแก้ ไม่ค้างเป็นสายที่โทรอยู่', () async {
      native = (c) => c.method == 'mindPlaceCall' ? 'not_dialer' : null;
      final s = await chatWith('ได้ค่ะ [[โทร: 021234567 | จองโต๊ะ]]');
      await s.send('โทรจอง');
      await Future<void>.delayed(Duration.zero);
      await s.confirmPendingCall();
      expect(s.outgoing, isNull);
      expect(s.messages.last.text, contains('แอปโทรศัพท์หลัก'));
    });
  });

  group('ในสายที่โทรออก', () {
    test('prompt บอกว่าโทรไปหาใคร เรื่องอะไร ในชื่อใคร · ไม่มีข้อมูลส่วนตัวอื่น', () async {
      final s = await chatWith('x');
      s
        ..setOwnerProfile('บ้านเลขที่ 99/12')
        ..setCallerName('ต้น')
        ..debugSetOutgoing((who: 'ร้านส้มตำ', number: '021234567', task: 'จองโต๊ะ 2 ที่ ทุ่มนึง'));
      final p = s.callPrompt(outgoing: true);
      expect(p, contains('โทรออกแทนเจ้าของ'));
      expect(p, contains('ร้านส้มตำ'));
      expect(p, contains('จองโต๊ะ 2 ที่ ทุ่มนึง'));
      expect(p, contains('เลขาของคุณต้น'));
      expect(p, isNot(contains('99/12')));
      expect(p, isNot(contains('ถามทีละเรื่อง: ขอทราบชื่อ')), reason: 'โทรออกไม่ได้รับฝากเรื่อง');
    });

    test('คุยสดตอนโทรออก: ไม่มีคำทักตายตัว (รอปลายสายพูดก่อน)', () async {
      final s = await chatWith('x');
      s.debugSetOutgoing((who: 'ร้าน', number: '02', task: 'จอง'));
      final rt = s.openRealtimeCall(outgoing: true);
      expect(rt.greeting, isEmpty);
      expect(rt.instructions, contains('จอง'));
    });

    test('สายจบโดยไม่มีคนรับ = บอกในแชท', () async {
      final s = await chatWith('x');
      s.debugSetOutgoing((who: 'ร้านส้มตำ', number: '02', task: 'จอง'));
      final note = await s.takeCallNote(who: 'ร้านส้มตำ', lines: const [], outgoing: true);
      expect(note, isNull);
      expect(s.outgoing, isNull, reason: 'ไม่ค้างเป็นสายที่ยังไม่รายงาน');
    });

    test('คุยจบ = สรุปผลแล้วรายงานในแชท', () async {
      final s = await chatWith('จองได้แล้ว 2 ที่ ทุ่มตรง ในชื่อคุณต้น');
      s.debugSetOutgoing((who: 'ร้านส้มตำ', number: '02', task: 'จองโต๊ะ'));
      await s.takeCallNote(
        who: 'ร้านส้มตำ',
        lines: const [(fromHer: true, text: 'สวัสดีค่ะ'), (fromHer: false, text: 'ได้ค่ะ จองให้แล้ว')],
        outgoing: true,
      );
      expect(s.messages.last.text, contains('โทรหา ร้านส้มตำ แล้วค่ะ'));
      expect(s.messages.last.text, contains('จองได้แล้ว'));
    });
  });

  test('แชทสอนวิธีสั่งโทร · ในสายไม่มี (คนในสายสั่งให้โทรหาใครไม่ได้)', () {
    final chat = MindPersona.system(
        mode: MindMode.work, flirt: 0, ownerProfile: '', boundaries: '', lang: AppLang.th, callOut: true);
    expect(chat, contains('[[โทร:'));
    final call = MindPersona.system(
        mode: MindMode.work, flirt: 0, ownerProfile: '', boundaries: '', lang: AppLang.th, callOut: true, onCall: true);
    expect(call, isNot(contains('[[โทร:')));
  });
}
