import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'avatar/avatar_view.dart';
import 'screens/calendar_screen.dart';
import 'screens/home_screen.dart';
import 'screens/mail_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/timeline_screen.dart';
import 'state/mind_state.dart';
import 'i18n/strings.dart';
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
            icon: Icons.face_retouching_natural_rounded),
        MindNavItem(index: 1, label: s.tabMail, icon: Icons.mail_outline_rounded),
        MindNavItem(
            index: 2, label: s.tabCalendar, icon: Icons.calendar_today_rounded),
        MindNavItem(index: 3, label: s.tabTimeline, icon: Icons.timeline_rounded),
        MindNavItem(index: 4, label: s.tabSettings, icon: Icons.tune_rounded),
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
    context.read<MindState>().speaker =
        (u) => _avatar.speakBytes(u.bytes, mime: u.mime);
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.select<MindState, MindMode>((s) => s.mode);
    final speaking = context.select<MindState, bool>((s) => s.speaking);

    return Scaffold(
      // ให้แผงแชทเลื่อนขึ้นเองตอนคีย์บอร์ดเด้ง ไม่งั้นช่องพิมพ์จะโดนบัง
      resizeToAvoidBottomInset: true,

      // พื้นหลังไล่สีและก้อนแสงของแต่ละหน้าไหลลงไปใต้แถบ กระจกจึงมีของจริงให้เบลอ
      // แถบลอยแบบเดิมเบลอพื้น Scaffold ที่โปร่งใสอยู่แล้ว — เบลอความว่างเปล่า
      // Scaffold บวกความสูงแถบเข้าไปใน MediaQuery.padding ของ body ให้เอง
      // SafeArea ในแต่ละหน้าจอจึงยังกันเนื้อหาไม่ให้มุดใต้แถบเหมือนเดิม
      extendBody: true,
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(avatar: _avatar),
          const MailScreen(),
          const CalendarScreen(),
          const TimelineScreen(),
          const SettingsScreen(),
        ],
      ),
      // ฟังเฉพาะตัวอวาตาร์ เพื่อไม่ให้ ready/error ลากทั้ง Scaffold มา rebuild
      bottomNavigationBar: ListenableBuilder(
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
