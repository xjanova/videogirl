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
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// ชื่อสินค้าในระบบรายงานของ xman studio
  ///
  /// ต้องตรงกับที่ฝั่งหลังบ้านใช้กรอง (`?product_name=`) · แอปอื่นในบ้าน
  /// ใช้ชื่อสั้นตัวพิมพ์เล็กเหมือนกันหมด (`tping` ฯลฯ)
  static const product = 'giggok';

  /// 🔴 **ระบบเดิมของบ้าน ไม่ใช่ปลายทางที่ทำขึ้นใหม่**
  ///
  /// `POST /api/v1/bug-reports` มีอยู่แล้วและแอปอื่นใช้อยู่จริง (นับได้ 3,526
  /// รายงานตอนต่อสายนี้) · มาพร้อมหน้าแอดมิน สถิติ และตัวส่งเข้า GitHub issue
  ///
  /// เคยหลงทำ `/api/giggok/debug-report` ขึ้นมาใหม่ทั้งชุด — ผิดกฎเดิมของบ้าน
  /// ที่เขียนไว้แล้วว่า *"อย่าเขียน endpoint ชุดใหม่ทั้งชุด"* · ของใหม่แปลว่า
  /// หน้าแอดมินไม่เห็น สถิติไม่รวม และคนไล่บั๊กต้องรู้ว่ามีสองที่
  static String endpointOf(String base) =>
      '${base.trim().replaceAll(RegExp(r'/+$'), '')}/api/v1/bug-reports';

  /// แปลงรายงานเป็นรูปที่ระบบรายงานของบ้านรับ
  ///
  /// แยกออกมาเป็นฟังก์ชันบริสุทธิ์เพื่อให้เทสต์ยืนยันได้ว่า **ไม่มีอะไรที่ไม่ควร
  /// อยู่หลุดเข้าไปในนี้** — ฟิลด์ที่ระบบเดิมมี (`stack_trace`, `user_email`)
  /// เราไม่ส่งโดยตั้งใจ ไม่ใช่เพราะลืม
  @visibleForTesting
  static Map<String, Object?> asBugReport(
    ReportFacts r, {
    required String installId,
  }) {
    final app = (r['app'] as Map?) ?? const {};
    final device = (r['device'] as Map?) ?? const {};
    final errors = (r['errors'] as List?) ?? const [];

    return {
      'product_name': product,
      'product_version': '${app['version'] ?? '?'}',
      // 🔴 `bug` เสมอ · **ห้ามใช้ `diagnostic`** ทั้งที่ในฐานมี 3,520 แถว
      //
      // ยิงจริงไปแล้วได้ 422 `The selected report type is invalid` —
      // validator ที่ deploy อยู่รับแค่
      // bug / misclassification / feature_request / crash / performance
      // (แถว `diagnostic` ที่มีอยู่เข้ามาก่อนหน้าด้วยทางอื่น)
      //
      // และ `bug` ตรงกับความจริงอยู่แล้ว — คนกดปุ่มนี้เพราะมีอะไรไม่ทำงาน
      // ไม่ใช่เพราะอยากส่งสถานะเฉย ๆ
      'report_type': 'bug',
      'title': _title(errors),
      // เนื้อรายงานเต็มไปเป็นข้อความ ให้คนอ่านได้โดยไม่ต้องกาง JSON
      'description': DebugReport.pretty(r),
      'metadata': {'category': 'app-state', ...r},
      'app_version': '${app['version'] ?? '?'}',
      'os_version': '${device['osVersion'] ?? '?'}',
      // 🔴 ไม่ใช่รหัสฮาร์ดแวร์ · เป็นเลขสุ่มของการติดตั้งครั้งนี้
      //
      // แอปอื่นในบ้านส่ง hardware hash มา ซึ่งใช้ได้กับของเขา แต่แอปนี้ขาย
      // ด้วยคำสัญญาเรื่องความเป็นส่วนตัวที่แคบกว่านั้น · เลขสุ่มพอสำหรับ
      // การจับคู่รายงานจากเครื่องเดียวกัน โดยไม่ผูกกับตัวเครื่องจริง
      'device_id': installId,
      'priority': errors.isEmpty ? 'low' : 'medium',
      'severity': errors.isEmpty ? 'minor' : 'moderate',
    };
  }

  /// หัวข้อที่อ่านแล้วรู้เรื่องในรายการยาว ๆ ของหน้าแอดมิน
  static String _title(List<Object?> errors) {
    if (errors.isEmpty) return 'app state (no errors)';
    final first = '${errors.first}';
    return first.length <= 120 ? first : '${first.substring(0, 119)}…';
  }

  /// ส่งขึ้นระบบรายงานของ xman studio
  ///
  /// ปลายทางเปิดสาธารณะโดยตั้งใจ (แอปในบ้านไม่มีหน้าล็อกอิน) จึงไม่ต้องมี
  /// รหัสสิทธิ์ก็ส่งได้ — คนที่เจอบั๊กก่อนซื้ออะไรคือรายงานที่ต้องการที่สุด
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
            body: utf8.encode(
                jsonEncode(asBugReport(r, installId: await installId()))),
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

  /// เลขสุ่มของการติดตั้งครั้งนี้ · สร้างครั้งเดียวแล้วจำไว้
  ///
  /// มีไว้จับคู่รายงานหลายฉบับจากเครื่องเดียวกันตอนไล่บั๊ก · **ไม่ได้มาจาก
  /// ฮาร์ดแวร์** จึงชี้ตัวคนไม่ได้ และหายไปพร้อมการถอนแอปเหมือนข้อมูลอื่น
  Future<String> installId() async {
    final saved = _installId;
    if (saved != null) return saved;
    final p = await SharedPreferences.getInstance();
    var id = p.getString(_kInstallId);
    if (id == null || id.isEmpty) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16)
          .padLeft(2, '0')).join();
      await p.setString(_kInstallId, id);
    }
    return _installId = id;
  }

  static const _kInstallId = 'reportInstallId';
  String? _installId;

  @override
  void dispose() {
    _disposed = true;
    _http.close();
    super.dispose();
  }
}
