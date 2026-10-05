/// สมองในเครื่องตอบช้า — สิ่งที่แก้ได้โดยไม่ต้องมีเครื่องจริง
///
/// 1. การสกัดความจำต้องไม่แย่งคิวของคำถามถัดไป (สมองในเครื่องคิดได้ทีละงาน
///    และการสกัดปิดบทสนทนาที่เปิดค้างไว้ทิ้ง)
/// 2. ตัวเลขความเร็วที่โชว์ในหน้าตั้งค่าต้องคิดถูก — ตัวเลขผิดคือการชี้ผิดจุด
library;

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/brain_provider.dart';
import 'package:videogirl/ai/local_brain.dart';
import 'package:videogirl/memory/distiller.dart';
import 'package:videogirl/state/mind_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  void chat(MindState s, int turns) {
    for (var i = 0; i < turns; i++) {
      s.debugPush(false, 'คำถามที่ $i');
      s.debugPush(true, 'คำตอบที่ $i');
    }
  }

  test('🔴 สมองในเครื่อง: ครบรอบสกัดแล้วรอให้ว่างก่อน ไม่สกัดทันทีหลังตอบ', () {
    final s = MindState()..setBrain(BrainProvider.onDevice);
    chat(s, kDistillEvery);

    expect(s.debugDistilPending, isTrue,
        reason: 'สกัดทันที = คำถามถัดไปต้องรอสมองสกัดจบ แล้วอ่านบทใหม่ทั้งหมด');
    expect(s.debugSinceDistill, kDistillEvery,
        reason: 'ยังไม่ได้สกัด ต้องยังนับตาที่ค้างไว้ ไม่งั้นตาพวกนี้หายไปจากความจำ');

    // คุยต่ออีก = ยังรออยู่ และนับต่อ
    chat(s, 2);
    expect(s.debugDistilPending, isTrue);
    expect(s.debugSinceDistill, kDistillEvery + 2);
    s.dispose();
  });

  test('สมองผ่านเน็ต: สกัดทันทีเหมือนเดิม (ไม่มีคิวให้แย่ง)', () {
    final s = MindState()..setBrain(BrainProvider.openai);
    chat(s, kDistillEvery);
    expect(s.debugDistilPending, isFalse);
    expect(s.debugSinceDistill, 0);
    s.dispose();
  });

  group('ตัวเลขความเร็ว', () {
    const stats = LocalReplyStats(
      variant: GemmaVariant.e2bCpu,
      backend: PreferredBackend.gpu,
      loadMs: 6000,
      newSession: true,
      firstMs: 1500,
      totalMs: 3500,
      chars: 120,
    );

    test('ความเร็วนับเฉพาะช่วงพิมพ์คำตอบ ไม่รวมช่วงอ่านคำถาม', () {
      expect(stats.charsPerSecond, closeTo(60, 0.01));
    });

    test('เวลารอคำแรกรวมเวลาเปิดสมองด้วย — นั่นคือสิ่งที่คนรอจริง', () {
      expect(stats.waitMs, 7500);
    });

    test('ตอบคำเดียวทันที (ไม่มีช่วงพิมพ์) ไม่หารศูนย์', () {
      const instant = LocalReplyStats(
        variant: GemmaVariant.e2bCpu,
        backend: PreferredBackend.cpu,
        loadMs: null,
        newSession: false,
        firstMs: 800,
        totalMs: 800,
        chars: 3,
      );
      expect(instant.charsPerSecond, 0);
      expect(instant.waitMs, 800);
    });
  });
}
