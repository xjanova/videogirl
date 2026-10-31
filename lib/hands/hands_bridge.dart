/// ช่องทางไปบริการ "ใช้เครื่องแทน" ฝั่ง Android (`giggok/hands` · hands/HandsBridge.kt)
///
/// 🔴 ฝั่ง Android เป็นด่านสุดท้าย ไม่ใช่ฝั่งนี้ · แอปธนาคาร/การเงิน แอปเราเอง ตัวติดตั้งแอป
/// และหน้าขอสิทธิ์ ถูกกันที่นั่น (อ่านหน้าจอไม่ได้ กดไม่ได้ เปิดไม่ได้) · ช่องรหัสผ่านพิมพ์ไม่ได้
/// และไม่ส่งตัวอักษรออกมา · เจ้าของกดหยุดในแจ้งเตือนแล้ว ทุกคำสั่งตอบ `stopped` ทันที
/// ไม่ต้องรอฝั่งนี้
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ปุ่ม ช่อง หรือข้อความหนึ่งชิ้นบนจอ · [id] ใช้ได้เฉพาะกับภาพจอล่าสุดเท่านั้น
class ScreenNode {
  const ScreenNode({
    required this.id,
    this.cls = '',
    this.text = '',
    this.desc = '',
    this.hint = '',
    this.vid = '',
    this.click = false,
    this.long = false,
    this.edit = false,
    this.scroll = false,
    this.check = false,
    this.on = false,
    this.pwd = false,
    this.sel = false,
    this.bounds = const [],
  });

  factory ScreenNode.fromMap(Map<Object?, Object?> m) {
    String str(String k) => m[k] is String ? m[k] as String : '';
    bool flag(String k) => m[k] == true;
    final b = m['b'];
    return ScreenNode(
      id: (m['id'] as num?)?.toInt() ?? -1,
      cls: str('cls'),
      text: str('text'),
      desc: str('desc'),
      hint: str('hint'),
      vid: str('vid'),
      click: flag('click'),
      long: flag('long'),
      edit: flag('edit'),
      scroll: flag('scroll'),
      check: flag('check'),
      on: flag('on'),
      pwd: flag('pwd'),
      sel: flag('sel'),
      bounds: b is List ? [for (final v in b) (v as num?)?.toInt() ?? 0] : const [],
    );
  }

  final int id;
  final String cls;
  final String text;
  final String desc;
  final String hint;

  /// ชื่อ resource id ของปุ่ม (เช่น `send_button`) · ใช้จับคู่ตอนเล่นขั้นตอนที่จำไว้ซ้ำ
  final String vid;
  final bool click;
  final bool long;
  final bool edit;
  final bool scroll;
  final bool check;
  final bool on;
  final bool pwd;
  final bool sel;
  final List<int> bounds;

  /// คำที่คนเห็นบนปุ่มนี้ (ข้อความ > คำอธิบาย > คำใบ้)
  String get label => text.isNotEmpty ? text : (desc.isNotEmpty ? desc : hint);
}

/// ภาพจอหนึ่งครั้ง เป็นตัวหนังสือ
class PhoneScreen {
  const PhoneScreen({
    this.package = '',
    this.app = '',
    this.blocked = false,
    this.keyboard = false,
    this.truncated = false,
    this.nodes = const [],
  });

  factory PhoneScreen.fromMap(Map<Object?, Object?> m) {
    final raw = m['nodes'];
    return PhoneScreen(
      package: m['package'] is String ? m['package'] as String : '',
      app: m['app'] is String ? m['app'] as String : '',
      blocked: m['blocked'] == true,
      keyboard: m['keyboard'] == true,
      truncated: m['truncated'] == true,
      nodes: raw is List ? [for (final n in raw) if (n is Map) ScreenNode.fromMap(n)] : const [],
    );
  }

  final String package;

  /// ชื่อแอปที่เห็นบนเครื่อง (ว่าง = ใช้ [package])
  final String app;

  /// แอปที่ห้ามแตะ (ธนาคาร การเงิน ฯลฯ) · ไม่มีข้อความบนจอส่งมา
  final bool blocked;
  final bool keyboard;
  final bool truncated;
  final List<ScreenNode> nodes;

  String get appName => app.isNotEmpty ? app : package;

  ScreenNode? byId(int id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }
}

/// คำตอบของคำสั่งหนึ่งครั้ง · [error] = รหัสจาก Android ('stopped' 'blocked' 'stale' 'password'
/// 'not_enabled' 'not_found' 'failed' 'unsupported' 'paused' 'busy')
class HandsReply {
  const HandsReply(this.ok, {this.error, this.data = const {}});

  factory HandsReply.fromMap(Object? raw) {
    if (raw is! Map) return const HandsReply(false, error: 'failed');
    final ok = raw['ok'] == true;
    final error = raw['error'] is String ? raw['error'] as String : null;
    return HandsReply(ok, error: ok ? null : (error ?? 'failed'), data: raw);
  }

  final bool ok;
  final String? error;
  final Map<Object?, Object?> data;

  String str(String key) => data[key] is String ? data[key] as String : '';
}

/// สิ่งที่ค้างจากแจ้งเตือน (เจ้าของกดหยุด / ตอบคำถาม / กดจำขั้นตอนเสร็จ)
class HandsPoll {
  const HandsPoll({this.stop = false, this.confirmId, this.allow = false, this.recordDone = false});

  factory HandsPoll.fromMap(Object? raw) {
    if (raw is! Map) return const HandsPoll();
    final c = raw['confirm'];
    return HandsPoll(
      stop: raw['stop'] == true,
      confirmId: c is Map ? (c['id'] as num?)?.toInt() : null,
      allow: c is Map && c['allow'] == true,
      recordDone: raw['recordDone'] == true,
    );
  }

  final bool stop;
  final int? confirmId;
  final bool allow;
  final bool recordDone;
}

/// สถานะของบริการใช้เครื่องแทน
class HandsStatus {
  const HandsStatus({
    this.supported = false,
    this.enabled = false,
    this.canAutoEnable = false,
    this.paused = false,
    this.running = false,
    this.notifications = true,
  });

  factory HandsStatus.fromMap(Object? raw) {
    if (raw is! Map) return const HandsStatus();
    return HandsStatus(
      supported: raw['supported'] == true,
      enabled: raw['enabled'] == true,
      canAutoEnable: raw['canAutoEnable'] == true,
      paused: raw['paused'] == true,
      running: raw['running'] == true,
      notifications: raw['notifications'] != false,
    );
  }

  final bool supported;

  /// บริการทำงานอยู่ตอนนี้
  final bool enabled;

  /// แอปเปิดบริการเองได้ตอนเริ่มงาน (มีสิทธิ์เขียนค่าระบบจากการตั้งค่าเสียงตรง)
  final bool canAutoEnable;

  /// พักไว้ให้แอปธนาคาร
  final bool paused;
  final bool running;
  final bool notifications;

  /// เริ่มงานได้ไหม (ไม่นับพัก/มีงานอยู่)
  bool get usable => supported && (enabled || canAutoEnable);
}

/// ช่องทางที่ [PhoneAgent] ใช้ · แยกเป็น interface เพื่อให้เทสต์ใส่ตัวปลอมได้
abstract class Hands {
  Future<HandsStatus> status();

  /// เปิดบริการ (ถ้าแอปเปิดเองได้) ขึ้นแจ้งเตือนพร้อมปุ่มหยุด · [title] = หัวแจ้งเตือน
  Future<HandsReply> begin({required String title, required String goal, bool inCall = false});

  /// อัปเดตบรรทัดในแจ้งเตือน
  Future<void> progress(String line, int step);

  /// จบงาน · ปิดแจ้งเตือน · แอปปิดบริการเองหลังว่างสักครู่ (ถ้าแอปเป็นคนเปิด)
  Future<void> end();

  /// รอจนจอนิ่ง แล้วอ่านจอเป็นตัวหนังสือ
  Future<(HandsReply, PhoneScreen?)> snapshot({int maxNodes = 120});

  /// ทำหนึ่งอย่าง · [action] ดู [PhoneAgent] ('tap' 'long_press' 'type' 'submit' 'scroll' 'back' 'home' 'recents' 'notifications')
  Future<HandsReply> act(String action, {int? id, String? text, String? dir});

  Future<HandsReply> openApp(String name);
  Future<HandsReply> setAlarm({required int hour, required int minute, String label = ''});
  Future<HandsReply> addEvent({required String title, required DateTime begin, DateTime? end, String location = ''});
  Future<HandsReply> composeEmail({String to = '', String subject = '', String body = ''});

  Future<HandsPoll> poll();

  /// ขึ้นแจ้งเตือนถามเจ้าของ (ทำเลย / ไม่ต้อง) · คำตอบมาทาง [poll]
  Future<void> askConfirm({required int id, required String title, required String body});
  Future<void> confirmDone(int id);

  /// ปุ่มหยุดในแอป · ผลเหมือนปุ่มในแจ้งเตือน
  Future<void> stop();

  /// เริ่ม/จบการจำขั้นตอน (เจ้าของทำให้ดู) · [recordStop] คืนขั้นที่จำได้
  Future<HandsReply> recordStart({required String title});
  Future<List<Map<Object?, Object?>>> recordStop();
}

/// ตัวจริง · คุยกับ hands/HandsBridge.kt
class HandsBridge implements Hands {
  HandsBridge({MethodChannel? channel}) : _ch = channel ?? kHandsChannel;

  final MethodChannel _ch;

  Future<Object?> _call(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<Object?>(method, args);
    } on MissingPluginException {
      return {'ok': false, 'error': 'unsupported'};
    } on PlatformException catch (e) {
      // ไม่ลง message · อาจมีข้อความบนจอของแอปอื่นติดมา
      debugPrint('hands: $method ไม่สำเร็จ — ${e.code}');
      return {'ok': false, 'error': 'failed'};
    }
  }

  @override
  Future<HandsStatus> status() async => HandsStatus.fromMap(await _call('status'));

  @override
  Future<HandsReply> begin({required String title, required String goal, bool inCall = false}) async =>
      HandsReply.fromMap(await _call('begin', {'title': title, 'goal': goal, 'inCall': inCall}));

  @override
  Future<void> progress(String line, int step) async => _call('progress', {'text': line, 'step': step});

  @override
  Future<void> end() async => _call('end');

  @override
  Future<(HandsReply, PhoneScreen?)> snapshot({int maxNodes = 120}) async {
    final raw = await _call('snapshot', {'max': maxNodes, 'quietMs': 350, 'maxWaitMs': 2500});
    final r = HandsReply.fromMap(raw);
    return (r, r.ok ? PhoneScreen.fromMap(r.data) : null);
  }

  @override
  Future<HandsReply> act(String action, {int? id, String? text, String? dir}) async => HandsReply.fromMap(
        await _call('act', {
          'do': action,
          'id': ?id,
          'text': ?text,
          'dir': ?dir,
        }),
      );

  @override
  Future<HandsReply> openApp(String name) async => HandsReply.fromMap(await _call('openApp', {'name': name}));

  @override
  Future<HandsReply> setAlarm({required int hour, required int minute, String label = ''}) async =>
      HandsReply.fromMap(await _call('setAlarm', {'hour': hour, 'minute': minute, 'label': label}));

  @override
  Future<HandsReply> addEvent({
    required String title,
    required DateTime begin,
    DateTime? end,
    String location = '',
  }) async =>
      HandsReply.fromMap(await _call('addEvent', {
        'title': title,
        'begin': begin.millisecondsSinceEpoch,
        'end': (end ?? begin.add(const Duration(hours: 1))).millisecondsSinceEpoch,
        'location': location,
      }));

  @override
  Future<HandsReply> composeEmail({String to = '', String subject = '', String body = ''}) async =>
      HandsReply.fromMap(await _call('composeEmail', {'to': to, 'subject': subject, 'body': body}));

  @override
  Future<HandsPoll> poll() async => HandsPoll.fromMap(await _call('poll'));

  @override
  Future<void> askConfirm({required int id, required String title, required String body}) async =>
      _call('askConfirm', {'id': id, 'title': title, 'body': body});

  @override
  Future<void> confirmDone(int id) async => _call('confirmDone', {'id': id});

  @override
  Future<void> stop() async => _call('stop');

  @override
  Future<HandsReply> recordStart({required String title}) async =>
      HandsReply.fromMap(await _call('recordStart', {'title': title}));

  @override
  Future<List<Map<Object?, Object?>>> recordStop() async {
    final raw = await _call('recordStop');
    final steps = raw is Map ? raw['steps'] : null;
    return steps is List ? [for (final s in steps) if (s is Map) s] : const [];
  }
}

const MethodChannel kHandsChannel = MethodChannel('giggok/hands');
