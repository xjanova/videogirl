/// เล่นเสียงเธอออกลำโพงตรง ๆ — ทางสำรองเมื่อเวที 3D รับเสียงไม่ได้
///
/// ## 🔴 ทำไมต้องมีทางสำรอง
///
/// ปกติเสียงไปเล่นใน WebView เพื่อให้ `lipsync.js` อ่านคลื่นแล้วขยับปาก
/// แต่ [MindAvatarController.speakBytes] **คืนเงียบ ๆ ทันที**เมื่อเวทียัง
/// ไม่พร้อม (`_ready == false`) ซึ่งเกิดขึ้นในสามกรณีที่ไม่ได้หายากเลย:
///
/// 1. ยังไม่ได้โหลด avatar pack — APK เปล่าไม่มีตัวเธออยู่ข้างใน
/// 2. เวทีโหลดพัง — `_onError` ตั้ง `_ready = false` แล้วไม่มีวันกลับมา
/// 3. ทักคำแรกเร็วกว่าคลิปท่าทางโหลดเสร็จ ซึ่งกินเวลาหลายวินาที
///
/// ทั้งสามกรณีจบเหมือนกันหมด: TTS สังเคราะห์เสร็จ (เสียเวลา ซีพียู และเงิน
/// ถ้าใช้ OpenAI) แล้วไบต์ถูกโยนทิ้งโดยไม่มีใครรู้ · ผู้ใช้ได้ยินความเงียบ
/// และอ่านว่า "เธอไม่ยอมพูดกับเรา"
///
/// **ปากไม่ขยับดีกว่าไม่มีเสียง** — ตัวนี้เล่นผ่าน MediaPlayer ฝั่งเนทีฟ
/// ตัวเดียวกับที่ใช้ตอนอยู่ในสาย เพียงแต่ออกช่อง media แทนช่องสาย
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../system/permissions.dart';

abstract final class MindAudio {
  /// ช่องเสียงสื่อ (STREAM_MUSIC) — ตรงกับ `CallAudio.STREAM_MEDIA`
  /// ไม่ใช่ช่องสาย เพราะนี่คือการคุยในแอป ไม่ใช่การคุยโทรศัพท์
  static const _stream = 'media';

  static int _seq = 0;

  /// เล่นจนจบแล้วคืน true · false = เล่นไม่ได้จริง ๆ
  static Future<bool> play(Uint8List bytes, {required String mime}) async {
    if (bytes.isEmpty) return false;
    File? file;
    try {
      final dir = await getTemporaryDirectory();
      final ext = mime.contains('wav') ? 'wav' : 'mp3';
      // ชื่อไม่ซ้ำ — ชื่อเดิมทำให้บางเครื่องเล่นไฟล์เก่าที่แคชไว้
      file = File('${dir.path}${Platform.pathSeparator}minde_out_${_seq++}.$ext');
      await file.writeAsBytes(bytes, flush: true);

      // 🔴 มีเวลาหมด · MediaPlayer ที่ไม่ยิง "จบ" (เสียงถูกแย่งช่อง ลำโพง
      // บลูทูธหลุดกลางประโยค) = ปุ่มที่รอประโยคนี้ค้างตลอดกาล
      final ok = await kSystemChannel.invokeMethod<bool>('callSpeak', {
        'path': file.path,
        'stream': _stream,
      }).timeout(limitFor(bytes, mime), onTimeout: () {
        debugPrint('เสียง: ทางสำรองเล่นไม่จบในเวลา — สั่งหยุด');
        unawaited(stop());
        return false;
      });
      return ok == true;
    } on Object catch (e) {
      debugPrint('เสียง: เล่นทางสำรองไม่สำเร็จ — $e');
      return false;
    } finally {
      // ลบทิ้งเสมอ ไม่งั้นคุยทั้งวันจะเหลือไฟล์เสียงค้างเต็ม temp
      // (ฝั่งเนทีฟอ่านจบไปแล้วตอน callSpeak คืนค่า)
      unawaited(file?.delete().catchError((_) => file!) ?? Future<void>.value());
    }
  }

  /// ความยาวเสียงโดยประมาณ (วินาที) · WAV อ่านจากหัวไฟล์ได้เป๊ะ
  /// นอกนั้น (mp3/ogg) คิดที่ 32 kbps ซึ่งต่ำกว่าทุกเจ้าที่ใช้ = ประมาณเกินเสมอ
  @visibleForTesting
  static double secondsOf(Uint8List b, String mime) {
    if (b.length >= 44 &&
        String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(b.sublist(8, 12)) == 'WAVE') {
      final rate = ByteData.sublistView(b).getUint32(28, Endian.little);
      if (rate > 0) return (b.length - 44) / rate;
    }
    return b.length / 4000;
  }

  /// เวลาที่ยอมรอเสียงหนึ่งประโยคเล่นจบ ก่อนถือว่าค้าง
  static Duration limitFor(Uint8List b, String mime) {
    final s = secondsOf(b, mime).clamp(0, 600);
    return Duration(milliseconds: (s * 1500).round() + 8000);
  }

  /// เสียงสื่อของเครื่องปิดสนิทอยู่ไหม · null = ถามไม่ได้ (ไม่ใช่ Android)
  ///
  /// เสียงเธอออกช่องสื่อทั้งสองทาง · ช่องนี้เป็นศูนย์ = เล่น "สำเร็จ" ทุกประโยค
  /// แต่ไม่มีใครได้ยินอะไรเลย ซึ่งจากฝั่งแอปแยกไม่ออกจากเสียงที่ออกปกติ
  static Future<bool?> mediaMuted() async {
    try {
      final v = await kSystemChannel.invokeMethod<Map<Object?, Object?>>('mediaVolume');
      final now = v?['now'];
      return now is int ? now <= 0 : null;
    } on Object {
      return null;
    }
  }

  /// หยุดเสียงที่กำลังเล่นอยู่ทันที
  static Future<void> stop() async {
    try {
      await kSystemChannel.invokeMethod<bool>('callStopSpeak');
    } on Object catch (e) {
      debugPrint('เสียง: สั่งหยุดไม่สำเร็จ — $e');
    }
  }
}
