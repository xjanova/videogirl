import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'glass.dart';

/// ปุ่มสลับแบบพิลล์กระจก — ตอนนี้ใช้สลับ ปฏิทิน | ไทม์ไลน์ ในแท็บเดียวกัน
///
/// ไทม์ไลน์ย้ายออกจากแถบล่างเพื่อเปิดที่ให้แท็บ "โทรศัพท์" (แถบต้องเป็นเลขคี่
/// หน้ามายด์จึงอยู่กลางได้ ดู MindNavBar) · สองหน้านี้เป็นเรื่องเวลาเหมือนกัน
/// จึงอยู่แท็บเดียวกัน · หน้าตายืมจากแท็บในแถบล่าง (พิลล์จาง + ตัวสีเน้น)
class MindSegmentSwitch extends StatelessWidget {
  const MindSegmentSwitch({
    super.key,
    required this.labels,
    required this.selected,
    required this.mode,
    required this.onSelect,
  });

  final List<String> labels;
  final int selected;
  final MindMode mode;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: MindRadius.pill,
      fill: MindColors.glass62,
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(child: _segment(i)),
        ],
      ),
    );
  }

  Widget _segment(int i) {
    final on = i == selected;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // แตะช่องที่เลือกอยู่แล้วไม่ทำอะไร
        onTap: on ? null : () => onSelect(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: on ? mode.accent.withValues(alpha: .13) : null,
            borderRadius: BorderRadius.circular(MindRadius.pill),
          ),
          child: Text(
            labels[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              color: on ? mode.accent : MindColors.ink55,
            ),
          ),
        ),
      ),
    );
  }
}
