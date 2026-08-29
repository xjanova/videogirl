import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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
  })  : _http = httpClient ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 30),
        _baseUrl = baseUrl ?? OpenAiConfig.baseUrl,
        _apiKey = apiKey ?? OpenAiConfig.apiKey;

  final http.Client _http;
  final Duration _timeout;

  /// เปลี่ยนปลายทางได้ เพื่อชี้ไปเซิร์ฟเวอร์ในบ้าน (Ollama, llama.cpp, LM Studio)
  /// ที่พูดภาษาเดียวกับ /v1/chat/completions ของ OpenAI
  final String _baseUrl;

  /// เซิร์ฟเวอร์ในบ้านส่วนใหญ่ไม่ต้องใช้คีย์ ปล่อยว่างได้
  final String _apiKey;

  Map<String, String> get _headers => {
        if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json; charset=utf-8',
      };

  /// ใช้คีย์อยู่ไหม — เซิร์ฟเวอร์ในบ้านไม่ต้องมีคีย์ก็เรียกได้
  bool get usable => _apiKey.isNotEmpty || _baseUrl != OpenAiConfig.baseUrl;

  /// ให้เธอคิดคำตอบ
  ///
  /// [history] เรียงเก่า→ใหม่ ตัวสุดท้ายคือสิ่งที่ผู้ใช้เพิ่งพิมพ์
  Future<String> reply({
    required String system,
    required List<Turn> history,
    String? model,
  }) async {
    if (!usable) {
      throw const OpenAiFailure('ยังไม่ได้ใส่คีย์ OpenAI ตอน build');
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
      throw const OpenAiFailure('โมเดลไม่ได้ตอบอะไรกลับมา');
    }

    final content = (choices.first as Map)['message']?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw const OpenAiFailure('โมเดลตอบกลับมาว่าง');
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
      throw const OpenAiFailure('ยังไม่ได้ใส่คีย์ OpenAI ตอน build');
    }

    final clean = stripForSpeech(text);
    if (clean.isEmpty) throw const OpenAiFailure('ไม่มีข้อความให้พูด');

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

  Future<Uint8List> _post(String path, String body) async {
    final http.Response res;
    try {
      res = await _http
          .post(Uri.parse('$_baseUrl$path'),
              headers: _headers, body: utf8.encode(body))
          .timeout(_timeout);
    } on Exception {
      // ไม่ส่ง exception ดิบขึ้นไป มันมี URL และบางทีมี header ติดไปด้วย
      throw const OpenAiFailure('ต่อเน็ตไม่ได้ ลองใหม่อีกครั้งนะคะ');
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
        return 'คีย์ OpenAI ใช้ไม่ได้แล้ว';
      case 429:
        return 'เรียกถี่เกินไป รอสักครู่นะคะ';
      case >= 500:
        return 'ฝั่ง OpenAI ขัดข้อง ลองใหม่อีกครั้งนะคะ';
    }
    try {
      final m = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final msg = m['error']?['message'] as String?;
      if (msg != null && msg.isNotEmpty) return msg;
    } on Exception {
      // ตอบกลับไม่ใช่ JSON — ตกไปใช้ข้อความกลางด้านล่าง
    }
    return 'เรียก OpenAI ไม่สำเร็จ (${res.statusCode})';
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
