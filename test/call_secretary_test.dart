/// รับสายแบบเลขาคนจริง — "น้องมาย"
///
/// ที่มา: เจ้าของ — "ทำให้พร้อม เหมือนคนมากขึ้นที่สุด บอกว่าตัวเองเป็นเลขา ชื่อน้องมาย
/// ให้คุยหรือสั่งไว้ได้ค่ะ มีการรับเหมือนคน"
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/phone/call_tags.dart';
import 'package:videogirl/phone/realtime_call.dart';
import 'package:videogirl/state/mind_state.dart';

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('น้องมาย เลขาของเจ้าของเบอร์', () {
    test('คำทักบอกว่าเป็นเลขาชื่อน้องมาย และคุยหรือฝากเรื่องไว้ได้', () async {
      final s = MindState();
      addTearDown(s.dispose);
      await s.load();
      final g = s.callGreeting();
      expect(g, contains('น้องมาย'));
      expect(g, contains('เลขา'));
      expect(g, contains('ฝากเรื่อง'));
    });

    test('ในสายเธอชื่อน้องมาย แม้เจ้าของจะตั้งชื่อเธอในแอปเป็นอื่น · ในแชทยังเป็นชื่อเดิม', () async {
      final s = MindState();
      addTearDown(s.dispose);
      await s.load();
      final call = s.callPrompt();
      expect(call, contains('"น้องมาย"'));
      expect(call, contains('เลขา'));
    });

    test('สอนวิธีคุยโทรศัพท์แบบคน: สั้น · คำรับ · ถามทีละเรื่อง · ทวนเบอร์ · บอกความจริงถ้าถูกถามว่าเป็น AI', () async {
      final s = MindState();
      addTearDown(s.dispose);
      await s.load();
      final p = s.callPrompt();
      for (final want in ['ทีละสั้น ๆ', 'อ๋อ ค่ะ', 'ถามทีละเรื่อง', 'ทวนชื่อ เบอร์', 'เลขา AI', 'กล่าวลา']) {
        expect(p, contains(want), reason: 'ขาด: $want');
      }
    });

    test('🔴 ทางเดิมใช้แท็ก · คุยสดใช้เครื่องมือ (แท็กในโหมดสดจะถูกอ่านออกเสียง)', () async {
      final s = MindState();
      addTearDown(s.dispose);
      await s.load();
      expect(s.callPrompt(), contains('[[วางสาย]]'));
      expect(s.callPrompt(), isNot(contains('end_call')));
      final live = s.callPrompt(live: true);
      expect(live, contains('end_call'));
      expect(live, contains('alert_owner'));
      expect(live, isNot(contains('[[')));
    });

    test('🔴 prompt สายยังไม่มีข้อมูลส่วนตัวของเจ้าของ ทั้งสองโหมด', () async {
      final s = MindState();
      addTearDown(s.dispose);
      await s.load();
      s.setOwnerProfile('บ้านเลขที่ 99/12 เบอร์ 0899999999');
      expect(s.callPrompt(), isNot(contains('99/12')));
      expect(s.callPrompt(live: true), isNot(contains('0899999999')));
    });
  });

  group('แท็กท้ายคำตอบ (ทางเดิม)', () {
    test('วางสาย · ด่วน · ตัดออกก่อนพูด', () {
      final a = CallTags.parse('ขอบคุณที่โทรมานะคะ สวัสดีค่ะ [[วางสาย]]');
      expect(a.text, 'ขอบคุณที่โทรมานะคะ สวัสดีค่ะ');
      expect(a.hangUp, isTrue);
      expect(a.urgent, isNull);

      final b = CallTags.parse('น้องมายแจ้งเจ้าของให้แล้วนะคะ [[ด่วน: คุณแม่เข้าโรงพยาบาล]]');
      expect(b.text, 'น้องมายแจ้งเจ้าของให้แล้วนะคะ');
      expect(b.hangUp, isFalse);
      expect(b.urgent, 'คุณแม่เข้าโรงพยาบาล');
    });

    test('แท็กที่โมเดลแต่งเองก็ไม่ถูกอ่านออกเสียง', () {
      expect(CallTags.parse('ได้เลยค่ะ [[note: x]]').text, 'ได้เลยค่ะ');
      expect(CallTags.parse('ปกติค่ะ').hangUp, isFalse);
    });
  });

  group('เครื่องมือของคุยสด', () {
    late _Socket socket;
    late RealtimeCall rt;

    setUp(() async {
      socket = _Socket();
      rt = RealtimeCall(apiKey: 'k', instructions: 'i', greeting: 'g', connect: (_, _) async => socket);
      await rt.start();
    });

    tearDown(() => rt.close());

    test('ประกาศ end_call กับ alert_owner ในเซสชัน', () {
      final tools = ((socket.sent.first['session'] as Map)['tools'] as List).cast<Map>();
      expect(tools.map((t) => t['name']), containsAll(['end_call', 'alert_owner']));
    });

    test('เธอเรียก end_call = ผู้เรียกได้สัญญาณวางสาย', () async {
      var hung = 0;
      rt.onEndCall = () => hung++;
      socket.push({
        'type': 'response.output_item.done',
        'item': {'type': 'function_call', 'name': 'end_call', 'call_id': 'c1', 'arguments': '{}'},
      });
      await Future<void>.delayed(Duration.zero);
      expect(hung, 1);
    });

    test('🔴 alert_owner แจ้งครั้งเดียวต่อสาย แล้วให้เธอพูดต่อ', () async {
      final reasons = <String>[];
      rt.onAlertOwner = reasons.add;
      for (final id in ['c1', 'c2']) {
        socket.push({
          'type': 'response.output_item.done',
          'item': {
            'type': 'function_call',
            'name': 'alert_owner',
            'call_id': id,
            'arguments': jsonEncode({'reason': 'คุณแม่เข้าโรงพยาบาล'}),
          },
        });
      }
      await Future<void>.delayed(Duration.zero);
      expect(reasons, ['คุณแม่เข้าโรงพยาบาล'], reason: 'คู่สายพูดว่าด่วนซ้ำ ๆ ต้องไม่กลายเป็นแจ้งเตือนรัว');
      expect(socket.sent.where((e) => e['type'] == 'conversation.item.create'), hasLength(2),
          reason: 'ตอบผลให้โมเดลทุกครั้ง ไม่งั้นเธอค้างรอ');
      expect(socket.sent.last['type'], 'response.create');
    });
  });

  test('คุยสดใช้ prompt แบบเครื่องมือ', () async {
    final s = MindState();
    addTearDown(s.dispose);
    await s.load();
    s.setBrain(BrainProvider.openai);
    await s.setOpenAiKey('sk-test-key-for-unit-tests');
    final rt = s.openRealtimeCall();
    expect(rt.instructions, contains('end_call'));
    expect(rt.instructions, isNot(contains('[[')));
  });
}
