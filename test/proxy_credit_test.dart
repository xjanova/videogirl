/// เครดิตของ "ผ่านบริการเรา" — กระเป๋าเงิน xman studio หักทุกข้อความ
///
/// ที่มา: เจ้าของสั่ง "ควรมี เครดิต หลอดโควต้า และ ปุ่มการเติม รายละเอียดการเติม
/// อยู่หน้าเว็บ ... และโมเดลไหนเราไม่ได้เปิดให้บริการ ไม่ควรโชว์"
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/openai_client.dart';
import 'package:videogirl/ai/proxy_account.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_ai.dart';
import 'package:videogirl/state/mind_state.dart';

Map<String, Object?> _account({
  bool linked = true,
  double balance = 10,
  double cap = 0,
  double spent = 0,
}) =>
    {
      'enabled': true,
      'linked': linked,
      'link_url': 'https://xman4289.com/giggok/link',
      'topup_url': 'https://xman4289.com/wallet/topup',
      'currency': 'THB',
      'balance': balance,
      'daily_cap': cap,
      'today': {'spent': spent, 'messages': 3},
      'models': [
        {'id': 'gpt-6-luna', 'label': 'Luna', 'price': 0.5},
        {'id': 'gpt-6.1-sol', 'label': 'Sol', 'price': 2},
      ],
      'default_model': 'gpt-6-luna',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('อ่านบัญชีจากหลังบ้าน', () {
    test('รุ่นที่ได้คือรุ่นที่หลังบ้านเปิดเท่านั้น', () {
      final a = ProxyAccount.fromJson(_account())!;
      expect(a.models.map((m) => m.id), ['gpt-6-luna', 'gpt-6.1-sol']);
      expect(a.balance, 10);
      expect(a.linked, isTrue);
    });

    test('รุ่นที่เลือกถูกปิดไปแล้ว → ใช้รุ่นแรกที่เปิด (ตรงกับหลังบ้าน)', () {
      final a = ProxyAccount.fromJson(_account())!;
      expect(a.modelFor('gpt-6.1-sol')!.id, 'gpt-6.1-sol');
      expect(a.modelFor('gpt-6-astra')!.id, 'gpt-6-luna');
      expect(a.modelFor('')!.id, 'gpt-6-luna');
    });

    test('ส่งได้อีกกี่ข้อความ = เงินที่มี หรือเพดานที่เหลือ อย่างไหนน้อยกว่า', () {
      final rich = ProxyAccount.fromJson(_account(balance: 10))!;
      expect(rich.messagesLeft(rich.models.first), 20); // 10 / 0.5
      final capped = ProxyAccount.fromJson(_account(balance: 100, cap: 5, spent: 4))!;
      expect(capped.messagesLeft(capped.models.last), 0); // เหลือเพดาน 1 บาท รุ่นละ 2
      expect(capped.messagesLeft(capped.models.first), 2); // 1 / 0.5
    });

    test('หลอดโควต้า: มีเพดานถึงมีหลอด', () {
      expect(ProxyAccount.fromJson(_account(cap: 50, spent: 10))!.todayShare, closeTo(.2, 1e-9));
      expect(ProxyAccount.fromJson(_account(cap: 0, spent: 10))!.todayShare, isNull);
      expect(ProxyAccount.fromJson(_account(cap: 5, spent: 9))!.todayShare, 1.0);
    });

    test('ยอดหลังหักมากับคำตอบ ไม่ต้องถามซ้ำ', () {
      final a = ProxyAccount.fromJson(_account(balance: 10, spent: 1))!
          .withBilling({'charged': 0.5, 'balance': 9.5, 'spent_today': 1.5, 'daily_cap': 0});
      expect(a.balance, 9.5);
      expect(a.spentToday, 1.5);
      expect(a.messagesToday, 4);
    });
  });

  group('🔴 ข้อผิดพลาดเรื่องเงินต้องบอกสิ่งที่ต้องทำจริง', () {
    const s = S(AppLang.th);

    Future<OpenAiFailure> failWith(int status, Map<String, Object?> body) async {
      final c = OpenAiClient(
        httpClient: MockClient((_) async => http.Response(jsonEncode(body), status,
            headers: {'content-type': 'application/json'})),
        baseUrl: 'https://xman4289.com/api/ai/v1',
        apiKey: 'KEY',
        strings: () => s,
        upstream: Upstream.proxy,
      );
      try {
        await c.reply(system: 'x', history: [(fromHer: false, text: 'hi')], model: '');
      } on OpenAiFailure catch (e) {
        return e;
      }
      fail('ต้องล้ม');
    }

    test('เครดิตไม่พอ (402) → บอกให้เติม พร้อมรหัสให้หน้าจอโชว์ปุ่ม', () async {
      final e = await failWith(402, {
        'error': {'message': 'Not enough credit', 'code': 'insufficient_credit'},
      });
      expect(e.message, s.errProxyNoCredit);
      expect(e.code, 'insufficient_credit');
    });

    test('ยังไม่ผูกบัญชี (403) → ไม่ใช่ "รหัสสิทธิ์ใช้ไม่ได้"', () async {
      final e = await failWith(403, {
        'error': {'message': 'Link this device', 'code': 'not_linked'},
      });
      expect(e.message, s.errProxyNotLinked);
      expect(e.message, isNot(s.errLicenseRejected));
    });

    test('ถึงเพดานวันนี้ (429) → ไม่ใช่ "ส่งถี่เกินไป"', () async {
      final e = await failWith(429, {
        'error': {'message': 'cap', 'code': 'daily_cap'},
      });
      expect(e.message, s.errProxyDailyCap);
    });

    test('รหัสสิทธิ์ผิดจริง (401 ไม่มีรหัสเหตุผล) ยังบอกเหมือนเดิม', () async {
      final e = await failWith(401, {'error': {'message': 'Invalid'}});
      expect(e.message, s.errLicenseRejected);
      expect(e.code, isNull);
    });

    test('คำตอบที่สำเร็จแนบยอดคงเหลือมา', () async {
      final c = OpenAiClient(
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({
                'choices': [
                  {'message': {'role': 'assistant', 'content': 'ค่ะ'}},
                ],
                'giggok_billing': {'charged': 0.5, 'balance': 9.5, 'spent_today': 0.5},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
        baseUrl: 'https://xman4289.com/api/ai/v1',
        apiKey: 'KEY',
        upstream: Upstream.proxy,
      );
      await c.reply(system: 'x', history: [(fromHer: false, text: 'hi')], model: '');
      expect(c.lastBilling?['balance'], 9.5);
    });
  });

  group('state ถามเครดิตจากหลังบ้าน', () {
    Future<MindState> proxyState() async {
      final s = MindState();
      await s.load();
      s
        ..setBrain(BrainProvider.mindProxy)
        ..setStoreBaseUrl('https://xman4289.com')
        ..setLicenseKey('KEY-123');
      return s;
    }

    test('ส่งรหัสสิทธิ์เป็น Bearer ไปที่ /api/ai/v1/account แล้วได้บัญชี', () async {
      final s = await proxyState();
      addTearDown(s.dispose);
      Uri? asked;
      String? auth;
      await s.refreshProxyAccount(
        client: ProxyAccountClient(
          client: MockClient((req) async {
            asked = req.url;
            auth = req.headers['Authorization'];
            return http.Response(jsonEncode(_account(balance: 42)), 200);
          }),
        ),
      );
      expect(asked.toString(), 'https://xman4289.com/api/ai/v1/account');
      expect(auth, 'Bearer KEY-123');
      expect(s.proxyAccount!.balance, 42);
      expect(s.proxyAccountError, isNull);
      expect(s.proxyModelInUse!.id, 'gpt-6-luna');
    });

    test('เลือกรุ่นของบริการแยกจากรุ่น OpenAI ของคีย์ตัวเอง', () async {
      final s = await proxyState();
      addTearDown(s.dispose);
      final before = s.brainModel;
      s.setProxyModel('gpt-6.1-sol');
      expect(s.proxyModel, 'gpt-6.1-sol');
      expect(s.brainModel, before);
    });

    test('รหัสสิทธิ์ไม่ผ่าน → บอกเหตุผล ไม่ล้ม', () async {
      final s = await proxyState();
      addTearDown(s.dispose);
      await s.refreshProxyAccount(
        client: ProxyAccountClient(client: MockClient((_) async => http.Response('{}', 401))),
      );
      expect(s.proxyAccount, isNull);
      expect(s.proxyAccountError, s.s.errLicenseRejected);
      expect(s.proxyAccountBusy, isFalse);
    });

    test('ยังไม่มีรหัสสิทธิ์ = ไม่ยิงไปไหน', () async {
      final s = await proxyState();
      addTearDown(s.dispose);
      s.setLicenseKey('');
      await s.refreshProxyAccount(
        client: ProxyAccountClient(client: MockClient((_) async => fail('ต้องไม่ยิง'))),
      );
      expect(s.proxyAccountError, s.s.licenseNeeded);
    });
  });
}
