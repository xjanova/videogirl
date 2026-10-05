/// บันทึกล่าสุดของแอป — วงแหวนในหน่วยความจำ
///
/// ## ทำไมดัก `debugPrint` แทนที่จะเขียน logger ตัวใหม่
///
/// ในแอปนี้มี `debugPrint` อยู่แล้ว **112 จุด** และเกือบทุกจุดเป็นบรรทัดที่
/// เขียนไว้ตอนไล่บั๊กจริง (`เสียง: …ไม่สำเร็จ`, `สมอง: ล้มแบบที่ไม่ได้เตรียมรับไว้`)
/// การเปลี่ยนไปใช้ logger ตัวใหม่คือการแก้ 112 จุดเพื่อให้ได้ข้อความชุดเดิม
/// และจะมีจุดที่ลืม แล้วบรรทัดที่สำคัญที่สุดจะเป็นจุดที่ลืมพอดี
///
/// `debugPrint` เป็นตัวแปรระดับไลบรารีที่**เขียนทับได้** จึงดักได้ทั้งหมด
/// ในที่เดียวโดยไม่ต้องแตะ call site สักจุด
///
/// ## 🔴 ของที่อยู่ในนี้ยังไม่ปลอดภัยพอจะส่งออก
///
/// บรรทัด log เขียนขึ้นตอนไล่บั๊ก ไม่ได้เขียนขึ้นเพื่อให้คนนอกอ่าน — บางบรรทัด
/// มีข้อความของผู้ใช้หรือข้อความดิบของ error ติดมาด้วย · ตัวที่ประกอบรายงาน
/// ([DebugReport]) เป็นคนล้างก่อนเสมอ **ห้ามส่ง `lines` ออกไปตรง ๆ**
library;

import 'package:flutter/foundation.dart';

abstract final class MindLog {
  /// เก็บกี่บรรทัด
  ///
  /// 300 มาจากการชั่ง: การเปิดแอปหนึ่งครั้งเขียนราว 40–80 บรรทัด เก็บ 300
  /// จึงครอบคลุมเหตุการณ์ก่อนหน้าปัญหาได้หลายรอบ · มากกว่านี้กินแรมโดยที่
  /// บรรทัดเก่ากว่านั้นแทบไม่เคยช่วยอธิบายอะไร
  static const capacity = 300;

  static final List<String> _lines = <String>[];

  /// สำเนาที่แก้ไม่ได้ · เรียงเก่า→ใหม่
  static List<String> get lines => List.unmodifiable(_lines);

  static int get count => _lines.length;

  static bool _installed = false;

  /// เวลาเริ่มแอป — ใช้ทำเวลาสัมพัทธ์ในแต่ละบรรทัด
  ///
  /// ใช้เวลาสัมพัทธ์ ไม่ใช่นาฬิกาจริง เพราะเวลาจริงของเครื่องเป็นข้อมูลที่
  /// พาไปหาตัวคนได้ (โซนเวลา = ประเทศ) และสิ่งที่คนไล่บั๊กต้องการคือ
  /// **ลำดับกับระยะห่าง** ไม่ใช่ว่ามันเกิดตอนบ่ายสองหรือบ่ายสาม
  static final DateTime _bootAt = DateTime.now();

  /// เริ่มดัก · เรียกครั้งเดียวตอนแอปเริ่ม
  ///
  /// ยังพิมพ์ออก console เหมือนเดิมทุกบรรทัด — ตัวนี้เป็นการ**แยกสำเนา**
  /// ไม่ใช่การเปลี่ยนทาง · ถ้ากลืนไป การไล่บั๊กด้วย logcat จะพังทันที
  static void install() {
    if (_installed) return;
    _installed = true;

    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message == null) return original(message, wrapWidth: wrapWidth);
      final kept = scrub(message);
      if (kept == null) return;
      add(kept);
      original(kept, wrapWidth: wrapWidth);
    };
  }

  /// บรรทัดของปลั๊กอินสมองที่**พิมพ์ข้อความสนทนาออกมาทั้งก้อน**
  ///
  /// 🔴 flutter_gemma พิมพ์ทุกอย่างที่ส่งเข้าโมเดล (รวมบทสนทนาที่เล่าย้อน)
  /// และทุกคำที่เธอตอบ ลง `debugPrint` · บรรทัดพวกนั้นมาอยู่ในวงแหวนนี้ แล้ว
  /// ไหลไปกับรายงานบั๊กที่ส่งออกนอกเครื่อง — ทั้งที่สัญญาของสมองในเครื่องคือ
  /// "คุยอะไรไม่ออกนอกเครื่อง" · และตอนสตรีมมันพิมพ์**ทุกคำสามรอบ**
  /// ซึ่งดันบรรทัดที่ใช้ไล่บั๊กจริงตกวงแหวนไปหมด
  ///
  /// ตัวที่พิมพ์ทีละคำ: ทิ้งเลย · ตัวที่พิมพ์ทั้งก้อน: เก็บว่าเกิดขึ้น ไม่เก็บเนื้อหา
  static const _perToken = [
    'InferenceChat: Received filtered token',
    'InferenceChat: Emitting text token',
    'InferenceChat: No function processing, emitting token',
  ];
  static const _wholeText = [
    'Current Message:',
    'InferenceChat: Raw response from native model',
    'InferenceChat: Complete response accumulated',
    'InferenceChat: Created message object',
  ];

  /// คืนบรรทัดที่ปลอดภัยจะเก็บ · null = ทิ้งทั้งบรรทัด
  @visibleForTesting
  static String? scrub(String message) {
    for (final p in _perToken) {
      if (message.startsWith(p)) return null;
    }
    for (final p in _wholeText) {
      if (message.startsWith(p)) return '$p [content removed, ${message.length} chars]';
    }
    return message;
  }

  static void add(String message) {
    final t = DateTime.now().difference(_bootAt);
    final s = (t.inMilliseconds / 1000).toStringAsFixed(1).padLeft(7);
    _lines.add('[$s] $message');
    if (_lines.length > capacity) {
      _lines.removeRange(0, _lines.length - capacity);
    }
  }

  static void clear() => _lines.clear();
}
