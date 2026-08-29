import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/mind_state.dart';
import '../theme/app_theme.dart';
import '../i18n/strings.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';

/// เมล — artboard 2d
/// เธอสรุปกล่องเช้านี้ แล้วร่างคำตอบรออนุมัติ
class MailScreen extends StatelessWidget {
  const MailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<MindState, MindMode>((s) => s.mode);
    final t = S.of(context);

    return LiquidBackground(
      gradient: MindGradients.mail,
      orbs: Orb.mail,
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
                  Text(t.mailTitle,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.2)),
                  Text(t.mailSubtitle,
                      style: const TextStyle(
                          fontSize: 11.5, color: MindColors.ink55)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                children: [
                  _MailCard(
                    dot: const Color(0xFFFF5C8A),
                    title: t.mail1Title,
                    body: t.mail1Body,
                  ),
                  const SizedBox(height: 11),
                  _DraftCard(mode: mode, t: t),
                  const SizedBox(height: 11),
                  _MailCard(
                    dot: const Color(0x4023204A),
                    title: t.mail3Title,
                    body: t.mail3Body,
                    glow: false,
                  ),
                  const SizedBox(height: 14),
                  _laterNote(t),
                ],
              ),
            ),
            _actions(mode, t),
          ],
        ),
      ),
    );
  }

  Widget _laterNote(S t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MindRadius.avatarThumb),
        border: Border.all(color: MindColors.ink22, width: 1),
      ),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
              fontSize: 11.5, height: 1.6, color: MindColors.ink60),
          children: [
            TextSpan(text: t.mailLaterNote1),
            TextSpan(
                text: t.mailLaterNote2,
                style: const TextStyle(
                    color: MindColors.ink, fontWeight: FontWeight.w600)),
            TextSpan(text: t.mailLaterNote3),
          ],
        ),
      ),
    );
  }

  Widget _actions(MindMode mode, S t) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        spacing: 9,
        children: [
          Expanded(
            child: Container(
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: MindColors.glass80,
                borderRadius: BorderRadius.circular(MindRadius.message),
                border: Border.all(color: MindColors.glassBorder, width: 1),
              ),
              child: Text(t.mailReadAloud,
                  style: const TextStyle(fontSize: 12.5)),
            ),
          ),
          Container(
            width: 54,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: mode.gradient,
              borderRadius: BorderRadius.circular(MindRadius.message),
              boxShadow: [
                BoxShadow(color: mode.accentSoft, blurRadius: 24, offset: const Offset(0, 10)),
              ],
            ),
            child: const Icon(Icons.edit_rounded, size: 18, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _MailCard extends StatelessWidget {
  const _MailCard({
    required this.dot,
    required this.title,
    required this.body,
    this.glow = true,
  });

  final Color dot;
  final String title;
  final String body;

  /// เมลที่ยังไม่ได้จัดการมีจุดเรือง เมลที่รอเฉย ๆ ไม่มี
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 22,
      fill: MindColors.glass62,
      filter: MindGlass.light,
      shadows: MindShadows.card(),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 11,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _Dot(color: dot, glow: glow),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(body,
                    style: const TextStyle(
                        fontSize: 11.5, height: 1.6, color: MindColors.ink60)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.glow = true});

  final Color color;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: glow
            ? [BoxShadow(color: color.withValues(alpha: .7), blurRadius: 10)]
            : null,
      ),
    );
  }
}

/// การ์ดร่างคำตอบ — ใบเดียวในจอที่ใช้พื้นไล่สีแทนกระจกใส
class _DraftCard extends StatelessWidget {
  const _DraftCard({required this.mode, required this.t});

  final MindMode mode;
  final S t;

  @override
  Widget build(BuildContext context) {
    final tint = mode.gradient.colors;

    return GlassPanel(
      radius: MindRadius.card,
      padding: const EdgeInsets.all(15),
      shadows: MindShadows.card(),
      gradient: LinearGradient(
        begin: const Alignment(-0.5, -1),
        end: const Alignment(0.5, 1),
        colors: [
          tint.first.withValues(alpha: .14),
          tint.last.withValues(alpha: .12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 11,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _Dot(color: tint.first),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(t.mail2Title,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                    Text(t.mail2Body,
                        style: const TextStyle(
                            fontSize: 11.5, height: 1.6, color: MindColors.ink60)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(t.mailDraftLabel,
              style: mindMono(size: 10, color: mode.accent, letterSpacing: .1)),
          const SizedBox(height: 7),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color: MindColors.glass85,
              borderRadius: BorderRadius.circular(MindRadius.message),
              border: Border.all(color: MindColors.glassBorder, width: 1),
            ),
            child: Text(
              t.mailDraftBody,
              style: const TextStyle(fontSize: 12.5, height: 1.7),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: mode.gradient,
                    borderRadius: BorderRadius.circular(MindRadius.control),
                    boxShadow: [
                      BoxShadow(
                          color: mode.accentSoft,
                          blurRadius: 20,
                          offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Text(t.mailSendNow,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ),
              Expanded(
                  child: _ghostButton(
                      Text(t.mailEditFirst, style: const TextStyle(fontSize: 12)))),
              SizedBox(
                width: 46,
                child: _ghostButton(const Icon(Icons.volume_up_rounded, size: 16)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ghostButton(Widget child) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: MindColors.glass85,
          borderRadius: BorderRadius.circular(MindRadius.control),
          border: Border.all(color: MindColors.glassBorder, width: 1),
        ),
        child: child,
      );
}
