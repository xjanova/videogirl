/// แผงสาย — สิ่งที่แทนที่แผงแชทตอนเธอกำลังคุยโทรศัพท์อยู่
///
/// อยู่บนหน้าหลักโดยตั้งใจ ไม่ใช่จอใหม่ที่ push ทับ เพราะ**ตัวเธออยู่ในนั้น**
/// เวทีอวาตาร์เป็น WebView ที่โหลด VRM 33MB · เปิดจอใหม่ที่มีเวทีของตัวเอง
/// คือโหลดใหม่ทั้งก้อนตอนที่สายกำลังต่ออยู่ ซึ่งทั้งช้าและกินแรมสองเท่า
/// เปลี่ยนแค่ครึ่งล่างของหน้าหลักแทน แล้วเวทีเดิมยังยืนอยู่ที่เดิม
library;

import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../phone/call_session.dart';
import '../theme/tokens.dart';
import 'glass.dart';

class CallPanel extends StatefulWidget {
  const CallPanel({super.key, required this.session, required this.mode});

  final CallSession session;
  final MindMode mode;

  @override
  State<CallPanel> createState() => _CallPanelState();
}

class _CallPanelState extends State<CallPanel> {
  final _draft = TextEditingController();

  @override
  void dispose() {
    // ตัวควบคุมช่องพิมพ์ที่ไม่ได้ปิด = ทุกสายที่รับทิ้งของค้างไว้หนึ่งชิ้น
    _draft.dispose();
    super.dispose();
  }

  Future<void> _say() async {
    final text = _draft.text.trim();
    if (text.isEmpty) return;
    _draft.clear();
    await widget.session.say(text);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final call = widget.session;
    final mode = widget.mode;

    return GlassPanel(
      margin: const EdgeInsets.fromLTRB(
          MindSpace.screenX, 0, MindSpace.screenX, MindSpace.screenX),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      filter: MindGlass.heavy,
      shadows: MindShadows.dock(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MindSpace.gap,
        children: [
          _head(t, call, mode),
          if (call.mute) _warn(t.callMuteWarn, const Color(0xFFD93A5B)),
          if (call.deaf) _warn(t.callDeaf, const Color(0xFFB07A16)),
          if (call.error != null) _warn(call.error!, const Color(0xFFD93A5B)),
          if (call.lines.isNotEmpty) _transcript(call, mode),
          // เจ้าของแทรกสายไปแล้ว = เขาคุยเอง · ช่องพิมพ์ตอนนั้นเป็นปุ่มที่
          // กดแล้วไม่มีใครได้ยิน เพราะเสียงกลับเข้าหูฟังไปแล้ว
          if (call.turn != CallTurn.handedOver) _composer(t, mode),
          _buttons(t, call, mode),
        ],
      ),
    );
  }

  // ── หัวแผง: ใครอยู่ปลายสาย และเธอกำลังทำอะไร ──────────────
  Widget _head(S t, CallSession call, MindMode mode) {
    return Row(
      spacing: MindSpace.sm,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: call.turn == CallTurn.handedOver
                ? MindColors.ink45
                : const Color(0xFF00A05A),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                call.who.isEmpty ? t.callOnAir : call.who,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MindType.body.copyWith(
                    fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              Text(
                _statusOf(t, call),
                style: const TextStyle(fontSize: 11.5, color: MindColors.ink55),
              ),
            ],
          ),
        ),
        // มาตรวัดเสียงที่ไมค์รับได้จริง
        //
        // 🔴 ไม่ใช่ของประดับ · เครื่องที่ไม่ยอมให้อัดเสียงระหว่างมีสายคืน
        // ความเงียบสนิทโดยไม่มี error อะไรเลย · แถบที่นิ่งสนิทตอนปลายสาย
        // กำลังพูดอยู่ คือคำตอบเดียวที่บอกได้ว่าเป็นที่เครื่อง ไม่ใช่ที่เธอ
        if (call.turn == CallTurn.listening) _meter(call.micLevel, mode),
      ],
    );
  }

  String _statusOf(S t, CallSession call) => switch (call.turn) {
        CallTurn.talking => t.callTalking,
        CallTurn.listening => t.callListening,
        CallTurn.thinking => t.callThinking,
        CallTurn.handedOver => t.callHandedOver,
        CallTurn.none => t.callOnAir,
      };

  Widget _meter(double level, MindMode mode) {
    // คูณหกก่อนตัดที่หนึ่ง · เสียงพูดผ่านสายวัดได้ราว 0.03–0.15 เท่านั้น
    // เอาค่าดิบมาวาดตรง ๆ แถบจะขยับไม่ถึงหนึ่งในหก แล้วดูเหมือนไมค์ตาย
    // ทั้งที่ได้ยินอยู่ ซึ่งเป็นข้อสรุปที่ผิดพอดีกับสิ่งที่แถบนี้มีไว้ตอบ
    final w = (60 * (level * 6).clamp(0.0, 1.0)).toDouble();
    return SizedBox(
      width: 60,
      height: 6,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: MindColors.glass80,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: w,
            decoration: BoxDecoration(
              gradient: mode.gradient,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _warn(String text, Color colour) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(MindRadius.control),
        border: Border.all(color: colour.withValues(alpha: .35), width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, height: 1.45, color: colour),
      ),
    );
  }

  // ── บทสนทนาสด ──────────────────────────────────────────
  //
  // สูงคงที่และเลื่อนได้ ไม่ใช่ยืดตามเนื้อหา · สายยาว ๆ จะดันปุ่มวางสาย
  // ตกจอไปจนกดไม่ได้ ซึ่งเป็นปุ่มที่ต้องกดได้ตลอดเวลาที่สุดในทั้งแอป
  Widget _transcript(CallSession call, MindMode mode) {
    final lines = call.lines;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 168),
      child: ListView.builder(
        reverse: true,
        padding: EdgeInsets.zero,
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final line = lines[lines.length - 1 - i];
          return Align(
            alignment:
                line.fromHer ? Alignment.centerLeft : Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * .74),
              decoration: BoxDecoration(
                gradient: line.fromHer ? mode.bubbleGradient : null,
                color: line.fromHer ? null : MindColors.glass85,
                borderRadius: BorderRadius.circular(MindRadius.message),
                border: Border.all(
                  color: line.fromHer
                      ? const Color(0x80FFFFFF)
                      : MindColors.glassBorder,
                  width: 1,
                ),
              ),
              child: Text(
                line.text,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.55,
                  color: line.fromHer ? Colors.white : MindColors.ink,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── พิมพ์ให้เธอพูด ──────────────────────────────────────
  //
  // อยู่ตรงนี้เสมอ ไม่ใช่โผล่มาตอนพัง · เป็นทางเดียวที่ทำงานได้แน่นอน
  // ทุกเครื่อง เพราะไม่ต้องพึ่งไมค์เลย และเป็นวิธีที่เจ้าของสั่งเธอ
  // กลางสายได้โดยไม่ต้องเปิดปากให้ปลายสายได้ยิน
  Widget _composer(S t, MindMode mode) {
    return Row(
      spacing: 7,
      children: [
        Expanded(
          child: SizedBox(
            height: 38,
            child: TextField(
              controller: _draft,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _say(),
              style: const TextStyle(fontSize: 12.5, color: MindColors.ink),
              decoration: InputDecoration(
                isDense: true,
                hintText: t.callSayHint,
                hintStyle:
                    const TextStyle(fontSize: 12.5, color: MindColors.ink45),
                filled: true,
                fillColor: MindColors.glass80,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MindRadius.control),
                  borderSide:
                      const BorderSide(color: Color(0xF2FFFFFF), width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MindRadius.control),
                  borderSide:
                      const BorderSide(color: Color(0xF2FFFFFF), width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MindRadius.control),
                  borderSide: BorderSide(color: mode.accentSoft, width: 1),
                ),
              ),
            ),
          ),
        ),
        GestureDetector(
          onTap: _say,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: mode.gradient,
              borderRadius: BorderRadius.circular(MindRadius.control),
            ),
            child: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
          ),
        ),
      ],
    );
  }

  // ── แทรกสาย / วางสาย ────────────────────────────────────
  Widget _buttons(S t, CallSession call, MindMode mode) {
    final canBarge = call.turn != CallTurn.handedOver;
    return Row(
      spacing: 8,
      children: [
        if (canBarge)
          Expanded(
            child: _pill(
              label: t.callBargeIn,
              icon: Icons.record_voice_over_rounded,
              colour: mode.accent,
              filled: false,
              onTap: call.bargeIn,
            ),
          ),
        Expanded(
          child: _pill(
            label: t.callHangUp,
            icon: Icons.call_end_rounded,
            colour: const Color(0xFFD93A5B),
            filled: true,
            onTap: call.hangUp,
          ),
        ),
      ],
    );
  }

  Widget _pill({
    required String label,
    required IconData icon,
    required Color colour,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? colour : MindColors.glass80,
            borderRadius: BorderRadius.circular(MindRadius.pill),
            border: Border.all(
              color: filled ? colour : colour.withValues(alpha: .45),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 7,
            children: [
              Icon(icon, size: 17, color: filled ? Colors.white : colour),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: filled ? Colors.white : colour,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
