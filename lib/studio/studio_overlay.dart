import 'dart:async';

import 'package:flutter/material.dart';

import '../avatar/avatar_view.dart';
import '../i18n/strings.dart';
import '../i18n/strings_studio.dart';
import '../state/mind_state.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';
import 'mind_studio.dart';
import 'studio_backdrop.dart';

/// ปุ่มของสตูดิโอ — ลอยทับเวทีเต็มจอ แล้ว**หายเอง**
///
/// 🔴 ทุกอย่างบนจอนี้ติดไปในภาพที่แชร์ให้คู่สายดู · ปุ่มที่ค้างอยู่คือปุ่มที่
/// คนอีกฝั่งนั่งดูตลอดสาย จึงหายเองหลังไม่มีใครแตะ 4 วินาที และแตะจอเพื่อเรียก
/// กลับ · ตอนอยู่ในจอลอยไม่มีอะไรเลยนอกจากตัวเธอ
///
/// ตอนกำลังอัดและปุ่มหายไปแล้ว ยังเหลือจุดแดงเล็ก ๆ มุมจอ — คลิปที่อัดอ่าน
/// จากผืนผ้าใบของเวทีตรง ๆ จุดนี้จึงไม่ติดไปในคลิป แต่เจ้าของต้องรู้เสมอว่ากำลัง
/// อัดอยู่
class StudioOverlay extends StatefulWidget {
  const StudioOverlay({
    super.key,
    required this.studio,
    required this.avatar,
    required this.state,
  });

  final MindStudio studio;
  final MindAvatarController avatar;
  final MindState state;

  @override
  State<StudioOverlay> createState() => _StudioOverlayState();
}

class _StudioOverlayState extends State<StudioOverlay> {
  static const _idle = Duration(seconds: 4);
  static const _recRed = Color(0xFFFF3B4E);

  bool _shown = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  /// นับถอยหลังซ่อนปุ่มใหม่ · ทุกการแตะในแผงเรียกตัวนี้ ไม่งั้นแผงหายกลางมือ
  void _arm() {
    _hide?.cancel();
    _hide = Timer(_idle, () {
      if (mounted) setState(() => _shown = false);
    });
  }

  void _toggle() {
    if (_shown) {
      _hide?.cancel();
      setState(() => _shown = false);
    } else {
      setState(() => _shown = true);
      _arm();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.studio, widget.avatar, widget.state]),
      builder: (context, _) {
        final studio = widget.studio;
        if (studio.inPip) return const SizedBox.shrink();
        final recording = studio.rec == StudioRec.recording;

        return Stack(
          fit: StackFit.expand,
          children: [
            // แตะตรงไหนก็ได้ = เรียก/ซ่อนปุ่ม
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggle,
              ),
            ),
            if (recording && !_shown)
              Positioned(
                top: MediaQuery.paddingOf(context).top + 10,
                right: 12,
                child: IgnorePointer(child: _RecBadge(elapsed: studio.recElapsed)),
              ),
            IgnorePointer(
              ignoring: !_shown,
              child: AnimatedOpacity(
                opacity: _shown ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: Listener(
                  onPointerDown: (_) => _arm(),
                  behavior: HitTestBehavior.translucent,
                  child: SafeArea(child: _controls(context)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _controls(BuildContext context) {
    final s = S.of(context);
    final studio = widget.studio;
    final state = widget.state;
    final mode = state.mode;

    return Padding(
      padding: const EdgeInsets.all(MindSpace.md),
      child: Column(
        children: [
          Row(
            children: [
              _Pill(
                icon: Icons.close_rounded,
                label: s.studioExit,
                onTap: studio.rec == StudioRec.saving ? null : studio.exit,
              ),
              const Spacer(),
              _Pill(
                icon: Icons.picture_in_picture_alt_rounded,
                label: s.studioPip,
                onTap: studio.enterPip,
              ),
            ],
          ),
          const Spacer(),
          GlassPanel(
            radius: MindRadius.panel,
            fill: MindColors.glass80,
            filter: MindGlass.light,
            shadows: MindShadows.soft(),
            padding: const EdgeInsets.all(MindSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: MindSpace.sm,
              children: [
                Text(
                  s.studioHowTo,
                  style: const TextStyle(fontSize: 11.5, height: 1.4, color: MindColors.ink60),
                ),
                _backdrops(context, s),
                if (StudioBackdrops.isKey(state.studioBackdrop))
                  Text(
                    s.studioKeyTip,
                    style: const TextStyle(fontSize: 11, height: 1.35, color: MindColors.ink55),
                  ),
                _camera(context, s, mode),
                _record(context, s, mode),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── ฉากหลัง ──────────────────────────────────────────

  Widget _backdrops(BuildContext context, S s) {
    final current = widget.state.studioBackdrop;
    final custom = !StudioBackdrops.presets.contains(current);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: MindSpace.xs,
      children: [
        _label(s.studioBackdrop),
        Wrap(
          spacing: MindSpace.sm,
          runSpacing: MindSpace.sm,
          children: [
            for (final v in StudioBackdrops.presets)
              _Swatch(
                color: StudioBackdrops.colorOf(v),
                label: _backdropName(s, v),
                selected: v == current,
                gradient: v == StudioBackdrops.app,
                onTap: () => widget.studio.setBackdrop(v),
              ),
            _Swatch(
              color: custom ? StudioBackdrops.colorOf(current) : Colors.white,
              label: s.studioBackdropCustom,
              selected: custom,
              icon: Icons.colorize_rounded,
              onTap: () => _pickCustom(context, s),
            ),
          ],
        ),
      ],
    );
  }

  static String _backdropName(S s, String v) => switch (v) {
        StudioBackdrops.app => s.studioBackdropApp,
        StudioBackdrops.green => s.studioBackdropGreen,
        StudioBackdrops.blue => s.studioBackdropBlue,
        StudioBackdrops.magenta => s.studioBackdropMagenta,
        StudioBackdrops.black => s.studioBackdropBlack,
        StudioBackdrops.white => s.studioBackdropWhite,
        _ => v,
      };

  Future<void> _pickCustom(BuildContext context, S s) async {
    _hide?.cancel();
    final current = widget.state.studioBackdrop;
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _HexDialog(
        s: s,
        initial: current == StudioBackdrops.app ? '' : current,
      ),
    );
    if (!mounted) return;
    _arm();
    if (picked != null) await widget.studio.setBackdrop(picked);
  }

  // ── กล้อง ─────────────────────────────────────────────

  Widget _camera(BuildContext context, S s, MindMode mode) {
    final a = widget.avatar;
    final warming = a.mocapPhase == MindMocapPhase.starting ||
        a.mocapPhase == MindMocapPhase.calibrating;
    final line = _mocapLine(s, a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: MindSpace.xs,
      children: [
        Row(
          spacing: MindSpace.sm,
          children: [
            Expanded(
              child: _Pill(
                icon: a.mocapOn ? Icons.face_retouching_off_rounded : Icons.face_rounded,
                label: a.mocapOn ? s.studioFollowFaceOff : s.studioFollowFace,
                busy: warming,
                tint: a.mocapOn ? mode.accent : null,
                onTap: () => a.mocapOn ? a.stopMocap() : a.startMocap(),
              ),
            ),
            SegmentedButton<MindMocapShot>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              segments: [
                ButtonSegment(value: MindMocapShot.face, label: Text(s.puppetShotFace)),
                ButtonSegment(value: MindMocapShot.bust, label: Text(s.puppetShotBust)),
                ButtonSegment(value: MindMocapShot.full, label: Text(s.puppetShotFull)),
              ],
              selected: {widget.state.mocapShot},
              onSelectionChanged: (v) => widget.studio.setShot(v.first),
            ),
          ],
        ),
        if (line != null)
          Text(line, style: const TextStyle(fontSize: 11, height: 1.35, color: MindColors.ink60)),
      ],
    );
  }

  /// สถานะกล้องเชิดหุ่นที่ต้องบอกจริง ๆ · null = ไม่มีอะไรต้องบอก
  static String? _mocapLine(S s, MindAvatarController a) {
    if (a.mocapBlocked) return s.puppetBlocked;
    if (a.mocapDenied) return s.puppetDenied;
    return switch (a.mocapPhase) {
      MindMocapPhase.starting => s.puppetStarting,
      MindMocapPhase.calibrating => a.mocapTracking ? s.puppetCalibrating : s.puppetNoFace,
      MindMocapPhase.failed => s.puppetFailed,
      MindMocapPhase.live => a.mocapTracking ? null : s.puppetNoFace,
      MindMocapPhase.off => null,
    };
  }

  // ── อัดคลิป ───────────────────────────────────────────

  Widget _record(BuildContext context, S s, MindMode mode) {
    final studio = widget.studio;
    final rec = studio.rec;
    final busy = rec == StudioRec.starting || rec == StudioRec.saving;
    final recording = rec == StudioRec.recording;

    return Row(
      spacing: MindSpace.sm,
      children: [
        Expanded(
          child: MergeSemantics(
            child: Row(
              children: [
                Switch(
                  value: widget.state.studioMic,
                  // เปลี่ยนกลางคลิปไม่มีผล — ไมค์ถูกต่อเข้าคลิปตอนเริ่มอัดเท่านั้น
                  onChanged: rec == StudioRec.idle ? studio.setMic : null,
                ),
                const SizedBox(width: MindSpace.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.studioRecMic,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: MindColors.ink)),
                      Text(s.studioRecMicNote,
                          style: const TextStyle(fontSize: 10.5, color: MindColors.ink55)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Semantics(
          button: true,
          label: recording ? s.studioStop : s.studioRecord,
          child: GestureDetector(
            onTap: busy
                ? null
                : recording
                    ? studio.stopRecording
                    : studio.startRecording,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: MindSpace.md, vertical: MindSpace.sm),
              decoration: BoxDecoration(
                color: recording ? _recRed : Colors.white,
                borderRadius: BorderRadius.circular(MindRadius.pill),
                border: Border.all(color: _recRed, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: MindSpace.xs,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _recRed),
                    )
                  else
                    Icon(
                      recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
                      size: 18,
                      color: recording ? Colors.white : _recRed,
                    ),
                  Text(
                    rec == StudioRec.saving
                        ? s.studioRecSaving
                        : recording
                            ? '${s.studioStop} · ${_clock(studio.recElapsed)}'
                            : s.studioRecord,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: recording ? Colors.white : _recRed,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static Widget _label(String text) => Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: MindColors.ink75),
      );
}

String _clock(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$sec';
}

/// ปุ่มเม็ดยาบนกระจก — ใช้ทั้งแถบบนและปุ่มกล้อง
class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
    this.tint,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final fg = tint ?? MindColors.ink;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? .45 : 1,
          child: GlassPanel(
            radius: MindRadius.pill,
            fill: MindColors.glass80,
            shadows: MindShadows.soft(),
            padding: const EdgeInsets.symmetric(horizontal: MindSpace.md, vertical: MindSpace.sm),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: MindSpace.xs,
                children: [
                  if (busy)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                    )
                  else
                    Icon(icon, size: 18, color: fg),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// วงสีของฉากหลัง
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    this.gradient = false,
    this.icon,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// วาดเป็นพื้นไล่สีของแอป ไม่ใช่สีเดียว
  final bool gradient;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dark = color.computeLuminance() < .4;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          child: Column(
            spacing: 2,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: gradient ? null : color,
                  gradient: gradient ? MindGradients.home : null,
                  border: Border.all(
                    color: selected ? MindColors.violet : MindColors.ink22,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: icon == null
                    ? null
                    : Icon(icon, size: 16, color: dark ? Colors.white : MindColors.ink60),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: MindColors.ink75,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// กล่องใส่รหัสสีเอง · เป็น StatefulWidget เพื่อให้ตัวควบคุมช่องพิมพ์ถูกปิด
/// ตอนกล่องหายไปจริง ไม่ใช่ตอนที่แอนิเมชันปิดกล่องยังวาดช่องพิมพ์อยู่
class _HexDialog extends StatefulWidget {
  const _HexDialog({required this.s, required this.initial});

  final S s;
  final String initial;

  @override
  State<_HexDialog> createState() => _HexDialogState();
}

class _HexDialogState extends State<_HexDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final hex = StudioBackdrops.fromInput(_text.text);
    if (hex == null) {
      setState(() => _error = widget.s.studioCustomBad);
      return;
    }
    Navigator.of(context).pop(hex);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return AlertDialog(
      title: Text(s.studioCustomTitle),
      content: TextField(
        controller: _text,
        autofocus: true,
        maxLength: 7,
        decoration: InputDecoration(hintText: s.studioCustomHint, errorText: _error),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel)),
        TextButton(onPressed: _submit, child: Text(s.save)),
      ],
    );
  }
}

/// จุดแดงกับเวลาที่อัดไปแล้ว — เหลืออยู่ตอนปุ่มหายไป
class _RecBadge extends StatelessWidget {
  const _RecBadge({required this.elapsed});

  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(MindRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          const Icon(Icons.fiber_manual_record_rounded, size: 10, color: _StudioOverlayState._recRed),
          Text(
            _clock(elapsed),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
