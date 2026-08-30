import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/avatar/avatar_pack.dart';

/// ชุดตัวมายด์มาจาก zip บนอินเทอร์เน็ต = ข้อมูลที่ไม่ควรเชื่อ
///
/// สองอย่างที่เทสต์นี้ล็อกไว้:
/// 1. รหัสชุดกลายเป็น**ชื่อโฟลเดอร์** ถ้าเดินออกนอกรากได้ การติดตั้งชุด
///    จะกลายเป็นการเขียนทับไฟล์ที่ไหนก็ได้ในพื้นที่ของแอป
/// 2. ชุดที่แพ็กมาไม่เนี้ยบ (ไม่มี pack.json / ชื่อไฟล์ไม่ตรง) ต้องยังใช้ได้
///    เพราะคนทำชุดคือเจ้าของเอง ไม่ใช่โปรแกรมที่แพ็กให้เป๊ะทุกครั้ง
void main() {
  group('รหัสชุดต้องออกนอกโฟลเดอร์ไม่ได้', () {
    test('ทางที่เดินออกนอกราก ถูกล้างจนไม่เหลือ', () {
      for (final bad in ['../../etc', '..', '../', '/', './.']) {
        final got = AvatarPacks.safeId(bad);
        expect(got == null || !got.contains('..'), isTrue,
            reason: '"$bad" ให้ "$got" ซึ่งยังเดินออกนอกโฟลเดอร์ได้');
        expect(got == null || !got.startsWith('.'), isTrue,
            reason: '"$bad" ให้ "$got" ซึ่งเป็นไฟล์ซ่อน');
      }
    });

    test('อักขระแปลก ๆ ถูกแปลงเป็นขีด ไม่ใช่ถูกปฏิเสธทั้งชุด', () {
      expect(AvatarPacks.safeId('Mind Summer!'), 'mind-summer-');
      expect(AvatarPacks.safeId('เลขาคนใหม่'), isNull,
          reason: 'ไทยล้วนไม่เหลืออะไรเลย ต้องคืน null ให้ผู้เรียกไปหาชื่ออื่น');
    });

    test('ว่างเปล่าคืน null ไม่ใช่สตริงว่างที่กลายเป็นโฟลเดอร์ไร้ชื่อ', () {
      expect(AvatarPacks.safeId(null), isNull);
      expect(AvatarPacks.safeId('   '), isNull);
    });

    test('ยาวเกินถูกตัด — ชื่อโฟลเดอร์ยาวเกินพังบนบางระบบไฟล์', () {
      final long = AvatarPacks.safeId('a' * 200);
      expect(long, isNotNull);
      expect(long!.length, lessThanOrEqualTo(48));
    });
  });

  group('อ่านรายละเอียดชุดจากโฟลเดอร์จริง', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('packtest');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('ไม่มี pack.json ก็ยังใช้ได้ — หา .vrm ตัวแรกให้เอง', () async {
      await File('${tmp.path}${Platform.pathSeparator}minde.vrm')
          .writeAsBytes([0]);
      final info = await AvatarPackInfo.read(tmp, 'legacy');
      expect(info, isNotNull);
      expect(info!.model, 'minde.vrm');
      expect(info.kind, AvatarPackKind.character);
    });

    test('pack.json ชี้ไฟล์ที่ไม่มีจริง ต้องตกไปหา .vrm ที่มีจริง', () async {
      await File('${tmp.path}${Platform.pathSeparator}nana.vrm')
          .writeAsBytes([0]);
      await File('${tmp.path}${Platform.pathSeparator}$kPackManifest')
          .writeAsString(jsonEncode({
        'id': 'nana',
        'model': 'พิมพ์ชื่อผิด.vrm',
        'kind': 'outfit',
        'name': {'th': 'นานา', 'en': 'Nana'},
      }));
      final info = await AvatarPackInfo.read(tmp, 'nana');
      expect(info, isNotNull);
      expect(info!.model, 'nana.vrm',
          reason: 'ชื่อผิดในไฟล์ ไม่ควรทำให้ทั้งชุดใช้ไม่ได้');
      expect(info.kind, AvatarPackKind.outfit);
      expect(info.nameFor(true), 'นานา');
      expect(info.nameFor(false), 'Nana');
    });

    test('pack.json เสีย ต้องไม่ทำให้ทั้งชุดพัง', () async {
      await File('${tmp.path}${Platform.pathSeparator}x.vrm').writeAsBytes([0]);
      await File('${tmp.path}${Platform.pathSeparator}$kPackManifest')
          .writeAsString('{ นี่ไม่ใช่ json');
      final info = await AvatarPackInfo.read(tmp, 'broken');
      expect(info, isNotNull, reason: 'มี .vrm อยู่จริง ก็ควรใส่ได้');
      expect(info!.model, 'x.vrm');
    });

    test('ไม่มี .vrm เลย = ไม่ใช่ชุด ต้องคืน null', () async {
      await File('${tmp.path}${Platform.pathSeparator}readme.txt')
          .writeAsString('hi');
      expect(await AvatarPackInfo.read(tmp, 'empty'), isNull);
    });

    test('มี clips.json = ชุดนี้แบ่งคลิปให้ชุดอื่นยืมได้', () async {
      await File('${tmp.path}${Platform.pathSeparator}a.vrm').writeAsBytes([0]);
      await File('${tmp.path}${Platform.pathSeparator}clips.json')
          .writeAsString('[]');
      final info = await AvatarPackInfo.read(tmp, 'base');
      expect(info!.providesClips, isTrue);
    });
  });
}
