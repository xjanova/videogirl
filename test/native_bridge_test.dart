import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/avatar/avatar_view.dart';
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
  final kotlinDir = Directory('android/app/src/main/kotlin/com/xjanova/videogirl');

  /// ซอร์ส Kotlin **ทุกไฟล์** ต่อกัน
  ///
  /// เคยอ่านแค่ MainActivity.kt แล้วเทสต์รายงานว่า CALL_PHONE ไม่มีใครใช้
  /// ทั้งที่ DialerActivity.kt ใช้อยู่ · ขอบเขตที่แคบกว่าความจริงทำให้
  /// เทสต์กล่าวหาโค้ดที่ถูกต้อง ซึ่งพอเกิดบ่อย ๆ คนจะเริ่มปิดเทสต์ทิ้ง
  late String kotlin;

  /// เฉพาะ MainActivity — ใช้กับด่านที่เกี่ยวกับ when และ KNOWN_REQUESTS
  late String activity;

  setUpAll(() {
    expect(kotlinDir.existsSync(), isTrue,
        reason: 'หาโฟลเดอร์ Kotlin ไม่เจอ — เทสต์นี้ผูกกับที่อยู่ของไฟล์');

    kotlin = kotlinDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.kt'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    activity = File('${kotlinDir.path}/MainActivity.kt').readAsStringSync();
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

  /// 🔴 สายเป็นเรื่องที่พลาดแล้วเห็นตอนสายจริงเท่านั้น
  ///
  /// [CallSession] เรียกเมธอดเนทีฟอีกชุดที่ไม่ได้ผ่าน [MindPermission] เลย
  /// (callInfo · mindAnswer · callSpeak · …) พิมพ์ชื่อผิดตัวเดียว = ได้
  /// `notImplemented` เงียบ ๆ กลางสายจริง แล้วเธอยืนอมพะนำอยู่ในสาย
  /// โดยที่หน้าจอบอกว่ากำลังคุยอยู่
  test('ทุกเมธอดที่ CallSession เรียก ต้องมีอยู่ใน when ของ Kotlin', () {
    final source = File('lib/phone/call_session.dart').readAsStringSync();

    final called = <String>{};
    for (final m in RegExp(r"""_invoke(?:<[^>]*>)?\(\s*'([A-Za-z]+)'""")
        .allMatches(source)) {
      called.add(m.group(1)!);
    }
    for (final m in RegExp(r"""invokeMethod<[^>]*>\(\s*'([A-Za-z]+)'""")
        .allMatches(source)) {
      called.add(m.group(1)!);
    }

    expect(called, isNotEmpty,
        reason: 'อ่านชื่อเมธอดจากซอร์สไม่เจอเลย — รูปแบบโค้ดเปลี่ยนไป '
            'ต้องแก้เทสต์นี้ ไม่ใช่ปล่อยผ่าน');

    final missing = called.where((m) => !kotlin.contains('"$m" ->')).toList();

    expect(missing, isEmpty,
        reason: 'ฝั่ง Kotlin ไม่มีเมธอดพวกนี้ — จะได้ notImplemented เงียบ ๆ '
            'กลางสายจริง:\n${missing.join('\n')}');
  });

  /// 🔴 จอสายเนทีฟอ่านค่าที่ตั้งไว้จากไฟล์ของ shared_preferences ตรง ๆ
  ///
  /// ต้องอ่านเองเพราะตอนสายดัง Flutter engine อาจยังไม่เริ่ม · สะพานนี้
  /// ผูกกันด้วยชื่อคีย์ล้วน ๆ และเมื่อชื่อไม่ตรง **ไม่มี error อะไรเลย**
  /// จอสายจะได้ค่าตั้งต้นทุกครั้ง แล้วสวิตช์ในหน้าตั้งค่าก็ดูเหมือนไม่มีผล
  test('คีย์ที่ MindPrefs อ่าน ต้องเป็นคีย์ที่ MindState เขียนจริง', () {
    final prefs = File('${kotlinDir.path}/MindPrefs.kt').readAsStringSync();
    final state = File('lib/state/mind_state.dart').readAsStringSync();

    final keys = RegExp(r'const val KEY_[A-Z_]+ = "([A-Za-z]+)"')
        .allMatches(prefs)
        .map((m) => m.group(1)!)
        .toList();

    expect(keys, isNotEmpty,
        reason: 'อ่านคีย์จาก MindPrefs.kt ไม่เจอเลย — รูปแบบเปลี่ยนไป '
            'ต้องแก้เทสต์นี้ ไม่ใช่ปล่อยผ่าน');

    final missing = keys.where((k) => !state.contains("_save('$k'")).toList();

    expect(missing, isEmpty,
        reason: 'จอสายเนทีฟอ่านคีย์พวกนี้ แต่ไม่มีใครเขียนลงไป — '
            'จะได้ค่าตั้งต้นตลอดกาลโดยไม่มีอะไรบอก:\n${missing.join(', ')}');
  });

  test('ทุกรหัสคำขอที่ส่งเข้า ask/askMany ต้องอยู่ใน KNOWN_REQUESTS', () {
    // ดึงรหัสที่ถูกใช้จริงในการขอสิทธิ์ ไม่ใช่ทุกค่าคงที่ที่ประกาศไว้
    // (REQ_NOTIFY มีทางตอบของตัวเองแยกต่างหาก จึงไม่ต้องอยู่ในชุดนี้)
    final used = <String>{};
    for (final m in RegExp(r'\bask(?:Many)?\(\s*(?:arrayOf\([^)]*\)|[^,]+),\s*'
            r'(REQ_[A-Z_]+)')
        .allMatches(activity)) {
      used.add(m.group(1)!);
    }

    expect(used, isNotEmpty,
        reason: 'อ่านรหัสคำขอจากซอร์สไม่เจอเลย — รูปแบบโค้ดเปลี่ยนไป '
            'ต้องแก้เทสต์นี้ ไม่ใช่ปล่อยผ่าน');

    final known = RegExp(r'KNOWN_REQUESTS\s*=\s*setOf\(([^)]*)\)')
        .firstMatch(activity)
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

    // เฉพาะ <uses-permission> เท่านั้น
    //
    // `android:permission` ของ <service> เป็นคนละเรื่อง — มันคือสิทธิ์ที่
    // **ผู้อื่นต้องมี**ถึงจะผูกกับบริการเราได้ ไม่ใช่สิทธิ์ที่เราขอ
    // (BIND_INCALL_SERVICE เป็นแบบนั้น) นับรวมแล้วจะกล่าวหาผิด
    final declared = RegExp(
            r'<uses-permission[^>]*android:name="android\.permission\.([A-Z_]+)"')
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

  /// 🔴 อารมณ์ที่ฝั่ง JS ไม่รู้จักถูกปัดเป็น neutral **เงียบ ๆ**
  ///
  /// `setMood()` ใน avatar.js เขียนว่า `m in MOOD_EXPRESSION ? m : 'neutral'`
  /// ส่งชื่อที่ไม่มีไปจึงไม่ได้ error อะไรเลย แค่ไม่มีอะไรเกิดขึ้น
  /// เกิดขึ้นจริงมาแล้วกับ 'waiting' ซึ่งมีคลิปรออยู่แต่ไม่มีวันได้เล่น
  test('ทุกอารมณ์ใน MindMood ต้องมีใน MOOD_EXPRESSION ของ avatar.js', () {
    final js = File('assets/avatar/avatar.js').readAsStringSync();

    final block = RegExp(r'const MOOD_EXPRESSION = \{([\s\S]*?)\n\};')
        .firstMatch(js)
        ?.group(1);

    expect(block, isNotNull,
        reason: 'หา MOOD_EXPRESSION ใน avatar.js ไม่เจอ — รูปแบบเปลี่ยนไป '
            'ต้องแก้เทสต์นี้ ไม่ใช่ปล่อยผ่าน');

    final known = RegExp(r'^\s*(\w+):', multiLine: true)
        .allMatches(block!)
        .map((m) => m.group(1)!)
        .toSet();

    final missing =
        MindMood.values.map((m) => m.name).where((n) => !known.contains(n));

    expect(missing, isEmpty,
        reason: 'อารมณ์พวกนี้จะถูกปัดเป็น neutral เงียบ ๆ ฝั่ง JS: '
            '${missing.join(', ')}');
  });

  /// คลิปที่ผูกกับอารมณ์ต้องผูกกับอารมณ์ที่มีอยู่จริง
  test('mood ใน clips.json ต้องเป็นอารมณ์ที่รู้จัก', () {
    final manifest = File('assets/avatar/model/clips.json');
    if (!manifest.existsSync()) return; // ชุดคลิปไม่ได้อยู่ในเครื่องทุกที่

    final clips = (jsonDecode(manifest.readAsStringSync())
        as Map<String, dynamic>)['clips'] as List;

    // 'speaking' ไม่ใช่อารมณ์จริง — เป็นคลังท่าตอนพูด ดู docs/packs.md
    final known = {...MindMood.values.map((m) => m.name), 'speaking'};

    final bad = <String>[];
    for (final c in clips) {
      for (final m in ((c as Map)['mood'] as List? ?? const [])) {
        if (!known.contains('$m')) bad.add('${c['id']}: $m');
      }
    }

    expect(bad, isEmpty,
        reason: 'คลิปพวกนี้ผูกกับอารมณ์ที่ไม่มีอยู่ จะไม่มีวันได้เล่น: '
            '${bad.join(', ')}');
  });
}
