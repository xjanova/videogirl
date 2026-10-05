import 'dart:typed_data';

import 'avatar_view.dart' show MindMocapShot;

/// ปากของเธอสำหรับเสียงที่**ไม่ได้เล่นบนเวที** — เสียงเธอในสายโทรศัพท์
///
/// ## 🔴 ทำไมต้องมี
///
/// ตอนอยู่ในสาย เสียงเธอออกทางเนทีฟ (ช่องเสียงสาย) เพื่อให้ไมค์รับเข้าสาย
/// ห้ามดังจากเวทีซ้ำ · ของเดิมปากจึง "พึมพำ" แบบสุ่มไปตลอดทั้งสาย รวมทั้ง
/// ตอนที่คู่สายพูดและเธอควรเงียบฟัง · ตอนนี้เวทีเล่นไฟล์เดียวกันแบบปิดเสียง
/// แล้วอ่านคลื่นไปขยับปาก ปากจึงตรงกับคำที่เธอพูดจริง
///
/// สองจังหวะ: [prepareLips] ถอดไฟล์ให้พร้อมก่อน (ใช้เวลาไม่แน่นอน) แล้ว
/// [startLips] ปล่อยพร้อมกับที่เนทีฟเริ่มเล่น · [restLips] ปิดปากเมื่อจบ
/// หรือถูกตัด — ต้องเรียกทุกครั้งหลัง prepare ไม่ว่าผลจะเป็นอย่างไร
///
/// แยกเป็น interface เพื่อให้ [CallSession] ไม่ต้องรู้จัก WebView และเทสต์ได้
abstract interface class MindLips {
  /// คืน false = เวทีรับไม่ได้ (ฝั่งเวทีตกไปพึมพำแทนเองจนกว่าจะ [restLips])
  Future<bool> prepareLips(Uint8List bytes, {required String mime});

  /// [lead] = หน่วงปากไว้ให้ตรงกับเสียงที่ออกลำโพงจริงของฝั่งเนทีฟ
  Future<void> startLips({Duration lead});

  Future<void> restLips();
}

/// สิ่งที่สตูดิโอสั่งเวที — แยกเป็น interface ให้ [MindStudio] เทสต์ได้โดยไม่มี WebView
abstract interface class StudioStage {
  /// เวทีพร้อมรับคำสั่งหรือยัง · ยังไม่พร้อม = คำสั่งทุกตัวหายเงียบ
  /// (ดู `_call` ใน avatar_view.dart) จึงต้องกันไว้ตั้งแต่ทางเข้า
  bool get ready;

  Future<void> setStudio(bool on);

  /// null = พื้นโปร่ง · '#rrggbb' = ฉากสีทึบ
  Future<void> setBackdrop(String? hex);

  /// บอกช็อตให้เวทีรู้แน่ ๆ แม้ค่าเท่าเดิม
  Future<void> syncMocapShot(MindMocapShot s);

  Future<MindRecStart> startRecording({required bool mic});
  Future<void> stopRecording();

  MindRecordingSink? get recordingSink;
  set recordingSink(MindRecordingSink? sink);
}

/// ผู้รับคลิปที่เวทีอัดอยู่ — ก้อนละวินาที เรียงตามลำดับ
abstract interface class MindRecordingSink {
  void recChunk(int seq, Uint8List bytes);

  /// ก้อนสุดท้ายส่งครบแล้ว · [chunks] = จำนวนก้อนทั้งหมดที่ฝั่งเวทีนับได้
  void recDone(String mime, int chunks);

  void recFailed(String why);
}

/// ผลของการสั่งเริ่มอัด
class MindRecStart {
  const MindRecStart({required this.ok, this.mime = '', this.mic = false, this.why});

  const MindRecStart.failed(String this.why)
      : ok = false,
        mime = '',
        mic = false;

  final bool ok;

  /// ชนิดไฟล์ที่เครื่องนี้อัดได้จริง (mp4 หรือ webm แล้วแต่ WebView)
  final String mime;

  /// ไมค์ติดจริงไหม · ขอแล้วไม่ติด = อัดต่อด้วยเสียงเธออย่างเดียว
  final bool mic;

  /// เหตุผลดิบ — ของนักพัฒนา ไม่ใช่ของผู้ใช้
  final String? why;
}
