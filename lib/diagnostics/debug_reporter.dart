/// เก็บรายงานดีบัคแล้วส่งให้ xman studio — เมื่อเจ้าของกดเท่านั้น
///
/// 🔴 **ไม่มีการส่งอัตโนมัติในไฟล์นี้ และห้ามมีในอนาคต**
///
/// ไม่มีตัวตั้งเวลา ไม่มีการส่งตอนแอปพัง ไม่มีการส่งตอนเปิดแอป · ทุกทางที่
/// ส่งได้เองคือทางที่เจ้าของไม่ได้เลือก และแอปนี้ขายด้วยคำสัญญาว่าข้อมูล
/// ไม่ออกนอกเครื่อง (ดู docs/security.md) — ตัวเก็บดีบัคคือสิ่งที่ทำลาย
/// คำสัญญานั้นได้ง่ายที่สุด เพราะมันมีเหตุผลที่ฟังดูดีรออยู่แล้ว
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../ai/voice_profile.dart';
import '../avatar/avatar_view.dart';
import '../state/mind_state.dart';
import '../store/mind_vault.dart';
import '../i18n/strings.dart';
import 'debug_report.dart';
import 'mind_log.dart';

enum ReportStage { idle, building, sending, sent, failed }

class DebugReporter extends ChangeNotifier {
  DebugReporter({http.Client? httpClient, S Function()? strings})
      : _http = httpClient ?? http.Client(),
        _s = strings ?? _thai;

  final http.Client _http;

  /// อ่านภาษา ณ ตอนที่ error เกิดจริง ไม่ใช่ตอนสร้าง — ผู้ใช้สลับภาษาได้
  /// ระหว่างแอปเปิดอยู่ (กฎเดียวกับ OpenAiClient และ LocalBrain)
  final S Function() _s;
  static S _thai() => const S(AppLang.th);

  ReportStage _stage = ReportStage.idle;
  ReportStage get stage => _stage;

  String? _error;
  String? get error => _error;

  /// รายงานที่ประกอบไว้ล่าสุด — เป็นตัวเดียวกับที่จะถูกส่งจริง
  ReportFacts? _report;
  ReportFacts? get report => _report;

  /// ไฟล์ที่บันทึกไว้ล่าสุด
  String? _savedPath;
  String? get savedPath => _savedPath;

  bool _disposed = false;

  void _set(ReportStage s, {String? error}) {
    if (_disposed) return;
    _stage = s;
    _error = error;
    notifyListeners();
  }

  void reset() {
    _report = null;
    _savedPath = null;
    _set(ReportStage.idle);
  }

  /// ประกอบรายงานจากสถานะจริงของแอปตอนนี้
  ///
  /// รับตัวที่รู้เรื่องเข้ามาแทนที่จะไปหาเอง — ตัวนี้จึงทดสอบได้โดยไม่ต้องมี
  /// ทั้งแอป และที่สำคัญกว่า: รายการของที่ใส่ลงไปอ่านจบได้ในหน้าจอเดียว
  /// ซึ่งเป็นเงื่อนไขเดียวที่ทำให้ตรวจได้จริงว่าไม่มีอะไรที่ไม่ควรอยู่
  Future<ReportFacts> collect({
    required MindState state,
    MindAvatarController? avatar,
    MindVault? vault,
  }) async {
    _set(ReportStage.building);

    final pkg = await _packageFacts();
    final lb = state.hasLocalBrain ? state.localBrain : null;

    final report = DebugReport.build(
      app: pkg,
      device: DebugReport.deviceFacts(
        ramGb: lb?.device?.gb,
        ramTier: lb?.device?.tier.name,
      ),

      // ── สิ่งที่ผู้ใช้เลือกไว้ · ชื่อของตัวเลือก ไม่ใช่ค่าของความลับ ──
      settings: {
        'lang': state.lang.code,
        'brain': state.brain.name,
        'brainModel': state.brainModel,
        'persona': state.persona.name,
        'voiceEnabled': state.voiceEnabled,
        for (final c in VoiceChannel.values)
          'voice_${c.name}': state.voiceFor(c).engine.name,
        'mocapShot': state.mocapShot.name,
        'autoAnswer': state.autoAnswer,
        'callStream': state.callStream,
        'bubbleSeconds': state.bubbleSeconds,
      },

      // ── มีของที่ต้องมีไหม · **บอกว่ามี ไม่ได้บอกว่าคืออะไร** ──
      status: {
        'hasOwnKey': state.hasOwnKey,
        'hasLicense': state.licenseKey.trim().isNotEmpty,
        'canTranscribe': state.canTranscribe,
        'deviceSttReady': state.deviceSttReady,
        'durableStore': state.durableStore,
        'vault': vault?.stage.name,
        'wipeOnUninstall': state.wipeOnUninstall,
        if (lb != null) ...{
          'localStage': lb.stage.name,
          'localVariant': lb.variant.id,
          'localInstalled': [for (final v in lb.installed) v.id],
        },
        if (avatar != null) ...{
          'avatarReady': avatar.ready,
          'avatarLoad': avatar.loadPercent,
          'mocapPhase': avatar.mocapPhase.name,
        },
      },

      // ── ปริมาณ ไม่ใช่เนื้อหา ──
      counts: {
        'messages': await state.storedMessageCount(),
        'memories': state.memory.count,
        'logLines': MindLog.count,
      },

      errors: [
        if (state.lastError != null) 'state: ${state.lastError}',
        if (lb?.error != null) 'localBrain: ${lb!.error}',
        if (avatar?.error != null) 'avatar: ${avatar!.error}',
        if (avatar?.speakError != null) 'speak: ${avatar!.speakError}',
        if (vault?.error != null) 'vault: ${vault!.error}',
      ],

      // 🔴 ค่าจริงของความลับ ส่งเข้าไปเพื่อ **ค้นแล้วลบทิ้ง** จากทุกบรรทัด
      // ไม่ใช่เพื่อใส่ลงรายงาน · เป็นด่านที่แน่นอนที่สุด เพราะรู้ค่าจริง
      secrets: [
        state.effectiveOpenAiKey,
        state.licenseKey,
      ].where((s) => s.trim().isNotEmpty),
    );

    _report = report;
    _set(ReportStage.idle);
    return report;
  }

  Future<ReportFacts> _packageFacts() async {
    try {
      final p = await PackageInfo.fromPlatform();
      return {
        'version': p.version,
        'build': p.buildNumber,
        'package': p.packageName,
      };
    } on Object catch (e) {
      debugPrint('รายงาน: อ่านรุ่นแอปไม่ได้ — $e');
      return const {'version': '?', 'build': '?'};
    }
  }

  /// บันทึกลงไฟล์ให้เจ้าของเอาไปส่งทางไหนก็ได้
  ///
  /// มีทางนี้เพราะ **การอัปโหลดไม่ควรเป็นทางเดียว** · คนที่ไม่อยากส่งผ่าน
  /// เซิร์ฟเวอร์ของเรายังช่วยไล่บั๊กได้ และคนที่ส่งแล้วไม่ถึงก็ยังมีของอยู่ในมือ
  Future<String?> saveToFile() async {
    final r = _report;
    if (r == null) return null;
    try {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}${Platform.pathSeparator}'
          '${DebugReport.fileName(DateTime.now())}';
      await File(path).writeAsString(DebugReport.pretty(r), flush: true);
      _savedPath = path;
      notifyListeners();
      return path;
    } on Object catch (e) {
      debugPrint('รายงาน: บันทึกไฟล์ไม่สำเร็จ — $e');
      _set(ReportStage.failed, error: '$e');
      return null;
    }
  }

  /// ทางที่หลังบ้านรับรายงาน
  static String endpointOf(String base) =>
      '${base.trim().replaceAll(RegExp(r'/+$'), '')}/api/giggok/debug-report';

  /// ส่งขึ้น xman studio
  ///
  /// ยืนยันตัวด้วยรหัสสิทธิ์เหมือนทางอื่นของแอป (ร้านชุด/พร็อกซี) เพราะแอปนี้
  /// **ไม่มีหน้าล็อกอิน** · ไม่มีรหัสก็ส่งได้ หลังบ้านจะเก็บเป็นรายงานนิรนาม
  /// — คนที่เจอบั๊กก่อนซื้ออะไรคือคนที่เราต้องการรายงานจากเขามากที่สุด
  Future<bool> send({required String baseUrl, String license = ''}) async {
    final r = _report;
    if (r == null) return false;
    if (baseUrl.trim().isEmpty) {
      _set(ReportStage.failed, error: _s().debugNoBase);
      return false;
    }

    _set(ReportStage.sending);
    try {
      final res = await _http
          .post(
            Uri.parse(endpointOf(baseUrl)),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
              if (license.trim().isNotEmpty)
                'Authorization': 'Bearer ${license.trim()}',
            },
            body: utf8.encode(jsonEncode(r)),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode >= 400) {
        // 🔴 บอกรหัสสถานะตรง ๆ · 404 แปลว่าหลังบ้านยังไม่มีปลายทางนี้
        // ซึ่งคนละเรื่องกับ "ส่งไม่ผ่าน" และแก้คนละที่กันด้วย
        _set(ReportStage.failed,
            error: res.statusCode == 404
                ? _s().debugNoEndpoint
                : _s().debugSendFailed(res.statusCode));
        return false;
      }
      _set(ReportStage.sent);
      return true;
    } on Object catch (e) {
      debugPrint('รายงาน: ส่งไม่สำเร็จ — $e');
      _set(ReportStage.failed, error: _s().debugOffline);
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _http.close();
    super.dispose();
  }
}
