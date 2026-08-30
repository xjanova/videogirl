/// สายโทรเข้า — เธอต้องรู้ว่าใครโทรมาถึงจะเป็นเลขาได้
///
/// ## 🔴 เพดานของ Android ที่ต้องรู้ก่อนอ่านต่อ
///
/// **รับสายได้ แต่พูดในสายไม่ได้** `TelecomManager.acceptRingingCall()`
/// รับสายได้จริง แต่**เสียงของสายเป็นทางเดินที่แอปธรรมดาแตะไม่ได้** —
/// ป้อนเสียงเธอเข้าไปหรือดึงเสียงคู่สายออกมาไม่ได้เลย ถ้าไม่ได้เป็นแอป
/// โทรศัพท์หลักของเครื่อง (InCallService + ผู้ใช้ตั้ง default dialer เอง)
///
/// ที่นี่จึงทำได้ถึงแค่ **รู้ว่าใครโทรมา จดไว้ และรับ/วางสายได้**
/// ส่วนการคุยแทนต้องตัดสินใจเรื่อง default dialer ก่อน · ดู CallBridge.kt
///
/// **เบอร์ที่โทรเข้ามักว่างเปล่า** ตั้งแต่ Android 9 ระบบไม่ส่งเบอร์มากับ
/// สัญญาณสายเข้าถ้าไม่มี READ_CALL_LOG และต่อให้มีก็ยังว่างได้บางเครื่อง
/// โดยไม่มี error อะไรบอก · ทางที่เชื่อถือได้คืออ่านจากบันทึกการโทรหลังสายจบ
/// ซึ่งเป็นสิ่งที่ [refresh] ทำทุกครั้งที่สายวางลง
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../journal/mind_journal.dart';
import '../system/permissions.dart';

/// ชนิดของสาย — ตรงกับค่าใน CallLog.Calls ของ Android
enum CallType {
  incoming(1),
  outgoing(2),
  missed(3),
  rejected(5),
  unknown(-1);

  const CallType(this.code);
  final int code;

  static CallType parse(Object? v) {
    final n = (v as num?)?.toInt();
    return CallType.values.firstWhere((t) => t.code == n,
        orElse: () => CallType.unknown);
  }
}

/// สถานะสายตอนนี้ — ตรงกับ TelephonyManager.CALL_STATE_*
enum CallState {
  idle(0),
  ringing(1),
  offHook(2);

  const CallState(this.code);
  final int code;

  static CallState parse(Object? v) {
    final n = (v as num?)?.toInt();
    return CallState.values.firstWhere((s) => s.code == n,
        orElse: () => CallState.idle);
  }
}

@immutable
class CallEvent {
  const CallEvent({
    required this.id,
    required this.at,
    required this.type,
    this.number,
    this.name,
    this.seconds = 0,
  });

  final int id;
  final DateTime at;
  final CallType type;
  final String? number;

  /// ชื่อในสมุดโทรศัพท์ · null = เบอร์ที่ไม่รู้จัก หรือยังไม่ได้ให้สิทธิ์
  final String? name;

  final int seconds;

  /// สิ่งที่เอาไปแสดง — ชื่อก่อน แล้วค่อยเบอร์
  ///
  /// เบอร์ที่ไม่มีทั้งชื่อทั้งเบอร์เกิดขึ้นได้จริง (สายที่ซ่อนเบอร์)
  /// ผู้เรียกต้องเผื่อค่าว่างเสมอ
  String get who => (name?.isNotEmpty ?? false) ? name! : (number ?? '');

  static CallEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final at = (raw['at'] as num?)?.toInt();
    if (at == null) return null;

    final name = (raw['name'] as String?)?.trim();
    final number = (raw['number'] as String?)?.trim();
    return CallEvent(
      id: (raw['id'] as num?)?.toInt() ?? at,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      type: CallType.parse(raw['type']),
      number: (number?.isEmpty ?? true) ? null : number,
      name: (name?.isEmpty ?? true) ? null : name,
      seconds: (raw['seconds'] as num?)?.toInt() ?? 0,
    );
  }
}

enum CallStage { idle, loading, ready, denied, failed }

class CallWatch extends ChangeNotifier {
  CallWatch({MindPermissions? permissions, MindJournal? journal})
      : _perms = permissions ?? MindPermissions(),
        _journal = journal;

  final MindPermissions _perms;
  MindJournal? _journal;

  void attachJournal(MindJournal j) => _journal = j;

  CallStage _stage = CallStage.idle;
  CallStage get stage => _stage;

  final List<CallEvent> _recent = [];
  List<CallEvent> get recent => List.unmodifiable(_recent);

  CallState _state = CallState.idle;
  CallState get state => _state;

  /// ใครกำลังโทรเข้าอยู่ตอนนี้ · null เมื่อไม่มีสาย
  String? _ringingWho;
  String? get ringingWho => _ringingWho;

  bool get ringing => _state == CallState.ringing;

  /// เริ่มเฝ้าสาย · ต้องเรียกครั้งเดียวตอนเปิดแอป
  ///
  /// การเฝ้าไม่ต้องใช้สิทธิ์อะไรเลย (รู้แค่ว่ามีสาย ไม่รู้ว่าใคร)
  /// เบอร์กับชื่อถึงจะต้องใช้ · จึงเริ่มเฝ้าได้เสมอ แล้วค่อยเติมรายละเอียด
  /// เมื่อได้สิทธิ์ ดีกว่าไม่เฝ้าเลยจนกว่าจะได้สิทธิ์ครบ
  Future<void> start() async {
    kSystemChannel.setMethodCallHandler(_onNative);
    try {
      await kSystemChannel.invokeMethod<bool>('watchCalls');
      debugPrint('call: เริ่มเฝ้าสายแล้ว');
    } on PlatformException catch (e) {
      debugPrint('call: เฝ้าสายไม่ได้ — $e');
    } on MissingPluginException {
      // ไม่ใช่ Android — ไม่ใช่ความผิดพลาด
    }
    await refresh();
  }

  Future<dynamic> _onNative(MethodCall call) async {
    debugPrint('call: ได้สัญญาณ ${call.method} ${call.arguments}');
    if (call.method != 'onCallState') return null;

    final args = call.arguments;
    if (args is! Map) return null;

    final was = _state;
    _state = CallState.parse(args['state']);

    final name = (args['name'] as String?)?.trim();
    final number = (args['number'] as String?)?.trim();
    _ringingWho = _state == CallState.ringing
        ? ((name?.isNotEmpty ?? false) ? name : number)
        : null;

    // สายวางแล้ว — ตอนนี้แหละที่บันทึกการโทรมีข้อมูลครบ
    //
    // อ่านตอนสายเข้าจะได้ของเก่า เพราะระบบยังไม่ได้เขียนแถวใหม่ลงไป
    // และเบอร์ที่มากับสัญญาณสายเข้าก็ว่างเปล่าบ่อยกว่าที่คิด
    if (was != CallState.idle && _state == CallState.idle) {
      await refresh();
      await _recordLatest();
    }

    notifyListeners();
    return null;
  }

  /// อ่านบันทึกการโทรล่าสุดจากเครื่อง
  Future<void> refresh({int limit = 30}) async {
    _set(CallStage.loading);

    await _perms.refresh();
    if (!_perms.of(MindPermission.phone)) {
      _set(CallStage.denied);
      return;
    }

    try {
      final raw = await kSystemChannel
          .invokeMethod<List<Object?>>('recentCalls', {'limit': limit});

      // null = ถามไม่สำเร็จ · [] = ไม่มีประวัติ · คนละเรื่องกัน
      if (raw == null) {
        _set(CallStage.denied);
        return;
      }

      _recent
        ..clear()
        ..addAll(raw.map(CallEvent.fromMap).whereType<CallEvent>());
      _set(CallStage.ready);
    } on PlatformException catch (e) {
      debugPrint('call: อ่านประวัติไม่ได้ — $e');
      _set(CallStage.failed);
    } on MissingPluginException {
      _set(CallStage.failed);
    }
  }

  /// รับสายที่กำลังดัง
  ///
  /// 🔴 รับได้ แต่**เธอพูดในสายไม่ได้** — เสียงยังเดินผ่านทางปกติของเครื่อง
  /// อ่านหัวไฟล์นี้ก่อนคิดจะเรียก
  Future<bool> answer() async {
    try {
      return await kSystemChannel.invokeMethod<bool>('answerCall') ?? false;
    } on PlatformException catch (e) {
      debugPrint('call: รับสายไม่ได้ — $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> hangUp() async {
    try {
      return await kSystemChannel.invokeMethod<bool>('hangUp') ?? false;
    } on PlatformException catch (e) {
      debugPrint('call: วางสายไม่ได้ — $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// สายของวันนี้
  List<CallEvent> get today {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return _recent.where((c) => c.at.isAfter(start)).toList();
  }

  /// สายที่ยังไม่ได้รับวันนี้ — สิ่งที่เลขาควรทักก่อนเรื่องอื่น
  List<CallEvent> get missedToday =>
      today.where((c) => c.type == CallType.missed).toList();

  /// ก้อนข้อความสำหรับ prompt — เธอจะได้ตอบว่าใครโทรมาบ้าง
  String promptBlock({int limit = 6}) {
    final list = today.take(limit).toList();
    if (list.isEmpty) return '';

    String two(int n) => n.toString().padLeft(2, '0');
    return list.map((c) {
      final t = '${two(c.at.hour)}:${two(c.at.minute)}';
      final who = c.who.isEmpty ? '?' : c.who;
      return '- $t ${c.type.name} $who';
    }).join('\n');
  }

  /// จดสายล่าสุดลงสมุดบันทึก
  ///
  /// จดเฉพาะสายที่เพิ่งจบ ไม่ใช่ทั้งประวัติ — บันทึกการโทรมีของตั้งแต่ก่อน
  /// แอปนี้มีอยู่ ยัดทั้งกองเข้าสมุดคือกลบทุกอย่างที่เธอทำจริงจนหมด
  /// คืน Future เพื่อให้ **รอได้** ไม่ใช่ยิงแล้วลอย
  ///
  /// ผู้เรียกเดียวคือ [_onNative] ซึ่ง async อยู่แล้ว และตอนนั้นสายวางไปแล้ว
  /// การรอเขียนดิสก์จึงไม่ได้ทำให้อะไรช้าลง · แลกมาด้วยพฤติกรรมที่กำหนด
  /// เวลาได้แน่นอน ซึ่งเป็นเงื่อนไขที่ทำให้เทสต์เรื่องนี้เชื่อถือได้
  Future<void> _recordLatest() async {
    if (_recent.isEmpty || _journal == null) return;
    final c = _recent.first;

    // สายที่จบไปนานแล้วไม่ใช่สายที่เพิ่งวาง — กันการจดซ้ำตอนรีเฟรชเฉย ๆ
    if (DateTime.now().difference(c.at) > const Duration(minutes: 5)) return;
    if (c.id == _lastRecordedId) return;
    _lastRecordedId = c.id;

    await _journal!.record(JournalKind.call, c.who, detail: c.type.name);
  }

  int? _lastRecordedId;

  void _set(CallStage s) {
    _stage = s;
    notifyListeners();
  }

  @override
  void dispose() {
    kSystemChannel.setMethodCallHandler(null);
    super.dispose();
  }
}
