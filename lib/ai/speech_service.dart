import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import 'openai_client.dart';
import 'voice_clone.dart';
import 'voice_profile.dart';

/// เครื่องสังเคราะห์เสียงที่ให้เลือกได้
/// ป้ายที่ผู้ใช้เห็นอยู่ใน i18n/enum_labels.dart — enum เก็บแค่ตัวตน
///
/// `clone` เสิร์ฟจากเซิร์ฟเวอร์โคลนเสียง ซึ่งยุคนี้ (F5-TTS, GPT-SoVITS,
/// openedai-speech, Kokoro-FastAPI ฯลฯ) ส่วนใหญ่เปิด endpoint เลียนแบบ
/// OpenAI ที่ `/v1/audio/speech` จึงใช้ client ตัวเดิมได้ เปลี่ยนแค่ปลายทาง
enum TtsEngine {
  openai,
  device,
  clone;

  /// ต้องมีคีย์ OpenAI ไหม
  bool get needsOpenAiKey => this == TtsEngine.openai;
}

/// เสียงหนึ่งชุดที่พร้อมส่งเข้าปากเธอ
typedef Utterance = ({Uint8List bytes, String mime});

/// รวมทางสังเคราะห์เสียงทั้งสองไว้หลังหน้าตาเดียวกัน
///
/// ทั้งสองทาง**คืนไบต์** ไม่ใช่เล่นเสียงเอง เพราะเสียงต้องไปเล่นใน WebView
/// ให้ lipsync.js อ่านคลื่นได้ ถ้าปล่อยให้ flutter_tts เล่นผ่านระบบเสียง Android
/// เสียงจะดังแต่ปากจะนิ่งสนิท เพราะ analyser ไม่เห็นสัญญาณนั้นเลย
class SpeechService {
  SpeechService({
    OpenAiClient? openai,
    FlutterTts? deviceTts,
    S Function()? strings,
  })  : _s = strings ?? _thai,
        _openai = openai ?? OpenAiClient(strings: strings),
        _injectedTts = deviceTts;

  final S Function() _s;
  static S _thai() => const S(AppLang.th);

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

  /// สังเคราะห์เสียงตามโปรไฟล์ของช่องทางนั้น ๆ
  Future<Utterance> synthesize(String text, {required VoiceProfile profile}) async {
    final clean = OpenAiClient.stripForSpeech(text);
    if (clean.isEmpty) throw OpenAiFailure(_s().errNothingToSay);

    return switch (profile.engine) {
      TtsEngine.openai => (
          bytes: await _openai.speak(
            clean,
            voice: profile.voice,
            instructions: profile.instructions,
            model: profile.model,
          ),
          mime: 'audio/mpeg',
        ),
      TtsEngine.device => await _synthesizeOnDevice(clean),

      // เสียงโคลนอยู่ฝั่งเซิร์ฟเวอร์ ใช้ voice เป็น id ของเสียงที่โคลนไว้
      TtsEngine.clone => (
          bytes: await _requireClone().speak(clean, voiceId: profile.voice),
          mime: 'audio/mpeg',
        ),
    };
  }

  /// บริการโคลนเสียง — ฉีดเข้ามาจาก state เมื่อผู้ใช้ตั้งค่าเซิร์ฟเวอร์แล้ว
  VoiceCloneService? cloneService;

  VoiceCloneService _requireClone() {
    final c = cloneService;
    if (c == null || !c.configured) {
      throw OpenAiFailure(_s().errCloneNotSet);
    }
    return c;
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
      throw OpenAiFailure(_s().errTtsFailed);
    }

    final file = File(path);
    if (!await file.exists()) {
      throw OpenAiFailure(_s().errTtsNoFile);
    }

    final bytes = await file.readAsBytes();
    // ลบทิ้งทันที ไม่งั้นคุยทั้งวันจะเหลือ wav ค้างเต็ม temp
    unawaited(file.delete().catchError((_) => file));

    if (bytes.isEmpty) {
      throw OpenAiFailure(_s().errTtsEmpty);
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
