import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../store/mind_kv.dart';
import '../store/mind_vault.dart';
import '../license/mind_license.dart';
import '../store/mind_store.dart';

import '../memory/chat_recall.dart';
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
import '../ai/local_server_scan.dart';
import '../ai/mind_audio.dart';
import '../ai/mind_persona.dart';
import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import '../i18n/strings_settings.dart';
import '../i18n/strings_voice.dart';
import '../ai/openai_client.dart';
import '../ai/openai_config.dart';
import '../ai/premium_catalog.dart';
import '../ai/premium_tts.dart';
import '../ai/proxy_account.dart';
import '../ai/realtime_chat.dart';
import '../ai/web_tools.dart';
import '../phone/call_tags.dart';
import '../phone/call_target.dart';
import '../phone/outgoing_call.dart';
import '../phone/phone_lookup.dart';
import '../phone/call_knowledge.dart';
import '../phone/call_lessons.dart';
import '../phone/owner_gate.dart';
import '../phone/identity_gate.dart';
import '../hands/hands_bridge.dart';
import '../hands/hands_tag.dart';
import '../hands/phone_agent.dart';
import '../hands/phone_macro.dart';
import '../hands/phone_task.dart';
import '../i18n/strings_hands.dart';
import '../phone/live_call.dart';
import '../phone/realtime_call.dart';
import '../brainx/brainx_cloud.dart';
import '../brainx/brainx_link.dart';
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
          premium: PremiumTts(
            keyOf: premiumKey,
            azureRegion: () => _azureRegion,
            strings: () => s,
          ),
        );
    // ความจำเปลี่ยน = ไฟล์ความจำบนสมอง BrainX ต้องตาม (ถ้าเชื่อมอยู่)
    this.memory.addListener(_queueMemory);
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

  /// สิทธิ์ของทั้งแอป (ตัวเดียวกับการ์ดสิทธิ์) · ให้เธอขอสิทธิ์ตอนเปิดดูของในเครื่องครั้งแรก
  MindPermissions? _perms;

  void attachPermissions(MindPermissions p) => _perms = p;

  // ═══ สมุดโทรศัพท์ ประวัติการโทร SMS (ดู PhoneLookup) ════════════════
  //
  // เจ้าของ: "ตอนนี้เธอไม่เห็นสมุดโทรศัพท์ ไม่เห็นสายโทรเข้าออกล่าสุด หรือ sms ต้องทำให้เธอรับรู้ได้"

  PhoneLookup? _lazyPhoneLookup;
  PhoneLookup get phoneLookup =>
      _lazyPhoneLookup ??= PhoneLookup(askPermission: _askPhonePermission, targets: callTargets);

  @visibleForTesting
  set debugPhoneLookup(PhoneLookup l) => _lazyPhoneLookup = l;

  /// ขอสิทธิ์ตอนเธอเปิดดูครั้งแรก · เจ้าของถามเองในแชทอยู่แล้ว กล่องขอจึงตรงเรื่องที่ถาม ·
  /// แอปไม่อยู่หน้าจอ / ปฏิเสธถาวรไปแล้ว = ไม่ขอ (กล่องไม่ขึ้น เธอบอกทางไปเปิดเอง)
  Future<bool> _askPhonePermission(MindPermission p) async {
    final perms = _perms;
    if (perms == null || _disposed || !_appVisible || perms.isBlocked(p)) return false;
    // กล่องขอค้าง (Activity ถูกทำลายกลางกล่อง แล้วไม่มีใครตอบ) ต้องไม่ทำให้แชทรอตลอดกาล
    await perms.request(p).timeout(const Duration(seconds: 90), onTimeout: () {});
    return !_disposed && perms.of(p);
  }

  /// สายโทรเข้า — ให้เธอตอบได้ว่าใครโทรมาบ้างวันนี้
  CallWatch? _calls;

  void attachCalls(CallWatch c) {
    _calls = c;
    var was = c.state;
    // สายจบ = จอสายเพิ่งจดว่าเธอรับเองไหม · อ่านเก็บไว้ (รายงานอ่านแบบไม่ต้องรอช่อง)
    c.addListener(() {
      if (c.state == CallState.idle) unawaited(lastAutoAnswer());
      if (was != CallState.idle && c.state == CallState.idle) _outgoingEnded();
      was = c.state;
    });
    unawaited(lastAutoAnswer());
  }

  // ═══ น้องมายโทรออกแทนเจ้าของ ═══════════════════════════════
  //
  // เจ้าของ: "ทำส่วน โทรออกต่อ" · ดู lib/phone/outgoing_call.dart · ทุกสายผ่านกล่องยืนยัน

  PendingCall? _pendingCall;
  PendingCall? get pendingCall => _pendingCall;
  int _callSeq = 0;

  /// สายที่น้องมายกำลังโทรออกอยู่ (หลังยืนยัน) · null = ไม่มี
  OutgoingTask? _outgoing;
  OutgoingTask? get outgoing => _outgoing;
  bool _outgoingAnswered = false;

  /// เจ้าของให้เธอถามกลางสายได้ไหม (สวิตช์ในกล่องยืนยัน · ตั้งต้นจาก [OutgoingRules.noAsking]) ·
  /// false = ไม่มีเครื่องมือ ask_owner เธอรับเรื่องไว้เองทั้งสาย
  bool _outgoingAskOk = true;
  bool get outgoingMayAskOwner => _outgoing != null && _outgoingAskOk;

  /// ชื่อที่น้องมายใช้เรียกเจ้าของตอนโทรแทน ("เลขาของคุณต้น") · ว่าง = "เจ้าของเบอร์นี้"
  String _callerName = '';
  String get callerName => _callerName;

  void setCallerName(String v) {
    _callerName = v.trim();
    _save('callerName', _callerName);
    _notify();
  }

  /// คำทักตอนรับสายที่เจ้าของตั้งเอง · ว่าง = คำทักตั้งต้น ([S.callGreeting])
  ///
  /// เจ้าของ: "มายด์พูดเยอะไปตอนรับสาย สอนให้พูดแค่คำที่เราตั้ง (ตั้งค่าได้ เมื่อรับสายให้พูด
  /// ว่าอะไร เหมือนตอนโทรออกที่ตั้งได้)" · ดู [callGreeting]
  String _callGreetingText = '';
  String get callGreetingText => _callGreetingText;

  /// เพดานความยาวคำทัก · ประโยคทักที่ยาวกว่านี้คือสิ่งที่เจ้าของบ่นว่า "พูดเยอะไป" เอง
  static const callGreetingMax = 160;

  void setCallGreetingText(String v) {
    var t = v.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length > callGreetingMax) t = t.substring(0, callGreetingMax);
    if (t == _callGreetingText) return;
    _callGreetingText = t;
    _save('callGreeting', t);
    _notify();
  }

  // ── หาว่าหมายถึงใคร ── (lib/phone/call_target.dart)
  //
  // เจ้าของ: "สั่งให้เธอโทรออกหาลูกค้าชื่อบัว เธอบอกไม่มี แทนที่จะค้นรายชื่อที่ใกล้เคียงมาและถามฉันก่อน
  // ว่าคนไหน หรือเบอร์โทรเข้ามาล่าสุดที่ไม่ได้บันทึกไว้"

  CallTargetResolver? _lazyCallTargets;
  CallTargetResolver get callTargets =>
      _lazyCallTargets ??= CallTargetResolver(clock: _clock, notes: () => _callNotes?.notes ?? const []);

  @visibleForTesting
  set debugCallTargets(CallTargetResolver r) => _lazyCallTargets = r;

  /// คำถาม "หมายถึงคนไหน" ที่รอเจ้าของตอบ (พิมพ์ พูด หรือแตะในกล่อง) · null = ไม่มี
  CallChoice? _callChoice;
  CallChoice? get callChoice => _callChoice;

  /// โหมดคุยต่อเนื่องด้วยเสียงเปิดอยู่ (ไมค์ในแชท · lib/ai/voice_chat.dart) · กล่องยืนยันบอกว่าพูดตอบได้
  bool _handsFree = false;
  bool get handsFree => _handsFree;

  void setHandsFree(bool v) {
    if (_handsFree == v) return;
    _handsFree = v;
    // แผงแชท (แถบสถานะ ปุ่มปิดไมค์) ต้องไม่พับหนีกลางบทสนทนา · ปิดโหมดแล้วค่อยนับถอยหลังตามปกติ
    if (v) {
      _chatOpen = true;
      _chatTimer?.cancel();
    } else {
      _startChatCountdown();
    }
    _notify();
  }

  /// เธอพูดออกเสียงไหม · ปิดเสียงไว้แต่เปิดคุยต่อเนื่อง = พูด (เจ้าของเลือกคุยด้วยเสียงเอง)
  bool get _voiceOut => _voiceEnabled || _handsFree;

  /// พูดข้อความที่ขึ้นแชทเองโดยไม่ผ่านสมอง (ผลโทร ผลงานในเครื่อง) · คุยต่อเนื่องแบบทีละตาใช้
  Future<void> speakNotice(String text) => _speakIfEnabled(text);

  /// เธอเขียน `[[โทร: … | …]]` → หาว่าใคร → ชัด = กล่องยืนยัน · ไม่ชัด = ถามเจ้าของ
  ///
  /// คืนข้อความที่ใช้**แทน**คำตอบของเธอ (ถามว่าคนไหน / หาไม่เจอ / เบอร์ฉุกเฉิน) · null = ใช้คำตอบเดิม
  /// ("ได้ค่ะ จะโทรให้") แล้วกล่องยืนยันขึ้นตามมา
  Future<String?> _resolveCall(String target, String task) async {
    // ถามไปแล้วว่าคนไหน แล้วเธอเขียนแท็กด้วยชื่อ/เลขท้ายจากรายการ = คนในรายการ ·
    // ไม่ใช่ค้นใหม่ และไม่ใช่โทรเลขสี่ตัวนั้นตรง ๆ
    final open = _callChoice;
    if (open != null && !open.expired(_clock())) {
      final i = CallReply.choice(target, open.choices);
      if (i != null && i >= 0) return _pickChoice(open, i, task: task) ? null : s.callOutBlocked;
    }
    if (OutgoingRules.looksLikeNumber(target)) {
      final number = target.trim();
      if (OutgoingRules.blocked(number)) return s.callOutBlocked;
      _offerCall(number: number, task: task);
      return null;
    }
    final r = await callTargets.resolve(target);
    if (_disposed) return null;
    final pick = r.pick;
    if (pick != null) {
      if (OutgoingRules.blocked(pick.number)) return s.callOutBlocked;
      _offerCall(number: pick.number, name: pick.name, task: task);
      // ชื่อในสมุดไม่ตรงกับที่สั่ง ("บัว" → "บัวบาน") · บอกว่าเลือกใคร เจ้าของจะได้รู้ก่อนกด
      return CallNameMatch.score(target, pick.who) >= .97
          ? null
          : s.callOutPicked(CallNameMatch.display(pick.who), pick.tail);
    }
    final core = CallNameMatch.core(target);
    if (r.choices.isNotEmpty) {
      _callChoice = CallChoice(target: core, task: task, choices: r.choices, id: ++_callSeq, at: _clock());
      _notify();
      return _choiceText(core, r.choices);
    }
    return r.noContacts ? s.callOutNeedContacts(core) : s.callOutNoContact(core);
  }

  /// รายการให้เจ้าของเลือก · เธอพูดออกเสียงด้วย จึงสั้น: ชื่อ + เลขท้าย / เบอร์ + เมื่อไหร่
  String _choiceText(String target, List<CallCandidate> choices) {
    final now = _clock();
    final lines = [
      for (var i = 0; i < choices.length; i++)
        choices[i].unsaved
            ? s.callChoiceUnsaved(
                i + 1,
                choices[i].number,
                s.callChoiceWhen(choices[i].at ?? now, now),
                missed: choices[i].missed,
                calls: choices[i].calls,
                said: choices[i].saidName ? CallNameMatch.display(target) : null,
              )
            : s.callChoiceContact(i + 1, CallNameMatch.display(choices[i].name!), choices[i].tail),
    ];
    final anyContact = choices.any((c) => !c.unsaved);
    return s.callOutChoose(CallNameMatch.display(target), lines.join('\n'),
        anyContact: anyContact, single: choices.length == 1);
  }

  /// เจ้าของเลือกคนที่ [index] · false = เบอร์ฉุกเฉิน/เก็บเงินพิเศษ ไม่ขึ้นกล่อง
  bool _pickChoice(CallChoice choice, int index, {String? task}) {
    final c = choice.choices[index];
    _callChoice = null;
    _notify();
    if (OutgoingRules.blocked(c.number)) return false;
    _offerCall(number: c.number, name: c.name, task: task ?? choice.task);
    return true;
  }

  /// เจ้าของแตะเลือกในกล่อง · กล่องเก่าที่ค้างอยู่ (id ไม่ตรง) = ไม่ทำอะไร
  void chooseCall(int id, int index) {
    final c = _callChoice;
    if (c == null || c.id != id || index < 0 || index >= c.choices.length) return;
    if (!_pickChoice(c, index)) _say(s.callOutBlocked);
  }

  /// "ไม่ใช่ทั้งหมด" · [id] = ของกล่องที่กด (กล่องเก่ายกเลิกคำถามใหม่ไม่ได้)
  void cancelCallChoice({int? id}) {
    final c = _callChoice;
    if (c == null || (id != null && c.id != id)) return;
    _callChoice = null;
    _say(s.callChoiceCancelled);
  }

  /// ตั้งกล่องยืนยัน · รอให้คำตอบของเธอขึ้นจอก่อน (ตาถัดไปของ event loop) ไม่งั้นลำดับกลับหัว
  void _offerCall({required String number, String? name, required String task}) {
    final p = PendingCall(number: number, name: name, task: task, id: ++_callSeq);
    _callChoice = null;
    unawaited(Future<void>(() {
      if (_disposed) return;
      _pendingCall = p;
      _notify();
    }));
  }

  /// คำตอบเรื่องโทรที่ตัดสินได้ในเครื่อง ไม่ต้องถามสมอง · null = ส่งให้สมองตามปกติ ·
  /// '' = ทำแล้ว (ข้อความ "กำลังโทร" ขึ้นเองแล้ว) ไม่ต้องตอบซ้ำ
  ///
  /// เจ้าของ: "แอพนี้ใช้งานแม้ในขับรถได้" · ตอบด้วยเสียงว่า "คนที่สอง" / "ลงท้าย 4521" / "โทรเลย" /
  /// "ยกเลิก" ต้องได้ผลทันที ไม่ต้องแตะจอ
  Future<String?> _localReply(String text) async {
    final choice = _callChoice;
    if (choice != null) {
      if (choice.expired(_clock())) {
        _callChoice = null;
      } else {
        final i = CallReply.choice(text, choice.choices);
        if (i == CallReply.cancel) {
          _callChoice = null;
          _notify();
          return s.callChoiceCancelled;
        }
        if (i != null) {
          final c = choice.choices[i];
          return _pickChoice(choice, i)
              ? s.callOutPicked(CallNameMatch.display(c.who), c.tail)
              : s.callOutBlocked;
        }
      }
    }
    final p = _pendingCall;
    if (p != null) {
      // 🔴 ทั้งประโยคต้องเป็นคำตอบ ("โทรเลย" "ใช่" "ยกเลิก") · "ได้ยินไหม" ไม่ใช่การยืนยัน (ดู CallReply.confirm)
      final yes = CallReply.confirm(text);
      // คุยต่อเนื่องด้วยเสียง = ต้องมีคำว่า "โทร" ชัด ๆ (ดู CallReply.saysCall) · "ใช่" เฉย ๆ ให้สมองตอบตามบริบท
      if (yes == true && (!_handsFree || CallReply.saysCall(text))) {
        if (!await _voiceBarred()) await confirmPendingCall();
        return '';
      }
      if (yes == false) {
        cancelPendingCall(id: p.id);
        return s.callChoiceCancelled;
      }
    }
    return null;
  }

  /// ข้อความจากเธอที่ไม่ได้มาจากสมอง (บอกผลการโทร) · ขึ้นจอ ลงบทสนทนา
  void _say(String text) {
    if (_disposed) return;
    _push(ChatMessage.her(text));
    _notify();
    onHerNotice?.call(text);
  }

  /// ข้อความจากเธอที่ไม่ได้มาจากสมอง (ผลงานในเครื่อง ผลการโทร) · ตอนคุยสดด้วยเสียง ตัวคุมเอาไปให้เธอพูด
  /// (ไม่งั้นคนขับรถไม่รู้ว่างานเสร็จแล้ว) · null = ไม่มีใครฟัง
  void Function(String text)? onHerNotice;

  /// [id] = ของกล่องที่ปิด · กล่องเก่าที่ปิดตามหลัง (เจ้าของตอบด้วยเสียงไปแล้ว) ต้องไม่ยกเลิกคำขอใหม่
  void cancelPendingCall({int? id}) {
    final p = _pendingCall;
    if (p == null || (id != null && p.id != id)) return;
    _pendingCall = null;
    _notify();
  }

  /// เจ้าของกด "โทรเลย" · [task] = เรื่องที่เจ้าของแก้ในกล่องยืนยัน (ว่าง = ใช้ของเธอ) ·
  /// [askOwner] = สวิตช์ "ถามฉันได้ระหว่างสาย" · null = ดูจากเรื่องที่สั่ง ([OutgoingRules.noAsking])
  Future<void> confirmPendingCall({String? task, bool? askOwner}) async {
    final asked = _pendingCall;
    if (asked == null) return;
    final edited = task?.trim() ?? '';
    final p = edited.isEmpty
        ? asked
        : PendingCall(number: asked.number, name: asked.name, task: edited, id: asked.id);
    _pendingCall = null;
    _notify();
    String? why;
    try {
      why = await kSystemChannel.invokeMethod<String>('mindPlaceCall', {'number': p.number});
    } on Object {
      why = 'no_telecom';
    }
    if (why != null) {
      _say(s.callOutFailed(why));
      return;
    }
    _outgoing = (who: p.who, number: p.number, task: p.task);
    _outgoingAskOk = askOwner ?? !OutgoingRules.noAsking(p.task);
    _outgoingAnswered = false;
    _say(s.callOutDialing(p.who));
  }

  /// [CallSession] บอกว่าปลายสายรับแล้ว น้องมายเริ่มคุย
  void noteOutgoingAnswered() => _outgoingAnswered = true;

  // ── ใช้เครื่องแทนเจ้าของ ── (lib/hands/)
  //
  // เจ้าของ: "ต้องทำให้ มายด์ คอนโทรลเครื่องได้หมด เปิดได้ได้ทุกแอพ ทำแทนเราได้"

  PhoneTaskView? _phoneTask;

  /// สวิตช์ "ให้เธอใช้เครื่องแทน" (ตั้งค่า) · ปิด = ไม่สอนแท็ก ไม่มีเครื่องมือในสาย
  bool _phoneControl = true;
  bool get phoneControl => _phoneControl;

  void setPhoneControl(bool v) {
    if (_phoneControl == v) return;
    _phoneControl = v;
    _save('phoneControl', v);
    if (!v) stopPhoneTask();
    _notify();
  }

  Hands? _lazyHands;
  Hands get hands => _lazyHands ??= HandsBridge();

  @visibleForTesting
  set debugHands(Hands h) => _lazyHands = h;

  PhoneAgent? _agent;

  /// คำถาม "ให้ทำขั้นนี้ไหม" ที่รอเจ้าของตอบในแอป (งานจากแชท)
  Completer<bool>? _askAnswer;
  int? _askId;

  /// รอเจ้าของตอบนานสุดเท่านี้ · ไม่ตอบ = ไม่ทำ แล้วหยุดงาน
  static const phoneAskWait = Duration(minutes: 2);
  static const _phoneAskPoll = Duration(milliseconds: 400);

  /// งานที่เธอทำอยู่ในเครื่อง (null = ไม่มี)
  PhoneTaskView? get phoneTask => _phoneTask;

  // ── เมล — ผ่านแอปเมลในเครื่อง ──
  //
  // เจ้าของ: "เชื่อมต่อกับแอพในเครื่องเลยได้ไหม เช่น google mail hotmail" · "อยากให้คอนโทรลเครื่อง
  // แล้วกดเปิดพวกมันขึ้นมาเธอใช้มันได้เลย" · ไม่มีรหัสผ่านเมล ไม่มี OAuth · เธอใช้มือเปิดแอปเมลเอง

  /// แอปเมลที่เปิดได้ในเครื่อง (PhoneData.mailApps) · null = ยังไม่ได้ถามเครื่อง
  List<({String name, String package})>? _mailApps;
  List<({String name, String package})> get mailApps => _mailApps ?? const [];

  /// ถามเครื่องแล้ว (ได้คำตอบ หรือถามไม่สำเร็จ) · หน้าเมลเลิกขึ้น "กำลังดู…" ·
  /// ถามไม่สำเร็จ prompt ยังเห็น null (บอกแบบกลาง ๆ ว่า Gmail หรือ Outlook) ไม่ใช่ "ไม่มีแอปเมล"
  bool _mailAppsAsked = false;
  bool get mailAppsKnown => _mailApps != null || _mailAppsAsked;

  /// ถามเครื่องว่ามีแอปเมลอะไร · ตอนเปิดแอปและตอนเปิดแท็บเมล (ลงแอปเมลเพิ่มทีหลังได้)
  Future<void> refreshMailApps() async {
    try {
      final raw = await kSystemChannel.invokeMethod<List<Object?>>('mailApps');
      if (_disposed) return;
      if (raw != null) {
        _mailApps = [
          for (final m in raw.whereType<Map>())
            if (m['name'] is String && m['package'] is String)
              (name: m['name'] as String, package: m['package'] as String),
        ];
      }
    } on Object catch (e) {
      debugPrint('mail: หาแอปเมลไม่ได้ — ${e.runtimeType}');
    }
    if (_disposed) return;
    _mailAppsAsked = true;
    _notify();
  }

  bool _mailChecking = false;

  /// ปุ่มเช็กเมลกดไม่ได้ตอนนี้ (กำลังเช็ก หรือเธอทำงานอื่นในเครื่องอยู่)
  bool get mailBusy => _mailChecking || _agent != null || _teaching != null;

  /// ปุ่ม "ให้เธอเช็กเมล" ในหน้าเมล · เธอเปิดแอปเมลอ่านแล้วสรุปในแชท (แจ้งเตือนด้วยถ้าแอปไม่อยู่หน้าจอ) ·
  /// กดรัว ๆ = เริ่มครั้งเดียว
  Future<void> checkMail(String app) async {
    if (_mailChecking || _disposed) return;
    _mailChecking = true;
    _notify();
    try {
      _say(s.mailCheckAck(app));
      await _phoneTaskFromChat(s.mailCheckGoal(app));
    } finally {
      _mailChecking = false;
      if (!_disposed) _notify();
    }
  }

  /// ให้เธอทำงานในเครื่องจนจบ · [confirm] ถามก่อนขั้นที่ย้อนกลับไม่ได้ (ในแชท = เจ้าของ ·
  /// ในสาย = คนที่ยืนยันตัวแล้ว) · [inCall] = สั่งมาจากสาย · [routine] = เริ่มด้วยขั้นตอนที่สอนไว้
  Future<PhoneTaskResult> runPhoneTask(
    String goal, {
    required PhoneConfirm confirm,
    bool inCall = false,
    PhoneMacro? routine,
  }) async {
    if (!_phoneControl) {
      return PhoneTaskResult(PhoneOutcome.unavailable, s.handsUnavailable(PhoneUnavailable.off),
          reason: PhoneUnavailable.off);
    }
    // งานเดียวต่อครั้ง · กดซ้ำ/สั่งซ้อนจากสายกับแชทพร้อมกัน/ระหว่างสอน = ปฏิเสธ ไม่เริ่มตัวที่สอง
    if (_agent != null || _teaching != null) {
      return PhoneTaskResult(PhoneOutcome.unavailable, s.handsUnavailable(PhoneUnavailable.busy),
          reason: PhoneUnavailable.busy);
    }
    final agent = PhoneAgent(
      hands: hands,
      think: (system, turns) => _askBrain(system, turns, cap: ReplyCap.background),
      lang: _lang,
      clock: _clock,
      routines: _macros,
      onView: (v) {
        if (_disposed) return;
        _phoneTask = v;
        _notify();
      },
    );
    _agent = agent;
    final who = (_soul?.name ?? '').trim();
    try {
      return await agent.run(goal,
          confirm: confirm,
          inCall: inCall,
          routine: routine,
          title: s.handsTitle(who.isEmpty ? s.handsDefaultWho : who));
    } finally {
      if (identical(_agent, agent)) _agent = null;
      _phoneTask = null;
      if (!_disposed) _notify();
    }
  }

  /// ปุ่มหยุด (ในแอป หรือคนในสายสั่ง) · ฝั่ง Android ปฏิเสธทุกคำสั่งต่อจากนี้ทันที
  void stopPhoneTask() {
    _agent?.stop();
    final a = _askAnswer;
    if (a != null && !a.isCompleted) a.complete(false);
  }

  /// เจ้าของตอบ "ให้ทำขั้นนี้ไหม" ในแอป · [id] ไม่ตรงคำถามที่รออยู่ = คำตอบเก่า ทิ้ง
  void answerPhoneAsk(int id, bool allow) {
    if (_askId != id) return;
    final a = _askAnswer;
    if (a != null && !a.isCompleted) a.complete(allow);
  }

  /// เจ้าของพูดตอบ "ให้ทำขั้นนี้ไหม" · true = เป็นคำตอบ (ใช้แล้ว ไม่ต้องส่งต่อ)
  ///
  /// 🔴 ตัดสินจาก**คำพูดของเจ้าของเอง** ในเครื่อง · โมเดลไม่มีเครื่องมือกดยืนยัน ([CallReply.stepConfirm])
  Future<bool> answerPhoneAskByVoice(String text) async {
    final id = _askId;
    if (id == null) return false;
    final yes = CallReply.stepConfirm(text);
    if (yes == null) return false;
    if (yes && await _voiceBarred()) return true;
    answerPhoneAsk(id, yes);
    return true;
  }

  /// เครื่องล็อกอยู่ไหม · main ต่อกับ Android · null (เทสต์) = ไม่ล็อก
  Future<bool> Function()? phoneLocked;

  /// 🔴 คำเรียกไม่ใช่การยืนยันตัวตน · คนอื่นพูดคำเดียวกันใส่เครื่องที่ล็อกอยู่ได้ · คุยได้ แต่โทรออกและขั้นที่ย้อนไม่ได้
  /// ต้องปลดล็อกก่อน · การยกเลิกทำได้เสมอ (ไม่ทำ = ปลอดภัย)
  Future<bool> _voiceBarred() async {
    if (!_handsFree || !(await phoneLocked?.call() ?? false)) return false;
    onHerNotice?.call(s.wakeUnlockFirst);
    return true;
  }

  static String _clip(String text, int max) => text.length <= max ? text : '${text.substring(0, max)}…';

  /// เธอเขียน `[[ทำในเครื่อง: …]]` ในแชท → ทำ → บอกผลในแชท
  Future<void> _phoneTaskFromChat(String goal, {PhoneMacro? routine}) async {
    // ให้คำตอบของเธอขึ้นจอก่อน แล้วค่อยผลของงาน
    await Future<void>.delayed(Duration.zero);
    final r = await runPhoneTask(goal, confirm: _confirmInChat, routine: routine);
    if (_disposed) return;
    _say(r.summary);
    // เธอทำงานอยู่ในแอปอื่น เจ้าของไม่เห็นแชท · บอกผลทางแจ้งเตือนด้วย
    if (r.outcome != PhoneOutcome.unavailable && !_appVisible) {
      unawaited(_notifyOwner(s.handsDoneNotice, r.summary));
    }
  }

  // ── ขั้นตอนที่เจ้าของสอนให้ดู (มาโคร) ──
  //
  // เจ้าของ: "ค. ทำทั้งสองแบบ โดยเริ่มจากแบบ ก. ก่อน" · ดู PhoneMacro

  List<PhoneMacro> _macros = const [];
  List<PhoneMacro> get phoneMacros => _macros;

  /// ชื่อขั้นตอนที่กำลังสอนอยู่ (null = ไม่ได้สอน)
  String? _teaching;
  String? get teachingMacro => _teaching;

  bool hasMacro(String name) => _macroNamed(name) != null;

  PhoneMacro? _macroNamed(String name) {
    final n = name.trim().toLowerCase();
    for (final m in _macros) {
      if (m.name.toLowerCase() == n) return m;
    }
    return null;
  }

  /// เริ่มจำ · null = เริ่มแล้ว · ข้อความ = เหตุที่เริ่มไม่ได้ (ขึ้นให้เจ้าของเห็น)
  Future<String?> startTeaching(String name) async {
    var n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (n.isEmpty) return s.macroNameEmpty;
    if (n.length > PhoneMacro.maxNameLength) n = n.substring(0, PhoneMacro.maxNameLength);
    if (!_phoneControl) return s.handsUnavailable(PhoneUnavailable.off);
    if (_agent != null || _teaching != null) return s.handsUnavailable(PhoneUnavailable.busy);
    // จองไว้ก่อนรอ Android · กดปุ่มรัว ๆ ไม่เริ่มสองรอบ
    _teaching = n;
    _notify();
    final r = await hands.recordStart(title: s.macroRecordTitle(n));
    if (!r.ok) {
      _teaching = null;
      _notify();
      return s.handsUnavailable(r.error ?? '');
    }
    unawaited(_watchTeaching(n));
    return null;
  }

  /// ปุ่ม "จำแล้ว" / "ยกเลิก" ในแจ้งเตือนมาทาง poll
  Future<void> _watchTeaching(String name) async {
    while (_teaching == name && !_disposed) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_teaching != name || _disposed) return;
      final p = await hands.poll();
      if (_teaching != name) return;
      if (p.recordDone) {
        await finishTeaching();
        return;
      }
      if (p.stop) {
        await cancelTeaching();
        return;
      }
    }
  }

  /// จบการสอนแล้วเก็บ · คืนจำนวนขั้นที่จำได้ (0 = ไม่ได้อะไร ไม่เก็บ) · ทับขั้นตอนชื่อเดิม
  /// (หน้าตั้งค่าถามเจ้าของก่อนเริ่มสอนแล้ว)
  Future<int> finishTeaching() async {
    final name = _teaching;
    if (name == null) return 0;
    _teaching = null;
    _notify();
    final steps = PhoneMacro.clean(await hands.recordStop());
    if (_disposed) return 0;
    if (steps.isEmpty) {
      _say(s.macroEmpty(name));
      return 0;
    }
    final m = PhoneMacro(name: name, steps: steps, created: _clock());
    _macros = [
      for (final x in _macros)
        if (x.name.toLowerCase() != name.toLowerCase()) x,
      m,
    ];
    _save('phoneMacros', PhoneMacro.encodeAll(_macros));
    _say(s.macroSaved(name, steps.length));
    if (!_appVisible) unawaited(_notifyOwner(s.macroSavedTitle, s.macroSaved(name, steps.length)));
    _notify();
    return steps.length;
  }

  Future<void> cancelTeaching() async {
    if (_teaching == null) return;
    _teaching = null;
    _notify();
    await hands.recordStop();
  }

  /// ลบ (หน้าตั้งค่าถามยืนยันก่อน)
  void deleteMacro(String name) {
    final before = _macros.length;
    _macros = [
      for (final x in _macros)
        if (x.name.toLowerCase() != name.trim().toLowerCase()) x,
    ];
    if (_macros.length == before) return;
    _save('phoneMacros', PhoneMacro.encodeAll(_macros));
    _notify();
  }

  /// ปุ่ม "ทำ" ในตั้งค่า · เล่นขั้นตอนที่สอนไว้ แล้วให้สมองดูต่อถ้าหน้าแอปเปลี่ยน · ผลขึ้นแชท
  Future<void> runMacro(String name) async {
    final m = _macroNamed(name);
    if (m == null) return;
    await _phoneTaskFromChat(s.macroGoal(m.name), routine: m);
  }

  bool get _appVisible {
    try {
      return WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    } on Object {
      return true;
    }
  }

  /// ถามเจ้าของก่อนขั้นที่ย้อนกลับไม่ได้ · ตอบได้สองทาง: กล่องในแอป (shell) หรือปุ่มในแจ้งเตือน ·
  /// ทางไหนมาก่อนใช้ทางนั้น · กดหยุด / ไม่ตอบใน [phoneAskWait] = ไม่ทำ
  Future<bool> _confirmInChat(PhoneStepAsk ask) async {
    final answer = Completer<bool>();
    _askAnswer = answer;
    _askId = ask.id;
    final body = [
      s.handsAskBody(ask.action, ask.app),
      if (ask.why.trim().isNotEmpty) s.handsAskWhy(ask.why.trim()),
      s.handsAskGoal(ask.goal),
    ].join('\n');
    unawaited(hands.askConfirm(id: ask.id, title: s.handsAskTitle, body: body));
    // คุยด้วยเสียงอยู่ = เจ้าของอาจไม่ได้มองจอ (ขับรถ · เธออยู่ในแอปอื่น) · ถามออกเสียง ตอบด้วยเสียงได้
    if (_handsFree) onHerNotice?.call(s.handsAskVoice(_clip(ask.action, 80), _clip(ask.app, 40)));
    try {
      final rounds = phoneAskWait.inMilliseconds ~/ _phoneAskPoll.inMilliseconds;
      for (var i = 0; i < rounds && !answer.isCompleted; i++) {
        final p = await hands.poll();
        if (answer.isCompleted) break;
        if (p.stop) {
          _agent?.stop();
          return false;
        }
        if (p.confirmId == ask.id) return p.allow;
        await Future.any<Object?>([answer.future, Future<void>.delayed(_phoneAskPoll)]);
      }
      return answer.isCompleted ? await answer.future : false;
    } finally {
      if (identical(_askAnswer, answer)) {
        _askAnswer = null;
        _askId = null;
      }
      unawaited(hands.confirmDone(ask.id));
    }
  }

  /// สายจบ · ยังไม่ได้คุยเลย (ไม่รับ/สายไม่ว่าง/วางก่อน) = บอกเจ้าของ · คุยแล้วรายงานผ่าน [takeCallNote]
  void _outgoingEnded() {
    final o = _outgoing;
    if (o == null || _outgoingAnswered) return;
    _outgoing = null;
    _say(s.callOutNoAnswer(o.who));
  }

  @visibleForTesting
  void debugSetOutgoing(OutgoingTask? t, {bool? askOwner}) {
    _outgoing = t;
    _outgoingAskOk = askOwner ?? (t == null || !OutgoingRules.noAsking(t.task));
  }

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
    CallSim? sim,
    File? audio,
    bool outgoing = false,
    String number = '',
  }) async {
    // สายที่น้องมายโทรออกเอง · จบตรงนี้ไม่ว่าจะสรุปได้หรือไม่ (ไม่ค้างเป็นสายที่ยังไม่รายงาน)
    final task = outgoing ? _outgoing : null;
    if (outgoing) _outgoing = null;
    // 🔴 คนโทรพูดโค้ดลับออกมาดัง ๆ · ลบก่อนเก็บ สรุป และส่งขึ้นสมอง
    lines = [for (final l in lines) (fromHer: l.fromHer, text: scrubCallCode(l.text))];
    if (lines.isEmpty) {
      await audio?.delete().catchError((Object _) => audio);
      return null;
    }
    final when = at ?? _clock();
    final callerSpoke =
        lines.any((l) => !l.fromHer && l.text.trim().isNotEmpty);

    var summary = callerSpoke ? '' : (task != null ? s.callOutSilent : s.callNoteSilent);
    if (callerSpoke) {
      try {
        final block = conversationBlock(
          [for (final l in lines) (fromHer: l.fromHer, text: l.text)],
          me: s.speakerCaller,
          her: _soul?.name ?? s.speakerHer,
        );
        summary = (await _askBrain(
          task != null ? outgoingSummaryPrompt(_lang == AppLang.th, task.task) : callSummaryPrompt(_lang == AppLang.th),
          [(fromHer: false, text: block)],
          cap: ReplyCap.background,
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
      sim: sim,
    );
    // เสียงสนทนาผูกกับบันทึกนี้ (ชื่อไฟล์ = id) · ไม่มีที่เก็บบันทึก = ไม่เก็บเสียงลอย ๆ
    if (audio != null) {
      if (_callNotes != null) {
        await CallRecordings.adopt(audio, note.id);
      } else {
        await audio.delete().catchError((Object _) => audio);
      }
    }
    await _callNotes?.add(note);
    // เครื่องสองซิม = หัวข้อบอกด้วยว่าโทรเข้าเบอร์ไหน (งาน/ส่วนตัว)
    final base = task != null ? s.callOutNoteTitle(task.who) : s.callNoteTitle(who);
    final title = sim == null ? base : '$base · ${s.viaSim(sim.slot, sim.label)}';
    // โทรออกให้ = เล่าผลกลับในแชทเหมือนเลขามารายงาน
    if (task != null) _say(s.callOutReport(task.who, summary));
    // ยิ่งคุยยิ่งเก่ง · สายที่คู่สายพูดจริงเท่านั้น (สายเงียบไม่มีอะไรให้เรียน)
    if (callerSpoke && lines.length >= 3) {
      unawaited(_learnFromCall(
        block: conversationBlock(
          [for (final l in lines) (fromHer: l.fromHer, text: l.text)],
          me: s.speakerCaller,
          her: _soul?.name ?? s.speakerHer,
        ),
        source: note.id,
        contact: CallLessons.contactKey(number, name: task?.who ?? who),
        task: task?.task,
      ));
    }
    unawaited(_journal?.record(
          JournalKind.call,
          title,
          detail: summary,
          id: note.id,
        ) ??
        Future<bool>.value(false));

    // แจ้งเตือนแม้แอปอยู่เบื้องหลัง · สิทธิ์แจ้งเตือนไม่ได้ให้ = ฝั่งเนทีฟข้ามเงียบ ๆ
    try {
      await kSystemChannel.invokeMethod<bool>('notifyCallNote', {
        'title': title,
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

  void attachSoul(MindSoul s) {
    _soul?.removeListener(_queueSoul);
    _soul = s..addListener(_queueSoul);
  }

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

  /// ทางออกเสียงตอนเวทีไม่อยู่บนจอ · WebView ถูกพักเสียงตามแอป และหลังจอตายไม่มีเวทีเลย
  /// (คุยด้วยเสียงต่อจากแอปอื่น · listen/ListenService.kt)
  Future<bool> Function(Utterance)? speakerOffScreen;

  /// แอปอยู่บนจอไหม · จอลอย (PiP) = inactive นับว่าอยู่ · ยังไม่มีข้อมูล (เทสต์) = นับว่าอยู่
  bool get _onScreen {
    try {
      final life = WidgetsBinding.instance.lifecycleState;
      return life != AppLifecycleState.paused &&
          life != AppLifecycleState.hidden &&
          life != AppLifecycleState.detached;
    } on Object {
      return true;
    }
  }

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
      // 🔴 เวทีหรือเครื่องเล่นที่ค้างต้องไม่ลากปุ่มที่เรียก hush ค้างตาม
      // (ลองฟังเสียง · ส่งข้อความ · ออกจากแอป ทั้งหมดเริ่มด้วย hush)
      await h().timeout(const Duration(seconds: 2));
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
    _stageShot = MindStageShot.parse(p.getString('stageShot'));
    _studioBackdrop = StudioBackdrops.parse(p.getString('studioBackdrop'));
    _studioMic = p.getBool('studioMic') ?? false;
    _preloadBrain = p.getBool('preloadBrain') ?? false;
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
    _geminiKey = await SecretStore.read(SecretStore.kGeminiKey);
    _elevenLabsKey = await SecretStore.read(SecretStore.kElevenLabsKey);
    _azureKey = await SecretStore.read(SecretStore.kAzureSpeechKey);
    _azureRegion = p.getString('azureRegion') ?? '';
    for (final e in const [TtsEngine.elevenlabs, TtsEngine.azure]) {
      try {
        final raw = p.getString('voices_${e.name}');
        if (raw == null) continue;
        _accountVoices[e] = [
          for (final v in jsonDecode(raw) as List) ?PremiumVoice.fromJson(v),
        ];
      } on Object {
        // รายชื่อที่จำไว้เพี้ยน = โหลดใหม่ได้ ไม่ใช่เรื่องที่ต้องล้ม
      }
    }
    _licenseKey = p.getString('licenseKey') ?? '';
    _licenseType = p.getString('licenseType') ?? '';
    _brainModel = p.getString('brainModel') ?? OpenAiConfig.brainModel;
    _proxyModel = p.getString('proxyModel') ?? '';
    _webSearch = p.getBool('webSearch') ?? true;
    _phoneControl = p.getBool('phoneControl') ?? true;
    _macros = PhoneMacro.decodeAll(p.getString('phoneMacros'));
    _brainxSearch = p.getBool('brainxSearch') ?? true;
    _brainxShare = p.getBool('brainxShare') ?? true;
    _callScopes = decodeScopes(p.getString('callBrainxScopes'));
    _callPlay = (p.getDouble('callPlay') ?? 0.4).clamp(0.0, 1.0);
    _callMaxMinutes = p.getInt('callMaxMinutes') ?? 3;
    _callStyle = p.getString('callStyle') ?? '';
    _lessons = CallLessons.decode(p.getString('callLessons'));
    _callCode = await SecretStore.read(SecretStore.kCallCode);
    _codeFails = decodeCodeFails(p.getString('callCodeFails'));
    _quiz = IdentityQuiz.decode(await SecretStore.read(SecretStore.kCallQuestions));
    _idFails = decodeCodeFails(p.getString('callIdentityFails'));

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
    _contactsOnly = p.getBool('autoAnswerContactsOnly') ?? false;
    _showOnCall = p.getBool('showMindOnCall') ?? true;
    _recordCalls = p.getBool('recordCalls') ?? true;
    _callerName = p.getString('callerName') ?? '';
    _callGreetingText = p.getString('callGreeting') ?? '';
    _realtimeCalls = p.getBool('realtimeCalls') ?? true;
    _voiceChatLive = p.getBool('voiceChatLive') ?? true;
    _voiceChatVoicePick = p.getString('voiceChatVoice') ?? '';
    _liveCalls = p.getBool('liveCalls') ?? false;
    _ringSeconds = p.getInt('ringSeconds') ?? 15;

    // 🔴 เขียนกระจกเงาทุกครั้งที่เปิดแอป ไม่ใช่แค่ตอนผู้ใช้เปลี่ยนค่า
    // · กู้จากสำเนาข้างนอก / ล้างข้อมูลแอป = prefs ว่าง แต่ฐานมีค่าครบ
    // ถ้ารอให้ผู้ใช้แตะสวิตช์ก่อน จอสายเนทีฟจะใช้ค่าตั้งต้น (รับสายเอง)
    // ทั้งที่ในแอปโชว์ว่าปิดไว้
    for (final (key, value) in <(String, Object)>[
      ('autoAnswer', _autoAnswer),
      ('autoAnswerContactsOnly', _contactsOnly),
      ('showMindOnCall', _showOnCall),
      ('ringSeconds', _ringSeconds),
      ('lang', _lang.code),
    ]) {
      unawaited(_mirror(key, value));
    }

    // บทสนทนาเก่าต้องกลับมาก่อนบทตัวอย่าง — ถ้าเคยคุยจริงแล้ว
    // การเอาบทตัวอย่างมาทับคือการลบสิ่งที่ผู้ใช้พิมพ์เองทิ้ง
    if (_store?.db != null) {
      await _loadContextFromDb();
      // ดัชนีบทสนทนาเก่าทำทีหลังได้ · ไม่ขวางการเปิดแอป (แบ่งเป็นช่วงอยู่แล้ว)
      unawaited(_chatRecall.load(_store!.db!));
      // ครั้งแรกหลังอัปเดตแอป ฐานยังว่างแต่ของเก่ายังอยู่ใน prefs
      // ดูดเข้ามาให้ครบก่อน ไม่งั้นเจ้าของจะเปิดแอปมาเจอว่าเธอลืมทุกอย่าง
      // ทั้งที่เพิ่งกดอัปเดตแอปเฉย ๆ
      if (_context.isEmpty) await _absorbLegacyContext();
    } else {
      _loadContext();
    }
    await memory.load();
    _seedConversation();

    // เคยเชื่อมสมอง BrainX ไว้ → ตรวจกับคลาวด์ แล้วกู้ของเดิมถ้าในเครื่องว่าง
    // ไม่ await · ไม่ขวางการเปิดแอป และส่วนที่เหลือของแอปไม่ต้องรอเน็ต
    unawaited(() async {
      await brainx.load();
      if (!brainx.connected || _disposed) return;
      await brainx.refreshAccount();
      if (brainx.connected && !_disposed) await _afterBrainXConnect();
    }());

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
    'autoAnswerContactsOnly',
    'showMindOnCall',
    'ringSeconds',
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
    // แอปกำลังลงเบื้องหลัง = จังหวะสุดท้ายที่แน่ใจว่าโค้ดยังวิ่ง · ของที่รอส่งขึ้น
    // สมอง BrainX ต้องไปตอนนี้ ไม่ใช่รออีกยี่สิบวินาทีที่อาจไม่มีวันมาถึง
    if (_lazyBrainX?.connected ?? false) unawaited(_lazyBrainX!.flush());
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
      )
        ..onRunaway = noteIncident
        ..herName = (() => _soul?.name);

  /// เรื่องที่ไม่ขึ้นเป็นข้อผิดพลาดให้ผู้ใช้เห็น แต่คนไล่บั๊กต้องรู้
  /// (สมองคิดไม่หยุดจนถูกตัด · เสียงค้างจนหมดเวลา) · ตัวรายงานเฝ้าตัวนับนี้
  ///
  /// 🔴 ที่มา: เครื่องร้อน เธอเงียบ ปุ่มค้าง — แต่ระบบรายงานไม่มีสักฉบับ
  /// เพราะ "ค้าง" ไม่เคยกลายเป็น error ที่ไหนเลย
  int _incidents = 0;
  int get incidents => _incidents;
  String? _lastIncident;
  String? get lastIncident => _lastIncident;

  void noteIncident(String what) {
    _incidents++;
    _lastIncident = what;
    if (!_disposed) _notify();
  }

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
    if (_brain != BrainProvider.onDevice || _disposed || !_preloadBrain) return;
    unawaited(localBrain.preload());
  }

  /// เปิดสมองรอไว้ตั้งแต่เปิดแอปไหม · **ปิดเป็นค่าตั้งต้น**
  ///
  /// 🔴 เคยเปิดเองทุกเครื่องในรุ่น 0.1.26 · สมอง 2–3 GB โหลดเข้าหน่วยความจำ
  /// ตอนที่เวทีเพิ่งโหลดตัวเธอเสร็จ (แย่ง GPU และหน่วยความจำก้อนเดียวกัน) แล้ว
  /// เจ้าของเจอ "ตัวเธอหายไป และไม่พูด" · ให้เลือกเปิดเองบนเครื่องที่รับไหว
  bool _preloadBrain = false;
  bool get preloadBrain => _preloadBrain;

  void setPreloadBrain(bool v) {
    if (_preloadBrain == v) return;
    _preloadBrain = v;
    _save('preloadBrain', v);
    _notify();
  }

  /// เก็บกวาดก่อนปิดแอปจริง — เงียบเสียง แล้วปล่อยสมองออกจากหน่วยความจำ
  ///
  /// 🔴 **มีเวลาหมดเสมอ** · ของเดิมรอสมองที่คิดค้างอยู่ให้จบก่อนปล่อย ปุ่มออก
  /// จากแอปจึงค้างไปด้วย · โปรเซสจะถูกปิดทิ้งอยู่แล้ว หน่วยความจำคืนแน่นอน
  /// การเก็บกวาดเป็นแค่ความสุภาพ ห้ามเป็นสิ่งที่ขวางทางออก
  Future<void> prepareExit({Duration limit = const Duration(seconds: 3)}) async {
    if (hasLocalBrain) localBrain.abort();
    try {
      await Future.wait([
        hush(),
        if (hasLocalBrain) localBrain.unload(),
      ]).timeout(limit);
    } on Object catch (e) {
      debugPrint('ออกจากแอป: เก็บกวาดไม่ทัน — ${e.runtimeType} · ออกเลย');
    }
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

  /// ทดสอบเซิร์ฟเวอร์ในบ้าน**ด้วยคำถามจริง** — ติดต่อได้ไหม · มีรุ่นที่ตั้งไว้ไหม · ตอบได้ไหม
  ///
  /// แยกสามขั้นเพื่อบอกเหตุผลให้ตรงจุด · ของเดิมรู้ได้ทางเดียวคือทักเธอแล้วได้
  /// "ต่อเน็ตไม่ได้" ซึ่งไม่บอกเลยว่าผิดที่ที่อยู่ ที่รุ่น หรือที่คอม
  Future<({bool ok, String message})> testHomeServer({
    LocalServerScanner? scanner,
    @visibleForTesting http.Client? httpClient,
  }) async {
    final url = _homeServerUrl.trim();
    if (url.isEmpty) return (ok: false, message: s.homeServerNoUrl);
    final scan = scanner ?? LocalServerScanner();
    try {
      final models = await scan.models(url);
      if (models == null) return (ok: false, message: s.homeUnreachable(url));
      final model = _homeServerModel.trim();
      if (models.isNotEmpty && !models.contains(model)) {
        return (ok: false, message: s.homeModelMissing(model, models.take(6).join(', ')));
      }
      final client = OpenAiClient(
        httpClient: httpClient,
        baseUrl: url,
        apiKey: '',
        timeout: const Duration(seconds: 120),
        strings: () => s,
        upstream: Upstream.homeServer,
      );
      final clock = Stopwatch()..start();
      try {
        final reply = await client.reply(
          system: s.homeTestSystem,
          history: [(fromHer: false, text: s.homeTestQuestion)],
          model: model,
        );
        final said = reply.trim().replaceAll(RegExp(r'\s+'), ' ');
        return (
          ok: true,
          message: s.homeTestOk((clock.elapsedMilliseconds / 1000).toStringAsFixed(1),
              said.length <= 60 ? said : '${said.substring(0, 59)}…'),
        );
      } finally {
        client.close();
      }
    } on OpenAiFailure catch (e) {
      return (ok: false, message: e.message);
    } on Object catch (e) {
      debugPrint('เซิร์ฟเวอร์ในบ้าน: ทดสอบล้ม — ${e.runtimeType}');
      return (ok: false, message: s.homeUnreachable(url));
    } finally {
      if (scanner == null) scan.close();
    }
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

  /// ระยะกล้องบนเวทีปกติ · ค่าตั้งต้นครึ่งตัวแบบนิ่ง (ดู [MindStageShot])
  MindStageShot _stageShot = MindStageShot.bust;
  MindStageShot get stageShot => _stageShot;

  void setStageShot(MindStageShot v) {
    if (_stageShot == v) return;
    _stageShot = v;
    _save('stageShot', v.name);
    _notify();
  }

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

  // ═══ คีย์ของเจ้าเสียงพรีเมียม (Gemini · ElevenLabs · Azure) ═══
  //
  // อยู่ใน SecretStore เหมือนคีย์ OpenAI · ไม่มีคีย์ = เจ้านั้นตกไปใช้เสียงเครื่อง
  // (synthesizeWithFallback) แล้วการ์ดเสียงบอกว่าต้องใส่คีย์ ไม่เงียบเฉย ๆ
  String _geminiKey = '';
  String _elevenLabsKey = '';
  String _azureKey = '';

  /// ภูมิภาคของ Azure Speech (เช่น southeastasia) · ไม่ใช่ความลับ เก็บใน prefs
  String _azureRegion = '';
  String get azureRegion => _azureRegion;

  /// คีย์ของเจ้านั้น · ว่าง = ยังไม่ได้ใส่ (หรือไม่ใช่เจ้าที่ต้องมีคีย์)
  String premiumKey(TtsEngine e) => switch (e) {
        TtsEngine.gemini => _geminiKey,
        TtsEngine.elevenlabs => _elevenLabsKey,
        TtsEngine.azure => _azureKey,
        _ => '',
      };

  /// เจ้านั้นพร้อมใช้ไหม (Azure ต้องมีภูมิภาคด้วย)
  bool premiumReady(TtsEngine e) =>
      premiumKey(e).isNotEmpty && (e != TtsEngine.azure || _azureRegion.isNotEmpty);

  Future<void> setPremiumKey(TtsEngine e, String v) async {
    final value = v.trim();
    final slot = switch (e) {
      TtsEngine.gemini => SecretStore.kGeminiKey,
      TtsEngine.elevenlabs => SecretStore.kElevenLabsKey,
      TtsEngine.azure => SecretStore.kAzureSpeechKey,
      _ => null,
    };
    if (slot == null) return;
    switch (e) {
      case TtsEngine.gemini:
        _geminiKey = value;
      case TtsEngine.elevenlabs:
        _elevenLabsKey = value;
      case TtsEngine.azure:
        _azureKey = value;
      default:
        break;
    }
    if (!await SecretStore.write(slot, value)) reportError(s.errKeyNotSaved);
    _notify();
  }

  /// เสียงที่โหลดมาจากบัญชีของผู้ใช้ (ElevenLabs / Azure) · จำข้ามการเปิดแอป
  final Map<TtsEngine, List<PremiumVoice>> _accountVoices = {};
  List<PremiumVoice> accountVoices(TtsEngine e) => _accountVoices[e] ?? const [];

  TtsEngine? _voicesLoading;
  bool voicesLoading(TtsEngine e) => _voicesLoading == e;

  /// โหลดรายชื่อเสียงจากบัญชี · คืนข้อความผิดพลาด หรือ null เมื่อสำเร็จ
  Future<String?> loadAccountVoices(TtsEngine e) async {
    final premium = _speech.premium;
    if (premium == null || _voicesLoading != null) return null;
    _voicesLoading = e;
    _notify();
    try {
      final list = switch (e) {
        TtsEngine.elevenlabs => await premium.elevenVoices(),
        TtsEngine.azure => await premium.azureVoiceList(),
        _ => const <PremiumVoice>[],
      };
      _accountVoices[e] = list;
      _save('voices_${e.name}', jsonEncode([for (final v in list) v.toJson()]));
      return null;
    } on OpenAiFailure catch (err) {
      return err.message;
    } on Object catch (err) {
      debugPrint('เสียง: โหลดรายชื่อเสียง ${e.name} ไม่ได้ — ${err.runtimeType}');
      return s.premiumFailed(PremiumTts.providerName(e));
    } finally {
      _voicesLoading = null;
      _notify();
    }
  }

  void setAzureRegion(String v) {
    // ภูมิภาคเป็นส่วนหนึ่งของชื่อโดเมน · เก็บเฉพาะตัวอักษร/ตัวเลข กันใส่ URL ทั้งเส้นมา
    _azureRegion = v.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    _save('azureRegion', _azureRegion);
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

  bool _voiceEnabled = true;
  bool get voiceEnabled => _voiceEnabled;

  void setBrainModel(String v) {
    _brainModel = v;
    _save('brainModel', v);
    _notify();
  }

  // ═══ เครดิตของ "ผ่านบริการเรา" (กระเป๋าเงิน xman studio) ═══════════
  //
  // หักทุกข้อความ ไม่มีโควต้าฟรี · ราคาและรุ่นที่เปิดให้ใช้ตั้งที่หลังบ้าน
  // แอปโชว์เฉพาะรุ่นที่หลังบ้านเปิด (ดู ProxyAccount)

  /// รุ่นของบริการเรา · แยกจาก [brainModel] (รุ่น OpenAI ของคีย์ตัวเอง) เพราะ
  /// สองรายการนี้คนละชุดกัน · ใช้ร่วมกันแล้วสลับไปมาจะได้รุ่นที่อีกฝั่งไม่มี
  String _proxyModel = '';
  String get proxyModel => _proxyModel;

  void setProxyModel(String id) {
    _proxyModel = id.trim();
    _save('proxyModel', _proxyModel);
    _notify();
  }

  ProxyAccount? _proxyAccount;
  ProxyAccount? get proxyAccount => _proxyAccount;
  bool _proxyAccountBusy = false;
  bool get proxyAccountBusy => _proxyAccountBusy;
  String? _proxyAccountError;
  String? get proxyAccountError => _proxyAccountError;

  /// รุ่นที่ข้อความถัดไปจะใช้จริง (ที่เลือกถ้ายังเปิด · ไม่งั้นรุ่นแรกที่เปิด)
  ProxyModel? get proxyModelInUse => _proxyAccount?.modelFor(_proxyModel);

  @visibleForTesting
  void debugSetProxyAccount(ProxyAccount? a) {
    _proxyAccount = a;
    _notify();
  }

  /// ถามหลังบ้านว่าเครดิตเหลือเท่าไหร่ ใช้ไปวันนี้เท่าไหร่ และเปิดรุ่นอะไรไว้
  Future<void> refreshProxyAccount({@visibleForTesting ProxyAccountClient? client}) async {
    if (_proxyAccountBusy) return;
    final base = _storeBaseUrl.trim();
    final lic = _licenseKey.trim();
    if (base.isEmpty || lic.isEmpty) {
      _proxyAccountError = base.isEmpty ? s.shopNoUrl : s.licenseNeeded;
      _notify();
      return;
    }
    _proxyAccountBusy = true;
    _notify();
    final c = client ?? ProxyAccountClient();
    try {
      _proxyAccount = await c.fetch(baseUrl: base, license: lic);
      _proxyAccountError = null;
    } on ProxyAccountError catch (e) {
      _proxyAccountError = switch (e.problem) {
        ProxyAccountProblem.offline => s.errOffline,
        ProxyAccountProblem.license => s.errLicenseRejected,
        ProxyAccountProblem.server => s.errProxyFailed(e.status ?? 0),
      };
    } finally {
      if (client == null) c.close();
      _proxyAccountBusy = false;
      if (!_disposed) _notify();
    }
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

  /// รับเฉพาะเบอร์ในสมุดโทรศัพท์ · **ปิดเป็นค่าตั้งต้น = รับทุกสาย**
  ///
  /// เดิมบังคับเฉพาะเบอร์ในสมุดเสมอ (ผู้ช่วยในสายเคยรู้ตารางงานของเจ้าของ) ·
  /// ตอนนี้สายไม่มีข้อมูลส่วนตัวเลย ([callPrompt]) · เจ้าของ: "ไม่ยอมรับสายเองเลย"
  bool _contactsOnly = false;
  bool get contactsOnly => _contactsOnly;

  void setContactsOnly(bool v) {
    _contactsOnly = v;
    _save('autoAnswerContactsOnly', v);
    _notify();
  }

  /// เธอรับสายแล้วตัดมาจอของเธอ **แม้จอล็อก** · เปิดเป็นค่าตั้งต้น
  ///
  /// เจ้าของ: "ตอนเธอรับสายให้ตัดมาหน้าจอเธอ" · ระหว่างสายแอปเหลือแค่จอสาย
  /// (ซ่อนแถบนำทางและปุ่มบนเวที) และถอนตัวจากจอล็อกทันทีที่วางสาย (ฝั่งเนทีฟ)
  bool _showOnCall = true;
  bool get showOnCall => _showOnCall;

  void setShowOnCall(bool v) {
    _showOnCall = v;
    _save('showMindOnCall', v);
    _notify();
  }

  /// สายล่าสุดเธอรับเองไหม และทำไม (จอสายเนทีฟจดไว้) · null = ยังไม่เคยมีสาย
  ///
  /// เดิมไม่รับแล้วเงียบ · เจ้าของเห็นแค่ "ไม่ยอมรับสายเองเลย" โดยไม่มีทางรู้ว่าติดตรงไหน
  Future<({String reason, DateTime at})?> lastAutoAnswer() async {
    try {
      final raw = await kSystemChannel.invokeMethod<String>('lastAutoAnswer');
      final parts = raw?.split('|');
      if (parts == null || parts.length != 2) return null;
      final ms = int.tryParse(parts[1]);
      if (ms == null) return null;
      return _lastAuto = (reason: parts[0], at: DateTime.fromMillisecondsSinceEpoch(ms));
    } on Object {
      // ไม่ใช่ Android / ช่องยังไม่พร้อม — ไม่ใช่ความผิดพลาด
      return null;
    }
  }

  /// ค่าที่อ่านไว้ล่าสุดของ [lastAutoAnswer] · รายงานดีบัคอ่านตัวนี้ ไม่รอช่องเนทีฟ
  ({String reason, DateTime at})? _lastAuto;
  String? get lastAutoAnswerReason => _lastAuto?.reason;

  void setRingSeconds(int v) {
    _ringSeconds = v;
    _save('ringSeconds', v);
    _notify();
  }

  String get ringLabel => _ringSeconds == 0
      ? s.ringImmediate
      : s.ringDelayNote(_ringSeconds);

  // ═══ สายที่เธอถือเอง ═══════════════════════════════════
  //
  // แยกจากการคุยในแอปทั้งหมด: คนปลายสายไม่ใช่เจ้าของ บุคลิกต่างกัน
  // เสียงต่างกัน และบทสนทนาไม่ควรปนเข้าไปในแชทของเจ้าของ

  /// ประโยคแรกที่เธอพูดเมื่อรับสายแทน · พูดตามนี้คำต่อคำ ไม่แต่งเพิ่ม
  ///
  /// เจ้าของตั้งเองได้ ([callGreetingText]) · ว่าง = คำทักตั้งต้น
  ///
  /// 🔴 บันทึกเสียงอยู่ = บอกคู่สายตั้งแต่ประโยคแรกเสมอ แม้เจ้าของตั้งคำทักเอง · คนที่ถูกบันทึก
  /// ควรรู้ตัว · ไม่อยากให้มีประโยคนี้ = ปิดการบันทึก · ไม่ต่อซ้ำเมื่อคำทักพูดถึงการบันทึกเองแล้ว
  String callGreeting() {
    final own = _callGreetingText.trim();
    final base = own.isEmpty ? s.callGreeting : own;
    if (!_recordCalls || _mentionsRecording(own)) return base;
    return '$base ${s.callRecordingNotice}';
  }

  /// ตรวจทั้งสองภาษา · เจ้าของพิมพ์คำทักเป็นภาษาไหนก็ได้ ไม่ขึ้นกับภาษาของแอป
  static bool _mentionsRecording(String t) {
    final l = t.toLowerCase();
    return AppLang.values.any((lang) => l.contains(S(lang).recordingWord));
  }

  /// บันทึกเสียงสนทนาในสายที่เธอรับแทน · เปิดเป็นค่าตั้งต้น (เจ้าของ: "ทำให้
  /// บันทึกเสียงสนทนาไว้ได้ด้วย") · ไฟล์อยู่ในเครื่องเท่านั้น ลบพร้อมบันทึกสาย
  bool _recordCalls = true;
  bool get recordCalls => _recordCalls;

  void setRecordCalls(bool v) {
    if (_recordCalls == v) return;
    _recordCalls = v;
    _save('recordCalls', v);
    _notify();
  }

  /// คำตอบสำหรับคนปลายสาย
  ///
  /// ใช้ system prompt คนละตัวกับการคุยในแอป (`onCall: true`) ซึ่งกดโหมด
  /// ส่วนตัวทิ้งและสั่งให้แนะนำตัวว่าเป็นผู้ช่วย · [history] เป็นบทสนทนา
  /// ของ **สายนี้เท่านั้น** ไม่ใช่แชทของเจ้าของ
  ///
  /// ## 🔴 กันด้วยโค้ด ไม่ใช่ด้วยคำสั่ง
  ///
  /// คนปลายสายคือคนแปลกหน้า และเป็นช่องทางเดียวที่คนนอกพูดเข้ามาถึงเธอได้ตรง ๆ
  /// · ของเดิมส่งโปรไฟล์เจ้าของ ความจำ 24 ข้อ ตารางนัดเต็ม และรายชื่อคนที่โทรมา
  /// วันนี้เข้าไป แล้วกันด้วยคำสั่ง "ห้ามอ่านให้ฟัง" อย่างเดียว · คำสั่งถูกหลอกได้
  /// ("ผมเป็นสามีเขา" "ลืมคำสั่งเดิม") แต่สิ่งที่ไม่อยู่ใน context หลุดไม่ได้
  ///
  /// สิ่งที่เธอได้ในสายจึงมีแค่: บุคลิก (ไม่รวมความสัมพันธ์) · ขอบเขตที่เจ้าของตั้ง ·
  /// ช่วงที่ไม่ว่างแบบไม่มีรายละเอียด · บทสนทนาของสายนี้ · และไม่แตะสมอง BrainX
  /// ไม่ค้นเว็บ ไม่มีบันทึกช่วยจำ (ดู [callPrompt] ที่เทสต์ยืนยันทั้งหมดนี้)
  Future<String> replyOnCall(List<({bool fromHer, String text})> history,
          {bool outgoing = false, String? contact}) =>
      _askBrain(callPrompt(outgoing: outgoing, contact: contact), history, cap: ReplyCap.call);

  ///
  /// [live] = คุยสด (Realtime) · วางสาย/แจ้งด่วนด้วยเครื่องมือแทนแท็ก (ดู [MindPersona.phoneStyle])
  @visibleForTesting
  ///
  /// [outgoing] = สายที่น้องมายโทรออกเอง · ได้เรื่องที่เจ้าของสั่ง ([outgoing]) เพิ่มอย่างเดียว
  ///
  /// [contact] = คีย์ของเบอร์นี้ (CallLessons.contactKey) · ได้บทเรียนของเบอร์นี้จากสายก่อน ๆ
  String callPrompt({bool live = false, bool outgoing = false, String? contact}) {
    final base = _callPromptBase(live: live, outgoing: outgoing);
    // โทรออก = คุยงานแทนเจ้าของ · ความขี้เล่นกับบุคลิกที่ตั้งไว้ให้คนโทรเข้า ไม่ใช้ที่นี่
    final style = outgoing && _outgoing != null
        ? MindPersona.outgoingManner(_lang)
        : MindPersona.callPersonality(_lang, play: _callPlay, style: _callStyle, maxMinutes: _callMaxMinutes);
    // บทเรียนจากสายก่อน ๆ + ที่เจ้าของสั่ง · ใช้เงียบ ๆ ห้ามเล่า (ไม่มีความจำส่วนตัวของเจ้าของในนี้)
    final learned = _lessons.forCall(contact);
    final lessons =
        MindPersona.callLessonsBlock(_lang, contact: learned.contact, owner: learned.owner, how: learned.how);
    // โค้ดลับ = คุยสดเท่านั้น (ต้องมีเครื่องมือ check_code) · ตัวโค้ดไม่เข้า prompt
    final code = live && _callCode.isNotEmpty ? MindPersona.callCodeRule(_lang) : '';
    // คำถามยืนยันตัวตน = คุยสดเท่านั้น (เครื่องมือ identity_*) · คำตอบไม่เข้า prompt
    final ids = live && _quiz.ready ? MindPersona.identityRule(_lang, phone: _phoneControl) : '';
    final withStyle = [base, style, lessons, code, ids].where((b) => b.isNotEmpty).join('\n');
    // เรื่องที่เจ้าของเปิดให้คนโทรรู้ · เฉพาะคุยสด (มีเครื่องมือ lookup_info)
    if (!live || !callLookupReady) return withStyle;
    final index = [
      callKnowledge.index(),
      if (_callBrainxOn) _callScopes.take(12).map((s) => s.split('/').last).join(' · '),
    ].where((s) => s.isNotEmpty).join(' · ');
    return '$withStyle\n${MindPersona.callKnowledgeRule(_lang, index)}';
  }

  // ── บุคลิกตอนรับสาย ──
  //
  // เจ้าของ: "ให้เธอตอบอารมณ์ คำสวยเหมือนคน มีหัวเราะบ้าง จีบได้ คุยสนุกได้ แต่ไม่ให้คุยนาน
  // เธอต้องหาทางลงได้เอง เพื่อวางสาย ขอตัวเป็น บุคลิกเรากำหนดได้ใช่ไหม"

  /// ความขี้เล่นกับคนโทร 0 = สุภาพเรียบร้อย · 1 = ขี้เล่น แซว/จีบเบา ๆ ได้
  double _callPlay = 0.4;
  double get callPlay => _callPlay;
  void setCallPlay(double v) {
    final next = v.clamp(0.0, 1.0);
    if (next == _callPlay) return;
    _callPlay = next;
    _save('callPlay', next);
    _notify();
  }

  /// คุยนานสุดกี่นาทีแล้วเธอเริ่มหาทางลงเอง · 0 = ไม่จำกัด
  static const callMinuteChoices = [2, 3, 5, 10, 0];
  int _callMaxMinutes = 3;
  int get callMaxMinutes => _callMaxMinutes;
  void setCallMaxMinutes(int v) {
    if (v < 0 || v == _callMaxMinutes) return;
    _callMaxMinutes = v;
    _save('callMaxMinutes', v);
    _notify();
  }

  /// ข้อความสะกิดกลางสายเมื่อคุยครบเวลา (ดู CallSession._talkRealtime)
  String callWrapUp({bool firm = false, bool outgoing = false}) =>
      MindPersona.callWrapUp(_lang,
          minutes: outgoing ? outgoingWrapMinutes(_callMaxMinutes) : _callMaxMinutes, firm: firm, outgoing: outgoing);

  /// สายที่เธอโทรออกไปคุยงานได้นานกว่าสายเข้า · จองหรือต่อรองที่ต้องรอเจ้าของตอบกินเวลาเกินสามนาทีได้จริง ·
  /// 0 = ไม่จำกัด เหมือนที่เจ้าของตั้ง
  static int outgoingWrapMinutes(int limit) => limit <= 0 ? 0 : (limit < 6 ? 6 : limit);

  /// บุคลิกที่เจ้าของเขียนเอง (เช่น เรียกคนโทรว่าพี่ ชอบหัวเราะ) · ว่าง = ตามค่าตั้งต้น
  static const callStyleMax = 400;
  String _callStyle = '';
  String get callStyle => _callStyle;
  void setCallStyle(String v) {
    final t = v.trim();
    final next = t.length > callStyleMax ? t.substring(0, callStyleMax) : t;
    if (next == _callStyle) return;
    _callStyle = next;
    _save('callStyle', next);
    _notify();
  }

  String _callPromptBase({bool live = false, bool outgoing = false}) => MindPersona.system(
        lang: _lang,
        mode: mode,
        flirt: effectiveFlirt,
        ownerProfile: '',
        boundaries: _boundaries,
        onCall: true,
        liveCall: live,
        outgoing: outgoing ? _outgoing : null,
        askOwner: _outgoingAskOk,
        callerName: _callerName,
        soul: _soul,
        schedule: _calendar?.busyBlock(now: _clock()) ?? '',
        now: _clock(),
      );

  /// ข้อมูลที่ให้คนโทรรู้ได้ (ดู CallKnowledge) · คลังในเครื่องที่เจ้าของใส่เอง
  CallKnowledge get callKnowledge => _lazyKnowledge ??= (CallKnowledge()..load());
  CallKnowledge? _lazyKnowledge;

  /// หมวดในสมอง BrainX ที่เจ้าของติ๊กให้คนโทรรู้ได้ · ค่าตั้งต้น = ไม่มีสักหมวด
  ///
  /// 🔒 คนโทรเป็นคนนอก · สมองมีบันทึกส่วนตัว รหัส งานลูกค้า · ต้องเลือกเปิดเองทีละหมวด
  /// หมวดที่ไม่ติ๊ก เธอมองไม่เห็นเลย (กรองทั้งฝั่งคลาวด์และในแอป ดู BrainXLink.searchAllowed)
  Set<String> _callScopes = const {};
  Set<String> get callBrainxScopes => _callScopes;

  void setCallBrainxScopes(Set<String> scopes) {
    final next = Set<String>.unmodifiable(scopes.map((s) => s.trim()).where((s) => s.isNotEmpty));
    if (setEquals(next, _callScopes)) return;
    _callScopes = next;
    _save('callBrainxScopes', jsonEncode(next.toList()..sort()));
    _notify();
  }

  @visibleForTesting
  static Set<String> decodeScopes(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final j = jsonDecode(raw);
      if (j is List) return Set.unmodifiable(j.whereType<String>().where((s) => s.isNotEmpty));
    } on FormatException {
      // ค่าเสีย = ไม่เปิดสักหมวด (ปลอดภัยกว่าเปิดเกิน)
    }
    return const {};
  }

  bool get _callBrainxOn => _callScopes.isNotEmpty && brainx.connected;

  /// มีอะไรให้เธอค้นตอนรับสายไหม · ไม่มี = ไม่ให้เครื่องมือค้น (เธอจะไม่เสียเวลาค้นของว่าง)
  bool get callLookupReady => !callKnowledge.isEmpty || _callBrainxOn;

  /// ค้นเรื่องที่เจ้าของเปิดให้คนโทรรู้ · คลังในเครื่องก่อน แล้วหมวด BrainX ที่ติ๊ก
  ///
  /// หน้าตั้งค่าใช้ตัวเดียวกันลองค้น · เจ้าของเห็นเหมือนที่เธอเห็นในสายทุกตัวอักษร
  Future<List<({String title, String text, String source})>> callLookup(String query) async {
    // ค้นพลาด = ไม่เจอ · ห้ามโยนเข้าสาย (เธอจะเงียบไปทั้งเทิร์น)
    final local = callKnowledge.search(query).then((v) => v, onError: (Object _) => const <KnowledgeHit>[]);
    final remote = _callBrainxOn ? brainx.searchAllowed(query, _callScopes) : Future.value(const <BrainXHit>[]);
    final (mine, brain) = await (local, remote).wait;
    return [
      for (final h in mine) (title: h.title, text: h.text, source: 'owner'),
      for (final h in brain) (title: h.title, text: h.text, source: 'brainx'),
    ];
  }

  /// เรื่องด่วนระหว่างสาย → แจ้งเตือนเจ้าของทันที (แตะแล้วไปจอสาย แทรกสายคุยเองได้)
  ///
  /// ใช้ช่องแจ้งเตือนเดียวกับบันทึกสาย (ดัง + เด้ง) · ไม่มีสิทธิ์แจ้งเตือน = เงียบ ๆ
  Future<void> alertOwner({required String who, required String reason}) async {
    try {
      await kSystemChannel.invokeMethod<bool>('notifyCallNote', {
        'title': s.callUrgentTitle(who),
        'body': reason,
      });
    } on Object catch (e) {
      debugPrint('สาย: แจ้งเรื่องด่วนไม่ได้ — ${e.runtimeType}');
    }
  }

  // ── สิ่งที่เธอเรียนรู้จากสาย ──
  //
  // เจ้าของ: "ยิ่งคุย ยิ่งเจอ ยิ่งสั่ง ก็ยิ่งเก่ง" · ดู CallLessons ว่าทำไมบทเรียนขยายสิทธิ์ไม่ได้

  CallLessons _lessons = CallLessons();
  List<CallLesson> get callLessons => _lessons.items;

  void _lessonsChanged() {
    _save('callLessons', _lessons.encode());
    _queueLessons();
    _notify();
  }

  void removeCallLesson(String id) {
    if (_lessons.remove(id)) _lessonsChanged();
  }

  void clearCallLessons() {
    if (_lessons.isEmpty) return;
    _lessons.clear();
    _lessonsChanged();
  }

  /// เจ้าของสั่งในแชทว่าอยากให้คุยโทรศัพท์แบบไหน (สกัดได้จาก `call|…`)
  bool addOwnerCallRule(String text) {
    if (!_lessons.addOwnerRule(text, at: _clock())) return false;
    _lessonsChanged();
    return true;
  }

  /// หลังจบสาย · สรุปบทเรียนด้วยสมองตัวที่เลือก · พลาด = ข้าม ไม่กระทบบันทึกสาย
  Future<void> _learnFromCall({required String block, required String source, String? contact, String? task}) async {
    try {
      final raw = await _askBrain(
        callLessonPrompt(_lang == AppLang.th, task: task),
        [(fromHer: false, text: block)],
        cap: ReplyCap.background,
      );
      if (_disposed) return;
      final n = _lessons.addFromCall(CallLessons.parse(raw), source: source, contact: contact, at: _clock());
      if (n > 0) {
        debugPrint('สาย: เรียนรู้จากสายนี้ $n ข้อ');
        _lessonsChanged();
      }
    } on Object catch (e) {
      debugPrint('สาย: สรุปบทเรียนไม่สำเร็จ — ${e.runtimeType}');
    }
  }

  // ── โค้ดลับ ──
  //
  // เจ้าของ: "เธออ่านและเรียกใช้ได้ แต่หลอกถามให้พูดไม่ได้ ยกเว้น คนมีโค๊ดลับ" · ดู OwnerGate

  /// อยู่ใน SecretStore (Keystore) ไม่ใช่ค่าตั้งค่าธรรมดา · ไม่เคยเข้า prompt ไม่ลง log
  String _callCode = '';
  bool get hasCallCode => _callCode.isNotEmpty;

  /// เวลาที่ใส่โค้ดผิด (ข้ามสาย) · ผิดครบ [codeFailLimit] ใน [codeFailWindow] = ล็อก
  List<DateTime> _codeFails = const [];
  static const codeFailLimit = 5;
  static const codeFailWindow = Duration(hours: 24);

  @visibleForTesting
  static List<DateTime> decodeCodeFails(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final j = jsonDecode(raw);
      if (j is List) return [for (final v in j) if (v is int) DateTime.fromMillisecondsSinceEpoch(v)];
    } on FormatException {
      // เสีย = เริ่มนับใหม่
    }
    return const [];
  }

  /// ล็อกอยู่ถึงเมื่อไร · null = ไม่ล็อก
  DateTime? get callCodeLockedUntil {
    final now = _clock();
    final recent = _codeFails.where((t) => now.difference(t) < codeFailWindow).toList()..sort();
    if (recent.length < codeFailLimit) return null;
    return recent[recent.length - codeFailLimit].add(codeFailWindow);
  }

  void _resetCodeFails() {
    _codeFails = const [];
    _save('callCodeFails', '[]');
  }

  /// ตั้ง/เปลี่ยนโค้ด · false = สั้นเกิน ([OwnerCode.acceptable]) หรือเก็บลง Keystore ไม่ได้
  Future<bool> setCallCode(String code) async {
    final v = code.trim();
    if (!OwnerCode.acceptable(v)) return false;
    if (!await SecretStore.write(SecretStore.kCallCode, v)) return false;
    _callCode = v;
    _resetCodeFails();
    _notify();
    return true;
  }

  Future<bool> clearCallCode() async {
    if (!await SecretStore.write(SecretStore.kCallCode, '')) return false;
    _callCode = '';
    _resetCodeFails();
    _notify();
    return true;
  }

  @visibleForTesting
  void debugSetCallCode(String code) => _callCode = code.trim();

  /// ให้รายงานดีบัคลบโค้ดออก (DebugReport.redact) · ใช้ที่อื่นไม่ได้
  String get callCodeForReport => _callCode;

  /// ตรวจคำที่คนโทรพูด · นับครั้งผิดข้ามสาย · ล็อกแล้วไม่เทียบอีก (โค้ดถูกก็ไม่ผ่านจนพ้นล็อก)
  Future<CodeCheck> checkCallCode(String heard) async {
    if (_callCode.isEmpty) return CodeCheck.wrong;
    if (callCodeLockedUntil != null) return CodeCheck.locked;
    if (OwnerCode.matches(_callCode, heard)) return CodeCheck.ok;
    final now = _clock();
    _codeFails = [..._codeFails.where((t) => now.difference(t) < codeFailWindow), now];
    _save('callCodeFails', jsonEncode([for (final t in _codeFails) t.millisecondsSinceEpoch]));
    _notify();
    return callCodeLockedUntil != null ? CodeCheck.locked : CodeCheck.wrong;
  }

  /// ลบโค้ดและคำตอบยืนยันตัวตนออกจากข้อความ · ทุกอย่างที่ออกจากสายไปเก็บ/สรุป/ส่งขึ้นสมองผ่านตัวนี้
  String scrubCallCode(String text) {
    var t = _callCode.isEmpty ? text : OwnerCode.redact(text, _callCode);
    // 🔴 คนโทรตอบคำถามออกมาดัง ๆ · ความจำเรื่องเจ้าของก็อาจมีคำตอบอยู่ (ชื่อแมว โรงเรียนเก่า)
    for (final q in _quiz.items) {
      if (q.answer.trim().isNotEmpty) t = OwnerCode.redact(t, q.answer, mark: '[answer]');
    }
    return t;
  }

  /// ประตูความจำเรื่องเจ้าของของสายนี้ · null = ไม่มีทางเปิด (ไม่มีทั้งโค้ดและคำถามยืนยันตัวตน ·
  /// สายไม่มีเครื่องมือ check_code / recall_owner) · มีแต่คำถาม = ไม่มี check_code เปิดได้ด้วย
  /// [IdentityGate] อย่างเดียว ([OwnerGate.grant])
  OwnerGate? ownerGateForCall({required String who}) {
    if (_callCode.isEmpty && !_quiz.ready) return null;
    return OwnerGate(
      check: checkCallCode,
      recall: ownerRecall,
      hasCode: _callCode.isNotEmpty,
      // ใครได้ฟังความจำไป เจ้าของต้องรู้ · ใส่ผิดจนหมดสิทธิ์ก็ต้องรู้ (อาจมีคนพยายามเดา)
      onOpened: () => unawaited(_notifyOwner(s.callCodeOpenedTitle(who), s.callCodeOpenedBody)),
      onRefused: (_) => unawaited(_notifyOwner(s.callCodeRefusedTitle(who), s.callCodeRefusedBody)),
    );
  }

  // ── คำถามยืนยันตัวตน ──
  //
  // เจ้าของ: "ให้ยืนยันด้วยคำถาม ยืนยันตัวตน อย่างน้อย 3 ข้อ เพื่อเข้าถึงสิทธิ์ เรากำหนดได้ในแอพว่าต้องตอบอะไร" ·
  // ดู IdentityGate · ผ่าน = สั่งให้เธอใช้เครื่องได้ระหว่างสายนั้น (CallPhone) + ฟังความจำเรื่องเจ้าของ

  /// อยู่ใน SecretStore (Keystore) · คำตอบไม่เคยเข้า prompt ไม่ลง log
  IdentityQuiz _quiz = IdentityQuiz.empty;

  /// เพิ่มทุกครั้งที่เจ้าของเปลี่ยน/ลบคำถาม · ประตูของสายที่สร้างก่อนหน้าใช้ไม่ได้อีก
  int _quizVersion = 0;

  /// เวลาที่ตอบไม่ผ่าน (ข้ามสาย) · ครบ [identityFailLimit] ใน [identityFailWindow] = ล็อก
  List<DateTime> _idFails = const [];
  static const identityFailLimit = 3;
  static const identityFailWindow = Duration(hours: 24);

  /// ตั้งคำถามครบและใช้ได้
  bool get callQuizReady => _quiz.ready;

  /// สำหรับหน้าจอทั่วไป · มีแต่คำถาม ไม่มีคำตอบ
  IdentityQuiz get callQuiz => _quiz.withoutAnswers();

  /// 🔒 สำหรับหน้าแก้คำถามเท่านั้น (เติมค่าเดิมให้เจ้าของแก้) · มีคำตอบ
  IdentityQuiz callQuizForEditing() => _quiz;

  /// ล็อกอยู่ถึงเมื่อไร · null = ไม่ล็อก
  DateTime? get identityLockedUntil {
    final now = _clock();
    final recent = _idFails.where((t) => now.difference(t) < identityFailWindow).toList()..sort();
    if (recent.length < identityFailLimit) return null;
    return recent[recent.length - identityFailLimit].add(identityFailWindow);
  }

  void _resetIdentityFails() {
    _idFails = const [];
    _save('callIdentityFails', '[]');
  }

  /// ตั้ง/เปลี่ยนคำถาม · false = ยังไม่ผ่านเงื่อนไข ([IdentityQuiz.problem]) หรือเก็บลง Keystore ไม่ได้ ·
  /// เปลี่ยนคำถาม = ล้างตัวนับครั้งที่ไม่ผ่าน
  Future<bool> setCallQuiz(IdentityQuiz quiz) async {
    final q = quiz.trimmed();
    if (!q.ready) return false;
    if (!await SecretStore.write(SecretStore.kCallQuestions, q.encode())) return false;
    _quiz = q;
    _quizVersion++;
    _resetIdentityFails();
    _notify();
    return true;
  }

  Future<bool> clearCallQuiz() async {
    if (!await SecretStore.write(SecretStore.kCallQuestions, '')) return false;
    _quiz = IdentityQuiz.empty;
    _quizVersion++;
    _resetIdentityFails();
    _notify();
    return true;
  }

  @visibleForTesting
  void debugSetCallQuiz(IdentityQuiz quiz) {
    _quiz = quiz.trimmed();
    _quizVersion++;
  }

  /// ให้รายงานดีบัคลบคำตอบออก (DebugReport.redact) · ใช้ที่อื่นไม่ได้
  List<String> get callAnswersForReport => [for (final q in _quiz.items) q.answer];

  Future<void> _identityFailed(int version) async {
    // เจ้าของเปลี่ยนคำถามระหว่างสาย = ตัวนับเริ่มใหม่ไปแล้ว ไม่นับของชุดเก่า
    if (version != _quizVersion) return;
    final now = _clock();
    _idFails = [..._idFails.where((t) => now.difference(t) < identityFailWindow), now];
    _save('callIdentityFails', jsonEncode([for (final t in _idFails) t.millisecondsSinceEpoch]));
    _notify();
  }

  /// คำถามยืนยันตัวตนของสายนี้ · null = เจ้าของไม่ได้ตั้ง (ไม่มีเครื่องมือ identity_*) ·
  /// [unlocks] = ประตูความจำของสายเดียวกัน · ผ่านแล้วเปิดให้ด้วย
  IdentityGate? identityGateForCall({required String who, OwnerGate? unlocks}) {
    if (!_quiz.ready) return null;
    final version = _quizVersion;
    return IdentityGate(
      quiz: _quiz,
      // เปลี่ยนคำถามกลางสาย = ชุดเก่าที่อาจหลุดไปแล้วใช้ไม่ได้ทันที
      isLocked: () => version != _quizVersion || identityLockedUntil != null,
      recordFail: () => _identityFailed(version),
      onPassed: () {
        unlocks?.grant();
        // ใครได้สิทธิ์สั่งเครื่อง เจ้าของต้องรู้ทันที
        unawaited(_notifyOwner(s.callIdPassedTitle(who), s.callIdPassedBody(phone: _phoneControl)));
      },
      onRefused: ({required bool locked}) {
        final until = identityLockedUntil;
        unawaited(_notifyOwner(
          s.callIdRefusedTitle(who),
          locked && until != null ? s.callIdLockedBody(_hhmm(until)) : s.callIdRefusedBody,
        ));
      },
    );
  }

  static String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _notifyOwner(String title, String body) async {
    try {
      await kSystemChannel.invokeMethod<bool>('notifyCallNote', {'title': title, 'body': body});
    } on Object catch (e) {
      debugPrint('สาย: แจ้งเจ้าของไม่ได้ — ${e.runtimeType}');
    }
  }

  /// ความจำของเธอเรื่องเจ้าของ · 🔒 เรียกได้ทางเดียวคือ OwnerGate.lookup หลังโค้ดถูก ·
  /// ความจำในเครื่อง + โน้ตของมายด์บนสมอง (`Mind/` เท่านั้น ไม่ใช่ทั้งสมอง) ·
  /// บรรทัดที่หน้าตาเหมือนความลับถูกตัดทิ้ง และโค้ดถูกลบออกก่อนเข้าสาย
  Future<List<({String title, String text})>> ownerRecall(String query) async {
    String clean(String t) => const LineSplitter()
        .convert(t)
        .where((l) => !looksLikeSecret(l))
        .map(scrubCallCode)
        .join('\n')
        .trim();
    final mine = [for (final f in memory.recall(query, limit: 6)) clean(f.text)];
    final brain = brainx.connected ? await brainx.searchAllowed(query, const {'Mind'}) : const <BrainXHit>[];
    return [
      for (final t in mine)
        if (t.isNotEmpty) (title: 'memory', text: t),
      for (final h in brain)
        if (clean(h.text) case final t when t.isNotEmpty) (title: h.title, text: t),
    ];
  }

  /// สังเคราะห์เสียงสำหรับพูดเข้าสาย · คืนไบต์ ไม่ได้เล่นเอง
  ///
  /// ไม่ผ่าน [_speakIfEnabled] เพราะเสียงในสาย**ห้ามไปออกที่ WebView**
  /// (ปากจะขยับตามคลื่นก็จริง แต่เสียงจะดังซ้ำสองทางแล้วก้องกลับเข้าสาย)
  /// ปากบนเวทีอ่านคลื่นจากไบต์ชุดเดียวกันนี้แบบปิดเสียง (ดู [MindLips])
  Future<Utterance> speakForCall(String text) =>
      synthesizeWithFallback(text, voiceFor(VoiceChannel.answer));

  // ═══ คุยสดในสาย (OpenAI Realtime) ═════════════════════════
  //
  // เจ้าของ: "ต้องทำ real time พูดคุยเลย ถ้าตั้งค่าเป็น open ai" · ใช้เมื่อสมองเป็น
  // OpenAI ด้วยคีย์ของเจ้าของ · ต่อไม่ได้ = ตกไปทางเดิม (ฟัง → ถอด → คิด → พูด)

  /// เปิดเป็นค่าตั้งต้น · ปิดได้ (Realtime คิดเงินตามเสียง แพงกว่าทางเดิม)
  bool _realtimeCalls = true;
  bool get realtimeCalls => _realtimeCalls;

  void setRealtimeCalls(bool v) {
    if (_realtimeCalls == v) return;
    _realtimeCalls = v;
    _save('realtimeCalls', v);
    _notify();
  }

  /// สายนี้คุยสดได้ไหม · ไม่ใช่ OpenAI ด้วยคีย์ตัวเอง = ไม่ได้ (ไม่ยืมคีย์ข้ามสมอง)
  bool get realtimeCallsReady =>
      _realtimeCalls && _brain == BrainProvider.openai && hasOwnKey;

  /// คุยด้วย GPT-Live แทน Realtime · ปิดเป็นค่าตั้งต้น เพราะ OpenAI ยังไม่ระบุว่ารองรับภาษาไทย
  /// และคิดเงินตามนาทีตลอดสาย · เจ้าของเปิดเองเมื่ออยากลอง ใช้ได้ก็ต่อเมื่อคุยสดเปิดอยู่
  bool _liveCalls = false;
  bool get liveCalls => _liveCalls;

  void setLiveCalls(bool v) {
    if (_liveCalls == v) return;
    _liveCalls = v;
    _save('liveCalls', v);
    _notify();
  }

  /// ต้องต่อสายตรงอยู่ด้วย · ผู้เรียกเช็กเอง ([CallSession] รู้ทางเสียงของสายนั้น)
  bool get callLiveReady => _liveCalls && realtimeCallsReady;

  /// ทางต่อ WebSocket · เทสต์ฉีดของปลอม
  @visibleForTesting
  RtConnect? debugRealtimeConnect;

  CallLookup? get _lookupForCall => callLookupReady
      ? (q) async => [for (final h in await callLookup(q)) (title: h.title, text: h.text)]
      : null;

  /// เซสชันคุยสดของสายนี้ · prompt เดียวกับทางเดิม (ไม่มีข้อมูลส่วนตัว — [callPrompt])
  ///
  /// [outgoing] = สายที่น้องมายโทรออก · ไม่มีคำทักตายตัว (รอปลายสายพูด "ฮัลโหล" ก่อน)
  /// · [greet] = false เมื่อรับช่วงต่อจาก GPT-Live ที่ทักไปแล้ว
  RealtimeCall openRealtimeCall({bool outgoing = false, bool greet = true, String? contact}) {
    final greeting = outgoing || !greet ? '' : callGreeting();
    // สร้างดัชนีคลังไว้ตั้งแต่สายเริ่ม · คำถามแรกของคนโทรจะได้ไม่ต้องรอ
    unawaited(callKnowledge.warm());
    return RealtimeCall(
      apiKey: effectiveOpenAiKey,
      instructions: callPrompt(live: true, outgoing: outgoing, contact: contact),
      greeting: greeting,
      // เสียงที่ตั้งไว้ให้ "ตอบรับสาย" · ไม่ใช่เสียงที่ Realtime รู้จัก = marin
      voice: voiceFor(VoiceChannel.answer).voice,
      language: _sttLang,
      transcriptionHint: MindPersona.callTranscriptionHint(_lang, greeting: greeting),
      languageReminder: MindPersona.callLanguageReminder(_lang),
      lookup: _lookupForCall,
      connect: debugRealtimeConnect,
    );
  }

  /// เซสชัน GPT-Live ของสายนี้ · prompt เดียวกับ Realtime ทุกตัวอักษร (ไม่มีข้อมูลส่วนตัว — [callPrompt])
  LiveCall openLiveCall({bool outgoing = false, String? contact}) {
    unawaited(callKnowledge.warm());
    return LiveCall(
      apiKey: effectiveOpenAiKey,
      instructions: callPrompt(live: true, outgoing: outgoing, contact: contact),
      greeting: outgoing ? '' : callGreeting(),
      // เสียงที่ตั้งไว้ให้ "ตอบรับสาย" · ไม่ใช่เสียงที่ GPT-Live รู้จัก = marin
      voice: voiceFor(VoiceChannel.answer).voice,
      languageReminder: MindPersona.callLanguageReminder(_lang),
      lookup: _lookupForCall,
      connect: debugRealtimeConnect,
    );
  }

  // ═══ คุยต่อเนื่องด้วยเสียงในแชท ═══════════════════════════
  //
  // เจ้าของ: "การกดไมค์พูดกับเธอควรพูดโต้ตอบได้เรียลไทม์ เหมือนที่เราทำกับการรับสาย และต้องเข้าใจว่าบริบทไหน
  // ที่เราหยุดให้เธอปฏิบัติได้ ... เพราะเราออกแบบให้แอพนี้ใช้งานแม้ในขับรถได้" · ตัวคุมอยู่ lib/ai/voice_chat.dart ·
  // ตรงนี้คือส่วนที่ต้องรู้จักสมอง ความจำ และเครื่องมือของแชท

  /// ใช้คุยสด (Realtime) ในโหมดคุยต่อเนื่องเมื่อทำได้ · ปิด = ทีละตา (ถอดเสียง → คิด → พูดด้วยเสียงที่เลือก)
  bool _voiceChatLive = true;
  bool get voiceChatLive => _voiceChatLive;

  void setVoiceChatLive(bool v) {
    if (_voiceChatLive == v) return;
    _voiceChatLive = v;
    _save('voiceChatLive', v);
    _notify();
  }

  /// คุยสดได้ไหมตอนนี้ · OpenAI ด้วยคีย์ของเจ้าของเท่านั้น (เหมือนในสาย · ไม่ยืมคีย์ข้ามสมอง)
  bool get voiceChatLiveReady => _voiceChatLive && _brain == BrainProvider.openai && hasOwnKey;

  /// เสียงที่เจ้าของเลือกให้คุยสด · ว่าง = ยังไม่เคยเลือก
  String _voiceChatVoicePick = '';

  void setVoiceChatVoice(String v) {
    if (!RealtimeCall.voices.contains(v) || v == _voiceChatVoicePick) return;
    _voiceChatVoicePick = v;
    _save('voiceChatVoice', v);
    _notify();
  }

  /// เสียงของเธอตอนคุยสด · เลือกเอง > เสียงแชท > ค่าตั้งต้น
  ///
  /// เจ้าของ: "ฉันรู้สึกว่าเธอเลือกใช้เสียง เดียวกับการโทรเข้าหรือออก" · ของเดิมตกไปเสียงรับสายจริง ·
  /// 🔴 ห้ามหยิบเสียงของช่องโทร · คนละช่อง เจ้าของตั้งแยกไว้คนละเหตุผล
  String get voiceChatVoice {
    if (RealtimeCall.voices.contains(_voiceChatVoicePick)) return _voiceChatVoicePick;
    final chat = voiceFor(VoiceChannel.chat).voice;
    return RealtimeCall.voices.contains(chat) ? chat : VoiceProfile.openAiDefaults.voice;
  }

  /// เสียงคุยสดในรูปที่สังเคราะห์เป็นไฟล์ได้ · ลองฟังกับเสียงขาน ซึ่งไม่ได้ผ่าน Realtime
  VoiceProfile get voiceChatLiveProfile {
    final chat = voiceFor(VoiceChannel.chat);
    final base = chat.engine == TtsEngine.openai
        ? chat
        : VoiceProfile.defaultFor(VoiceChannel.chat, lang).copyWith(engine: TtsEngine.openai);
    return base.copyWith(voice: voiceChatVoice);
  }

  /// เสียงที่เธอจะขาน · ต้องเป็นเสียงเดียวกับที่คุยต่อ ไม่งั้นขานคนละคน
  VoiceProfile get _wakeReplyProfile =>
      voiceChatLiveReady ? voiceChatLiveProfile : voiceFor(VoiceChannel.chat);

  /// เปลี่ยนเมื่อเสียงขานที่อัดไว้ใช้ไม่ได้แล้ว ([renderWakeReplies] ต้องอัดใหม่)
  int get wakeReplyKey => Object.hash(lang, _wakeReplyProfile);

  RealtimeChat openVoiceChat({required ChatToolRunner tools}) => RealtimeChat(
        apiKey: effectiveOpenAiKey,
        instructions: voiceChatPrompt(),
        tools: chatVoiceTools(web: _webSearch && _webSearcher() != null, phone: _phoneControl),
        runChatTool: tools,
        voice: voiceChatVoice,
        language: _sttLang,
        connect: debugRealtimeConnect,
      );

  /// บุคลิกในแชทเดิมทั้งหมด (ความจำ ตาราง โปรไฟล์ สายวันนี้) ไม่มีแท็ก + วิธีคุยด้วยเสียงและเครื่องมือ
  String voiceChatPrompt() {
    final linked = _brainxSearch && brainx.connected;
    final system = MindPersona.system(
      lang: _lang,
      mode: mode,
      flirt: effectiveFlirt,
      ownerProfile: _ownerProfile,
      boundaries: _boundaries,
      soul: _soul,
      memories: memory.promptBlock(limit: coreMemories),
      schedule: _calendar?.promptBlock() ?? '',
      calls: _callsBlock,
      now: _clock(),
      pcProfile: linked ? brainx.ownerProfile : '',
    );
    final block = MindPersona.voiceChatBlock(
      _lang,
      web: _webSearch && _webSearcher() != null,
      phone: _phoneControl,
      mailApps: _mailApps == null ? null : [for (final a in _mailApps!) a.name],
    );
    return '$system\n$block';
  }

  /// บทล่าสุดในแชท ให้เซสชันเสียงรู้ว่าคุยอะไรกันอยู่ · ว่าง = ยังไม่ได้คุย
  String voiceChatRecap({int turns = 8}) {
    final recent = _context.length > turns ? _context.sublist(_context.length - turns) : _context;
    if (recent.isEmpty) return '';
    final lines = [
      for (final m in recent)
        '${m.fromHer ? 'You' : 'Owner'}: ${m.text.replaceAll(RegExp(r'\s+'), ' ').trim()}',
    ];
    return 'The chat so far, just before the owner switched to voice (for context; do not repeat it):\n'
        '${lines.join('\n')}';
  }

  /// บทพูดของคุยสดลงแชท · ความจำ ไทม์ไลน์ และสมองบนคอมเห็นเหมือนคุยด้วยการพิมพ์
  void noteVoiceLine({required bool fromHer, required String text}) {
    final t = text.trim();
    if (t.isEmpty || _disposed) return;
    // ระหว่างคุยสด แผงแชทไม่ควรพับหนีกลางบทสนทนา
    _push(fromHer ? ChatMessage.her(t) : ChatMessage.me(t));
    _notify();
  }

  /// เสียงขานรับเมื่อถูกเรียกชื่อ · สังเคราะห์ล่วงหน้าด้วยเสียงแชทของเธอ ขานได้ทันทีโดยไม่รอเน็ต ·
  /// ทางไหนล้มก็ตกไปเสียงเครื่องเหมือนการพูดปกติ · ได้ไม่ครบ = คืนเท่าที่ได้
  Future<List<Utterance>> renderWakeReplies() async {
    final profile = _wakeReplyProfile;
    final out = <Utterance>[];
    for (final word in s.wakeReplyWords) {
      try {
        out.add(await synthesizeWithFallback(word, profile));
      } on Object catch (e) {
        debugPrint('เสียงขาน: สังเคราะห์ไม่สำเร็จ — ${e.runtimeType}');
      }
    }
    return out;
  }

  /// เจ้าของพูดตอบกล่องยืนยันการโทรระหว่างคุยสด · true = ตัดสินแล้ว (โทร/ไม่โทร)
  ///
  /// 🔴 ตัดสินจาก**คำพูดของเจ้าของเอง** ในเครื่อง ไม่ใช่จากที่โมเดลเข้าใจ · โมเดลไม่มีเครื่องมือกดยืนยันเอง
  Future<bool> confirmCallByVoice(String text) async {
    final p = _pendingCall;
    if (p == null) return false;
    final yes = CallReply.confirm(text);
    if (yes == null) return false;
    // ด้วยเสียง "ใช่" "โอเค" อาจตอบคำถามอื่นของเธอ · กดโทรเมื่อพูดว่าโทรชัด ๆ เท่านั้น
    if (yes && !CallReply.saysCall(text)) return false;
    if (yes) {
      if (await _voiceBarred()) return false;
      await confirmPendingCall();
    } else {
      cancelPendingCall(id: p.id);
    }
    return true;
  }

  /// เครื่องมือที่เธอเรียกระหว่างคุยสด · คืนผลเป็นข้อความให้เธอพูดต่อ (อังกฤษ · เธอแปลเองตอนพูด)
  Future<String> runVoiceTool(String name, Map<String, Object?> args) async {
    String arg(String k) => '${args[k] ?? ''}'.trim();
    switch (name) {
      case 'call_someone':
        final who = arg('who');
        final task = arg('task');
        if (who.isEmpty) return 'Ask the owner who to call.';
        final said = await _resolveCall(who, task.isEmpty ? who : task);
        if (said == null) {
          return 'A confirmation card is on the screen now. Tell the owner in one short sentence who you will call '
              '(name and last four digits) and that they can say "call now" or "cancel". Do not say the call has '
              'started.';
        }
        // ข้อความถาม/หาไม่เจอขึ้นแชทด้วย · เจ้าของที่มองจอได้แตะเลือกได้ · ไม่ผ่าน [_say]
        // (onHerNotice จะสั่งให้เธอพูดซ้ำทั้งที่ผลนี้กลับไปให้เธอพูดอยู่แล้ว)
        if (!_disposed) {
          _push(ChatMessage.her(said));
          _notify();
        }
        return 'Not dialed. What the app found (tell the owner briefly in your own spoken words; if it is a list, '
            'read the names with the last four digits and ask which one, then call call_someone again with that '
            'exact name or number):\n$said';
      case 'phone_lookup':
        final kind = switch (arg('kind')) {
          'contacts' => PhoneLookupKind.contacts,
          'sms' => PhoneLookupKind.sms,
          _ => PhoneLookupKind.calls,
        };
        var q = arg('query');
        if (q.length > PhoneLookup.argChars) q = q.substring(0, PhoneLookup.argChars);
        return phoneLookup.run(PhoneLookupCall(kind, q), last: true);
      case 'web_search':
        final web = _webSearch ? _webSearcher() : null;
        if (web == null) return 'Web search is not available right now. Say so briefly.';
        return webTools.run(ToolCall(WebTool.search, arg('query')), last: true, web: web);
      case 'phone_task':
        if (!_phoneControl) return 'You are not allowed to use the phone right now (the owner turned it off).';
        final goal = arg('goal');
        if (goal.isEmpty) return 'Ask the owner what to do.';
        unawaited(_phoneTaskFromChat(goal));
        return 'Started. Tell the owner in one short sentence that you are doing it now; you will tell them the result.';
    }
    return 'Unknown tool.';
  }

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
      final at = DateTime.now();
      unawaited(db.addMessage(fromHer: m.fromHer, text: m.text).then(
            // ทำดัชนีด้วย id จากฐาน · ระบบนึกออกหาคู่ "ถาม → ตอบ" จากลำดับ id
            (id) {
              _chatRecall.add((id: id, fromHer: m.fromHer, text: m.text, at: at));
              _queueDay(at);
            },
            onError: (Object e) => debugPrint('state: เก็บข้อความไม่ได้ — ${e.runtimeType}'),
          ));
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
    // เธอกำลังพิมพ์แท็กขอค้น · ไม่โชว์ "[[ค้นหา: …" ให้เห็น บอกว่ากำลังหาแทน
    // · แท็กท้ายคำตอบ ([[โทร: …]] / [[ทำในเครื่อง: …]]) ตัดทิ้ง โชว์แค่ข้อความก่อนหน้า
    final cut = text.indexOf('[[');
    final shown = (cut < 0 ? text : text.substring(0, cut)).trim();
    _partial = WebTools.looksLikeTag(text) || (cut >= 0 && shown.isEmpty) ? s.lookingUpGeneric : shown;
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
        // ตอบเรื่องโทรที่ค้างอยู่ ("คนที่สอง" "โทรเลย") ตัดสินในเครื่องก่อน · ไม่ใช่ = ถามสมอง
        reply = await _localReply(text) ?? await _think();
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
      // '' = เรื่องโทรที่ทำไปแล้ว (ข้อความ "กำลังโทร" ขึ้นเองแล้ว) · ไม่มีอะไรต้องตอบหรือพูดซ้ำ
      if (reply.isEmpty) return;
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
  ///
  /// 🔴 **เสียงจริงของเจ้า/รุ่น/เสียงที่เลือกอยู่เท่านั้น — ไม่ตกไปเสียงเครื่อง**
  ///
  /// ของเดิมใช้ทางเดียวกับตอนคุย ซึ่งตกไปใช้เสียงเครื่องเมื่อเจ้าที่เลือกใช้ไม่ได้
  /// (คีย์ผิด เครดิตหมด) · เจ้าของกดฟังเสียง ElevenLabs แล้วได้ยินเสียงเครื่อง
  /// โดยไม่รู้ว่ามันไม่ใช่ตัวที่เลือก และเหตุผลไปขึ้นที่หน้าแชทซึ่งไม่ได้เปิดอยู่
  ///
  /// คืนเหตุผลที่ฟังไม่ได้ (ภาษาคน) · null = เล่นเสียงตัวที่เลือกแล้วจริง
  /// [onPlaying] ถูกเรียกตอนสร้างเสียงเสร็จและเริ่มเล่น (หน้าจอบอกขั้นตอนได้)
  Future<String?> previewVoice(
    VoiceChannel channel, {
    VoiceProfile? as,
    void Function()? onPlaying,
  }) async {
    final out = speaker;
    if (out == null) return s.errVoiceNoOutput;
    await hush();
    final profile = as ?? voiceFor(channel);
    final seq = ++_speechSeq;
    try {
      debugPrint('เสียง: ลองฟัง ${profile.engine.name} · ${profile.model} · ${profile.voice}');
      final u = await _speech.synthesize(s.flirtSample(effectiveFlirt), profile: profile);
      if (_disposed || seq != _speechSeq) return null;
      _speaking = true;
      _speakingSeq = seq;
      _notify();
      onPlaying?.call();
      final played = await out(u);
      if (!played && seq == _speechSeq) return s.errVoiceNoOutput;
      // เล่น "สำเร็จ" แต่เสียงสื่อเป็นศูนย์ = ไม่มีใครได้ยิน · ต้องบอกตรงนี้
      if (played && await MindAudio.mediaMuted() == true) return s.errMediaMuted;
      return null;
    } on OpenAiFailure catch (e) {
      return e.message;
    } on Object catch (e) {
      debugPrint('เสียง: ลองฟังล้มแบบที่ไม่ได้เตรียมรับไว้ — ${e.runtimeType}');
      return s.errTtsFailed;
    } finally {
      if (_speakingSeq == seq || !_speaking) _speaking = false;
      if (!_disposed) _notify();
    }
  }

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
    if (_speaking || _typing || !_chatOpen || _handsFree) return;
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
    final out = (_onScreen ? null : speakerOffScreen) ?? speaker;
    // คุยต่อเนื่องด้วยเสียง (มือว่าง ขับรถ) = เจ้าของเปิดไมค์คุยเอง ต้องได้ยินคำตอบแม้ปิดเสียงไว้
    if (!_voiceOut) {
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
      if (seq != _speechSeq || !_voiceOut) return;

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
        // 🔴 บอกเจ้าของว่าทำไมเสียงเปลี่ยน · เงียบ ๆ = เขาเลือกเสียงพรีเมียม
        // ไว้ (คีย์ผิด/เครดิตหมด) แล้วได้ยินเสียงเครื่องโดยไม่รู้ว่าต้องแก้อะไร
        reportError(e.message);
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
    final tools = _webSearch;
    final web = tools ? _webSearcher() : null;
    final linked = _brainxSearch && brainx.connected;
    if (linked) unawaited(brainx.refreshOwnerProfile());
    final nudge = _nudgeDue();
    final system = MindPersona.system(
      lang: _lang,
      mode: mode,
      flirt: effectiveFlirt,
      ownerProfile: _ownerProfile,
      boundaries: _boundaries,
      soul: _soul,
      memories: memory.promptBlock(limit: coreMemories),
      schedule: _calendar?.promptBlock() ?? '',
      calls: _callsBlock,
      now: _clock(),
      tools: tools,
      webSearch: web != null,
      callOut: true,
      phoneControl: _phoneControl,
      routines: [for (final m in _macros) m.name],
      phoneData: true,
      mailApps: _mailApps == null ? null : [for (final a in _mailApps!) a.name],
      pcProfile: linked ? brainx.ownerProfile : '',
      nudge: nudge
          ? MindPersona.cloudNudgeBlock(_lang,
              survivesUninstall: _store?.vault.stage == VaultStage.ready)
          : '',
    );
    final history = [
      for (final m in _context) (fromHer: m.fromHer, text: m.text),
    ];
    // สมองก้อนเดียวกับมายด์บนคอม · ค้นพร้อมกันกับความจำในเครื่อง เกินสามวิก็ตอบจากที่มี
    final brainHits = linked ? await _brainHits(history) : const <BrainXHit>[];
    final recall = recallFor(history, brain: brainHits);
    var answer = await _askBrain(system, history, onPartial: _showPartial, recall: recall);
    if (nudge) _noteNudge(answer);

    // เธอขอข้อมูล (แท็ก [[ค้นหา: …]] / [[ประวัติโทร: …]]) → ไปหาให้ → แนบผลแล้วให้ตอบอีกรอบ
    //
    // 🔴 ตาของเธอที่ขอค้นใส่เป็น**คำตอบดิบทั้งก้อน** ไม่ใช่แท็กที่สร้างใหม่ ·
    // สมองในเครื่องจำสิ่งที่มันพูดไว้ตรงตัวอักษร ถ้าไม่ตรง session ต่อไม่ได้
    // ต้องอ่านทั้งบทใหม่ (ช้า) · บทที่ขอค้นกับผลไม่ลงความจำ/หน้าจอ เห็นแค่คำตอบสุดท้าย
    //
    // ของในเครื่อง (สมุดโทรศัพท์ สาย SMS) ไม่ขึ้นกับสวิตช์ค้นเว็บ · ไม่ได้ออกเน็ตไปหาที่ไหน
    var turns = history;
    for (var round = 1; round <= maxLookups; round++) {
      if (_disposed) break;
      final webCall = tools ? WebTools.parse(answer) : null;
      final phoneCall = webCall == null ? PhoneLookup.parse(answer) : null;
      if (webCall == null && phoneCall == null) break;
      _partial = webCall != null
          ? s.lookingUp(webCall.arg)
          : switch (phoneCall!.kind) {
              PhoneLookupKind.contacts => s.lookingContacts,
              PhoneLookupKind.calls => s.lookingCalls,
              PhoneLookupKind.sms => s.lookingSms,
            };
      _notify();
      final last = round == maxLookups;
      final result = webCall != null
          ? await webTools.run(webCall, last: last, web: web)
          : await phoneLookup.run(phoneCall!, last: last);
      if (_disposed) break;
      turns = [
        ...turns,
        (fromHer: true, text: answer.trim()),
        (fromHer: false, text: result),
      ];
      answer = await _askBrain(
        system,
        turns,
        onPartial: _showPartial,
        // สมองทางเน็ตไม่จำอะไร ต้องแนบบันทึกช่วยจำซ้ำ · สมองในเครื่องจำไว้แล้วใน session
        recall: _brain == BrainProvider.onDevice ? '' : recall,
      );
    }
    // 🔴 แท็กสั่งงาน (โทรออก / ทำในเครื่อง) อ่านเสมอ แม้ปิดค้นเว็บ · เดิม `if (!tools) return answer;`
    // อยู่ก่อนตรงนี้ ปิดสวิตช์ค้นเว็บแล้วแท็ก [[โทร: …]] ที่ยังสอนอยู่หลุดขึ้นจอและถูกอ่านออกเสียง
    //
    // สั่งให้โทรออก → หาว่าใคร → ขอเจ้าของยืนยันก่อน (ไม่โทรเอง) · แท็กไม่ขึ้นจอ ไม่อ่านออกเสียง ·
    // หาก่อนตอบ (ในเครื่อง ไม่กี่ร้อยมิลลิวินาที) · ไม่ชัด/ไม่เจอ = คำถาม "คนไหนคะ" แทน "ได้ค่ะ จะโทรให้"
    final out = CallOutTag.parse(PhoneLookup.strip(WebTools.strip(answer)));
    String? callSaid;
    if (out.target != null && !_disposed) {
      _partial = s.lookingContacts;
      _notify();
      callSaid = await _resolveCall(out.target!, out.task!);
    }
    // สั่งให้ทำในเครื่อง → เธอทำเอง ถามเจ้าของเฉพาะขั้นที่ย้อนกลับไม่ได้ (PhonePolicy)
    final hand = HandsTag.parse(out.text);
    if (hand.goal != null && _phoneControl) unawaited(_phoneTaskFromChat(hand.goal!));
    if (callSaid != null) return callSaid;
    // เขียนแต่แท็กมา = อย่าให้เหลือฟองเปล่า
    if (hand.text.isEmpty) {
      if (out.target != null) return s.callOutAck;
      if (hand.goal != null && _phoneControl) return s.handsAck;
    }
    return hand.text;
  }

  // ═══ สมองก้อนเดียวกับมายด์บนคอม (BrainX Cloud) ═══════════════
  //
  // เจ้าของ: "มายด์ของ brainx ในคอมที่ขึ้นคราวด์แล้ว ก็เชื่อมต่อแอพนี้ด้วย จะคุย
  // เรื่องเดียวกันจำได้หมด" · "ไม่ต้องกลัวว่าถอนแล้วจะลืมที่คุยกัน จีบกันไว้"
  // · บัญชี xman เดียวกัน = คีย์เดียวกัน · จ่าย BrainX Cloud แล้ว มือถือเชื่อมฟรี
  //
  // 🔴 สายโทรศัพท์ไม่แตะส่วนนี้ (replyOnCall ไม่เรียก) — บังคับด้วยโค้ด ·
  // ยกเว้นทางเดียว: คุยสดค้นได้เฉพาะหมวดที่เจ้าของติ๊กเอง (ดู callLookup)

  BrainXLink? _lazyBrainX;
  BrainXLink get brainx => _lazyBrainX ??= _wireBrainX(BrainXLink());

  @visibleForTesting
  set debugBrainX(BrainXLink l) => _lazyBrainX = _wireBrainX(l);

  /// token หลุด → ขอใหม่ผ่านหลังบ้านด้วยไลเซนส์ปัจจุบัน (ไม่มีคีย์ BrainX ในเครื่องให้ใช้)
  BrainXLink _wireBrainX(BrainXLink l) => l
    ..xmanSource = (() => (storeBase: _storeBaseUrl, license: _licenseKey))
    ..addListener(_notify);

  /// ค้นสมอง BrainX ตอนตอบ
  bool _brainxSearch = true;
  bool get brainxSearch => _brainxSearch;
  void setBrainxSearch(bool v) {
    _brainxSearch = v;
    _save('brainxSearch', v);
    _notify();
  }

  /// ส่งความจำ บทสนทนา และความสัมพันธ์ของมือถือขึ้นสมอง
  bool _brainxShare = true;
  bool get brainxShare => _brainxShare;
  void setBrainxShare(bool v) {
    _brainxShare = v;
    _save('brainxShare', v);
    if (v) _queueAll();
    _notify();
  }

  /// เช็กแล้วว่าต้องกู้คืนไหมหลังเชื่อม · ก่อนหน้านั้นห้ามส่งอะไรขึ้น
  ///
  /// 🔴 ลงแอปใหม่แล้วเชื่อม = ในเครื่องว่างเปล่า · ถ้าส่งขึ้นก่อนกู้ ความจำว่าง ๆ
  /// จะไปเขียนทับของเดิมบนคลาวด์ แล้วของที่ตั้งใจเก็บไว้กู้ก็หายเพราะการกู้เอง
  bool _brainxReady = false;

  Future<List<BrainXHit>> _brainHits(List<({bool fromHer, String text})> history) async {
    final q = recallQuery(history);
    if (q.isEmpty) return const [];
    final hits = await brainx.recall(q);
    // บันทึกของวันนี้บนมือถือ = บทที่อยู่ในหน้าต่างบทสนทนาอยู่แล้ว ไม่ต้องนึกซ้ำ
    final today = MindPaths.phoneDay(_clock());
    return [for (final h in hits) if (h.path != today) h].take(4).toList();
  }

  /// เชื่อมด้วยบัญชี xman ที่ผูกเครื่องไว้ แล้วกู้ของเดิมถ้าในเครื่องยังว่าง
  Future<void> connectBrainX({String? key}) async {
    if (key != null && key.trim().isNotEmpty) {
      await brainx.connectWithKey(key);
    } else {
      await brainx.connectViaXman(storeBase: _storeBaseUrl, license: _licenseKey);
    }
    if (brainx.connected) await _afterBrainXConnect();
  }

  Future<void> disconnectBrainX() async {
    _brainxReady = false;
    await brainx.disconnect();
  }

  /// ผลกู้คืนล่าสุด (โชว์ในหน้าตั้งค่า) · null = ยังไม่เคยกู้รอบนี้
  ({int facts, int lines, bool soul})? _restored;
  ({int facts, int lines, bool soul})? get brainxRestored => _restored;

  bool _brainxRestoring = false;
  bool get brainxRestoring => _brainxRestoring;

  Future<void> _afterBrainXConnect() async {
    unawaited(brainx.refreshOwnerProfile(force: true));
    final fresh = memory.count == 0 && await storedMessageCount() <= 4;
    if (fresh) await restoreFromBrainX();
    _brainxReady = true;
    _queueAll();
  }

  /// ดึงความจำ บทสนทนา และความสัมพันธ์ของมือถือกลับจากสมอง
  ///
  /// บทสนทนาเติมเฉพาะตอนในเครื่องยังแทบว่าง (ลงแอปใหม่) · มีของอยู่แล้วจะไม่ยัดซ้ำ
  /// ส่วนความจำกันซ้ำเองอยู่แล้ว
  Future<({int facts, int lines, bool soul})?> restoreFromBrainX() async {
    if (_brainxRestoring || !brainx.connected) return null;
    _brainxRestoring = true;
    _notify();
    try {
      final b = await brainx.fetchBackup();
      if (b == null) return null;
      var facts = 0;
      for (final f in b.facts) {
        if (await memory.remember(f.text, kind: f.kind)) {
          facts++;
          if (f.pinned) {
            final id = memory.facts.lastWhere((x) => x.text == f.text.trim()).id;
            await memory.setPinned(id, true);
          }
        }
      }
      // บทเรียนของสาย · รวมเงียบ ๆ ไม่นับในผลกู้คืน (ซ้ำไม่เพิ่ม)
      if (_lessons.merge(CallLessons.parseMarkdown(b.lessons)) > 0) _lessonsChanged();
      var soul = false;
      if (b.soul != null && _soul != null) {
        await _soul!.restore(b.soul!);
        soul = true;
      }
      var lines = 0;
      final db = _store?.db;
      if (db != null && b.lines.isNotEmpty && await storedMessageCount() <= 4) {
        for (final l in b.lines) {
          await db.addMessage(fromHer: l.fromHer, text: l.text, at: l.at);
          lines++;
        }
        _context.clear();
        _messages.clear();
        await _loadContextFromDb();
        _chatRecall.clear();
        await _chatRecall.load(db, force: true);
      }
      _restored = (facts: facts, lines: lines, soul: soul);
      debugPrint('brainx: กู้คืน ความจำ $facts · บทสนทนา $lines บรรทัด · ความสัมพันธ์ $soul');
      return _restored;
    } finally {
      _brainxRestoring = false;
      _notify();
    }
  }

  bool get _canShare => _brainxShare && _brainxReady && brainx.connected;

  void _queueMemory() {
    if (!_canShare || memory.count == 0) return;
    brainx.queue(MindPaths.phoneMemory, BrainXLink.renderMemory(memory.facts));
  }

  void _queueLessons() {
    if (!_canShare || _lessons.isEmpty) return;
    brainx.queue(MindPaths.phoneCallLessons, _lessons.renderMarkdown());
  }

  void _queueSoul() {
    final soul = _soul;
    if (!_canShare || soul == null) return;
    brainx.queue(MindPaths.phoneSoul, BrainXLink.renderSoul(soul.snapshot()));
  }

  void _queueDay(DateTime at) {
    if (!_canShare) return;
    final lines = _chatRecall.linesOn(at);
    if (lines.isEmpty) return;
    brainx.queue(
      MindPaths.phoneDay(at),
      BrainXLink.renderDay(at, [for (final l in lines) (at: l.at, fromHer: l.fromHer, text: l.text)],
          her: _soul?.name ?? s.speakerHer),
    );
  }

  void _queueAll() {
    _queueMemory();
    _queueLessons();
    _queueSoul();
    _queueDay(_clock());
  }

  // ── ชวนเก็บความทรงจำบนคลาวด์ (เนียน ๆ) ─────────────────
  //
  // เจ้าของแอปสั่ง: ยังไม่ขึ้นคลาวด์ = ให้เธอเปรย ๆ และจีบให้สมัคร เพราะกลัวหายไป
  // · จังหวะคุมที่นี่ ไม่ใช่ให้โมเดลตัดสินเองทุกตา: เปรยได้ไม่เกินสัปดาห์ละครั้ง
  // (หลังเปรยไปหกครั้งแล้วเหลือเดือนละครั้ง) · ต้องสนิทกันแล้วและมีความจำที่น่า
  // เสียดายจริง · ไม่ใช่ตอนงอนกันอยู่ · ไม่ใช้เลยถ้าเชื่อมอยู่แล้ว

  static const _kNudgeAt = 'cloudNudgeAt';
  static const _kNudgeOffer = 'cloudNudgeOfferAt';
  static const _kNudgeCount = 'cloudNudgeCount';

  bool _nudgeDue() {
    final soul = _soul;
    if (soul == null || brainx.connected) return false;
    if (soul.bond.index < Bond.familiar.index || soul.sulk >= .3) return false;
    if (memory.count < 8) return false;
    final now = _clock();
    DateTime? at(String k) {
      final v = _kv?.getInt(k);
      return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
    }

    final count = _kv?.getInt(_kNudgeCount) ?? 0;
    final last = at(_kNudgeAt);
    final gap = count >= 6 ? const Duration(days: 30) : const Duration(days: 7);
    if (last != null && now.difference(last) < gap) return false;
    // เสนอไปแล้วแต่จังหวะไม่เหมาะ (เธอข้ามไป) → พักหกชั่วโมงก่อนเสนอใหม่
    final offered = at(_kNudgeOffer);
    if (offered != null && now.difference(offered) < const Duration(hours: 6)) return false;
    _kv?.setInt(_kNudgeOffer, now.millisecondsSinceEpoch);
    return true;
  }

  /// เธอเปรยจริงไหม (เอ่ยชื่อ BrainX ตามที่สั่ง) · เปรยแล้วค่อยนับรอบ
  void _noteNudge(String answer) {
    if (!answer.toLowerCase().contains('brainx')) return;
    _kv?.setInt(_kNudgeAt, _clock().millisecondsSinceEpoch);
    _kv?.setInt(_kNudgeCount, (_kv?.getInt(_kNudgeCount) ?? 0) + 1);
  }

  /// ขอค้นได้กี่รอบต่อหนึ่งคำถาม · สองพอสำหรับ "หาที่ก่อน แล้วค่อยดูอากาศ"
  /// · มากกว่านั้นคือรอนานและจ่ายแพงขึ้นโดยแทบไม่ได้อะไรเพิ่ม
  static const maxLookups = 2;

  /// ให้เธอหาข้อมูลจากอินเทอร์เน็ตได้ไหม (ดู WebTools) · ค่าตั้งต้นเปิด ตามที่เจ้าของสั่ง
  bool _webSearch = true;
  bool get webSearch => _webSearch;

  void setWebSearch(bool v) {
    if (_webSearch == v) return;
    _webSearch = v;
    _save('webSearch', v);
    _notify();
  }

  WebTools? _lazyWebTools;
  WebTools get webTools => _lazyWebTools ??= WebTools();

  @visibleForTesting
  set debugWebTools(WebTools t) => _lazyWebTools = t;

  /// ค้นเว็บทั่วไป (ข่าว ราคา ผลบอล) ได้ไหมกับสมองตอนนี้ · null = ไม่ได้
  ///
  /// ได้เฉพาะ **OpenAI ด้วยคีย์ของเจ้าของ** (เครื่องมือ web_search ของ OpenAI) ·
  /// คำค้นไปที่เดียวกับที่ข้อความไปอยู่แล้ว ไม่ได้เปิดทางใหม่ให้ข้อมูลออก ·
  /// สมองในเครื่อง/ในบ้านเลือกเพราะไม่อยากให้อะไรออกไปที่ OpenAI จึงไม่ยืมคีย์มาค้น
  WebSearcher? _webSearcher() {
    if (_brain != BrainProvider.openai || !hasOwnKey) return null;
    return (query) async {
      // web_search ใช้ได้บางรุ่น · รุ่นที่เลือกไว้ไม่รองรับ (400) → ลองรุ่นที่รองรับ
      // แน่ ๆ แล้วจำรุ่นที่ผ่านไว้ ไม่ต้องล้มก่อนทุกครั้ง
      final models = {?_searchModel, _brainModel, ...webSearchModels};
      OpenAiFailure? last;
      for (final m in models) {
        try {
          final r = await _openai.webSearch(
            query,
            model: m,
            country: _lang == AppLang.th ? 'TH' : null,
            timezone: _lang == AppLang.th ? 'Asia/Bangkok' : null,
          );
          _searchModel = m;
          return r;
        } on OpenAiFailure catch (e) {
          last = e;
          if (e.status != 400 && e.status != 404) rethrow;
        }
      }
      throw last ?? OpenAiFailure(s.errNoReply);
    };
  }

  String? _searchModel;

  /// รุ่นที่ OpenAI ระบุว่าใช้ web_search ได้ (ตรวจ 2026-10-06) · ถูกก่อน แพงทีหลัง
  static const webSearchModels = ['gpt-4.1-mini', 'gpt-6-astra'];

  @visibleForTesting
  WebSearcher? get debugWebSearcher => _webSearcher();

  // ═══ นึกออก — ความจำและบทสนทนาเก่าตามเรื่องที่คุย ═══════════
  //
  // 🔴 ของเดิมยัด "ปักหมุด + ใหม่สุด 60 ข้อ" เข้าทุกครั้ง · จำเกิน 60 ข้อแล้ว
  // เรื่องเก่าหลุดถาวร และบทสนทนาที่เก่ากว่า 16 บรรทัดค้นไม่ได้เลย
  //
  // ตอนนี้: system prompt ถือแค่แกน (ปักหมุด + ใหม่สุด) · ที่เหลือ "นึกเอา"
  // ตามข้อความล่าสุด แล้วแนบไว้หน้าข้อความนั้นเป็นบันทึกช่วยจำ
  //
  // 🔴 **ไม่ใส่ใน system prompt** โดยตั้งใจ · สมองในเครื่องใช้ session เดิมต่อ
  // เมื่อ system prompt ไม่เปลี่ยน (ดู LocalBrain.sessionKeyOf) · ถ้าสิ่งที่นึก
  // ออกอยู่ในนั้น system prompt จะเปลี่ยนทุกตา = อ่านบทสนทนาใหม่ทั้งหมดทุกตา
  // ซึ่งคือส่วนที่ช้าที่สุดบนมือถือ

  /// ความจำที่อยู่ใน system prompt ทุกครั้ง (ปักหมุดก่อน แล้วใหม่สุด)
  static const coreMemories = 24;

  final ChatRecall _chatRecall = ChatRecall();

  /// ข้อความที่ยาวกว่านี้บอกเรื่องในตัวเอง · สั้นกว่า ("แล้วอันนั้นล่ะ") ต้องอาศัย
  /// ข้อความก่อนหน้าช่วยบอกว่าคุยเรื่องอะไรอยู่
  static const _shortAsk = 15;

  /// บันทึกช่วยจำสำหรับข้อความล่าสุดของเจ้าของ · ว่าง = ไม่มีอะไรเกี่ยวพอ
  @visibleForTesting
  String recallFor(List<({bool fromHer, String text})> history,
      {List<BrainXHit> brain = const []}) {
    final query = recallQuery(history);
    if (query.isEmpty) return '';

    final core = {for (final f in memory.forPrompt(limit: coreMemories)) f.id};
    final facts = memory.recall(query, skip: core, limit: 6);
    final past = _chatRecall.search(query, limit: 3, skipNewest: _contextLimit);
    if (facts.isEmpty && past.isEmpty && brain.isEmpty) return '';

    String clip(String? t) {
      final v = (t ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
      return v.length <= 140 ? v : '${v.substring(0, 139)}…';
    }

    final her = _soul?.name ?? s.speakerHer;
    final b = StringBuffer()..writeln(s.recallOpen);
    if (facts.isNotEmpty) {
      b.writeln(s.recallFacts);
      for (final f in facts) {
        b.writeln('- ${f.text}');
      }
    }
    if (past.isNotEmpty) {
      b.writeln(s.recallPast);
      for (final p in past) {
        final parts = [
          if (p.ask != null) '${s.speakerMe}: ${clip(p.ask)}',
          if (p.answer != null) '$her: ${clip(p.answer)}',
        ];
        b.writeln('- ${s.dayLabel(p.at)}: ${parts.join(' → ')}');
      }
    }
    if (brain.isNotEmpty) {
      b.writeln(s.recallBrainX);
      for (final h in brain) {
        b.writeln('- ${h.title}: ${clip(h.text)}');
      }
    }
    b.write(s.recallClose);
    return b.toString();
  }

  /// คำค้นของตานี้ · ข้อความล่าสุดของเจ้าของ (+ข้อความก่อนหน้า ถ้าล่าสุดสั้นเกินบอกเรื่อง)
  @visibleForTesting
  static String recallQuery(List<({bool fromHer, String text})> history) {
    final mine = [for (final t in history) if (!t.fromHer) t.text.trim()];
    if (mine.isEmpty || history.last.fromHer) return '';
    var query = mine.last;
    if (query.length < _shortAsk && mine.length >= 2) {
      query = '$query\n${mine[mine.length - 2]}';
    }
    return query;
  }

  /// แนบบันทึกช่วยจำไว้หน้าข้อความล่าสุด (สมองที่ไม่ถือ session · ทางเน็ต)
  static List<({bool fromHer, String text})> withRecall(
    List<({bool fromHer, String text})> history,
    String recall,
  ) {
    if (recall.isEmpty || history.isEmpty || history.last.fromHer) return history;
    return [
      ...history.sublist(0, history.length - 1),
      (fromHer: false, text: '$recall\n\n${history.last.text}'),
    ];
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
    ReplyCap cap = ReplyCap.chat,
    String recall = '',
  }) async {
    if (_brain == BrainProvider.onDevice) {
      debugPrint('สมอง: ในเครื่อง ${localBrain.variant.label}');
      return localBrain.reply(
          system: system,
          history: history,
          onPartial: onPartial,
          cap: cap,
          recall: recall);
    }

    final (:client, :model, :ours) = _networkBrain();
    try {
      final answer = await client.reply(
        system: system,
        history: withRecall(history, recall),
        model: model,
      );
      // หลอดเครดิตขยับตามจริงทุกข้อความ · หลังบ้านแนบยอดใหม่มากับคำตอบ
      final billing = client.lastBilling;
      final account = _proxyAccount;
      if (_brain == BrainProvider.mindProxy && billing != null && account != null) {
        _proxyAccount = account.withBilling(billing);
        _notify();
      }
      return answer;
    } on OpenAiFailure catch (e) {
      // เครดิตหมด/ถึงเพดาน/ยังไม่ผูกบัญชี = ตัวเลขในหน้าตั้งค่าเก่าแล้ว ถามใหม่
      if (_brain == BrainProvider.mindProxy && e.code != null) {
        unawaited(refreshProxyAccount());
      }
      rethrow;
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
          // 🔴 รุ่นของบริการเรา ไม่ใช่รุ่น OpenAI ที่ตั้งไว้ใช้กับคีย์ตัวเอง · ว่าง =
          // ให้หลังบ้านเลือกรุ่นแรกที่เปิดไว้ · รุ่นที่ปิดไปแล้วหลังบ้านใช้รุ่นแรกแทน
          model: _proxyModel.isNotEmpty
              ? _proxyModel
              : (_proxyAccount?.defaultModel ?? ''),
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
      //
      // 🔴 ข้อที่**เกี่ยวกับบทสนทนานี้**ก่อน แล้วค่อยใหม่สุด · ของเดิมให้แค่ใหม่สุด
      // 40 ข้อ เรื่องเก่าที่กำลังถูกพูดถึงอีกครั้งจึงไม่อยู่ในรายการ แล้วถูกจำซ้ำ
      // (และโมเดลเขียน replace| ทับเรื่องเดิมไม่ได้ถ้ามองไม่เห็นเรื่องเดิม)
      final related = memory.recall(block, limit: 20);
      final relatedIds = {for (final f in related) f.id};
      final known = [
        for (final f in related) '- ${f.text}',
        for (final f in memory.forPrompt(limit: 30))
          if (!relatedIds.contains(f.id)) '- ${f.text}',
      ].take(40).join('\n');
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
        cap: ReplyCap.background,
      );
      if (_disposed) return;

      var kept = 0;
      for (final f in parseDistilled(raw)) {
        // เจ้าของสั่งเรื่องการคุยโทรศัพท์ = บทเรียนของสาย ไม่ใช่ความจำเรื่องตัวเจ้าของ
        if (f.callRule) {
          if (addOwnerCallRule(f.text)) {
            kept++;
            unawaited(_journal?.record(JournalKind.learned, f.text) ?? Future<bool>.value(false));
          }
          continue;
        }
        final ok = f.replaces == null
            ? await memory.remember(f.text, kind: f.kind)
            : await memory.replace(f.replaces!, f.text, kind: f.kind);
        if (ok) {
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
    // งานในเครื่อง/การสอนที่ค้าง · ไม่หยุด = ลูปถามสมองต่อ และ Android ยังจับจออยู่จนหมดเวลาเอง
    stopPhoneTask();
    if (_teaching != null) {
      _teaching = null;
      unawaited(hands.recordStop());
    }
    _bubbleTimer?.cancel();
    _chatTimer?.cancel();
    _distilTimer?.cancel();
    _openai.close();
    _speech.dispose();
    if (hasLocalBrain) _lazyLocal!.dispose();
    _lazyWebTools?.close();
    _lazyKnowledge?.dispose();
    memory.removeListener(_queueMemory);
    _soul?.removeListener(_queueSoul);
    final link = _lazyBrainX;
    if (link != null) {
      link.removeListener(_notify);
      // ของที่ยังไม่ได้ส่งขึ้นต้องไปก่อนปิด · ไม่รอ (dispose รอไม่ได้) แต่ยิงออกไปแล้ว
      unawaited(link.flush().whenComplete(link.dispose));
    }
    super.dispose();
  }
}
