/// สมองที่รันในเครื่อง — ไม่ส่งอะไรออกอินเทอร์เน็ตเลย
///
/// ใช้ Gemma 4 ตระกูล E (E = ทำมาสำหรับอุปกรณ์ปลายทางโดยเฉพาะ) ผ่าน LiteRT-LM
/// ไฟล์ `.litertlm` ใช้ quantization ผสม 2/4/8 บิต ทำให้น้ำหนักตอนรัน
/// ต่ำถึง ~0.8 GB ส่วน embedding 1.12 GB ใช้ memory-map ไม่กินแรม
///
/// ขนาดไฟล์ยืนยันจาก Hugging Face เมื่อ 2026-09-03 ไม่ได้เดา
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import '../i18n/strings_settings.dart';
import 'device_capability.dart';
import 'openai_client.dart';

/// รุ่นที่เลือกได้ — ทุกตัวเป็น Apache-2.0 โหลดได้โดยไม่ต้องมี token
///
/// ## 🔴 ไฟล์เดียวกันรันได้ทั้ง CPU และ GPU — ไม่ใช่ไฟล์ `-gpu`
///
/// ไฟล์ `-gpu.litertlm` ของ litert-community **ไม่ใช่ไฟล์ GPU ของ Android**
/// มันขนาดเท่าไฟล์ `-web` ทุกไบต์ (2,008,432,640 สำหรับ E2B) คือรุ่น WebGPU
/// ที่ประกาศ `gpu_artisan` · LiteRT-LM บน Android จึงตายด้วย
/// `NOT_FOUND: TF_LITE_PREFILL_DECODE not found in the model` · ดู [retiredModels]
///
/// ไฟล์ปกติ (ไม่มีคำต่อท้าย) คือตัวที่ Google วัดบน Android ทั้ง CPU และ GPU
/// (การ์ดโมเดล: S26 Ultra GPU อ่าน prompt 3,808 โทเค็น/วิ เทียบ CPU 557)
/// อ่านหัวไฟล์ซ้ำเมื่อ 2026-10-05: `backend_constraint: cpu` ผูกอยู่กับ**ส่วน
/// เสียงและภาพเท่านั้น** (`tf_lite_audio_adapter`, `tf_lite_vision_adapter`,
/// `tf_lite_audio_encoder_hw`) ส่วนตัวคิดหลัก `tf_lite_prefill_decode` ไม่มีข้อจำกัด
/// และมี `prefer_activation_type: fp16` ซึ่งเป็นของ GPU · บันทึกเก่าที่บอกว่า
/// "ทั้งไฟล์เป็น cpu" อ่านป้ายผิดส่วน
///
/// ใช้ CPU หรือ GPU จึงไม่ใช่เรื่องของรุ่น แต่เป็นการตั้งค่าของ [LocalBrain]
/// (ดู [LocalBrain.useGpu]) · `id` ยังลงท้าย `-cpu` เพราะมันคือชื่อที่ปลั๊กอิน
/// จำไว้ว่าติดตั้งอะไรไปแล้ว เปลี่ยนชื่อ = เครื่องที่โหลดไว้ต้องโหลดใหม่ 2–4 GB
enum GemmaVariant {
  e2bCpu(
    id: 'gemma-4-e2b-cpu',
    label: 'Gemma 4 E2B',
    hint: '',
    file: 'gemma-4-E2B-it.litertlm',
    repo: 'litert-community/gemma-4-E2B-it-litert-lm',
    bytes: 2588147712,
  ),
  e4bCpu(
    id: 'gemma-4-e4b-cpu',
    label: 'Gemma 4 E4B',
    hint: '',
    file: 'gemma-4-E4B-it.litertlm',
    repo: 'litert-community/gemma-4-E4B-it-litert-lm',
    bytes: 3659530240,
  );

  const GemmaVariant({
    required this.id,
    required this.label,
    required this.hint,
    required this.file,
    required this.repo,
    required this.bytes,
  });

  final String id, label, hint, file, repo;
  final int bytes;

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

/// รุ่นที่เคยเสนอแล้วถอดออก — เก็บชื่อกับที่อยู่ไว้เพื่อ**ตามไปลบไฟล์**เท่านั้น
///
/// สองตัวนี้คือไฟล์ WebGPU ที่เคยเข้าใจผิดว่าเป็นไฟล์ GPU ของ Android (ดู [GemmaVariant])
///
/// 🔴 ถอดออกจาก [GemmaVariant] เฉย ๆ ไม่พอ · คนที่โหลด `-gpu` ไปแล้วจะเหลือ
/// ไฟล์ 2–3 GB ที่**ไม่มีปุ่มไหนในแอปลบได้อีกเลย** เพราะทั้งปุ่มลบและการ
/// สแกนตอนเปิดแอปวิ่งบน `GemmaVariant.values` ซึ่งไม่มีชื่อพวกนี้อยู่แล้ว
///
/// ปลั๊กอินเก็บไฟล์แยกตาม**ชื่อไฟล์** ไม่ใช่ชื่อรุ่น (`mobile_model_manager`
/// `spec.files[].filename`) ชื่อไฟล์ตรงนี้จึงต่างจากของที่ยังใช้อยู่คนละตัว
/// ลบแล้วไม่โดนของที่ยังต้องใช้
const retiredModels = <({String name, String url})>[
  (
    name: 'gemma-4-e2b-gpu',
    url: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm'
        '/resolve/main/gemma-4-E2B-it-gpu.litertlm',
  ),
  (
    name: 'gemma-4-e4b-gpu',
    url: 'https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm'
        '/resolve/main/gemma-4-E4B-it-gpu.litertlm',
  ),
];

/// สถานะของโมเดลในเครื่อง
enum LocalModelStage { unknown, missing, downloading, ready, failed }

/// ผลวัดของคำตอบหนึ่งครั้ง — **วัดจากเครื่องนี้จริง** ไม่ใช่ตัวเลขจากการ์ดโมเดล
///
/// มีไว้ตอบคำถามที่เจ้าของถามได้ตลอด: "ใช้รุ่นไหน โหลดมาจริงไหม ทำไมช้า"
/// · ถ้าไม่มีตัวเลขจริง ทุกคำตอบคือการเดา และการเดาผิดคือการแก้ผิดจุด
class LocalReplyStats {
  const LocalReplyStats({
    required this.variant,
    required this.backend,
    required this.loadMs,
    required this.newSession,
    required this.firstMs,
    required this.totalMs,
    required this.chars,
  });

  final GemmaVariant variant;
  final PreferredBackend backend;

  /// เวลาเปิดสมอง (อ่านไฟล์เข้าหน่วยความจำ + เตรียม GPU) ถ้าเกิดในคำตอบนี้
  /// · null = เปิดรอไว้แล้ว ไม่ได้เสียเวลานี้
  final int? loadMs;

  /// ต้องอ่านบทบาทและบทสนทนาใหม่ทั้งหมดไหม · true = ตานี้ช้ากว่าปกติ
  final bool newSession;

  /// จากเริ่มคิดถึงคำแรก (ไม่รวมเวลาเปิดสมอง)
  final int firstMs;

  /// จากเริ่มคิดถึงคำสุดท้าย (ไม่รวมเวลาเปิดสมอง)
  final int totalMs;

  final int chars;

  /// ตัวอักษรต่อวินาทีช่วงพิมพ์คำตอบ · ตัวอักษรเพราะนับได้ตรง ๆ และคนอ่านเข้าใจ
  /// ส่วน "โทเค็น" ของภาษาไทยไม่ตรงกับคำ บอกไปก็เทียบอะไรไม่ได้
  double get charsPerSecond {
    final gen = totalMs - firstMs;
    return gen <= 0 ? 0 : chars * 1000 / gen;
  }

  /// รอทั้งหมดก่อนเห็นคำแรก (รวมเปิดสมอง ถ้ามี)
  int get waitMs => (loadMs ?? 0) + firstMs;
}

/// เพดานของคำตอบหนึ่งครั้งจากสมองในเครื่อง — จำนวน token และเวลา
///
/// 🔴 สมองในเครื่องกิน CPU/GPU เต็มตลอดที่คิด · ไม่มีเพดาน = โมเดลที่ติดลูป
/// คิดต่อได้หลายนาทีจนเต็ม context (เครื่องร้อน ทั้งเครื่องช้า) และงานอื่นทุกงาน
/// ที่ต่อคิวอยู่ (คำถามถัดไป การปล่อยสมองตอนออกจากแอป) ค้างตามทั้งหมด
///
/// ตัวเลขเผื่อเครื่องช้า (CPU ราว 4–8 token/วิ) · คำตอบปกติของเธอสั้นกว่านี้มาก
enum ReplyCap {
  /// คุยในแชท · ยาวได้พอเขียนอีเมลหรือสรุปยาว ๆ
  chat(1024, Duration(seconds: 150)),

  /// ตอบในสายโทรศัพท์ · คู่สายรอฟังอยู่ ต้องสั้น
  call(320, Duration(seconds: 45)),

  /// งานเบื้องหลัง (สกัดความจำ สรุปสาย) · ไม่มีใครเห็นตอนมันวน จึงต้องเข้มที่สุด
  background(480, Duration(seconds: 90));

  const ReplyCap(this.tokens, this.time);
  final int tokens;
  final Duration time;
}

class LocalBrain extends ChangeNotifier {
  LocalBrain({
    S Function()? strings,
    GemmaVariant? initialVariant,
    this.onVariantPicked,
    bool useGpu = true,
    this.onUseGpuChanged,
  })  : _s = strings ?? _thai,
        _variant = initialVariant ?? GemmaVariant.e2bCpu,
        _useGpu = useGpu,
        // รุ่นที่จำมาจากรอบก่อน = เขาเลือกเองไว้แล้ว · การตรวจอัตโนมัติ
        // ต้องไม่มาทับ ไม่งั้นการเลือกในหน้าตั้งค่าจะอยู่ได้แค่รอบเดียว
        _userPicked = initialVariant != null;

  final S Function() _s;
  static S _thai() => const S(AppLang.th);

  /// บอกฝั่งที่เก็บค่าว่าผู้ใช้เลือกรุ่นไหน — ต้องรอดข้ามการเปิดปิดแอป
  final void Function(GemmaVariant)? onVariantPicked;

  // ── GPU ─────────────────────────────────────────────────
  //
  // ช้าบนมือถือคือการ**อ่าน prompt** ไม่ใช่การพิมพ์คำตอบ · prompt ของเธอยาว
  // (บุคลิก ความจำ ตารางนัด และบทสนทนาที่เล่าย้อน) และ CPU อ่านได้ราว 557
  // โทเค็น/วิ ส่วน GPU ราว 3,800 (การ์ดโมเดล S26 Ultra) · คำตอบแรกจึงต่างกัน
  // หลายวินาทีต่อตา

  /// ผู้ใช้อยากให้ใช้ GPU ไหม — ค่าตั้งต้นคือใช้
  bool _useGpu;
  bool get useGpu => _useGpu;

  /// บอกฝั่งที่เก็บค่าว่าผู้ใช้เปิด/ปิด GPU
  final void Function(bool)? onUseGpuChanged;

  /// โมเดลที่เปิดอยู่ใช้อะไรคิดจริง · null = ยังไม่ได้เปิด
  PreferredBackend? _activeBackend;
  PreferredBackend? get activeBackend => _activeBackend;

  /// คิดด้วย GPU อยู่จริงไหม · null = ยังไม่ได้เปิดโมเดล ยังไม่รู้
  bool? get runningOnGpu => _activeBackend == null
      ? null
      : _activeBackend == PreferredBackend.gpu;

  /// GPU ของเครื่องนี้ใช้ไม่ได้ — ลองแล้วล้ม หรือเคยพาแอปตายกลางทาง
  bool _gpuBroken = false;
  bool get gpuBroken => _gpuBroken;

  /// ธงใน SharedPreferences — ต้องรอดการที่ process ตายกลางทาง
  ///
  /// ไดรเวอร์ GPU บางรุ่นพา process ล่มทั้งก้อนตอนเปิด engine ซึ่ง try/catch
  /// จับไม่ได้ · ถ้าไม่จำไว้ แอปจะเปิด GPU → ตาย → เปิดใหม่ → ตาย วนไปไม่จบ
  static const _kGpuTrying = 'gemmaGpuTrying';
  static const _kGpuBroken = 'gemmaGpuBroken';

  bool _gpuMemoLoaded = false;

  Future<void> _loadGpuMemo() async {
    if (_gpuMemoLoaded) return;
    _gpuMemoLoaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(_kGpuTrying) ?? false) {
        // รอบก่อนเปิด GPU ค้างไว้แล้วไม่เคยกลับมาบอกว่าจบ = แอปตายกลางทาง
        debugPrint('gemma: รอบก่อนเปิด GPU แล้วแอปตาย — ใช้ CPU แทน');
        await p.setBool(_kGpuBroken, true);
        await p.remove(_kGpuTrying);
      }
      _gpuBroken = p.getBool(_kGpuBroken) ?? false;
    } on Object catch (e) {
      debugPrint('gemma: อ่านธง GPU ไม่ได้ — $e');
    }
  }

  static Future<void> _writeGpuFlag(String key, bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      v ? await p.setBool(key, true) : await p.remove(key);
    } on Object catch (e) {
      debugPrint('gemma: เขียนธง GPU ไม่ได้ — $e');
    }
  }

  /// เปิด/ปิด GPU · เปิดใหม่ = ให้โอกาส GPU อีกรอบ แม้เคยล้มมาแล้ว
  Future<void> setUseGpu(bool v) async {
    if (_useGpu == v && !(v && _gpuBroken)) return;
    _useGpu = v;
    onUseGpuChanged?.call(v);
    if (v && _gpuBroken) {
      _gpuBroken = false;
      await _writeGpuFlag(_kGpuBroken, false);
    }
    // โมเดลที่เปิดอยู่ผูกกับ backend เดิม · ปิดทิ้ง ตาถัดไปเปิดใหม่ด้วยค่าใหม่
    await _release();
    if (!_disposed) notifyListeners();
  }

  /// เปิดโมเดล — ลอง GPU ก่อน ไม่ได้ก็ CPU
  ///
  /// ปลั๊กอินเปิด engine จริงตอน `createModel` (ไม่ใช่ตอนสร้าง chat) และล้าง
  /// สถานะตัวเองเมื่อล้ม จึงเรียกซ้ำด้วย CPU ได้ทันทีในรอบเดียวกัน
  Future<InferenceModel> _createModel() async {
    await _loadGpuMemo();
    if (_useGpu && !_gpuBroken) {
      await _writeGpuFlag(_kGpuTrying, true);
      try {
        final m = await _createWith(PreferredBackend.gpu);
        _activeBackend = PreferredBackend.gpu;
        return m;
      } on Object catch (e) {
        // เครื่องไม่มี OpenCL / หน่วยความจำ GPU ไม่พอ / ไดรเวอร์ไม่รองรับ
        // · จำไว้ว่าเครื่องนี้ GPU ใช้ไม่ได้ ไม่ต้องรอให้มันล้มซ้ำทุกครั้งที่เปิดแอป
        debugPrint('gemma: เปิด GPU ไม่ได้ ใช้ CPU แทน — $e');
        _gpuBroken = true;
        await _writeGpuFlag(_kGpuBroken, true);
      } finally {
        await _writeGpuFlag(_kGpuTrying, false);
      }
    }
    final m = await _createWith(PreferredBackend.cpu);
    _activeBackend = PreferredBackend.cpu;
    return m;
  }

  Future<InferenceModel> _createWith(PreferredBackend backend) =>
      FlutterGemmaPlugin.instance.createModel(
        modelType: ModelType.gemmaIt,
        fileType: ModelFileType.litertlm,
        preferredBackend: backend,
        // มายด์ตอบสั้น แต่ system prompt (ข้อมูลเจ้าของ + ขอบเขต) ยาวพอควร
        // และตอนที่ต้องเล่าบทสนทนาย้อนหลัง คำถามเดียวก็ยาวได้หลายพันตัวอักษร
        maxTokens: 8192,
      );

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
    // หน้าตั้งค่าต้องรู้ตั้งแต่ก่อนทักคำแรก ว่าเครื่องนี้ GPU เคยใช้ไม่ได้
    await _loadGpuMemo();

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
  /// หรือยัง · เครื่องแรม 12 GB เคยได้ `best = E4B` แต่คนส่วนใหญ่โหลด E2B
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

  /// เปิดสมองอยู่ในหน่วยความจำแล้วไหม · false = คำถามถัดไปต้องรอเปิดก่อน
  bool get loaded => _model != null;

  /// เปิดสมองครั้งล่าสุดใช้เวลากี่มิลลิวินาที · null = ยังไม่เคยเปิด
  int? _lastLoadMs;
  int? get lastLoadMs => _lastLoadMs;

  /// ผลวัดของคำตอบล่าสุด · null = ยังไม่ได้ตอบสักครั้งในรอบนี้
  LocalReplyStats? _lastStats;
  LocalReplyStats? get lastStats => _lastStats;

  /// ขนาดไฟล์ที่อยู่ในเครื่องจริงของแต่ละรุ่น (จากการสแกนล่าสุด)
  final Map<GemmaVariant, int> _onDisk = {};

  /// ไบต์ของไฟล์ที่อยู่ในเครื่องจริง · null = ไม่มีไฟล์
  int? bytesOnDisk(GemmaVariant v) => _onDisk[v];

  bool _benchmarking = false;

  /// กำลังทดสอบความเร็วอยู่
  bool get benchmarking => _benchmarking;

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
    // 🔴 ข้อผิดพลาดจากเนทีฟมาเป็น `PlatformException(code, message, …)`
    // ซึ่งไม่มีโคลอนหลังชื่อคลาส ตัวตัดข้างล่างจึงจับไม่ได้ แล้วทั้งก้อนดิบ
    // ไปขึ้นกลางแชท · ใช้แค่ข้อความของมัน
    if (e is PlatformException) {
      return shortenError(e.message?.trim().isNotEmpty == true
          ? e.message!
          : e.code);
    }
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
    // 🔴 ห้ามสลับกลางการโหลด · การโหลดที่ยังวิ่งอยู่จะไปตรวจความครบและเข้า
    // ทะเบียนกับรุ่นที่**เพิ่งเลือก** แทนรุ่นที่มันโหลดจริง แล้วปุ่มโหลดโผล่
    // กลับมาให้กดซ้อนอีกตัว
    if (_stage == LocalModelStage.downloading) return;
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

  bool _swept = false;

  /// ลบไฟล์ของรุ่นที่ถอดออกไปแล้ว — ดู [retiredModels] ว่าทำไมต้องมี
  ///
  /// ครั้งเดียวต่อการเปิดแอปก็พอ · [refresh] ถูกเรียกทุกครั้งที่เข้าหน้าตั้งค่า
  /// และการถามระบบไฟล์ซ้ำ ๆ ไม่ได้ให้อะไรเพิ่มเลยหลังกวาดรอบแรกไปแล้ว
  Future<void> _sweepRetired() async {
    if (_swept) return;
    _swept = true;
    for (final r in retiredModels) {
      try {
        final spec = InferenceModelSpec.fromLegacyUrl(
          name: r.name,
          modelUrl: r.url,
          modelType: ModelType.gemmaIt,
          fileType: ModelFileType.litertlm,
        );
        final mm = FlutterGemmaPlugin.instance.modelManager;
        if (!await mm.isModelInstalled(spec)) continue;
        await mm.deleteModel(spec);
        debugPrint('gemma: ลบไฟล์รุ่นที่เลิกใช้แล้ว — ${r.name}');
      } on Object catch (e) {
        // ลบไม่สำเร็จคือเสียพื้นที่ ไม่ใช่ใช้งานไม่ได้ · ห้ามลาก refresh
        // ทั้งก้อนล้มตาม ไม่งั้นหน้าตั้งค่าจะขึ้น "เช็คโมเดลไม่ได้" ทั้งที่
        // โมเดลที่ใช้อยู่ปกติดี
        debugPrint('gemma: ลบ ${r.name} ไม่ได้ — $e');
      }
    }
  }

  /// เช็คว่าโมเดลอยู่ในเครื่องแล้วหรือยัง — ไล่ **ทุกรุ่น** ไม่ใช่เฉพาะรุ่นที่เลือก
  Future<void> refresh() async {
    // กำลังโหลดอยู่ = สถานะจริงคือ "กำลังโหลด" · สแกนตอนนี้จะเขียนทับเป็น
    // missing แล้วแถบความคืบหน้าหาย ปุ่มโหลดโผล่กลับมาทั้งที่ยังโหลดอยู่
    // (แตะสมองตัวเดิมซ้ำในหน้าตั้งค่าก็มาถึงตรงนี้)
    if (_stage == LocalModelStage.downloading) return;
    try {
      await _ensurePlugin();
      await _sweepRetired();

      _installed.clear();
      for (final v in GemmaVariant.values) {
        // ถามทีละรุ่น · ปลั๊กอินไม่มี API บอกรายการที่ติดตั้งไว้ทั้งหมด
        if (!await FlutterGemmaPlugin.instance.modelManager
            .isModelInstalled(_spec(v))) {
          continue;
        }
        // 🔴 มีไฟล์ยังไม่พอ ต้องครบด้วย — ดู [isComplete]
        // ไฟล์ครึ่งเดียวที่นับว่าติดตั้งแล้ว = ปุ่มโหลดหายไป ผู้ใช้ติดอยู่
        // กับข้อความ engine ที่แปลไม่ออกโดยไม่มีทางแก้เอง
        if (await isComplete(v)) _installed.add(v);
      }

      final installed = _installed.contains(_variant);
      // ไฟล์อยู่ในเครื่องแล้ว = บอกปลั๊กอินตั้งแต่ตอนนี้เลย · ดู [_markActive]
      // ว่าทำไมของที่ "ติดตั้งแล้ว" ยังใช้ไม่ได้ถ้าไม่บอก
      if (installed) _markActive();
      _set(installed ? LocalModelStage.ready : LocalModelStage.missing);
    } on Exception catch (e) {
      debugPrint('gemma: เช็คโมเดลไม่ได้ — $e');
      _set(LocalModelStage.failed, error: _s().errCheckModel(shortenError(e)));
    }
  }

  /// โหลดโมเดลลงเครื่อง — หลาย GB ต้องมีไวไฟและพื้นที่ว่างพอ
  Future<void> download() async {
    if (_stage == LocalModelStage.downloading) return; // แตะซ้ำ = ไม่โหลดซ้อน
    // ผูกกับรุ่นที่เริ่มโหลด ไม่ใช่รุ่นที่เลือกอยู่ตอนจบ
    final v = _variant;
    _progress = 0;
    _bytesPerSecond = 0;
    _startedAt = DateTime.now();
    _set(LocalModelStage.downloading);
    try {
      await _ensurePlugin();
      final stream = FlutterGemmaPlugin.instance.modelManager
          .downloadModelWithProgress(_spec(v));
      await for (final p in stream) {
        if (_disposed) return;
        _progress = p.currentFileProgress;

        // ความเร็วเฉลี่ยตั้งแต่เริ่ม นิ่งกว่าความเร็วชั่วขณะ
        // ตัวเลขที่กระโดดไปมาทำให้ ETA เชื่อถือไม่ได้และผู้ใช้กังวลเปล่า ๆ
        final elapsed = DateTime.now().difference(_startedAt!).inSeconds;
        if (elapsed > 0) _bytesPerSecond = downloadedBytes ~/ elapsed;

        notifyListeners();
      }
      // 🔴 ตรวจว่าครบจริงก่อนบอกว่าเสร็จ
      //
      // สตรีมจบไม่ได้แปลว่าไฟล์ครบ · เน็ตหลุดกลางทางแล้วสตรีมปิดตัวเองเงียบ ๆ
      // ก็มาถึงบรรทัดนี้เหมือนกัน · ถ้าไม่ตรวจ ผู้ใช้จะได้ไฟล์ครึ่งเดียวที่
      // ระบบบอกว่า "พร้อมใช้" แล้วไปเจอข้อความ engine ที่แปลไม่ออกตอนกดคุย
      if (!await isComplete(v)) {
        // ลบทิ้งเลย · เก็บไว้แปลว่ารอบหน้า `isModelInstalled` ยังตอบ true
        // แล้วผู้ใช้จะติดอยู่ในวงเดิมโดยไม่มีปุ่มให้กดโหลดใหม่
        await _removeFile(v);
        _installed.remove(v);
        _set(LocalModelStage.failed, error: _s().errModelIncomplete);
        return;
      }

      // โหลดจบแล้วต้องเข้าทะเบียนทันที ไม่ต้องรอสแกนรอบหน้า ไม่งั้นสลับไป
      // รุ่นอื่นแล้วกลับมาจะขึ้นปุ่มโหลดซ้ำทั้งที่เพิ่งโหลดเสร็จ
      _installed.add(v);
      _set(LocalModelStage.ready);
    } on Object catch (e) {
      debugPrint('gemma: โหลดโมเดลไม่สำเร็จ — $e');
      _set(LocalModelStage.failed, error: _s().errDownloadModel(shortenError(e)));
    }
  }

  Future<void> _removeFile(GemmaVariant v) async {
    try {
      await FlutterGemmaPlugin.instance.modelManager.deleteModel(_spec(v));
    } on Object catch (e) {
      debugPrint('gemma: ลบไฟล์ที่ไม่ครบไม่สำเร็จ — $e');
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
  /// systemInstruction ผูกกับ session ตอนสร้าง จึงต้องสร้าง chat ใหม่เมื่อมัน
  /// เปลี่ยน**จริง** (ดู [sessionKeyOf] ว่าอะไรนับว่าเปลี่ยน)
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

  /// [onPartial] ได้ข้อความที่พิมพ์มาแล้วทั้งก้อนทุกครั้งที่มีคำใหม่ · ให้หน้าจอ
  /// โชว์คำตอบระหว่างที่เธอยังคิดอยู่ ไม่ต้องนั่งดูจุดสามจุดจนจบประโยค
  ///
  /// [cap] เพดานของงานนี้ (ดู [ReplyCap]) · ไม่ใส่ = เพดานของการคุยปกติ
  Future<String> reply({
    required String system,
    required List<Turn> history,
    void Function(String partial)? onPartial,
    ReplyCap cap = ReplyCap.chat,
    String recall = '',
  }) {
    final done = Completer<String>();
    final ticket = _abortTicket;
    _queue = _queue.then((_) async {
      try {
        // ถูกสั่งเลิกระหว่างรอคิว (ปุ่มออกจากแอป) = ไม่ต้องเริ่มคิดเลย
        if (ticket != _abortTicket) throw OpenAiFailure(_s().errLocalStopped);
        done.complete(await _reply(
            system: system,
            history: history,
            onPartial: onPartial,
            cap: cap,
            recall: recall));
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
    void Function(String partial)? onPartial,
    required ReplyCap cap,
    String recall = '',
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
      final coldStart = _model == null;
      final continued = await _ensureChat(system, history);
      final chat = _chat!;

      // นับจากตรงนี้ · เวลาเปิดสมอง (ถ้ามี) แยกไว้อีกตัว จะได้รู้ว่าช้าเพราะอะไร
      final clock = Stopwatch()..start();

      // ต่อจากของเดิมได้ = เนทีฟถือประวัติไว้ครบแล้ว ส่งแค่คำล่าสุดพอ
      // ต่อไม่ได้ = session เพิ่งเกิดใหม่และว่างเปล่า ต้องเล่าย้อนให้ฟังก่อน
      // บันทึกช่วยจำ (สิ่งที่นึกออก) แนบหน้าข้อความ **ตอนส่งเท่านั้น**
      // · ไม่ลง [_fed] ซึ่งจำตามบทสนทนาจริง ไม่งั้นตาถัดไปเทียบไม่ตรง แล้ว
      // ต้องเปิด session ใหม่ทุกตา (ดู MindState.recallFor)
      final said = continued ? last : _withTranscript(history);
      await chat.addQuery(Message.text(
        text: recall.isEmpty ? said : '$recall\n\n$said',
        isUser: true,
      ));

      // 🔴 สตรีมทีละคำ ไม่ใช่รอทั้งก้อน
      //
      // บนมือถือคำตอบหนึ่งประโยคกินเวลาหลายวินาที · ของเดิมรอจนจบแล้วค่อยโชว์
      // ทั้งก้อน คนถามเห็นจุดสามจุดค้างอยู่ตลอดช่วงนั้นแล้วอ่านว่า "ช้า" ทั้งที่
      // คำแรกพร้อมตั้งนานแล้ว · ความเร็วจริงเท่าเดิม แต่ไม่ต้องรอดูความว่างเปล่า
      final buf = StringBuffer();
      int? firstMs;
      var tokens = 0;
      final ticket = _abortTicket;
      // 🔴 **ต้องมีเพดาน** · เนทีฟคิดต่อได้จนเต็ม 8192 token ถ้าโมเดลวนซ้ำ
      // (เจอบนเครื่องจริง: เครื่องร้อนจัด ทั้งเครื่องช้า เธอเงียบ ปุ่มออกจากแอป
      // ค้าง เพราะทุกอย่างต่อคิวรอคำตอบที่ไม่มีวันจบ) · ตัดที่จำนวนคำ เวลา
      // หรือเมื่อเห็นว่าวนซ้ำ แล้วสั่งเนทีฟให้หยุดจริง ไม่ใช่แค่เลิกฟัง
      String? cut;
      var keep = -1;
      await for (final r in chat.generateChatResponseAsync()) {
        if (r is! TextResponse || r.token.isEmpty) continue;
        firstMs ??= clock.elapsedMilliseconds;
        buf.write(r.token);
        tokens++;
        if (ticket != _abortTicket) {
          cut = 'stopped';
        } else if (tokens >= cap.tokens) {
          cut = 'tokens';
        } else if (clock.elapsed >= cap.time) {
          cut = 'time';
        } else if (tokens % 24 == 0) {
          final at = loopAt(buf.toString());
          if (at != null) {
            cut = 'loop';
            keep = at;
          }
        }
        if (cut != null) break;
        onPartial?.call(buf.toString());
      }
      clock.stop();

      var text = buf.toString();
      if (cut != null) {
        await _haltNative(chat);
        if (keep > 0 && keep < text.length) text = text.substring(0, keep);
        // ภาษาอังกฤษโดยตั้งใจ · ข้อความนี้ไปที่รายงานให้คนไล่บั๊กอ่าน ไม่ขึ้นจอ
        final why = 'gemma: cut reply ($cut) at $tokens tokens · '
            '${clock.elapsed.inSeconds}s · ${cap.name}';
        debugPrint(why);
        onRunaway?.call(why);
        if (cut == 'stopped') throw OpenAiFailure(_s().errLocalStopped);
      }
      if (text.trim().isEmpty) {
        throw OpenAiFailure(_s().errLocalEmpty);
      }

      final backend = _activeBackend;
      if (backend != null) {
        _lastStats = LocalReplyStats(
          variant: _variant,
          backend: backend,
          loadMs: coldStart ? _lastLoadMs : null,
          newSession: !continued,
          firstMs: firstMs ?? clock.elapsedMilliseconds,
          totalMs: clock.elapsedMilliseconds,
          chars: text.trim().length,
        );
        debugPrint('gemma: ตอบใน ${_lastStats!.waitMs} ms ถึงคำแรก · '
            'ทั้งหมด ${_lastStats!.totalMs} ms · ${backend.name}'
            '${coldStart ? ' (เปิดสมอง ${_lastLoadMs ?? '?'} ms)' : ''}'
            '${continued ? '' : ' · อ่านบทสนทนาใหม่'}');
        if (!_disposed) notifyListeners();
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

  String _withTranscript(List<Turn> history) =>
      transcriptFor(history, _s(), her: herName?.call());

  /// ชื่อที่เจ้าของตั้งให้เธอ · null = ชื่อเดิม
  ///
  /// 🔴 ป้ายในบทที่เล่าย้อนต้องเป็นชื่อเดียวกับใน system prompt · ตั้งชื่อใหม่แล้ว
  /// บทยังเขียนว่า "มายด์:" = โมเดลเห็นสองคน คนหนึ่งชื่อใหม่ อีกคนชื่อเก่าที่พูด
  /// ทุกบรรทัดของเธอ
  String? Function()? herName;

  /// บทสนทนาก่อนหน้าเป็นข้อความก้อนเดียว ต่อท้ายด้วยคำที่เพิ่งพิมพ์มา
  ///
  /// 🔴 **ไม่ยัดตาเก่าเข้าไปทีละตาผ่าน `addQuery`** ทั้งที่ดูเป็นวิธีที่ตรงกว่า
  /// เพราะไฟล์ `.litertlm` บนแอนดรอยด์ส่งข้อความดิบลงเนทีฟโดย**ไม่ได้ติดป้าย
  /// ว่าใครพูด** (ดู Message.transformToChatPrompt) เนทีฟถือว่าทุกก้อนที่ป้อน
  /// เข้ามาคือฝั่งผู้ใช้ แล้วคำตอบเก่าของเธอจะกลายเป็นคำที่เจ้าของพูด
  /// ติดป้ายเองในข้อความจึงเป็นวิธีเดียวที่บทบาทไม่สลับ
  @visibleForTesting
  static String transcriptFor(List<Turn> history, S s, {String? her}) {
    if (history.isEmpty) return '';
    final past = history.sublist(0, history.length - 1);
    if (past.isEmpty) return history.last.text.trim();

    final herLabel = (her?.trim().isNotEmpty ?? false) ? her!.trim() : s.speakerHer;
    final lines = past
        .map((t) => '${t.fromHer ? herLabel : s.speakerMe}: ${t.text}')
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

  /// ขนาดไฟล์โมเดลที่อยู่ในเครื่องจริง · null = หาไม่เจอ
  ///
  /// ถามปลั๊กอินว่าไฟล์อยู่ไหน แทนที่จะเดาโครงโฟลเดอร์เอง — มันย้ายที่เก็บ
  /// ได้ทุกเวอร์ชัน และเราจะไม่รู้จนกว่าจะพัง
  Future<int?> installedBytes(GemmaVariant v) async {
    try {
      final paths = await FlutterGemmaPlugin.instance.modelManager
          .getModelFilePaths(_spec(v));
      final path = paths?.values.firstOrNull;
      if (path == null) return null;
      final f = File(path);
      return await f.exists() ? await f.length() : null;
    } on Object catch (e) {
      debugPrint('gemma: วัดขนาดไฟล์ไม่ได้ — $e');
      return null;
    }
  }

  /// ไฟล์ครบไหม
  ///
  /// 🔴 **ไฟล์ที่มีอยู่ ≠ ไฟล์ที่ใช้ได้**
  ///
  /// `isModelInstalled()` ของปลั๊กอินดูแค่ว่า*มีไฟล์อยู่* · โหลด 2.9 GB
  /// ค้างกลางทางแล้วเน็ตหลุด จะได้ไฟล์ครึ่งเดียวที่ตอบว่า "ติดตั้งแล้ว"
  /// ตลอดไป · สถานะในแอปเป็น `ready` ทุกอย่างดูปกติ จนกว่าจะกดคุย แล้วได้
  /// `NOT_FOUND: TF_LITE_PREFILL_DECODE not found in the model` ซึ่งไม่มีทาง
  /// เดาจากข้อความนั้นได้เลยว่าแปลว่า "โหลดไม่ครบ"
  ///
  /// เทียบกับขนาดที่รู้อยู่แล้ว (ยืนยันกับ Hugging Face ตรงกันเป๊ะทั้งสองรุ่น)
  /// · ยอมคลาดเคลื่อนเล็กน้อยไว้เผื่อวันที่ผู้ให้บริการ rebuild ไฟล์แล้วขนาด
  /// ขยับไปไม่กี่ไบต์ — ของที่ขาดไปครึ่งกิกจะยังถูกจับได้อยู่ดี
  static const _sizeTolerance = 0.02;

  Future<bool> isComplete(GemmaVariant v) async {
    final actual = await installedBytes(v);
    if (actual == null) {
      _onDisk.remove(v);
      return false;
    }
    _onDisk[v] = actual;
    final diff = (actual - v.bytes).abs() / v.bytes;
    if (diff <= _sizeTolerance) return true;
    debugPrint('gemma: ${v.id} ไฟล์ไม่ครบ — มี $actual ควรมี ${v.bytes}');
    return false;
  }

  /// 🔴 บอกปลั๊กอินว่า "ใช้รุ่นไหน" ก่อนสร้างโมเดล **ทุกครั้ง**
  ///
  /// ## อาการที่เจอบนเครื่องจริง
  ///
  /// โหลดโมเดลเสร็จ คุยได้ปกติ · **ปิดแอปเปิดใหม่แล้วพังถาวร** ด้วย
  /// `No active inference model set. Use FlutterGemma.installModel() or
  /// modelManager.setActiveModel() to set a model first`
  ///
  /// ## ทำไม
  ///
  /// `_activeInferenceModel` ของปลั๊กอินเป็น **ตัวชี้ในหน่วยความจำล้วน**
  /// มันถูกตั้งให้เองตอน `downloadModel*` เท่านั้น (mobile_model_manager.dart
  /// บรรทัด 182/196/211/324/678) และ **ไม่มีอะไรกู้มันคืนตอนเปิดแอปรอบหน้า**
  ///
  /// `isModelInstalled()` ยังตอบ true อยู่ (ไฟล์อยู่ในเครื่องจริง) สถานะใน
  /// แอปจึงเป็น `ready` ทุกอย่างดูปกติหมด — จนกว่าจะถึงบรรทัดที่สร้างโมเดลจริง
  ///
  /// ## กับดักของเรื่องนี้
  ///
  /// ทดสอบตอนเพิ่งโหลดเสร็จจะ**ไม่มีวันเจอ** เพราะรอบนั้นตัวชี้ยังอยู่
  /// ต้องปิดแอปแล้วเปิดใหม่ถึงจะโผล่ · เป็นเหตุผลที่มันรอดมาถึงมือผู้ใช้
  ///
  /// เรียกทุกครั้งก่อนสร้าง ไม่ใช่ครั้งเดียวตอนเริ่ม — มันแค่ตั้งค่าฟิลด์
  /// (ดู `setActiveModel` บรรทัด 710) ไม่มีค่าใช้จ่ายให้ต้องประหยัด
  /// และการเรียกทุกครั้งแปลว่าการสลับรุ่นก็ถูกต้องเองโดยไม่ต้องจำอะไรเพิ่ม
  void _markActive() {
    try {
      FlutterGemmaPlugin.instance.modelManager.setActiveModel(_spec(_variant));
    } on Object catch (e) {
      // ตั้งไม่ได้ก็ปล่อยให้ createModel เป็นคนบอกเหตุผลจริง — ข้อความของมัน
      // ตรงกว่าที่เราจะเดาเองตรงนี้
      debugPrint('gemma: ตั้งรุ่นที่ใช้ไม่สำเร็จ — $e');
    }
  }

  /// session ที่เปิดอยู่เกิดเมื่อไหร่ และต่อมาแล้วกี่ตา
  DateTime? _sessionAt;
  int _sessionTurns = 0;

  /// 🔴 ใช้ session เดิมต่อได้นานแค่ไหน แม้ตัวเลขใน prompt จะขยับไปแล้ว
  ///
  /// session ใหม่ = โมเดลต้องอ่าน prompt ทั้งก้อนและบทสนทนาที่เล่าย้อนใหม่
  /// ทั้งหมด ซึ่งคือส่วนที่ช้าที่สุดบนมือถือ · ของเดิมสร้างใหม่ทุกครั้งที่ prompt
  /// ต่างไปแม้แต่ตัวเลขเดียว และ prompt ของเธอมีตัวเลขที่ขยับทุกตา (ความผูกพัน
  /// เป็น %, ระดับงอน, ชั่วโมงตอนนี้) = อ่านใหม่ทั้งบท**ทุกตา**
  ///
  /// ตอนนี้ตัวเลขที่ขยับไม่นับเป็นการเปลี่ยน (ดู [sessionKeyOf]) แต่ต้องมีเพดาน
  /// ไม่งั้นเธอจะคิดด้วยตัวเลขเก่าไปตลอด · เปลี่ยนจริง (เรื่องใหม่ในความจำ
  /// สายเข้าใหม่ สลับโหมด) ยังสร้างใหม่ทันทีเหมือนเดิม
  static const _sessionMaxTurns = 8;
  static const _sessionMaxAge = Duration(minutes: 30);

  bool get _sessionFresh =>
      _sessionTurns < _sessionMaxTurns &&
      _sessionAt != null &&
      DateTime.now().difference(_sessionAt!) < _sessionMaxAge;

  /// ป้ายที่บอกว่า prompt สองก้อน "ต่างกันจริง" ไหม
  ///
  /// ตัวเลขทุกตัวถูกมองข้าม — ที่ขยับทุกตาคือตัวเลขล้วน (% ความผูกพัน,
  /// ระดับงอน, จำนวนวันที่รู้จัก, ชั่วโมงตอนนี้) ส่วนเรื่องที่ควรสร้าง session
  /// ใหม่ทันทีมาเป็น**บรรทัด**เสมอ (ความจำใหม่ นัดใหม่ สายใหม่ เริ่มงอน
  /// เปลี่ยนสถานะความสัมพันธ์)
  @visibleForTesting
  static String sessionKeyOf(String system) =>
      system.replaceAll(RegExp(r'\d+'), '#');

  /// คืนค่าว่า session ที่ได้ **ต่อจากบทสนทนาเดิมได้เลย** หรือเพิ่งเกิดใหม่
  Future<bool> _ensureChat(String system, List<Turn> history) async {
    await _ensurePlugin();
    if (_model == null) await _open();

    final key = sessionKeyOf(system);
    if (_chat != null &&
        _loadedSystem == key &&
        _sessionFresh &&
        _continues(history)) {
      _sessionTurns++;
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
    _loadedSystem = key;
    _sessionAt = DateTime.now();
    _sessionTurns = 0;
    _fed = const [];
    return false;
  }

  /// เปิดสมองเข้าหน่วยความจำ แล้วจับเวลาไว้บอกเจ้าของ
  Future<void> _open() async {
    final clock = Stopwatch()..start();
    _markActive();
    _model = await _createModel();
    _lastLoadMs = clock.elapsedMilliseconds;
    _loadedSystem = null;
    debugPrint('gemma: เปิดสมอง ${_variant.id} ด้วย ${_activeBackend?.name} '
        'ใน $_lastLoadMs ms');
    if (!_disposed) notifyListeners(); // หน้าตั้งค่าบอกว่าใช้ GPU หรือ CPU อยู่
  }

  /// เปิดสมองรอไว้ก่อน ไม่ต้องรอให้ทักคำแรก
  ///
  /// 🔴 การเปิดสมองคือส่วนที่ช้าที่สุดของคำถามแรก — อ่านไฟล์ 2–3 GB เข้า
  /// หน่วยความจำ และบน GPU ต้องคอมไพล์ shader อีกรอบ รวมกันหลายวินาทีถึง
  /// หลายสิบวินาที · ของเดิมเริ่มทำตอนเจ้าของกดส่งคำแรก เขาจึงจ่ายเวลานี้
  /// ทุกครั้งที่เปิดแอป ทั้งที่แอปว่างอยู่ตั้งแต่เปิดขึ้นมา
  ///
  /// ต่อคิวเดียวกับการคิด · ล้มก็เงียบ คำถามแรกจะลองเปิดเองอีกรอบอยู่แล้ว
  Future<void> preload() {
    final done = Completer<void>();
    _queue = _queue.then((_) async {
      try {
        if (_stage == LocalModelStage.unknown) await refresh();
        if (_disposed || _model != null || _stage != LocalModelStage.ready) {
          return;
        }
        await _ensurePlugin();
        await _open();
      } on Object catch (e) {
        debugPrint('gemma: เปิดสมองรอไว้ไม่สำเร็จ — ${shortenError(e)}');
      } finally {
        done.complete();
      }
    });
    return done.future;
  }

  /// ทดสอบความเร็วด้วยคำถามสั้น ๆ คำถามเดียว แล้วคืนผลวัดจริง
  ///
  /// ให้เจ้าของเห็นกับตาว่าโมเดลอยู่ในเครื่องจริงและตอบได้เร็วแค่ไหน · ใช้บทบาท
  /// สั้น ๆ ของมันเอง ซึ่งแปลว่าตาถัดไปของบทสนทนาจริงต้องอ่านบทใหม่หนึ่งรอบ
  Future<LocalReplyStats?> benchmark() async {
    if (_benchmarking) return null;
    _benchmarking = true;
    if (!_disposed) notifyListeners();
    try {
      final s = _s();
      await reply(
        system: s.gemmaBenchSystem,
        history: [(fromHer: false, text: s.gemmaBenchQuestion)],
      );
      return _lastStats;
    } finally {
      _benchmarking = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// ปล่อยสมองออกจากหน่วยความจำ (ปุ่มออกจากแอป) · ไฟล์ในเครื่องยังอยู่
  ///
  /// 🔴 สั่งเลิกงานที่กำลังคิดอยู่**ก่อน** แล้วค่อยต่อคิวปล่อย · ของเดิมต่อคิว
  /// อย่างเดียว ปุ่มออกจากแอปจึงต้องรอคำตอบที่ค้างอยู่ (ซึ่งอาจไม่มีวันจบ)
  Future<void> unload() {
    abort();
    return _release();
  }

  /// เลขรอบของการสั่งเลิก · งานที่จำเลขเก่าไว้รู้ตัวว่าถูกยกเลิกแล้ว
  int _abortTicket = 0;

  /// ให้เลิกคิดเดี๋ยวนี้ ทั้งงานที่คิดอยู่และงานที่รอคิว · ไม่รอให้หยุดจริง
  void abort() {
    _abortTicket++;
    final chat = _chat;
    if (chat != null) unawaited(_haltNative(chat));
  }

  /// สั่งเนทีฟหยุดสร้างคำ แล้วทิ้ง session · มีเวลาหมดเพราะเนทีฟที่ค้างอาจไม่ตอบ
  ///
  /// session ที่ถูกตัดกลางประโยคไม่รู้ว่าเนทีฟจำอะไรไว้บ้าง · ทิ้งแล้วเปิดใหม่
  /// (เล่าบทย้อนใหม่หนึ่งรอบ) ปลอดภัยกว่าต่อจากของที่ขาดครึ่ง
  Future<void> _haltNative(InferenceChat chat) async {
    try {
      await chat.stopGeneration().timeout(const Duration(seconds: 3));
    } on Object catch (e) {
      debugPrint('gemma: สั่งหยุดไม่สำเร็จ — ${e.runtimeType}');
    }
    if (identical(_chat, chat)) {
      _chat = null;
      _loadedSystem = null;
      _fed = const [];
      unawaited(chat.close().timeout(const Duration(seconds: 3)).catchError((_) {}));
    }
  }

  /// แจ้งเมื่อคำตอบถูกตัดเพราะยาว/นาน/วนซ้ำ · state ส่งต่อเป็นรายงาน
  void Function(String what)? onRunaway;

  /// ตำแหน่งที่ข้อความเริ่มวนซ้ำ (ตัดตรงนี้แล้วเหลือรอบแรกไว้) · null = ไม่วน
  ///
  /// ท้ายข้อความ [tail] ตัวอักษรโผล่ซ้ำตั้งแต่ [times] ครั้ง = โมเดลติดลูป
  /// ข้อความจริงแทบไม่มีวลียาว 40 ตัวที่ซ้ำเป๊ะสามรอบ
  @visibleForTesting
  static int? loopAt(String text, {int tail = 40, int times = 3}) {
    if (text.length < tail * times) return null;
    final t = text.substring(text.length - tail);
    var count = 0;
    var first = -1;
    for (var i = text.indexOf(t); i != -1; i = text.indexOf(t, i + 1)) {
      if (first < 0) first = i;
      if (++count >= times) return first + tail;
    }
    return null;
  }

  /// ปล่อยโมเดล — **ต่อคิวเดียวกับการคิดคำตอบ**
  ///
  /// สลับรุ่น/ลบโมเดลระหว่างที่เธอกำลังคิดอยู่ = ปิด session ที่เนทีฟกำลัง
  /// สร้างคำตอบให้อยู่ · ต่อคิวไว้ ให้คำตอบที่ค้างอยู่จบก่อนค่อยปล่อย
  Future<void> _release() {
    final done = Completer<void>();
    _queue = _queue.then((_) async {
      await _releaseNow();
      done.complete();
    });
    return done.future;
  }

  Future<void> _releaseNow() async {
    try {
      await _chat?.close();
      await _model?.close();
    } on Object {
      // ปิดไม่ได้ก็ปล่อย จะสร้างใหม่รอบหน้าอยู่แล้ว
    }
    _chat = null;
    _model = null;
    _activeBackend = null;
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
