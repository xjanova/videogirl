/// รูปหน้าที่โหมดเชิดหุ่นขับได้ — คิ้ว ตา ปาก อารมณ์ ลิ้น
///
/// 🔴 **สีหน้าเป็นสิ่งที่ล้มเงียบที่สุดในแอปนี้**
///
/// `expressionManager.setValue('ชื่อที่โมเดลไม่มี')` เป็น no-op เงียบ ๆ และ
/// morph target ที่ไม่มีก็เหมือนกัน · ตาเปล่าแยกไม่ออกระหว่าง "ยังไม่ถึงรอบ"
/// กับ "สั่งชื่อผิดมาตลอด" — เคยเกิดจริงกับ `lookUp/Down/Left/Right` ที่โหมด
/// เชิดหุ่นสั่งไปทั้งเซสชันโดยไม่มีอะไรเกิดขึ้นเลย
///
/// เทสต์นี้อ่าน **ไฟล์ .vrm จริง** แล้วเทียบกับชื่อที่โค้ดจะสั่ง จึงจับได้
/// ตั้งแต่ตอน build ว่าอันไหนจะเงียบ
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// ชื่อ morph ทั้งหมดในไฟล์ · null = ไม่มีไฟล์โมเดลในเครื่องนี้
Set<String>? _morphNames(File vrm) {
  final bytes = vrm.readAsBytesSync();
  final data = ByteData.sublistView(bytes);

  // glb: magic 'glTF', version, length · แล้วต่อด้วยก้อน JSON
  if (data.getUint32(0, Endian.little) != 0x46546C67) return null;
  final jsonLen = data.getUint32(12, Endian.little);
  final gltf = jsonDecode(
      utf8.decode(bytes.sublist(20, 20 + jsonLen))) as Map<String, dynamic>;

  final names = <String>{};
  for (final m in (gltf['meshes'] as List? ?? const [])) {
    final mesh = m as Map<String, dynamic>;
    for (final n in ((mesh['extras'] as Map?)?['targetNames'] as List? ??
        const [])) {
      names.add('$n');
    }
    for (final p in (mesh['primitives'] as List? ?? const [])) {
      for (final n in (((p as Map)['extras'] as Map?)?['targetNames'] as List? ??
          const [])) {
        names.add('$n');
      }
    }
  }
  return names;
}

void main() {
  final vrm = File('assets/avatar/model/minde.vrm');
  final js = File('assets/avatar/morphs.js');
  final mocap = File('assets/avatar/mocap.js');
  final avatar = File('assets/avatar/avatar.js');

  group('ชั้นขับ morph', () {
    test('morphs.js รู้จักความสามารถที่โหมดเชิดหุ่นสั่งจริง', () {
      final code = js.readAsStringSync();
      // ทุกตัวที่ avatar.js สั่ง ต้องมีรายชื่อ morph รออยู่ใน morphs.js
      // ไม่งั้น `set()` จะคืน false ทุกครั้งโดยไม่มีใครสังเกต
      for (final cap in [
        'browUp',
        'browDown',
        'browSorrow',
        'browJoy',
        'eyeWide',
        'tongue',
      ]) {
        expect(code, contains('$cap:'),
            reason: 'avatar.js สั่ง $cap แต่ morphs.js ไม่รู้จัก');
      }
    });

    test('🔴 ต้องเขียน morph หลัง vrm.update() เสมอ', () {
      final code = avatar.readAsStringSync();
      final update = code.indexOf('vrm.update(dt);');
      final brows = code.indexOf('this._brows();');

      expect(update, greaterThan(0));
      expect(brows, greaterThan(update),
          reason: 'เขียนก่อน vrm.update ตัวจัดการ expression อาจล้างทิ้ง '
              'แล้วคิ้วจะไม่ขยับเลยโดยไม่มี error');
    });

    test('🔴 เลิกเชิดแล้วต้องล้างค่ากลับเป็นศูนย์', () {
      // กับดักเดียวกับ lookUp/Down ที่เคยโดนมาแล้ว — ปิดโหมดตอนเลิกคิ้วอยู่
      // แล้วคิ้วค้างอย่างนั้นทั้งเซสชัน ไม่มีทางกลับนอกจากปิดแอป
      expect(avatar.readAsStringSync(), contains('m.clear()'));
      expect(js.readAsStringSync(), contains('clear()'));
    });
  });

  group('สัญญาณจากกล้อง', () {
    test('เก็บ blendshape ที่ต้องใช้ครบ', () {
      final code = mocap.readAsStringSync();
      for (final shape in [
        // กระพริบตา / หลับตา
        'eyeBlinkLeft', 'eyeBlinkRight',
        // คิ้ว — ต้องมีทั้งในและนอก ไม่งั้นแยก "เศร้า" จาก "ตกใจ" ไม่ได้
        'browInnerUp', 'browOuterUpLeft', 'browDownLeft',
        // ยิ้ม
        'mouthSmileLeft', 'mouthSmileRight',
        // ยิ้มแบบสบายใจ ต้องดูตาด้วย
        'eyeSquintLeft', 'eyeSquintRight',
        // แลบลิ้น
        'tongueOut',
      ]) {
        expect(code, contains("'$shape'"),
            reason: '$shape ไม่ได้ถูกเก็บ สัญญาณนั้นจึงเป็นศูนย์ตลอดกาล');
      }
    });

    test('อารมณ์ครบห้าตัวตามที่ VRM มี', () {
      final code = mocap.readAsStringSync();
      for (final e in ['happy', 'sad', 'surprised', 'angry', 'relaxed']) {
        expect(code, contains('emote.$e'),
            reason: 'VRM มี expression $e แต่ไม่มีอะไรขับมัน');
      }
    });
  });

  group('เทียบกับไฟล์โมเดลจริง', () {
    test('ชื่อ morph ที่ morphs.js เดาไว้ ต้องตรงกับที่โมเดลมีจริง', () {
      if (!vrm.existsSync()) return; // ชุดตัวละครไม่ได้อยู่ในเครื่องทุกที่
      final names = _morphNames(vrm);
      if (names == null || names.isEmpty) return;

      // คิ้วเป็นเหตุผลทั้งหมดที่ชั้นนี้มีอยู่ — ถ้าชื่อไม่ตรง คิ้วจะไม่ขยับ
      for (final n in [
        'Fcl_BRW_Surprised',
        'Fcl_BRW_Angry',
        'Fcl_BRW_Sorrow',
        'Fcl_BRW_Joy',
      ]) {
        expect(names, contains(n),
            reason: 'morphs.js เล็ง $n แต่โมเดลไม่มี — คิ้วจะเงียบ');
      }
    });

    /// 🔴 ข้อเท็จจริงที่ต้องบันทึกไว้ ไม่ใช่ความล้มเหลว
    ///
    /// โมเดล VRoid มาตรฐาน **ไม่มี morph ลิ้น** · `Fcl_HA_*` คือ 歯 (ฟัน)
    /// กับ 牙 (เขี้ยว) ไม่ใช่ลิ้น · แลบลิ้นจึงทำไม่ได้กับชุดที่แถมมา
    /// จนกว่าจะมีคนปั้นลิ้นใส่ชุดใหม่
    ///
    /// เทสต์นี้ไม่ได้บังคับให้มีลิ้น — มันบันทึกว่า **วันนี้ยังไม่มี** และจะ
    /// ดังขึ้นเมื่อมีชุดที่มีลิ้นเข้ามา ซึ่งเป็นวันที่ต้องมาลบเทสต์นี้ทิ้ง
    test('บันทึกไว้: ชุดที่แถมมายังไม่มี morph ลิ้น', () {
      if (!vrm.existsSync()) return;
      final names = _morphNames(vrm);
      if (names == null || names.isEmpty) return;

      final tongue = names.where((n) =>
          n.toLowerCase().contains('tng') ||
          n.toLowerCase().contains('tongue') ||
          n.contains('ベロ'));

      expect(tongue, isEmpty,
          reason: 'มีลิ้นแล้ว! ลบเทสต์นี้ทิ้งได้ และ morphs.js จะขับมันเอง');
    });

    test('expression ที่โค้ดสั่ง มีอยู่ในโมเดลจริง', () {
      if (!vrm.existsSync()) return;
      final names = _morphNames(vrm);
      if (names == null || names.isEmpty) return;

      // VRM expression ผูกกับ Fcl_ALL_* — ห้าตัวนี้คืออารมณ์ทั้งหมดที่มี
      for (final n in [
        'Fcl_ALL_Joy',
        'Fcl_ALL_Sorrow',
        'Fcl_ALL_Angry',
        'Fcl_ALL_Surprised',
        'Fcl_ALL_Fun',
      ]) {
        expect(names, contains(n));
      }
      // กระพริบตาแยกข้าง
      expect(names, containsAll(['Fcl_EYE_Close_L', 'Fcl_EYE_Close_R']));
    });
  });
}
