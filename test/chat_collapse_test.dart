import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/state/mind_state.dart';

/// แผงแชทพับเองเมื่อเงียบ — มีสองจังหวะที่ถ้าพลาดแล้วผู้ใช้ด่าทันที
///
/// 1. พับตอนเธอกำลังพูด = คำตอบหายไปกลางประโยค
/// 2. พับตอนคนกำลังพิมพ์ = แผงหายพร้อมคีย์บอร์ดระหว่างพิมพ์ค้างอยู่
///
/// ทั้งคู่เป็นเรื่อง**เวลา** ซึ่งไล่ด้วยการแคปหน้าจอไม่ได้ ต้องคุมนาฬิกาเอง
/// (บทเรียนเดียวกับฟองคำพูดที่เคยนับผิดจังหวะจนไม่เคยโผล่ให้เห็นเลย)
void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('เงียบครบเวลาแล้วพับเอง', () {
    fakeAsync((async) {
      final s = MindState();
      s.openChat();
      expect(s.chatOpen, isTrue);

      async.elapse(const Duration(seconds: MindState.chatIdleSeconds - 1));
      expect(s.chatOpen, isTrue, reason: 'ยังไม่ครบเวลา ไม่ควรพับ');

      async.elapse(const Duration(seconds: 2));
      expect(s.chatOpen, isFalse);
      s.dispose();
    });
  });

  test('🔴 กำลังพิมพ์อยู่ ห้ามพับ ไม่ว่าจะนานแค่ไหน', () {
    fakeAsync((async) {
      final s = MindState();
      s.openChat();
      s.setTyping(true);

      async.elapse(const Duration(minutes: 5));
      expect(s.chatOpen, isTrue,
          reason: 'แผงหายพร้อมคีย์บอร์ดระหว่างพิมพ์ค้าง = แย่ที่สุด');
      s.dispose();
    });
  });

  test('พิมพ์เสร็จแล้วเริ่มนับใหม่ ไม่ใช่นับต่อจากของเดิม', () {
    fakeAsync((async) {
      final s = MindState();
      s.openChat();
      s.setTyping(true);
      async.elapse(const Duration(minutes: 2));

      s.setTyping(false);
      async.elapse(const Duration(seconds: MindState.chatIdleSeconds - 1));
      expect(s.chatOpen, isTrue, reason: 'ต้องเริ่มนับใหม่ตั้งแต่ต้น');

      async.elapse(const Duration(seconds: 2));
      expect(s.chatOpen, isFalse);
      s.dispose();
    });
  });

  test('แตะเรียกกลับมาได้ และนาฬิกาเริ่มใหม่', () {
    fakeAsync((async) {
      final s = MindState();
      s.openChat();
      async.elapse(const Duration(seconds: MindState.chatIdleSeconds + 1));
      expect(s.chatOpen, isFalse);

      s.openChat();
      expect(s.chatOpen, isTrue);
      async.elapse(const Duration(seconds: MindState.chatIdleSeconds - 1));
      expect(s.chatOpen, isTrue, reason: 'เปิดใหม่แล้วต้องได้เวลาเต็ม');
      s.dispose();
    });
  });

  test('สั่งพับเองได้ทันที ไม่ต้องรอหมดเวลา', () {
    fakeAsync((async) {
      final s = MindState();
      s.openChat();
      s.collapseChat();
      expect(s.chatOpen, isFalse);
      s.dispose();
    });
  });
}
