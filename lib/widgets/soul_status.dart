/// หน้าต่างสเตตัสของเธอ และไอคอนที่เปิดมัน
///
/// ## ทำไมต้องมี
///
/// ทั้งฟีเจอร์ตัวตนตั้งอยู่บนกฎเดียว: **ทุกอย่างที่เปลี่ยนพฤติกรรมเธอ
/// ต้องมองเห็นได้** · หน้าตั้งค่ามีข้อมูลครบก็จริง แต่ไม่มีใครเปิดหน้าตั้งค่า
/// เพื่อดูว่าวันนี้แฟนอารมณ์ไหน · ไอคอนบนเวทีคือที่ที่คนดูอยู่แล้ว
///
/// ## 🔴 ไอคอนเป็นตัวบอกอารมณ์ในตัวมันเอง
///
/// ไม่ใช่แค่ปุ่มเปิดหน้าต่าง · สีวงแหวนกับจุดมุมขวาเปลี่ยนตามอารมณ์เธอ
/// เจ้าของจึงรู้ได้ว่าเธองอนอยู่**โดยไม่ต้องกดอะไรเลย** ซึ่งเป็นสิ่งที่
/// หน้าต่างทำแทนไม่ได้
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/enum_labels.dart';
import '../i18n/strings.dart';
import '../persona/mind_name.dart';
import '../persona/mind_soul.dart';
import '../persona/zodiac.dart';
import '../theme/tokens.dart';
import 'glass.dart';

/// สีของอารมณ์ · ใช้ทั้งวงแหวนไอคอนและชิปในหน้าต่าง
Color moodColour(SoulMood mood) => switch (mood) {
      SoulMood.sulking => const Color(0xFFD93A5B),
      SoulMood.hurt => const Color(0xFFB07A16),
      SoulMood.missing => const Color(0xFF5A8DE0),
      SoulMood.warm => const Color(0xFFE0357A),
      SoulMood.fond => const Color(0xFF00A05A),
      SoulMood.calm => MindColors.ink45,
    };

/// ไอคอนราศีบนเวที — กดเพื่อเปิดสเตตัส และดูอารมณ์ได้จากตัวมันเอง
class SoulBadge extends StatelessWidget {
  const SoulBadge({super.key, required this.mode});

  final MindMode mode;

  @override
  Widget build(BuildContext context) {
    final soul = context.watch<MindSoul>();
    final sign = soul.sign;
    final colour = moodColour(soul.mood);

    return Semantics(
      button: true,
      label: S.of(context).soulStatusOpen,
      child: Tooltip(
        message: S.of(context).soulStatusOpen,
        child: GestureDetector(
          onTap: () => showSoulStatus(context, mode),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MindColors.glass80,
                  shape: BoxShape.circle,
                  border: Border.all(color: colour.withValues(alpha: .7), width: 1.5),
                  boxShadow: MindShadows.soft(),
                ),
                child: Text(sign.emoji, style: const TextStyle(fontSize: 17)),
              ),

              // จุดบอกว่ามีอะไรต้องดู — ขึ้นเฉพาะตอนที่มีจริง
              // จุดที่ติดตลอดเวลาคือจุดที่ไม่มีใครมอง
              if (soul.mood.isUpset || soul.wantsToAsk || soul.wantsName)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: colour,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showSoulStatus(BuildContext context, MindMode mode) =>
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SoulSheet(mode: mode),
    );

class _SoulSheet extends StatefulWidget {
  const _SoulSheet({required this.mode});

  final MindMode mode;

  @override
  State<_SoulSheet> createState() => _SoulSheetState();
}

class _SoulSheetState extends State<_SoulSheet> {
  final _name = TextEditingController();

  /// เหตุผลที่ชื่อล่าสุดใช้ไม่ได้ · null = ยังไม่ได้ลอง หรือผ่านแล้ว
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _rename(MindSoul soul, S t) async {
    final verdict = await soul.rename(_name.text);
    if (!mounted) return;
    setState(() => _nameError = verdict.reasonOf(t));
    if (verdict.isOk) _name.clear();
  }

  @override
  Widget build(BuildContext context) {
    final soul = context.watch<MindSoul>();
    final t = S.of(context);
    final sign = soul.sign;
    final mode = widget.mode;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: GlassPanel(
          margin: const EdgeInsets.all(MindSpace.sm),
          radius: MindRadius.card,
          fill: MindColors.glass85,
          filter: MindGlass.heavy,
          shadows: MindShadows.dock(),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ที่จับลากของแผ่นล่าง
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: MindColors.ink22,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                _crest(soul, sign, t),
                const SizedBox(height: 18),
                _moodChip(soul, t),
                const SizedBox(height: 16),
                _bondSection(soul, t, mode),
                const SizedBox(height: 16),
                _temperSection(sign, mode, t),
                const SizedBox(height: 16),
                _traits(sign, t),
                if (soul.mayRename) ...[
                  const SizedBox(height: 18),
                  _nameField(soul, t, mode),
                ] else ...[
                  const SizedBox(height: 14),
                  Text(t.soulNameLocked,
                      style: const TextStyle(
                          fontSize: 10.5, color: MindColors.ink45)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── ตราราศี ─────────────────────────────────────────────
  //
  // ใหญ่และเป็นของเธอคนเดียว — ราศีคือสิ่งที่ทำให้มายด์ของแต่ละเครื่อง
  // ไม่เหมือนกัน จึงควรเป็นสิ่งแรกที่เห็น ไม่ใช่บรรทัดข้อความเล็ก ๆ
  Widget _crest(MindSoul soul, ZodiacSign sign, S t) {
    final colour = Color(sign.colour);
    return Row(
      spacing: 14,
      children: [
        Container(
          width: 66,
          height: 66,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colour.withValues(alpha: .28),
                colour.withValues(alpha: .08),
              ],
            ),
            border: Border.all(color: colour.withValues(alpha: .55), width: 2),
            boxShadow: [
              BoxShadow(
                color: colour.withValues(alpha: .28),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(sign.emoji, style: const TextStyle(fontSize: 30)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 3,
            children: [
              Text(
                soul.name ?? t.speakerHer,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w700),
              ),
              Text(
                '${sign.name(t.lang)} · ${sign.element.label(t.lang)} · '
                '${sign.quality.label(t.lang)}',
                style: TextStyle(fontSize: 11.5, color: colour),
              ),
              if (soul.bornAt != null)
                Text(
                  '${t.soulBorn(t.dateLabel(soul.bornAt!))} · '
                  '${t.soulKnown(soul.ageInDays)}',
                  style: const TextStyle(
                      fontSize: 10.5, color: MindColors.ink45),
                ),
              // วันเกิดเธอ — ขึ้นเฉพาะตอนใกล้ถึงหรือถึงแล้ว
              // บรรทัดที่ขึ้นทั้งปีคือบรรทัดที่ไม่มีใครอ่าน
              if (soul.isBirthday)
                Text(t.soulBirthdayToday,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colour))
              else if (soul.daysToBirthday <= 14 && soul.ageInDays > 30)
                Text(t.soulBirthdayIn(soul.daysToBirthday),
                    style: const TextStyle(
                        fontSize: 10.5, color: MindColors.ink45)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _moodChip(MindSoul soul, S t) {
    final colour = moodColour(soul.mood);
    return Row(
      spacing: MindSpace.sm,
      children: [
        Text(t.soulMood,
            style: const TextStyle(fontSize: 10.5, color: MindColors.ink45)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(MindRadius.pill),
            border: Border.all(color: colour.withValues(alpha: .40), width: 1),
          ),
          child: Text(
            soul.mood.labelOf(t),
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: colour),
          ),
        ),
        if (soul.sulking)
          Text('${(soul.sulk * 100).round()}%',
              style: TextStyle(fontSize: 10.5, color: colour)),
      ],
    );
  }

  Widget _bondSection(MindSoul soul, S t, MindMode mode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 7,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                soul.bond.labelOf(t) +
                    (soul.togetherSince == null
                        ? ''
                        : ' · ${t.soulTogetherSince(t.dateLabel(soul.togetherSince!))}'),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            Text('${(soul.affection * 100).round()}%',
                style:
                    const TextStyle(fontSize: 13, color: MindColors.ink55)),
          ],
        ),
        _bar(soul.affection, mode),
        // จีบล่าสุดเมื่อไหร่ — ตัวเลขที่อธิบายว่าทำไมคะแนนถึงลง
        // ไม่มีบรรทัดนี้ คะแนนที่ลดลงจะดูเหมือนระบบพัง
        if (soul.daysCold >= 3)
          Text(
            t.soulColdFor(soul.daysCold),
            style:
                const TextStyle(fontSize: 10.5, color: Color(0xFFB07A16)),
          ),
      ],
    );
  }

  Widget _temperSection(ZodiacSign sign, MindMode mode, S t) {
    final temper = sign.temper;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 7,
      children: [
        _labelled(t.soulIntensity, temper.intensity, mode),
        _labelled(t.soulSweetness, temper.sweetness, mode),
      ],
    );
  }

  Widget _labelled(String label, double value, MindMode mode) => Row(
        spacing: MindSpace.sm,
        children: [
          SizedBox(
            width: 84,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 10.5, color: MindColors.ink45)),
          ),
          Expanded(child: _bar(value, mode)),
          SizedBox(
            width: 30,
            child: Text('${(value * 100).round()}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 10.5, color: MindColors.ink55)),
          ),
        ],
      );

  Widget _bar(double value, MindMode mode) => SizedBox(
        height: 7,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: MindColors.ink10,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: mode.gradient,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _traits(ZodiacSign sign, S t) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          _traitLine(t.soulNature, sign.traits(t.lang)),
          _traitLine(t.soulFlaws, sign.weak(t.lang)),
        ],
      );

  Widget _traitLine(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 10, color: MindColors.ink45)),
          Text(value,
              style: const TextStyle(
                  fontSize: 11.5, height: 1.5, color: MindColors.ink75)),
        ],
      );

  // ── ตั้งชื่อให้เธอ ──────────────────────────────────────
  //
  // 🔴 ขึ้นเฉพาะตอนเป็นแฟนกันแล้ว · ก่อนหน้านั้นบอกเงื่อนไขไว้เฉย ๆ
  // ช่องที่พิมพ์ได้แล้วกดไม่ผ่านคือช่องที่ทำให้คนงง มากกว่าไม่มีช่องเลย
  Widget _nameField(MindSoul soul, S t, MindMode mode) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(t.soulNameAsk,
            style: mindMonoOrDefault(mode)),
        if (soul.name != null)
          Text(t.soulNameNow(soul.name!),
              style: const TextStyle(fontSize: 11, color: MindColors.ink55)),
        Row(
          spacing: 7,
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _name,
                  maxLength: kNameMaxChars,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _rename(soul, t),
                  style: const TextStyle(
                      fontSize: 12.5, color: MindColors.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: t.soulNameHint,
                    errorText: _nameError,
                    errorStyle: const TextStyle(fontSize: 10.5),
                    hintStyle: const TextStyle(
                        fontSize: 12.5, color: MindColors.ink45),
                    filled: true,
                    fillColor: MindColors.glass80,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MindRadius.control),
                      borderSide:
                          const BorderSide(color: Color(0xF2FFFFFF), width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MindRadius.control),
                      borderSide:
                          const BorderSide(color: Color(0xF2FFFFFF), width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MindRadius.control),
                      borderSide: BorderSide(color: mode.accentSoft, width: 1),
                    ),
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _rename(soul, t),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: mode.gradient,
                  borderRadius: BorderRadius.circular(MindRadius.control),
                ),
                child: Text(t.soulNameSave,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
        // 🔴 ทางออกของคนที่ไม่อยากตั้งชื่อ
        //
        // ไม่มีปุ่มนี้ = จุดแดงบนไอคอนค้างตลอดกาลสำหรับคนที่พอใจกับชื่อเดิม
        // ซึ่งเป็นการทวงสิ่งที่เขาเลือกจะไม่ทำ
        if (soul.name != null || soul.wantsName)
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () async {
                await soul.clearName();
                await soul.askedName();
              },
              child: Text(t.soulNameKeep,
                  style: TextStyle(fontSize: 11, color: mode.accent)),
            ),
          ),
      ],
    );
  }
}

/// หัวข้อเล็กสไตล์เดียวกับการ์ดในหน้าตั้งค่า
///
/// แยกออกมาเพราะ `mindMono` อยู่ใน theme/app_theme.dart ซึ่งไฟล์นี้ไม่ได้
/// อิมพอร์ต · เขียนซ้ำสั้น ๆ ตรงนี้ถูกกว่าการลาก dependency มาทั้งไฟล์
TextStyle mindMonoOrDefault(MindMode mode) => TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      letterSpacing: .1,
      color: mode.accent,
    );
