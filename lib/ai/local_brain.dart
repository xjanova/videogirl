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

import 'openai_client.dart';

/// รุ่นที่เลือกได้ — ทุกตัวเป็น Apache-2.0 โหลดได้โดยไม่ต้องมี token
enum GemmaVariant {
  e2bGpu(
    id: 'gemma-4-e2b-gpu',
    label: 'Gemma 4 E2B (GPU)',
    hint: 'เร็วที่สุดบนมือถือที่มี GPU ดี · แนะนำ',
    file: 'gemma-4-E2B-it-gpu.litertlm',
    repo: 'litert-community/gemma-4-E2B-it-litert-lm',
    bytes: 2008432640,
    backend: PreferredBackend.gpu,
  ),
  e2bCpu(
    id: 'gemma-4-e2b-cpu',
    label: 'Gemma 4 E2B (CPU)',
    hint: 'ใช้ได้ทุกเครื่อง แต่ช้ากว่า',
    file: 'gemma-4-E2B-it.litertlm',
    repo: 'litert-community/gemma-4-E2B-it-litert-lm',
    bytes: 2588147712,
    backend: PreferredBackend.cpu,
  ),
  e4bGpu(
    id: 'gemma-4-e4b-gpu',
    label: 'Gemma 4 E4B (GPU)',
    hint: 'ฉลาดกว่า แต่กินพื้นที่และแรมมากกว่า',
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
  GemmaVariant _variant = GemmaVariant.e2bGpu;
  GemmaVariant get variant => _variant;

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
      : '${(_bytesPerSecond / 1048576).toStringAsFixed(1)} MB/วิ';

  /// เวลาที่เหลือโดยประมาณ — ว่างถ้ายังเดาไม่ได้
  String get etaLabel {
    if (_bytesPerSecond <= 0 || _progress >= 100) return '';
    final left = (_variant.bytes - downloadedBytes) ~/ _bytesPerSecond;
    if (left < 60) return 'เหลืออีก ~$left วิ';
    return 'เหลืออีก ~${(left / 60).ceil()} นาที';
  }

  static String _gb(int bytes) => (bytes / 1073741824).toStringAsFixed(1);

  String? _error;
  String? get error => _error;

  InferenceModel? _model;
  InferenceChat? _chat;
  String? _loadedSystem;
  bool _disposed = false;

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
    if (_variant == v) return;
    await _release(); // โมเดลเดิมยังกินแรมอยู่ ต้องปล่อยก่อนสลับ
    _variant = v;
    await refresh();
  }

  /// เช็คว่าโมเดลอยู่ในเครื่องแล้วหรือยัง
  Future<void> refresh() async {
    try {
      final installed = await FlutterGemmaPlugin.instance.modelManager
          .isModelInstalled(_spec(_variant));
      _set(installed ? LocalModelStage.ready : LocalModelStage.missing);
    } on Exception catch (e) {
      _set(LocalModelStage.failed, error: 'เช็คโมเดลไม่ได้ — $e');
    }
  }

  /// โหลดโมเดลลงเครื่อง — หลาย GB ต้องมีไวไฟและพื้นที่ว่างพอ
  Future<void> download() async {
    _progress = 0;
    _bytesPerSecond = 0;
    _startedAt = DateTime.now();
    _set(LocalModelStage.downloading);
    try {
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
      _set(LocalModelStage.failed, error: 'โหลดโมเดลไม่สำเร็จ — $e');
    }
  }

  Future<void> remove() async {
    await _release();
    try {
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
      throw const OpenAiFailure('ยังไม่ได้โหลดโมเดลลงเครื่อง');
    }

    try {
      await _ensureChat(system);
      final chat = _chat!;

      // ส่งเฉพาะข้อความล่าสุดของผู้ใช้ ตัว InferenceChat เก็บประวัติให้เองแล้ว
      final last = history.isEmpty ? '' : history.last.text;
      if (last.isEmpty) throw const OpenAiFailure('ไม่มีข้อความให้ตอบ');

      await chat.addQuery(Message.text(text: last, isUser: true));
      final res = await chat.generateChatResponse();

      final text = switch (res) {
        TextResponse r => r.token,
        _ => '',
      };
      if (text.trim().isEmpty) {
        throw const OpenAiFailure('โมเดลในเครื่องตอบกลับมาว่าง');
      }
      return text.trim();
    } on OpenAiFailure {
      rethrow;
    } on Exception catch (e) {
      throw OpenAiFailure('โมเดลในเครื่องทำงานไม่สำเร็จ — $e');
    }
  }

  Future<void> _ensureChat(String system) async {
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
