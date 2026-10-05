import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import 'openai_client.dart';
import 'premium_tts.dart';
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
  clone,

  /// Google Gemini TTS — คีย์ AI Studio ของผู้ใช้
  gemini,

  /// ElevenLabs — คีย์ของผู้ใช้
  elevenlabs,

  /// Microsoft Azure AI Speech — คีย์ + ภูมิภาคของผู้ใช้
  azure;

  /// ต้องมีคีย์ OpenAI ไหม
  bool get needsOpenAiKey => this == TtsEngine.openai;

  /// เจ้าเสียงพรีเมียมที่ใช้คีย์ของผู้ใช้เอง (ไม่นับ OpenAI ที่มีช่องคีย์อยู่แล้ว)
  bool get isPremium =>
      this == TtsEngine.gemini || this == TtsEngine.elevenlabs || this == TtsEngine.azure;

  /// ทางที่ **ต่อสายไว้จริง** และเอาไปโชว์ให้ผู้ใช้เลือกได้
  ///
  /// 🔴 `clone` ไม่อยู่ในนี้โดยตั้งใจ · [VoiceCloneService] ไม่เคยถูกสร้าง
  /// ที่ไหนในแอปเลย (`cloneService` ไม่เคยถูก assign) และไม่มีหน้าจอให้อัด
  /// เสียงตัวอย่างหรือตั้งที่อยู่เซิร์ฟเวอร์โคลน · เลือกแล้วจะตกไปเป็นเสียง
  /// เครื่องเงียบ ๆ ทุกครั้ง = ฟีเจอร์ที่ดูเหมือนมีแต่พัง ซึ่งแย่กว่าไม่มี
  ///
  /// **วันที่ต่อสายเสร็จ ให้เอากลับเข้ามาที่นี่ที่เดียว** หน้าตั้งค่าอ่านจากตัวนี้
  static List<TtsEngine> get wired => const [
        TtsEngine.device,
        TtsEngine.openai,
        TtsEngine.gemini,
        TtsEngine.elevenlabs,
        TtsEngine.azure,
      ];
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
    this.premium,
  })  : _s = strings ?? _thai,
        _openai = openai ?? OpenAiClient(strings: strings),
        _injectedTts = deviceTts;

  /// เจ้าเสียงพรีเมียม (Gemini · ElevenLabs · Azure) · null = ไม่ได้ต่อ
  final PremiumTts? premium;

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

      TtsEngine.gemini || TtsEngine.elevenlabs || TtsEngine.azure =>
        await _requirePremium().speak(profile.engine, clean, profile,
            thai: _s().isThai),

      // เสียงโคลนอยู่ฝั่งเซิร์ฟเวอร์ ใช้ voice เป็น id ของเสียงที่โคลนไว้
      TtsEngine.clone => (
          bytes: await _requireClone().speak(clean, voiceId: profile.voice),
          mime: 'audio/mpeg',
        ),
    };
  }

  PremiumTts _requirePremium() {
    final p = premium;
    if (p == null) throw OpenAiFailure(_s().errTtsFailed);
    return p;
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
    // 🔴 ไฟล์ที่มีแต่หัว WAV = เครื่องไม่ได้อ่านอะไรออกมาเลย · ส่วนใหญ่เพราะ
    // ยังไม่มีเสียงของภาษานั้นในเครื่อง (ภาษาไทยต้องโหลดเพิ่มเองบนหลายรุ่น)
    // ของเดิมส่งไฟล์เงียบนี้ไปเล่นต่อ ทุกทางตอบว่าเล่นสำเร็จ แล้วเธอเงียบเฉย ๆ
    final secs = wavSeconds(bytes);
    if (secs != null && secs < minSpeechSeconds) {
      debugPrint('เสียงเครื่อง: ได้เสียงแค่ ${secs.toStringAsFixed(2)} วิ '
          '(${bytes.length} ไบต์) ภาษา $_deviceLang');
      throw OpenAiFailure(await _languageReady()
          ? _s().errTtsEmpty
          : _s().errTtsNoVoice);
    }
    return (bytes: bytes, mime: 'audio/wav');
  }

  /// ไฟล์สั้นกว่านี้นับว่าไม่มีเสียงพูด · คำเดียวที่สั้นที่สุดยังยาวกว่านี้
  static const minSpeechSeconds = 0.15;

  /// ความยาวเสียงในไฟล์ WAV (วินาที) · null = อ่านหัวไฟล์ไม่ออก (ไม่ตัดสิน)
  ///
  /// เดินทีละ chunk ไม่ใช่อ่านตำแหน่งตายตัว — บางเครื่องแทรก chunk `LIST`
  /// ก่อน `data` · และบางเครื่องเขียนขนาด data เป็น 0/0xFFFFFFFF ตอนเขียน
  /// แบบสตรีม จึงใช้ขนาดที่เหลือจริงของไฟล์แทนเมื่อค่านั้นเชื่อไม่ได้
  @visibleForTesting
  static double? wavSeconds(Uint8List b) {
    if (b.length < 12) return null;
    String tag(int at) => String.fromCharCodes(b.sublist(at, at + 4));
    if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
    final view = ByteData.sublistView(b);
    int? byteRate;
    var at = 12;
    while (at + 8 <= b.length) {
      final id = tag(at);
      final size = view.getUint32(at + 4, Endian.little);
      final body = at + 8;
      if (id == 'fmt ' && body + 12 <= b.length) {
        byteRate = view.getUint32(body + 8, Endian.little);
      } else if (id == 'data') {
        if (byteRate == null || byteRate == 0) return null;
        final left = b.length - body;
        final n = (size == 0 || size > left) ? left : size;
        return n / byteRate;
      }
      at = body + size + (size.isOdd ? 1 : 0);
    }
    return null;
  }

  /// เครื่องมีเสียงของภาษาที่ใช้อยู่ไหม · ถามไม่ได้ = ถือว่ามี (ไม่กล่าวหาเครื่อง)
  Future<bool> _languageReady() async {
    try {
      final ok = await _tts.isLanguageAvailable(_deviceLang ?? 'th-TH');
      return ok != false;
    } on Object {
      return true;
    }
  }

  /// ภาษาที่ตั้งให้เสียงเครื่องไว้ล่าสุด
  String? _deviceLang;

  Future<void> _prepareDevice() async {
    // 🔴 ตั้งภาษาตามภาษาของแอป **ทุกครั้งที่มันเปลี่ยน** ไม่ใช่ครั้งเดียว
    //
    // ของเดิมตั้ง th-TH ตายตัวครั้งเดียวตอนเริ่ม · คนที่ใช้แอปภาษาอังกฤษ
    // (และคู่สายที่เธอคุยด้วยเป็นภาษาอังกฤษ) ได้ข้อความอังกฤษที่อ่านด้วย
    // เสียงไทยทุกประโยค และสลับภาษาในแอปแล้วก็ไม่เปลี่ยนตาม
    final lang = _s().isThai ? 'th-TH' : 'en-US';
    if (_deviceLang != lang) {
      await _tts.setLanguage(lang);
      _deviceLang = lang;
    }
    if (_deviceReady) return;
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
