/// เชื่อมสมอง BrainX แล้วใช้งานจริง — กู้คืนเอง · ค้นตอนตอบ · ไม่เขียนทับของเดิม
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/brainx/brainx_cloud.dart';
import 'package:videogirl/brainx/brainx_link.dart';
import 'package:videogirl/memory/mind_memory.dart';
import 'package:videogirl/state/mind_state.dart';

class _Brain extends OpenAiClient {
  final seen = <List<Turn>>[];
  @override
  bool get usable => true;
  @override
  void close() {}
  @override
  Future<String> reply({required String system, required List<Turn> history, String? model}) async {
    seen.add(List.of(history));
    return 'จำได้ค่ะ วันพฤหัสนี้';
  }
}

http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('🔴 ลงแอปใหม่ → เชื่อมด้วยบัญชี → ความจำเดิมกลับมา และคำตอบรู้เรื่องที่คุยบนคอม', () async {
    final notes = <String, String>{
      MindPaths.phoneMemory: BrainXLink.renderMemory([
        MemoryFact(id: '1', text: 'เจ้าของแพ้กุ้ง', kind: MemoryKind.fact, createdAt: DateTime(2026)),
        MemoryFact(id: '2', text: 'เจ้าของชอบแมว', kind: MemoryKind.preference, createdAt: DateTime(2026)),
      ]),
    };
    final uploads = <String>[];
    final cloud = MockClient((req) async {
      switch (req.url.path) {
        case '/api/cloud/login':
          return _json({
            'token': 'bxc_t',
            'account': {'licenseType': 'monthly', 'isValid': true, 'noteCount': 10},
          });
        case '/api/cloud/manifest':
          return _json({
            'files': [for (final p in notes.keys) {'path': p}],
          });
        case '/api/cloud/notes/fetch':
          final paths = ((jsonDecode(req.body) as Map)['paths'] as List).cast<String>();
          return _json({
            'files': [
              for (final p in paths)
                if (notes.containsKey(p)) {'path': p, 'content': notes[p]},
            ],
          });
        case '/api/cloud/notes':
          for (final f in (jsonDecode(req.body) as Map)['files'] as List) {
            uploads.add(f['path'] as String);
            notes[f['path'] as String] = f['content'] as String;
          }
          return _json({'written': 1});
        case '/mcp':
          final msg = jsonDecode(req.body) as Map;
          if (msg['method'] == 'initialize') {
            return http.Response('{"jsonrpc":"2.0","id":1,"result":{}}', 200,
                headers: {'mcp-session-id': 's1', 'content-type': 'application/json'});
          }
          if (msg['method'] == 'notifications/initialized') return http.Response('', 202);
          return _json({
            'jsonrpc': '2.0',
            'id': msg['id'],
            'result': {
              'content': [
                {
                  'type': 'text',
                  'text': jsonEncode({
                    'results': [
                      {
                        'title': '2026-10-05 pc',
                        'path': 'Mind/Conversations/2026-10-05 pc.md',
                        'matchContext': 'เจ้าของบอกมายด์บนคอมว่าจะไปเชียงใหม่วันพฤหัส',
                      },
                    ],
                  }),
                },
              ],
            },
          });
      }
      return http.Response('', 404);
    });

    final brain = _Brain();
    final s = MindState(openai: brain);
    addTearDown(s.dispose);
    s.debugBrainX = BrainXLink(
      cloud: BrainXCloud(client: cloud, baseUrl: 'https://serverbrain.test'),
      // หลังบ้านล็อกอินแทน ส่งมาแค่ token (คีย์ไม่ถึงมือถือ)
      xman: MockClient((_) async => _json({
            'linked': true,
            'active': true,
            'token': 'bxc_t',
            'account': {'licenseType': 'monthly', 'isValid': true, 'noteCount': 10},
          })),
      readSecret: (_) async => '',
      writeSecret: (_, _) async => true,
      flushDelay: const Duration(milliseconds: 5),
    );
    await s.load();
    s
      ..setBrain(BrainProvider.openai)
      ..setStoreBaseUrl('https://xman4289.com')
      ..setLicenseKey('FREE-DEVICE');
    await s.setOpenAiKey('sk-test-key-for-unit-tests');

    expect(s.memory.count, 0, reason: 'สมมติฐาน: เพิ่งลงแอปใหม่');
    expect(uploads, isEmpty);
    await s.connectBrainX();

    expect(s.brainx.connected, isTrue);
    expect(s.memory.facts.map((f) => f.text), containsAll(['เจ้าของแพ้กุ้ง', 'เจ้าของชอบแมว']),
        reason: 'ความจำเดิมกลับมาเองตอนเชื่อม');
    expect(s.brainxRestored!.facts, 2);

    await s.send('ไปเชียงใหม่วันไหนนะ');
    final asked = brain.seen.last.last.text;
    expect(asked, contains('BrainX'));
    expect(asked, contains('เชียงใหม่วันพฤหัส'), reason: 'รู้เรื่องที่คุยกับมายด์บนคอม');

    await s.brainx.flush();
    expect(uploads, contains(MindPaths.phoneMemory));
    expect(BrainXLink.parseMemory(notes[MindPaths.phoneMemory]!), hasLength(2),
        reason: '🔴 ไม่เอาความจำว่างไปเขียนทับของเดิม');
  });

  test('ไม่ได้เชื่อม = ไม่ยิงไปคลาวด์เลย และคำตอบไม่มีส่วน BrainX', () async {
    final brain = _Brain();
    final s = MindState(openai: brain);
    addTearDown(s.dispose);
    s.debugBrainX = BrainXLink(
      cloud: BrainXCloud(client: MockClient((_) async => fail('ต้องไม่ยิง'))),
      xman: MockClient((_) async => fail('ต้องไม่ยิง')),
      readSecret: (_) async => '',
      writeSecret: (_, _) async => true,
    );
    await s.load();
    s.setBrain(BrainProvider.openai);
    await s.setOpenAiKey('sk-test-key-for-unit-tests');
    await s.send('สวัสดี');
    expect(brain.seen.single.last.text, isNot(contains('BrainX')));
  });
}
