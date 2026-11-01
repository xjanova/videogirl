/// ไมค์ของมายด์ที่อยู่ได้ตอนแอปไม่อยู่บนจอ — คู่กับ listen/ListenService.kt
///
/// ## ทำไม
///
/// เจ้าของ: "พอเราสั่งให้ทำอะไร มายด์ต้องยังคงรันเบื้องหลัง เธอต้องยังคงตอบพูดคุยกับฉันได้อยู่แม้หน้าจอจะไม่ใช่แอพแล้ว
/// เพราะเธออาจไปเปิดเมลหรือเปิดเว็บให้เรา เสียงโต้ตอบต้องคงได้ยินและยังรับฟังเราได้อยู่ คล้าย ๆ google assistant
/// ถ้าเราตั้งค่าไว้ ก็ใช้คำพิเศษเรียกเธอให้รับคำสั่งได้เช่นกัน เช่นน้องมายด์ เธอต้องขานทันทีที่รู้ว่าเรียก เช่น ขา หรือ คะ"
///
/// ## 🔴 เส้นเสียง
///
/// ฝั่งเนทีฟถือไมค์ตัวเดียว · ระหว่างรอคำเรียกเสียงไม่ถึง Dart ด้วยซ้ำ · ขานรับเล่นจากฝั่งเนทีฟ (Dart ตื่นช้ากว่านั้น) ·
/// เสียงเริ่มส่งมาที่นี่เมื่อเรียกแล้ว หรือเจ้าของแตะไมค์เอง
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'voice_chat.dart';

/// สถานะจากฝั่งเนทีฟ (ถามทุกครั้ง ไม่จำไว้ · เจ้าของปิดจากแจ้งเตือนได้โดยแอปไม่รู้)
class ListenStatus {
  const ListenStatus({
    required this.running,
    required this.wake,
    required this.taught,
    required this.word,
    required this.sensitivity,
    required this.paused,
    required this.replies,
  });

  factory ListenStatus.from(Map<Object?, Object?> m) => ListenStatus(
        running: m['running'] == true,
        wake: m['wake'] == true,
        taught: m['taught'] == true,
        word: m['word'] as String?,
        sensitivity: (m['sensitivity'] as int?) ?? 1,
        paused: m['paused'] == true,
        replies: (m['replies'] as int?) ?? 0,
      );

  static const off = ListenStatus(
      running: false, wake: false, taught: false, word: null, sensitivity: 1, paused: false, replies: 0);

  final bool running;

  /// เจ้าของเปิดสวิตช์รอฟังไว้
  final bool wake;
  final bool taught;
  final String? word;
  final int sensitivity;

  /// ปล่อยไมค์อยู่ (มีสาย / แอปอื่นใช้ไมค์)
  final bool paused;
  final int replies;
}

/// ผลหนึ่งรอบตอนสอนคำเรียก
class TeachEvent {
  const TeachEvent({required this.ok, required this.count, this.why, this.done = false});

  final bool ok;
  final int count;

  /// `length` เสียงสั้น/ยาวเกิน · `unlike` ไม่เหมือนตัวก่อน ๆ
  final String? why;
  final bool done;
}

class MindListen {
  MindListen({MethodChannel? channel, EventChannel? pcm})
      : _ch = channel ?? const MethodChannel('giggok/listen'),
        _pcm = pcm ?? const EventChannel('giggok/listen/pcm') {
    _ch.setMethodCallHandler(_onCall);
  }

  static final instance = MindListen();

  /// จำนวนตัวอย่างที่ต้องพูด · ต้องตรงกับ `WakeMatcher.SAMPLES_NEEDED`
  static const samples = 4;

  final MethodChannel _ch;
  final EventChannel _pcm;

  /// ถูกเรียกชื่อแล้ว ขานไปแล้ว · ไมค์ส่งเสียงรอที่ [stream]
  void Function()? onWake;

  /// เจ้าของกดปิดไมค์จากแจ้งเตือน
  void Function()? onStop;

  /// ไมค์ใช้ต่อไม่ได้แล้ว · บริการปิดตัวเอง
  void Function()? onMicLost;

  /// สถานะเปลี่ยนจากนอกแอป (กดหยุดรอฟังจากแจ้งเตือน)
  void Function()? onChanged;
  void Function(TeachEvent e)? onTeach;

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'wake':
        onWake?.call();
      case 'stop':
        onStop?.call();
      case 'wakeOff':
        onChanged?.call();
      case 'micLost':
        onChanged?.call();
        onMicLost?.call();
      case 'teach':
        final m = (call.arguments as Map?) ?? const {};
        onTeach?.call(TeachEvent(
          ok: m['ok'] == true,
          count: (m['count'] as int?) ?? 0,
          why: m['why'] as String?,
          done: m['done'] == true,
        ));
    }
    return null;
  }

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      debugPrint('ไมค์เบื้องหลัง: $method ไม่สำเร็จ — ${e.code}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<ListenStatus> status() async {
    final m = await _call<Map<Object?, Object?>>('status');
    return m == null ? ListenStatus.off : ListenStatus.from(m);
  }

  /// เครื่องล็อกอยู่ไหม · ตอบไม่ได้ = นับว่าล็อก (ทางปลอดภัยของการกดขั้นที่ย้อนไม่ได้)
  Future<bool> locked() async => await _call<bool>('locked') ?? true;

  /// เปิดไมค์ให้คุย · false = บริการไม่ขึ้น (ใช้ไมค์แบบต้องอยู่บนจอแทน)
  Future<bool> open() async {
    final ok = await _call<bool>('open').timeout(const Duration(seconds: 3), onTimeout: () => false);
    return ok ?? false;
  }

  Future<void> close() => _call<bool>('close');

  /// รับช่วงการปลุกแล้ว · ไม่เรียกภายในไม่กี่วินาที ฝั่งเนทีฟถือว่าไม่มีใครฟังแล้วกลับไปรอ
  Future<void> claim() => _call<bool>('claim');
  Future<void> sync() => _call<bool>('sync');
  Future<void> setWake(bool on) => _call<bool>('setWake', {'on': on});
  Future<void> setSensitivity(int level) => _call<bool>('setSensitivity', {'level': level});
  Future<void> setLabel(String word) => _call<bool>('setLabel', {'word': word});
  Future<void> forget() => _call<bool>('forget');
  Future<bool> teachStart() async => await _call<bool>('teachStart') ?? false;
  Future<void> teachStop() => _call<bool>('teachStop');
  Future<void> playReply() => _call<bool>('playReply');

  Future<void> setReplies(List<({Uint8List bytes, String mime})> clips) => _call<bool>('setReplies', {
        'clips': [
          for (final c in clips) {'bytes': c.bytes, 'ext': c.mime.contains('wav') ? 'wav' : 'mp3'},
        ],
      });

  /// PCM 16 บิต 16 kHz ช่องเดียว ทีละ 100 มิลลิวินาที · มีเสียงค้าง (เจ้าของพูดต่อจากคำเรียก) ได้ก่อน
  Stream<Uint8List> get stream => _pcm.receiveBroadcastStream().map((e) => e as Uint8List);
}

/// ไมค์ของคุยต่อเนื่อง · ใช้บริการเบื้องหลังเมื่อได้ · ไม่ได้ = ไมค์แบบเดิมที่อยู่ได้เฉพาะบนจอ
class ServiceChatMic implements ChatMic {
  ServiceChatMic({MindListen? listen, ChatMic? fallback})
      : _given = listen,
        _fallback = fallback ?? RecordChatMic();

  /// แตะตอนใช้จริงเท่านั้น · [MindListen] ผูก MethodChannel ตั้งแต่เกิด
  final MindListen? _given;
  MindListen get _listen => _given ?? MindListen.instance;
  final ChatMic _fallback;
  bool _onService = false;
  bool _usedFallback = false;

  @override
  bool get survivesBackground => _onService;

  @override
  Future<Stream<Uint8List>> open() async {
    if (await _listen.open()) {
      _onService = true;
      return _listen.stream;
    }
    _onService = false;
    _usedFallback = true;
    return _fallback.open();
  }

  @override
  Future<void> close() async {
    _onService = false;
    // เรียกเสมอ · รอบที่ถูกปลุกด้วยคำเรียก บริการถือไมค์อยู่แล้วแม้ [open] ยังไม่ถูกเรียก (ต่อเซิร์ฟเวอร์ไม่ติด)
    await _listen.close();
    if (_usedFallback) {
      _usedFallback = false;
      await _fallback.close();
    }
  }

  @override
  void dispose() => _fallback.dispose();
}
