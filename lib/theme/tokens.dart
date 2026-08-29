import 'dart:ui';

import 'package:flutter/material.dart';

/// Design token — ถอดตรงจาก artboard ของ Claude Design
/// `ai-assistant-avatar-app/project/Mind Android Liquid.dc.html` (หน้าจอ 2a–2h)
///
/// artboard คือแหล่งความจริง ถ้าจะแก้สี/ระยะ ให้แก้ที่นั่นแล้วค่อยถอดกลับมาที่นี่
/// อย่าแก้ค่าตรงนี้ลอย ๆ ไม่งั้น design กับ code จะหลุดจากกัน

// ─────────────────────────────────────────────────────────────
//  สีคงที่ — ไม่ขึ้นกับโหมด
// ─────────────────────────────────────────────────────────────
abstract final class MindColors {
  /// สีหมึกหลัก ใช้กับตัวอักษรทุกที่
  static const ink = Color(0xFF23204A);

  static const ink75 = Color(0xBF23204A);
  static const ink60 = Color(0x9923204A);
  static const ink55 = Color(0x8C23204A);
  static const ink50 = Color(0x8023204A);
  static const ink45 = Color(0x7323204A);
  static const ink22 = Color(0x3823204A);
  static const ink10 = Color(0x1A23204A);

  /// สีม่วงกลาง ปลายทางของ gradient ทั้งสองโหมด
  static const violet = Color(0xFF7C6CFF);

  /// จุดแดงกะพริบตอนสายเข้า
  static const ringing = Color(0xFFFF4D8D);

  // แผ่นกระจก
  static const glass55 = Color(0x8CFFFFFF);
  static const glass62 = Color(0x9EFFFFFF);
  static const glass72 = Color(0xB8FFFFFF);
  static const glass80 = Color(0xCCFFFFFF);
  static const glass85 = Color(0xD9FFFFFF);
  static const glassBorder = Color(0xE6FFFFFF);
  static const glassBorderSoft = Color(0xCCFFFFFF);

  // ก้อนแสงลอยพื้นหลัง
  static const orbPink = Color(0xFFFFB0D8);
  static const orbMint = Color(0xFF7FEDD6);
  static const orbLilac = Color(0xFFB0A8FF);
}

// ─────────────────────────────────────────────────────────────
//  เงา — ทุกเงาในดีไซน์ใช้ฐานสีม่วงเดียวกัน rgb(90,70,180)
// ─────────────────────────────────────────────────────────────
abstract final class MindShadows {
  static const _base = Color(0xFF5A46B4);

  static List<BoxShadow> soft() => [
        BoxShadow(
            color: _base.withValues(alpha: .08),
            blurRadius: 14,
            offset: const Offset(0, 4)),
      ];

  static List<BoxShadow> card() => [
        BoxShadow(
            color: _base.withValues(alpha: .12),
            blurRadius: 30,
            offset: const Offset(0, 10)),
      ];

  static List<BoxShadow> bubble() => [
        BoxShadow(
            color: _base.withValues(alpha: .16),
            blurRadius: 30,
            offset: const Offset(0, 10)),
      ];

  /// แผงแชทล่างสุด เงาพุ่งขึ้น
  static List<BoxShadow> dock() => [
        BoxShadow(
            color: _base.withValues(alpha: .14),
            blurRadius: 40,
            offset: const Offset(0, -2)),
      ];
}

// ─────────────────────────────────────────────────────────────
//  มุมโค้ง
// ─────────────────────────────────────────────────────────────
abstract final class MindRadius {
  static const bubbleTail = 6.0;
  static const control = 14.0;
  static const message = 16.0;
  static const avatarThumb = 18.0;
  static const bubble = 20.0;
  static const card = 24.0;
  static const panel = 26.0;
  static const pill = 99.0;
}

abstract final class MindSpace {
  static const screenX = 10.0;
  static const cardX = 14.0;
  static const gap = 8.0;

  /// จังหวะแนวตั้ง — ใช้ค่าจากบันไดนี้เท่านั้น อย่าพิมพ์เลขลอย ๆ
  ///
  /// ก่อนหน้านี้ระยะห่างในแอปมี 8/10/12/14/16 ปนกันโดยไม่มีเหตุผล
  /// สายตาอ่านจังหวะที่ไม่สม่ำเสมอออกแม้บอกไม่ถูกว่าอะไรผิด
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  /// ความสูงของทุกอย่างที่กดได้ — ต่ำกว่านี้นิ้วโป้งพลาด
  /// (Material บอก 48 · เราใช้ 44 แล้วเผื่อ hit area ด้วย padding รอบนอก)
  static const tapHeight = 44.0;
}

// ─────────────────────────────────────────────────────────────
//  บันไดตัวอักษร
//
//  ปัญหาเดิมคือทุกอย่างอยู่ในช่วง 10–20px น้ำหนักใกล้กันหมด ตาจึงไม่รู้ว่า
//  ต้องอ่านอะไรก่อน · แก้ด้วยการถ่างช่วงให้ห่างจริง และให้แต่ละขั้นมีหน้าที่
//  ชัดเจนหนึ่งอย่าง ไม่ใช่ไล่ขนาดลงไปเฉย ๆ
// ─────────────────────────────────────────────────────────────
abstract final class MindType {
  /// หัวจอ — มีจอละหนึ่งอันเท่านั้น
  static const display = TextStyle(
    fontSize: 26,
    height: 1.24,
    fontWeight: FontWeight.w700,
    letterSpacing: -.4,
    color: MindColors.ink,
  );

  /// หัวข้อในการ์ด / ชื่อรายการ
  static const title = TextStyle(
    fontSize: 15,
    height: 1.36,
    fontWeight: FontWeight.w600,
    letterSpacing: -.1,
    color: MindColors.ink,
  );

  /// เนื้อความ
  static const body = TextStyle(
    fontSize: 13.5,
    height: 1.52,
    fontWeight: FontWeight.w400,
    color: MindColors.ink75,
  );

  /// คำอธิบายใต้เนื้อความ
  static const caption = TextStyle(
    fontSize: 12,
    height: 1.44,
    fontWeight: FontWeight.w400,
    color: MindColors.ink55,
  );

  /// ป้ายหมวด — ตัวเล็กแต่ **หนาและถ่างตัว** ไม่ใช่ตัวเล็กแล้วจาง
  /// ป้ายที่จางคือป้ายที่ไม่มีใครอ่าน แล้วโครงของหน้าก็หายไปด้วย
  static const overline = TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.1,
    color: MindColors.ink55,
  );

  /// ตัวหนังสือบนปุ่ม
  static const button = TextStyle(
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: .1,
  );
}

// ─────────────────────────────────────────────────────────────
//  พื้นหลังไล่สีของแต่ละหน้าจอ (ตรงตาม 2a–2g)
// ─────────────────────────────────────────────────────────────
abstract final class MindGradients {
  static const home = LinearGradient(
    begin: Alignment(-0.26, -1),
    end: Alignment(0.26, 1),
    colors: [Color(0xFFFFF2E4), Color(0xFFF1E9FF), Color(0xFFE2F8FF)],
    stops: [0, .46, 1],
  );

  static const incomingCall = LinearGradient(
    begin: Alignment(-0.17, -1),
    end: Alignment(0.17, 1),
    colors: [Color(0xFFFFE9F2), Color(0xFFF3E9FF), Color(0xFFE6F9FF)],
    stops: [0, .44, 1],
  );

  static const outgoingCall = LinearGradient(
    begin: Alignment(-0.17, -1),
    end: Alignment(0.17, 1),
    colors: [Color(0xFFE8FBF4), Color(0xFFEEF0FF), Color(0xFFFFF0E8)],
    stops: [0, .48, 1],
  );

  static const mail = LinearGradient(
    begin: Alignment(-0.09, -1),
    end: Alignment(0.09, 1),
    colors: [Color(0xFFFFF3E8), Color(0xFFF4ECFF), Color(0xFFE8F8FF)],
    stops: [0, .40, 1],
  );

  static const calendar = LinearGradient(
    begin: Alignment(-0.09, -1),
    end: Alignment(0.09, 1),
    colors: [Color(0xFFEAF7FF), Color(0xFFF2ECFF), Color(0xFFFFEEF6)],
    stops: [0, .46, 1],
  );

  static const timeline = LinearGradient(
    begin: Alignment(-0.09, -1),
    end: Alignment(0.09, 1),
    colors: [Color(0xFFF4F0FF), Color(0xFFEAF9F4), Color(0xFFFFF4EA)],
    stops: [0, .50, 1],
  );

  static const settings = LinearGradient(
    begin: Alignment(-0.09, -1),
    end: Alignment(0.09, 1),
    colors: [Color(0xFFFFEEF5), Color(0xFFF1ECFF), Color(0xFFE9F9FF)],
    stops: [0, .48, 1],
  );
}

// ─────────────────────────────────────────────────────────────
//  โหมด งาน / ส่วนตัว — แกนกลางของทั้งแอป
//  สลับทีเดียวเปลี่ยนทั้งสี ชิปคำถาม และน้ำเสียงที่มายด์ตอบ
// ─────────────────────────────────────────────────────────────
/// โหมดที่มีผลจริง — ป้ายที่ผู้ใช้เห็นอยู่ใน i18n/enum_labels.dart
/// enum เก็บแค่ตัวตน ไม่เก็บข้อความ ไม่งั้นแปลไม่ได้
enum MindMode {
  work,
  love;

  bool get isWork => this == MindMode.work;
}

extension MindModePalette on MindMode {
  Color get accent =>
      isWork ? const Color(0xFF00A894) : const Color(0xFFE0357A);

  /// gradient ของปุ่มส่ง / pill ที่เลือกอยู่ / ฟองข้อความของเธอ
  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isWork
            ? const [Color(0xFF00C2A8), Color(0xFF7C6CFF)]
            : const [Color(0xFFFF6FAE), Color(0xFF7C6CFF)],
      );

  /// ใช้เป็นสีเงาเรืองใต้ปุ่มส่ง และสีวงแหวนรอบอวาตาร์
  Color get accentSoft => isWork
      ? const Color(0xFF00C2A8).withValues(alpha: .45)
      : const Color(0xFFFF6FAE).withValues(alpha: .45);

  /// ฟองข้อความฝั่งมายด์ โปร่งกว่า gradient ปุ่มเล็กน้อย
  LinearGradient get bubbleGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isWork
            ? [
                const Color(0xFF00C2A8).withValues(alpha: .90),
                const Color(0xFF7C6CFF).withValues(alpha: .85)
              ]
            : [
                const Color(0xFFFF6FAE).withValues(alpha: .92),
                const Color(0xFF7C6CFF).withValues(alpha: .85)
              ],
      );

  MindMode get opposite => isWork ? MindMode.love : MindMode.work;
}

// ─────────────────────────────────────────────────────────────
//  ฟิลเตอร์กระจก — CSS ใช้ blur() + saturate() คู่กัน
//  Flutter ต้อง compose เอง ไม่งั้นจะได้กระจกซีดกว่าดีไซน์
// ─────────────────────────────────────────────────────────────
abstract final class MindGlass {
  /// blur 14 saturate 1.5 — ฟองคำพูด, การ์ด
  static ImageFilter get light => filter(blur: 14, saturation: 1.5);

  /// blur 16 saturate 1.5 — การ์ดสายเข้า
  static ImageFilter get medium => filter(blur: 16, saturation: 1.5);

  /// blur 20 saturate 1.6 — แผงแชทล่างสุด
  static ImageFilter get heavy => filter(blur: 20, saturation: 1.6);

  static ImageFilter filter(
          {required double blur, required double saturation}) =>
      ImageFilter.compose(
        outer: ColorFilter.matrix(_saturationMatrix(saturation)),
        inner: ImageFilter.blur(sigmaX: blur / 2, sigmaY: blur / 2),
      );

  /// CSS saturate() ใช้ luminance ตาม Rec.709
  static List<double> _saturationMatrix(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final ir = 1 - s;
    return <double>[
      lr * ir + s, lg * ir, lb * ir, 0, 0, //
      lr * ir, lg * ir + s, lb * ir, 0, 0, //
      lr * ir, lg * ir, lb * ir + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }
}
