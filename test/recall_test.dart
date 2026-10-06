/// นึกออกตามเรื่องที่ถาม — ไม่ใช่ท่องความจำ 60 ข้อล่าสุดทุกครั้ง
///
/// ที่มา: เจ้าของถาม "ระบบ RAG ของเธอ ความทรงจำของเธอ ใช้งานได้ดีหรือยัง" ·
/// ของเดิมเรื่องเก่าที่ไม่ได้ปักหมุดหลุดจาก prompt ถาวรเมื่อจำเกิน 60 ข้อ
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/memory/recall.dart';

/// ความจำ 120 ข้อแบบที่สะสมจริง · เรื่องที่ต้องหาฝังอยู่ในกอง
RecallIndex _memories() {
  final idx = RecallIndex();
  const filler = [
    'เจ้าของชอบดื่มกาแฟดำตอนเช้า',
    'เจ้าของประชุมทีมทุกวันอังคารสิบโมง',
    'คุณต้นเป็นหัวหน้าฝ่ายขาย',
    'เจ้าของไม่ชอบให้ตอบยาว',
    'เจ้าของออกกำลังกายตอนเย็นวันพุธ',
    'น้องเมย์เป็นน้องสาวของเจ้าของ',
    'เจ้าของใช้รถฮอนด้าซีวิค',
    'เจ้าของชอบฟังเพลงแจ๊ส',
    'เจ้าของทำงานที่สีลม',
    'เจ้าของตื่นตีห้าครึ่ง',
  ];
  for (var i = 0; i < 120; i++) {
    idx.put('f$i', '${filler[i % filler.length]} (เรื่องที่ $i)');
  }
  idx.put('shrimp', 'เจ้าของแพ้กุ้ง กินแล้วผื่นขึ้น');
  idx.put('mom', 'วันเกิดคุณแม่ของเจ้าของคือ 14 กุมภาพันธ์');
  idx.put('dog', 'เจ้าของเลี้ยงหมาชื่อโบโบ้ พันธุ์ชิวาว่า');
  idx.put('wifi', "The office Wi-Fi network is called XMAN-5G");
  return idx;
}

void main() {
  group('🔴 เจอเรื่องเก่าที่ฝังอยู่ในกอง', () {
    final idx = _memories();

    test('ถามเรื่องอาหาร → เจอว่าแพ้กุ้ง', () {
      final hits = idx.search('เย็นนี้สั่งต้มยำกุ้งดีไหม');
      expect(hits.first.id, 'shrimp');
    });

    test('ถามวันเกิดแม่ → เจอ', () {
      expect(idx.search('วันเกิดแม่ฉันวันไหนนะ').first.id, 'mom');
    });

    test('ชื่อหมา (ชื่อเฉพาะ) → เจอ', () {
      expect(idx.search('โบโบ้ป่วย ทำไงดี').first.id, 'dog');
    });

    test('ภาษาอังกฤษก็เจอ', () {
      expect(idx.search('what is the office wifi?').first.id, 'wifi');
    });

    test('พิมพ์วรรณยุกต์ผิดยังเจอ', () {
      expect(idx.search('แพกุง').first.id, 'shrimp');
    });
  });

  group('ไม่ดึงของที่ไม่เกี่ยวมาให้รก', () {
    final idx = _memories();

    test('ทักทายเฉย ๆ = ไม่มีอะไรเกี่ยว', () {
      expect(idx.search('สวัสดีค่ะ เป็นไงบ้าง'), isEmpty);
      expect(idx.search('ครับ'), isEmpty);
    });

    test('คำถามที่ไม่มีในความจำ = ไม่เจอเรื่องแพ้กุ้ง', () {
      final hits = idx.search('พรุ่งนี้ฝนตกไหม');
      expect(hits.map((h) => h.id), isNot(contains('shrimp')));
    });

    test('ตัดของที่อยู่ในบทสนทนาแล้วออกได้', () {
      final hits = idx.search('แพ้กุ้ง', exclude: {'shrimp'});
      expect(hits.map((h) => h.id), isNot(contains('shrimp')));
    });
  });

  group('ใส่/ลบทีละรายการ', () {
    test('ลบแล้วค้นไม่เจอ · แก้แล้วค้นด้วยข้อความใหม่', () {
      final idx = RecallIndex()
        ..put('a', 'เจ้าของอยู่กรุงเทพ')
        ..put('b', 'เจ้าของชอบแมว');
      idx.put('a', 'เจ้าของย้ายไปอยู่เชียงใหม่แล้ว');
      expect(idx.search('กรุงเทพ'), isEmpty);
      expect(idx.search('เชียงใหม่').single.id, 'a');
      idx.remove('a');
      expect(idx.search('เชียงใหม่'), isEmpty);
      expect(idx.size, 1);
    });
  });

  group('ความใกล้เคียง — กันจำซ้ำที่เขียนต่างนิดเดียว', () {
    test('เรื่องเดียวกันคนละถ้อยคำเล็กน้อย = ใกล้มาก', () {
      expect(RecallIndex.similarity('เจ้าของแพ้กุ้ง', 'เจ้าของแพ้กุ้งค่ะ'), greaterThan(0.7));
      expect(RecallIndex.similarity('เจ้าของชอบกาแฟดำ', 'เจ้าของชอบกาแฟดำ ไม่ใส่น้ำตาล'),
          greaterThan(0.45));
    });

    test('คนละเรื่อง = ห่าง', () {
      expect(RecallIndex.similarity('เจ้าของแพ้กุ้ง', 'เจ้าของชอบแมว'), lessThan(0.3));
    });
  });

  test('ตัดวรรณยุกต์และแปลงเลขไทย', () {
    expect(RecallIndex.normalize('ก้อง ๑๒๓'), 'กอง 123');
  });
}
