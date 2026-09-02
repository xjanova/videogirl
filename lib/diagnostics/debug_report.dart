/// รายงานดีบัคที่ส่งให้ผู้พัฒนาได้ — **โดยไม่พาข้อมูลของเจ้าของไปด้วย**
///
/// ## 🔴 กฎที่ไม่ยอมแลก
///
/// แอปนี้สัญญากับผู้ใช้ไว้ว่า **ถ้าเลือกสมองในเครื่อง ไม่มีอะไรออกนอกเครื่อง**
/// (ดู docs/security.md) · ตัวเก็บข้อมูลดีบัคคือสิ่งที่ทำลายสัญญานั้นได้ง่าย
/// ที่สุดในทั้งแอป เพราะมันมีเหตุผลที่ฟังดูดีอยู่แล้วว่าทำไมต้องส่งออกไป
///
/// สามข้อที่บังคับไว้ในโค้ด ไม่ใช่แค่ตั้งใจ:
///
/// 1. **ส่งเมื่อเจ้าของกดเท่านั้น** ไม่มีการส่งอัตโนมัติ ไม่มีตัวตั้งเวลา
///    ไม่มีการส่งตอนแอปพัง — ทุกทางที่ส่งเองได้คือทางที่เจ้าของไม่ได้เลือก
/// 2. **เห็นก่อนส่งเสมอ** หน้าจอโชว์รายงานทั้งฉบับตามที่จะส่งจริง
///    ไม่ใช่คำอธิบายว่าส่งอะไรบ้าง — คำอธิบายกับของจริงเพี้ยนจากกันได้
/// 3. **ไม่มีเนื้อหา มีแต่รูปทรง** จำนวนข้อความ ไม่ใช่ข้อความ · ชื่อรุ่นที่เลือก
///    ไม่ใช่คีย์ · สถานะว่ามีคีย์ไหม ไม่ใช่ตัวคีย์
///
/// ## สิ่งที่ห้ามอยู่ในรายงาน ไม่ว่าทางไหน
///
/// คีย์ OpenAI · รหัสสิทธิ์ · บทสนทนา · ความจำ · ไทม์ไลน์ · เบอร์โทร · ชื่อคน
/// ในสมุดโทรศัพท์ · เนื้อหาในปฏิทิน · เวลาจริงของเครื่อง
library;

import 'dart:convert';
import 'dart:io';

import '../memory/mind_memory.dart' show looksLikeSecret;
import 'mind_log.dart';

/// รูปทรงของเครื่องและของแอป ที่พอจะไล่ปัญหาได้โดยไม่ต้องรู้ว่าใครใช้
typedef ReportFacts = Map<String, Object?>;

abstract final class DebugReport {
  /// รุ่นของรูปแบบรายงาน — ฝั่งหลังบ้านใช้แยกว่าจะอ่านยังไง
  ///
  /// ขึ้นเลขเมื่อ**ลบหรือเปลี่ยนความหมาย**ของฟิลด์ ไม่ใช่ตอนเพิ่มฟิลด์ใหม่
  /// (ผู้อ่านที่เขียนไว้ดีจะข้ามฟิลด์ที่ไม่รู้จักอยู่แล้ว)
  static const version = 1;

  /// เครื่องหมายแทนบรรทัดที่ถูกตัดออก
  ///
  /// **ไม่แปลตามภาษา**โดยตั้งใจ · รายงานถูกอ่านโดยคนไล่บั๊ก ไม่ใช่โดยเจ้าของ
  /// เครื่อง · เครื่องหมายที่เปลี่ยนภาษาไปตามเครื่องที่ส่งมา ทำให้ค้นรายงาน
  /// ทั้งกองด้วยคำเดียวไม่ได้ · และคำนี้อ่านออกทั้งสองภาษาอยู่แล้ว
  /// ASCII ล้วน — เครื่องมือที่ใช้ค้นรายงานทั้งกอง (grep, ช่องค้นในแอดมิน)
  /// เจอปัญหาการเข้ารหัสกับอักขระนอก ASCII บ่อยพอที่จะไม่คุ้มเสี่ยง
  static const redactedMark = '[redacted - looked like a secret]';

  /// ยาวเกินนี้ตัด — บรรทัด log ที่ยาวผิดปกติมักคือของที่ไม่ควรอยู่ในนั้น
  /// (สแตกเทรซทั้งดุ้น หรือข้อความที่หลุดมา) และไม่มีใครอ่านจนจบอยู่ดี
  static const maxLineChars = 400;

  /// ประกอบรายงาน
  ///
  /// [secrets] คือค่าจริงของความลับที่แอปถืออยู่ (คีย์ รหัสสิทธิ์) — ส่งเข้ามา
  /// เพื่อ**ค้นแล้วลบทิ้ง**จากทุกบรรทัด · การรู้ค่าจริงทำให้ลบได้แน่นอนกว่า
  /// การเดารูปแบบ ซึ่งเป็นด่านที่สองต่างหาก
  static ReportFacts build({
    required ReportFacts app,
    required ReportFacts device,
    required ReportFacts settings,
    required ReportFacts status,
    required ReportFacts counts,
    required List<String> errors,
    Iterable<String> secrets = const [],
    List<String>? logLines,
  }) {
    String wash(String s) => redact(s, secrets: secrets);
    return {
      'report': version,
      'app': app,
      'device': device,
      'settings': settings,
      'status': status,
      'counts': counts,
      'errors': [for (final e in errors) wash(e)],
      'log': [for (final l in logLines ?? MindLog.lines) wash(l)],
    };
  }

  /// สิ่งที่แอปรู้เกี่ยวกับเครื่อง โดยไม่ถามอะไรที่ชี้ตัวคนได้
  ///
  /// 🔴 ไม่เอา: หมายเลขเครื่อง (ANDROID_ID / IMEI) · ชื่อเครื่องที่ผู้ใช้ตั้งเอง
  /// (มักเป็นชื่อคน) · เวลาจริง (โซนเวลา = ประเทศ) · ภาษาของระบบ
  ///
  /// `Platform.operatingSystemVersion` คืนรุ่นแอนดรอยด์กับหมายเลข build ของ ROM
  /// ซึ่งเป็นสิ่งที่ต้องรู้จริงตอนไล่บั๊กเฉพาะรุ่น และเหมือนกันทั้งล้านเครื่อง
  static ReportFacts deviceFacts({String? ramGb, String? ramTier}) => {
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'ramGb': ?ramGb,
        'ramTier': ?ramTier,
      };

  /// ล้างความลับออกจากข้อความหนึ่งบรรทัด
  ///
  /// สองด่าน เพราะด่านเดียวไม่พอ:
  /// 1. **ค่าจริงที่เรารู้** — แทนที่ตรง ๆ แน่นอนที่สุด แต่รู้เฉพาะที่แอปถืออยู่
  /// 2. **รูปแบบที่เข้าข่ายความลับ** ([looksLikeSecret] ตัวเดียวกับที่กันไม่ให้
  ///    เธอจำรหัสผ่าน) — จับของที่เราไม่รู้ค่า เช่นเลขบัตรที่ผู้ใช้เผลอพิมพ์
  ///    แล้วมันไปโผล่ใน log
  static String redact(String input, {Iterable<String> secrets = const []}) {
    var s = input;

    for (final secret in secrets) {
      final v = secret.trim();
      // สั้นเกินไปแทนที่ไม่ได้ · 'a' จะกลืนตัวอักษร a ทั้งบรรทัด
      if (v.length < 8) continue;
      s = s.replaceAll(v, '••••');
    }

    // ทั้งบรรทัดเข้าข่าย = ทิ้งทั้งบรรทัด ดีกว่าเดาว่าส่วนไหนคือความลับ
    if (looksLikeSecret(s)) return redactedMark;

    return s.length <= maxLineChars
        ? s
        : '${s.substring(0, maxLineChars - 1)}…';
  }

  /// รายงานในรูปแบบที่คนอ่านออก — ใช้ทั้งบนหน้าจอพรีวิวและในไฟล์ที่บันทึก
  ///
  /// ตัวเดียวกันทั้งสองที่โดยตั้งใจ · พรีวิวที่ไม่ใช่ของจริงคือพรีวิวที่โกหก
  static String pretty(ReportFacts report) =>
      const JsonEncoder.withIndent('  ').convert(report);

  /// ชื่อไฟล์ที่บอกได้ว่าอันไหนของรอบไหน โดยไม่บอกเวลาจริงของเครื่อง
  ///
  /// ใช้เวลา UTC — เวลาท้องถิ่นในชื่อไฟล์คือการบอกโซนเวลาโดยไม่ตั้งใจ
  static String fileName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    final u = now.toUtc();
    return 'giggok-debug-${u.year}${two(u.month)}${two(u.day)}'
        '-${two(u.hour)}${two(u.minute)}${two(u.second)}.json';
  }
}
