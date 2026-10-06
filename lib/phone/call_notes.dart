/// บันทึกสายที่มายด์รับแทน — ใครโทรมา ฝากเรื่องอะไรไว้ และคุยกันว่าอะไร
///
/// ## ทำไมต้องมี
///
/// ของเดิมพอวางสาย บทสนทนาทั้งหมดหายไปกับหน่วยความจำ · มายด์รับสายแทน
/// คุยกับคู่สายจริง แต่เจ้าของไม่มีทางรู้ว่าใครฝากอะไรไว้ — เลขาที่รับสาย
/// แต่ไม่จดอะไรเลย คือเลขาที่ไม่ได้ทำงาน
///
/// ## 🔴 เจ้าของต้องเห็นและลบได้ทุกอย่าง (กฎเดียวกับความจำและไทม์ไลน์)
///
/// บทสนทนาของคนที่โทรมาเป็นข้อมูลของคนอื่นที่อยู่ในเครื่องเรา · เก็บในฐาน
/// ของแอปเท่านั้น ไม่ส่งไปไหน และลบได้จากหน้าที่เปิดดู
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../store/mind_db.dart';
import 'call_watch.dart';

/// หนึ่งบรรทัดในสาย
typedef CallNoteLine = ({bool fromHer, String text});

@immutable
class CallNote {
  const CallNote({
    required this.id,
    required this.at,
    required this.who,
    required this.summary,
    required this.lines,
    this.seen = false,
    this.sim,
  });

  final String id;
  final DateTime at;

  /// ชื่อในสมุดโทรศัพท์ หรือเบอร์ · ว่างได้ (เบอร์ซ่อน)
  final String who;

  /// โทรเข้าทางซิมไหน (เครื่องสองซิม) · null = ซิมเดียว / ระบบไม่บอก
  final CallSim? sim;

  /// สรุปให้เจ้าของ: ใคร เรื่องอะไร ฝากอะไร ต้องโทรกลับไหม
  final String summary;
  final List<CallNoteLine> lines;

  /// เจ้าของเปิดอ่านแล้วหรือยัง
  final bool seen;

  /// คู่สายพูดอะไรบ้างไหม · ไม่พูดเลย = สายเงียบ/วางไปก่อน
  bool get callerSpoke => lines.any((l) => !l.fromHer && l.text.trim().isNotEmpty);

  CallNote copyWith({bool? seen}) => CallNote(
        id: id,
        at: at,
        who: who,
        summary: summary,
        lines: lines,
        seen: seen ?? this.seen,
        sim: sim,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'at': at.millisecondsSinceEpoch,
        'who': who,
        'summary': summary,
        'transcript': jsonEncode([
          for (final l in lines) {'her': l.fromHer, 't': l.text},
        ]),
        'seen': seen ? 1 : 0,
        'sim': sim?.encode(),
      };

  static CallNote? fromRow(Map<String, Object?> r) {
    final id = '${r['id'] ?? ''}';
    final at = r['at'];
    if (id.isEmpty || at is! int) return null;
    final lines = <CallNoteLine>[];
    try {
      final raw = jsonDecode('${r['transcript'] ?? '[]'}');
      if (raw is List) {
        for (final e in raw) {
          if (e is Map && e['t'] is String) {
            lines.add((fromHer: e['her'] == true, text: e['t'] as String));
          }
        }
      }
    } on FormatException {
      // บทสนทนาเสียก็ยังเหลือสรุปให้อ่าน · ดีกว่าทิ้งทั้งบันทึก
    }
    return CallNote(
      id: id,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      who: '${r['who'] ?? ''}',
      summary: '${r['summary'] ?? ''}',
      lines: lines,
      seen: r['seen'] == 1,
      sim: CallSim.decode(r['sim'] as String?),
    );
  }
}

/// เพดาน · บันทึกสายเก่ากว่านี้ถูกตัดทิ้งเหมือนไทม์ไลน์
const kCallNotesLimit = 100;

class CallNotes extends ChangeNotifier {
  CallNotes({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  MindDb? _db;
  final List<CallNote> _notes = [];

  void attachDb(MindDb? db) => _db = db;

  /// ใหม่สุดก่อน
  List<CallNote> get notes => List.unmodifiable(_notes);

  int get unseen => _notes.where((n) => !n.seen).length;

  CallNote? byId(String id) {
    for (final n in _notes) {
      if (n.id == id) return n;
    }
    return null;
  }

  Future<void> load() async {
    final db = _db;
    if (db == null) return;
    try {
      _notes
        ..clear()
        ..addAll((await db.allCallNotes(limit: kCallNotesLimit))
            .map(CallNote.fromRow)
            .whereType<CallNote>());
      notifyListeners();
    } on Object catch (e) {
      debugPrint('call notes: อ่านไม่ได้ — $e');
    }
  }

  Future<void> add(CallNote n) async {
    _notes.insert(0, n);
    if (_notes.length > kCallNotesLimit) {
      _notes.removeRange(kCallNotesLimit, _notes.length);
    }
    notifyListeners();
    try {
      await _db?.putCallNote(n.toRow());
    } on Object catch (e) {
      debugPrint('call notes: บันทึกไม่ได้ — $e');
    }
  }

  Future<void> markSeen(String id) async {
    final i = _notes.indexWhere((n) => n.id == id);
    if (i < 0 || _notes[i].seen) return;
    _notes[i] = _notes[i].copyWith(seen: true);
    notifyListeners();
    try {
      await _db?.setCallNoteSeen(id);
    } on Object catch (e) {
      debugPrint('call notes: ทำเครื่องหมายว่าอ่านแล้วไม่ได้ — $e');
    }
  }

  Future<void> remove(String id) async {
    _notes.removeWhere((n) => n.id == id);
    notifyListeners();
    try {
      await _db?.deleteCallNote(id);
    } on Object catch (e) {
      debugPrint('call notes: ลบไม่ได้ — $e');
    }
  }

  /// ก้อนสำหรับ prompt — เธอจะได้ตอบได้ว่า "เมื่อเช้าคุณนภาโทรมาฝากว่า…"
  ///
  /// เฉพาะสองวันล่าสุด และไม่เกิน [limit] สาย · เก่ากว่านั้นเจ้าของเปิดดูเองได้
  /// ในไทม์ไลน์ ไม่ต้องจ่าย token ทุกตา
  ///
  /// [unseenTag] ต่อท้ายสายที่เจ้าของยังไม่ได้เปิดอ่าน (ในภาษาของ prompt)
  /// เธอจะได้รู้ว่าต้องบอกเรื่องนี้ก่อน
  String promptBlock({int limit = 5, String unseenTag = ''}) {
    final since = _clock().subtract(const Duration(days: 2));
    final recent = _notes.where((n) => n.at.isAfter(since)).take(limit);
    if (recent.isEmpty) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return recent.map((n) {
      final t = '${two(n.at.day)}/${two(n.at.month)} ${two(n.at.hour)}:${two(n.at.minute)}';
      final who = n.who.isEmpty ? '?' : n.who;
      final flag = n.seen || unseenTag.isEmpty ? '' : ' $unseenTag';
      return '- $t $who: ${n.summary}$flag';
    }).join('\n');
  }
}
