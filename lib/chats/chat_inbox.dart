/// แชท WhatsApp ที่มีคนทักมา · คู่กับ android/.../chats/ChatBridge.kt (ชื่อเมธอดและคีย์ต้องตรงกัน)
///
/// เจ้าของ (2026-11-07): "ทำให้เธอตอบ what app ได้ด้วย · เมื่อมีคนแชทมา" · อ่านจากแจ้งเตือน แล้วส่งผ่านปุ่ม
/// "ตอบกลับ" ของ WhatsApp เอง ไม่มีการล็อกอินหรือ API · **ส่งได้เฉพาะตอนเจ้าของกดส่ง** (ฝั่งเนทีฟเป็นคนส่ง)
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
  });

  final int id;
  final String app;
  final String who;
  final String text;
  final DateTime at;

  /// สองสามบรรทัดก่อนหน้าในห้องเดียวกัน ("them: …" / "me: …") · ช่วยให้ร่างตรงเรื่อง
  final List<String> earlier;

  bool get business => app.endsWith('.w4b');

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
    );
  }
}

/// ผลหลังเจ้าของตอบกล่องถาม · [error]: skipped (ไม่ส่ง) · expired (แชทนั้นหายจากแจ้งเตือนแล้ว) · failed · empty
@immutable
class ChatAnswer {
  const ChatAnswer({required this.id, required this.sent, this.text = '', this.who = '', this.error});
  final int id;
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
    );
  }
}

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

  Future<({bool on, bool access})> status() async {
    final m = await _invoke<Map<Object?, Object?>>('status');
    return (on: m?['on'] == true, access: m?['access'] == true);
  }

  Future<void> setOn(bool on) => _invoke<bool>('setOn', {'on': on});

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
