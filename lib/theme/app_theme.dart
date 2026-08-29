import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// ธีมของแอป — artboard ใช้ IBM Plex Sans Thai เป็นตัวเนื้อ
/// และ IBM Plex Mono กับตัวเลข/ป้ายสถานะ (เวลา, MIND, ป้าย ร่างคำตอบของเธอ)
///
/// 🔴 **ทำไมไฟล์นี้ต้องยาวกว่าที่คิด:** วิดเจ็ตของ Material ที่ไม่ได้ตั้งธีมไว้
/// จะวาดด้วยสีของตัวเองเสมอ — Slider หัวจับอ้วนเงาหนา, Switch เขียว,
/// แถบความคืบหน้าน้ำเงิน — โผล่กลางหน้าจอที่ออกแบบเองมาอย่างดี
/// นี่คือสิ่งที่คนดูออกทันทีว่า "แอปนี้ไม่ได้ตั้งใจทำ" แม้จะบอกไม่ถูกว่าอะไรผิด
/// ตั้งที่นี่ที่เดียว ทุกหน้าจอได้ไปด้วยกันหมด ไม่ต้องไปห่อทีละที่
///
/// สีเน้นวิ่งตาม[โหมด] เพราะทั้งแอปหมุนรอบโหมดอยู่แล้ว — Slider กับ Switch
/// ที่เป็นสีคงที่จะกลายเป็นจุดเดียวในจอที่ไม่เปลี่ยนตามตอนสลับโหมด
ThemeData mindTheme([MindMode mode = MindMode.work]) {
  final accent = mode.accent;

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MindColors.violet,
      brightness: Brightness.light,
    ).copyWith(surface: Colors.transparent, primary: accent),
    // ทุกหน้าจอวาดพื้นหลังไล่สีของตัวเอง Scaffold ต้องไม่ทับ
    scaffoldBackgroundColor: Colors.transparent,
    splashFactory: InkSparkle.splashFactory,
  );

  final text = GoogleFonts.ibmPlexSansThaiTextTheme(base.textTheme).apply(
    bodyColor: MindColors.ink,
    displayColor: MindColors.ink,
  );

  return base.copyWith(
    // บันไดตัวอักษรของเราแทนที่ของ Material ทีละขั้น เพื่อให้วิดเจ็ตสำเร็จรูป
    // (ListTile, Dialog, SnackBar) หยิบขนาดเดียวกับที่เราเขียนเองไปใช้
    textTheme: text.copyWith(
      headlineSmall: text.headlineSmall?.merge(MindType.display),
      titleMedium: text.titleMedium?.merge(MindType.title),
      bodyMedium: text.bodyMedium?.merge(MindType.body),
      bodySmall: text.bodySmall?.merge(MindType.caption),
      labelLarge: text.labelLarge?.merge(MindType.button),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),

    // ── Slider ────────────────────────────────────────────
    // ของเดิมคือ Material 3 ดิบ: หัวจับกลมใหญ่พร้อมเงาตกหนัก บนรางบาง
    // อัตราส่วนหัว/รางที่ไม่สัมพันธ์กันคือสิ่งที่ทำให้มันดูเป็นของแถม
    sliderTheme: SliderThemeData(
      trackHeight: 6,
      activeTrackColor: accent,
      inactiveTrackColor: MindColors.ink10,
      thumbColor: Colors.white,
      overlayColor: accent.withValues(alpha: .12),
      thumbShape: _RingThumb(ring: accent),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
      trackShape: const RoundedRectSliderTrackShape(),
      // ป้ายค่าที่เด้งขึ้นตอนลาก เราไม่ใช้ ปิดไปเลยจะได้ไม่มีกล่องดำโผล่
      showValueIndicator: ShowValueIndicator.never,
    ),

    // ── Switch ────────────────────────────────────────────
    // ค่าตั้งต้นของ M3 ใช้สี primary จาก seed ซึ่งเป็นม่วง ไม่ใช่สีของโหมด
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? accent : MindColors.ink22),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbIcon: const WidgetStatePropertyAll(Icon(null)),
    ),

    // ── แถบความคืบหน้า ────────────────────────────────────
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: MindColors.ink10,
      circularTrackColor: MindColors.ink10,
      linearMinHeight: 4,
      borderRadius: BorderRadius.circular(99),
    ),

    // ── ช่องกรอกข้อความ ───────────────────────────────────
    // ค่าตั้งต้นมีเส้นใต้สีม่วงและ label ที่ลอยขึ้น ซึ่งชนกับแผ่นกระจกทั้งหมด
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: false,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: MindSpace.md, vertical: MindSpace.md),
      hintStyle: MindType.body.copyWith(color: MindColors.ink45),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: accent,
      selectionColor: accent.withValues(alpha: .22),
      selectionHandleColor: accent,
    ),

    // ── ตัวชี้เมื่อกด ─────────────────────────────────────
    // InkSparkle บนแผ่นกระจกจะเห็นเป็นประกายสีเทาแปลก ๆ · ให้มันเป็นสีเน้นจาง
    splashColor: accent.withValues(alpha: .10),
    highlightColor: accent.withValues(alpha: .06),

    dividerTheme: const DividerThemeData(
      color: MindColors.ink10,
      thickness: 1,
      space: 1,
    ),

    // ── กล่องโต้ตอบ / SnackBar ────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MindRadius.card)),
      titleTextStyle: MindType.title.copyWith(fontSize: 17),
      contentTextStyle: MindType.body,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: MindColors.ink,
      contentTextStyle: MindType.body.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MindRadius.control)),
      elevation: 0,
    ),
  );
}

/// หัวจับของ Slider — วงขาวมีขอบสีเน้น ไม่ใช่วงกลมทึบที่มีเงาตกหนัก
///
/// เขียนเองเพราะ `RoundSliderThumbShape` ให้ได้แค่วงกลมสีเดียว การจะได้
/// "ขาวมีขอบ" ต้องวาดสองชั้น · รายละเอียดระดับนี้แหละที่แยกของที่ตั้งใจทำ
/// ออกจากของที่ปล่อยตามค่าตั้งต้น
class _RingThumb extends SliderComponentShape {
  const _RingThumb({required this.ring});

  final Color ring;

  static const radius = 10.0;

  @override
  Size getPreferredSize(bool enabled, bool isDiscrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;

    // เงาสั้นและเบา แค่พอให้หัวจับลอยพ้นราง ไม่ใช่เงาก้อนใหญ่แบบ Material
    canvas.drawCircle(
      center.translate(0, 1),
      radius,
      Paint()
        ..color = const Color(0x265A46B4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      radius - 1.25,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = ring,
    );
  }
}

/// ตัวอักษรแบบ mono ที่ใช้กับป้ายสถานะ เวลา และหัวข้อตัวพิมพ์ใหญ่
TextStyle mindMono({
  double size = 11,
  FontWeight weight = FontWeight.w500,
  Color color = MindColors.ink50,
  double letterSpacing = .12,
}) =>
    GoogleFonts.ibmPlexMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing * size,
    );
