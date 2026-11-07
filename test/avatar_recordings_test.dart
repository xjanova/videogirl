/// ทางเข้าฟังเสียงบันทึกสนทนาจากหน้าอวาต้า · เจ้าของ (2026-11-07): "เพิ่มทางเข้าฟังเสียงบันทึกสนทนาไว้ที่หน้า อวาต้า"
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videogirl/i18n/strings.dart';

String _src(String path) => File(path).readAsStringSync();

void main() {
  test('ปุ่มหูฟังอยู่ในแถวปุ่มบนเวที (ไม่ขึ้นตอนอยู่ในสาย/สตูดิโอ)', () {
    final home = _src('lib/screens/home_screen.dart');
    final column = home.substring(home.indexOf('if (!studio && !onCall)'), home.indexOf('// แถบบอกสถานะกล้อง'));
    expect(column, contains('Icons.headphones_rounded'));
    expect(column, contains('showCallRecordingsSheet(context, mode)'));
  });

  test('🔴 ปิดแผ่นรายการ = หยุดเสียง · เล่นทางเดียวกับที่เธอเปิดให้ฟังด้วยเสียง', () {
    final sheet = _src('lib/widgets/call_recordings_sheet.dart');
    final show = sheet.substring(sheet.indexOf('Future<void> showCallRecordingsSheet('), sheet.indexOf('class _RecordingsSheet '));
    expect(show.indexOf('unawaited(state.stopRecording())'), greaterThan(show.indexOf('await showModalBottomSheet')));
    expect(sheet, contains('state.playCallNote(n)'));
    final state = _src('lib/state/mind_state.dart');
    expect(state, contains('Future<void> playCallNote(CallNote note) async {'));
    expect(state, contains('_playingNoteId = note.id;'));
  });

  test('ข้อความครบสองภาษา', () {
    for (final lang in AppLang.values) {
      expect(S(lang).recordingsTitle, isNotEmpty);
      expect(S(lang).recordingsEmpty, isNotEmpty);
    }
  });
}
