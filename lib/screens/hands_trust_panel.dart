import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../hands/phone_task.dart';
import '../i18n/strings.dart';
import '../i18n/strings_trust.dart';
import '../state/mind_state.dart';
import '../theme/tokens.dart';

/// รายการ "อนุญาตถาวร" ของงานในเครื่อง · ดูและยกเลิกได้ทีละอัน หรือทั้งหมด (ยืนยันก่อน)
class HandsTrustPanel extends StatelessWidget {
  const HandsTrustPanel({super.key, required this.accent});
  final Color accent;

  Future<void> _removeAll(BuildContext context, MindState state, S t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t.trustRemoveAllAsk),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t.trustRemoveAll)),
        ],
      ),
    );
    if (ok == true) state.untrustHands(null);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final state = context.watch<MindState>();
    final items = state.handsTrust.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.trustIntro, style: const TextStyle(fontSize: 11, height: 1.45, color: MindColors.ink55)),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text(t.trustNone, style: const TextStyle(fontSize: 11, height: 1.45, color: MindColors.ink55))
        else ...[
          for (final e in items)
            Row(
              children: [
                if (PhoneStepKind.parse(e.key.split('|').last).risky)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB46A00)),
                  ),
                Expanded(
                  child: Text(
                    '${e.value} · ${t.handsKindLabel(PhoneStepKind.parse(e.key.split('|').last))}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                TextButton(onPressed: () => state.untrustHands(e.key), child: Text(t.trustRemove)),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(onPressed: () => _removeAll(context, state, t), child: Text(t.trustRemoveAll)),
          ),
        ],
      ],
    );
  }
}
