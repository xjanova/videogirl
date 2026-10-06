/// สมองก้อนเดียวกับมายด์บนคอม (BrainX Cloud)
///
/// ที่มา: เจ้าของ — "มายด์ของ brainx ในคอมที่ขึ้นคราวด์แล้ว ก็เชื่อมต่อแอพนี้ด้วย
/// จะคุยเรื่องเดียวกันจำได้หมด" · "ใช้ไอดีเดียวกันกับ xman id … ถ้าเสียค่าคราวด์
/// brainx อยู่แล้ว แอพนี้ก็เชื่อมฟรีเลย" · "ไม่ต้องกลัวว่าถอนแล้วจะลืมที่คุยกัน จีบกันไว้"
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/mind_persona.dart';
import 'package:videogirl/ai/secret_store.dart';
import 'package:videogirl/brainx/brainx_cloud.dart';
import 'package:videogirl/brainx/brainx_link.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/memory/mind_memory.dart';
import 'package:videogirl/theme/tokens.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

/// คลาวด์ปลอมที่จำทุกอย่างที่ส่งขึ้น · ตอบ /mcp แบบ BrainX.Server
class _FakeCloud {
  final notes = <String, String>{};
  final calls = <String>[];
  String? lastAuth;
  bool expired = false;
  String token = 'bxc_test_token';

  http.Client client() => MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        lastAuth = req.headers['Authorization'];
        final path = req.url.path;
        if (path == '/api/cloud/login') {
          final b = jsonDecode(req.body) as Map;
          if (b['licenseKey'] != 'BRX-PAID') return _json({'code': 'INVALID_LICENSE', 'message': 'x'}, 401);
          return _json({
            'token': token,
            'tokenId': 'abc',
            'account': {
              'licenseType': 'monthly',
              'isValid': !expired,
              'daysRemaining': 20,
              'usedBytes': 1,
              'quotaBytes': 1000,
              'noteCount': 1886,
            },
          });
        }
        if (req.headers['Authorization'] != 'Bearer $token') {
          return _json({'code': 'UNAUTHORIZED', 'message': 'x'}, 401);
        }
        switch (path) {
          case '/api/cloud/notes':
            if (expired) return _json({'code': 'LICENSE_EXPIRED', 'message': 'x'}, 402);
            for (final f in (jsonDecode(req.body) as Map)['files'] as List) {
              expect(f['sha256'], BrainXCloud.sha(f['content'] as String), reason: 'ตรงสัญญา sha256');
              notes[f['path'] as String] = f['content'] as String;
            }
            return _json({'written': 1});
          case '/api/cloud/notes/fetch':
            final paths = ((jsonDecode(req.body) as Map)['paths'] as List).cast<String>();
            return _json({
              'files': [
                for (final p in paths)
                  if (notes.containsKey(p)) {'path': p, 'content': notes[p], 'sha256': 'x'},
              ],
            });
          case '/api/cloud/manifest':
            return _json({
              'files': [for (final p in notes.keys) {'path': p, 'sha256': 'x', 'size': 1}],
            });
          case '/mcp':
            final msg = jsonDecode(req.body) as Map;
            if (msg['method'] == 'initialize') {
              return http.Response(jsonEncode({'jsonrpc': '2.0', 'id': msg['id'], 'result': {}}), 200,
                  headers: {'content-type': 'application/json', 'mcp-session-id': 'sess-1'});
            }
            if (msg['method'] == 'notifications/initialized') return http.Response('', 202);
            expect(req.headers['Mcp-Session-Id'], 'sess-1');
            if (expired) {
              return _json({
                'jsonrpc': '2.0',
                'id': null,
                'error': {'code': -32010, 'message': 'x', 'data': {'code': 'LICENSE_EXPIRED'}},
              }, 402);
            }
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
                          'matchContext': 'เจ้าของบอกมายด์บนคอมว่าพรุ่งนี้จะไปเชียงใหม่',
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  BrainXLink linkWith(_FakeCloud cloud, http.Client xman, Map<String, String> secrets) => BrainXLink(
        cloud: BrainXCloud(client: cloud.client(), baseUrl: 'https://serverbrain.test'),
        xman: xman,
        readSecret: (k) async => secrets[k] ?? '',
        writeSecret: (k, v) async {
          secrets[k] = v;
          return true;
        },
        flushDelay: const Duration(milliseconds: 10),
      );

  /// หลังบ้านตอบเหมือน xmanstudio: ล็อกอินคลาวด์ให้แล้ว ส่งมาแค่ token กับบัญชี
  Map<String, Object?> xmanToken(_FakeCloud cloud) => {
        'linked': true,
        'active': true,
        'token': cloud.token,
        'account': {'licenseType': 'monthly', 'isValid': true, 'daysRemaining': 20, 'noteCount': 1886},
      };

  MockClient xmanSays(Map<String, Object?> body, {void Function(http.Request)? seen}) =>
      MockClient((req) async {
        seen?.call(req);
        return _json(body);
      });

  group('🔴 บัญชี xman เดียวกัน = คีย์เดียวกัน · จ่าย BrainX แล้วมือถือเชื่อมฟรี', () {
    test('🔴 เชื่อมด้วยบัญชี: หลังบ้านล็อกอินแทน ส่งมาแค่ token · คีย์ไม่เคยถึงมือถือ', () async {
      final cloud = _FakeCloud();
      final secrets = <String, String>{};
      http.Request? asked;
      final link = linkWith(cloud, xmanSays(xmanToken(cloud), seen: (r) => asked = r), secrets);
      addTearDown(link.dispose);

      await link.connectViaXman(storeBase: 'https://xman4289.com', license: 'FREE-DEVICE');
      expect(asked!.method, 'POST');
      expect(asked!.url.toString(), 'https://xman4289.com/api/ai/v1/brainx');
      expect(asked!.headers['Authorization'], 'Bearer FREE-DEVICE');
      expect((jsonDecode(asked!.body) as Map)['device_name'], 'GigGok (Android)');
      expect(link.state, BrainXState.connected);
      expect(link.account!.noteCount, 1886);
      expect(secrets[SecretStore.kBrainXToken], 'bxc_test_token', reason: 'token เก็บในที่เก็บความลับ');
      expect(secrets[SecretStore.kBrainXKey] ?? '', isEmpty);
      expect(cloud.calls.where((c) => c.contains('login')), isEmpty, reason: 'มือถือไม่ได้ล็อกอินเอง ไม่มีคีย์ให้ล็อกอิน');

      // ใช้ token นั้นค้นสมองได้จริง
      expect(await link.recall('เชียงใหม่'), isNotEmpty);
    });

    test('🔴 คีย์ที่พิมพ์เองก็ไม่ลงเครื่อง · รุ่นเก่าที่เคยเก็บคีย์ไว้ ถูกลบตอนเปิดแอป', () async {
      final secrets = <String, String>{};
      final link = linkWith(_FakeCloud(), xmanSays({}), secrets);
      addTearDown(link.dispose);
      await link.connectWithKey('BRX-PAID');
      expect(link.state, BrainXState.connected);
      expect(secrets.values, isNot(contains('BRX-PAID')));

      final old = <String, String>{SecretStore.kBrainXToken: 'bxc_test_token', SecretStore.kBrainXKey: 'BRX-PAID'};
      final upgraded = linkWith(_FakeCloud(), xmanSays({}), old);
      addTearDown(upgraded.dispose);
      await upgraded.load();
      expect(upgraded.connected, isTrue, reason: 'token เดิมยังใช้ได้ ไม่ต้องเชื่อมใหม่');
      expect(old[SecretStore.kBrainXKey], isEmpty);
    });

    test('BrainX Cloud หมดอายุ (หลังบ้านบอก) = บอกให้ต่ออายุ', () async {
      final link = linkWith(_FakeCloud(), xmanSays({'linked': true, 'active': false, 'expired': true}), {});
      addTearDown(link.dispose);
      await link.connectViaXman(storeBase: 'https://xman4289.com', license: 'X');
      expect(link.state, BrainXState.expired);
    });

    test('ยังไม่ได้ผูกบัญชี / ยังไม่มี BrainX Cloud = บอกสิ่งที่ต้องทำ ไม่ล็อกอินมั่ว', () async {
      final cloud = _FakeCloud();
      final a = linkWith(cloud, xmanSays({'linked': false, 'active': false}), {});
      addTearDown(a.dispose);
      await a.connectViaXman(storeBase: 'https://xman4289.com', license: 'X');
      expect(a.state, BrainXState.notLinked);

      final b = linkWith(cloud, xmanSays({'linked': true, 'active': false, 'buy_url': 'https://xman4289.com/products/brainx'}), {});
      addTearDown(b.dispose);
      await b.connectViaXman(storeBase: 'https://xman4289.com', license: 'X');
      expect(b.state, BrainXState.notSubscribed);
      expect(b.buyUrl, 'https://xman4289.com/products/brainx');
      expect(cloud.calls.where((c) => c.contains('login')), isEmpty);
    });

    test('คีย์ไม่ผ่าน (ฟรี/ทดลอง ที่คลาวด์ไม่รับ) = ให้สมัคร', () async {
      final link = linkWith(_FakeCloud(), xmanSays({}), {});
      addTearDown(link.dispose);
      await link.connectWithKey('BRX-DEMO');
      expect(link.state, BrainXState.notSubscribed);
    });

    test('หมดอายุ = บอกให้ต่ออายุ', () async {
      final cloud = _FakeCloud()..expired = true;
      final link = linkWith(cloud, xmanSays({}), {});
      addTearDown(link.dispose);
      await link.connectWithKey('BRX-PAID');
      expect(link.state, BrainXState.expired);
    });
  });

  group('คุยเรื่องเดียวกับมายด์บนคอม', () {
    test('ค้นสมองผ่าน /mcp ได้บทที่คุยกับมายด์บนคอม', () async {
      final cloud = _FakeCloud();
      final link = linkWith(cloud, xmanSays({}), {});
      addTearDown(link.dispose);
      await link.connectWithKey('BRX-PAID');

      final hits = await link.recall('ไปเชียงใหม่วันไหนนะ');
      expect(hits.single.text, contains('เชียงใหม่'));
      expect(hits.single.path, 'Mind/Conversations/2026-10-05 pc.md');
      // ถามอีกครั้งใช้ session เดิม ไม่ initialize ใหม่ทุกตา
      await link.recall('อีกเรื่อง');
      expect(cloud.calls.where((c) => c == 'POST /mcp').length, 4);
    });

    test('token ถูกเพิกถอน → ขอใหม่เงียบ ๆ ผ่านหลังบ้าน (ไม่มีคีย์ในเครื่องก็ได้) แล้วค้นต่อได้', () async {
      final cloud = _FakeCloud();
      final secrets = <String, String>{SecretStore.kBrainXToken: 'bxc_test_token'};
      final link = linkWith(cloud, MockClient((_) async => _json(xmanToken(cloud))), secrets)
        ..xmanSource = (() => (storeBase: 'https://xman4289.com', license: 'FREE-DEVICE'));
      addTearDown(link.dispose);
      await link.load(); // เปิดแอปใหม่: มีแค่ token
      cloud.token = 'bxc_new_token'; // คลาวด์เพิกถอนตัวเก่า
      expect(await link.recall('เชียงใหม่'), isNotEmpty);
      expect(secrets[SecretStore.kBrainXToken], 'bxc_new_token');
    });

    test('token ถูกเพิกถอน · ใส่คีย์เองไว้ในรอบนี้ → ล็อกอินใหม่ได้ในรอบนี้', () async {
      final cloud = _FakeCloud();
      final link = linkWith(cloud, xmanSays({}), {});
      addTearDown(link.dispose);
      await link.connectWithKey('BRX-PAID');
      cloud.token = 'bxc_new_token';
      expect(await link.recall('เชียงใหม่'), isNotEmpty);
    });

    test('ค้นไม่ทันเวลา = ตอบจากที่มี ไม่รอ', () async {
      final slow = BrainXLink(
        cloud: BrainXCloud(
            client: MockClient((_) => Future.delayed(const Duration(seconds: 5), () => http.Response('{}', 200)))),
        readSecret: (_) async => 'x',
        writeSecret: (_, _) async => true,
      );
      addTearDown(slow.dispose);
      await slow.load();
      final clock = Stopwatch()..start();
      expect(await slow.recall('อะไรก็ได้', limit: const Duration(milliseconds: 200)), isEmpty);
      expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('🔴 ถอนแอปแล้วไม่ลืม — ส่งขึ้นแล้วกู้กลับได้ครบ', () {
    test('ความจำ ความสัมพันธ์ และบทสนทนา ไปแล้วกลับมาเหมือนเดิม', () async {
      final cloud = _FakeCloud();
      final link = linkWith(cloud, xmanSays({}), {});
      addTearDown(link.dispose);
      await link.connectWithKey('BRX-PAID');

      final day = DateTime(2026, 10, 6);
      link
        ..queue(
            MindPaths.phoneMemory,
            BrainXLink.renderMemory([
              MemoryFact(id: '1', text: 'เจ้าของแพ้กุ้ง', kind: MemoryKind.fact, createdAt: day, pinned: true),
              MemoryFact(id: '2', text: 'ชอบกาแฟดำ', kind: MemoryKind.preference, createdAt: day),
            ]))
        ..queue(MindPaths.phoneSoul, BrainXLink.renderSoul({'affection': .72, 'together': true, 'name': 'ไอซ์'}))
        ..queue(
            MindPaths.phoneDay(day),
            BrainXLink.renderDay(day, [
              (at: DateTime(2026, 10, 6, 9, 5), fromHer: false, text: 'คิดถึงจัง'),
              (at: DateTime(2026, 10, 6, 9, 6), fromHer: true, text: 'คิดถึงเหมือนกันค่ะ\nวันนี้กินข้าวยัง'),
            ], her: 'ไอซ์'));
      await link.flush();
      expect(cloud.notes.keys, containsAll([MindPaths.phoneMemory, MindPaths.phoneSoul, MindPaths.phoneDay(day)]));

      // ลงแอปใหม่ = เชื่อมใหม่แล้วดึงกลับ
      final fresh = BrainXLink(
        cloud: BrainXCloud(client: cloud.client(), baseUrl: 'https://serverbrain.test'),
        readSecret: (_) async => '',
        writeSecret: (_, _) async => true,
        clock: () => DateTime(2026, 10, 7),
      );
      addTearDown(fresh.dispose);
      await fresh.connectWithKey('BRX-PAID');
      final b = (await fresh.fetchBackup())!;

      expect(b.facts.map((f) => f.text), ['เจ้าของแพ้กุ้ง', 'ชอบกาแฟดำ']);
      expect(b.facts.first.pinned, isTrue);
      expect(b.facts.last.kind, MemoryKind.preference);
      expect(b.soul!['together'], isTrue);
      expect(b.soul!['name'], 'ไอซ์');
      expect(b.lines, hasLength(2));
      expect(b.lines.last.fromHer, isTrue);
      expect(b.lines.last.text, 'คิดถึงเหมือนกันค่ะ\nวันนี้กินข้าวยัง', reason: 'ข้อความหลายบรรทัดกลับมาครบ');
      expect(b.lines.first.at, DateTime(2026, 10, 6, 9, 5));
    });

    test('ส่งไม่ผ่าน (หมดอายุ) = ของยังอยู่ในคิว ไม่หาย', () async {
      final cloud = _FakeCloud();
      final link = linkWith(cloud, xmanSays({}), {});
      addTearDown(link.dispose);
      await link.connectWithKey('BRX-PAID');
      cloud.expired = true;
      link.queue(MindPaths.phoneMemory, 'x');
      await link.flush();
      expect(link.debugPending, contains(MindPaths.phoneMemory));
      expect(link.state, BrainXState.expired);
    });
  });

  group('ชวนเก็บบนคลาวด์แบบเนียน ๆ — พูดแต่เรื่องจริง', () {
    test('ความเสี่ยงที่เปรยตรงกับสถานะเครื่องจริง', () {
      final noVault = MindPersona.cloudNudgeBlock(AppLang.th, survivesUninstall: false);
      final vault = MindPersona.cloudNudgeBlock(AppLang.th, survivesUninstall: true);
      expect(noVault, contains('ลบแอป'));
      expect(vault, isNot(contains('ลบแอป')), reason: 'มีสำเนาแล้ว ถอนแอปไม่ลืม ห้ามพูดเกินจริง');
      expect(vault, contains('BrainX Cloud'));
      expect(noVault, contains('ห้ามทำให้เจ้าของรู้สึกผิด'));
    });

    test('สายโทรศัพท์ไม่มีทั้งการเปรยและสิ่งที่มายด์บนคอมจด', () {
      final sys = MindPersona.system(
        mode: MindMode.work,
        flirt: 0,
        ownerProfile: '',
        boundaries: '',
        lang: AppLang.th,
        onCall: true,
        pcProfile: 'เจ้าของชอบกาแฟ',
        nudge: 'NUDGE',
      );
      expect(sys, isNot(contains('NUDGE')));
      expect(sys, isNot(contains('ชอบกาแฟ')));
    });
  });
}
