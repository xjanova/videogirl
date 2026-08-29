import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// หัวจอมาตรฐาน — ป้ายกำกับ + ชื่อจอ + คำขยาย
///
/// ทั้งสี่จอเคยเขียนหัวเองแยกกัน ขนาดตัวอักษรจึงต่าง ๆ กันไปทีละครึ่งพอยต์
/// และระยะขอบก็ไม่ตรงกัน · หัวจอคือสิ่งแรกที่ตาไปโดน ถ้าตรงนี้ไม่ตรงกัน
/// ทั้งแอปจะรู้สึกเหมือนคนละแอปมาต่อกัน
class MindScreenHeader extends StatelessWidget {
  const MindScreenHeader({
    super.key,
    required this.overline,
    required this.title,
    this.subtitle,
    this.trailing,
    this.padding,
  });

  /// ป้ายตัวเล็กเหนือชื่อจอ — บอกว่าอยู่ส่วนไหนของแอป
  final String overline;

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// จอที่ตัวลิสต์มีขอบซ้ายขวาของตัวเองอยู่แล้ว (หน้าตั้งค่า) ส่งค่าที่ไม่มี
  /// ขอบซ้ายขวาเข้ามา ไม่งั้นหัวจะเยื้องเข้าเป็นสองเท่าของอีกสามจอ
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ??
          const EdgeInsets.fromLTRB(
              MindSpace.lg, MindSpace.lg, MindSpace.lg, MindSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(overline.toUpperCase(),
                    style: mindMono(
                        size: 10.5,
                        weight: FontWeight.w600,
                        color: MindColors.ink45,
                        letterSpacing: .16)),
                const SizedBox(height: MindSpace.sm),
                Text(title, style: MindType.display),
                if (subtitle != null) ...[
                  const SizedBox(height: MindSpace.xs),
                  Text(subtitle!, style: MindType.caption),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: MindSpace.md),
            Padding(
              padding: const EdgeInsets.only(top: MindSpace.sm),
              child: trailing,
            ),
          ],
        ],
      ),
    );
  }
}

/// ป้ายหมวดในหน้าตั้งค่า — ตัวเล็ก **หนา ถ่างตัว** ไม่ใช่ตัวเล็กแล้วจาง
class MindSectionLabel extends StatelessWidget {
  const MindSectionLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: MindType.overline
            .copyWith(color: color ?? MindColors.ink55),
      );
}

/// บอกว่าหน้านี้ยังเป็นข้อมูลตัวอย่าง
///
/// ปุ่มที่แตะแล้วเงียบสนิทคือสิ่งที่ทำให้แอปรู้สึกพัง แม้ตัวมันจะไม่ได้พัง
/// ตอบอะไรสักอย่างที่ **จริง** ดีกว่าไม่ตอบ และดีกว่าแกล้งทำเป็นทำงานได้
void showDemoNote(BuildContext context) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(S.of(context).demoAction),
      duration: const Duration(seconds: 2),
      margin: const EdgeInsets.fromLTRB(
          MindSpace.lg, 0, MindSpace.lg, MindSpace.xxl * 3),
    ));
}
