import 'dart:async';
import 'package:flutter/services.dart';

/// Optional shell audio transport. Failure always leaves the ordinary phone path available.
class DirectAudio {
  static const _channel = MethodChannel('giggok/direct_audio');
  static const _events = EventChannel('giggok/direct_audio_events');
  StreamSubscription<dynamic>? _sub;
  void Function(String source, int timeUs, int rate, Uint8List pcm)? onAudio;
  void Function()? onLost;
  String path = 'speaker';
  bool active = false;

  Future<bool> start({required bool record}) async {
    try {
      _sub ??= _events.receiveBroadcastStream().listen((dynamic event) {
        if (event is! Map) return;
        final pcm = event['pcm'];
        if (pcm is Uint8List) {
          onAudio?.call(event['source'] as String, event['timeUs'] as int, event['rate'] as int, pcm);
        }
      }, onError: (Object _) { active = false; onLost?.call(); });
      final result = await _channel.invokeMethod<String>('start', {'record': record});
      active = result?.startsWith('direct:') == true;
      path = active ? result! : 'speaker';
      if (!active) { await _sub?.cancel(); _sub = null; }
      return active;
    } on Exception {
      await _sub?.cancel(); _sub = null;
      active = false;
      return false;
    }
  }
  Future<void> write(Uint8List pcm) async {
    if (!active) return;
    try { await _channel.invokeMethod<void>('write', {'pcm': pcm}); }
    on Exception { active = false; onLost?.call(); }
  }
  Future<int> pending() async {
    if (!active) return 0;
    try { return await _channel.invokeMethod<int>('pending') ?? 0; }
    on Exception { active = false; onLost?.call(); return 0; }
  }
  Future<({int timeUs, int pendingMs})?> clear() async {
    try {
      final parts = (await _channel.invokeMethod<String>('clear') ?? '').split(':');
      final timeUs = parts.length == 3 && parts.first == 'ok' ? int.tryParse(parts[1]) : null;
      final pendingMs = parts.length == 3 ? int.tryParse(parts[2]) : null;
      if (timeUs == null || pendingMs == null) {
        // A failed clear stops the helper session; carry on over the speaker path.
        active = false;
        onLost?.call();
        return null;
      }
      return (timeUs: timeUs, pendingMs: pendingMs);
    } on Exception { active = false; onLost?.call(); return null; }
  }
  Future<String> takeover() async {
    try { return await _channel.invokeMethod<String>('takeover') ?? 'unavailable'; }
    on Exception { active = false; return 'unavailable'; }
  }
  Future<void> stop() async {
    active = false;
    try { await _channel.invokeMethod<void>('stop'); } on Exception { /* optional helper */ }
    await _sub?.cancel(); _sub = null;
  }
}
