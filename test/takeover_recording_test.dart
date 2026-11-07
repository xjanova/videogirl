/// เจ้าของแทรกสายแล้ว เสียงอัดต้องมีทั้งสองฝั่ง
///
/// เจ้าของ: "การอัดเสียงสนทนา ถ้าเจ้าของกดแทรกพูดเอง การอัดเสียง อีกฝ่าย จะไม่ได้ยิน ได้ยินแต่เสียงเจ้าของ
/// ที่มีความก้อง ด้วย" · ของเดิมเปิด VOICE_UPLINK ซ้อน VOICE_DOWNLINK · HAL ที่มีทางอัดในสายทางเดียว
/// ส่งเสียงขาออกให้ทั้งสองตัว = เสียงเจ้าของสองชั้นห่างกันไม่กี่มิลลิวินาที (ก้อง) และไม่มีคู่สายเลย
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src = File('android/app/src/main/java/com/xjanova/videogirl/direct/DirectAudioServer.java').readAsStringSync();
  String body() {
    final start = src.indexOf('boolean startOwnerCapture()');
    var depth = 0;
    for (var i = src.indexOf('{', start); i < src.length; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}' && --depth == 0) return src.substring(start, i + 1);
    }
    fail('ปีกกาไม่ครบ');
  }

  test('🔴 แทรกสาย = อัดทางเดียว VOICE_CALL แทนที่ downlink · ไม่เปิดสองทางซ้อนกัน', () {
    final b = body();
    expect(b, contains('MediaRecorder.AudioSource.VOICE_CALL'));
    expect(b, isNot(contains('VOICE_UPLINK')), reason: 'สองทางพร้อมกัน = เสียงเจ้าของซ้อนสองชั้น');
    final release = b.indexOf('release(old)');
    expect(release, greaterThan(0));
    expect(b.indexOf('VOICE_CALL'), greaterThan(release), reason: 'ปิดตัวเก่าก่อนเปิดตัวใหม่');
    expect(b.indexOf('down=null'), lessThan(release), reason: 'ตัวอ่านเก่าต้องรู้ว่าถูกปิดเอง ไม่ใช่สายหลุด');
  });

  test('🔴 เปิด VOICE_CALL ไม่ได้ = กลับไปอัดคู่สายเหมือนเดิม · ไม่ทิ้งคู่สาย', () {
    final b = body();
    final fallback = b.indexOf('catch(Exception e)');
    expect(b.indexOf('VOICE_DOWNLINK', fallback), greaterThan(fallback));
    expect(b.substring(fallback), contains('return false;'), reason: 'แอปจดว่าอัดเจ้าของไม่ได้');
  });

  test('จบ session แล้วเริ่มสายใหม่ด้วย downlink ตามปกติ', () {
    expect(src, contains('down=null; up=null; callCapture=false;'));
  });
}
