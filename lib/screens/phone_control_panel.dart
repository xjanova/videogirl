import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../hands/hands_bridge.dart';
import '../i18n/strings.dart';
import '../i18n/strings_hands.dart';
import '../state/mind_state.dart';
import '../system/permissions.dart';
import '../theme/tokens.dart';

/// ตั้งค่า › ทั่วไป › ใช้เครื่องแทน · สวิตช์ + สถานะจริงของบริการ (ถามฝั่ง Android ทุกครั้งที่เปิด/กลับเข้าแอป)
class PhoneControlPanel extends StatefulWidget {
  const PhoneControlPanel({super.key, required this.accent});

  final Color accent;

  @override
  State<PhoneControlPanel> createState() => _PhoneControlPanelState();
}

class _PhoneControlPanelState extends State<PhoneControlPanel> with WidgetsBindingObserver {
  HandsStatus? _status;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // กลับมาจากหน้าการช่วยเหลือพิเศษ · สถานะอาจเพิ่งเปลี่ยน
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final st = await context.read<MindState>().hands.status();
      if (!mounted) return;
      setState(() => _status = st);
    } finally {
      _checking = false;
    }
  }

  Future<void> _openAccessibility() async {
    try {
      await kSystemChannel.invokeMethod<Object?>('openAccessibility');
    } on Object {
      // เปิดหน้าตั้งค่าไม่ได้ = ไม่มีอะไรให้ทำต่อ · สถานะยังบอกอยู่
    }
  }

  bool _starting = false;

  void _toast(String text) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 5)));

  /// ตั้งชื่อ → (ชื่อซ้ำ: ถามก่อนทับ) → เริ่มจำ
  Future<void> _teach() async {
    if (_starting) return;
    final state = context.read<MindState>();
    final t = S.of(context);
    final name = await showDialog<String>(context: context, builder: (_) => const _MacroNameDialog());
    if (!mounted || name == null || name.trim().isEmpty) return;
    if (state.hasMacro(name)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          content: Text(t.macroOverwrite(name.trim())),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.macroCancel)),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t.macroOverwriteYes)),
          ],
        ),
      );
      if (!mounted || ok != true) return;
    }
    setState(() => _starting = true);
    final why = await state.startTeaching(name);
    if (!mounted) return;
    setState(() => _starting = false);
    if (why != null) _toast(why);
  }

  Future<void> _delete(String name) async {
    final t = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t.macroDeleteAsk(name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.macroCancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t.macroDelete)),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    context.read<MindState>().deleteMacro(name);
  }

  Widget _macros(BuildContext context, S t) {
    final state = context.watch<MindState>();
    final teaching = state.teachingMacro;
    final busy = state.phoneTask != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        const Divider(height: 18),
        Text(t.macroSection, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: MindColors.ink)),
        Text(t.macroSectionHint, style: const TextStyle(fontSize: 10.5, height: 1.5, color: MindColors.ink55)),
        if (teaching != null) ...[
          Text(t.macroTeaching(teaching), style: const TextStyle(fontSize: 11.5, height: 1.45, color: MindColors.ink)),
          Row(
            spacing: 8,
            children: [
              OutlinedButton(onPressed: () => unawaited(state.cancelTeaching()), child: Text(t.macroCancel)),
              FilledButton(onPressed: () => unawaited(state.finishTeaching()), child: Text(t.macroDone)),
            ],
          ),
        ] else ...[
          if (state.phoneMacros.isEmpty)
            Text(t.macroNone, style: const TextStyle(fontSize: 11, color: MindColors.ink55)),
          for (final m in state.phoneMacros)
            Row(
              children: [
                Expanded(
                  child: Text('${m.name} · ${t.macroSteps(m.steps.length)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: MindColors.ink)),
                ),
                TextButton(
                  onPressed: busy ? null : () => unawaited(state.runMacro(m.name)),
                  child: Text(t.macroRun),
                ),
                IconButton(
                  tooltip: t.macroDelete,
                  onPressed: () => unawaited(_delete(m.name)),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: busy || _starting ? null : () => unawaited(_teach()),
              icon: const Icon(Icons.school_outlined, size: 16),
              label: Text(t.macroTeach),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final on = context.select<MindState, bool>((s) => s.phoneControl);
    final st = _status;
    final (line, ready) = switch (st) {
      null => ('…', true),
      HandsStatus(supported: false) => (t.handsStatusUnsupported, false),
      HandsStatus(paused: true) => (t.handsStatusPaused, true),
      HandsStatus(canAutoEnable: true) => (t.handsStatusAuto, true),
      HandsStatus(enabled: true) => (t.handsStatusManual, true),
      _ => (t.handsStatusNeedsSetup, false),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
          spacing: MindSpace.md,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(t.handsSwitch,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: MindColors.ink)),
                  Text(t.handsSwitchHint, style: const TextStyle(fontSize: 10.5, height: 1.5, color: MindColors.ink55)),
                ],
              ),
            ),
            Switch(
              value: on,
              activeTrackColor: widget.accent,
              onChanged: (v) => context.read<MindState>().setPhoneControl(v),
            ),
          ],
        ),
        if (on) ...[
          Row(
            spacing: 6,
            children: [
              Icon(ready ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  size: 16, color: ready ? const Color(0xFF1E8E3E) : MindColors.ink55),
              Expanded(
                child: Text(line, style: const TextStyle(fontSize: 11, height: 1.45, color: MindColors.ink)),
              ),
            ],
          ),
          if (st != null && st.supported && !st.enabled && !st.canAutoEnable)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _openAccessibility,
                icon: const Icon(Icons.accessibility_new_rounded, size: 16),
                label: Text(t.handsOpenA11y),
              ),
            ),
          if (st != null && !st.notifications)
            Text(t.handsNotificationsOff, style: const TextStyle(fontSize: 10.5, height: 1.45, color: MindColors.ink55)),
          if (st != null && st.supported) _macros(context, t),
        ],
      ],
    );
  }
}

/// ตั้งชื่อขั้นตอนที่จะสอน · คืนชื่อ (null = ยกเลิก)
class _MacroNameDialog extends StatefulWidget {
  const _MacroNameDialog();

  @override
  State<_MacroNameDialog> createState() => _MacroNameDialogState();
}

class _MacroNameDialogState extends State<_MacroNameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return AlertDialog(
      title: Text(t.macroTeach),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 60,
        decoration: InputDecoration(labelText: t.macroNameLabel, hintText: t.macroNameHint),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.macroCancel)),
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => FilledButton(
            onPressed: _name.text.trim().isEmpty ? null : () => Navigator.pop(context, _name.text.trim()),
            child: Text(t.macroStart),
          ),
        ),
      ],
    );
  }
}
