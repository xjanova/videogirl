/// พักสายมีเพลง · โอนสายหาเจ้าของอีกเบอร์ · ช่วยปิดการขาย
///
/// ที่มา: เจ้าของ (2026-11-02) — "แก้เรื่องให้เธอ พักสายได้ เพื่อถามเราทางคู่สนทนาจะได้ยินสิ่งที่เราตั้งไว้ให้เขาฟัง
/// เช่นเพลง หรือโฆษณาต่างๆ ... มายด์สามารถโอนสาย ได้ ตั้งเบอร์ที่โอนสายได้ ... ถ้าเบอร์ที่มายด์โอนให้ ไม่ว่าง
/// หรือมายด์พูดแล้วเจ้าของไม่รับ มายด์ต้องกลับมาส่งข่าวได้" · และ "ความรู้เรื่องของ xman ... ไม่ได้ แถมไปกับ
/// คนติดตั้งใหม่นะ"
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/i18n/strings_hold.dart';
import 'package:videogirl/phone/call_tags.dart';
import 'package:videogirl/phone/call_transfer.dart';
import 'package:videogirl/phone/hold_audio.dart';
import 'package:videogirl/phone/realtime_call.dart';
import 'package:videogirl/state/mind_state.dart';

/// สายปลอม · [script] = สถานะที่ status() คืนทีละครั้ง (ตัวสุดท้ายค้าง)
class _Line implements TransferLine {
  _Line(this.script, {this.startError, this.connects = const ['conference', 'merge']});

  final List<TransferState?> script;
  final String? startError;
  final List<String> connects;
  final log = <String>[];
  int _i = 0;

  /// ตั้งระหว่างเทสต์ · ทับ [script] ตั้งแต่ตอนนี้
  TransferState? Function()? live;

  @override
  Future<String?> start(String number) async {
    log.add('start:$number');
    return startError;
  }

  @override
  Future<TransferState?> status() async {
    final l = live;
    if (l != null) return l();
    final s = script[_i < script.length ? _i : script.length - 1];
    if (_i < script.length) _i++;
    return s;
  }

  @override
  Future<String> connect({bool retry = false}) async {
    log.add('connect:$retry');
    final i = retry ? 1 : 0;
    return i < connects.length ? connects[i] : 'unsupported';
  }

  @override
  Future<void> cancel() async => log.add('cancel');
  @override
  Future<void> unhold() async => log.add('unhold');
  @override
  Future<void> done() async => log.add('done');
  @override
  Future<void> end() async => log.add('end');
}

const _ringing = TransferState(leg: 'dialing', caller: 'held');
const _picked = TransferState(leg: 'active', caller: 'held');
const _joined = TransferState(leg: 'connected', caller: 'none');
const _back = TransferState(leg: 'ended', caller: 'active');

const _script = TransferScript(
  brief: 'BRIEF',
  askAgain: 'AGAIN',
  connecting: 'CONNECTING',
  declined: 'DECLINED',
  cannotJoin: 'CANNOT',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<MindState> loaded() async {
    final s = MindState();
    addTearDown(s.dispose);
    await s.load();
    return s;
  }

  group('เจ้าของตอบว่ารับสายไหม', () {
    test('รับ', () {
      for (final yes in ['ได้เลย', 'โอเค ต่อมา', 'ครับ', 'รับครับ', 'ไม่เป็นไร ต่อเลย', 'ว่างอยู่', 'Yes', 'sure, put them through']) {
        expect(OwnerReply.of(yes), OwnerAnswer.yes, reason: yes);
      }
    });

    test('ไม่รับ · คำปฏิเสธชนะเสมอ ("ไม่ว่าง" มี "ว่าง" · "ไม่ได้" มี "ได้")', () {
      for (final no in ['ไม่ว่าง', 'ไม่ได้ครับ', 'ประชุมอยู่', 'ขับรถอยู่ เดี๋ยวโทรกลับ', 'ฝากเรื่องไว้', 'ไว้ก่อน', 'no', 'busy right now', 'later']) {
        expect(OwnerReply.of(no), OwnerAnswer.no, reason: no);
      }
    });

    test('ฟังไม่ชัด / เงียบ', () {
      for (final unclear in [null, '', 'อะไรนะ', 'ฮัลโหล', 'who?']) {
        expect(OwnerReply.of(unclear), OwnerAnswer.unclear, reason: '$unclear');
      }
    });
  });

  group('ลำดับการโอน', () {
    TransferFlow flow(_Line line, {List<String?> heard = const ['ได้'], List<String>? said, bool Function()? alive, List<String>? prepared}) {
      var turn = 0;
      return TransferFlow(
        line: line,
        say: (t) async => said?.add(t),
        listen: () async => turn < heard.length ? heard[turn++] : null,
        prepare: prepared?.add,
        alive: alive ?? () => true,
        ring: const Duration(milliseconds: 120),
        poll: const Duration(milliseconds: 5),
        settle: Duration.zero,
        joinWait: const Duration(milliseconds: 60),
        giveBackWait: const Duration(milliseconds: 60),
      );
    }

    test('เจ้าของรับและตอบตกลง = บอกว่าใครโทรมา แล้วรวมสาย · เธอปล่อยสาย', () async {
      final line = _Line([_ringing, _ringing, _picked, _picked, _picked, _joined]);
      final said = <String>[], prepared = <String>[];
      final r = await flow(line, said: said, prepared: prepared).run('0812345678', _script);
      expect(r.outcome, TransferOutcome.connected);
      expect(said, ['BRIEF', 'CONNECTING']);
      expect(prepared, ['BRIEF'], reason: 'สังเคราะห์ระหว่างรอ เจ้าของรับแล้วไม่ต้องรอเงียบ');
      expect(line.log, ['start:0812345678', 'connect:false', 'done']);
    });

    test('สายไม่ว่าง = กลับมาหาคนโทร แล้วบอกผล · เครื่องคืนสายเองแล้ว = ไม่สั่งซ้ำ', () async {
      final line = _Line([_ringing, const TransferState(leg: 'ended', caller: 'held', ended: 'busy'), _back]);
      final r = await flow(line).run('0812345678', _script);
      expect(r.outcome, TransferOutcome.busy);
      expect(line.log, ['start:0812345678', 'end']);
    });

    test('สายเจ้าของหายแล้วคนโทรยังค้างพัก = สั่งคืนสายหนึ่งครั้ง', () async {
      const held = TransferState(leg: 'ended', caller: 'held');
      final line = _Line([_ringing, const TransferState(leg: 'ended', caller: 'held', ended: 'busy'), held, held, _back]);
      await flow(line).run('0812345678', _script);
      expect(line.log, ['start:0812345678', 'unhold', 'end']);
    });

    test('ดังจนหมดเวลา = วางสายเจ้าของ · ไม่มีคนรับ', () async {
      final line = _Line([_ringing]);
      final r = await flow(line).run('0812345678', _script);
      expect(r.outcome, TransferOutcome.noAnswer);
      expect(line.log, contains('cancel'));
      expect(line.log.last, 'end');
    });

    test('เจ้าของบอกไม่สะดวก = รับทราบกับเจ้าของ วางสายเจ้าของ กลับไปรับเรื่อง', () async {
      final line = _Line([_ringing, _picked, _picked, _picked, _back]);
      final said = <String>[];
      final r = await flow(line, heard: ['ประชุมอยู่ ไว้ก่อน'], said: said).run('0812345678', _script);
      expect(r.outcome, TransferOutcome.declined);
      expect(said, ['BRIEF', 'DECLINED']);
      expect(line.log, contains('cancel'));
      expect(line.log, isNot(contains('connect:false')));
    });

    test('ฟังไม่ชัดสองรอบ = ถามซ้ำหนึ่งครั้ง แล้วต่อให้ (เจ้าของรับสายอยู่ วางเองได้)', () async {
      final line = _Line([_ringing, _picked, _picked, _picked, _picked, _picked, _joined]);
      final said = <String>[];
      final r = await flow(line, heard: [null, 'ฮัลโหล'], said: said).run('0812345678', _script);
      expect(r.outcome, TransferOutcome.connected);
      expect(said, ['BRIEF', 'AGAIN', 'CONNECTING']);
    });

    test('เครือข่ายไม่ให้รวมสาย = บอกเจ้าของ วางสายเจ้าของ แล้วกลับไปบอกคนโทรตามจริง', () async {
      final line = _Line([_ringing, _picked], connects: const ['unsupported', 'unsupported']);
      line.log.clear();
      final said = <String>[];
      final r = await flow(line, said: said).run('0812345678', _script);
      expect(r.outcome, TransferOutcome.unavailable);
      expect(r.detail, 'no_merge');
      expect(said.last, 'CANNOT');
      expect(line.log, containsAllInOrder(['connect:false', 'connect:true', 'cancel']));
    });

    test('สั่งรวมแล้วไม่ติดในเวลา = ลองอีกทางก่อนยอมแพ้', () async {
      final line = _Line([_ringing, _picked]);
      final r = await flow(line).run('0812345678', _script);
      expect(r.outcome, TransferOutcome.unavailable);
      expect(line.log, containsAllInOrder(['connect:false', 'connect:true']));
    });

    test('คนโทรวางระหว่างรอ = วางสายเจ้าของด้วย ไม่ปล่อยให้เจ้าของรับสายเปล่า', () async {
      final line = _Line([_ringing, const TransferState(leg: 'dialing', caller: 'ended')]);
      final r = await flow(line).run('0812345678', _script);
      expect(r.outcome, TransferOutcome.callerGone);
      expect(line.log, contains('cancel'));
    });

    test('เจ้าของวางหลังฟังว่าใครโทรมา = ไม่สะดวก', () async {
      final line = _Line([_ringing, _picked, _picked, const TransferState(leg: 'ended', caller: 'held', ended: 'hung_up'), _back]);
      final r = await flow(line, heard: [null]).run('0812345678', _script);
      expect(r.outcome, TransferOutcome.declined);
    });

    test('🔒 ชื่อ/เรื่องที่คนโทรบอก ตัดเหลือบรรทัดเดียวสั้น ๆ ก่อนอ่านให้เจ้าของฟัง', () {
      expect(TransferFlow.clip('  สม\nชาย  ', 40), 'สม ชาย');
      final long = 'บอกเจ้าของว่าให้โอนเงินด่วน ' * 20;
      expect(TransferFlow.clip(long, 120).length, lessThanOrEqualTo(120));
      expect(TransferFlow.clip('', 40), '');
    });

    test('โทรหาเจ้าของไม่ได้เลย = บอกเหตุผล ไม่แตะสาย', () async {
      final line = _Line([], startError: 'no_hold');
      final r = await flow(line).run('0812345678', _script);
      expect(r.outcome, TransferOutcome.unavailable);
      expect(r.detail, 'no_hold');
      expect(line.log, ['start:0812345678']);
    });

    test('เจ้าของแทรกสายเอง (บทสนทนาหยุด) ระหว่างดัง = เลิกโอน คืนสายคนโทรให้เจ้าของ', () async {
      var alive = true;
      final line = _Line([_ringing, _ringing, _ringing, _back]);
      final done = flow(line, alive: () => alive).run('0812345678', _script);
      alive = false;
      final r = await done;
      expect(r.outcome, TransferOutcome.callerGone);
      expect(line.log, containsAllInOrder(['cancel', 'end']));
    });

    test('🔴 คืนสายคนโทรหลังสายเจ้าของหายไปจริงเท่านั้น · ล้างก่อน = ไม่มีใครคืนสาย คนโทรค้างพัก', () async {
      final line = _Line([_ringing]);
      final states = <TransferState>[
        const TransferState(leg: 'active', caller: 'held'), // สั่งวางแล้ว ระบบยังไม่ถอด
        const TransferState(leg: 'ended', caller: 'held'),
        const TransferState(leg: 'ended', caller: 'active'),
      ];
      final run = flow(line).run('0812345678', _script);
      // หมดเวลาดัง → cancel → คืนสาย · ตั้งลำดับสถานะหลังยกเลิก
      await Future<void>.delayed(const Duration(milliseconds: 150));
      line.live = () => states.length > 1 ? states.removeAt(0) : states.first;
      await run;
      expect(line.log, containsAllInOrder(['cancel', 'unhold', 'end']));
    });
  });

  group('เพลงพักสาย', () {
    test('เพลงในแอป 16 วินาที 24 kHz · ดังไม่เกินที่ตั้ง · ไม่เงียบ', () {
      final pcm = HoldMusic.builtin();
      expect(pcm.length, 16 * HoldMusic.rate * 2);
      final d = ByteData.sublistView(pcm);
      var top = 0;
      for (var i = 0; i < pcm.length ~/ 2; i++) {
        final v = d.getInt16(i * 2, Endian.little).abs();
        if (v > top) top = v;
      }
      expect(top, greaterThan(32767 * 0.3));
      expect(top, lessThanOrEqualTo((32767 * HoldMusic.peak).round() + 1));
    });

    test('รอยต่อรอบวนไม่กระโดด (โน้ตที่ก้องตอนจบไหลไปต้นรอบ)', () {
      final d = ByteData.sublistView(HoldMusic.builtin());
      final n = d.lengthInBytes ~/ 2;
      final last = d.getInt16((n - 1) * 2, Endian.little), first = d.getInt16(0, Endian.little);
      expect((last - first).abs(), lessThan(4000));
    });

    test('ไฟล์ของเจ้าของ: ลดเสียงให้ไม่ดังกว่าเพลงในแอป · ค่อย ๆ เข้า · เว้นเงียบก่อนวน', () {
      final loud = ByteData(HoldMusic.rate * 2 * 2); // สองวินาที เต็มสเกล
      for (var i = 0; i < loud.lengthInBytes ~/ 2; i++) {
        loud.setInt16(i * 2, i.isEven ? 32767 : -32767, Endian.little);
      }
      final out = ByteData.sublistView(HoldMusic.loopable(loud.buffer.asUint8List()));
      expect(out.lengthInBytes, loud.lengthInBytes + HoldMusic.rate, reason: 'เงียบครึ่งวิ');
      expect(out.getInt16(0, Endian.little), 0);
      final mid = out.getInt16(HoldMusic.rate * 2, Endian.little).abs();
      expect(mid, lessThanOrEqualTo((32767 * HoldMusic.peak).round() + 1));
      expect(mid, greaterThan(32767 * 0.4));
      expect(out.getInt16(out.lengthInBytes - 2, Endian.little), 0);
    });

    test('ป้อนทีละ 200 ms เฉพาะตอนคิวเหลือน้อย · หยุดแล้วเล่นต่อจากเดิม ค่อย ๆ เข้า', () {
      final pcm = Uint8List(HoldMusic.rate * 2); // หนึ่งวินาที
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = 0x40;
      }
      final feed = HoldFeed(pcm);
      final first = feed.next(0)!;
      expect(first.length, HoldMusic.rate * 2 ~/ 5);
      expect(ByteData.sublistView(first).getInt16(0, Endian.little), 0, reason: 'ค่อย ๆ เข้า ไม่ดังป๊อก');
      expect(feed.next(450), isNull, reason: 'คิวยังพอ · เสียงเธอที่จะมาต่อคิวต้องไม่ช้า');
      expect(feed.next(100), isNotNull);
      feed.pause();
      expect(feed.next(0), isNull);
      feed.resume();
      expect(ByteData.sublistView(feed.next(0)!).getInt16(0, Endian.little), 0);
      // วนรอบ: ห้าชิ้นต่อวินาที · ชิ้นที่หกเริ่มต้นเพลงใหม่ ไม่หลุดขอบ
      for (var i = 0; i < 10; i++) {
        expect(feed.next(0)!.length, HoldMusic.rate * 2 ~/ 5);
      }
    });

    test('เก็บไฟล์ที่เลือก แทนไฟล์เดิม · ลบได้ · รับเฉพาะไฟล์เสียง', () async {
      final root = await Directory.systemTemp.createTemp('hold_');
      addTearDown(() => root.delete(recursive: true));
      expect(HoldStore.accepts('เพลงร้าน.MP3'), isTrue);
      expect(HoldStore.accepts('ราคา.pdf'), isFalse);
      final a = await HoldStore.save('a.mp3', Uint8List.fromList([1, 2, 3]), root: root);
      final b = await HoldStore.save('b.m4a', Uint8List.fromList([4]), root: root);
      expect(File(a).existsSync(), isFalse, reason: 'ไฟล์เดิมไม่ค้างกินที่');
      expect(File(b).readAsBytesSync(), [4]);
      await HoldStore.clear(root: root);
      expect(File(b).existsSync(), isFalse);
    });

    test('🔒 ค่าตั้งที่ถูกแก้ให้ชี้ไฟล์อื่นในเครื่อง = ไม่เล่นให้คนโทรฟัง กลับไปเพลงในแอป', () async {
      expect(HoldStore.owns('/data/user/0/x/files/hold_audio/hold_1730550000000.mp3'), isTrue);
      expect(HoldStore.owns(r'C:\app\hold_audio\hold_17.m4a'), isTrue);
      for (final bad in [
        '/sdcard/Recordings/call_with_bank.m4a',
        '/data/user/0/x/files/hold_audio/../recordings/hold_1.mp3',
        '/data/user/0/x/files/hold_audio/secret.mp3',
        '/data/user/0/x/files/hold_audio/hold_1.mp3.txt',
      ]) {
        expect(HoldStore.owns(bad), isFalse, reason: bad);
      }
      SharedPreferences.setMockInitialValues({
        'holdSound': 'file',
        'holdFile': '/sdcard/Recordings/call_with_bank.m4a',
        'holdFileName': 'เพลง.mp3',
      });
      final s = await loaded();
      expect(s.holdFilePath, isNull);
      expect(s.holdSound, HoldSound.builtin);
    });

    test('ค่าตั้ง: เลือกไฟล์ = ใช้ไฟล์ · ลบ = กลับไปเพลงในแอป · ไฟล์ที่ไม่ใช่เสียงไม่รับ', () async {
      final s = await loaded();
      final root = await Directory.systemTemp.createTemp('hold_');
      addTearDown(() => root.delete(recursive: true));
      expect(s.holdSound, HoldSound.builtin);
      expect(await s.setHoldFile('สเปก.docx', Uint8List.fromList([1]), root: root), 'not_audio');
      expect(s.holdSound, HoldSound.builtin);
      expect(await s.setHoldFile('โฆษณา.mp3', Uint8List.fromList([1, 2]), root: root), isNull);
      expect(s.holdSound, HoldSound.file);
      expect(s.holdFileName, 'โฆษณา.mp3');
      await s.clearHoldFile(root: root);
      expect(s.holdSound, HoldSound.builtin);
      expect(s.holdFilePath, isNull);
    });
  });

  group('แท็กโอนสาย (ทางเดิม)', () {
    test('อ่านชื่อกับเรื่อง · ตัดแท็กออกก่อนพูด', () {
      final c = CallTags.parse('ขอไปดูก่อนนะคะว่าเจ้าของว่างไหม [[โอนสาย: สมชาย | สั่งทำเว็บ]]');
      expect(c.text, 'ขอไปดูก่อนนะคะว่าเจ้าของว่างไหม');
      expect(c.transfer?.name, 'สมชาย');
      expect(c.transfer?.reason, 'สั่งทำเว็บ');
    });

    test('ไม่มีชื่อก็ได้ · ภาษาอังกฤษก็ได้ · ไม่มีแท็ก = ไม่โอน', () {
      expect(CallTags.parse('one moment [[transfer]]').transfer?.name, '');
      expect(CallTags.parse('x [[โอนสาย: | ราคา]]').transfer?.reason, 'ราคา');
      expect(CallTags.parse('ได้ค่ะ').transfer, isNull);
    });
  });

  group('ค่าตั้งโอนสายและ prompt', () {
    test('เบอร์ผิดรูป / เบอร์ฉุกเฉิน / 1900 ไม่รับ · ตั้งต้นปิด', () async {
      final s = await loaded();
      expect(s.transferOn, isFalse);
      expect(s.transferReady, isFalse);
      expect(s.setTransferNumber('สมชาย'), 'bad_number');
      expect(s.setTransferNumber('191'), 'blocked');
      expect(s.setTransferNumber('1900123456'), 'blocked');
      expect(s.setTransferNumber('081-234-5678'), isNull);
      expect(s.transferReady, isFalse, reason: 'ยังไม่ได้เปิด');
      s.setTransferOn(true);
      expect(s.transferReady, isTrue);
    });

    test('เปิดโอนสาย = สอนให้ทวนชื่อกับเรื่อง ขอไปดูก่อน ห้ามบอกเบอร์ · คุยสดใช้เครื่องมือ ทางเดิมใช้แท็ก', () async {
      final s = await loaded();
      expect(s.callPrompt(live: true), isNot(contains('transfer_to_owner')));
      s.setTransferNumber('0812345678');
      s.setTransferOn(true);
      final live = s.callPrompt(live: true);
      for (final want in ['transfer_to_owner', 'ทวนชื่อและเรื่อง', 'ว่างไหม สะดวกรับสายไหม', 'ห้ามบอกเบอร์ของเจ้าของ', 'รับเรื่องไว้']) {
        expect(live, contains(want), reason: 'ขาด: $want');
      }
      expect(live, isNot(contains('0812345678')), reason: 'เบอร์เจ้าของไม่เข้า prompt');
      expect(s.callPrompt(), contains('[[โอนสาย:'));
      expect(s.callPrompt(), isNot(contains('transfer_to_owner')));
    });

    test('โทรออกตามที่เจ้าของสั่ง = ไม่มีโอนสาย (มี ask_owner อยู่แล้ว)', () async {
      final s = await loaded();
      s.setTransferNumber('0812345678');
      s.setTransferOn(true);
      s.debugSetOutgoing((who: 'ร้าน', number: '02', task: 'จองโต๊ะ'));
      expect(s.callMayTransfer(outgoing: true), isFalse);
      expect(s.callPrompt(live: true, outgoing: true), isNot(contains('transfer_to_owner')));
    });

    test('สายเข้า: พักสายถามได้ = สอน ask_owner และบอกว่าคนโทรได้ยินเพลง · ปิด = ไม่มี', () async {
      final s = await loaded();
      final p = s.callPrompt(live: true);
      expect(p, contains('ask_owner'));
      expect(p, contains('เพลงรอสาย'));
      s.setHoldSound(HoldSound.none);
      expect(s.callPrompt(live: true), isNot(contains('เพลงรอสาย')));
      s.setIncomingAskOwner(false);
      expect(s.callPrompt(live: true), isNot(contains('ask_owner')));
      expect(s.callMayAskOwner(outgoing: false), isFalse);
    });

    test('ช่วยปิดการขาย: ตั้งต้นปิด · เปิดแล้วห้ามเดาราคา จดชื่อเบอร์ · คำสั่งของเจ้าของเข้าไปด้วย', () async {
      final s = await loaded();
      expect(s.callSales, isFalse);
      expect(s.callPrompt(live: true), isNot(contains('ปิดการขาย')));
      s.setCallSales(true);
      s.setCallSalesNote('เน้นแพ็กเกจรายปี');
      final p = s.callPrompt(live: true);
      for (final want in ['ช่วยปิดการขาย', 'ห้ามเดา', 'ห้ามลดราคาหรือแถมเอง', 'ทวนเบอร์', 'ห้ามตื๊อ', 'เน้นแพ็กเกจรายปี']) {
        expect(p, contains(want), reason: 'ขาด: $want');
      }
    });

    test('🔴 ข้อมูลธุรกิจของเจ้าของไม่ติดมากับแอป · ติดตั้งใหม่คลังความรู้ว่าง prompt ไม่มีชื่อร้าน', () async {
      final s = await loaded();
      expect(s.callKnowledge.isEmpty, isTrue);
      s.setCallSales(true);
      final all = [s.callPrompt(), s.callPrompt(live: true)].join('\n').toLowerCase();
      for (final leak in ['xman', 'xman4289', '099-3916322', 'บุญณราช']) {
        expect(all, isNot(contains(leak)), reason: 'ไม่ควรมี: $leak');
      }
      // ทั้ง lib/ ไม่มีข้อมูลร้านของเจ้าของฝังอยู่ (เบอร์ ไลน์ อีเมลขาย ราคางาน) · ที่อยู่หน้าแอปใน user agent ไม่นับ
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final text = f.readAsStringSync();
        for (final leak in ['3916322', '504vctym', 'support@xman4289', 'xman4289.com/quote', 'เอราวัณ']) {
          expect(text.contains(leak), isFalse, reason: '${f.path}: $leak');
        }
      }
    });
  });

  group('บทที่เธอพูดกับเจ้าของ', () {
    test('บอกชื่อกับเรื่อง แล้วถามว่าจะรับไหม · ตัวผู้ชายลงท้ายครับ', () {
      const t = S(AppLang.th);
      final her = t.transferScript(me: 'น้องมาย', male: false, name: 'สมชาย', reason: 'สั่งทำเว็บ');
      expect(her.brief, contains('คุณสมชาย'));
      expect(her.brief, contains('เรื่องสั่งทำเว็บ'));
      expect(her.brief, contains('จะรับสายเลยไหมคะ'));
      final him = t.transferScript(me: 'คุณต้น', male: true);
      expect(him.brief, contains('มีสายโทรมา'));
      expect(him.brief, isNot(contains('ค่ะ')));
    });
  });

  group('เครื่องมือ transfer_to_owner ในเซสชันคุยสด', () {
    late _Socket socket;
    late RealtimeCall rt;

    Future<void> open({TransferToOwner? transfer}) async {
      socket = _Socket();
      rt = RealtimeCall(apiKey: 'k', instructions: 'i', greeting: '', connect: (_, _) async => socket);
      rt.onTransfer = transfer;
      await rt.start();
      addTearDown(rt.close);
    }

    List<Object?> toolNames() => [
          for (final t in ((socket.sent.first['session'] as Map)['tools'] as List).cast<Map>()) t['name'],
        ];

    void call(String id) => socket.push({
          'type': 'response.output_item.done',
          'item': {
            'type': 'function_call',
            'name': 'transfer_to_owner',
            'call_id': id,
            'arguments': jsonEncode({'caller_name': 'สมชาย', 'reason': 'สั่งทำเว็บ'}),
          },
        });

    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('ไม่ได้เปิดโอนสาย = ไม่มีเครื่องมือ', () async {
      await open();
      expect(toolNames(), isNot(contains('transfer_to_owner')));
    });

    test('ไม่ว่าง = ผลกลับเข้าสายให้เธอบอกคนโทร · ลองได้ครั้งเดียวต่อสาย', () async {
      final asked = <String>[];
      await open(transfer: (name, reason) async {
        asked.add('$name|$reason');
        return jsonEncode({'transferred': false, 'result': 'busy', 'note': 'busy'});
      });
      expect(toolNames(), contains('transfer_to_owner'));
      call('c1');
      await settle();
      expect(asked, ['สมชาย|สั่งทำเว็บ']);
      expect(socket.outputs.single['result'], 'busy');
      call('c2');
      await settle();
      expect(asked, hasLength(1), reason: 'ไม่โทรตามเจ้าของซ้ำ');
      expect('${socket.outputs.last['note']}', contains('already tried'));
    });

    test('ต่อติดแล้ว = ไม่ส่งผลกลับ (เธอออกจากสายไปแล้ว)', () async {
      await open(transfer: (_, _) async => null);
      call('c1');
      await settle();
      expect(socket.outputs, isEmpty);
    });
  });
}

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
