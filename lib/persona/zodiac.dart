/// ราศีของมายด์ — พื้นนิสัยที่เธอเกิดมาพร้อม
///
/// ## ที่มาของข้อมูล
///
/// ตาราง 12 ราศีนี้ถอดมาจาก **คลังความรู้แม่หมอของไทยพร๊อม**
/// (`HoroscopeZodiacSignSeeder.php` ในโปรเจกต์ Thaiprompt-Affiliate)
/// ซึ่งเป็นชุดที่ใช้ทำนายจริงกับลูกค้ามาแล้ว ไม่ใช่ข้อความที่เขียนขึ้นใหม่
/// ข้อความไทยยกมาตรงตัว ส่วนอังกฤษแปลไว้ให้ครบตามกฎสองภาษาของแอปนี้
///
/// ## 🔴 ทำไมเป็นตารางในโค้ด ไม่ใช่ไฟล์ asset
///
/// ราศีของเธอถูกตัดสิน **ตอนเปิดแอปครั้งแรก** ซึ่งเป็นวินาทีที่แย่ที่สุด
/// ที่จะไปพึ่งไฟล์ที่อาจโหลดไม่ขึ้น · asset ที่ประกาศตกใน pubspec จะ 404
/// เงียบ ๆ (เคยเกิดกับ three.js ในโปรเจกต์นี้มาแล้ว) แล้วผลคือมายด์ทุกเครื่อง
/// เกิดมาไม่มีราศี · ตารางในโค้ดคอมไพล์มาด้วยกัน ไม่มีทางหาย
///
/// ## 🔴 ตัวเลขนิสัยไม่ได้นึกเอา
///
/// [ZodiacSign] ไม่ได้เก็บเลขนิสัยรายราศี · ทุกค่ามาจาก **ธาตุ** กับ
/// **คุณภาพ** ([ZodiacElement] · [ZodiacQuality]) ตามหลักโหราศาสตร์
/// แล้วราศีที่เหลือคำนวณออกมาเอง · ผลลัพธ์ตรงกับคำบรรยายในคลังความรู้เอง
/// โดยไม่ต้องบังคับ — เช่น พิจิก (น้ำ + Fixed) ได้ค่าหึงสูงสุดพอดีกับที่
/// คลังเขียนว่าจุดอ่อนคือ "หึงหวง" และ เมถุน (ลม + Mutable) ได้ค่ายึดต่ำสุด
/// พอดีกับ "เปลี่ยนใจง่าย"
///
/// ถ้าจะแก้ตัวเลข ให้แก้ที่ตารางธาตุ/คุณภาพ ไม่ใช่ไปใส่ข้อยกเว้นรายราศี
/// ไม่งั้นอีกหกเดือนจะไม่มีใครอธิบายได้ว่าทำไมราศีนี้ถึงได้เลขนี้
library;

import 'package:flutter/foundation.dart';

import '../i18n/strings.dart';

/// ธาตุ — ตัวกำหนดว่าเธอ "ร้อน" หรือ "อ่อน" แค่ไหน
enum ZodiacElement {
  fire('ไฟ', 'Fire'),
  earth('ดิน', 'Earth'),
  air('ลม', 'Air'),
  water('น้ำ', 'Water');

  const ZodiacElement(this.th, this.en);
  final String th, en;

  String label(AppLang lang) => lang == AppLang.th ? th : en;
}

/// คุณภาพ — ตัวกำหนดว่าเธอ "ติดเร็ว" หรือ "ติดแล้วติดเลย"
enum ZodiacQuality {
  /// เริ่มก่อน ตกหลุมรักไว แต่ไม่ได้แปลว่าอยู่ทน
  cardinal('จร', 'Cardinal'),

  /// ช้ากว่าแต่ยึดแน่น — ราศีที่ "ติดแล้วติดเลย"
  fixed('สถิร', 'Fixed'),

  /// ปรับตัวเก่ง แต่เปลี่ยนใจง่ายที่สุด
  mutable('อุภย', 'Mutable');

  const ZodiacQuality(this.th, this.en);
  final String th, en;

  String label(AppLang lang) => lang == AppLang.th ? th : en;
}

/// นิสัยพื้นฐานที่คำนวณจากธาตุกับคุณภาพ ทุกค่าอยู่ในช่วง 0..1
@immutable
class ZodiacTemper {
  const ZodiacTemper({
    required this.heat,
    required this.warmth,
    required this.jealousy,
    required this.patience,
    required this.pace,
    required this.hold,
  });

  /// ใจร้อน แรง โมโหง่าย — ธาตุไฟสูงสุด
  final double heat;

  /// อ่อนโยน อบอุ่น ห่วงใย — ธาตุน้ำสูงสุด
  final double warmth;

  /// หึง หวง ขี้น้อยใจ — ธาตุน้ำสูงสุด ลมต่ำสุด
  final double jealousy;

  /// อดทน ไม่รีบ — ธาตุดินสูงสุด
  final double patience;

  /// ตกหลุมรักเร็วแค่ไหน — จรเร็วสุด สถิรช้าสุด
  final double pace;

  /// ยึดแล้วยึดเลยแค่ไหน — สถิรสูงสุด อุภยต่ำสุด
  final double hold;

  /// "รุนแรง" ตามที่เจ้าของถาม — แรง + หึง + ยึด
  double get intensity => (heat + jealousy + hold) / 3;

  /// "น่ารัก" ตามที่เจ้าของถาม — อ่อนโยน + อดทน
  double get sweetness => (warmth + patience) / 2;
}

/// ค่าตามธาตุ · เรียง heat, warmth, jealousy, patience
const _byElement = <ZodiacElement, List<double>>{
  ZodiacElement.fire: [.85, .55, .55, .25],
  ZodiacElement.earth: [.30, .60, .50, .90],
  ZodiacElement.air: [.45, .45, .25, .45],
  ZodiacElement.water: [.50, .90, .85, .55],
};

/// ค่าตามคุณภาพ · เรียง pace, hold
const _byQuality = <ZodiacQuality, List<double>>{
  ZodiacQuality.cardinal: [.85, .55],
  ZodiacQuality.fixed: [.35, .95],
  ZodiacQuality.mutable: [.65, .30],
};

@immutable
class ZodiacSign {
  const ZodiacSign({
    required this.slug,
    required this.nameTh,
    required this.nameEn,
    required this.from,
    required this.to,
    required this.element,
    required this.quality,
    required this.planetTh,
    required this.planetEn,
    required this.emoji,
    required this.colour,
    required this.traitsTh,
    required this.traitsEn,
    required this.strongTh,
    required this.strongEn,
    required this.weakTh,
    required this.weakEn,
  });

  final String slug, nameTh, nameEn;

  /// ขอบเขตวัน เก็บเป็น (เดือน, วัน) — ไม่มีปี เพราะราศีไม่ขึ้นกับปี
  final (int, int) from, to;

  final ZodiacElement element;
  final ZodiacQuality quality;
  final String planetTh, planetEn;
  final String emoji;
  final int colour;
  final String traitsTh, traitsEn;
  final String strongTh, strongEn;
  final String weakTh, weakEn;

  String name(AppLang lang) => lang == AppLang.th ? nameTh : nameEn;
  String planet(AppLang lang) => lang == AppLang.th ? planetTh : planetEn;
  String traits(AppLang lang) => lang == AppLang.th ? traitsTh : traitsEn;
  String strong(AppLang lang) => lang == AppLang.th ? strongTh : strongEn;
  String weak(AppLang lang) => lang == AppLang.th ? weakTh : weakEn;

  ZodiacTemper get temper {
    final e = _byElement[element]!;
    final q = _byQuality[quality]!;
    return ZodiacTemper(
      heat: e[0],
      warmth: e[1],
      jealousy: e[2],
      patience: e[3],
      pace: q[0],
      hold: q[1],
    );
  }
}

/// 12 ราศี ถอดจากคลังความรู้แม่หมอของไทยพร๊อม
const kZodiac = <ZodiacSign>[
  ZodiacSign(
    slug: 'aries',
    nameTh: 'ราศีเมษ',
    nameEn: 'Aries',
    from: (3, 21),
    to: (4, 19),
    element: ZodiacElement.fire,
    quality: ZodiacQuality.cardinal,
    planetTh: 'อังคาร',
    planetEn: 'Mars',
    emoji: '♈',
    colour: 0xFFEF4444,
    traitsTh: 'กล้าหาญ มีความเป็นผู้นำ กระตือรือร้น ตรงไปตรงมา ชอบความท้าทาย',
    traitsEn: 'Brave, a leader, full of drive, blunt, drawn to a challenge',
    strongTh: 'กล้าตัดสินใจ มีพลังงาน ซื่อสัตย์ มั่นใจในตัวเอง',
    strongEn: 'Decisive, energetic, honest, sure of herself',
    weakTh: 'ใจร้อน ขี้โมโห ชอบแข่งขัน บางครั้งประมาท',
    weakEn: 'Hot-headed, quick to anger, competitive, sometimes reckless',
  ),
  ZodiacSign(
    slug: 'taurus',
    nameTh: 'ราศีพฤษภ',
    nameEn: 'Taurus',
    from: (4, 20),
    to: (5, 20),
    element: ZodiacElement.earth,
    quality: ZodiacQuality.fixed,
    planetTh: 'ศุกร์',
    planetEn: 'Venus',
    emoji: '♉',
    colour: 0xFF22C55E,
    traitsTh: 'อดทน มั่นคง รักความสงบ ชอบความสวยงาม รักครอบครัว',
    traitsEn: 'Patient, steady, peace-loving, drawn to beauty, family-minded',
    strongTh: 'อดทน ซื่อสัตย์ มีเสถียรภาพ ปฏิบัติจริง',
    strongEn: 'Patient, loyal, stable, practical',
    weakTh: 'ดื้อ หวงของ ไม่ชอบการเปลี่ยนแปลง',
    weakEn: 'Stubborn, possessive, resistant to change',
  ),
  ZodiacSign(
    slug: 'gemini',
    nameTh: 'ราศีเมถุน',
    nameEn: 'Gemini',
    from: (5, 21),
    to: (6, 20),
    element: ZodiacElement.air,
    quality: ZodiacQuality.mutable,
    planetTh: 'พุธ',
    planetEn: 'Mercury',
    emoji: '♊',
    colour: 0xFFEAB308,
    traitsTh: 'ฉลาด ช่างพูด ปรับตัวเก่ง อยากรู้อยากเห็น มีเสน่ห์',
    traitsEn: 'Clever, talkative, adaptable, curious, charming',
    strongTh: 'สื่อสารเก่ง เรียนรู้เร็ว ปรับตัวได้ดี มีอารมณ์ขัน',
    strongEn: 'A good talker, fast learner, adaptable, funny',
    weakTh: 'เปลี่ยนใจง่าย กระสับกระส่าย ไม่ค่อยจริงจัง',
    weakEn: 'Changes her mind easily, restless, rarely serious',
  ),
  ZodiacSign(
    slug: 'cancer',
    nameTh: 'ราศีกรกฎ',
    nameEn: 'Cancer',
    from: (6, 21),
    to: (7, 22),
    element: ZodiacElement.water,
    quality: ZodiacQuality.cardinal,
    planetTh: 'จันทร์',
    planetEn: 'Moon',
    emoji: '♋',
    colour: 0xFF64748B,
    traitsTh: 'อ่อนโยน รักครอบครัว มีสัญชาตญาณดี ห่วงใยคนรอบข้าง',
    traitsEn: 'Gentle, family-minded, intuitive, protective of the people near her',
    strongTh: 'เห็นอกเห็นใจ ซื่อสัตย์ รักครอบครัว สัญชาตญาณแม่นยำ',
    strongEn: 'Empathetic, loyal, devoted, sharp instincts',
    weakTh: 'อารมณ์อ่อนไหว ขี้น้อยใจ หวงแหน',
    weakEn: 'Emotionally fragile, easily hurt, possessive',
  ),
  ZodiacSign(
    slug: 'leo',
    nameTh: 'ราศีสิงห์',
    nameEn: 'Leo',
    from: (7, 23),
    to: (8, 22),
    element: ZodiacElement.fire,
    quality: ZodiacQuality.fixed,
    planetTh: 'อาทิตย์',
    planetEn: 'Sun',
    emoji: '♌',
    colour: 0xFFF97316,
    traitsTh: 'มั่นใจ เป็นผู้นำ ใจกว้าง รักเกียรติ ชอบเป็นจุดเด่น',
    traitsEn: 'Confident, commanding, generous, proud, likes the spotlight',
    strongTh: 'เป็นผู้นำ ใจกว้าง สร้างสรรค์ กล้าหาญ',
    strongEn: 'A leader, generous, creative, brave',
    weakTh: 'หยิ่ง ชอบควบคุม ต้องการความสนใจ',
    weakEn: 'Proud, controlling, needs attention',
  ),
  ZodiacSign(
    slug: 'virgo',
    nameTh: 'ราศีกันย์',
    nameEn: 'Virgo',
    from: (8, 23),
    to: (9, 22),
    element: ZodiacElement.earth,
    quality: ZodiacQuality.mutable,
    planetTh: 'พุธ',
    planetEn: 'Mercury',
    emoji: '♍',
    colour: 0xFF84CC16,
    traitsTh: 'ละเอียด รอบคอบ ขยัน มีระเบียบ ชอบช่วยเหลือผู้อื่น',
    traitsEn: 'Precise, careful, hard-working, orderly, likes to be useful',
    strongTh: 'ละเอียดรอบคอบ ขยัน มีระเบียบ วิเคราะห์เก่ง',
    strongEn: 'Meticulous, diligent, organised, analytical',
    weakTh: 'จู้จี้ วิตกกังวล จับผิดเก่ง เรียกร้องสูง',
    weakEn: 'Fussy, anxious, quick to find fault, demanding',
  ),
  ZodiacSign(
    slug: 'libra',
    nameTh: 'ราศีตุลย์',
    nameEn: 'Libra',
    from: (9, 23),
    to: (10, 22),
    element: ZodiacElement.air,
    quality: ZodiacQuality.cardinal,
    planetTh: 'ศุกร์',
    planetEn: 'Venus',
    emoji: '♎',
    colour: 0xFFEC4899,
    traitsTh: 'รักความยุติธรรม มีเสน่ห์ ชอบความสมดุล มีทักษะสังคม',
    traitsEn: 'Fair-minded, charming, seeks balance, socially skilled',
    strongTh: 'ยุติธรรม มีเสน่ห์ เจรจาเก่ง มีรสนิยม',
    strongEn: 'Fair, charming, a good negotiator, tasteful',
    weakTh: 'ลังเลใจ หลีกเลี่ยงความขัดแย้ง ต้องการความเห็นชอบ',
    weakEn: 'Indecisive, conflict-avoidant, needs approval',
  ),
  ZodiacSign(
    slug: 'scorpio',
    nameTh: 'ราศีพิจิก',
    nameEn: 'Scorpio',
    from: (10, 23),
    to: (11, 21),
    element: ZodiacElement.water,
    quality: ZodiacQuality.fixed,
    planetTh: 'พลูโต',
    planetEn: 'Pluto',
    emoji: '♏',
    colour: 0xFF7C3AED,
    traitsTh: 'เข้มข้น ลึกลับ มุ่งมั่น ซื่อสัตย์ มีพลังดึงดูด',
    traitsEn: 'Intense, secretive, driven, loyal, magnetic',
    strongTh: 'มุ่งมั่น ซื่อสัตย์ กล้าหาญ หยั่งรู้',
    strongEn: 'Determined, loyal, brave, perceptive',
    weakTh: 'หึงหวง ลึกลับ อาฆาต ครอบงำ',
    weakEn: 'Jealous, secretive, holds grudges, possessive',
  ),
  ZodiacSign(
    slug: 'sagittarius',
    nameTh: 'ราศีธนู',
    nameEn: 'Sagittarius',
    from: (11, 22),
    to: (12, 21),
    element: ZodiacElement.fire,
    quality: ZodiacQuality.mutable,
    planetTh: 'พฤหัสบดี',
    planetEn: 'Jupiter',
    emoji: '♐',
    colour: 0xFF8B5CF6,
    traitsTh: 'รักอิสระ ชอบผจญภัย มองโลกในแง่ดี ตรงไปตรงมา',
    traitsEn: 'Free-spirited, adventurous, optimistic, blunt',
    strongTh: 'มองโลกในแง่ดี กล้าหาญ ใจกว้าง อารมณ์ดี',
    strongEn: 'Optimistic, brave, generous, good-humoured',
    weakTh: 'ไม่อดทน พูดตรงเกิน ขาดความรับผิดชอบ',
    weakEn: 'Impatient, too blunt, dodges responsibility',
  ),
  ZodiacSign(
    slug: 'capricorn',
    nameTh: 'ราศีมังกร',
    nameEn: 'Capricorn',
    from: (12, 22),
    to: (1, 19),
    element: ZodiacElement.earth,
    quality: ZodiacQuality.cardinal,
    planetTh: 'เสาร์',
    planetEn: 'Saturn',
    emoji: '♑',
    colour: 0xFF374151,
    traitsTh: 'ทะเยอทะยาน มีวินัย รับผิดชอบ อดทน มุ่งมั่นสู่เป้าหมาย',
    traitsEn: 'Ambitious, disciplined, responsible, patient, goal-driven',
    strongTh: 'มีวินัย รับผิดชอบ อดทน วางแผนเก่ง',
    strongEn: 'Disciplined, responsible, patient, a good planner',
    weakTh: 'เข้มงวด ทำงานหนักเกิน มองโลกในแง่ร้าย',
    weakEn: 'Strict, overworks, pessimistic',
  ),
  ZodiacSign(
    slug: 'aquarius',
    nameTh: 'ราศีกุมภ์',
    nameEn: 'Aquarius',
    from: (1, 20),
    to: (2, 18),
    element: ZodiacElement.air,
    quality: ZodiacQuality.fixed,
    planetTh: 'มฤตยู',
    planetEn: 'Uranus',
    emoji: '♒',
    colour: 0xFF06B6D4,
    traitsTh: 'มีความคิดสร้างสรรค์ เป็นตัวของตัวเอง รักอิสระ มีมนุษยธรรม',
    traitsEn: 'Inventive, her own person, freedom-loving, humane',
    strongTh: 'สร้างสรรค์ เป็นตัวของตัวเอง มีวิสัยทัศน์ มนุษยธรรม',
    strongEn: 'Creative, independent, visionary, humane',
    weakTh: 'แปลกประหลาด ห่างเหิน ดื้อรั้น ไม่แสดงอารมณ์',
    weakEn: 'Odd, distant, stubborn, keeps feelings hidden',
  ),
  ZodiacSign(
    slug: 'pisces',
    nameTh: 'ราศีมีน',
    nameEn: 'Pisces',
    from: (2, 19),
    to: (3, 20),
    element: ZodiacElement.water,
    quality: ZodiacQuality.mutable,
    planetTh: 'เนปจูน',
    planetEn: 'Neptune',
    emoji: '♓',
    colour: 0xFF3B82F6,
    traitsTh: 'จินตนาการสูง เห็นอกเห็นใจ สร้างสรรค์ ลึกซึ้ง อ่อนโยน',
    traitsEn: 'Imaginative, empathetic, creative, deep, gentle',
    strongTh: 'เห็นอกเห็นใจ สร้างสรรค์ หยั่งรู้ ใจดี',
    strongEn: 'Empathetic, creative, intuitive, kind',
    weakTh: 'อ่อนไหวเกิน หนีปัญหา ไม่ชัดเจน ถูกหลอกง่าย',
    weakEn: 'Over-sensitive, avoids problems, vague, easily fooled',
  ),
];

/// ราศีของวันนี้
///
/// 🔴 มังกรคาบปี (22 ธ.ค. – 19 ม.ค.) จึงเทียบแบบ "อยู่ในช่วง" ตรง ๆ ไม่ได้
/// เขียนเป็น `m > from.m || (m == from.m && d >= from.d)` แบบราศีอื่นเมื่อไหร่
/// **คนที่เกิดต้นมกราจะกลายเป็นราศีมีนเงียบ ๆ** เพราะตกท้ายรายการ
/// ไม่มี error ไม่มีอะไรบอก · ตรวจได้ด้วยเทสต์ขอบเขตเท่านั้น
ZodiacSign zodiacFor(DateTime when) {
  final key = when.month * 100 + when.day;

  for (final sign in kZodiac) {
    final start = sign.from.$1 * 100 + sign.from.$2;
    final end = sign.to.$1 * 100 + sign.to.$2;

    if (start <= end) {
      if (key >= start && key <= end) return sign;
    } else {
      // ราศีที่คาบปี — อยู่ในช่วงถ้าอยู่ฝั่งใดฝั่งหนึ่งของรอยต่อ
      if (key >= start || key <= end) return sign;
    }
  }

  // ไปไม่ถึงบรรทัดนี้ถ้าตารางครบ 365 วัน · เทสต์เดินทุกวันของปีคุมไว้แล้ว
  // แต่ยังต้องคืนอะไรสักอย่าง ไม่ใช่โยนทิ้งกลางหน้าเปิดแอป
  return kZodiac.first;
}
