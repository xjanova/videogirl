/// อ่านแรมของเครื่องแล้วบอกว่าไหวรุ่นไหน
///
/// ทำไมต้องเช็ค: Gemma 4 E2B กินพื้นที่ 2 GB และแรมตอนรันอีกก้อน
/// ส่วน GigGok เองก็แบก WebView + three.js + โมเดล VRM 33 MB อยู่แล้ว
/// ถ้าปล่อยให้เครื่องแรม 4 GB โหลด E4B มา ระบบจะฆ่าแอปทิ้งกลางคัน
/// และผู้ใช้จะเสียเน็ตโหลดฟรี 3 GB โดยไม่ได้อะไรเลย
library;
import 'package:flutter/foundation.dart';
import 'package:system_info_plus/system_info_plus.dart';

import 'local_brain.dart';


/// สิ่งที่เครื่องนี้ไหว
@immutable
class DeviceVerdict {
  const DeviceVerdict({
    required this.ramMb,
    required this.best,
    required this.allowed,
    required this.headline,
    required this.detail,
  });

  /// แรมที่ Android รายงาน (MB) — null ถ้าอ่านไม่ได้
  final int? ramMb;

  /// รุ่นที่แนะนำ — null แปลว่าไม่ควรใช้สมองในเครื่องเลย
  final GemmaVariant? best;

  /// รุ่นที่ยอมให้เลือกได้ทั้งหมด
  final List<GemmaVariant> allowed;

  final String headline;
  final String detail;

  bool get canRunLocal => best != null;

  String get ramLabel =>
      ramMb == null ? 'อ่านแรมไม่ได้' : '${(ramMb! / 1024).toStringAsFixed(1)} GB';
}

abstract final class DeviceCapability {
  /// แรมที่เครื่องรายงาน หน่วย MB
  ///
  /// เบื้องหลังคือ `ActivityManager.MemoryInfo.totalMem` ซึ่ง**น้อยกว่า**แรม
  /// ที่เขียนบนกล่องเสมอ เพราะเคอร์เนลกันไว้ส่วนหนึ่งตั้งแต่บูต
  /// เครื่องที่โฆษณาว่า 8 GB มักรายงานราว 7.2–7.6 GB
  /// เกณฑ์ข้างล่างจึงตั้งบนตัวเลข "ที่รายงาน" ไม่ใช่ตัวเลขบนกล่อง
  static Future<int?> totalRamMb() async {
    try {
      return await SystemInfoPlus.physicalMemory;
    } on Exception catch (e) {
      debugPrint('อ่านแรมไม่ได้ — $e');
      return null;
    }
  }

  // เกณฑ์ (หน่วย MB ที่ระบบรายงาน)
  //
  // ประมาณการที่ใช้ตั้งเกณฑ์:
  //   GigGok เปล่า ๆ  ~0.6–1.0 GB (Flutter + WebView + three.js + VRM 33MB)
  //   Gemma E2B ตอนรัน ~1.2–2.0 GB (น้ำหนัก ~0.8GB + embedding 1.12GB แบบ mmap)
  //   Gemma E4B ตอนรัน มากกว่านั้นอีกราวหนึ่งเท่าตัวของส่วนน้ำหนัก
  //
  // Android ปล่อยให้แอปหน้าจอใช้ได้จริงราวครึ่งเดียวของ totalMem
  // ก่อน low-memory killer จะเริ่มทำงาน จึงต้องเผื่อเยอะกว่าที่คิด
  // ⚠️ ตัวเลขพวกนี้เทียบกับ "แรมที่ระบบรายงาน" ซึ่งต่ำกว่าเลขบนกล่อง 10–12%
  // วัดจริงบนอีมูเลเตอร์ Android 14: ตั้ง 2560 MiB -> MemTotal 2474.7 MiB (ขาด 3.33%)
  // นั่นคือพื้นต่ำสุดเพราะอีมูเลเตอร์ไม่มี carveout ของ OEM เลย
  // เครื่องจริงโดน modem/TEE/GPU/ISP กันไปอีก จึงขาดมากกว่านั้น
  //
  // ถ้าตั้งเกณฑ์เท่ากับเลขบนกล่อง (เช่น 8192 สำหรับเครื่อง 8GB)
  // **เครื่อง 8GB จริงจะตกเกณฑ์ทุกเครื่อง** จึงต้องตั้งไว้ระหว่างชั้น
  //
  //   ชั้น 4GB  รายงานราว 3500–3800
  //   ชั้น 6GB  รายงานราว 5300–5600
  //   ชั้น 8GB  รายงานราว 7000–7600
  //   ชั้น 12GB รายงานราว 10800+
  static const _minForLocal = 4600; // เหนือชั้น 4GB ใต้ชั้น 6GB
  static const _comfortableForE2b = 6600; // เหนือชั้น 6GB ใต้ชั้น 8GB
  static const _minForE4b = 9500; // เหนือชั้น 8GB ใต้ชั้น 12GB

  static DeviceVerdict verdictFor(int? ramMb) {
    if (ramMb == null || ramMb <= 0) {
      return const DeviceVerdict(
        ramMb: null,
        best: null,
        allowed: GemmaVariant.values,
        headline: 'อ่านแรมเครื่องไม่ได้',
        detail: 'เลือกรุ่นเองได้ แต่ถ้าเครื่องแรมน้อยกว่า 6 GB '
            'แนะนำให้ใช้ OpenAI หรือเซิร์ฟเวอร์ในบ้านแทน',
      );
    }

    if (ramMb < _minForLocal) {
      return DeviceVerdict(
        ramMb: ramMb,
        best: null,
        allowed: const [],
        headline: 'เครื่องนี้แรมไม่พอสำหรับสมองในเครื่อง',
        detail: 'ระบบรายงานแรม ${(ramMb / 1024).toStringAsFixed(1)} GB '
            'ซึ่งไม่พอจะแบกทั้งอวาตาร์ 3D และโมเดลภาษาพร้อมกัน\n'
            'แนะนำให้ใช้ OpenAI หรือเซิร์ฟเวอร์ในบ้านแทน '
            'จะได้ไม่เสียเน็ตโหลด 2 GB ฟรี ๆ แล้วแอปเด้งกลางทาง',
      );
    }

    if (ramMb < _comfortableForE2b) {
      return DeviceVerdict(
        ramMb: ramMb,
        best: GemmaVariant.e2bGpu,
        allowed: const [GemmaVariant.e2bGpu],
        headline: 'ไหว แต่ตึงมือ',
        detail: 'ระบบรายงานแรม ${(ramMb / 1024).toStringAsFixed(1)} GB '
            'ใช้ E2B แบบ GPU ได้ (ไฟล์เล็กที่สุด 2.0 GB)\n'
            'ปิดแอปอื่นก่อนคุยจะลื่นกว่า และอาจสะดุดบ้างตอนอวาตาร์ขยับพร้อมกัน',
      );
    }

    if (ramMb < _minForE4b) {
      return DeviceVerdict(
        ramMb: ramMb,
        best: GemmaVariant.e2bGpu,
        allowed: const [GemmaVariant.e2bGpu, GemmaVariant.e2bCpu],
        headline: 'ไหวสบาย',
        detail: 'ระบบรายงานแรม ${(ramMb / 1024).toStringAsFixed(1)} GB '
            'ใช้ E2B ได้ทั้งแบบ GPU และ CPU\n'
            'E4B ยังไม่แนะนำสำหรับเครื่องนี้ เพราะต้องแบกอวาตาร์ 3D ไปพร้อมกัน',
      );
    }

    return DeviceVerdict(
      ramMb: ramMb,
      best: GemmaVariant.e4bGpu,
      allowed: GemmaVariant.values,
      headline: 'เครื่องแรง ใช้รุ่นใหญ่ได้',
      detail: 'ระบบรายงานแรม ${(ramMb / 1024).toStringAsFixed(1)} GB '
          'ใช้ E4B ได้ ซึ่งฉลาดกว่า E2B ชัดเจน\n'
          'ถ้าอยากให้ตอบไวกว่าโดยยอมลดความฉลาดลงหน่อย เลือก E2B แทนได้',
    );
  }

  /// อ่านแรมแล้วสรุปในขั้นตอนเดียว
  static Future<DeviceVerdict> detect() async => verdictFor(await totalRamMb());
}
