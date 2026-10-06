import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ai/mind_audio.dart';
import 'avatar/avatar_view.dart';
import 'calendar/device_calendar.dart';
import 'phone/call_session.dart';
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
      body: IndexedStack(
        index: onCall || studio ? 0 : _tab,
        children: [
          HomeScreen(avatar: _avatar, active: onCall || studio || _tab == 0),
          const MailScreen(),
          const CalendarScreen(),
          const TimelineScreen(),
          SettingsScreen(section: _settingsSection),
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
