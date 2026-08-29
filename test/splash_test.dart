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
  testWidgets('วิดีโอเปิดไม่ขึ้น ต้องไม่กั้นทางเข้าแอป', (tester) async {
    var done = false;

    await tester.pumpWidget(MaterialApp(
      home: SplashOverlay(onDone: () => done = true),
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
      home: SplashOverlay(onDone: () {}),
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
