/// โค้ดลับของเจ้าของ — คนนอกหลอกถามความจำไม่ได้ · คนมีโค้ดฟังได้
///
/// ที่มา: เจ้าของ — "เธออ่านและเรียกใช้ได้ แต่หลอกถามให้พูดไม่ได้ ยกเว้น คนมีโค๊ดลับ"
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('OwnerCode', () {
    test('เว้นวรรค ตัวใหญ่เล็ก เครื่องหมาย เลขไทย และคำอ่านตัวเลข = โค้ดเดียวกัน', () {
      const code = 'ม้าลายสีชมพู 42';
      for (final heard in ['ม้าลาย สีชมพู สี่สอง', 'ม้า-ลาย สี ชมพู ๔๒', 'ม้าลายสีชมพู42.']) {
        expect(OwnerCode.matches(code, heard), isTrue, reason: heard);
      }
      expect(OwnerCode.matches('Pink Zebra 42', 'pink zebra four two'), isTrue);
      expect(OwnerCode.matches(code, 'ม้าลายสีชมพู 43'), isFalse);
      expect(OwnerCode.matches(code, 'ม้าลายสีชมพู'), isFalse, reason: 'ขาดไปส่วนเดียวก็ไม่ผ่าน');
    });

    test('มีคำนำหน้าสั้น ๆ ได้ ("รหัสคือ …") · คำเดายาวเหยียดหลายคำไม่ได้', () {
      const code = 'ม้าลายสีชมพู42';
      expect(OwnerCode.matches(code, 'รหัสคือ ม้าลายสีชมพู42 ค่ะ'), isTrue);
      expect(OwnerCode.matches(code, 'แมวดำ หมาขาว ช้างเทา ม้าลายสีชมพู42 นกแก้ว ปลาทอง'), isFalse);
    });

    test('โค้ดสั้นเกินหกตัวไม่รับ (นับหลังตัดช่องว่าง)', () {
      expect(OwnerCode.acceptable('1 2 3 4'), isFalse);
      expect(OwnerCode.acceptable('ม้าลายสีชมพู'), isTrue);
      expect(OwnerCode.acceptable('pink42'), isTrue);
    });

    test('same: เทียบครบทุกไบต์ · สตริงว่างไม่ผ่าน', () {
      expect(OwnerCode.same('abc', 'abc'), isTrue);
      expect(OwnerCode.same('abc', 'abd'), isFalse);
      expect(OwnerCode.same('abc', 'abcd'), isFalse);
      expect(OwnerCode.same('', ''), isFalse);
    });

    test('🔴 ลบโค้ดออกจากบทสาย · พูดเว้นวรรคหรือพูดเป็นคำก็ถูกลบ', () {
      const code = 'ม้าลายสีชมพู 42';
      expect(OwnerCode.redact('ผมมีรหัสครับ ม้าลาย สีชมพู สี่สอง ครับ', code), 'ผมมีรหัสครับ [code] ครับ');
      expect(OwnerCode.redact('code is Pink Zebra 4 2', 'pink zebra 42'), 'code is [code]');
      expect(OwnerCode.redact('ไม่มีอะไร', code), 'ไม่มีอะไร');
    });
  });

  group('OwnerGate', () {
    test('🔴 ก่อนโค้ดถูก recall_owner ไม่เรียกค้นเลย · ถูกแล้วค้นได้', () async {
      var searched = 0;
      final g = OwnerGate(
        check: (h) async => h == 'right' ? CodeCheck.ok : CodeCheck.wrong,
        recall: (q) async {
          searched++;
          return [(title: 'memory', text: 'เจ้าของชอบกาแฟดำ')];
        },
      );
      final before = await g.lookup('เจ้าของชอบอะไร');
      expect(before['allowed'], isFalse);
      expect(searched, 0, reason: 'ของที่ไม่ได้ค้น หลุดเข้าสายไม่ได้');
      expect((await g.verify('right'))['verified'], isTrue);
      final after = await g.lookup('เจ้าของชอบอะไร');
      expect(after['allowed'], isTrue);
      expect(jsonEncode(after), contains('กาแฟดำ'));
    });

    test('ลองได้สามครั้งต่อสาย · ครั้งที่สามผิด = ไม่ตรวจอีก แจ้งเจ้าของครั้งเดียว', () async {
      var checks = 0;
      final refused = <CodeCheck>[];
      final g = OwnerGate(
        check: (_) async {
          checks++;
          return CodeCheck.wrong;
        },
        recall: (_) async => const [],
        onRefused: refused.add,
      );
      for (var i = 0; i < 5; i++) {
        final r = await g.verify('guess$i');
        expect(r['verified'], isFalse);
        expect(jsonEncode(r), isNot(contains('guess')), reason: 'ไม่ทวนคำที่เดา');
      }
      expect(checks, OwnerGate.maxTries);
      expect(refused, [CodeCheck.wrong]);
    });

    test('ล็อกข้ามสาย = บอกให้ปฏิเสธ ไม่ให้ลองอีก', () async {
      final refused = <CodeCheck>[];
      final g = OwnerGate(check: (_) async => CodeCheck.locked, recall: (_) async => const [], onRefused: refused.add);
      final r = await g.verify('x');
      expect(r['verified'], isFalse);
      expect('${r['note']}', contains('Do not ask for the code again'));
      expect(refused, [CodeCheck.locked]);
    });
  });

  group('เครื่องมือในสาย', () {
    late _Socket socket;
    late RealtimeCall rt;

    Future<void> open({OwnerGate? gate}) async {
      socket = _Socket();
      rt = RealtimeCall(apiKey: 'k', instructions: 'i', greeting: '', connect: (_, _) async => socket);
      rt.ownerGate = gate;
      await rt.start();
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
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('ไม่ได้ตั้งโค้ด = ไม่มีเครื่องมือ check_code / recall_owner', () async {
      await open();
      expect(toolNames(), isNot(contains('check_code')));
      expect(toolNames(), isNot(contains('recall_owner')));
    });

    test('มีโค้ด: ขอความจำก่อนบอกโค้ด = ไม่ได้ · บอกถูกแล้วได้', () async {
      await open(
        gate: OwnerGate(
          check: (h) async => OwnerCode.matches('ม้าลายสีชมพู42', h) ? CodeCheck.ok : CodeCheck.wrong,
          recall: (_) async => [(title: 'memory', text: 'เจ้าของไปเชียงใหม่วันศุกร์')],
        ),
      );
      expect(toolNames(), containsAll(['check_code', 'recall_owner']));
      call('c1', 'recall_owner', {'query': 'เจ้าของไปไหน'});
      await settle();
      expect(socket.outputs.last['allowed'], isFalse);
      expect(jsonEncode(socket.outputs.last), isNot(contains('เชียงใหม่')));

      call('c2', 'check_code', {'code': 'ม้าลาย สีชมพู สี่สอง'});
      await settle();
      expect(socket.outputs.last['verified'], isTrue);
      call('c3', 'recall_owner', {'query': 'เจ้าของไปไหน'});
      await settle();
      expect(jsonEncode(socket.outputs.last), contains('เชียงใหม่'));
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

    test('🔴 ตัวโค้ดไม่อยู่ใน prompt ของสาย · กฎโค้ดมีเฉพาะคุยสดที่ตั้งโค้ดแล้ว', () async {
      final s = await loaded(() => DateTime(2026, 10, 31, 10));
      expect(s.callPrompt(live: true), isNot(contains('check_code')));
      s.debugSetCallCode('ม้าลายสีชมพู42');
      for (final p in [s.callPrompt(), s.callPrompt(live: true), s.callPrompt(live: true, outgoing: true)]) {
        expect(p, isNot(contains('ม้าลาย')));
        expect(p, isNot(contains('42')));
      }
      expect(s.callPrompt(live: true), contains('check_code'));
      expect(s.callPrompt(), isNot(contains('check_code')), reason: 'ทางเดิมไม่มีเครื่องมือ');
    });

    test('ผิดห้าครั้งในวันเดียว = ล็อก (โค้ดถูกก็ไม่ผ่าน) · พ้น 24 ชั่วโมงเปิดเอง', () async {
      var now = DateTime(2026, 10, 31, 10);
      final s = await loaded(() => now);
      s.debugSetCallCode('ม้าลายสีชมพู42');
      for (var i = 0; i < MindState.codeFailLimit - 1; i++) {
        expect(await s.checkCallCode('ผิด$i'), CodeCheck.wrong);
      }
      expect(await s.checkCallCode('ผิดอีก'), CodeCheck.locked);
      expect(await s.checkCallCode('ม้าลายสีชมพู42'), CodeCheck.locked);
      expect(s.callCodeLockedUntil, isNotNull);
      now = now.add(const Duration(hours: 25));
      expect(s.callCodeLockedUntil, isNull);
      expect(await s.checkCallCode('ม้าลายสีชมพู42'), CodeCheck.ok);
    });

    test('🔴 บันทึกสายไม่มีโค้ดที่คนโทรพูด', () async {
      final s = await loaded(() => DateTime(2026, 10, 31, 10));
      s.debugSetCallCode('ม้าลายสีชมพู42');
      final note = await s.takeCallNote(who: 'คุณเอ', lines: const [
        (fromHer: true, text: 'สวัสดีค่ะ'),
        (fromHer: false, text: 'ผมมีโค้ดครับ ม้าลาย สีชมพู สี่สอง'),
      ]);
      expect(note, isNotNull);
      expect(jsonEncode([for (final l in note!.lines) l.text]), isNot(contains('ม้าลาย')));
      expect(note.summary, isNot(contains('ม้าลาย')));
    });

    test('ใครบอกโค้ดถูก เจ้าของได้แจ้งเตือน', () async {
      final s = await loaded(() => DateTime(2026, 10, 31, 10));
      s.debugSetCallCode('ม้าลายสีชมพู42');
      final g = s.ownerGateForCall(who: 'คุณเอ')!;
      await g.verify('ม้าลายสีชมพู42');
      await Future<void>.delayed(Duration.zero);
      final n = calls.where((c) => c.method == 'notifyCallNote').single;
      expect('${(n.arguments as Map)['title']}', contains('คุณเอ'));
      expect(jsonEncode(n.arguments), isNot(contains('ม้าลาย')));
    });
  });
}
