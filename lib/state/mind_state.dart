import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../memory/distiller.dart';
import '../calendar/device_calendar.dart';
import '../memory/mind_memory.dart';
import '../ai/brain_provider.dart';
import '../ai/local_brain.dart';
import '../ai/mind_persona.dart';
import '../i18n/strings.dart';
import '../ai/openai_client.dart';
import '../ai/openai_config.dart';
import '../ai/speech_service.dart';
import '../ai/voice_profile.dart';
import '../theme/tokens.dart';

/// ข้อความหนึ่งบรรทัดในแชท
@immutable
class ChatMessage {
  const ChatMessage.her(this.text) : fromHer = true;
  const ChatMessage.me(this.text) : fromHer = false;

  final String text;
  final bool fromHer;
}

/// สิ่งที่ผู้ใช้ "ตั้ง" ไว้ในหน้าตั้งค่า — ต่างจาก [MindMode] ที่เป็นโหมดที่มีผลจริง
/// ตอนนี้ เพราะ [auto] จะแปลงเป็นงาน/ส่วนตัวตามเวลา
/// ป้ายที่ผู้ใช้เห็นอยู่ใน i18n/enum_labels.dart — enum เก็บแค่ตัวตน
enum PersonaSetting { work, love, auto }

class MindState extends ChangeNotifier {
  MindState({
    DateTime Function()? clock,
    OpenAiClient? openai,
    SpeechService? speech,
    MindMemory? memory,
  })  : _clock = clock ?? DateTime.now,
        _openai = openai ?? OpenAiClient(),
        _speech = speech ?? SpeechService(),
        memory = memory ?? MindMemory();

  /// สิ่งที่เธอจำได้จากที่เคยคุยกัน
  ///
  /// เป็น public เพราะหน้าตั้งค่าต้องเปิดดูและลบได้ — ความจำที่เจ้าของ
  /// เปิดดูไม่ได้ ไม่ใช่ผู้ช่วย
  final MindMemory memory;

  /// ปฏิทินของเครื่อง — ต่อเข้ามาทีหลังด้วย [attachCalendar]
  ///
  /// ไม่ได้เป็นเจ้าของเองเพราะมันต้องใช้ [MindPermissions] ตัวเดียวกับทั้งแอป
  /// และตัวนั้นถูกสร้างที่ main · null = ยังไม่ได้ต่อ ซึ่งเกิดได้ในเทสต์
  DeviceCalendar? _calendar;

  /// ให้เธอรู้ตารางจริง · เรียกครั้งเดียวตอนเปิดแอป
  void attachCalendar(DeviceCalendar c) => _calendar = c;

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

    _lang = AppLang.fromCode(p.getString('lang'));
    _persona = PersonaSetting.values.firstWhere(
      (e) => e.name == p.getString('persona'),
      orElse: () => PersonaSetting.work,
    );
    _flirt = p.getDouble('flirt') ?? .72;
    _ownerProfile =
        p.getString('ownerProfile') ?? MindPersona.defaultOwnerProfile(_lang);
    _boundaries = p.getString('boundaries') ?? MindPersona.defaultBoundaries(_lang);
    _brain = BrainProvider.values.firstWhere(
      (e) => e.name == p.getString('brain'),
      orElse: () => BrainProvider.openai,
    );
    _homeServerUrl = p.getString('homeServerUrl') ?? HomeServerDefaults.baseUrl;
    _homeServerModel = p.getString('homeServerModel') ?? HomeServerDefaults.model;
    _avatarPackUrl = p.getString('avatarPackUrl') ?? _packUrlDefault;
    _avatarPackId = p.getString('avatarPackId') ?? '';
    _storeBaseUrl = p.getString('storeBaseUrl') ?? _storeDefault;
    _licenseKey = p.getString('licenseKey') ?? '';
    _brainModel = p.getString('brainModel') ?? OpenAiConfig.brainModel;
    _realtimeModel = p.getString('realtimeModel') ?? OpenAiConfig.realtimeModel;

    for (final c in VoiceChannel.values) {
      final raw = p.getString('voice_${c.name}');
      if (raw == null) continue;
      try {
        _voices[c] = VoiceProfile.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
          VoiceProfile.defaultFor(c, _lang),
        );
      } on FormatException {
        // ค่าที่บันทึกไว้เสีย ปล่อยให้ใช้ค่าตั้งต้นแทน ดีกว่าแอปเปิดไม่ขึ้น
      }
    }
    _bubbleEnabled = p.getBool('bubbleEnabled') ?? true;
    _bubbleSeconds = p.getInt('bubbleSeconds') ?? 5;
    _voiceEnabled = p.getBool('voiceEnabled') ?? true;
    _autoAnswer = p.getBool('autoAnswer') ?? true;
    _ringSeconds = p.getInt('ringSeconds') ?? 15;

    // บทสนทนาเก่าต้องกลับมาก่อนบทตัวอย่าง — ถ้าเคยคุยจริงแล้ว
    // การเอาบทตัวอย่างมาทับคือการลบสิ่งที่ผู้ใช้พิมพ์เองทิ้ง
    _loadContext();
    await memory.load();
    _seedConversation();

    // 🔴 เริ่มนับตั้งแต่เปิดแอป ไม่ใช่รอให้มีข้อความใหม่
    //
    // `_armChat` ถูกเรียกจาก `_push` เท่านั้น แต่บทสนทนาตอนเปิดแอป
    // (ทั้งบทตัวอย่างและที่กู้มาจากดิสก์) ถูกเติมตรง ๆ ไม่ผ่าน `_push`
    // ผลคือนาฬิกาไม่เคยเริ่มเดิน แผงจึงไม่พับเลยจนกว่าจะคุยสักคำ
    // — เจอตอนลองจริงบนเครื่อง รอ 17 วินาทีแล้วแผงยังอยู่เหมือนเดิม
    _startChatCountdown();
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
  MindMode get mode => switch (_persona) {
        PersonaSetting.work => MindMode.work,
        PersonaSetting.love => MindMode.love,
        PersonaSetting.auto => _autoMode(),
      };

  MindMode _autoMode() {
    final now = _clock();
    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    if (isWeekend) return MindMode.love;
    return now.hour >= 20 || now.hour < 7 ? MindMode.love : MindMode.work;
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
  String _ownerProfile = MindPersona.defaultOwnerProfile(AppLang.th);
  String get ownerProfile => _ownerProfile;

  String _boundaries = MindPersona.defaultBoundaries(AppLang.th);
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

  void resetOwnerProfile() =>
      setOwnerProfile(MindPersona.defaultOwnerProfile(_lang));
  void resetBoundaries() => setBoundaries(MindPersona.defaultBoundaries(_lang));

  // ═══ ภาษา ══════════════════════════════════════════════
  AppLang _lang = AppLang.th;
  AppLang get lang => _lang;

  /// ตารางข้อความของภาษาที่ใช้อยู่ ใช้ในที่ที่ไม่มี BuildContext
  S get s => S(_lang);

  /// เปลี่ยนภาษา
  ///
  /// ค่าตั้งต้นของ "ข้อมูลเกี่ยวกับเรา" "ขอบเขต" และคำสั่งน้ำเสียง ผูกกับภาษาด้วย
  /// แต่ **ห้ามเขียนทับของที่ผู้ใช้แก้เอง** — เช็คว่ายังเท่ากับค่าตั้งต้นของภาษาเดิมไหม
  /// ถ้าใช่ค่อยสลับ ถ้าไม่ใช่แปลว่าเขาเขียนเองแล้ว ปล่อยไว้
  void setLang(AppLang v) {
    if (_lang == v) return;
    final old = _lang;

    if (_ownerProfile.trim() == MindPersona.defaultOwnerProfile(old).trim()) {
      _ownerProfile = MindPersona.defaultOwnerProfile(v);
      _save('ownerProfile', _ownerProfile);
    }
    if (_boundaries.trim() == MindPersona.defaultBoundaries(old).trim()) {
      _boundaries = MindPersona.defaultBoundaries(v);
      _save('boundaries', _boundaries);
    }
    for (final c in VoiceChannel.values) {
      if (_voices[c] == VoiceProfile.defaultFor(c, old)) {
        _voices[c] = VoiceProfile.defaultFor(c, v);
        _save('voice_${c.name}', jsonEncode(_voices[c]!.toJson()));
      }
    }

    _lang = v;
    _save('lang', v.code);

    // ถ้ายังไม่มีใครคุยจริง (ยังเป็นบทตัวอย่างล้วน) ให้สลับภาษาตามไปด้วย
    // ถ้าคุยไปแล้ว ปล่อยไว้ — ประวัติจริงของผู้ใช้ห้ามถูกเขียนทับ
    if (_context.isEmpty) {
      _messages.clear();
      _seedConversation();
    }
    _notify();
  }

  // ═══ สมอง — เลือกผู้ประมวลผลได้ ═════════════════════════
  BrainProvider _brain = BrainProvider.openai;
  BrainProvider get brain => _brain;

  /// สมองที่รันบนมือถือ สร้างเมื่อเลือกใช้จริงเท่านั้น
  /// (โหลดปลั๊กอินและจอง native handle ตั้งแต่ตอนสร้าง)
  LocalBrain? _lazyLocal;
  LocalBrain get localBrain => _lazyLocal ??= LocalBrain();

  /// มี LocalBrain อยู่แล้วไหม — ใช้ตอน dispose จะได้ไม่ไปสร้างขึ้นมาใหม่
  bool get hasLocalBrain => _lazyLocal != null;

  String _homeServerUrl = HomeServerDefaults.baseUrl;
  String get homeServerUrl => _homeServerUrl;

  String _homeServerModel = HomeServerDefaults.model;
  String get homeServerModel => _homeServerModel;

  void setBrain(BrainProvider v) {
    _brain = v;
    _save('brain', v.name);
    _notify();
    if (v == BrainProvider.onDevice) localBrain.refresh();
  }

  void setHomeServerUrl(String v) {
    _homeServerUrl = v.trim();
    _save('homeServerUrl', _homeServerUrl);
    _notify();
  }

  void setHomeServerModel(String v) {
    _homeServerModel = v.trim();
    _save('homeServerModel', _homeServerModel);
    _notify();
  }

  // ═══ ชุดตัวมายด์ ═══════════════════════════════════════
  //
  // โมเดล VRM กับคลิปท่าทางไม่ได้ฝังใน APK ที่ CI build (repo เป็น public
  // และคลิป Mixamo แจกต่อไม่ได้) แอปจึงต้องโหลดเองจากที่ที่เจ้าของตั้งไว้
  //
  // ตั้งเป็นค่าที่แก้ในแอปได้ ไม่ใช่ --dart-define อย่างเดียว เพราะจะได้
  // เปลี่ยนที่เก็บชุดโดยไม่ต้อง build ใหม่ทั้งตัว ค่าตั้งต้นมาจาก dart-define
  static const _packUrlDefault =
      String.fromEnvironment('AVATAR_PACK_URL');

  String _avatarPackUrl = _packUrlDefault;
  String get avatarPackUrl => _avatarPackUrl;

  void setAvatarPackUrl(String v) {
    _avatarPackUrl = v.trim();
    _save('avatarPackUrl', _avatarPackUrl);
    _notify();
  }

  /// ชุดที่ใส่อยู่ — จำไว้ข้ามการเปิดปิดแอป ไม่งั้นเปลี่ยนชุดแล้วเปิดใหม่
  /// จะกลับไปเป็นชุดแรกตามลำดับตัวอักษร ซึ่งดูเหมือนแอปลืม
  String _avatarPackId = '';
  String get avatarPackId => _avatarPackId.isEmpty ? '' : _avatarPackId;

  void setAvatarPackId(String v) {
    _avatarPackId = v;
    _save('avatarPackId', v);
    _notify();
  }

  // ═══ ร้านของมายด์ ══════════════════════════════════════
  //
  // ที่อยู่หลังบ้าน xman studio ที่ขายชุด · ตั้งตอน build ได้ และแก้ในแอปได้
  // เพื่อให้ย้ายร้านหรือชี้ไปเซิร์ฟเวอร์ทดสอบได้โดยไม่ต้อง build ใหม่
  static const _storeDefault =
      String.fromEnvironment('STORE_BASE_URL', defaultValue: '');

  String _storeBaseUrl = _storeDefault;
  String get storeBaseUrl => _storeBaseUrl;

  void setStoreBaseUrl(String v) {
    _storeBaseUrl = v.trim();
    _save('storeBaseUrl', _storeBaseUrl);
    _notify();
  }

  /// คีย์ไลเซนส์ — ตัวบอกว่าเครื่องนี้ซื้ออะไรไปแล้ว
  ///
  /// ระบบเดียวกับ TpingApp/WinXTools (ดู docs/pack-store.md)
  /// ว่างไว้ก็เปิดร้านดูของได้ แค่ไม่รู้ว่าซื้ออะไรไปแล้ว
  String _licenseKey = '';
  String get licenseKey => _licenseKey;

  void setLicenseKey(String v) {
    _licenseKey = v.trim();
    _save('licenseKey', _licenseKey);
    _notify();
  }

  // ═══ เสียงและโมเดล ═════════════════════════════════════
  String _brainModel = OpenAiConfig.brainModel;
  String get brainModel => _brainModel;

  /// เสียงแยกตามช่องทาง — คุยในแอป / รับสายแทน / โทรออก
  /// บริบทต่างกันจริง จึงไม่ควรใช้เสียงเดียวกันทั้งหมด
  final Map<VoiceChannel, VoiceProfile> _voices = {
    for (final c in VoiceChannel.values) c: VoiceProfile.defaultFor(c, AppLang.th),
  };

  VoiceProfile voiceFor(VoiceChannel c) => _voices[c]!;

  /// โมเดลคุยสดสำหรับตอนรับสาย/โทรออกจริง (ยังไม่ได้ต่อ — docs/telephony.md)
  String _realtimeModel = OpenAiConfig.realtimeModel;
  String get realtimeModel => _realtimeModel;

  bool _voiceEnabled = true;
  bool get voiceEnabled => _voiceEnabled;

  void setBrainModel(String v) {
    _brainModel = v;
    _save('brainModel', v);
    _notify();
  }

  void setRealtimeModel(String v) {
    _realtimeModel = v;
    _save('realtimeModel', v);
    _notify();
  }

  void setVoice(VoiceChannel c, VoiceProfile p) {
    _voices[c] = p;
    _save('voice_${c.name}', jsonEncode(p.toJson()));
    _notify();
  }

  void resetVoice(VoiceChannel c) => setVoice(c, VoiceProfile.defaultFor(c, _lang));

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

  String get ringLabel => _ringSeconds == 0
      ? s.ringImmediate
      : s.ringDelayNote(_ringSeconds);

  // ═══ แชท ═══════════════════════════════════════════════
  /// บทสนทนาตัวอย่างตอนเปิดครั้งแรก
  ///
  /// เติมตอน [load] ไม่ใช่ตอนประกาศ เพราะข้อความขึ้นกับภาษาที่ผู้ใช้เคยเลือกไว้
  /// ซึ่งอ่านได้หลัง SharedPreferences พร้อมเท่านั้น
  final List<ChatMessage> _messages = [];

  void _seedConversation() {
    if (_messages.isNotEmpty) return;
    _messages.addAll([
      ChatMessage.her(s.seedGreeting),
      ChatMessage.me(s.seedAsk),
      ChatMessage.her(s.seedAnswer),
    ]);
  }

  /// แผงแชทลอยทับอวาตาร์อยู่ ถ้าเก็บยาวกว่านี้จะบังตัวเธอ
  static const _historyLimit = 6;

  /// ส่งเข้าโมเดลมากกว่าที่แสดง เพื่อให้เธอจำบริบทได้ยาวกว่าที่ตาเห็น
  static const _contextLimit = 16;

  final List<ChatMessage> _context = [];

  /// คีย์ที่เก็บบทสนทนาไว้ข้ามการเปิดปิดแอป
  ///
  /// 🔴 ของเดิม `_context` อยู่ในหน่วยความจำล้วน ปิดแอปแล้วเธอลืมหมด
  /// ทั้งที่เพิ่งคุยกันเมื่อกี้ · ซึ่งเป็นสิ่งที่ผู้ใช้อ่านว่า "โง่" มากที่สุด
  static const _prefContext = 'context';

  /// นับตาที่คุยไปตั้งแต่สกัดความจำรอบล่าสุด
  int _sinceDistill = 0;

  void _saveContext() {
    final p = _prefs;
    if (p == null) return;
    p.setString(
      _prefContext,
      jsonEncode([
        for (final m in _context) {'her': m.fromHer, 't': m.text},
      ]),
    );
  }

  void _loadContext() {
    final raw = _prefs?.getString(_prefContext);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      for (final e in list) {
        if (e is! Map) continue;
        final t = '${e['t'] ?? ''}';
        if (t.isEmpty) continue;
        _context.add(
            e['her'] == true ? ChatMessage.her(t) : ChatMessage.me(t));
      }
      // เอาท้าย ๆ ขึ้นจอด้วย ไม่งั้นเปิดแอปมาจะเห็นบทตัวอย่างเหมือนไม่เคยคุยกัน
      // ทั้งที่เธอจำได้อยู่ — จอกับความจำไม่ตรงกันคือสิ่งที่อ่านว่าแอปพัง
      if (_context.isNotEmpty) {
        _messages.addAll(_context.length > _historyLimit
            ? _context.sublist(_context.length - _historyLimit)
            : _context);
      }
    } catch (e) {
      debugPrint('state: อ่านบทสนทนาเก่าไม่ได้ — $e');
    }
  }

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
      reply = await _think();
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
  Future<void> previewVoice([VoiceChannel channel = VoiceChannel.chat]) =>
      _speakIfEnabled(s.flirtSample(effectiveFlirt), channel: channel);

  // ═══ ฟองคำพูดเหนือหัวเธอ ═══════════════════════════════
  //
  // ฟองนี้ลอยทับตัวเธอ ถ้าค้างไว้ตลอดก็บังหน้าเธอตลอด
  // จึงให้จางหายเองหลังอ่านทัน แล้วคืนจอให้เธอ
  bool _bubbleEnabled = true;
  bool get bubbleEnabled => _bubbleEnabled;

  /// 0 = ค้างไว้ไม่หาย
  int _bubbleSeconds = 5;
  int get bubbleSeconds => _bubbleSeconds;

  static const bubbleSecondChoices = <int>[0, 3, 5, 8, 12, 20];

  bool _bubbleShown = false;
  Timer? _bubbleTimer;

  /// ฟองควรโผล่ตอนนี้ไหม
  ///
  /// ซ่อนระหว่างพูดด้วย เพราะตอนพูดกล้องดึงเข้าเป็นระยะ bust
  /// หัวเธอจะขึ้นมาสูงจนฟองไปคร่อมหน้าพอดี
  bool get bubbleVisible => _bubbleEnabled && _bubbleShown && !_speaking;

  void setBubbleEnabled(bool v) {
    _bubbleEnabled = v;
    _save('bubbleEnabled', v);
    if (!v) {
      _bubbleTimer?.cancel();
      _bubbleShown = false;
    }
    _notify();
  }

  void setBubbleSeconds(int v) {
    _bubbleSeconds = v;
    _save('bubbleSeconds', v);
    // ตั้งเวลาใหม่ทันทีถ้าฟองโผล่อยู่ ผู้ใช้จะได้เห็นผลของค่าที่เพิ่งเลือก
    if (_bubbleShown) _startBubbleCountdown();
    _notify();
  }

  /// เรียกเมื่อเธอเพิ่งพูดอะไรใหม่
  ///
  /// **นาฬิกาเริ่มนับตอนฟองโผล่จริง ไม่ใช่ตอนข้อความมาถึง**
  /// เพราะระหว่างเธอพูด ฟองถูกซ่อนอยู่ (กล้องดึงเข้าใกล้ ฟองจะคร่อมหน้า)
  /// ถ้านับตั้งแต่ข้อความมา พอเธอพูดจบ 6 วิ นาฬิกา 5 วิก็หมดไปแล้ว
  /// ผลคือฟองไม่เคยโผล่ให้เห็นเลยสักครั้ง — เจอตอนทดสอบบนเครื่องจริง
  void _armBubble() {
    _bubbleTimer?.cancel();
    if (!_bubbleEnabled) {
      _bubbleShown = false;
      return;
    }
    _bubbleShown = true;
    _startBubbleCountdown();
  }

  void _startBubbleCountdown() {
    _bubbleTimer?.cancel();
    // ยังพูดอยู่ = ฟองยังไม่โผล่ ยังไม่ต้องนับ
    // จะถูกเรียกอีกทีตอนพูดจบ
    if (_speaking || !_bubbleShown || _bubbleSeconds <= 0) return;
    _bubbleTimer = Timer(Duration(seconds: _bubbleSeconds), () {
      _bubbleShown = false;
      _notify();
    });
  }

  // ═══ แผงแชท — พับเองเมื่อไม่ได้คุย ═══════════════════════
  //
  // แผงแชทกินครึ่งล่างของจอ ทำให้มองไม่เห็นเธอเต็มตัว ไม่เห็นห้อง
  // และตอนเปิดโหมดกล้องยิ่งบังของที่ต้องดู · พับเองเมื่อเงียบไปสักพัก
  // แล้วกลับมาเองเมื่อมีใครพูด

  /// เงียบไปกี่วินาทีถึงจะพับ
  ///
  /// 14 วินาทีมาจากการชั่ง: สั้นกว่านี้แผงจะหุบตอนคนกำลังอ่านคำตอบยาว ๆ
  /// ยาวกว่านี้ก็แทบไม่ต่างจากไม่พับเลย
  static const chatIdleSeconds = 14;

  bool _chatOpen = true;
  bool get chatOpen => _chatOpen;

  Timer? _chatTimer;

  /// เรียกเมื่อมีข้อความใหม่ — เปิดแผงแล้วเริ่มนับใหม่
  void _armChat() {
    _chatOpen = true;
    _startChatCountdown();
  }

  /// 🔴 นาฬิกาต้องไม่เดินตอนเธอกำลังพูด และตอนคนกำลังพิมพ์
  ///
  /// กับดักเดียวกับฟองคำพูด: ถ้านับตั้งแต่ข้อความมาถึง แผงจะหุบกลางประโยค
  /// ที่เธอกำลังพูดอยู่ · และถ้าไม่กันตอนพิมพ์ แผงจะหายไปพร้อมกับคีย์บอร์ด
  /// ระหว่างที่คนกำลังพิมพ์ค้างอยู่ ซึ่งเป็นสิ่งที่แย่ที่สุดที่จะเกิดขึ้นได้
  void _startChatCountdown() {
    _chatTimer?.cancel();
    if (_speaking || _typing || !_chatOpen) return;
    _chatTimer = Timer(const Duration(seconds: chatIdleSeconds), () {
      _chatOpen = false;
      _notify();
    });
  }

  /// เปิดแผงกลับมา — แตะที่ปุ่มพับไว้ หรือเริ่มพิมพ์
  void openChat() {
    if (_chatOpen) {
      _startChatCountdown();
      return;
    }
    _chatOpen = true;
    _startChatCountdown();
    _notify();
  }

  /// พับเอง — ให้ผู้ใช้สั่งได้ด้วย ไม่ใช่รอให้หมดเวลาอย่างเดียว
  void collapseChat() {
    _chatTimer?.cancel();
    if (!_chatOpen) return;
    _chatOpen = false;
    _notify();
  }

  /// กำลังพิมพ์อยู่ไหม — ช่องพิมพ์เป็นคนบอก
  ///
  /// state ไม่รู้จัก FocusNode และไม่ควรรู้ ไม่งั้นเทสต์ต้องมี widget tree
  bool _typing = false;
  void setTyping(bool v) {
    if (_typing == v) return;
    _typing = v;
    if (v) {
      _chatOpen = true;
      _chatTimer?.cancel();
      _notify();
    } else {
      _startChatCountdown();
    }
  }

  /// แตะที่ตัวเธอเพื่อเรียกฟองกลับมาอ่านซ้ำ
  void showBubbleAgain() {
    if (!_bubbleEnabled || bubbleText.isEmpty) return;
    _armBubble();
    _notify();
  }

  bool _speaking = false;

  /// กำลังพูดอยู่ไหม
  ///
  /// ตอนพูด `avatar.speak()` จะดึงกล้องเข้ามาเป็นระยะ bust หัวเธอจะขึ้นมาสูง
  /// ฟองคำพูดที่ artboard วางไว้สำหรับท่ายืนเต็มตัวจะไปคร่อมหน้าพอดี
  /// หน้าหลักจึงซ่อนฟองระหว่างนี้ — ข้อความเดียวกันอยู่ในแผงแชทข้างล่างอยู่แล้ว
  bool get speaking => _speaking;

  Future<void> _speakIfEnabled(String text,
      {VoiceChannel channel = VoiceChannel.chat}) async {
    final out = speaker;
    if (!_voiceEnabled) {
      debugPrint('เสียง: ปิดอยู่ในหน้าตั้งค่า');
      return;
    }
    if (out == null) {
      debugPrint('เสียง: ยังไม่ได้ต่อทางออกเสียง (speaker == null)');
      return;
    }
    final profile = voiceFor(channel);
    // เครื่อง Android พูดได้แม้ไม่มีคีย์ OpenAI จึงเช็คเฉพาะทางที่ต้องใช้คีย์
    if (profile.engine == TtsEngine.openai && !OpenAiConfig.configured) {
      debugPrint('เสียง: เลือก OpenAI ไว้แต่ build นี้ไม่มีคีย์');
      return;
    }

    try {
      debugPrint('เสียง[${channel.name}]: ${profile.engine.name} '
          '· ${profile.model} · ${profile.voice}');
      final utterance = await _speech.synthesize(text, profile: profile);
      if (_disposed) return;

      debugPrint('เสียง: ได้ ${utterance.bytes.length} ไบต์ '
          '(${utterance.mime}) ส่งเข้าเวที');
      _speaking = true;
      _notify();
      await out(utterance);
    } on OpenAiFailure catch (e) {
      // เสียงพูดไม่ออกไม่ควรทำให้บทสนทนาพัง — ข้อความยังอยู่ครบ
      debugPrint('เสียง: สังเคราะห์ไม่สำเร็จ — ${e.message}');
      _lastError = e.message;
    } finally {
      // ต้องปลดเสมอ ไม่งั้นฟองจะหายถาวรถ้าเล่นเสียงพัง
      _speaking = false;
      // ฟองเพิ่งโผล่ตอนนี้ ค่อยเริ่มนับถอยหลัง · แผงแชทก็เหมือนกัน
      _startBubbleCountdown();
      _startChatCountdown();
      _notify();
    }
  }


  /// ส่งบทสนทนาไปให้ผู้ประมวลผลที่เลือกไว้
  ///
  /// ทั้งสามทางรับ system prompt ตัวเดียวกัน บุคลิกของเธอจึงไม่เปลี่ยน
  /// ตามผู้ให้บริการ เปลี่ยนแค่ว่าใครเป็นคนคิด
  Future<String> _think() async {
    final system = MindPersona.system(
      lang: _lang,
      mode: mode,
      flirt: effectiveFlirt,
      ownerProfile: _ownerProfile,
      boundaries: _boundaries,
      memories: memory.promptBlock(),
      schedule: _calendar?.promptBlock() ?? '',
    );
    final history = [
      for (final m in _context) (fromHer: m.fromHer, text: m.text),
    ];
    return _askBrain(system, history);
  }

  /// ยิงคำถามไปที่สมองที่เลือกไว้
  ///
  /// แยกออกมาเพราะมีคนใช้สองที่: การคุยปกติ กับการสกัดความจำ
  /// ถ้าไม่แยก การสกัดจะต้องก๊อป switch สามทางนี้ไปอีกชุด แล้ววันหนึ่ง
  /// จะมีทางใดทางหนึ่งที่แก้ไปที่เดียวแล้วอีกที่ไม่ตาม
  Future<String> _askBrain(
    String system,
    List<({bool fromHer, String text})> history,
  ) async {
    switch (_brain) {
      case BrainProvider.openai:
        if (!OpenAiConfig.configured) return _cannedReply();
        debugPrint('สมอง: OpenAI $_brainModel');
        return _openai.reply(system: system, history: history, model: _brainModel);

      case BrainProvider.homeServer:
        debugPrint('สมอง: เซิร์ฟเวอร์ในบ้าน $_homeServerModel @ $_homeServerUrl');
        // เซิร์ฟเวอร์ในบ้านพูดภาษาเดียวกับ /v1/chat/completions จึงใช้ client
        // ตัวเดิมได้ แค่เปลี่ยนปลายทางและไม่ต้องส่งคีย์
        final home = OpenAiClient(
          baseUrl: _homeServerUrl,
          apiKey: '',
          // โมเดลบนคอมบ้านช้ากว่า OpenAI มาก ให้เวลามากกว่า
          timeout: const Duration(seconds: 120),
        );
        try {
          return await home.reply(
            system: system,
            history: history,
            model: _homeServerModel,
          );
        } finally {
          home.close();
        }

      case BrainProvider.onDevice:
        debugPrint('สมอง: ในเครื่อง ${localBrain.variant.label}');
        return localBrain.reply(system: system, history: history);
    }
  }

  String _cannedReply() => mode.isWork ? s.cannedWork : s.cannedLove;

  void _push(ChatMessage m) {
    // ฟองแสดงเฉพาะสิ่งที่ **เธอ** พูด ข้อความของเราไม่ต้องมีฟองเหนือหัวเธอ
    if (m.fromHer) _armBubble();
    _armChat();
    _messages.add(m);
    _context.add(m);
    if (_messages.length > _historyLimit) {
      _messages.removeRange(0, _messages.length - _historyLimit);
    }
    if (_context.length > _contextLimit) {
      _context.removeRange(0, _context.length - _contextLimit);
    }
    _saveContext();

    // สกัดความจำเป็นรอบ ไม่ใช่ทุกข้อความ — การสกัดคือการเรียกโมเดลอีกครั้ง
    // ทำทุกข้อความ = จ่ายสองเท่าช้าสองเท่าตลอดเวลา ทั้งที่คุยกันสิบประโยค
    // อาจมีเรื่องที่ควรจำแค่เรื่องเดียว
    if (m.fromHer && ++_sinceDistill >= kDistillEvery) {
      _sinceDistill = 0;
      unawaited(_distil());
    }
  }

  /// สกัดสิ่งที่ควรจำออกจากบทสนทนาล่าสุด แล้วเก็บลงความจำถาวร
  ///
  /// เงียบเสมอเมื่อพลาด — นี่เป็นงานเบื้องหลังที่ผู้ใช้ไม่ได้สั่ง
  /// ขึ้น error ให้เห็นจะกลายเป็นการรบกวนด้วยเรื่องที่เขาไม่ได้ขอ
  Future<void> _distil() async {
    if (_context.length < 4) return;
    try {
      final block = conversationBlock(
        [for (final m in _context) (fromHer: m.fromHer, text: m.text)],
        me: s.speakerMe,
        her: s.speakerHer,
      );
      final raw = await _askBrain(
        distillPrompt(_lang == AppLang.th),
        [(fromHer: false, text: block)],
      );
      if (_disposed) return;

      var kept = 0;
      for (final f in parseDistilled(raw)) {
        if (await memory.remember(f.text, kind: f.kind)) kept++;
      }
      if (kept > 0) debugPrint('memory: จำเพิ่ม $kept เรื่อง');
    } catch (e) {
      debugPrint('memory: สกัดไม่สำเร็จ — $e');
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
    _bubbleTimer?.cancel();
    _chatTimer?.cancel();
    _openai.close();
    _speech.dispose();
    if (hasLocalBrain) _lazyLocal!.dispose();
    super.dispose();
  }
}
