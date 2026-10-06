/// นึกถึงบทสนทนาเก่า — "เมื่อเดือนก่อนเราคุยเรื่องนี้กันว่ายังไง"
///
/// ## 🔴 ของเดิม
///
/// เธอเห็นแค่ 16 บรรทัดล่าสุด · ที่เก่ากว่านั้นเหลือแค่ข้อเท็จจริงที่สกัดไว้
/// (ถ้าสกัดทัน) · บทสนทนาเก็บในฐานครบทุกบรรทัดอยู่แล้ว แต่ไม่มีใครค้นมันเลย
///
/// ตัวนี้ทำดัชนีบทสนทนาเก่าในหน่วยความจำ (ดู [RecallIndex]) แล้วหยิบคู่
/// "เจ้าของพูด → เธอตอบ" ที่เกี่ยวกับเรื่องตอนนี้มาให้เธอนึกออก · ทั้งหมดในเครื่อง
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../store/mind_db.dart';
import 'recall.dart';

/// หนึ่งบรรทัดของบทสนทนาเก่า
typedef PastLine = ({int id, bool fromHer, String text, DateTime at});

/// คู่ที่นึกออก · [ask] หรือ [answer] อาจว่างถ้าอีกฝั่งหาไม่เจอ
typedef PastExchange = ({DateTime at, String? ask, String? answer});

class ChatRecall {
  ChatRecall({this.maxLines = 4000});

  /// เก็บบทสนทนาย้อนหลังไว้ค้นได้กี่บรรทัด · หน่วยความจำราวครึ่ง MB ที่ 4,000
  final int maxLines;

  final RecallIndex _index = RecallIndex();
  final Map<int, PastLine> _lines = {};
  bool _loaded = false;
  bool get loaded => _loaded;
  int get size => _lines.length;

  /// บรรทัดสั้นกว่านี้ไม่บอกเรื่องอะไร ("ค่ะ" "โอเค") · ไม่ทำดัชนี
  static const _minChars = 6;

  /// อ่านบทสนทนาเก่าจากฐานมาทำดัชนี · แบ่งเป็นช่วงให้จอไม่กระตุก
  Future<void> load(MindDb db, {bool force = false}) async {
    if (_loaded && !force) return;
    try {
      final rows = await db.messagesForRecall(maxLines);
      var i = 0;
      for (final r in rows) {
        _put(r);
        // ทุก 250 บรรทัดปล่อยให้เฟรมได้วาด · ทำดัชนีพันบรรทัดรวดเดียวคือจอค้าง
        if (++i % 250 == 0) await Future<void>.delayed(Duration.zero);
      }
      _loaded = true;
      debugPrint('recall: ทำดัชนีบทสนทนาเก่า ${_lines.length} บรรทัด');
    } on Object catch (e) {
      debugPrint('recall: อ่านบทสนทนาเก่าไม่ได้ — ${e.runtimeType}');
    }
  }

  /// บรรทัดใหม่ที่เพิ่งลงฐาน (ได้ id จากฐานแล้ว)
  void add(PastLine line) {
    _put(line);
    // เกินเพดาน = ทิ้งบรรทัดเก่าสุด
    while (_lines.length > maxLines) {
      final oldest = _lines.keys.reduce((a, b) => a < b ? a : b);
      _lines.remove(oldest);
      _index.remove('$oldest');
    }
  }

  void clear() {
    _lines.clear();
    _index.clear();
  }

  /// ทุกบรรทัดของวันนั้น เรียงตามลำดับ · ใช้เขียนบันทึกรายวันขึ้นสมอง BrainX
  List<PastLine> linesOn(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return [
      for (final id in (_lines.keys.toList()..sort()))
        if (!_lines[id]!.at.isBefore(start) && _lines[id]!.at.isBefore(end)) _lines[id]!,
    ];
  }

  void _put(PastLine l) {
    _lines[l.id] = l;
    if (l.text.trim().length >= _minChars) _index.put('${l.id}', l.text);
  }

  /// คู่บทสนทนาเก่าที่เกี่ยวกับ [query]
  ///
  /// [skipNewest] = บรรทัดล่าสุดที่อยู่ในหน้าต่างบทสนทนาแล้ว ไม่ต้องนึกซ้ำ
  List<PastExchange> search(String query, {int limit = 3, int skipNewest = 16}) {
    if (_lines.isEmpty) return const [];
    final ids = _lines.keys.toList()..sort();
    final skip = ids.length <= skipNewest
        ? ids.map((i) => '$i').toSet()
        : ids.sublist(ids.length - skipNewest).map((i) => '$i').toSet();

    final out = <PastExchange>[];
    final used = <int>{};
    for (final h in _index.search(query, limit: limit * 3, exclude: skip)) {
      final id = int.parse(h.id);
      final line = _lines[id];
      if (line == null) continue;
      // คู่ของมัน: เจ้าของพูด → บรรทัดถัดไปที่เป็นของเธอ · เธอพูด → บรรทัดก่อนหน้าของเจ้าของ
      final mate = _mate(ids, id, wantHer: !line.fromHer);
      final key = line.fromHer ? (mate?.id ?? id) : id;
      if (!used.add(key) || (mate != null && skip.contains('${mate.id}'))) continue;
      final ask = line.fromHer ? mate : line;
      final answer = line.fromHer ? line : mate;
      out.add((at: line.at, ask: ask?.text, answer: answer?.text));
      if (out.length >= limit) break;
    }
    return out;
  }

  PastLine? _mate(List<int> ids, int id, {required bool wantHer}) {
    final i = ids.indexOf(id);
    if (i < 0) return null;
    final j = wantHer ? i + 1 : i - 1;
    if (j < 0 || j >= ids.length) return null;
    final m = _lines[ids[j]];
    return m != null && m.fromHer == wantHer ? m : null;
  }
}
