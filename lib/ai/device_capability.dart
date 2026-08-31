/// อ่านแรมของเครื่องแล้วบอกว่าไหวรุ่นไหน
///
/// ทำไมต้องเช็ค: Gemma 4 E2B กินพื้นที่ 2 GB และแรมตอนรันอีกก้อน
/// ส่วน GigGok เองก็แบก WebView + three.js + โมเดล VRM 33 MB อยู่แล้ว
/// ถ้าปล่อยให้เครื่องแรม 4 GB โหลด E4B มา ระบบจะฆ่าแอปทิ้งกลางคัน
/// และผู้ใช้จะเสียเน็ตโหลดฟรี 3 GB โดยไม่ได้อะไรเลย
///
/// **ผลตรวจเก็บเป็น "ระดับ" ไม่ใช่ข้อความ** — ข้อความผูกกับภาษา
/// ถ้าเก็บเป็นไทยตั้งแต่ตอนตรวจ พอสลับเป็นอังกฤษก็แปลไม่ได้แล้ว
library;

import 'package:flutter/foundation.dart';
import 'package:system_info_plus/system_info_plus.dart';

import 'local_brain.dart';

/// ระดับความไหวของเครื่อง
enum RamTier { unknown, tooSmall, tight, comfortable, roomy }

/// สิ่งที่เครื่องนี้ไหว
@immutable
class DeviceVerdict {
  const DeviceVerdict({
    required this.ramMb,
    required this.tier,
    required this.best,
    required this.allowed,
  });

  /// แรมที่ Android รายงาน (MB) — null ถ้าอ่านไม่ได้
  final int? ramMb;

  final RamTier tier;

  /// รุ่นที่แนะนำ — null แปลว่าไม่ควรใช้สมองในเครื่องเลย
  final GemmaVariant? best;

  /// รุ่นที่ยอมให้เลือกได้ทั้งหมด
  final List<GemmaVariant> allowed;

  bool get canRunLocal => best != null;

  /// แรมเป็น GB ทศนิยมหนึ่งตำแหน่ง สำหรับเสียบเข้าข้อความ
  String get gb => ramMb == null ? '?' : (ramMb! / 1024).toStringAsFixed(1);
}

abstract final class DeviceCapability {
  /// แรมที่เครื่องรายงาน หน่วย MB
  ///
  /// เบื้องหลังคือ `ActivityManager.MemoryInfo.totalMem` ซึ่ง**น้อยกว่า**แรม
  /// ที่เขียนบนกล่องเสมอ เพราะเคอร์เนลกันไว้ส่วนหนึ่งตั้งแต่บูต
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

  /// เกณฑ์ขั้นต่ำเป็น GB ทศนิยมหนึ่งตำแหน่ง — สำหรับเสียบเข้าข้อความที่ผู้ใช้อ่าน
  ///
  /// อ่านจากค่าคงที่ตัวเดียวกับที่ใช้ตัดสินจริง ไม่ใช่พิมพ์เลขซ้ำในข้อความ
  /// ไม่งั้นวันที่ขยับเกณฑ์ หน้าจอจะบอกเลขเก่าโดยไม่มีอะไรเตือน
  static String get minLocalGb => (_minForLocal / 1024).toStringAsFixed(1);

  static DeviceVerdict verdictFor(int? ramMb) {
    if (ramMb == null || ramMb <= 0) {
      return const DeviceVerdict(
        ramMb: null,
        tier: RamTier.unknown,
        best: null,
        allowed: GemmaVariant.values,
      );
    }

    if (ramMb < _minForLocal) {
      return DeviceVerdict(
        ramMb: ramMb,
        tier: RamTier.tooSmall,
        best: null,
        allowed: const [],
      );
    }

    if (ramMb < _comfortableForE2b) {
      return DeviceVerdict(
        ramMb: ramMb,
        tier: RamTier.tight,
        best: GemmaVariant.e2bGpu,
        allowed: const [GemmaVariant.e2bGpu],
      );
    }

    if (ramMb < _minForE4b) {
      return DeviceVerdict(
        ramMb: ramMb,
        tier: RamTier.comfortable,
        best: GemmaVariant.e2bGpu,
        allowed: const [GemmaVariant.e2bGpu, GemmaVariant.e2bCpu],
      );
    }

    return DeviceVerdict(
      ramMb: ramMb,
      tier: RamTier.roomy,
      best: GemmaVariant.e4bGpu,
      allowed: GemmaVariant.values,
    );
  }

  /// อ่านแรมแล้วสรุปในขั้นตอนเดียว
  static Future<DeviceVerdict> detect() async => verdictFor(await totalRamMb());
}
