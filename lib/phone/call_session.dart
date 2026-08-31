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
import '../state/mind_state.dart';
import '../system/permissions.dart';
import 'call_watch.dart';

/// บรรทัดหนึ่งของบทสนทนาในสาย
@immutable
class CallLine {
  const CallLine.her(this.text) : fromHer = true;
  const CallLine.them(this.text) : fromHer = false;

  final String text;
  final bool fromHer;
}

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
  })  : _watch = watch,
        _state = state,
        _ch = channel ?? kSystemChannel,
        _injectedRecorder = recorder,
        _perms = permissions ?? MindPermissions() {
    _watch.addListener(_onWatch);
  }

  final CallWatch _watch;
  final MindState _state;
  final MethodChannel _ch;
  final MindPermissions _perms;

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

  Future<void> _refresh() async {
    if (_disposed) return;

    final info = await _callInfo();
    final live = info?['live'] == true;
    final mind = info?['mind'] == true;
    final name = (info?['name'] as String?)?.trim();
    final number = (info?['number'] as String?)?.trim();
    final who = (name?.isNotEmpty ?? false) ? name! : (number ?? '');

    final was = _live && _mind;
    _live = live;
    _mind = mind;
    if (who.isNotEmpty) _who = who;

    if (!live) {
      _finish();
      return;
    }

    // มีสายจริงแล้วค่อยเริ่มถามซ้ำ · นาฬิกานี้คือตัวจับ "เจ้าของกดให้มายด์รับ
    // จากจอสายเนทีฟ" ซึ่งไม่มีสัญญาณอะไรวิ่งมาบอกฝั่งนี้เลย
    _poll ??= Timer.periodic(const Duration(seconds: 1), (_) => _refresh());

    if (mind && !was) _begin();
    if (!mind && was && _turn != CallTurn.handedOver) {
      // เจ้าของแทรกสายจากจอเนทีฟ — หยุดเธอฝั่งนี้ให้ตรงกัน
      _turn = CallTurn.handedOver;
      unawaited(_stopListening());
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

  /// เริ่มบทสนทนาของสายนี้
  void _begin() {
    _lines.clear();
    _deaf = false;
    _mute = false;
    _error = null;
    _silentRounds = 0;
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

    unawaited(_stopListening());
    unawaited(_invoke('callEndAudio'));
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
    _turn = CallTurn.handedOver;
    _mind = false;
    _notify();
    await _stopListening();
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
      await _talk();
    } on OpenAiFailure catch (e) {
      _error = e.message;
    } on Exception catch (e) {
      debugPrint('สาย: บทสนทนาสะดุด — $e');
    }
    // จบวงแล้วแต่สายยังอยู่ = เธอเงียบรอเจ้าของพิมพ์ ไม่ใช่ "กำลังฟัง" ค้าง
    if (_turn == CallTurn.listening) _turn = CallTurn.none;
    _notify();
  }

  Future<void> _talk() async {
    await _speak(_state.callGreeting(), remember: true);

    while (_live && _mind && !_disposed) {
      final heard = await _listen();
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

      _lines.add(CallLine.her(reply));
      _notify();
      await _speak(reply);
    }
  }

  /// พูดออกลำโพงให้ไมค์รับเข้าสาย · รอจนเล่นจบจริง
  ///
  /// 🔴 **ห้ามส่งไปที่ WebView** ทั้งที่นั่นเป็นทางเสียงปกติของเธอ
  /// เสียงในสายต้องออกช่องเสียงของสายเท่านั้น ไม่งั้นจะดังซ้อนสองทาง
  /// แล้วก้องกลับเข้าไปในสาย · ปากยังขยับอยู่ เพราะตอนอารมณ์ `calling`
  /// LipSync ใช้จังหวะที่สร้างเอง ไม่ได้อ่านจากคลื่นเสียง
  Future<void> _speak(String text, {bool remember = false}) async {
    if (text.trim().isEmpty) return;
    if (remember) _lines.add(CallLine.her(text));

    _turn = CallTurn.talking;
    _notify();

    // ไมค์ต้องปิดตอนเธอพูด ไม่งั้นจะได้ยินเสียงตัวเองกลับเข้ามาเป็นคำถาม
    await _stopListening();

    final utterance = await _state.speakForCall(text);
    final file = await _writeTemp(utterance.bytes, _extFor(utterance.mime));

    final ok = await _invoke<bool>('callSpeak', {
      'path': file.path,
      'stream': _state.callStream,
    });

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

  StreamSubscription<Uint8List>? _mic;

  /// อัดเสียง 16 บิต ช่องเดียว 16 kHz = 32,000 ไบต์ต่อวินาที
  static const _rate = 16000;
  static const _bytesPerSecond = _rate * 2;

  /// เพดานหนึ่งเทิร์น · ยาวกว่านี้คือคนพูดยาวจนเธอควรตอบได้แล้ว
  static const _maxTurn = Duration(seconds: 20);

  /// เงียบนานเท่านี้หลังเริ่มพูดแล้ว = จบประโยค
  static const _endOfSpeech = Duration(milliseconds: 1100);

  /// ไม่มีใครพูดเลยนานเท่านี้ = รอบนี้ไม่ได้อะไร
  static const _patience = Duration(seconds: 10);

  /// ระดับที่นับว่าเป็นเสียงพูด — เทียบกับพื้นเสียงที่วัดได้จริง ไม่ใช่ค่าคงที่
  ///
  /// ค่าคงที่ใช้ไม่ได้เพราะสายที่เปิดลำโพงในรถกับในห้องเงียบ พื้นเสียง
  /// ต่างกันหลายเท่า · แต่ยังต้องมีพื้นขั้นต่ำ ไม่งั้นในห้องเงียบสนิท
  /// สัญญาณรบกวนระดับบิตสุดท้ายจะถูกนับเป็นคำพูด
  static const _floorMin = .012;

  Future<String?> _listen() async {
    if (!await _canListen()) {
      _markDeaf();
      return null;
    }

    _turn = CallTurn.listening;
    _notify();

    final pcm = BytesBuilder(copy: false);
    final done = Completer<void>();
    var quiet = 0.0;
    var loud = 0.0;
    var speechStarted = false;
    var peak = 0.0;
    DateTime? lastLoud;
    final startedAt = DateTime.now();

    void finish() {
      if (!done.isCompleted) done.complete();
    }

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
          if (pcm.length < _bytesPerSecond * _maxTurn.inSeconds) pcm.add(chunk);

          final level = levelOf(chunk);
          _micLevel = level;
          if (level > peak) peak = level;

          // พื้นเสียง = ค่าต่ำสุดที่เคยเห็น · ไต่ขึ้นช้า ๆ กันการล็อกค่าไว้
          // ที่ศูนย์ตลอดกาลเมื่อชิ้นแรกบังเอิญเป็นความเงียบสนิท
          quiet = quiet == 0 ? level : math.min(quiet * 1.02, level);
          loud = math.max(_floorMin, quiet * 3.5);

          final now = DateTime.now();
          if (level > loud) {
            speechStarted = true;
            lastLoud = now;
          }

          if (speechStarted &&
              lastLoud != null &&
              now.difference(lastLoud!) > _endOfSpeech) {
            finish();
          } else if (!speechStarted &&
              now.difference(startedAt) > _patience) {
            finish();
          } else if (now.difference(startedAt) > _maxTurn) {
            finish();
          }

          _notify();
        },
        onError: (Object e) {
          debugPrint('สาย: ไมค์ขัดข้อง — $e');
          finish();
        },
        onDone: finish,
        cancelOnError: true,
      );

      await done.future.timeout(_maxTurn + const Duration(seconds: 2),
          onTimeout: () {});
    } on Exception catch (e) {
      debugPrint('สาย: เปิดไมค์ไม่ได้ — $e');
      _markDeaf();
      return null;
    } finally {
      await _stopListening();
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

    final bytes = pcm.takeBytes();
    if (bytes.length < _bytesPerSecond ~/ 3) return null; // สั้นกว่า 0.3 วิ

    try {
      final text = await _state.transcribeCall(wavOf(bytes));
      return text.isEmpty ? null : text;
    } on OpenAiFailure catch (e) {
      _error = e.message;
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
    _notify();
  }

  Future<void> _stopListening() async {
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

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _watch.removeListener(_onWatch);
    unawaited(_stopListening());
    _lazyRecorder?.dispose();
    super.dispose();
  }
}
