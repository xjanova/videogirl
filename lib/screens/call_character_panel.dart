/// ตั้งตัวละครที่คุยในสาย — ชื่อ เพศ บทบาท นิสัย คำทัก · เลือกตัวรับสาย/โทรออก · ผูกกับเจ้าเสียง
///
/// 🔴 เจ้าของ: "ทำให้ใช้ง่ายอย่าให้งง" → บนสุดบอกเสมอว่า **ตอนนี้ใครคุยในสาย และเพราะอะไร**
/// แล้วค่อยเป็นรายการตัว · การผูกกับเสียงอยู่ล่างสุดเป็นตารางเดียว อ่านได้ในแวบเดียว
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai/speech_service.dart';
import '../i18n/enum_labels.dart';
import '../i18n/strings.dart';
import '../i18n/strings_brains.dart';
import '../persona/call_character.dart';
import '../state/mind_state.dart';
import '../theme/tokens.dart';

class CallCharacterPanel extends StatelessWidget {
  const CallCharacterPanel({super.key, required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MindState>();
    final t = S.of(context);
    final cast = state.cast;

    String reason({required bool live}) {
      final e = state.callVoiceEngine(live: live);
      return cast.boundFor(e) ? t.chBecauseVoice(e.labelOf(t)) : t.chBecausePicked;
    }

    final answer = state.callCharacter();
    final out = state.callCharacter(outgoing: true);
    final live = state.callCharacter(live: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.chWhat, style: const TextStyle(fontSize: 11, height: 1.5, color: MindColors.ink75)),
        const SizedBox(height: 10),

        // ── ตอนนี้ใครคุย ──
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(MindRadius.control),
            border: Border.all(color: accent.withValues(alpha: .4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 5,
            children: [
              Text(
                t.chNow,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: accent),
              ),
              _NowRow(label: t.chNowAnswer, who: answer, why: reason(live: false)),
              _NowRow(label: t.chNowOutgoing, who: out, why: reason(live: false)),
              if (state.liveCalls) _NowRow(label: t.chLive, who: live, why: reason(live: true)),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── รายการตัว ──
        Text(t.chList, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        for (final c in cast.characters)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CharacterTile(
              c: c,
              accent: accent,
              answer: cast.answerId == c.id,
              outgoing: cast.outgoingId == c.id,
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => _edit(context, null),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: Text(t.chAdd),
        ),
        const SizedBox(height: 16),

        // ── ผูกกับเจ้าเสียง ──
        Text(t.chBindTitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(t.chBindWhat, style: const TextStyle(fontSize: 10.5, height: 1.45, color: MindColors.ink55)),
        const SizedBox(height: 8),
        for (final e in TtsEngine.wired)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              spacing: 10,
              children: [
                SizedBox(
                  width: 112,
                  child: Text(
                    e.labelOf(t),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: state.callVoiceEngine() == e ? accent : MindColors.ink,
                    ),
                  ),
                ),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: cast.boundFor(e) ? cast.byEngine[e] : '',
                    style: const TextStyle(fontSize: 11.5, color: MindColors.ink),
                    items: [
                      DropdownMenuItem(value: '', child: Text(t.chBindNone)),
                      for (final c in cast.characters)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text('${c.name} · ${c.male ? t.chMale : t.chFemale}', overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => state.bindCharacter(e, (v == null || v.isEmpty) ? null : v),
                  ),
                ),
              ],
            ),
          ),
        Text(t.chBindTip, style: const TextStyle(fontSize: 10, height: 1.4, color: MindColors.ink50)),
      ],
    );
  }
}

class _NowRow extends StatelessWidget {
  const _NowRow({required this.label, required this.who, required this.why});
  final String label;
  final CallCharacter who;
  final String why;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(label, style: const TextStyle(fontSize: 11, color: MindColors.ink55)),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${who.name} (${who.male ? t.chMale : t.chFemale})',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(
                  text: '  ·  $why',
                  style: const TextStyle(color: MindColors.ink55),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}

class _CharacterTile extends StatelessWidget {
  const _CharacterTile({required this.c, required this.accent, required this.answer, required this.outgoing});
  final CallCharacter c;
  final Color accent;
  final bool answer;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final state = context.read<MindState>();
    final picked = answer || outgoing;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 6, 9),
      decoration: BoxDecoration(
        color: picked ? accent.withValues(alpha: .07) : MindColors.glass80,
        borderRadius: BorderRadius.circular(MindRadius.control),
        border: Border.all(color: picked ? accent : MindColors.glassBorder, width: picked ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: (c.male ? const Color(0xFF2563EB) : const Color(0xFFE0357A)).withValues(alpha: .15),
                child: Icon(
                  c.male ? Icons.man_rounded : Icons.woman_rounded,
                  size: 19,
                  color: c.male ? const Color(0xFF2563EB) : const Color(0xFFE0357A),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Text(
                      c.isBuiltIn ? '${c.name}  ·  ${t.chBuiltIn}' : c.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      [
                        c.male ? t.chMale : t.chFemale,
                        if (c.role.isNotEmpty) c.role,
                        if (c.traits.isNotEmpty) c.traits.replaceAll('\n', ' '),
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: MindColors.ink55),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: t.chEdit,
                visualDensity: VisualDensity.compact,
                onPressed: () => _edit(context, c),
                icon: const Icon(Icons.edit_rounded, size: 18),
              ),
              if (!c.isBuiltIn)
                IconButton(
                  tooltip: t.chDelete,
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        content: Text(t.chDeleteAsk(c.name)),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t.chDelete)),
                        ],
                      ),
                    );
                    if (ok == true) state.deleteCharacter(c.id);
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              FilterChip(
                label: Text(t.chUseAnswer, style: const TextStyle(fontSize: 11)),
                selected: answer,
                selectedColor: accent.withValues(alpha: .2),
                onSelected: (_) => state.setAnswerCharacter(c.id),
              ),
              FilterChip(
                label: Text(t.chUseOutgoing, style: const TextStyle(fontSize: 11)),
                selected: outgoing,
                selectedColor: accent.withValues(alpha: .2),
                onSelected: (_) => state.setOutgoingCharacter(c.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _edit(BuildContext context, CallCharacter? c) async {
  final state = context.read<MindState>();
  final result = await showModalBottomSheet<CallCharacter>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CharacterEditor(initial: c),
  );
  if (result != null) state.saveCharacter(result);
}

class _CharacterEditor extends StatefulWidget {
  const _CharacterEditor({this.initial});
  final CallCharacter? initial;

  @override
  State<_CharacterEditor> createState() => _CharacterEditorState();
}

class _CharacterEditorState extends State<_CharacterEditor> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _role = TextEditingController(text: widget.initial?.role ?? '');
  late final _traits = TextEditingController(text: widget.initial?.traits ?? '');
  late final _greeting = TextEditingController(text: widget.initial?.greeting ?? '');
  late CharacterGender _gender = widget.initial?.gender ?? CharacterGender.female;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _traits.dispose();
    _greeting.dispose();
    super.dispose();
  }

  void _addTrait(String p) {
    final cur = _traits.text.trim();
    if (cur.contains(p)) return;
    _traits.text = cur.isEmpty ? p : '$cur · $p';
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Text(
              widget.initial == null ? t.chAdd : t.chEdit,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            TextField(
              controller: _name,
              maxLength: CallCharacter.nameMax,
              decoration: InputDecoration(labelText: t.chName, isDense: true),
            ),
            Text(t.chGender, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            SegmentedButton<CharacterGender>(
              segments: [
                ButtonSegment(
                  value: CharacterGender.female,
                  label: Text(t.chFemale),
                  icon: const Icon(Icons.woman_rounded),
                ),
                ButtonSegment(value: CharacterGender.male, label: Text(t.chMale), icon: const Icon(Icons.man_rounded)),
              ],
              selected: {_gender},
              onSelectionChanged: (v) => setState(() => _gender = v.first),
            ),
            TextField(
              controller: _role,
              maxLength: CallCharacter.roleMax,
              decoration: InputDecoration(labelText: t.chRole, hintText: t.chRoleHint, isDense: true),
            ),
            TextField(
              controller: _traits,
              maxLength: CallCharacter.traitsMax,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(labelText: t.chTraits, hintText: t.chTraitsHint, isDense: true),
            ),
            Text(t.chTraitsQuick, style: const TextStyle(fontSize: 11, color: MindColors.ink55)),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in t.chTraitPresets)
                  ActionChip(
                    label: Text(p, style: const TextStyle(fontSize: 11)),
                    onPressed: () => _addTrait(p),
                  ),
              ],
            ),
            TextField(
              controller: _greeting,
              maxLength: CallCharacter.greetingMax,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: t.chGreeting, isDense: true),
            ),
            FilledButton.icon(
              onPressed: () {
                if (_name.text.trim().isEmpty) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.chNameNeeded)));
                  return;
                }
                final base =
                    widget.initial ?? CallCharacter(id: 'c${DateTime.now().microsecondsSinceEpoch}', name: _name.text);
                Navigator.pop(
                  context,
                  base.copyWith(
                    name: _name.text,
                    gender: _gender,
                    role: _role.text,
                    traits: _traits.text,
                    greeting: _greeting.text,
                  ),
                );
              },
              icon: const Icon(Icons.check_rounded),
              label: Text(t.chSave),
            ),
          ],
        ),
      ),
    );
  }
}
