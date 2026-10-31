import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/phone/direct_recording.dart';

Uint8List pcm(List<int> values) {
  final bytes = ByteData(values.length * 2);
  for (var i = 0; i < values.length; i++) {
    bytes.setInt16(i * 2, values[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

List<int> samples(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return List.generate(
    bytes.length ~/ 2,
    (i) => data.getInt16(i * 2, Endian.little),
  );
}

void main() {
  test(
    'independent caller and assistant timestamps align with silence gaps',
    () {
      final mixer = DirectRecordingMixer();
      mixer.add(
        source: 'caller',
        timeUs: 0,
        pcm: pcm([100, 200, 300, 400]),
        sampleRate: 16000,
      );
      mixer.add(
        source: 'assistant',
        timeUs: 125,
        pcm: pcm([1000, 2000]),
        sampleRate: 16000,
      );
      expect(samples(mixer.drain(throughUs: 375)), [
        100,
        200,
        1300,
        2400,
        0,
        0,
      ]);
    },
  );

  test('mixing stays in range on both signs without integer wrap', () {
    final mixer = DirectRecordingMixer();
    for (final source in ['caller', 'assistant', 'owner']) {
      mixer.add(
        source: source,
        timeUs: 0,
        pcm: pcm([20000, -20000]),
        sampleRate: 16000,
      );
    }
    final mixed = samples(mixer.drain(throughUs: 125));
    expect(mixed[0], greaterThan(24000));
    expect(mixed[1], -mixed[0]);
  });

  test('24k resampling has no seams at irregular chunk edges', () {
    final values = List.generate(2400, (i) => (i % 97) * 300 - 14000);
    final whole = DirectRecordingMixer();
    final split = DirectRecordingMixer();
    whole.add(
      source: 'assistant',
      timeUs: 0,
      pcm: pcm(values),
      sampleRate: 24000,
    );
    var offset = 0;
    for (final size in [1, 2, 71, 3, 307, 2016]) {
      split.add(
        source: 'assistant',
        timeUs: offset * 1000000 ~/ 24000,
        pcm: pcm(values.sublist(offset, offset + size)),
        sampleRate: 24000,
      );
      offset += size;
    }
    expect(offset, values.length);
    final joined = samples(split.drain(throughUs: 100000));
    final single = samples(whole.drain(throughUs: 100000));
    expect(joined.length, single.length);
    for (var i = 0; i < single.length; i++) {
      expect((joined[i] - single[i]).abs(), lessThanOrEqualTo(1)); // A rounding tie, not a seam.
    }
  });

  test(
    'barge-in drops future assistant PCM but preserves caller and owner',
    () {
      final mixer = DirectRecordingMixer();
      mixer.add(
        source: 'caller',
        timeUs: 0,
        pcm: pcm([100, 100, 100, 100]),
        sampleRate: 16000,
      );
      mixer.add(
        source: 'assistant',
        timeUs: 0,
        pcm: pcm([1000, 1000, 1000, 1000]),
        sampleRate: 16000,
      );
      mixer.discardAfter(source: 'assistant', timeUs: 125);
      mixer.add(
        source: 'owner',
        timeUs: 125,
        pcm: pcm([2000, 2000]),
        sampleRate: 16000,
      );
      expect(samples(mixer.drain(throughUs: 250)), [1100, 1100, 2100, 2100]);
    },
  );

  test('drained ring slots cannot leak into later silence', () {
    final mixer = DirectRecordingMixer(maxBufferMs: 1);
    mixer.add(
      source: 'caller',
      timeUs: 0,
      pcm: pcm(List.filled(16, 900)),
      sampleRate: 16000,
    );
    expect(samples(mixer.drain(throughUs: 1000)), List.filled(16, 900));
    expect(samples(mixer.drain(throughUs: 2000)), List.filled(16, 0));
    expect(mixer.bufferedFrames, 0);
  });

  test(
    'late samples cannot rewrite output and bounded drains preserve long gaps',
    () {
      final mixer = DirectRecordingMixer(maxBufferMs: 1);
      expect(mixer.drain(throughUs: 1000000000).length, 32);
      expect(mixer.positionUs, 1000);
      mixer.add(
        source: 'caller',
        timeUs: 0,
        pcm: pcm([500, 500]),
        sampleRate: 16000,
      );
      expect(samples(mixer.drain(throughUs: 2000)), List.filled(16, 0));
    },
  );

  test(
    'malformed PCM, unbounded packets, unsupported rates and far future rejected',
    () {
      final mixer = DirectRecordingMixer(maxBufferMs: 1);
      expect(
        () => mixer.add(
          source: 'caller',
          timeUs: 0,
          pcm: Uint8List(1),
          sampleRate: 16000,
        ),
        throwsFormatException,
      );
      expect(
        () => mixer.add(
          source: 'caller',
          timeUs: 0,
          pcm: pcm([1]),
          sampleRate: 8000,
        ),
        throwsArgumentError,
      );
      expect(
        () => mixer.add(
          source: 'caller',
          timeUs: 0,
          pcm: Uint8List(34),
          sampleRate: 16000,
        ),
        throwsRangeError,
      );
      expect(
        () => mixer.add(
          source: 'caller',
          timeUs: 1000000000,
          pcm: pcm([1]),
          sampleRate: 16000,
        ),
        throwsRangeError,
      );
      expect(mixer.bufferedFrames, 0);
    },
  );

  test('overlap from one source replaces samples instead of doubling them', () {
    final mixer = DirectRecordingMixer();
    mixer.add(
      source: 'caller',
      timeUs: 0,
      pcm: pcm([10, 20, 30, 40]),
      sampleRate: 16000,
    );
    mixer.add(
      source: 'caller',
      timeUs: 0,
      pcm: pcm([10, 20, 30, 40]),
      sampleRate: 16000,
    );
    expect(samples(mixer.drain(throughUs: 250)), [10, 20, 30, 40]);
  });
}
