/// พูดใส่ไมค์แทนการพิมพ์ในช่องแชท
///
/// 🔴 ปุ่มไมค์ในช่องแชท**เคยเป็นปุ่มหลอก** — กดแล้วเปลี่ยนสีตัวเองอย่างเดียว
/// ไม่มีการอัด ไม่มีการถอดเสียง ทั้งที่ข้อความในช่องพิมพ์ชวนให้กดมันอยู่
/// ("พิมพ์ หรือกดไมค์…") · ของที่ดูเหมือนมีแต่ไม่ทำงานแย่กว่าไม่มี เพราะ
/// คนใช้จะโทษตัวเองว่ากดผิด แล้วลองซ้ำอยู่อย่างนั้น
///
/// **ข้อความที่ถอดได้จะถูกใส่ลงช่องพิมพ์ ไม่ใช่ส่งทันที** — การถอดเสียงผิด
/// ได้เสมอ (โดยเฉพาะภาษาไทยผ่านไมค์มือถือ) ส่งเลยแปลว่าเธอได้ยินผิดแล้ว
/// ตอบไปแล้วก่อนที่เจ้าของจะทันเห็นว่ามันเพี้ยน
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import '../phone/call_session.dart';
import 'device_speech.dart';
import 'openai_client.dart';

/// อยู่ขั้นไหนของการพูดหนึ่งครั้ง
enum VoiceInputStage {
  idle,

  /// กำลังขอสิทธิ์ / เปิดไมค์ — สั้นแต่ไม่ใช่ศูนย์ ต้องมีสถานะของตัวเอง
  /// ไม่งั้นปุ่มจะนิ่งอยู่หนึ่งอึดใจแล้วคนจะกดซ้ำ
  opening,
  listening,

  /// อัดเสร็จแล้ว กำลังส่งไปถอด
  working,
  failed,
}

/// อัดเสียงจากไมค์แล้วถอดเป็นข้อความ
///
/// ไม่รู้จัก widget และไม่รู้จัก [MindState] — รับสองความสามารถที่ต้องใช้
/// เข้ามาเป็นฟังก์ชัน จึงทดสอบได้โดยไม่ต้องมีไมค์จริงและไม่ต้องมีเน็ต
class VoiceInput extends ChangeNotifier {
  VoiceInput({
    required this.ensureMic,
    required this.transcribe,
    required S Function() strings,
    this.device,
    this.preferDevice,
    AudioRecorder? recorder,
  })  : _s = strings,
        _injected = recorder;

  /// ตัวถอดเสียงในเครื่อง — null = ไม่มีทางนี้ (เช่นในเทสต์)
  final DeviceSpeech? device;

  /// ตอนนี้ควรใช้ทางในเครื่องไหม
  ///
  /// 🔴 จริงเมื่อผู้ใช้เลือก "สมองในเครื่อง" — ทางนั้นสัญญาว่าไม่มีอะไรออก
  /// นอกเครื่อง การส่งเสียงไปถอดข้างนอกจึงเป็นการผิดสัญญา · ส่วนคนที่เลือก
  /// สมองทางอื่นอยู่แล้ว ใช้ทางข้างนอกซึ่งแม่นกว่ามากสำหรับภาษาไทย
  final bool Function()? preferDevice;

  /// รอบนี้ใช้ทางในเครื่องอยู่ไหม
  bool _onDevice = false;
  bool get onDevice => _onDevice;

  /// ข้อความที่ได้ยินระหว่างพูด — มีเฉพาะทางในเครื่อง
  String _heard = '';
  String get heard => _heard;

  /// ขอสิทธิ์ไมค์ · คืน true เมื่อใช้ได้
  final Future<bool> Function() ensureMic;

  /// ส่งไฟล์ WAV ไปถอดเป็นข้อความ · คืนสตริงว่างได้เมื่อไม่มีเสียงพูด
  final Future<String> Function(Uint8List wav) transcribe;

  final S Function() _s;

  /// สร้างตอนใช้จริงเท่านั้น — AudioRecorder ผูก MethodChannel ตั้งแต่
  /// constructor จึงพังใน unit test ที่ยังไม่มี binding
  final AudioRecorder? _injected;
  AudioRecorder? _lazy;
  AudioRecorder get _recorder => _lazy ??= _injected ?? AudioRecorder();

  /// เดียวกับที่ใช้ในสาย — 16 kHz mono 16 บิต คือสิ่งที่ตัวถอดเสียงอยากได้
  static const _rate = 16000;
  static const _bytesPerSecond = _rate * 2;

  /// เพดานหนึ่งครั้ง
  ///
  /// ไม่ใช่ข้อจำกัดทางเทคนิค แต่เป็น**ตาข่ายรับตอนคนลืมกดหยุด** — ไมค์ที่
  /// เปิดค้างไว้ทั้งวันคือทั้งแบตที่หายไปและเสียงในห้องที่ถูกอัดโดยไม่ตั้งใจ
  static const maxTake = Duration(seconds: 60);

  /// สั้นกว่านี้แปลว่ากดแล้วปล่อยทันที ยังไม่ทันมีคำพูด
  static const _minBytes = _bytesPerSecond ~/ 3;

  VoiceInputStage _stage = VoiceInputStage.idle;
  VoiceInputStage get stage => _stage;

  bool get busy =>
      _stage == VoiceInputStage.opening ||
      _stage == VoiceInputStage.listening ||
      _stage == VoiceInputStage.working;

  /// ระดับเสียงล่าสุด 0..1 — ให้ปุ่มเต้นตามเสียงจริง
  ///
  /// วงที่เต้นตามเสียงบอกสิ่งที่ไอคอนสีแดงบอกไม่ได้: **ไมค์ได้ยินเราอยู่จริง**
  /// คนที่พูดใส่ไมค์ที่ดับอยู่จะรู้ทันทีแทนที่จะรู้ตอนได้ข้อความเปล่ากลับมา
  double _level = 0;
  double get level => _level;

  String? _error;
  String? get error => _error;

  StreamSubscription<Uint8List>? _mic;
  Timer? _cap;
  BytesBuilder? _pcm;

  /// ปิดไปแล้วหรือยัง — กันการแตะสถานะหลังหน้าจอตายไปแล้ว
  bool _disposed = false;

  void _set(VoiceInputStage s, {String? error}) {
    if (_disposed) return;
    _stage = s;
    _error = error;
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    if (_stage == VoiceInputStage.failed) _stage = VoiceInputStage.idle;
    notifyListeners();
  }

  /// เริ่มฟัง · คืน false เมื่อเริ่มไม่ได้ (เหตุผลอยู่ใน [error])
  Future<bool> start() async {
    if (busy) return false;
    _set(VoiceInputStage.opening);
    _heard = '';

    if (!await ensureMic()) {
      _set(VoiceInputStage.failed, error: _s().micDenied);
      return false;
    }
    if (_disposed) return false;

    // ทางในเครื่องมาก่อนเมื่อผู้ใช้เลือกสมองในเครื่อง — เสียงต้องไม่ออกไปไหน
    final dev = device;
    if (dev != null && (preferDevice?.call() ?? false)) {
      if (await dev.available()) {
        _onDevice = true;
        return _startOnDevice(dev);
      }
      // มีสิทธิ์ครบแต่เครื่องทำไม่ได้ · บอกตรง ๆ ดีกว่าแอบส่งเสียงออกไป
      // ให้ทางข้างนอกถอดแทน ซึ่งเป็นการผิดสัญญาที่ผู้ใช้ไม่มีทางรู้
      _set(VoiceInputStage.failed, error: _s().micNoOnDevice);
      return false;
    }
    _onDevice = false;

    final pcm = _pcm = BytesBuilder(copy: false);
    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _rate,
          numChannels: 1,
          // ตรงข้ามกับตอนอยู่ในสาย: ที่นี่**อยากได้**ตัวตัดเสียงรบกวนกับ
          // ตัวตัดเสียงก้อง เพราะสิ่งที่จะถูกลบทิ้งคือเสียงห้อง ไม่ใช่เสียงคู่สาย
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceRecognition,
          ),
        ),
      );

      _mic = stream.listen(
        (chunk) {
          if (pcm.length < _bytesPerSecond * maxTake.inSeconds) pcm.add(chunk);
          _level = CallSession.levelOf(chunk);
          if (!_disposed) notifyListeners();
        },
        onError: (Object e) {
          debugPrint('ไมค์: ขัดข้องระหว่างอัด — $e');
          unawaited(stop());
        },
        cancelOnError: true,
      );
    } on Object catch (e) {
      debugPrint('ไมค์: เปิดไม่สำเร็จ — $e');
      await _teardown();
      _set(VoiceInputStage.failed, error: _s().micFailed);
      return false;
    }

    // 🔴 ประกาศว่ากำลังฟัง **ก็ต่อเมื่อยังไม่มีใครสั่งหยุดระหว่างทาง**
    //
    // ระหว่างที่ยังขอสิทธิ์/เปิดไมค์อยู่ ตัว stream อาจล้มแล้วเรียก stop()
    // ไปแล้วก็ได้ · ถ้าตั้งทับลงไปดื้อ ๆ ปุ่มจะบอกว่ากำลังฟังทั้งที่ไมค์
    // ปิดไปแล้ว แล้วคนจะพูดทั้งประโยคใส่ไมค์ที่ดับอยู่
    if (_stage != VoiceInputStage.opening) return false;
    _cap = Timer(maxTake, () => unawaited(stop()));
    _set(VoiceInputStage.listening);
    return true;
  }

  /// ทางในเครื่อง — ระบบเป็นเจ้าของไมค์เอง เราแค่รอผล
  ///
  /// ต่างจากทางอัดเสียงตรงที่ **ไม่มีไฟล์ให้ถือ** ระบบฟังแล้วคืนข้อความมาเลย
  /// จึงไม่มีขั้น "กำลังถอดเสียง" แยกออกมา
  Future<bool> _startOnDevice(DeviceSpeech dev) async {
    dev
      ..onLevel = (v) {
        _level = v;
        if (!_disposed) notifyListeners();
      }
      ..onPartial = (t) {
        _heard = t;
        if (!_disposed) notifyListeners();
      };

    // ไม่ await ตรงนี้ · future นี้จบเมื่อ**ผู้ใช้พูดจบ** ซึ่งอาจอีกหลายวินาที
    // ผู้เรียกต้องได้ปุ่มที่กดหยุดได้ทันที ไม่ใช่ค้างรออยู่ใน start()
    unawaited(dev.listen(locale: _s().isThai ? 'th-TH' : 'en-US').then((text) {
      if (_disposed) return;
      _level = 0;
      if (text != null && text.trim().isNotEmpty) {
        _pending = text.trim();
        _set(VoiceInputStage.idle);
      } else {
        _set(VoiceInputStage.failed, error: _faultText(dev.fault));
      }
      _done?.call(_pending);
      _done = null;
      _pending = null;
    }));

    _cap = Timer(maxTake, () => unawaited(dev.stop()));
    if (_stage != VoiceInputStage.opening) return false;
    _set(VoiceInputStage.listening);
    return true;
  }

  /// ข้อความที่รอส่งกลับให้ผู้เรียก [stop]
  String? _pending;
  void Function(String?)? _done;

  String _faultText(SttFault? f) => switch (f) {
        SttFault.unavailable => _s().micNoOnDevice,
        SttFault.language => _s().micNoLanguagePack,
        SttFault.noMatch || null => _s().micHeardNothing,
        SttFault.permission => _s().micDenied,
        SttFault.busy => _s().micBusy,
        _ => _s().micFailed,
      };

  /// หยุดฟังแล้วถอดเสียง · คืนข้อความที่ได้ (null = ไม่ได้อะไร)
  Future<String?> stop() async {
    if (_stage != VoiceInputStage.listening &&
        _stage != VoiceInputStage.opening) {
      return null;
    }

    if (_onDevice) {
      final dev = device!;
      _cap?.cancel();
      _cap = null;
      _set(VoiceInputStage.working);

      // ผลมาทางเหตุการณ์จากระบบ ไม่ใช่ค่าที่ส่งกลับจาก stop()
      // จึงต้องรอที่นี่จนกว่ามันจะมาถึง
      final wait = Completer<String?>();
      _done = wait.complete;
      await dev.stop();
      return wait.future;
    }

    _set(VoiceInputStage.working);

    final pcm = _pcm;
    await _teardown();
    final bytes = pcm?.takeBytes() ?? Uint8List(0);

    if (bytes.length < _minBytes) {
      _set(VoiceInputStage.failed, error: _s().micHeardNothing);
      return null;
    }

    try {
      final text = (await transcribe(CallSession.wavOf(bytes, rate: _rate)))
          .trim();
      if (_disposed) return null;
      if (text.isEmpty) {
        // 🔴 เงียบไม่ใช่ความผิดพลาด · คนกดแล้วยังไม่ทันพูดก็มาถึงตรงนี้
        // พูดเหมือนระบบพังจะทำให้เขาไปไล่หาสาเหตุที่ไม่มีอยู่จริง
        _set(VoiceInputStage.failed, error: _s().micHeardNothing);
        return null;
      }
      _set(VoiceInputStage.idle);
      return text;
    } on OpenAiFailure catch (e) {
      _set(VoiceInputStage.failed, error: e.message);
      return null;
    } on Object catch (e) {
      debugPrint('ไมค์: ถอดเสียงไม่สำเร็จ — $e');
      _set(VoiceInputStage.failed, error: _s().errBrainUnexpected);
      return null;
    }
  }

  /// ทิ้งเสียงที่อัดไว้โดยไม่ถอด — ใช้ตอนออกจากหน้าจอกลางคัน
  Future<void> cancel() async {
    if (!busy) return;
    if (_onDevice) await device?.cancel();
    await _teardown();
    _pcm = null;
    _set(VoiceInputStage.idle);
  }

  Future<void> _teardown() async {
    _done = null;
    _pending = null;
    _cap?.cancel();
    _cap = null;
    await _mic?.cancel();
    _mic = null;
    _level = 0;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } on Object catch (e) {
      // หยุดไม่ได้ก็ปล่อย · dispose ข้างล่างจะเก็บให้อีกที
      debugPrint('ไมค์: หยุดอัดไม่สำเร็จ — $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_onDevice) unawaited(device?.cancel() ?? Future<void>.value());
    _cap?.cancel();
    unawaited(_mic?.cancel());
    // อย่าแตะ getter ตรงนี้ ไม่งั้นการปิดหน้าจอจะไปสร้าง AudioRecorder ใหม่
    _lazy?.dispose();
    super.dispose();
  }
}
