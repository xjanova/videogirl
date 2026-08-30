import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'avatar/avatar_pack.dart';
import 'background/mind_background.dart';
import 'background/mind_watch.dart';
import 'system/permissions.dart';
import 'screens/splash_screen.dart';
import 'shell.dart';
import 'i18n/strings.dart';
import 'state/mind_state.dart';
import 'update/updater.dart';
import 'theme/app_theme.dart';

/// พอร์ตของเซิร์ฟเวอร์ในเครื่องที่เสิร์ฟเวทีอวาตาร์
///
/// ทำไมต้องมีเซิร์ฟเวอร์: avatar.js เป็น ES module ที่ใช้ importmap
/// ถ้าโหลดผ่าน file:// Android WebView จะบล็อกด้วยกฎ CORS ของ opaque origin
/// เสิร์ฟผ่าน http://localhost แทน แล้วทุกอย่างทำงานเหมือนบนเดสก์ท็อป
const kAvatarPort = 8747;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // พื้นหลังไล่สีของแต่ละหน้าจอวิ่งขึ้นไปใต้แถบสถานะ
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // 🔴 วาดจอแรกทันที **ห้ามรออะไรก่อนบรรทัดนี้**
  //
  // ของเดิมรอ server + prefs + ทะเบียนชุด + บริการเบื้องหลัง ให้เสร็จก่อน
  // ผลที่วัดได้บนเครื่องจริง: จอขาวของ Android ค้าง **10.2 วินาที**
  // (`SplashScreenView: Build` → `Splash Screen EXITING` ห่างกัน 10.2 วิ)
  // แล้ววิดีโอเปิดแอปเพิ่งได้เริ่มตอนนั้น — ซึ่งสายเกินไปจนแทบไม่มีใครทันเห็น
  //
  // ทุกอย่างที่เคยรอ ย้ายไปโหลด**ระหว่างที่วิดีโอกำลังเล่น** ใน MindBootstrap
  runApp(const MindBootstrap());
}

/// ตัวเปิดแอป — วาดวิดีโอก่อน แล้วค่อยโหลดของหนักอยู่ข้างหลัง
///
/// เหตุผลที่ของหนักย้ายมาอยู่ที่นี่ได้ ทั้งที่เดิมต้องเสร็จก่อนวาดจอแรก:
/// **วิดีโอเปิดแอปบังทั้งจออยู่แล้ว** การกะพริบจากค่าเริ่มต้นไปค่าจริง
/// ที่เคยต้องกันด้วยการรอ จึงถูกบังไปด้วยตัวมันเอง
class MindBootstrap extends StatefulWidget {
  const MindBootstrap({super.key});

  @override
  State<MindBootstrap> createState() => _MindBootstrapState();
}

class _MindBootstrapState extends State<MindBootstrap> {
  final MindState _state = MindState();
  final AvatarPacks _pack = AvatarPacks();

  /// โหลดของหนักเสร็จหรือยัง — เชลล์สร้างไม่ได้ก่อนหน้านี้เพราะ WebView
  /// จะยิงไปที่ localhost ที่ยังไม่มีเซิร์ฟเวอร์ แล้วขึ้น error ค้าง
  bool _ready = false;

  /// วิดีโอเล่นจบ (หรือถูกแตะข้าม) แล้วหรือยัง
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await InAppLocalhostServer(port: kAvatarPort).start();
      await _state.load();
      await _pack.restore(preferId: _state.avatarPackId);
      await configureMindBackground();
    } catch (e) {
      // เปิดไม่ครบดีกว่าเปิดไม่ได้ — ผู้ใช้ยังเข้าแอปได้ แล้วส่วนที่พัง
      // จะแสดงสถานะของตัวเองในหน้าที่เกี่ยวข้อง
      debugPrint('boot: เตรียมของไม่ครบ — $e');
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _state.dispose();
    _pack.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _state),
        ChangeNotifierProvider.value(value: _pack),
        ChangeNotifierProvider.value(value: _state.memory),
        ChangeNotifierProvider(create: (_) => Updater()),
        ChangeNotifierProvider(create: (_) => MindWatch()..refresh()),
        ChangeNotifierProvider(create: (_) => MindPermissions()..refresh()),
      ],
      child: Consumer<MindState>(
        builder: (context, state, _) => MaterialApp(
          title: 'GigGok',
          debugShowCheckedModeBanner: false,
          theme: mindTheme(state.mode),
          locale: state.lang.locale,
          supportedLocales: [for (final l in AppLang.values) l.locale],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Stack(
            fit: StackFit.expand,
            children: [
              if (_ready) const MindShell(),
              if (!_splashDone)
                MindSplash(
                  // วิดีโอเล่นจบแล้วแต่ของยังโหลดไม่เสร็จ ก็ค้างหน้าเปิดไว้ต่อ
                  // ดีกว่าโยนคนเข้าไปเจอจอเปล่าที่ยังไม่มีอะไร
                  appReady: _ready,
                  onDone: () => setState(() => _splashDone = true),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
