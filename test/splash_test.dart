import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/screens/splash_screen.dart';

/// หน้าเปิดแอปมีหน้าที่เดียวที่ห้ามพลาด — **ต้องปล่อยคนเข้าแอปเสมอ**
///
/// เทสต์นี้ไม่ได้ตรวจว่าวิดีโอสวยไหม (ตรวจไม่ได้และไม่ใช่ประเด็น)
/// แต่ตรวจว่าเมื่อตัวเล่นวิดีโอ **เปิดไม่ขึ้น** หน้าเปิดยังยอมหลบให้
/// ในเทสต์ไม่มีปลั๊กอินฝั่ง native อยู่จริง `initialize()` จึงโยน
/// MissingPluginException ซึ่งเป็นตัวแทนที่ตรงเป๊ะของ "โคเดกพัง / ไฟล์หาย"
/// บนเครื่องจริง — เป็นทางที่ถ้าพลาดจะได้จอค้างถาวรโดยไม่มี error ที่ไหนบอก
void main() {
  testWidgets('คลิปจบแล้วแต่แอปยังโหลดไม่เสร็จ ต้องค้างหน้าเปิดไว้ก่อน',
      (tester) async {
    var done = false;
    // appReady:false = ของหนักยังโหลดไม่เสร็จ · วิดีโอเปิดไม่ขึ้นในเทสต์อยู่แล้ว
    // จึงเท่ากับกรณี "คลิปจบทันที" ซึ่งเป็นกรณีที่ต้องไม่ปล่อยผ่าน
    await tester.pumpWidget(MaterialApp(
      home: MindSplash(appReady: false, onDone: () => done = true),
    ));
    await tester.pumpAndSettle();
    expect(done, isFalse,
        reason: 'ปล่อยเข้าแอปก่อนของพร้อม = เจอจอเปล่าที่ยังไม่มีอะไร');

    // พอพร้อมแล้วค่อยปล่อย
    await tester.pumpWidget(MaterialApp(
      home: MindSplash(appReady: true, onDone: () => done = true),
    ));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });

  testWidgets('วิดีโอเปิดไม่ขึ้น ต้องไม่กั้นทางเข้าแอป', (tester) async {
    var done = false;

    await tester.pumpWidget(MaterialApp(
      home: MindSplash(appReady: true, onDone: () => done = true),
    ));

    await tester.pumpAndSettle();

    // ไม่ยืนยันว่า**เฟรมไหน** ที่มันหลบ — จังหวะ pump เป็นรายละเอียดภายใน
    // ที่เปลี่ยนได้ ยืนยันแค่ว่าสุดท้ายมันต้องหลบ
    expect(done, isTrue,
        reason: 'ตัวเล่นวิดีโอพังแล้วหน้าเปิดไม่ยอมหลบ = เข้าแอปไม่ได้เลย');
  });

  testWidgets('ระหว่างรอ ต้องมีพื้นทึบ ไม่ใช่จอโปร่งเห็นเชลล์ที่ยังไม่พร้อม',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MindSplash(appReady: true, onDone: () {}),
    ));

    expect(find.byType(ColoredBox), findsWidgets);
    await tester.pumpAndSettle();
  });

  test('ป้ายข้ามมีครบสองภาษาและไม่ซ้ำกัน', () {
    const th = S(AppLang.th), en = S(AppLang.en);
    expect(th.splashSkip, isNotEmpty);
    expect(en.splashSkip, isNotEmpty);
    expect(th.splashSkip, isNot(en.splashSkip));
  });
}
