import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// ธีมของแอป — artboard ใช้ IBM Plex Sans Thai เป็นตัวเนื้อ
/// และ IBM Plex Mono กับตัวเลข/ป้ายสถานะ (เวลา, MIND, ป้าย ร่างคำตอบของเธอ)
ThemeData mindTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: MindColors.violet,
      brightness: Brightness.light,
    ).copyWith(surface: Colors.transparent),
    // ทุกหน้าจอวาดพื้นหลังไล่สีของตัวเอง Scaffold ต้องไม่ทับ
    scaffoldBackgroundColor: Colors.transparent,
    splashFactory: InkSparkle.splashFactory,
  );

  return base.copyWith(
    textTheme: GoogleFonts.ibmPlexSansThaiTextTheme(base.textTheme).apply(
      bodyColor: MindColors.ink,
      displayColor: MindColors.ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
  );
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
