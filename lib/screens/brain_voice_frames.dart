/// สามกรอบของหน้า "สมองและเสียง" — สมองเอไอ · ตัวถอดเสียง · โมเดลสังเคราะห์เสียง
///
/// 🔴 เจ้าของบอกว่าเดิมแยกไม่ออกว่าตัวเลือกไหนคือสมอง ตัวไหนคือเสียง
/// จึงให้แต่ละกรอบมีเลขขั้น สีประจำ ไอคอน ชื่อ และประโยคบอกหน้าที่ของมันเสมอ
/// · ของในกรอบไม่ปนกัน: การตั้งค่าของเจ้าเสียงอยู่ในกรอบเสียงเท่านั้น
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../ai/brain_provider.dart';
import '../ai/cloud_brains.dart';
import '../ai/eleven_tuning.dart';
import '../ai/openai_client.dart';
import '../ai/premium_catalog.dart';
import '../ai/speech_service.dart';
import '../ai/stt_engine.dart';
import '../ai/voice_profile.dart';
import '../i18n/enum_labels.dart';
import '../i18n/strings.dart';
import '../i18n/strings_brains.dart';
import '../state/mind_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// สีประจำกรอบ · ต่างกันชัดพอให้รู้ด้วยตาว่าอยู่กรอบไหน
abstract final class FrameColors {
  static const brain = Color(0xFF6C4BFF);
  static const stt = Color(0xFF0089C7);
  static const tts = Color(0xFFE0357A);
}

/// กรอบหนึ่งกรอบ: เส้นขอบสีหนา · แถบหัวมีเลขขั้น ไอคอน ชื่อ และหน้าที่
class SettingsFrame extends StatelessWidget {
  const SettingsFrame({
    super.key,
    required this.number,
    required this.icon,
    required this.color,
    required this.title,
    required this.what,
    required this.child,
    this.status,
  });

  final int number;
  final IconData icon;
  final Color color;
  final String title;
  final String what;
  final Widget child;

  /// สรุปสั้น ๆ ว่าตอนนี้ใช้อะไรอยู่ · โชว์ที่หัวกรอบ
  final String? status;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Semantics(
      container: true,
      label: '${t.frameStep(number)} · $title',
      child: Container(
        decoration: BoxDecoration(
          color: MindColors.glass72,
          borderRadius: BorderRadius.circular(MindRadius.card),
          border: Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .16), blurRadius: 18, offset: const Offset(0, 6)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  color.withValues(alpha: .20),
                  color.withValues(alpha: .06),
                ]),
                border: Border(bottom: BorderSide(color: color.withValues(alpha: .35))),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 11,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Icon(icon, size: 19, color: Colors.white),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Row(
                          spacing: 7,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: .14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(t.frameStep(number),
                                  style: MindType.fit(
                                      mindMono(size: 9.5, color: color, weight: FontWeight.w700), t.frameStep(number))),
                            ),
                            Flexible(
                              child: Text(title,
                                  style: TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w800, color: color)),
                            ),
                          ],
                        ),
                        Text(what,
                            style: const TextStyle(fontSize: 11, height: 1.5, color: MindColors.ink75)),
                        if (status != null && status!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Row(
                              spacing: 5,
                              children: [
                                Icon(Icons.check_circle_rounded, size: 13, color: color),
                                Flexible(
                                  child: Text('${t.nowUsing}: $status',
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: color)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(padding: const EdgeInsets.all(14), child: child),
          ],
        ),
      ),
    );
  }
}

/// หัวข้อย่อยในกรอบ: "ขั้นที่ 1 · เลือกเจ้าที่จะใช้"
class FrameStepLabel extends StatelessWidget {
  const FrameStepLabel(this.text, {super.key, required this.color, this.top = 4});
  final String text;
  final Color color;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top, bottom: 8),
        child: Row(
          spacing: 6,
          children: [
            Container(width: 3, height: 13, color: color),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ),
          ],
        ),
      );
}

// ═══ สมองเอไอ: รายการรุ่น + ราคา ═══════════════════════════════

String _usd(double v) {
  if (v == 0) return '0';
  if (v < 1) return v.toStringAsFixed(v < 0.1 ? 3 : 2).replaceFirst(RegExp(r'0+$'), '');
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

/// รายการรุ่นของเจ้าหนึ่งเจ้า · แต่ละแถวบอกความสามารถ ระดับ และราคา
class BrainModelList extends StatelessWidget {
  const BrainModelList({
    super.key,
    required this.provider,
    required this.selected,
    required this.onPick,
    required this.mode,
  });

  final BrainProvider provider;
  final String selected;
  final ValueChanged<String> onPick;
  final MindMode mode;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final models = CloudBrains.modelsOf(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in models)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ModelRow(
              model: m,
              selected: m.id == selected,
              onTap: () => onPick(m.id),
            ),
          ),
        Text(t.brainPriceFootnote,
            style: const TextStyle(fontSize: 9.5, height: 1.5, color: MindColors.ink50)),
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.model, required this.selected, required this.onTap});
  final BrainModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    const c = FrameColors.brain;
    final (tierText, tierColor) = switch (model.tier) {
      BrainTier.cheap => (t.tierCheap, const Color(0xFF0E9F6E)),
      BrainTier.balanced => (t.tierBalanced, const Color(0xFF0089C7)),
      BrainTier.smart => (t.tierSmart, const Color(0xFF6C4BFF)),
      BrainTier.top => (t.tierTop, const Color(0xFFB45309)),
    };
    final note = model.priceNoteOf(t);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: selected ? c.withValues(alpha: .10) : MindColors.glass80,
            borderRadius: BorderRadius.circular(MindRadius.control),
            border: Border.all(
              color: selected ? c : MindColors.glassBorder,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  size: 17,
                  color: selected ? c : MindColors.ink22,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(model.label,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        _Chip(tierText, tierColor),
                        if (model.freeTier) _Chip(t.brainFreeTier, const Color(0xFF0E9F6E)),
                      ],
                    ),
                    Text(model.hintOf(t),
                        style: const TextStyle(fontSize: 11, height: 1.45, color: MindColors.ink75)),
                    Text(
                      '${t.brainPrice(_usd(model.inUsd), _usd(model.outUsd))}  ·  '
                      '${t.brainPer1k(_usd(model.usdPer1kMessages))}',
                      style: const TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w600, color: MindColors.ink),
                    ),
                    if (note.isNotEmpty)
                      Text(note,
                          style: const TextStyle(fontSize: 9.5, height: 1.4, color: Color(0xFFB45309))),
                    Row(
                      children: [
                        Text(model.id, style: mindMono(size: 9, color: MindColors.ink45)),
                        if (model.contextK > 0) ...[
                          const Text('  ·  ', style: TextStyle(fontSize: 9, color: MindColors.ink45)),
                          Flexible(
                            child: Text(t.brainContext(model.contextK),
                                style: const TextStyle(fontSize: 9.5, color: MindColors.ink50)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .4)),
        ),
        child: Text(text, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
      );
}

// ═══ ตัวถอดเสียง ═══════════════════════════════════════════

/// ชื่อตัวถอดเสียงที่ใช้จริง (สำหรับหัวกรอบ)
String sttNowLabel(MindState state, S t) {
  final e = state.sttActual;
  return e == SttEngine.auto ? '${t.sttViaBrain} (${state.brain.labelOf(t)})' : e.labelOf(t);
}

class SttPicker extends StatelessWidget {
  const SttPicker({super.key, required this.state});
  final MindState state;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    const c = FrameColors.stt;
    final ready = state.canTranscribe;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in SttEngine.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _PlainChoice(
              color: c,
              title: e.labelOf(t),
              subtitle: e == SttEngine.auto ? t.sttAutoHint(sttNowLabel(state, t)) : e.hintOf(t),
              selected: state.stt == e,
              onTap: () => state.setStt(e),
            ),
          ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (ready ? const Color(0xFF0E9F6E) : const Color(0xFFB45309)).withValues(alpha: .08),
            borderRadius: BorderRadius.circular(MindRadius.control),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Icon(
                ready ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                size: 16,
                color: ready ? const Color(0xFF0E9F6E) : const Color(0xFFB45309),
              ),
              Expanded(
                child: Text(
                  [
                    ready ? t.sttReady : '${t.sttNotReady} — ${state.whyNoMic}',
                    state.transcribesOnDevice ? t.sttStaysHere : t.sttGoesOut,
                  ].join('\n'),
                  style: const TextStyle(fontSize: 10.5, height: 1.5, color: MindColors.ink75),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlainChoice extends StatelessWidget {
  const _PlainChoice({
    required this.color,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final Color color;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: .10) : MindColors.glass80,
              borderRadius: BorderRadius.circular(MindRadius.control),
              border: Border.all(color: selected ? color : MindColors.glassBorder, width: selected ? 1.6 : 1),
            ),
            child: Row(
              spacing: 10,
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 17, color: selected ? color : MindColors.ink22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      if (subtitle.isNotEmpty)
                        Text(subtitle,
                            style: const TextStyle(fontSize: 10.5, height: 1.4, color: MindColors.ink55)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ═══ ElevenLabs: ปรับแต่ง ═══════════════════════════════════

/// ปรับทุกค่าของ ElevenLabs สำหรับช่องทางหนึ่ง · ค่าเปลี่ยนแล้วบันทึกทันที
class ElevenTuningPanel extends StatelessWidget {
  const ElevenTuningPanel({super.key, required this.state, required this.channel});
  final MindState state;
  final VoiceChannel channel;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    const c = FrameColors.tts;
    final p = state.voiceFor(channel);
    final e = p.eleven;
    final v4 = p.model.startsWith('eleven_v4');
    void set(ElevenTuning n) => state.setVoice(channel, p.copyWith(eleven: n));
    final fx = state.elevenEffects;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(MindRadius.control),
        border: Border.all(color: c.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: 6,
            children: [
              const Icon(Icons.tune_rounded, size: 16, color: c),
              Expanded(
                child: Text(t.elTuneTitle,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(t.elTuneWhat, style: const TextStyle(fontSize: 10.5, height: 1.4, color: MindColors.ink55)),
          _Slider(
            label: t.elStability,
            hint: t.elStabilityHint,
            value: e.stability,
            min: 0,
            max: 1,
            show: (x) => x.toStringAsFixed(2),
            onChanged: (x) => set(e.copyWith(stability: x)),
          ),
          _Slider(
            label: t.elSimilarity,
            hint: t.elSimilarityHint,
            value: e.similarity,
            min: 0,
            max: 1,
            show: (x) => x.toStringAsFixed(2),
            onChanged: (x) => set(e.copyWith(similarity: x)),
          ),
          Opacity(
            opacity: v4 ? .45 : 1,
            child: IgnorePointer(
              ignoring: v4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (v4)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(t.elV3Only,
                          style: const TextStyle(fontSize: 10, color: Color(0xFFB45309))),
                    ),
                  _Slider(
                    label: t.elStyle,
                    hint: t.elStyleHint,
                    value: e.style,
                    min: 0,
                    max: 1,
                    show: (x) => x.toStringAsFixed(2),
                    onChanged: (x) => set(e.copyWith(style: x)),
                  ),
                  _Slider(
                    label: t.elSpeed,
                    value: e.speed,
                    min: 0.7,
                    max: 1.2,
                    show: (x) => '${x.toStringAsFixed(2)}×',
                    onChanged: (x) => set(e.copyWith(speed: x)),
                  ),
                  _Switch(
                    label: t.elSpeakerBoost,
                    hint: t.elSpeakerBoostHint,
                    on: e.speakerBoost,
                    onChanged: (x) => set(e.copyWith(speakerBoost: x)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(t.elMood, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          Text(t.elMoodHint, style: const TextStyle(fontSize: 10.5, height: 1.4, color: MindColors.ink55)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Pill(t.elMoodNone, e.mood.isEmpty, () => set(e.copyWith(mood: ''))),
              for (final m in ElevenTuning.moods)
                _Pill('${t.elMoodName(m)} [$m]', e.mood == m, () => set(e.copyWith(mood: m))),
            ],
          ),
          const SizedBox(height: 12),
          Text(t.elEffects, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          Text(t.elEffectsHint, style: const TextStyle(fontSize: 10.5, height: 1.4, color: MindColors.ink55)),
          const SizedBox(height: 6),
          if (fx.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: state.elevenBusy ? null : () => _loadExtras(context, state),
                icon: state.elevenBusy
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_rounded, size: 16),
                label: Text(t.elLoadEffects),
              ),
            )
          else ...[
            _Dropdown(
              label: t.elFilter,
              off: t.elOff,
              items: fx.filters,
              value: e.filter,
              onChanged: (v) => set(e.copyWith(filter: v)),
            ),
            _Dropdown(
              label: t.elRoom,
              off: t.elOff,
              items: fx.environments,
              value: e.environment,
              onChanged: (v) => set(e.copyWith(environment: v)),
            ),
            _Dropdown(
              label: t.elNoise,
              off: t.elOff,
              items: fx.noises,
              value: e.noise,
              onChanged: (v) => set(e.copyWith(noise: v)),
            ),
          ],
          _Slider(
            label: t.elDistance,
            value: e.distance,
            min: 0,
            max: 1,
            show: (x) => x.toStringAsFixed(2),
            onChanged: (x) => set(e.copyWith(distance: x)),
          ),
          const SizedBox(height: 8),
          Text(t.elNormalize, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              _Pill(t.elNormAuto, e.normalize == 'auto', () => set(e.copyWith(normalize: 'auto'))),
              _Pill(t.elNormOn, e.normalize == 'on', () => set(e.copyWith(normalize: 'on'))),
              _Pill(t.elNormOff, e.normalize == 'off', () => set(e.copyWith(normalize: 'off'))),
            ],
          ),
          _Switch(
            label: t.elSeed,
            hint: t.elSeedHint,
            on: e.seed > 0,
            onChanged: (x) => set(e.copyWith(seed: x ? 1 + DateTime.now().millisecondsSinceEpoch % 999999 : 0)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: e == const ElevenTuning() ? null : () => set(const ElevenTuning()),
              child: Text(t.elResetTuning),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _loadExtras(BuildContext context, MindState state) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final err = await state.loadElevenExtras();
  if (err != null) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(err)));
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.show,
    required this.onChanged,
    this.hint,
  });
  final String label;
  final String? hint;
  final double value;
  final double min;
  final double max;
  final String Function(double) show;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                Text(show(value), style: mindMono(size: 10.5, color: FrameColors.tts)),
              ],
            ),
            if (hint != null)
              Text(hint!, style: const TextStyle(fontSize: 10, height: 1.4, color: MindColors.ink55)),
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: ((max - min) * 20).round(),
              activeColor: FrameColors.tts,
              onChanged: onChanged,
            ),
          ],
        ),
      );
}

class _Switch extends StatelessWidget {
  const _Switch({required this.label, required this.on, required this.onChanged, this.hint});
  final String label;
  final String? hint;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  if (hint != null)
                    Text(hint!, style: const TextStyle(fontSize: 10, height: 1.4, color: MindColors.ink55)),
                ],
              ),
            ),
            // สีที่ track · thumb สีชมพูบน track ชมพูของธีมโหมดส่วนตัว = ปุ่มกลมหาย
            Switch(value: on, activeTrackColor: FrameColors.tts, onChanged: onChanged),
          ],
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.on, this.onTap);
  final String text;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: on ? FrameColors.tts : MindColors.glass80,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? FrameColors.tts : MindColors.ink10),
          ),
          child: Text(text,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: on ? Colors.white : MindColors.ink75)),
        ),
      );
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.off,
    required this.items,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String off;
  final List<ElevenEffect> items;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // ค่าที่เคยเลือกแต่ไม่อยู่ในแคตตาล็อกแล้ว = ถือว่าไม่ใช้ (กัน DropdownButton ล้ม)
    final current = items.any((e) => e.id == value) ? value : '';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        spacing: 10,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: current,
              style: const TextStyle(fontSize: 11.5, color: MindColors.ink),
              items: [
                DropdownMenuItem(value: '', child: Text(off)),
                for (final e in items)
                  DropdownMenuItem(value: e.id, child: Text(e.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => onChanged(v ?? ''),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══ ElevenLabs: บัญชี + โคลนเสียงเจ้าของ ═════════════════════════

/// เสียงในบัญชีเป็นเสียงโคลนไหม (ElevenLabs ใส่ category = cloned)
bool isClonedVoice(PremiumVoice v) => v.detail.split(' · ').contains('cloned');

class ElevenClonePanel extends StatefulWidget {
  const ElevenClonePanel({super.key, required this.state});
  final MindState state;

  @override
  State<ElevenClonePanel> createState() => _ElevenClonePanelState();
}

class _ElevenClonePanelState extends State<ElevenClonePanel> {
  AudioRecorder? _rec;
  final _takes = <({String path, int secs})>[];
  bool _recording = false;
  int _secs = 0;
  Timer? _tick;
  bool _consent = false;
  bool _noise = true;
  bool _busy = false;
  String? _doneId;
  final _name = TextEditingController();

  MindState get state => widget.state;

  @override
  void dispose() {
    _tick?.cancel();
    final r = _rec;
    if (r != null) {
      unawaited(r.dispose());
    }
    _name.dispose();
    _cleanup();
    super.dispose();
  }

  void _cleanup() {
    for (final t in _takes) {
      try {
        File(t.path).deleteSync();
      } on Object {
        // ไฟล์ชั่วคราว ลบไม่ได้ก็ปล่อยให้ระบบเก็บกวาด
      }
    }
    _takes.clear();
  }

  void _say(String msg) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _start() async {
    final t = S.of(context);
    final rec = _rec ??= AudioRecorder();
    if (!await rec.hasPermission()) {
      _say(t.elCloneNoMic);
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}${Platform.pathSeparator}'
        'eleven_clone_${DateTime.now().millisecondsSinceEpoch}.wav';
    await rec.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 44100, numChannels: 1),
      path: path,
    );
    if (!mounted) return;
    setState(() {
      _recording = true;
      _secs = 0;
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _secs++);
    });
  }

  Future<void> _stop() async {
    _tick?.cancel();
    final path = await _rec?.stop();
    if (!mounted) return;
    setState(() {
      _recording = false;
      if (path != null && _secs > 0) _takes.add((path: path, secs: _secs));
    });
  }

  int get _total => _takes.fold(0, (a, b) => a + b.secs);

  Future<void> _clone() async {
    final t = S.of(context);
    if (_total < 20) {
      _say(t.elCloneTooShort);
      return;
    }
    setState(() => _busy = true);
    try {
      final name = _name.text.trim().isEmpty ? t.elCloneNameDefault : _name.text.trim();
      final id = await state.cloneElevenVoice(
        name: name,
        files: [for (final x in _takes) x.path],
        removeNoise: _noise,
      );
      if (!mounted) return;
      setState(() {
        _doneId = id;
        _cleanup();
      });
      _say(t.elCloneDone);
    } on OpenAiFailure catch (e) {
      if (mounted) _say(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _use(VoiceChannel c, String id) {
    final thai = S.of(context).isThai;
    final p = PremiumCatalog.adapt(state.voiceFor(c), TtsEngine.elevenlabs, thai: thai);
    // เสียงโคลนต้องการความเหมือนสูง · ปรับเฉพาะเมื่อยังเป็นค่าตั้งต้นของ ElevenLabs
    final tune = p.eleven == const ElevenTuning() ? p.eleven.copyWith(similarity: 0.9) : p.eleven;
    state.setVoice(c, p.copyWith(voice: id, eleven: tune));
    _say('✓ ${c.labelOf(S.of(context))}');
  }

  Future<void> _delete(PremiumVoice v) async {
    final t = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(t.elCloneDeleteAsk(v.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.elCloneDelete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final err = await state.deleteElevenVoice(v.id);
    if (mounted) _say(err ?? t.elCloneDeleted);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    const c = FrameColors.tts;
    final acct = state.elevenAccount;
    final clones = state.accountVoices(TtsEngine.elevenlabs).where(isClonedVoice).toList();
    final blocked = acct != null && !acct.canClone;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(MindRadius.control),
        border: Border.all(color: c.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            spacing: 6,
            children: [
              const Icon(Icons.record_voice_over_rounded, size: 16, color: c),
              Expanded(
                child: Text(t.elCloneTitle,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: c)),
              ),
            ],
          ),
          Text(t.elCloneWhat, style: const TextStyle(fontSize: 11, height: 1.5, color: MindColors.ink75)),
          Text(t.elClonePlan, style: const TextStyle(fontSize: 10, height: 1.4, color: MindColors.ink55)),

          // ── บัญชี ──
          Row(
            children: [
              Expanded(
                child: Text(
                  acct == null
                      ? t.elAccount
                      : '${t.elAccountLine(acct.tier, acct.left, acct.limit)}'
                          '${acct.voiceLimit > 0 ? ' · ${t.elVoiceSlots(acct.voiceSlotsUsed, acct.voiceLimit)}' : ''}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: state.elevenBusy ? null : () => _loadExtras(context, state),
                child: Text(t.elAccountLoad, style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
          if (blocked)
            Text(t.elCloneNoPlan, style: const TextStyle(fontSize: 10.5, color: Color(0xFFB45309))),

          // ── เสียงโคลนที่มีอยู่ ──
          if (clones.isNotEmpty) ...[
            Text(t.elCloneMine, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            for (final v in clones)
              _CloneRow(
                voice: v,
                fresh: v.id == _doneId,
                onChat: () => _use(VoiceChannel.chat, v.id),
                onAnswer: () => _use(VoiceChannel.answer, v.id),
                onDelete: () => _delete(v),
              ),
          ],

          // ── อัดเสียงใหม่ ──
          if (!blocked) ...[
            const Divider(height: 14),
            Text(t.elCloneRead, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MindColors.glass85,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(t.elCloneScript, style: const TextStyle(fontSize: 12, height: 1.6)),
            ),
            Row(
              spacing: 8,
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _recording ? Colors.red : c),
                  onPressed: _busy ? null : (_recording ? _stop : _start),
                  icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded, size: 18),
                  label: Text(_recording ? '${t.elCloneStop} · ${_secs}s' : t.elCloneRecord),
                ),
                if (_takes.isNotEmpty && !_recording)
                  TextButton(
                    onPressed: _busy ? null : () => setState(_cleanup),
                    child: Text(t.elCloneRedo),
                  ),
              ],
            ),
            if (_takes.isNotEmpty) ...[
              for (var i = 0; i < _takes.length; i++)
                Text('• ${t.elCloneTake(i + 1, _takes[i].secs)}',
                    style: const TextStyle(fontSize: 10.5, color: MindColors.ink75)),
              Text(t.elCloneTotal(_total),
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: _total >= 60 ? const Color(0xFF0E9F6E) : const Color(0xFFB45309))),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: t.elCloneName,
                  hintText: t.elCloneNameDefault,
                  isDense: true,
                ),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _noise,
                onChanged: (v) => setState(() => _noise = v ?? true),
                title: Text(t.elCloneNoise, style: const TextStyle(fontSize: 11.5)),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _consent,
                onChanged: (v) => setState(() => _consent = v ?? false),
                title: Text(t.elCloneConsent, style: const TextStyle(fontSize: 11.5)),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: c),
                onPressed: (_consent && !_busy && !_recording) ? _clone : null,
                icon: _busy
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(_busy ? t.elCloneBusy : t.elCloneGo),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _CloneRow extends StatelessWidget {
  const _CloneRow({
    required this.voice,
    required this.fresh,
    required this.onChat,
    required this.onAnswer,
    required this.onDelete,
  });
  final PremiumVoice voice;
  final bool fresh;
  final VoidCallback onChat;
  final VoidCallback onAnswer;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: fresh ? FrameColors.tts.withValues(alpha: .10) : MindColors.glass80,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fresh ? FrameColors.tts : MindColors.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq_rounded, size: 15, color: FrameColors.tts),
              const SizedBox(width: 6),
              Expanded(
                child: Text(voice.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: t.elCloneDelete,
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: MindColors.ink55),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            children: [
              OutlinedButton(onPressed: onChat, child: Text(t.elCloneUseChat, style: const TextStyle(fontSize: 11))),
              OutlinedButton(
                  onPressed: onAnswer, child: Text(t.elCloneUseAnswer, style: const TextStyle(fontSize: 11))),
            ],
          ),
        ],
      ),
    );
  }
}
