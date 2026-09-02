/// สัญญาณว่า "เธอกำลังคิดอยู่"
///
/// 🔴 ช่วงนี้คือช่วงที่**เงียบที่สุดของทั้งแอป และยาวที่สุดด้วย**
///
/// สมองในเครื่องบนมือถือใช้เวลาหลายวินาทีต่อคำตอบหนึ่งคำตอบ (E2B บนชิปกลาง ๆ
/// วัดได้ราว 4–12 วิ) ส่วนพร็อกซีกับเซิร์ฟเวอร์ในบ้านก็หลักวินาทีเหมือนกัน
/// ของเดิมระหว่างนั้นมีแค่ปุ่มส่งจางลง 50% ซึ่งบนกระจกที่โปร่งอยู่แล้ว
/// แทบไม่ต่างจากเดิม — ผลคือคนกดส่งแล้วไม่รู้ว่าติดหรือไม่ติด แล้วกดซ้ำ
/// (กดซ้ำถูกกันไว้ที่ state แต่ **ความรู้สึกว่าแอปค้าง** ไม่มีอะไรกันไว้เลย)
///
/// ทุกจุดที่โชว์สัญญาณนี้ใช้จังหวะเดียวกันหมด เพราะสองจังหวะที่ไม่ตรงกัน
/// บนจอเดียวอ่านเป็นความสับสน ไม่ใช่ความมีชีวิต
library;

import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../theme/tokens.dart';

/// จังหวะหนึ่งรอบของจุดสามจุด
///
/// 1100 มิลลิวินาทีมาจากการชั่ง: เร็วกว่านี้อ่านเป็นความรีบร้อน/กระวนกระวาย
/// ช้ากว่านี้อ่านเป็นแอปค้าง ซึ่งเป็นสิ่งเดียวที่อนิเมชั่นนี้มีหน้าที่ปฏิเสธ
const _cycle = Duration(milliseconds: 1100);

/// จุดสามจุดที่ลอยขึ้นแล้วจางลงไล่กันไป
///
/// เหลื่อมกันจุดละ .16 ของรอบ — น้อยกว่านี้จะดูเหมือนขยับพร้อมกันทั้งสามจุด
/// มากกว่านี้จะขาดเป็นจุดเดียววิ่งไปมา ไม่ใช่กลุ่มเดียวกัน
class ThinkingDots extends StatefulWidget {
  const ThinkingDots({
    super.key,
    required this.color,
    this.size = 6,
    this.gap = 5,
  });

  final Color color;
  final double size;
  final double gap;

  @override
  State<ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<ThinkingDots>
    with SingleTickerProviderStateMixin {
  /// 🔴 สร้างใน [initState] ไม่ใช่ `late final ... = AnimationController(...)`
  ///
  /// ตัวหลังจะถูกสร้าง**ตอนที่มีคนอ่านครั้งแรก** ซึ่งในทางที่ปิดอนิเมชั่นไว้
  /// คือไม่มีใครอ่านเลยตลอดอายุของวิดเจ็ต · แล้ว `dispose()` จะกลายเป็นคน
  /// อ่านคนแรก = สร้าง AnimationController ขึ้นมาตอนกำลังถอดออกจากต้นไม้
  /// ซึ่งต้องไปหา TickerMode ของ ancestor ที่ตายไปแล้ว (เจอตอนเขียนเทสต์)
  late final AnimationController _c;

  /// ผู้ใช้ปิดอนิเมชั่นในตั้งค่าเครื่องไว้ไหม
  ///
  /// อ่านจาก MediaQuery จึงต้องอยู่ใน [didChangeDependencies] — ค่านี้
  /// เปลี่ยนได้ระหว่างแอปเปิดอยู่ (ผู้ใช้สลับในตั้งค่าเครื่องแล้วกลับมา)
  bool _still = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _cycle);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ผู้ที่ปิดอนิเมชั่นมักปิดเพราะการเคลื่อนไหวทำให้เวียนหัวหรือไมเกรนกำเริบ
    // จุดที่ขยับวนไม่จบเป็นตัวที่รบกวนที่สุดในกลุ่มนี้ · หยุดนาฬิกาไปเลย
    // ไม่ใช่แค่ไม่วาด ไม่งั้นยังกินเฟรมอยู่เงียบ ๆ ตลอดเวลา
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0→1→0 หนึ่งลูก ต่อหนึ่งจุด ตามเฟสของมัน
  ///
  /// ใช้เส้นโค้งสามเหลี่ยมแล้วดัดด้วย easeInOut แทน sine เพราะจุดต้อง
  /// **พักอยู่ล่างสุดนานกว่าอยู่บนสุด** ไม่งั้นจะดูเหมือนเต้นอยู่ตลอดเวลา
  double _wave(double t, int index) {
    final phase = (t - index * .16) % 1.0;
    final up = phase < .5 ? phase * 2 : (1 - phase) * 2;
    return Curves.easeInOut.transform(up.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    // ปิดอนิเมชั่นแล้วยังต้องเห็นว่ามีสามจุดอยู่ แค่ให้มันนิ่ง
    final still = _still;

    return Semantics(
      liveRegion: true,
      label: S.of(context).thinkingLabel,
      child: SizedBox(
        height: widget.size * 2,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) SizedBox(width: widget.gap),
              if (still)
                _dot(1, .55)
              else
                AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) {
                    final v = _wave(_c.value, i);
                    return Transform.translate(
                      // ลอยขึ้นแค่ครึ่งหนึ่งของขนาดจุด · มากกว่านี้กลายเป็น
                      // ลูกบอลเด้ง ซึ่งเป็นคนละอารมณ์กับ "กำลังคิด"
                      offset: Offset(0, -widget.size * .5 * v),
                      child: _dot(.62 + .38 * v, .38 + .62 * v),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dot(double scale, double opacity) => Transform.scale(
        scale: scale,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: opacity),
          ),
        ),
      );
}

/// ฟองที่เธอ "กำลังพิมพ์" อยู่ในแผงแชท — หน้าตาเดียวกับฟองข้อความของเธอ
///
/// ใช้ gradient กับทรงเดียวกับ [MindMode.bubbleGradient] โดยตั้งใจ
/// เพราะสิ่งที่จะโผล่มาแทนที่มันคือฟองข้อความจริง · ทรงที่ต่างกันจะทำให้
/// จังหวะที่คำตอบมาถึงกลายเป็นการกระตุก แทนที่จะเป็นการเติมข้อความลงในที่เดิม
class ThinkingBubble extends StatelessWidget {
  const ThinkingBubble({super.key, required this.mode});

  final MindMode mode;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: mode.bubbleGradient,
          borderRadius: BorderRadius.circular(MindRadius.message),
          border: Border.all(color: const Color(0x80FFFFFF), width: 1),
          boxShadow: MindShadows.soft(),
        ),
        child: const ThinkingDots(color: Colors.white),
      ),
    );
  }
}

/// ฟองกำลังคิดเหนือหัวเธอบนเวที — ทรงเดียวกับ [SpeechBubble] ที่มันมาแทน
///
/// ต้องเป็นทรงกระจกเหมือนกัน ไม่ใช่ gradient แบบในแผงแชท เพราะบนเวที
/// ฟองลอยทับตัวเธอ ถ้าทึบจะบังหน้า
class ThinkingPuff extends StatelessWidget {
  const ThinkingPuff({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: MindColors.glass72,
        border: Border.all(color: MindColors.glassBorder, width: 1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(MindRadius.bubble),
          topRight: Radius.circular(MindRadius.bubble),
          bottomRight: Radius.circular(MindRadius.bubble),
          bottomLeft: Radius.circular(MindRadius.bubbleTail),
        ),
        boxShadow: MindShadows.bubble(),
      ),
      child: const ThinkingDots(color: MindColors.ink55, size: 7, gap: 6),
    );
  }
}
