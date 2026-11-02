import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import '../i18n/strings_voice.dart';
import 'eleven_tuning.dart';
import 'openai_client.dart';
import 'premium_catalog.dart';
import 'speech_service.dart';
import 'voice_profile.dart';

/// เสียงพรีเมียมจากเจ้าอื่น — Google Gemini · ElevenLabs · Microsoft Azure
///
/// ทุกเจ้าใช้**คีย์ของผู้ใช้เอง** (เก็บใน SecretStore) แล้วคืนไบต์เสียงแบบเดียว
/// กับ OpenAI เพื่อให้เข้าท่อเดิม (เวที → ปากขยับ / ทางสำรอง) ได้ทันที
///
/// สเปกตรวจกับเอกสารทางการ 2026-10-06 · รายละเอียดและสิ่งที่ยังยืนยันไม่ได้
/// อยู่ใน docs/premium-voices.md
///
/// ข้อผิดพลาดทุกตัวออกมาเป็น [OpenAiFailure] ที่เป็นภาษาคน · ผู้เรียก
/// (synthesizeWithFallback) ตกไปใช้เสียงเครื่องแล้วบอกเหตุผลให้ผู้ใช้เห็น
class PremiumTts {
  PremiumTts({
    http.Client? httpClient,
    required String Function(TtsEngine) keyOf,
    required String Function() azureRegion,
    S Function()? strings,
    Duration timeout = const Duration(seconds: 40),
  })  : _http = httpClient ?? http.Client(),
        _keyOf = keyOf,
        _region = azureRegion,
        _s = strings ?? _thai,
        _timeout = timeout;

  final http.Client _http;
  final String Function(TtsEngine) _keyOf;
  final String Function() _region;
  final S Function() _s;
  final Duration _timeout;
  static S _thai() => const S(AppLang.th);

  static String providerName(TtsEngine e) => switch (e) {
        TtsEngine.gemini => 'Gemini',
        TtsEngine.elevenlabs => 'ElevenLabs',
        TtsEngine.azure => 'Azure',
        _ => e.name,
      };

  /// ElevenLabs แนะนำไม่เกิน 2,000 ตัวอักษรต่อคำขอบน text-to-dialogue
  /// · คำตอบของเธอสั้นกว่านี้มาก ตัวนี้กันกรณีหลุด ไม่ใช่การใช้งานปกติ
  static const elevenMaxChars = 2000;

  Future<Utterance> speak(TtsEngine engine, String text, VoiceProfile p,
      {required bool thai}) async {
    final key = _keyOf(engine).trim();
    final name = providerName(engine);
    if (key.isEmpty) throw OpenAiFailure(_s().premiumKeyNeeded(name));
    return switch (engine) {
      TtsEngine.gemini => _gemini(key, text, p),
      TtsEngine.elevenlabs => _eleven(key, text, p, thai: thai),
      TtsEngine.azure => _azure(key, text, p, thai: thai),
      _ => throw OpenAiFailure(_s().premiumFailed(name)),
    };
  }

  // ── Google Gemini ──────────────────────────────────────

  Future<Utterance> _gemini(String key, String text, VoiceProfile p) async {
    final model = p.model.startsWith('gemini-') ? p.model : PremiumCatalog.geminiModels.first;
    final voice = p.voice.isEmpty ? PremiumCatalog.geminiDefaultVoice : p.voice;
    final style = p.instructions.trim();
    final body = jsonEncode({
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'text': text,
              // 🔴 คำสั่งน้ำเสียงต้องอยู่ช่องแยก · รุ่น 3.8 อ่านทุกตัวอักษรใน
              // text ออกเสียง ใส่ "พูดอบอุ่น: …" ไว้ในนั้น = เธออ่านคำสั่งออกมาด้วย
              if (style.isNotEmpty) 'speech_metadata': {'style': style},
            }
          ],
        }
      ],
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {'voiceName': voice},
          },
        },
      },
    });
    final res = await _send(
      TtsEngine.gemini,
      http.Request(
        'POST',
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/'
            '$model:generateContent'),
      )
        ..headers.addAll({
          'x-goog-api-key': key,
          'Content-Type': 'application/json; charset=utf-8',
        })
        ..bodyBytes = utf8.encode(body),
    );
    final (bytes, mime) = _geminiAudio(res);
    return (bytes: bytes, mime: mime);
  }

  /// แกะเสียงจากคำตอบของ Gemini
  ///
  /// เอกสารรุ่นใหม่บอกว่าได้ WAV ที่มีหัวไฟล์แล้ว แต่รุ่นก่อนหน้าได้ PCM ดิบ
  /// (`audio/L16;codec=pcm;rate=24000`) · รับทั้งสองแบบ: มี RIFF = ใช้เลย
  /// ไม่มี = ห่อหัว WAV เองตาม rate ที่บอกมา
  @visibleForTesting
  static (Uint8List, String) geminiAudio(Uint8List body) => _geminiAudio(body);

  static (Uint8List, String) _geminiAudio(Uint8List body) {
    final j = jsonDecode(utf8.decode(body));
    String? data;
    String mime = '';
    final cands = j is Map ? j['candidates'] : null;
    if (cands is List) {
      for (final c in cands) {
        final parts = (c is Map ? c['content'] : null) is Map ? c['content']['parts'] : null;
        if (parts is! List) continue;
        for (final part in parts) {
          if (part is! Map) continue;
          final inline = part['inlineData'] ?? part['inline_data'];
          if (inline is Map && inline['data'] is String) {
            data = inline['data'] as String;
            mime = '${inline['mimeType'] ?? inline['mime_type'] ?? ''}';
            break;
          }
        }
        if (data != null) break;
      }
    }
    if (data == null || data.isEmpty) throw const FormatException('no audio');
    final audio = base64Decode(data);
    if (audio.length >= 12 &&
        String.fromCharCodes(audio.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(audio.sublist(8, 12)) == 'WAVE') {
      return (audio, 'audio/wav');
    }
    final rate = int.tryParse(RegExp(r'rate=(\d+)').firstMatch(mime)?.group(1) ?? '') ?? 24000;
    return (pcmToWav(audio, rate), 'audio/wav');
  }

  /// ห่อ PCM 16 บิต ช่องเดียว ด้วยหัว WAV
  @visibleForTesting
  static Uint8List pcmToWav(Uint8List pcm, int rate) {
    final h = ByteData(44);
    void tag(int at, String t) {
      for (var i = 0; i < 4; i++) {
        h.setUint8(at + i, t.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    h.setUint32(4, 36 + pcm.length, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little);
    h.setUint16(22, 1, Endian.little);
    h.setUint32(24, rate, Endian.little);
    h.setUint32(28, rate * 2, Endian.little);
    h.setUint16(32, 2, Endian.little);
    h.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    h.setUint32(40, pcm.length, Endian.little);
    return Uint8List.fromList([...h.buffer.asUint8List(), ...pcm]);
  }

  // ── ElevenLabs ─────────────────────────────────────────

  Future<Utterance> _eleven(String key, String text, VoiceProfile p,
      {required bool thai}) async {
    final voice = p.voice.trim();
    if (voice.isEmpty) throw OpenAiFailure(_s().elevenPickVoice);
    final model = p.model.startsWith('eleven_') ? p.model : PremiumCatalog.elevenModels.first;
    final dialogue = model.startsWith('eleven_v4');
    final uri = dialogue
        ? Uri.parse('https://api.elevenlabs.io/v1/text-to-dialogue?output_format=mp3_44100_128')
        : Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/'
            '${Uri.encodeComponent(voice)}?output_format=mp3_44100_128');
    final body = elevenBody(text, p, thai: thai);

    final res = await _send(
      TtsEngine.elevenlabs,
      http.Request('POST', uri)
        ..headers.addAll({
          'xi-api-key': key,
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'audio/mpeg',
        })
        ..bodyBytes = utf8.encode(jsonEncode(body)),
    );
    return (bytes: res, mime: 'audio/mpeg');
  }

  /// เนื้อคำขอ ElevenLabs พร้อมการปรับแต่งทั้งหมด · แยกให้เทสต์ตรวจได้
  ///
  /// v4 ใช้ได้ผ่าน text-to-dialogue (ตามเอกสาร) · v3 ผ่าน text-to-speech
  /// · ต้องส่ง model_id เสมอ ไม่ส่ง = multilingual_v2 ซึ่งไม่มีภาษาไทย
  ///
  /// 🔴 ส่งเฉพาะช่องที่รุ่นนั้นรับ · text-to-dialogue ไม่มี style / speed /
  /// speaker boost (เอกสาร ToDialogueSettings มีแค่ stability · similarity)
  /// ส่งช่องที่ไม่รู้จักไปเสี่ยง 422 ทั้งประโยค
  @visibleForTesting
  static Map<String, Object> elevenBody(String text, VoiceProfile p, {required bool thai}) {
    final model = p.model.startsWith('eleven_') ? p.model : PremiumCatalog.elevenModels.first;
    final t = p.eleven;
    final tagged = t.tagged(text);
    final said = tagged.length > elevenMaxChars ? tagged.substring(0, elevenMaxChars) : tagged;
    double r(double v) => (v * 100).roundToDouble() / 100;
    final common = <String, Object>{
      'model_id': model,
      'language_code': thai ? 'th' : 'en',
      if (t.normalize != 'auto') 'apply_text_normalization': t.normalize,
      if (t.seed > 0) 'seed': t.seed,
      if (t.hasEffects) 'audio_effects': t.effectsJson(),
    };
    if (model.startsWith('eleven_v4')) {
      return {
        ...common,
        'inputs': [
          {'text': said, 'voice_id': p.voice.trim()}
        ],
        'settings': {'stability': r(t.stability), 'similarity': r(t.similarity)},
      };
    }
    return {
      'text': said,
      ...common,
      'voice_settings': {
        'stability': r(t.stability),
        'similarity_boost': r(t.similarity),
        'style': r(t.style),
        'use_speaker_boost': t.speakerBoost,
        'speed': r(t.speed),
      },
    };
  }

  String _elevenKey() {
    final key = _keyOf(TtsEngine.elevenlabs).trim();
    if (key.isEmpty) throw OpenAiFailure(_s().premiumKeyNeeded('ElevenLabs'));
    return key;
  }

  /// โคลนเสียงแบบทันที (Instant Voice Clone) จากไฟล์เสียงตัวอย่าง
  ///
  /// POST /v1/voices/add · multipart · คืน voice_id ที่ใช้พูดได้ทันที
  /// · ต้องเป็นแผน Starter ขึ้นไป (แผนฟรีโคลนไม่ได้ → 401/403 พร้อมข้อความ)
  Future<String> elevenClone({
    required String name,
    required List<String> files,
    bool removeNoise = true,
    String description = '',
  }) async {
    final key = _elevenKey();
    final req = http.MultipartRequest('POST', Uri.parse('https://api.elevenlabs.io/v1/voices/add'))
      ..headers['xi-api-key'] = key
      ..fields['name'] = name
      ..fields['remove_background_noise'] = '$removeNoise';
    if (description.isNotEmpty) req.fields['description'] = description;
    for (final f in files) {
      req.files.add(await http.MultipartFile.fromPath('files', f));
    }
    final res = await _send(TtsEngine.elevenlabs, req);
    final j = jsonDecode(utf8.decode(res));
    final id = j is Map ? j['voice_id'] : null;
    if (id is! String || id.isEmpty) throw OpenAiFailure(_s().premiumFailed('ElevenLabs'));
    return id;
  }

  /// ลบเสียงออกจากบัญชี (ใช้กับเสียงโคลนของเจ้าของ)
  Future<void> elevenDeleteVoice(String id) async {
    await _send(
      TtsEngine.elevenlabs,
      http.Request('DELETE', Uri.parse('https://api.elevenlabs.io/v1/voices/${Uri.encodeComponent(id)}'))
        ..headers['xi-api-key'] = _elevenKey(),
    );
  }

  /// แผนและเครดิตที่เหลือ · ใช้บอกเจ้าของว่าโคลนได้ไหม เหลือใช้อีกเท่าไร
  Future<ElevenAccount> elevenAccount() async {
    final res = await _send(
      TtsEngine.elevenlabs,
      http.Request('GET', Uri.parse('https://api.elevenlabs.io/v1/user/subscription'))
        ..headers['xi-api-key'] = _elevenKey(),
    );
    return ElevenAccount.parse(jsonDecode(utf8.decode(res)));
  }

  /// เอฟเฟกต์ที่ใช้ได้ (ฟิลเตอร์ · ห้อง · เสียงพื้นหลัง) · GET /v1/audio-effects/catalog
  Future<ElevenEffects> elevenEffects() async {
    final res = await _send(
      TtsEngine.elevenlabs,
      http.Request('GET', Uri.parse('https://api.elevenlabs.io/v1/audio-effects/catalog'))
        ..headers['xi-api-key'] = _elevenKey(),
    );
    return ElevenEffects.parse(jsonDecode(utf8.decode(res)));
  }

  /// ถอดเสียงด้วย Scribe v2 · POST /v1/speech-to-text (multipart)
  Future<String> elevenTranscribe(Uint8List wav, {required bool thai}) async {
    final req = http.MultipartRequest('POST', Uri.parse('https://api.elevenlabs.io/v1/speech-to-text'))
      ..headers['xi-api-key'] = _elevenKey()
      ..fields['model_id'] = 'scribe_v2'
      ..fields['language_code'] = thai ? 'th' : 'en'
      ..fields['tag_audio_events'] = 'false'
      ..files.add(http.MultipartFile.fromBytes('file', wav, filename: 'speech.wav'));
    final res = await _send(TtsEngine.elevenlabs, req);
    final j = jsonDecode(utf8.decode(res));
    return (j is Map && j['text'] is String ? j['text'] as String : '').trim();
  }

  /// เสียงทั้งหมดในบัญชี ElevenLabs ของผู้ใช้ (รวมเสียงที่เพิ่มจากคลังและเสียงโคลน)
  Future<List<PremiumVoice>> elevenVoices() async {
    final res = await _send(
      TtsEngine.elevenlabs,
      http.Request('GET', Uri.parse('https://api.elevenlabs.io/v2/voices?page_size=100'))
        ..headers['xi-api-key'] = _elevenKey(),
    );
    final j = jsonDecode(utf8.decode(res));
    final list = j is Map ? j['voices'] : null;
    if (list is! List) return const [];
    return [
      for (final v in list)
        if (v is Map && v['voice_id'] is String)
          PremiumVoice(
            v['voice_id'] as String,
            '${v['name'] ?? v['voice_id']}',
            [
              if (v['labels'] is Map) ...[
                (v['labels'] as Map)['gender'],
                (v['labels'] as Map)['accent'],
              ],
              v['category'],
            ].whereType<String>().where((e) => e.isNotEmpty).join(' · '),
          ),
    ];
  }

  // ── Microsoft Azure ────────────────────────────────────

  Future<Utterance> _azure(String key, String text, VoiceProfile p,
      {required bool thai}) async {
    final region = _region().trim();
    if (region.isEmpty) throw OpenAiFailure(_s().azureNeedsRegion);
    final voice = p.voice.isEmpty ? PremiumCatalog.azureVoices(thai: thai).first.id : p.voice;
    final res = await _send(
      TtsEngine.azure,
      http.Request(
        'POST',
        Uri.parse('https://$region.tts.speech.microsoft.com/cognitiveservices/v1'),
      )
        ..headers.addAll({
          'Ocp-Apim-Subscription-Key': key,
          'Content-Type': 'application/ssml+xml; charset=utf-8',
          'X-Microsoft-OutputFormat': 'audio-24khz-96kbitrate-mono-mp3',
          'User-Agent': 'GigGok',
        })
        ..bodyBytes = utf8.encode(azureSsml(text, voice, thai: thai)),
    );
    return (bytes: res, mime: 'audio/mpeg');
  }

  /// SSML ของ Azure · เสียงหลายภาษา (Multilingual) ที่ต้องพูดไทย ห่อด้วย
  /// `<lang>` ให้ชัด ไม่ต้องเดาภาษาจากข้อความ
  ///
  /// 🔴 ต้อง escape ทุกครั้ง · ข้อความของเธอมี & < > ได้ (เช่น "A&B") และ
  /// SSML ที่พังคือ 400 ทั้งประโยค ไม่ใช่แค่ตัวอักษรนั้นหาย
  @visibleForTesting
  static String azureSsml(String text, String voice, {required bool thai}) {
    final esc = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
    final locale = RegExp(r'^([a-z]{2}-[A-Z]{2})-').firstMatch(voice)?.group(1) ??
        (thai ? 'th-TH' : 'en-US');
    final want = thai ? 'th-TH' : 'en-US';
    final say = voice.contains('Multilingual') && locale != want
        ? '<lang xml:lang="$want">$esc</lang>'
        : esc;
    final v = voice.replaceAll('"', '');
    return '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" '
        'xmlns:mstts="http://www.w3.org/2001/mstts" xml:lang="$locale">'
        '<voice name="$v">$say</voice></speak>';
  }

  /// เสียงที่ภูมิภาคนั้นมีจริง (กรองเฉพาะไทย + หลายภาษา) · ใช้หาเสียง MAI
  /// ที่ยังเป็น preview และมีไม่ครบทุกภูมิภาค
  Future<List<PremiumVoice>> azureVoiceList() async {
    final key = _keyOf(TtsEngine.azure).trim();
    final region = _region().trim();
    if (key.isEmpty) throw OpenAiFailure(_s().premiumKeyNeeded('Azure'));
    if (region.isEmpty) throw OpenAiFailure(_s().azureNeedsRegion);
    final res = await _send(
      TtsEngine.azure,
      http.Request('GET',
          Uri.parse('https://$region.tts.speech.microsoft.com/cognitiveservices/voices/list'))
        ..headers['Ocp-Apim-Subscription-Key'] = key,
    );
    final j = jsonDecode(utf8.decode(res));
    if (j is! List) return const [];
    return [
      for (final v in j)
        if (v is Map &&
            v['ShortName'] is String &&
            ('${v['Locale']}' == 'th-TH' || '${v['ShortName']}'.contains('Multilingual')))
          PremiumVoice(
            v['ShortName'] as String,
            '${v['DisplayName'] ?? v['LocalName'] ?? v['ShortName']}',
            [v['Gender'], v['Locale'], v['Status']].whereType<String>().join(' · '),
          ),
    ];
  }

  // ── ร่วมกัน ────────────────────────────────────────────

  Future<Uint8List> _send(TtsEngine engine, http.BaseRequest req) async {
    final name = providerName(engine);
    http.Response res;
    try {
      // Bound the complete download, not just the response headers. A stalled
      // audio body used to leave Listen disabled indefinitely.
      res = await (() async {
        return http.Response.fromStream(await _http.send(req));
      })().timeout(_timeout);
    } on Object catch (e) {
      debugPrint('เสียง $name: ส่งไม่ถึง — ${e.runtimeType}');
      throw OpenAiFailure(_s().errOffline);
    }
    final body = res.bodyBytes;
    if (res.statusCode == 200) return body;
    // ห้ามพิมพ์ body ทั้งก้อน · บางเจ้าสะท้อนข้อความที่ส่งไปกลับมาใน error
    debugPrint('เสียง $name: ตอบ ${res.statusCode}');
    throw OpenAiFailure(switch (res.statusCode) {
      401 => _s().premiumBadKey(name),
      403 => _s().premiumForbidden(name),
      402 || 429 => _s().premiumQuota(name),
      400 || 422 => _s().premiumSettingsRejected(name),
      404 => _s().premiumVoiceUnavailable(name),
      _ => _s().premiumFailed(name),
    });
  }

  void close() => _http.close();
}

/// แผนของบัญชี ElevenLabs · GET /v1/user/subscription
@immutable
class ElevenAccount {
  const ElevenAccount({
    this.tier = '',
    this.used = 0,
    this.limit = 0,
    this.canClone = false,
    this.voiceSlotsUsed = 0,
    this.voiceLimit = 0,
  });

  final String tier;
  final int used;
  final int limit;
  final bool canClone;
  final int voiceSlotsUsed;
  final int voiceLimit;

  int get left => (limit - used).clamp(0, limit);

  static ElevenAccount parse(Object? j) {
    if (j is! Map) return const ElevenAccount();
    int n(String k) => j[k] is num ? (j[k] as num).toInt() : 0;
    return ElevenAccount(
      tier: '${j['tier'] ?? ''}',
      used: n('character_count'),
      limit: n('character_limit'),
      canClone: j['can_use_instant_voice_cloning'] == true,
      voiceSlotsUsed: n('voice_slots_used'),
      voiceLimit: n('voice_limit'),
    );
  }
}
