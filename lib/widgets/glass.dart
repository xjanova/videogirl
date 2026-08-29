import 'dart:ui';

import 'package:flutter/material.dart';

import '../i18n/enum_labels.dart';
import '../i18n/strings.dart';
import '../theme/tokens.dart';

/// แผ่นกระจก — พื้นฐานของทุกพื้นผิวในธีม Liquid Glass
///
/// ต้อง clip ก่อน BackdropFilter เสมอ ไม่งั้นมันจะเบลอทั้งจอ ไม่ใช่แค่ในกรอบ
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = MindRadius.panel,
    this.shape,
    this.fill = MindColors.glass55,
    this.border = MindColors.glassBorder,
    this.filter,
    this.shadows,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.gradient,
  });

  final Widget child;
  final double radius;

  /// มุมที่ไม่เท่ากันทั้งสี่ด้าน — ใช้กับแผ่นที่ชนขอบจอ เช่นแถบนำทางล่าง
  /// ถ้าใส่มา จะทับ [radius] ทั้งดุ้น
  final BorderRadiusGeometry? shape;

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
    final radii = shape ?? BorderRadius.circular(radius);

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? fill : null,
        gradient: gradient,
        borderRadius: radii,
        border: border == null ? null : Border.all(color: border!, width: 1),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (filter != null) {
      surface = BackdropFilter(filter: filter!, child: surface);
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(borderRadius: radii, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: radii.resolve(Directionality.of(context)),
        child: surface,
      ),
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
            topLeft: Radius.circular(MindRadius.bubble),
            topRight: Radius.circular(MindRadius.bubble),
            bottomRight: Radius.circular(MindRadius.bubble),
            bottomLeft: Radius.circular(MindRadius.bubbleTail),
          ),
          boxShadow: MindShadows.bubble(),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(MindRadius.bubble),
            topRight: Radius.circular(MindRadius.bubble),
            bottomRight: Radius.circular(MindRadius.bubble),
            bottomLeft: Radius.circular(MindRadius.bubbleTail),
          ),
          child: BackdropFilter(
            filter: MindGlass.light,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: MindColors.glass72,
                border: Border.all(color: MindColors.glassBorder, width: 1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(MindRadius.bubble),
                  topRight: Radius.circular(MindRadius.bubble),
                  bottomRight: Radius.circular(MindRadius.bubble),
                  bottomLeft: Radius.circular(MindRadius.bubbleTail),
                ),
              ),
              child: Text(
                text,
                style: const TextStyle(fontSize: 12.5, height: 1.55, color: MindColors.ink),
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
        borderRadius: BorderRadius.circular(MindRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: MindColors.glass80,
            borderRadius: BorderRadius.circular(MindRadius.pill),
            border: Border.all(color: MindColors.glassBorder, width: 1),
            boxShadow: MindShadows.soft(),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: MindColors.ink75),
          ),
        ),
      ),
    );
  }
}

/// สวิตช์ งาน / ส่วนตัว บนหัวจอ
class ModeToggle extends StatelessWidget {
  const ModeToggle({super.key, required this.mode, required this.onToggle});

  final MindMode mode;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: S.of(context).toggleModeHint(mode.labelOf(S.of(context))),
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: MindColors.glass55,
            borderRadius: BorderRadius.circular(MindRadius.pill),
            border: Border.all(color: MindColors.glassBorderSoft, width: 1),
            boxShadow: MindShadows.soft(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 2,
            children: [
              for (final m in MindMode.values)
                _pill(m, selected: m == mode, label: m.labelOf(S.of(context))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(MindMode m, {required bool selected, required String label}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: selected ? m.gradient : null,
        borderRadius: BorderRadius.circular(MindRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          color: selected ? Colors.white : MindColors.ink55,
        ),
      ),
    );
  }
}
