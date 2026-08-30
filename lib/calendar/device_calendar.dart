/// ปฏิทินของเครื่อง — ตารางจริงของเจ้าของ
///
/// **ของเดิมเป็นภาพนิ่ง** แท็บปฏิทินโชว์ `_Slot(title: t.calStandup, time: '09:00–09:30')`
/// ซึ่งเป็นข้อความตายตัวจากไฟล์ภาษา · สวย แต่ไม่ใช่นัดของใครทั้งนั้น
/// เลขาที่บอกตารางผิดทุกวันแย่กว่าเลขาที่ไม่บอกอะไรเลย
///
/// ไฟล์นี้อ่านจาก Calendar Provider ของ Android ผ่าน [kSystemChannel]
/// **อ่านอย่างเดียว** ไม่เขียน ไม่ลบ และไม่ส่งออกจากเครื่อง
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../system/permissions.dart';

/// นัดหนึ่งนัด
@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.begin,
    required this.end,
    required this.allDay,
    this.location,
    this.calendar,
    this.color,
  });

  final int id;
  final String title;
  final DateTime begin;
  final DateTime end;
  final bool allDay;
  final String? location;

  /// ปฏิทินต้นทาง — เครื่องหนึ่งมักมีหลายบัญชี งานกับส่วนตัวปนกัน
  final String? calendar;

  /// สีที่ผู้ใช้ตั้งไว้ในปฏิทินต้นทาง · 0 = ไม่ได้ตั้ง
  final int? color;

  Duration get length => end.difference(begin);

  bool get isPast => end.isBefore(DateTime.now());

  bool get isNow {
    final now = DateTime.now();
    return !begin.isAfter(now) && end.isAfter(now);
  }

  /// อ่านจากแมปที่ฝั่ง Android ส่งมา · คืน null ถ้าแถวนั้นใช้ไม่ได้
  ///
  /// ทนความไม่ครบ เพราะปฏิทินบางบัญชีไม่ใส่ชื่อนัดมาเลย และนัดที่ไม่มีชื่อ
  /// ยังเป็นนัดอยู่ดี — ทิ้งทั้งแถวจะทำให้ตารางขาดโดยไม่มีใครรู้
  static CalendarEvent? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final begin = (raw['begin'] as num?)?.toInt();
    final end = (raw['end'] as num?)?.toInt();
    if (begin == null || end == null) return null;

    final color = (raw['color'] as num?)?.toInt();
    return CalendarEvent(
      id: (raw['id'] as num?)?.toInt() ?? begin,
      title: '${raw['title'] ?? ''}'.trim(),
      begin: DateTime.fromMillisecondsSinceEpoch(begin),
      // นัดที่ไม่มีเวลาจบ (บางบัญชีส่ง 0 มา) ให้ถือว่ายาวหนึ่งชั่วโมง
      // ดีกว่าโชว์ว่าจบก่อนเริ่ม
      end: DateTime.fromMillisecondsSinceEpoch(end > begin ? end : begin + 3600000),
      allDay: raw['allDay'] == true,
      location: (raw['location'] as String?)?.trim(),
      calendar: raw['calendar'] as String?,
      color: color == null || color == 0 ? null : color,
    );
  }
}

/// สถานะของแท็บปฏิทิน
///
/// แยก [denied] ออกจาก [ready] ที่ไม่มีนัดเลย เพราะคนละเรื่องและคนละวิธีแก้:
/// "ยังไม่ได้ให้สิทธิ์" ต้องมีปุ่มให้กด · "ไม่มีนัด" คือข่าวดี
enum CalendarStage { idle, loading, ready, denied, failed }

class DeviceCalendar extends ChangeNotifier {
  DeviceCalendar({MindPermissions? permissions})
      : _perms = permissions ?? MindPermissions();

  final MindPermissions _perms;

  CalendarStage _stage = CalendarStage.idle;
  CalendarStage get stage => _stage;

  final List<CalendarEvent> _events = [];
  List<CalendarEvent> get events => List.unmodifiable(_events);

  DateTime? _loadedAt;
  DateTime? get loadedAt => _loadedAt;

  /// อ่านนัดตั้งแต่ต้นวันนี้ไปอีก [days] วัน
  ///
  /// เริ่มที่**ต้นวัน** ไม่ใช่ตอนนี้ เพราะนัดที่ผ่านไปแล้วเมื่อเช้ายังเป็นส่วนหนึ่ง
  /// ของวันนี้ · คนถามว่า "วันนี้มีอะไรบ้าง" ไม่ได้ถามว่า "เหลืออะไรบ้าง"
  Future<void> load({int days = 7}) async {
    _set(CalendarStage.loading);

    // ถามระบบใหม่ทุกครั้ง ไม่เชื่อค่าที่จำไว้ — สิทธิ์ถูกถอนได้จากหน้าตั้งค่า
    // ของเครื่องตอนที่แอปเราไม่ได้อยู่หน้าจอ แล้วไม่มีใครมาบอกเรา
    await _perms.refresh();
    if (!_perms.of(MindPermission.calendar)) {
      _set(CalendarStage.denied);
      return;
    }

    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = from.add(Duration(days: days));

    try {
      final raw = await kSystemChannel.invokeMethod<List<Object?>>('readCalendar', {
        'from': from.millisecondsSinceEpoch,
        'to': to.millisecondsSinceEpoch,
      });

      // null = ถามไม่สำเร็จ · [] = ถามสำเร็จแล้วไม่มีนัด · คนละเรื่องกัน
      if (raw == null) {
        _set(CalendarStage.denied);
        return;
      }

      _events
        ..clear()
        ..addAll(raw.map(CalendarEvent.fromMap).whereType<CalendarEvent>());
      _loadedAt = DateTime.now();
      _set(CalendarStage.ready);
    } on PlatformException catch (e) {
      debugPrint('calendar: อ่านไม่ได้ — $e');
      _set(CalendarStage.failed);
    } on MissingPluginException {
      // รันบนแพลตฟอร์มที่ไม่มีสะพานนี้ (เทสต์ เดสก์ท็อป) — ไม่ใช่ความผิดพลาด
      _set(CalendarStage.failed);
    }
  }

  /// ขอสิทธิ์แล้วโหลดต่อทันทีถ้าได้
  Future<void> requestThenLoad() async {
    await _perms.request(MindPermission.calendar);
    await load();
  }

  /// นัดของวันนี้ · เรียงตามเวลาเริ่ม
  List<CalendarEvent> get today {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return _events
        .where((e) => e.begin.isBefore(end) && e.end.isAfter(start))
        .toList();
  }

  /// นัดถัดไปที่ยังไม่ผ่าน — null ถ้าไม่เหลือแล้ว
  CalendarEvent? get next {
    final now = DateTime.now();
    for (final e in _events) {
      if (e.end.isAfter(now)) return e;
    }
    return null;
  }

  /// จัดกลุ่มตามวัน สำหรับหน้าที่โชว์ทั้งสัปดาห์
  Map<DateTime, List<CalendarEvent>> get byDay {
    final out = <DateTime, List<CalendarEvent>>{};
    for (final e in _events) {
      final day = DateTime(e.begin.year, e.begin.month, e.begin.day);
      (out[day] ??= []).add(e);
    }
    return out;
  }

  /// ก้อนข้อความสำหรับใส่ prompt — เธอจะได้ตอบเรื่องตารางได้จริง
  ///
  /// ตัดที่ [limit] เพราะทุกบรรทัดคือ token ที่จ่ายทุกครั้งที่คุย
  String promptBlock({int limit = 8}) {
    if (_events.isEmpty) return '';
    final now = DateTime.now();
    final soon = _events.where((e) => e.end.isAfter(now)).take(limit);
    if (soon.isEmpty) return '';

    String two(int n) => n.toString().padLeft(2, '0');
    return soon.map((e) {
      final d = '${two(e.begin.day)}/${two(e.begin.month)}';
      // นัดทั้งวันเขียนแค่วันที่ ไม่ต้องมีคำว่าทั้งวัน — การไม่มีเวลาคือ
      // สัญญาณอยู่แล้ว สั้นกว่า และไม่ต้องมีคำของภาษาใดภาษาหนึ่งใน prompt
      final t = e.allDay
          ? ''
          : ' ${two(e.begin.hour)}:${two(e.begin.minute)}'
              '-${two(e.end.hour)}:${two(e.end.minute)}';
      final where = (e.location?.isNotEmpty ?? false) ? ' @${e.location}' : '';
      return '- $d$t ${e.title}$where';
    }).join('\n');
  }

  void _set(CalendarStage s) {
    _stage = s;
    notifyListeners();
  }
}
