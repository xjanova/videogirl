import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/ai/device_capability.dart';
import 'package:videogirl/ai/local_brain.dart';
import 'package:videogirl/ai/secret_store.dart';
import 'package:videogirl/state/mind_state.dart';

/// สิ่งที่ผู้ใช้เห็นตอนโมเดลในเครื่องมีปัญหา
///
/// ที่มา: หน้าตั้งค่าเคยขึ้นข้อความข้อผิดพลาดของปลั๊กอินทั้งดุ้น — สิบกว่าบรรทัด
/// มี `void main() async {...}` กับลิงก์ pub.dev ติดมาด้วย ผู้ใช้ทำอะไรกับมัน
/// ไม่ได้เลยนอกจากตกใจ
void main() {
  _activeModelGroup();
  _variantGroup();

  group('ย่อข้อความข้อผิดพลาดก่อนเอาไปโชว์', () {
    test('ข้อผิดพลาดหลายบรรทัด เหลือแค่บรรทัดแรก', () {
      // นี่คือของจริงที่เคยขึ้นบนหน้าจอ ย่อมาเล็กน้อย
      const real = 'ModelDownloadException: Failed to download model: '
          'gemma-4-e4b-gpu (location: unknown)\n\n'
          'You must call FlutterGemma.initialize() in main() before using '
          'the plugin.\n\n'
          'Example:\n'
          '  void main() async {\n'
          '    WidgetsFlutterBinding.ensureInitialized();\n'
          '    await FlutterGemma.initialize();\n'
          '    runApp(MyApp());\n'
          '  }\n';

      final short = LocalBrain.shortenError(real);

      expect(short, isNot(contains('void main')));
      expect(short, isNot(contains('runApp')));
      expect(short, isNot(contains('\n')));
      // ยังต้องบอกได้ว่าเกิดอะไรขึ้น ไม่ใช่ย่อจนไม่เหลือความหมาย
      expect(short, contains('Failed to download model'));
    });

    test('คำนำหน้าชนิดข้อผิดพลาดถูกตัดออก ไม่ให้โผล่ถึงผู้ใช้', () {
      expect(LocalBrain.shortenError(Exception('เน็ตหลุด')), 'เน็ตหลุด');
      expect(LocalBrain.shortenError(StateError('ยังไม่พร้อม')), 'ยังไม่พร้อม');
    });

    test('ข้อความยาวมากถูกตัด ไม่ดันจอจนอ่านอย่างอื่นไม่ได้', () {
      final short = LocalBrain.shortenError('x' * 500);

      expect(short.length, lessThanOrEqualTo(140));
      expect(short, endsWith('…'));
    });

    test('ข้อผิดพลาดที่ไม่มีข้อความ ต้องไม่กลายเป็นช่องว่างเปล่า', () {
      // ช่องว่างเปล่าบนหน้าจอ = ผู้ใช้ไม่รู้ว่าพังหรือไม่พัง
      final short = LocalBrain.shortenError(Exception(''));

      expect(short.trim(), isNotEmpty);
    });
  });

  group('ที่อยู่ไฟล์โมเดลทุกรุ่น', () {
    test('ประกอบเป็น URL ของ HuggingFace ที่ถูกต้อง และไม่ซ้ำกัน', () {
      final urls = <String>{};

      for (final v in GemmaVariant.values) {
        expect(v.url, startsWith('https://huggingface.co/'));
        expect(v.url, contains('/resolve/main/'));
        expect(v.url, endsWith('.litertlm'),
            reason: 'ใส่ .task แทน .litertlm = เทมเพลตซ้อนสองชั้น คำตอบเพี้ยน');
        expect(v.bytes, greaterThan(1000000000), reason: 'โมเดลพวกนี้เป็น GB');
        urls.add(v.url);
      }

      expect(urls.length, GemmaVariant.values.length,
          reason: 'สองรุ่นชี้ไฟล์เดียวกัน = เลือกรุ่นแล้วได้ของเดิม');
    });

    /// 🔴 ไฟล์ `-gpu.litertlm` ของ litert-community **รันไทม์ที่เราพ่วงมา
    /// อ่านไม่ออก**
    ///
    /// มันประกาศ `backend_constraint: gpu_artisan` และข้างในมีแต่ส่วน
    /// `gpu_artisan` / `tf_lite_artisan_text_decoder` ส่วน LiteRT-LM 0.10.0
    /// หาส่วนชื่อ `tf_lite_prefill_decode` ที่ไม่มีอยู่ในนั้น
    ///
    /// ที่เจ็บคือมันพังตอน **สร้าง engine** ไม่ใช่ตอนโหลด — โหลดจบ 100%
    /// หน้าตั้งค่าขึ้นเขียวว่าพร้อมใช้ แล้วค่อยตายตอนทักคำแรก หลังผู้ใช้
    /// เสียเน็ตไป 3 GB · ไม่มีเทสต์ไหนในเครื่องจับได้เพราะไฟล์ไม่ได้อยู่ในเครื่อง
    ///
    /// เทสต์นี้จับที่ *ชื่อไฟล์* ซึ่งเป็นจุดเดียวที่ยังตรวจได้ตอนคอมไพล์
    test('🔴 ห้ามชี้ไปที่ไฟล์ -gpu ที่ LiteRT-LM 0.10.0 อ่านไม่ออก', () {
      for (final v in GemmaVariant.values) {
        expect(v.file, isNot(contains('-gpu')),
            reason: 'ไฟล์ -gpu ตายตอนสร้าง engine หลังโหลดจบแล้ว: ${v.id}');
        expect(v.backend, PreferredBackend.cpu,
            reason: 'ไฟล์พวกนี้ประกาศ backend_constraint: cpu มาเอง: ${v.id}');
      }
    });

    /// รุ่นที่ถอดออกต้องมีคนตามไปลบไฟล์ให้ ไม่งั้นเหลือ 2–3 GB ที่ลบไม่ได้
    test('รุ่นที่ถอดออกไปแล้ว ต้องอยู่ในรายการที่ตามไปลบ และไม่ทับของที่ใช้อยู่', () {
      final live = {for (final v in GemmaVariant.values) v.url};

      expect(retiredModels, isNotEmpty);
      for (final r in retiredModels) {
        expect(r.url, startsWith('https://huggingface.co/'));
        expect(r.url, endsWith('.litertlm'));
        expect(live, isNot(contains(r.url)),
            reason: 'ลบตัวที่ยังใช้อยู่ = ผู้ใช้ต้องโหลดใหม่ทุกครั้งที่เปิดแอป');
      }
    });
  });

  group('รุ่นที่เอาไปให้ผู้ใช้เลือก', () {
    test('เครื่องเล็ก ต้องไม่เห็นรุ่นที่รันไม่ไหว', () {
      // แรม 6 GB (ระบบรายงานราว 5500) — ไหวแค่ E2B GPU
      final verdict = DeviceCapability.verdictFor(5500);

      final list = LocalBrain.selectableFor(verdict, const {});

      expect(list, contains(GemmaVariant.e2bCpu));
      expect(list, isNot(contains(GemmaVariant.e4bCpu)),
          reason: 'โชว์ E4B ให้เครื่องที่รันไม่ไหว = เขาเสียเน็ตโหลด 3.7 GB ฟรี');
    });

    test('เครื่องใหญ่ เห็นครบทุกรุ่น', () {
      final verdict = DeviceCapability.verdictFor(11000);

      expect(LocalBrain.selectableFor(verdict, const {}),
          GemmaVariant.values.toList());
    });

    test('รุ่นที่โหลดไว้แล้ว ต้องไม่ถูกซ่อนแม้เกินเกณฑ์', () {
      // เคยโหลด E4B ไว้ตอนใช้เครื่องอื่น หรือเกณฑ์เพิ่งถูกขยับ
      // ซ่อนทิ้งเฉย ๆ = พื้นที่ 2.8 GB ที่หายไปโดยลบไม่ได้
      final verdict = DeviceCapability.verdictFor(5500);

      final list =
          LocalBrain.selectableFor(verdict, const {GemmaVariant.e4bCpu});

      expect(list, contains(GemmaVariant.e4bCpu));
    });

    test('ยังไม่ได้ตรวจแรม ให้เห็นทุกรุ่นไปก่อน ไม่ใช่รายการเปล่า', () {
      // รายการเปล่าชั่วครู่แล้วค่อยโผล่ = จอกะพริบ อ่านได้ว่าแอปพัง
      expect(LocalBrain.selectableFor(null, const {}),
          GemmaVariant.values.toList());
    });

    test('เครื่องเล็กเกินไปจริง ๆ ไม่เหลือรุ่นให้เลือกเลย', () {
      final verdict = DeviceCapability.verdictFor(3000);

      expect(verdict.allowed, isEmpty);
      expect(LocalBrain.selectableFor(verdict, const {}), isEmpty);
    });
  });

  group('คีย์ของผู้ใช้', () {
    test('ปิดบังแล้วยังพอรู้ว่าใส่ถูกตัว แต่เอาไปใช้ต่อไม่ได้', () {
      const key = 'sk-proj-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789';

      final masked = SecretStore.mask(key);

      expect(masked, isNot(contains('MnOpQrSt')));
      expect(masked.length, lessThan(key.length));
      expect(masked, startsWith('sk-proj'));
      expect(masked, endsWith('6789'));
    });

    test('ค่าว่างไม่กลายเป็นจุดไข่ปลาหลอกว่ามีคีย์', () {
      expect(SecretStore.mask(''), '');
      expect(SecretStore.mask('   '), '');
    });

    test('สั้นผิดปกติ ปิดทั้งหมด ไม่เผยแม้แต่ต้นคีย์', () {
      expect(SecretStore.mask('sk-abc'), '••••••');
    });

    test('รูปแบบคีย์ OpenAI — เตือนได้ว่าน่าจะใส่ผิดช่อง', () {
      expect(MindState.looksLikeOpenAiKey('sk-proj-xxxx'), isTrue);
      expect(MindState.looksLikeOpenAiKey('  sk-abc  '), isTrue);
      // คนวางคีย์ Groq/Claude มาผิดช่องเป็นเรื่องที่เกิดจริง
      expect(MindState.looksLikeOpenAiKey('gsk_abc'), isFalse);
      expect(MindState.looksLikeOpenAiKey(''), isFalse);
    });
  });
}

/// 🔴 รุ่นที่ผู้ใช้เลือก/โหลดไว้ ต้องไม่ถูกสลับทิ้งเอง
///
/// อาการที่เจอบนเครื่องจริง: โหลด E2B ไว้แล้ว เปิดแอปใหม่ → ทักคำแรกได้
/// "ยังไม่ได้โหลดโมเดลลงเครื่อง" ทั้งที่ไฟล์อยู่ครบ
///
/// สาเหตุสองชั้นซ้อนกัน:
/// 1. การตรวจแรมอัตโนมัติสลับไปรุ่นที่ `DeviceVerdict.best` บอก **โดยไม่ดูว่า
///    รุ่นนั้นโหลดไว้หรือยัง** — เครื่องแรม 12 GB ได้ `best = e4bGpu`
///    แต่ปุ่มโหลดตั้งต้นที่ E2B คนจึงโหลด E2B กันเกือบทั้งหมด
/// 2. `_userPicked` ไม่เคยถูกจำข้ามการเปิดปิดแอป → เลือกเองในหน้าตั้งค่า
///    ก็ถูกทับทิ้งในรอบถัดไปอยู่ดี
void _variantGroup() {
  group('🔴 รุ่นโมเดลที่เลือกไว้ต้องไม่ถูกสลับทิ้ง', () {
    test('รุ่นที่แนะนำกับค่าตั้งต้นของปุ่มโหลด ต้องเป็นตัวเดียวกัน', () {
      // ต้นเหตุเดิม: 12 GB ได้ `best = E4B` แต่ปุ่มโหลดตั้งต้นที่ E2B
      // คนจึงโหลด E2B แล้วโดนสลับไป E4B ที่ไม่มีในเครื่องทุกครั้งที่เปิดแอป
      final lb = LocalBrain();
      expect(DeviceCapability.verdictFor(11000).best, lb.variant,
          reason: 'สองค่านี้ไม่ตรงกัน = เปิดแอปแล้วสลับไปรุ่นที่ไม่มีในเครื่อง');
      lb.dispose();
    });

    test('รุ่นที่จำมาจากรอบก่อน ถือว่าผู้ใช้เลือกเอง', () {
      final lb = LocalBrain(initialVariant: GemmaVariant.e2bCpu);
      expect(lb.variant, GemmaVariant.e2bCpu,
          reason: 'ไม่จำ = เปิดแอปใหม่แล้วกลับไปค่าตั้งต้นทุกครั้ง');
      lb.dispose();
    });

    test('เลือกรุ่นแล้วต้องบอกฝั่งที่เก็บค่าให้จำไว้', () async {
      GemmaVariant? saved;
      final lb = LocalBrain(onVariantPicked: (v) => saved = v);
      await lb.selectVariant(GemmaVariant.e4bCpu);

      expect(saved, GemmaVariant.e4bCpu,
          reason: 'ไม่บอก = การเลือกอยู่ได้แค่รอบเดียว');
      lb.dispose();
    });

    test('ชื่อรุ่นที่จำไว้แปลกลับได้ · ชื่อที่ไม่รู้จักคืน null', () {
      expect(GemmaVariant.parse('gemma-4-e4b-cpu'), GemmaVariant.e4bCpu);
      expect(GemmaVariant.parse('gemma-4-e2b-cpu'), GemmaVariant.e2bCpu);
      // ชื่อของรุ่นที่ถอดออกไปแล้วต้องคืน null ไม่ใช่ไปโผล่เป็นรุ่นอื่น
      // คนที่ค้างอยู่ที่ `-gpu` ต้องตกกลับไปที่การเลือกอัตโนมัติ
      for (final r in retiredModels) {
        expect(GemmaVariant.parse(r.name), isNull, reason: r.name);
      }
      // รุ่นถูกถอดออกจากแอปได้ ค่าที่จำไว้จึงชี้ไปที่ที่ไม่มีแล้วได้
      expect(GemmaVariant.parse('รุ่นที่เลิกใช้ไปแล้ว'), isNull);
      expect(GemmaVariant.parse(null), isNull);
    });
  });
}

/// 🔴 ตัวชี้ "รุ่นที่ใช้อยู่" ของปลั๊กอินอยู่ในหน่วยความจำล้วน
///
/// อาการจริงที่เจอบนเครื่อง: โหลดโมเดลเสร็จ คุยได้ปกติ **ปิดแอปเปิดใหม่แล้ว
/// พังถาวร** ด้วย `No active inference model set`
///
/// `_activeInferenceModel` ถูกตั้งให้เองเฉพาะตอน `downloadModel*` เท่านั้น
/// และไม่มีอะไรกู้คืนตอนเปิดแอปรอบหน้า · ขณะที่ `isModelInstalled()` ยังตอบ
/// true (ไฟล์อยู่จริง) สถานะในแอปจึงเป็น `ready` ทุกอย่างดูปกติหมด
///
/// **ทดสอบตอนเพิ่งโหลดเสร็จจะไม่มีวันเจอ** เพราะรอบนั้นตัวชี้ยังอยู่ —
/// นั่นคือเหตุผลที่มันรอดมาถึงมือผู้ใช้ · และเป็นเหตุผลที่เทสต์นี้อ่านซอร์ส
/// แทนที่จะรันจริง (รันจริงต้องมีปลั๊กอิน + ไฟล์โมเดล 2 GB)
void _activeModelGroup() {
  group('🔴 ต้องบอกปลั๊กอินว่าใช้รุ่นไหน ก่อนสร้างโมเดล', () {
    final src = File('lib/ai/local_brain.dart').readAsStringSync();

    test('มีการเรียก setActiveModel อยู่จริง', () {
      expect(src, contains('setActiveModel('),
          reason: 'ไม่เรียก = โหลดเสร็จคุยได้ แต่เปิดแอปใหม่แล้วพังถาวร');
    });

    test('🔴 ต้องเรียก **ก่อน** createModel', () {
      final mark = src.indexOf('_markActive();\n      _model =');
      final create = src.indexOf('FlutterGemmaPlugin.instance.createModel');

      expect(mark, greaterThan(0),
          reason: 'ต้องตั้งรุ่นที่ใช้ติดกันก่อนบรรทัดที่สร้างโมเดล');
      expect(mark, lessThan(create));
    });

    test('ตั้งด้วย spec ของรุ่นที่เลือกอยู่ ไม่ใช่ค่าตายตัว', () {
      expect(src, contains('setActiveModel(_spec(_variant))'),
          reason: 'ตั้งรุ่นตายตัว = สลับรุ่นแล้วยังชี้ไปตัวเก่า');
    });

    test('ตั้งตั้งแต่ตอนสแกนเจอไฟล์ด้วย ไม่ใช่รอจนถึงตอนคุย', () {
      expect(src, contains('if (installed) _markActive();'));
    });
  });
}
