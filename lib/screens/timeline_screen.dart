import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';

/// ไทม์ไลน์ — artboard 2f
/// วันนี้เธอทำอะไรให้บ้าง และย้อนกลับได้ทุกอย่าง
class TimelineScreen extends StatelessWidget {
  const TimelineScreen({super.key});

  static const _entries = <_Entry>[
    _Entry('08:12', 'สรุปกล่องเมลเช้า', '24 ฉบับ → 3 ที่ต้องตอบ · ร่างคำตอบไว้ 2',
        Color(0xFF00C2A8), 'ดูร่าง', Color(0xFF00A894)),
    _Entry('09:05', 'รับสายแทน — คุณวิชัย', 'ใบเสนอราคา QT-2609 ขอต่อรอง 7% · จดไว้แล้ว',
        Color(0xFF7C6CFF), 'ฟังเสียง · อ่านสรุป', Color(0xFF5A4DE0)),
    _Entry('09:40', 'ส่งเมลตอบคุณนภา', 'อนุมัติเลื่อนอาร์ตเวิร์กเป็นวันจันทร์เช้า',
        Color(0xFF3EC7FF), 'ย้อนกลับ (เหลือ 23 ชม.)', MindeColors.ink50),
    _Entry('10:20', 'โทรออก — คุณต้น', 'เลื่อนรีวิวเป็นพฤหัส 15:00 · เขาตอบตกลง',
        Color(0xFF00C2A8), 'ดูบทสนทนา', Color(0xFF00A894)),
    _Entry('11:15', 'รอคุณอนุมัติ', 'ส่วนลด QT-2609 เกินอำนาจที่ตั้งไว้ (สูงสุด 5%)',
        Color(0xFFFFAB3D), 'ตัดสินใจตอนนี้', Color(0xFFB46A00)),
    _Entry('12:00', 'เตือนกินข้าว', 'เธอปิดแจ้งเตือนงานให้ 45 นาที',
        Color(0xFFFF6FAE), '', Colors.transparent),
  ];

  static const _stats = <(String, int)>[
    ('รับสาย', 3),
    ('ส่งเมล', 5),
    ('นัด', 2),
    ('รอคุณ', 4),
  ];

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      gradient: MindeGradients.timeline,
      orbs: Orb.timeline,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Text('วันนี้เธอทำให้ 14 อย่าง',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                spacing: 8,
                children: [for (final s in _stats) Expanded(child: _stat(s.$1, s.$2))],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                itemCount: _entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _row(_entries[i], last: i == _entries.length - 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, int count) {
    return GlassPanel(
      radius: MindeRadius.avatarThumb,
      fill: MindeColors.glass62,
      padding: const EdgeInsets.symmetric(vertical: 10),
      shadows: MindeShadows.soft(),
      child: Column(
        spacing: 2,
        children: [
          Text('$count',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text(label,
              style: const TextStyle(fontSize: 10.5, color: MindeColors.ink55)),
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
                  child: Container(width: 1, color: MindeColors.ink10),
                ),
            ],
          ),
          Expanded(
            child: GlassPanel(
              radius: 20,
              fill: MindeColors.glass62,
              filter: MindeGlass.light,
              shadows: MindeShadows.soft(),
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Row(
                    spacing: 8,
                    children: [
                      Text(e.time, style: mindeMono(size: 10.5, color: MindeColors.ink50)),
                      Expanded(
                        child: Text(e.title,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  Text(e.detail,
                      style: const TextStyle(
                          fontSize: 11.5, height: 1.6, color: MindeColors.ink60)),
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
