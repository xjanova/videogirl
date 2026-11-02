/// ดัชนีค้นข้อความไทยในเครื่อง · ใช้ร่วมกันระหว่างคลังข้อมูลสาย (CallKnowledge)
/// กับแพ็กความรู้ (KnowledgePacks)
///
/// ภาษาไทยไม่มีช่องว่างระหว่างคำ จึงเทียบด้วยชิ้นตัวอักษรสามตัว (trigram) แทนคำ ·
/// ชิ้นที่พบบ่อยทั่วคลังมีน้ำหนักน้อย (idf) · สร้างในเธรดแยก
/// (คลังเต็มล้านตัวอักษรสร้างบนเธรดหลัก = เสียงในสายสะดุดครึ่งวินาที แชทกระตุก)
///
/// 🔴 แยกออกมาจาก call_knowledge.dart ไม่ใช่ก๊อป · ตัวค้นสองชุดที่หน้าตาเหมือนกัน
/// วันหนึ่งจะแก้บั๊กที่ชุดเดียวแล้วอีกชุดไม่ตาม
library;

import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// เอกสารหนึ่งชิ้นที่จะเข้าดัชนี · [tag] ให้ผู้เรียกรู้ว่าท่อนที่เจอมาจากไหน (เช่น รหัสแพ็ก)
typedef KnowledgeDoc = ({String title, String text, String tag});

@immutable
class KnowledgeHit {
  const KnowledgeHit(this.title, this.text, this.score, {this.tag = ''});
  final String title;
  final String text;
  final double score;
  final String tag;
}

class KnowledgeChunk {
  KnowledgeChunk(this.title, this.text, this.tag, this.grams);
  final String title;
  final String text;
  final String tag;
  final Set<int> grams;
}

class KnowledgeIndex {
  KnowledgeIndex(this.chunks, this.df);

  /// ความยาวท่อน · พอให้เธออ่านตอบในสาย และไม่ล้น prompt ของแชท
  static const chunkChars = 600;

  final List<KnowledgeChunk> chunks;
  final Map<int, int> df;

  bool get isEmpty => chunks.isEmpty;

  /// สร้างในเธรดแยก · static = closure ไม่ติด `this` ของผู้เรียก (ตัวต่อเน็ตส่งข้ามเธรดไม่ได้)
  static Future<KnowledgeIndex> buildInBackground(List<KnowledgeDoc> docs) => Isolate.run(() => build(docs));

  /// ตัดแต่ละเอกสารเป็นท่อนละ ~600 ตัวอักษร แล้วนับว่าชิ้นไหนพบในกี่ท่อน
  static KnowledgeIndex build(List<KnowledgeDoc> docs) {
    final chunks = <KnowledgeChunk>[];
    for (final (:title, :text, :tag) in docs) {
      final buf = StringBuffer();
      void flush() {
        final t = buf.toString().trim();
        if (t.isNotEmpty) chunks.add(KnowledgeChunk(title, t, tag, grams('$title $t')));
        buf.clear();
      }

      for (final line in text.split('\n')) {
        if (buf.length + line.length > chunkChars && buf.isNotEmpty) flush();
        // บรรทัดยาวมาก (หน้าเว็บที่ไม่มีขึ้นบรรทัด) ตัดเป็นท่อน
        for (var i = 0; i < line.length; i += chunkChars) {
          buf.writeln(line.substring(i, math.min(line.length, i + chunkChars)));
          if (buf.length >= chunkChars) flush();
        }
      }
      flush();
    }
    final df = <int, int>{};
    for (final c in chunks) {
      for (final g in c.grams) {
        df[g] = (df[g] ?? 0) + 1;
      }
    }
    return KnowledgeIndex(chunks, df);
  }

  /// ท่อนที่ตรงคำถามที่สุด · ว่าง = ไม่มีเรื่องนี้ (ให้เธอบอกตามจริง ไม่แต่ง)
  ///
  /// [minCover] = สัดส่วนจำนวนชิ้นของคำถามที่ต้องเจอในท่อน · สายใช้ 0.25 (คนโทรถามเรื่องในคลังอยู่แล้ว)
  ///
  /// แชทค้นทุกข้อความรวมคำทักทาย ใช้ [minShare] กับ [minEvidence] แทน · นับจำนวนชิ้นอย่างเดียว
  /// ใช้กับคำถามไทยในแชทไม่ได้ (วัดกับแพ็กตัวอย่าง 2026-11-02: "โดนงูกัดต้องทำยังไง" ไม่เจอ
  /// แต่ "วันนี้เหนื่อยจัง" เจอ) เพราะชิ้นคร่อมรอยต่อคำมีเยอะ:
  /// - [minShare] = สัดส่วน "น้ำหนัก" (idf) ของคำถามที่เจอในท่อน · ชิ้นที่ไม่มีในคลังเลย (นาฬิกาปลุก, ไลน์)
  ///   หนักเท่าชิ้นหายากที่สุด = ข้อความที่พูดเรื่องอื่นตกไปเอง
  /// - [minEvidence] = หลักฐานขั้นต่ำ หน่วยเป็น "ชิ้นที่มีในท่อนเดียว" · ข้อความสั้นที่บังเอิญซ้ำคำ
  ///   ทั่วไปสองสามคำไม่ผ่าน
  /// - [minRun] = ต้องมีชิ้นที่ตรงต่อกันในคำถามอย่างน้อยเท่านี้ (3 = ช่วงที่ตรงยาว 5 ตัวอักษรขึ้นไป) ·
  ///   เศษสั้น ๆ ที่บังเอิญซ้ำกระจายทั่วประโยคไม่นับ ("คิดถึงจังเลย" เคยไปตรงหัวข้อแบตโทรศัพท์
  ///   ด้วย "ถึง" กับ "จังเ") · คำที่ตรงครบทั้งคำ (คำอังกฤษ "fire" มีแค่สองชิ้น) นับผ่าน
  List<KnowledgeHit> search(String query,
      {int limit = 3, double minCover = 0.25, double minShare = 0, double minEvidence = 0, int minRun = 1}) {
    final seq = gramSeq(query);
    final q = {for (final g in seq) if (g >= 0) g};
    if (q.isEmpty || chunks.isEmpty) return const [];
    final n = chunks.length;
    final unit = math.log(1 + n);
    var mass = 0.0;
    if (minShare > 0) {
      for (final g in q) {
        final d = df[g];
        mass += d == null ? unit : math.log(1 + n / d);
      }
    }
    final scored = <KnowledgeHit>[];
    for (final c in chunks) {
      var score = 0.0, matched = 0;
      for (final g in q) {
        if (!c.grams.contains(g)) continue;
        matched++;
        score += math.log(1 + n / (df[g] ?? 1));
      }
      // ต้องตรงพอสมควร · เจอแค่ชิ้นสองชิ้นที่บังเอิญซ้ำ = ไม่นับ
      if (matched < math.min(2, q.length) || matched < q.length * minCover) continue;
      if (score < minEvidence * unit || score < mass * minShare) continue;
      if (minRun > 1 && !_hasRun(seq, c.grams, minRun)) continue;
      scored.add(KnowledgeHit(c.title, c.text, score / (1 + math.log(1 + c.grams.length / 50)), tag: c.tag));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList(growable: false);
  }

  /// มีชิ้นที่ตรงต่อกันตามลำดับในคำถามถึง [min] ไหม · หรือช่วงคำ (คั่นด้วย -1 ใน [seq]) ยาวสองชิ้นขึ้นไป
  /// ที่ตรงครบทั้งช่วง
  static bool _hasRun(List<int> seq, Set<int> have, int min) {
    var run = 0, len = 0;
    for (final g in seq) {
      if (g < 0) {
        if (len >= 2 && run == len) return true;
        run = len = 0;
        continue;
      }
      len++;
      run = have.contains(g) ? run + 1 : 0;
      if (run >= min) return true;
    }
    return false;
  }

  static final _breaks = RegExp(r'[\s\p{P}\p{S}]+', unicode: true);
  static final _invisible = RegExp(r'[​-‍⁠﻿]');

  // เขียนเป็นรหัสตัวอักษร · ตัวสแกนข้อความไทยในโค้ด (i18n_test) จะได้ไม่นับเป็นข้อความบนจอ
  static final _amSplit = String.fromCharCodes(const [0x0E4D, 0x0E32]), _am = String.fromCharCode(0x0E33);
  static final _aeSplit = String.fromCharCodes(const [0x0E40, 0x0E40]), _ae = String.fromCharCode(0x0E41);

  /// ชิ้นตัวอักษรสามตัวของแต่ละช่วงคำ (ตัดที่ช่องว่างและเครื่องหมาย) · ช่วงสั้นกว่าสามตัวใช้ทั้งช่วง
  ///
  /// อัดเป็นตัวเลข (16 บิตต่อตัวอักษร) · ชุดของตัวเลขกินเครื่องน้อยกว่าชุดของสตริงหลายเท่า
  /// · ทำให้เหมือนกันก่อน: ตัดอักขระล่องหน (เว็บไทยแทรกไว้ตัดบรรทัด) ·
  /// นิคหิต+สระอา = สระอำ · เอ+เอ = แอ (พิมพ์ได้สองแบบ หน้าตาเหมือนกัน)
  static Set<int> grams(String text) => {for (final g in gramSeq(text)) if (g >= 0) g};

  /// ชิ้นเรียงตามลำดับในข้อความ ซ้ำได้ · -1 คั่นระหว่างช่วงคำ (ใช้หาช่วงที่ตรงต่อกัน ดู [search])
  static List<int> gramSeq(String text) {
    final norm = text
        .toLowerCase()
        .replaceAll(_invisible, '')
        .replaceAll(_amSplit, _am)
        .replaceAll(_aeSplit, _ae);
    final out = <int>[];
    for (final run in norm.split(_breaks)) {
      final u = run.codeUnits;
      if (u.isEmpty) continue;
      if (u.length < 3) {
        out.add(u.length << 48 | (u.length > 1 ? u[1] << 16 : 0) | u[0]);
      } else {
        for (var i = 0; i + 3 <= u.length; i++) {
          out.add(3 << 48 | u[i + 2] << 32 | u[i + 1] << 16 | u[i]);
        }
      }
      out.add(-1);
    }
    return out;
  }
}
