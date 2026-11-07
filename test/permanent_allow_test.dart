/// อนุญาตถาวร · เจ้าของ (2026-11-07): "ให้เราเปิดการอนุญาตถาวร โดยไม่ต้องถามเราทุกครั้งได้ในแอป" ·
/// "ให้อนุญาตถาวรได้หมด แต่อันไหนเสี่ยง เพียงขั้นเตือนก่อนอนุญาต เพราะบางคนต้องการเอาไว้รันเรื่องเงินอย่างเดียว"
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/hands/hands_bridge.dart';
import 'package:videogirl/hands/phone_action.dart';
import 'package:videogirl/hands/phone_policy.dart';
import 'package:videogirl/hands/phone_task.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_trust.dart';
import 'package:videogirl/state/mind_state.dart';

String _src(String path) => File(path).readAsStringSync();

String _body(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'หา $signature ไม่เจอ');
  var depth = 0;
  for (var i = source.indexOf('{', start); i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}' && --depth == 0) return source.substring(start, i + 1);
  }
  fail('ปีกกาของ $signature ไม่ครบ');
}

const _hands = 'android/app/src/main/kotlin/com/xjanova/videogirl/hands';

PhoneScreen _screen(String package, List<ScreenNode> nodes) => PhoneScreen(package: package, app: 'App', nodes: nodes);

void main() {
  group('แยกเรื่องของขั้นที่ถาม', () {
    test('เงิน · ลบ · ตั้งค่า · ส่ง · ดูไม่ออก', () {
      final shop = _screen('com.shop', const [
        ScreenNode(id: 1, cls: 'Button', text: 'ชำระเงิน', click: true),
        ScreenNode(id: 2, cls: 'Button', text: 'Delete', click: true),
        ScreenNode(id: 3, cls: 'Button', text: 'ส่ง', click: true),
        ScreenNode(id: 4, cls: 'Button', text: 'Transfer', click: true),
      ]);
      expect(PhonePolicy.kindOf(const PhoneAction('tap', id: 1), shop), PhoneStepKind.money);
      expect(PhonePolicy.kindOf(const PhoneAction('tap', id: 4), shop), PhoneStepKind.money);
      expect(PhonePolicy.kindOf(const PhoneAction('tap', id: 2), shop), PhoneStepKind.erase);
      expect(PhonePolicy.kindOf(const PhoneAction('tap', id: 3), shop), PhoneStepKind.send);
      final settings = _screen(PhonePolicy.settingsPackage, const [ScreenNode(id: 1, cls: 'Switch', text: 'Wi-Fi', check: true)]);
      expect(PhonePolicy.kindOf(const PhoneAction('tap', id: 1), settings), PhoneStepKind.settings);
      expect(PhonePolicy.kindOf(const PhoneAction('tap', id: 9, risky: true), shop), PhoneStepKind.unknown);
    });

    test('🔴 เรื่องเสี่ยง (ต้องเตือนก่อนอนุญาตถาวร) = ทุกเรื่องยกเว้นส่ง/โพสต์', () {
      expect([for (final k in PhoneStepKind.values) if (k.risky) k],
          [PhoneStepKind.money, PhoneStepKind.erase, PhoneStepKind.settings, PhoneStepKind.unknown]);
      expect(PhoneStepKind.parse('money'), PhoneStepKind.money);
      expect(PhoneStepKind.parse('?'), PhoneStepKind.unknown, reason: 'ค่าแปลก = เสี่ยงไว้ก่อน');
      const ask = PhoneStepAsk(id: 1, goal: 'g', action: 'a', app: 'KBank', package: 'com.kbank', kind: PhoneStepKind.money);
      expect(ask.trustKey, 'com.kbank|money');
    });

    test('ข้อความครบสองภาษา', () {
      for (final lang in AppLang.values) {
        final s = S(lang);
        for (final k in PhoneStepKind.values) {
          expect(s.handsKindLabel(k), isNotEmpty);
        }
        expect(s.handsAlwaysWarnBody('x', 'y'), isNotEmpty);
        expect(s.trustNone, isNotEmpty);
      }
    });
  });

  group('เก็บและใช้', () {
    test('อ่านค่าที่เก็บ · ค่าเสีย = ไม่อนุญาตอะไร', () {
      expect(MindState.decodeHandsTrust('{"com.kbank|money":"KBank","bad":"x",  "a|send":3}'), {'com.kbank|money': 'KBank'});
      expect(MindState.decodeHandsTrust('not json'), isEmpty);
      expect(MindState.decodeHandsTrust(null), isEmpty);
    });

    test('🔴 อนุญาตไว้ = ทำเลยแต่บอกในแชท · ให้สิทธิ์ได้จากคำตอบของเจ้าของเท่านั้น', () {
      final state = _src('lib/state/mind_state.dart');
      // ปีกกาแรกคือพารามิเตอร์ {bool trust} · ตัดถึงปีกกาปิดของเมธอดแทน
      final at = state.indexOf('Future<bool> _confirmInChat(');
      final confirm = state.substring(at, state.indexOf('\n  }\n', at));
      expect(confirm, contains('_handsTrust.containsKey(ask.trustKey)'));
      expect(confirm, contains('s.handsTrustedDid('));
      expect(confirm, contains('alwaysRisky: ask.kind.risky'));
      expect(confirm, contains('if (p.allow && p.always) _trustHands(ask);'));
      expect(state, contains('if (allow && always && ask != null) _trustHands(ask);'));
      expect(RegExp(r'_trustHands\(').allMatches(state).length, 3, reason: 'ประกาศ + สองทางที่เจ้าของตอบ');
      expect(const HandsPoll(allow: false, always: true).always, isTrue);
      expect(HandsPoll.fromMap({'confirm': {'id': 1, 'allow': false, 'always': true}}).always, isFalse,
          reason: 'ไม่ทำ = ไม่อนุญาตถาวร');
    });

    test('🔴 กล่องในแอป: ติ๊กถาวร + เรื่องเสี่ยง = เตือนอีกชั้นก่อนปิดกล่อง', () {
      final shell = _src('lib/shell.dart');
      final allow = _body(shell, 'Future<void> _allow(');
      expect(allow, contains('if (_always && a.kind.risky)'));
      expect(allow, contains('if (ok != true || !mounted) return;'));
      expect(shell, contains('state.answerPhoneAsk(ask.id, answer.allow, always: answer.always)'));
    });

    test('ยกเลิกทั้งหมดต้องยืนยันก่อน', () {
      final panel = _src('lib/screens/hands_trust_panel.dart');
      expect(_body(panel, 'Future<void> _removeAll('), contains('if (ok == true) state.untrustHands(null);'));
      expect(_src('lib/screens/settings_screen.dart'), contains('HandsTrustPanel(accent: mode.accent)'));
    });
  });

  group('ฝั่งเนทีฟ', () {
    test('🔴 strings.xml: เครื่องหมาย \' ต้อง escape ไม่งั้น build พัง (mergeReleaseResources)', () {
      for (final dir in ['values', 'values-en']) {
        for (final line in _src('android/app/src/main/res/$dir/strings.xml').split('\n')) {
          final m = RegExp(r'<string name="[^"]+">(.*)</string>').firstMatch(line);
          if (m == null) continue;
          final v = m.group(1)!;
          // ทั้งข้อความครอบด้วย "…" ได้ · ข้างในคำพูด "…" ก็ได้ · นอกนั้นต้องเป็น \'
          final bare = v.replaceAll(r"\'", '').replaceAll(RegExp(r'"[^"]*"'), '');
          expect(bare.contains("'"), isFalse, reason: '$dir: $line');
        }
      }
    });

    test('🔴 แจ้งเตือนมีปุ่ม "ไม่ต้องถามอีก" เฉพาะเรื่องไม่เสี่ยง (เตือนในแจ้งเตือนไม่ได้)', () {
      final ask = _body(_src('$_hands/HandsService.kt'), 'fun ask(');
      expect(ask, contains('!alwaysRisky'));
      expect(ask, contains('ACTION_ALWAYS'));
    });

    test('🔴 กล่องลอย: ติ๊กถาวร + เสี่ยง = กดครั้งแรกแค่เตือน แล้วรอให้ปุ่มพร้อมใหม่', () {
      final overlay = _src('$_hands/AskOverlay.kt');
      expect(overlay, contains('R.string.hands_always_warn'));
      expect(overlay, contains('R.string.hands_always_confirm'));
      for (final dir in ['values', 'values-en']) {
        final xml = _src('android/app/src/main/res/$dir/strings.xml');
        for (final n in ['hands_always', 'hands_always_check', 'hands_always_warn', 'hands_always_confirm', 'chat_always_check', 'chat_send_trust']) {
          expect(xml, contains('name="$n"'), reason: '$dir ขาด $n');
        }
      }
    });
  });
}
