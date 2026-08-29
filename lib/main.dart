import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import 'shell.dart';
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

  await InAppLocalhostServer(port: kAvatarPort).start();

  // โหลดค่าที่ผู้ใช้ตั้งไว้ให้เสร็จก่อนวาดจอแรก ไม่งั้นหน้าจอจะกะพริบจาก
  // ค่าเริ่มต้นไปค่าจริง และคนที่ตั้งโหมดส่วนตัวไว้จะเห็นสีเขียวงานแวบหนึ่ง
  final state = MindState();
  await state.load();

  runApp(MindApp(state: state));
}

class MindApp extends StatelessWidget {
  const MindApp({super.key, required this.state});

  final MindState state;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider(create: (_) => Updater()),
      ],
      child: MaterialApp(
        title: 'GigGok',
        debugShowCheckedModeBanner: false,
        theme: mindTheme(),
        home: const MindShell(),
      ),
    );
  }
}
