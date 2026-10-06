import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import 'openai_config.dart';

/// ข้อผิดพลาดที่เอาไปโชว์ผู้ใช้ได้เลย — ไม่มี stack trace ไม่มีคำว่า Exception
/// และไม่มีคีย์หลุดออกมา
class OpenAiFailure implements Exception {
  const OpenAiFailure(this.message, {this.status, this.code});

  final String message;
  final int? status;

  /// รหัสเหตุผลจากพร็อกซีของเรา (`insufficient_credit` · `not_linked` ·
  /// `daily_cap` · `wallet_inactive`) · หน้าจอใช้เลือกปุ่มที่ต้องโชว์ (เติมเงิน/ผูกบัญชี)
  final String? code;

  @override
  String toString() => message;
}

/// ข้อความหนึ่งเทิร์นสำหรับส่งเข้าโมเดล
typedef Turn = ({bool fromHer, String text});

/// ปลายทางที่ client นี้คุยด้วย · ใช้เลือกข้อความผิดพลาดให้ตรงกับที่ผู้ใช้เลือก
enum Upstream { openai, proxy, homeServer }

class OpenAiClient {
  OpenAiClient({
    http.Client? httpClient,
    Duration? timeout,
    String? baseUrl,
    String? apiKey,
    String Function()? apiKeyOf,
    String Function()? baseUrlOf,
    S Function()? strings,
    this.upstream = Upstream.openai,
  })  : _s = strings ?? _thai,
        _http = httpClient ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 30),
        _baseUrlOf = baseUrlOf ?? (() => baseUrl ?? OpenAiConfig.baseUrl),
        _apiKeyOf = apiKeyOf ?? (() => apiKey ?? OpenAiConfig.apiKey);

  final Upstream upstream;

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

    final m = model ?? OpenAiConfig.brainModel;
    // ส่งระดับการคิดเฉพาะตอนคุยกับ OpenAI ตรง ๆ · พร็อกซีของเราเลือกรุ่นเอง
    // ฝั่งเซิร์ฟเวอร์ และเซิร์ฟเวอร์ในบ้าน (Ollama ฯลฯ) ไม่รู้จักฟิลด์นี้
    final effort =
        _baseUrl == OpenAiConfig.baseUrl ? OpenAiConfig.effortFor(m) : null;
    final body = jsonEncode({
      'model': m,
      'messages': [
        {'role': 'system', 'content': system},
        for (final t in history)
          {'role': t.fromHer ? 'assistant' : 'user', 'content': t.text},
      ],
      'reasoning_effort': ?effort,
      // เพดานนับรวมการคิดภายในด้วย · คิดได้ (low/minimal หรือไม่รู้ว่ารุ่นนี้
      // คิดไหม) = เผื่อที่ให้ยังเหลือพอสำหรับคำตอบ · ไม่คิด = 600 พอสำหรับเธอ
      'max_completion_tokens': effort == 'none' ? 600 : 2000,
    });

    final res = await _post('/chat/completions', body);
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(res));
    } on FormatException {
      // พร็อกซี/เซิร์ฟเวอร์ในบ้านตอบหน้า HTML มาแทน JSON
      throw OpenAiFailure(_s().errNoReply);
    }
    final choices = json is Map ? json['choices'] : null;

    if (choices is! List || choices.isEmpty) {
      throw OpenAiFailure(_s().errNoReply);
    }

    final first = choices.first;
    final message = first is Map ? first['message'] : null;
    final content = message is Map ? message['content'] as Object? : null;
    if (content is! String || content.trim().isEmpty) {
      throw OpenAiFailure(_s().errEmptyReply);
    }
    // พร็อกซีของเราแนบว่าข้อความนี้หักไปเท่าไหร่ เหลือเท่าไหร่ · หลอดเครดิต
    // ขยับได้ทันทีโดยไม่ต้องถามซ้ำ (ดู ProxyAccount)
    final billing = json is Map ? json['giggok_billing'] : null;
    lastBilling = billing is Map ? billing.cast<String, Object?>() : null;
    return content.trim();
  }

  /// ค่าใช้จ่ายของคำตอบล่าสุดจากพร็อกซีของเรา · null = ไม่ได้ผ่านพร็อกซี
  Map<String, Object?>? lastBilling;

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
      // เซิร์ฟเวอร์ในบ้านส่วนใหญ่ (Ollama) ไม่มีปลายทางถอดเสียงเลย = 404
      if (upstream == Upstream.homeServer &&
          (res.statusCode == 404 || res.statusCode == 405)) {
        throw OpenAiFailure(_s().errHomeNoStt, status: res.statusCode);
      }
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
      final code = upstream == Upstream.proxy ? proxyCode(res.bodyBytes) : null;
      throw OpenAiFailure(_readableError(res), status: res.statusCode, code: code);
    }
    return res.bodyBytes;
  }

  /// รหัสเหตุผลที่พร็อกซีของเราแนบมากับ error (`error.code`) · null = ไม่มี
  @visibleForTesting
  static String? proxyCode(List<int> body) {
    try {
      final m = jsonDecode(utf8.decode(body));
      final err = m is Map ? m['error'] : null;
      final c = err is Map ? err['code'] : null;
      return c is String && c.isNotEmpty ? c : null;
    } on Object {
      return null;
    }
  }

  /// แปลง error ของ OpenAI เป็นภาษาคน — และไม่เผยรายละเอียดระบบให้ผู้ใช้เห็น
  String _readableError(http.Response res) {
    final s = _s();
    // 🔴 เรื่องเงินของพร็อกซีต้องมาก่อนกฎตามรหัสสถานะ · ไม่งั้น "ยังไม่ได้ผูกบัญชี"
    // (403) กลายเป็น "รหัสสิทธิ์ใช้ไม่ได้" และ "ถึงเพดานวันนี้" (429) กลายเป็น
    // "ส่งถี่เกินไป" ซึ่งบอกให้ไปทำคนละอย่างกับที่ต้องทำจริง
    if (upstream == Upstream.proxy) {
      switch (proxyCode(res.bodyBytes)) {
        case 'insufficient_credit':
          return s.errProxyNoCredit;
        case 'not_linked':
          return s.errProxyNotLinked;
        case 'daily_cap':
          return s.errProxyDailyCap;
        case 'wallet_inactive':
          return s.errProxyWalletInactive;
      }
    }
    switch ((upstream, res.statusCode)) {
      case (Upstream.openai, 401):
        return s.errBadKey;
      case (Upstream.proxy, 401 || 403):
        return s.errLicenseRejected;
      case (_, 429):
        return s.errRateLimited;
      case (Upstream.openai, >= 500):
        return s.errUpstream;
      case (Upstream.proxy, >= 500):
        return s.errProxyDown;
      case (Upstream.homeServer, >= 500):
        return s.errHomeDown;
    }
    try {
      final m = jsonDecode(utf8.decode(res.bodyBytes));
      // 🔴 อ่านแบบเช็กชนิดทุกชั้น · เซิร์ฟเวอร์ในบ้าน (LM Studio, Ollama บางรุ่น)
      // ตอบ `{"error": "ข้อความ"}` เป็นสตริงตรง ๆ ไม่ใช่ `{"error": {"message"}}`
      // ของเดิม `m['error']?['message']` จึงโยน TypeError ซึ่งไม่ใช่ Exception
      // ลอดตัวดักข้างล่างออกไป แล้วผู้ใช้ได้ "ส่งใหม่อีกที" แทนเหตุผลจริง
      final err = m is Map ? m['error'] : null;
      final msg = switch (err) {
        String s => s,
        Map e when e['message'] is String => e['message'] as String,
        _ => null,
      };
      if (msg != null && msg.trim().isNotEmpty) return msg.trim();
    } on Object {
      // ตอบกลับไม่ใช่ JSON — ตกไปใช้ข้อความกลางด้านล่าง
    }
    return switch (upstream) {
      Upstream.openai => s.errRequestFailed(res.statusCode),
      Upstream.proxy => s.errProxyFailed(res.statusCode),
      Upstream.homeServer => s.errHomeFailed(res.statusCode),
    };
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
