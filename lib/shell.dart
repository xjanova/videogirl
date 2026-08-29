import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'avatar/avatar_view.dart';
import 'screens/calendar_screen.dart';
import 'screens/home_screen.dart';
import 'screens/mail_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/timeline_screen.dart';
import 'state/minde_state.dart';
import 'theme/tokens.dart';
import 'widgets/glass.dart';

/// แถบนำทาง — หมายเหตุ: artboard ไม่มีแถบนี้ (แต่ละหน้าจอเป็น artboard แยกกัน)
/// เพิ่มเข้ามาเพราะแอปจริงต้องเดินไปมาได้ ถ้าอยากได้แบบอื่นให้กลับไปวางใน
/// Claude Design แล้วค่อยถอดกลับมา อย่าออกแบบเพิ่มเองที่นี่
class MindeShell extends StatefulWidget {
  const MindeShell({super.key});

  @override
  State<MindeShell> createState() => _MindeShellState();
}

class _MindeShellState extends State<MindeShell> {
  /// อวาตาร์อยู่ระดับ shell ไม่ใช่ระดับหน้าจอ — ถ้าสร้างใหม่ทุกครั้งที่สลับแท็บ
  /// VRM 33MB จะโหลดใหม่ทุกรอบ และเธอจะรีเซ็ตท่ากลับไปยืนตรงทุกครั้ง
  final _avatar = MindeAvatarController();

  int _tab = 0;
  bool _speakerWired = false;

  static const _tabs = <({String label, IconData icon})>[
    (label: 'มินเดะ', icon: Icons.face_retouching_natural_rounded),
    (label: 'เมล', icon: Icons.mail_outline_rounded),
    (label: 'ปฏิทิน', icon: Icons.calendar_today_rounded),
    (label: 'ไทม์ไลน์', icon: Icons.timeline_rounded),
    (label: 'ตั้งค่า', icon: Icons.tune_rounded),
  ];

  @override
  void dispose() {
    _avatar.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_speakerWired) return;
    _speakerWired = true;

    // ต่อทางออกของเสียงเข้ากับปากของเธอ
    // state สังเคราะห์ไบต์มาให้ แล้ว WebView เป็นคนเล่นและอ่านคลื่นไปขยับปาก
    context.read<MindeState>().speaker =
        (u) => _avatar.speakBytes(u.bytes, mime: u.mime);
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.select<MindeState, MindeMode>((s) => s.mode);

    return Scaffold(
      // ให้แผงแชทเลื่อนขึ้นเองตอนคีย์บอร์ดเด้ง ไม่งั้นช่องพิมพ์จะโดนบัง
      resizeToAvoidBottomInset: true,
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: GlassPanel(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          radius: MindeRadius.card,
          filter: MindeGlass.heavy,
          shadows: MindeShadows.dock(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < _tabs.length; i++) _navItem(i, mode),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, MindeMode mode) {
    final selected = index == _tab;
    final tab = _tabs[index];

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (selected) return;
            setState(() => _tab = index);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              gradient: selected ? mode.gradient : null,
              borderRadius: BorderRadius.circular(MindeRadius.avatarThumb),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 3,
              children: [
                Icon(
                  tab.icon,
                  size: 17,
                  color: selected ? Colors.white : MindeColors.ink50,
                ),
                Text(
                  tab.label,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: selected ? Colors.white : MindeColors.ink50,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
