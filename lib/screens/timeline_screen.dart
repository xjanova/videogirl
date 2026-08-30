import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../calendar/device_calendar.dart';
import '../i18n/strings.dart';
import '../journal/mind_journal.dart';
import '../state/mind_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';
import '../widgets/screen_header.dart';

/// สมุดบันทึก — เรื่องที่เกิดขึ้นจริง เรียงจากใหม่ไปเก่า
///
/// **ของเดิมเป็นภาพนิ่ง** หกเหตุการณ์ตั้งแต่ 08:12 ถึง 12:00 กับตัวเลขสรุป
/// "รับสาย 3 · เมล 5 · ประชุม 2" ที่เป็นค่าคงที่ในโค้ด — เวลาเดิมทุกวัน
/// จำนวนเดิมทุกวัน ไม่ว่าใครใช้หรือใช้เมื่อไหร่
///
/// ตอนนี้อ่านจาก [MindJournal] ที่เธอเขียนจริง · ตัวเลขบนสุดนับของวันนี้จริง
/// และช่อง "นัด" มาจากปฏิทินของเครื่อง ไม่ใช่จากสมุด
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final mode = context.select<MindState, MindMode>((s) => s.mode);
    final journal = context.watch<MindJournal>();
    final cal = context.watch<DeviceCalendar>();
    final today = journal.today;

    return LiquidBackground(
      gradient: MindGradients.timeline,
      orbs: Orb.timeline,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MindScreenHeader(
              overline: t.tabTimeline,
              title: t.tlTitle,
              subtitle: today.isEmpty
                  ? t.tlNothingToday
                  : t.tlDidToday(today.length),
              trailing: journal.isEmpty
                  ? null
                  : MindIconButton(
                      icon: Icons.delete_sweep_rounded,
                      tooltip: t.tlClear,
                      mode: mode,
                      onTap: () => _confirmClear(journal, t),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MindSpace.lg),
              child: Row(
                spacing: 8,
                children: [
                  Expanded(
                      child: _stat(
                          t.tlStatTalk,
                          journal.countToday(
                              {JournalKind.asked, JournalKind.replied}))),
                  Expanded(
                      child: _stat(t.tlStatLearn,
                          journal.countToday({JournalKind.learned}))),
                  // ช่องนี้มาจากปฏิทิน ไม่ใช่สมุด — นัดเป็นเรื่องที่ "มีอยู่"
                  // ไม่ใช่เรื่องที่ "เกิดขึ้น" จึงไม่ได้ถูกบันทึกลงสมุด
                  Expanded(child: _stat(t.tlStatMeet, cal.today.length)),
                  Expanded(
                      child: _stat(
                          t.tlStatOther,
                          journal.countToday({
                            JournalKind.pack,
                            JournalKind.update,
                            JournalKind.system,
                          }))),
                ],
              ),
            ),
            Expanded(
              child: journal.isEmpty
                  ? _empty(mode, t)
                  : _list(journal, mode, t),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(MindJournal journal, S t) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.tlClear),
        content: Text(t.tlClearAsk),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.tlClear),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await journal.clear();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t.tlCleared)));
  }

  /// สมุดว่าง — บอกว่าจะมีอะไร ไม่ใช่ปล่อยจอโล่ง
  Widget _empty(MindMode mode, S t) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MindSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined, size: 42, color: MindColors.ink22),
            const SizedBox(height: MindSpace.md),
            Text(t.tlEmpty, style: MindType.title, textAlign: TextAlign.center),
            const SizedBox(height: MindSpace.sm),
            Text(t.tlEmptyWhy,
                style: MindType.caption, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _list(MindJournal journal, MindMode mode, S t) {
    // แบนเป็นรายการเดียวที่มีทั้งหัวข้อวันและบรรทัดบันทึก เพื่อให้เลื่อนได้ลื่น
    // โดยไม่ต้องซ้อน ListView ในกันและกัน
    final rows = <Object>[];
    final days = journal.byDay.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    for (final day in days) {
      rows.add(day.key);
      rows.addAll(day.value);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          MindSpace.lg, MindSpace.md, MindSpace.lg, MindSpace.xxl),
      itemCount: rows.length,
      separatorBuilder: (_, i) => SizedBox(height: rows[i + 1] is DateTime ? 14 : 10),
      itemBuilder: (_, i) {
        final row = rows[i];
        if (row is DateTime) {
          return Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: MindSectionLabel(_dayHeading(row, t)),
          );
        }
        final entry = row as JournalEntry;
        // เส้นต่อจุดหยุดที่บรรทัดสุดท้ายของแต่ละวัน ไม่งั้นเส้นจะพุ่งทะลุ
        // หัวข้อวันถัดไปเหมือนเป็นวันเดียวกัน
        final last = i + 1 >= rows.length || rows[i + 1] is DateTime;
        return _row(entry, mode, t, last: last);
      },
    );
  }

  String _dayHeading(DateTime day, S t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return t.calToday;
    if (diff == 1) return t.calYesterday;
    return t.dayLabel(day);
  }

  Widget _row(JournalEntry e, MindMode mode, S t, {required bool last}) {
    final dot = _dotColour(e.kind, mode);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 11,
        children: [
          Column(
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 15),
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: dot.withValues(alpha: .6), blurRadius: 10)
                  ],
                ),
              ),
              if (!last)
                Expanded(child: Container(width: 1, color: MindColors.ink10)),
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
                      Text(_clock(e.at),
                          style: mindMono(size: 10.5, color: MindColors.ink50)),
                      Expanded(
                        child: Text(_kindLabel(e.kind, t),
                            style: MindType.overline.copyWith(
                                fontSize: 9.5, color: dot, letterSpacing: .6)),
                      ),
                    ],
                  ),
                  Text(e.title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600, height: 1.4)),
                  if (e.detail.isNotEmpty)
                    Text(e.detail,
                        style: const TextStyle(
                            fontSize: 11.5, height: 1.6, color: MindColors.ink60)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _clock(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}';
  }

  String _kindLabel(JournalKind k, S t) => switch (k) {
        JournalKind.asked => t.tlKindAsked,
        JournalKind.replied => t.tlKindReplied,
        JournalKind.learned => t.tlKindLearned,
        JournalKind.pack => t.tlKindPack,
        JournalKind.update => t.tlKindUpdate,
        JournalKind.system => t.tlKindSystem,
      };

  /// สีจุดแยกชนิด — สีเดียวกับของเดิมเพื่อให้หน้าตายังเป็นชุดเดียวกับทั้งแอป
  Color _dotColour(JournalKind k, MindMode mode) => switch (k) {
        JournalKind.asked => const Color(0xFF3EC7FF),
        JournalKind.replied => mode.accent,
        JournalKind.learned => const Color(0xFF00C2A8),
        JournalKind.pack => const Color(0xFFFF6FAE),
        JournalKind.update => const Color(0xFFFFAB3D),
        JournalKind.system => MindColors.ink45,
      };

  /// ตัวเลขสรุป — ตัวเลขต้อง**เด่นกว่าป้าย**ชัดเจน ไม่ใช่ใหญ่กว่านิดเดียว
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
}
