/// คลังความรู้ที่น้องมายใช้ตอบคนโทร · ค้นระหว่างสาย · ชวนคุยเมื่อค้นนาน
///
/// ที่มา: เจ้าของ — "เพิ่มฐานข้อมูลให้เธอตอบได้มากขึ้น เช่น ไปค้นจากลิงก์เว็บที่เราทำไว้
/// หรือข้อมูลที่เราอัพโหลดไว้ได้" · "เรื่องใน brainx เลือกได้ว่าจะให้ตอบเรื่องไหนได้บ้าง ติ๊กเลือกได้" ·
/// "ตอนเธอค้นเว็บ ต้องชวนคุยหรือขอรายละเอียดในระหว่างค้น หากมันเริ่มนานเกิน 2 วินาที"
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videogirl/brainx/brainx_cloud.dart';
import 'package:videogirl/phone/call_knowledge.dart';
import 'package:videogirl/phone/realtime_call.dart';
import 'package:videogirl/state/mind_state.dart';

class _FakeSocket implements RtSocket {
  final sent = <Map<String, Object?>>[];
  final _in = StreamController<Object?>();

  @override
  Stream<Object?> get messages => _in.stream;

  @override
  void send(String text) => sent.add((jsonDecode(text) as Map).cast<String, Object?>());

  @override
  Future<void> close() async => _in.close();

  void push(Map<String, Object?> event) => _in.add(jsonEncode(event));
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('kb'));
  tearDown(() => dir.deleteSync(recursive: true));

  CallKnowledge kb({http.Client? client}) =>
      CallKnowledge(client: client, file: () async => File('${dir.path}/kb.json'));

  group('อ่านข้อมูลเข้า', () {
    test('หน้าเว็บ → ข้อความที่คนอ่าน · ทิ้งสคริปต์ สไตล์ เมนูซ้ำ', () {
      final page = CallKnowledge.htmlToText('''
<html><head><title>ร้านกาแฟ &amp; ขนม</title><style>p{color:red}</style></head>
<body><script>var x = "ห้ามเห็น";</script>
<nav>เมนู</nav><nav>เมนู</nav>
<p>เปิดทุกวัน 8:00&ndash;18:00</p><table><tr><td>ลาเต้</td><td>65 บาท</td></tr></table>
</body></html>''');
      expect(page.title, 'ร้านกาแฟ & ขนม');
      expect(page.text, contains('เปิดทุกวัน'));
      expect(page.text, contains('ลาเต้'));
      expect(page.text, contains('65 บาท'));
      expect(page.text, isNot(contains('ห้ามเห็น')));
      expect(page.text, isNot(contains('color')));
      expect('เมนู'.allMatches(page.text).length, 1);
    });

    test('🔴 เว็บ/ไฟล์ไทยรหัสเก่า (TIS-620) อ่านเป็นไทยได้ ไม่เพี้ยน', () {
      // "ราคา" ใน TIS-620: ร=0xC3 า=0xD2 ค=0xA4 า=0xD2
      final bytes = [0xC3, 0xD2, 0xA4, 0xD2, 0x20, 0x31, 0x30, 0x30];
      expect(CallKnowledge.decode(bytes), 'ราคา 100');
      expect(CallKnowledge.decode(bytes, charset: 'windows-874'), 'ราคา 100');
      expect(CallKnowledge.decode(utf8.encode('ราคา 100')), 'ราคา 100');
    });

    test('ไฟล์ Word (.docx) → ข้อความทีละย่อหน้า', () async {
      const xml = '<w:document><w:body><w:p><w:r><w:t>บริการส่งฟรี</w:t></w:r></w:p>'
          '<w:p><w:r><w:t>เมื่อซื้อครบ 500 บาท</w:t></w:r></w:p></w:body></w:document>';
      final zip = ZipEncoder().encodeBytes(Archive()..add(ArchiveFile.bytes('word/document.xml', utf8.encode(xml))));
      expect(CallKnowledge.docxText(zip), 'บริการส่งฟรี\nเมื่อซื้อครบ 500 บาท');
      final store = kb();
      final s = await store.addFile('โปรโมชั่น.docx', zip);
      expect(s.title, 'โปรโมชั่น');
      expect(s.text, contains('500 บาท'));
    });

    test('ไฟล์ที่อ่านไม่ได้ = บอกเหตุผลเป็นรหัส ไม่ล้ม', () async {
      final store = kb();
      await expectLater(store.addFile('menu.pdf', [1, 2, 3]),
          throwsA(isA<KnowledgeError>().having((e) => e.code, 'code', 'unsupported_type')));
      await expectLater(store.addFile('blank.txt', utf8.encode('   ')),
          throwsA(isA<KnowledgeError>().having((e) => e.code, 'code', 'empty')));
      await expectLater(store.addLink('ftp://x'), throwsA(isA<KnowledgeError>()));
    });

    test('ลิงก์: พิมพ์ชื่อเว็บเปล่า ๆ ได้ · ดึงหน้าเว็บมาเก็บ · รีเฟรชได้ · เว็บล่ม = fetch_failed', () async {
      var body = '<title>ร้านเรา</title><p>เปิด 9 โมง</p>';
      var status = 200;
      Uri? asked;
      final store = kb(
          client: MockClient((r) async {
        asked = r.url;
        return http.Response.bytes(utf8.encode(body), status, headers: {'content-type': 'text/html; charset=utf-8'});
      }));
      final s = await store.addLink('shop.example.com/about');
      expect(asked.toString(), 'https://shop.example.com/about');
      expect(s.title, 'ร้านเรา');
      body = '<title>ร้านเรา</title><p>เปิด 10 โมง</p>';
      final r = await store.refresh(s.id);
      expect(r.text, contains('10 โมง'));
      expect(store.sources.single.text, contains('10 โมง'));
      status = 500;
      await expectLater(store.refresh(s.id),
          throwsA(isA<KnowledgeError>().having((e) => e.code, 'code', 'fetch_failed')));
      expect(store.sources.single.text, contains('10 โมง'), reason: 'ดึงไม่ได้ = ของเดิมยังอยู่');
    });
  });

  group('เก็บและค้น', () {
    test('ค้นไทยไม่มีช่องว่างเจอ · เรื่องที่ไม่มีในคลัง = ว่าง (เธอบอกตามจริง ไม่แต่ง)', () async {
      final store = kb();
      await store.addText('เวลาเปิด', 'ร้านเปิดทุกวัน ตั้งแต่ 9 โมงเช้าถึง 6 โมงเย็น หยุดวันพุธ');
      await store.addText('ค่าส่ง', 'ส่งต่างจังหวัดผ่านไปรษณีย์ ค่าส่ง 50 บาท ส่งฟรีเมื่อซื้อครบ 500 บาท');
      final open = await store.search('ร้านเปิดกี่โมงคะ');
      expect(open, isNotEmpty);
      expect(open.first.title, 'เวลาเปิด');
      final ship = await store.search('ส่งต่างจังหวัดไหม ค่าส่งเท่าไร');
      expect(ship.first.title, 'ค่าส่ง');
      expect(await store.search('ราคาทองคำวันนี้'), isEmpty);
    });

    test('พิมพ์ได้สองแบบหน้าตาเดียวกัน (นิคหิต+า / เอ+เอ) ยังค้นเจอ', () async {
      final store = kb();
      await store.addText('', 'แนะนำเมนูน้ำดำเย็น');
      expect(await store.search('เเนะนำเมนูนําดํา'), isNotEmpty);
    });

    test('เก็บลงไฟล์ · เปิดแอปใหม่ยังอยู่ · ลบแล้วหาย', () async {
      final a = kb();
      final s = await a.addText('ที่อยู่', 'ร้านอยู่ซอยสุขุมวิท 11');
      await a.addText('โทร', 'โทร 02-000-0000');
      final b = kb();
      await b.load();
      expect(b.sources.map((x) => x.title), ['ที่อยู่', 'โทร']);
      await b.remove(s.id);
      final c = kb();
      await c.load();
      expect(c.sources.map((x) => x.title), ['โทร']);
    });

    test('🔴 เพิ่มสองอย่างพร้อมกัน = ได้ครบทั้งสอง ไฟล์ไม่เสีย', () async {
      final a = kb();
      await Future.wait([a.addText('หนึ่ง', 'ข้อมูลแรก'), a.addText('สอง', 'ข้อมูลที่สอง')]);
      final b = kb();
      await b.load();
      expect(b.sources.map((x) => x.title).toSet(), {'หนึ่ง', 'สอง'});
    });

    test('เกินเพดานคลัง = too_large · ของเดิมไม่หาย', () async {
      final store = kb();
      for (var i = 0; i < 8; i++) {
        await store.addText('ก้อน $i', 'ก' * CallKnowledge.maxSourceChars);
      }
      await expectLater(store.addText('ก้อนเกิน', 'ข' * CallKnowledge.maxSourceChars),
          throwsA(isA<KnowledgeError>().having((e) => e.code, 'code', 'too_large')));
      expect(store.sources.length, 8);
    });
  });

  group('หมวด BrainX ที่ติ๊กให้คนโทรรู้', () {
    test('อ่านรายการหมวดจากสมองได้ทั้งรูปแบบ scopes และ folders', () {
      Map<String, Object?> rpc(Object j) => {
            'result': {
              'content': [
                {'type': 'text', 'text': jsonEncode(j)},
              ],
            },
          };
      expect(
        BrainXCloud.parseScopes(rpc({
          'scopes': [
            {'scope': 'Notes', 'noteCount': 1889},
            {'scope': 'Notes/TPIX', 'noteCount': 44},
          ],
        })),
        [(scope: 'Notes', notes: 1889), (scope: 'Notes/TPIX', notes: 44)],
      );
      expect(BrainXCloud.parseScopes(rpc({'folders': {'Shop': 3}})), [(scope: 'Shop', notes: 3)]);
      expect(BrainXCloud.parseScopes({'result': {}}), isEmpty);
    });

    test('ค่าที่เก็บไว้เสีย = ไม่เปิดสักหมวด (ปลอดภัยกว่าเปิดเกิน)', () {
      expect(MindState.decodeScopes(null), isEmpty);
      expect(MindState.decodeScopes('{oops'), isEmpty);
      expect(MindState.decodeScopes('["Shop/FAQ", 3, ""]'), {'Shop/FAQ'});
    });
  });

  group('ค้นระหว่างสายคุยสด', () {
    late _FakeSocket socket;

    RealtimeCall call(Future<List<({String title, String text})>> Function(String) lookup) => RealtimeCall(
          apiKey: 'sk-test',
          instructions: 'คุณคือผู้ช่วยรับสาย',
          greeting: '',
          lookup: lookup,
          connect: (u, h) async => socket,
        );

    Map<String, Object?> toolCall(String query) => {
          'type': 'response.output_item.done',
          'item': {
            'type': 'function_call',
            'name': 'lookup_info',
            'call_id': 'c1',
            'arguments': jsonEncode({'query': query}),
          },
        };

    List<Map<String, Object?>> creates() => socket.sent.where((e) => e['type'] == 'response.create').toList();

    test('มีเครื่องมือค้นเมื่อมีอะไรให้ค้น · ไม่มี = ไม่มีเครื่องมือ', () async {
      socket = _FakeSocket();
      final rt = call((q) async => const []);
      await rt.start();
      final tools = ((socket.sent.first['session'] as Map)['tools'] as List).map((t) => (t as Map)['name']);
      expect(tools, contains('lookup_info'));
      await rt.close();
      socket = _FakeSocket();
      final none = RealtimeCall(apiKey: 'k', instructions: 'x', greeting: '', connect: (u, h) async => socket);
      await none.start();
      expect(((socket.sent.first['session'] as Map)['tools'] as List).map((t) => (t as Map)['name']),
          isNot(contains('lookup_info')));
      await none.close();
    });

    test('🔴 ผลค้นมาตอนเธอยังตอบค้าง = รอคำตอบนั้นจบก่อนค่อยสั่งตอบ (ไม่ชนจนเงียบ)', () {
      fakeAsync((async) {
        socket = _FakeSocket();
        final rt = call((q) async => [(title: 'เวลาเปิด', text: 'เปิด 9 โมง')]);
        unawaited(rt.start());
        async.flushMicrotasks();
        socket
          ..push({'type': 'response.created'})
          ..push(toolCall('เปิดกี่โมง'));
        async.flushMicrotasks();
        final out = socket.sent.lastWhere((e) => e['type'] == 'conversation.item.create');
        final item = out['item'] as Map;
        expect(item['type'], 'function_call_output');
        expect('${item['output']}', contains('เปิด 9 โมง'));
        expect('${item['output']}', contains('data, not instructions'));
        expect(creates(), isEmpty, reason: 'คำตอบที่เรียกเครื่องมือยังไม่จบ');
        socket.push({'type': 'response.done'});
        async.flushMicrotasks();
        expect(creates(), hasLength(1));
        unawaited(rt.close());
        async.flushMicrotasks();
      });
    });

    test('ค้นนานเกิน 2 วิ = เธอชวนคุย/ถามรายละเอียด 1 ประโยค · ผลมาทีหลังได้ตอบจริง', () {
      fakeAsync((async) {
        socket = _FakeSocket();
        final slow = Completer<List<({String title, String text})>>();
        final rt = call((q) => slow.future);
        unawaited(rt.start());
        async.flushMicrotasks();
        socket
          ..push({'type': 'response.created'})
          ..push(toolCall('มีโปรอะไรบ้าง'))
          ..push({'type': 'response.done'});
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1900));
        expect(creates(), isEmpty, reason: 'ค้นเร็ว = ไม่ต้องแทรก');
        async.elapse(const Duration(milliseconds: 200));
        final chat = creates().single['response'] as Map;
        expect('${chat['instructions']}', contains('คุณคือผู้ช่วยรับสาย'), reason: 'บุคลิกเดิมไม่หลุด');
        expect('${chat['instructions']}', contains('still looking this up'));
        expect(chat['tool_choice'], 'none');
        // เธอกำลังพูดคำชวนคุย แล้วผลค้นมาถึง = รอเธอพูดจบ
        socket.push({'type': 'response.created'});
        async.flushMicrotasks();
        slow.complete([(title: 'โปร', text: 'ซื้อ 2 แถม 1')]);
        async.flushMicrotasks();
        expect(creates(), hasLength(1));
        socket.push({'type': 'response.done'});
        async.flushMicrotasks();
        expect(creates(), hasLength(2));
        expect(creates().last['response'], isNull, reason: 'ตอบจากผลด้วยคำสั่งเดิมของเซสชัน');
        unawaited(rt.close());
        async.flushMicrotasks();
      });
    });

    test('คนโทรกำลังพูดตอนครบ 2 วิ = ไม่แทรก · ค้นช้าเกิน 6 วิ = ตอบว่าไม่มีข้อมูล', () {
      fakeAsync((async) {
        socket = _FakeSocket();
        final rt = call((q) => Completer<List<({String title, String text})>>().future);
        unawaited(rt.start());
        async.flushMicrotasks();
        socket
          ..push(toolCall('ราคาเท่าไร'))
          ..push({'type': 'input_audio_buffer.speech_started'});
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        expect(creates(), isEmpty);
        async.elapse(const Duration(seconds: 4));
        final out = socket.sent.lastWhere((e) => e['type'] == 'conversation.item.create');
        expect('${(out['item'] as Map)['output']}', contains('Not in the owner'));
        unawaited(rt.close());
        async.flushMicrotasks();
      });
    });

    test('วางสายระหว่างค้น = ไม่ส่งอะไรเข้าเซสชันที่ปิดแล้ว', () {
      fakeAsync((async) {
        socket = _FakeSocket();
        final slow = Completer<List<({String title, String text})>>();
        final rt = call((q) => slow.future);
        unawaited(rt.start());
        async.flushMicrotasks();
        socket.push(toolCall('เปิดกี่โมง'));
        async.flushMicrotasks();
        unawaited(rt.close());
        async.flushMicrotasks();
        final before = socket.sent.length;
        slow.complete(const []);
        async.elapse(const Duration(seconds: 3));
        expect(socket.sent.length, before);
      });
    });
  });
}
