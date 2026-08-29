import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/state/mind_state.dart';

/// ฟองคำพูดเหนือหัวเธอ — จังหวะการโผล่และหายไป
///
/// เขียนเทสต์เพราะทดสอบด้วยการแคปหน้าจอสู้จังหวะเวลาไม่ไหว
/// และบั๊กที่เจอตอนแรก (ฟองไม่เคยโผล่เลยเวลาเปิดเสียง) เป็นเรื่องของ
/// **ลำดับเวลา** ล้วน ๆ ซึ่งเทสต์จับได้ตรงกว่าและไม่หลุดอีก
void main() {
  group('ฟองคำพูด', () {
    test('โผล่เมื่อเธอพูด แล้วหายเองหลังครบเวลา', () {
      fakeAsync((async) {
        final s = MindState()..setBubbleSeconds(5);

        expect(s.bubbleVisible, isFalse, reason: 'ยังไม่มีใครพูด ฟองต้องไม่โผล่');

        s.send('ทดสอบ');
        async.flushMicrotasks();

        expect(s.bubbleVisible, isTrue, reason: 'เธอเพิ่งตอบ ฟองต้องโผล่');

        async.elapse(const Duration(seconds: 4));
        expect(s.bubbleVisible, isTrue, reason: 'ยังไม่ครบ 5 วิ ต้องยังอยู่');

        async.elapse(const Duration(seconds: 2));
        expect(s.bubbleVisible, isFalse, reason: 'ครบ 5 วิแล้ว ต้องหายไป');

        s.dispose();
      });
    });

    test('ปิดสวิตช์แล้วไม่โผล่เลย', () {
      fakeAsync((async) {
        final s = MindState()..setBubbleEnabled(false);
        s.send('ทดสอบ');
        async.flushMicrotasks();

        expect(s.bubbleVisible, isFalse);
        async.elapse(const Duration(seconds: 1));
        expect(s.bubbleVisible, isFalse);

        s.dispose();
      });
    });

    test('ตั้ง 0 วิ = ค้างไว้ ไม่หายเอง', () {
      fakeAsync((async) {
        final s = MindState()..setBubbleSeconds(0);
        s.send('ทดสอบ');
        async.flushMicrotasks();

        expect(s.bubbleVisible, isTrue);
        async.elapse(const Duration(minutes: 5));
        expect(s.bubbleVisible, isTrue, reason: '0 วิแปลว่าค้างไว้ ห้ามหาย');

        s.dispose();
      });
    });

    test('แตะตัวเธอเรียกฟองที่หายไปแล้วกลับมาได้', () {
      fakeAsync((async) {
        final s = MindState()..setBubbleSeconds(3);
        s.send('ทดสอบ');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        expect(s.bubbleVisible, isFalse);

        s.showBubbleAgain();
        expect(s.bubbleVisible, isTrue, reason: 'แตะแล้วต้องกลับมา');

        async.elapse(const Duration(seconds: 5));
        expect(s.bubbleVisible, isFalse, reason: 'แล้วต้องหายอีกครั้งตามเวลาเดิม');

        s.dispose();
      });
    });

    test('ข้อความของเราไม่ทำให้ฟองโผล่ ฟองเป็นของเธอเท่านั้น', () {
      fakeAsync((async) {
        final s = MindState()..setBubbleSeconds(5);
        s.send('ข้อความแรก');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 10));
        expect(s.bubbleVisible, isFalse);

        // ส่งใหม่ ระหว่างที่ยังไม่มีคำตอบ ฟองต้องยังไม่โผล่จากข้อความของเราเอง
        final before = s.bubbleText;
        s.send('ข้อความสอง');
        expect(s.bubbleText, before,
            reason: 'ฟองต้องยังเป็นคำพูดล่าสุดของเธอ ไม่ใช่ของเรา');

        s.dispose();
      });
    });
  });
}
