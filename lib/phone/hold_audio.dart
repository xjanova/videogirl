import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// เสียงที่คนโทรได้ยินตอนน้องมายพักสายไปถามเจ้าของ
///
/// เจ้าของ: "ทางคู่สนทนาจะได้ยินสิ่งที่เราตั้งไว้ให้เขาฟังเช่นเพลง หรือโฆษณาต่างๆ"
///
/// 🔴 ใช้ได้เฉพาะการพักสาย**ในแอป** (ask_owner · สายยังคุยอยู่ แค่ปิดไมค์) · ตอนโอนสายหาเจ้าของ
/// คนโทรถูกพักสาย**ในเครือข่าย** เสียงจากแอปไปไม่ถึง (ดู CallTransfer.kt)
enum HoldSound {
  /// เพลงกล่องดนตรีที่แต่งในแอป · ไม่ต้องมีไฟล์ ไม่มีลิขสิทธิ์ใคร
  builtin,

  /// ไฟล์ที่เจ้าของเลือกจากเครื่อง (เพลง โฆษณา)
  file,

  /// เงียบ (แบบเดิม)
  none;

  static HoldSound of(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => builtin);
}

/// PCM 16 บิต ช่องเดียว ของเพลงพักสาย
class HoldMusic {
  /// ตรงกับอัตราที่ตัวช่วยต่อสายตรงเล่นเข้าสาย (`ShellAudio.RATE`)
  static const rate = 24000;

  /// ไฟล์ของเจ้าของถอดไม่เกินเท่านี้ · เพลงสี่นาทีถอดเต็ม = ราว 11 MB ค้างในหน่วยความจำทั้งสาย
  static const maxFileMs = 120000;

  /// ดังสุดของเพลงพักสาย (สัดส่วนเต็มสเกล) · ต่ำกว่าเสียงเธอ ไม่ให้คนโทรสะดุ้ง
  static const peak = 0.45;

  static Uint8List? _builtin;

  /// เพลงในแอป 16 วินาที วนต่อกันเนียน (โน้ตที่ยังก้องตอนจบไหลไปต้นรอบ)
  static Uint8List builtin() => _builtin ??= _compose();

  /// เหมือน [builtin] แต่แต่งนอกเธรดจอ (ราวหนึ่งในสิบวินาทีบนเครื่องจริง) · ระหว่างสายจอต้องไม่กระตุก
  static Future<Uint8List> load() async {
    final ready = _builtin;
    if (ready != null) return ready;
    final made = await Isolate.run(_compose);
    return _builtin = made;
  }

  static double _hz(int midi) => 440.0 * math.pow(2, (midi - 69) / 12.0);

  static Uint8List _compose() {
    const beat = 0.5; // วินาทีต่อโน้ต · แปดโน้ตต่อคอร์ด
    // C – Am – F – G · โน้ตในคอร์ด (ราก สาม ห้า รากบน) ช่วงกล่องดนตรี 440–1046 Hz
    const chords = [
      [72, 76, 79, 84],
      [69, 72, 76, 81],
      [65, 69, 72, 77],
      [67, 71, 74, 79],
    ];
    const bass = [60, 57, 53, 55];
    const pattern = [0, 1, 2, 3, 2, 1, 2, 1];
    final n = (chords.length * pattern.length * beat * rate).round();
    final mix = Float64List(n);

    void bell(double at, int midi, double gain, {double decay = 0.45, double ring = 1.6}) {
      final f = _hz(midi);
      final start = (at * rate).round();
      final len = (ring * rate).round();
      for (var i = 0; i < len; i++) {
        final t = i / rate;
        final attack = t < 0.005 ? t / 0.005 : 1.0;
        final w = 2 * math.pi * f * t;
        // ฮาร์มอนิกบนหายเร็วกว่าเสียงหลัก = เสียงกริ๊งแบบกล่องดนตรี
        final v = math.sin(w) +
            0.25 * math.exp(-t / 0.2) * math.sin(2 * w) +
            0.08 * math.exp(-t / 0.1) * math.sin(3 * w);
        mix[(start + i) % n] += gain * attack * math.exp(-t / decay) * v;
      }
    }

    for (var c = 0; c < chords.length; c++) {
      final bar = c * pattern.length * beat;
      bell(bar, bass[c], 0.35, decay: 1.4, ring: 4.0);
      for (var k = 0; k < pattern.length; k++) {
        bell(bar + k * beat, chords[c][pattern[k]], k == 0 ? 0.6 : 0.45);
      }
    }
    return _toPcm(mix, peak);
  }

  /// ไฟล์ของเจ้าของ (ถอดแล้ว) → พร้อมวน · ลดเสียงให้ไม่ดังกว่า [peak] · ค่อย ๆ เข้า/ค่อย ๆ จบ
  /// แล้วเว้นเงียบครึ่งวิก่อนวนรอบใหม่ (เพลงที่ถูกตัดตรง [maxFileMs] จบนุ่มสองวิ ไม่ขาดกลางคำ)
  static Uint8List loopable(Uint8List pcm) {
    final count = pcm.length ~/ 2;
    if (count == 0) return Uint8List(0);
    final src = ByteData.sublistView(pcm);
    var top = 1;
    for (var i = 0; i < count; i++) {
      final v = src.getInt16(i * 2, Endian.little).abs();
      if (v > top) top = v;
    }
    final gain = math.min(1.0, peak * 32767 / top);
    final fadeIn = math.min(count, rate ~/ 50);
    final cut = count >= (maxFileMs - 1000) * rate ~/ 1000;
    final fadeOut = math.min(count, cut ? rate * 2 : rate ~/ 20);
    final gap = rate ~/ 2;
    final out = ByteData((count + gap) * 2);
    for (var i = 0; i < count; i++) {
      var g = gain;
      if (i < fadeIn) g *= i / fadeIn;
      final left = count - i;
      if (left < fadeOut) g *= left / fadeOut;
      out.setInt16(i * 2, (src.getInt16(i * 2, Endian.little) * g).round(), Endian.little);
    }
    return out.buffer.asUint8List();
  }

  static Uint8List _toPcm(Float64List mix, double peak) {
    var top = 1e-9;
    for (final v in mix) {
      if (v.abs() > top) top = v.abs();
    }
    final scale = peak * 32767 / top;
    final out = ByteData(mix.length * 2);
    for (var i = 0; i < mix.length; i++) {
      out.setInt16(i * 2, (mix[i] * scale).round().clamp(-32768, 32767), Endian.little);
    }
    return out.buffer.asUint8List();
  }

  /// ห่อ PCM เป็น WAV ให้เครื่องเล่นของระบบเล่นได้ (ทางลำโพง)
  static Uint8List wav(Uint8List pcm) {
    final out = BytesBuilder();
    void ascii(String v) => out.add(v.codeUnits);
    void u32(int v) => out.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
    void u16(int v) => out.add([v & 255, (v >> 8) & 255]);
    ascii('RIFF');
    u32(36 + pcm.length);
    ascii('WAVE');
    ascii('fmt ');
    u32(16);
    u16(1);
    u16(1);
    u32(rate);
    u32(rate * 2);
    u16(2);
    u16(16);
    ascii('data');
    u32(pcm.length);
    out.add(pcm);
    return out.toBytes();
  }
}

/// ป้อนเพลงพักสายเข้าสายตรงทีละชิ้น ตามคิวที่เหลือ · ไม่มีจับเวลาเอง ([CallSession] เรียกทุกรอบ 100 ms)
///
/// 🔴 คิวสั้นไว้เสมอ ([aheadMs]) · เธอกลับมาพูดเมื่อไหร่ เสียงเธอต่อคิวหลังเพลงที่ส่งไปแล้ว ·
/// ไม่ล้างคิว (`DirectAudio.clear` พลาด = เสียงทางสายตรงหายทั้งสาย) · คิวสั้น = เธอช้าไม่เกินครึ่งวิ
class HoldFeed {
  HoldFeed(this.pcm, {this.pieceMs = 200, this.aheadMs = 400});

  final Uint8List pcm;
  final int pieceMs;
  final int aheadMs;

  int _pos = 0;
  bool _fadeIn = true;
  bool _paused = false;

  bool get paused => _paused;

  /// หยุดป้อน (เธอกำลังจะพูด) · ตำแหน่งเพลงคงไว้ เล่นต่อจากเดิม
  void pause() => _paused = true;

  void resume() {
    if (!_paused) return;
    _paused = false;
    _fadeIn = true;
  }

  /// ชิ้นถัดไปที่ควรส่ง เมื่อคิวยังเหลือ [pendingMs] · null = ยังไม่ต้องส่ง
  Uint8List? next(int pendingMs) {
    if (_paused || pcm.length < 2 || pendingMs >= aheadMs) return null;
    final size = (HoldMusic.rate * pieceMs ~/ 1000) * 2;
    final piece = Uint8List(size);
    for (var i = 0; i < size; i++) {
      piece[i] = pcm[(_pos + i) % pcm.length];
    }
    _pos = (_pos + size) % pcm.length;
    if (_fadeIn) {
      _fadeIn = false;
      final data = ByteData.sublistView(piece);
      final count = size ~/ 2;
      for (var i = 0; i < count; i++) {
        data.setInt16(i * 2, (data.getInt16(i * 2, Endian.little) * i / count).round(), Endian.little);
      }
    }
    return piece;
  }
}

/// ไฟล์เสียงพักสายที่เจ้าของเลือก · เก็บสำเนาในพื้นที่แอป (ไฟล์ต้นทางย้าย/ลบทีหลังก็ยังเล่นได้)
class HoldStore {
  static final _ext = RegExp(r'\.(mp3|m4a|aac|wav|ogg|opus|flac|amr|3gp)$', caseSensitive: false);

  /// ไฟล์เสียงที่เครื่องถอดได้ (ดู PcmDecoder.kt) · ดูจากนามสกุล ตัวเลือกไฟล์บางเครื่องบอกชนิดผิด
  static bool accepts(String name) => _ext.hasMatch(name.trim());

  static final _ours = RegExp(r'[\\/]hold_audio[\\/]hold_\d+\.(mp3|m4a|aac|wav|ogg|opus|flac|amr|3gp)$');

  /// ที่อยู่นี้เป็นสำเนาที่ [save] เขียนไว้เองไหม · ค่าตั้งที่ถูกแก้ให้ชี้ไฟล์อื่นในเครื่อง = ไม่เล่นให้คนโทรฟัง
  static bool owns(String path) => !path.contains('..') && _ours.hasMatch(path);

  static Future<Directory> _dir([Directory? root]) async =>
      Directory('${(root ?? await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}hold_audio');

  /// เก็บไฟล์ใหม่แทนไฟล์เดิม · คืนที่อยู่ไฟล์ · [root] ให้เทสต์ชี้ที่อื่นได้
  static Future<String> save(String name, Uint8List bytes, {Directory? root}) async {
    final m = _ext.firstMatch(name.trim());
    if (m == null) throw ArgumentError.value(name, 'name', 'not an audio file');
    final dir = await _dir(root);
    await clear(root: root);
    await dir.create(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}hold_${DateTime.now().millisecondsSinceEpoch}'
        '.${m.group(1)!.toLowerCase()}');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }

  static Future<void> clear({Directory? root}) async {
    final dir = await _dir(root);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
