import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../i18n/strings_knowledge.dart';
import '../state/mind_state.dart';
import '../store/knowledge_pack.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';
import '../widgets/screen_header.dart';

/// อ่านแพ็กความรู้ที่ติดตั้งไว้ · หัวข้อในภาษาของแอป พร้อมรูปประกอบ · อ่านได้ตอนออฟไลน์
///
/// ซื้อแล้วต้องเปิดอ่านเองได้ ไม่ใช่รู้แค่ว่า "มายด์รู้เรื่องนี้" · เข้าป่าไม่มีเน็ต หน้านี้คือคู่มือ
class KnowledgeReaderScreen extends StatefulWidget {
  const KnowledgeReaderScreen({super.key, required this.packId, this.onAsk});

  final String packId;

  /// "ถามมายด์เรื่องนี้" ใต้หัวข้อ · null (เปิดจากหน้าตั้งค่า) = ไม่มีปุ่ม
  final ValueChanged<String>? onAsk;

  @override
  State<KnowledgeReaderScreen> createState() => _KnowledgeReaderScreenState();
}

class _KnowledgeReaderScreenState extends State<KnowledgeReaderScreen> {
  late final Future<Map<String, File>> _images =
      context.read<MindState>().knowledgePacks.imagesOf(widget.packId).catchError((Object e) {
    // ที่เก็บอ่านไม่ได้ = อ่านแต่ตัวหนังสือ ดีกว่าหน้าพัง
    debugPrint('อ่านแพ็ก: หารูปไม่ได้ — ${e.runtimeType}');
    return const <String, File>{};
  });

  static final _bullet = RegExp(r'^[-*]\s+');

  /// กดถามแล้ว = หน้ากำลังปิด · กดซ้ำระหว่างหน้าเลื่อนออกต้องไม่ส่งคำถามซ้ำ
  var _asked = false;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final mode = context.select<MindState, MindMode>((s) => s.mode);
    final kp = context.read<MindState>().knowledgePacks;

    return Scaffold(
      body: LiquidBackground(
        gradient: MindGradients.settings,
        orbs: Orb.settings,
        child: SafeArea(
          child: ListenableBuilder(
            // ลบแพ็กจากที่อื่นระหว่างอ่าน = หน้านี้ต้องรู้ ไม่ใช่โชว์ของที่ไม่มีแล้ว
            listenable: kp,
            builder: (context, _) {
              final pack = kp.byId(widget.packId);
              final close = MindIconButton(
                icon: Icons.close_rounded,
                tooltip: t.cancel,
                mode: mode,
                onTap: () => Navigator.of(context).maybePop(),
              );
              if (pack == null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MindScreenHeader(overline: t.shopTabKnowledge, title: t.kpGone, trailing: close),
                  ],
                );
              }
              final m = pack.manifest;
              final sections = pack.sectionsFor(t.isThai);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MindScreenHeader(
                    overline: t.kpCategory(m.category),
                    title: m.name.of(t.isThai),
                    subtitle: t.kpTopics(sections.length, m.version),
                    trailing: close,
                  ),
                  Expanded(
                    child: FutureBuilder<Map<String, File>>(
                      future: _images,
                      builder: (context, snap) {
                        final images = snap.data ?? const <String, File>{};
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(MindSpace.lg, 0, MindSpace.lg, MindSpace.xxl),
                          children: [
                            if (m.category == PackCategory.trading) ...[
                              Text(t.kpTradingNote, style: MindType.caption),
                              const SizedBox(height: MindSpace.md),
                            ],
                            for (final s in sections) ...[
                              _section(context, t, s, images),
                              const SizedBox(height: MindSpace.md),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, S t, PackSection s, Map<String, File> images) {
    final ask = widget.onAsk;
    return GlassPanel(
      radius: MindRadius.card,
      fill: MindColors.glass62,
      shadows: MindShadows.card(),
      padding: const EdgeInsets.all(MindSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.title, style: MindType.title),
          const SizedBox(height: MindSpace.sm),
          ..._body(s.text, images),
          if (ask != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                label: Text(t.kpAskAbout),
                onPressed: () {
                  if (_asked) return;
                  _asked = true;
                  Navigator.of(context).maybePop();
                  ask(s.title);
                },
              ),
            ),
        ],
      ),
    );
  }

  /// markdown แบบเรียบ: ย่อหน้า · รายการ (-, *) · รูปที่อยู่บรรทัดเดียวของมันเอง ·
  /// รูปกลางประโยคเหลือแค่คำบรรยาย · รูปที่ไม่มีในแพ็ก = ไม่แสดง
  List<Widget> _body(String text, Map<String, File> images) {
    final out = <Widget>[];
    final para = <String>[];
    void flush() {
      if (para.isEmpty) return;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: MindSpace.sm),
        child: Text(para.join('\n'), style: MindType.body),
      ));
      para.clear();
    }

    for (final raw in text.split('\n')) {
      final line = raw.trim();
      final img = KnowledgePacks.imageMarkdown.firstMatch(line);
      if (img != null && img.start == 0 && img.end == line.length) {
        flush();
        final ref = KnowledgePacks.imageRef(img.group(2)!);
        final file = ref == null ? null : images[ref];
        if (file != null) out.add(_image(file, img.group(1)!.trim()));
        continue;
      }
      if (line.isEmpty) {
        flush();
        continue;
      }
      para.add(KnowledgePacks.plain(line).replaceFirst(_bullet, '• '));
    }
    flush();
    return out;
  }

  Widget _image(File file, String alt) => Padding(
        padding: const EdgeInsets.only(bottom: MindSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(MindRadius.card / 2),
              child: Image.file(
                file,
                fit: BoxFit.contain,
                // ถอดรหัสที่ความกว้างจอ ไม่ใช่ขนาดเต็มของไฟล์ · หน่วยความจำต่อรูปคงที่
                cacheWidth: 1080,
                semanticLabel: alt.isEmpty ? null : alt,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            if (alt.isNotEmpty) ...[
              const SizedBox(height: MindSpace.xs),
              Text(alt, style: MindType.caption.copyWith(fontSize: 11)),
            ],
          ],
        ),
      );
}
