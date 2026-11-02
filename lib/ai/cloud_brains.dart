/// สมองบนคลาวด์ของเจ้าอื่น — xAI Grok · Anthropic Claude · Google Gemini
///
/// ทุกเจ้าใช้**คีย์ของผู้ใช้เอง** (เก็บใน SecretStore) · ผู้ใช้เลือกเจ้าก่อน
/// แล้วค่อยเลือกรุ่นของเจ้านั้น พร้อมเห็นความสามารถและราคาของแต่ละรุ่น
///
/// 🔴 รายการรุ่นมีแต่รุ่นปัจจุบัน · ไม่ใส่รุ่นที่ประกาศเลิกแล้วหรือรุ่นที่ถูกแทน
/// (เจ้าของสั่ง "ไม่ใช้โมเดลที่จะเลิกใช้") · ราคาตรวจกับหน้าราคาทางการ 2026-11-02
/// รายละเอียดอยู่ใน docs/cloud-brains.md
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;

import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import '../i18n/strings_brains.dart';
import 'brain_provider.dart';
import 'openai_client.dart';
import 'openai_config.dart';
import 'secret_store.dart';

/// รุ่นสมองหนึ่งรุ่นในรายการให้เลือก
class BrainModel {
  const BrainModel({
    required this.id,
    required this.label,
    required this.inUsd,
    required this.outUsd,
    this.tier = BrainTier.balanced,
    this.freeTier = false,
    this.contextK = 0,
  });

  /// ชื่อที่ส่งให้ API
  final String id;
  final String label;

  /// ราคาต่อ 1 ล้านโทเคน (USD) ขาเข้า / ขาออก
  final double inUsd;
  final double outUsd;

  final BrainTier tier;

  /// มีแผนฟรีให้ลอง (Gemini)
  final bool freeTier;

  /// context window (พันโทเคน) · 0 = ไม่แสดง
  final int contextK;

  /// ความสามารถ / เหมาะกับอะไร (ข้อความอยู่ใน i18n/strings_brains.dart)
  String hintOf(S s) => s.brainModelHintOf(id);

  /// ราคาที่ประกาศว่าจะเปลี่ยน · ว่าง = ไม่มี
  String priceNoteOf(S s) => s.brainModelPriceNote(id);

  /// ค่าใช้จ่ายโดยประมาณต่อ 1,000 ข้อความ (USD)
  ///
  /// คิดที่ขาเข้า ~3,000 โทเคน (บุคลิก + ความจำ + ประวัติแชท) และขาออก ~250
  /// · ตัวเลขนี้มีไว้เทียบรุ่นกันเอง ไม่ใช่ใบแจ้งหนี้
  double get usdPer1kMessages => inUsd * 3 + outUsd * 0.25;
}

/// ระดับคร่าว ๆ ใช้ทำป้ายสี
enum BrainTier { cheap, balanced, smart, top }

/// รายการรุ่นของแต่ละเจ้า
abstract final class CloudBrains {
  // ── OpenAI ──
  /// ราคาจาก developers.openai.com/api/docs/pricing (Standard)
  static const openai = [
    BrainModel(
      id: 'gpt-5.6-sol',
      label: 'GPT-5.6 Sol',
      inUsd: 4,
      outUsd: 20,
      tier: BrainTier.smart,
      contextK: 1050,
    ),
    BrainModel(
      id: 'gpt-6.1-sol',
      label: 'GPT-6.1 Sol',
      inUsd: 2,
      outUsd: 10,
      tier: BrainTier.smart,
      contextK: 1050,
    ),
    BrainModel(
      id: 'gpt-6.1-terra',
      label: 'GPT-6.1 Terra',
      inUsd: 1,
      outUsd: 5,
      tier: BrainTier.balanced,
      contextK: 1050,
    ),
    BrainModel(
      id: 'gpt-5.6-terra',
      label: 'GPT-5.6 Terra',
      inUsd: 2,
      outUsd: 12,
      tier: BrainTier.balanced,
    ),
    BrainModel(
      id: 'gpt-6-luna',
      label: 'GPT-6 Luna',
      inUsd: 0.10,
      outUsd: 0.50,
      tier: BrainTier.cheap,
    ),
    BrainModel(id: 'gpt-6-astra', label: 'GPT-6 Astra', inUsd: 10, outUsd: 50, tier: BrainTier.top),
  ];

  // ── xAI Grok ──
  /// docs.x.ai/docs/pricing · ราคาช่วง context สั้น (< 200k)
  static const grokBaseUrl = 'https://api.x.ai/v1';
  static const grok = [
    BrainModel(
      id: 'grok-4.3',
      label: 'Grok 4.3',
      inUsd: 1.25,
      outUsd: 2.50,
      tier: BrainTier.balanced,
      contextK: 1000,
    ),
    BrainModel(
      id: 'grok-4.7',
      label: 'Grok 4.7',
      inUsd: 2,
      outUsd: 6,
      tier: BrainTier.smart,
      contextK: 500,
    ),
  ];

  // ── Anthropic Claude ──
  /// docs.anthropic.com/en/docs/about-claude/pricing
  static const claudeUrl = 'https://api.anthropic.com/v1/messages';
  static const claudeVersion = '2023-06-01';
  static const claude = [
    BrainModel(
      id: 'claude-haiku-5-5',
      label: 'Claude Haiku 5.5',
      inUsd: 0.10,
      outUsd: 0.50,
      tier: BrainTier.cheap,
      contextK: 1000,
    ),
    BrainModel(
      id: 'claude-sonnet-5-5',
      label: 'Claude Sonnet 5.5',
      inUsd: 2,
      outUsd: 10,
      tier: BrainTier.balanced,
      contextK: 1000,
    ),
    BrainModel(
      id: 'claude-opus-5-5',
      label: 'Claude Opus 5.5',
      inUsd: 4,
      outUsd: 20,
      tier: BrainTier.smart,
      contextK: 1000,
    ),
    BrainModel(
      id: 'claude-fable-5-1',
      label: 'Claude Fable 5.1',
      inUsd: 10,
      outUsd: 50,
      tier: BrainTier.top,
      contextK: 1000,
    ),
  ];

  // ── Google Gemini ──
  /// ai.google.dev/gemini-api/docs/pricing (Paid tier) · ใช้ทาง OpenAI-compatible
  static const geminiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta/openai';
  static const gemini = [
    BrainModel(
      id: 'gemini-3.5-flash-lite',
      label: 'Gemini 3.5 Flash-Lite',
      inUsd: 0.30,
      outUsd: 2.50,
      tier: BrainTier.cheap,
      freeTier: true,
    ),
    BrainModel(
      id: 'gemini-3.8-flash',
      label: 'Gemini 3.8 Flash',
      inUsd: 0.75,
      outUsd: 3.75,
      tier: BrainTier.balanced,
      freeTier: true,
    ),
    BrainModel(
      id: 'gemini-4-argon',
      label: 'Gemini 4 Argon',
      inUsd: 2,
      outUsd: 10,
      tier: BrainTier.top,
      contextK: 1000,
    ),
  ];

  /// รุ่นของเจ้านั้น · ว่าง = เจ้านั้นไม่มีรายการ (พร็อกซี / เซิร์ฟเวอร์ในบ้าน / ในเครื่อง)
  static List<BrainModel> modelsOf(BrainProvider p) => switch (p) {
    BrainProvider.openai => openai,
    BrainProvider.grok => grok,
    BrainProvider.claude => claude,
    BrainProvider.gemini => gemini,
    _ => const [],
  };

  /// รุ่นตั้งต้นของเจ้านั้น — รุ่นที่สมดุลสำหรับการคุย ไม่ใช่รุ่นที่แพงที่สุด
  static String defaultModel(BrainProvider p) => switch (p) {
    BrainProvider.grok => 'grok-4.3',
    BrainProvider.claude => 'claude-sonnet-5-5',
    BrainProvider.gemini => 'gemini-3.8-flash',
    _ => OpenAiConfig.brainModel,
  };

  static BrainModel? find(String id) {
    for (final list in [openai, grok, claude, gemini]) {
      for (final m in list) {
        if (m.id == id) return m;
      }
    }
    return null;
  }

  /// ชื่อเจ้าที่ผู้ใช้เห็น
  static String providerName(BrainProvider p) => switch (p) {
    BrainProvider.grok => 'Grok',
    BrainProvider.claude => 'Claude',
    BrainProvider.gemini => 'Gemini',
    _ => 'OpenAI',
  };

  /// ช่องเก็บคีย์ใน SecretStore · Gemini ใช้ช่องเดียวกับเสียง Gemini (คีย์ AI Studio ตัวเดียวกัน)
  static String? keySlot(BrainProvider p) => switch (p) {
    BrainProvider.grok => SecretStore.kXaiKey,
    BrainProvider.claude => SecretStore.kAnthropicKey,
    BrainProvider.gemini => SecretStore.kGeminiKey,
    BrainProvider.openai => SecretStore.kOpenAiKey,
    _ => null,
  };

  /// หน้าเอาคีย์ของเจ้านั้น
  static String keyPage(BrainProvider p) => switch (p) {
    BrainProvider.grok => 'https://console.x.ai/',
    BrainProvider.claude => 'https://console.anthropic.com/settings/keys',
    BrainProvider.gemini => 'https://aistudio.google.com/apikey',
    _ => 'https://platform.openai.com/api-keys',
  };

  /// คีย์หน้าตาถูกไหม — เตือนอย่างเดียว ไม่ปฏิเสธ (รูปแบบเปลี่ยนได้)
  static bool keyLooksRight(BrainProvider p, String v) {
    final k = v.trim();
    return switch (p) {
      BrainProvider.grok => k.startsWith('xai-'),
      BrainProvider.claude => k.startsWith('sk-ant-'),
      BrainProvider.gemini => k.startsWith('AIza'),
      BrainProvider.openai => k.startsWith('sk-'),
      _ => true,
    };
  }

  /// ระดับการคิดที่จะขอ (`reasoning_effort`) · null = ไม่ส่ง
  ///
  /// 🔴 งานคุยต้องตอบไว · ไม่ขอ = ใช้ค่าตั้งต้นของรุ่นซึ่งคิดนานและกินโทเคนขาออก
  /// - Grok 4.3 รับ none · Grok 4.7 เอกสารไม่ระบุว่าตั้งได้ → ไม่ส่ง (ส่งผิด = 400)
  /// - Gemini แปลง `minimal` ให้ทุกรุ่น (Argon แปลงเป็น low) ตามตารางในเอกสาร
  static String? effortFor(BrainProvider p, String model) {
    final id = model.trim().toLowerCase();
    return switch (p) {
      BrainProvider.grok => id.startsWith('grok-4.3') ? 'none' : null,
      BrainProvider.gemini => id.startsWith('gemini-') ? 'minimal' : null,
      _ => null,
    };
  }
}

/// คุยกับ Claude ผ่าน Messages API ของ Anthropic
///
/// ไม่ใช้ชั้นเข้ากันได้กับ OpenAI ของ Anthropic เพราะเอกสารบอกว่ามีไว้ทดสอบ
/// ไม่ใช่ใช้งานจริง · header ต่างกัน (`x-api-key` + `anthropic-version`)
/// และ system prompt อยู่ช่องแยก ไม่ใช่ข้อความแรก
///
/// รับช่วง [OpenAiClient] เพื่อให้ทางเดิมในแอป (`_askBrain`) ใช้ได้ทันที
/// · ถอดเสียง / พูด / คุยสดไม่ได้ผ่านตัวนี้ (Claude ไม่มี API เสียง)
class ClaudeClient extends OpenAiClient {
  // ใช้ httpClient สองที่ (ตัวเองกับแม่) จึงเป็น super parameter ไม่ได้
  // ignore: use_super_parameters
  ClaudeClient({
    http.Client? httpClient,
    required String Function() apiKeyOf,
    super.strings,
    Duration timeout = const Duration(seconds: 60),
  }) : _h = httpClient ?? http.Client(),
       _t = timeout,
       super(
         httpClient: httpClient,
         apiKeyOf: apiKeyOf,
         baseUrl: 'https://api.anthropic.com/v1',
         upstream: Upstream.cloud,
         cloudName: 'Claude',
         timeout: timeout,
       );

  final http.Client _h;
  final Duration _t;

  @override
  bool get usable => currentKey.isNotEmpty;

  @override
  Future<String> reply({required String system, required List<Turn> history, String? model}) async {
    final key = currentKey;
    if (key.isEmpty) throw OpenAiFailure(strings.errNoKey);
    final body = buildBody(
      system: system,
      history: history,
      model: model ?? CloudBrains.defaultModel(BrainProvider.claude),
    );

    final http.Response res;
    try {
      res = await _h
          .post(
            Uri.parse(CloudBrains.claudeUrl),
            headers: {
              'x-api-key': key,
              'anthropic-version': CloudBrains.claudeVersion,
              'content-type': 'application/json; charset=utf-8',
            },
            body: utf8.encode(jsonEncode(body)),
          )
          .timeout(_t);
    } on Object catch (e) {
      debugPrint('Claude: ส่งไม่ถึง — ${e.runtimeType}');
      throw OpenAiFailure(strings.errOffline, offline: true);
    }
    if (res.statusCode != 200) {
      debugPrint('Claude: ตอบ ${res.statusCode}');
      throw OpenAiFailure(describeError(res), status: res.statusCode);
    }
    return readText(utf8.decode(res.bodyBytes));
  }

  /// เนื้อคำขอ · แยกออกมาให้เทสต์ตรวจได้โดยไม่ต้องยิงเน็ต
  ///
  /// 🔴 Messages API บังคับให้ข้อความแรกเป็น user และสลับ user/assistant
  /// · ประวัติของแอปอาจขึ้นต้นด้วยคำทักของเธอ หรือมีฝั่งเดียวกันติดกัน
  /// → รวมข้อความฝั่งเดียวกันที่ติดกัน และตัดของเธอที่นำหน้าทิ้ง
  @visibleForTesting
  static Map<String, Object> buildBody({
    required String system,
    required List<Turn> history,
    required String model,
  }) {
    final msgs = <Map<String, String>>[];
    for (final t in history) {
      final role = t.fromHer ? 'assistant' : 'user';
      final text = t.text.trim();
      if (text.isEmpty) continue;
      if (msgs.isEmpty && role == 'assistant') continue;
      if (msgs.isNotEmpty && msgs.last['role'] == role) {
        msgs.last['content'] = '${msgs.last['content']}\n\n$text';
      } else {
        msgs.add({'role': role, 'content': text});
      }
    }
    if (msgs.isEmpty) msgs.add({'role': 'user', 'content': '…'});
    return {
      'model': model,
      // เพดานรวมการคิดภายใน · รุ่นที่คิดตลอด (Opus / Fable) ต้องมีที่ให้คิดก่อนตอบ
      'max_tokens': 2000,
      'system': system,
      'messages': msgs,
      // งานคุยต้องตอบไว · effort ต่ำ = คิดน้อยลง ตอบเร็วขึ้น โทเคนน้อยลง
      'output_config': {'effort': 'low'},
    };
  }

  /// ดึงเฉพาะข้อความตอบ · บล็อก thinking ไม่ใช่คำตอบ ห้ามเอาไปพูด
  @visibleForTesting
  static String readText(String raw) {
    final j = jsonDecode(raw);
    final content = j is Map ? j['content'] : null;
    if (content is! List) return '';
    return [
      for (final c in content)
        if (c is Map && c['type'] == 'text' && c['text'] is String) c['text'] as String,
    ].join().trim();
  }

  @override
  void close() {
    _h.close();
    super.close();
  }
}
