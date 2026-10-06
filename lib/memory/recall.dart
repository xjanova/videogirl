/// นึกออก — ค้นความจำและบทสนทนาเก่า**ตามเรื่องที่กำลังคุย**
///
/// ## 🔴 ของเดิมไม่ใช่การนึก แต่คือการท่อง
///
/// ทุกครั้งที่คุย เธอได้ความจำ "ปักหมุด + ใหม่สุด 60 ข้อ" เหมือนกันหมด ไม่ว่า
/// จะถามเรื่องอะไร · พอจำเกิน 60 ข้อ เรื่องเก่าที่ไม่ได้ปักหมุด (เช่น "เจ้าของ
/// แพ้กุ้ง" ที่จำไว้เดือนก่อน) จะไม่ถึงตาเธออีกเลย แม้จะถามเรื่องอาหารตรง ๆ ·
/// และบทสนทนาที่เก่ากว่า 16 บรรทัดล่าสุดค้นไม่ได้เลย
///
/// ## ทำไมไม่ใช่ embedding
///
/// - ต้องมีโมเดลอีกตัว (ดาวน์โหลด + หน่วยความจำ) บนเครื่องที่สมองกิน 2–3 GB อยู่แล้ว
///   หรือส่งความจำของเจ้าของออกไปข้างนอกเพื่อทำเวกเตอร์ — ผิดคำสัญญาเรื่องความเป็นส่วนตัว
/// - ความจำคือ "ข้อเท็จจริงหนึ่งบรรทัด" ที่มีคำสำคัญอยู่ในตัว (กุ้ง, ประชุม, คุณต้น)
///   การจับคำตรงทำงานได้ดีกับของแบบนี้
///
/// ## ทำไมเป็น n-gram ตัวอักษร
///
/// ภาษาไทยไม่เว้นวรรคระหว่างคำ ตัดคำต้องมีพจนานุกรม (หนักและพลาดกับชื่อคน
/// ชื่อร้าน) · ชิ้นตัวอักษร 2–3 ตัวจับ "กุ้ง" ใน "เจ้าของแพ้กุ้ง" ได้โดยไม่ต้องรู้ว่า
/// คำแบ่งตรงไหน · ตัดวรรณยุกต์ออกก่อนเพื่อให้พิมพ์ผิดวรรณยุกต์ยังเจอ
///
/// คะแนนแบบ BM25: ชิ้นที่หายาก (ชื่อคน ชื่ออาหาร) มีน้ำหนักมาก ชิ้นที่เจอทุกที่
/// (ที่ ได้ ไม่) แทบไม่มีน้ำหนัก · ทั้งหมดในเครื่อง ไม่มีอะไรออกไปไหน
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// ผลค้นหนึ่งรายการ
@immutable
class RecallHit {
  const RecallHit(this.id, this.score);
  final String id;

  /// น้ำหนักหลักฐาน ≈ จำนวน "ชิ้นหายาก" ที่ตรงกัน · ดู [RecallIndex.search]
  final double score;
}

/// ดัชนีค้นข้อความสั้น ๆ · ใส่/ลบทีละรายการได้ (บทสนทนางอกทุกตา)
class RecallIndex {
  final Map<String, Map<String, int>> _postings = {};
  final Map<String, int> _lengths = {};
  final Map<String, Iterable<String>> _docGrams = {};
  int _totalLength = 0;

  int get size => _lengths.length;
  bool contains(String id) => _lengths.containsKey(id);

  void clear() {
    _postings.clear();
    _lengths.clear();
    _docGrams.clear();
    _totalLength = 0;
  }

  void put(String id, String text) {
    remove(id);
    final g = grams(text);
    if (g.isEmpty) return;
    final tf = <String, int>{};
    for (final x in g) {
      tf[x] = (tf[x] ?? 0) + 1;
    }
    tf.forEach((gram, n) => (_postings[gram] ??= {})[id] = n);
    _docGrams[id] = tf.keys.toList(growable: false);
    _lengths[id] = g.length;
    _totalLength += g.length;
  }

  void remove(String id) {
    final len = _lengths.remove(id);
    if (len == null) return;
    _totalLength -= len;
    for (final g in _docGrams.remove(id) ?? const <String>[]) {
      final docs = _postings[g];
      if (docs == null) continue;
      docs.remove(id);
      if (docs.isEmpty) _postings.remove(g);
    }
  }

  /// ค้น
  ///
  /// [minScore] = ต้องตรงกันอย่างน้อยกี่ "ชิ้นหายาก" (ชิ้นที่มีในเอกสารเดียว)
  /// · คำสำคัญไทยหนึ่งคำ (เช่น "กุ้ง") ให้ราวสามชิ้น จึงตั้งที่ 2 · ชิ้นที่เจอ
  /// ทั่วไป (เป็น ได้ ที่) มีน้ำหนักต่ำมากจนรวมกันหลายชิ้นก็ไม่ถึง
  ///
  /// 🔴 ไม่เทียบกับความยาวคำถาม · "เย็นนี้สั่งต้มยำกุ้งดีไหม" มีคำที่เกี่ยวแค่
  /// คำเดียวในสิบกว่าคำ ถ้าคิดเป็นสัดส่วนของคำถามจะไม่ผ่านทั้งที่เกี่ยวตรง ๆ
  List<RecallHit> search(
    String query, {
    int limit = 8,
    double minScore = 2,
    Set<String> exclude = const {},
  }) {
    final n = _lengths.length;
    if (n == 0) return const [];
    final q = grams(stripChatter(query)).toSet();
    if (q.isEmpty) return const [];

    const k1 = 1.2, b = 0.75;
    final avg = _totalLength / n;
    // idf ของชิ้นที่มีในเอกสารเดียว = หน่วยของคะแนน
    final unit = math.log(1 + (n - 0.5) / 1.5);
    if (unit <= 0) return const [];
    final acc = <String, double>{};
    for (final g in q) {
      final docs = _postings[g];
      if (docs == null) continue;
      final df = docs.length;
      final idf = math.log(1 + (n - df + 0.5) / (df + 0.5));
      docs.forEach((id, tf) {
        if (exclude.contains(id)) return;
        final len = _lengths[id]!;
        final w = idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * len / avg));
        acc[id] = (acc[id] ?? 0) + w;
      });
    }
    final hits = [
      for (final e in acc.entries)
        if (e.value / unit >= minScore) RecallHit(e.key, e.value / unit),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList();
  }

  // ── เตรียมข้อความ ─────────────────────────────────────────

  static final _tone = RegExp('[็-๎]'); // ็ ่ ้ ๊ ๋ ์ ํ ๎
  static final _split = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);
  static final _latin = RegExp(r'^[a-z0-9]+$');
  static final _number = RegExp(r'^[0-9]+$');
  static final _hyphen = RegExp(r'(?<=[a-z0-9])-(?=[a-z0-9])');

  /// คำอังกฤษที่อยู่ในทุกประโยค · ไม่บอกว่าเรื่องอะไร
  static const _latinStop = {
    'the', 'is', 'are', 'a', 'an', 'of', 'to', 'and', 'in', 'on', 'for', 'at',
    'it', 'i', 'me', 'my', 'you', 'your', 'he', 'she', 'we', 'do', 'does',
    'what', 'when', 'where', 'how', 'can', 'be', 'was', 'this', 'that', 'with',
  };

  /// ตัวพิมพ์เล็ก · ตัดวรรณยุกต์/การันต์ · เลขไทยเป็นเลขอารบิก · wi-fi = wifi
  @visibleForTesting
  static String normalize(String s) {
    final lower = s
        .toLowerCase()
        .replaceAll(_tone, '')
        .replaceAll('ๆ', '')
        .replaceAll(_hyphen, '');
    final out = StringBuffer();
    for (final c in lower.runes) {
      out.writeCharCode(c >= 0x0E50 && c <= 0x0E59 ? c - 0x0E50 + 0x30 : c);
    }
    return out.toString();
  }

  /// ชิ้นตัวอักษร · คำละตินทั้งคำเป็นหนึ่งชิ้น (ภาษาอังกฤษเว้นวรรคอยู่แล้ว)
  @visibleForTesting
  static List<String> grams(String text) {
    final out = <String>[];
    for (final chunk in normalize(text).split(_split)) {
      if (chunk.isEmpty) continue;
      if (_number.hasMatch(chunk)) {
        out.add('n:$chunk'); // "ห้อง 5" ต้องค้นด้วยเลข 5 ได้ แม้เลขหลักเดียว
        continue;
      }
      if (_latin.hasMatch(chunk)) {
        if (chunk.length >= 2 && !_latinStop.contains(chunk)) out.add('w:$chunk');
        continue;
      }
      if (chunk.length < 2) continue;
      for (var i = 0; i + 2 <= chunk.length; i++) {
        out.add(chunk.substring(i, i + 2));
      }
      for (var i = 0; i + 3 <= chunk.length; i++) {
        out.add(chunk.substring(i, i + 3));
      }
    }
    return out;
  }

  /// คำที่อยู่ในแทบทุกประโยคคุยเล่น ไม่บอกว่าคุยเรื่องอะไร · ตัดออกจาก**คำถาม**
  ///
  /// เลือกเฉพาะคำที่ยาวพอและแทบไม่เป็นส่วนของคำอื่น ("คะ" ไม่อยู่ในนี้เพราะ
  /// อยู่ใน "คะแนน") · ที่เหลือปล่อยให้ IDF จัดการ
  static const _chatter = [
    'ครับ', 'ค่ะ', 'หน่อย', 'ไหม', 'มั้ย', 'อะไร', 'ยังไง', 'อย่างไร',
    'หรือเปล่า', 'รึเปล่า', 'เธอ', 'ฉัน', 'มายด์', 'จำได้', 'รู้ไหม', 'บอกหน่อย',
    'what', 'do you', 'remember', 'tell me', 'please',
  ];

  @visibleForTesting
  static String stripChatter(String q) {
    var s = q.toLowerCase();
    for (final w in _chatter) {
      s = s.replaceAll(w, ' ');
    }
    return s;
  }

  /// ใกล้เคียงกันแค่ไหน (0..1) · ใช้หาข้อเดิมที่เรื่องใหม่มาแทน
  static double similarity(String a, String b) => compare(a, b).jaccard;

  /// [jaccard] สัดส่วนชิ้นที่ตรงกัน · [diff] จำนวนชิ้นที่มีฝั่งเดียว
  ///
  /// ต้องมีทั้งสองค่า · ประโยคยาวที่ต่างกันแค่คำสำคัญคำเดียว ("ไปสยามเพื่อวิ่ง"
  /// / "ไปสีลมเพื่อวิ่ง") มีสัดส่วนตรงกันสูงทั้งที่เป็นคนละเรื่อง · จำนวนชิ้นที่
  /// ต่างกันบอกได้ว่าต่างแค่คำลงท้าย (สองสามชิ้น) หรือต่างที่เนื้อ
  static ({double jaccard, int diff}) compare(String a, String b) {
    bool keep(String g) => g.length == 3 || g.startsWith('w:') || g.startsWith('n:');
    final x = grams(a).where(keep).toSet();
    final y = grams(b).where(keep).toSet();
    if (x.isEmpty || y.isEmpty) {
      return (jaccard: a.trim() == b.trim() ? 1 : 0, diff: x.length + y.length);
    }
    final inter = x.intersection(y).length;
    return (
      jaccard: inter / (x.length + y.length - inter),
      diff: x.length + y.length - 2 * inter,
    );
  }
}
