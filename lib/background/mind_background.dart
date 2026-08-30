/// มายด์ตอนแอปปิดอยู่
///
/// **ทำไมต้องเป็น foreground service:** Android ฆ่า process ของแอปที่ไม่ได้อยู่
/// หน้าจอภายในไม่กี่นาที · งานที่ต้องเกิดตอนเจ้าของไม่ได้เปิดแอป (เฝ้ากล่องเมล
/// เฝ้ารุ่นใหม่ ต่อไปคือคัดกรองสาย) จึงต้องมีบริการที่ระบบสัญญาว่าจะไม่ฆ่า
/// ซึ่งแลกมาด้วยการ**ต้องมีการแจ้งเตือนค้างอยู่** — Android บังคับ ไม่มีทางเลี่ยง
///
/// **ทำไมรันเป็น Dart ไม่ใช่ Kotlin:** ตรรกะทั้งหมดของแอปนี้เป็น Dart
/// (ตัวอัปเดต, ไคลเอนต์ OpenAI, ต่อไปคือเมล) เขียนซ้ำใน Kotlin คือของสองชุด
/// ที่จะค่อย ๆ ไม่ตรงกัน · `flutter_background_service` รัน isolate แยกให้
///
/// 🔴 **isolate นี้ไม่เห็นตัวแปรใด ๆ ของฝั่ง UI เลย** — คนละ isolate คนละหน่วยความจำ
/// สื่อสารกันได้สองทางเท่านั้น: `service.invoke()/on()` และ SharedPreferences
/// เผลอ import state ของ UI มาใช้ตรง ๆ = ได้ instance เปล่า ๆ ที่ไม่มีข้อมูลอะไร
/// โดยไม่มี error บอก
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/strings.dart';
import '../update/updater.dart';

/// ช่องแจ้งเตือนของบริการ — ต้องตรงกับที่ประกาศใน AndroidManifest
const kMindChannelId = 'mind_watch';

/// จังหวะที่เธอตื่นมาดูงาน
///
/// 5 นาทีเป็นค่าที่แลกกันแล้วระหว่างความสดของข้อมูลกับแบต · ถี่กว่านี้
/// ระบบจะเริ่มหรี่ให้เองอยู่ดีถ้าไม่ได้ยกเว้น Battery Optimization
const kMindTick = Duration(minutes: 5);

/// เวลาที่เธอตื่นมาดูงานครั้งล่าสุด (epoch ms)
///
/// 🔴 **นี่คือสิ่งเดียวที่บอกได้ว่าบริการยังไม่ตาย** — บริการเบื้องหลังบน Android
/// ตายเงียบเป็นเรื่องปกติ (ROM จีนฆ่า, Doze แช่แข็ง, ระบบเก็บแรมคืน) และไม่มี
/// callback ไหนมาบอก · ถ้าไม่บันทึกเวลาไว้ เราจะแยกไม่ออกระหว่าง "ยังไม่ถึงรอบ"
/// กับ "ตายไปตั้งแต่เมื่อวาน" ซึ่งเป็นคนละปัญหากันคนละเรื่อง
const kPrefLastBeat = 'bgLastBeat';

/// จำนวนครั้งที่ตื่นมาแล้วสะสม — ใช้ดูว่าโดนหรี่ไปเท่าไหร่เทียบกับที่ควรจะเป็น
const kPrefBeats = 'bgBeats';

/// ผลตรวจรุ่นใหม่ล่าสุดที่เจอตอนอยู่เบื้องหลัง — ว่าง = ยังไม่เจอ
const kPrefBgUpdate = 'bgUpdateFound';

/// เปิดสวิตช์ให้เธอเฝ้างานเบื้องหลังไหม
const kPrefWatchEnabled = 'bgWatch';

/// ตั้งค่าบริการ — เรียกครั้งเดียวตอนเปิดแอป
///
/// `autoStart: false` โดยตั้งใจ: การแจ้งเตือนค้างจอเป็นสิ่งที่ต้อง**ขออนุญาต
/// ด้วยการให้ผู้ใช้กดเอง** ไม่ใช่สิ่งที่แอปหยิบไปเองตั้งแต่เปิดครั้งแรก
Future<void> configureMindBackground() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: mindBackgroundMain,
      isForegroundMode: true,
      autoStart: false,
      autoStartOnBoot: true,
      notificationChannelId: kMindChannelId,
      initialNotificationTitle: 'GigGok',
      // ข้อความแรกก่อนจังหวะแรกจะมาถึง — หลังจากนั้น _beat เขียนทับด้วย
      // ภาษาที่ผู้ใช้ตั้งไว้จริง · ตรงนี้ยังไม่มีทางรู้ภาษาเพราะยังไม่ได้อ่าน prefs
      initialNotificationContent: 'GigGok',
      foregroundServiceNotificationId: 8747,
      foregroundServiceTypes: [AndroidForegroundType.dataSync],
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

/// จุดเริ่มของ isolate เบื้องหลัง
///
/// `@pragma('vm:entry-point')` ห้ามลบ — tree shaker ตอน build release มองไม่เห็น
/// ว่ามีใครเรียกฟังก์ชันนี้ (ฝั่งเรียกอยู่ใน Kotlin) แล้วจะตัดทิ้ง
/// อาการคือ debug ทำงานปกติ release เงียบสนิท ซึ่งหาสาเหตุยากมาก
@pragma('vm:entry-point')
Future<void> mindBackgroundMain(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  // ปลั๊กอินไม่ได้ลงทะเบียนให้เองใน isolate เบื้องหลัง — ไม่เรียกบรรทัดนี้
  // SharedPreferences จะโยน MissingPluginException
  DartPluginRegistrant.ensureInitialized();

  // ⚠️ ตอน isolate นี้เริ่ม จะเห็น log ว่า
  //    `flutter_background_service_android` threw an error:
  //    This class should only be used in the main isolate (UI App)
  // **ไม่ใช่บั๊ก และไม่ต้องแก้** — เป็นตัว registrant ของปลั๊กอินเองที่บ่นว่า
  // คลาสฝั่ง UI ของมันไม่ควรถูกสร้างที่นี่ ซึ่งเราก็ไม่ได้สร้าง
  // ยืนยันแล้วบนเครื่องจริงว่าบริการยังรันและเต้นครบทุกจังหวะ
  service.on('stop').listen((_) => service.stopSelf());

  // เต้นทันทีหนึ่งครั้ง ไม่ต้องรอครบรอบแรก — คนกดเปิดสวิตช์แล้วอยากเห็นว่า
  // มันทำงานเดี๋ยวนั้น ไม่ใช่รออีกห้านาทีแล้วค่อยเชื่อ
  await _beat(service);
  Timer.periodic(kMindTick, (_) => _beat(service));
}

/// หนึ่งจังหวะของงานเบื้องหลัง
///
/// จับ error ทั้งก้อน — ถ้าปล่อยให้หลุดออกจาก callback ของ Timer
/// timer จะตายไปเงียบ ๆ แล้วบริการจะยังอยู่แต่ไม่ทำอะไรอีกเลย
/// ซึ่งเป็นความล้มเหลวที่มองไม่เห็นที่สุดของงานเบื้องหลัง
Future<void> _beat(ServiceInstance service) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // ค่าอาจถูกฝั่ง UI แก้ไปแล้ว isolate นี้ไม่รู้เอง

    final beats = (prefs.getInt(kPrefBeats) ?? 0) + 1;
    await prefs.setInt(kPrefBeats, beats);
    await prefs.setInt(kPrefLastBeat, _nowMs());

    // isolate นี้ไม่มี BuildContext แต่ S(lang) ใช้ได้โดยไม่ต้องมี
    // ภาษาต้องอ่านจาก prefs ไม่ใช่ hardcode ไทย ไม่งั้นคนตั้งอังกฤษไว้
    // จะเจอไทยโผล่ในแถบแจ้งเตือนโดยที่ในแอปเป็นอังกฤษหมด
    final t = S(AppLang.fromCode(prefs.getString('lang')));
    final found = await _checkUpdate(prefs, t);

    if (service is AndroidServiceInstance) {
      // การแจ้งเตือนที่ค้างอยู่แล้ว ใช้บอกสิ่งที่เจอไปเลย ดีกว่ายิงอีกอันซ้อน
      await service.setForegroundNotificationInfo(
        title: 'GigGok',
        content: found ?? t.bgWatching,
      );
    }

    // ฝั่ง UI ที่เปิดอยู่จะได้อัปเดตทันที ไม่ต้องรอ reload prefs เอง
    service.invoke('beat', {'at': _nowMs(), 'beats': beats, 'found': found});
  } catch (e) {
    debugPrint('background: จังหวะนี้พลาด — $e');
  }
}

/// ตรวจรุ่นใหม่ · คืนข้อความที่จะเอาไปขึ้นแจ้งเตือน หรือ null ถ้าไม่มีอะไรใหม่
Future<String?> _checkUpdate(SharedPreferences prefs, S t) async {
  final updater = Updater(strings: () => t);
  try {
    final info = await updater.check();
    if (info == null) {
      await prefs.remove(kPrefBgUpdate);
      return null;
    }
    final text = t.bgUpdateFound(info.version);
    await prefs.setString(kPrefBgUpdate, info.version);
    return text;
  } on Exception catch (e) {
    // ไม่มีเน็ตเป็นเรื่องปกติมากตอนอยู่เบื้องหลัง ไม่ใช่ความผิดพลาดที่ต้องรายงาน
    debugPrint('background: ตรวจรุ่นใหม่ไม่ได้ — $e');
    return null;
  } finally {
    updater.dispose();
  }
}

int _nowMs() => DateTime.now().millisecondsSinceEpoch;
