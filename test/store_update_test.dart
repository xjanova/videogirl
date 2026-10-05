/// ตัวอัปเดตถาม xman studio ก่อน GitHub
///
/// สิ่งที่ต้องไม่พลาด: ลิงก์ที่ผู้ใช้โหลดต้องมาจากหลังบ้าน (ไม่เห็น GitHub) ·
/// ไม่มี sha256 = ไม่ได้ข้อมูลไปติดตั้ง · หลังบ้านล้ม = ถอยไปทางสำรองได้
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:videogirl/update/updater.dart';

void main() {
  Updater withServer(Object? body, {int status = 200, List<Uri>? seen}) =>
      Updater(
        storeBaseOf: () => 'https://store.test/',
        httpClient: MockClient((req) async {
          seen?.add(req.url);
          return http.Response.bytes(
              utf8.encode(jsonEncode(body)), status,
              headers: {'content-type': 'application/json'});
        }),
      );

  const sha =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  test('ถามปลายทางของบ้านพร้อมรุ่นปัจจุบัน', () async {
    final seen = <Uri>[];
    await withServer({'has_update': false}, seen: seen)
        .checkStoreForTest('0.1.24');
    expect(seen.single.toString(),
        'https://store.test/api/v1/product/giggok/update/check?current_version=0.1.24');
  });

  test('มีรุ่นใหม่ → ได้ลิงก์ของหลังบ้านและ sha256', () async {
    final info = await withServer({
      'has_update': true,
      'latest_version': '0.1.25',
      'download_url': 'https://store.test/giggok/download/0.1.25',
      'changelog': '· ใหม่',
      'sha256': sha.toUpperCase(),
      'file_size': 104857600,
      'filename': 'giggok-0.1.25.apk',
    }).checkStoreForTest('0.1.24');

    expect(info!.version, '0.1.25');
    expect(info.apkUrl, 'https://store.test/giggok/download/0.1.25');
    expect(info.sha256, sha, reason: 'แฮชต้องเป็นตัวเล็ก ไม่งั้นเทียบไม่ตรง');
    expect(info.apkName, 'giggok-0.1.25.apk');
  });

  test('ไม่มีรุ่นใหม่ → ตอบชัดว่าไม่มี (ไม่ใช่ไปถาม GitHub ต่อ)', () async {
    final info = await withServer({'has_update': false}).checkStoreForTest('0.1.24');
    expect(info, isNotNull);
    expect(info!.version, isEmpty);
  });

  test('หลังบ้านไม่รู้จักสินค้า (404) → ทางสำรอง', () async {
    final info = await withServer({'message': 'Product not found'}, status: 404)
        .checkStoreForTest('0.1.24');
    expect(info, isNull);
  });

  test('แฮชผิดรูป → ไม่มีแฮช = ตัวติดตั้งจะปฏิเสธ', () async {
    final info = await withServer({
      'has_update': true,
      'latest_version': '0.1.25',
      'download_url': 'https://store.test/x',
      'sha256': 'not-a-hash',
    }).checkStoreForTest('0.1.24');
    expect(info!.sha256, isNull);
  });

  test('ชื่อไฟล์จากเซิร์ฟเวอร์ที่มี path ถูกตัดทิ้ง', () async {
    final info = await withServer({
      'has_update': true,
      'latest_version': '0.1.25',
      'download_url': 'https://store.test/x',
      'sha256': sha,
      'filename': '../../evil.apk',
    }).checkStoreForTest('0.1.24');
    expect(info!.apkName, 'evil.apk');
  });

  test('หลังบ้านบอกว่าใหม่ แต่ไม่ใหม่กว่าจริง → ไม่พาไปติดตั้งทับ', () async {
    final info = await withServer({
      'has_update': true,
      'latest_version': '0.1.24',
      'download_url': 'https://store.test/x',
      'sha256': sha,
    }).checkStoreForTest('0.1.24');
    expect(info, isNull);
  });
}
