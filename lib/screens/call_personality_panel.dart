import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../i18n/strings_settings.dart';
import '../state/mind_state.dart';
import '../theme/tokens.dart';

/// How she talks to callers. Owner: "ให้เธอตอบอารมณ์ คำสวยเหมือนคน มีหัวเราะบ้าง จีบได้ คุยสนุกได้
/// แต่ไม่ให้คุยนาน เธอต้องหาทางลงได้เอง เพื่อวางสาย ขอตัวเป็น บุคลิกเรากำหนดได้ใช่ไหม".
class CallPersonalityPanel extends StatefulWidget {
  const CallPersonalityPanel({super.key, required this.accent});
  final Color accent;
  @override
  State<CallPersonalityPanel> createState() => _CallPersonalityPanelState();
}

class _CallPersonalityPanelState extends State<CallPersonalityPanel> {
  /// The slider value while a finger is on it · saved once on release, not on every frame.
  double? _dragging;

  Future<void> _editStyle(MindState state) async {
    final ctl = TextEditingController(text: state.callStyle);
    try {
      final v = await showDialog<String>(
        context: context,
        builder: (c) {
          final t = S.of(c);
          return AlertDialog(
            title: Text(t.cpStyle, style: const TextStyle(fontSize: 15)),
            content: TextField(
              controller: ctl,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              maxLength: MindState.callStyleMax,
              decoration: InputDecoration(helperText: t.cpStyleHint, helperMaxLines: 4),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: Text(t.cancel)),
              TextButton(onPressed: () => Navigator.pop(c, ctl.text), child: Text(t.save)),
            ],
          );
        },
      );
      if (v != null && mounted) state.setCallStyle(v);
    } finally {
      // The field still paints during the close animation.
      unawaited(Future<void>.delayed(const Duration(milliseconds: 600), ctl.dispose));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final state = context.watch<MindState>();
    final play = _dragging ?? state.callPlay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.cpPlay, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        Slider(
          value: play,
          activeColor: widget.accent,
          onChanged: (v) => setState(() => _dragging = v),
          onChangeEnd: (v) {
            state.setCallPlay(v);
            setState(() => _dragging = null);
          },
        ),
        Text(t.cpPlayWord(play), style: const TextStyle(fontSize: 11, height: 1.45, color: MindColors.ink55)),
        const SizedBox(height: 14),
        Text(t.cpMinutes, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in MindState.callMinuteChoices)
              ChoiceChip(
                label: Text(t.cpMinutesValue(m), style: const TextStyle(fontSize: 12)),
                selected: state.callMaxMinutes == m,
                selectedColor: widget.accent.withValues(alpha: 0.18),
                onSelected: (_) => state.setCallMaxMinutes(m),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(t.cpMinutesHint, style: const TextStyle(fontSize: 10.5, height: 1.45, color: MindColors.ink55)),
        const SizedBox(height: 14),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_editStyle(state)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(t.cpStyle, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(
                      state.callStyle.isEmpty ? t.cpStyleEmpty : state.callStyle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, height: 1.5, color: MindColors.ink55),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit_rounded, size: 18, color: MindColors.ink45),
            ],
          ),
        ),
      ],
    );
  }
}
