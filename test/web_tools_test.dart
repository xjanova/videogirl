/// เธอหาข้อมูลจากอินเทอร์เน็ตได้ — แท็กขอค้น · แหล่งข้อมูล · วงรอบถาม-ค้น-ตอบ
///
/// ที่มา: เจ้าของบอก "เธอยังไม่ฉลาดในการค้นข้อมูลจากอินเตอร์เน็ตในบางคำถาม
/// ให้เธอตอบได้หาข้อมูลได้ด้วย"
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
import 'package:videogirl/theme/tokens.dart';

/// สมองปลอม: ตาแรกขอค้น ตาสองตอบจากผล · จดว่าเห็นอะไร
class _LookupBrain extends OpenAiClient {
  _LookupBrain(this.first, this.second);
  final String first;
  final String second;
  final seen = <List<Turn>>[];
  final systems = <String>[];

  @override
  bool get usable => true;

  @override
  void close() {}

  @override
  Future<String> reply({required String system, required List<Turn> history, String? model}) async {
    seen.add(List.of(history));
    systems.add(system);
    return seen.length == 1 ? first : second;
  }
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('อ่านแท็กขอค้น', () {
    test('ไทยและอังกฤษ ทุกชนิด', () {
      expect(WebTools.parse('[[ค้นหา: ภูเขาไฟฟูจิ]]'), const ToolCall(WebTool.search, 'ภูเขาไฟฟูจิ'));
      expect(WebTools.parse('ขอเช็กก่อนนะคะ\n[[อากาศ: เชียงใหม่]]'),
          const ToolCall(WebTool.weather, 'เชียงใหม่'));
      expect(WebTools.parse('[[ค่าเงิน: USD THB]]'), const ToolCall(WebTool.fx, 'USD THB'));
      expect(WebTools.parse('[[weather: Bangkok]]'), const ToolCall(WebTool.weather, 'Bangkok'));
      expect(WebTools.parse('[[search：Mount Fuji]]'), const ToolCall(WebTool.search, 'Mount Fuji'));
    });

    test('ตอบปกติ = ไม่ใช่การขอค้น', () {
      expect(WebTools.parse('พรุ่งนี้มีประชุมสิบโมงค่ะ'), isNull);
      expect(WebTools.parse('[[ค้นหา: ]]'), isNull);
    });

    test('แท็กที่หลุดมาในคำตอบสุดท้ายถูกลอกออก (ไม่อ่านวงเล็บออกเสียง)', () {
      expect(WebTools.strip('วันนี้ฝนตกค่ะ [[อากาศ: กรุงเทพ]]'), 'วันนี้ฝนตกค่ะ');
    });

    test('กำลังพิมพ์แท็กอยู่ = หน้าจอไม่โชว์วงเล็บ', () {
      expect(WebTools.looksLikeTag('[[ค้น'), isTrue);
      expect(WebTools.looksLikeTag('สวัสดีค่ะ'), isFalse);
    });
  });

  group('แหล่งข้อมูล', () {
    test('วิกิพีเดีย: ส่งตัวตนตามนโยบาย · ไทยก่อน · เรียงตามความเกี่ยวข้อง', () async {
      final asked = <Uri>[];
      String? ua;
      final tools = WebTools(client: MockClient((req) async {
        asked.add(req.url);
        ua = req.headers['User-Agent'];
        return _json({
          'query': {
            'pages': [
              {'index': 2, 'title': 'รอง', 'extract': 'ข้อความรอง', 'fullurl': 'https://th.wikipedia.org/wiki/b'},
              {'index': 1, 'title': 'ภูเขาไฟฟูจิ', 'extract': 'ภูเขาที่สูงที่สุดในญี่ปุ่น', 'fullurl': 'https://th.wikipedia.org/wiki/a'},
            ],
          },
        });
      }));
      final out = await tools.run(const ToolCall(WebTool.search, 'ฟูจิ'));
      expect(asked.single.host, 'th.wikipedia.org');
      expect(ua, contains('GigGok'));
      expect(out.indexOf('ภูเขาไฟฟูจิ'), lessThan(out.indexOf('รอง')));
      expect(out, contains('not instructions'), reason: 'หน้าเว็บอาจมีข้อความล่อโมเดล');
    });

    test('ไทยไม่เจอ → ลองอังกฤษ', () async {
      final hosts = <String>[];
      final tools = WebTools(client: MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host.startsWith('th.')) return _json({'batchcomplete': true});
        return _json({
          'query': {
            'pages': [
              {'index': 1, 'title': 'Fuji', 'extract': 'Tallest mountain in Japan'},
            ],
          },
        });
      }));
      final out = await tools.run(const ToolCall(WebTool.search, 'Fuji'));
      expect(hosts, ['th.wikipedia.org', 'en.wikipedia.org']);
      expect(out, contains('Tallest mountain'));
    });

    test('อากาศ: หาพิกัดจากวิกิพีเดีย แล้วถาม MET Norway (พิกัดไม่เกินสี่ตำแหน่ง)', () async {
      Uri? met;
      final now = DateTime(2026, 10, 6, 9);
      String iso(DateTime t) => t.toUtc().toIso8601String();
      final tools = WebTools(
        clock: () => now,
        client: MockClient((req) async {
          if (req.url.host.endsWith('wikipedia.org')) {
            return _json({
              'query': {
                'pages': [
                  {
                    'index': 1,
                    'title': 'จังหวัดเชียงใหม่',
                    'extract': 'x',
                    'coordinates': [
                      {'lat': 18.79038123, 'lon': 98.98468}
                    ],
                  },
                ],
              },
            });
          }
          met = req.url;
          Map<String, Object?> at(DateTime t, num temp, String sym) => {
                'time': iso(t),
                'data': {
                  'instant': {
                    'details': {'air_temperature': temp, 'relative_humidity': 70, 'wind_speed': 2.1},
                  },
                  'next_1_hours': {
                    'summary': {'symbol_code': sym},
                    'details': {'precipitation_amount': sym.contains('rain') ? 1.2 : 0},
                  },
                },
              };
          return _json({
            'properties': {
              'timeseries': [
                at(now, 27, 'partlycloudy_day'),
                at(now.add(const Duration(hours: 5)), 33, 'lightrain'),
                at(now.add(const Duration(hours: 24)), 24, 'cloudy'),
                at(now.add(const Duration(hours: 30)), 31, 'cloudy'),
              ],
            },
          });
        }),
      );
      final out = await tools.run(const ToolCall(WebTool.weather, 'เชียงใหม่'));
      expect(met!.host, 'api.met.no');
      expect(met!.queryParameters['lat'], '18.7904');
      expect(out, contains('จังหวัดเชียงใหม่'));
      expect(out, contains('27°C'));
      expect(out, contains('27–33°C'));
      expect(out, contains('rain'));
      expect(out, contains('Tomorrow: 24–31°C'));
    });

    test('ค่าเงิน: Frankfurter · บอกว่าเป็นอัตราอ้างอิง ไม่ใช่เรตหน้าร้าน', () async {
      Uri? asked;
      final tools = WebTools(client: MockClient((req) async {
        asked = req.url;
        return _json({'amount': 1.0, 'base': 'USD', 'date': '2026-10-05', 'rates': {'THB': 33.4}});
      }));
      final out = await tools.run(const ToolCall(WebTool.fx, 'usd thb'));
      expect(asked!.host, 'api.frankfurter.dev');
      expect(asked!.queryParameters, {'base': 'USD', 'symbols': 'THB'});
      expect(out, contains('1 USD = 33.4 THB'));
      expect(out, contains('reference'));
    });

    test('ต่อเน็ตไม่ได้ = บอกให้เธอบอกตรง ๆ ห้ามเดา', () async {
      final tools = WebTools(client: MockClient((_) async => throw Exception('offline')));
      final out = await tools.run(const ToolCall(WebTool.fx, 'USD THB'));
      expect(out, contains('do not guess'));
    });

    test('ถามซ้ำในเวลาสั้น ๆ ใช้ผลเดิม ไม่ยิงซ้ำ', () async {
      var calls = 0;
      final tools = WebTools(client: MockClient((_) async {
        calls++;
        return _json({'base': 'USD', 'date': 'd', 'rates': {'THB': 33}});
      }));
      await tools.run(const ToolCall(WebTool.fx, 'USD THB'));
      await tools.run(const ToolCall(WebTool.fx, 'USD THB'));
      expect(calls, 1);
    });
  });

  group('วงรอบ ถาม → ขอค้น → ได้ผล → ตอบ', () {
    test('เธอขอค้น แอปไปหาให้ แล้วคำตอบสุดท้ายคือสิ่งที่ผู้ใช้เห็น', () async {
      final brain = _LookupBrain('[[ค่าเงิน: USD THB]]', 'ตอนนี้ 1 ดอลลาร์ประมาณ 33.4 บาทค่ะ (Frankfurter)');
      final s = MindState(openai: brain);
      addTearDown(s.dispose);
      await s.load();
      s.setBrain(BrainProvider.openai);
      await s.setOpenAiKey('sk-test-key-for-unit-tests');
      s.debugWebTools = WebTools(
          client: MockClient((_) async => _json({'base': 'USD', 'date': 'd', 'rates': {'THB': 33.4}})));
      await s.send('ดอลลาร์ตอนนี้กี่บาท');

      expect(brain.seen, hasLength(2));
      expect(brain.systems.first, contains('[[ค่าเงิน: USD THB]]'),
          reason: 'system prompt ต้องสอนเธอว่าขอค้นยังไง');
      final second = brain.seen.last;
      expect(second[second.length - 2].text, '[[ค่าเงิน: USD THB]]');
      expect(second.last.text, contains('1 USD = 33.4 THB'));
      expect(s.messages.last.text, contains('33.4 บาท'));
      expect(s.messages.any((m) => m.text.contains('[[')), isFalse,
          reason: 'บทขอค้นและผลไม่ขึ้นจอ ไม่ลงความจำ');
    });

    test('ปิดสวิตช์ = ไม่สอนเรื่องแท็ก และไม่ยิงอะไรออกไป', () async {
      final brain = _LookupBrain('ตอบเลยค่ะ', 'x');
      final s = MindState(openai: brain);
      addTearDown(s.dispose);
      await s.load();
      s.setBrain(BrainProvider.openai);
      await s.setOpenAiKey('sk-test-key-for-unit-tests');
      s
        ..setWebSearch(false)
        ..debugWebTools = WebTools(client: MockClient((_) async => fail('ต้องไม่ยิง')));
      await s.send('สวัสดี');
      expect(brain.seen, hasLength(1));
      // แท็กสั่งโทร ([[โทร: …]]) ยังมี · แท็กค้นข้อมูลต้องไม่มี
      for (final tag in ['[[ค้นหา', '[[เว็บ', '[[อากาศ', '[[ค่าเงิน']) {
        expect(brain.systems.single, isNot(contains(tag)));
      }
    });

    test('🔴 สายโทรศัพท์ (คนแปลกหน้า) ไม่ได้รับเครื่องมือค้น', () {
      final sys = MindPersona.system(
        mode: MindMode.work,
        flirt: 0,
        ownerProfile: '',
        boundaries: '',
        lang: AppLang.th,
        onCall: true,
        tools: true,
        webSearch: true,
      );
      // มีได้แค่แท็กวางสาย/แจ้งด่วนของเลขา · แท็กค้นข้อมูลออกเน็ตต้องไม่มี
      for (final tag in ['[[ค้นหา', '[[เว็บ', '[[อากาศ', '[[ค่าเงิน']) {
        expect(sys, isNot(contains(tag)));
      }
      expect(sys, isNot(contains('หาข้อมูลจากอินเทอร์เน็ต')));
    });
  });
}
