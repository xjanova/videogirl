import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import 'openai_client.dart';
import 'openai_config.dart';

/// เครื่องสังเคราะห์เสียงที่ให้เลือกได้
enum TtsEngine {
  /// OpenAI gpt-4o-mini-tts — สมจริงที่สุด สั่งโทนเสียงได้ แต่เสียเงินต่อครั้ง
  openai('OpenAI', 'สมจริงที่สุด สั่งอารมณ์เสียงได้ · มีค่าใช้จ่าย'),

  /// เครื่องเสียงของ Android เอง — ฟรี ใช้ได้แม้ไม่มีเน็ต แต่เสียงหุ่นยนต์กว่า
  device('เครื่อง Android', 'ฟรี ใช้ออฟไลน์ได้ · เสียงหุ่นยนต์กว่า');

  const TtsEngine(this.label, this.hint);
  final String label, hint;
}

/// เสียงหนึ่งชุดที่พร้อมส่งเข้าปากเธอ
typedef Utterance = ({Uint8List bytes, String mime});

/// รวมทางสังเคราะห์เสียงทั้งสองไว้หลังหน้าตาเดียวกัน
///
/// ทั้งสองทาง**คืนไบต์** ไม่ใช่เล่นเสียงเอง เพราะเสียงต้องไปเล่นใน WebView
/// ให้ lipsync.js อ่านคลื่นได้ ถ้าปล่อยให้ flutter_tts เล่นผ่านระบบเสียง Android
/// เสียงจะดังแต่ปากจะนิ่งสนิท เพราะ analyser ไม่เห็นสัญญาณนั้นเลย
class SpeechService {
  SpeechService({OpenAiClient? openai, FlutterTts? deviceTts})
      : _openai = openai ?? OpenAiClient(),
        _injectedTts = deviceTts;

  final OpenAiClient _openai;
  final FlutterTts? _injectedTts;

  /// สร้างตอนใช้จริงเท่านั้น
  ///
  /// FlutterTts ผูก MethodChannel ตั้งแต่ constructor ถ้าสร้างทันทีที่แอปเริ่ม
  /// จะพังใน unit test ที่ยังไม่มี binding และคนที่พิมพ์คุยอย่างเดียว
  /// ก็ไม่ต้องปลุกเครื่องเสียงของระบบขึ้นมาเปล่า ๆ
  FlutterTts? _lazyTts;
  FlutterTts get _tts => _lazyTts ??= _injectedTts ?? FlutterTts();

  bool _deviceReady = false;
  int _seq = 0;

  Future<Utterance> synthesize(
    String text, {
    required TtsEngine engine,
    required String voice,
    required String instructions,
    String? model,
  }) async {
    final clean = OpenAiClient.stripForSpeech(text);
    if (clean.isEmpty) throw const OpenAiFailure('ไม่มีข้อความให้พูด');

    return switch (engine) {
      TtsEngine.openai => (
          bytes: await _openai.speak(clean,
              voice: voice, instructions: instructions, model: model),
          mime: 'audio/mpeg',
        ),
      TtsEngine.device => await _synthesizeOnDevice(clean),
    };
  }

  /// เครื่องไหนไม่มีเสียงไทยติดมา ให้รู้ตั้งแต่ตอนเลือกในหน้าตั้งค่า
  /// ไม่ใช่ตอนกดคุยแล้วเงียบ
  Future<bool> deviceSupportsThai() async {
    try {
      final ok = await _tts.isLanguageAvailable('th-TH');
      return ok == true;
    } on Exception {
      return false;
    }
  }

  Future<Utterance> _synthesizeOnDevice(String text) async {
    await _prepareDevice();

    final dir = await getTemporaryDirectory();
    // ชื่อไม่ซ้ำกันทุกครั้ง — ถ้าใช้ชื่อเดิม บางเครื่องคืนไฟล์เก่าที่แคชไว้
    final path = '${dir.path}${Platform.pathSeparator}minde_${_seq++}.wav';

    final result = await _tts.synthesizeToFile(text, path, true);
    if (result != 1) {
      throw const OpenAiFailure('เครื่องนี้สังเคราะห์เสียงไม่สำเร็จ');
    }

    final file = File(path);
    if (!await file.exists()) {
      throw const OpenAiFailure('เครื่องนี้ไม่รองรับการบันทึกเสียงเป็นไฟล์');
    }

    final bytes = await file.readAsBytes();
    // ลบทิ้งทันที ไม่งั้นคุยทั้งวันจะเหลือ wav ค้างเต็ม temp
    unawaited(file.delete().catchError((_) => file));

    if (bytes.isEmpty) {
      throw const OpenAiFailure('ไฟล์เสียงที่ได้ว่างเปล่า');
    }
    return (bytes: bytes, mime: 'audio/wav');
  }

  Future<void> _prepareDevice() async {
    if (_deviceReady) return;
    await _tts.setLanguage('th-TH');
    await _tts.setSpeechRate(.48); // ค่าเริ่มต้นของ Android เร็วเกินจนฟังไม่ทัน
    await _tts.setPitch(1.08); // ยกขึ้นนิดเดียว ให้เสียงอ่อนลงโดยไม่เพี้ยน
    // ต้องรอให้เขียนไฟล์เสร็จก่อน synthesizeToFile ถึงจะคืนค่าจริง
    await _tts.awaitSynthCompletion(true);
    _deviceReady = true;
  }

  void dispose() {
    _openai.close();
    // อย่าแตะ getter ตรงนี้ ไม่งั้นการปิดแอปจะไปสร้าง FlutterTts ขึ้นมาใหม่
    _lazyTts?.stop();
  }
}

/// ค่าเริ่มต้นของเสียง เก็บไว้ที่เดียวกับตัวเลือกโมเดล
abstract final class VoiceDefaults {
  static const engine = TtsEngine.openai;
  static const openAiVoice = 'coral';
  static String get openAiModel => OpenAiConfig.ttsModel;
}
