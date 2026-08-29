import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../i18n/strings.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';
import '../widgets/screen_header.dart';

/// ไทม์ไลน์ — artboard 2f
/// วันนี้เธอทำอะไรให้บ้าง และย้อนกลับได้ทุกอย่าง
class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key});

  /// เหตุการณ์ตัวอย่าง — เก็บเป็นเมธอดไม่ใช่ const เพราะข้อความเปลี่ยนตามภาษา
  List<_Entry> _entriesFor(S t) => [
        _Entry('08:12', t.tl1Title, t.tl1Detail, const Color(0xFF00C2A8),
            t.tl1Action, const Color(0xFF00A894)),
        _Entry('09:05', t.tl2Title, t.tl2Detail, const Color(0xFF7C6CFF),
            t.tl2Action, const Color(0xFF5A4DE0)),
        _Entry('09:40', t.tl3Title, t.tl3Detail, const Color(0xFF3EC7FF),
            t.tl3Action, MindColors.ink50),
        _Entry('10:20', t.tl4Title, t.tl4Detail, const Color(0xFF00C2A8),
            t.tl4Action, const Color(0xFF00A894)),
        _Entry('11:15', t.tl5Title, t.tl5Detail, const Color(0xFFFFAB3D),
            t.tl5Action, const Color(0xFFB46A00)),
        _Entry('12:00', t.tl6Title, t.tl6Detail, const Color(0xFFFF6FAE), '',
            Colors.transparent),
      ];

  List<(String, int)> _statsFor(S t) => [
        (t.tlCalls, 3),
        (t.tlMails, 5),
        (t.tlMeetings, 2),
        (t.tlWaiting, 4),
      ];

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final entries = _entriesFor(t);
    return LiquidBackground(
      gradient: MindGradients.timeline,
      orbs: Orb.timeline,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MindScreenHeader(overline: t.tabTimeline, title: t.tlTitle),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MindSpace.lg),
              child: Row(
                spacing: 8,
                children: [
                  for (final st in _statsFor(t))
                    Expanded(child: _stat(st.$1, st.$2)),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) =>
                    _row(entries[i], last: i == entries.length - 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ตัวเลขสรุป — ตัวเลขต้อง**เด่นกว่าป้าย**ชัดเจน ไม่ใช่ใหญ่กว่านิดเดียว
  /// ของเดิม 17px กับ 10.5px ห่างกันไม่พอ ตาจึงอ่านทั้งกล่องเป็นก้อนเดียว
  /// และเลขใช้ mono เพราะสี่ช่องเรียงกันต้องกว้างเท่ากันถึงจะดูเป็นตาราง
  Widget _stat(String label, int count) {
    return GlassPanel(
      radius: MindRadius.avatarThumb,
      fill: MindColors.glass62,
      padding: const EdgeInsets.symmetric(
          vertical: MindSpace.md, horizontal: MindSpace.xs),
      shadows: MindShadows.soft(),
      child: Column(
        children: [
          Text('$count',
              style: mindMono(
                  size: 24,
                  weight: FontWeight.w700,
                  color: MindColors.ink,
                  letterSpacing: 0)),
          const SizedBox(height: MindSpace.xs),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: MindType.overline.copyWith(fontSize: 9.5, letterSpacing: .6)),
        ],
      ),
    );
  }

  Widget _row(_Entry e, {required bool last}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 11,
        children: [
          // เส้นเวลา — จุดเรืองสีตามชนิดงาน ต่อกันด้วยเส้นบาง ๆ
          Column(
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 15),
                decoration: BoxDecoration(
                  color: e.dot,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: e.dot.withValues(alpha: .6), blurRadius: 10)],
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 1, color: MindColors.ink10),
                ),
            ],
          ),
          Expanded(
            child: GlassPanel(
              radius: 20,
              fill: MindColors.glass62,
              filter: MindGlass.light,
              shadows: MindShadows.soft(),
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Row(
                    spacing: 8,
                    children: [
                      Text(e.time, style: mindMono(size: 10.5, color: MindColors.ink50)),
                      Expanded(
                        child: Text(e.title,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  Text(e.detail,
                      style: const TextStyle(
                          fontSize: 11.5, height: 1.6, color: MindColors.ink60)),
                  if (e.action.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(e.action,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: e.actionColor)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

@immutable
class _Entry {
  const _Entry(this.time, this.title, this.detail, this.dot, this.action, this.actionColor);

  final String time, title, detail, action;
  final Color dot, actionColor;
}
