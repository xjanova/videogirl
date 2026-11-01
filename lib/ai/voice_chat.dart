/// คุยต่อเนื่องด้วยเสียงในแชท — แตะไมค์ครั้งเดียว แล้วคุยกันไปเรื่อย ๆ ไม่ต้องกดส่ง
///
/// ## ทำไม
///
/// เจ้าของ: "การกดไมค์พูดกับเธอควรพูดโต้ตอบได้เรียลไทม์ เหมือนที่เราทำกับการรับสาย และต้องเข้าใจว่า
/// บริบทไหนที่เราหยุดให้เธอปฏิบัติได้ เช่นพูดแล้วหยุดเว้นให้เธอคิดได้เลย ไม่ต้องมากดส่งอีก เพราะเรา
/// ออกแบบให้แอพนี้ใช้งานแม้ในขับรถได้"
///
/// ## สามทาง เลือกเองตามสมองที่ตั้งไว้
///
/// - **live** — OpenAI + คีย์ของเจ้าของ ([MindState.voiceChatLiveReady]) → [RealtimeChat] · เซิร์ฟเวอร์ฟังว่า
///   ประโยคจบหรือยัง (semantic_vad) ไม่ใช่แค่เงียบ · เสียงเธอมาเป็นสตรีม ตอบในเสี้ยววินาที
/// - **turns** — สมองอื่นที่ถอดเสียงได้ → [TurnTaker] ฟังความเงียบ ถอดเสียงล่วงหน้า แล้วดูว่าประโยคจบไหม →
///   ส่งเข้าแชททางเดียวกับการพิมพ์ ([sendTurn]) → เธอตอบด้วยเสียงที่ตั้งไว้
/// - **device** — สมองในเครื่อง → ตัวถอดเสียงของเครื่อง (เสียงไม่ออกนอกเครื่อง · สัญญาของทางนั้น) ·
///   ประโยคค้าง ("แล้วก็…") = ฟังต่ออีกรอบแล้วต่อกัน
///
/// ## 🔴 พูดทีละฝั่ง
///
/// ไมค์กับลำโพงอยู่เครื่องเดียวกัน · ระหว่างที่เธอพูดไมค์ไม่ส่ง (เหมือนในสาย) ไม่งั้นเธอได้ยินเสียงตัวเอง
/// แล้วตอบตัวเอง · อยากให้หยุดกลางประโยค = แตะแถบสถานะ ([interrupt])
///
/// ## 🔴 ปิดเอง
///
/// เงียบนาน · สายเข้า · แอปลงเบื้องหลัง · ออกจากแท็บ · เข้าสตูดิโอ · เจ้าของพูด "พอแล้ว" · เธอลาแล้ว (live) ·
/// ไมค์ที่เปิดค้างโดยไม่มีใครคุยคือเครื่องอัดเสียงในรถ/ในห้อง
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../avatar/stage_bridge.dart';
import '../i18n/strings_ai.dart';
import '../phone/call_session.dart';
import '../phone/call_target.dart';
import '../state/mind_state.dart';
import '../system/permissions.dart';
import 'device_speech.dart';
import 'openai_client.dart';
import 'realtime_chat.dart';
import 'turn_taking.dart';

/// ตอนนี้อยู่ขั้นไหน · แถบสถานะบนจอบอกตามนี้
enum VoiceChatPhase {
  off,

  /// ขอสิทธิ์ / ต่อเซิร์ฟเวอร์ / เปิดไมค์
  opening,

  /// รอเจ้าของพูด
  listening,

  /// เจ้าของกำลังพูด
  hearing,

  /// เธอกำลังคิด / ใช้เครื่องมือ
  thinking,

  /// เสียงเธอกำลังออกลำโพง · แตะให้หยุดได้
  speaking,
}

enum VoiceChatEngine { live, turns, device }

/// ไมค์ของโหมดคุยต่อเนื่อง · แยกเป็น interface ให้เทสต์ป้อนเสียงเองได้
abstract interface class ChatMic {
  /// PCM 16 บิต 16 kHz ช่องเดียว
  Future<Stream<Uint8List>> open();
  Future<void> close();
  void dispose();
}

class RecordChatMic implements ChatMic {
  /// สร้างตอนใช้จริงเท่านั้น · AudioRecorder ผูก MethodChannel ตั้งแต่ constructor
  AudioRecorder? _rec;
  AudioRecorder get _r => _rec ??= AudioRecorder();

  @override
  Future<Stream<Uint8List>> open() => _r.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: VoiceChat.rate,
          numChannels: 1,
          // ไม่มีสาย ไม่มีเสียงคู่สายให้ถนอม · ตัดเสียงก้อง/เสียงรบกวนช่วยในรถ
          echoCancel: true,
          noiseSuppress: true,
          // ไม่ขอ audio focus · ขอแล้วเพลง/นำทางในรถเงียบทั้งช่วงที่คุย และเสียงเธอเอง (เสียงสื่อ) ถูกกดตาม
          audioInterruption: AudioInterruptionMode.none,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceRecognition,
            // เปิด SCO = ย้ายเสียงรถไปโหมดโทรศัพท์ (เพลงหยุด คุณภาพเสียงตก) · ใช้ไมค์ของเครื่อง
            manageBluetooth: false,
          ),
        ),
      );

  @override
  Future<void> close() async {
    final r = _rec;
    if (r == null) return;
    try {
      if (await r.isRecording()) await r.stop();
    } on Object catch (e) {
      debugPrint('voice chat: หยุดไมค์ไม่สำเร็จ — ${e.runtimeType}');
    }
  }

  @override
  void dispose() {
    final r = _rec;
    if (r != null) unawaited(r.dispose());
  }
}

class VoiceChat extends ChangeNotifier {
  VoiceChat({
    required this.state,
    required this.sendTurn,
    required this.ensureMic,
    this.lips,
    this.keepAwake,
    this.callActive,
    Future<String> Function(Uint8List wav)? transcribe,
    ChatMic? mic,
    MethodChannel? channel,
    DateTime Function()? clock,
  })  : _transcribeWav = transcribe ?? state.transcribeChat,
        _mic = mic ?? RecordChatMic(),
        _ch = channel ?? kSystemChannel,
        _clock = clock ?? DateTime.now;

  final MindState state;

  /// ส่งหนึ่งตาเข้าแชท ทางเดียวกับการพิมพ์ (หน้าแชท `_sendText`) · จบเมื่อเธอตอบและพูดจบแล้ว
  final Future<void> Function(String text) sendTurn;

  /// ขอสิทธิ์ไมค์ · true = ใช้ได้
  final Future<bool> Function() ensureMic;

  /// ปากของเธอสำหรับเสียงสด (เสียงออกทางเนทีฟ ไม่ใช่เวที)
  final MindLips? lips;

  /// เปิด/ปิดจอค้าง · ขับรถอยู่จอดับ = แอปลงเบื้องหลัง = ไมค์ถูกปิด
  final Future<void> Function(bool on)? keepAwake;

  /// มีสายที่เธอถืออยู่ไหม · มี = ไม่ปิดช่องเสียงสด (สายรับช่วงช่องเดียวกันไปแล้ว)
  final bool Function()? callActive;

  final Future<String> Function(Uint8List wav) _transcribeWav;
  final ChatMic _mic;
  final MethodChannel _ch;
  final DateTime Function() _clock;

  static const rate = 16000;

  /// หลังเสียงเธอจบ ไม่ฟังช่วงสั้น ๆ นี้ · ลำโพงยังปล่อยหาง ห้องยังก้อง · ในสายใช้ 250 แต่ที่นี่ออกลำโพงสื่อ
  /// และลำโพงรถทางบลูทูธช้ากว่าที่เครื่องรายงานราว 0.2–0.3 วิ · สั้นไป = เธอได้ยินหางเสียงตัวเองเป็นคำของเจ้าของ
  static const echoTail = Duration(milliseconds: 500);

  /// ถอดเสียงหนึ่งตาช้ากว่านี้ = นับว่าล้ม · ไม่งั้นไมค์ค้างรอผลที่ไม่มาโดยไม่มีใครรู้
  static const transcribeLimit = Duration(seconds: 20);

  /// เงียบทั้งสองฝั่งนานเท่านี้ = ปิดไมค์ให้ · คุยสดคิดเงินตามเวลาที่ต่ออยู่ จึงสั้นกว่า
  static const idleLive = Duration(minutes: 2);
  static const idleTurns = Duration(minutes: 4);

  /// ถอดเสียงล้มติดกันเท่านี้ = ปิด (คีย์ผิด เน็ตหลุด) · ไม่วนส่งเสียงไปล้มซ้ำทั้งทาง
  static const maxFailures = 3;

  /// เสียงก่อนเริ่มพูดที่เก็บไว้ · พยางค์แรกเบากว่าเกณฑ์ ไม่เก็บ = ถอดได้ไม่ครบคำ
  static const _preRoll = rate * 2 * 400 ~/ 1000;

  VoiceChatPhase _phase = VoiceChatPhase.off;
  VoiceChatPhase get phase => _phase;
  bool get active => _phase != VoiceChatPhase.off;

  VoiceChatEngine? _engine;
  VoiceChatEngine? get engine => _engine;

  /// ระดับเสียงไมค์ 0..1 · ให้ปุ่มเต้นตามเสียงจริง
  double _level = 0;
  double get level => _level;

  /// คำที่ได้ยินระหว่างพูด (ทางในเครื่องเท่านั้น)
  String _heard = '';
  String get heard => _heard;

  /// รอบการเปิด · เปลี่ยน = งานค้างของรอบเก่าเลิกเอง
  int _seq = 0;
  bool _disposed = false;
  Timer? _tick;
  bool _tickBusy = false;
  StreamSubscription<Uint8List>? _sub;
  DateTime _lastActivity = DateTime(0);
  DateTime _openAt = DateTime(0);
  DateTime _loudAt = DateTime(0);
  bool _gated = false;
  final _loud = _Loudness();

  /// ข้อความแจ้งที่เธอกำลังพูด (ทีละตา/ในเครื่อง) · ระหว่างนี้ไมค์ไม่ฟัง
  int _notices = 0;

  // ── live ──
  RealtimeChat? _rt;
  bool _liveAudio = false;
  bool _responding = false;
  int _toolsRunning = 0;
  bool _endWhenQuiet = false;
  bool _lipsOn = false;
  final _lipFrames = <({double endMs, double level})>[];
  double _lipTotalMs = 0;

  // ── turns / device ──
  final _taker = TurnTaker();
  BytesBuilder _pcm = BytesBuilder(copy: false);
  bool _delivering = false;
  bool _finishPending = false;
  int _failures = 0;

  void _set(VoiceChatPhase p) {
    if (_disposed) return;
    _phase = p;
    notifyListeners();
  }

  void _activity() => _lastActivity = _clock();

  /// เปิดโหมดคุยต่อเนื่อง · เปิดไม่ได้ = เหตุผลขึ้นแถบเดียวกับข้อผิดพลาดอื่น ([MindState.reportError])
  Future<void> start() async {
    if (active || _disposed) return;
    final seq = ++_seq;
    _set(VoiceChatPhase.opening);
    final live = state.voiceChatLiveReady;
    if (!live && !state.canTranscribe) {
      await stop(why: state.whyNoMic);
      return;
    }
    if (!await ensureMic()) {
      if (seq == _seq) await stop(why: state.s.micDenied);
      return;
    }
    if (seq != _seq || _disposed) return;

    state.setHandsFree(true);
    state.onHerNotice = _onNotice;
    _activity();
    _openAt = DateTime(0);
    unawaited(keepAwake?.call(true));
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) => unawaited(_onTick()));

    if (live && await _startLive(seq)) return;
    if (seq != _seq) return;
    if (live) {
      // คุยสดต่อไม่ได้ (เน็ต คีย์ เซิร์ฟเวอร์) · ถอดเสียงได้ = คุยทีละตาแทน ดีกว่าไมค์ที่ไม่ทำอะไร
      if (!state.canTranscribe) {
        await stop(why: state.s.voiceChatLiveLost(fallback: false));
        return;
      }
      state.reportError(state.s.voiceChatLiveLost(fallback: true));
    }
    await _startTurnTaking(seq);
  }

  Future<void> _startTurnTaking(int seq) async {
    if (state.transcribesOnDevice) {
      unawaited(_deviceLoop(seq));
      return;
    }
    if (!await _startTurns(seq) && seq == _seq) await stop(why: state.s.micFailed);
  }

  /// ปิดโหมด · [why] = บอกเจ้าของว่าทำไมไมค์ปิด (ปิดเองไม่ต้องบอก)
  Future<void> stop({String? why}) async {
    if (_phase == VoiceChatPhase.off && _engine == null && _tick == null) {
      if (why != null) state.reportError(why);
      return;
    }
    _seq++;
    final engine = _engine;
    _engine = null;
    _tick?.cancel();
    _tick = null;
    _phase = VoiceChatPhase.off;
    _delivering = false;
    _notices = 0;
    _heard = '';
    _level = 0;
    _resetTurn();
    if (state.onHerNotice == _onNotice) state.onHerNotice = null;
    state.setHandsFree(false);
    if (why != null) state.reportError(why);
    if (!_disposed) notifyListeners();

    await _closeLive();
    await _closeMic();
    if (engine == VoiceChatEngine.device) {
      final d = state.deviceSpeech;
      if (d != null) {
        d
          ..onLevel = null
          ..onPartial = null;
        await d.cancel();
      }
    }
    // ปิดไมค์ = เจ้าของไม่อยากฟังต่อ / สายเข้า · เสียงที่ยังพูดค้างต้องเงียบตาม
    if (state.speaking) await state.hush();
    await keepAwake?.call(false);
  }

  /// เจ้าของแตะให้เธอหยุดพูด · แล้วฟังทันที ไม่ต้องรอหางเสียง
  Future<void> interrupt() async {
    if (!active) return;
    _activity();
    final rt = _rt;
    if (rt != null) {
      await rt.interrupt();
      _responding = false;
    } else {
      await state.hush();
    }
    _openAt = _clock();
  }

  // ═══ live ═══════════════════════════════════════════════

  Future<bool> _startLive(int seq) async {
    final RealtimeChat rt;
    try {
      rt = state.openVoiceChat(tools: _runTool);
    } on Object catch (e) {
      debugPrint('voice chat: สร้างคุยสดไม่ได้ — ${e.runtimeType}');
      return false;
    }
    _rt = rt;
    _engine = VoiceChatEngine.live;
    _responding = false;
    _toolsRunning = 0;
    _endWhenQuiet = false;
    _lipFrames.clear();
    _lipTotalMs = 0;

    rt.onAudio = (pcm) {
      if (!identical(_rt, rt)) return;
      // ชิ้นละ 20 มิลลิวินาที · ปากตามตำแหน่งที่ลำโพงเล่นถึงจริง (เหมือนในสาย)
      for (var offset = 0; offset + 1 < pcm.length; offset += 960) {
        final slice = Uint8List.sublistView(pcm, offset, math.min(offset + 960, pcm.length));
        _lipTotalMs += slice.length * 1000 / 48000;
        _lipFrames.add((endMs: _lipTotalMs, level: CallSession.levelOf(slice)));
      }
      unawaited(_invoke<bool>('liveAudioWrite', {'pcm': pcm}));
    };
    rt.onInterruption = () async {
      final pending = await _invoke<int>('liveAudioPending') ?? 0;
      if (pending <= 0) return 0;
      await _invoke<bool>('liveAudioClear');
      _lipFrames.clear();
      _lipTotalMs = 0;
      _setLips(false);
      _responding = false;
      return pending;
    };
    rt.onResponseStart = () => _responding = true;
    rt.onResponseDone = () => _responding = false;
    rt.onHerText = (t) => state.noteVoiceLine(fromHer: true, text: t);
    rt.onCallerText = (t) => unawaited(_ownerSaid(rt, t));
    // เธอลาแล้ว · ปิดไมค์เมื่อเสียงลาออกลำโพงหมด (ดู [_onTick])
    rt.onEndCall = () => _endWhenQuiet = true;
    rt.onError = (m) {
      if (!identical(_rt, rt) || rt.connected) return;
      unawaited(_liveDropped(seq));
    };

    if (await _invoke<bool>('liveAudioStart', {'usage': 'media'}) != true) {
      _rt = null;
      _engine = null;
      return false;
    }
    _liveAudio = true;
    try {
      await rt.start();
    } on Object catch (e) {
      debugPrint('voice chat: ต่อคุยสดไม่ได้ — ${e.runtimeType}');
      await _closeLive();
      _engine = null;
      return false;
    }
    if (seq != _seq) {
      await _closeLive();
      return true;
    }
    // เซสชันใหม่ไม่รู้ว่าเพิ่งคุยอะไรกันในแชท · ไม่บอก = "เมื่อกี้เรื่องนั้นล่ะ" แล้วเธองง
    final recap = state.voiceChatRecap();
    if (recap.isNotEmpty) rt.remind(recap);
    final ok = await _openMic(seq, (chunk, _) {
      if (!_gated && identical(_rt, rt)) rt.sendMic(chunk);
    });
    if (!ok) {
      await _closeLive();
      _engine = null;
      return false;
    }
    if (seq == _seq) _set(VoiceChatPhase.listening);
    return true;
  }

  /// เจ้าของพูดจบหนึ่งตา (บทจากเซิร์ฟเวอร์)
  Future<void> _ownerSaid(RealtimeChat rt, String text) async {
    _activity();
    state.noteVoiceLine(fromHer: false, text: text);
    if (VoiceStop.matches(text)) {
      await stop();
      return;
    }
    // 🔴 "โทรเลย" / "ยกเลิก" ตัดสินจากคำของเจ้าของเองในเครื่อง ไม่ใช่จากที่โมเดลเข้าใจ
    if (state.pendingCall == null) return;
    final yes = CallReply.confirm(text);
    if (yes == null || !await state.confirmCallByVoice(text)) return;
    if (identical(_rt, rt)) {
      rt.remind(yes
          ? 'The owner said to call. The app is dialing now; you will be on that call.'
          : 'The owner cancelled the call. It was not placed.');
    }
  }

  Future<String> _runTool(String name, Map<String, Object?> args) async {
    _toolsRunning++;
    _activity();
    try {
      return await state.runVoiceTool(name, args);
    } finally {
      _toolsRunning = math.max(0, _toolsRunning - 1);
      _activity();
    }
  }

  /// ท่อคุยสดหลุดกลางทาง · ถอดเสียงได้ = คุยทีละตาต่อ ไม่ให้เจ้าของที่ขับรถอยู่ต้องมาแตะใหม่
  Future<void> _liveDropped(int seq) async {
    if (seq != _seq || _engine != VoiceChatEngine.live) return;
    await _closeLive();
    await _closeMic();
    if (seq != _seq) return;
    if (!state.canTranscribe) {
      await stop(why: state.s.voiceChatLiveLost(fallback: false));
      return;
    }
    state.reportError(state.s.voiceChatLiveLost(fallback: true));
    await _startTurnTaking(seq);
  }

  Future<void> _closeLive() async {
    final rt = _rt;
    _rt = null;
    _responding = false;
    _toolsRunning = 0;
    _endWhenQuiet = false;
    _setLips(false);
    _lipFrames.clear();
    _lipTotalMs = 0;
    if (rt != null) {
      rt
        ..onAudio = null
        ..onInterruption = null
        ..onResponseStart = null
        ..onResponseDone = null
        ..onHerText = null
        ..onCallerText = null
        ..onEndCall = null
        ..onError = null;
      await rt.close();
    }
    if (_liveAudio) {
      _liveAudio = false;
      // สายรับช่วงช่องเสียงสดไปแล้ว (CallAudio มีช่องเดียว) · ปิดตอนนี้ = ปิดเสียงเธอในสาย
      if (!(callActive?.call() ?? false)) await _invoke<bool>('liveAudioStop');
    }
  }

  void _setLips(bool on) {
    if (on == _lipsOn) return;
    _lipsOn = on;
    unawaited(lips?.setBabble(on));
  }

  // ═══ ทีละตา ══════════════════════════════════════════════

  Future<bool> _startTurns(int seq) async {
    _engine = VoiceChatEngine.turns;
    _resetTurn();
    _failures = 0;
    final ok = await _openMic(seq, (chunk, level) => _onTurnChunk(seq, chunk, level));
    if (!ok) return false;
    if (seq == _seq) _set(VoiceChatPhase.listening);
    return true;
  }

  void _resetTurn() {
    _taker.reset();
    _pcm = BytesBuilder(copy: false);
    _finishPending = false;
  }

  void _onTurnChunk(int seq, Uint8List chunk, double level) {
    if (seq != _seq || _engine != VoiceChatEngine.turns) return;
    // เธอคิด/พูดอยู่ หรือรอผลถอดตาที่จบแล้ว = ไม่ฟัง (พูดทีละฝั่ง)
    if (_delivering || _finishPending || _gated) return;
    _pcm.add(chunk);
    if (!_taker.started && _pcm.length > _preRoll * 2) {
      final b = _pcm.takeBytes();
      _pcm = BytesBuilder(copy: false)..add(Uint8List.sublistView(b, b.length - _preRoll));
    }
    switch (_taker.feed(level, _clock().millisecondsSinceEpoch, _pcm.length)) {
      case TurnStep.none:
        break;
      case TurnStep.transcribe:
        unawaited(_transcribe(seq, _pcm.toBytes(), _taker.askedAt));
      case TurnStep.done:
        _endTurn(seq);
      case TurnStep.noise:
        _resetTurn();
    }
  }

  /// จบตาแล้ว · มีผลถอดของเสียงทั้งหมดแล้ว = ส่งเลย · ยังไม่มี = รอผล (หรือขอถอดทั้งหมดตอนนี้)
  void _endTurn(int seq) {
    final t = _taker.text;
    if (t != null) {
      _resetTurn();
      if (t.isNotEmpty) unawaited(_deliver(seq, t));
      return;
    }
    _finishPending = true;
    final bytes = _pcm.length;
    if (_taker.askNow(bytes)) unawaited(_transcribe(seq, _pcm.toBytes(), bytes));
  }

  Future<void> _transcribe(int seq, Uint8List pcm, int forBytes) async {
    var text = '';
    try {
      text = (await _transcribeWav(CallSession.wavOf(pcm, rate: rate)).timeout(transcribeLimit)).trim();
      _failures = 0;
    } on Object catch (e) {
      if (seq != _seq) return;
      // ไม่ลงข้อความดิบ (มี URL / header ได้) · ลงแค่ชนิด
      debugPrint('voice chat: ถอดเสียงไม่สำเร็จ — ${e.runtimeType}');
      final why = e is OpenAiFailure ? e.message : state.s.errBrainUnexpected;
      if (++_failures >= maxFailures) {
        await stop(why: why);
        return;
      }
      state.reportError(why);
    }
    if (seq != _seq) return;
    _taker.heard(text, forBytes);
    if (_finishPending && _taker.askedAt == forBytes) {
      _resetTurn();
      if (text.isNotEmpty) unawaited(_deliver(seq, text));
    }
  }

  /// ส่งหนึ่งตาให้เธอ (ทีละตา/ในเครื่อง) · จบเมื่อเธอตอบและพูดจบ
  Future<void> _deliver(int seq, String text) async {
    if (seq != _seq) return;
    _activity();
    if (VoiceStop.matches(text)) {
      await stop();
      return;
    }
    _delivering = true;
    _set(VoiceChatPhase.thinking);
    try {
      // เธอยังตอบข้อความที่พิมพ์ไว้อยู่ = รอ · ส่งตอนนี้ [MindState.send] คืนงานเดิม คำนี้หายเงียบ
      for (var i = 0; i < 300 && !state.canSend && seq == _seq; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (seq != _seq) return;
      await sendTurn(text);
    } finally {
      if (seq == _seq) {
        _delivering = false;
        _openAt = _clock().add(echoTail);
        _activity();
        _resetTurn();
      }
    }
  }

  // ═══ ในเครื่อง ═══════════════════════════════════════════

  Future<void> _deviceLoop(int seq) async {
    _engine = VoiceChatEngine.device;
    final dev = state.deviceSpeech;
    if (dev == null || !await dev.available()) {
      if (seq == _seq) await stop(why: state.s.micNoOnDevice);
      return;
    }
    if (seq != _seq) return;
    dev
      ..onLevel = (v) {
        if (seq != _seq) return;
        _level = v;
        if (_loud.feed(v)) {
          _loudAt = _clock();
          _activity();
        }
      }
      ..onPartial = (t) {
        if (seq != _seq) return;
        _heard = t;
        _loudAt = _clock();
        _activity();
      };
    final locale = state.s.isThai ? 'th-TH' : 'en-US';
    while (seq == _seq && !_disposed) {
      // เธอพูดอยู่ (คำตอบ / ข้อความแจ้ง) = รอ · ไม่งั้นตัวถอดเสียงได้ยินเสียงเธอเอง
      while (seq == _seq && (_gated || _notices > 0 || state.speaking)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (seq != _seq) return;
      _heard = '';
      _set(VoiceChatPhase.listening);
      var said = (await dev.listen(locale: locale))?.trim() ?? '';
      if (seq != _seq) return;
      if (said.isEmpty) {
        final f = dev.fault;
        // เงียบ / ถูกยกเลิกให้เธอพูด / เครื่องยังไม่ว่าง = ฟังใหม่ · เงียบนานเกิน นาฬิกาปิดไมค์ให้เอง
        if (f == null || f == SttFault.noMatch || f == SttFault.busy) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        await stop(why: _faultText(f));
        return;
      }
      // ตัวถอดเสียงของเครื่องตัดจบเร็วเมื่อเงียบ · ประโยคค้าง = ฟังต่ออีกรอบแล้วต่อกัน
      for (var more = 0; more < 3 && TurnEnd.looksUnfinished(said) && seq == _seq; more++) {
        _heard = '';
        final cut = Timer(_taker.hold, () {
          if (_heard.isEmpty) unawaited(dev.cancel());
        });
        final next = (await dev.listen(locale: locale))?.trim() ?? '';
        cut.cancel();
        if (next.isEmpty) break;
        said = '$said $next';
      }
      if (seq != _seq) return;
      await _deliver(seq, said);
    }
  }

  String _faultText(SttFault f) => switch (f) {
        SttFault.unavailable => state.s.micNoOnDevice,
        SttFault.language => state.s.micNoLanguagePack,
        SttFault.permission => state.s.micDenied,
        SttFault.busy => state.s.micBusy,
        _ => state.s.micFailed,
      };

  // ═══ ร่วมกัน ═════════════════════════════════════════════

  Future<bool> _openMic(int seq, void Function(Uint8List chunk, double level) onChunk) async {
    try {
      final stream = await _mic.open();
      if (seq != _seq) {
        await _mic.close();
        return false;
      }
      _sub = stream.listen(
        (chunk) {
          double level;
          try {
            level = CallSession.levelOf(chunk);
          } on Object {
            level = 0;
          }
          _level = level;
          if (_loud.feed(level) && !_gated) {
            _loudAt = _clock();
            _activity();
          }
          onChunk(chunk, level);
        },
        onError: (Object e) {
          debugPrint('voice chat: ไมค์ขัดข้อง — ${e.runtimeType}');
          if (seq == _seq) unawaited(stop(why: state.s.micFailed));
        },
        cancelOnError: true,
      );
      return true;
    } on Object catch (e) {
      debugPrint('voice chat: เปิดไมค์ไม่สำเร็จ — ${e.runtimeType}');
      return false;
    }
  }

  Future<void> _closeMic() async {
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    await _mic.close();
  }

  /// ข้อความที่ขึ้นแชทเองโดยไม่ผ่านสมอง (ผลโทร ผลงานในเครื่อง) · คนขับรถไม่ได้มองจอ ต้องได้ยิน
  void _onNotice(String text) {
    if (!active) return;
    _activity();
    final rt = _rt;
    if (_engine == VoiceChatEngine.live && rt != null) {
      rt.announce('Tell the owner this now, in one or two short spoken sentences in your own words: $text');
      return;
    }
    // ตัวถอดเสียงในเครื่องที่ฟังอยู่ต้องหยุดก่อน ไม่งั้นได้ยินเสียงเธอเป็นคำของเจ้าของ
    if (_engine == VoiceChatEngine.device) unawaited(state.deviceSpeech?.cancel() ?? Future<void>.value());
    _notices++;
    final seq = _seq;
    unawaited(state.speakNotice(text).whenComplete(() {
      if (seq != _seq) return;
      _notices = math.max(0, _notices - 1);
      _openAt = _clock().add(echoTail);
    }));
  }

  /// ทุก 100 มิลลิวินาที: เสียงเธอยังออกอยู่ไหม → กั้นไมค์ · ปาก · สถานะบนจอ · เงียบนาน = ปิด
  Future<void> _onTick() async {
    if (_tickBusy || !active || _disposed) return;
    _tickBusy = true;
    final seq = _seq;
    try {
      // 🔴 เจ้าของเปลี่ยนสมอง/ลบคีย์/ปิดคุยสดกลางทาง · ทางที่ใช้อยู่ไม่ตรงกับที่ตั้งแล้ว = ปิด ·
      // โดยเฉพาะเปลี่ยนเป็นสมองในเครื่อง ซึ่งสัญญาว่าเสียงไม่ออกนอกเครื่อง แต่ท่อคุยสดยังส่งเสียงไป OpenAI อยู่
      final stale = switch (_engine) {
        VoiceChatEngine.live => !state.voiceChatLiveReady,
        VoiceChatEngine.turns => state.transcribesOnDevice || !state.canTranscribe,
        VoiceChatEngine.device => !state.transcribesOnDevice,
        null => false,
      };
      if (stale) {
        debugPrint('voice chat: ตั้งค่าสมองเปลี่ยนกลางทาง ปิดไมค์');
        await stop();
        return;
      }
      final rt = _rt;
      var speaking = false;
      var audible = false;
      if (_engine == VoiceChatEngine.live && rt != null) {
        final pending = await _invoke<int>('liveAudioPending') ?? 0;
        if (seq != _seq || !identical(_rt, rt)) return;
        audible = pending > 0;
        speaking = _responding || audible;
        _setLips(audible);
        if (audible && _lipFrames.isNotEmpty) {
          final playedMs = _lipTotalMs - pending;
          while (_lipFrames.length > 1 && _lipFrames.first.endMs <= playedMs) {
            _lipFrames.removeAt(0);
          }
          unawaited(lips?.setLiveLevel(_lipFrames.first.level));
        }
        // ลาแล้วและเสียงลาจบแล้ว = ปิดไมค์
        if (_endWhenQuiet && !speaking) {
          await stop();
          return;
        }
      } else {
        audible = state.speaking;
        speaking = audible || _notices > 0;
      }
      final now = _clock();
      if (speaking || _toolsRunning > 0 || _delivering) _activity();
      if (speaking) _openAt = now.add(echoTail);
      _gated = speaking || now.isBefore(_openAt);

      final idle = _engine == VoiceChatEngine.live ? idleLive : idleTurns;
      if (now.difference(_lastActivity) > idle) {
        debugPrint('voice chat: เงียบเกิน ${idle.inMinutes} นาที ปิดไมค์');
        await stop(why: state.s.voiceChatIdleOff);
        return;
      }

      final hearing = !_gated &&
          (_engine == VoiceChatEngine.turns ? _taker.started : now.difference(_loudAt) < const Duration(milliseconds: 700));
      final next = audible
          ? VoiceChatPhase.speaking
          : (_delivering || _responding || _toolsRunning > 0 || _finishPending)
              ? VoiceChatPhase.thinking
              : hearing
                  ? VoiceChatPhase.hearing
                  : VoiceChatPhase.listening;
      if (_phase != VoiceChatPhase.opening && _phase != VoiceChatPhase.off) _phase = next;
      if (!_disposed) notifyListeners();
    } finally {
      _tickBusy = false;
    }
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      debugPrint('voice chat: $method ไม่สำเร็จ — ${e.code}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (active || _tick != null) unawaited(stop());
    _mic.dispose();
    super.dispose();
  }
}

/// ดังกว่าพื้นเสียงไหม · พื้นปรับตามห้อง/รถ (เหมือนในสาย และ [TurnTaker])
class _Loudness {
  double _quiet = 0;

  bool feed(double level) {
    _quiet = _quiet == 0 ? level : math.min(_quiet * 1.02, level);
    return level > math.max(.012, _quiet * 3.5);
  }
}
