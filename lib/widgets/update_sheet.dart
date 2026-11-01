import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../theme/tokens.dart';
import '../update/updater.dart';

/// กล่องที่เด้งเองเมื่อมีรุ่นใหม่ · เด้งเมื่อไหร่ดูที่ UpdatePrompt
///
/// ใช้ [Updater] ตัวเดียวกับการ์ดในหน้าตั้งค่า · ปิดกล่องกลางการโหลด = โหลดต่อ
/// แล้วเปิดหน้าติดตั้งให้เองเมื่อเสร็จ ความคืบหน้ายังดูได้ที่การ์ด
/// · ไม่โหลดเองเด็ดขาด ต้องกด "อัปเดตเลย" ก่อน
class UpdateSheet extends StatefulWidget {
  const UpdateSheet({super.key, required this.info, required this.mode});

  final UpdateInfo info;
  final MindMode mode;

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  /// กดซ้ำ = pop สองครั้ง ซึ่งจะปิดจอที่อยู่ใต้กล่องไปด้วย
  bool _closed = false;

  /// กดอัปเดตจากกล่องนี้แล้ว · สถานะ ready ที่ค้างมาจากรอบก่อน (เคยกดยกเลิก
  /// ที่หน้าติดตั้ง) ต้องไม่ทำให้กล่องปิดตัวเองทันทีที่เปิด
  bool _tapped = false;

  /// คืน true = กดอัปเดตไปแล้ว · false / null (ปัดลง) = ไว้ทีหลัง
  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.pop(context, _tapped);
  }

  void _install(Updater up) {
    _tapped = true;
    up.downloadAndInstall();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final up = context.watch<Updater>();
    final info = up.pending ?? widget.info;
    final mode = widget.mode;
    final busy = up.stage == UpdateStage.downloading ||
        up.stage == UpdateStage.verifying;

    // หน้าติดตั้งของระบบขึ้นแล้ว · กล่องนี้หมดหน้าที่
    if (_tapped && up.stage == UpdateStage.ready && !_closed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
    }

    final installLabel = up.stage == UpdateStage.ready
        ? t.updateInstallNow
        : t.updateNow(info.sizeBytes > 0 ? info.sizeLabel : null);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Row(
              spacing: 12,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: mode.gradient,
                    borderRadius: BorderRadius.circular(MindRadius.control),
                  ),
                  child: const Icon(Icons.system_update_rounded,
                      color: Colors.white, size: 22),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(t.updateAvailable(info.version),
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                      if (up.currentVersion.isNotEmpty)
                        Text(t.updateYouHave(up.currentVersion),
                            style: const TextStyle(
                                fontSize: 11.5, color: MindColors.ink55)),
                    ],
                  ),
                ),
              ],
            ),
            if (info.notes.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                decoration: BoxDecoration(
                  color: MindColors.glass85,
                  borderRadius: BorderRadius.circular(MindRadius.message),
                  border: Border.all(color: MindColors.glassBorder, width: 1),
                ),
                child: SingleChildScrollView(
                  child: Text(info.notes,
                      style: const TextStyle(fontSize: 12, height: 1.6)),
                ),
              ),
            if (busy) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(MindRadius.pill),
                child: LinearProgressIndicator(
                  value: up.stage == UpdateStage.verifying ? null : up.progress,
                  minHeight: 5,
                  backgroundColor: MindColors.ink10,
                  valueColor: AlwaysStoppedAnimation(mode.accent),
                ),
              ),
              Text(
                up.stage == UpdateStage.verifying
                    ? t.updateVerifying
                    : t.updateProgress(
                        up.progressLabel, (up.progress * 100).round()),
                style: const TextStyle(fontSize: 11, color: MindColors.ink55),
              ),
            ],
            if (up.error != null)
              Text(up.error!,
                  style: const TextStyle(
                      fontSize: 11.5, height: 1.5, color: Color(0xFFB46A00))),
            Text('${t.updateClosesNote} · ${t.updateSource}',
                style: const TextStyle(
                    fontSize: 10.5, height: 1.5, color: MindColors.ink55)),
            const SizedBox(height: 2),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _close,
                    child: Text(busy ? t.updateHide : t.updateLater,
                        textAlign: TextAlign.center),
                  ),
                ),
                if (!busy)
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                          backgroundColor: mode.accent),
                      onPressed: () => _install(up),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(installLabel, textAlign: TextAlign.center),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
