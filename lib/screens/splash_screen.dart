import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../i18n/strings.dart';
import '../shell.dart';
import '../theme/tokens.dart';

/// วิดีโอเปิดแอป — โลโก้ GigGok เคลื่อนไหว (720×1280 · 10 วินาที · h264+aac)
const _kSplashAsset = 'assets/brand/splash.mp4';

/// นานที่สุดที่ยอมให้หน้าเปิดกั้นทางเข้าแอป
///
/// ตัวไฟล์ยาว 10 วินาที ซึ่งนานเกินกว่าจะให้ผู้ใช้นั่งรอ**ทุกครั้ง**ที่เปิดแอป
/// คลิปเป็นอนิเมชันวนไม่มีจังหวะจบ (โลโก้อยู่ครบตั้งแต่เฟรมแรก มีแค่ดาวลอยเพิ่ม)
/// ตัดตรงไหนก็ไม่เสียท่อนสำคัญ · อยากให้เล่นจนจบก็แก้ค่านี้เป็น 10 วินาที
const _kSplashMax = Duration(milliseconds: 3600);

/// ตัวปลดล็อกกรณี `initialize()` ค้าง — โคเดกมีปัญหาหรือไฟล์เสีย
///
/// ถ้าไม่มีตัวนี้ วิดีโอที่เปิดไม่ขึ้นจะกลายเป็นจอค้างถาวรที่เข้าแอปไม่ได้เลย
const _kSplashGiveUp = Duration(seconds: 5);

/// เปิดเสียงสติงตอนเข้าแอปไหม
///
/// ปิดไว้เป็นค่าตั้งต้น: แอปที่ส่งเสียงเองทุกครั้งที่เปิดคือแอปที่โดนถอน
/// ถ้าเจ้าของอยากได้เสียงด้วย เปลี่ยนเป็น `true` ที่เดียวจบ — และเสียงจะยัง
/// **ไม่ตัดเพลงที่ผู้ใช้ฟังอยู่** เพราะเปิด `mixWithOthers` ไว้แล้วข้างล่าง
const _kSplashSound = false;

/// สีพื้นก่อนเฟรมแรกจะมาถึง วัดจากขอบคลิปจริง (#FCFAF4)
/// ตั้งให้ตรงกันเพื่อไม่ให้เห็นขาวแวบหนึ่งตอนวิดีโอยังไม่ทันขึ้น
const _kSplashBackdrop = Color(0xFFFCFAF4);

/// ทางเข้าแอป — หน้าเปิดซ้อนอยู่**บน**เชลล์ ไม่ใช่ก่อนหน้าเชลล์
///
/// สำคัญตรงที่ [MindShell] ถูกสร้างตั้งแต่เฟรมแรกพร้อมกับวิดีโอ ไม่ใช่หลังจากนั้น
/// อวาตาร์ VRM 33MB จึงเริ่มโหลด**ระหว่าง**ที่โลโก้กำลังเล่น เวลารวมที่ผู้ใช้รอ
/// คือค่าที่มากกว่าของสองอย่าง ไม่ใช่ผลบวก · ถ้าทำเป็นสองหน้าต่อกันจะกลายเป็น
/// splash 3.6 วิ **บวก** เวลาโหลดโมเดลอีกหลายวิ ซึ่งช้ากว่าไม่มี splash เสียอีก
class MindBoot extends StatefulWidget {
  const MindBoot({super.key});

  @override
  State<MindBoot> createState() => _MindBootState();
}

class _MindBootState extends State<MindBoot> {
  /// เริ่มจางออกแล้ว
  bool _fading = false;

  /// ถอดออกจากต้นไม้แล้ว — ถอดทิ้งจริง ไม่ใช่แค่ opacity 0
  /// ไม่งั้น VideoPlayer จะยังถือ surface ของ ExoPlayer ไว้ทั้งที่มองไม่เห็น
  bool _gone = false;

  void _dismiss() {
    if (_fading || !mounted) return;
    setState(() => _fading = true);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const MindShell(),
        if (!_gone)
          // ระหว่างจาง ปิดการรับสัมผัสไว้ ไม่งั้นนิ้วจะทะลุไปโดนแถบนำทาง
          // ของเชลล์ที่ยังมองแทบไม่เห็น แล้วแอปจะเด้งไปหน้าที่ไม่ได้ตั้งใจกด
          IgnorePointer(
            ignoring: _fading,
            child: AnimatedOpacity(
              opacity: _fading ? 0 : 1,
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOut,
              onEnd: () {
                if (_fading && mounted) setState(() => _gone = true);
              },
              child: SplashOverlay(onDone: _dismiss),
            ),
          ),
      ],
    );
  }
}

/// ปิดตัวเล่นแบบยิงทิ้ง — ห้ามมีใคร `await` ตัวนี้แล้วเอาผลไปใช้ต่อ
///
/// 🔴 `VideoPlayerController.dispose()` เริ่มด้วย `await _creatingCompleter.future`
/// ซึ่ง completer ตัวนั้นจะ complete ก็ต่อเมื่อ `initialize()` **สำเร็จ**
/// พอ initialize พัง (โคเดกไม่รองรับ / ไฟล์หาย) completer จึงไม่มีวันสำเร็จ
/// และ `dispose()` **ค้างตลอดกาล** — ไม่ throw ไม่ timeout ไม่มี log อะไรเลย
///
/// แปลว่าถ้าเขียน `await v.dispose(); _finish();` ตามสัญชาตญาณ บรรทัด
/// `_finish()` จะไม่ถูกเรียกตลอดชีวิตแอป = จอค้างถาวรที่เกิดจาก**โค้ดเก็บกวาด**
/// ไม่ใช่จากวิดีโอ · กฎคือ **ปลดล็อกก่อน เก็บกวาดทีหลัง เสมอ**
///
/// เจอด้วยเทสต์ ไม่ใช่ด้วยการเปิดแอปดู — บนเครื่องจริงวิดีโอมันเปิดขึ้น
Future<void> _closeQuietly(VideoPlayerController v) async {
  try {
    await v.dispose();
  } catch (e) {
    debugPrint('splash: ปิดตัวเล่นไม่สำเร็จ — $e');
  }
}

/// ตัววิดีโอล้วน ๆ แยกออกมาเป็น public เพื่อให้เทสต์จับ**ทางที่พัง**ได้
///
/// ทางที่ต้องพิสูจน์ไม่ใช่ทางปกติ แต่คือ "วิดีโอเปิดไม่ขึ้นแล้วยังเข้าแอปได้ไหม"
/// ซึ่งเป็นกรณีที่ถ้าพลาดจะกลายเป็นจอค้างถาวร และไม่มี error ที่ไหนบอกเลย
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends State<SplashOverlay> {
  VideoPlayerController? _video;
  Timer? _hold, _giveUp, _hint;
  bool _hintOn = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _giveUp = Timer(_kSplashGiveUp, _finish);
    _start();
  }

  Future<void> _start() async {
    final v = VideoPlayerController.asset(
      _kSplashAsset,
      // ไม่แย่ง audio focus จากเพลงที่ผู้ใช้ฟังอยู่ · ต้องตั้งตั้งแต่ตอนสร้าง
      // ตัวเล่น จะมาตั้งทีหลังไม่ได้ และการตั้ง volume เป็น 0 อย่างเดียว
      // **ไม่พอ** — ExoPlayer ยังขอ focus แล้วเพลงของผู้ใช้จะหยุดอยู่ดี
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    try {
      await v.initialize();
    } catch (e) {
      // เปิดวิดีโอไม่ได้ไม่ใช่เหตุผลที่จะกันคนออกจากแอป — เชลล์อยู่ข้างหลังแล้ว
      debugPrint('splash: เปิดวิดีโอไม่ได้ — $e');
      // ปลดล็อกทางเข้าแอปก่อน แล้วค่อยเก็บกวาด — ห้ามสลับลำดับ เหตุผลอยู่ที่
      // doc ของ _closeQuietly ข้างบน (dispose ของตัวที่ init พังจะค้างถาวร)
      _finish();
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
    setState(() => _video = v);

    // คลิปสั้นกว่าเพดานก็ปล่อยให้จบเอง ไม่ต้องตัดกลางคัน
    final len = v.value.duration;
    final wait = len > Duration.zero && len < _kSplashMax ? len : _kSplashMax;
    _hold = Timer(wait, _finish);

    // ป้าย "แตะเพื่อข้าม" โผล่ทีหลัง — ขึ้นพร้อมโลโก้เลยจะแย่งสายตาโลโก้
    _hint = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _hintOn = true);
    });
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _hold?.cancel();
    _giveUp?.cancel();
    _hint?.cancel();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _giveUp?.cancel();
    _hint?.cancel();
    final v = _video;
    if (v != null) unawaited(_closeQuietly(v));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _finish,
      child: ColoredBox(
        color: _kSplashBackdrop,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (v != null && v.value.isInitialized)
              // คลิปเป็นแนวตั้ง 9:16 จอมือถือส่วนใหญ่สูงกว่านั้น — cover แล้ว
              // ยอมให้ล้นข้างดีกว่า contain ที่จะเหลือแถบพื้นบนล่าง
              FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: v.value.size.width,
                  height: v.value.size.height,
                  child: VideoPlayer(v),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 56),
                child: AnimatedOpacity(
                  opacity: _hintOn ? 1 : 0,
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
    );
  }
}
