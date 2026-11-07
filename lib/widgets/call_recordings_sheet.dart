import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../phone/call_notes.dart';
import '../state/mind_state.dart';
import '../i18n/strings_ai.dart';
import '../theme/tokens.dart';

/// เสียงสนทนาที่บันทึกไว้ เปิดจากหน้าอวาต้า · เจ้าของ: "เพิ่มทางเข้าฟังเสียงบันทึกสนทนาไว้ที่หน้า อวาต้า"
///
/// เล่นผ่าน [MindState.playCallNote] ตัวเดียวกับที่เธอเปิดให้ฟังด้วยเสียง · ปิดแผ่นนี้ = หยุดเสียง
/// (เสียงคนอื่นห้ามดังต่อโดยไม่มีปุ่มหยุด)
Future<void> showCallRecordingsSheet(BuildContext context, MindMode mode) async {
  final state = context.read<MindState>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => ChangeNotifierProvider<MindState>.value(value: state, child: _RecordingsSheet(mode: mode)),
  );
  unawaited(state.stopRecording());
}

class _RecordingsSheet extends StatefulWidget {
  const _RecordingsSheet({required this.mode});
  final MindMode mode;

  @override
  State<_RecordingsSheet> createState() => _RecordingsSheetState();
}

class _RecordingsSheetState extends State<_RecordingsSheet> {
  late final Future<List<CallNote>> _list = context.read<MindState>().recordedCalls();

  String _when(S t, DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.dayLabel(at)} · ${two(at.hour)}:${two(at.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final state = context.watch<MindState>();
    final accent = widget.mode.accent;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      maxChildSize: .92,
      builder: (c, scroll) => FutureBuilder<List<CallNote>>(
        future: _list,
        builder: (c, snap) {
          final notes = snap.data;
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              Text(t.recordingsTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (notes == null)
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              else if (notes.isEmpty)
                Text(t.recordingsEmpty, style: const TextStyle(fontSize: 12.5, height: 1.5, color: MindColors.ink55))
              else
                for (final n in notes)
                  _row(t, state, n, accent),
            ],
          );
        },
      ),
    );
  }

  Widget _row(S t, MindState state, CallNote n, Color accent) {
    final playing = state.playingRecording && state.playingNoteId == n.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          IconButton.filledTonal(
            tooltip: playing ? t.callNoteStop : t.callNotePlay,
            onPressed: () => playing ? state.stopRecording() : state.playCallNote(n),
            icon: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded, color: accent),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(t.callNoteTitle(n.who), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                Text(_when(t, n.at), style: const TextStyle(fontSize: 10.5, color: MindColors.ink50)),
                if (n.summary.trim().isNotEmpty)
                  Text(n.summary.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, height: 1.45, color: MindColors.ink55)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
