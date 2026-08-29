import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// ปุ่มของทั้งแอป — หนึ่งชนิด สี่หน้าตา
///
/// **ทำไมต้องรวม:** ก่อนหน้านี้ทุกปุ่มถูกประกอบสดจาก `Container` ตรงที่ใช้
/// ผลคือในจอเดียวกันมีปุ่มสูง 46 กับ 40 · รัศมี 16 กับ 14 · บางอันมีเงาเรือง
/// บางอันไม่มี · สายตาอ่านความไม่สม่ำเสมอนั้นออกก่อนที่สมองจะบอกได้ว่าอะไรผิด
///
/// 🔴 **และปุ่มพวกนั้นส่วนใหญ่กดไม่ได้จริง** — เป็น Container ที่ไม่มี onTap
/// ดูเหมือนปุ่มทุกอย่างแต่แตะแล้วเงียบ ซึ่งแย่กว่าปุ่มหน้าตาไม่สวยมาก
/// ตัวนี้บังคับให้ต้องส่ง [onTap] มา · อยากได้ปุ่มที่ยังไม่ต่อสาย ให้ส่ง null
/// แล้วมันจะ**จางลงให้เห็นว่ากดไม่ได้** ไม่ใช่แกล้งทำเป็นกดได้
enum MindButtonKind {
  /// งานหลักของจอ — มีได้จอละหนึ่งอย่าง
  primary,

  /// ทางเลือกรอง วางคู่กับ primary ได้
  secondary,

  /// ลิงก์ในเนื้อหา แทนตัวหนังสือสีเปล่า ๆ ที่แตะไม่รู้ว่าแตะได้
  quiet,
}

class MindButton extends StatelessWidget {
  const MindButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = MindButtonKind.secondary,
    this.mode = MindMode.work,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onTap;
  final MindButtonKind kind;
  final MindMode mode;
  final IconData? icon;

  /// กินความกว้างที่เหลือทั้งหมด — ใช้กับปุ่มที่อยู่ใน Row คู่กัน
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final primary = kind == MindButtonKind.primary;
    final quiet = kind == MindButtonKind.quiet;

    final fg = primary
        ? Colors.white
        : quiet
            ? mode.accent
            : MindColors.ink;

    Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 17, color: fg),
          const SizedBox(width: MindSpace.sm),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MindType.button.copyWith(color: fg),
          ),
        ),
      ],
    );

    content = Padding(
      padding: EdgeInsets.symmetric(horizontal: quiet ? MindSpace.md : MindSpace.lg),
      child: content,
    );

    final radius = BorderRadius.circular(MindRadius.control);

    return Opacity(
      opacity: enabled ? 1 : .42,
      child: _Glow(
        // เงาเรืองมีเฉพาะปุ่มหลักและเฉพาะตอนกดได้ — เงาคือสิ่งที่บอกว่า
        // "อันนี้แหละที่ต้องกด" ถ้าใส่ให้ทุกปุ่มมันก็ไม่ได้บอกอะไรอีกต่อไป
        enabled: primary && enabled,
        color: mode.accentSoft,
        radius: radius,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            height: MindSpace.tapHeight,
            decoration: BoxDecoration(
              gradient: primary && enabled ? mode.gradient : null,
              color: primary
                  ? (enabled ? null : MindColors.ink22)
                  : quiet
                      ? Colors.transparent
                      : MindColors.glass80,
              borderRadius: radius,
              border: quiet || primary
                  ? null
                  : Border.all(color: MindColors.glassBorder, width: 1),
            ),
            child: InkWell(
              borderRadius: radius,
              onTap: enabled
                  ? () {
                      // สัมผัสสั้น ๆ ตอนกด — บนแผ่นกระจกโปร่ง ริปเปิลอย่างเดียว
                      // มองเห็นยาก คนจะไม่แน่ใจว่ากดติดหรือยัง
                      HapticFeedback.selectionClick();
                      onTap!();
                    }
                  : null,
              child: Center(child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// ปุ่มไอคอนล้วน — จัตุรัสขนาดเท่าความสูงของปุ่มปกติ จะได้ยืนในแถวเดียวกันได้พอดี
class MindIconButton extends StatelessWidget {
  const MindIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.mode = MindMode.work,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onTap;

  /// บังคับให้ใส่เสมอ — ปุ่มที่มีแต่ไอคอนคือปุ่มที่ screen reader อ่านไม่ออก
  /// ถ้าไม่มีป้ายกำกับ และคนที่ไม่รู้จักไอคอนนั้นก็เดาไม่ถูกเหมือนกัน
  final String tooltip;

  final MindMode mode;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final radius = BorderRadius.circular(MindRadius.control);

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Opacity(
          opacity: enabled ? 1 : .42,
          child: _Glow(
            enabled: filled && enabled,
            color: mode.accentSoft,
            radius: radius,
            child: Material(
              color: Colors.transparent,
              child: Ink(
                width: MindSpace.tapHeight,
                height: MindSpace.tapHeight,
                decoration: BoxDecoration(
                  gradient: filled && enabled ? mode.gradient : null,
                  color: filled ? null : MindColors.glass80,
                  borderRadius: radius,
                  border: filled
                      ? null
                      : Border.all(color: MindColors.glassBorder, width: 1),
                ),
                child: InkWell(
                  borderRadius: radius,
                  onTap: enabled
                      ? () {
                          HapticFeedback.selectionClick();
                          onTap!();
                        }
                      : null,
                  child: Icon(icon,
                      size: 19,
                      color: filled ? Colors.white : MindColors.ink75),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// เงาเรืองใต้ปุ่มหลัก แยกออกมาเพราะต้องอยู่ **นอก** Material
/// ไม่งั้นริปเปิลตอนกดจะไปตัดขอบเงาให้เห็นเป็นสี่เหลี่ยม
class _Glow extends StatelessWidget {
  const _Glow({
    required this.enabled,
    required this.color,
    required this.radius,
    required this.child,
  });

  final bool enabled;
  final Color color;
  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(color: color, blurRadius: 22, offset: const Offset(0, 8)),
        ],
      ),
      child: child,
    );
  }
}
