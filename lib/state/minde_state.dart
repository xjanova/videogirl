import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/minde_persona.dart';
import '../ai/openai_client.dart';
import '../ai/openai_config.dart';
import '../ai/speech_service.dart';
import '../theme/tokens.dart';

/// ข้อความหนึ่งบรรทัดในแชท
@immutable
class ChatMessage {
  const ChatMessage.her(this.text) : fromHer = true;
  const ChatMessage.me(this.text) : fromHer = false;

  final String text;
  final bool fromHer;
}

/// สิ่งที่ผู้ใช้ "ตั้ง" ไว้ในหน้าตั้งค่า — ต่างจาก [MindeMode] ที่เป็นโหมดที่มีผลจริง
/// ตอนนี้ เพราะ [auto] จะแปลงเป็นงาน/ส่วนตัวตามเวลา
enum PersonaSetting {
  work('งาน'),
  love('ส่วนตัว'),
  auto('อัตโนมัติ');

  const PersonaSetting(this.label);
  final String label;
}

/// ระดับการแซว/จีบ 0.0 = ทางการล้วน → 1.0 = หวานจัด
extension FlirtLevel on double {
  String get flirtSample {
    if (this < .2) return 'ประชุมบ่ายสามค่ะ';
    if (this < .45) return 'ประชุมบ่ายสามนะคะ อย่าลืมเตรียมสไลด์ด้วยค่ะ';
    if (this < .75) return 'ประชุมบ่ายสามนะคะ… อย่าลืมกินข้าวก่อนด้วยล่ะ';
    return 'ประชุมบ่ายสามนะคะ… อย่าลืมกินข้าวก่อนด้วยล่ะ เดี๋ยวมินเดะงอน';
  }
}

class MindeState extends ChangeNotifier {
  MindeState({
    DateTime Function()? clock,
    OpenAiClient? openai,
    SpeechService? speech,
  })  : _clock = clock ?? DateTime.now,
        _openai = openai ?? OpenAiClient(),
        _speech = speech ?? SpeechService();

  /// ฉีดนาฬิกาเข้ามาได้เพื่อให้เทสต์โหมดอัตโนมัติได้โดยไม่ต้องรอถึงสองทุ่ม
  final DateTime Function() _clock;
  final OpenAiClient _openai;
  final SpeechService _speech;

  bool _disposed = false;

  /// ทางออกของเสียง — shell เป็นคนต่อเข้ากับ WebView ของอวาตาร์
  /// state ไม่ควรรู้จัก widget ตรง ๆ ไม่งั้นเทสต์ไม่ได้เลย
  Future<void> Function(Utterance)? speaker;

  // ═══ บันทึกค่า ═════════════════════════════════════════
  SharedPreferences? _prefs;

  /// เรียกครั้งเดียวตอนแอปเริ่ม โหลดค่าที่ผู้ใช้เคยตั้งไว้กลับมา
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;

    _persona = PersonaSetting.values.firstWhere(
      (e) => e.name == p.getString('persona'),
      orElse: () => PersonaSetting.work,
    );
    _flirt = p.getDouble('flirt') ?? .72;
    _ownerProfile = p.getString('ownerProfile') ?? MindePersona.defaultOwnerProfile;
    _boundaries = p.getString('boundaries') ?? MindePersona.defaultBoundaries;
    _voiceInstructions =
        p.getString('voiceInstructions') ?? MindePersona.defaultVoiceInstructions;
    _brainModel = p.getString('brainModel') ?? OpenAiConfig.brainModel;
    _openAiVoice = p.getString('openAiVoice') ?? VoiceDefaults.openAiVoice;
    _ttsEngine = TtsEngine.values.firstWhere(
      (e) => e.name == p.getString('ttsEngine'),
      orElse: () => VoiceDefaults.engine,
    );
    _voiceEnabled = p.getBool('voiceEnabled') ?? true;
    _autoAnswer = p.getBool('autoAnswer') ?? true;
    _ringSeconds = p.getInt('ringSeconds') ?? 15;

    _notify();
  }

  void _save(String key, Object value) {
    final p = _prefs;
    if (p == null) return;
    switch (value) {
      case String v:
        p.setString(key, v);
      case double v:
        p.setDouble(key, v);
      case int v:
        p.setInt(key, v);
      case bool v:
        p.setBool(key, v);
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  // ═══ โหมด ══════════════════════════════════════════════
  PersonaSetting _persona = PersonaSetting.work;
  PersonaSetting get persona => _persona;

  /// โหมดที่มีผลจริงตอนนี้ — คลี่ [PersonaSetting.auto] ออกตามเวลาแล้ว
  MindeMode get mode => switch (_persona) {
        PersonaSetting.work => MindeMode.work,
        PersonaSetting.love => MindeMode.love,
        PersonaSetting.auto => _autoMode(),
      };

  MindeMode _autoMode() {
    final now = _clock();
    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    if (isWeekend) return MindeMode.love;
    return now.hour >= 20 || now.hour < 7 ? MindeMode.love : MindeMode.work;
  }

  void setPersona(PersonaSetting value) {
    if (_persona == value) return;
    _persona = value;
    _save('persona', value.name);
    _notify();
  }

  void toggleMode() =>
      setPersona(mode.isWork ? PersonaSetting.love : PersonaSetting.work);

  // ═══ ระดับการจีบ ═══════════════════════════════════════
  double _flirt = .72;
  double get flirt => _flirt;

  /// เพดานที่มีผลจริง — โหมดงานกดลงเหลือครึ่งเดียว
  double get effectiveFlirt => mode.isWork ? _flirt * .5 : _flirt;

  void setFlirt(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (_flirt == clamped) return;
    _flirt = clamped;
    _save('flirt', clamped);
    _notify();
  }

  // ═══ ข้อมูลดิบ + ขอบเขต ════════════════════════════════
  String _ownerProfile = MindePersona.defaultOwnerProfile;
  String get ownerProfile => _ownerProfile;

  String _boundaries = MindePersona.defaultBoundaries;
  String get boundaries => _boundaries;

  void setOwnerProfile(String v) {
    _ownerProfile = v;
    _save('ownerProfile', v);
    _notify();
  }

  void setBoundaries(String v) {
    _boundaries = v;
    _save('boundaries', v);
    _notify();
  }

  void resetOwnerProfile() => setOwnerProfile(MindePersona.defaultOwnerProfile);
  void resetBoundaries() => setBoundaries(MindePersona.defaultBoundaries);

  // ═══ เสียงและโมเดล ═════════════════════════════════════
  String _brainModel = OpenAiConfig.brainModel;
  String get brainModel => _brainModel;

  String _openAiVoice = VoiceDefaults.openAiVoice;
  String get openAiVoice => _openAiVoice;

  TtsEngine _ttsEngine = VoiceDefaults.engine;
  TtsEngine get ttsEngine => _ttsEngine;

  String _voiceInstructions = MindePersona.defaultVoiceInstructions;
  String get voiceInstructions => _voiceInstructions;

  bool _voiceEnabled = true;
  bool get voiceEnabled => _voiceEnabled;

  void setBrainModel(String v) {
    _brainModel = v;
    _save('brainModel', v);
    _notify();
  }

  void setOpenAiVoice(String v) {
    _openAiVoice = v;
    _save('openAiVoice', v);
    _notify();
  }

  void setTtsEngine(TtsEngine v) {
    _ttsEngine = v;
    _save('ttsEngine', v.name);
    _notify();
  }

  void setVoiceInstructions(String v) {
    _voiceInstructions = v;
    _save('voiceInstructions', v);
    _notify();
  }

  void setVoiceEnabled(bool v) {
    _voiceEnabled = v;
    _save('voiceEnabled', v);
    _notify();
  }

  // ═══ รับสายอัตโนมัติ ═══════════════════════════════════
  bool _autoAnswer = true;
  bool get autoAnswer => _autoAnswer;

  /// ปล่อยให้กริ่งดังกี่วินาที ก่อนเธอรับแทน
  /// 0 = รับทันที · ค่าเริ่มต้น 15 วิ ให้เจ้าของมีจังหวะคว้าเครื่องก่อน
  int _ringSeconds = 15;
  int get ringSeconds => _ringSeconds;

  static const ringChoices = <int>[0, 5, 10, 15, 20, 30, 45, 60];

  void setAutoAnswer(bool v) {
    _autoAnswer = v;
    _save('autoAnswer', v);
    _notify();
  }

  void setRingSeconds(int v) {
    _ringSeconds = v;
    _save('ringSeconds', v);
    _notify();
  }

  String get ringLabel => _ringSeconds == 0 ? 'รับทันที' : 'ดัง $_ringSeconds วินาทีก่อน';

  // ═══ แชท ═══════════════════════════════════════════════
  final List<ChatMessage> _messages = [
    const ChatMessage.her(
        'อรุณสวัสดิ์ค่ะ เช้านี้มีเมล 24 ฉบับ มินเดะคัดให้เหลือ 3 ที่ต้องตอบนะคะ'),
    const ChatMessage.me('บ่ายนี้ว่างไหม'),
    const ChatMessage.her(
        'บ่ายว่างตั้งแต่ 14:00 ค่ะ แต่คุณต้นขอเลื่อนรีวิวมาบ่ายสาม จะให้มินเดะโทรไปคุยให้ไหมคะ'),
  ];

  /// แผงแชทลอยทับอวาตาร์อยู่ ถ้าเก็บยาวกว่านี้จะบังตัวเธอ
  static const _historyLimit = 6;

  /// ส่งเข้าโมเดลมากกว่าที่แสดง เพื่อให้เธอจำบริบทได้ยาวกว่าที่ตาเห็น
  static const _contextLimit = 16;

  final List<ChatMessage> _context = [];

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  String get bubbleText => _messages
      .lastWhere((m) => m.fromHer, orElse: () => const ChatMessage.her(''))
      .text;

  bool _sending = false;
  bool get sending => _sending;

  String? _lastError;

  /// ข้อความผิดพลาดล่าสุดที่พอบอกผู้ใช้ได้ — ไม่มี stack trace
  String? get lastError => _lastError;

  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    _notify();
  }

  Future<void>? _inFlight;

  /// กันกดส่งซ้อน
  ///
  /// ใช้ Future ที่ค้างอยู่ ไม่ใช่แค่ธง bool — เพราะถ้าไม่มีคีย์ OpenAI
  /// เส้นทางตอบจะไม่มี await คั่นเลย ธงจะถูกปลดก่อนที่นิ้วจะยกจากจอด้วยซ้ำ
  /// ส่วน async function คืน Future ที่ยังไม่ resolve เสมอ จึงกันได้ทุกกรณี
  /// คนกดซ้ำจะได้ Future เดิมกลับไป ไม่ใช่ข้อความซ้ำ
  Future<void> send(String raw) {
    if (raw.trim().isEmpty) return Future<void>.value();
    final running = _inFlight;
    if (running != null) return running;

    final started = _send(raw.trim());
    _inFlight = started;
    return started.whenComplete(() => _inFlight = null);
  }

  Future<void> _send(String text) async {
    _sending = true;
    _lastError = null;
    _push(ChatMessage.me(text));
    _notify();

    String reply;
    try {
      reply = OpenAiConfig.configured
          ? await _openai.reply(
              system: MindePersona.system(
                mode: mode,
                flirt: effectiveFlirt,
                ownerProfile: _ownerProfile,
                boundaries: _boundaries,
              ),
              history: [
                for (final m in _context) (fromHer: m.fromHer, text: m.text),
              ],
              model: _brainModel,
            )
          : _cannedReply();
    } on OpenAiFailure catch (e) {
      _lastError = e.message;
      reply = _cannedReply();
    }

    if (_disposed) return;

    _push(ChatMessage.her(reply));
    _sending = false;
    _notify();

    await _speakIfEnabled(reply);
  }

  /// ให้เธอพูดตัวอย่างในหน้าตั้งค่า — ผู้ใช้จะได้ยินผลของเสียงที่เลือกทันที
  /// ไม่ต้องเดาว่าเปลี่ยนแล้วต่างยังไง
  Future<void> previewVoice() => _speakIfEnabled(effectiveFlirt.flirtSample);

  Future<void> _speakIfEnabled(String text) async {
    final out = speaker;
    if (!_voiceEnabled || out == null) return;
    // เครื่อง Android พูดได้แม้ไม่มีคีย์ OpenAI จึงเช็คเฉพาะทางที่ต้องใช้คีย์
    if (_ttsEngine == TtsEngine.openai && !OpenAiConfig.configured) return;

    try {
      final utterance = await _speech.synthesize(
        text,
        engine: _ttsEngine,
        voice: _openAiVoice,
        instructions: _voiceInstructions,
      );
      if (_disposed) return;
      await out(utterance);
    } on OpenAiFailure catch (e) {
      // เสียงพูดไม่ออกไม่ควรทำให้บทสนทนาพัง — ข้อความยังอยู่ครบ
      _lastError = e.message;
      _notify();
    }
  }

  String _cannedReply() => mode.isWork
      ? 'รับทราบค่ะ มินเดะจัดการให้แล้วจะสรุปกลับมานะคะ'
      : 'ได้เลยค่ะ… แต่ขอค่าจ้างเป็นคำชมสักคำนะคะ';

  void _push(ChatMessage m) {
    _messages.add(m);
    _context.add(m);
    if (_messages.length > _historyLimit) {
      _messages.removeRange(0, _messages.length - _historyLimit);
    }
    if (_context.length > _contextLimit) {
      _context.removeRange(0, _context.length - _contextLimit);
    }
  }

  // ═══ ไมค์ ══════════════════════════════════════════════
  bool _mic = false;
  bool get mic => _mic;

  void toggleMic() {
    _mic = !_mic;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _openai.close();
    _speech.dispose();
    super.dispose();
  }
}
