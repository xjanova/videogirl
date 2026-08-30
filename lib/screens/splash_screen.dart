import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../i18n/strings.dart';
import '../theme/tokens.dart';

/// วิดีโอเปิดแอป — โลโก้ GigGok เคลื่อนไหว (720×1280 · 10 วินาที · h264+aac)
const _kSplashAsset = 'assets/brand/splash.mp4';

/// เปิดเสียงด้วยไหม — เจ้าของสั่งให้เล่นทั้งภาพและเสียง
///
/// ยังเปิด `mixWithOthers` ไว้ ไม่ใช่เพื่อความเงียบ แต่เพื่อไม่ให้ **หยุดเพลง
/// ที่ผู้ใช้ฟังอยู่** ตอนเปิดแอป · เสียงสติงดังทับเพลงได้ แต่ไม่ควรฆ่าเพลงทิ้ง
const _kSplashSound = true;

/// ถ้า `initialize()` ไม่คืบหน้าเลย ให้ผ่านไปเถอะ
///
/// ตั้งยาวกว่าความยาวคลิปมาก เพราะเงื่อนไขนี้มีไว้กันวิดีโอที่**เปิดไม่ขึ้นเลย**
/// ไม่ใช่ไว้ตัดวิดีโอที่กำลังเล่นอยู่ดี ๆ · ตัวจับเวลานี้ถูกยกเลิกทันทีที่
/// เฟรมแรกขึ้นจอ ดังนั้นคลิปที่ยาวกว่านี้ก็ไม่โดนตัด
const _kSplashGiveUp = Duration(seconds: 20);

/// สีพื้นก่อนเฟรมแรกมาถึง วัดจากขอบคลิปจริง (#FCFAF4)
const _kSplashBackdrop = Color(0xFFFCFAF4);

/// หน้าเปิดแอป — เล่นวิดีโอ**จนจบ** พร้อมเสียง
///
/// 🔴 บทเรียนที่วัดได้บนเครื่องจริง: ของเดิมไม่มีใครทันเห็นวิดีโอเลย
/// เพราะ `main()` รอโหลดของหนักก่อน `runApp` ทำให้จอขาวของ Android ค้าง
/// **10.2 วินาที** แล้ววิดีโอเพิ่งได้เริ่มตอนนั้น · ตอนนี้ `runApp` วาดทันที
/// แล้วของหนักไปโหลดข้างหลังระหว่างที่วิดีโอเล่น (ดู MindBootstrap)
///
/// **ไม่ตัดวิดีโอ** — จบเมื่อคลิปเล่นจบเท่านั้น (หรือผู้ใช้แตะข้ามเอง)
/// และถ้าคลิปจบก่อนที่แอปจะโหลดเสร็จ ก็ค้างหน้านี้ไว้ต่อ ดีกว่าโยนคนเข้าไป
/// เจอจอเปล่าที่ยังไม่มีอะไร
class MindSplash extends StatefulWidget {
  const MindSplash({
    super.key,
    required this.appReady,
    required this.onDone,
    this.loadPercent = 0,
  });

  /// ตัวเธอขึ้นจอพร้อมให้เห็นแล้วหรือยัง — ยังไม่พร้อมก็ยังไม่ปล่อยให้เข้าแอป
  ///
  /// เจ้าของสั่งว่าเข้าแอปแล้วต้องเห็นตัวเธอเลย ไม่ใช่โครงร่าง
  final bool appReady;

  /// ความคืบหน้าการโหลดจริง 0–100
  final int loadPercent;

  final VoidCallback onDone;

  @override
  State<MindSplash> createState() => _MindSplashState();
}

class _MindSplashState extends State<MindSplash> {
  VideoPlayerController? _video;
  Timer? _giveUp, _hint;
  bool _hintOn = false;
  bool _clipDone = false;
  bool _fading = false;

  @override
  void initState() {
    super.initState();
    _giveUp = Timer(_kSplashGiveUp, _finishClip);
    _start();
  }

  @override
  void didUpdateWidget(MindSplash old) {
    super.didUpdateWidget(old);
    // คลิปจบไปก่อนแล้ว แต่ตอนนั้นแอปยังโหลดไม่เสร็จ · พอเสร็จค่อยปล่อย
    if (widget.appReady && _clipDone) _leave();
  }

  Future<void> _start() async {
    final v = VideoPlayerController.asset(
      _kSplashAsset,
      // ไม่ฆ่าเพลงที่ผู้ใช้ฟังอยู่ · ต้องตั้งตั้งแต่ตอนสร้างตัวเล่น
      // จะมาตั้งทีหลังไม่ได้
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    try {
      await v.initialize();
    } catch (e) {
      // เปิดวิดีโอไม่ได้ไม่ใช่เหตุผลที่จะกันคนออกจากแอป
      debugPrint('splash: เปิดวิดีโอไม่ได้ — $e');
      _finishClip();
      unawaited(_closeQuietly(v));
      return;
    }

    if (!mounted) {
      unawaited(_closeQuietly(v));
      return;
    }

    await v.setVolume(_kSplashSound ? 1 : 0);
    await v.play();

    if (!mounted) {
      unawaited(_closeQuietly(v));
      return;
    }

    // เฟรมแรกขึ้นจอแล้ว ตัวปลดล็อกฉุกเฉินไม่จำเป็นอีกต่อไป
    // ถ้าไม่ยกเลิก คลิปที่ยาวกว่า 20 วิจะโดนตัดกลางคัน
    _giveUp?.cancel();
    _giveUp = null;
    setState(() => _video = v);

    // จบเมื่อ**คลิปเล่นจบจริง** ไม่ใช่ตามนาฬิกาที่เราตั้งเอง
    //
    // ใช้ตำแหน่งเทียบความยาวแทน onEnded เพราะ video_player ไม่มี callback
    // ตอนจบ มีแต่ค่าใน value ที่ต้องคอยดู
    v.addListener(_watch);

    _hint = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _hintOn = true);
    });
  }

  void _watch() {
    final v = _video;
    if (v == null || _clipDone) return;
    final value = v.value;
    if (!value.isInitialized) return;
    // เผื่อปลายไว้เล็กน้อย — บางตัวถอดรหัสหยุดก่อนถึงมิลลิวินาทีสุดท้ายพอดี
    final ended = !value.isPlaying &&
        value.position >= value.duration - const Duration(milliseconds: 250);
    if (ended) _finishClip();
  }

  /// คลิปจบแล้ว — แต่จะออกจากหน้านี้ได้ก็ต่อเมื่อแอปพร้อมด้วย
  void _finishClip() {
    if (_clipDone) return;
    _giveUp?.cancel();
    _hint?.cancel();
    // setState เพราะหน้าต้องสลับจากวิดีโอไปเป็นโลโก้นิ่ง + แถบความคืบหน้า
    if (mounted) {
      setState(() => _clipDone = true);
    } else {
      _clipDone = true;
    }
    if (widget.appReady) _leave();
  }

  void _leave() {
    if (_fading || !mounted) return;
    setState(() => _fading = true);
  }

  Future<void> _closeQuietly(VideoPlayerController v) async {
    try {
      await v.dispose();
    } catch (e) {
      debugPrint('splash: ปิดตัวเล่นไม่สำเร็จ — $e');
    }
  }

  @override
  void dispose() {
    _giveUp?.cancel();
    _hint?.cancel();
    final v = _video;
    if (v != null) {
      v.removeListener(_watch);
      unawaited(_closeQuietly(v));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;

    return IgnorePointer(
      // ระหว่างจาง ปิดการรับสัมผัส ไม่งั้นนิ้วทะลุไปโดนแถบนำทางของเชลล์
      // ที่ยังมองแทบไม่เห็น แล้วแอปเด้งไปหน้าที่ไม่ได้ตั้งใจกด
      ignoring: _fading,
      child: AnimatedOpacity(
        opacity: _fading ? 0 : 1,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOut,
        onEnd: () {
          if (_fading && mounted) widget.onDone();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // แตะข้ามได้ — แอปไม่ตัดให้เอง แต่ถ้าเจ้าของอยากข้ามก็ต้องข้ามได้
          onTap: () {
            // แตะข้ามวิดีโอ — แต่ถ้าตัวเธอยังโหลดไม่เสร็จ จะไปหยุดที่หน้าโลโก้
            // พร้อมเปอร์เซ็นต์ ไม่ใช่ทะลุเข้าไปเจอโครงร่าง
            _finishClip();
          },
          child: ColoredBox(
            color: _kSplashBackdrop,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── ชั้นล่างสุด: โลโก้นิ่ง อยู่**ตลอดเวลา** ──
                //
                // 🔴 ต้องอยู่ตั้งแต่เฟรมแรก ไม่ใช่โผล่ทีหลัง
                //
                // จอเริ่มต้นของ Android ก็เป็นโลโก้ตัวนี้บนพื้นสีนี้ ถ้าที่นี่
                // เริ่มด้วยพื้นเปล่า ผู้ใช้จะเห็นโลโก้**หายไปหลายวินาที**
                // ตอน Flutter รับช่วงต่อ แล้วค่อยโผล่กลับมา — วัดได้จริงว่า
                // ขาดตอนไป ~4 วินาที · มีโลโก้รออยู่ก่อนแล้ววิดีโอค่อยเล่นทับ
                // ตาจึงเห็นเป็นภาพเดียวที่เริ่มขยับ ไม่ใช่สามจอสลับกัน
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: Image.asset(
                      'assets/brand/giggok-wordmark.png',
                      width: 260,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),

                // ── วิดีโอ เล่นทับโลโก้ที่รออยู่ ──
                if (v != null && v.value.isInitialized && !_clipDone)
                  // คลิปแนวตั้ง 9:16 จอมือถือส่วนใหญ่สูงกว่านั้น — cover
                  // แล้วยอมให้ล้นข้าง ดีกว่า contain ที่เหลือแถบพื้นบนล่าง
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: v.value.size.width,
                      height: v.value.size.height,
                      child: VideoPlayer(v),
                    ),
                  ),

                // ── หลังวิดีโอจบ: ความคืบหน้าจริงใต้โลโก้ ──
                if (_clipDone)
                  Align(
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 190),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 200,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                // เปอร์เซ็นต์จริงจากไบต์ที่โหลดมาแล้ว
                                // ยังไม่มีตัวเลขค่อยให้แถบวิ่งไปก่อน
                                // ดีกว่าค้างที่ 0 ซึ่งอ่านว่าแอปแฮงก์
                                value: widget.loadPercent > 0
                                    ? widget.loadPercent / 100
                                    : null,
                                minHeight: 5,
                                backgroundColor: const Color(0x1A23204A),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            S.of(context).splashLoading(widget.loadPercent),
                            style: const TextStyle(
                              fontSize: 12.5,
                              letterSpacing: .4,
                              color: MindColors.ink55,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 56),
                    child: AnimatedOpacity(
                      opacity: _hintOn && !_clipDone ? 1 : 0,
                      duration: const Duration(milliseconds: 520),
                      child: Text(
                        S.of(context).splashSkip,
                        style: const TextStyle(
                          fontSize: 12,
                          letterSpacing: .8,
                          color: MindColors.ink45,
                        ),
                      ),
                    ),
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
