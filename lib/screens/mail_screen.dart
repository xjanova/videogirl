import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/mind_state.dart';
import '../i18n/strings.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';
import '../widgets/screen_header.dart';

/// เมล — artboard 2d
///
/// 🔴 **ยังไม่ได้ต่อกล่องเมลจริง และหน้านี้บอกตรง ๆ**
///
/// ของเดิมวางกล่องเมลสมมติทั้งหน้าตาม artboard (สยามเทค / คุณนภา / ร่างคำตอบ
/// "24 ฉบับ") พร้อมปุ่มส่งเมลที่กดแล้วขึ้นว่าเป็นข้อมูลตัวอย่าง · คนเพิ่งลงแอป
/// อ่านว่าเธอเข้าไปอ่านเมลของเขาแล้ว — ทั้งไม่จริงและน่ากลัว · หลักเดียวกับ
/// หน้าปฏิทินที่เลิกใช้นัดสมมติไปก่อนแล้ว: เลขาที่บอกของปลอมแย่กว่าเลขาที่บอกว่ายังไม่รู้
///
/// วันที่ต่อเมลจริง ค่อยกลับไปถอดการ์ดจาก artboard 2d มาใส่ข้อมูลจริง
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 10,
                      children: [
                        Row(
                          spacing: 10,
                          children: [
                            Icon(Icons.mark_email_unread_outlined,
                                size: 18, color: mode.accent),
                            Expanded(
                              child: Text(t.mailNotYetTitle,
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        for (final p in t.mailNotYetPoints)
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
                              Expanded(
                                child: Text(p,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.6,
                                        color: MindColors.ink60)),
                              ),
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
                      t.mailNotYetMeanwhile,
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
}
