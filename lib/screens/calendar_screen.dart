import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/mind_state.dart';
import '../theme/app_theme.dart';
import '../i18n/strings.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(t.calDate,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.2)),
                  Text(t.calSubtitle,
                      style: const TextStyle(fontSize: 11.5, color: MindColors.ink55)),
                ],
              ),
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
                ],
              ),
            ),
            _actions(mode, t),
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

  Widget _actions(MindMode mode, S t) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(t.calNext,
              style: mindMono(size: 10, color: MindColors.ink50, letterSpacing: .1)),
          Row(
            spacing: 9,
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: mode.gradient,
                    borderRadius: BorderRadius.circular(MindRadius.message),
                    boxShadow: [
                      BoxShadow(
                          color: mode.accentSoft,
                          blurRadius: 24,
                          offset: const Offset(0, 10)),
                    ],
                  ),
                  child: Text(t.calConfirm,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
              Expanded(
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MindColors.glass80,
                    borderRadius: BorderRadius.circular(MindRadius.message),
                    border: Border.all(color: MindColors.glassBorder, width: 1),
                  ),
                  child: Text(t.calFindAnother, style: const TextStyle(fontSize: 12.5)),
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
