import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import 'openai_config.dart';

/// ข้อผิดพลาดที่เอาไปโชว์ผู้ใช้ได้เลย — ไม่มี stack trace ไม่มีคำว่า Exception
/// และไม่มีคีย์หลุดออกมา
class OpenAiFailure implements Exception {
  const OpenAiFailure(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// ข้อความหนึ่งเทิร์นสำหรับส่งเข้าโมเดล
typedef Turn = ({bool fromHer, String text});

class OpenAiClient {
  OpenAiClient({
    http.Client? httpClient,
    Duration? timeout,
    String? baseUrl,
    String? apiKey,
    String Function()? apiKeyOf,
    String Function()? baseUrlOf,
    S Function()? strings,
  })  : _s = strings ?? _thai,
        _http = httpClient ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 30),
        _baseUrlOf = baseUrlOf ?? (() => baseUrl ?? OpenAiConfig.baseUrl),
        _apiKeyOf = apiKeyOf ?? (() => apiKey ?? OpenAiConfig.apiKey);

  /// อ่านภาษา ณ ตอนที่ error เกิดจริง ไม่ใช่ตอนสร้าง client
  /// เพราะผู้ใช้สลับภาษาได้ระหว่างแอปเปิดอยู่
  final S Function() _s;
  static S _thai() => const S(AppLang.th);

  final http.Client _http;
  final Duration _timeout;

  /// 🔴 อ่านค่าตอนใช้จริง ไม่ใช่ตอนสร้าง client — เหตุผลเดียวกับ [_s]
  ///
  /// ผู้ใช้กรอกคีย์เอง แก้คีย์ หรือสลับไปพร็อกซีหลังบ้านได้ทุกเมื่อขณะแอปเปิดอยู่
  /// ถ้าอ่านค่าตอนสร้าง client จะต้องสร้างใหม่ทุกครั้งที่มีการแก้ ซึ่งเป็นเรื่อง
  /// ที่ลืมได้ง่ายและจะเงียบ — คนใช้กรอกคีย์แล้วยังโดนบอกว่ายังไม่ได้ตั้งคีย์
  ///
  /// เปลี่ยนปลายทางได้เพื่อชี้ไปเซิร์ฟเวอร์ในบ้าน (Ollama, llama.cpp, LM Studio)
  /// หรือพร็อกซีของเรา ที่พูดภาษาเดียวกับ /v1/chat/completions ของ OpenAI
  final String Function() _baseUrlOf;

  /// เซิร์ฟเวอร์ในบ้านส่วนใหญ่ไม่ต้องใช้คีย์ ปล่อยว่างได้
  final String Function() _apiKeyOf;

  String get _baseUrl => _baseUrlOf();

  Map<String, String> get _headers {
    final key = _apiKeyOf();
    return {
      if (key.isNotEmpty) 'Authorization': 'Bearer $key',
      'Content-Type': 'application/json; charset=utf-8',
    };
  }

  /// ใช้คีย์อยู่ไหม — เซิร์ฟเวอร์ในบ้านไม่ต้องมีคีย์ก็เรียกได้
  bool get usable =>
      _apiKeyOf().isNotEmpty || _baseUrl != OpenAiConfig.baseUrl;

  /// ให้เธอคิดคำตอบ
  ///
  /// [history] เรียงเก่า→ใหม่ ตัวสุดท้ายคือสิ่งที่ผู้ใช้เพิ่งพิมพ์
  Future<String> reply({
    required String system,
    required List<Turn> history,
    String? model,
  }) async {
    if (!usable) {
      throw OpenAiFailure(_s().errNoKey);
    }

    final body = jsonEncode({
      'model': model ?? OpenAiConfig.brainModel,
      'messages': [
        {'role': 'system', 'content': system},
        for (final t in history)
          {'role': t.fromHer ? 'assistant' : 'user', 'content': t.text},
      ],
      'max_completion_tokens': 600,
    });

    final res = await _post('/chat/completions', body);
    final json = jsonDecode(utf8.decode(res)) as Map<String, dynamic>;
    final choices = json['choices'] as List?;

    if (choices == null || choices.isEmpty) {
      throw OpenAiFailure(_s().errNoReply);
    }

    final content = (choices.first as Map)['message']?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw OpenAiFailure(_s().errEmptyReply);
    }
    return content.trim();
  }

  /// แปลงข้อความเป็นเสียงพูด คืน mp3 เป็นไบต์
  ///
  /// ตัดอิโมจิออกก่อนเสมอ ไม่งั้น TTS จะอ่านชื่ออิโมจิออกมาดัง ๆ
  Future<Uint8List> speak(
    String text, {
    required String voice,
    required String instructions,
    String? model,
  }) async {
    if (!usable) {
      throw OpenAiFailure(_s().errNoKey);
    }

    final clean = stripForSpeech(text);
    if (clean.isEmpty) throw OpenAiFailure(_s().errNothingToSay);

    final ttsModel = model ?? OpenAiConfig.ttsModel;

    final body = jsonEncode({
      'model': ttsModel,
      'voice': voice,
      'input': clean,
      // ตระกูล tts-1 ไม่รู้จักพารามิเตอร์นี้ ส่งไปจะได้ 400 กลับมา
      // จึงใส่เฉพาะโมเดลที่รับจริง
      if (OpenAiConfig.supportsInstructions(ttsModel) && instructions.isNotEmpty)
        'instructions': instructions,
      'response_format': 'mp3',
    });

    return _post('/audio/speech', body);
  }

  /// ถอดเสียงเป็นข้อความ · คืนสตริงว่างเมื่อไม่มีเสียงพูดอยู่ในไฟล์
  ///
  /// 🔴 **ตัวว่างไม่ใช่ความผิดพลาด** ปลายสายเงียบไปสามวินาทีก็ได้ตัวว่าง
  /// เหมือนกับตอนที่เครื่องไม่ยอมให้อัดเสียงระหว่างมีสาย · ผู้เรียกต้องแยก
  /// สองกรณีนี้เอง (ดูระดับเสียงที่วัดได้ ไม่ใช่ดูข้อความที่ถอดได้)
  ///
  /// ส่งเป็น multipart ไม่ใช่ JSON — endpoint นี้รับไฟล์ ไม่ใช่ base64
  /// และ `response_format: text` ทำให้ได้ข้อความเปล่า ๆ ไม่ต้องแกะ JSON
  Future<String> transcribe(
    Uint8List wav, {
    String? model,
    String? language,
  }) async {
    if (!usable) throw OpenAiFailure(_s().errNoKey);
    if (wav.isEmpty) return '';

    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/audio/transcriptions'),
    )
      // ใช้ _headers ไม่ได้เพราะ multipart ต้องให้ http ตั้ง Content-Type เอง
      // (มี boundary ต่อท้าย) แต่ต้องอ่านคีย์ตอนนี้เหมือนกัน
      ..headers.addAll({
        for (final e in _headers.entries)
          if (e.key != 'Content-Type') e.key: e.value,
      })
      ..fields['model'] = model ?? OpenAiConfig.sttModel
      ..fields['response_format'] = 'text'
      ..files.add(http.MultipartFile.fromBytes('file', wav, filename: 'call.wav'));

    // บอกภาษาไปเลยดีกว่าให้เดา · เสียงจากสายโทรศัพท์ถูกบีบจนโมเดลเดาภาษา
    // ผิดได้บ่อย แล้วผลที่ได้คือคำไทยถูกถอดเป็นอังกฤษที่อ่านไม่ออก
    if (language != null && language.isNotEmpty) req.fields['language'] = language;

    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _http.send(req).timeout(_timeout),
      );
    } on Exception {
      throw OpenAiFailure(_s().errOffline);
    }

    if (res.statusCode >= 400) {
      throw OpenAiFailure(_readableError(res), status: res.statusCode);
    }
    return utf8.decode(res.bodyBytes).trim();
  }

  Future<Uint8List> _post(String path, String body) async {
    final http.Response res;
    try {
      res = await _http
          .post(Uri.parse('$_baseUrl$path'),
              headers: _headers, body: utf8.encode(body))
          .timeout(_timeout);
    } on Exception {
      // ไม่ส่ง exception ดิบขึ้นไป มันมี URL และบางทีมี header ติดไปด้วย
      throw OpenAiFailure(_s().errOffline);
    }

    if (res.statusCode >= 400) {
      throw OpenAiFailure(_readableError(res), status: res.statusCode);
    }
    return res.bodyBytes;
  }

  /// แปลง error ของ OpenAI เป็นภาษาคน — และไม่เผยรายละเอียดระบบให้ผู้ใช้เห็น
  String _readableError(http.Response res) {
    switch (res.statusCode) {
      case 401:
        return _s().errBadKey;
      case 429:
        return _s().errRateLimited;
      case >= 500:
        return _s().errUpstream;
    }
    try {
      final m = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final msg = m['error']?['message'] as String?;
      if (msg != null && msg.isNotEmpty) return msg;
    } on Exception {
      // ตอบกลับไม่ใช่ JSON — ตกไปใช้ข้อความกลางด้านล่าง
    }
    return _s().errRequestFailed(res.statusCode);
  }

  void close() => _http.close();

  /// ตัดอิโมจิ มาร์กดาวน์ และช่องว่างซ้ำ ก่อนส่งให้ TTS อ่าน
  ///
  /// system prompt สั่งห้ามใส่อิโมจิอยู่แล้ว แต่โมเดลก็ยังใส่มาบ้าง
  /// (เห็นกับตาตอนทดสอบ gpt-5.6-sol) จึงต้องกันอีกชั้นตรงนี้
  static String stripForSpeech(String input) {
    final noEmoji = input.replaceAll(
      RegExp(
        r'[\u{1F000}-\u{1FAFF}\u{2190}-\u{2BFF}\u{FE00}-\u{FE0F}\u{200D}]',
        unicode: true,
      ),
      '',
    );
    return noEmoji
        .replaceAll(RegExp(r'[*_`#>]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
