import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/strings.dart';
import '../i18n/strings_settings.dart';
import '../theme/tokens.dart';

/// First thing in the call settings: is her voice going straight into the call right now, and one
/// button to make it so. The status is asked of the helper itself, not remembered — after a reboot
/// or an update the helper is gone even though setup once succeeded.
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

  // Coming back from Android's pairing screen or the native setup page.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) unawaited(_check());
  }

  Future<void> _check() async {
    String live;
    try { live = await _channel.invokeMethod<String>('live') ?? 'offline'; }
    on Exception { live = 'offline'; }
    if (!mounted) return;
    setState(() => _live = live);
  }

  Future<void> _connect() async {
    if (_busy) return;
    if (_live == 'not_paired') { await _openSetup(); return; }
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
    setState(() { _busy = false; _failed = status == 'setup_failed'; });
    await _check();
  }

  Future<void> _openSetup() async {
    try { await _channel.invokeMethod<void>('open'); } on Exception { /* settings page stays usable */ }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final ready = _live == 'ready';
    final text = switch (_live) {
      'ready' => t.directCallReady,
      'in_call' => t.directCallInCall,
      'unsupported' => t.directCallUnsupported,
      'not_paired' => t.directCallNotPaired,
      'checking' => t.directCallChecking,
      _ => _failed ? t.directCallNeedsDebugging : t.directCallOffline,
    };
    final canConnect = !ready && _live != 'in_call' && _live != 'unsupported' && _live != 'checking';
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
                  Text(_busy ? t.directCallChecking : text,
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
            label: Text(_live == 'not_paired' ? t.directCallFirstSetup : t.directCallConnect),
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
      ],
    );
  }
}
