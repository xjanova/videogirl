import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';

/// หน้าแก้ไขข้อความยาว — ใช้กับ "ข้อมูลเกี่ยวกับเรา" และ "ขอบเขตการตอบ"
///
/// แยกเป็นหน้าเต็มจอเพราะสองอย่างนี้ยาวเป็นสิบบรรทัด ยัดลงการ์ดเล็ก ๆ
/// แล้วผู้ใช้จะแก้ไม่ไหว และมองไม่เห็นว่าเธอรู้อะไรเกี่ยวกับเราบ้าง
class TextEditorScreen extends StatefulWidget {
  const TextEditorScreen({
    super.key,
    required this.title,
    required this.hint,
    required this.initial,
    required this.mode,
    required this.onReset,
  });

  final String title;

  /// อธิบายว่าข้อความนี้เอาไปใช้ทำอะไร ผู้ใช้จะได้เขียนได้ตรงจุด
  final String hint;

  final String initial;
  final MindMode mode;

  /// คืนค่าตั้งต้นของโรงงาน
  final String Function() onReset;

  @override
  State<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  late final TextEditingController _text;
  late String _saved;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initial);
    _saved = widget.initial;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _dirty => _text.text != _saved;

  Future<void> _confirmDiscard() async {
    if (!_dirty) {
      Navigator.of(context).pop<String?>(null);
      return;
    }

    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(context).discardTitle),
        content: Text(S.of(context).discardBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.of(context).keepTyping)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.of(context).discard,
                style: const TextStyle(color: Color(0xFFE0357A))),
          ),
        ],
      ),
    );

    if (leave == true && mounted) Navigator.of(context).pop<String?>(null);
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(context).resetTitle),
        content: Text(S.of(context).resetBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(S.of(context).cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.of(context).reset,
                style: const TextStyle(color: Color(0xFFE0357A))),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      setState(() => _text.text = widget.onReset());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        body: LiquidBackground(
          gradient: MindGradients.settings,
          orbs: Orb.settings,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _confirmDiscard,
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: MindColors.ink),
                      ),
                      Expanded(
                        child: Text(widget.title,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                      TextButton(
                        onPressed: _reset,
                        child: Text(S.of(context).resetToDefault,
                            style: const TextStyle(
                                fontSize: 12, color: MindColors.ink60)),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(widget.hint,
                      style: const TextStyle(
                          fontSize: 11.5, height: 1.6, color: MindColors.ink55)),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: GlassPanel(
                      radius: MindRadius.card,
                      fill: MindColors.glass72,
                      filter: MindGlass.light,
                      shadows: MindShadows.card(),
                      padding: const EdgeInsets.all(14),
                      child: TextField(
                        controller: _text,
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        style: const TextStyle(
                            fontSize: 12.5, height: 1.7, color: MindColors.ink),
                        decoration: InputDecoration.collapsed(
                          hintText: S.of(context).typeHere,
                          hintStyle: const TextStyle(color: MindColors.ink45),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: GestureDetector(
                    onTap: () {
                      _saved = _text.text;
                      Navigator.of(context).pop<String?>(_text.text);
                    },
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: widget.mode.gradient,
                        borderRadius: BorderRadius.circular(MindRadius.message),
                        boxShadow: [
                          BoxShadow(
                              color: widget.mode.accentSoft,
                              blurRadius: 24,
                              offset: const Offset(0, 10)),
                        ],
                      ),
                      child: Text(S.of(context).save,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
