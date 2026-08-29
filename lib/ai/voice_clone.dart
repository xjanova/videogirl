/// โคลนเสียงเจ้าของ แล้วให้มายด์พูดด้วยเสียงนั้น
///
/// งานโคลนจริงอยู่ที่ **เซิร์ฟเวอร์** ไม่ใช่ในแอป เพราะโมเดลโคลนเสียง
/// ต้องใช้ GPU และไฟล์เป็นหลาย GB · ยัดลงมือถือแล้วแอปจะบวมและช้าเกินใช้งาน
///
/// เซิร์ฟเวอร์ปลายทางตั้งได้ — ชี้ไปคอมที่บ้านตอนพัฒนา
/// แล้วชี้ไป xman studio ตอนปล่อยจริง (ดู docs/backend.md)
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import 'openai_client.dart';

/// เสียงหนึ่งเสียงที่โคลนไว้แล้ว
@immutable
class ClonedVoice {
  const ClonedVoice({
    required this.id,
    required this.name,
    required this.status,
    this.seconds,
  });

  final String id;
  final String name;

  /// pending / training / ready / failed
  final String status;

  /// ความยาวตัวอย่างเสียงที่ใช้ฝึก
  final double? seconds;

  bool get isReady => status == 'ready';

  static ClonedVoice fromJson(Map<String, dynamic> j) => ClonedVoice(
        id: '${j['id']}',
        name: j['name'] as String? ?? '',
        status: j['status'] as String? ?? 'pending',
        seconds: (j['seconds'] as num?)?.toDouble(),
      );
}

enum CloneStage { idle, recording, uploading, training, ready, failed }

class VoiceCloneService extends ChangeNotifier {
  VoiceCloneService({
    http.Client? httpClient,
    AudioRecorder? recorder,
    S Function()? strings,
  })  : _s = strings ?? _thai,
        _http = httpClient ?? http.Client(),
        _injectedRecorder = recorder;

  final S Function() _s;
  static S _thai() => const S(AppLang.th);

  final http.Client _http;
  final AudioRecorder? _injectedRecorder;

  /// สร้างตอนใช้จริง — AudioRecorder จับ MethodChannel ตั้งแต่ constructor
  AudioRecorder? _lazyRecorder;
  AudioRecorder get _recorder => _lazyRecorder ??= _injectedRecorder ?? AudioRecorder();

  bool _disposed = false;

  // ── ปลายทาง ──────────────────────────────────────────────
  String _baseUrl = '';
  String _token = '';

  /// ตั้งปลายทางและโทเคนของผู้ใช้ — โทเคนมาจากการล็อกอิน ไม่ใช่คีย์ที่ฝังในแอป
  void configure({required String baseUrl, required String token}) {
    _baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    _token = token;
  }

  bool get configured => _baseUrl.isNotEmpty;

  Map<String, String> get _headers => {
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
        'Accept': 'application/json',
      };

  // ── สถานะ ────────────────────────────────────────────────
  CloneStage _stage = CloneStage.idle;
  CloneStage get stage => _stage;

  String? _error;
  String? get error => _error;

  List<ClonedVoice> _voices = const [];
  List<ClonedVoice> get voices => _voices;

  /// วินาทีที่อัดไปแล้ว ใช้บอกผู้ใช้ว่าพอหรือยัง
  int _recordedSeconds = 0;
  int get recordedSeconds => _recordedSeconds;

  /// ตัวอย่างเสียงสั้นกว่านี้โคลนออกมาไม่เหมือน
  static const minSeconds = 30;

  /// ยาวกว่านี้ก็ไม่ได้ดีขึ้นแล้ว แต่ไฟล์ใหญ่ขึ้นเปล่า ๆ
  static const maxSeconds = 120;

  bool get enoughRecorded => _recordedSeconds >= minSeconds;

  void _set(CloneStage s, {String? error}) {
    if (_disposed) return;
    _stage = s;
    _error = error;
    notifyListeners();
  }

  /// บทให้อ่านตอนอัด — ครอบคลุมเสียงวรรณยุกต์ครบห้าเสียงและสระยาว-สั้น
  /// ตัวอย่างที่พูดคำซ้ำ ๆ จะได้เสียงโคลนที่แบนและอ่านคำใหม่ไม่เป็นธรรมชาติ
  static const readingScript = '''
สวัสดีครับ ผมกำลังบันทึกเสียงเพื่อใช้เป็นเสียงของผู้ช่วยส่วนตัว

วันนี้อากาศดีมาก ท้องฟ้าแจ่มใส ไม่มีเมฆเลยสักก้อน
ช่วงบ่ายผมมีนัดประชุมกับลูกค้าเรื่องใบเสนอราคา
ถ้าใครโทรมาระหว่างนั้น ช่วยรับสายแล้วจดเรื่องไว้ให้ด้วยนะ

หนึ่ง สอง สาม สี่ ห้า หก เจ็ด แปด เก้า สิบ
ไก่ ไข่ ขวด ควาย ระฆัง งู จาน ฉิ่ง ช้าง โซ่

ขอบคุณมากครับ แล้วเจอกันใหม่พรุ่งนี้เช้า
''';

  // ── อัดเสียง ─────────────────────────────────────────────
  String? _samplePath;

  Future<bool> startRecording() async {
    if (!await _recorder.hasPermission()) {
      _set(CloneStage.failed, error: _s().errNeedMic);
      return false;
    }

    final dir = await getTemporaryDirectory();
    _samplePath = '${dir.path}${Platform.pathSeparator}voice_sample.wav';
    _recordedSeconds = 0;

    // WAV 16 บิต 24 kHz โมโน — โมเดลโคลนเสียงเกือบทุกตัวคาดรูปแบบนี้
    // อย่าใช้ไฟล์บีบอัด ร่องรอยการบีบจะติดไปอยู่ในเสียงที่โคลนออกมาด้วย
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 24000,
        numChannels: 1,
      ),
      path: _samplePath!,
    );

    _set(CloneStage.recording);
    return true;
  }

  /// ให้ UI เรียกทุกวินาทีระหว่างอัด
  void tick() {
    if (_stage != CloneStage.recording) return;
    _recordedSeconds++;
    if (_recordedSeconds >= maxSeconds) {
      stopRecording();
      return;
    }
    notifyListeners();
  }

  Future<String?> stopRecording() async {
    if (_stage != CloneStage.recording) return null;
    final path = await _recorder.stop();
    _set(CloneStage.idle);
    return path ?? _samplePath;
  }

  Future<void> cancelRecording() async {
    if (_stage == CloneStage.recording) await _recorder.cancel();
    _recordedSeconds = 0;
    _samplePath = null;
    _set(CloneStage.idle);
  }

  // ── ส่งไปโคลน ────────────────────────────────────────────
  Future<ClonedVoice?> upload({required String name}) async {
    final path = _samplePath;
    if (path == null) {
      _set(CloneStage.failed, error: _s().errNoSample);
      return null;
    }
    if (!configured) {
      _set(CloneStage.failed, error: _s().errNoServer);
      return null;
    }

    _set(CloneStage.uploading);
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$_baseUrl/voices'))
        ..headers.addAll(_headers)
        ..fields['name'] = name
        ..files.add(await http.MultipartFile.fromPath('sample', path));

      final streamed = await req.send().timeout(const Duration(minutes: 3));
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode >= 400) {
        _set(CloneStage.failed, error: _readable(streamed.statusCode, body));
        return null;
      }

      final voice = ClonedVoice.fromJson(
          jsonDecode(body) as Map<String, dynamic>);
      _set(voice.isReady ? CloneStage.ready : CloneStage.training);
      await refresh();
      return voice;
    } on Exception {
      _set(CloneStage.failed, error: _s().errUploadFailed);
      return null;
    }
  }

  Future<void> refresh() async {
    if (!configured) return;
    try {
      final res = await _http
          .get(Uri.parse('$_baseUrl/voices'), headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode >= 400) return;

      final list = jsonDecode(utf8.decode(res.bodyBytes));
      if (list is! List) return;
      _voices = [
        for (final v in list)
          if (v is Map<String, dynamic>) ClonedVoice.fromJson(v),
      ];
      if (!_disposed) notifyListeners();
    } on Exception {
      // อ่านรายการไม่ได้ไม่ใช่เรื่องคอขาดบาดตาย ปล่อยรายการเดิมไว้
    }
  }

  Future<void> remove(String id) async {
    if (!configured) return;
    try {
      await _http
          .delete(Uri.parse('$_baseUrl/voices/$id'), headers: _headers)
          .timeout(const Duration(seconds: 20));
    } on Exception {
      // ไม่ต้องทำอะไร refresh จะบอกสถานะจริง
    }
    await refresh();
  }

  /// พูดด้วยเสียงที่โคลนไว้ — คืน mp3 เป็นไบต์เหมือนเครื่องเสียงตัวอื่น
  Future<Uint8List> speak(String text, {required String voiceId}) async {
    if (!configured) {
      throw OpenAiFailure(_s().errCloneNotSet);
    }

    final clean = OpenAiClient.stripForSpeech(text);
    if (clean.isEmpty) throw OpenAiFailure(_s().errNothingToSay);

    try {
      final res = await _http
          .post(
            Uri.parse('$_baseUrl/tts'),
            headers: {..._headers, 'Content-Type': 'application/json; charset=utf-8'},
            body: utf8.encode(jsonEncode({'text': clean, 'voice_id': voiceId})),
          )
          .timeout(const Duration(seconds: 90));

      if (res.statusCode >= 400) {
        throw OpenAiFailure(
            _readable(res.statusCode, utf8.decode(res.bodyBytes)));
      }
      if (res.bodyBytes.isEmpty) {
        throw OpenAiFailure(_s().errServerEmptyAudio);
      }
      return res.bodyBytes;
    } on OpenAiFailure {
      rethrow;
    } on Exception {
      throw OpenAiFailure(_s().errCloneUnreachable);
    }
  }

  String _readable(int status, String body) {
    switch (status) {
      case 401 || 403:
        return _s().errNoPermission;
      case 402:
        return _s().errQuotaGone;
      case 413:
        return _s().errFileTooBig;
      case >= 500:
        return _s().errServerDown;
    }
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      final msg = m['message'] as String?;
      if (msg != null && msg.isNotEmpty) return msg;
    } on Exception {
      // ตอบกลับไม่ใช่ JSON
    }
    return _s().errRequestFailed(status);
  }

  @override
  void dispose() {
    _disposed = true;
    _lazyRecorder?.dispose();
    _http.close();
    super.dispose();
  }
}
