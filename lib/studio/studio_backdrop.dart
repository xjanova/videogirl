import 'dart:ui';

/// ฉากหลังของสตูดิโอ — เก็บเป็นสตริงเดียว: `app` หรือ `#rrggbb`
///
/// สตริงเพราะฝั่งเวที (avatar.js `setBackdrop`) รับรหัสสีตรง ๆ และสีที่เจ้าของ
/// ตั้งเองต้องเก็บได้โดยไม่ต้องมี enum ตัวใหม่ทุกสี
abstract final class StudioBackdrops {
  /// พื้นไล่สีของแอป — สวยบนจอ แต่ตัดพื้นออกไม่ได้
  static const app = 'app';

  /// เขียวคีย์มาตรฐาน (chroma green) — ห่างจากสีผิวที่สุด แอปไลฟ์/OBS ตัดง่ายสุด
  static const green = '#00b140';

  /// ฟ้าคีย์มาตรฐาน — ใช้เมื่อชุดหรือผมของเธอมีสีเขียว
  static const blue = '#0047bb';

  /// ชมพูบานเย็น — ทางสุดท้ายเมื่อชุดมีทั้งเขียวและฟ้า
  static const magenta = '#ff00ff';

  static const black = '#000000';
  static const white = '#ffffff';

  static const presets = [app, green, blue, magenta, black, white];

  static final _hex = RegExp(r'^#[0-9a-f]{6}$');

  /// ค่าที่อ่านมาจากที่เก็บ · เพี้ยน/ว่าง = พื้นของแอป
  static String parse(Object? v) {
    final s = '${v ?? ''}'.trim().toLowerCase();
    if (_hex.hasMatch(s)) return s;
    return app;
  }

  /// รับรหัสสีที่ผู้ใช้พิมพ์เอง (มีหรือไม่มี # ก็ได้) · null = ไม่ใช่รหัสสี
  static String? fromInput(String raw) {
    var s = raw.trim().toLowerCase();
    if (!s.startsWith('#')) s = '#$s';
    return _hex.hasMatch(s) ? s : null;
  }

  /// ค่าที่ส่งให้เวที · null = พื้นโปร่ง
  static String? toStage(String v) => v == app ? null : v;

  /// เป็นฉากสำหรับตัดพื้น (คีย์สี) ไหม — ใช้บอกเคล็ดลับให้ถูกเรื่อง
  static bool isKey(String v) => v == green || v == blue || v == magenta;

  static Color colorOf(String v) {
    if (v == app) return const Color(0xFFF1E9FF);
    return Color(0xFF000000 | int.parse(v.substring(1), radix: 16));
  }
}
