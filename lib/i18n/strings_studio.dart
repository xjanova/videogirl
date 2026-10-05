import 'strings.dart';

/// ข้อความของสตูดิโอ — เวทีเต็มจอสำหรับวิดีโอคอล ไลฟ์ และอัดคลิป
extension StudioStrings on S {
  String get studioOpen => pick('สตูดิโอวิดีโอ', 'Video studio');
  String get studioExit => pick('ออกจากสตูดิโอ', 'Leave studio');
  String get studioNoAvatar => pick(
        'ต้องมีตัวเธอบนเวทีก่อน ถึงจะเข้าสตูดิโอได้',
        'She needs to be on stage before the studio can open',
      );

  /// วิธีใช้ — บอกความจริงข้อจำกัดของ Android ไปพร้อมกัน
  String get studioHowTo => pick(
        'วิดีโอคอล: ในแอปที่คุยอยู่ กด "แชร์หน้าจอ" แล้วกลับมาหน้านี้ '
            'คู่สายจะเห็นเธอเต็มจอ · ปิดกล้องในแอปนั้นด้วย ไม่งั้นจะแย่งกล้องหน้า\n'
            'แตะจอเพื่อเรียกปุ่ม · ปุ่มหายเองเพื่อไม่ให้ติดไปในภาพ',
        'Video calls: in your call app, tap "Share screen", then come back here '
            'and they will see her full-screen · turn that app\'s camera off, '
            'or it will fight her for the front camera\n'
            'Tap the screen for controls · they hide themselves so they stay out of the picture',
      );

  // ── ฉากหลัง ──
  String get studioBackdrop => pick('ฉากหลัง', 'Backdrop');
  String get studioBackdropApp => pick('พื้นแอป', 'App');
  String get studioBackdropGreen => pick('เขียว', 'Green');
  String get studioBackdropBlue => pick('ฟ้า', 'Blue');
  String get studioBackdropMagenta => pick('บานเย็น', 'Magenta');
  String get studioBackdropBlack => pick('ดำ', 'Black');
  String get studioBackdropWhite => pick('ขาว', 'White');
  String get studioBackdropCustom => pick('สีเอง', 'Custom');
  String get studioKeyTip => pick(
        'ฉากสีนี้ตัดพื้นออกได้ (chroma key) ในแอปไลฟ์หรือ OBS — '
            'เลือกสีที่ไม่มีในชุดของเธอ',
        'This colour can be keyed out (chroma key) in live apps or OBS — '
            'pick one that is not in her outfit',
      );
  String get studioCustomTitle => pick('ใส่รหัสสีฉากหลัง', 'Backdrop colour code');
  String get studioCustomHint => pick('เช่น #00b140', 'e.g. #00b140');
  String get studioCustomBad => pick(
        'รหัสสีไม่ถูก ต้องเป็น # ตามด้วยเลขฐานสิบหก 6 ตัว',
        'Not a colour code — use # followed by 6 hex digits',
      );

  // ── กล้อง ──
  String get studioFollowFace => pick('ให้หน้าเธอตามหน้าเรา', 'Mirror my face');
  String get studioFollowFaceOff => pick('เลิกตามหน้าเรา', 'Stop mirroring');
  String get studioShot => pick('ระยะภาพ', 'Shot');

  // ── จอลอย ──
  String get studioPip => pick('จอลอย', 'Float');
  String get studioPipUnsupported => pick(
        'เครื่องนี้เปิดจอลอยไม่ได้ (ไม่รองรับ หรือปิดสิทธิ์ไว้ในตั้งค่าเครื่อง)',
        'Floating window is unavailable (unsupported, or turned off in system settings)',
      );

  // ── อัดคลิป ──
  String get studioRecord => pick('อัดคลิป', 'Record');
  String get studioStop => pick('หยุดอัด', 'Stop');
  String get studioRecMic => pick('อัดเสียงไมค์ด้วย', 'Include my mic');
  String get studioRecMicNote => pick(
        'ปิดไว้ = คลิปมีแต่เสียงเธอ ไม่มีเสียงในห้อง',
        'Off = the clip has only her voice, no room sound',
      );
  String get studioRecSaving => pick('กำลังบันทึกคลิป…', 'Saving the clip…');
  String studioRecSaved(String where) =>
      pick('บันทึกคลิปลงแกลเลอรีแล้ว · $where', 'Clip saved to your gallery · $where');
  String get studioRecGap => pick(
        'บางช่วงขาดหายระหว่างอัด คลิปอาจสะดุดตรงนั้น',
        'Part of the recording went missing — the clip may skip there',
      );
  String get studioRecFailed => pick(
        'เครื่องนี้อัดคลิปจากเวทีไม่ได้',
        'This device cannot record the stage',
      );
  String get studioRecEmpty => pick(
        'ไม่ได้ภาพอะไรเลย คลิปนี้จึงไม่ถูกบันทึก',
        'Nothing was captured, so no clip was saved',
      );
  String get studioSaveFailed => pick(
        'บันทึกคลิปลงแกลเลอรีไม่สำเร็จ',
        'Could not save the clip to your gallery',
      );
  String get studioSaveNeedsFiles => pick(
        'ต้องให้สิทธิ์เขียนไฟล์ก่อน ถึงจะบันทึกคลิปลงแกลเลอรีได้',
        'File access is needed to save clips to your gallery',
      );
  String get studioMicDenied => pick(
        'ไม่ได้สิทธิ์ไมค์ — คลิปนี้มีเฉพาะเสียงเธอ',
        'No microphone permission — this clip has only her voice',
      );
  String get studioMicFailed => pick(
        'เปิดไมค์ไม่ได้ — คลิปนี้มีเฉพาะเสียงเธอ',
        'The microphone would not start — this clip has only her voice',
      );
  String get studioRecLimit => pick(
        'ครบ 30 นาที หยุดอัดให้แล้ว · อัดต่อได้เป็นคลิปใหม่',
        'Reached 30 minutes, so recording stopped · start again for a new clip',
      );
  String get studioRecBackground => pick(
        'แอปถูกพับลงระหว่างอัด จึงหยุดอัดและบันทึกส่วนที่ได้ไว้แล้ว',
        'The app went to the background, so recording stopped and what was captured was saved',
      );
}
