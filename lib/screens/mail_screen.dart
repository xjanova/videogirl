import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/minde_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';

/// เมล — artboard 2d
/// เธอสรุปกล่องเช้านี้ แล้วร่างคำตอบรออนุมัติ
class MailScreen extends StatelessWidget {
  const MailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<MindeState, MindeMode>((s) => s.mode);

    return LiquidBackground(
      gradient: MindeGradients.mail,
      orbs: Orb.mail,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text('กล่องเมลเช้านี้',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.2)),
                  Text('24 ฉบับ · เธอคัดให้เหลือ 3 ที่ต้องตอบ',
                      style: TextStyle(fontSize: 11.5, color: MindeColors.ink55)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                children: [
                  const _MailCard(
                    dot: Color(0xFFFF5C8A),
                    title: 'สยามเทค — ขอต่อรองราคา QT-2609',
                    body: 'ขอส่วนลด 7% แลกกับสั่งเพิ่มเป็น 500 ชุด · ต้องการคำตอบก่อนศุกร์',
                  ),
                  const SizedBox(height: 11),
                  _DraftCard(mode: mode),
                  const SizedBox(height: 11),
                  const _MailCard(
                    dot: Color(0x4023204A),
                    title: 'HR — ยืนยันวันลาพักร้อน',
                    body: 'รอกดยืนยัน 12–14 ก.ย. เธอกดให้ได้ถ้าคุณสั่ง',
                    glow: false,
                  ),
                  const SizedBox(height: 14),
                  _laterNote(),
                ],
              ),
            ),
            _actions(mode),
          ],
        ),
      ),
    );
  }

  Widget _laterNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(MindeRadius.avatarThumb),
        border: Border.all(color: MindeColors.ink22, width: 1),
      ),
      child: const Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 11.5, height: 1.6, color: MindeColors.ink60),
          children: [
            TextSpan(text: 'อีก 21 ฉบับเธอจัดเป็น '),
            TextSpan(
                text: 'อ่านทีหลัง',
                style: TextStyle(color: MindeColors.ink, fontWeight: FontWeight.w600)),
            TextSpan(text: ' — ข่าวสาร 12 · ใบเสร็จ 6 · สแปม 3'),
          ],
        ),
      ),
    );
  }

  Widget _actions(MindeMode mode) {
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
                color: MindeColors.glass80,
                borderRadius: BorderRadius.circular(MindeRadius.message),
                border: Border.all(color: MindeColors.glassBorder, width: 1),
              ),
              child: const Text('ให้เธออ่านสรุปให้ฟัง', style: TextStyle(fontSize: 12.5)),
            ),
          ),
          Container(
            width: 54,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: mode.gradient,
              borderRadius: BorderRadius.circular(MindeRadius.message),
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
      fill: MindeColors.glass62,
      filter: MindeGlass.light,
      shadows: MindeShadows.card(),
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
                        fontSize: 11.5, height: 1.6, color: MindeColors.ink60)),
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
  const _DraftCard({required this.mode});

  final MindeMode mode;

  @override
  Widget build(BuildContext context) {
    final tint = mode.gradient.colors;

    return GlassPanel(
      radius: MindeRadius.card,
      padding: const EdgeInsets.all(15),
      shadows: MindeShadows.card(),
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text('คุณนภา — เลื่อนส่งไฟล์อาร์ตเวิร์ก',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    Text('ขอเลื่อนจากศุกร์เป็นจันทร์ เพราะรอไฟล์จากลูกค้า',
                        style: TextStyle(
                            fontSize: 11.5, height: 1.6, color: MindeColors.ink60)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('ร่างคำตอบของเธอ',
              style: mindeMono(size: 10, color: mode.accent, letterSpacing: .1)),
          const SizedBox(height: 7),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              color: MindeColors.glass85,
              borderRadius: BorderRadius.circular(MindeRadius.message),
              border: Border.all(color: MindeColors.glassBorder, width: 1),
            ),
            child: const Text(
              'สวัสดีค่ะคุณนภา\n'
              'เลื่อนเป็นวันจันทร์ได้ค่ะ แต่รบกวนส่งภายในเช้าวันจันทร์นะคะ '
              'เพราะทีมต้องรีวิวก่อนส่งโรงพิมพ์บ่ายวันเดียวกัน\n'
              'ขอบคุณค่ะ',
              style: TextStyle(fontSize: 12.5, height: 1.7),
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
                    borderRadius: BorderRadius.circular(MindeRadius.control),
                    boxShadow: [
                      BoxShadow(
                          color: mode.accentSoft,
                          blurRadius: 20,
                          offset: const Offset(0, 8)),
                    ],
                  ),
                  child: const Text('ส่งเลย',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
              Expanded(child: _ghostButton(const Text('แก้ก่อน', style: TextStyle(fontSize: 12)))),
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
          color: MindeColors.glass85,
          borderRadius: BorderRadius.circular(MindeRadius.control),
          border: Border.all(color: MindeColors.glassBorder, width: 1),
        ),
        child: child,
      );
}
