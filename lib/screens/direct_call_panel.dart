import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/strings.dart';
import '../i18n/strings_settings.dart';
import '../theme/tokens.dart';

/// First thing in the call settings: is her voice going straight into the call right now, and one
/// button to make it so. The status is asked of the helper itself, not remembered from setup.
class DirectCallPanel extends StatefulWidget {
  const DirectCallPanel({super.key, required this.accent});
  final Color accent;
  @override
  State<DirectCallPanel> createState() => _DirectCallPanelState();
}

class _DirectCallPanelState extends State<DirectCallPanel> with WidgetsBindingObserver {
  static const _channel = MethodChannel('giggok/direct_setup');
  static const _green = Color(0xFF1E8E3E);
  String _live = 'checking';
  bool _busy = false, _failed = false;
  bool _pauseBusy = false, _keyRejected = false;
  int _pauseMinutes = 5;
  Map<dynamic, dynamic> _pause = {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_busy && !_pauseBusy) unawaited(_check());
    });
    unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // Coming back from Android's pairing screen or the native setup page.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) unawaited(_check());
  }

  Future<void> _check() async {
    String live;
    Map<dynamic, dynamic> pause = {};
    var keyRejected = false;
    try { live = await _channel.invokeMethod<String>('live') ?? 'offline'; }
    on Exception { live = 'offline'; }
    try {
      pause = await _channel.invokeMethod<Map<dynamic, dynamic>>('pauseStatus') ?? {};
      if (live == 'offline') keyRejected = await _channel.invokeMethod<String>('status') == 'key_rejected';
    } on Exception { /* old installed build has no pause channel yet */ }
    if (!mounted) return;
    setState(() { _live = live; _pause = pause; _keyRejected = keyRejected; });
  }

  Future<void> _connect() async {
    if (_busy) return;
    if (_live == 'not_paired' || _keyRejected) { await _openSetup(); return; }
    setState(() { _busy = true; _failed = false; });
    var status = '';
    try {
      await _channel.invokeMethod<void>('reconnect');
      // Launch + probe run in the background and take a few seconds.
      for (var i = 0; i < 20 && mounted; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        status = await _channel.invokeMethod<String>('status') ?? '';
        if (status != 'connecting') break;
      }
    } on Exception { status = 'setup_failed'; }
    if (!mounted) return;
    setState(() { _busy = false; _failed = status == 'setup_failed'; _keyRejected = status == 'key_rejected'; });
    await _check();
  }

  Future<void> _pauseForBanking() async {
    if (_pauseBusy) return;
    final t = S.of(context);
    if (_pause['needsConfirmation'] == true) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t.directPauseTitle),
          content: Text(t.directPauseConfirm),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(t.directPauseCancel)),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(t.directPauseConfirmButton)),
          ],
        ),
      );
      if (approved != true || !mounted) return;
    }
    await _pauseCommand('pause', {'minutes': _pauseMinutes});
  }

  Future<void> _pauseCommand(String method, [Map<String, Object>? arguments]) async {
    if (_pauseBusy || !mounted) return;
    setState(() => _pauseBusy = true);
    var ok = false;
    try { ok = await _channel.invokeMethod<bool>(method, arguments) ?? false; }
    on Exception { /* show a single localized result below */ }
    if (!mounted) return;
    setState(() => _pauseBusy = false);
    await _check();
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      method == 'restorePause' ? S.of(context).directPauseRestoreFailed : S.of(context).directPauseFailed,
    )));
  }

  Future<void> _openSetup() async {
    try { await _channel.invokeMethod<void>('open'); } on Exception { /* settings page stays usable */ }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final paused = _pause['paused'] == true;
    final ready = _live == 'ready' && !paused;
    final until = _pause['until'] is int ? _pause['until'] as int : 0;
    final remaining = ((until - DateTime.now().millisecondsSinceEpoch + 59999) ~/ 60000).clamp(0, 999);
    final text = switch (_live) {
      'ready' => t.directCallReady,
      'in_call' => t.directCallInCall,
      'unsupported' => t.directCallUnsupported,
      'not_paired' => t.directCallNotPaired,
      'checking' => t.directCallChecking,
      _ => _keyRejected ? t.directCallKeyRejected : (_failed ? t.directCallNeedsDebugging : t.directCallOffline),
    };
    final canConnect = !paused && !ready && _live != 'in_call' && _live != 'unsupported' && _live != 'checking';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(ready ? Icons.check_circle_rounded : Icons.settings_phone_rounded,
                size: 26, color: ready ? _green : widget.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(t.directCallTitle,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(paused ? t.directCallPaused : (_busy ? t.directCallChecking : text),
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          fontWeight: ready ? FontWeight.w600 : FontWeight.w400,
                          color: ready ? _green : (_failed ? const Color(0xFFB46A00) : MindColors.ink55))),
                ],
              ),
            ),
          ],
        ),
        if (canConnect) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: widget.accent),
            onPressed: _busy ? null : () => unawaited(_connect()),
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.link_rounded, size: 18),
            label: Text(_live == 'not_paired' || _keyRejected ? t.directCallFirstSetup : t.directCallConnect),
          ),
        ],
        if (_live != 'not_paired')
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => unawaited(_openSetup()),
              child: Text(t.directCallSetup, style: const TextStyle(fontSize: 11.5)),
            ),
          ),
        const SizedBox(height: 8),
        if (paused) ...[
          Text(remaining > 0 ? '${t.directPauseRemaining} ${t.directPauseMinutes(remaining)}' : t.directPauseWaiting,
              style: const TextStyle(fontSize: 11.5, color: MindColors.ink55)),
          Row(children: [
            TextButton(onPressed: _pauseBusy ? null : () => unawaited(_pauseCommand('extendPause')),
                child: Text(t.directPauseExtend)),
            const SizedBox(width: 8),
            TextButton(onPressed: _pauseBusy ? null : () => unawaited(_pauseCommand('restorePause')),
                child: Text(t.directPauseRestore)),
          ]),
        ] else if (_pause['supported'] == true && _live != 'not_paired' && _live != 'in_call') ...[
          Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            DropdownButton<int>(
              value: _pauseMinutes,
              items: [5, 15, 30].map((minutes) => DropdownMenuItem(
                value: minutes, child: Text(t.directPauseMinutes(minutes)),
              )).toList(),
              onChanged: _pauseBusy ? null : (value) { if (value != null) setState(() => _pauseMinutes = value); },
            ),
            FilledButton.icon(
              onPressed: _pauseBusy ? null : () => unawaited(_pauseForBanking()),
              icon: const Icon(Icons.pause_circle_outline_rounded, size: 18),
              label: Text(t.directPauseButton),
            ),
          ]),
        ] else if (_live != 'not_paired')
          Text(t.directPauseNeedsSetup, style: const TextStyle(fontSize: 11, color: MindColors.ink55)),
        if (_pause['notificationsEnabled'] == false)
          Text(t.directStatusNotificationsOff, style: const TextStyle(fontSize: 11, color: Color(0xFFB46A00))),
      ],
    );
  }
}
