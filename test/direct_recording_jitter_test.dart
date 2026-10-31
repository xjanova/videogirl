import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/phone/direct_recording.dart';

Uint8List _pcm(List<int> values) {
  final bytes = ByteData(values.length * 2);
  for (var i = 0; i < values.length; i++) {
    bytes.setInt16(i * 2, values[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

List<int> _samples(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  return List.generate(bytes.length ~/ 2, (i) => data.getInt16(i * 2, Endian.little));
}

List<int> _tone(double hz, int amplitude, int count) =>
    List.generate(count, (i) => (math.sin(2 * math.pi * hz * i / 24000) * amplitude).round());

double _rms(List<int> values) =>
    math.sqrt(values.fold<double>(0, (sum, v) => sum + v * v) / values.length);

void main() {
  test('jittered playback timestamps leave no holes or clicks in her voice', () {
    // The helper stamps each PLAYED packet from the wall clock plus the track's coarse head position.
    final mixer = DirectRecordingMixer();
    final voice = _tone(440, 12000, 24000);
    final random = math.Random(7);
    for (var offset = 0; offset < voice.length; offset += 480) {
      final jitterUs = random.nextInt(14000) - 7000;
      mixer.add(
        source: 'assistant',
        timeUs: 20000 + offset * 1000000 ~/ 24000 + jitterUs,
        pcm: _pcm(voice.sublist(offset, offset + 480)),
        sampleRate: 24000,
        jitterUs: 100000,
      );
    }
    final out = _samples(mixer.drain(throughUs: 990000)).sublist(1600);
    var jump = 0;
    for (var i = 1; i < out.length; i++) {
      jump = math.max(jump, (out[i] - out[i - 1]).abs());
    }
    // A 440 Hz tone at this level moves about 2070 per 16 kHz frame at its steepest.
    expect(jump, lessThan(2300));
    expect(out.where((s) => s == 0).length, lessThan(8));
  });

  test('a real pause beyond the jitter window still lands at its own time', () {
    final mixer = DirectRecordingMixer();
    void say(int atUs) => mixer.add(
          source: 'assistant',
          timeUs: atUs,
          pcm: _pcm(List.filled(2400, 8000)),
          sampleRate: 24000,
          jitterUs: 100000,
        );
    say(0);
    say(500000);
    final out = _samples(mixer.drain(throughUs: 700000));
    expect(out[4000], 0); // 250 ms: between the two sentences.
    expect(out[8800], closeTo(8000, 8)); // 550 ms: the second sentence, not pulled back to 100 ms.
  });

  test('jitter tolerance does not stop a barge-in from starting clean', () {
    final mixer = DirectRecordingMixer();
    mixer.add(
      source: 'assistant',
      timeUs: 0,
      pcm: _pcm(List.filled(2400, 8000)),
      sampleRate: 24000,
      jitterUs: 100000,
    );
    mixer.discardAfter(source: 'assistant', timeUs: 50000);
    mixer.add(
      source: 'assistant',
      timeUs: 60000,
      pcm: _pcm(List.filled(2400, 4000)),
      sampleRate: 24000,
      jitterUs: 100000,
    );
    final out = _samples(mixer.drain(throughUs: 150000));
    expect(out[100 * 16], closeTo(4000, 8));
    expect(out[55 * 16], 0);
  });

  test('speech above 8 kHz does not fold back into the 16 kHz recording', () {
    final mixer = DirectRecordingMixer();
    final hiss = _tone(11000, 12000, 24000);
    mixer.add(source: 'assistant', timeUs: 0, pcm: _pcm(hiss), sampleRate: 24000);
    final out = _samples(mixer.drain(throughUs: 900000)).sublist(1600);
    expect(_rms(out), lessThan(_rms(hiss) * 0.12));
  });

  test('speech below the cutoff passes through at its own level', () {
    final mixer = DirectRecordingMixer();
    final voice = _tone(1000, 12000, 24000);
    mixer.add(source: 'assistant', timeUs: 0, pcm: _pcm(voice), sampleRate: 24000);
    final out = _samples(mixer.drain(throughUs: 900000)).sublist(1600);
    expect(_rms(out), closeTo(_rms(voice), _rms(voice) * 0.03));
  });

  test('a hot mix bends under full scale instead of flattening or wrapping', () {
    final mixer = DirectRecordingMixer();
    for (final source in ['caller', 'assistant', 'owner']) {
      mixer.add(source: source, timeUs: 0, pcm: _pcm([30000, -30000, 8000]), sampleRate: 16000);
    }
    final out = _samples(mixer.drain(throughUs: 188));
    expect(out[0], inExclusiveRange(24000, 32767));
    expect(out[1], -out[0]);
    expect(out[2], 24000); // At the knee: untouched.
  });

  group('withHeadroom', () {
    test('takes 3 dB off, keeps the sign, never overflows', () {
      expect(_samples(withHeadroom(_pcm([32767, -32768, 1000, 0]))), [22937, -22938, 700, 0]);
    });

    test('an odd byte count still comes out as whole samples', () {
      expect(withHeadroom(Uint8List(5)).length, 4);
      expect(withHeadroom(Uint8List(0)), isEmpty);
    });

    test('reads a view that starts on an odd offset', () {
      final raw = Uint8List(7);
      raw.setRange(1, 5, _pcm([1000, -1000]));
      expect(_samples(withHeadroom(Uint8List.sublistView(raw, 1, 5))), [700, -700]);
    });
  });
}
