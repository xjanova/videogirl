import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../i18n/strings_hold.dart';
import '../phone/hold_audio.dart';
import '../state/mind_state.dart';
import '../system/permissions.dart';
import '../theme/tokens.dart';

/// Hold, transfer and sales on calls. Owner: "แก้เรื่องให้เธอ พักสายได้ เพื่อถามเรา ทางคู่สนทนาจะได้ยินสิ่งที่
/// เราตั้งไว้ให้เขาฟังเช่นเพลง หรือโฆษณาต่างๆ ... มายด์สามารถโอนสาย ได้ ตั้งเบอร์ที่โอนสายได้". Every default is
/// neutral (built-in music, transfer and sales off): the owner's own business facts live in call knowledge.
class CallHoldPanel extends StatefulWidget {
  const CallHoldPanel({super.key, required this.accent});
  final Color accent;
  @override
  State<CallHoldPanel> createState() => _CallHoldPanelState();
}

class _CallHoldPanelState extends State<CallHoldPanel> {
  static const _warn = Color(0xFFB46A00);

  final _number = TextEditingController();
  final _numberFocus = FocusNode();
  String? _numberError;
  String? _soundError;

  /// Picking or removing runs · one at a time (double taps do nothing).
  bool _busy = false;
  bool _previewing = false;
  File? _previewTemp;

  @override
  void initState() {
    super.initState();
    _number.text = context.read<MindState>().transferNumber;
    _numberFocus.addListener(() {
      if (!_numberFocus.hasFocus) _saveNumber();
    });
  }

  @override
  void dispose() {
    if (_previewing) unawaited(_stopPreview(rebuild: false));
    unawaited(_previewTemp?.delete().then((_) {}, onError: (Object _) {}));
    _number.dispose();
    _numberFocus.dispose();
    super.dispose();
  }

  void _saveNumber() {
    final state = context.read<MindState>();
    final t = S.of(context);
    final err = state.setTransferNumber(_number.text);
    setState(() => _numberError = switch (err) {
          'bad_number' => t.transferBadNumber,
          'blocked' => t.transferBlocked,
          _ => null,
        });
    // An emptied number cannot stay switched on.
    if (err == null && _number.text.trim().isEmpty && state.transferOn) state.setTransferOn(false);
  }

  Future<void> _pick(MindState state) async {
    if (_busy) return;
    final t = S.of(context);
    setState(() {
      _busy = true;
      _soundError = null;
    });
    try {
      Map<Object?, Object?>? picked;
      try {
        picked = await kSystemChannel.invokeMethod<Map<Object?, Object?>>('pickTextFile');
      } on PlatformException {
        picked = {'error': 'read_failed'};
      } on MissingPluginException {
        picked = null;
      }
      if (picked == null || !mounted) return; // cancelled
      final error = picked['error'], name = picked['name'], bytes = picked['bytes'];
      if (error is String || name is! String || bytes is! Uint8List) {
        setState(() => _soundError = error == 'too_large' ? t.holdTooLarge : t.holdReadFailed);
        return;
      }
      if (_previewing) await _stopPreview();
      final err = await state.setHoldFile(name, bytes);
      if (mounted && err != null) setState(() => _soundError = t.holdNotAudio);
    } on FileSystemException {
      if (mounted) setState(() => _soundError = t.holdReadFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear(MindState state) async {
    if (_busy) return;
    final t = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t.holdClearAsk(state.holdFileName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.holdClear, style: const TextStyle(color: Color(0xFFC62828))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (_previewing) await _stopPreview();
      await state.clearHoldFile();
    } on FileSystemException {
      // The copy is already gone · the setting still went back to the built-in music.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview(MindState state) async {
    if (_previewing) {
      await _stopPreview();
      return;
    }
    final t = S.of(context);
    setState(() {
      _previewing = true;
      _soundError = null;
    });
    try {
      final path = state.holdSound == HoldSound.file ? state.holdFilePath : await _builtinFile();
      if (path == null) return;
      // Resolves when it finishes or is stopped.
      final ok = await kSystemChannel.invokeMethod<bool>('playAudioFile', {'path': path});
      if (ok != true && mounted && _previewing && state.holdSound == HoldSound.file) {
        setState(() => _soundError = t.holdCannotPlay);
      }
    } on PlatformException {
      if (mounted) setState(() => _soundError = t.holdCannotPlay);
    } on MissingPluginException {
      // Not Android · nothing to play.
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<String> _builtinFile() async {
    final have = _previewTemp;
    if (have != null && await have.exists()) return have.path;
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}hold_preview.wav');
    await f.writeAsBytes(HoldMusic.wav(await HoldMusic.load()), flush: true);
    _previewTemp = f;
    return f.path;
  }

  Future<void> _stopPreview({bool rebuild = true}) async {
    try {
      await kSystemChannel.invokeMethod<bool>('stopAudioFile');
    } on Object {
      // Nothing native to stop.
    }
    if (rebuild && mounted) setState(() => _previewing = false);
  }

  Future<void> _editSalesNote(MindState state) async {
    final ctl = TextEditingController(text: state.callSalesNote);
    try {
      final v = await showDialog<String>(
        context: context,
        builder: (c) {
          final t = S.of(c);
          return AlertDialog(
            title: Text(t.salesNote, style: const TextStyle(fontSize: 15)),
            content: TextField(
              controller: ctl,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              maxLength: MindState.salesNoteMax,
              decoration: InputDecoration(helperText: t.salesNoteHint, helperMaxLines: 3),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: Text(t.cancel)),
              TextButton(onPressed: () => Navigator.pop(c, ctl.text), child: Text(t.save)),
            ],
          );
        },
      );
      if (v != null && mounted) state.setCallSalesNote(v);
    } finally {
      // The field still paints during the close animation.
      unawaited(Future<void>.delayed(const Duration(milliseconds: 600), ctl.dispose));
    }
  }

  Widget _switch(String title, String hint, bool value, ValueChanged<bool>? onChanged) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(hint, style: const TextStyle(fontSize: 10.5, height: 1.45, color: MindColors.ink55)),
              ],
            ),
          ),
          // สีที่ track ไม่ใช่ thumb · thumb สีเดียวกับ track ของธีม = ปุ่มกลมหายตอนเปิด (เห็นบนเครื่องจริง)
          Switch(value: value, activeTrackColor: widget.accent, onChanged: onChanged),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final state = context.watch<MindState>();
    final sound = state.holdSound;
    final hasFile = state.holdFilePath != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.holdCardIntro, style: const TextStyle(fontSize: 11, height: 1.45, color: MindColors.ink55)),
        const SizedBox(height: 12),
        _switch(t.holdAskIncoming, t.holdAskIncomingHint, state.incomingAskOwner, state.setIncomingAskOwner),
        const SizedBox(height: 14),
        Text(t.holdSoundLabel, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in HoldSound.values)
              if (s != HoldSound.file || hasFile)
                ChoiceChip(
                  label: Text(t.holdSoundName(s), style: const TextStyle(fontSize: 12)),
                  selected: sound == s,
                  selectedColor: widget.accent.withValues(alpha: 0.18),
                  onSelected: (_) => state.setHoldSound(s),
                ),
          ],
        ),
        if (hasFile) ...[
          const SizedBox(height: 6),
          Text(t.holdFileNow(state.holdFileName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: MindColors.ink55)),
        ],
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: _busy ? null : () => unawaited(_pick(state)),
              icon: const Icon(Icons.library_music_rounded, size: 18),
              label: Text(t.holdPick, style: const TextStyle(fontSize: 12)),
            ),
            if (sound != HoldSound.none)
              TextButton.icon(
                onPressed: () => unawaited(_preview(state)),
                icon: Icon(_previewing ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                label: Text(_previewing ? t.holdPreviewStop : t.holdPreview, style: const TextStyle(fontSize: 12)),
              ),
            if (hasFile)
              TextButton.icon(
                onPressed: _busy ? null : () => unawaited(_clear(state)),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text(t.holdClear, style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
        Text(t.holdPickHint, style: const TextStyle(fontSize: 10.5, height: 1.45, color: MindColors.ink55)),
        if (_soundError != null) ...[
          const SizedBox(height: 4),
          Text(_soundError!, style: const TextStyle(fontSize: 11.5, height: 1.4, color: _warn)),
        ],
        const SizedBox(height: 4),
        Text(t.holdLimit, style: const TextStyle(fontSize: 10.5, height: 1.45, color: MindColors.ink45)),
        const Divider(height: 28),
        _switch(
          t.transferSwitch,
          t.transferHint,
          state.transferOn,
          (v) {
            if (v) {
              // The typed number may not be saved yet (focus still in the field).
              _saveNumber();
              if (_numberError != null) return;
              if (state.transferNumber.trim().isEmpty) {
                setState(() => _numberError = t.transferNeedsNumber);
                return;
              }
            }
            state.setTransferOn(v);
          },
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _number,
          focusNode: _numberFocus,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _saveNumber(),
          decoration: InputDecoration(
            isDense: true,
            labelText: t.transferNumber,
            hintText: t.transferNumberHint,
            errorText: _numberError,
          ),
        ),
        const SizedBox(height: 6),
        Text(t.transferLimits, style: const TextStyle(fontSize: 10.5, height: 1.45, color: MindColors.ink45)),
        const Divider(height: 28),
        _switch(t.salesSwitch, t.salesHint, state.callSales, state.setCallSales),
        if (state.callSales && !state.callLookupReady) ...[
          const SizedBox(height: 4),
          Text(t.salesNeedsKnowledge, style: const TextStyle(fontSize: 11, height: 1.4, color: _warn)),
        ],
        if (state.callSales)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_editSalesNote(state)),
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        Text(t.salesNote, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text(
                          state.callSalesNote.isEmpty ? t.salesNoteHint : state.callSalesNote,
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
          ),
      ],
    );
  }
}
