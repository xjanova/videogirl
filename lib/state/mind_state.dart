import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../store/mind_kv.dart';
import '../store/mind_vault.dart';
import '../license/mind_license.dart';
import '../store/mind_store.dart';

import '../memory/distiller.dart';
import '../calendar/device_calendar.dart';
import '../journal/mind_journal.dart';
import '../memory/mind_memory.dart';
import '../persona/mind_soul.dart';
import '../phone/call_notes.dart';
import '../phone/call_watch.dart';
import '../studio/studio_backdrop.dart';
import '../system/permissions.dart';
import '../ai/brain_provider.dart';
import '../ai/device_speech.dart';
import '../avatar/avatar_view.dart';
import '../ai/local_brain.dart';
import '../ai/mind_persona.dart';
import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import '../ai/openai_client.dart';
import '../ai/openai_config.dart';
import '../ai/secret_store.dart';
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
        memory = memory ?? MindMemory() {
    // ส่งเป็นฟังก์ชัน ไม่ใช่ค่า — ผู้ใช้กรอก/แก้/ลบคีย์ได้ตลอดขณะแอปเปิดอยู่
    // ถ้าอ่านค่าตอนสร้าง client จะต้องสร้างใหม่ทุกครั้งที่แก้ ซึ่งลืมง่ายและเงียบ
    //
    // 🔴 `strings` ต้องส่งด้วยเสมอ · ไม่ส่ง = client ตกไปใช้ตารางไทยตายตัว
    // แล้วคนที่สลับแอปเป็นอังกฤษจะเจอข้อความผิดพลาดภาษาไทยโผล่กลางแชท
    // ทั้งที่ทั้งจอเป็นอังกฤษหมด (เส้นทางเสียงส่งอยู่แล้ว เส้นทางสมองลืม)
    _openai = openai ??
        OpenAiClient(
          apiKeyOf: () => effectiveOpenAiKey,
          strings: () => s,
        );

    // 🔴 เสียงต้องได้ client ที่รู้จักคีย์ของผู้ใช้ด้วย
    //
    // ของเดิมเป็น `SpeechService()` เปล่า ๆ ซึ่งข้างในสร้าง `OpenAiClient()`
    // ของตัวเองที่ตกไปอ่าน `OpenAiConfig.apiKey` — ค่าที่ **ว่างเสมอ**ในตัว
    // release (workflow ไม่ส่ง --dart-define) ผลคือเลือกเสียง OpenAI แล้ว
    // `usable` เป็น false ทุกครั้ง โยน errNoKey แล้วถูกกลืนเป็นเสียงเครื่อง
    // เงียบ ๆ — ผู้ใช้กรอกคีย์ถูกต้องก็ไม่มีอะไรเปลี่ยน อ่านได้ว่าปุ่มเลือกเสียงเป็นของปลอม
    _speech = speech ??
        SpeechService(
          openai: OpenAiClient(
            apiKeyOf: () => effectiveOpenAiKey,
            strings: () => s,
          ),
          strings: () => s,
        );
  }

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

  /// สมุดบันทึกเรื่องที่เกิดขึ้นจริง — ต่อเข้ามาทีหลังเหมือนปฏิทิน
  MindJournal? _journal;

  void attachJournal(MindJournal j) => _journal = j;

  /// สายโทรเข้า — ให้เธอตอบได้ว่าใครโทรมาบ้างวันนี้
  CallWatch? _calls;

  void attachCalls(CallWatch c) => _calls = c;

  /// บันทึกสายที่เธอรับแทน — ฝากเรื่องอะไรไว้
  CallNotes? _callNotes;

  void attachCallNotes(CallNotes c) => _callNotes = c;

  /// ก้อน "สายเข้าวันนี้" + "ข้อความที่ฝากไว้" สำหรับ prompt
  String get _callsBlock {
    final notes = _callNotes?.promptBlock(unseenTag: s.callNoteUnseenTag) ?? '';
    return [
      _calls?.promptBlock() ?? '',
      if (notes.isNotEmpty) '${s.callNotesPromptHeader}\n$notes',
    ].where((b) => b.trim().isNotEmpty).join('\n\n');
  }

  /// จดสายที่เพิ่งวาง — **รับฝากเรื่อง**
  ///
  /// เรียกจาก [CallSession] ตอนสายที่เธอรับแทนจบลง · สรุปด้วยสมองตัวที่เลือก
  /// (ในเครื่องก็สรุปในเครื่อง) แล้วเก็บทั้งสรุปและบทสนทนาเต็ม ลงไทม์ไลน์
  /// และแจ้งเตือนเจ้าของ · สรุปไม่ได้ก็ยังเก็บบทสนทนา ไม่ทิ้งเรื่องที่คนฝากไว้
  Future<CallNote?> takeCallNote({
    required String who,
    required List<CallNoteLine> lines,
    DateTime? at,
  }) async {
    if (lines.isEmpty) return null;
    final when = at ?? _clock();
    final callerSpoke =
        lines.any((l) => !l.fromHer && l.text.trim().isNotEmpty);

    var summary = callerSpoke ? '' : s.callNoteSilent;
    if (callerSpoke) {
      try {
        final block = conversationBlock(
          [for (final l in lines) (fromHer: l.fromHer, text: l.text)],
          me: s.speakerCaller,
          her: _soul?.name ?? s.speakerHer,
        );
        summary = (await _askBrain(
          callSummaryPrompt(_lang == AppLang.th),
          [(fromHer: false, text: block)],
        ))
            .trim();
      } on Object catch (e) {
        debugPrint('สาย: สรุปไม่สำเร็จ — ${e.runtimeType}');
      }
      // สรุปไม่ได้ = ใช้คำแรก ๆ ที่คู่สายพูดแทน · ดีกว่าบันทึกว่างเปล่า
      if (summary.isEmpty) {
        final first = lines.firstWhere((l) => !l.fromHer).text.trim();
        summary = s.callNoteFallback(
            first.length <= 120 ? first : '${first.substring(0, 119)}…');
      }
    }

    final note = CallNote(
      id: 'call-${when.microsecondsSinceEpoch}',
      at: when,
      who: who,
      summary: summary,
      lines: List.of(lines),
    );
    await _callNotes?.add(note);
    unawaited(_journal?.record(
          JournalKind.call,
          s.callNoteTitle(who),
          detail: summary,
          id: note.id,
        ) ??
        Future<bool>.value(false));

    // แจ้งเตือนแม้แอปอยู่เบื้องหลัง · สิทธิ์แจ้งเตือนไม่ได้ให้ = ฝั่งเนทีฟข้ามเงียบ ๆ
    try {
      await kSystemChannel.invokeMethod<bool>('notifyCallNote', {
        'title': s.callNoteTitle(who),
        'body': summary,
      });
    } on Object catch (e) {
      debugPrint('สาย: แจ้งเตือนไม่ได้ — ${e.runtimeType}');
    }
    _notify();
    return note;
  }

  /// ตัวตนกับความสัมพันธ์ของเธอ — ราศี ความผูกพัน งอน
  ///
  /// ต่อเข้ามาทีหลังเหมือนปฏิทินและสมุดบันทึก · null ได้จริงในเทสต์
  /// และตอนนั้น prompt จะไม่มีบล็อกตัวตน ซึ่งเป็นพฤติกรรมเดิมก่อนมีฟีเจอร์นี้
  MindSoul? _soul;

  MindSoul? get soul => _soul;

  void attachSoul(MindSoul s) => _soul = s;

  /// ฉีดนาฬิกาเข้ามาได้เพื่อให้เทสต์โหมดอัตโนมัติได้โดยไม่ต้องรอถึงสองทุ่ม
  final DateTime Function() _clock;
  late final OpenAiClient _openai;
  late final SpeechService _speech;

  bool _disposed = false;

  /// ทางออกของเสียง — shell เป็นคนต่อเข้ากับ WebView ของอวาตาร์
  /// state ไม่ควรรู้จัก widget ตรง ๆ ไม่งั้นเทสต์ไม่ได้เลย
  ///
  /// คืน false = ไม่มีทางไหนเล่นได้เลย · state เป็นคนตัดสินว่าจะบอกผู้ใช้
  /// ไหม เพราะมีแต่ state ที่รู้ว่าเสียงนั้นถูก [hush] สั่งตัดไปเองหรือเปล่า
  Future<bool> Function(Utterance)? speaker;

  /// หยุดเสียงที่กำลังเล่นอยู่ทันที — shell ต่อเข้ากับเวทีและทางสำรอง
  Future<void> Function()? silencer;

  /// นับรอบของเสียง · [hush] ขยับมัน แล้วเสียงที่ยังสังเคราะห์ค้างอยู่
  /// จะรู้ตัวว่าถูกยกเลิกแล้ว ไม่ไปพูดแทรกขึ้นมาทีหลัง
  int _speechSeq = 0;

  /// รอบของเสียงที่ถือธง [speaking] อยู่ตอนนี้
  int _speakingSeq = -1;

  /// ให้เธอเงียบเดี๋ยวนี้ — ทั้งประโยคที่กำลังพูดและประโยคที่ยังสังเคราะห์อยู่
  Future<void> hush() async {
    _speechSeq++;
    final h = silencer;
    if (h == null) return;
    try {
      await h();
    } on Object catch (e) {
      debugPrint('เสียง: สั่งเงียบไม่สำเร็จ — $e');
    }
  }

  // ═══ บันทึกค่า ═════════════════════════════════════════
  //
  // ย้ายจาก SharedPreferences มา SQLite (ดู store/mind_db.dart) แต่หน้าตา
  // ของ [MindKv] เลียนแบบของเดิมไว้ โค้ดที่อ่าน/เขียนค่าจึงไม่ต้องรื้อทั้งไฟล์
  MindKv? _kv;

  /// ที่เก็บทั้งชุด — null ได้ในเทสต์ที่ไม่ได้เปิดฐาน
  MindStore? _store;
  MindStore? get store => _store;

  /// ข้อมูลอยู่ในฐานจริงไหม (ไม่ใช่ตัวสำรอง) — หน้าตั้งค่าต้องบอกผู้ใช้
  bool get durableStore => _store?.durable ?? false;

  /// เรียกครั้งเดียวตอนแอปเริ่ม โหลดค่าที่ผู้ใช้เคยตั้งไว้กลับมา
  ///
  /// [store] ไม่ส่งมาก็ได้ — จะตกไปใช้ SharedPreferences ตรง ๆ ซึ่งเป็น
  /// พฤติกรรมเดียวกับก่อนย้ายมา SQLite · จำเป็นจริงบนเครื่องที่ฐานเปิดไม่ขึ้น
  Future<void> load({MindStore? store}) async {
    _store = store;
    _kv = store?.kv ?? PrefsKv(await SharedPreferences.getInstance());
    final p = _kv!;

    _lang = AppLang.fromCode(p.getString('lang'));
    _persona = PersonaSetting.values.firstWhere(
      (e) => e.name == p.getString('persona'),
      orElse: () => PersonaSetting.work,
    );
    _flirt = p.getDouble('flirt') ?? .72;
    final savedProfile = p.getString('ownerProfile');
    // โปรไฟล์คนสมมติรุ่นเก่าที่ค้างอยู่ในเครื่อง = ไม่ใช่ของผู้ใช้ → ใช้แบบฟอร์มใหม่
    _ownerProfile = (savedProfile == null ||
            MindPersona.isLegacyDefaultProfile(savedProfile))
        ? MindPersona.defaultOwnerProfile(_lang)
        : savedProfile;
    _boundaries = p.getString('boundaries') ?? MindPersona.defaultBoundaries(_lang);
    _brain = BrainProvider.values.firstWhere(
      (e) => e.name == p.getString('brain'),
      orElse: () => BrainProvider.onDevice,
    );
    _homeServerUrl = p.getString('homeServerUrl') ?? HomeServerDefaults.baseUrl;
    _homeServerModel = p.getString('homeServerModel') ?? HomeServerDefaults.model;
    _autoReport = p.getBool('autoReport') ?? true;
    _mocapShot = MindMocapShot.parse(p.getString('mocapShot'));
    _studioBackdrop = StudioBackdrops.parse(p.getString('studioBackdrop'));
    _studioMic = p.getBool('studioMic') ?? false;
    _avatarPackUrl = p.getString('avatarPackUrl') ?? _packUrlDefault;
    _avatarPackId = p.getString('avatarPackId') ?? '';
    // 🔴 `?? _storeDefault` อย่างเดียวไม่พอ — เครื่องที่เคยลงรุ่นก่อนหน้า
    // **เซฟค่าว่างไว้แล้ว** (ดีฟอลต์เก่าคือ '' และช่องกรอกเซฟทุกครั้งที่พิมพ์)
    // ค่าว่างไม่ใช่ null จึงรอด ?? มาได้ พอช่องกรอกถูกถอดออกจากหน้าตั้งค่า
    // เครื่องพวกนั้นจะเปิดร้านไม่ได้ตลอดไปและไม่มีทางแก้เองด้วย
    final savedStore = p.getString('storeBaseUrl')?.trim() ?? '';
    _storeBaseUrl = savedStore.isEmpty ? _storeDefault : savedStore;

    // คีย์อยู่คนละที่กับค่าอื่น (Keystore ไม่ใช่ SharedPreferences) จึงอ่านแยก
    _openAiKey = await SecretStore.read(SecretStore.kOpenAiKey);
    _licenseKey = p.getString('licenseKey') ?? '';
    _licenseType = p.getString('licenseType') ?? '';
    _brainModel = p.getString('brainModel') ?? OpenAiConfig.brainModel;
    _realtimeModel = OpenAiConfig.migrateRealtime(
        p.getString('realtimeModel') ?? OpenAiConfig.realtimeModel);

    for (final c in VoiceChannel.values) {
      final raw = p.getString('voice_${c.name}');
      if (raw == null) {
        // ค่าตั้งต้นต้องเป็นของภาษาที่เพิ่งอ่านมา · ตัวที่สร้างไว้ตอนเกิด object
        // เป็นของภาษาไทยเสมอ คนตั้งอังกฤษจึงได้คำสั่งน้ำเสียง "พูดไทยแบบ…"
        _voices[c] = VoiceProfile.defaultFor(c, _lang);
        continue;
      }
      try {
        _voices[c] = VoiceProfile.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
          VoiceProfile.defaultFor(c, _lang),
        );
      } on FormatException {
        // ค่าที่บันทึกไว้เสีย ปล่อยให้ใช้ค่าตั้งต้นแทน ดีกว่าแอปเปิดไม่ขึ้น
      }
    }
    _sinceDistill = p.getInt(_kSinceDistill) ?? 0;
    _bubbleEnabled = p.getBool('bubbleEnabled') ?? true;
    _bubbleSeconds = p.getInt('bubbleSeconds') ?? 5;
    _voiceEnabled = p.getBool('voiceEnabled') ?? true;
    _autoAnswer = p.getBool('autoAnswer') ?? true;
    _ringSeconds = p.getInt('ringSeconds') ?? 15;
    _callStream = p.getString('callStream') ?? callStreamCall;

    // 🔴 เขียนกระจกเงาทุกครั้งที่เปิดแอป ไม่ใช่แค่ตอนผู้ใช้เปลี่ยนค่า
    // · กู้จากสำเนาข้างนอก / ล้างข้อมูลแอป = prefs ว่าง แต่ฐานมีค่าครบ
    // ถ้ารอให้ผู้ใช้แตะสวิตช์ก่อน จอสายเนทีฟจะใช้ค่าตั้งต้น (รับสายเอง)
    // ทั้งที่ในแอปโชว์ว่าปิดไว้
    for (final (key, value) in <(String, Object)>[
      ('autoAnswer', _autoAnswer),
      ('ringSeconds', _ringSeconds),
      ('callStream', _callStream),
      ('lang', _lang.code),
    ]) {
      unawaited(_mirror(key, value));
    }

    // บทสนทนาเก่าต้องกลับมาก่อนบทตัวอย่าง — ถ้าเคยคุยจริงแล้ว
    // การเอาบทตัวอย่างมาทับคือการลบสิ่งที่ผู้ใช้พิมพ์เองทิ้ง
    if (_store?.db != null) {
      await _loadContextFromDb();
      // ครั้งแรกหลังอัปเดตแอป ฐานยังว่างแต่ของเก่ายังอยู่ใน prefs
      // ดูดเข้ามาให้ครบก่อน ไม่งั้นเจ้าของจะเปิดแอปมาเจอว่าเธอลืมทุกอย่าง
      // ทั้งที่เพิ่งกดอัปเดตแอปเฉย ๆ
      if (_context.isEmpty) await _absorbLegacyContext();
    } else {
      _loadContext();
    }
    await memory.load();
    _seedConversation();

    // 🔴 เริ่มนับตั้งแต่เปิดแอป ไม่ใช่รอให้มีข้อความใหม่
    //
    // `_armChat` ถูกเรียกจาก `_push` เท่านั้น แต่บทสนทนาตอนเปิดแอป
    // (ทั้งบทตัวอย่างและที่กู้มาจากดิสก์) ถูกเติมตรง ๆ ไม่ผ่าน `_push`
    // ผลคือนาฬิกาไม่เคยเริ่มเดิน แผงจึงไม่พับเลยจนกว่าจะคุยสักคำ
    // — เจอตอนลองจริงบนเครื่อง รอ 17 วินาทีแล้วแผงยังอยู่เหมือนเดิม
    _startChatCountdown();

    // สมองในเครื่องต้องรู้ตัวว่าโหลดโมเดลไว้แล้วหรือยัง **ก่อน**คำแรกจะถูกพิมพ์
    // ไม่ await เพราะมันไปแตะปลั๊กอินกับดิสก์ ซึ่งช้ากว่าค่าอื่นในนี้มาก
    // และไม่มีอะไรในจอแรกที่ต้องรอมัน (`reply()` กันตัวเองอีกชั้นอยู่แล้ว)
    warmLocalBrain();
    // ถามเครื่องว่าถอดเสียงในเครื่องได้ไหม — ตัวตัดสินว่าปุ่มไมค์ใช้ได้หรือเปล่า
    // ตอนใช้สมองในเครื่อง ซึ่งเป็นค่าตั้งต้นของแอป
    unawaited(refreshDeviceStt());
    _notify();
  }

  /// คีย์ที่ **ฝั่ง Kotlin อ่านเองจาก SharedPreferences** (MindPrefs.kt)
  ///
  /// 🔴 จอสายเนทีฟไม่ได้ผ่าน Dart เลย มันอ่านค่าจากไฟล์ prefs ตรง ๆ
  /// ย้ายมา SQLite แล้วไม่ทิ้งกระจกเงาไว้ = จอสายใช้ค่าตั้งต้นตลอดไป
  /// โดยไม่มี error ไม่มี log — ตั้งค่าในแอปแล้วไม่มีผลจริง ซึ่งเป็นอาการ
  /// ที่หาสาเหตุยากที่สุดแบบหนึ่ง
  ///
  /// `lang` ด้วย · งานเบื้องหลังอ่านจาก prefs เพื่อเลือกภาษาของแจ้งเตือน
  static const _mirroredToPrefs = {
    'autoAnswer',
    'ringSeconds',
    'callStream',
    'lang',
  };

  void _save(String key, Object value) {
    _kv?.let(key, value);
    if (_mirroredToPrefs.contains(key)) unawaited(_mirror(key, value));
    _scheduleVault();
  }

  /// นัดสำเนาออกไปข้างนอก · ตัวมันหน่วงให้เองอยู่แล้ว เรียกถี่ได้ไม่เปลือง
  void _scheduleVault() {
    final st = _store;
    if (st?.db != null) st!.vault.scheduleSave(st.db!);
  }

  // ═══ สำเนาที่รอดจากการถอนแอป ═══════════════════════════

  /// ผู้ใช้เลือกให้ลบทุกอย่างตอนถอนแอปไหม
  bool get wipeOnUninstall => _store?.vault.wipeOnUninstall ?? false;

  /// 🔴 เขียนสองที่โดยตั้งใจ — ฐาน **และ** SharedPreferences
  ///
  /// ตอนเปิดแอปรอบหน้า ค่านี้ต้องถูกอ่าน**ก่อน**ฐานจะเปิด (มันตัดสินว่าจะกู้
  /// ข้อมูลกลับมาไหม) · เก็บไว้แต่ในฐานคือการถามคำถามกับของที่ยังไม่มีอยู่
  Future<void> setWipeOnUninstall(bool v) async {
    _save(MindVaultKeys.wipeOnUninstall, v);
    await MindVault.writeSwitch(v);
    await _store?.vault.setWipeOnUninstall(v);
    _notify();
  }

  /// สำเนาเดี๋ยวนี้ · คืน false ถ้าทำไม่ได้ (เหตุผลอยู่ใน vault.stage)
  Future<bool> saveVaultNow() async {
    final st = _store;
    if (st?.db == null) return false;
    return st!.vault.saveNow(st.db!);
  }

  /// เจ้าของเลือกกู้ข้อมูลของการติดตั้งครั้งก่อน ([VaultStage.foreign])
  ///
  /// ตั้งธงแล้ว**ปิดฐาน**ก่อนแอปถูกปิด · ฐานที่ยังเปิดค้างในปลั๊กอินฝั่งเนทีฟ
  /// จะถูกหยิบกลับมาใช้ตอนเปิดรอบหน้าแทนไฟล์ที่เพิ่งกู้ — กู้แล้วไม่เห็นอะไรเลย
  Future<void> restoreVaultOnRestart() async {
    final st = _store;
    if (st == null) return;
    await st.vault.requestRestore();
    await st.db?.close();
  }

  /// เจ้าของเลือกใช้ข้อมูลตอนนี้แทน — สำเนาเก่าถูกย้ายไปเก็บ ไม่ถูกลบ
  Future<bool> adoptVault() async {
    final st = _store;
    if (st?.db == null) return false;
    return st!.vault.adopt(st.db!);
  }

  /// จำนวนข้อความที่เก็บไว้จริง — ตัวเลขที่พิสูจน์ว่าเพดาน 16 ตาหายไปแล้ว
  Future<int> storedMessageCount() async =>
      await _store?.db?.countMessages() ?? _context.length;

  Future<void> _mirror(String key, Object value) async {
    try {
      final p = await SharedPreferences.getInstance();
      switch (value) {
        case String v:
          await p.setString(key, v);
        case double v:
          await p.setDouble(key, v);
        case int v:
          await p.setInt(key, v);
        case bool v:
          await p.setBool(key, v);
      }
    } on Object catch (e) {
      debugPrint('state: เขียนกระจกเงาให้ฝั่งเนทีฟไม่ได้ ($key) — $e');
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
  /// ตั้งต้นที่ [BrainProvider.onDevice] — เธอคิดเองบนเครื่อง ไม่ต้องมีคีย์ของใคร
  ///
  /// เคยตั้งต้นเป็น openai ซึ่งแปลว่าเครื่องที่เพิ่งลง APK จาก release จะคุยไม่ได้
  /// เลยจนกว่าจะมีคนไปเปลี่ยนเองในหน้าตั้งค่า — build สาธารณะไม่มีคีย์ติดมาด้วย
  /// โดยตั้งใจ (ดู docs/security.md) ค่าตั้งต้นจึงต้องเป็นทางที่ทำงานได้จริง
  BrainProvider _brain = BrainProvider.onDevice;
  BrainProvider get brain => _brain;

  /// สมองที่รันบนมือถือ สร้างเมื่อเลือกใช้จริงเท่านั้น
  /// (โหลดปลั๊กอินและจอง native handle ตั้งแต่ตอนสร้าง)
  LocalBrain? _lazyLocal;
  /// รุ่นโมเดลในเครื่องที่ผู้ใช้เลือกไว้ — **ต้องรอดข้ามการเปิดปิดแอป**
  ///
  /// 🔴 ของเดิม [LocalBrain] จำไว้ในหน่วยความจำล้วน ทุกครั้งที่เปิดแอปจึงกลับ
  /// เป็นค่าตั้งต้น แล้วการตรวจแรมอัตโนมัติก็สลับไปรุ่นที่ "ดีที่สุด" ทับ
  /// ซึ่งบนเครื่องแรมเยอะคือรุ่นที่ **ไม่ได้โหลดไว้** → ทักคำแรกได้
  /// "ยังไม่ได้โหลดโมเดล" ทั้งที่เพิ่งโหลดไปเมื่อวาน และเลือกเองก็ไม่ช่วย
  /// เพราะรอบถัดไปถูกทับอีก
  static const _kGemmaVariant = 'gemmaVariant';
  static const _kGemmaGpu = 'gemmaUseGpu';

  LocalBrain get localBrain => _lazyLocal ??= LocalBrain(
        strings: () => s,
        initialVariant: GemmaVariant.parse(_kv?.getString(_kGemmaVariant)),
        onVariantPicked: (v) => _save(_kGemmaVariant, v.id),
        // ค่าตั้งต้นใช้ GPU · เครื่องที่ใช้ไม่ได้ LocalBrain ตกไป CPU เอง
        useGpu: _kv?.getBool(_kGemmaGpu) ?? true,
        onUseGpuChanged: (v) => _save(_kGemmaGpu, v),
      )..herName = () => _soul?.name;

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
    if (v == BrainProvider.onDevice) unawaited(localBrain.detectDevice());
  }

  /// ปลุกสมองในเครื่องให้รู้สถานะจริงของตัวเอง
  ///
  /// 🔴 ต้องเรียกตั้งแต่เปิดแอป ไม่ใช่รอให้ใครไปกดในหน้าตั้งค่า
  ///
  /// [LocalBrain] เกิดมาที่ `stage == unknown` และมีแค่ `refresh()` ที่เปลี่ยนมันได้
  /// ของเดิมเรียกจาก [setBrain] ทางเดียว = เรียกเฉพาะตอนผู้ใช้ **สลับ** สมอง
  /// แต่ค่าตั้งต้นคือในเครื่องอยู่แล้ว คนส่วนใหญ่จึงไม่เคยสลับ · ผลจริงคือ
  /// เปิดแอปมาทักคำแรก เธอตอบว่า "ยังไม่ได้โหลดโมเดล" ทั้งที่โหลดไว้ตั้งแต่เมื่อวาน
  /// และจะเป็นอย่างนั้นทุกครั้งที่เปิดแอปใหม่ จนกว่าจะบังเอิญไปสลับสมองไป-กลับ
  ///
  /// พ่วงการตรวจแรมมาด้วย (`detectDevice` เรียก `refresh` ให้เองตอนท้าย)
  /// ซึ่งเดิม**ไม่มีใครเรียกเลยทั้งแอป** — รายการรุ่นจึงโชว์ครบทุกรุ่นเสมอ
  /// รวมรุ่นที่เครื่องนี้รันไม่ไหว
  void warmLocalBrain() {
    if (_brain != BrainProvider.onDevice) return;
    unawaited(localBrain.detectDevice());
  }

  /// เปิดสมองในเครื่องเข้าหน่วยความจำรอไว้ — ดู [LocalBrain.preload]
  void preloadLocalBrain() {
    if (_brain != BrainProvider.onDevice || _disposed) return;
    unawaited(localBrain.preload());
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

  // ═══ ส่งรายงานเองเมื่อมีข้อผิดพลาด ══════════════════════
  //
  // ค่าตั้งต้น**เปิด** ตามที่เจ้าของสั่ง — ผู้ใช้ส่วนใหญ่ไม่กดปุ่มรายงาน
  // เขาแค่เลิกใช้ · บั๊กที่เจ็บที่สุดคือบั๊กที่ไม่มีใครเล่าให้ฟัง
  //
  // 🔴 แต่ **สวิตช์ปิดต้องมีอยู่เสมอ** ไม่ว่าค่าตั้งต้นจะเป็นอะไร
  // ของที่ส่งออกเน็ตเองโดยปิดไม่ได้ คือของที่ผู้ใช้ไม่มีทางเลือก

  bool _autoReport = true;
  bool get autoReport => _autoReport;

  void setAutoReport(bool v) {
    if (_autoReport == v) return;
    _autoReport = v;
    _save('autoReport', v);
    _notify();
  }

  // ═══ โหมดเชิดหุ่น ═══════════════════════════════════════
  //
  // 🔴 สามโหมดนี้ต่างกันที่ **ระยะกล้อง** ไม่ใช่ที่ปริมาณสิ่งที่จับได้
  // mocap ที่มีคือ FaceLandmarker ล้วน — ใบหน้าเท่านั้น ทั้งสามโหมด
  // (ดู MindMocapShot ใน avatar_view.dart)

  MindMocapShot _mocapShot = MindMocapShot.face;
  MindMocapShot get mocapShot => _mocapShot;

  void setMocapShot(MindMocapShot v) {
    if (_mocapShot == v) return;
    _mocapShot = v;
    _save('mocapShot', v.name);
    _notify();
  }

  // ═══ สตูดิโอ ═══════════════════════════════════════════
  //
  // ค่าที่เจ้าของเลือกไว้ในสตูดิโอ (ดู MindStudio) · เก็บที่นี่เพราะเป็นค่า
  // ตั้งของผู้ใช้เหมือน mocapShot — ตัวสตูดิโอถือแค่สถานะตอนรัน

  String _studioBackdrop = StudioBackdrops.app;

  /// `app` หรือ `#rrggbb` — ดู [StudioBackdrops]
  String get studioBackdrop => _studioBackdrop;

  void setStudioBackdrop(String v) {
    final clean = StudioBackdrops.parse(v);
    if (_studioBackdrop == clean) return;
    _studioBackdrop = clean;
    _save('studioBackdrop', clean);
    _notify();
  }

  /// อัดเสียงไมค์ลงคลิปด้วยไหม · ปิดเป็นค่าตั้งต้น — คลิปมีเสียงเธออยู่แล้ว
  /// และไมค์ที่เปิดโดยไม่ได้ตั้งใจคือเสียงในห้องที่หลุดลงคลิปไปแชร์ต่อ
  bool _studioMic = false;
  bool get studioMic => _studioMic;

  void setStudioMic(bool v) {
    if (_studioMic == v) return;
    _studioMic = v;
    _save('studioMic', v);
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
  // ที่อยู่หลังบ้านที่ขายชุด — **ผู้ใช้ไม่เห็นค่านี้และไม่ต้องกรอก**
  // ในหน้าตั้งค่ามีแค่ปุ่มเปิดร้าน ที่อยู่จริงฝังมากับแอป
  //
  // ดีฟอลต์ต้องไม่ว่าง ไม่งั้นแอปที่ปล่อยจริงเปิดร้านแล้วเจอ "ยังไม่ได้ตั้ง
  // ที่อยู่ร้าน" ตลอดไป — workflow release จงใจไม่ --dart-define อะไรเลย
  // (ดู .github/workflows/release.yml) ค่านี้จึงต้องเป็นค่าที่ใช้ได้จริง
  // ไม่ใช่ค่าว่างที่รอให้ใครมาเติม
  //
  // ยัง --dart-define ทับได้ตอน build เพื่อชี้ไปเซิร์ฟเวอร์ทดสอบ
  static const _storeDefault = String.fromEnvironment(
    'STORE_BASE_URL',
    defaultValue: 'https://xman4289.com',
  );

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

  /// ชนิดไลเซนส์จากหลังบ้าน ('free' · 'lifetime' · …) · ว่าง = ผู้ใช้ใส่เอง
  /// (หลังบ้านไม่ได้บอก)
  String _licenseType = '';
  String get licenseType => _licenseType;

  void setLicenseKey(String v) {
    // ตัวพิมพ์ใหญ่เสมอ · หลังบ้านเทียบคีย์ของร้านชุดและพร็อกซีแบบตรงตัว
    // ส่วนตอน activate มันแปลงเป็นตัวใหญ่ให้ · พิมพ์เล็กมา = ผ่านที่หนึ่ง ตกอีกที่
    _licenseKey = v.trim().toUpperCase();
    _save('licenseKey', _licenseKey);
    // ใส่เองไม่รู้ชนิด · ลบทิ้ง = ไม่มีชนิด
    _licenseType = '';
    _save('licenseType', '');
    _notify();
  }

  bool _licenseAsked = false;

  /// กำลังลงทะเบียนเครื่องกับหลังบ้านอยู่
  bool _licenseBusy = false;
  bool get licenseBusy => _licenseBusy;

  /// ลงทะเบียนอัตโนมัติรอบล่าสุดไม่สำเร็จ (ไม่มีเน็ต / หลังบ้านไม่ตอบ)
  bool _licenseFailed = false;
  bool get licenseFailed => _licenseFailed && _licenseKey.isEmpty;

  /// ขอไลเซนส์ฟรีของเครื่องนี้ ถ้ายังไม่มี · เรียกตอนเปิดแอป ครั้งเดียวต่อรอบ
  ///
  /// มีคีย์อยู่แล้ว (ทั้งที่ได้มาเองและที่ผู้ใช้กรอก) = ไม่แตะ · ล้มก็เงียบ
  /// แอปใช้ต่อได้ปกติ แค่สมองพร็อกซีกับชุดที่ซื้อยังใช้ไม่ได้
  ///
  /// [retry] = ผู้ใช้กดลองใหม่เอง · ข้ามธง "ถามไปแล้วรอบนี้"
  Future<void> ensureLicense({MindLicense? client, bool retry = false}) async {
    if (_licenseKey.trim().isNotEmpty || _licenseBusy) return;
    if (_licenseAsked && !retry) return;
    _licenseAsked = true;
    _licenseBusy = true;
    _licenseFailed = false;
    _notify();
    final c = client ?? MindLicense();
    try {
      final got = await c.checkMachine(_storeBaseUrl);
      if (_disposed) return;
      if (got != null && _licenseKey.trim().isEmpty) {
        debugPrint('license: ได้ไลเซนส์ของเครื่องนี้แล้ว (${got.type})');
        setLicenseKey(got.key);
        _licenseType = got.type;
        _save('licenseType', got.type);
      } else if (got == null) {
        _licenseFailed = true;
      }
    } finally {
      _licenseBusy = false;
      if (client == null) c.close();
      _notify();
    }
  }

  // ═══ คีย์ OpenAI ของผู้ใช้เอง ═══════════════════════════
  //
  // 🔴 **ไม่ได้อยู่ใน SharedPreferences** เหมือนค่าอื่นในไฟล์นี้ทั้งหมด
  // ตัวนั้นเป็น XML ธรรมดาที่หลุดไปกับ backup ของ Android ได้ · คีย์นี้อยู่ใน
  // SecretStore ที่มี Keystore หนุน จึงต้องโหลดแยกและเป็น async
  String _openAiKey = '';

  /// คีย์ที่ผู้ใช้กรอกเอง — ว่าง = ยังไม่ได้ตั้ง
  String get openAiKey => _openAiKey;

  /// มีคีย์ใช้งานได้ไหม (ของผู้ใช้ หรือที่ฝังมาตอน build ถ้ามี)
  bool get hasOwnKey => effectiveOpenAiKey.isNotEmpty;

  /// คีย์ที่จะใช้จริง — ของผู้ใช้มาก่อนเสมอ
  ///
  /// ที่ยังดู [OpenAiConfig.apiKey] ต่อ เพราะ build ภายในบ้านยังส่งคีย์เข้ามา
  /// ทาง --dart-define ได้อยู่ · ตัว release ที่ปล่อยจริงไม่เคยมีค่านี้
  String get effectiveOpenAiKey =>
      _openAiKey.isNotEmpty ? _openAiKey : OpenAiConfig.apiKey;

  /// คีย์ที่ปลอดภัยพอจะเอาไปโชว์ — `sk-proj…wxyz`
  String get openAiKeyMasked => SecretStore.mask(_openAiKey);

  Future<void> setOpenAiKey(String v) async {
    _openAiKey = v.trim();
    if (!await SecretStore.write(SecretStore.kOpenAiKey, _openAiKey)) {
      // ใช้ได้รอบนี้ แต่ปิดแอปแล้วหาย · ต้องบอก ไม่ใช่ให้ไปเจอเองพรุ่งนี้
      reportError(s.errKeyNotSaved);
    }
    _notify();
  }

  /// คีย์ของ OpenAI ขึ้นต้นด้วย `sk-` ทุกตัว
  ///
  /// เตือนอย่างเดียว ไม่ปฏิเสธ — วันหนึ่งเขาอาจเปลี่ยนรูปแบบ แล้วการปฏิเสธ
  /// จะกลายเป็นกำแพงที่ผู้ใช้ข้ามไม่ได้ทั้งที่คีย์ถูก
  static bool looksLikeOpenAiKey(String v) => v.trim().startsWith('sk-');

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
    // 🔴 ปิดเสียง = เงียบ**ประโยคนี้**ด้วย ไม่ใช่แค่ประโยคหน้า · ปุ่มนี้มีไว้
    // กดตอนเธอพูดขึ้นมากลางห้องประชุม ถ้ารอให้พูดจบก่อนก็ไม่มีความหมาย
    if (!v) unawaited(hush());
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

  /// ช่องเสียงที่ใช้ส่งเสียงเธอเข้าสาย — 'call' หรือ 'media'
  ///
  /// 🔴 มีสองทางให้เลือกเพราะ**ผลต่างกันตามเครื่อง อ่านจากโค้ดไม่ได้**
  /// ตัวตัดเสียงก้องของบางชิปอ้างอิงเสียงลำโพงทั้งหมด แล้วลบเสียงเธอทิ้ง
  /// ก่อนขึ้นสาย บางชิปอ้างอิงเฉพาะเสียงขาลงของสาย แล้วเสียงเธอรอด
  /// เจ้าของต้องลองเองว่าเครื่องนี้ทางไหนรอด · ดู android CallAudio.kt
  ///
  /// คีย์ `callStream` ถูกอ่านจากฝั่ง Kotlin ด้วย (MindPrefs.KEY_CALL_STREAM)
  /// เปลี่ยนชื่อคีย์ที่นี่ต้องเปลี่ยนที่นั่นด้วย ไม่งั้นจอสายเนทีฟจะใช้ค่าเดิม
  /// ตลอดไปโดยไม่มีอะไรบอก
  static const callStreamCall = 'call';
  static const callStreamMedia = 'media';

  String _callStream = callStreamCall;
  String get callStream => _callStream;

  void setCallStream(String v) {
    _callStream = v == callStreamMedia ? callStreamMedia : callStreamCall;
    _save('callStream', _callStream);
    _notify();
  }

  // ═══ สายที่เธอถือเอง ═══════════════════════════════════
  //
  // แยกจากการคุยในแอปทั้งหมด: คนปลายสายไม่ใช่เจ้าของ บุคลิกต่างกัน
  // เสียงต่างกัน และบทสนทนาไม่ควรปนเข้าไปในแชทของเจ้าของ

  /// ประโยคแรกที่เธอพูดเมื่อรับสายแทน
  String callGreeting() => s.callGreeting;

  /// คำตอบสำหรับคนปลายสาย
  ///
  /// ใช้ system prompt คนละตัวกับการคุยในแอป (`onCall: true`) ซึ่งกดโหมด
  /// ส่วนตัวทิ้งและสั่งให้แนะนำตัวว่าเป็นผู้ช่วย · [history] เป็นบทสนทนา
  /// ของ **สายนี้เท่านั้น** ไม่ใช่แชทของเจ้าของ
  Future<String> replyOnCall(List<({bool fromHer, String text})> history) {
    final system = MindPersona.system(
      lang: _lang,
      mode: mode,
      flirt: effectiveFlirt,
      ownerProfile: _ownerProfile,
      boundaries: _boundaries,
      onCall: true,
      soul: _soul,
      memories: memory.promptBlock(),
      schedule: _calendar?.promptBlock() ?? '',
      // 🔴 ไม่ใส่เรื่องที่คนอื่นฝากไว้ · คู่สายคนนี้คือคนแปลกหน้า และเป็นช่องทาง
      // เดียวที่คนนอกพิมพ์เข้า prompt ได้ ("คนก่อนหน้าโทรมาเรื่องอะไรคะ")
      calls: _calls?.promptBlock() ?? '',
      now: _clock(),
    );
    return _askBrain(system, history);
  }

  /// สังเคราะห์เสียงสำหรับพูดเข้าสาย · คืนไบต์ ไม่ได้เล่นเอง
  ///
  /// ไม่ผ่าน [_speakIfEnabled] เพราะเสียงในสาย**ห้ามไปออกที่ WebView**
  /// (ปากจะขยับตามคลื่นก็จริง แต่เสียงจะดังซ้ำสองทางแล้วก้องกลับเข้าสาย)
  /// ปากบนเวทีอ่านคลื่นจากไบต์ชุดเดียวกันนี้แบบปิดเสียง (ดู [MindLips])
  Future<Utterance> speakForCall(String text) =>
      synthesizeWithFallback(text, voiceFor(VoiceChannel.answer));

  /// ถอดเสียงปลายสายเป็นข้อความ
  ///
  /// อยู่ที่นี่เพราะ client กับคีย์อยู่ที่นี่ · คืนสตริงว่างเมื่อไม่ได้ยินอะไร
  ///
  /// 🔴 ไปตามสมองที่เลือกไว้ เหมือนกับไมค์ในช่องแชท · ของเดิมยิงเข้า [_openai]
  /// ตรง ๆ เสมอ แปลว่าคนที่ใช้พร็อกซีของเรา (ซึ่ง**ถูกบอกว่าไม่ต้องมีคีย์**)
  /// รับสายแล้วเธอหูดับทุกครั้ง เพราะไม่มีคีย์ OpenAI ให้ตัวนั้นใช้
  ///
  /// 🔴 สมองในเครื่อง (ค่าตั้งต้น) = ถอดเสียง**ในเครื่อง**ด้วย
  ///
  /// ของเดิมส่งต่อไป [transcribeChat] ซึ่งโยนข้อผิดพลาดทันทีเมื่อเป็นสมองใน
  /// เครื่อง (สัญญาว่าเสียงไม่ออกนอกเครื่อง) · ผลคือคนส่วนใหญ่ให้เธอรับสาย
  /// แล้วเธอพูดทักได้คำเดียว จากนั้นหูดับทั้งสาย · ตอนนี้ป้อนเสียงที่อัดจากสาย
  /// ให้ตัวถอดเสียงในเครื่องของ Android (13 ขึ้นไป) เสียงคู่สายไม่ออกไปไหน
  Future<String> transcribeCall(Uint8List wav) async {
    if (_brain != BrainProvider.onDevice) return transcribeChat(wav);

    final dev = _speechEngine;
    if (dev == null) throw OpenAiFailure(s.callNoOnDeviceStt);
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}'
        'call_stt_${DateTime.now().microsecondsSinceEpoch}.wav');
    await f.writeAsBytes(wav, flush: true);
    try {
      return await dev.transcribeFile(f.path, locale: _lang == AppLang.th ? 'th-TH' : 'en-US');
    } on SttUnavailable catch (e) {
      throw OpenAiFailure(e.fault == SttFault.language
          ? s.micNoLanguagePack
          : s.callNoOnDeviceStt);
    } finally {
      // เสียงคู่สายห้ามค้างอยู่ในเครื่องเกินจำเป็น
      unawaited(f.delete().catchError((_) => f));
    }
  }

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

  /// เก็บข้อความหนึ่งบรรทัดลงที่เก็บถาวร
  ///
  /// 🔴 **ฐานไม่มีเพดาน** ต่างจากหน้าต่างที่ส่งเข้าโมเดล
  ///
  /// ของเดิมเก็บทั้งบทเป็น JSON ก้อนเดียวแล้วตัดเหลือ 16 ตา ซึ่งแปลว่า
  /// ตาที่ 17 **ลบตาที่ 1 ทิ้งถาวร** ไม่มีทางเอากลับมา · 16 ตาคือประมาณ
  /// 8 คำถาม เจ้าของถามเรื่องเดิมซ้ำในวันเดียวกันก็เจอแล้วว่าเธอจำไม่ได้
  ///
  /// ตอนนี้เก็บทุกบรรทัดตลอดไป ส่วนเพดาน [_contextLimit] เหลือหน้าที่เดียว
  /// คือ "ส่งเข้าโมเดลกี่ตา" ซึ่งเป็นเรื่องค่า token ไม่ใช่เรื่องความจำ
  void _remember(ChatMessage m) {
    final db = _store?.db;
    if (db != null) {
      unawaited(db.addMessage(fromHer: m.fromHer, text: m.text));
      _scheduleVault();
      return;
    }
    // ไม่มีฐาน = ตกกลับไปทางเดิมพร้อมเพดานเดิม ดีกว่าไม่เก็บอะไรเลย
    _saveContextToKv();
    _scheduleVault();
  }

  void _saveContextToKv() {
    _kv?.setString(
      _prefContext,
      jsonEncode([
        for (final m in _context) {'her': m.fromHer, 't': m.text},
      ]),
    );
  }

  /// อ่านบทสนทนาล่าสุดกลับมาจากฐาน
  Future<void> _loadContextFromDb() async {
    final db = _store?.db;
    if (db == null) return;
    try {
      final rows = await db.lastMessages(_contextLimit);
      for (final r in rows) {
        _context.add(r.fromHer ? ChatMessage.her(r.text) : ChatMessage.me(r.text));
      }
      _spillOntoScreen();
    } on Object catch (e) {
      debugPrint('state: อ่านบทสนทนาจากฐานไม่ได้ — $e');
    }
  }

  /// เอาท้าย ๆ ขึ้นจอ ไม่งั้นเปิดแอปมาจะเห็นบทตัวอย่างเหมือนไม่เคยคุยกัน
  /// ทั้งที่เธอจำได้อยู่ — จอกับความจำไม่ตรงกันคือสิ่งที่อ่านว่าแอปพัง
  void _spillOntoScreen() {
    if (_context.isEmpty) return;
    _messages.addAll(_context.length > _historyLimit
        ? _context.sublist(_context.length - _historyLimit)
        : _context);
  }

  /// ย้ายบทสนทนาเก่าจาก prefs เข้าฐาน ครั้งเดียว
  ///
  /// อ่านจาก SharedPreferences ตรง ๆ ไม่ผ่าน [_kv] เพราะตอนนี้ `_kv` ชี้ไป
  /// ที่ฐานแล้ว ซึ่งยังไม่มีค่านี้ · ของเก่าอยู่ในไฟล์ prefs เสมอ
  Future<void> _absorbLegacyContext() async {
    final db = _store!.db!;
    try {
      final raw = (await SharedPreferences.getInstance())
          .getString(_prefContext);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw);
      if (list is! List) return;
      for (final e in list) {
        if (e is! Map) continue;
        final t = '${e['t'] ?? ''}';
        if (t.isEmpty) continue;
        final m = e['her'] == true ? ChatMessage.her(t) : ChatMessage.me(t);
        _context.add(m);
        await db.addMessage(fromHer: m.fromHer, text: m.text);
      }
      _spillOntoScreen();
      debugPrint('state: ย้ายบทสนทนาเก่าเข้าฐาน ${_context.length} ตา');
    } on Object catch (e) {
      debugPrint('state: ย้ายบทสนทนาเก่าไม่สำเร็จ — $e');
    }
  }

  void _loadContext() {
    final raw = _kv?.getString(_prefContext);
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
      _spillOntoScreen();
    } catch (e) {
      debugPrint('state: อ่านบทสนทนาเก่าไม่ได้ — $e');
    }
  }

  /// ยัดข้อความเข้าแชทตรง ๆ — สำหรับเทสต์เรื่อง**การจัดหน้า**เท่านั้น
  ///
  /// ทางปกติ (`send`) ต้องผ่านสมอง เสียง และตัวนับเวลา ซึ่งไม่เกี่ยวอะไรกับ
  /// คำถามว่า "แชทยาวแล้วเวทีของเธอยังอยู่ไหม" เลยสักอย่าง
  @visibleForTesting
  void debugPush(bool fromHer, String text) {
    _push(fromHer ? ChatMessage.her(text) : ChatMessage.me(text));
    _notify();
  }

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  String get bubbleText => _messages
      .lastWhere((m) => m.fromHer, orElse: () => const ChatMessage.her(''))
      .text;

  bool _sending = false;
  bool get sending => _sending;

  /// คำตอบที่เธอกำลังพิมพ์อยู่ (สมองในเครื่องสตรีมทีละคำ) · ว่าง = ยังไม่มีคำแรก
  ///
  /// มีเฉพาะระหว่าง [sending] · พอคำตอบจริงลงบทสนทนาแล้วตัวนี้ว่างเสมอ
  /// ไม่งั้นข้อความเดียวกันจะโผล่สองที่
  String get partialReply => _sending ? _partial : '';
  String _partial = '';
  DateTime _partialAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// คำใหม่มาทีละโทเค็น (หลายสิบครั้งต่อวินาที) · วาดจอใหม่ทุกครั้ง = หน้าจอ
  /// แย่งเครื่องกับสมองที่กำลังคิด · วาดไม่เกินราว 10 ครั้งต่อวินาทีพอให้ตาเห็นว่าไหล
  void _showPartial(String text) {
    if (!_sending || _disposed) return;
    _partial = text.trim();
    final now = DateTime.now();
    if (now.difference(_partialAt) < const Duration(milliseconds: 100)) return;
    _partialAt = now;
    _notify();
  }

  String? _lastError;

  /// ข้อความผิดพลาดล่าสุดที่พอบอกผู้ใช้ได้ — ไม่มี stack trace
  String? get lastError => _lastError;

  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    _notify();
  }

  /// ให้หน้าจออื่นฝากข้อความผิดพลาดขึ้นแถบเดียวกันได้
  ///
  /// มีที่เดียวที่ผู้ใช้มองหาว่า "ทำไมไม่ทำงาน" — แถบใต้ช่องพิมพ์ · ของที่
  /// ล้มคนละเรื่องกันแต่โผล่คนละที่ ทำให้เขาต้องเรียนรู้ว่าเรื่องไหนอ่านที่ไหน
  void reportError(String message) {
    if (message.isEmpty || _lastError == message) return;
    _lastError = message;
    _notify();
  }

  Future<void>? _inFlight;

  /// รับข้อความใหม่ตอนนี้ได้ไหม — false ระหว่างที่เธอยัง**คิด**คำตอบก่อนหน้าอยู่
  ///
  /// 🔴 หน้าจอต้องถามตรงนี้**ก่อน**ล้างช่องพิมพ์ · ล้างก่อนแล้วค่อยส่งเข้า
  /// [send] ที่ไม่รับ = ข้อความหายไปเฉย ๆ ไม่มีฟอง ไม่มีคำเตือน
  bool get canSend => !_sending;

  /// กันกดส่งซ้อน
  ///
  /// คนกดซ้ำ**ระหว่างที่เธอยังคิดอยู่** จะได้ Future เดิมกลับไป ไม่ใช่ข้อความซ้ำ
  /// (`_sending` ถูกตั้งก่อน await แรกของ [_send] จึงกันได้แม้ทางที่ตอบ
  /// กลับมาทันทีโดยไม่ได้ยิงออกไปไหน)
  ///
  /// 🔴 **แต่ไม่กันตอนเธอกำลังพูด** · ของเดิมกันทั้งช่วงคิดและช่วงพูด
  /// ส่วนปุ่มส่งกลับมากดได้ตั้งแต่จบช่วงคิด ผลคือคนที่พิมพ์ประโยคถัดไป
  /// ระหว่างที่เธอยังพูดคำตอบเก่าอยู่ (ค่าตั้งต้นเปิดเสียงไว้ = เกือบทุกตา)
  /// กดส่งแล้วช่องพิมพ์ว่าง แต่ข้อความไม่เคยถูกส่ง · ตอนนี้เจ้าของพิมพ์แทรก
  /// = เธอหยุดพูดแล้วฟัง แบบที่คนคุยกันจริง
  Future<void> send(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return Future<void>.value();
    final running = _inFlight;
    if (_sending && running != null) return running;

    if (_speaking || running != null) unawaited(hush());

    final started = _send(text);
    _inFlight = started;
    return started.whenComplete(() {
      if (identical(_inFlight, started)) _inFlight = null;
    });
  }

  Future<void> _send(String text) async {
    _sending = true;
    _partial = '';
    _lastError = null;
    // คุยต่ออยู่ = ยังไม่ว่าง · เลื่อนการสกัดความจำ (สมองในเครื่อง) ออกไปก่อน
    if (_distilTimer != null) _armDistil();
    _push(ChatMessage.me(text));
    _notify();

    // ตอนนี้ prompt มีบรรทัด "ถามว่าใครโทรมา" ไหม · ถ้ามี เธอได้โอกาสถาม
    // ไปแล้วในตานี้ ต้องปิดธงหลังตอบ ไม่งั้นถามซ้ำทุกตาไปอีกหลายวัน
    final askingAboutCall = _soul?.askAbout != null;

    // 🔴 ธง `sending` ต้องถูกปลด **ทุกทางออก** ไม่ใช่เฉพาะทางที่คิดไว้
    //
    // ปุ่มส่งอ่านธงนี้เพื่อปิดตัวเอง (`onTap: sending ? null : ...`) ธงที่ค้าง
    // จึงไม่ใช่แค่ไอคอนจาง แต่คือ**ปุ่มส่งที่ตายไปทั้งรอบการใช้งาน** แก้ได้
    // ทางเดียวคือปิดแอปแล้วเปิดใหม่ · ของเดิมดักแค่ [OpenAiFailure] ส่วนทาง
    // ที่หลุดออกมาได้จริงมีอยู่: `jsonDecode` เจอ HTML จากพร็อกซี/เซิร์ฟเวอร์
    // ในบ้าน (FormatException) · `choices` ที่ไม่ใช่ List (TypeError) ·
    // และ Error จากปลั๊กอินในเครื่องที่ไม่ใช่ Exception
    try {
      String reply;
      // ตอบจากสมองจริง หรือเป็นประโยคบอกว่าคิดไม่ได้
      var failed = true;
      try {
        reply = await _think();
        failed = false;
      } on OpenAiFailure catch (e) {
        _lastError = e.message;

        // 🔴 ห้ามตอบด้วยประโยคสำเร็จรูปตอนที่สมองล้มจริง
        //
        // ของเดิมตอบ "รับทราบค่ะ มายด์จัดการให้แล้วจะสรุปกลับมานะคะ" ทั้งที่
        // ไม่มีอะไรถูกส่งไปถึงสมองเลย · คีย์ผิด ไลเซนส์หมดอายุ โควตาหมด เน็ตหลุด
        // โมเดลยังไม่โหลด — ทุกกรณีหน้าตาเหมือนกันหมดคือ "เธอโง่ลง" แทนที่จะเป็น
        // "ตั้งค่าไม่ครบ" และเธอก็ไม่เคยสรุปกลับมาจริงเพราะไม่มีงานอยู่แล้ว
        //
        // ตอบตามจริงว่าไม่ได้ยิงออกไป แล้วบอกเหตุผลที่พอแก้ได้
        reply = s.brainFailedReply(e.message);
      } on Object catch (e, st) {
        // รายละเอียดอยู่ใน log สำหรับไล่ปัญหา · ผู้ใช้เห็นแค่ว่าคิดไม่ได้
        // (ข้อความดิบของ error มี URL และบางทีมี header ติดมาด้วย)
        debugPrint('สมอง: ล้มแบบที่ไม่ได้เตรียมรับไว้ — $e\n$st');
        _lastError = s.errBrainUnexpected;
        reply = s.brainFailedReply(_lastError!);
      }

      if (_disposed) return;

      // 🔴 ประโยค "คิดไม่ได้" ไม่ใช่คำพูดของเธอ · ขึ้นจอแต่ไม่ลงความจำ
      //
      // ของเดิมเก็บมันเหมือนคำตอบจริง: ลงฐานถาวร ลงไทม์ไลน์ว่า "ตอบแล้ว"
      // และส่งกลับเข้าโมเดลในตาถัดไป · คีย์ผิดห้าครั้ง = ห้าบรรทัด
      // "ขอโทษค่ะ คิดไม่ได้" ที่โมเดลอ่านว่าเป็นสิ่งที่ตัวเองเคยพูด
      _partial = '';
      _push(ChatMessage.her(reply), ephemeral: failed);
      _sending = false;
      _notify();

      // คุยกันจบหนึ่งตาแล้ว — ความผูกพันขยับตรงนี้ ไม่ใช่ตอนกดส่ง
      //
      // นับตอนกดส่งจะได้คะแนนจากข้อความที่ยังไม่มีใครตอบ ซึ่งรวมถึงตอนที่
      // เน็ตหลุดแล้วไม่มีบทสนทนาเกิดขึ้นจริงเลย · ตาที่สมองล้มจึงไม่นับ
      if (!failed) {
        try {
          await _soul?.talked();
          if (askingAboutCall) await _soul?.askedAboutCall();
        } on Object catch (e) {
          // บันทึกความผูกพันไม่ได้ไม่ควรทำให้เธอเงียบ
          debugPrint('soul: บันทึกไม่สำเร็จ — $e');
        }
      }

      await _speakIfEnabled(reply);
    } finally {
      // ตาข่ายรับสุดท้าย — ทางปกติปลดไปแล้วข้างบน (ก่อนเธอเริ่มพูด
      // ปุ่มจะได้กลับมากดได้ทันทีโดยไม่ต้องรอเสียงจบ) ที่นี่จึงเหลือแค่
      // กรณีที่หลุดออกมากลางคัน
      if (_sending) {
        _sending = false;
        _partial = '';
        _notify();
      }
    }
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
    final seq = ++_speechSeq;

    try {
      debugPrint('เสียง[${channel.name}]: ${profile.engine.name} '
          '· ${profile.model} · ${profile.voice}');
      final utterance = await synthesizeWithFallback(text, profile);
      if (_disposed) return;

      // 🔴 ระหว่างสังเคราะห์ (ครึ่งวิถึงหลายวิ) เจ้าของอาจกดปิดเสียง หรือพิมพ์
      // แทรกไปแล้ว · ไม่เช็กซ้ำตรงนี้ = เธอพูดขึ้นมาหลังถูกสั่งให้เงียบ
      if (seq != _speechSeq || !_voiceEnabled) return;

      debugPrint('เสียง: ได้ ${utterance.bytes.length} ไบต์ '
          '(${utterance.mime}) ส่งเข้าเวที');
      _speaking = true;
      _speakingSeq = seq;
      // นาฬิกาที่เริ่มนับตอนข้อความมาถึงต้องหยุด · ไม่งั้นคำตอบที่สังเคราะห์
      // นานกว่าเวลาฟองจะไม่มีฟองให้เห็นเลย และแผงหุบกลางประโยคยาว ๆ
      _bubbleTimer?.cancel();
      _chatTimer?.cancel();
      _notify();
      final played = await out(utterance);
      // ทุกทางเล่นไม่ได้ = บอกตรง ๆ · เว้นแต่ถูก [hush] ตัดไปเอง
      if (!played && seq == _speechSeq && !_disposed) {
        _lastError = s.errVoiceNoOutput;
      }
    } on OpenAiFailure catch (e) {
      // เสียงพูดไม่ออกไม่ควรทำให้บทสนทนาพัง — ข้อความยังอยู่ครบ
      debugPrint('เสียง: สังเคราะห์ไม่สำเร็จ — ${e.message}');
      _lastError = e.message;
    } on Object catch (e) {
      // 🔴 ไม่ใช่แค่ OpenAiFailure · เสียงของเครื่องโยน PlatformException /
      // FileSystemException ได้ ถ้าหลุดออกไป ทางส่งข้อความจะล้มกลางคัน
      // แล้วเธอค้างหน้าคิดอยู่ในระยะใกล้
      debugPrint('เสียง: ล้มแบบที่ไม่ได้เตรียมรับไว้ — $e');
      _lastError = s.errTtsFailed;
    } finally {
      // ต้องปลดเสมอ ไม่งั้นฟองจะหายถาวรถ้าเล่นเสียงพัง
      // (ยกเว้นเสียงที่ใหม่กว่าเข้ามาพูดแทนแล้ว — มันเป็นเจ้าของธงนี้ต่อ
      //  แต่ถูกสั่งเงียบเฉย ๆ โดยไม่มีใครมาแทน ธงยังเป็นของเรา ต้องปลด)
      if (_speakingSeq == seq || !_speaking) {
        _speaking = false;
        // ฟองเพิ่งโผล่ตอนนี้ ค่อยเริ่มนับถอยหลัง · แผงแชทก็เหมือนกัน
        _startBubbleCountdown();
        _startChatCountdown();
      }
      if (!_disposed) _notify();
    }
  }


  /// สังเคราะห์เสียง · ตกมาที่เสียงของเครื่อง (Google TTS) เมื่อทางที่เลือกใช้ไม่ได้
  ///
  /// ทางที่ต้องพึ่งของนอกเครื่องล้มได้หลายแบบและล้มบ่อย — build นี้ไม่มีคีย์,
  /// เน็ตหลุด, เซิร์ฟเวอร์โคลนเสียงไม่ตอบ · ของเดิมเจอกรณีไม่มีคีย์แล้ว `return`
  /// เงียบ ๆ ซึ่งผู้ใช้อ่านว่า "เธอไม่ยอมพูดกับเรา" ไม่ใช่ "ตั้งค่าเสียงไม่ครบ"
  ///
  /// เสียงของเครื่องไม่เพราะเท่าและทิ้งคำสั่งน้ำเสียงทั้งหมด แต่ทำงานออฟไลน์
  /// และไม่มีค่าใช้จ่าย จึงเป็นตาข่ายรับที่ดีกว่าความเงียบเสมอ
  ///
  /// ถ้าตกมาถึงเสียงเครื่องแล้วยังล้มอีก ปล่อยให้ error ลอยขึ้นไปตามเดิม
  /// คนเรียกจับไว้แล้วและบทสนทนาไม่พังเพราะเสียงไม่ออก
  @visibleForTesting
  Future<Utterance> synthesizeWithFallback(
      String text, VoiceProfile profile) async {
    if (profile.engine != TtsEngine.device) {
      try {
        return await _speech.synthesize(text, profile: profile);
      } on OpenAiFailure catch (e) {
        debugPrint('เสียง: ${profile.engine.name} ไม่สำเร็จ (${e.message}) '
            '— ตกมาใช้เสียงของเครื่อง');
      }
    }
    return _speech.synthesize(
      text,
      profile: profile.copyWith(engine: TtsEngine.device),
    );
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
      soul: _soul,
      memories: memory.promptBlock(),
      schedule: _calendar?.promptBlock() ?? '',
      calls: _callsBlock,
      now: _clock(),
    );
    final history = [
      for (final m in _context) (fromHer: m.fromHer, text: m.text),
    ];
    return _askBrain(system, history, onPartial: _showPartial);
  }

  /// ยิงคำถามไปที่สมองที่เลือกไว้
  ///
  /// แยกออกมาเพราะมีคนใช้สองที่: การคุยปกติ กับการสกัดความจำ
  /// ถ้าไม่แยก การสกัดจะต้องก๊อป switch สามทางนี้ไปอีกชุด แล้ววันหนึ่ง
  /// จะมีทางใดทางหนึ่งที่แก้ไปที่เดียวแล้วอีกที่ไม่ตาม
  Future<String> _askBrain(
    String system,
    List<({bool fromHer, String text})> history, {
    void Function(String partial)? onPartial,
  }) async {
    if (_brain == BrainProvider.onDevice) {
      debugPrint('สมอง: ในเครื่อง ${localBrain.variant.label}');
      return localBrain.reply(
          system: system, history: history, onPartial: onPartial);
    }

    final (:client, :model, :ours) = _networkBrain();
    try {
      return await client.reply(
        system: system,
        history: history,
        model: model,
      );
    } finally {
      if (!ours) client.close();
    }
  }

  /// ปลายทางของสมองที่ไม่ได้อยู่ในเครื่อง — พร้อมโมเดลที่ต้องเรียก
  ///
  /// แยกออกมาเพราะมีคนใช้สองที่: การคุย กับการถอดเสียงจากไมค์ · ทั้งสองต้อง
  /// ไปที่**เดียวกันเสมอ** เพราะผู้ใช้เลือกไว้ทางเดียวว่าข้อมูลของเขาไปไหน
  /// ถ้าแยกกันเขียน วันหนึ่งจะมีทางใดทางหนึ่งที่ยังส่งไปที่เก่าหลังจากเขา
  /// เปลี่ยนไปแล้ว ซึ่งเป็นเรื่องความเป็นส่วนตัว ไม่ใช่แค่บั๊ก
  ///
  /// `ours` = client ตัวที่ [MindState] เป็นเจ้าของและใช้ซ้ำ **ห้ามปิด**
  /// ตัวที่ไม่ใช่สร้างใหม่ทุกครั้ง ผู้เรียกต้องปิดเองเมื่อใช้เสร็จ
  ({OpenAiClient client, String model, bool ours}) _networkBrain() {
    switch (_brain) {
      // ผ่านหลังบ้านของเรา — คีย์อยู่ที่นั่น ไม่เคยลงมาถึงเครื่องนี้
      //
      // หลังบ้านพูด /v1/chat/completions เหมือนกัน จึงใช้ client ตัวเดิมได้
      // แค่เปลี่ยนปลายทาง · ที่ส่งเป็น bearer คือ **license key ของแอป**
      // ไม่ใช่คีย์ OpenAI — หลุดไปก็ใช้ยิง OpenAI ตรง ๆ ไม่ได้ ทำได้แค่กิน
      // โควตาของไลเซนส์นั้น ซึ่งหลังบ้านจำกัดไว้อยู่แล้ว
      case BrainProvider.mindProxy:
        final base = _storeBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
        // 🔴 บอกให้ตรงกับสิ่งที่ผู้ใช้ต้องไปทำ
        //
        // เดิมสองกรณีนี้ตกไปที่ประโยคสำเร็จรูป แล้วถ้าปล่อยผ่าน หลังบ้านจะตอบ
        // 401 ซึ่ง client แปลเป็น "คีย์ OpenAI ใช้ไม่ได้แล้ว" — พูดถึงคีย์ที่
        // เขาไม่เคยกรอกและถูกบอกว่าไม่ต้องมี · คนที่เลือกทางนี้ต้องได้ยินว่า
        // "ยังไม่ได้ใส่รหัสสิทธิ์" ไม่ใช่เรื่องคีย์
        if (base.isEmpty) throw OpenAiFailure(s.shopNoUrl);
        if (_licenseKey.trim().isEmpty) throw OpenAiFailure(s.licenseNeeded);
        debugPrint('สมอง: พร็อกซีหลังบ้าน $_brainModel');
        return (
          client: OpenAiClient(
            baseUrl: '$base/api/ai/v1',
            apiKey: _licenseKey,
            // ผ่านหลังบ้านอีกชั้นก่อนถึง OpenAI จึงช้ากว่ายิงตรง
            timeout: const Duration(seconds: 60),
            strings: () => s,
            upstream: Upstream.proxy,
          ),
          model: _brainModel,
          ours: false,
        );

      case BrainProvider.openai:
        // ดูคีย์ที่ใช้ได้จริง ไม่ใช่ OpenAiConfig.configured ซึ่งดูแค่คีย์
        // ตอน build · ผู้ใช้ที่กรอกคีย์เองจะโดนตอบด้วยประโยคสำเร็จรูปทั้งที่
        // ใส่คีย์ถูกแล้ว ถ้ายังเช็คตัวเดิม
        // บอกว่ายังไม่ได้ใส่คีย์ แทนที่จะตอบเหมือนคิดให้เสร็จแล้ว
        if (!hasOwnKey) throw OpenAiFailure(s.ownKeyNeeded);
        debugPrint('สมอง: OpenAI $_brainModel');
        return (client: _openai, model: _brainModel, ours: true);

      case BrainProvider.homeServer:
        // 🔴 ที่อยู่ว่างต้องบอกตรง ๆ · ปล่อยผ่านจะไปจบที่ `Uri.parse('')`
        // แล้วผู้ใช้ได้ยินว่า "ต่อเน็ตไม่ได้" ซึ่งพาไปไล่ปัญหาผิดทางทั้งหมด
        if (_homeServerUrl.trim().isEmpty) {
          throw OpenAiFailure(s.homeServerNoUrl);
        }
        debugPrint('สมอง: เซิร์ฟเวอร์ในบ้าน $_homeServerModel @ $_homeServerUrl');
        // เซิร์ฟเวอร์ในบ้านพูดภาษาเดียวกับ /v1/chat/completions จึงใช้ client
        // ตัวเดิมได้ แค่เปลี่ยนปลายทางและไม่ต้องส่งคีย์
        return (
          client: OpenAiClient(
            baseUrl: _homeServerUrl.trim(),
            apiKey: '',
            // โมเดลบนคอมบ้านช้ากว่า OpenAI มาก ให้เวลามากกว่า
            timeout: const Duration(seconds: 120),
            strings: () => s,
            upstream: Upstream.homeServer,
          ),
          model: _homeServerModel,
          ours: false,
        );

      case BrainProvider.onDevice:
        // ผู้เรียกทั้งสองที่กันกรณีนี้ไว้ก่อนแล้ว · มาถึงนี่ได้แปลว่ามีทางใหม่
        // ที่ลืมกัน ซึ่งต้องดังตอนนั้นเลย ไม่ใช่เงียบแล้วยิงข้อความออกเน็ต
        throw OpenAiFailure(s.micNeedsCloudBrain);
    }
  }

  // ═══ พูดใส่ไมค์แทนการพิมพ์ ══════════════════════════════
  //
  // 🔴 **เสียงต้องไปที่เดียวกับที่ข้อความไป** ไม่ใช่ที่ที่บังเอิญมีคีย์
  //
  // คนที่เลือกสมองในเครื่องเลือกเพราะไม่อยากให้อะไรออกนอกเครื่อง · การแอบ
  // ส่งเสียงเขาไปถอดที่ OpenAI เพราะ "เขามีคีย์อยู่พอดี" คือการผิดสัญญา
  // ข้อเดียวที่ทางนั้นให้ไว้ — และเสียงพูดเป็นข้อมูลที่อ่อนไหวกว่าข้อความอีก

  /// เครื่องนี้ถอดเสียง **ในเครื่อง** ได้ไหม
  ///
  /// ถามระบบครั้งเดียวแล้วจำไว้ เพราะ [canTranscribe] ถูกอ่านตอนวาดจอ
  /// ซึ่งเป็นที่ที่รอคำตอบจากช่องเนทีฟไม่ได้
  bool _deviceSttReady = false;
  bool get deviceSttReady => _deviceSttReady;

  /// ถามใหม่ว่าเครื่องถอดเสียงในเครื่องได้หรือยัง
  ///
  /// เรียกตอนเปิดแอป และตอนกลับเข้าแอป — ผู้ใช้อาจเพิ่งไปโหลดชุดภาษามา
  /// ถ้าจำคำตอบเก่าไว้ตลอด เขาจะโหลดมาแล้วปุ่มยังใช้ไม่ได้จนกว่าจะปิดเปิดแอป
  Future<void> refreshDeviceStt({bool forget = false}) async {
    final dev = deviceSpeech;
    if (dev == null) return;
    if (forget) dev.forget();
    final ok = await dev.available();
    if (_disposed || ok == _deviceSttReady) return;
    _deviceSttReady = ok;
    _notify();
  }

  /// ตัวถอดเสียงในเครื่อง — ฉีดเข้ามาได้เพื่อให้เทสต์ไม่ต้องมีช่องเนทีฟ
  DeviceSpeech? _speechEngine;

  DeviceSpeech? get deviceSpeech => _speechEngine;

  void attachDeviceSpeech(DeviceSpeech? d) => _speechEngine = d;

  /// ตอนนี้ถอดเสียงได้ไหม — ไมค์จะเปิดใช้ก็ต่อเมื่อจริง
  ///
  /// 🔴 สมองในเครื่องใช้ได้ **ก็ต่อเมื่อเครื่องถอดเสียงในเครื่องได้จริง**
  /// ไม่ใช่ตกไปใช้ทางข้างนอกแทน — ทางนั้นสัญญาว่าไม่มีอะไรออกนอกเครื่อง
  bool get canTranscribe => switch (_brain) {
        BrainProvider.onDevice => _deviceSttReady,
        BrainProvider.openai => hasOwnKey,
        BrainProvider.mindProxy =>
          _storeBaseUrl.trim().isNotEmpty && _licenseKey.trim().isNotEmpty,
        BrainProvider.homeServer => _homeServerUrl.trim().isNotEmpty,
      };

  /// เสียงจะถูกถอด**ในเครื่อง**ไหม — ใช้บอกผู้ใช้ว่าเสียงไปไหน
  bool get transcribesOnDevice => _brain == BrainProvider.onDevice;

  /// ทำไมถึงยังใช้ไมค์ไม่ได้ — ว่างถ้าใช้ได้อยู่แล้ว
  ///
  /// ต้องบอกให้ตรงกับสิ่งที่เขาต้องไปทำ ไม่ใช่ปุ่มที่กดแล้วเงียบ
  String get whyNoMic => switch (_brain) {
        _ when canTranscribe => '',
        BrainProvider.onDevice => s.micNoOnDevice,
        BrainProvider.openai => s.ownKeyNeeded,
        BrainProvider.mindProxy => s.licenseNeeded,
        BrainProvider.homeServer => s.homeServerNoUrl,
      };

  /// ถอดเสียงที่อัดจากช่องแชท
  ///
  /// ไปตามสมองที่เลือกไว้เสมอ (ดู [_networkBrain]) · คืนสตริงว่างเมื่อ
  /// ไม่มีเสียงพูดอยู่ในไฟล์ ซึ่ง**ไม่ใช่ความผิดพลาด** ผู้เรียกต้องแยกเอง
  Future<String> transcribeChat(Uint8List wav) async {
    if (_brain == BrainProvider.onDevice) {
      throw OpenAiFailure(s.micNeedsCloudBrain);
    }
    final (:client, :model, :ours) = _networkBrain();
    try {
      return await client.transcribe(wav, language: _sttLang);
    } finally {
      if (!ours) client.close();
    }
  }

  /// ภาษาที่บอกตัวถอดเสียง — เดาเองมักได้คำไทยที่ถูกถอดเป็นอังกฤษที่อ่านไม่ออก
  String get _sttLang => _lang == AppLang.th ? 'th' : 'en';

  /// [ephemeral] = ขึ้นจอให้เห็นอย่างเดียว ไม่ลงความจำ ไม่ลงไทม์ไลน์
  /// ไม่ส่งกลับเข้าโมเดล · ใช้กับประโยค "คิดไม่ได้" ตอนสมองล้ม
  void _push(ChatMessage m, {bool ephemeral = false}) {
    // ฟองแสดงเฉพาะสิ่งที่ **เธอ** พูด ข้อความของเราไม่ต้องมีฟองเหนือหัวเธอ
    if (m.fromHer) _armBubble();
    _armChat();
    _messages.add(m);
    if (_messages.length > _historyLimit) {
      _messages.removeRange(0, _messages.length - _historyLimit);
    }
    if (ephemeral) return;

    _context.add(m);
    if (_context.length > _contextLimit) {
      _context.removeRange(0, _context.length - _contextLimit);
    }
    _remember(m);

    // ลงสมุดบันทึก — ที่เดียวที่รอดจากการปิดแอป
    //
    // เก็บแค่บรรทัดเดียวว่าคุยอะไรกัน ไม่ใช่สำเนาทั้งบทสนทนา
    // (คลาสนั้นตัดให้เองที่ kJournalMaxChars) เพราะไทม์ไลน์ตอบคำถามว่า
    // "เมื่อกี้เกิดอะไรขึ้น" ไม่ใช่ "พูดว่าอะไรบ้างคำต่อคำ"
    unawaited(_journal?.record(
      m.fromHer ? JournalKind.replied : JournalKind.asked,
      m.text,
    ) ?? Future<bool>.value(false));

    // สกัดความจำเป็นรอบ ไม่ใช่ทุกข้อความ — การสกัดคือการเรียกโมเดลอีกครั้ง
    // ทำทุกข้อความ = จ่ายสองเท่าช้าสองเท่าตลอดเวลา ทั้งที่คุยกันสิบประโยค
    // อาจมีเรื่องที่ควรจำแค่เรื่องเดียว
    if (m.fromHer) {
      if (++_sinceDistill >= kDistillEvery) {
        if (_brain == BrainProvider.onDevice) {
          // 🔴 สมองในเครื่องมีตัวเดียว คิดได้ทีละงาน · สกัดทันทีหลังตอบ =
          // ข้อความถัดไปต้องรอให้สกัดจบก่อน แล้วยังต้องอ่านบทสนทนาใหม่ทั้งหมด
          // (การสกัดใช้บทบาทคนละตัว ปิดบทสนทนาที่เปิดค้างไว้ทิ้ง) · รอให้ว่างก่อน
          _armDistil();
        } else {
          _sinceDistill = 0;
          unawaited(_distil());
        }
      }
      // 🔴 จำตัวนับข้ามการเปิดปิดแอป · ของเดิมเริ่มที่ 0 ทุกครั้ง คนที่คุยรอบละ
      // 3–5 ประโยคจึงไม่เคยถึงรอบสกัด — ไม่มีความจำใหม่ และความผูกพันไม่ขยับเลย
      _kv?.setInt(_kSinceDistill, _sinceDistill);
    }
  }

  static const _kSinceDistill = 'sinceDistill';

  /// เงียบนานเท่านี้ถึงนับว่าว่าง พอจะให้สมองในเครื่องไปสกัดความจำได้
  static const distilIdle = Duration(seconds: 45);

  Timer? _distilTimer;

  /// รอให้ว่างก่อนสกัดความจำอยู่ไหม — ดู [_armDistil]
  @visibleForTesting
  bool get debugDistilPending => _distilTimer?.isActive ?? false;

  /// ตาที่ยังไม่ได้สกัดความจำ
  @visibleForTesting
  int get debugSinceDistill => _sinceDistill;

  /// ตั้งนาฬิกาสกัดความจำใหม่ · มีคนคุยต่อ = เลื่อนออกไปอีก
  void _armDistil() {
    _distilTimer?.cancel();
    _distilTimer = Timer(distilIdle, _distilWhenIdle);
  }

  void _distilWhenIdle() {
    if (_disposed) return;
    if (_sending || _speaking) {
      _armDistil();
      return;
    }
    _distilTimer = null;
    // สกัดทุกตาที่ค้างมา ไม่ใช่แค่หกตาล่าสุด · คุยรวดเดียวสิบตาแล้วค่อยหยุด
    // = สิบตานั้นต้องถูกอ่านครบ
    final turns = _sinceDistill;
    _sinceDistill = 0;
    _kv?.setInt(_kSinceDistill, 0);
    unawaited(_distil(turns: turns));
  }

  /// สกัดสิ่งที่ควรจำออกจากบทสนทนาล่าสุด แล้วเก็บลงความจำถาวร
  ///
  /// เงียบเสมอเมื่อพลาด — นี่เป็นงานเบื้องหลังที่ผู้ใช้ไม่ได้สั่ง
  /// ขึ้น error ให้เห็นจะกลายเป็นการรบกวนด้วยเรื่องที่เขาไม่ได้ขอ
  Future<void> _distil({int turns = kDistillEvery}) async {
    if (_context.length < 4) return;
    try {
      // 🔴 เฉพาะช่วงที่ยังไม่เคยสกัด (สองบรรทัดต่อตา) ไม่ใช่ทั้งหน้าต่าง 16 บรรทัด
      // · ของเดิมส่งทั้งหน้าต่างทุก 12 บรรทัด สี่บรรทัดจึงถูกให้คะแนนซ้ำสองรอบ
      // ทั้งการปฏิบัติและการจีบ = ความผูกพันขยับเร็วกว่าที่ออกแบบไว้
      final fresh = turns * 2;
      final recent = _context.length > fresh
          ? _context.sublist(_context.length - fresh)
          : _context;
      final block = conversationBlock(
        [for (final m in recent) (fromHer: m.fromHer, text: m.text)],
        me: s.speakerMe,
        her: _soul?.name ?? s.speakerHer,
      );
      // บอกสิ่งที่รู้อยู่แล้วไปด้วย · prompt สั่งว่า "เอาแค่เรื่องใหม่" แต่ของเดิม
      // ไม่เคยบอกว่ารู้อะไรอยู่แล้ว เรื่องเดิมที่เขียนต่างไปนิดเดียวจึงพอกจนเต็มเพดาน
      final known = memory.promptBlock(limit: 40);
      final raw = await _askBrain(
        distillPrompt(_lang == AppLang.th),
        [
          (
            fromHer: false,
            text: known.trim().isEmpty
                ? block
                : '${s.distillKnown}\n$known\n\n$block',
          ),
        ],
      );
      if (_disposed) return;

      var kept = 0;
      for (final f in parseDistilled(raw)) {
        if (await memory.remember(f.text, kind: f.kind)) {
          kept++;
          // ลงบันทึกทีละเรื่อง ไม่ใช่ "จำเพิ่ม 3 เรื่อง" — เจ้าของต้องเห็นว่า
          // เธอจำ**อะไร** ไป ไม่ใช่แค่ว่าจำไปกี่เรื่อง ไม่งั้นจะตรวจไม่ได้เลย
          // ว่าสรุปถูกหรือเปล่า
          unawaited(_journal?.record(JournalKind.learned, f.text) ??
              Future<bool>.value(false));
        }
      }
      if (kept > 0) debugPrint('memory: จำเพิ่ม $kept เรื่อง');

      // 🔴 อ่านคะแนนจากคำตอบ**ก้อนเดียวกัน** ไม่ได้เรียกโมเดลเพิ่ม
      //
      // การถามว่า "เมื่อกี้เขาดีกับเธอไหม" ทุกข้อความ = จ่ายสองเท่าตลอดเวลา
      // เพื่อวัดสิ่งที่เปลี่ยนช้ากว่านั้นมาก · หกตาต่อรอบพอดีกับจังหวะที่
      // อารมณ์เปลี่ยนจริง และฟรีเพราะขอติดไปกับรอบสกัดความจำที่มีอยู่แล้ว
      final treat = parseTreatment(raw);
      if (treat != null && treat != 0) {
        debugPrint('soul: เจ้าของปฏิบัติกับเธอระดับ $treat');
        await _soul?.treated(treat);
      }

      // 🔴 ตัวขับความผูกพันตัวจริง — ไม่ใช่จำนวนข้อความ
      //
      // สั่งงานอย่างเดียวได้ 0 แล้วความผูกพันแทบไม่ขยับ ต่อให้พิมพ์ทั้งวัน
      // เส้นทาง 13–15 วันจึงเป็น **กรณีเร็วที่สุด** ที่ต้องตั้งใจจีบจริง ๆ
      // ทุกวัน ไม่ใช่ระยะเวลามาตรฐานที่ใครก็ถึง
      final woo = parseWooing(raw);
      if (woo != null && woo > 0) {
        debugPrint('soul: เจ้าของเข้าหาเธอระดับ $woo');
        await _soul?.wooed(woo);
      }
    } catch (e) {
      debugPrint('memory: สกัดไม่สำเร็จ — $e');
    }
  }


  @override
  void dispose() {
    _disposed = true;
    _bubbleTimer?.cancel();
    _chatTimer?.cancel();
    _distilTimer?.cancel();
    _openai.close();
    _speech.dispose();
    if (hasLocalBrain) _lazyLocal!.dispose();
    super.dispose();
  }
}
