/// เด้งบอกเองเมื่อมีรุ่นใหม่ ไม่ต้องรอเจ้าของเดินไปหน้าตั้งค่า
///
/// เจ้าของ (2026-11-01): "ระบบอัพเดท ควรเด้งขึ้นมาเมื่อมีเวอร์ชั่นใหม่ไม่ใช่เหรอ" ·
/// ของเดิมเช็คแค่ตอนการ์ดอัปเดตในหน้าตั้งค่าถูกวาด กับในแจ้งเตือนของบริการ
/// เบื้องหลัง (เฉพาะคนที่เปิดสวิตช์เฝ้างาน) · คนที่ไม่เปิดหน้าตั้งค่าจึงไม่รู้เลย
///
/// กติกา
/// - เช็คหลังหน้าเปิดแอปหายไปแล้ว และตอนกลับเข้าแอปเมื่อเช็คครั้งล่าสุดนานเกิน
///   [recheckEvery] · แอปโทรศัพท์ถูกพักและเปิดกลับบ่อยมาก ยิงทุกครั้งไม่ได้
/// - บริการเบื้องหลังเจอรุ่นที่ยังไม่ได้บอก = เช็คทันทีไม่รอรอบ · คนแตะ
///   แจ้งเตือน "มีรุ่นใหม่" แล้วเข้าแอปมาต้องเจอกล่องเลย
/// - "ไว้ทีหลัง" = ไม่ถามรุ่นนี้อีก [snoozeFor] · รุ่นที่ใหม่กว่าถามทันที
/// - ไม่โหลดหรือติดตั้งเอง ต้องกดเองเสมอ (หลักเดียวกับการ์ดในหน้าตั้งค่า)
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../background/mind_background.dart' show kPrefBgUpdate;

class UpdatePrompt {
  UpdatePrompt({
    Future<SharedPreferences> Function()? prefs,
    DateTime Function()? now,
  })  : _prefs = prefs ?? SharedPreferences.getInstance,
        _now = now ?? DateTime.now;

  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _now;

  static const recheckEvery = Duration(minutes: 30);
  static const snoozeFor = Duration(hours: 12);

  static const kPrefSnoozeVersion = 'updateSnoozeVersion';
  static const kPrefSnoozeUntil = 'updateSnoozeUntil';

  /// เช็คครั้งล่าสุดในโปรเซสนี้ · ไม่เก็บลงเครื่องโดยตั้งใจ เปิดแอปใหม่ = เช็คเลย
  DateTime? _lastCheck;

  /// รุ่นจากบริการเบื้องหลังที่รู้แล้ว · เจอค่าใหม่ = เช็คทันที
  String? _bgSeen;

  /// ถึงเวลาถามหลังบ้านหรือยัง
  Future<bool> due() async {
    String? bg;
    try {
      final p = await _prefs();
      await p.reload(); // isolate เบื้องหลังเขียนค่านี้ ฝั่งนี้ไม่รู้เอง
      bg = p.getString(kPrefBgUpdate);
    } on Object catch (e) {
      debugPrint('update prompt: read prefs failed — ${e.runtimeType}');
    }
    return isDue(lastCheck: _lastCheck, now: _now(), bgFound: bg, bgSeen: _bgSeen);
  }

  /// เรียกหลังถามหลังบ้านเสร็จ ไม่ว่าผลจะเป็นอะไร
  Future<void> markChecked() async {
    _lastCheck = _now();
    try {
      _bgSeen = (await _prefs()).getString(kPrefBgUpdate);
    } on Object {
      // อ่านไม่ได้ = ครั้งหน้าเช็คตามรอบปกติ
    }
  }

  Future<bool> snoozed(String version) async {
    try {
      final p = await _prefs();
      return isSnoozed(
        version: version,
        snoozedVersion: p.getString(kPrefSnoozeVersion),
        untilMs: p.getInt(kPrefSnoozeUntil),
        now: _now(),
      );
    } on Object {
      return false; // อ่านไม่ได้ = ถาม ดีกว่าเงียบไปทั้งที่มีรุ่นใหม่
    }
  }

  Future<void> snooze(String version) async {
    try {
      final p = await _prefs();
      await p.setString(kPrefSnoozeVersion, version);
      await p.setInt(
          kPrefSnoozeUntil, _now().add(snoozeFor).millisecondsSinceEpoch);
    } on Object catch (e) {
      debugPrint('update prompt: save snooze failed — ${e.runtimeType}');
    }
  }

  @visibleForTesting
  static bool isDue({
    required DateTime? lastCheck,
    required DateTime now,
    String? bgFound,
    String? bgSeen,
  }) {
    if (lastCheck == null) return true;
    if (bgFound != null && bgFound.isNotEmpty && bgFound != bgSeen) return true;
    // นาฬิกาเครื่องถูกตั้งย้อน = ถือว่าถึงเวลา ไม่งั้นเงียบไปจนกว่าเวลาจะไล่ทัน
    final gap = now.difference(lastCheck);
    return gap.isNegative || gap >= recheckEvery;
  }

  @visibleForTesting
  static bool isSnoozed({
    required String version,
    required String? snoozedVersion,
    required int? untilMs,
    required DateTime now,
  }) {
    if (snoozedVersion != version || untilMs == null) return false;
    final left = untilMs - now.millisecondsSinceEpoch;
    // เหลือนานเกินกว่าที่เลื่อนได้จริง = นาฬิกาเคยเดินหน้าผิด ไม่เชื่อค่านี้
    return left > 0 && left <= snoozeFor.inMilliseconds;
  }
}
