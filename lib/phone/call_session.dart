/// สายที่เธอถือเอง — ตั้งแต่รับจนวาง
///
/// ## 🔴 เพดานจริงของ Android ที่ทั้งไฟล์นี้ตั้งอยู่บน
///
/// **ไม่มี API ป้อนเสียงเข้าสาย และไม่มี API ดึงเสียงในสายออกมา**
/// `VOICE_UPLINK` / `VOICE_DOWNLINK` / `VOICE_CALL` ถูกสงวนให้แอประบบ
/// ตั้งแต่ Android 10 · เป็นแอปโทรศัพท์หลักก็ไม่ได้สิทธิ์พวกนี้
///
/// สิ่งที่ทำที่นี่จึงเป็นกลไกอ้อมทั้งสองทาง:
///
/// | ทิศ | วิธี | โอกาสสำเร็จ |
/// |---|---|---|
/// | เธอ → ปลายสาย | เปิดลำโพง เล่นเสียงเธอออกลำโพง ให้ไมค์รับเข้าไป | ดี |
/// | ปลายสาย → เธอ | อัดจากไมค์ตอนเปิดลำโพง เสียงคู่สายออกลำโพงมาด้วย | ลุ้น |
///
/// ทางที่สอง "ลุ้น" เพราะหลายเครื่องคืน**ความเงียบสนิท**ให้แอปที่อัดเสียง
/// ระหว่างมีสาย โดยไม่มี error ไม่มี permission denied — ได้ไฟล์ครบ
/// ขนาดถูกต้อง แต่ทุกตัวอย่างเป็นศูนย์ · จับได้ทางเดียวคือ**วัดระดับเสียง
/// ที่อัดได้จริง** ซึ่งเป็นสิ่งที่ [micLevel] กับ [deaf] มีไว้ทำ
///
/// เมื่อเครื่องหูหนวก เธอยังทำงานได้ครึ่งหนึ่ง: เจ้าของพิมพ์ให้เธอพูด
/// ([say]) แล้วเสียงยังออกไปถึงปลายสายตามปกติ · ครึ่งที่หายไปคือการฟัง
/// ไม่ใช่ทั้งฟีเจอร์ — ดู docs/telephony.md สำหรับทางที่ไม่ต้องลุ้นเลย
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../ai/openai_client.dart';
import '../avatar/stage_bridge.dart';
import '../i18n/strings_ai.dart';
import '../state/mind_state.dart';
import '../system/permissions.dart';
import 'call_notes.dart';
import 'call_tags.dart';
import 'call_watch.dart';
import 'realtime_call.dart';

/// บรรทัดหนึ่งของบทสนทนาในสาย
@immutable
class CallLine {
  const CallLine.her(this.text) : fromHer = true;
  const CallLine.them(this.text) : fromHer = false;

  final String text;
  final bool fromHer;
}

/// ผลของเซสชันคุยสด · ต่อไม่ได้ (ใช้ทางเดิมตั้งแต่ทัก) · จบตามสาย · หลุดกลางสาย (ใช้ทางเดิมต่อ)
enum _RtResult { couldNotStart, ended, dropped }

/// เธอกำลังทำอะไรอยู่ในสายตอนนี้
enum CallTurn {
  /// ไม่มีสายที่เธอถืออยู่
  none,

  /// กำลังพูดออกลำโพง
  talking,

  /// กำลังฟังปลายสาย
  listening,

  /// กำลังคิดคำตอบ
  thinking,

  /// เจ้าของแทรกสายแล้ว — เธอเงียบ สายยังอยู่
  handedOver,
}

class CallSession extends ChangeNotifier {
  CallSession({
    required CallWatch watch,
    required MindState state,
    MethodChannel? channel,
    AudioRecorder? recorder,
    MindPermissions? permissions,
    MindLips? lips,
  })  : _watch = watch,
        _state = state,
        _ch = channel ?? kSystemChannel,
        _injectedRecorder = recorder,
        _perms = permissions ?? MindPermissions(),
        _lips = lips {
    _watch.addListener(_onWatch);
  }

  final CallWatch _watch;
  final MindState _state;
  final MethodChannel _ch;
  final MindPermissions _perms;

  /// ปากของเธอบนเวที · null = ไม่มีเวที (เทสต์ / จอสายเนทีฟตอนล็อกเครื่อง)
  final MindLips? _lips;

  /// หน่วงปากไว้เท่านี้หลังสั่งเล่นทางเนทีฟ
  ///
  /// ฝั่งเนทีฟต้องสร้าง MediaPlayer อ่านหัวไฟล์ (prepareAsync) แล้วเสียงยัง
  /// ต้องวิ่งผ่านบัฟเฟอร์ลำโพงอีกชั้น ก่อนจะ "ได้ยิน" จริง · ส่วนเวทีที่เตรียม
  /// ไฟล์ไว้แล้วออกตัวแทบทันที · ไม่หน่วง = ปากนำเสียงจนดูเป็นพากย์
  /// ค่านี้ประมาณจากสองช่วงนั้นรวมกัน ไม่ได้วัดจากเครื่องจริง
  static const lipLead = Duration(milliseconds: 60);

  /// สร้างตอนใช้จริงเท่านั้น — AudioRecorder ผูก MethodChannel ตั้งแต่
  /// constructor เหมือน FlutterTts ถ้าสร้างทันทีจะพังในเทสต์ที่ยังไม่มี binding
  final AudioRecorder? _injectedRecorder;
  AudioRecorder? _lazyRecorder;
  AudioRecorder get _recorder => _lazyRecorder ??= _injectedRecorder ?? AudioRecorder();

  bool _disposed = false;

  // ── สิ่งที่หน้าจออ่าน ────────────────────────────────────

  bool _live = false;
  bool _mind = false;
  String _who = '';
  CallTurn _turn = CallTurn.none;

  /// มีสายที่ **เธอ** เป็นคนถืออยู่หรือเปล่า — สัญญาณให้ตัดไปหน้าจอสาย
  bool get onStage => _live && (_mind || _turn == CallTurn.handedOver);

  /// มีสายอยู่จริงตอนนี้ (ใครถือก็ตาม)
  bool get live => _live;

  /// เธอเป็นคนถือสายนี้อยู่
  bool get mindHolding => _mind;

  String get who => _who;
  CallTurn get turn => _turn;

  /// สายนี้เข้าทางซิมไหน (เครื่องสองซิม) · null = ซิมเดียว / ระบบไม่บอก
  CallSim? _sim;
  CallSim? get sim => _sim;

  final List<CallLine> _lines = [];
  List<CallLine> get lines => List.unmodifiable(_lines);

  /// ระดับเสียงที่ไมค์รับได้จริง 0..1
  ///
  /// 🔴 นี่คือ**เครื่องมือวินิจฉัยที่สำคัญที่สุดของทั้งฟีเจอร์** เพราะเครื่อง
  /// ที่ไม่ยอมให้อัดเสียงระหว่างมีสายจะคืนความเงียบโดยไม่มี error อะไรเลย
  /// ตัวเลขนี้คือความต่างระหว่าง "ปลายสายเงียบ" กับ "เครื่องนี้ไม่ให้ฟัง"
  double _micLevel = 0;
  double get micLevel => _micLevel;

  /// เครื่องนี้ไม่ยอมให้เธอได้ยินอะไรเลย · ตั้งหลังเงียบสนิทติดกันหลายรอบ
  bool _deaf = false;
  bool get deaf => _deaf;

  /// เปิดลำโพงเข้าสายไม่สำเร็จ — ปลายสายจะไม่ได้ยินเธอเลย
  bool _mute = false;
  bool get mute => _mute;

  String? _error;
  String? get error => _error;

  // ── วงจรชีวิตของสาย ─────────────────────────────────────

  Timer? _poll;

  /// ถามฝั่งเนทีฟว่าสายตอนนี้เป็นยังไง
  ///
  /// 🔴 **ถามเอา ไม่ใช่รอให้ยิงมาบอก** จอสายเนทีฟตัดสินใจว่าใครรับสาย
  /// ตอนที่ Flutter engine อาจยังไม่ได้เริ่มด้วยซ้ำ · ถ้ารอสัญญาณ
  /// สายที่เธอรับตอนแอปปิดอยู่จะไม่มีใครรู้เลย แล้วหน้าจอสายก็ไม่ขึ้น
  ///
  /// [CallWatch] เป็นตัวปลุก (มันเป็นเจ้าของ handler ของช่องนี้อยู่แล้ว
  /// ตั้งซ้อนจะไปทับของมันแบบเงียบ ๆ) ส่วนนาฬิกาหนึ่งวินาทีเป็นตัวกันพลาด
  /// สำหรับตอนที่แอปเพิ่งเปิดขึ้นมากลางสาย
  void _onWatch() {
    if (_watch.state == CallState.idle && !_live) return;
    unawaited(_refresh());
  }

  /// เรียกครั้งเดียวตอนเปิดแอป
  ///
  /// 🔴 **จำเป็น ไม่ใช่ของแถม** เพราะกรณีที่สำคัญที่สุดคือแอปเพิ่งถูกเปิด
  /// ขึ้นมาโดยจอสายเนทีฟ *หลัง* เธอรับสายไปแล้ว — สัญญาณสถานะสายเกิดขึ้น
  /// ก่อน Flutter engine เริ่มด้วยซ้ำ · ถ้ารอฟังสัญญาณอย่างเดียว
  /// **หน้าจอสายจะไม่มีวันขึ้นในกรณีนั้นเลย** ซึ่งเป็นกรณีปกติที่สุดของทั้งฟีเจอร์
  Future<void> start() => _refresh();

  /// ขยับทุกครั้งที่เจ้าของแทรกสาย · คำตอบของ [_callInfo] ที่ถามไป**ก่อน**
  /// แทรกสาย เป็นภาพเก่าที่ยังบอกว่าเธอถือสายอยู่ ต้องทิ้ง
  int _handOverSeq = 0;

  Future<void> _refresh() async {
    if (_disposed) return;

    final seq = _handOverSeq;
    final info = await _callInfo();
    // 🔴 ภาพเก่า — ถ้าเชื่อมัน `mind && !was` จะเป็นจริงทันทีหลังแทรกสาย
    // แล้ว [_begin] ทักคู่สายซ้ำ ล้างบทสนทนาทิ้ง ทั้งที่เจ้าของเพิ่งยกเครื่องขึ้นแนบหู
    if (seq != _handOverSeq || _disposed) return;
    final live = info?['live'] == true;
    final mind = info?['mind'] == true;
    final name = (info?['name'] as String?)?.trim();
    final number = (info?['number'] as String?)?.trim();
    final who = (name?.isNotEmpty ?? false) ? name! : (number ?? '');

    final was = _live && _mind;
    _live = live;
    _mind = mind;
    if (who.isNotEmpty) _who = who;
    _sim = CallSim.fromMap(info) ?? _sim;

    if (!live) {
      _finish();
      return;
    }

    // มีสายจริงแล้วค่อยเริ่มถามซ้ำ · นาฬิกานี้คือตัวจับ "เจ้าของกดให้มายด์รับ
    // จากจอสายเนทีฟ" ซึ่งไม่มีสัญญาณอะไรวิ่งมาบอกฝั่งนี้เลย
    _poll ??= Timer.periodic(const Duration(seconds: 1), (_) => _refresh());

    if (mind && !was) _begin();
    if (!mind && was && _turn != CallTurn.handedOver) {
      // เจ้าของแทรกสายจากจอเนทีฟ — หยุดเธอฝั่งนี้ให้ตรงกัน (ปิดไมค์จริงด้วย)
      _turn = CallTurn.handedOver;
      _endRealtime();
      unawaited(_closeMic());
    }
    _notify();
  }

  Future<Map<Object?, Object?>?> _callInfo() async {
    try {
      return await _ch.invokeMethod<Map<Object?, Object?>>('callInfo');
    } on PlatformException catch (e) {
      debugPrint('สาย: ถามสถานะไม่ได้ — $e');
      return null;
    } on MissingPluginException {
      return null; // ไม่ใช่ Android — ไม่ใช่ความผิดพลาด
    }
  }

  /// สายนี้เธอเป็นคนคุย และเริ่มเมื่อไหร่ — ใช้จดบันทึกตอนสายจบ
  bool _handled = false;
  DateTime? _startedAt;

  /// เริ่มบทสนทนาของสายนี้
  void _begin() {
    // ส่งสายคืนให้เธอหลังเจ้าของแทรก = สายเดิม · บทสนทนาต่อจากเดิม ไม่ล้าง
    if (!_handled) _lines.clear();
    _handled = true;
    _startedAt ??= DateTime.now();
    _deaf = false;
    _mute = false;
    _error = null;
    _silentRounds = 0;
    // ไมค์ (และไฟล์บันทึก) เปิดก่อนเธอทัก · คำทักกับคำแรกของคู่สายอยู่ในบันทึกด้วย
    unawaited(() async {
      await _startRecording();
      await _openMic();
    }());
    unawaited(_converse());
  }

  /// สายจบแล้ว — เก็บของให้ครบ
  ///
  /// 🔴 ต้องคืนเสียงและปิดไมค์แม้ทางที่มาถึงตรงนี้จะเป็นทางไหนก็ตาม
  /// ไมค์ที่ค้างเปิดหลังสายจบคือไฟแสดงสถานะสีเขียวที่ไม่มีวันดับ
  void _finish() {
    // ไม่เคยมีสาย = ไม่มีอะไรต้องเก็บ · [_refresh] ถูกเรียกทุกครั้งที่กริ่งดัง
    // ด้วย (สายที่ยังไม่ได้รับ `live` เป็น false) ถ้าไม่กันไว้ จะสั่งคืนเสียง
    // และแจ้งหน้าจอใหม่ทุกวินาทีตลอดเวลาที่กริ่งดัง
    final wasLive = _live || _poll != null;
    _poll?.cancel();
    _poll = null;
    _live = false;
    _mind = false;
    _turn = CallTurn.none;
    _micLevel = 0;
    if (!wasLive) return;

    _endRealtime();
    unawaited(_closeMic());
    unawaited(_invoke('callEndAudio'));
    if (_handled) _reportCall();

    // 🔴 จดเรื่องที่ฝากไว้ **ทุกสายที่เธอเป็นคนคุย** · ของเดิมพอวางสาย
    // บทสนทนาหายไปกับหน่วยความจำ เจ้าของไม่มีทางรู้ว่าใครฝากอะไรไว้
    if (_handled && _lines.isNotEmpty) {
      final who = _who;
      final lines = [for (final l in _lines) (fromHer: l.fromHer, text: l.text)];
      final at = _startedAt;
      final sim = _sim;
      unawaited(() async {
        final audio = await _finishRecording();
        await _state.takeCallNote(who: who, lines: lines, at: at, sim: sim, audio: audio);
      }()
          .catchError((Object e) {
        debugPrint('สาย: จดบันทึกไม่สำเร็จ — ${e.runtimeType}');
      }));
    } else {
      // ไม่มีบันทึกสายให้ผูก = ไม่เก็บเสียงไว้ลอย ๆ
      unawaited(() async {
        try {
          await (await _finishRecording())?.delete();
        } on Object {
          // ลบไม่ได้ก็ไม่ต้องล้มอะไร · ไฟล์อยู่ในพื้นที่ของแอปเอง
        }
      }());
    }
    _handled = false;
    _alertedOwner = false;
    _startedAt = null;
    // สายถัดไปอาจเข้าอีกซิม · ไม่ล้าง = บันทึกสายหน้าติดซิมของสายนี้
    _sim = null;
    _notify();
  }

  // ── ปุ่มบนหน้าจอสาย ─────────────────────────────────────

  /// ให้เธอรับสายที่กำลังดังอยู่ (กดจากในแอป ไม่ใช่จากจอสายเนทีฟ)
  Future<void> letMindAnswer() async {
    final ok = await _invoke<bool>('mindAnswer', {'stream': _state.callStream});
    _mute = ok != true;
    await _refresh();
  }

  /// **แทรกสาย** — เจ้าของขอคุยเอง เธอเงียบทันที เสียงกลับเข้าหูฟัง
  ///
  /// หยุดเธอฝั่ง Dart ก่อนสั่งเนทีฟ · ถ้าสั่งเนทีฟก่อน เทิร์นที่ค้างอยู่
  /// อาจสั่งพูดประโยคถัดไปทับเข้ามาหลังเสียงถูกโอนกลับหูฟังแล้ว
  /// ซึ่งแปลว่าเสียงเธอไปดังใส่หูเจ้าของที่เพิ่งยกเครื่องขึ้นแนบพอดี
  Future<void> bargeIn() async {
    _handOverSeq++;
    _turn = CallTurn.handedOver;
    _mind = false;
    _notify();
    // ปิดไมค์จริง ไม่ใช่แค่เลิกฟัง · เจ้าของคุยเองแล้ว ไม่ใช่สิ่งที่เธอควรอัดต่อ
    _endRealtime();
    await _invoke('liveAudioStop');
    await _closeMic();
    await _invoke('callStopSpeak');
    await _invoke('mindHandOver');
  }

  /// วางสาย
  Future<void> hangUp() async {
    await _invoke('callDisconnect');
    _finish();
  }

  /// ให้เธอพูดประโยคที่เจ้าของพิมพ์เข้าไปในสาย
  ///
  /// ทางนี้ทำงานได้เสมอ **แม้เครื่องจะไม่ยอมให้เธอฟังสาย** เพราะไม่ต้องใช้ไมค์
  /// เลย · เป็นเหตุผลที่ช่องพิมพ์อยู่บนหน้าจอสายตลอด ไม่ใช่โผล่มาตอนพัง
  Future<void> say(String text) {
    final clean = text.trim();
    // เจ้าของแทรกสายไปแล้ว = เสียงกลับเข้าหูฟัง · พูดตอนนี้ปลายสายไม่ได้ยิน
    // มีแต่เจ้าของที่โดนเสียงเธอดังใส่หู
    if (clean.isEmpty || !_live || !_mind) return Future<void>.value();

    // คุยสดอยู่ = ให้เซสชันเดียวกันพูด (เสียงเดียวกัน ช่องเดียวกัน ไม่ชนกัน) ·
    // คำที่พูดจริงกลับมาเป็นบทของเธอเอง ([RealtimeCall.onHerText]) ไม่ต้องจดซ้ำ
    final rt = _rt;
    if (rt != null && rt.connected) {
      rt.say(clean);
      return Future<void>.value();
    }

    // กันกดส่งซ้อน — คืน Future เดิมให้คนกดซ้ำ ไม่ใช่พูดซ้ำสองรอบทับกัน
    final running = _saying;
    if (running != null) return running;

    final started = () async {
      _lines.add(CallLine.her(clean));
      _notify();
      try {
        await _speak(clean);
      } on OpenAiFailure catch (e) {
        // เจ้าของกดส่งแล้วไม่มีอะไรเกิดขึ้นคือสิ่งที่แย่ที่สุดตรงนี้
        // เขาจะกดซ้ำ แล้วเธอจะพูดสองรอบถ้ามันกลับมาทำงานพอดี
        _error = e.message;
        _notify();
      } on Object catch (e) {
        debugPrint('สาย: พูดประโยคที่พิมพ์ไม่สำเร็จ — $e');
        _error = _state.s.errTtsFailed;
        if (_turn == CallTurn.talking) _turn = CallTurn.none;
        _notify();
      }
    }();
    _saying = started;
    return started.whenComplete(() => _saying = null);
  }

  Future<void>? _saying;

  // ── บทสนทนา ─────────────────────────────────────────────

  /// 🔴 รอบเงียบติดกันกี่รอบถึงจะสรุปว่าเครื่องนี้ไม่ให้ฟัง
  ///
  /// สองรอบไม่พอ — คนที่รับสายแล้วรอให้อีกฝั่งพูดก่อนก็เงียบสองรอบได้
  /// สามรอบ (~30 วินาทีของความเงียบสนิทระดับสัญญาณ ไม่ใช่แค่ไม่มีคำพูด)
  /// แยกสองอย่างนี้ออกจากกันได้จริง เพราะห้องเงียบยังมีเสียงพื้น
  static const _deafAfter = 3;

  int _silentRounds = 0;

  /// 🔴 ห่อทั้งวงไว้ ไม่ใช่ห่อเฉพาะประโยคแรก
  ///
  /// เมธอดนี้ถูกเรียกแบบไม่รอผล (สายไม่ควรค้างรอบทสนทนา) ซึ่งแปลว่า
  /// ข้อผิดพลาดที่หลุดออกไปจะกลายเป็น unhandled async error ที่ไม่มีใคร
  /// เห็นนอกจาก log · การสังเคราะห์เสียงล้มกลางสายเป็นเรื่องที่เกิดได้จริง
  /// (เน็ตหลุดตอนขับรถ) และตอนนั้นเจ้าของต้องเห็นว่าเกิดอะไรขึ้น
  Future<void> _converse() async {
    try {
      // คุยสด (OpenAI Realtime) ก่อน ถ้าตั้งไว้ · ต่อไม่ได้ = ทางเดิม · หลุดกลางสาย =
      // ทางเดิมต่อจากที่ค้าง (ไม่ทักซ้ำ)
      var greeted = false;
      var done = false;
      if (_state.realtimeCallsReady) {
        final r = await _talkRealtime();
        greeted = r != _RtResult.couldNotStart;
        done = r == _RtResult.ended;
      }
      if (!done && _live && _mind && !_disposed) await _talk(greet: !greeted);
    } on OpenAiFailure catch (e) {
      _error = e.message;
    } on Object catch (e) {
      // 🔴 Object ไม่ใช่ Exception · TypeError จากคำตอบหน้าตาแปลกของ
      // พร็อกซี/เซิร์ฟเวอร์ในบ้านเป็น Error · หลุดไปแล้วจอสายค้าง
      // "กำลังคิด…" ทั้งสาย ทั้งที่เธอเงียบไปแล้ว
      debugPrint('สาย: บทสนทนาสะดุด — $e');
      _error = _state.s.errBrainUnexpected;
    }
    // จบวงแล้วแต่สายยังอยู่ = เธอเงียบรอเจ้าของพิมพ์ ไม่ใช่ค้างที่ขั้นไหนสักขั้น
    // (handedOver เป็นของเจ้าของ ห้ามเขียนทับ)
    if (_turn != CallTurn.handedOver) _turn = CallTurn.none;
    _notify();
  }

  // ── คุยสด (OpenAI Realtime) ─────────────────────────────
  //
  // ดู realtime_call.dart · ไมค์เปิดค้างทั้งสายอยู่แล้ว ([_mic]) → ส่งเข้าเซสชัน
  // **ยกเว้นตอนเสียงเธอยังออกลำโพง** (ลำโพง/ไมค์เดียวกัน ส่งไปเธอจะได้ยินตัวเองแล้ว
  // ตอบตัวเอง) · เสียงเธอเป็นชิ้น PCM ส่งเข้าช่องเสียงสดของเนทีฟทันทีที่มาถึง

  RealtimeCall? _rt;
  Completer<void>? _rtEnded;

  /// เธอกำลังตอบอยู่ (ตั้งแต่เซิร์ฟเวอร์เริ่มคำตอบจนจบ) — เสียงอาจยังค้างในลำโพงหลังนี้
  bool _rtResponding = false;

  /// กั้นไมค์ไม่ให้เข้าเซสชัน · เริ่มที่กั้น (เธอกำลังจะทัก)
  bool _rtGated = true;
  bool _rtLips = false;
  DateTime _rtOpenAt = DateTime(0);

  /// จบเซสชันคุยสด (สายจบ / เจ้าของแทรกสาย / ทิ้งตัวนี้)
  void _endRealtime() {
    final e = _rtEnded;
    if (e != null && !e.isCompleted) e.complete();
  }

  Future<_RtResult> _talkRealtime() async {
    final rt = _state.openRealtimeCall();
    final ended = Completer<void>();
    var dropped = false;
    _rt = rt;
    _rtEnded = ended;
    _rtResponding = false;
    _rtGated = true;

    rt.onAudio = (pcm) {
      unawaited(_invoke('liveAudioWrite', {'pcm': pcm}));
    };
    rt.onResponseStart = () {
      _rtResponding = true;
      _rtGated = true;
    };
    rt.onResponseDone = () {
      _rtResponding = false;
    };
    rt.onHerText = (t) {
      _lines.add(CallLine.her(t));
      _notify();
    };
    rt.onCallerText = (t) {
      _lines.add(CallLine.them(t));
      _heardRounds++;
      _turn = CallTurn.thinking;
      _notify();
    };
    rt.onError = (m) {
      if (!rt.connected && !ended.isCompleted) {
        dropped = true;
        ended.complete();
      }
    };
    // ลากันแล้ว = วางสายเมื่อเสียงลาของเธอออกลำโพงหมด (ดูนาฬิกาข้างล่าง)
    var hangWhenQuiet = false;
    rt.onEndCall = () => hangWhenQuiet = true;
    rt.onAlertOwner = (reason) => unawaited(_state.alertOwner(who: _who, reason: reason));

    if (await _invoke<bool>('liveAudioStart', {'stream': _state.callStream}) != true) {
      _rt = null;
      return _RtResult.couldNotStart;
    }
    try {
      await rt.start();
    } on Object catch (e) {
      debugPrint('สาย: คุยสดต่อไม่ได้ ใช้ทางเดิม — ${e.runtimeType}');
      await _invoke('liveAudioStop');
      await rt.close();
      _rt = null;
      return _RtResult.couldNotStart;
    }

    _rounds = 1;
    final started = DateTime.now();
    if (!await _openMic()) _markDeaf();
    _onChunk = (chunk, level) {
      _micLevel = level;
      if (!_rtGated) rt.sendMic(chunk);
    };
    _turn = CallTurn.talking;
    _notify();

    // ฟังลำโพงเนทีฟว่าเสียงเธอหมดหรือยัง → เปิด/ปิดไมค์ · ปาก · สถานะบนจอ
    var busy = false;
    final tick = Timer.periodic(const Duration(milliseconds: 150), (_) async {
      if (busy || ended.isCompleted) return;
      busy = true;
      try {
        final pending = await _invoke<int>('liveAudioPending') ?? 0;
        final now = DateTime.now();
        final speaking = _rtResponding || pending > 0;
        if (speaking) _rtOpenAt = now.add(_echoTail);
        _rtGated = speaking || now.isBefore(_rtOpenAt);

        // เธอขอวางสายแล้ว และประโยคลาพูดจบแล้ว · กันไว้ห้าวินาทีแรก (โมเดลเรียกพลาดตอนทัก)
        if (hangWhenQuiet && !speaking && now.difference(started) > const Duration(seconds: 5)) {
          hangWhenQuiet = false;
          unawaited(hangUp());
          return;
        }

        if (speaking != _rtLips) {
          _rtLips = speaking;
          unawaited(_lips?.setBabble(speaking));
        }
        final turn = speaking
            ? CallTurn.talking
            : (_turn == CallTurn.thinking ? CallTurn.thinking : CallTurn.listening);
        if (turn != _turn && _turn != CallTurn.handedOver) {
          _turn = turn;
          _notify();
        }
        // เงียบสนิทระดับสัญญาณนานเกิน = เครื่องไม่ให้ฟัง (ส่วนใหญ่: ยังไม่เปิดการช่วยเหลือพิเศษ)
        if (!_deaf && _peakEver < _floorMin && now.difference(started) > const Duration(seconds: 25)) {
          _markDeaf();
        }
      } finally {
        busy = false;
      }
    });

    await ended.future;
    tick.cancel();
    _onChunk = null;
    if (_rtLips) {
      _rtLips = false;
      unawaited(_lips?.setBabble(false));
    }
    await rt.close();
    if (identical(_rt, rt)) _rt = null;
    await _invoke('liveAudioStop');
    return dropped && _live && _mind && !_disposed ? _RtResult.dropped : _RtResult.ended;
  }

  Future<void> _talk({bool greet = true}) async {
    if (greet) await _speak(_state.callGreeting(), remember: true);

    while (_live && _mind && !_disposed) {
      // 🔴 เจ้าของพิมพ์ให้เธอพูดอยู่ ([say]) = รอให้พูดจบก่อนค่อยเปิดไมค์
      // · [say] ปิดเทิร์นการฟังทันที ถ้าวนกลับมาฟังเลย ไมค์จะได้ยินเสียง
      // เธอเองจากลำโพง แล้วเธอตอบตัวเอง
      final saying = _saying;
      if (saying != null) await saying;
      if (!_live || !_mind || _disposed) break;

      final heard = await _listen();
      if (!_live || !_mind || _disposed) break;

      // เทิร์นนี้ถูก [say] ตัดกลางคัน — ให้ประโยคของเจ้าของจบก่อนค่อยตอบ
      // ไม่งั้นเสียงสองประโยคชนกัน ฝั่งเนทีฟตัดตัวแรกทิ้งแล้วขึ้นเตือนว่าเปิดลำโพงไม่ได้
      final cutIn = _saying;
      if (cutIn != null) await cutIn;
      if (!_live || !_mind || _disposed) break;

      if (heard == null || heard.isEmpty) {
        if (_deaf) break; // เครื่องนี้ไม่ให้ฟัง — เหลือทางพิมพ์อย่างเดียว
        continue;
      }

      _lines.add(CallLine.them(heard));
      _turn = CallTurn.thinking;
      _notify();

      final reply = await _state.replyOnCall([
        for (final l in _lines) (fromHer: l.fromHer, text: l.text),
      ]);
      if (!_live || !_mind || _disposed) break;

      // แท็กท้ายคำตอบ (ทางเดิมไม่มีเครื่องมือ) · ตัดออกก่อนพูด ไม่ให้อ่านวงเล็บออกเสียง
      final c = CallTags.parse(reply);
      if (c.text.isNotEmpty) {
        _lines.add(CallLine.her(c.text));
        _notify();
        await _speak(c.text);
      }
      if (c.urgent != null && !_alertedOwner) {
        _alertedOwner = true;
        unawaited(_state.alertOwner(who: _who, reason: c.urgent!));
      }
      final age = DateTime.now().difference(_startedAt ?? DateTime.now());
      if (c.hangUp && age > const Duration(seconds: 5) && _live && _mind) {
        await hangUp();
        break;
      }
    }
  }

  /// แจ้งเจ้าของเรื่องด่วนไปแล้วในสายนี้ · ครั้งเดียวต่อสาย
  bool _alertedOwner = false;

  /// พูดออกลำโพงให้ไมค์รับเข้าสาย · รอจนเล่นจบจริง
  ///
  /// 🔴 **ห้ามส่งไปที่ WebView** ทั้งที่นั่นเป็นทางเสียงปกติของเธอ
  /// เสียงในสายต้องออกช่องเสียงของสายเท่านั้น ไม่งั้นจะดังซ้อนสองทาง
  /// แล้วก้องกลับเข้าไปในสาย · ปากบนเวทียังขยับตามคำจริง เพราะเวทีเล่น
  /// ไฟล์เดียวกันแบบปิดเสียงเพื่ออ่านคลื่น (ดู [MindLips])
  Future<void> _speak(String text, {bool remember = false}) async {
    if (text.trim().isEmpty) return;
    if (remember) _lines.add(CallLine.her(text));

    _turn = CallTurn.talking;
    _notify();

    // ไมค์ต้องปิดตอนเธอพูด ไม่งั้นจะได้ยินเสียงตัวเองกลับเข้ามาเป็นคำถาม
    await _stopListening();

    final utterance = await _state.speakForCall(text);

    // ปากของเธอบนเวทีอ่านคลื่นจากไฟล์เดียวกันนี้ (เล่นแบบปิดเสียง) · เตรียม
    // ก่อนเช็กซ้ำ เพราะการถอดไฟล์ฝั่งเวทีกินเวลาเหมือนกัน
    final lips = _lips;
    final lipsReady = lips != null &&
        await lips.prepareLips(utterance.bytes, mime: utterance.mime);

    // 🔴 เช็กซ้ำหลังสังเคราะห์ · ระหว่างนั้น (ครึ่งวิถึงหลายวิ) เจ้าของอาจแทรก
    // สายไปแล้ว และเสียงถูกโอนกลับเข้าหูฟังแล้ว · เล่นต่อ = เสียงเธอดังใส่หู
    // เจ้าของที่เพิ่งยกเครื่องขึ้นแนบ ซึ่งเป็นสิ่งที่ [bargeIn] มีไว้กันพอดี
    if (!_live || !_mind || _disposed) {
      await lips?.restLips();
      if (_turn == CallTurn.talking) _turn = CallTurn.none;
      _notify();
      return;
    }

    final file = await _writeTemp(utterance.bytes, _extFor(utterance.mime));

    // ปล่อยปากพร้อมสั่งเล่น ไม่รอ · รอ = ปากออกตัวทีหลังเสียงเสมอ
    if (lipsReady) unawaited(lips.startLips(lead: lipLead));
    final ok = await _invoke<bool>('callSpeak', {
      'path': file.path,
      'stream': _state.callStream,
    });
    // ปิดปากทุกครั้ง ทั้งจบปกติ ถูกแทรกสาย และวางสาย · ไม่ปิด = ปากค้าง
    // พึมพำต่อ (กรณีเตรียมไม่สำเร็จ) ทั้งที่เธอเงียบไปแล้ว
    if (lips != null) unawaited(lips.restLips());

    // 🔴 "เล่นไม่จบ" ไม่ได้แปลว่า "เปิดลำโพงไม่ได้" เสมอไป
    //
    // ฝั่งเนทีฟตอบ false ทั้งตอนเล่นพังจริง **และตอนถูกสั่งหยุดกลางประโยค**
    // ซึ่งเกิดทุกครั้งที่เจ้าของแทรกสายหรือวางสาย · ถ้าไม่แยกสองอย่างนี้
    // ทุกครั้งที่กดแทรกสายจะขึ้นคำเตือนสีแดงว่าปลายสายไม่ได้ยินเธอ
    // ทั้งที่ไม่มีอะไรผิดเลย
    if (ok != true && _live && _mind) _mute = true;

    unawaited(file.delete().catchError((_) => file));

    // 🔴 อย่าเขียนทับ handedOver · [bargeIn] ตั้งสถานะนั้นไว้ **ก่อน** สั่งหยุด
    // เสียง ซึ่งแปลว่าบรรทัดนี้ทำงานทีหลังเสมอ · ไม่กันไว้ = กดแทรกสายแล้ว
    // หน้าจอเด้งกลับไปเป็น "กำลังฟัง" ทั้งที่เจ้าของถือสายอยู่แล้ว
    if (_turn == CallTurn.talking) {
      _turn = (_live && _mind) ? CallTurn.listening : CallTurn.none;
    }
    _notify();
  }

  static String _extFor(String mime) => mime.contains('wav') ? 'wav' : 'mp3';

  Future<File> _writeTemp(Uint8List bytes, String ext) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}'
        'call_${DateTime.now().microsecondsSinceEpoch}.$ext');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  // ── ฟังปลายสาย ──────────────────────────────────────────

  /// ไมค์ของทั้งสาย · เปิดครั้งเดียวตอนเธอเริ่มคุย ปิดตอนสายจบ/เจ้าของแทรกสาย
  ///
  /// 🔴 เดิมเปิด-ปิดไมค์ทุกเทิร์น (ปิดตอนเธอพูด) · เปิดใหม่แต่ละครั้งกินเวลา
  /// และคำแรกของคู่สายหายไปกับช่วงนั้น · ตอนนี้ไมค์เปิดค้าง ตอนเธอพูดแค่
  /// **ไม่ฟัง** (ไม่ส่งให้ตัวจับประโยค) · ได้เสียงทั้งสายต่อเนื่องสำหรับบันทึกด้วย
  StreamSubscription<Uint8List>? _mic;

  /// ผู้รับก้อนเสียงของเทิร์นที่กำลังฟังอยู่ · null = ตอนนี้ไม่ฟัง (เธอพูด/คิด)
  void Function(Uint8List chunk, double level)? _onChunk;

  /// อัดเสียง 16 บิต ช่องเดียว 16 kHz = 32,000 ไบต์ต่อวินาที
  static const _rate = 16000;
  static const _bytesPerSecond = _rate * 2;

  /// เพดานหนึ่งเทิร์น · ยาวกว่านี้คือคนพูดยาวจนเธอควรตอบได้แล้ว
  static const _maxTurn = Duration(seconds: 20);

  /// เงียบนานเท่านี้หลังเริ่มพูดแล้ว = จบประโยค
  ///
  /// สั้นลงจาก 1.1 วิ · เจ้าของ: "ควรฟังแล้วโต้ตอบได้เหมือนแอป ChatGPT โต้ตอบสดๆ"
  /// ทุกส่วนที่รอได้ต้องสั้น · ต่ำกว่านี้เริ่มตัดคนที่หยุดหายใจกลางประโยค
  static const _endOfSpeech = Duration(milliseconds: 800);

  /// หลังเธอพูดจบ ไม่ฟังช่วงสั้น ๆ นี้ · เสียงเธอยังก้องในห้อง/ลำโพงยังปล่อยหาง
  /// ถ้าฟังทันที เธอจะได้ยินหางเสียงตัวเองเป็นคำพูดของคู่สาย
  static const _echoTail = Duration(milliseconds: 250);

  /// ไม่มีใครพูดเลยนานเท่านี้ = รอบนี้ไม่ได้อะไร
  static const _patience = Duration(seconds: 10);

  /// ระดับที่นับว่าเป็นเสียงพูด — เทียบกับพื้นเสียงที่วัดได้จริง ไม่ใช่ค่าคงที่
  ///
  /// ค่าคงที่ใช้ไม่ได้เพราะสายที่เปิดลำโพงในรถกับในห้องเงียบ พื้นเสียง
  /// ต่างกันหลายเท่า · แต่ยังต้องมีพื้นขั้นต่ำ ไม่งั้นในห้องเงียบสนิท
  /// สัญญาณรบกวนระดับบิตสุดท้ายจะถูกนับเป็นคำพูด
  static const _floorMin = .012;

  /// เปิดไมค์ของทั้งสาย (ถ้ายังไม่เปิด) · false = เปิดไม่ได้ / ไม่มีสิทธิ์
  Future<bool> _openMic() {
    if (_mic != null) return Future.value(true);
    // 🔴 เปิดพร้อมกันสองทาง (ตอนเริ่มสาย + ตอนเริ่มคุย) = ปลั๊กอินอัดสองสตรีมซ้อน ·
    // คนมาทีหลังรอคำตอบของคนแรก
    return _opening ??= _doOpenMic().whenComplete(() => _opening = null);
  }

  Future<bool>? _opening;

  Future<bool> _doOpenMic() async {
    if (!await _canListen()) return false;
    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _rate,
          numChannels: 1,
          // 🔴 ทุกค่าที่นี่เลือกมาเพื่อ**ไม่ไปแตะเสียงของสายที่กำลังคุยอยู่**
          //
          // voiceRecognition — แหล่งที่ปิดตัวตัดเสียงก้องกับตัวลดเสียงรบกวน
          //   ซึ่งเป็นสองตัวที่จะลบเสียงคู่สายที่ออกลำโพงมาทิ้งพอดี
          // audioManagerMode ต้องเป็น modeNormal — ปลั๊กอินจะตั้ง
          //   AudioManager.mode ก่อนอัด · บังคับ modeInCommunication ระหว่าง
          //   สายจริงคือการยึดเส้นทางเสียงของสายไปทั้งเส้น สายจะเงียบทันที
          // manageBluetooth false — เปิด SCO ระหว่างสายคือย้ายสายไปหูฟัง
          //   ที่อาจไม่ได้ใส่อยู่
          // muteAudio false — เราต้องการเสียงลำโพง ไม่ใช่ปิดมันทิ้ง
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceRecognition,
            audioManagerMode: AudioManagerMode.modeNormal,
            manageBluetooth: false,
            muteAudio: false,
            speakerphone: false,
          ),
        ),
      );
      _mic = stream.listen(
        (chunk) {
          _recSink?.add(chunk);
          _recBytes += chunk.length;
          final level = levelOf(chunk);
          if (level > _peakEver) _peakEver = level;
          final turn = _onChunk;
          if (turn != null) {
            turn(chunk, level);
          } else {
            _micLevel = 0; // ไม่ได้ฟังอยู่ · แถบบนจอไม่ควรเต้น
          }
        },
        onError: (Object e) {
          debugPrint('สาย: ไมค์ขัดข้อง — $e');
          _mic = null;
          _endTurn?.call();
        },
        onDone: () {
          _mic = null;
          _endTurn?.call();
        },
        cancelOnError: true,
      );
      return true;
    } on MissingPluginException {
      return false;
    } on Exception catch (e) {
      debugPrint('สาย: เปิดไมค์ไม่ได้ — $e');
      return false;
    }
  }

  Future<String?> _listen() async {
    if (!await _openMic()) {
      _markDeaf();
      return null;
    }

    _turn = CallTurn.listening;
    _rounds++;
    _notify();

    final pcm = BytesBuilder(copy: false);
    final done = Completer<void>();
    var quiet = 0.0;
    var loud = 0.0;
    var speechStarted = false;
    var peak = 0.0;
    DateTime? lastLoud;
    final startedAt = DateTime.now();
    final deafUntil = startedAt.add(_echoTail);

    void finish() {
      if (!done.isCompleted) done.complete();
    }

    // ให้ [_stopListening] ปิดเทิร์นนี้ได้ · ไม่มีทางนี้ เทิร์นจะค้างรอจนหมดเวลา
    // 22 วิ ระหว่างนั้นจอบอก "กำลังฟัง" และทุกอย่างที่คู่สายพูดหายไปหมด
    _endTurn = finish;

    _onChunk = (chunk, level) {
      final now = DateTime.now();
      _micLevel = level;
      if (now.isBefore(deafUntil)) return; // หางเสียงของเธอเอง
      if (pcm.length < _bytesPerSecond * _maxTurn.inSeconds) pcm.add(chunk);
      if (level > peak) peak = level;

      // พื้นเสียง = ค่าต่ำสุดที่เคยเห็น · ไต่ขึ้นช้า ๆ กันการล็อกค่าไว้
      // ที่ศูนย์ตลอดกาลเมื่อชิ้นแรกบังเอิญเป็นความเงียบสนิท
      quiet = quiet == 0 ? level : math.min(quiet * 1.02, level);
      loud = math.max(_floorMin, quiet * 3.5);

      if (level > loud) {
        speechStarted = true;
        lastLoud = now;
      }

      if (speechStarted && lastLoud != null && now.difference(lastLoud!) > _endOfSpeech) {
        finish();
      } else if (!speechStarted && now.difference(startedAt) > _patience) {
        finish();
      } else if (now.difference(startedAt) > _maxTurn) {
        finish();
      }

      _notify();
    };

    try {
      await done.future.timeout(_maxTurn + const Duration(seconds: 2), onTimeout: () {});
    } finally {
      if (identical(_endTurn, finish)) _endTurn = null;
      _onChunk = null;
      _micLevel = 0;
    }

    // 🔴 ตัดสินจาก**ระดับเสียงที่วัดได้** ไม่ใช่จากข้อความที่ถอดได้
    //
    // เครื่องที่ไม่ให้อัดระหว่างสายคืนไฟล์ครบ ขนาดถูกต้อง แต่ทุกตัวอย่าง
    // เป็นศูนย์ · ถ้าดูแต่ผลถอดเสียง จะแยกไม่ออกจาก "ปลายสายไม่ได้พูด"
    // แล้วเราจะยิงค่าใช้จ่ายการถอดเสียงทิ้งไปเรื่อย ๆ โดยไม่มีวันได้อะไร
    if (peak < _floorMin) {
      _silentRounds++;
      if (_silentRounds >= _deafAfter) _markDeaf();
      _notify();
      return null;
    }
    _silentRounds = 0;

    if (!speechStarted) return null;
    _heardRounds++;

    final bytes = pcm.takeBytes();
    if (bytes.length < _bytesPerSecond ~/ 3) return null; // สั้นกว่า 0.3 วิ

    try {
      final text = await _state.transcribeCall(wavOf(bytes));
      return text.isEmpty ? null : text;
    } on OpenAiFailure catch (e) {
      _error = e.message;

      // 🔴 ถอดเสียงไม่ได้ = หูดับ ต้องหยุดวน ไม่ใช่ลองใหม่ไปเรื่อย ๆ
      //
      // เดิม `_deaf` ถูกตั้งจากสิทธิ์ไมค์หรือเสียงเบาเกินเท่านั้น การถอดเสียง
      // ที่ล้ม (ไม่มีคีย์ / คีย์ผิด / เน็ตหลุด) จึงคืน null แล้ววนอัดตาเดิม
      // ซ้ำไม่รู้จบจนกว่าปลายสายจะวาง — เธอเงียบไปทั้งสาย
      //
      // เป็นทางที่คนส่วนใหญ่เจอจริง เพราะรับสายอัตโนมัติเปิดมาตั้งแต่ต้น
      // และสมองดีฟอลต์คือในเครื่อง ซึ่งไม่มีคีย์ OpenAI ให้ถอดเสียงอยู่แล้ว
      _markDeaf();
      _notify();
      return null;
    }
  }

  Future<bool> _canListen() async {
    await _perms.refresh();
    return _perms.of(MindPermission.mic);
  }

  void _markDeaf() {
    if (_deaf) return;
    _deaf = true;
    _micLevel = 0;
    // 🔴 สาเหตุที่พบบ่อยที่สุดบอกได้ตรง ๆ · Android 10+ ให้ความเงียบกับแอปที่อัด
    // ระหว่างสาย เว้นแต่เปิดบริการการช่วยเหลือพิเศษ (android MindAccessibility.kt)
    if (!_perms.of(MindPermission.accessibility)) _error = _state.s.callNeedsA11y;
    _notify();
  }

  /// ปิดเทิร์นการฟังที่ค้างอยู่ — ดู [_listen]
  void Function()? _endTurn;

  /// เลิกฟังเทิร์นนี้ · **ไมค์ยังเปิดอยู่** (ดู [_mic]) ปิดจริงที่ [_closeMic]
  Future<void> _stopListening() async {
    final end = _endTurn;
    _endTurn = null;
    _onChunk = null;
    end?.call();
    _micLevel = 0;
  }

  /// ปิดไมค์ของทั้งสาย — สายจบ / เจ้าของแทรกสาย / ทิ้งตัวนี้
  Future<void> _closeMic() async {
    await _stopListening();
    final sub = _mic;
    _mic = null;
    await sub?.cancel();
    _micLevel = 0;

    // 🔴 อ่านตัวแปรตรง ๆ ไม่ใช่ผ่าน getter
    //
    // getter จะ **สร้าง** ตัวอัดเสียงขึ้นมาใหม่เพื่อสั่งหยุดสิ่งที่ไม่เคย
    // เริ่ม · [_stopListening] ถูกเรียกทุกครั้งที่สายจบและทุกครั้งก่อนเธอพูด
    // ซึ่งแปลว่าปลั๊กอินไมค์จะถูกปลุกขึ้นมาเปล่า ๆ แม้ในสายที่ไม่เคยฟังเลย
    final rec = _lazyRecorder;
    if (rec == null) return;

    try {
      if (await rec.isRecording()) await rec.stop();
    } on MissingPluginException {
      // ไม่ใช่ Android — ไม่ใช่ความผิดพลาด
      // ต้องดักก่อน Exception เสมอ มันเป็นลูกของ Exception
    } on Exception catch (e) {
      debugPrint('สาย: ปิดไมค์ไม่สนิท — $e');
    }
  }

  /// ระดับเสียงเฉลี่ยกำลังสองของก้อนตัวอย่าง 16 บิต · 0..1
  ///
  /// เป็น public เพื่อให้เทสต์ยิงตรงได้ · ตรรกะแยกเสียงพูดออกจากความเงียบ
  /// คือจุดที่ทั้งฟีเจอร์ตัดสินว่า "เครื่องนี้ให้ฟังไหม" ปล่อยให้ทดสอบ
  /// ผ่านสายจริงอย่างเดียวไม่ได้
  static double levelOf(Uint8List chunk) {
    if (chunk.length < 2) return 0;
    final samples = chunk.buffer.asInt16List(
      chunk.offsetInBytes,
      chunk.lengthInBytes ~/ 2,
    );
    var sum = 0.0;
    for (final s in samples) {
      final v = s / 32768.0;
      sum += v * v;
    }
    return math.sqrt(sum / samples.length);
  }

  /// ห่อ PCM ดิบด้วยหัวไฟล์ WAV · public เพื่อให้เทสต์ยิงตรงได้
  ///
  /// ปลายทางรับ **ไฟล์** ไม่ใช่ตัวอย่างดิบ · ส่ง PCM เปล่า ๆ ไปจะได้ 400
  /// ที่อ่านว่า "รูปแบบไฟล์ไม่รองรับ" ซึ่งชี้ไปผิดทางว่าเสียงมีปัญหา
  static Uint8List wavOf(Uint8List pcm, {int rate = _rate}) {
    final out = BytesBuilder();
    void ascii(String v) => out.add(v.codeUnits);
    void u32(int v) =>
        out.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
    void u16(int v) => out.add([v & 255, (v >> 8) & 255]);

    ascii('RIFF');
    u32(36 + pcm.length);
    ascii('WAVE');
    ascii('fmt ');
    u32(16); // ความยาวของก้อน fmt
    u16(1); // PCM ไม่บีบอัด
    u16(1); // ช่องเดียว
    u32(rate);
    u32(rate * 2); // ไบต์ต่อวินาที
    u16(2); // ไบต์ต่อหนึ่งเฟรม
    u16(16); // บิตต่อตัวอย่าง
    ascii('data');
    u32(pcm.length);
    out.add(pcm);
    return out.toBytes();
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      debugPrint('สาย: $method ไม่สำเร็จ — $e');
      return null;
    } on MissingPluginException {
      return null; // ไม่ใช่ Android — ไม่ใช่ความผิดพลาด
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  // ── บันทึกเสียงสนทนา ─────────────────────────────────────
  //
  // เจ้าของ: "ทำให้บันทึกเสียงสนทนาไว้ได้ด้วย" · ไมค์เปิดค้างทั้งสายอยู่แล้ว
  // ([_mic]) จึงเขียนทุกก้อนลงไฟล์ WAV เดียว · เก็บในเครื่องเท่านั้น (ไม่ขึ้นสำเนา
  // ไม่ขึ้นคลาวด์) ลบพร้อมบันทึกสาย · เธอบอกคู่สายตอนทักว่ามีการบันทึก

  IOSink? _recSink;
  File? _recFile;
  int _recBytes = 0;

  Future<void> _startRecording() async {
    if (_recSink != null || !_state.recordCalls) return;
    try {
      final dir = await CallRecordings.dir();
      // เสียงดิบระหว่างสาย · ห่อเป็น WAV ตอนจบ (ตอนนั้นถึงรู้ขนาด)
      final f = File('${dir.path}${Platform.pathSeparator}rec-${DateTime.now().microsecondsSinceEpoch}.pcm');
      _recFile = f;
      _recBytes = 0;
      _recSink = f.openWrite();
    } on Object catch (e) {
      debugPrint('สาย: เริ่มบันทึกเสียงไม่ได้ — ${e.runtimeType}');
      _recSink = null;
      _recFile = null;
    }
  }

  /// ปิดไฟล์ แก้ขนาดในหัวไฟล์ · คืนไฟล์ หรือ null ถ้าสั้นเกินจะมีความหมาย
  Future<File?> _finishRecording() async {
    final sink = _recSink;
    final file = _recFile;
    final bytes = _recBytes;
    _recSink = null;
    _recFile = null;
    _recBytes = 0;
    if (sink == null || file == null) return null;
    try {
      await sink.flush();
      await sink.close();
      final pcmLen = await file.length();
      if (bytes < _bytesPerSecond || pcmLen < _bytesPerSecond) {
        await file.delete();
        return null;
      }
      // หัวไฟล์ที่รู้ขนาดแล้ว + เสียงดิบทั้งก้อน (สตรีมต่อ ไม่โหลดทั้งไฟล์เข้าหน่วยความจำ)
      final wav = File(file.path.replaceFirst(RegExp(r'\.pcm$'), '.wav'));
      final header = wavOf(Uint8List(0));
      final out = wav.openWrite();
      try {
        out.add(header.sublist(0, 4));
        out.add(_u32(36 + pcmLen));
        out.add(header.sublist(8, 40));
        out.add(_u32(pcmLen));
        await out.addStream(file.openRead());
      } finally {
        await out.close();
      }
      await file.delete();
      return wav;
    } on Object catch (e) {
      debugPrint('สาย: ปิดไฟล์บันทึกเสียงไม่ได้ — ${e.runtimeType}');
      return null;
    }
  }

  static Uint8List _u32(int v) =>
      Uint8List.fromList([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);

  @visibleForTesting
  Future<File?> debugRecord(List<Uint8List> chunks) async {
    await _startRecording();
    for (final c in chunks) {
      _recSink?.add(c);
      _recBytes += c.length;
    }
    return _finishRecording();
  }

  // ── ตัวเลขของสายนี้ (ไม่มีเนื้อหา ไม่มีเบอร์) · ส่งรายงานเองเมื่อสายมีปัญหา ──

  int _rounds = 0;
  int _heardRounds = 0;
  double _peakEver = 0;

  /// สายที่เธอถือแล้วมีอะไรผิด → จดเป็นเหตุการณ์ให้รายงานส่งเอง
  ///
  /// 🔴 เจ้าของ: "รับแล้ว แต่ไม่ยอมพูดตอบโต้อะไรเลย" · ไม่มีรายงานสักฉบับ เพราะ
  /// ไม่มีอะไร "ล้ม" — เธอแค่ได้ยินความเงียบ · ตัวเลขชุดนี้บอกได้ว่าเงียบเพราะ
  /// เครื่องไม่ให้ฟัง (peak≈0) เสียงเธอไปไม่ถึง (mute) หรือคู่สายไม่พูด
  void _reportCall() {
    final a11y = _perms.of(MindPermission.accessibility);
    final line = 'call: rounds=$_rounds heard=$_heardRounds '
        'peak=${_peakEver.toStringAsFixed(3)} deaf=$_deaf mute=$_mute a11y=$a11y '
        'stream=${_state.callStream}';
    debugPrint(line);
    if (_deaf || _mute || (_rounds > 0 && _heardRounds == 0)) _state.noteIncident(line);
    _rounds = 0;
    _heardRounds = 0;
    _peakEver = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _watch.removeListener(_onWatch);
    _endRealtime();
    unawaited(_closeMic());
    unawaited(_finishRecording());
    _lazyRecorder?.dispose();
    super.dispose();
  }
}
