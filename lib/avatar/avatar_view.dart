import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../theme/tokens.dart';

/// อารมณ์ที่มินเดะแสดงได้ — ตรงกับ MOOD_EXPRESSION ใน avatar.js
/// ถ้าเพิ่มที่นี่ต้องไปเพิ่มใน BrainX ด้วย ไม่งั้นจะตกกลับเป็น neutral เงียบ ๆ
enum MindeMood { neutral, happy, pleased, concerned, thinking, sorry, alert, angry }

/// ระยะกล้อง — 'bust' ตอนคุย, 'full' ตอนยืนเฉย
enum MindeFraming { bust, full }

/// รีโมตของอวาตาร์ ส่งคำสั่งข้ามไปฝั่ง WebView
///
/// ทุกคำสั่งเงียบไว้ถ้าเวทียังไม่พร้อม เพราะ UI เรียกได้ตลอดเวลา
/// (ผู้ใช้กดส่งข้อความได้ตั้งแต่วินาทีแรก แต่ VRM 33MB ยังโหลดไม่เสร็จ)
class MindeAvatarController extends ChangeNotifier {
  InAppWebViewController? _web;
  bool _ready = false;
  String? _error;

  /// โมเดลโหลดขึ้นเวทีแล้วหรือยัง
  bool get ready => _ready;

  /// ข้อความผิดพลาดจากฝั่ง WebView — ปกติคือหาไฟล์ minde.vrm ไม่เจอ
  String? get error => _error;

  void _attach(InAppWebViewController web) => _web = web;

  void _onReady() {
    if (_ready) return;
    _ready = true;
    _error = null;
    notifyListeners();
  }

  void _onError(String message) {
    _ready = false;
    _error = message;
    notifyListeners();
  }

  /// เสียงพูดพังไม่ใช่เรื่องเดียวกับเวทีพัง — เธอยังยืนอยู่ได้
  /// จึงไม่แตะ `_ready` ไม่งั้นจะไปซ่อนตัวเธอทั้งที่ภาพไม่ได้มีปัญหา
  String? _speakError;
  String? get speakError => _speakError;

  void _onSpeakFailed(String why) {
    _speakError = why;
    notifyListeners();
  }

  Future<void> setMood(MindeMood mood) => _call("window.minde.mood('${mood.name}')");

  /// เล่นไฟล์เสียงพร้อมขยับปาก — url ต้องเข้าถึงได้จากฝั่ง WebView
  Future<void> speak(String url) =>
      _call("window.minde.speak(${_jsString(url)})");

  /// เล่นเสียงจากไบต์ที่สังเคราะห์มา (OpenAI หรือเครื่อง Android ก็ได้)
  ///
  /// ส่งผ่าน callAsyncJavaScript พร้อม arguments ไม่ใช่ต่อสตริงเข้า JS
  /// เพราะ base64 ของ mp3 ยาวเป็นแสนตัวอักษร การต่อสตริงขนาดนั้นทั้งช้า
  /// และเสี่ยงพังถ้ามีอักขระหลุด · รอจนเล่นจบเพื่อให้ผู้เรียกรู้จังหวะ
  Future<void> speakBytes(Uint8List bytes, {String mime = 'audio/mpeg'}) async {
    final web = _web;
    if (web == null || !_ready) return;
    try {
      await web.callAsyncJavaScript(
        functionBody: 'return await window.minde.speakBytes(b64, mime);',
        arguments: {'b64': base64Encode(bytes), 'mime': mime},
      );
    } catch (e) {
      debugPrint('avatar: เล่นเสียงไม่สำเร็จ — $e');
    }
  }

  Future<void> stop() => _call('window.minde.stop()');

  Future<void> setFraming(MindeFraming f) =>
      _call("window.minde.frame('${f.name}')");

  Future<void> _call(String js) async {
    final web = _web;
    if (web == null || !_ready) return;
    try {
      await web.evaluateJavascript(source: js);
    } catch (e) {
      debugPrint('avatar: สั่ง "$js" ไม่สำเร็จ — $e');
    }
  }

  /// escape ให้ปลอดภัยก่อนยัดเข้า JS — url อาจมาจากเซิร์ฟเวอร์ ไม่ควรเชื่อ
  static String _jsString(String v) =>
      '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll(r'$', r'\$')}"';

  @override
  void dispose() {
    _web = null;
    super.dispose();
  }
}

/// เวทีของมินเดะ — WebView โปร่งใสที่มี three-vrm อยู่ข้างใน
///
/// ถ้าโมเดลยังไม่มีในเครื่อง จะขึ้นกรอบ placeholder แบบเดียวกับใน artboard
/// ไม่ใช่จอว่าง เพราะจอว่างทำให้แยกไม่ออกว่า "ยังโหลด" กับ "พัง"
class MindeAvatarView extends StatefulWidget {
  const MindeAvatarView({
    super.key,
    required this.controller,
    required this.mode,
    this.serverPort = 8747,
  });

  final MindeAvatarController controller;

  /// ใช้กับสีวงแหวนรอบตัวเธอตอนยังไม่มีโมเดล
  final MindeMode mode;

  final int serverPort;

  @override
  State<MindeAvatarView> createState() => _MindeAvatarViewState();
}

class _MindeAvatarViewState extends State<MindeAvatarView> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final failed = widget.controller.error != null;
        return Stack(
          fit: StackFit.expand,
          children: [
            // WebView ยังอยู่แม้ตอน error เพื่อให้ hot reload หรือการวางไฟล์โมเดล
            // ทีหลังแล้ว reload กลับมาทำงานได้โดยไม่ต้องสร้างใหม่ทั้งก้อน
            Opacity(
              opacity: widget.controller.ready ? 1 : 0,
              child: InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri('http://localhost:${widget.serverPort}/assets/avatar/index.html'),
                ),
                initialSettings: InAppWebViewSettings(
                  transparentBackground: true,
                  supportZoom: false,
                  disableVerticalScroll: true,
                  disableHorizontalScroll: true,
                  // เวทีนี้เสิร์ฟจาก localhost ของตัวเอง ไม่เปิดทางให้หน้าอื่น
                  javaScriptCanOpenWindowsAutomatically: false,
                  useHybridComposition: true,

                  // ปุ่มส่งอยู่ฝั่ง Flutter WebView จึงไม่เคยเห็น user gesture
                  // ถ้าไม่ปลดตรงนี้ AudioContext จะค้างสถานะ suspended ตลอด
                  // อาการคือเสียงไม่ออกและปากไม่ขยับ โดยไม่มี error ที่ไหนเลย
                  mediaPlaybackRequiresUserGesture: false,
                ),
                onWebViewCreated: (web) {
                  widget.controller._attach(web);
                  web.addJavaScriptHandler(
                    handlerName: 'minde',
                    callback: (args) {
                      final msg = args.isEmpty ? null : args.first;
                      if (msg is! Map) return null;
                      switch (msg['type']) {
                        case 'ready':
                          widget.controller._onReady();
                        case 'error':
                          widget.controller._onError('${msg['message']}');

                        // ท่อเสียงพังได้หลายจุดโดยไม่มี error ที่ไหนเลย
                        // จึงให้ฝั่ง JS รายงานกลับมาทุกครั้ง โดยเฉพาะสถานะ
                        // AudioContext ซึ่งถ้าเป็น suspended เสียงจะถูกกลืนหาย
                        case 'speak-start':
                          debugPrint('avatar: เริ่มพูด ${msg['bytes']} ไบต์ '
                              '(${msg['mime']}) · AudioContext=${msg['ctx']}');
                        case 'speak-done':
                          debugPrint('avatar: พูดจบ done=${msg['done']} '
                              'AudioContext=${msg['ctx']} level=${msg['level']}');
                        case 'speak-failed':
                          debugPrint('avatar: พูดไม่ได้ — ${msg['why']} '
                              '(AudioContext=${msg['ctx']})');
                          widget.controller._onSpeakFailed('${msg['why']}');
                      }
                      return null;
                    },
                  );
                },
                // เฉพาะ main frame เท่านั้นที่ถือว่าพัง
                //
                // clips.json อ้างถึง Bored.fbx / Waiting.fbx ที่ไม่เคยโหลดมาจาก
                // Mixamo — motion.js ข้ามให้อยู่แล้ว แต่ WebView ยิง callback นี้
                // ทุก subresource ที่พลาด ถ้าไม่กรอง เธอจะโดนซ่อนหลัง placeholder
                // ทั้งที่ยืนอยู่บนเวทีเรียบร้อยแล้ว
                onReceivedError: (_, request, err) {
                  if (request.isForMainFrame ?? false) {
                    widget.controller._onError(err.description);
                  }
                },
                onReceivedHttpError: (_, request, response) {
                  if (request.isForMainFrame ?? false) {
                    widget.controller._onError('HTTP ${response.statusCode}');
                  }
                },
              ),
            ),
            if (!widget.controller.ready)
              _AvatarPlaceholder(mode: widget.mode, failed: failed),
          ],
        );
      },
    );
  }
}

/// กรอบประๆ ตรงตาม artboard 2a — inset 16/44/4/12, มุม 26, แถบทแยง 135°
class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.mode, required this.failed});

  final MindeMode mode;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 44, 4),
      child: CustomPaint(
        painter: const _DashedStripePainter(),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              failed ? 'ยังไม่มี minde.vrm ในเครื่อง' : 'VRM avatar · minde.vrm · full body',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                letterSpacing: .6,
                color: MindeColors.ink45,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedStripePainter extends CustomPainter {
  const _DashedStripePainter();

  static const _radius = Radius.circular(MindeRadius.panel);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, _radius);

    // repeating-linear-gradient 135° ขาว .55 / .15 สลับทุก 9px
    canvas.save();
    canvas.clipRRect(rrect);
    final stripe = Paint()..color = const Color(0x8CFFFFFF);
    canvas.drawRRect(rrect, Paint()..color = const Color(0x26FFFFFF));
    const step = 9 * math.sqrt2; // ระยะตามแนวนอนของแถบเอียง 45°
    for (var x = -size.height; x < size.width; x += step * 2) {
      canvas.drawPath(
        Path()
          ..moveTo(x, 0)
          ..lineTo(x + step, 0)
          ..lineTo(x + step + size.height, size.height)
          ..lineTo(x + size.height, size.height)
          ..close(),
        stripe,
      );
    }
    canvas.restore();

    // เส้นขอบประ 1px
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = MindeColors.ink22;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), border);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedStripePainter oldDelegate) => false;
}
