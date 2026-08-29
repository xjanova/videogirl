import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// แผ่นกระจก — พื้นฐานของทุกพื้นผิวในธีม Liquid Glass
///
/// ต้อง clip ก่อน BackdropFilter เสมอ ไม่งั้นมันจะเบลอทั้งจอ ไม่ใช่แค่ในกรอบ
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = MindeRadius.panel,
    this.fill = MindeColors.glass55,
    this.border = MindeColors.glassBorder,
    this.filter,
    this.shadows,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.gradient,
  });

  final Widget child;
  final double radius;
  final Color fill;
  final Color? border;

  /// ปล่อยว่าง = ไม่เบลอพื้นหลัง ใช้กับการ์ดที่ทับก้อนแสงอยู่แล้ว จะได้ไม่เปลืองแรง
  final ImageFilter? filter;

  final List<BoxShadow>? shadows;
  final EdgeInsets padding;
  final EdgeInsets margin;

  /// การ์ดบางใบ (เช่น ร่างคำตอบในหน้าเมล) ใช้ไล่สีแทนสีทึบ
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? fill : null,
        gradient: gradient,
        borderRadius: shape,
        border: border == null ? null : Border.all(color: border!, width: 1),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (filter != null) {
      surface = BackdropFilter(filter: filter!, child: surface);
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(borderRadius: shape, boxShadow: shadows),
      child: ClipRRect(borderRadius: shape, child: surface),
    );
  }
}

/// ฟองคำพูดข้างหัวอวาตาร์ — มุมล่างซ้ายบีบเป็นหาง (20 20 20 6 ใน CSS)
class SpeechBubble extends StatelessWidget {
  const SpeechBubble({super.key, required this.text, this.maxWidth = 210});

  final String text;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(MindeRadius.bubble),
            topRight: Radius.circular(MindeRadius.bubble),
            bottomRight: Radius.circular(MindeRadius.bubble),
            bottomLeft: Radius.circular(MindeRadius.bubbleTail),
          ),
          boxShadow: MindeShadows.bubble(),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(MindeRadius.bubble),
            topRight: Radius.circular(MindeRadius.bubble),
            bottomRight: Radius.circular(MindeRadius.bubble),
            bottomLeft: Radius.circular(MindeRadius.bubbleTail),
          ),
          child: BackdropFilter(
            filter: MindeGlass.light,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: MindeColors.glass72,
                border: Border.all(color: MindeColors.glassBorder, width: 1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(MindeRadius.bubble),
                  topRight: Radius.circular(MindeRadius.bubble),
                  bottomRight: Radius.circular(MindeRadius.bubble),
                  bottomLeft: Radius.circular(MindeRadius.bubbleTail),
                ),
              ),
              child: Text(
                text,
                style: const TextStyle(fontSize: 12.5, height: 1.55, color: MindeColors.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ชิปคำถามลัดใต้แชท และปุ่มกลม ๆ อื่น ๆ ที่หน้าตาเหมือนกัน
class GlassChip extends StatelessWidget {
  const GlassChip({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MindeRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: MindeColors.glass80,
            borderRadius: BorderRadius.circular(MindeRadius.pill),
            border: Border.all(color: MindeColors.glassBorder, width: 1),
            boxShadow: MindeShadows.soft(),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: MindeColors.ink75),
          ),
        ),
      ),
    );
  }
}

/// สวิตช์ งาน / ส่วนตัว บนหัวจอ
class ModeToggle extends StatelessWidget {
  const ModeToggle({super.key, required this.mode, required this.onToggle});

  final MindeMode mode;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'สลับโหมด ตอนนี้โหมด${mode.label}',
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: MindeColors.glass55,
            borderRadius: BorderRadius.circular(MindeRadius.pill),
            border: Border.all(color: MindeColors.glassBorderSoft, width: 1),
            boxShadow: MindeShadows.soft(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 2,
            children: [
              for (final m in MindeMode.values) _pill(m, selected: m == mode),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(MindeMode m, {required bool selected}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: selected ? m.gradient : null,
        borderRadius: BorderRadius.circular(MindeRadius.pill),
      ),
      child: Text(
        m.label,
        style: TextStyle(
          fontSize: 10.5,
          color: selected ? Colors.white : MindeColors.ink55,
        ),
      ),
    );
  }
}
