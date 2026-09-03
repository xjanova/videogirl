import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ai/mind_audio.dart';
import 'avatar/avatar_view.dart';
import 'phone/call_session.dart';
import 'screens/calendar_screen.dart';
import 'screens/home_screen.dart';
import 'screens/mail_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/timeline_screen.dart';
import 'state/mind_state.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_speakerWired) return;
    _speakerWired = true;

    // ต่อทางออกของเสียงเข้ากับปากของเธอ
    // state สังเคราะห์ไบต์มาให้ แล้ว WebView เป็นคนเล่นและอ่านคลื่นไปขยับปาก
    //
    // 🔴 **สองทาง ไม่ใช่ทางเดียว** · เวที 3D รับเสียงไม่ได้เมื่อยังไม่ได้โหลด
    // avatar pack, เวทีโหลดพัง, หรือทักก่อนคลิปท่าทางโหลดเสร็จ — ทั้งสาม
    // กรณีของเดิมจบด้วยความเงียบสนิทโดยไม่มีใครรู้ · ปากไม่ขยับดีกว่าไม่มีเสียง
    final state = context.read<MindState>();
    state.speaker = (u) async {
      if (await _avatar.speakBytes(u.bytes, mime: u.mime)) return;
      if (await MindAudio.play(u.bytes, mime: u.mime)) return;
      // ทั้งสองทางไม่ได้ = บอกตรง ๆ ไม่ใช่ปล่อยให้เดาว่าทำไมเธอเงียบ
      state.reportError(state.s.errVoiceNoOutput);
    };
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

    return Scaffold(
      // ให้แผงแชทเลื่อนขึ้นเองตอนคีย์บอร์ดเด้ง ไม่งั้นช่องพิมพ์จะโดนบัง
      resizeToAvoidBottomInset: true,

      // พื้นหลังไล่สีและก้อนแสงของแต่ละหน้าไหลลงไปใต้แถบ กระจกจึงมีของจริงให้เบลอ
      // แถบลอยแบบเดิมเบลอพื้น Scaffold ที่โปร่งใสอยู่แล้ว — เบลอความว่างเปล่า
      // Scaffold บวกความสูงแถบเข้าไปใน MediaQuery.padding ของ body ให้เอง
      // SafeArea ในแต่ละหน้าจอจึงยังกันเนื้อหาไม่ให้มุดใต้แถบเหมือนเดิม
      extendBody: true,
      body: IndexedStack(
        index: onCall ? 0 : _tab,
        children: [
          HomeScreen(avatar: _avatar),
          const MailScreen(),
          const CalendarScreen(),
          const TimelineScreen(),
          const SettingsScreen(),
        ],
      ),
      // ฟังเฉพาะตัวอวาตาร์ เพื่อไม่ให้ ready/error ลากทั้ง Scaffold มา rebuild
      bottomNavigationBar: onCall
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
                onSelect: (i) => setState(() => _tab = i),
              ),
            ),
    );
  }
}
