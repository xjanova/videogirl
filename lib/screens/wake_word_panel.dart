import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai/mind_listen.dart';
import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import '../state/mind_state.dart';
import '../system/permissions.dart';
import '../theme/tokens.dart';

/// ตั้งค่า › ทั่วไป › เรียกชื่อเธอ · สอนคำเรียก เปิด/ปิดการรอฟัง ความไว ลองฟังเสียงขาน
///
/// เจ้าของ: "ถ้าเราตั้งค่าไว้ ก็ใช้คำพิเศษเรียกเธอให้รับคำสั่งได้เช่นกัน เช่นน้องมายด์ เธอต้องขานทันทีที่รู้ว่าเรียก
/// เช่น ขา หรือ คะ" · สถานะถามฝั่ง Android ทุกครั้ง (เจ้าของปิดจากแจ้งเตือนได้โดยหน้านี้ไม่รู้)
class WakeWordPanel extends StatefulWidget {
  const WakeWordPanel({super.key, required this.accent, this.listen});

  final Color accent;

  /// เทสต์ใส่ตัวปลอม
  final MindListen? listen;

  @override
  State<WakeWordPanel> createState() => _WakeWordPanelState();
}

class _WakeWordPanelState extends State<WakeWordPanel> with WidgetsBindingObserver {
  late final MindListen _listen = widget.listen ?? MindListen.instance;
  final _word = TextEditingController();
  ListenStatus? _status;

  /// กำลังสอน · null = ไม่ได้สอน · ค่า = พูดครบกี่ครั้งแล้ว
  int? _taught;
  String? _message;
  bool _busy = false;
  bool _preparing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listen
      ..onTeach = _onTeach
      ..onChanged = _refresh;
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _listen
      ..onTeach = null
      ..onChanged = null;
    // ออกจากหน้ากลางการสอน · ไมค์ต้องไม่อัดค้าง คำเรียกเดิมยังอยู่
    if (_taught != null) unawaited(_listen.teachStop());
    _word.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
    // สลับแอปกลางการสอน = เสียงนั้นไม่ใช่ตัวอย่าง
    if (state == AppLifecycleState.paused && _taught != null) _cancelTeach();
  }

  void _refresh() => unawaited(_check());

  Future<void> _check() async {
    final st = await _listen.status();
    if (!mounted) return;
    setState(() => _status = st);
    if (_word.text.isEmpty && st.word != null) _word.text = st.word!;
  }

  void _onTeach(TeachEvent e) {
    if (!mounted || _taught == null) return;
    final t = S.of(context);
    if (e.done) {
      setState(() {
        _taught = null;
        _message = t.wakeTeachDone;
      });
      unawaited(_finishTeach());
      return;
    }
    setState(() {
      _taught = e.count;
      _message = switch (e.why) {
        'length' => t.wakeTeachTooShort,
        'unlike' => t.wakeTeachUnlike,
        _ => null,
      };
    });
  }

  /// สอนจบ · ตั้งชื่อคำเรียก เปิดรอฟัง เตรียมเสียงขาน
  Future<void> _finishTeach() async {
    final state = context.read<MindState>();
    await _listen.setLabel(_word.text.trim());
    await _listen.setWake(true);
    await _renderReplies(state);
    await _check();
  }

  /// เสียงขานต้องเตรียมล่วงหน้า · รอเน็ตตอนถูกเรียก = ไม่ทันที · ล้มทั้งหมด = เสียงสั้น ๆ ฝั่งเนทีฟแทน
  Future<void> _renderReplies(MindState state) async {
    if (mounted) setState(() => _preparing = true);
    try {
      final clips = await state.renderWakeReplies();
      if (clips.isNotEmpty) await _listen.setReplies(clips);
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _teach() async {
    if (_busy || _taught != null) return;
    final t = S.of(context);
    final word = _word.text.trim();
    if (word.isEmpty) {
      setState(() => _message = t.wakeWordEmpty);
      return;
    }
    _busy = true;
    try {
      if (_status?.taught == true && !await _confirm(t.wakeReplaceAsk, t.wakeReplaceYes)) return;
      if (!mounted) return;
      final perms = context.read<MindPermissions>();
      if (!perms.of(MindPermission.mic)) await perms.request(MindPermission.mic);
      if (!mounted) return;
      if (!perms.of(MindPermission.mic)) {
        setState(() => _message = t.micDenied);
        return;
      }
      // ไม่มีแจ้งเตือน = ไมค์เปิดโดยเจ้าของไม่เห็นปุ่มหยุด · ขอไว้ · ปฏิเสธก็ยังใช้ได้ (จุดเขียวยังขึ้น)
      if (!perms.of(MindPermission.notify)) await perms.request(MindPermission.notify);
      final ok = await _listen.teachStart();
      if (!mounted) return;
      setState(() {
        _taught = ok ? 0 : null;
        _message = ok ? null : t.wakeTeachFailed;
      });
    } finally {
      _busy = false;
    }
  }

  void _cancelTeach() {
    unawaited(_listen.teachStop());
    setState(() {
      _taught = null;
      _message = null;
    });
  }

  Future<void> _setWake(bool on) async {
    if (_busy) return;
    _busy = true;
    final state = context.read<MindState>();
    try {
      await _listen.setWake(on);
      await _check();
      if (on) await _renderReplies(state);
    } finally {
      _busy = false;
    }
  }

  Future<void> _setSensitivity(int level) async {
    await _listen.setSensitivity(level);
    await _check();
  }

  Future<void> _forget() async {
    if (_busy) return;
    final t = S.of(context);
    _busy = true;
    try {
      if (!await _confirm(t.wakeForgetAsk, t.wakeForgetYes)) return;
      await _listen.forget();
      _word.clear();
      await _check();
    } finally {
      _busy = false;
    }
  }

  Future<void> _tryReply() async {
    final st = _status;
    if (st != null && st.replies == 0) await _renderReplies(context.read<MindState>());
    await _listen.playReply();
    await _check();
  }

  Future<bool> _confirm(String body, String yes) async {
    final t = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.wakeCancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
        ],
      ),
    );
    return ok ?? false;
  }

  static const _small = TextStyle(fontSize: 10.5, height: 1.5, color: MindColors.ink55);

  Widget _teaching(S t) {
    final word = _word.text.trim();
    final done = _taught ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(t.wakeSay(word, done + 1, MindListen.samples),
            style: const TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w600, color: MindColors.ink)),
        LinearProgressIndicator(value: done / MindListen.samples, color: widget.accent),
        if (_message != null)
          Text(_message!, style: const TextStyle(fontSize: 11, height: 1.45, color: Color(0xFFB3261E))),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(onPressed: _cancelTeach, child: Text(t.wakeCancel)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final st = _status;
    if (_taught != null) return _teaching(t);
    final taught = st?.taught == true;
    final on = st?.wake == true && taught;
    final (line, good) = switch (st) {
      null => ('…', true),
      ListenStatus(taught: false) => (t.wakeNeedTeach, false),
      ListenStatus(paused: true) => (t.wakePaused, false),
      ListenStatus(running: true) => (t.wakeListening, true),
      _ => (t.wakeOffNow, false),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(t.wakeIntro, style: _small),
        Row(
          spacing: MindSpace.md,
          children: [
            Expanded(
              child: Text(t.wakeSwitch,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: MindColors.ink)),
            ),
            Switch(
              value: on,
              activeTrackColor: widget.accent,
              onChanged: taught ? (v) => unawaited(_setWake(v)) : null,
            ),
          ],
        ),
        Row(
          spacing: 6,
          children: [
            Icon(good ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                size: 16, color: good ? const Color(0xFF1E8E3E) : MindColors.ink55),
            Expanded(
              child: Text(taught && st?.word != null ? '${t.wakeWordIs(st!.word!)} · $line' : line,
                  style: const TextStyle(fontSize: 11, height: 1.45, color: MindColors.ink)),
            ),
          ],
        ),
        if (_message != null) Text(_message!, style: const TextStyle(fontSize: 11, height: 1.45, color: MindColors.ink)),
        if (_preparing) Text(t.wakePreparing, style: _small),
        TextField(
          controller: _word,
          maxLength: 30,
          decoration: InputDecoration(
            labelText: t.wakeWordField,
            hintText: t.wakeDefaultWord,
            counterText: '',
            isDense: true,
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: () => unawaited(_teach()),
              icon: const Icon(Icons.mic_none_rounded, size: 16),
              label: Text(taught ? t.wakeTeachAgain : t.wakeTeach),
            ),
            if (taught)
              TextButton.icon(
                onPressed: _preparing ? null : () => unawaited(_tryReply()),
                icon: const Icon(Icons.volume_up_rounded, size: 16),
                label: Text(t.wakeTryReply),
              ),
            if (taught)
              TextButton.icon(
                onPressed: () => unawaited(_forget()),
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: Text(t.wakeForget),
              ),
          ],
        ),
        if (taught) ...[
          Text(t.wakeSensitivity, style: const TextStyle(fontSize: 11, color: MindColors.ink)),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 0, label: Text(t.wakeStrict)),
              ButtonSegment(value: 1, label: Text(t.wakeNormal)),
              ButtonSegment(value: 2, label: Text(t.wakeLoose)),
            ],
            selected: {st?.sensitivity ?? 1},
            onSelectionChanged: (s) => unawaited(_setSensitivity(s.first)),
          ),
        ],
        Text(t.wakePrivacy, style: _small),
      ],
    );
  }
}
