/// สมองที่รันในเครื่อง — ไม่ส่งอะไรออกอินเทอร์เน็ตเลย
///
/// ใช้ Gemma 4 ตระกูล E (E = ทำมาสำหรับอุปกรณ์ปลายทางโดยเฉพาะ) ผ่าน LiteRT-LM
/// ไฟล์ `.litertlm` ใช้ quantization ผสม 2/4/8 บิต ทำให้น้ำหนักตอนรัน
/// ต่ำถึง ~0.8 GB ส่วน embedding 1.12 GB ใช้ memory-map ไม่กินแรม
///
/// ขนาดไฟล์ยืนยันจาก Hugging Face เมื่อ 2026-08-29 ไม่ได้เดา
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import 'device_capability.dart';
import 'openai_client.dart';

/// รุ่นที่เลือกได้ — ทุกตัวเป็น Apache-2.0 โหลดได้โดยไม่ต้องมี token
enum GemmaVariant {
  e2bGpu(
    id: 'gemma-4-e2b-gpu',
    label: 'Gemma 4 E2B (GPU)',
    hint: '',
    file: 'gemma-4-E2B-it-gpu.litertlm',
    repo: 'litert-community/gemma-4-E2B-it-litert-lm',
    bytes: 2008432640,
    backend: PreferredBackend.gpu,
  ),
  e2bCpu(
    id: 'gemma-4-e2b-cpu',
    label: 'Gemma 4 E2B (CPU)',
    hint: '',
    file: 'gemma-4-E2B-it.litertlm',
    repo: 'litert-community/gemma-4-E2B-it-litert-lm',
    bytes: 2588147712,
    backend: PreferredBackend.cpu,
  ),
  e4bGpu(
    id: 'gemma-4-e4b-gpu',
    label: 'Gemma 4 E4B (GPU)',
    hint: '',
    file: 'gemma-4-E4B-it-gpu.litertlm',
    repo: 'litert-community/gemma-4-E4B-it-litert-lm',
    bytes: 2969059328,
    backend: PreferredBackend.gpu,
  );

  const GemmaVariant({
    required this.id,
    required this.label,
    required this.hint,
    required this.file,
    required this.repo,
    required this.bytes,
    required this.backend,
  });

  final String id, label, hint, file, repo;
  final int bytes;
  final PreferredBackend backend;

  String get url => 'https://huggingface.co/$repo/resolve/main/$file';

  String get sizeLabel => '${(bytes / 1073741824).toStringAsFixed(1)} GB';
}

/// สถานะของโมเดลในเครื่อง
enum LocalModelStage { unknown, missing, downloading, ready, failed }

class LocalBrain extends ChangeNotifier {
  LocalBrain({S Function()? strings}) : _s = strings ?? _thai;

  final S Function() _s;
  static S _thai() => const S(AppLang.th);

  GemmaVariant _variant = GemmaVariant.e2bGpu;
  GemmaVariant get variant => _variant;

  // ── ความสามารถของเครื่อง ─────────────────────────────────
  DeviceVerdict? _device;

  /// ผลตรวจแรม — null แปลว่ายังไม่ได้ตรวจ
  DeviceVerdict? get device => _device;

  /// ผู้ใช้เลือกรุ่นเองแล้วหรือยัง
  /// ถ้าเลือกเองแล้ว การตรวจอัตโนมัติต้องไม่ไปเปลี่ยนทับ
  bool _userPicked = false;

  /// ตรวจแรมแล้วเลือกรุ่นที่เหมาะให้เอง
  ///
  /// เรียกตอนเปิดหน้าตั้งค่า ทำครั้งเดียวพอ แรมของเครื่องไม่เปลี่ยนระหว่างใช้งาน
  Future<void> detectDevice() async {
    if (_device != null) return;
    _device = await DeviceCapability.detect();

    final best = _device!.best;
    if (!_userPicked && best != null && best != _variant) {
      await _release();
      _variant = best;
    }
    if (!_disposed) notifyListeners();
    await refresh();
  }

  LocalModelStage _stage = LocalModelStage.unknown;
  LocalModelStage get stage => _stage;

  /// 0–100 ของไฟล์ที่กำลังโหลด
  int _progress = 0;
  int get progress => _progress;

  DateTime? _startedAt;
  int _bytesPerSecond = 0;

  /// ไบต์ที่โหลดมาแล้ว คำนวณจากเปอร์เซ็นต์ × ขนาดจริงที่รู้อยู่แล้ว
  /// (ตัวปลั๊กอินคืนมาแค่เปอร์เซ็นต์ ไม่ได้บอกไบต์)
  int get downloadedBytes => (_variant.bytes * _progress / 100).round();

  /// "1.2 / 2.0 GB" — ผู้ใช้ต้องเห็นว่าเหลืออีกเท่าไหร่ ไม่ใช่แค่เปอร์เซ็นต์ลอย ๆ
  String get sizeProgressLabel =>
      '${_gb(downloadedBytes)} / ${_gb(_variant.bytes)} GB';

  /// "4.3 MB/วิ" — ว่างถ้ายังคำนวณไม่ได้
  String get speedLabel => _bytesPerSecond <= 0
      ? ''
      : _s().gemmaSpeed((_bytesPerSecond / 1048576).toStringAsFixed(1));

  /// เวลาที่เหลือโดยประมาณ — ว่างถ้ายังเดาไม่ได้
  String get etaLabel {
    if (_bytesPerSecond <= 0 || _progress >= 100) return '';
    final left = (_variant.bytes - downloadedBytes) ~/ _bytesPerSecond;
    if (left < 60) return _s().gemmaEtaSeconds(left);
    return _s().gemmaEtaMinutes((left / 60).ceil());
  }

  static String _gb(int bytes) => (bytes / 1073741824).toStringAsFixed(1);

  String? _error;
  String? get error => _error;

  InferenceModel? _model;
  InferenceChat? _chat;
  String? _loadedSystem;
  bool _disposed = false;

  /// 🔴 ปลั๊กอินต้องถูก initialize ก่อนเรียกอะไรก็ตาม
  ///
  /// ไม่ทำ = ทุกทางที่แตะปลั๊กอินโยน StateError "FlutterGemma not initialized!"
  /// ซึ่งเป็นข้อความยาวเหยียดพร้อมโค้ดตัวอย่างของนักพัฒนา แล้วมันไปโผล่บนหน้า
  /// ตั้งค่าให้ผู้ใช้อ่านทั้งดุ้น
  ///
  /// **จงใจไม่เรียกใน `main()`** ตามที่เอกสารปลั๊กอินบอก เพราะ `main()` ของแอปนี้
  /// มีกฎว่า**ห้าม await อะไรก่อน `runApp`** (ของเดิมรอจนจอขาวค้าง 10.2 วิ)
  /// จึงทำเป็น lazy แทน แล้วให้ทุกทางที่แตะปลั๊กอินรอ future ตัวเดียวกัน
  ///
  /// เก็บเป็น `Future` ไม่ใช่ `bool` เพราะสองทางที่เรียกพร้อมกัน (เช่น
  /// `detectDevice()` กับปุ่มโหลด) ต้องรอรอบเดียว ไม่ใช่ initialize ซ้อนกัน
  Future<void>? _pluginReady;

  /// ย่อข้อความข้อผิดพลาดให้เหลือเท่าที่ผู้ใช้ควรเห็น
  ///
  /// ข้อผิดพลาดของปลั๊กอินบางตัวยาวเป็นสิบบรรทัด มีทั้งโค้ดตัวอย่างและลิงก์
  /// เอกสารสำหรับนักพัฒนา · ของจริงที่เคยขึ้นบนหน้าตั้งค่าคือทั้งดุ้นของ
  /// "FlutterGemma not initialized!" พร้อม `void main() async {...}`
  /// ซึ่งผู้ใช้ทำอะไรกับมันไม่ได้เลย นอกจากตกใจ
  ///
  /// เอาบรรทัดแรกพอ ตัดคำนำหน้าชนิดข้อผิดพลาดออก แล้วจำกัดความยาว
  /// ส่วนของเต็มยังอยู่ใน debugPrint สำหรับตอนไล่ปัญหา
  ///
  /// 🔴 คำนำหน้าของ `Error` ใน Dart **ไม่ได้ใช้ชื่อคลาส** — `StateError`
  /// พิมพ์ออกมาเป็น `Bad state:` ไม่ใช่ `StateError:` (และ `ArgumentError`
  /// เป็น `Invalid argument(s):`) · ของจริงที่ผู้ใช้เจอคือ
  /// `Bad state: FlutterGemma not initialized!` ถ้าดักแต่ `*Error:`
  /// คำว่า "Bad state:" จะหลุดถึงหน้าจอ
  @visibleForTesting
  static String shortenError(Object e) {
    final first = e
        .toString()
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
        .replaceFirst(
          RegExp(r'^\s*(\w*(Exception|Error)|Bad state'
              r'|Invalid argument\(s\)|Unsupported operation)\s*:\s*'),
          '',
        )
        .trim();
    if (first.isEmpty) return e.runtimeType.toString();
    return first.length <= 140 ? first : '${first.substring(0, 139)}…';
  }

  Future<void> _ensurePlugin() async {
    final pending = _pluginReady ??= FlutterGemma.initialize();
    try {
      await pending;
    } on Object catch (e) {
      // ล้มแล้วต้องลองใหม่ได้ · ถ้าปล่อย future ที่พังไว้ ทุกครั้งต่อจากนี้
      // จะพังตามด้วยข้อผิดพลาดเดิมโดยไม่ได้ลองจริงสักครั้ง
      _pluginReady = null;
      debugPrint('gemma: initialize ไม่สำเร็จ — $e');

      // 🔴 ห่อเป็น Exception เสมอ · ทุกที่ที่เรียกดักด้วย `on Exception`
      // แต่ initialize() ล้มด้วย **Error** ได้ (StateError เป็น Error ไม่ใช่
      // Exception) ซึ่งจะลอดทุกตัวดักออกไปเป็นข้อผิดพลาดที่ไม่มีใครรับ
      // = จอแดง แทนที่จะเป็นข้อความบอกผู้ใช้ว่าเกิดอะไรขึ้น
      throw Exception(shortenError(e));
    }
  }

  void _set(LocalModelStage s, {String? error}) {
    if (_disposed) return;
    _stage = s;
    _error = error;
    notifyListeners();
  }

  InferenceModelSpec _spec(GemmaVariant v) => InferenceModelSpec.fromLegacyUrl(
        name: v.id,
        modelUrl: v.url,
        modelType: ModelType.gemmaIt,
        // .litertlm ให้ LiteRT-LM จัดการ chat template เอง
        // ถ้าใส่ผิดเป็น .task เทมเพลตจะถูกใส่ซ้ำสองชั้นแล้วคำตอบจะเพี้ยน
        fileType: ModelFileType.litertlm,
      );

  Future<void> selectVariant(GemmaVariant v) async {
    // ผู้ใช้เลือกเอง = การตรวจอัตโนมัติต้องไม่มาเปลี่ยนทับทีหลัง
    _userPicked = true;
    if (_variant == v) return;
    await _release(); // โมเดลเดิมยังกินแรมอยู่ ต้องปล่อยก่อนสลับ
    _variant = v;
    await refresh();
  }

  /// เช็คว่าโมเดลอยู่ในเครื่องแล้วหรือยัง
  Future<void> refresh() async {
    try {
      await _ensurePlugin();
      final installed = await FlutterGemmaPlugin.instance.modelManager
          .isModelInstalled(_spec(_variant));
      _set(installed ? LocalModelStage.ready : LocalModelStage.missing);
    } on Exception catch (e) {
      debugPrint('gemma: เช็คโมเดลไม่ได้ — $e');
      _set(LocalModelStage.failed, error: _s().errCheckModel(shortenError(e)));
    }
  }

  /// โหลดโมเดลลงเครื่อง — หลาย GB ต้องมีไวไฟและพื้นที่ว่างพอ
  Future<void> download() async {
    _progress = 0;
    _bytesPerSecond = 0;
    _startedAt = DateTime.now();
    _set(LocalModelStage.downloading);
    try {
      await _ensurePlugin();
      final stream = FlutterGemmaPlugin.instance.modelManager
          .downloadModelWithProgress(_spec(_variant));
      await for (final p in stream) {
        if (_disposed) return;
        _progress = p.currentFileProgress;

        // ความเร็วเฉลี่ยตั้งแต่เริ่ม นิ่งกว่าความเร็วชั่วขณะ
        // ตัวเลขที่กระโดดไปมาทำให้ ETA เชื่อถือไม่ได้และผู้ใช้กังวลเปล่า ๆ
        final elapsed = DateTime.now().difference(_startedAt!).inSeconds;
        if (elapsed > 0) _bytesPerSecond = downloadedBytes ~/ elapsed;

        notifyListeners();
      }
      _set(LocalModelStage.ready);
    } on Exception catch (e) {
      debugPrint('gemma: โหลดโมเดลไม่สำเร็จ — $e');
      _set(LocalModelStage.failed, error: _s().errDownloadModel(shortenError(e)));
    }
  }

  Future<void> remove() async {
    await _release();
    try {
      await _ensurePlugin();
      await FlutterGemmaPlugin.instance.modelManager.deleteModel(_spec(_variant));
    } on Exception {
      // ลบไม่ได้ก็ไม่เป็นไร refresh จะบอกสถานะจริงเอง
    }
    await refresh();
  }

  /// ให้เธอคิดคำตอบโดยไม่ต่อเน็ต
  ///
  /// [system] เปลี่ยนได้ทุกครั้ง (โหมด/ระดับการจีบ/ข้อมูลเจ้าของ)
  /// systemInstruction ผูกกับ session ตอนสร้าง จึงต้องสร้าง chat ใหม่เมื่อมันเปลี่ยน
  Future<String> reply({
    required String system,
    required List<Turn> history,
  }) async {
    if (_stage != LocalModelStage.ready) {
      throw OpenAiFailure(_s().errModelNotDownloaded);
    }

    try {
      await _ensureChat(system);
      final chat = _chat!;

      // ส่งเฉพาะข้อความล่าสุดของผู้ใช้ ตัว InferenceChat เก็บประวัติให้เองแล้ว
      final last = history.isEmpty ? '' : history.last.text;
      if (last.isEmpty) throw OpenAiFailure(_s().errNothingToAnswer);

      await chat.addQuery(Message.text(text: last, isUser: true));
      final res = await chat.generateChatResponse();

      final text = switch (res) {
        TextResponse r => r.token,
        _ => '',
      };
      if (text.trim().isEmpty) {
        throw OpenAiFailure(_s().errLocalEmpty);
      }
      return text.trim();
    } on OpenAiFailure {
      rethrow;
    } on Exception catch (e) {
      debugPrint('gemma: โมเดลในเครื่องทำงานไม่สำเร็จ — $e');
      throw OpenAiFailure(_s().errLocalFailed(shortenError(e)));
    }
  }

  Future<void> _ensureChat(String system) async {
    await _ensurePlugin();
    if (_model == null) {
      _model = await FlutterGemmaPlugin.instance.createModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
        preferredBackend: _variant.backend,
        // มายด์ตอบสั้น แต่ system prompt (ข้อมูลเจ้าของ + ขอบเขต) ยาวพอควร
        maxTokens: 4096,
      );
      _loadedSystem = null;
    }

    if (_chat == null || _loadedSystem != system) {
      await _chat?.close();
      _chat = await _model!.createChat(
        temperature: .8,
        topK: 40,
        topP: .95,
        randomSeed: 1,
        systemInstruction: system,
      );
      _loadedSystem = system;
    }
  }

  Future<void> _release() async {
    try {
      await _chat?.close();
      await _model?.close();
    } on Exception {
      // ปิดไม่ได้ก็ปล่อย จะสร้างใหม่รอบหน้าอยู่แล้ว
    }
    _chat = null;
    _model = null;
    _loadedSystem = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _release();
    super.dispose();
  }
}
