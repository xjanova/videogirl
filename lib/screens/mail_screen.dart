import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/mind_state.dart';
import '../i18n/strings.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';
import '../widgets/screen_header.dart';

/// เมล — เธอใช้แอปเมลในเครื่องแทนเจ้าของ
///
/// เจ้าของ: "เชื่อมต่อกับแอพในเครื่องเลยได้ไหม เช่น google mail hotmail" · "อยากให้คอนโทรลเครื่อง
/// แล้วกดเปิดพวกมันขึ้นมาเธอใช้มันได้เลย จะง่ายกว่าไปขออนุญาต" · ไม่มีรหัสผ่านเมล ไม่มี OAuth ·
/// เธอใช้มือ (MindHands · PhoneAgent) เปิดแอปเมลอ่าน แล้วสรุปในแชท · หน้านี้ไม่ได้โชว์เมลเอง
///
/// 🔴 ห้ามกลับไปวางกล่องเมลสมมติตาม artboard 2d (สยามเทค / คุณนภา / "24 ฉบับ") ·
/// คนเพิ่งลงแอปอ่านว่าเธออ่านเมลของเขาไปแล้ว — ทั้งไม่จริงและน่ากลัว
class MailScreen extends StatelessWidget {
  const MailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<MindState, MindMode>((s) => s.mode);
    final apps = context.select<MindState, List<({String name, String package})>>((s) => s.mailApps);
    final known = context.select<MindState, bool>((s) => s.mailAppsKnown);
    final busy = context.select<MindState, bool>((s) => s.mailBusy);
    final hands = context.select<MindState, bool>((s) => s.phoneControl);
    final t = S.of(context);

    final note = !hands
        ? t.mailHandsOff
        : busy
            ? t.mailBusy
            : t.mailResultInChat;

    return LiquidBackground(
      gradient: MindGradients.mail,
      orbs: Orb.mail,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MindScreenHeader(
              overline: t.tabMail,
              title: t.mailTitle,
              subtitle: t.mailSubtitle,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                children: [
                  GlassPanel(
                    radius: MindRadius.card,
                    fill: MindColors.glass62,
                    filter: MindGlass.light,
                    shadows: MindShadows.card(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 10,
                      children: [
                        Row(
                          spacing: 10,
                          children: [
                            Icon(Icons.mark_email_unread_outlined,
                                size: 18, color: mode.accent),
                            Expanded(
                              child: Text(t.mailAppsTitle,
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        if (!known)
                          _line(t.mailLooking)
                        else if (apps.isEmpty)
                          _line(t.mailNoApp)
                        else
                          for (final (i, app) in apps.indexed)
                            MindButton(
                              label: t.mailCheckButton(app.name),
                              kind: i == 0 ? MindButtonKind.primary : MindButtonKind.secondary,
                              icon: Icons.mark_email_read_outlined,
                              mode: mode,
                              expand: true,
                              onTap: hands && !busy
                                  ? () => unawaited(context.read<MindState>().checkMail(app.name))
                                  : null,
                            ),
                        _line(note),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  GlassPanel(
                    radius: MindRadius.card,
                    fill: MindColors.glass62,
                    filter: MindGlass.light,
                    shadows: MindShadows.card(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 10,
                      children: [
                        Row(
                          spacing: 10,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded,
                                size: 18, color: mode.accent),
                            Expanded(
                              child: Text(t.mailCanDoTitle,
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        for (final p in t.mailCanDoPoints)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 9,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: mode.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              Expanded(child: _line(p)),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(MindRadius.avatarThumb),
                      border: Border.all(color: MindColors.ink22, width: 1),
                    ),
                    child: Text(
                      t.mailSafety,
                      style: const TextStyle(
                          fontSize: 11.5, height: 1.6, color: MindColors.ink60),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _line(String text) => Text(text,
      style: const TextStyle(fontSize: 12, height: 1.6, color: MindColors.ink60));
}
