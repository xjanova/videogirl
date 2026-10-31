import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ai/mind_audio.dart';
import 'avatar/avatar_view.dart';
import 'calendar/device_calendar.dart';
import 'hands/phone_task.dart';
import 'phone/call_session.dart';
import 'phone/outgoing_call.dart';
import 'screens/calendar_screen.dart';
import 'screens/home_screen.dart';
import 'screens/mail_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/timeline_screen.dart';
import 'state/mind_state.dart';
import 'studio/mind_studio.dart';
import 'system/app_life.dart';
import 'i18n/strings.dart';
import 'i18n/strings_ai.dart';
import 'i18n/strings_hands.dart';
import 'theme/tokens.dart';
import 'widgets/mind_nav_bar.dart';

/// แถบนำทาง — หมายเหตุ: artboard ไม่มีแถบนี้ (แต่ละหน้าจอเป็น artboard แยกกัน)
/// เพิ่มเข้ามาเพราะแอปจริงต้องเดินไปมาได้ ถ้าอยากได้แบบอื่นให้กลับไปวางใน
/// Claude Design แล้วค่อยถอดกลับมา อย่าออกแบบเพิ่มเองที่นี่
class MindShell extends StatefulWidget {
  const MindShell({super.key});

  @override
  State<MindShell> createState() => _MindShellState();
}

class _MindShellState extends State<MindShell> {
  /// อวาตาร์อยู่ **เหนือ shell ขึ้นไปอีกชั้น** ไม่ใช่ของ shell เอง
  ///
  /// เดิมสร้างที่นี่ แต่หน้าเปิดแอปต้องรู้ความคืบหน้าการโหลด VRM ด้วย
  /// เพื่อโชว์เปอร์เซ็นต์จริง · ถ้าตัวควบคุมเกิดที่นี่ หน้าเปิดแอปที่อยู่
  /// ชั้นบนกว่าจะมองไม่เห็นมันเลย
  MindAvatarController get _avatar => context.read<MindAvatarController>();

  int _tab = 0;
  bool _speakerWired = false;

  /// เรียงตาม IndexedStack — ห้ามสลับ ไม่งั้นแท็บจะไปเปิดผิดหน้า
  /// ไอคอนคงที่ ส่วนป้ายมาจากตารางแปลตอนวาด
  /// เก็บป้ายไว้ใน const list ไม่ได้ เพราะมันเปลี่ยนตามภาษาที่ผู้ใช้เลือก
  List<MindNavItem> _tabsFor(S s) => [
        MindNavItem(
            index: 0,
            label: s.tabMind,
            icon: Icons.face_retouching_natural_rounded,
            asset: 'assets/brand/nav/mind.png'),
        MindNavItem(
            index: 1,
            label: s.tabMail,
            icon: Icons.mail_outline_rounded,
            asset: 'assets/brand/nav/mail.png'),
        MindNavItem(
            index: 2,
            label: s.tabCalendar,
            icon: Icons.calendar_today_rounded,
            asset: 'assets/brand/nav/calendar.png'),
        MindNavItem(
            index: 3,
            label: s.tabTimeline,
            icon: Icons.timeline_rounded,
            asset: 'assets/brand/nav/timeline.png'),
        MindNavItem(
            index: 4,
            label: s.tabSettings,
            icon: Icons.tune_rounded,
            asset: 'assets/brand/nav/settings.png'),
      ];

  /// ลำดับที่เห็นบนแถบ — มายด์ย้ายไปกลาง อีกสี่อันคงลำดับสัมพัทธ์เดิมไว้ทุกตัว
  /// (เมล ก่อน ปฏิทิน, ไทม์ไลน์ ก่อน ตั้งค่า) คนที่ใช้อยู่แล้วต้องจำใหม่แค่ที่เดียว
  static const _order = <int>[1, 2, 0, 3, 4];

  /// หน้าของเธอ — ไฟล์ภาพนิ่งใน assets/brand/ (pubspec ประกาศทั้งโฟลเดอร์ไว้แล้ว)
  /// ถ้ายังไม่มีไฟล์ ปุ่มจะตกไปใช้ไอคอนแทนเอง ไม่พัง


  // ไม่ dispose อวาตาร์ที่นี่ — ผู้สร้างเป็นคนปิด (MindBootstrap)
  // ปิดจากที่นี่ = ตัวควบคุมตายทั้งที่ provider ยังแจกอยู่

  /// ผลของสตูดิโอ (บันทึกคลิปแล้ว / ไมค์ไม่ติด / จอลอยไม่ได้) ขึ้นเป็นแถบล่าง
  /// ที่เดียว · ต้องฟังจากที่นี่ เพราะคลิปอาจบันทึกเสร็จ**หลัง**ออกจากสตูดิโอแล้ว
  MindStudio? _studio;
  int _studioSeen = 0;

  /// หมวดที่เปิดอยู่ในหน้าตั้งค่า · Back ต้องปิดหมวดก่อน ไม่ใช่พาออกจากแท็บ
  final _settingsSection = ValueNotifier<SettingsSection?>(null);

  /// ตำแหน่งของหน้าตั้งค่าใน IndexedStack
  static const _settingsTab = 4;

  void _onStudio() {
    final st = _studio;
    if (st == null || !mounted || st.noticeSeq == _studioSeen) return;
    _studioSeen = st.noticeSeq;
    final msg = st.notice;
    if (msg == null) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 6),
      ));
  }

  @override
  void dispose() {
    _state?.removeListener(_onPendingCall);
    _state?.removeListener(_onPhoneAsk);
    _studio?.removeListener(_onStudio);
    _settingsSection.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_speakerWired) return;
    _speakerWired = true;

    _studio = context.read<MindStudio>()..addListener(_onStudio);
    _studioSeen = _studio!.noticeSeq;

    // ต่อทางออกของเสียงเข้ากับปากของเธอ
    // state สังเคราะห์ไบต์มาให้ แล้ว WebView เป็นคนเล่นและอ่านคลื่นไปขยับปาก
    //
    // 🔴 **สองทาง ไม่ใช่ทางเดียว** · เวที 3D รับเสียงไม่ได้เมื่อยังไม่ได้โหลด
    // avatar pack, เวทีโหลดพัง, หรือทักก่อนคลิปท่าทางโหลดเสร็จ — ทั้งสาม
    // กรณีของเดิมจบด้วยความเงียบสนิทโดยไม่มีใครรู้ · ปากไม่ขยับดีกว่าไม่มีเสียง
    final state = context.read<MindState>();
    // ทั้งสองทางไม่ได้ = คืน false แล้ว state บอกผู้ใช้เอง · state รู้ว่าเสียงนั้น
    // ถูกสั่งเงียบไปเองหรือเปล่า ที่นี่ไม่รู้ (ทางสำรองคืน false ตอนถูกตัดกลางคันด้วย)
    state.speaker = (u) async {
      var played = await _avatar.speakBytes(u.bytes, mime: u.mime);
      if (!played) {
        // ทางสำรอง: เครื่องเล่นของ Android · ปากขยับแบบประมาณระหว่างนั้น
        unawaited(_avatar.setBabble(true));
        try {
          played = await MindAudio.play(u.bytes, mime: u.mime);
        } finally {
          unawaited(_avatar.setBabble(false));
        }
      }
      // เล่น "สำเร็จ" แต่เสียงสื่อของเครื่องเป็นศูนย์ = ไม่มีใครได้ยิน · บอกตรง ๆ
      if (played && await MindAudio.mediaMuted() == true && mounted) {
        state.reportError(state.s.errMediaMuted);
      }
      return played;
    };
    state.silencer = () async {
      await _avatar.stop();
      await MindAudio.stop();
    };
    state.addListener(_onPendingCall);
    state.addListener(_onPhoneAsk);
    _state = state;
  }

  /// คำถาม "ให้ทำขั้นนี้ไหม" ที่โชว์กล่องไปแล้ว
  int _shownAsk = 0;

  /// เธอกำลังจะทำขั้นที่ย้อนกลับไม่ได้ในเครื่อง (งานจากแชท) · ถามในแอปด้วย ไม่ใช่แค่แจ้งเตือน ·
  /// งานที่คนในสายสั่ง ถามคนในสายเอง ไม่ขึ้นกล่องที่นี่
  void _onPhoneAsk() {
    final task = _state?.phoneTask;
    final ask = task?.asking;
    if (task == null || ask == null || task.inCall || ask.id == _shownAsk || !mounted) return;
    _shownAsk = ask.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_confirmPhoneStep(ask)));
  }

  Future<void> _confirmPhoneStep(PhoneStepAsk ask) async {
    final state = _state;
    if (state == null || !mounted || state.phoneTask?.asking?.id != ask.id) return;
    final allow = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _PhoneAskSheet(ask: ask),
    );
    // ปิดกล่องเฉย ๆ = ไม่ตอบที่นี่ (ยังตอบจากแจ้งเตือนได้ · ไม่ตอบเลย = ไม่ทำ เมื่อหมดเวลา)
    if (allow != null) state.answerPhoneAsk(ask.id, allow);
  }

  MindState? _state;

  /// คำขอโทรออกที่โชว์กล่องไปแล้ว · กันโชว์ซ้ำทุกครั้งที่ state ขยับ
  int _shownCall = 0;

  /// 🔴 น้องมายโทรออกได้ก็ต่อเมื่อเจ้าของกดยืนยันเท่านั้น · การโทรคือการกระทำต่อคนอื่น
  /// ที่ย้อนกลับไม่ได้ (คนรับเสียเวลา มีค่าโทร) และคำสั่งในแชทอาจถูกตีความผิด
  void _onPendingCall() {
    final p = _state?.pendingCall;
    if (p == null || p.id == _shownCall || !mounted) return;
    _shownCall = p.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_confirmCall(p)));
  }

  Future<void> _confirmCall(PendingCall p) async {
    final state = _state;
    if (state == null || !mounted) return;
    final go = await showModalBottomSheet<({String task, bool askOwner})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CallConfirmSheet(call: p, canAsk: state.realtimeCallsReady),
    );
    // ปิดกล่องเฉย ๆ (ปัดลง/ย้อนกลับ) = ไม่โทร
    if (go != null) {
      await state.confirmPendingCall(task: go.task, askOwner: go.askOwner);
    } else {
      state.cancelPendingCall();
    }
  }

  void _select(int i) {
    setState(() => _tab = i);
    // แท็บปฏิทินอ่านของใหม่ทุกครั้งที่เปิด ถ้าของเดิมเก่าแล้ว · ไม่งั้นนัดที่เพิ่ง
    // เพิ่ง หรือสิทธิ์ที่เพิ่งให้ จะไม่โผล่จนกว่าจะปิดเปิดแอป
    if (i == 2) unawaited(context.read<DeviceCalendar>().refreshIfStale());
  }

  /// ปุ่ม Back ของ Android
  ///
  /// 🔴 ของเดิมไม่มีตัวจับเลย Back จากทุกแท็บ = ปิดแอปทันที · คนที่อยู่หน้า
  /// ตั้งค่าแล้วกด Back เพื่อ "ย้อนกลับ" ถูกพาออกจากแอปไปเฉย ๆ
  /// ลำดับ: แท็บอื่น → กลับหน้าเธอ · แผงแชทเปิด → พับ · นอกนั้นค่อยออก
  void _onBack(MindState state) {
    // สตูดิโอเต็มจอ = Back คือออกจากสตูดิโอ ไม่ใช่ออกจากแอป
    final studio = context.read<MindStudio>();
    if (studio.active) {
      unawaited(studio.exit());
    } else if (_tab == _settingsTab && _settingsSection.value != null) {
      _settingsSection.value = null;
    } else if (_tab != 0) {
      _select(0);
    } else if (state.chatOpen) {
      state.collapseChat();
    } else {
      // 🔴 หน้าแรกแล้วไม่มีอะไรให้ปิด = พักแอปไว้เบื้องหลัง **ไม่ใช่ปิด**
      // ปิดแอปได้ทางเดียวคือปุ่ม "ออกจากแอป" (ดู AppLife)
      unawaited(AppLife.moveToBack());
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.select<MindState, MindMode>((s) => s.mode);
    final speaking = context.select<MindState, bool>((s) => s.speaking);

    // มีสายที่เธอถืออยู่ = ตัดมาแท็บของเธอ แล้วเก็บแถบนำทางไปก่อน
    //
    // 🔴 ไม่แตะ `_tab` โดยตั้งใจ · เขียนทับตอน build คือ setState ระหว่างวาด
    // และแปลว่าพอสายจบ เจ้าของจะถูกทิ้งไว้ที่แท็บของเธอ แทนที่จะกลับไป
    // ที่หน้าที่ค้างอยู่ก่อนสายเข้า
    final onCall = context.select<CallSession, bool>((c) => c.onStage);
    final studio = context.select<MindStudio, bool>((s) => s.active) && !onCall;

    return PopScope(
      // ระหว่างสาย Back ไม่ปิดแอป · สายยังอยู่ที่จอสายของเครื่อง
      // ไม่ปล่อยให้ Flutter ปิดหน้าแอปเองเลย · ทุกกรณีไปที่ _onBack
      // (ย้อนจนสุด = พักไว้เบื้องหลัง) · ดู AppLife ว่าทำไม
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack(context.read<MindState>());
      },
      child: _scaffold(context, mode, speaking, onCall, studio),
    );
  }

  Widget _scaffold(BuildContext context, MindMode mode, bool speaking,
      bool onCall, bool studio) {
    return Scaffold(
      // ให้แผงแชทเลื่อนขึ้นเองตอนคีย์บอร์ดเด้ง ไม่งั้นช่องพิมพ์จะโดนบัง
      resizeToAvoidBottomInset: true,

      // พื้นหลังไล่สีและก้อนแสงของแต่ละหน้าไหลลงไปใต้แถบ กระจกจึงมีของจริงให้เบลอ
      // แถบลอยแบบเดิมเบลอพื้น Scaffold ที่โปร่งใสอยู่แล้ว — เบลอความว่างเปล่า
      // Scaffold บวกความสูงแถบเข้าไปใน MediaQuery.padding ของ body ให้เอง
      // SafeArea ในแต่ละหน้าจอจึงยังกันเนื้อหาไม่ให้มุดใต้แถบเหมือนเดิม
      extendBody: true,
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: onCall || studio ? 0 : _tab,
              children: [
                HomeScreen(avatar: _avatar, active: onCall || studio || _tab == 0),
                const MailScreen(),
                const CalendarScreen(),
                const TimelineScreen(),
                SettingsScreen(section: _settingsSection),
              ],
            ),
          ),
          if (!studio) const _PhoneTaskBanner(),
        ],
      ),
      // ฟังเฉพาะตัวอวาตาร์ เพื่อไม่ให้ ready/error ลากทั้ง Scaffold มา rebuild
      bottomNavigationBar: onCall || studio
          ? null
          : ListenableBuilder(
              listenable: _avatar,
              builder: (context, _) => MindNavBar(
                items: [for (final i in _order) _tabsFor(S.of(context))[i]],
                current: _tab,
                centerIndex: 0,
                mode: mode,
                // ที่เปลี่ยนชุดหรือทรงผม · null = ปุ่มใช้ไอคอนสำรอง
                face: _avatar.faceImage,
                avatarReady: _avatar.ready,
                speaking: speaking,
                onSelect: _select,
              ),
            ),
    );
  }
}

/// กล่องยืนยันก่อนน้องมายโทรออก · เจ้าของอ่านและแก้เรื่องที่จะให้คุยได้ก่อนกดโทร
///
/// คืนเรื่องที่จะคุย (แก้แล้วหรือไม่ก็ได้) เมื่อกด "โทรเลย" · null = ไม่โทร
class _CallConfirmSheet extends StatefulWidget {
  const _CallConfirmSheet({required this.call, required this.canAsk});

  final PendingCall call;

  /// คุยสดได้ = เธอถามเจ้าของกลางสายได้ · บอกในกล่องให้ตรงกับที่จะเกิดจริง
  final bool canAsk;

  @override
  State<_CallConfirmSheet> createState() => _CallConfirmSheetState();
}

class _CallConfirmSheetState extends State<_CallConfirmSheet> {
  late final _task = TextEditingController(text: widget.call.task);

  /// "ถามฉันได้ระหว่างสาย" · ตั้งต้นจากเรื่องที่สั่ง ("ห้ามถามฉัน" = ปิด) เจ้าของเปลี่ยนเองได้
  late bool _askOwner = !OutgoingRules.noAsking(widget.call.task);

  /// กดซ้ำ = pop สองครั้ง ซึ่งจะปิดจอที่อยู่ใต้กล่องไปด้วย
  bool _closed = false;

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  void _close(String? task) {
    if (_closed) return;
    _closed = true;
    Navigator.pop(context, task == null ? null : (task: task, askOwner: widget.canAsk && _askOwner));
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final p = widget.call;
    return SafeArea(
      child: Padding(
        // คีย์บอร์ดขึ้น = ดันกล่องขึ้นตาม ปุ่มโทรไม่ถูกบัง
        padding: EdgeInsets.fromLTRB(20, 18, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Text(t.callOutConfirmTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(t.callOutTo(p.who, p.number), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text(t.callOutTaskLabel, style: const TextStyle(fontSize: 11, color: MindColors.ink55)),
            TextField(
              controller: _task,
              minLines: 2,
              maxLines: 8,
              maxLength: 1200,
              style: const TextStyle(fontSize: 13.5, height: 1.5),
              decoration: InputDecoration(
                isDense: true,
                helperText: t.callOutEditHint,
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
            if (widget.canAsk)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _askOwner,
                onChanged: (v) => setState(() => _askOwner = v),
                title: Text(t.callAskOwnerAllow, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(_askOwner ? t.callAskOwnerAllowOn : t.callAskOwnerAllowOff,
                    style: const TextStyle(fontSize: 10.5, height: 1.45, color: MindColors.ink55)),
              ),
            Text(t.callOutConfirmNote(canAsk: widget.canAsk && _askOwner),
                style: const TextStyle(fontSize: 10.5, height: 1.5, color: MindColors.ink55)),
            const SizedBox(height: 4),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _close(null),
                    child: Text(t.callOutCancel),
                  ),
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: _task,
                    // ลบเรื่องจนว่าง = ไม่มีอะไรให้เธอคุย · ไม่ให้กดโทร
                    builder: (context, _) => FilledButton.icon(
                      onPressed: _task.text.trim().isEmpty ? null : () => _close(_task.text.trim()),
                      icon: const Icon(Icons.call_rounded, size: 18),
                      label: Text(t.callOutGo),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// กล่อง "ให้ทำขั้นนี้ไหม" ก่อนเธอกดส่ง จ่าย ซื้อ หรือลบในเครื่อง · true = ทำ · false = ไม่ทำ
///
/// ปิดตัวเองเมื่อคำถามนี้ถูกตอบจากแจ้งเตือนแล้ว หรืองานจบไปแล้ว · กล่องค้างแล้วกดทีหลัง
/// จะไปตอบคำถามอื่นไม่ได้ (MindState เทียบ id)
class _PhoneAskSheet extends StatefulWidget {
  const _PhoneAskSheet({required this.ask});

  final PhoneStepAsk ask;

  @override
  State<_PhoneAskSheet> createState() => _PhoneAskSheetState();
}

class _PhoneAskSheetState extends State<_PhoneAskSheet> {
  /// กดซ้ำ = pop สองครั้ง ซึ่งจะปิดจอที่อยู่ใต้กล่องไปด้วย
  bool _closed = false;

  void _close(bool? allow) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.pop(context, allow);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final a = widget.ask;
    final current = context.select<MindState, int?>((s) => s.phoneTask?.asking?.id);
    if (current != a.id && !_closed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close(null));
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Text(t.handsAskTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(t.handsAskBody(a.action, a.app), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            if (a.why.trim().isNotEmpty)
              Text(t.handsAskWhy(a.why.trim()), style: const TextStyle(fontSize: 12, height: 1.45)),
            Text(t.handsAskGoal(a.goal), style: const TextStyle(fontSize: 11, height: 1.45, color: MindColors.ink55)),
            const SizedBox(height: 4),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: () => _close(false), child: Text(t.handsDeny)),
                ),
                Expanded(
                  child: FilledButton(onPressed: () => _close(true), child: Text(t.handsAllow)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// แถบบนจอระหว่างเธอทำงานในเครื่อง (งานจากแชท) · บอกว่ากำลังทำอะไร พร้อมปุ่มหยุด
class _PhoneTaskBanner extends StatelessWidget {
  const _PhoneTaskBanner();

  @override
  Widget build(BuildContext context) {
    final task = context.select<MindState, PhoneTaskView?>((s) => s.phoneTask);
    if (task == null) return const SizedBox.shrink();
    final t = S.of(context);
    return Positioned(
      top: 0,
      left: 12,
      right: 12,
      child: SafeArea(
        bottom: false,
        child: Material(
          color: MindColors.ink.withValues(alpha: .86),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            child: Row(
              spacing: 8,
              children: [
                const Icon(Icons.touch_app_rounded, size: 18, color: Colors.white),
                Expanded(
                  child: Text(
                    task.step == 0 ? '${t.handsWorking} · ${task.line}' : t.handsStepLine(task.step, task.maxSteps, task.line),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  onPressed: () => context.read<MindState>().stopPhoneTask(),
                  child: Text(t.handsStop),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
