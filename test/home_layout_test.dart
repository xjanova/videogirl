/// หน้าหลัก — เธอต้องอยู่บนจอ และปุ่มเสียงต้องอยู่ตรงที่คุยกัน
///
/// ## 🔴 สองอาการที่เจ้าของเจอบนเครื่องจริง
///
/// 1. **"เวลาแชท ตัวอวาต้าหายไป"** — ไม่ใช่ความรู้สึก · แผงแชทไม่มีเพดาน
///    ความสูง มันโตตามข้อความไปเรื่อย ๆ และใน `Column` ลูกที่ไม่ยืดหยุ่น
///    ได้ที่ก่อน `Expanded` จึงได้เศษที่เหลือ · วัดจริงบนจอ 1080×2340
///    ก่อนแก้: คุยแค่ **3 ข้อความ เวทีเหลือ 0 พิกเซล** พร้อม RenderFlex
///    overflow 151 พิกเซล
///
/// 2. **"ไม่มีปุ่มเปิดปิดเสียงเธอ"** — สวิตช์มีอยู่ แต่อยู่ในหน้าตั้งค่า
///    ซึ่งเป็นคนละที่กับที่คนกำลังคุยอยู่ · การปิดปากเธอเป็นเรื่องของนาทีนี้
///    (มีคนอยู่ข้าง ๆ อยู่บนรถ) ไม่ใช่ค่าที่ตั้งครั้งเดียวแล้วจบ
///
/// ทั้งคู่เป็นเรื่อง**การจัดหน้า** ซึ่งเทสต์ระดับ state จับไม่ได้เลยสักตัว
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/avatar/avatar_pack.dart';
import 'package:videogirl/avatar/avatar_view.dart';
import 'package:videogirl/avatar/stage_bridge.dart';
import 'package:videogirl/persona/mind_soul.dart';
import 'package:videogirl/phone/call_session.dart';
import 'package:videogirl/phone/call_watch.dart';
import 'package:videogirl/screens/home_screen.dart';
import 'package:videogirl/state/mind_state.dart';
import 'package:videogirl/studio/mind_studio.dart';
import 'package:videogirl/system/permissions.dart';

/// เวทีที่พร้อมเสมอ — ในเทสต์ WebView สร้างไม่ได้ ตัวควบคุมจริงจึงไม่มีวันพร้อม
class _ReadyStage implements StudioStage {
  @override
  bool get ready => true;
  @override
  MindRecordingSink? recordingSink;
  @override
  Future<void> setStudio(bool on) async {}
  @override
  Future<void> setBackdrop(String? hex) async {}
  @override
  Future<void> syncMocapShot(MindMocapShot s) async {}
  @override
  Future<MindRecStart> startRecording({required bool mic}) async =>
      const MindRecStart.failed('test');
  @override
  Future<void> stopRecording() async {}
}

class _QuietPlatform implements StudioPlatform {
  @override
  Future<void> keepScreenOn(bool on) async {}
  @override
  Future<bool> enterPip(int w, int h) async => false;
  @override
  Future<void> autoPip(bool on, int w, int h) async {}
  @override
  Future<StudioSave> saveVideo(String path, String name, String mime) async =>
      const StudioSave();
  @override
  Future<void> immersive(bool on) async {}
  @override
  set onPip(void Function(bool inPip)? listener) {}
}

late MindStudio _studio;

/// ยาวพอ ๆ กับที่เธอตอบจริงเวลาถูกถามคำถามปลายเปิด
const _long = 'คำตอบยาวแบบที่เธอตอบจริงเวลาเล่าอะไรสักเรื่องให้ฟัง '
    'ซึ่งกินหลายบรรทัดบนจอมือถือและไม่ใช่เรื่องแปลกอะไรเลย '
    'เพราะคนถามคำถามปลายเปิดกันเป็นปกติทุกวัน';

Future<MindState> _mount(WidgetTester t) async {
  // 🔴 InAppWebView สร้างในเทสต์ไม่ได้ (ไม่มี platform implementation)
  // ซึ่งไม่เกี่ยวกับสิ่งที่วัดตรงนี้เลย · ปล่อยให้ ErrorWidget ยืนแทนที่
  // แล้วกลืนเฉพาะ assertion ตัวนั้น · ข้อผิดพลาดอื่นยังทำให้เทสต์ตกเหมือนเดิม
  final onError = FlutterError.onError;
  FlutterError.onError = (d) {
    if ('${d.exception}'.contains('InAppWebViewPlatform')) return;
    onError?.call(d);
  };
  addTearDown(() => FlutterError.onError = onError);

  t.view.physicalSize = const Size(1080, 2340);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);

  final state = MindState()..setBrain(BrainProvider.openai);
  final avatar = MindAvatarController();
  addTearDown(avatar.dispose);

  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<MindState>.value(value: state),
      ChangeNotifierProvider(create: (_) => MindPermissions()),
      ChangeNotifierProvider(create: (_) => AvatarPacks()),
      ChangeNotifierProvider(
          create: (_) => CallSession(watch: CallWatch(), state: state)),
      ChangeNotifierProvider(create: (_) => MindSoul()),
      ChangeNotifierProvider(
        create: (_) => _studio = MindStudio(
          stage: _ReadyStage(),
          state: state,
          permissions: MindPermissions(),
          platform: _QuietPlatform(),
        ),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: HomeScreen(avatar: avatar))),
  ));
  await t.pump(const Duration(milliseconds: 400));
  return state;
}

/// ถอดจอออกก่อนแล้วค่อยปิด state — ตัวนับเวลาของแผงแชทยังเดินอยู่
/// และ flutter_test ตกทันทีถ้ามี Timer ค้างตอนจบเทสต์
Future<void> _unmount(WidgetTester t, MindState state) async {
  await t.pumpWidget(const SizedBox.shrink());
  state.dispose();
  await t.pump();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('🔴 แชทยาวแค่ไหน เวทีของเธอก็ต้องไม่ยุบหาย', (t) async {
    final s = await _mount(t);
    s.openChat();

    for (var i = 0; i < 8; i++) {
      s.debugPush(i.isEven, '$_long ($i)');
      await t.pump(const Duration(milliseconds: 400));

      expect(t.getSize(find.byType(MindAvatarView)).height, greaterThan(0),
          reason: 'เวทีเหลือศูนย์ = เธอหายไปทั้งตัว (ข้อความที่ ${i + 1})');

      // ช่องพิมพ์ต้องยังอยู่ ไม่ใช่ถูกข้อความดันตกขอบจอไป
      expect(find.byType(TextField), findsOneWidget,
          reason: 'พิมพ์ตอบไม่ได้ทั้งที่แผงเปิดอยู่ (ข้อความที่ ${i + 1})');
    }

    await _unmount(t, s);
  });

  testWidgets('🔴 ปุ่มปิดเสียงเธอต้องอยู่บนจอที่คุยกัน ไม่ใช่ในหน้าตั้งค่า',
      (t) async {
    final s = await _mount(t);
    s.openChat();
    s.debugPush(true, 'สวัสดีค่ะ');
    await t.pump(const Duration(milliseconds: 400));

    expect(s.voiceEnabled, isTrue, reason: 'ค่าตั้งต้นคือเปิดเสียง');

    final button = find.byIcon(Icons.volume_up_rounded);
    expect(button, findsOneWidget, reason: 'ไม่มีปุ่ม = ต้องเดินไปอีกแท็บ');

    await t.tap(button);
    await t.pump();

    expect(s.voiceEnabled, isFalse, reason: 'กดแล้วต้องปิดจริง');
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget,
        reason: 'ไอคอนต้องเปลี่ยนตาม ไม่งั้นกดแล้วไม่รู้ว่าติดไหม');

    await _unmount(t, s);
  });

  /// 🔴 เข้าสตูดิโอต้องไม่สร้างเวทีใหม่
  ///
  /// เวทีคือ WebView + VRM 33MB · ถ้าโครงต้นไม้เปลี่ยนตำแหน่งตอนซ่อนหัวจอ
  /// กับแผงแชท Flutter จะสร้างมันใหม่ทั้งก้อน = เธอหายไปโหลดใหม่หลายวินาที
  /// ทุกครั้งที่กดเข้า/ออก โดยไม่มี error ที่ไหนบอก
  testWidgets('🔴 สตูดิโอซ่อนทุกอย่างนอกจากเวที และเวทีเป็นตัวเดิม', (t) async {
    final s = await _mount(t);
    final before = t.element(find.byType(MindAvatarView));
    expect(find.byIcon(Icons.videocam_rounded), findsOneWidget,
        reason: 'ทางเข้าสตูดิโอต้องอยู่บนเวที');

    await _studio.enter();
    await t.pump(const Duration(milliseconds: 400));

    expect(identical(t.element(find.byType(MindAvatarView)), before), isTrue,
        reason: 'เวทีถูกสร้างใหม่ = เธอหายไปโหลดใหม่ทั้งตัว');
    expect(find.text('MIND'), findsNothing, reason: 'หัวจอติดไปในภาพที่แชร์');
    expect(find.byIcon(Icons.videocam_rounded), findsNothing,
        reason: 'ปุ่มบนเวทีติดไปในภาพที่แชร์');
    final full = t.getSize(find.byType(MindAvatarView));
    expect(full.height, closeTo(2340 / 3, 1), reason: 'เวทีต้องเต็มจอ');

    await _studio.exit();
    await t.pump(const Duration(milliseconds: 400));
    expect(identical(t.element(find.byType(MindAvatarView)), before), isTrue);
    expect(find.text('MIND'), findsOneWidget);

    await _unmount(t, s);
  });
}
