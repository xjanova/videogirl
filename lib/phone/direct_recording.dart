import 'dart:math' as math;
import 'dart:typed_data';

/// Her voice arrives at full scale. 3 dB off before it goes into the call leaves the phone's
/// uplink and the recording room to mix it, which at full scale they only do by clipping.
const herGain = 0.7;

/// Whole samples only: the helper ends the session on an odd write.
Uint8List withHeadroom(Uint8List pcm) {
  final count = pcm.length ~/ 2;
  final source = ByteData.sublistView(pcm);
  final out = ByteData(count * 2);
  for (var i = 0; i < count; i++) {
    out.setInt16(i * 2, (source.getInt16(i * 2, Endian.little) * herGain).round(), Endian.little);
  }
  return out.buffer.asUint8List();
}

/// Bounded PCM timeline for direct call recordings. All timestamps share the
/// helper's monotonic epoch. Drain with a short delay so both sides have arrived.
/// A source replaces its own overlapping samples; different sources are mixed.
class DirectRecordingMixer {
  DirectRecordingMixer({
    int maxBufferMs = 10000,
    this.maxSources = 3,
    int startTimeUs = 0,
  }) : _capacity = maxBufferMs * 16,
       _cursor = startTimeUs * outputRate ~/ 1000000 {
    if (maxBufferMs < 1 || maxBufferMs > 60000) {
      throw RangeError.range(maxBufferMs, 1, 60000, 'maxBufferMs');
    }
    if (maxSources < 1 || maxSources > 8 || startTimeUs < 0) {
      throw ArgumentError('Invalid timeline bounds');
    }
  }

  static const outputRate = 16000;

  /// Mixed peaks stay untouched up to here, then bend towards full scale.
  static const _knee = 24000;

  /// Low-pass at 7.2 kHz for 24 kHz input (windowed sinc): speech above 8 kHz would otherwise
  /// fold back into the 16 kHz recording as a rasp on every "s".
  static const _lowPass = [
    0.00600, -0.01328, -0.05011, 0.25983, 0.59512, 0.25983, -0.05011, -0.01328, 0.00600,
  ];

  final int maxSources;
  final int _capacity;
  int _cursor;
  int _end = 0;
  final Map<String, _Source> _sources = {};

  int get positionUs => _cursor * 1000000 ~/ outputRate;
  int get bufferedFrames => math.max(0, _end - _cursor);

  /// PCM16 little endian; only the two call transport rates are accepted.
  /// Late samples are ignored. Reject unreasonable packets before allocating.
  ///
  /// [jitterUs] is how far a packet's stamp may stray from where the source's
  /// audio already reaches and still be its continuation. Her stamps come from
  /// the wall clock plus the track's coarse head position, so they wobble by
  /// tens of ms; taken literally every packet leaves a hole or an overlap, and
  /// dozens of those a second is the crackle in the recording.
  void add({
    required String source,
    required int timeUs,
    required Uint8List pcm,
    required int sampleRate,
    int jitterUs = 0,
  }) {
    if (source.isEmpty || source.length > 64 || timeUs < 0) {
      throw ArgumentError('Invalid source or timestamp');
    }
    if (sampleRate != 16000 && sampleRate != 24000) {
      throw ArgumentError.value(
        sampleRate,
        'sampleRate',
        'Expected 16000 or 24000',
      );
    }
    if (pcm.length.isOdd) {
      throw const FormatException('Incomplete PCM16 sample');
    }
    if (pcm.isEmpty) return;
    final count = pcm.length ~/ 2;
    if (count > _capacity * sampleRate ~/ outputRate) {
      throw RangeError('Audio packet exceeds the buffer window');
    }
    final suppliedStart = timeUs * outputRate / 1000000;
    if (suppliedStart >= _cursor + _capacity) {
      throw RangeError('Audio timestamp is outside the buffer window');
    }
    var state = _sources[source];
    if (state == null) {
      if (_sources.length >= maxSources) {
        throw StateError('Too many audio sources');
      }
      state = _Source(_capacity);
      _sources[source] = state;
    }
    final step = outputRate / sampleRate;
    final expected = state.nextPosition;
    final continuous =
        state.rate == sampleRate &&
        expected != null &&
        (expected - suppliedStart).abs() <=
            math.max(0.01601, jitterUs * outputRate / 1000000); // One us timestamp rounding.
    final start = continuous ? expected : suppliedStart;
    if (start + count * step > _cursor + _capacity + 0.000001) {
      throw RangeError('Audio packet extends beyond the buffer window');
    }
    if (!continuous) {
      state.lastPosition = null;
      state.lastValue = null;
      state.history.fillRange(0, state.history.length, 0);
    }
    final data = ByteData.sublistView(pcm);
    for (var i = 0; i < count; i++) {
      final position = start + i * step;
      final raw = data.getInt16(i * 2, Endian.little);
      final value = sampleRate == outputRate ? raw : _filter(state, raw);
      final previousPosition = state.lastPosition;
      final previousValue = state.lastValue;
      if (previousPosition != null && previousValue != null) {
        final first = (previousPosition - 0.000001).ceil();
        final last = (position + 0.000001).floor();
        for (var frame = math.max(_cursor, first); frame <= last; frame++) {
          final fraction = ((frame - previousPosition) / step).clamp(0.0, 1.0);
          _put(
            state,
            frame,
            (previousValue + (value - previousValue) * fraction).round(),
          );
        }
      } else if ((position - position.round()).abs() < 0.000001) {
        _put(state, position.round(), value);
      }
      state.lastPosition = position;
      state.lastValue = value;
    }
    state.rate = sampleRate;
    state.nextPosition = start + count * step;
  }

  int _filter(_Source source, int value) {
    final history = source.history;
    history[source.head] = value.toDouble();
    source.head = (source.head + 1) % history.length;
    var sum = 0.0;
    for (var i = 0; i < history.length; i++) {
      sum += _lowPass[i] * history[(source.head + i) % history.length];
    }
    return sum.round();
  }

  static int _limit(int sum) {
    final size = sum.abs();
    if (size <= _knee) return sum;
    final over = (size - _knee) / (32767 - _knee);
    final bent = (_knee + (32767 - _knee) * over / (1 + over)).round();
    return sum.isNegative ? -bent : bent;
  }

  void _put(_Source source, int frame, int value) {
    if (frame < _cursor || frame >= _cursor + _capacity) return;
    source.samples[frame % _capacity] = value;
    _end = math.max(_end, frame + 1);
  }

  /// Produce silence for gaps, limit the mixed sum, then release consumed
  /// slots. Each call allocates at most maxBufferMs of output; call again when
  /// catching up over a longer gap. Time never moves backwards.
  Uint8List drain({required int throughUs}) {
    if (throughUs < 0) throw ArgumentError.value(throughUs, 'throughUs');
    final target = throughUs * outputRate ~/ 1000000;
    final count = (target - _cursor).clamp(0, _capacity);
    final result = ByteData(count * 2);
    for (var i = 0; i < count; i++) {
      final slot = (_cursor + i) % _capacity;
      var sum = 0;
      for (final state in _sources.values) {
        sum += state.samples[slot];
        state.samples[slot] = 0;
      }
      result.setInt16(i * 2, _limit(sum), Endian.little);
    }
    _cursor += count;
    return result.buffer.asUint8List();
  }

  /// Flush future assistant playback on barge-in without erasing caller audio.
  /// The next packet starts a new resampling segment; it cannot interpolate
  /// against the discarded sentence's last sample.
  void discardAfter({required String source, required int timeUs}) {
    if (timeUs < 0) throw ArgumentError.value(timeUs, 'timeUs');
    final state = _sources[source];
    if (state == null) return;
    final first = math.max(_cursor, (timeUs * outputRate / 1000000).ceil());
    for (var frame = first; frame < _cursor + _capacity; frame++) {
      state.samples[frame % _capacity] = 0;
    }
    state.nextPosition = null;
    state.lastPosition = null;
    state.lastValue = null;
    state.history.fillRange(0, state.history.length, 0);
  }
}

class _Source {
  _Source(int capacity) : samples = Int32List(capacity);
  final Int32List samples;
  final history = Float64List(DirectRecordingMixer._lowPass.length);
  int head = 0;
  int? rate;
  double? nextPosition;
  double? lastPosition;
  int? lastValue;
}
