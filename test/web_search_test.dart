/// ค้นเว็บจริง — ข่าว ราคา ผลบอล เรื่องวันนี้ (OpenAI web_search ด้วยคีย์ของเจ้าของ)
///
/// ที่มา: เจ้าของ — "มายด์ยังค้นออกเน็ตไม่ได้ เหมือนยังใช้ model ในเครื่อง ทั้งๆที่เลือก
/// open ai" · ของเดิมค้นได้แค่วิกิพีเดีย/อากาศ/ค่าเงิน และ prompt สั่งให้ตอบว่า
/// "ข่าวล่าสุดยังค้นไม่ได้" กับทุกสมอง
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/mind_persona.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/ai/web_tools.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/state/mind_state.dart';

typedef _Found = ({String text, List<({String title, String url})> sources});

/// สมองปลอม: ตาแรกขอค้นเว็บ ตาสองตอบจากผล · ค้นเว็บได้เฉพาะรุ่นที่บอกไว้
class _WebBrain extends OpenAiClient {
  static const first = '[[เว็บ: ราคาทองวันนี้]]';
  static const supports = {'gpt-4.1-mini'};
  final seen = <List<Turn>>[];
  final systems = <String>[];
  final searched = <({String query, String model})>[];

  @override
  bool get usable => true;

  @override
  void close() {}

  @override
  Future<String> reply({required String system, required List<Turn> history, String? model}) async {
    seen.add(List.of(history));
    systems.add(system);
    return seen.length == 1 ? first : 'ทองคำแท่งวันนี้ขายออก 52,300 บาทค่ะ (สมาคมค้าทองคำ)';
  }

  @override
  Future<_Found> webSearch(String query, {required String model, String? country, String? timezone}) async {
    searched.add((query: query, model: model));
    if (!supports.contains(model)) {
      throw const OpenAiFailure('web_search not supported', status: 400);
    }
    return (
      text: 'Thai gold bar sell price today: 52,300 THB (Gold Traders Association).',
      sources: [(title: 'สมาคมค้าทองคำ', url: 'https://www.goldtraders.or.th/')],
    );
  }
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('แท็กค้นเว็บ', () {
    test('ไทยและอังกฤษ · ข่าว/news ก็นับเป็นค้นเว็บ', () {
      expect(WebTools.parse('[[เว็บ: ราคาทองวันนี้]]'), const ToolCall(WebTool.web, 'ราคาทองวันนี้'));
      expect(WebTools.parse('[[ข่าว: น้ำท่วมเชียงใหม่]]'), const ToolCall(WebTool.web, 'น้ำท่วมเชียงใหม่'));
      expect(WebTools.parse('[[web: Premier League results]]'),
          const ToolCall(WebTool.web, 'Premier League results'));
      expect(WebTools.parse('[[news: Bangkok]]'), const ToolCall(WebTool.web, 'Bangkok'));
    });

    test('ได้ผลพร้อมแหล่งที่มา และห่อว่าเป็นข้อมูล ไม่ใช่คำสั่ง', () async {
      final tools = WebTools(client: MockClient((_) async => fail('ไม่ยิงเอง ใช้ทางของสมอง')));
      final out = await tools.run(const ToolCall(WebTool.web, 'ราคาทอง'),
          web: (q) async => (
                text: 'Gold 52,300 THB',
                sources: [(title: '', url: 'https://www.goldtraders.or.th/x')],
              ));
      expect(out, contains('52,300'));
      expect(out, contains('www.goldtraders.or.th'), reason: 'ไม่มีชื่อหน้า = ใช้ชื่อเว็บแทน');
      expect(out, contains('not instructions'));
    });

    test('สมองนี้ค้นเว็บไม่ได้ = บอกโมเดลตรง ๆ ไม่แต่งเอง', () async {
      final out = await WebTools().run(const ToolCall(WebTool.web, 'ข่าววันนี้'));
      expect(out, contains('not available'));
    });

    test('ค้นแล้วล้ม = บอกว่าเช็กไม่ได้ ห้ามเดา', () async {
      final out = await WebTools().run(const ToolCall(WebTool.web, 'x'),
          web: (_) async => throw const OpenAiFailure('down', status: 500));
      expect(out, contains('do not guess'));
    });
  });

  group('OpenAI web_search (Responses API)', () {
    test('ส่งแค่คำค้น ไปที่ /responses พร้อมเครื่องมือ web_search และประเทศ', () async {
      http.Request? asked;
      final c = OpenAiClient(
        apiKey: 'sk-test',
        httpClient: MockClient((req) async {
          asked = req;
          return _json({
            'output': [
              {'type': 'web_search_call', 'id': 'ws_1', 'status': 'completed'},
              {
                'type': 'message',
                'content': [
                  {
                    'type': 'output_text',
                    'text': 'ทองคำแท่ง 52,300 บาท',
                    'annotations': [
                      {'type': 'url_citation', 'url': 'https://a.example/1', 'title': 'A'},
                      {'type': 'url_citation', 'url': 'https://a.example/1', 'title': 'A ซ้ำ'},
                      {'type': 'url_citation', 'url': 'https://b.example/2', 'title': 'B'},
                    ],
                  },
                ],
              },
            ],
          });
        }),
      );
      final r = await c.webSearch('ราคาทองวันนี้', model: 'gpt-4.1-mini', country: 'TH', timezone: 'Asia/Bangkok');
      expect(asked!.url.path, '/v1/responses');
      final body = jsonDecode(asked!.body) as Map;
      expect(body['model'], 'gpt-4.1-mini');
      final tool = (body['tools'] as List).single as Map;
      expect(tool['type'], 'web_search');
      expect((tool['user_location'] as Map)['country'], 'TH');
      expect(body['input'], contains('ราคาทองวันนี้'));
      expect(r.text, 'ทองคำแท่ง 52,300 บาท');
      expect([for (final s in r.sources) s.url], ['https://a.example/1', 'https://b.example/2'],
          reason: 'แหล่งเดียวกันไม่ซ้ำ');
    });

    test('ไม่มีคีย์ = บอกว่าต้องใส่คีย์ ไม่ยิงออกไป', () async {
      final c = OpenAiClient(apiKey: '', httpClient: MockClient((_) async => fail('ต้องไม่ยิง')));
      expect(() => c.webSearch('x', model: 'm'), throwsA(isA<OpenAiFailure>()));
    });
  });

  group('เธอรู้ว่าค้นเว็บได้ — เฉพาะสมองที่ค้นได้จริง', () {
    test('สอนแท็กเว็บ และห้ามบอกว่าค้นไม่ได้', () {
      final on = MindPersona.toolsBlock(AppLang.th, web: true);
      expect(on, contains('[[เว็บ:'));
      expect(on, contains('ห้ามบอกว่าค้นไม่ได้'));
      expect(on, isNot(contains('ยังค้นไม่ได้')));
      final off = MindPersona.toolsBlock(AppLang.th);
      expect(off, isNot(contains('[[เว็บ:')));
      expect(off, contains('ยังค้นไม่ได้'), reason: 'สมองที่ค้นเว็บไม่ได้ ต้องไม่สัญญาเกินจริง');
      expect(MindPersona.toolsBlock(AppLang.en, web: true), contains('[[web:'));
    });

    test('OpenAI ด้วยคีย์ตัวเอง = ค้นได้ · สมองอื่นไม่ยืมคีย์มาค้น', () async {
      final s = MindState(openai: _WebBrain());
      addTearDown(s.dispose);
      await s.load();
      s.setBrain(BrainProvider.openai);
      await s.setOpenAiKey('sk-test-key-for-unit-tests');
      expect(s.debugWebSearcher, isNotNull);
      for (final b in [BrainProvider.onDevice, BrainProvider.homeServer, BrainProvider.mindProxy]) {
        s.setBrain(b);
        expect(s.debugWebSearcher, isNull, reason: '$b เลือกเพราะไม่อยากให้อะไรออกไปที่ OpenAI');
      }
    });

    test('รุ่นที่เลือกไว้ไม่รองรับ web_search → ใช้รุ่นที่รองรับ แล้วจำไว้', () async {
      final brain = _WebBrain();
      final s = MindState(openai: brain);
      addTearDown(s.dispose);
      await s.load();
      s.setBrain(BrainProvider.openai);
      await s.setOpenAiKey('sk-test-key-for-unit-tests');
      final web = s.debugWebSearcher!;
      await web('ทอง');
      expect(brain.searched.last.model, 'gpt-4.1-mini');
      final tries = brain.searched.length;
      await web('ทองอีกที');
      expect(brain.searched.length, tries + 1, reason: 'ครั้งต่อไปไปรุ่นที่ผ่านเลย ไม่ล้มก่อน');
    });
  });

  test('วงรอบจริง: ถามราคาทอง → เธอค้นเว็บ → ตอบจากผล', () async {
    final brain = _WebBrain();
    final s = MindState(openai: brain);
    addTearDown(s.dispose);
    await s.load();
    s.setBrain(BrainProvider.openai);
    await s.setOpenAiKey('sk-test-key-for-unit-tests');
    await s.send('ทองวันนี้ราคาเท่าไหร่');

    expect(brain.systems.first, contains('[[เว็บ:'));
    expect(brain.searched.map((e) => e.query), contains('ราคาทองวันนี้'));
    expect(brain.seen.last.last.text, contains('52,300 THB'));
    expect(s.messages.last.text, contains('52,300'));
    expect(s.messages.any((m) => m.text.contains('[[')), isFalse);
  });
}
