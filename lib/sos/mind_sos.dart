/// ระบบแจ้งเหตุฉุกเฉินฝั่ง Dart — คู่กับ sos/SosBridge.kt
///
/// Dart แค่เตรียมแผนและแสดงผล · ตอนเกิดเหตุฝั่งเนทีฟทำเองทั้งหมด (ดู docs/sos.md)
///
/// 🔴 ไม่มีเมธอดไหนรับเบอร์โทร และห้ามเพิ่ม · สั่งได้แค่ "เกิดเหตุชนิดนี้" แล้วเริ่มนับถอยหลังที่หยุดได้
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'sos_directory.dart';
import 'sos_phrases.dart';
import 'sos_plan.dart';
import 'sos_profile.dart';

class SosReading {
  const SosReading({
    required this.atMs,
    required this.peakG,
    required this.deltaV,
    required this.before,
    required this.verdict,
  });

  final int atMs;
  final double peakG;
  final double deltaV;
  final double? before;
  final String verdict;
}

/// ผลของเหตุล่าสุด ขาหนึ่ง · who เป็นเบอร์ฉุกเฉินหรือชื่อที่เจ้าของตั้ง
class SosOutcome {
  const SosOutcome(this.type, this.who, this.outcome);

  final String type;
  final String who;
  final String outcome;
}

class SosStatus {
  const SosStatus(this.m);

  static const empty = SosStatus({});

  final Map<Object?, Object?> m;

  bool _b(String k) => m[k] == true;

  bool get armed => _b('armed');
  bool get running => _b('running');
  int get drills => (m['drills'] as int?) ?? 0;
  bool get accel => _b('accel');
  bool get lowPower => _b('lowPower');
  bool get location => _b('location');
  bool get background => _b('background');
  bool get sms => _b('sms');
  bool get call => _b('call');
  bool get phone => _b('phone');
  bool get mic => _b('mic');
  bool get notify => _b('notify');
  bool get fullScreen => _b('fullScreen');
  bool get battExempt => _b('battExempt');
  bool get dialer => _b('dialer');
  bool get recognizer => _b('recognizer');

  /// ยังไม่รู้ = ไม่เตือน · ฝั่งเนทีฟตรวจตอนเปิดระบบ
  bool get thaiVoice => m['thaiVoice'] != false;
  bool get busy => m['phase'] == 'ALERT' || m['phase'] == 'DISPATCH';

  /// ไม่มีค่า = ถือว่าทดสอบ · ป้ายต้องไม่บอกว่าแจ้งจริงทั้งที่ไม่รู้
  bool get testMode => m['testMode'] != false;
  bool get silent => busy && _b('silent');

  Map<Object?, Object?> get _battery => (m['battery'] as Map<Object?, Object?>?) ?? const {};
  int get armedMinutes => ((_battery['armedMs'] as int?) ?? 0) ~/ 60000;
  int get tripMinutes => ((_battery['tripMs'] as int?) ?? 0) ~/ 60000;
  int get batteryDrop => (_battery['batteryDrop'] as int?) ?? 0;

  /// เบอร์ที่ซิมไม่รู้จักว่าเป็นเบอร์ฉุกเฉิน · สายพวกนี้อาจเข้าทางปกติ ไม่ใช่ทางฉุกเฉิน
  List<String> get notEcc => [
        for (final e in ((m['ecc'] as Map<Object?, Object?>?) ?? const {}).entries)
          if (e.value != true) '${e.key}',
      ];

  List<SosReading> get readings {
    try {
      final list = jsonDecode((m['readings'] as String?) ?? '[]') as List<dynamic>;
      return [
        for (final r in list.reversed)
          SosReading(
            atMs: ((r as Map<String, dynamic>)['at'] as num).toInt(),
            peakG: (r['peak'] as num).toDouble(),
            deltaV: (r['dv'] as num).toDouble(),
            before: (r['before'] as num?)?.toDouble(),
            verdict: r['verdict'] as String,
          ),
      ];
    } on Object {
      return const [];
    }
  }

  List<SosOutcome> get lastReport {
    final r = m['lastReport'] as Map<Object?, Object?>?;
    if (r == null) return const [];
    return [
      for (final s in (r['sent'] as List<Object?>? ?? const []))
        SosOutcome(
          (s! as Map<Object?, Object?>)['type']! as String,
          s['who']! as String,
          s['outcome']! as String,
        ),
    ];
  }

  bool get lastCancelled => (m['lastReport'] as Map<Object?, Object?>?)?['cancelled'] == true;
}

class SosPlace {
  const SosPlace({
    required this.link,
    required this.coords,
    required this.plus,
    required this.accuracy,
    required this.ageMinutes,
  });

  final String link;
  final String coords;
  final String plus;
  final double? accuracy;
  final int ageMinutes;
}

class MindSos {
  MindSos._() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'alert') onAlert?.call();
      onChanged?.call();
    });
  }

  static final MindSos instance = MindSos._();
  static const MethodChannel _ch = MethodChannel('giggok/sos');

  /// หน้าที่เปิดอยู่ฟังการเปลี่ยนสถานะ
  VoidCallback? onChanged;

  /// เหตุเริ่มนับถอยหลัง · ไว้ให้เวทีสะดุ้งตาม
  VoidCallback? onAlert;

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null; // เทสต์ · แพลตฟอร์มอื่น
    }
  }

  Future<SosStatus> status() async {
    final m = await _call<Map<Object?, Object?>>('sosStatus');
    return m == null ? SosStatus.empty : SosStatus(m);
  }

  Future<SosProfile> profile() async => SosProfile.parse(await _call<String>('sosProfile'));

  Future<bool> save(SosProfile p) async =>
      await _call<bool>('sosSave', {
        'plan': SosPlanBuilder.build(p, year: DateTime.now().year),
        'profile': p.encode(),
      }) ==
      true;

  /// เปิดแอป · ให้ตัวเฝ้ากลับมาทำงานถ้าถูกระบบปิดไป
  Future<void> sync() async => _call<bool>('sosSync');

  /// เริ่มนับถอยหลัง · ระบบยังไม่เปิด = false
  Future<bool> trigger(SosKindName kind, {bool voice = false, bool silent = false}) async =>
      await _call<bool>('sosTrigger', {'kind': kind.wire, 'voice': voice, 'silent': silent}) == true;

  /// คำของเจ้าของเป็นการขอความช่วยเหลือไหม · true = เริ่มนับถอยหลังแล้ว ไม่ต้องส่งเข้าสมอง
  ///
  /// 🔴 ด่านนี้อยู่ก่อนสมองและก่อน MindState._voiceBarred โดยตั้งใจ · เครื่องล็อกอยู่ก็ขอความช่วยเหลือได้
  /// ทางนี้ไปได้แค่นับถอยหลังที่หยุดได้ · การโทรทั่วไปยังต้องปลดล็อกเหมือนเดิม
  Future<bool> heard(String text) async {
    if (SosPhrases.standDown(text)) {
      if (!(await status()).silent) return false;
      await stop();
      return true;
    }
    final kind = SosPhrases.match(text);
    return kind != null && await trigger(kind, voice: true, silent: SosPhrases.silent(text));
  }

  /// ครอบทางส่งข้อความเข้าแชท · ระบบไม่ได้เปิด = ข้อความไปหาเธอตามปกติ
  Future<void> Function(String) guarded(Future<void> Function(String) send) => (text) async {
        if (!await heard(text)) await send(text);
      };

  /// ซ้อม · ฝั่งเนทีฟส่งได้แค่เบอร์ทดสอบที่ตรวจแล้วว่าไม่ใช่เบอร์ฉุกเฉิน
  Future<bool> drill({bool silent = false}) async => await _call<bool>(
        'sosDrill',
        {'kind': silent ? SosKindName.other.wire : SosKindName.crash.wire, 'silent': silent},
      ) ==
      true;

  Future<void> stop() async => _call<bool>('sosStop');

  Future<SosPlace?> location() async {
    final m = await _call<Map<Object?, Object?>>('sosLocation');
    if (m == null) return null;
    return SosPlace(
      link: m['link']! as String,
      coords: m['coords']! as String,
      plus: m['plus']! as String,
      accuracy: (m['accuracy'] as num?)?.toDouble(),
      ageMinutes: ((m['ageMs'] as num?) ?? 0) ~/ 60000,
    );
  }

  /// target: copy · sms · line · any · เจ้าของกดส่งเองทุกทาง
  Future<bool> share(String target) async => await _call<bool>('sosShare', {'target': target}) == true;

  Future<void> openSetting(String which) async => _call<bool>('sosOpenSetting', {'which': which});

  Future<void> wipe() async => _call<bool>('sosWipe');
}
