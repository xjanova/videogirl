import 'dart:math' as math;
import 'dart:typed_data';

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
  final int maxSources;
  final int _capacity;
  int _cursor;
  int _end = 0;
  final Map<String, _Source> _sources = {};

  int get positionUs => _cursor * 1000000 ~/ outputRate;
  int get bufferedFrames => math.max(0, _end - _cursor);

  /// PCM16 little endian; only the two call transport rates are accepted.
  /// Late samples are ignored. Reject unreasonable packets before allocating.
  void add({
    required String source,
    required int timeUs,
    required Uint8List pcm,
    required int sampleRate,
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
            0.01601; // One us timestamp rounding.
    final start = continuous ? expected : suppliedStart;
    if (start + count * step > _cursor + _capacity + 0.000001) {
      throw RangeError('Audio packet extends beyond the buffer window');
    }
    if (!continuous) {
      state.lastPosition = null;
      state.lastValue = null;
    }
    final data = ByteData.sublistView(pcm);
    for (var i = 0; i < count; i++) {
      final position = start + i * step;
      final value = data.getInt16(i * 2, Endian.little);
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

  void _put(_Source source, int frame, int value) {
    if (frame < _cursor || frame >= _cursor + _capacity) return;
    source.samples[frame % _capacity] = value;
    _end = math.max(_end, frame + 1);
  }

  /// Produce silence for gaps, saturate the mixed sum, then release consumed
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
      result.setInt16(i * 2, sum.clamp(-32768, 32767), Endian.little);
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
  }
}

class _Source {
  _Source(int capacity) : samples = Int32List(capacity);
  final Int32List samples;
  int? rate;
  double? nextPosition;
  double? lastPosition;
  int? lastValue;
}
