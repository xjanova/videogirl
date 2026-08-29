import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// ก้อนแสงเบลอที่ลอยอยู่หลังทุกอย่าง — คือหัวใจของธีม Liquid Glass
/// ตรงกับ `@keyframes liqDrift` ใน artboard: เลื่อน (16,-20) และขยาย 1.14 ที่กลางรอบ
@immutable
class Orb {
  const Orb({
    required this.color,
    required this.diameter,
    required this.seconds,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.drifts = true,
  });

  final Color color;
  final double diameter;

  /// ความยาวหนึ่งรอบของ liqDrift แต่ละก้อนตั้งไม่เท่ากันเพื่อไม่ให้ขยับพร้อมกัน
  final int seconds;

  final double? left, top, right, bottom;

  /// บางหน้าจอ (2b เป็นต้นไป) ก้อนแสงอยู่นิ่ง มีแต่หน้าหลักที่ลอย
  final bool drifts;

  // ชุดก้อนแสงประจำแต่ละหน้าจอ ถอดจาก artboard ตรง ๆ
  static const home = <Orb>[
    Orb(color: MindeColors.orbPink, diameter: 280, left: -60, top: -70, seconds: 14),
    Orb(color: MindeColors.orbMint, diameter: 300, right: -100, top: 150, seconds: 18),
    Orb(color: MindeColors.orbLilac, diameter: 280, left: -60, bottom: 20, seconds: 16),
  ];

  static const mail = <Orb>[
    Orb(color: Color(0xFFFFC48C), diameter: 300, right: -70, top: -90, seconds: 15, drifts: false),
    Orb(color: Color(0xFFA8B6FF), diameter: 300, left: -90, bottom: 0, seconds: 17, drifts: false),
  ];

  static const calendar = <Orb>[
    Orb(color: Color(0xFF8CD8FF), diameter: 300, left: -80, top: -80, seconds: 15, drifts: false),
    Orb(color: Color(0xFFFFA8D0), diameter: 300, right: -90, bottom: 40, seconds: 17, drifts: false),
  ];

  static const timeline = <Orb>[
    Orb(color: MindeColors.orbLilac, diameter: 300, right: -80, top: -60, seconds: 15, drifts: false),
    Orb(color: MindeColors.orbMint, diameter: 300, left: -80, bottom: 0, seconds: 17, drifts: false),
  ];

  static const settings = <Orb>[
    Orb(color: Color(0xFFFFA8C8), diameter: 300, left: -80, top: -70, seconds: 15, drifts: false),
    Orb(color: Color(0xFF9CC4FF), diameter: 300, right: -90, bottom: 20, seconds: 17, drifts: false),
  ];
}

class LiquidBackground extends StatefulWidget {
  const LiquidBackground({
    super.key,
    required this.gradient,
    required this.orbs,
    required this.child,
  });

  final Gradient gradient;
  final List<Orb> orbs;
  final Widget child;

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  /// รอบร่วมของ 14/16/18 วินาที = 504 วิ ใช้ตัวเดียวคุมทุกก้อนได้โดยไม่หลุดจังหวะ
  static const _sharedPeriod = Duration(seconds: 504);

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(vsync: this, duration: _sharedPeriod);
    if (widget.orbs.any((o) => o.drifts)) _drift.repeat();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: widget.gradient),
      child: Stack(
        children: [
          // ก้อนแสงวาดรวมใน painter เดียว ถูกกว่าซ้อน widget + ImageFiltered ทีละก้อนมาก
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _drift,
                builder: (_, _) => CustomPaint(
                  painter: _OrbPainter(
                    orbs: widget.orbs,
                    elapsedSeconds: _drift.value * _sharedPeriod.inSeconds,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(child: widget.child),
        ],
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter({required this.orbs, required this.elapsedSeconds});

  final List<Orb> orbs;
  final double elapsedSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    for (final orb in orbs) {
      final r = orb.diameter / 2;

      // แปลง left/top/right/bottom ของ CSS เป็นจุดศูนย์กลาง
      final cx = orb.left != null
          ? orb.left! + r
          : orb.right != null
              ? size.width - orb.right! - r
              : size.width / 2;
      final cy = orb.top != null
          ? orb.top! + r
          : orb.bottom != null
              ? size.height - orb.bottom! - r
              : size.height / 2;

      var center = Offset(cx, cy);
      var scale = 1.0;

      if (orb.drifts) {
        // liqDrift เป็น ease-in-out ไป-กลับ ใช้โคไซน์ให้ได้เส้นโค้งเดียวกัน
        final t = (1 - math.cos(2 * math.pi * (elapsedSeconds / orb.seconds))) / 2;
        center += Offset(16 * t, -20 * t);
        scale = 1 + .14 * t;
      }

      final radius = r * scale;
      final rect = Rect.fromCircle(center: center, radius: radius);

      // radial-gradient(circle, สี 0%, โปร่งใส 70%) — ขอบฟุ้งมาจาก gradient เอง
      // ไม่ต้องพึ่ง ImageFilter.blur ซึ่งกิน GPU หนักบนเครื่องกลาง ๆ
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [orb.color, orb.color.withValues(alpha: 0)],
            stops: const [0, .7],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.elapsedSeconds != elapsedSeconds || old.orbs != orbs;
}
