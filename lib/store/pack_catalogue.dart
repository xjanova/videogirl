/// ร้านชุด — ฝั่งแอป
///
/// คุยกับหลังบ้าน xman studio ตามสัญญาใน `docs/pack-store.md`
/// ที่นั่นแอดมินเพิ่มชุดและตั้งราคาได้เอง โดยไม่ต้องออกแอปใหม่
///
/// 🔴 **ลิงก์ไฟล์ต้องขอตอนจะโหลดเท่านั้น** ไม่ใช่มากับแค็ตตาล็อก
/// ถ้าลิงก์ `.zip` มากับรายการสินค้าตั้งแต่แรก การจ่ายเงินจะกลายเป็นเรื่อง
/// สมัครใจ — คนแรกที่เปิดร้านก็เอาลิงก์ไปแจกได้เลยโดยไม่ต้องซื้อด้วยซ้ำ
///
/// **ยังไม่มีหลังบ้านจริงตอนนี้** — คลาสนี้เขียนตามสัญญาที่ตกลงไว้แล้ว
/// เวลาเรียกแล้วต่อไม่ติดจะขึ้นสถานะบอกตรง ๆ ว่าติดต่อร้านไม่ได้
/// ไม่ใช่ขึ้นร้านเปล่าที่อ่านได้ว่า "ไม่มีของขาย"
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../avatar/avatar_pack.dart';

/// ที่อยู่หลังบ้าน — ตั้งตอน build ได้ และแก้ในแอปได้
const kStoreBaseDefault =
    String.fromEnvironment('STORE_BASE_URL', defaultValue: '');

enum ShopStage { idle, loading, ready, failed }

enum ShopError {
  /// ยังไม่ได้ตั้งที่อยู่ร้าน
  noUrl,

  /// ต่อไม่ติด หรือร้านยังไม่เปิด
  unreachable,

  /// ยังไม่ได้ยืนยันสิทธิ์ (ไลเซนส์)
  noLicense,
}

/// สินค้าหนึ่งชิ้นในร้าน
@immutable
class ShopItem {
  const ShopItem({
    required this.id,
    required this.nameTh,
    required this.nameEn,
    required this.kind,
    required this.price,
    required this.currency,
    required this.sizeBytes,
    this.preview,
    this.requires,
    this.owned = false,
  });

  final String id;
  final String nameTh;
  final String nameEn;
  final AvatarPackKind kind;

  /// 0 = แจกฟรี
  final double price;
  final String currency;

  /// ขนาดไฟล์ — ต้องบอกก่อนโหลด คนใช้ 4G ควรได้รู้ว่ากำลังจะโหลด 35MB
  final int sizeBytes;

  final String? preview;

  /// ต้องมีตัวละครตัวไหนก่อน (สำหรับชุดเสื้อผ้า) — null = ใช้ได้เดี่ยว
  final String? requires;

  final bool owned;

  String nameFor(bool thai) => thai ? nameTh : nameEn;

  String get sizeLabel => '${(sizeBytes / 1048576).toStringAsFixed(0)} MB';

  ShopItem withOwned(bool v) => ShopItem(
        id: id,
        nameTh: nameTh,
        nameEn: nameEn,
        kind: kind,
        price: price,
        currency: currency,
        sizeBytes: sizeBytes,
        preview: preview,
        requires: requires,
        owned: v,
      );

  /// อ่านจาก JSON แบบทนความไม่เนี้ยบ — ช่องที่ขาดไม่ควรทำให้ทั้งรายการหาย
  static ShopItem? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}'.trim();
    if (id.isEmpty) return null;

    final name = raw['name'];
    final th = name is Map ? '${name['th'] ?? id}' : '${name ?? id}';
    final en = name is Map ? '${name['en'] ?? th}' : th;

    return ShopItem(
      id: id,
      nameTh: th,
      nameEn: en,
      kind: AvatarPackKind.parse(raw['kind']),
      price: (raw['price'] as num?)?.toDouble() ?? 0,
      currency: '${raw['currency'] ?? 'THB'}',
      sizeBytes: (raw['sizeBytes'] as num?)?.toInt() ?? 0,
      preview: raw['preview'] as String?,
      requires: raw['requires'] as String?,
    );
  }
}

class PackCatalogue extends ChangeNotifier {
  PackCatalogue({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  ShopStage _stage = ShopStage.idle;
  ShopStage get stage => _stage;

  ShopError? _error;
  ShopError? get error => _error;

  final List<ShopItem> _items = [];
  List<ShopItem> get items => List.unmodifiable(_items);

  /// ดึงรายการสินค้า และสิทธิ์ครอบครองถ้ามีไลเซนส์
  ///
  /// [licenseKey] ไม่มีก็เรียกได้ — จะได้แค่รายการสินค้า ไม่รู้ว่าซื้ออะไรไปแล้ว
  /// ซึ่งยังมีประโยชน์ คนยังไม่ซื้อก็ควรเห็นว่ามีอะไรขายบ้าง
  Future<void> load(String baseUrl, {String? licenseKey}) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) {
      _set(ShopStage.failed, ShopError.noUrl);
      return;
    }

    _set(ShopStage.loading, null);
    try {
      final res = await _http
          .get(Uri.parse('$base/api/packs'),
              headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (res.statusCode >= 400) {
        _set(ShopStage.failed, ShopError.unreachable);
        return;
      }

      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final list = body is Map ? body['packs'] : body;
      if (list is! List) {
        _set(ShopStage.failed, ShopError.unreachable);
        return;
      }

      _items
        ..clear()
        ..addAll(list.map(ShopItem.fromJson).whereType<ShopItem>());

      if (licenseKey != null && licenseKey.isNotEmpty) {
        await _markOwned(base, licenseKey);
      }
      _set(ShopStage.ready, null);
    } on Exception catch (e) {
      // ร้านยังไม่เปิดเป็นเรื่องปกติตอนนี้ ไม่ใช่ความผิดพลาดที่ต้องดังโครม
      debugPrint('shop: ต่อร้านไม่ติด — $e');
      _set(ShopStage.failed, ShopError.unreachable);
    }
  }

  /// ทาบสิทธิ์ครอบครองลงบนรายการที่มีอยู่
  ///
  /// แยกคำขอออกจากแค็ตตาล็อกตามสัญญา เพราะแค็ตตาล็อกแคชได้ยาว
  /// แต่สิทธิ์เปลี่ยนทันทีที่จ่ายเงินเสร็จ
  Future<void> _markOwned(String base, String licenseKey) async {
    try {
      final res = await _http.get(
        Uri.parse('$base/api/packs/mine'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $licenseKey',
        },
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode >= 400) return;

      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final owned = (body is Map ? body['owned'] : body);
      if (owned is! List) return;
      final ids = owned.map((e) => '$e').toSet();

      for (var i = 0; i < _items.length; i++) {
        _items[i] = _items[i].withOwned(ids.contains(_items[i].id));
      }
    } on Exception catch (e) {
      // รู้รายการสินค้าแล้วแต่ไม่รู้ว่าซื้ออะไรไป — ยังดีกว่าไม่เห็นร้านเลย
      debugPrint('shop: อ่านสิทธิ์ครอบครองไม่ได้ — $e');
    }
  }

  /// ขอลิงก์โหลดของชิ้นที่ซื้อแล้ว
  ///
  /// คืน null ถ้ายังไม่ได้ซื้อ (403) หรือไลเซนส์หมดอายุ (401)
  /// ลิงก์ที่ได้มีอายุสั้น ต้องเอาไปโหลดทันที อย่าเก็บไว้ใช้ทีหลัง
  Future<({String url, String? sha256})?> downloadLink(
    String baseUrl,
    String licenseKey,
    String id,
  ) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    try {
      final key = licenseKey.trim();
      final res = await _http.post(
        Uri.parse('$base/api/packs/$id/download'),
        headers: {
          'Accept': 'application/json',
          // ไม่มีไลเซนส์ = **ไม่ส่งหัวข้อนี้เลย** ไม่ใช่ส่ง "Bearer " เปล่า ๆ
          // ของฟรีโหลดได้โดยไม่ต้องมีไลเซนส์ แต่หัวข้อ Authorization ที่ว่าง
          // เป็นค่าที่ผิดรูป WAF/พร็อกซีบางตัวตัดทิ้งหรือตอบ 400 กลับมา
          // ซึ่งจะกลายเป็น "โหลดของฟรีไม่ได้" โดยที่หลังบ้านไม่ผิดอะไรเลย
          if (key.isNotEmpty) 'Authorization': 'Bearer $key',
        },
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode >= 400) {
        debugPrint('shop: ขอลิงก์ไม่ได้ HTTP ${res.statusCode}');
        return null;
      }
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is! Map) return null;
      final url = '${body['url'] ?? ''}';
      if (url.isEmpty) return null;
      return (url: url, sha256: body['sha256'] as String?);
    } on Exception catch (e) {
      debugPrint('shop: ขอลิงก์ไม่ได้ — $e');
      return null;
    }
  }

  void _set(ShopStage s, ShopError? e) {
    _stage = s;
    _error = e;
    notifyListeners();
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}
