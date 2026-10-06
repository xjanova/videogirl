/// ปุ่มค้นหาเซิร์ฟเวอร์ในบ้าน + ปุ่มทดสอบ
///
/// ที่มา: เจ้าของขอ "การใช้ Local model ควรมีปุ่มแสกน และทดสอบว่าใช้ได้" · ของเดิม
/// ต้องพิมพ์ IP เองแล้วรู้ผลทางเดียวคือทักเธอแล้วได้ "ต่อเน็ตไม่ได้" ซึ่งไม่บอก
/// ว่าผิดที่ที่อยู่ ที่รุ่น หรือที่คอม
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/local_server_scan.dart';
import 'package:videogirl/i18n/strings_ai.dart';
import 'package:videogirl/i18n/strings_voice.dart';
import 'package:videogirl/state/mind_state.dart';

http.Response _models(List<String> ids) => http.Response(
      jsonEncode({
        'object': 'list',
        'data': [for (final id in ids) {'id': id, 'object': 'model'}],
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ไล่เฉพาะวงในบ้าน', () {
    test('วงส่วนตัวเท่านั้น', () {
      expect(LocalServerScanner.isPrivate('192.168.1.20'), isTrue);
      expect(LocalServerScanner.isPrivate('10.0.0.5'), isTrue);
      expect(LocalServerScanner.isPrivate('172.20.3.4'), isTrue);
      expect(LocalServerScanner.isPrivate('172.32.0.1'), isFalse);
      expect(LocalServerScanner.isPrivate('8.8.8.8'), isFalse);
      expect(LocalServerScanner.isPrivate('fe80::1'), isFalse);
    });

    test('🔴 ไม่ไล่วงของเน็ตมือถือ/VPN (เพื่อนบ้านคือลูกค้าคนอื่นของค่าย)', () {
      for (final n in ['wlan0', 'swlan0', 'ap0', 'eth0', 'en0', 'Wi-Fi', 'Ethernet', 'rndis0']) {
        expect(LocalServerScanner.isLanInterface(n), isTrue, reason: n);
      }
      for (final n in ['rmnet_data0', 'ccmni0', 'tun0', 'v4-rmnet_data0', 'clat4', 'pdp0', 'ppp0']) {
        expect(LocalServerScanner.isLanInterface(n), isFalse, reason: n);
      }
    });

    test('ทั้งวง /24 ยกเว้นตัวเอง + เครื่องนี้เอง (Termux)', () {
      final t = LocalServerScanner.targets(['192.168.1.20', '8.8.8.8']);
      expect(t, contains('127.0.0.1'));
      expect(t, contains('192.168.1.1'));
      expect(t, contains('192.168.1.254'));
      expect(t, isNot(contains('192.168.1.20')));
      expect(t.where((h) => h.startsWith('8.8.')), isEmpty);
      expect(t.length, 254); // 253 เพื่อนบ้าน + 127.0.0.1
    });
  });

  test('เจอพอร์ตเปิด → ยืนยันด้วย /v1/models · พอร์ตเปิดที่ไม่ใช่เซิร์ฟเวอร์โมเดลถูกทิ้ง', () async {
    final asked = <String>[];
    final scanner = LocalServerScanner(
      localIps: () async => ['192.168.1.20'],
      probe: (h, p) async =>
          (h == '192.168.1.50' && p == 11434) || (h == '192.168.1.9' && p == 8080) ||
          (h == '127.0.0.1' && p == 1234),
      client: MockClient((req) async {
        asked.add(req.url.toString());
        if (req.url.host == '192.168.1.50') return _models(['gemma4:latest', 'qwen3:8b']);
        if (req.url.host == '127.0.0.1') return _models(['local-model']);
        return http.Response('<html>router</html>', 200); // หน้าเว็บของเราเตอร์
      }),
      parallel: 400,
    );
    final progress = <double>[];
    final found = await scanner.scan(onProgress: progress.add);

    expect(found.map((s) => s.baseUrl),
        ['http://127.0.0.1:1234/v1', 'http://192.168.1.50:11434/v1'],
        reason: 'เครื่องนี้เองขึ้นก่อน · เราเตอร์ที่เปิด 8080 ไม่ใช่เซิร์ฟเวอร์โมเดล');
    expect(found.last.kind, 'Ollama');
    expect(found.last.models, ['gemma4:latest', 'qwen3:8b']);
    expect(progress.last, 1.0);
    expect(asked.every((u) => u.endsWith('/v1/models')), isTrue,
        reason: 'ระหว่างค้นหาไม่ส่งอะไรอื่นออกไป');
  });

  test('อ่านรายชื่อรุ่น · ติดต่อไม่ได้ = null (ไม่ใช่รายการว่าง)', () async {
    final ok = LocalServerScanner(client: MockClient((_) async => _models(['a', 'b'])));
    expect(await ok.models('http://x:11434/v1/'), ['a', 'b']);
    final down = LocalServerScanner(client: MockClient((_) async => throw Exception('refused')));
    expect(await down.models('http://x:11434/v1'), isNull);
    final notModel = LocalServerScanner(client: MockClient((_) async => http.Response('{}', 200)));
    expect(await notModel.models('http://x:11434/v1'), isNull);
  });

  group('ปุ่มทดสอบ — บอกให้ตรงจุดว่าผิดที่ไหน', () {
    Future<MindState> state() async {
      final s = MindState();
      await s.load();
      s
        ..setBrain(BrainProvider.homeServer)
        ..setHomeServerUrl('http://192.168.1.50:11434/v1')
        ..setHomeServerModel('gemma4:latest');
      return s;
    }

    test('ติดต่อไม่ได้ = บอกที่อยู่ที่ลอง พร้อมสิ่งที่ต้องเช็ก', () async {
      final s = await state();
      addTearDown(s.dispose);
      final r = await s.testHomeServer(
          scanner: LocalServerScanner(client: MockClient((_) async => throw Exception('x'))));
      expect(r.ok, isFalse);
      expect(r.message, s.s.homeUnreachable('http://192.168.1.50:11434/v1'));
    });

    test('ไม่มีรุ่นที่ตั้งไว้ = บอกรุ่นที่มีจริงให้เลือก', () async {
      final s = await state();
      addTearDown(s.dispose);
      final r = await s.testHomeServer(
          scanner: LocalServerScanner(client: MockClient((_) async => _models(['qwen3:8b']))));
      expect(r.ok, isFalse);
      expect(r.message, s.s.homeModelMissing('gemma4:latest', 'qwen3:8b'));
    });

    test('ถามจริงแล้วตอบได้ = บอกเวลาและคำตอบ', () async {
      final s = await state();
      addTearDown(s.dispose);
      String? sentModel;
      final r = await s.testHomeServer(
        scanner: LocalServerScanner(client: MockClient((_) async => _models(['gemma4:latest']))),
        httpClient: MockClient((req) async {
          final body = jsonDecode(req.body) as Map<String, Object?>;
          sentModel = body['model'] as String?;
          expect(body.containsKey('reasoning_effort'), isFalse,
              reason: 'Ollama ไม่รู้จักฟิลด์ของ OpenAI');
          return http.Response(
            jsonEncode({
              'choices': [
                {'message': {'role': 'assistant', 'content': 'พร้อมค่ะ'}},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect(r.ok, isTrue, reason: r.message);
      expect(r.message, contains('พร้อมค่ะ'));
      expect(sentModel, 'gemma4:latest');
    });

    test('ยังไม่ได้ใส่ที่อยู่ = บอกตรง ๆ ไม่ยิงไปไหน', () async {
      final s = await state();
      addTearDown(s.dispose);
      s.setHomeServerUrl('');
      final r = await s.testHomeServer(
          scanner: LocalServerScanner(client: MockClient((_) async => fail('ต้องไม่ยิง'))));
      expect(r.ok, isFalse);
      expect(r.message, s.s.homeServerNoUrl);
    });
  });
}
