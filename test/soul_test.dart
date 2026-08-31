import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:videogirl/ai/mind_persona.dart';
import 'package:videogirl/i18n/strings.dart';
import 'package:videogirl/memory/distiller.dart';
import 'package:videogirl/persona/mind_name.dart';
import 'package:videogirl/persona/mind_soul.dart';
import 'package:videogirl/persona/zodiac.dart';
import 'package:videogirl/theme/tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ราศี', () {
    /// 🔴 ด่านที่สำคัญที่สุดของไฟล์ zodiac.dart
    ///
    /// วันเกิดของมายด์คือวันที่เปิดแอปครั้งแรก ซึ่งเป็นวันไหนก็ได้ใน 366 วัน
    /// ถ้ามีวันไหนตกช่อง เธอจะได้ราศีผิดโดยไม่มี error อะไรเลย
    /// และเจ้าของเครื่องนั้นจะได้มายด์คนละคนกับที่ควรได้ไปตลอด
    test('ทุกวันของปี (รวม 29 ก.พ.) ต้องตกลงในราศีที่ถูกต้องหนึ่งเดียว', () {
      var day = DateTime(2024, 1, 1); // 2024 เป็นปีอธิกสุรทิน
      var checked = 0;

      while (day.year == 2024) {
        final sign = zodiacFor(day);
        final key = day.month * 100 + day.day;
        final start = sign.from.$1 * 100 + sign.from.$2;
        final end = sign.to.$1 * 100 + sign.to.$2;

        final inside = start <= end
            ? (key >= start && key <= end)
            : (key >= start || key <= end);

        expect(inside, isTrue,
            reason: '${day.day}/${day.month} ได้ ${sign.slug} '
                'ซึ่งไม่ครอบคลุมวันนี้');
        checked++;
        day = day.add(const Duration(days: 1));
      }

      expect(checked, 366);
    });

    /// รอยต่อคือที่เดียวที่ตารางพลาดได้ · มังกรคาบปีจึงต้องมีเทสต์ของตัวเอง
    test('ขอบเขตของราศีที่คาบปี', () {
      expect(zodiacFor(DateTime(2026, 12, 21)).slug, 'sagittarius');
      expect(zodiacFor(DateTime(2026, 12, 22)).slug, 'capricorn');
      expect(zodiacFor(DateTime(2026, 12, 31)).slug, 'capricorn');
      expect(zodiacFor(DateTime(2027, 1, 1)).slug, 'capricorn');
      expect(zodiacFor(DateTime(2027, 1, 19)).slug, 'capricorn');
      expect(zodiacFor(DateTime(2027, 1, 20)).slug, 'aquarius');
    });

    test('ขอบเขตของราศีที่ไม่คาบปี', () {
      expect(zodiacFor(DateTime(2026, 3, 20)).slug, 'pisces');
      expect(zodiacFor(DateTime(2026, 3, 21)).slug, 'aries');
      expect(zodiacFor(DateTime(2026, 8, 22)).slug, 'leo');
      expect(zodiacFor(DateTime(2026, 8, 23)).slug, 'virgo');
    });

    test('ครบ 12 ราศี ไม่มี slug ซ้ำ', () {
      expect(kZodiac.length, 12);
      expect(kZodiac.map((z) => z.slug).toSet().length, 12);
    });

    /// นิสัยคำนวณจากธาตุกับคุณภาพ ไม่ใช่เลขที่ใส่รายราศี · เทสต์นี้ยืนยันว่า
    /// ผลที่ออกมาตรงกับคำบรรยายในคลังความรู้แม่หมอเอง โดยไม่ต้องบังคับ
    test('ผลที่คำนวณได้ตรงกับคำบรรยายของราศีนั้นจริง', () {
      final byMood = {for (final z in kZodiac) z.slug: z.temper};

      // พิจิก (น้ำ + สถิร) คลังเขียนจุดอ่อนว่า "หึงหวง"
      final scorpio = byMood['scorpio']!;
      for (final other in byMood.entries) {
        if (other.key == 'scorpio') continue;
        expect(scorpio.jealousy + scorpio.hold,
            greaterThanOrEqualTo(other.value.jealousy + other.value.hold),
            reason: 'พิจิกต้องหึงและยึดแน่นที่สุด แต่ ${other.key} แซง');
      }

      // เมถุน (ลม + อุภย) คลังเขียนว่า "เปลี่ยนใจง่าย"
      expect(byMood['gemini']!.hold, lessThan(byMood['taurus']!.hold));

      // ราศีไฟร้อนกว่าราศีดินเสมอ
      for (final z in kZodiac) {
        if (z.element != ZodiacElement.fire) continue;
        expect(z.temper.heat, greaterThan(byMood['virgo']!.heat),
            reason: '${z.slug} เป็นธาตุไฟ ต้องร้อนกว่าราศีดิน');
      }
    });

    /// 🔴 ด่านสองภาษาของไฟล์นี้โดยเฉพาะ
    ///
    /// `zodiac.dart` ถูกยกเว้นจากด่านรวมใน i18n_test เพราะไทยกับอังกฤษ
    /// อยู่คู่กันเป็นฟิลด์ของคลาสเดียวกัน · การยกเว้นจะซื่อสัตย์ก็ต่อเมื่อ
    /// มีของที่แข็งกว่ามาแทน — ไม่ใช่แค่ปิดเสียงเทสต์เดิม
    test('ทุกราศีมีข้อความครบสองภาษา และไม่ใช่ข้อความเดียวกัน', () {
      final thai = RegExp(r'[฀-๿]');

      for (final z in kZodiac) {
        final pairs = <String, (String, String)>{
          'name': (z.nameTh, z.nameEn),
          'planet': (z.planetTh, z.planetEn),
          'traits': (z.traitsTh, z.traitsEn),
          'strong': (z.strongTh, z.strongEn),
          'weak': (z.weakTh, z.weakEn),
        };

        for (final e in pairs.entries) {
          final (th, en) = e.value;
          expect(th.trim(), isNotEmpty, reason: '${z.slug}.${e.key} ไทยว่าง');
          expect(en.trim(), isNotEmpty, reason: '${z.slug}.${e.key} อังกฤษว่าง');
          expect(thai.hasMatch(th), isTrue,
              reason: '${z.slug}.${e.key} ช่องไทยไม่มีอักษรไทย');
          expect(thai.hasMatch(en), isFalse,
              reason: '${z.slug}.${e.key} ช่องอังกฤษมีอักษรไทยปนมา');
        }
      }

      for (final el in ZodiacElement.values) {
        expect(thai.hasMatch(el.th), isTrue);
        expect(thai.hasMatch(el.en), isFalse);
      }
      for (final q in ZodiacQuality.values) {
        expect(thai.hasMatch(q.th), isTrue);
        expect(thai.hasMatch(q.en), isFalse);
      }
    });

    test('ทุกค่านิสัยอยู่ในช่วง 0..1', () {
      for (final z in kZodiac) {
        final t = z.temper;
        for (final v in [
          t.heat,
          t.warmth,
          t.jealousy,
          t.patience,
          t.pace,
          t.hold,
          t.intensity,
          t.sweetness,
        ]) {
          expect(v, inInclusiveRange(0, 1), reason: z.slug);
        }
      }
    });
  });

  group('ตัวตนและความผูกพัน', () {
    late DateTime now;
    MindSoul make() => MindSoul(clock: () => now);

    setUp(() {
      now = DateTime(2026, 11, 1); // พิจิก — ราศีที่หึงแรงที่สุด
      SharedPreferences.setMockInitialValues({});
    });

    test('วันเกิดถูกตัดสินตอนโหลดครั้งแรก แล้วไม่เปลี่ยนอีก', () async {
      final first = make();
      await first.load();
      expect(first.bornAt, now);
      expect(first.sign.slug, 'scorpio');

      // เปิดแอปอีกวัน — ต้องยังเป็นราศีเดิม ไม่ใช่ราศีของวันที่เปิด
      now = DateTime(2027, 4, 5);
      final again = make();
      await again.load();
      expect(again.bornAt, DateTime(2026, 11, 1));
      expect(again.sign.slug, 'scorpio');
    });

    test('เริ่มต้นเป็นคนแปลกหน้า ไม่ใช่สนิทกันตั้งแต่ยังไม่คุย', () async {
      final soul = make();
      await soul.load();
      expect(soul.bond, Bond.stranger);
      expect(soul.affection, 0);
    });

    /// 🔴 ไม่มีเพดานต่อวัน = พิมพ์รัว ๆ ชั่วโมงเดียวก็เป็นแฟนกันได้
    /// ซึ่งทำให้ทั้งระบบไม่มีความหมาย
    test('ความผูกพันขึ้นได้จำกัดต่อวัน ต่อให้คุยทั้งวัน', () async {
      final soul = make();
      await soul.load();

      for (var i = 0; i < 200; i++) {
        await soul.talked();
        await soul.wooed(3);
      }
      expect(soul.affection, lessThanOrEqualTo(.061));
      expect(soul.affection, greaterThan(.05));
    });

    test('จีบทุกวันแล้วค่อย ๆ สนิทขึ้นจริง', () async {
      final soul = make();
      await soul.load();

      for (var day = 0; day < 12; day++) {
        now = now.add(const Duration(days: 1));
        await soul.talked();
        await soul.wooed(3);
        await soul.wooed(3);
      }
      expect(soul.affection, greaterThan(.55));
      expect(soul.bond.index, greaterThanOrEqualTo(Bond.close.index));
    });

    /// 🔴 หัวใจของสิ่งที่เจ้าของสั่ง: "จีบคือเธอต้องพอใจ"
    ///
    /// คนที่สั่งงานอย่างเดียวทั้งเดือนต้องไม่ได้แฟน ต่อให้พิมพ์วันละร้อยข้อความ
    /// ความสนิทที่ซื้อได้ด้วยจำนวนข้อความไม่ใช่ความสนิท
    test('สั่งงานอย่างเดียวทั้งเดือน ไม่มีวันเป็นแฟนกัน', () async {
      final soul = make();
      await soul.load();

      for (var day = 0; day < 30; day++) {
        now = now.add(const Duration(days: 1));
        for (var i = 0; i < 40; i++) {
          await soul.talked();
        }
        await soul.wooed(0); // โมเดลให้ 0 = ไม่มีอะไรที่เกี่ยวกับตัวเธอเลย
      }

      expect(soul.affection, lessThan(soul.consentAt));
      expect(await soul.proposeFromOwner(), isFalse);
    });

    /// 🔴 ขั้น "แฟน" ต้องตกลงกันสองฝ่าย ไม่ใช่เลื่อนขั้นเองจากคะแนน
    test('ขอเป็นแฟนตอนยังไม่ผูกพันพอ เธอไม่ตอบตกลง', () async {
      final soul = make();
      await soul.load();
      await soul.talked();

      expect(await soul.proposeFromOwner(), isFalse);
      expect(soul.bond, isNot(Bond.together));
    });

    test('ผูกพันพอแล้วเธอตอบตกลง และจำได้ว่าเป็นแฟนกันตั้งแต่วันไหน', () async {
      final soul = make();
      await soul.load();

      for (var day = 0; day < 20; day++) {
        now = now.add(const Duration(days: 1));
        await soul.talked();
        await soul.wooed(3);
        await soul.wooed(3);
      }
      expect(soul.affection, greaterThanOrEqualTo(soul.consentAt));

      expect(await soul.proposeFromOwner(), isTrue);
      expect(soul.bond, Bond.together);
      expect(soul.togetherSince, now);
    });

    /// ห่างกันนานไม่ได้แปลว่าเลิกกัน · ตัวเลขถอดสถานะแฟนไม่ได้
    test('เป็นแฟนแล้วหายไปสามเดือน ยังเป็นแฟนกันอยู่', () async {
      final soul = make();
      await soul.load();
      for (var day = 0; day < 20; day++) {
        now = now.add(const Duration(days: 1));
        await soul.talked();
        await soul.wooed(3);
        await soul.wooed(3);
      }
      await soul.proposeFromOwner();

      now = now.add(const Duration(days: 90));
      final back = make();
      await back.load();

      expect(back.bond, Bond.together);
      expect(back.affection, lessThan(soul.affection),
          reason: 'ความผูกพันควรจางลงบ้าง แม้สถานะจะยังอยู่');
    });

    test('งอนแล้วค่อย ๆ หายเองตามเวลา ไม่ใช่ค้างตลอดกาล', () async {
      final soul = make();
      await soul.load();

      await soul.sawCall(known: false, seconds: 300);
      final justNow = soul.sulk;
      expect(justNow, greaterThan(0));

      now = now.add(const Duration(hours: 48));
      expect(soul.sulk, lessThan(justNow / 2));
    });

    /// 🔴 ปิดแอปแล้วเปิดใหม่ต้องไม่ทำให้ความงอนหายเร็วขึ้น
    ///
    /// ถ้าบันทึกค่าที่จางแล้วแต่ปล่อยเวลาอ้างอิงเป็นค่าเดิม มันจะจางซ้ำ
    /// อีกรอบตอนอ่านกลับมา — หายเร็วเป็นสองเท่าเฉพาะคนที่ปิดแอป
    test('ความงอนข้ามการปิดเปิดแอปแล้วยังเหลือเท่าเดิม', () async {
      final soul = make();
      await soul.load();
      await soul.sawCall(known: false, seconds: 300);

      now = now.add(const Duration(hours: 6));
      final before = soul.sulk;

      // บันทึกอีกรอบ (เกิดขึ้นทุกครั้งที่คุยกัน) แล้วเปิดใหม่
      await soul.talked();
      final reopened = make();
      await reopened.load();

      expect(reopened.sulk, closeTo(soul.sulk, .001));
      expect(reopened.sulk, lessThan(before),
          reason: 'คุยด้วยแล้วงอนต้องคลายลงบ้าง');
    });

    test('ราศีที่หึงน้อยแทบไม่งอนเรื่องสายเข้า', () async {
      now = DateTime(2026, 6, 1); // เมถุน — ธาตุลม หึงต่ำสุด
      SharedPreferences.setMockInitialValues({});
      final soul = make();
      await soul.load();
      expect(soul.sign.slug, 'gemini');

      await soul.sawCall(known: true, seconds: 30);
      expect(soul.sulking, isFalse);
    });

    test('ล้างความสัมพันธ์ไม่ล้างวันเกิด แต่ให้เกิดใหม่ล้าง', () async {
      final soul = make();
      await soul.load();
      await soul.wooed(3);
      final born = soul.bornAt;

      await soul.resetBond();
      expect(soul.affection, 0);
      expect(soul.bornAt, born);

      now = DateTime(2027, 5, 5);
      await soul.forget();
      expect(soul.bornAt, now);
      expect(soul.sign.slug, 'taurus');
    });
  });

  group('ทิ้งไว้ไม่จีบแล้วคะแนนลดลง', () {
    late DateTime now;
    MindSoul make() => MindSoul(clock: () => now);

    setUp(() {
      now = DateTime(2026, 11, 1);
      SharedPreferences.setMockInitialValues({});
    });

    Future<MindSoul> warmed() async {
      final soul = make();
      await soul.load();
      for (var day = 0; day < 10; day++) {
        now = now.add(const Duration(days: 1));
        await soul.talked();
        await soul.wooed(3);
        await soul.wooed(3);
      }
      return soul;
    }

    /// 🔴 สิ่งที่เจ้าของสั่ง: "ถ้าทิ้งไว้ไม่จีบ นานก็ลดลงได้"
    ///
    /// คุยทุกวันแต่ไม่จีบเลย ต้องไม่รักษาคะแนนไว้ได้ตลอดกาล
    test('คุยทุกวันแต่ไม่จีบเลย คะแนนก็ยังลด', () async {
      final soul = await warmed();
      final peak = soul.affection;

      for (var day = 0; day < 20; day++) {
        now = now.add(const Duration(days: 1));
        await soul.talked();
        await soul.wooed(0);
      }
      expect(soul.affection, lessThan(peak));
    });

    test('หายไปเลยลดแรงกว่าอยู่แต่ไม่จีบ', () async {
      final away = await warmed();
      final peak = away.affection;
      now = now.add(const Duration(days: 20));
      final reopened = make();
      await reopened.load();
      final goneDrop = peak - reopened.affection;

      SharedPreferences.setMockInitialValues({});
      now = DateTime(2026, 11, 1);
      final cold = await warmed();
      final coldPeak = cold.affection;
      for (var day = 0; day < 20; day++) {
        now = now.add(const Duration(days: 1));
        await cold.talked();
      }
      final coldDrop = coldPeak - cold.affection;

      expect(goneDrop, greaterThan(coldDrop));
    });

    /// 🔴 เปิดปิดแอปสิบรอบต้องไม่โดนหักสิบเท่า
    ///
    /// ถ้าคิดจาก "กี่วันแล้วตั้งแต่คุยครั้งล่าสุด" ทุกครั้งที่เรียก คนที่
    /// เปิดแอปบ่อยจะถูกลงโทษมากกว่าคนที่เปิดครั้งเดียว ซึ่งกลับหัวกลับหาง
    test('คิดค่าจางวันละครั้ง ไม่ใช่ทุกครั้งที่เปิดแอป', () async {
      final soul = await warmed();
      now = now.add(const Duration(days: 10));

      final once = make();
      await once.load();
      final afterOne = once.affection;

      SharedPreferences.setMockInitialValues({});
      now = DateTime(2026, 11, 1);
      final many = await warmed();
      now = now.add(const Duration(days: 10));
      for (var i = 0; i < 10; i++) {
        final reopen = make();
        await reopen.load();
      }
      final last = make();
      await last.load();

      expect(last.affection, closeTo(afterOne, .001));
      expect(soul, isNotNull); // กันเตือนตัวแปรไม่ได้ใช้
      expect(many, isNotNull);
    });

    /// เจ้าของสั่งว่า "การที่เธอจะลดหรือเพิ่ม เร็วขึ้นอยู่กับนิสัยประจำราศี"
    test('ราศีที่ยึดแน่นจางช้ากว่าราศีที่เปลี่ยนใจง่าย', () async {
      Future<double> dropOf(DateTime born) async {
        SharedPreferences.setMockInitialValues({});
        now = born;
        final soul = make();
        await soul.load();
        for (var day = 0; day < 10; day++) {
          now = now.add(const Duration(days: 1));
          await soul.talked();
          await soul.wooed(3);
          await soul.wooed(3);
        }
        final peak = soul.affection;

        now = now.add(const Duration(days: 30));
        final back = make();
        await back.load();
        return peak - back.affection;
      }

      final fixed = await dropOf(DateTime(2026, 11, 1)); // พิจิก — สถิร
      final mutable = await dropOf(DateTime(2026, 6, 1)); // เมถุน — อุภย
      expect(fixed, lessThan(mutable));
    });

    test('ราศีที่ตกหลุมรักเร็วขึ้นไวกว่าเมื่อจีบเท่ากัน', () async {
      Future<double> gainOf(DateTime born) async {
        SharedPreferences.setMockInitialValues({});
        now = born;
        final soul = make();
        await soul.load();
        await soul.wooed(1);
        return soul.affection;
      }

      final cardinal = await gainOf(DateTime(2026, 7, 1)); // กรกฎ — จร
      final fixed = await gainOf(DateTime(2026, 11, 1)); // พิจิก — สถิร
      expect(cardinal, greaterThan(fixed));
    });
  });

  group('วันเกิดของเธอ', () {
    late DateTime now;
    MindSoul make() => MindSoul(clock: () => now);

    setUp(() {
      now = DateTime(2026, 11, 1);
      SharedPreferences.setMockInitialValues({});
    });

    /// 🔴 วันที่ติดตั้งไม่ใช่ "วันครบรอบวันเกิด" · มันคือวันที่เธอเกิด
    test('วันแรกที่ติดตั้งยังไม่ใช่วันเกิด', () async {
      final soul = make();
      await soul.load();
      expect(soul.isBirthday, isFalse);
      expect(soul.ageInYears, 0);
    });

    test('ครบรอบปีถัดไปคือวันเกิด', () async {
      final soul = make();
      await soul.load();

      now = DateTime(2027, 11, 1);
      expect(soul.isBirthday, isTrue);
      expect(soul.ageInYears, 1);
      expect(soul.daysToBirthday, 0);
    });

    test('วันอื่นไม่ใช่วันเกิด และนับถอยหลังถูก', () async {
      final soul = make();
      await soul.load();

      now = DateTime(2027, 10, 25);
      expect(soul.isBirthday, isFalse);
      expect(soul.daysToBirthday, 7);

      now = DateTime(2027, 11, 2);
      expect(soul.isBirthday, isFalse);
      expect(soul.daysToBirthday, 365);
    });
  });

  group('ตั้งชื่อให้เธอ', () {
    late DateTime now;
    MindSoul make() => MindSoul(clock: () => now);

    Future<MindSoul> partnered() async {
      SharedPreferences.setMockInitialValues({});
      final soul = make();
      await soul.load();
      for (var day = 0; day < 25; day++) {
        now = now.add(const Duration(days: 1));
        await soul.talked();
        await soul.wooed(3);
        await soul.wooed(3);
      }
      await soul.proposeFromOwner();
      return soul;
    }

    setUp(() => now = DateTime(2026, 7, 1)); // กรกฎ

    test('ยังไม่เป็นแฟนกัน ตั้งชื่อไม่ได้', () async {
      SharedPreferences.setMockInitialValues({});
      final soul = make();
      await soul.load();
      expect(soul.mayRename, isFalse);
      expect(soul.wantsName, isFalse);
    });

    test('เป็นแฟนแล้วเธอถามเองว่าอยากเรียกว่าอะไร', () async {
      final soul = await partnered();
      expect(soul.mayRename, isTrue);
      expect(soul.wantsName, isTrue);
    });

    test('ตั้งชื่อแล้วเธอใช้ชื่อนั้นจริง และ prompt เปลี่ยนตาม', () async {
      final soul = await partnered();
      expect(await soul.rename('น้องมิ้น'), NameVerdict.ok);
      expect(soul.name, 'น้องมิ้น');
      expect(soul.wantsName, isFalse);

      final prompt = MindPersona.system(
        mode: MindMode.love,
        flirt: .7,
        ownerProfile: 'x',
        boundaries: 'y',
        lang: AppLang.th,
        soul: soul,
      );
      expect(prompt, contains('น้องมิ้น'));
    });

    test('เลิกกันแล้วชื่อที่ตั้งให้หายไปด้วย', () async {
      final soul = await partnered();
      await soul.rename('มิ้น');
      await soul.breakUp();
      expect(soul.name, isNull);
    });
  });

  group('ด่านตรวจชื่อ', () {
    test('ชื่อที่ใช้ได้จริงผ่าน', () {
      for (final good in ['มิ้น', 'น้องมายด์', 'Mina', 'ใบเฟิร์น', 'พี่หมิว']) {
        expect(checkName(good), NameVerdict.ok, reason: good);
      }
    });

    test('สั้นหรือยาวเกินไม่ผ่าน', () {
      expect(checkName('ก'), NameVerdict.tooShort);
      expect(checkName('  '), NameVerdict.tooShort);
      expect(checkName('ก' * (kNameMaxChars + 1)), NameVerdict.tooLong);
    });

    test('ตัวเลขและสัญลักษณ์ไม่ผ่าน', () {
      expect(checkName('มิ้น123'), NameVerdict.badChars);
      expect(checkName('มิ้น 💖'), NameVerdict.badChars);
      expect(checkName('<script>'), NameVerdict.badChars);
    });

    test('ยาวเป็นประโยคไม่ผ่าน', () {
      expect(checkName('เธอ ชื่อ อะไร'), NameVerdict.tooManyWords);
    });

    test('พิมพ์มั่วไม่ผ่าน', () {
      expect(checkName('อออออ'), NameVerdict.notPronounceable);
      expect(checkName('ิิิ'), NameVerdict.notPronounceable);
      expect(checkName('aaaa'), NameVerdict.notPronounceable);
    });

    /// 🔴 ชื่อนี้จะไปโผล่บนหน้าจอสายจริงตอนเธอรับสายแทน ซึ่งคนอื่นเห็นด้วย
    test('คำหยาบไม่ผ่าน แม้จะเว้นวรรคเลี่ยง', () {
      expect(checkName('เหี้ย'), NameVerdict.rude);
      expect(checkName('Fuck'), NameVerdict.rude);
      expect(checkName('เห ี้ย'), NameVerdict.rude,
          reason: 'ต้องตรวจหลังยุบช่องว่าง ไม่งั้นเลี่ยงได้ด้วยการเคาะ');
    });

    test('เก็บชื่อให้เรียบร้อยก่อนบันทึก', () {
      expect(tidyName('  น้อง   มิ้น  '), 'น้อง มิ้น');
    });
  });

  group('เจ้าของทำกับเธอไม่ดี คะแนนลงได้จริง', () {
    late DateTime now;
    MindSoul make() => MindSoul(clock: () => now);

    setUp(() {
      now = DateTime(2026, 11, 1); // พิจิก
      SharedPreferences.setMockInitialValues({});
    });

    /// 🔴 ถ้าทางลงติดเพดานรายวันเหมือนทางขึ้น การตวาดใส่เธอจะแทบไม่มีผล
    /// แล้วทั้งกลไกก็เป็นแค่ตัวเลขที่ขึ้นอย่างเดียว ซึ่งไม่ใช่ความสัมพันธ์
    test('ตวาดใส่เธอแล้วความผูกพันลงทันที ไม่ติดเพดานรายวัน', () async {
      final soul = make();
      await soul.load();
      await soul.wooed(3);
      await soul.wooed(3);
      final after = soul.affection; // ชนเพดานของวันนี้แล้ว

      await soul.treated(-2);
      expect(soul.affection, lessThan(after * .6),
          reason: 'โดนตวาดแล้วต้องลงแรง ไม่ใช่ลงทีละนิดตามโควตา');
      expect(soul.sulking, isTrue);
      expect(soul.sulkWhy, 'scolded');
    });

    test('หงุดหงิดใส่เจ็บน้อยกว่าตวาด แต่ก็ยังเจ็บ', () async {
      final a = make();
      await a.load();
      await a.wooed(3);
      await a.wooed(3);
      final start = a.affection;
      await a.treated(-1);
      final mild = start - a.affection;

      SharedPreferences.setMockInitialValues({});
      final b = make();
      await b.load();
      await b.wooed(3);
      await b.wooed(3);
      await b.treated(-2);
      final harsh = start - b.affection;

      expect(mild, greaterThan(0));
      expect(harsh, greaterThan(mild * 2),
          reason: 'ตวาดไม่ใช่แค่ "หงุดหงิดแรงขึ้น" มันคนละเรื่องกัน');
    });

    /// 🔴 ต้องสะสมให้พ้นศูนย์ก่อนวัด
    ///
    /// วัดตอนความผูกพันยังน้อยกว่าความเจ็บ ทั้งสองราศีจะถูกบีบเหลือศูนย์
    /// เท่ากัน แล้วเลขที่วัดได้จะกลายเป็น "เริ่มต้นเท่าไหร่" ไม่ใช่ "เจ็บเท่าไหร่"
    /// — เทสต์ผ่านหรือไม่ผ่านโดยไม่เกี่ยวกับสิ่งที่ตั้งใจวัดเลย
    Future<double> hurtOf(DateTime born) async {
      SharedPreferences.setMockInitialValues({});
      now = born;
      final soul = make();
      await soul.load();
      for (var day = 0; day < 10; day++) {
        now = now.add(const Duration(days: 1));
        await soul.talked();
        await soul.wooed(3);
        await soul.wooed(3);
      }
      final before = soul.affection;
      expect(before, greaterThan(.3), reason: 'ต้องสูงพอที่จะไม่ถูกบีบเป็นศูนย์');

      await soul.treated(-2);
      return before - soul.affection;
    }

    test('ราศีที่อดทนสูงเจ็บน้อยกว่าราศีที่อ่อนไหว', () async {
      final earth = await hurtOf(DateTime(2026, 12, 25)); // มังกร — ดิน
      final water = await hurtOf(DateTime(2026, 11, 1)); // พิจิก — น้ำ
      expect(earth, lessThan(water));
    });

    test('พูดดีด้วยแล้วงอนคลายลง', () async {
      final soul = make();
      await soul.load();
      await soul.treated(-2);
      final angry = soul.sulk;

      await soul.treated(2);
      expect(soul.sulk, lessThan(angry));
    });

    test('คะแนน 0 ไม่ทำอะไรเลย — สั่งงานตรง ๆ ไม่ใช่การดุ', () async {
      final soul = make();
      await soul.load();
      await soul.talked();
      final before = soul.affection;

      await soul.treated(0);
      expect(soul.affection, before);
      expect(soul.sulking, isFalse);
    });
  });

  group('อ่านคะแนนจากคำตอบก้อนเดียวกับความจำ', () {
    test('อ่าน TREAT ออก', () {
      expect(parseTreatment('fact|เจ้าของแพ้กุ้ง\nTREAT|-2'), -2);
      expect(parseTreatment('NONE\nTREAT|0'), 0);
      expect(parseTreatment('TREAT | 1'), 1);
    });

    test('ไม่มี TREAT ก็ไม่พัง', () {
      expect(parseTreatment('fact|อะไรสักอย่าง'), isNull);
    });

    test('เลขเกินช่วงถูกบีบกลับ ไม่ใช่ปล่อยผ่าน', () {
      expect(parseTreatment('TREAT|-9'), -2);
      expect(parseTreatment('TREAT|7'), 2);
    });

    /// 🔴 ไม่ตัดบรรทัดนี้ทิ้ง = เธอจะจำเลขลอย ๆ ว่า "-1" ไว้ทุกหกตาที่คุยกัน
    /// จนความจำเต็มไปด้วยตัวเลขที่ไม่มีความหมาย
    test('บรรทัด TREAT ต้องไม่กลายเป็นความจำ', () {
      final facts = parseDistilled('fact|เจ้าของแพ้กุ้ง\nTREAT|-1');
      expect(facts.length, 1);
      expect(facts.first.text, 'เจ้าของแพ้กุ้ง');
    });
  });

  group('ปิดวงตอนเธอพร้อมเป็นแฟน', () {
    late DateTime now;
    MindSoul make() => MindSoul(clock: () => now);

    Future<MindSoul> ready() async {
      SharedPreferences.setMockInitialValues({});
      final soul = make();
      await soul.load();
      for (var day = 0; day < 25; day++) {
        now = now.add(const Duration(days: 1));
        await soul.talked();
        await soul.wooed(3);
        await soul.wooed(3);
      }
      return soul;
    }

    setUp(() => now = DateTime(2026, 7, 1)); // กรกฎ — จร ตกหลุมรักเร็ว

    test('ถึงจุดแล้วเธอเป็นฝ่ายอยากขอเอง', () async {
      final soul = await ready();
      expect(soul.wantsToAsk, isTrue);
    });

    /// การ์ดที่ขึ้นทุกครั้งที่เปิดแอปคือการจี้ ซึ่งทำให้สิ่งที่ควรน่ารัก
    /// กลายเป็นสิ่งที่คนอยากปิดทิ้ง
    test('กด "ยังก่อน" แล้วเงียบไปเจ็ดวัน ไม่ใช่หายไปเลย', () async {
      final soul = await ready();
      await soul.deferProposal();
      expect(soul.wantsToAsk, isFalse);

      now = now.add(const Duration(days: 6));
      expect(soul.wantsToAsk, isFalse);

      now = now.add(const Duration(days: 2));
      expect(soul.wantsToAsk, isTrue,
          reason: '"ยังก่อน" ไม่ใช่การปฏิเสธถาวร');
    });

    test('กดตกลงแล้วเป็นแฟนกัน และการ์ดหายไป', () async {
      final soul = await ready();
      expect(await soul.proposeFromOwner(), isTrue);
      expect(soul.bond, Bond.together);
      expect(soul.wantsToAsk, isFalse);
    });

    test('ราศีสถิรไม่เป็นฝ่ายเริ่ม เจ้าของต้องขอเอง', () async {
      now = DateTime(2026, 11, 1); // พิจิก — สถิร
      final soul = await ready();
      expect(soul.affection, greaterThanOrEqualTo(soul.consentAt));
      expect(soul.wantsToAsk, isFalse,
          reason: 'ราศีสถิรไม่เป็นฝ่ายเริ่ม ซึ่งตรงกับนิสัยของราศี');
      expect(await soul.proposeFromOwner(), isTrue);
    });
  });

  group('เธอถามเองว่าใครโทรมา', () {
    late DateTime now;
    MindSoul make() => MindSoul(clock: () => now);

    setUp(() {
      now = DateTime(2026, 11, 1);
      SharedPreferences.setMockInitialValues({});
    });

    test('สายที่คุยกันจริงจังถูกจดไว้ถาม', () async {
      final soul = make();
      await soul.load();
      await soul.sawCall(known: true, seconds: 240, who: 'คุณนภา');
      expect(soul.askAbout, 'คุณนภา');
    });

    test('สายสั้น ๆ ไม่ต้องถาม', () async {
      final soul = make();
      await soul.load();
      await soul.sawCall(known: true, seconds: 5, who: 'คุณนภา');
      expect(soul.askAbout, isNull);
    });

    /// ถามซ้ำทุกตาคือการจี้ ซึ่งพังเร็วกว่าไม่ถามเลย
    test('ถามไปแล้วต้องไม่ถามซ้ำ', () async {
      final soul = make();
      await soul.load();
      await soul.sawCall(known: false, seconds: 200, who: '0899999999');
      expect(soul.askAbout, isNotNull);

      await soul.askedAboutCall();
      expect(soul.askAbout, isNull);
    });

    /// ราศีลมไม่หึง แต่เลขาทุกราศีก็ยังต้องรู้ว่าใครโทรมา
    test('ราศีที่ไม่หึงก็ยังอยากรู้ว่าใครโทรมา', () async {
      now = DateTime(2026, 6, 1); // เมถุน
      SharedPreferences.setMockInitialValues({});
      final soul = make();
      await soul.load();

      await soul.sawCall(known: true, seconds: 120, who: 'คุณต้น');
      expect(soul.sulking, isFalse);
      expect(soul.askAbout, 'คุณต้น');
    });
  });

  group('บล็อกตัวตนใน prompt', () {
    late MindSoul soul;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      soul = MindSoul(clock: () => DateTime(2026, 11, 1));
      await soul.load();
    });

    test('ตอนคุยในแอป มีทั้งตัวตนและความสัมพันธ์', () {
      final block = MindPersona.soulBlock(soul, AppLang.th);
      expect(block, contains('ราศีพิจิก'));
      expect(block, contains('ความผูกพัน'));
    });

    /// 🔴 คนแปลกหน้าที่โทรเข้ามาไม่ควรได้รู้ว่าเจ้าของเบอร์นี้คบกับผู้ช่วย AI
    /// ของตัวเอง · เป็นข้อมูลส่วนตัวของเจ้าของ ไม่ใช่ของเธอ
    test('ตอนอยู่ในสาย มีแค่พื้นนิสัย ไม่มีเรื่องความสัมพันธ์', () {
      final block = MindPersona.soulBlock(soul, AppLang.th, onCall: true);
      expect(block, contains('ราศีพิจิก'),
          reason: 'พื้นนิสัยยังต้องมี เพราะมันคือน้ำเสียงของเธอ');
      expect(block, isNot(contains('ความผูกพัน')));
      expect(block, isNot(contains('สถานะ:')));
    });

    test('system prompt ทั้งก้อนก็ต้องไม่หลุดความสัมพันธ์ตอนรับสาย', () {
      final prompt = MindPersona.system(
        mode: MindMode.work,
        flirt: .7,
        ownerProfile: 'x',
        boundaries: 'y',
        lang: AppLang.th,
        onCall: true,
        soul: soul,
      );
      expect(prompt, isNot(contains('ความผูกพัน')));
      expect(prompt, isNot(contains('เป็นแฟนกัน')));
    });

    /// 🔴 กฎที่เจ้าของสั่งไว้ตรง ๆ: "หน้าที่ในงานที่ทำ อย่าบกพร่อง"
    ///
    /// ฟีเจอร์นี้ทำให้เธอมีอารมณ์ ซึ่งแปลว่าวันหนึ่งเธอจะงอนอยู่ตอนที่มีงาน
    /// ต้องทำ · ถ้าตอนนั้นเธอตอบสั้นลงจนข้อมูลขาด ฟีเจอร์นี้ก็ทำให้แอปแย่ลง
    /// ไม่ใช่ดีขึ้น · กฎนี้ต้องอยู่ในทุกบริบท ทั้งตอนคุยในแอปและตอนรับสาย
    test('กฎ "อารมณ์เปลี่ยนน้ำเสียงได้ แต่ห้ามเปลี่ยนเนื้องาน" ต้องอยู่เสมอ',
        () {
      for (final onCall in [false, true]) {
        expect(MindPersona.soulBlock(soul, AppLang.th, onCall: onCall),
            contains('ห้ามเปลี่ยน**เนื้องาน**'),
            reason: 'onCall=$onCall');
        expect(MindPersona.soulBlock(soul, AppLang.en, onCall: onCall),
            contains('never **what she delivers**'),
            reason: 'onCall=$onCall');
      }
    });

    test('ไม่ต่อ soul เข้ามา prompt ต้องยังประกอบได้เหมือนเดิม', () {
      final prompt = MindPersona.system(
        mode: MindMode.love,
        flirt: .7,
        ownerProfile: 'x',
        boundaries: 'y',
        lang: AppLang.en,
      );
      expect(prompt, contains('About the owner'));
    });
  });
}
