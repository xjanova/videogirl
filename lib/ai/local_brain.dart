/// สมองที่รันในเครื่อง — ไม่ส่งอะไรออกอินเทอร์เน็ตเลย
///
/// ใช้ Gemma 4 ตระกูล E (E = ทำมาสำหรับอุปกรณ์ปลายทางโดยเฉพาะ) ผ่าน LiteRT-LM
/// ไฟล์ `.litertlm` ใช้ quantization ผสม 2/4/8 บิต ทำให้น้ำหนักตอนรัน
/// ต่ำถึง ~0.8 GB ส่วน embedding 1.12 GB ใช้ memory-map ไม่กินแรม
///
/// ขนาดไฟล์ยืนยันจาก Hugging Face เมื่อ 2026-08-29 ไม่ได้เดา
library;

import 'dart:async';

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

  /// แปลง id ที่จำไว้กลับเป็นรุ่น · null = ยังไม่เคยเลือก หรือชื่อที่ไม่รู้จัก
  /// (รุ่นถูกถอดออกจากแอปได้ ค่าที่จำไว้จึงชี้ไปที่ที่ไม่มีอยู่แล้วได้)
  static GemmaVariant? parse(Object? id) {
    for (final v in GemmaVariant.values) {
      if (v.id == '$id') return v;
    }
    return null;
  }
}

/// สถานะของโมเดลในเครื่อง
enum LocalModelStage { unknown, missing, downloading, ready, failed }

class LocalBrain extends ChangeNotifier {
  LocalBrain({
    S Function()? strings,
    GemmaVariant? initialVariant,
    this.onVariantPicked,
  })  : _s = strings ?? _thai,
        _variant = initialVariant ?? GemmaVariant.e2bGpu,
        // รุ่นที่จำมาจากรอบก่อน = เขาเลือกเองไว้แล้ว · การตรวจอัตโนมัติ
        // ต้องไม่มาทับ ไม่งั้นการเลือกในหน้าตั้งค่าจะอยู่ได้แค่รอบเดียว
        _userPicked = initialVariant != null;

  final S Function() _s;
  static S _thai() => const S(AppLang.th);

  /// บอกฝั่งที่เก็บค่าว่าผู้ใช้เลือกรุ่นไหน — ต้องรอดข้ามการเปิดปิดแอป
  final void Function(GemmaVariant)? onVariantPicked;

  GemmaVariant _variant;
  GemmaVariant get variant => _variant;

  // ── ความสามารถของเครื่อง ─────────────────────────────────
  DeviceVerdict? _device;

  /// ผลตรวจแรม — null แปลว่ายังไม่ได้ตรวจ
  DeviceVerdict? get device => _device;

  /// ผู้ใช้เลือกรุ่นเองแล้วหรือยัง
  /// ถ้าเลือกเองแล้ว การตรวจอัตโนมัติต้องไม่ไปเปลี่ยนทับ
  bool _userPicked;

  /// ตรวจแรมแล้วเลือกรุ่นที่เหมาะให้เอง แล้วอ่านสถานะโมเดลในเครื่อง
  ///
  /// แรมตรวจครั้งเดียวพอ (ไม่เปลี่ยนระหว่างใช้งาน) แต่ **[refresh] ต้องวิ่งทุกครั้ง**
  /// ที่ถูกเรียก · ของเดิม `if (_device != null) return;` คร่อมทั้งเมธอด ทำให้
  /// การเรียกซ้ำเงียบไปทั้งดุ้นรวมถึงการอ่านสถานะไฟล์ ซึ่งเป็นคนละเรื่องกัน
  /// และเปลี่ยนได้จริงระหว่างใช้งาน (โหลดเสร็จ ลบทิ้ง สลับรุ่น)
  Future<void> detectDevice() async {
    _device ??= await DeviceCapability.detect();

    // 🔴 **ต้องรู้ก่อนว่ามีอะไรโหลดไว้แล้ว ก่อนจะไปเลือกรุ่นให้เขา**
    //
    // ของเดิมเลือกรุ่นก่อนแล้วค่อยสแกน จึงเลือกโดยไม่รู้ว่าเครื่องมีอะไรอยู่
    await refresh();
    await _autoPick();
    if (!_disposed) notifyListeners();
  }

  /// เลือกรุ่นให้เอง — เฉพาะตอนที่ยัง**ไม่มีอะไรให้เลือก**เท่านั้น
  ///
  /// 🔴 **ห้ามสลับออกจากรุ่นที่โหลดไว้แล้วเด็ดขาด**
  ///
  /// ของเดิมสลับไปรุ่นที่ `DeviceVerdict.best` บอก โดยไม่ดูว่ารุ่นนั้นโหลดไว้
  /// หรือยัง · เครื่องแรม 12 GB ได้ `best = e4bGpu` แต่คนส่วนใหญ่โหลด E2B
  /// (ค่าตั้งต้นของปุ่มโหลด) ผลคือ **เปิดแอปแล้วมันสลับไปรุ่นที่ไม่มีในเครื่อง
  /// ทุกครั้ง** แล้วทักคำแรกได้ "ยังไม่ได้โหลดโมเดล" ทั้งที่เพิ่งโหลดไปเมื่อวาน
  ///
  /// และเพราะ `_userPicked` ไม่เคยถูกจำข้ามการเปิดปิดแอป การเลือกเองในหน้า
  /// ตั้งค่าก็ถูกทับทิ้งในการเปิดครั้งถัดไปอยู่ดี
  ///
  /// ไฟล์ที่โหลดไว้แล้วคือ**คำแถลงเจตนาที่หนักแน่นที่สุดที่มี** — 2 GB ที่เขา
  /// ยอมเสียเน็ตโหลดมา · การสลับทิ้งคือการโยนของนั้นทิ้งแทนเขา
  Future<void> _autoPick() async {
    if (_userPicked) return;

    // มีของอยู่ในเครื่องแล้ว = ใช้ของนั้น ไม่ต้องไปหาอะไรที่ดีกว่า
    if (_installed.isNotEmpty) {
      if (_installed.contains(_variant)) return;
      final best = _device?.best;
      final pick = (best != null && _installed.contains(best))
          ? best
          : _installed.first;
      await _release();
      _variant = pick;
      _set(LocalModelStage.ready);
      return;
    }

    // ยังไม่มีอะไรเลย — ตรงนี้ค่อยแนะนำรุ่นที่เครื่องรับไหว
    final best = _device?.best;
    if (best != null && best != _variant) {
      await _release();
      _variant = best;
      _set(LocalModelStage.missing);
    }
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

  /// บทสนทนาที่ **session ปัจจุบันเห็นมาแล้ว** เรียงเก่า→ใหม่
  ///
  /// 🔴 จำเป็นเพราะประวัติของ [InferenceChat] อยู่ฝั่งเนทีฟ และหายทั้งหมด
  /// ทุกครั้งที่ session ถูกสร้างใหม่ — ซึ่งเกิด**บ่อยกว่าที่คิดมาก**:
  /// systemInstruction ผูกกับ session ตอนสร้าง และ system prompt ของแอปนี้
  /// ขยับเกือบทุกตา (ความผูกพันเป็น %, ระดับงอน, ตารางนัดที่เลื่อนไป)
  /// ยังไม่นับการสกัดความจำที่ยิงเข้ามาด้วย prompt คนละตัวทุก 6 ตา
  ///
  /// ของเดิมส่งเข้าโมเดลแค่ข้อความล่าสุดโดยเชื่อว่าเนทีฟจำที่เหลือไว้ให้
  /// ผลจริงคือเธอลืมบทสนทนากลางคันเป็นระยะ โดยไม่มีอะไรบอกว่าลืม
  List<String> _fed = const [];

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
    onVariantPicked?.call(v);
    if (_variant == v) return;
    await _release(); // โมเดลเดิมยังกินแรมอยู่ ต้องปล่อยก่อนสลับ
    _variant = v;

    // ไม่เรียก refresh() ซ้ำ — เรารู้อยู่แล้วว่ารุ่นไหนโหลดไว้บ้างจากการสแกน
    // ครั้งก่อน · การสแกนใหม่คือยิงข้ามแพลตฟอร์มอีกสามรอบ แล้วปุ่มจะหน่วง
    // ทุกครั้งที่แตะเลือกรุ่น ทั้งที่คำตอบไม่เปลี่ยน
    _set(_installed.contains(v)
        ? LocalModelStage.ready
        : LocalModelStage.missing);
  }

  /// รุ่นที่โหลดลงเครื่องไว้แล้ว — มีได้หลายรุ่นพร้อมกัน
  ///
  /// ต้องรู้ทีละรุ่น ไม่ใช่แค่ "รุ่นที่เลือกอยู่โหลดแล้วหรือยัง" เพราะผู้ใช้
  /// โหลดไว้หลายรุ่นแล้วสลับไปมาได้ · ถ้ารู้แค่รุ่นที่เลือก การสลับกลับไป
  /// รุ่นที่เคยโหลดไว้แล้วจะขึ้นปุ่ม "โหลด 2.4 GB" ทั้งที่ไฟล์อยู่ในเครื่อง
  final Set<GemmaVariant> _installed = {};

  /// สำเนาที่แก้ไม่ได้ ให้ UI อ่าน
  Set<GemmaVariant> get installed => Set.unmodifiable(_installed);

  bool isInstalled(GemmaVariant v) => _installed.contains(v);

  /// รุ่นที่ควรเอาไปแสดงให้ผู้ใช้เลือก
  ///
  /// **ตัดรุ่นที่เครื่องนี้รันไม่ไหวออกก่อนเสมอ** — โชว์รุ่นที่กดแล้วโหลด 3 GB
  /// มาเพื่อให้ระบบฆ่าทิ้งตอนรัน คือการกินเน็ตของเขาฟรี ๆ
  ///
  /// รุ่นที่ "โหลดไว้แล้ว" ไม่ถูกตัดทิ้งแม้จะเกินเกณฑ์ เพราะไฟล์อยู่ในเครื่อง
  /// เขาแล้ว การซ่อนทิ้งเฉย ๆ จะกลายเป็นพื้นที่ที่หายไปโดยลบไม่ได้
  List<GemmaVariant> get selectable => selectableFor(_device, _installed);

  /// ตรรกะล้วน แยกออกมาให้เทสต์ได้โดยไม่ต้องมีเครื่องจริง
  ///
  /// ยังไม่ได้ตรวจแรม (`device == null`) ให้แสดงทุกรุ่นไปก่อน — ซ่อนทิ้งตอนที่
  /// ยังไม่รู้ผล จะกลายเป็นรายการที่กะพริบเปลี่ยนไปมาตอนผลตรวจมาถึง
  @visibleForTesting
  static List<GemmaVariant> selectableFor(
    DeviceVerdict? device,
    Set<GemmaVariant> installed,
  ) {
    final ok = device?.allowed ?? GemmaVariant.values;
    return GemmaVariant.values
        .where((v) => ok.contains(v) || installed.contains(v))
        .toList();
  }

  /// เครื่องนี้รันโมเดลในเครื่องไม่ไหวเลย
  bool get deviceTooSmall => _device != null && _device!.allowed.isEmpty;

  /// เช็คว่าโมเดลอยู่ในเครื่องแล้วหรือยัง — ไล่ **ทุกรุ่น** ไม่ใช่เฉพาะรุ่นที่เลือก
  Future<void> refresh() async {
    try {
      await _ensurePlugin();

      _installed.clear();
      for (final v in GemmaVariant.values) {
        // ถามทีละรุ่น · ปลั๊กอินไม่มี API บอกรายการที่ติดตั้งไว้ทั้งหมด
        if (await FlutterGemmaPlugin.instance.modelManager
            .isModelInstalled(_spec(v))) {
          _installed.add(v);
        }
      }

      final installed = _installed.contains(_variant);
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
      // โหลดจบแล้วต้องเข้าทะเบียนทันที ไม่ต้องรอสแกนรอบหน้า ไม่งั้นสลับไป
      // รุ่นอื่นแล้วกลับมาจะขึ้นปุ่มโหลดซ้ำทั้งที่เพิ่งโหลดเสร็จ
      _installed.add(_variant);
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
      _installed.remove(_variant);
    } on Exception {
      // ลบไม่ได้ก็ไม่เป็นไร refresh จะบอกสถานะจริงเอง
    }
    await refresh();
  }

  /// ให้เธอคิดคำตอบโดยไม่ต่อเน็ต
  ///
  /// [system] เปลี่ยนได้ทุกครั้ง (โหมด/ระดับการจีบ/ข้อมูลเจ้าของ)
  /// systemInstruction ผูกกับ session ตอนสร้าง จึงต้องสร้าง chat ใหม่เมื่อมันเปลี่ยน
  /// คิวของงานที่ยิงเข้าโมเดลตัวเดียวกัน
  ///
  /// 🔴 **มีสองคนเรียกพร้อมกันได้จริง** — การคุยปกติ กับการสกัดความจำที่ถูก
  /// ยิงแบบ `unawaited` ทุก 6 ตา · ทั้งคู่ใช้ session ฝั่งเนทีฟตัวเดียวกัน
  /// และการสกัดใช้ system prompt คนละตัว ซึ่งแปลว่ามันจะ **ปิด session
  /// ที่อีกฝั่งกำลังรอคำตอบอยู่** แล้วผลที่ได้คือ error จากเนทีฟ หรือคำตอบ
  /// ที่ปนกันสองงาน · ต่อคิวให้เข้าทีละคน
  ///
  /// แลกมาด้วยการที่ข้อความถัดไปต้องรอรอบสกัดจบก่อน (1 ใน 6 ตา)
  /// ซึ่งช้ากว่าเดิม แต่เป็นความช้าที่ถูกต้อง ไม่ใช่ความเร็วที่พัง
  Future<void> _queue = Future<void>.value();

  Future<String> reply({
    required String system,
    required List<Turn> history,
  }) {
    final done = Completer<String>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await _reply(system: system, history: history));
      } on Object catch (e, st) {
        // คิวต้องไม่พังตามงานที่ล้ม ไม่งั้นทุกคำถามหลังจากนี้จะล้มตามกันหมด
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  Future<String> _reply({
    required String system,
    required List<Turn> history,
  }) async {
    // 🔴 `unknown` ไม่ใช่ "ยังไม่ได้โหลด" แต่คือ "ยังไม่ได้ดู"
    //
    // ถ้าไม่แยกสองอย่างนี้ ทุกครั้งที่ยังไม่มีใครเรียก [refresh] มาก่อน
    // (เช่นเพิ่งเปิดแอปแล้วทักคำแรกเลย) เธอจะตอบว่ายังไม่ได้โหลดโมเดล
    // ทั้งที่ไฟล์อยู่ในเครื่องมาตั้งแต่เมื่อวาน · ดูก่อนแล้วค่อยตัดสิน
    if (_stage == LocalModelStage.unknown) await refresh();

    // 🔴 สี่กรณีนี้ผู้ใช้ต้อง**ทำคนละอย่าง** จึงห้ามพูดเหมือนกันหมด
    //
    // ของเดิมทุกทางที่ไม่ใช่ ready ตอบว่า "ยังไม่ได้โหลดโมเดล" เหมือนกันหมด
    // คนที่กำลังโหลดอยู่ 60% ถูกบอกให้ไปโหลด · คนที่เครื่องรันไม่ไหวก็ถูกบอก
    // ให้ไปโหลดของที่โหลดมาก็ใช้ไม่ได้ · และข้อผิดพลาดจริงที่ refresh อ่านมาได้
    // ถูกกลืนหายไปทั้งที่เป็นข้อมูลชิ้นเดียวที่พาไปหาสาเหตุได้
    switch (_stage) {
      case LocalModelStage.ready:
        break;
      case LocalModelStage.downloading:
        throw OpenAiFailure(_s().errModelDownloading(_progress));
      case LocalModelStage.failed:
        throw OpenAiFailure(_error ?? _s().errModelNotDownloaded);
      case LocalModelStage.unknown:
      case LocalModelStage.missing:
        throw OpenAiFailure(deviceTooSmall
            ? _s().errDeviceTooSmallForLocal
            : _s().errModelNotDownloaded);
    }

    final last = history.isEmpty ? '' : history.last.text.trim();
    if (last.isEmpty) throw OpenAiFailure(_s().errNothingToAnswer);

    try {
      final continued = await _ensureChat(system, history);
      final chat = _chat!;

      // ต่อจากของเดิมได้ = เนทีฟถือประวัติไว้ครบแล้ว ส่งแค่คำล่าสุดพอ
      // ต่อไม่ได้ = session เพิ่งเกิดใหม่และว่างเปล่า ต้องเล่าย้อนให้ฟังก่อน
      await chat.addQuery(Message.text(
        text: continued ? last : _withTranscript(history),
        isUser: true,
      ));
      final res = await chat.generateChatResponse();

      final text = switch (res) {
        TextResponse r => r.token,
        _ => '',
      };
      if (text.trim().isEmpty) {
        throw OpenAiFailure(_s().errLocalEmpty);
      }

      // session ถือครบทั้งบทสนทนา **บวกคำตอบที่เพิ่งสร้าง** แล้ว
      // จดไว้เพื่อให้ตาถัดไปรู้ว่าต่อจากตรงนี้ได้เลย
      _fed = [for (final t in history) t.text, text.trim()];
      return text.trim();
    } on OpenAiFailure {
      rethrow;
    } on Object catch (e) {
      // 🔴 `on Exception` ไม่พอ · ปลั๊กอินนี้ล้มด้วย **Error** ได้จริง
      // (StateError เป็น Error ไม่ใช่ Exception — เจอมาแล้วกับ
      //  "Bad state: FlutterGemma not initialized!") ตัวที่ลอดออกไปจะไม่มี
      // ใครรับ แล้วจบที่จอแดง พร้อมปุ่มส่งที่ค้างอยู่ในสถานะกำลังส่งตลอดกาล
      debugPrint('gemma: โมเดลในเครื่องทำงานไม่สำเร็จ — $e');

      // session อาจค้างอยู่ในสภาพที่ไม่รู้ว่าเนทีฟเห็นอะไรไปแล้วบ้าง
      // ตาถัดไปต้องเล่าย้อนใหม่ทั้งหมด ดีกว่าต่อจากประวัติที่อาจขาดหาย
      _fed = const [];
      throw OpenAiFailure(_s().errLocalFailed(shortenError(e)));
    }
  }

  String _withTranscript(List<Turn> history) => transcriptFor(history, _s());

  /// บทสนทนาก่อนหน้าเป็นข้อความก้อนเดียว ต่อท้ายด้วยคำที่เพิ่งพิมพ์มา
  ///
  /// 🔴 **ไม่ยัดตาเก่าเข้าไปทีละตาผ่าน `addQuery`** ทั้งที่ดูเป็นวิธีที่ตรงกว่า
  /// เพราะไฟล์ `.litertlm` บนแอนดรอยด์ส่งข้อความดิบลงเนทีฟโดย**ไม่ได้ติดป้าย
  /// ว่าใครพูด** (ดู Message.transformToChatPrompt) เนทีฟถือว่าทุกก้อนที่ป้อน
  /// เข้ามาคือฝั่งผู้ใช้ แล้วคำตอบเก่าของเธอจะกลายเป็นคำที่เจ้าของพูด
  /// ติดป้ายเองในข้อความจึงเป็นวิธีเดียวที่บทบาทไม่สลับ
  @visibleForTesting
  static String transcriptFor(List<Turn> history, S s) {
    if (history.isEmpty) return '';
    final past = history.sublist(0, history.length - 1);
    if (past.isEmpty) return history.last.text.trim();

    final lines = past
        .map((t) => '${t.fromHer ? s.speakerHer : s.speakerMe}: ${t.text}')
        .join('\n');
    return '${s.localRecap}\n$lines\n\n'
        '${s.speakerMe}: ${history.last.text.trim()}';
  }

  bool _continues(List<Turn> history) => continues(_fed, history);

  /// [history] ต่อจากสิ่งที่ session เห็นมาแล้วพอดีไหม
  ///
  /// เทียบจาก**ท้าย** ไม่ใช่หัว เพราะฝั่งเรียกตัดบทสนทนาเก่าทิ้งเมื่อยาวเกิน
  /// เพดาน · เทียบจากหัวจะเจอว่า "ไม่ตรง" ทุกตาหลังจากนั้น แล้วเธอจะโดน
  /// เล่าย้อนทั้งบทใหม่ทุกครั้งที่พิมพ์ ซึ่งช้าโดยไม่ได้อะไรเพิ่ม
  @visibleForTesting
  static bool continues(List<String> fed, List<Turn> history) {
    if (history.isEmpty) return false;
    final past = history.sublist(0, history.length - 1);
    if (past.length > fed.length) return false;
    final offset = fed.length - past.length;
    for (var i = 0; i < past.length; i++) {
      if (fed[offset + i] != past[i].text) return false;
    }
    return true;
  }

  /// คืนค่าว่า session ที่ได้ **ต่อจากบทสนทนาเดิมได้เลย** หรือเพิ่งเกิดใหม่
  Future<bool> _ensureChat(String system, List<Turn> history) async {
    await _ensurePlugin();
    if (_model == null) {
      _model = await FlutterGemmaPlugin.instance.createModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
        preferredBackend: _variant.backend,
        // มายด์ตอบสั้น แต่ system prompt (ข้อมูลเจ้าของ + ขอบเขต) ยาวพอควร
        // และตอนที่ต้องเล่าบทสนทนาย้อนหลัง คำถามเดียวก็ยาวได้หลายพันตัวอักษร
        maxTokens: 8192,
      );
      _loadedSystem = null;
    }

    if (_chat != null && _loadedSystem == system && _continues(history)) {
      return true;
    }

    await _chat?.close();
    _chat = await _model!.createChat(
      temperature: .8,
      topK: 40,
      topP: .95,
      randomSeed: 1,
      systemInstruction: system,
    );
    _loadedSystem = system;
    _fed = const [];
    return false;
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
    // session ที่ถือประวัติไว้ตายไปพร้อมกัน · ไม่ล้างที่นี่ = ตาถัดไปเชื่อว่า
    // เนทีฟยังจำบทสนทนาเดิมได้ แล้วส่งไปแค่คำเดียวให้ session ที่ว่างเปล่า
    _fed = const [];
  }

  @override
  void dispose() {
    _disposed = true;
    _release();
    super.dispose();
  }
}
