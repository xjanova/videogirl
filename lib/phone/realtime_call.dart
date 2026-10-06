/// คุยสดในสายผ่าน OpenAI Realtime — ฟังไปตอบไป ไม่ต้องรอทีละขั้น
///
/// ## ทำไม
///
/// เจ้าของ: "มันควรฟังแล้วโต้ตอบได้เหมือนแอป ChatGPT โต้ตอบสดๆ" · "ต้องทำ real time
/// พูดคุยเลย ถ้าตั้งค่าเป็น open ai" · ทางเดิมทำทีละขั้น (รอคู่สายหยุด → ถอดเสียง →
/// คิด → สังเคราะห์เสียงทั้งประโยค → เล่น) รวมกันหลายวินาทีต่อหนึ่งตา · Realtime ส่ง
/// เสียงเข้า-ออกเป็นสตรีมบน WebSocket เดียว เซิร์ฟเวอร์จับจังหวะพูดเอง เสียงเธอเริ่ม
/// มาภายในเสี้ยววินาทีหลังคู่สายหยุด
///
/// ## 🔴 พูดทีละฝั่ง (half-duplex) โดยตั้งใจ
///
/// ในสาย เสียงเธอกับเสียงคู่สายออก**ลำโพงเดียวกัน**แล้วเข้า**ไมค์เดียวกัน** (Android
/// ไม่ให้แตะเสียงในสายตรง ๆ · ดู docs/telephony.md) · ส่งไมค์ตอนเธอพูด = เซิร์ฟเวอร์
/// ได้ยินเสียงเธอเองแล้วตัดบทตัวเอง · ผู้เรียก ([CallSession]) จึงหยุดส่งไมค์ระหว่างที่
/// เสียงเธอยังออกลำโพงอยู่ · คู่สายแทรกกลางประโยคเธอไม่ได้ (เหมือนวิทยุสื่อสาร)
///
/// ## 🔴 ส่งอะไรออกไป
///
/// เสียงในสาย + system prompt ของสาย (ไม่มีข้อมูลส่วนตัวของเจ้าของ — MindState.callPrompt)
/// ไปที่ OpenAI ด้วยคีย์ของเจ้าของเอง · ที่เดียวกับที่ทางเดิมส่ง (ถอดเสียง/คิด/เสียงพูด)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// ท่อ WebSocket ที่ใช้จริง · แยกเป็น interface เพื่อเทสต์โดยไม่ต่อเน็ต
abstract interface class RtSocket {
  Stream<Object?> get messages;
  void send(String text);
  Future<void> close();
}

class _IoSocket implements RtSocket {
  _IoSocket(this._ws);
  final WebSocket _ws;
  @override
  Stream<Object?> get messages => _ws;
  @override
  void send(String text) => _ws.add(text);
  @override
  Future<void> close() => _ws.close();
}

typedef RtConnect = Future<RtSocket> Function(Uri url, Map<String, String> headers);

Future<RtSocket> _ioConnect(Uri url, Map<String, String> headers) async =>
    _IoSocket(await WebSocket.connect(url.toString(), headers: headers)
        .timeout(const Duration(seconds: 10)));

class RealtimeCall {
  RealtimeCall({
    required this.apiKey,
    required this.instructions,
    required this.greeting,
    this.model = defaultModel,
    this.voice = 'marin',
    this.language = 'th',
    RtConnect? connect,
  }) : _connect = connect ?? _ioConnect;

  /// รุ่นในตัวอย่างของเอกสาร OpenAI (ตรวจ 2026-10-06)
  static const defaultModel = 'gpt-realtime-2.1';

  /// เสียงที่ Realtime รู้จัก · เสียงที่ตั้งไว้ไม่อยู่ในนี้ = ใช้ marin
  static const voices = {'alloy', 'ash', 'ballad', 'coral', 'echo', 'sage', 'shimmer', 'verse', 'marin', 'cedar'};

  final String apiKey;
  final String instructions;
  final String greeting;
  final String model;
  final String voice;
  final String language;
  final RtConnect _connect;

  /// เสียงเธอ PCM 16 บิต 24 kHz · ส่งต่อให้ลำโพงทันที
  void Function(Uint8List pcm24k)? onAudio;

  /// เธอเริ่มตอบ (ก่อนเสียงชิ้นแรกจะมา) · ผู้เรียกหยุดส่งไมค์ได้ตั้งแต่ตอนนี้
  void Function()? onResponseStart;

  /// เธอตอบจบ (เสียงอาจยังค้างในลำโพง ผู้เรียกดูเองว่าเล่นหมดหรือยัง)
  void Function()? onResponseDone;

  /// ประโยคเต็มของเธอ / ของคู่สาย — ลงบทสนทนาและบันทึกสาย
  void Function(String text)? onHerText;
  void Function(String text)? onCallerText;

  /// ท่อหลุด / เซิร์ฟเวอร์แจ้งข้อผิดพลาด
  void Function(String message)? onError;

  /// เธอลากับคู่สายแล้ว ขอวางสาย · ผู้เรียกวางเมื่อเสียงลาออกลำโพงจบ
  void Function()? onEndCall;

  /// เรื่องด่วน · ผู้เรียกแจ้งเตือนเจ้าของ
  void Function(String reason)? onAlertOwner;

  RtSocket? _socket;
  StreamSubscription<Object?>? _sub;
  bool _closed = false;
  bool get connected => _socket != null && !_closed;

  /// ต่อ ตั้งค่าเซสชัน แล้วให้เธอทักก่อน · โยนเมื่อต่อไม่ได้ (ผู้เรียกตกไปทางเดิม)
  Future<void> start() async {
    final url = Uri.parse('wss://api.openai.com/v1/realtime?model=$model');
    final s = await _connect(url, {'Authorization': 'Bearer $apiKey'});
    if (_closed) {
      await s.close();
      return;
    }
    _socket = s;
    _sub = s.messages.listen(_onMessage, onError: (Object e) {
      onError?.call('socket: ${e.runtimeType}');
      _closed = true;
    }, onDone: () {
      if (!_closed) onError?.call('socket closed');
      _closed = true;
    });

    _send({
      'type': 'session.update',
      'session': {
        'type': 'realtime',
        'model': model,
        'instructions': instructions,
        'output_modalities': ['audio'],
        'audio': {
          'input': {
            'format': {'type': 'audio/pcm', 'rate': 24000},
            'transcription': {'model': 'gpt-4o-mini-transcribe', 'language': language},
            // เสียงจากลำโพงมือถือมีเสียงห้องปน · เกณฑ์สูงกว่าค่าตั้งต้นเล็กน้อย
            // หยุด 600 มิลลิวินาที = จบตา · ตอบไวแต่ไม่ตัดคนหยุดหายใจ
            'turn_detection': {
              'type': 'server_vad',
              'threshold': 0.55,
              'prefix_padding_ms': 300,
              'silence_duration_ms': 600,
              'create_response': true,
              'interrupt_response': false,
            },
          },
          'output': {
            'format': {'type': 'audio/pcm', 'rate': 24000},
            'voice': voices.contains(voice) ? voice : 'marin',
          },
        },
        // วางสายเอง / แจ้งเจ้าของเรื่องด่วน · prompt บอกว่าเรียกเมื่อไหร่ (MindPersona.phoneStyle)
        'tools': [
          {
            'type': 'function',
            'name': 'end_call',
            'description': 'Hang up the phone call. Only after you and the caller have both said goodbye.',
            'parameters': {'type': 'object', 'properties': <String, Object?>{}, 'required': <String>[]},
          },
          {
            'type': 'function',
            'name': 'alert_owner',
            'description': 'Send the owner an urgent notification about this call right now.',
            'parameters': {
              'type': 'object',
              'properties': {
                'reason': {'type': 'string', 'description': 'One short sentence: who is calling and why it is urgent.'},
              },
              'required': ['reason'],
            },
          },
        ],
        'tool_choice': 'auto',
      },
    });
    // รับสาย = เธอทักก่อน · ประโยคทักกำหนดตายตัว (มีเรื่องบันทึกเสียงอยู่ในนั้น ต้องพูดครบ)
    // โทรออก (ไม่มีคำทัก) = รอปลายสาย "ฮัลโหล" ก่อน · เซิร์ฟเวอร์ตอบเองเมื่อเขาพูดจบ
    if (greeting.trim().isNotEmpty) {
      _send({
        'type': 'response.create',
        'response': {
          'output_modalities': ['audio'],
          'instructions': 'Greet the caller now, saying exactly this and nothing else: $greeting',
        },
      });
    }
  }

  /// ให้เธอเริ่มพูดตามคำสั่งนี้ (เช่น ปลายสายรับแล้วเงียบ)
  void nudge(String instructions) {
    if (!connected) return;
    _send({
      'type': 'response.create',
      'response': {'output_modalities': ['audio'], 'instructions': instructions},
    });
  }

  final _resampler = Resampler16to24();

  /// ไมค์ 16 kHz → 24 kHz → ส่ง · ผู้เรียกกั้นเองตอนเธอพูด
  void sendMic(Uint8List pcm16k) {
    if (!connected || pcm16k.isEmpty) return;
    final up = _resampler.convert(pcm16k);
    if (up.isEmpty) return;
    _send({'type': 'input_audio_buffer.append', 'audio': base64Encode(up)});
  }

  /// เจ้าของพิมพ์ให้เธอพูดประโยคนี้เข้าสาย · พูดตรงตามนั้น ไม่แต่งเพิ่ม
  void say(String text) {
    if (!connected || text.trim().isEmpty) return;
    _send({
      'type': 'response.create',
      'response': {
        'output_modalities': ['audio'],
        'instructions': 'Say exactly this to the caller, in the same language, and nothing else: ${text.trim()}',
      },
    });
  }

  void _send(Map<String, Object?> event) {
    final s = _socket;
    if (s == null || _closed) return;
    try {
      s.send(jsonEncode(event));
    } on Object catch (e) {
      onError?.call('send: ${e.runtimeType}');
    }
  }

  final _herText = StringBuffer();

  void _onMessage(Object? raw) {
    if (raw is! String) return;
    final Map<String, Object?> e;
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return;
      e = d.cast<String, Object?>();
    } on FormatException {
      return;
    }
    switch (e['type']) {
      case 'response.created':
        _herText.clear();
        onResponseStart?.call();
      case 'response.output_audio.delta':
        final b64 = e['delta'];
        if (b64 is String && b64.isNotEmpty) {
          try {
            onAudio?.call(base64Decode(b64));
          } on FormatException {
            // ชิ้นเสีย ข้ามไป · ดีกว่าหยุดทั้งประโยค
          }
        }
      case 'response.output_audio_transcript.delta':
        final d = e['delta'];
        if (d is String) _herText.write(d);
      case 'response.output_audio_transcript.done':
        final t = (e['transcript'] as String?)?.trim() ?? _herText.toString().trim();
        _herText.clear();
        if (t.isNotEmpty) onHerText?.call(t);
      case 'conversation.item.input_audio_transcription.completed':
        final t = (e['transcript'] as String?)?.trim() ?? '';
        if (t.isNotEmpty) onCallerText?.call(t);
      case 'response.output_item.done':
        final item = e['item'];
        if (item is Map && item['type'] == 'function_call') _onTool(item.cast<String, Object?>());
      case 'response.done':
        onResponseDone?.call();
      case 'error':
        final err = e['error'];
        final msg = err is Map ? '${err['code'] ?? err['type'] ?? ''}: ${err['message'] ?? ''}' : '$err';
        debugPrint('realtime: $msg');
        onError?.call(msg);
    }
  }

  bool _alerted = false;

  void _onTool(Map<String, Object?> item) {
    final callId = item['call_id'];
    switch (item['name']) {
      case 'end_call':
        onEndCall?.call();
      case 'alert_owner':
        var reason = '';
        try {
          final a = jsonDecode('${item['arguments'] ?? '{}'}');
          if (a is Map) reason = '${a['reason'] ?? ''}'.trim();
        } on FormatException {
          // อาร์กิวเมนต์เสีย · ยังแจ้งได้ แค่ไม่มีเหตุผล
        }
        // 🔴 แจ้งครั้งเดียวต่อสาย · คู่สายพูดว่า "ด่วน" ซ้ำ ๆ ต้องไม่กลายเป็นแจ้งเตือนรัว
        if (!_alerted) {
          _alerted = true;
          onAlertOwner?.call(reason);
        }
        // บอกโมเดลว่าแจ้งแล้ว ให้พูดต่อ ("แจ้งเจ้าของให้แล้วนะคะ")
        if (callId is String) {
          _send({
            'type': 'conversation.item.create',
            'item': {'type': 'function_call_output', 'call_id': callId, 'output': '{"notified":true}'},
          });
          _send({'type': 'response.create'});
        }
    }
  }

  Future<void> close() async {
    if (_closed && _socket == null) return;
    _closed = true;
    await _sub?.cancel();
    _sub = null;
    final s = _socket;
    _socket = null;
    try {
      await s?.close();
    } on Object {
      // ปิดซ้ำ / หลุดไปแล้ว — ไม่ใช่เรื่องที่ต้องพัง
    }
  }

  @visibleForTesting
  void debugReceive(String raw) => _onMessage(raw);
}

/// แปลงเสียง PCM 16 บิตช่องเดียวจาก 16 kHz เป็น 24 kHz (ประมาณเส้นตรง)
///
/// ไมค์ของสายอัดที่ 16 kHz (ทางเดิมที่พิสูจน์แล้วบนเครื่องจริง) แต่ Realtime รับ 24 kHz ·
/// จำตัวอย่างสุดท้ายและจังหวะข้ามก้อน ไม่งั้นรอยต่อทุก 20–100 มิลลิวินาทีจะเป็นเสียงแตก
class Resampler16to24 {
  /// ตำแหน่งตัวอย่างขาออกถัดไป ในหน่วยตัวอย่างขาเข้า นับจากต้นก้อนปัจจุบัน ·
  /// ติดลบได้ถึง -1 = อยู่ระหว่างตัวสุดท้ายของก้อนก่อน ([_carry]) กับตัวแรกของก้อนนี้
  double _t = 0;
  int? _carry;

  static const _step = 16000 / 24000;

  Uint8List convert(Uint8List pcm) {
    final n = pcm.lengthInBytes ~/ 2;
    if (n == 0) return Uint8List(0);
    final src = ByteData.sublistView(pcm);
    int x(int i) => i < 0 ? (_carry ?? src.getInt16(0, Endian.little)) : src.getInt16(i * 2, Endian.little);

    final out = ByteData(((n + 2) * 3) ~/ 2 * 2);
    var count = 0;
    var t = _t;
    while (t <= n - 1) {
      final i = t.floor();
      final f = t - i;
      final a = x(i);
      final v = f == 0 ? a : a + (x(i + 1) - a) * f;
      out.setInt16(count * 2, v.round().clamp(-32768, 32767), Endian.little);
      count++;
      t += _step;
    }
    _t = t - n;
    _carry = x(n - 1);
    return out.buffer.asUint8List(0, count * 2);
  }
}
