/// เครดิตของ "ผ่านบริการเรา" — กระเป๋าเงิน xman studio (บาท) หักทุกข้อความ
///
/// ## ทำไมต้องมี
///
/// เจ้าของสั่ง: ต้องเห็นเครดิต หลอดโควต้า ปุ่มเติม (รายละเอียดการเติมอยู่หน้าเว็บ)
/// และ **รุ่นที่เราไม่ได้เปิดให้บริการต้องไม่โผล่** · ของเดิมแอปโชว์รุ่นของ
/// OpenAI ทั้งรายการ แล้วหลังบ้านเงียบ ๆ ใช้รุ่นของตัวเองแทนถ้าไม่ได้เปิดไว้
///
/// ทุกอย่างมาจาก `GET /api/ai/v1/account` ของหลังบ้าน (AppAiController) ·
/// ราคาและรุ่นแอดมินตั้งที่ /admin/ai-settings · แอปไม่ตั้งราคาเอง
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// รุ่นที่หลังบ้านเปิดให้ใช้ พร้อมราคาต่อข้อความ
@immutable
class ProxyModel {
  const ProxyModel({required this.id, required this.label, required this.price});

  final String id;
  final String label;

  /// บาทต่อข้อความ · 0 = แอดมินเปิดให้ใช้ฟรี
  final double price;

  static ProxyModel? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = '${raw['id'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    final label = '${raw['label'] ?? ''}'.trim();
    return ProxyModel(
      id: id,
      label: label.isEmpty ? id : label,
      price: (raw['price'] as num?)?.toDouble() ?? 0,
    );
  }
}

@immutable
class ProxyAccount {
  const ProxyAccount({
    required this.enabled,
    required this.linked,
    required this.balance,
    required this.dailyCap,
    required this.spentToday,
    required this.messagesToday,
    required this.models,
    required this.topupUrl,
    required this.linkUrl,
    this.currency = 'THB',
    this.defaultModel,
  });

  /// บริการเปิดอยู่ไหม (แอดมินปิดได้)
  final bool enabled;

  /// เครื่องนี้ผูกกับบัญชีแล้วหรือยัง · ยังไม่ผูก = ไม่มีกระเป๋าให้หัก
  final bool linked;

  final double balance;

  /// เพดานใช้จ่ายต่อวัน · 0 = ไม่จำกัด
  final double dailyCap;
  final double spentToday;
  final int messagesToday;
  final List<ProxyModel> models;
  final String topupUrl;
  final String linkUrl;
  final String currency;
  final String? defaultModel;

  static ProxyAccount? fromJson(Object? raw) {
    if (raw is! Map) return null;
    double d(Object? v) => (v as num?)?.toDouble() ?? 0;
    final today = raw['today'] is Map ? raw['today'] as Map : const {};
    return ProxyAccount(
      enabled: raw['enabled'] != false,
      linked: raw['linked'] == true,
      balance: d(raw['balance']),
      dailyCap: d(raw['daily_cap']),
      spentToday: d(today['spent']),
      messagesToday: (today['messages'] as num?)?.toInt() ?? 0,
      models: [
        for (final m in (raw['models'] is List ? raw['models'] as List : const []))
          ?ProxyModel.fromJson(m),
      ],
      topupUrl: '${raw['topup_url'] ?? ''}',
      linkUrl: '${raw['link_url'] ?? ''}',
      currency: '${raw['currency'] ?? 'THB'}',
      defaultModel: raw['default_model'] as String?,
    );
  }

  /// รุ่นที่จะใช้จริง: ที่เลือกไว้ถ้ายังเปิดอยู่ · ไม่งั้นรุ่นแรกที่เปิด (หลังบ้านก็ทำแบบนี้)
  ProxyModel? modelFor(String chosen) {
    for (final m in models) {
      if (m.id == chosen) return m;
    }
    return models.isEmpty ? null : models.first;
  }

  /// เครดิตพอส่งได้อีกประมาณกี่ข้อความด้วยรุ่นนี้ · null = รุ่นฟรี (ไม่จำกัดด้วยเงิน)
  int? messagesLeft(ProxyModel m) {
    if (m.price <= 0) return null;
    var left = (balance / m.price).floor();
    if (dailyCap > 0) {
      final capLeft = ((dailyCap - spentToday) / m.price).floor();
      if (capLeft < left) left = capLeft;
    }
    return left < 0 ? 0 : left;
  }

  /// หลอดโควต้าของวันนี้ 0..1 · null = ไม่มีเพดาน (ไม่มีหลอดให้เทียบ)
  double? get todayShare =>
      dailyCap > 0 ? (spentToday / dailyCap).clamp(0, 1).toDouble() : null;

  /// ยอดหลังหักข้อความล่าสุด (มากับคำตอบ ไม่ต้องถามหลังบ้านซ้ำ)
  ProxyAccount withBilling(Map<String, Object?> b) => ProxyAccount(
        enabled: enabled,
        linked: linked,
        balance: (b['balance'] as num?)?.toDouble() ?? balance,
        dailyCap: (b['daily_cap'] as num?)?.toDouble() ?? dailyCap,
        spentToday: (b['spent_today'] as num?)?.toDouble() ?? spentToday,
        messagesToday: messagesToday + 1,
        models: models,
        topupUrl: topupUrl,
        linkUrl: linkUrl,
        currency: currency,
        defaultModel: defaultModel,
      );
}

/// ถามหลังบ้านว่าเครดิตเหลือเท่าไหร่ และเปิดรุ่นอะไรไว้
class ProxyAccountClient {
  ProxyAccountClient({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  /// โยน [ProxyAccountError] เมื่อถามไม่ได้ · ผู้เรียกแปลเป็นภาษาคนเอง
  Future<ProxyAccount> fetch({required String baseUrl, required String license}) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final http.Response res;
    try {
      res = await _http.get(
        Uri.parse('$base/api/ai/v1/account'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${license.trim()}',
        },
      ).timeout(const Duration(seconds: 12));
    } on Object {
      throw const ProxyAccountError(ProxyAccountProblem.offline);
    }
    if (res.statusCode == 401) throw const ProxyAccountError(ProxyAccountProblem.license);
    if (res.statusCode != 200) {
      throw ProxyAccountError(ProxyAccountProblem.server, status: res.statusCode);
    }
    try {
      final a = ProxyAccount.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
      if (a != null) return a;
    } on FormatException {
      // ตกไปข้างล่าง
    }
    throw ProxyAccountError(ProxyAccountProblem.server, status: res.statusCode);
  }

  void close() => _http.close();
}

enum ProxyAccountProblem { offline, license, server }

class ProxyAccountError implements Exception {
  const ProxyAccountError(this.problem, {this.status});
  final ProxyAccountProblem problem;
  final int? status;
}
