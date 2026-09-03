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

      final ok = await kSystemChannel.invokeMethod<bool>('callSpeak', {
        'path': file.path,
        'stream': _stream,
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

  /// หยุดเสียงที่กำลังเล่นอยู่ทันที
  static Future<void> stop() async {
    try {
      await kSystemChannel.invokeMethod<bool>('callStopSpeak');
    } on Object catch (e) {
      debugPrint('เสียง: สั่งหยุดไม่สำเร็จ — $e');
    }
  }
}
