import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'avatar/avatar_pack.dart';
import 'calendar/device_calendar.dart';
import 'journal/mind_journal.dart';
import 'avatar/avatar_view.dart';
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

  /// สิทธิ์ทั้งแอปใช้ตัวเดียวกัน — สองตัวจะเห็นสถานะไม่ตรงกันได้
  /// ตอนที่ผู้ใช้เพิ่งกดอนุญาตในหน้าหนึ่งแล้วอีกหน้ายังจำค่าเก่าอยู่
  final MindPermissions _perms = MindPermissions();

  /// ปฏิทินของเครื่อง — เธอต้องรู้ตารางจริงถึงจะตอบเรื่องนัดได้
  late final DeviceCalendar _calendar = DeviceCalendar(permissions: _perms);

  /// สมุดบันทึกเรื่องที่เกิดขึ้นจริง — แท็บไทม์ไลน์อ่านจากตรงนี้
  final MindJournal _journal = MindJournal();

  /// ตัวควบคุมอวาตาร์อยู่ที่นี่ ไม่ใช่ในเชลล์ เพราะหน้าเปิดแอปต้องอ่าน
  /// ความคืบหน้าการโหลด VRM มาโชว์เป็นเปอร์เซ็นต์จริง
  final MindAvatarController _avatar = MindAvatarController();

  /// พร้อมสร้างเชลล์หรือยัง — ต้องมีเซิร์ฟเวอร์ + ค่าที่ตั้งไว้ + ทะเบียนชุด
  ///
  /// ทั้งสามอย่างนี้เร็ว (หลักร้อยมิลลิวินาที) ต่างจากการโหลด VRM 33MB
  /// ที่กินหลายวินาที · แยกกันเพื่อให้ **WebView เริ่มโหลด VRM ตั้งแต่วิดีโอ
  /// ยังเล่นอยู่** ไม่ใช่รอวิดีโอจบแล้วค่อยเริ่ม
  bool _canBuildShell = false;

  /// วิดีโอเล่นจบ (หรือถูกแตะข้าม) แล้วหรือยัง
  bool _splashDone = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // ── รอบแรก: ของที่ต้องมีก่อนสร้างเชลล์ (เร็วทั้งหมด) ──
    //
    // ทะเบียนชุดต้องเสร็จก่อนด้วย ไม่งั้น WebView โหลดด้วยทางเก่าแล้วต้อง
    // รีโหลดทีหลัง = โหลด VRM 33MB สองรอบ ซึ่งช้ากว่ารอให้เสร็จก่อนมาก
    try {
      await InAppLocalhostServer(port: kAvatarPort).start();

      // อยู่รอบแรกเพราะบทสนทนาเกิดขึ้นได้ทันทีที่เชลล์ขึ้น · ต่อทีหลัง
      // แปลว่าข้อความแรก ๆ ไม่ถูกบันทึก โดยไม่มีอะไรบอกว่าหายไป
      //
      // (การกู้บทสนทนาเก่าไม่ผ่าน _push — ใช้ _context.add ตรง ๆ
      //  จึงไม่มีการบันทึกซ้ำทุกครั้งที่เปิดแอป)
      await _journal.load();
      _state.attachJournal(_journal);
      _pack.onInstalled = (pack) => _journal.record(
            JournalKind.pack,
            pack.nameFor(_state.lang == AppLang.th),
          );

      await _state.load();
      await _pack.restore(preferId: _state.avatarPackId);
    } catch (e) {
      debugPrint('boot: เตรียมของไม่ครบ — $e');
    }
    if (!mounted) return;
    setState(() => _canBuildShell = true);

    // ── รอบสอง: ของที่รอได้ ทำหลังเชลล์เริ่มโหลด VRM ไปแล้ว ──
    try {
      await configureMindBackground();
    } catch (e) {
      debugPrint('boot: ตั้งบริการเบื้องหลังไม่สำเร็จ — $e');
    }

    // อ่านปฏิทินตั้งแต่เปิดแอป ไม่ใช่รอให้เปิดแท็บปฏิทินก่อน
    //
    // ถ้ารอ เธอจะตอบว่าไม่รู้ตารางจนกว่าเจ้าของจะบังเอิญกดแท็บนั้น
    // ซึ่งอ่านได้ว่าเธอจำไม่ได้ ทั้งที่ความจริงคือยังไม่ได้ถาม
    // ยังไม่ได้ให้สิทธิ์ก็ไม่เป็นไร — จบที่สถานะ denied เงียบ ๆ
    _state.attachCalendar(_calendar);
    await _calendar.load();
  }

  @override
  void dispose() {
    _avatar.dispose();
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
        ChangeNotifierProvider.value(value: _avatar),
        ChangeNotifierProvider.value(value: _state.memory),
        ChangeNotifierProvider(create: (_) => Updater()),
        ChangeNotifierProvider(create: (_) => MindWatch()..refresh()),
        ChangeNotifierProvider.value(value: _perms..refresh()),
        ChangeNotifierProvider.value(value: _calendar),
        ChangeNotifierProvider.value(value: _journal),
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
              // เชลล์เกิดตั้งแต่วิดีโอยังเล่นอยู่ WebView จึงเริ่มโหลด VRM
              // ไปพร้อมกัน แทนที่จะรอวิดีโอจบแล้วค่อยเริ่มนับหนึ่ง
              if (_canBuildShell) const MindShell(),
              if (!_splashDone)
                // 🔴 รอ `visible` ไม่ใช่ `ready`
                //
                // เจ้าของสั่งว่าเข้าแอปแล้วต้องเห็นตัวเธอเลย ไม่ใช่โครงร่าง
                // `visible` = VRM ขึ้นจอแล้ว · `ready` = คลิปท่าทางครบด้วย
                // ซึ่งมาช้ากว่าอีกหลายวินาทีโดยที่เธอยืนอยู่แล้ว
                Consumer<MindAvatarController>(
                  builder: (context, avatar, _) => MindSplash(
                    appReady: avatar.visible || avatar.error != null,
                    loadPercent: avatar.loadPercent,
                    onDone: () => setState(() => _splashDone = true),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
