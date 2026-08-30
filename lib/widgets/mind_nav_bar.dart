import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// แถบนำทางล่างจอ — เต็มความกว้าง มีหน้ามายด์เป็นปุ่มกลาง
///
/// สามอย่างที่ทำให้แถบนี้ต่างจากแถบลอยแบบเดิม:
///
///  1. ไม่มี margin และไม่ถูกห่อด้วย SafeArea — กระจกวิ่งไปชนขอบจอทั้งสามด้าน
///     แล้ว *ดูด* ระยะปลอดภัยล่างเข้ามาเป็น padding ของตัวเอง ปุ่มจึงลอยเหนือ
///     แถบเลื่อนของระบบ ส่วนกระจกยังไหลลงไปอยู่ใต้มันตามภาษาของ Liquid Glass
///     ใช้ MediaQuery.paddingOf ไม่ใช่ viewPaddingOf โดยตั้งใจ: ตอนคีย์บอร์ดเด้ง
///     padding.bottom จะกลายเป็น 0 เอง ซึ่งถูกแล้ว เพราะตอนนั้นแถบถูกดันขึ้นมา
///     อยู่เหนือคีย์บอร์ด ไม่ได้อยู่ติดแถบเลื่อนอีกต่อไป
///
///  2. ตัววิดเจ็ต *สูงกว่า* แผ่นกระจกอยู่ [lift] พิกเซล ช่องว่างโปร่งด้านบนนั้น
///     คือที่ยืนของปุ่มกลาง ถ้าปล่อยให้ปุ่มล้นออกนอกกล่องแทน มันจะยังวาดออกมา
///     ให้เห็นก็จริง แต่ Flutter จะไม่ส่ง hit test ไปนอกกรอบของ parent
///     ครึ่งบนของปุ่มจะกดไม่ได้เลยโดยไม่มีอะไรฟ้อง
///
///  3. ปุ่มกลางอยู่กึ่งกลางแนวนอนพอดี (Alignment.center) ได้ก็ต่อเมื่อจำนวนแท็บ
///     เป็นเลขคี่และมันอยู่ช่องกลาง — มี assert กันไว้ใน build
class MindNavBar extends StatelessWidget {
  const MindNavBar({
    super.key,
    required this.items,
    required this.current,
    required this.centerIndex,
    required this.mode,
    required this.onSelect,
    this.face,
    this.avatarReady = false,
    this.speaking = false,
    this.onCenterReselect,
  });

  /// ความสูงของแผ่นกระจก ไม่รวมระยะปลอดภัยล่าง
  static const double barHeight = 58;

  /// เส้นผ่านศูนย์กลางของปุ่มหน้ามายด์
  static const double faceSize = 56;

  /// ปุ่มกลางโผล่พ้นขอบบนของแผ่นกระจกเท่าไร
  static const double lift = 16;

  /// แท็บทั้งหมด *เรียงตามที่จะเห็นบนจอ* (ไม่ใช่ตามลำดับใน IndexedStack)
  final List<MindNavItem> items;

  /// ดัชนีหน้าจอที่เปิดอยู่
  final int current;

  /// ดัชนีหน้าจอที่จะกลายเป็นปุ่มหน้ามายด์ตรงกลาง
  final int centerIndex;

  final MindMode mode;
  final ValueChanged<int> onSelect;

  /// รูปหน้าของเธอ — ปล่อย null ได้ จะตกไปใช้ไอคอนแทนโดยไม่พัง
  final ImageProvider? face;

  /// VRM ขึ้นเวทีแล้วหรือยัง ใช้กับจุดสถานะมุมล่างขวาของปุ่มกลาง
  final bool avatarReady;

  /// กำลังพูดอยู่ไหม ใช้กับวงแหวนที่กระเพื่อมออก
  final bool speaking;

  /// กดปุ่มกลางซ้ำตอนอยู่หน้ามายด์อยู่แล้ว (เช่น โฟกัสช่องพิมพ์ / เปิดไมค์)
  final VoidCallback? onCenterReselect;

  @override
  Widget build(BuildContext context) {
    assert(items.length.isOdd && items.length >= 3,
        'ปุ่มกลางจะอยู่กึ่งกลางจริงก็ต่อเมื่อจำนวนแท็บเป็นเลขคี่');
    assert(items[items.length ~/ 2].index == centerIndex,
        'ปุ่มกลางต้องถูกวางไว้ช่องกลางของ items ด้วย');

    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return SizedBox(
      height: lift + barHeight + safeBottom,
      child: Stack(
        // วงแหวนตอนพูดขยายเลยกรอบปุ่มออกไป ถ้าปล่อยให้ clip มันจะโดนตัดเป็นสี่เหลี่ยม
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _NotchedGlass(
              // ทึบขึ้นกว่าค่าเริ่มต้นหนึ่งขั้น เพราะตอนนี้ข้างหลังเป็นเนื้อหาจริง
              // (extendBody) ไม่ใช่พื้นเปล่าเหมือนแถบลอยแบบเดิม
              padding: EdgeInsets.only(bottom: safeBottom),
              child: SizedBox(
                height: barHeight,
                child: Row(
                  children: [
                    for (final item in items)
                      Expanded(
                        child: item.index == centerIndex
                            // ช่องว่างจองที่ให้ปุ่มกลาง ตัวปุ่มจริงลอยอยู่ใน Stack
                            ? const SizedBox.shrink()
                            : _NavItem(
                                item: item,
                                selected: item.index == current,
                                mode: mode,
                                onTap: () => onSelect(item.index),
                              ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: safeBottom + barHeight - (faceSize - lift),
            child: Center(
              child: _MindFaceButton(
                size: faceSize,
                mode: mode,
                selected: current == centerIndex,
                face: face,
                ready: avatarReady,
                speaking: speaking,
                label: items[items.length ~/ 2].label,
                onTap: () => current == centerIndex
                    ? onCenterReselect?.call()
                    : onSelect(centerIndex),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// แผ่นกระจกของแถบล่าง ที่ขอบบน **เว้าโค้งรับปุ่มกลาง**
///
/// ทำไมไม่ใช้ GlassPanel เหมือนที่อื่น: มันตัดด้วย `ClipRRect` ซึ่งได้แค่
/// สี่เหลี่ยมมุมโค้ง · รอยเว้าเป็นส่วนโค้งของวงกลมที่ **กินเข้าไปในแผ่น**
/// ต้องใช้ `Path` ของตัวเอง
///
/// ก่อนหน้านี้ปุ่มหน้ามายด์ลอยทับขอบตรง ๆ เห็นเป็นวงกลมวางบนแถบ
/// เว้าให้รับกันแล้วมันกลายเป็นชิ้นเดียวกัน — ปุ่มโผล่ออกมาจากแถบ
/// ไม่ใช่ของสองชิ้นที่บังเอิญมาซ้อนกัน
class _NotchedGlass extends StatelessWidget {
  const _NotchedGlass({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      // เงาต้องวาดตาม path เดียวกัน ไม่งั้นจะเห็นเงาสี่เหลี่ยมโผล่ตรงรอยเว้า
      painter: const _NotchShadow(),
      child: ClipPath(
        clipper: const _NotchClipper(),
        child: BackdropFilter(
          filter: MindGlass.heavy,
          child: DecoratedBox(
            decoration: const BoxDecoration(color: MindColors.glass72),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// รูปทรงของแผ่น — มุมบนโค้ง ล่างชนขอบจอ และเว้าเป็นวงกลมตรงกลาง
///
/// แยกเป็นฟังก์ชันเดียวที่ทั้งตัวตัดและตัววาดเงาเรียกใช้ ไม่งั้นสองอย่างนี้
/// จะค่อย ๆ เพี้ยนออกจากกันจนเห็นขอบเงาโผล่พ้นกระจก
Path _navBarPath(Size size) {
  const r = MindRadius.card;

  // จุดศูนย์กลางของรอยเว้า = จุดศูนย์กลางของปุ่มกลางพอดี
  // ปุ่มโผล่พ้นขอบบน [lift] พิกเซล ศูนย์กลางจึงอยู่ **เหนือ** ขอบบน
  // เท่ากับ (เส้นผ่านศูนย์กลาง/2 − lift)
  final cx = size.width / 2;
  final cy = -(MindNavBar.faceSize / 2 - MindNavBar.lift);

  /// เผื่อช่องว่างรอบปุ่มไว้ ไม่ให้ขอบกระจกไปแตะตัวปุ่มพอดีเป๊ะ
  const gap = 7.0;
  const nr = MindNavBar.faceSize / 2 + gap;

  final path = Path();

  // ครึ่งความกว้างของรอยเว้าตรงระดับขอบบน — จากพีทาโกรัส
  // วงกลมรัศมี nr ศูนย์กลางอยู่เหนือขอบ |cy| จะตัดขอบที่ ±√(nr²−cy²)
  final dy = cy.abs();
  final half = nr > dy ? math.sqrt(nr * nr - dy * dy) : 0.0;

  path
    ..moveTo(0, r)
    ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
    ..lineTo(cx - half, 0);

  if (half > 0) {
    final start = math.atan2(dy, -half);
    final end = math.atan2(dy, half);
    path.arcTo(
      Rect.fromCircle(center: Offset(cx, cy), radius: nr),
      start,
      end - start,
      false,
    );
  }

  path
    ..lineTo(size.width - r, 0)
    ..arcToPoint(Offset(size.width, r), radius: const Radius.circular(r))
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  return path;
}

class _NotchClipper extends CustomClipper<Path> {
  const _NotchClipper();

  @override
  Path getClip(Size size) => _navBarPath(size);

  @override
  bool shouldReclip(_NotchClipper oldClipper) => false;
}

class _NotchShadow extends CustomPainter {
  const _NotchShadow();

  @override
  void paint(Canvas canvas, Size size) {
    final path = _navBarPath(size);
    canvas.drawShadow(path, const Color(0xFF5A46B4), 12, true);
  }

  @override
  bool shouldRepaint(_NotchShadow oldDelegate) => false;
}

/// หนึ่งแท็บ — `index` คือดัชนีใน IndexedStack ไม่ใช่ตำแหน่งบนแถบ
/// แยกสองอย่างนี้ออกจากกันเพื่อให้ย้ายตำแหน่งปุ่มบนแถบได้โดยไม่ต้องสลับหน้าจอ
@immutable
class MindNavItem {
  const MindNavItem({
    required this.index,
    required this.label,
    required this.icon,
    this.asset,
  });

  final int index;
  final String label;

  /// ไอคอนสำรอง — ใช้เมื่อไม่มี [asset] หรือโหลดภาพไม่ขึ้น
  ///
  /// เก็บไว้เสมอ ไม่ตัดทิ้ง เพราะภาพเป็นไฟล์ที่หายได้ (แพ็กตกหล่น ไฟล์เสีย)
  /// แถบนำทางที่ไอคอนหายไปคือแถบที่ใช้ไม่ได้เลย
  final IconData icon;

  /// ภาพไอคอน 3D แบบลิควิด เจนจาก Magnific — ดู assets/brand/nav/
  final String? asset;
}

// ─────────────────────────────────────────────────────────────
//  แท็บธรรมดา — หน้าตาเดิมทุกอย่าง ย้ายออกมาเป็นวิดเจ็ตของตัวเอง
// ─────────────────────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.mode,
    required this.onTap,
  });

  final MindNavItem item;
  final bool selected;
  final MindMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // กดซ้ำแท็บเดิมไม่ทำอะไร — setState ซ้ำ ๆ ตอนรัวนิ้วไม่มีประโยชน์
        onTap: selected ? null : onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              // พิลล์สีจาง ไม่ใช่บล็อกไล่สีทึบ
              //
              // ทั้งแอปเป็นแผ่นกระจกใส ๆ สี่เหลี่ยมทึบสีเข้มบนแถบล่างจึงเป็น
              // ก้อนที่หนักที่สุดในจอ ทั้งที่หน้าที่มันมีคือ "บอกว่าอยู่ตรงไหน"
              // สีจางบวกไอคอนสีเน้นบอกได้เท่ากันโดยไม่แย่งสายตาจากเนื้อหา
              color: selected ? mode.accent.withValues(alpha: .13) : null,
              borderRadius: BorderRadius.circular(MindRadius.avatarThumb),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 3,
              children: [
                // ไอคอนภาพเป็นสีของตัวเอง (ม่วง-ชมพูลิควิด) ย้อมตามโหมดไม่ได้
                // จึงแยกที่เลือกอยู่ด้วย **ความทึบ** แทนสี — ตัวที่ไม่ได้เลือก
                // จางลงจนถอยไปเป็นฉากหลัง ตัวที่เลือกเต็มสีและมีพิลล์รอง
                if (item.asset != null)
                  SizedBox(
                    // ใหญ่กว่าไอคอนเส้นเดิม (18) เพราะไอคอน 3D มีขอบ มีเงา
                    // และมีที่ว่างรอบตัวในภาพ ขนาดเท่ากันจะเห็นสัญลักษณ์
                    // ข้างในเล็กจนอ่านไม่ออก
                    width: 26,
                    height: 26,
                    child: Opacity(
                      opacity: selected ? 1 : .48,
                      child: Image.asset(
                        item.asset!,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (_, _, _) => Icon(
                          item.icon,
                          size: 18,
                          color: selected ? mode.accent : MindColors.ink50,
                        ),
                      ),
                    ),
                  )
                else
                  Icon(
                    item.icon,
                    size: 18,
                    color: selected ? mode.accent : MindColors.ink50,
                  ),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? mode.accent : MindColors.ink50,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  ปุ่มกลาง — หน้าเธอ
// ─────────────────────────────────────────────────────────────
/// ทำไมถึงเป็นภาพนิ่ง ไม่ใช่ภาพสดจากเวที: อวาตาร์เรนเดอร์อยู่ใน WebView
/// ฝั่ง Flutter อ่านพิกเซลจาก platform view ไม่ได้ และต่อให้แคปได้ WebView
/// ก็ถูกซ่อนอยู่ใต้ IndexedStack ตอนอยู่แท็บอื่น ภาพที่ได้จะค้างหรือว่างเปล่า
/// ดู [MindNavBar.face] — ตัวปุ่มรับ ImageProvider อะไรก็ได้ ถ้าวันหนึ่งแคปสำเร็จ
/// แล้วเก็บเป็นไฟล์ ก็ส่ง FileImage เข้ามาแทนได้โดยไม่ต้องแก้ปุ่ม
class _MindFaceButton extends StatefulWidget {
  const _MindFaceButton({
    required this.size,
    required this.mode,
    required this.selected,
    required this.face,
    required this.ready,
    required this.speaking,
    required this.label,
    required this.onTap,
  });

  final double size;
  final MindMode mode;
  final bool selected;
  final ImageProvider? face;
  final bool ready;
  final bool speaking;
  final String label;
  final VoidCallback onTap;

  @override
  State<_MindFaceButton> createState() => _MindFaceButtonState();
}

class _MindFaceButtonState extends State<_MindFaceButton>
    with SingleTickerProviderStateMixin {
  /// จังหวะเดียวกับ liqRing ในหน้าหลัก — ขยายออกแล้วจางหาย
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _MindFaceButton old) {
    super.didUpdateWidget(old);
    if (old.speaking != widget.speaking) _sync();
  }

  /// หยุดจริง ๆ ตอนไม่ได้พูด — วงแหวนที่หมุนเปล่าคือ 60fps ที่กินแบตฟรี
  void _sync() {
    if (widget.speaking) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // ① คลื่นตอนพูด — วาดอยู่หลังสุด ขยายเลยขอบปุ่มออกไป
              Positioned.fill(child: _halo(mode)),

              // ② วงแหวนไล่สีตามโหมด + ③ หน้าเธอ
              AnimatedScale(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                scale: widget.selected ? 1 : .94,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: mode.gradient,
                    boxShadow: [
                      ...MindShadows.card(),
                      // เรืองสีโหมดเฉพาะตอนเลือกอยู่ — คือสัญญาณ "เลือกแล้ว"
                      // ที่ไม่ต้องไปแตะสีของวงแหวนหรือหน้าเธอเลย
                      if (widget.selected)
                        BoxShadow(
                          color: mode.accentSoft,
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                    ],
                  ),
                  child: ClipOval(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: MindColors.glass85,
                        shape: BoxShape.circle,
                      ),
                      child: _face(mode),
                    ),
                  ),
                ),
              ),

              // ④ จุดสถานะ — เธอขึ้นเวทีแล้วหรือยัง
              Positioned(right: 2, bottom: 2, child: _dot(mode)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _halo(MindMode mode) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final t = _pulse.value;
          return Opacity(
            opacity: widget.speaking ? (1 - t) * .9 : 0,
            child: Transform.scale(
              scale: 1 + .30 * t,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mode.accentSoft,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// ภาพหาย ไฟล์ยังไม่ถูกวาง หรือ decode พัง — ตกมาที่ไอคอนเสมอ
  /// แถบนำทางห้ามพังเพราะรูปหนึ่งใบ
  Widget _face(MindMode mode) {
    final img = widget.face;
    if (img == null) return _glyph(mode);
    return Image(
      image: img,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) => _glyph(mode),
    );
  }

  Widget _glyph(MindMode mode) => Center(
        child: Icon(
          Icons.face_retouching_natural_rounded,
          size: 26,
          color: mode.accent,
        ),
      );

  Widget _dot(MindMode mode) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.ready ? mode.accent : MindColors.ink22,
          border: Border.all(color: MindColors.glass85, width: 2),
        ),
      );
}
