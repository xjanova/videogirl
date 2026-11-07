/// เจ้าของสั่งให้เธอทักใครก่อน: `[[ส่งแชท: ใคร | แอป | ข้อความ]]`
///
/// เจ้าของ (2026-11-07): "เพิ่มเครื่องมือ แขนขา หูตา ให้เธอ มากที่สุด" · ตอบแชทที่ทักมาแล้ว ต่อไปคือทักไปเองเมื่อเจ้าของสั่ง
///
/// 🔒 ไม่มีทางส่งตรง · แท็กนี้กลายเป็นงานของมือ (PhoneAgent) แล้วปุ่ม "ส่ง" ผ่านด่าน PhonePolicy + กล่องถามของเจ้าของ
/// (หรืออนุญาตถาวรที่เจ้าของกดเองไว้) เหมือนงานในเครื่องอื่น ๆ · แท็กจากสมองใช้ได้เฉพาะเมื่อคำของเจ้าของเองขอให้ส่ง
/// ([SendWords]) · ข้อความที่ทักมาจากคนนอกไม่มีทางสร้างแท็กนี้ (cleanChatDraft ตัดแท็กทิ้ง)
library;

import 'package:flutter/foundation.dart';

/// ส่งหาใคร ทางไหน ว่าอะไร (ตรงตัว)
@immutable
class ChatSendOrder {
  const ChatSendOrder({required this.who, required this.app, required this.text});
  final String who;
  final String app;
  final String text;
}

abstract final class ChatSendTag {
  static final _tag = RegExp(
    r'\[\[\s*(ส่งแชท|ส่งข้อความ|ทักแชท|send chat|send message)\s*[:：]\s*([^\]\n|]{1,80})\|\s*([^\]\n|]{1,40})\|\s*([^\]\n]{1,1000})\]\]',
    caseSensitive: false,
  );

  /// [text] = ข้อความที่เหลือ (ตัดแท็กออก) · [order] = งานส่ง (null = ไม่มีแท็ก หรือช่องไหนว่าง)
  static ({String text, ChatSendOrder? order}) parse(String reply) {
    final m = _tag.firstMatch(reply);
    final text = reply.replaceAll(_tag, '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    if (m == null) return (text: text, order: null);
    final who = m.group(2)!.trim(), app = m.group(3)!.trim();
    var body = m.group(4)!.trim();
    const quotes = ['"', '“', '”', '«', '»'];
    while (body.length >= 2 && quotes.contains(body[0]) && quotes.contains(body[body.length - 1])) {
      body = body.substring(1, body.length - 1).trim();
    }
    if (who.isEmpty || app.isEmpty || body.isEmpty) return (text: text, order: null);
    return (text: text, order: ChatSendOrder(who: who, app: app, text: body));
  }
}

/// คำของเจ้าของที่ขอให้ส่ง/ทัก/บอกใคร · ตัดสินในเครื่อง · ไม่มีคำพวกนี้ = สมองคิดเอง หรือถูกเว็บ/ข้อความอื่นสั่ง
abstract final class SendWords {
  static final _ask = RegExp(
    r'ส่ง|ทัก|บอก|แจ้ง|ฝาก|ถาม|ตอบ|แชท|แชต|ไลน์|ข้อความ|เมสเสจ|อวยพร|'
    r'\b(send|text|message|msg|tell|ask|reply|dm|ping|let\s+\S+\s+know|whatsapp|line)\b',
    caseSensitive: false,
  );

  static bool asks(String ownerText) => _ask.hasMatch(ownerText);
}
