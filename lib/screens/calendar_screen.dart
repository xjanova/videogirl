import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/mind_state.dart';
import '../theme/app_theme.dart';
import '../i18n/strings.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';
import '../widgets/screen_header.dart';

/// นัดประชุม — artboard 2e
/// เธอหาช่องว่างร่วมของทุกคน แล้วรอคุณยืนยัน
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<MindState, MindMode>((s) => s.mode);
    final t = S.of(context);

    return LiquidBackground(
      gradient: MindGradients.calendar,
      orbs: Orb.calendar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MindScreenHeader(
              overline: t.tabCalendar,
              title: t.calDate,
              subtitle: t.calSubtitle,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                children: [
                  _Slot(title: t.calStandup, time: '09:00–09:30'),
                  const SizedBox(height: 10),
                  _Slot(title: t.calClient, time: '11:00–12:00'),
                  const SizedBox(height: 10),
                  _proposal(mode, t),
                  const SizedBox(height: MindSpace.md),
                  _restOfDay(context, mode, t),
                ],
              ),
            ),
            _actions(context, mode, t),
          ],
        ),
      ),
    );
  }

  /// ช่องที่เธอเสนอ — ใบเดียวที่มีป้ายกำกับและพื้นไล่สี
  Widget _proposal(MindMode mode, S t) {
    final tint = mode.gradient.colors;

    return GlassPanel(
      radius: MindRadius.card,
      padding: const EdgeInsets.all(15),
      shadows: MindShadows.card(),
      gradient: LinearGradient(
        begin: const Alignment(-0.5, -1),
        end: const Alignment(0.5, 1),
        colors: [
          tint.first.withValues(alpha: .16),
          tint.last.withValues(alpha: .12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              gradient: mode.gradient,
              borderRadius: BorderRadius.circular(MindRadius.pill),
            ),
            child: Text(t.calProposedBadge,
                style: mindMono(size: 9.5, color: Colors.white, letterSpacing: .1)),
          ),
          const SizedBox(height: 10),
          Text(t.calReview,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          const Text('15:00–15:30 · Google Meet',
              style: TextStyle(fontSize: 11.5, color: MindColors.ink60)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _Attendee(t.calFree(t.nameTon)),
              _Attendee(t.calFree(t.nameNapa)),
              _Attendee(t.calAddPerson, free: false),
            ],
          ),
        ],
      ),
    );
  }

  /// ปิดท้ายรายการนัดด้วยคำตอบ ไม่ใช่ปล่อยว่าง
  ///
  /// ก่อนหน้านี้ครึ่งล่างของจอเป็นที่ว่างเปล่า ๆ ซึ่งอ่านได้สองแบบ:
  /// "โหลดไม่เสร็จ" กับ "ไม่มีนัดแล้ว" · แบบหลังเป็นข่าวดีแต่ไม่มีใครรู้
  /// เพราะไม่ได้พูดออกมา · ที่ว่างที่ไม่ได้ตั้งใจคือสิ่งที่ทำให้แอปดูยังไม่เสร็จ
  Widget _restOfDay(BuildContext context, MindMode mode, S t) {
    return GlassPanel(
      radius: MindRadius.card,
      fill: MindColors.glass55,
      shadows: MindShadows.soft(),
      padding: const EdgeInsets.symmetric(
          vertical: MindSpace.xl, horizontal: MindSpace.lg),
      child: Column(
        children: [
          // วงแสงนุ่ม ๆ ใช้จานสีเดียวกับก้อนแสงพื้นหลัง จะได้เป็นเนื้อเดียวกับ
          // ทั้งจอ ไม่ใช่ภาพประกอบที่ลอยมาจากที่อื่น
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                mode.accent.withValues(alpha: .18),
                mode.accent.withValues(alpha: .02),
              ]),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.wb_twilight_rounded,
                size: 34, color: mode.accent.withValues(alpha: .85)),
          ),
          const SizedBox(height: MindSpace.md),
          Text(t.calRestClear, style: MindType.title),
          const SizedBox(height: MindSpace.xs),
          Text(t.calRestHours(4),
              style: MindType.caption, textAlign: TextAlign.center),
          const SizedBox(height: MindSpace.md),
          MindButton(
            label: t.calHold,
            kind: MindButtonKind.quiet,
            icon: Icons.lock_clock_rounded,
            mode: mode,
            onTap: () => showDemoNote(context),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, MindMode mode, S t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          MindSpace.lg, MindSpace.sm, MindSpace.lg, MindSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MindSpace.sm,
        children: [
          MindSectionLabel(t.calNext),
          Row(
            spacing: MindSpace.sm,
            children: [
              Expanded(
                flex: 2,
                child: MindButton(
                  label: t.calConfirm,
                  kind: MindButtonKind.primary,
                  icon: Icons.check_rounded,
                  mode: mode,
                  expand: true,
                  onTap: () => showDemoNote(context),
                ),
              ),
              Expanded(
                child: MindButton(
                  label: t.calFindAnother,
                  mode: mode,
                  expand: true,
                  onTap: () => showDemoNote(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// นัดที่มีอยู่แล้วในปฏิทิน — เธอไม่ได้แตะ แค่แสดงให้เห็นว่าชนหรือไม่
class _Slot extends StatelessWidget {
  const _Slot({required this.title, required this.time});

  final String title, time;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 22,
      fill: MindColors.glass62,
      filter: MindGlass.light,
      shadows: MindShadows.soft(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
          Text(time, style: mindMono(size: 11, color: MindColors.ink55)),
        ],
      ),
    );
  }
}

class _Attendee extends StatelessWidget {
  const _Attendee(this.name, {this.free = true});

  final String name;

  /// ว่างตรงกัน = มีเครื่องหมายถูก ถ้าไม่ใช่คน (ปุ่มเพิ่ม) ให้ปิด
  /// ข้อความเต็มมาจากผู้เรียกแล้ว widget ไม่ต่อคำเอง ไม่งั้นแปลแล้วเรียงผิดไวยากรณ์
  final bool free;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: MindColors.glass80,
        borderRadius: BorderRadius.circular(MindRadius.pill),
        border: Border.all(color: MindColors.glassBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          if (free)
            const Icon(Icons.check_rounded, size: 13, color: Color(0xFF00A894)),
          Text(
            name,
            style: const TextStyle(fontSize: 11, color: MindColors.ink75),
          ),
        ],
      ),
    );
  }
}
