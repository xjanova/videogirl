/// ตัวถอดเสียง — แปลงเสียงพูดของเจ้าของ (ไมค์ในแชท · คู่สายตอนรับสาย) เป็นข้อความ
///
/// แยกจากสมองได้ เพราะสมองบางเจ้าไม่มี API ฟังเสียงเลย (Claude) และบางคน
/// อยากให้เสียงอยู่ในเครื่องแม้สมองอยู่บนคลาวด์
///
/// [auto] = ตามสมองที่เลือก (พฤติกรรมเดิม) · สมองที่ไม่มีหูของตัวเอง
/// (Claude · Gemini) ถอดในเครื่องแทน — ไม่แอบส่งเสียงไปเจ้าที่สามที่ผู้ใช้ไม่ได้เลือก
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import '../i18n/strings_brains.dart';
import '../i18n/strings_voice.dart';
import 'openai_client.dart';

enum SttEngine {
  auto,

  /// ตัวถอดเสียงของ Android · ไม่ออกนอกเครื่อง ไม่มีค่าใช้จ่าย
  device,

  /// gpt-transcribe ของ OpenAI · คีย์ OpenAI
  openai,

  /// Scribe v2 ของ ElevenLabs · คีย์ ElevenLabs · \$0.22 / ชั่วโมง
  elevenlabs,

  /// grok-voice-transcribe-2.0 ของ xAI · คีย์ xAI · รองรับไทย
  grok;

  /// ราคาต่อชั่วโมงเสียง (USD) ตามหน้าราคาทางการ 2026-11-02 · null = ไม่แสดง
  double? get usdPerHour => switch (this) {
        SttEngine.elevenlabs => 0.22,
        SttEngine.device => 0,
        _ => null,
      };
}

/// ถอดเสียงด้วย Grok · POST https://api.x.ai/v1/stt (multipart)
abstract final class GrokStt {
  static const url = 'https://api.x.ai/v1/stt';
  static const model = 'grok-voice-transcribe-2.0';

  static Future<String> transcribe(
    Uint8List wav, {
    required String key,
    required bool thai,
    required S strings,
    http.Client? client,
  }) async {
    if (key.isEmpty) throw OpenAiFailure(strings.brainKeyNeeded('Grok'));
    final c = client ?? http.Client();
    try {
      final req = http.MultipartRequest('POST', Uri.parse(url))
        ..headers['Authorization'] = 'Bearer $key'
        ..fields['model'] = model
        ..fields['language'] = thai ? 'th' : 'en'
        ..files.add(http.MultipartFile.fromBytes('file', wav, filename: 'speech.wav'));
      final http.StreamedResponse res;
      try {
        res = await c.send(req).timeout(const Duration(seconds: 40));
      } on Object catch (e) {
        debugPrint('Grok STT: ส่งไม่ถึง — ${e.runtimeType}');
        throw OpenAiFailure(strings.errOffline, offline: true);
      }
      final body = await res.stream.toBytes();
      if (res.statusCode != 200) {
        debugPrint('Grok STT: ตอบ ${res.statusCode}');
        throw OpenAiFailure(switch (res.statusCode) {
          401 || 403 => strings.premiumBadKey('Grok'),
          402 || 429 => strings.premiumQuota('Grok'),
          _ => strings.premiumFailed('Grok'),
        }, status: res.statusCode);
      }
      final j = jsonDecode(utf8.decode(body));
      return (j is Map && j['text'] is String ? j['text'] as String : '').trim();
    } finally {
      if (client == null) c.close();
    }
  }
}
