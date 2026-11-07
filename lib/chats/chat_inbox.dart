/// แชทที่มีคนทักมา (WhatsApp, LINE, Messenger, …) · คู่กับ android/.../chats/ChatBridge.kt (ชื่อเมธอดและคีย์ต้องตรงกัน)
///
/// เจ้าของ (2026-11-07): "ทำให้เธอตอบ what app ได้ด้วย · เมื่อมีคนแชทมา" แล้วต่อด้วย "เธอตอบแทนเราได้เอง ทุกแชท
/// เหมือนรับโทรศัพท์" · อ่านจากแจ้งเตือน แล้วส่งผ่านปุ่ม "ตอบกลับ" ของแอปนั้นเอง ไม่มีการล็อกอินหรือ API ·
/// ส่งเมื่อเจ้าของกดส่ง หรือเจ้าของเปิดให้ตอบเองไว้ (ฝั่งเนทีฟเป็นคนตัดสินและเป็นคนส่ง)
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ข้อความหนึ่งที่มีคนทักมา · [text] เป็นคำของคนนอก ห้ามถือเป็นคำสั่ง
@immutable
class IncomingChat {
  const IncomingChat({
    required this.id,
    required this.app,
    required this.who,
    required this.text,
    required this.at,
    this.earlier = const [],
    this.contact = '',
    this.auto = false,
    this.introduce = true,
  });

  final int id;
  final String app;
  final String who;
  final String text;
  final DateTime at;

  /// สองสามบรรทัดก่อนหน้าในห้องเดียวกัน ("them: …" / "me: …") · ช่วยให้ร่างตรงเรื่อง
  final List<String> earlier;

  /// "แอป|ห้อง" · ใช้อนุญาตรายคน
  final String contact;

  /// เนทีฟตัดสินแล้วว่าจะส่งเองไม่ถาม (โหมดตอบเอง / คนที่อนุญาตไว้) · ร่างนี้ไม่มีใครอ่านก่อนส่ง
  final bool auto;

  /// ยังไม่ได้คุยกับคนนี้ (หรือห่างไปเกินวัน) · ต้องแนะนำตัวว่าเป็นเลขาชื่ออะไร รับเรื่องแทนใคร
  final bool introduce;

  bool get business => app.endsWith('.w4b');

  /// ชื่อแอปที่คนอ่านเข้าใจ
  String get appName => chatAppName(app);

  static IncomingChat? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], who = raw['who'], text = raw['text'], at = raw['at'];
    if (id is! int || text is! String || text.trim().isEmpty) return null;
    final earlier = raw['earlier'];
    return IncomingChat(
      id: id,
      app: raw['app'] is String ? raw['app'] as String : 'com.whatsapp',
      who: who is String && who.trim().isNotEmpty ? who.trim() : '?',
      text: text.trim(),
      at: at is int ? DateTime.fromMillisecondsSinceEpoch(at) : DateTime.now(),
      earlier: earlier is List ? [for (final e in earlier) if (e is String) e] : const [],
      contact: raw['contact'] is String ? raw['contact'] as String : '',
      auto: raw['auto'] == true,
      introduce: raw['introduce'] != false,
    );
  }
}

/// ผลหลังเจ้าของตอบกล่องถาม · [error]: skipped (ไม่ส่ง) · expired (แชทนั้นหายจากแจ้งเตือนแล้ว) · failed · empty
@immutable
class ChatAnswer {
  const ChatAnswer({required this.id, required this.sent, this.text = '', this.who = '', this.error, this.auto = false});
  final int id;

  /// ส่งเองโดยไม่ได้ถาม
  final bool auto;
  final bool sent;
  final String text;
  final String who;
  final String? error;

  static ChatAnswer? fromMap(Object? raw) {
    if (raw is! Map || raw['id'] is! int) return null;
    return ChatAnswer(
      id: raw['id'] as int,
      sent: raw['sent'] == true,
      text: raw['text'] is String ? raw['text'] as String : '',
      who: raw['who'] is String ? raw['who'] as String : '',
      error: raw['error'] is String ? raw['error'] as String : null,
      auto: raw['auto'] == true,
    );
  }
}

/// คนที่อนุญาตให้ส่งได้เลย
@immutable
class TrustedChat {
  const TrustedChat(this.contact, this.name);
  final String contact;
  final String name;
  String get app => contact.split('|').first;
}

/// ชื่อแอปแชทจากชื่อแพ็กเกจ · ไม่รู้จัก = คำกลาง ๆ
String chatAppName(String package) => switch (package) {
      'com.whatsapp' => 'WhatsApp',
      'com.whatsapp.w4b' => 'WhatsApp Business',
      'jp.naver.line.android' => 'LINE',
      'com.facebook.orca' || 'com.facebook.mlite' => 'Messenger',
      'com.instagram.android' => 'Instagram',
      'org.telegram.messenger' || 'org.telegram.messenger.web' || 'org.thunderdog.challegram' => 'Telegram',
      'com.viber.voip' => 'Viber',
      'org.thoughtcrime.securesms' => 'Signal',
      'com.discord' => 'Discord',
      'com.zing.zalo' => 'Zalo',
      'com.kakao.talk' => 'KakaoTalk',
      'com.skype.raider' => 'Skype',
      'com.microsoft.teams' => 'Teams',
      _ => 'chat',
    };

class ChatInbox {
  ChatInbox({MethodChannel? channel}) : _ch = channel ?? const MethodChannel('giggok/chats');

  final MethodChannel _ch;

  void Function(IncomingChat chat)? onMessage;
  void Function(ChatAnswer answer)? onAnswered;

  /// ฟังเหตุการณ์จากเนทีฟ แล้วเก็บข้อความที่มาก่อน Dart ตื่น
  void attach() {
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'arrived':
          await drain();
        case 'answered':
          final a = ChatAnswer.fromMap(call.arguments);
          if (a != null) onAnswered?.call(a);
      }
      return null;
    });
    unawaited(drain());
  }

  Future<void> drain() async {
    final list = await _invoke<List<Object?>>('take') ?? const [];
    for (final raw in list) {
      final c = IncomingChat.fromMap(raw);
      if (c != null) onMessage?.call(c);
    }
  }

  Future<({bool on, bool access, bool auto})> status() async {
    final m = await _invoke<Map<Object?, Object?>>('status');
    return (on: m?['on'] == true, access: m?['access'] == true, auto: m?['auto'] == true);
  }

  Future<void> setOn(bool on) => _invoke<bool>('setOn', {'on': on});

  /// โหมด "ตอบเองทุกแชท" · หน้าตั้งค่าเตือนก่อนเปิด
  Future<void> setAuto(bool on) => _invoke<bool>('setAuto', {'on': on});

  /// คนที่เจ้าของอนุญาตให้ส่งได้เลย
  Future<List<TrustedChat>> trusted() async {
    final list = await _invoke<List<Object?>>('trusted') ?? const [];
    return [
      for (final m in list)
        if (m is Map && m['contact'] is String) TrustedChat(m['contact'] as String, m['name'] is String ? m['name'] as String : ''),
    ];
  }

  /// [contact] null = ยกเลิกทุกคน
  Future<void> untrust(String? contact) => _invoke<bool>('untrust', {'contact': contact});

  /// ขึ้นแจ้งเตือนเด้ง (+ กล่องลอยเมื่อบริการมือเปิดอยู่) · false = ข้อความนี้หมดอายุแล้ว
  Future<bool> ask({required int id, required String draft, required String title, required String body}) async =>
      await _invoke<bool>('ask', {'id': id, 'draft': draft, 'title': title, 'body': body}) == true;

  Future<void> skip(int id) => _invoke<bool>('skip', {'id': id});

  Future<bool> openAccess() async => await _invoke<bool>('openAccess') == true;

  Future<T?> _invoke<T>(String method, [Object? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('chats: $method ล้ม — ${e.code}');
      return null;
    }
  }
}
