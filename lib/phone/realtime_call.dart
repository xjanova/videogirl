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

import 'package:flutter/foundation.dart';

import 'voice_session.dart';

export 'voice_session.dart';

class RealtimeCall extends VoiceSession {
  RealtimeCall({
    required this.apiKey,
    required this.instructions,
    required this.greeting,
    this.model = defaultModel,
    this.voice = 'marin',
    this.language = 'th',
    this.transcriptionHint = '',
    this.turnDetection,
    super.languageReminder,
    super.lookup,
    super.connect,
  });

  /// จังหวะจบตา · null = server_vad แบบในสาย (เงียบ 600 มิลลิวินาที = จบ) ·
  /// แชทด้วยเสียงใช้ semantic_vad ที่ฟังว่าประโยคจบหรือยัง (ดู RealtimeChat)
  final Map<String, Object?>? turnDetection;

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

  /// บริบทให้ตัวถอดเสียงคู่สาย (MindPersona.callTranscriptionHint) · ว่าง = ไม่ส่ง
  final String transcriptionHint;

  String? _audioItem;
  int _audioContentIndex = 0;
  int _itemAudioBytes = 0;
  final _interruptedItems = <String>{};

  RtSocket? _socket;
  StreamSubscription<Object?>? _sub;
  bool _closed = false;
  @override
  bool get connected => _socket != null && !_closed;

  @override
  Future<void> start() async {
    final url = Uri.parse('wss://api.openai.com/v1/realtime?model=$model');
    final s = await connectSocket(url, {'Authorization': 'Bearer $apiKey'});
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
            'transcription': {
              'model': 'gpt-4o-mini-transcribe',
              'language': language,
              if (transcriptionHint.isNotEmpty) 'prompt': transcriptionHint,
            },
            // เสียงจากลำโพงมือถือมีเสียงห้องปน · เกณฑ์สูงกว่าค่าตั้งต้นเล็กน้อย
            // หยุด 600 มิลลิวินาที = จบตา · ตอบไวแต่ไม่ตัดคนหยุดหายใจ
            'turn_detection': turnDetection ??
                {
                  'type': 'server_vad',
                  'threshold': 0.55,
                  'prefix_padding_ms': 300,
                  'silence_duration_ms': 600,
                  'create_response': true,
                  'interrupt_response': fullDuplex,
                },
          },
          'output': {
            'format': {'type': 'audio/pcm', 'rate': 24000},
            'voice': voices.contains(voice) ? voice : 'marin',
          },
        },
        // วางสายเอง / แจ้งเจ้าของเรื่องด่วน · prompt บอกว่าเรียกเมื่อไหร่ (MindPersona.phoneStyle)
        'tools': sessionTools,
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

  @override
  void nudge(String instructions) {
    if (!connected) return;
    _send({
      'type': 'response.create',
      'response': {
        'output_modalities': ['audio'],
        // 🔴 คำสั่งของคำตอบนี้แทนที่ของทั้งเซสชัน · ส่งเดี่ยว ๆ = เธอลืมเรื่องที่ต้องโทรมาแจ้ง
        'instructions': '${this.instructions}\n\n=== Right now ===\n$instructions',
      },
    });
  }

  final _resampler = Resampler16to24();

  /// อีกฝ่ายเริ่มพูด · คุยกับเจ้าของใช้เป็นจังหวะส่งภาพ (ดู VoiceChat)
  void Function()? onSpeechStart;

  @override
  bool get callerTalking => _callerTalking;

  @override
  void sendMic(Uint8List pcm16k) {
    if (!connected || pcm16k.isEmpty) return;
    final up = _resampler.convert(pcm16k);
    if (up.isEmpty) return;
    _send({'type': 'input_audio_buffer.append', 'audio': base64Encode(up)});
  }

  /// ภาพหนึ่งใบเข้าบทสนทนา · ไม่สั่งให้ตอบ · ใช้กับคำพูดที่ตามมา · ดู MindEyes
  void sendImage(Uint8List jpeg) {
    if (!connected || jpeg.isEmpty) return;
    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_image', 'image_url': 'data:image/jpeg;base64,${base64Encode(jpeg)}'},
        ],
      },
    });
  }

  /// ข้อความระบบ
  @override
  void remind(String text) {
    if (!connected || text.trim().isEmpty) return;
    _send({
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'system',
        'content': [
          {'type': 'input_text', 'text': text},
        ],
      },
    });
  }

  /// ข้อความระบบ แล้วให้เธอพูดถึงมัน · เธอตอบอยู่ = รอคิวจนจบ · คนโทรพูดอยู่ = ไม่สั่ง
  /// (เซิร์ฟเวอร์ตอบเองเมื่อเขาพูดจบ และเห็นข้อความนี้ในคำตอบนั้น)
  @override
  void announce(String text) {
    if (!connected || text.trim().isEmpty) return;
    remind(text);
    if (!_callerTalking) _respond();
  }

  @override
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
        _responding = true;
        _lastCreate = null;
        _herText.clear();
        _audioItem = null;
        _itemAudioBytes = 0;
        onResponseStart?.call();
      case 'input_audio_buffer.speech_started':
        _callerTalking = true;
        if (fullDuplex) unawaited(_interruptPlayback());
        onSpeechStart?.call();
      case 'input_audio_buffer.speech_stopped':
        _callerTalking = false;
      case 'response.output_audio.delta':
        final item = e['item_id'] as String?;
        if (item != null && _interruptedItems.contains(item)) return;
        if (item != null && item != _audioItem) {
          _audioItem = item;
          _itemAudioBytes = 0;
        }
        _audioContentIndex = e['content_index'] as int? ?? 0;
        final b64 = e['delta'];
        if (b64 is String && b64.isNotEmpty) {
          try {
            final pcm = base64Decode(b64);
            _itemAudioBytes += pcm.length;
            onAudio?.call(pcm);
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
        if (t.isNotEmpty) {
          holdLanguage(t);
          onHerText?.call(t);
        }
      case 'conversation.item.input_audio_transcription.completed':
        final t = (e['transcript'] as String?)?.trim() ?? '';
        if (t.isNotEmpty) {
          heardCaller(t);
          onCallerText?.call(t);
        }
      case 'response.output_item.done':
        final item = e['item'];
        if (item is Map && item['type'] == 'function_call') runTool(item.cast<String, Object?>());
      case 'response.done':
        _responding = false;
        onResponseDone?.call();
        // คำตอบที่รอคิวอยู่ (ผลค้น/แจ้งเจ้าของแล้ว) · ส่งตอนนี้ได้แล้ว
        final next = _queued;
        _queued = null;
        if (next != null) _respond(next);
      case 'error':
        final err = e['error'];
        if (err is Map && err['code'] == 'conversation_already_has_active_response') _onBusyRejected();
        final msg = err is Map ? '${err['code'] ?? err['type'] ?? ''}: ${err['message'] ?? ''}' : '$err';
        debugPrint('realtime: $msg');
        onError?.call(msg);
    }
  }

  /// เจ้าของแตะให้เธอหยุดพูด · ยกเลิกคำตอบที่ยังสร้างอยู่ ตัดเสียงที่ค้าง แล้วบอกเซิร์ฟเวอร์ว่าเธอพูดถึงไหน
  /// (ไม่บอก = เธอคิดว่าพูดครบแล้ว และตาถัดไปอ้างถึงประโยคที่เจ้าของไม่ได้ยิน)
  Future<void> interrupt() async {
    if (!connected) return;
    if (_responding) _send({'type': 'response.cancel'});
    _queued = null;
    await _interruptPlayback();
  }

  Future<void> _interruptPlayback() async {
    final item = _audioItem;
    if (item == null || _interruptedItems.contains(item)) return;
    _interruptedItems.add(item);
    // Bound retained IDs even on exceptionally long calls.
    if (_interruptedItems.length > 64) _interruptedItems.remove(_interruptedItems.first);
    final contentIndex = _audioContentIndex;
    final totalMs = _itemAudioBytes ~/ 48;
    final pendingMs = await onInterruption?.call() ?? totalMs;
    if (!connected) return;
    _send({
      'type': 'conversation.item.truncate',
      'item_id': item,
      'content_index': contentIndex,
      'audio_end_ms': (totalMs - pendingMs).clamp(0, totalMs),
    });
  }

  // ── คิวคำตอบ ─────────────────────────────────────────────
  //
  // 🔴 ส่ง response.create ตอนเธอยังตอบค้างอยู่ = เซิร์ฟเวอร์ปัดทิ้ง
  // (conversation_already_has_active_response) แล้วเธอเงียบทั้งที่ผลค้นมาแล้ว ·
  // ผลเครื่องมือมาถึงตอน output_item.done ซึ่งมาก่อน response.done ของคำตอบเดียวกันเสมอ

  bool _responding = false, _callerTalking = false;
  Map<String, Object?>? _queued, _lastCreate;

  /// ให้เธอตอบ · ยังตอบค้างอยู่ = รอคิวจนจบ (คิวเดียว · คำตอบจากผลจริงชนะคำชวนคุย)
  void _respond([Map<String, Object?> response = const {}]) {
    if (_closed) return;
    if (_responding) {
      if (_queued == null || response.isEmpty) _queued = response;
      return;
    }
    _lastCreate = response;
    _send({'type': 'response.create', if (response.isNotEmpty) 'response': response});
  }

  /// เซิร์ฟเวอร์เริ่มตอบเองตัดหน้า (คนโทรพูดจบพอดี) แล้วปัดของเราทิ้ง · ผลค้น/แจ้งแล้ว = ต่อคิวไว้
  /// ตอบหลังตัวนั้นจบ · คำชวนคุย = ทิ้ง (เธอพูดอยู่แล้ว)
  void _onBusyRejected() {
    final last = _lastCreate;
    _lastCreate = null;
    if (last != null && last.isEmpty) _queued ??= const {};
  }

  @override
  void toolOutput(String callId, String output) {
    _send({
      'type': 'conversation.item.create',
      'item': {'type': 'function_call_output', 'call_id': callId, 'output': output},
    });
    // เธอยังพูดคำชวนคุยค้างอยู่ = รอให้จบประโยคก่อน ไม่ตัดกลางคำ
    _respond();
  }

  @override
  void stillLookingUp({bool owner = false}) {
    // เธอพูดอยู่ หรือคนโทรกำลังพูด = ไม่เงียบอยู่แล้ว ไม่ต้องแทรก
    if (_closed || _responding || _callerTalking) return;
    debugPrint(owner ? 'call: ยังรอเจ้าของตอบ · ให้เธอชวนคุยระหว่างรอ' : 'call: ค้นนานเกิน 2 วิ · ให้เธอชวนคุยระหว่างรอ');
    final now = owner
        ? VoiceSession.ownerWaitLine
        : 'You are still looking this up and the result is not back yet. Keep the caller company in ONE short, '
            'warm sentence, like a real person on the phone: say you are still checking, and if their question was '
            'broad, ask one short detail that would help (which product, which branch, which day). Do not answer '
            'the question itself yet and do not repeat what you said a moment ago.';
    _respond({
      'output_modalities': ['audio'],
      // คำสั่งของคำตอบนี้แทนที่ของทั้งเซสชัน · ต่อท้ายของเดิม บุคลิกกับภาษาจะได้ไม่หลุด
      'instructions': '$instructions\n\n=== Right now ===\n$now',
      'tool_choice': 'none',
    });
  }

  @override
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
