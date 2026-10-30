import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/phone/direct_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('giggok/direct_audio');
  const events = 'giggok/direct_audio_events';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Map<String, Object?> replies;
  late List<String> calls;

  setUp(() {
    calls = [];
    replies = {};
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      final reply = replies[call.method];
      if (reply is PlatformException) throw reply;
      return reply;
    });
    // The event stream only needs to accept listen/cancel.
    messenger.setMockMethodCallHandler(
        const MethodChannel(events), (call) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(const MethodChannel(events), null);
  });

  test('a helper that cannot reach the uplink leaves the speaker path', () async {
    replies['start'] = 'unavailable';
    final direct = DirectAudio();
    expect(await direct.start(record: true), isFalse);
    expect(direct.active, isFalse);
    expect(direct.path, 'speaker');
  });

  test('no helper paired at all leaves the speaker path', () async {
    replies['start'] =
        PlatformException(code: 'direct_unavailable', message: 'IllegalStateException');
    final direct = DirectAudio();
    expect(await direct.start(record: false), isFalse);
    expect(direct.path, 'speaker');
  });

  test('the report names the variant that reached the uplink', () async {
    replies['start'] = 'direct:C';
    final direct = DirectAudio();
    expect(await direct.start(record: true), isTrue);
    expect(direct.path, 'direct:C');
  });

  test('barge-in returns the cut time and what the caller never heard', () async {
    replies['start'] = 'direct:A';
    replies['clear'] = 'ok:1250000:340';
    final direct = DirectAudio();
    var lost = false;
    direct.onLost = () => lost = true;
    await direct.start(record: true);
    final cut = await direct.clear();
    expect(cut, isNotNull);
    expect(cut!.timeUs, 1250000);
    expect(cut.pendingMs, 340);
    expect(lost, isFalse);
    expect(direct.active, isTrue);
  });

  test('a failed barge-in hands the call back to the speaker path', () async {
    // The helper stops the whole session when CLEAR fails; staying "active"
    // would leave her silent for the rest of the call.
    replies['start'] = 'direct:C';
    replies['clear'] = 'error:IOException';
    final direct = DirectAudio();
    var lost = false;
    direct.onLost = () => lost = true;
    await direct.start(record: true);
    expect(await direct.clear(), isNull);
    expect(lost, isTrue);
    expect(direct.active, isFalse);
    await direct.write(Uint8List(480));
    expect(calls.where((m) => m == 'write'), isEmpty);
  });
}
