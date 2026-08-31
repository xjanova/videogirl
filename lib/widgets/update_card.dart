import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../update/updater.dart';
import 'glass.dart';

/// การ์ดอัปเดตในหน้าตั้งค่า
///
/// เช็คให้เองตอนเปิดหน้า แต่**ไม่**โหลดหรือติดตั้งเองเด็ดขาด
/// การเปลี่ยนแอปในเครื่องผู้ใช้ต้องให้เขากดเองเสมอ
class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key, required this.mode});

  final MindMode mode;

  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  bool _checkedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkedOnce) return;
    _checkedOnce = true;
    // เช็คเงียบ ๆ ครั้งเดียวตอนเข้าหน้านี้ ไม่ยิงทุกครั้งที่ rebuild
    context.read<Updater>().check();
  }

  @override
  Widget build(BuildContext context) {
    final up = context.watch<Updater>();
    final mode = widget.mode;

    return GlassPanel(
      radius: MindRadius.card,
      fill: MindColors.glass62,
      filter: MindGlass.light,
      shadows: MindShadows.card(),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(S.of(context).sectionUpdate,
              style: mindMono(size: 10, color: mode.accent, letterSpacing: .1)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _status(up, S.of(context))),
              if (up.stage == UpdateStage.checking)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (up.stage != UpdateStage.downloading &&
                  up.stage != UpdateStage.verifying)
                GestureDetector(
                  onTap: up.check,
                  child: Text(S.of(context).updateRecheck,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: mode.accent)),
                ),
            ],
          ),
          if (up.stage == UpdateStage.downloading ||
              up.stage == UpdateStage.verifying) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(MindRadius.pill),
              child: LinearProgressIndicator(
                value: up.stage == UpdateStage.verifying ? null : up.progress,
                minHeight: 5,
                backgroundColor: MindColors.ink10,
                valueColor: AlwaysStoppedAnimation(mode.accent),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              up.stage == UpdateStage.verifying
                  ? S.of(context).updateVerifying
                  : S.of(context).updateProgress(
                      up.progressLabel, (up.progress * 100).round()),
              style: const TextStyle(fontSize: 10.5, color: MindColors.ink55),
            ),
          ],
          if (up.stage == UpdateStage.available && up.pending != null) ...[
            const SizedBox(height: 12),
            _releaseNotes(up.pending!),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: up.downloadAndInstall,
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: mode.gradient,
                  borderRadius: BorderRadius.circular(MindRadius.control),
                  boxShadow: [
                    BoxShadow(
                        color: mode.accentSoft,
                        blurRadius: 20,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: Text(S.of(context).updateInstall(up.pending!.sizeLabel),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ),
          ],
          if (up.error != null) ...[
            const SizedBox(height: 10),
            Text(up.error!,
                style: const TextStyle(
                    fontSize: 11, height: 1.5, color: Color(0xFFB46A00))),
          ],
        ],
      ),
    );
  }

  Widget _status(Updater up, S t) {
    final current = up.currentVersion.isEmpty ? '—' : up.currentVersion;
    final text = switch (up.stage) {
      UpdateStage.checking => t.updateChecking,
      UpdateStage.available => t.updateAvailable('${up.pending?.version}'),
      UpdateStage.ready => t.updateReady,
      _ => t.updateCurrent(current),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 3,
      children: [
        Text(text,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        Text(t.updateSource,
            style: const TextStyle(fontSize: 10.5, color: MindColors.ink55)),
      ],
    );
  }

  Widget _releaseNotes(UpdateInfo info) {
    if (info.notes.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: MindColors.glass85,
        borderRadius: BorderRadius.circular(MindRadius.message),
        border: Border.all(color: MindColors.glassBorder, width: 1),
      ),
      child: Text(
        info.notes,
        maxLines: 8,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5, height: 1.6),
      ),
    );
  }
}
