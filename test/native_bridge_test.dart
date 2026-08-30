import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/system/permissions.dart';

/// ด่านกันสะพาน Dart↔Kotlin หลุดจากกัน
///
/// สองฝั่งนี้ผูกกันด้วย**ชื่อสตริง**เท่านั้น คอมไพเลอร์ไม่มีทางรู้ว่ามันตรงกัน
/// และเมื่อไม่ตรง มันไม่พังดัง ๆ — มันเงียบ:
///
/// - ชื่อเมธอดไม่ตรง → `notImplemented` → ปุ่มกดแล้วไม่มีอะไรเกิดขึ้น
/// - รหัสคำขอไม่อยู่ใน KNOWN_REQUESTS → **Future ค้างตลอดกาล** และเพราะ
///   [MindPermissions] ตั้ง `_busy` ไว้จนกว่าจะได้คำตอบ **ปุ่มขอสิทธิ์ทั้งแอป
///   ตายตามไปด้วยทั้งเซสชัน**
///
/// อันหลังเกิดขึ้นจริงมาแล้ว: `onRequestPermissionsResult` เคยรับเฉพาะรหัส
/// กล้องกับไมค์ สิทธิ์ทุกตัวที่เพิ่มทีหลังจึงค้างหมดโดยไม่มี error สักบรรทัด
///
/// เทสต์พวกนี้อ่านซอร์ส Kotlin ตรง ๆ ซึ่งหยาบแต่**จับได้ตอนรันเทสต์**
/// ไม่ใช่ตอนผู้ใช้กดปุ่มบนเครื่องจริงแล้วเงียบ
void main() {
  final activity =
      File('android/app/src/main/kotlin/com/xjanova/videogirl/MainActivity.kt');

  late String kotlin;

  setUpAll(() {
    expect(activity.existsSync(), isTrue,
        reason: 'หา MainActivity.kt ไม่เจอ — เทสต์นี้ผูกกับที่อยู่ของไฟล์');
    kotlin = activity.readAsStringSync();
  });

  test('ทุกเมธอดที่ฝั่ง Dart เรียก ต้องมีอยู่ใน when ของ Kotlin', () {
    final missing = <String>[];

    for (final p in MindPermission.values) {
      for (final method in [p.check, p.ask]) {
        // มองหา `"ชื่อ" ->` ซึ่งเป็นรูปของ when ในไฟล์นั้น
        if (!kotlin.contains('"$method" ->')) missing.add('${p.name}: $method');
      }
    }

    expect(missing, isEmpty,
        reason: 'ฝั่ง Kotlin ไม่มีเมธอดพวกนี้ — จะได้ notImplemented เงียบ ๆ:\n'
            '${missing.join('\n')}');
  });

  test('ทุกรหัสคำขอที่ส่งเข้า ask/askMany ต้องอยู่ใน KNOWN_REQUESTS', () {
    // ดึงรหัสที่ถูกใช้จริงในการขอสิทธิ์ ไม่ใช่ทุกค่าคงที่ที่ประกาศไว้
    // (REQ_NOTIFY มีทางตอบของตัวเองแยกต่างหาก จึงไม่ต้องอยู่ในชุดนี้)
    final used = <String>{};
    for (final m in RegExp(r'\bask(?:Many)?\(\s*(?:arrayOf\([^)]*\)|[^,]+),\s*'
            r'(REQ_[A-Z_]+)')
        .allMatches(kotlin)) {
      used.add(m.group(1)!);
    }

    expect(used, isNotEmpty,
        reason: 'อ่านรหัสคำขอจากซอร์สไม่เจอเลย — รูปแบบโค้ดเปลี่ยนไป '
            'ต้องแก้เทสต์นี้ ไม่ใช่ปล่อยผ่าน');

    final known = RegExp(r'KNOWN_REQUESTS\s*=\s*setOf\(([^)]*)\)')
        .firstMatch(kotlin)
        ?.group(1);

    expect(known, isNotNull, reason: 'ไม่มี KNOWN_REQUESTS ใน MainActivity.kt');

    final missing = used.where((r) => !known!.contains(r)).toList();

    expect(missing, isEmpty,
        reason: 'รหัสพวกนี้ขอสิทธิ์ได้แต่ไม่มีใครตอบ — Future จะค้างตลอดกาล\n'
            'และปุ่มขอสิทธิ์ทั้งแอปจะตายทั้งเซสชัน:\n${missing.join(', ')}');
  });

  test('ทุกสิทธิ์ที่ขอในแอป ต้องประกาศไว้ใน manifest', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    // สิทธิ์ที่ Kotlin ขอผ่าน Manifest.permission.X หรือสตริงเต็ม
    final asked = <String>{};
    for (final m
        in RegExp(r'Manifest\.permission\.([A-Z_]+)').allMatches(kotlin)) {
      asked.add(m.group(1)!);
    }

    final missing = asked
        .where((p) => !manifest.contains('android.permission.$p'))
        .toList();

    expect(missing, isEmpty,
        reason: 'ขอสิทธิ์ที่ไม่ได้ประกาศใน manifest = ระบบปฏิเสธทันที '
            'โดยไม่ขึ้นกล่องให้ผู้ใช้เห็นด้วยซ้ำ:\n${missing.join(', ')}');
  });

  test('สิทธิ์ที่ประกาศใน manifest ต้องมีคนใช้จริง', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    // สิทธิ์ที่ระบบให้เองตอนติดตั้ง ไม่ต้องมีโค้ดขอ
    const installTime = {
      'INTERNET',
      'FOREGROUND_SERVICE',
      'FOREGROUND_SERVICE_DATA_SYNC',
      'RECEIVE_BOOT_COMPLETED',
      'WAKE_LOCK',
      'VIBRATE',
      // สามตัวนี้ขอผ่าน Intent ไปหน้าตั้งค่า ไม่ได้ผ่าน Manifest.permission
      'REQUEST_INSTALL_PACKAGES',
      'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      'POST_NOTIFICATIONS',
    };

    final declared = RegExp(r'android\.permission\.([A-Z_]+)')
        .allMatches(manifest)
        .map((m) => m.group(1)!)
        .toSet()
        .difference(installTime);

    final unused = declared.where((p) => !kotlin.contains(p)).toList();

    // สิทธิ์ที่ขอไปโดยไม่ได้ใช้ คือสิ่งที่ผู้ใช้จำได้ตอนกดปฏิเสธ
    // และทำให้ตอนที่ต้องใช้จริงขอยากขึ้น
    expect(unused, isEmpty,
        reason: 'ประกาศไว้แต่ไม่มีโค้ดไหนใช้ — เอาออกหรือใช้ให้จริง:\n'
            '${unused.join(', ')}');
  });
}
