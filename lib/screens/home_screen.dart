import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../avatar/avatar_pack.dart';
import '../avatar/avatar_view.dart';
import '../state/mind_state.dart';
import '../theme/app_theme.dart';
import '../i18n/enum_labels.dart';
import '../i18n/strings.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';

/// หน้าหลัก — artboard 2a
/// อวาตาร์อยู่ในแสงสี แชทเป็นแผ่นกระจกเหลวลอยทับ
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.avatar});

  final MindAvatarController avatar;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final _draft = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _ring;

  @override
  void initState() {
    super.initState();
    // liqRing — วงแหวนขยายออกแล้วจางหาย 3 วินาทีต่อรอบ
    _ring = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }

  @override
  void dispose() {
    _draft.dispose();
    _focus.dispose();
    _ring.dispose();
    super.dispose();
  }

  Future<void> _send(MindState state) async {
    final text = _draft.text;
    if (text.trim().isEmpty) return;
    _draft.clear();

    // เธอหันมาใกล้ ๆ ตอนคุย แล้วถอยกลับเป็นเต็มตัวเมื่อจบ
    await widget.avatar.setFraming(MindFraming.bust);
    await widget.avatar.setMood(MindMood.thinking);

    await state.send(text);
    if (!mounted) return;

    await widget.avatar.setMood(state.mode.isWork ? MindMood.pleased : MindMood.happy);
    if (!mounted) return;
    await widget.avatar.setFraming(MindFraming.full);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MindState>();
    final mode = state.mode;

    return LiquidBackground(
      gradient: MindGradients.home,
      orbs: Orb.home,
      child: SafeArea(
        child: Column(
          children: [
            _header(state, mode),
            Expanded(child: _stage(state, mode)),
            _chatDock(state, mode),
          ],
        ),
      ),
    );
  }

  // ── หัวจอ ───────────────────────────────────────────────
  Widget _header(MindState state, MindMode mode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        spacing: 10,
        children: [
          Text('MIND', style: mindMono(size: 11, weight: FontWeight.w600, color: mode.accent, letterSpacing: .16)),
          Expanded(
            child: Text(
              mode.statusOf(S.of(context)),
              style: const TextStyle(fontSize: 11, color: MindColors.ink55),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ModeToggle(mode: mode, onToggle: state.toggleMode),
        ],
      ),
    );
  }

  // ── เวทีของเธอ ──────────────────────────────────────────
  //
  // artboard วาดบนกรอบ 380×800 ตายตัว ถ้าเอาพิกัดพิกเซลจากตรงนั้นมาใช้ตรง ๆ
  // บนจอจริง (ทดสอบบน 1080×2340) ฟองคำพูดจะไปคร่อมหน้าเธอ และวงแหวนจะหลุดตำแหน่ง
  // จึงเก็บเป็น **สัดส่วน** ของเวที แล้วคูณกลับตามขนาดจริงของแต่ละเครื่อง
  static const _artboardStage = Size(380, 452); // 800 − หัวจอ − แผงแชท

  static const _ringLeft = 92 / 380;
  static const _ringTop = 44 / 452;
  static const _ringSize = 136 / 380;
  static const _bubbleLeft = 112 / 380;
  static const _bubbleTop = 14 / 452;
  static const _bubbleMaxWidth = 210 / 380;

  Widget _stage(MindState state, MindMode mode) {
    final bubble = state.bubbleText;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: _artboardStage.height * .66),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final h = box.maxHeight.isFinite ? box.maxHeight : _artboardStage.height;
          final ring = w * _ringSize;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // แตะที่ตัวเธอเพื่อเรียกฟองที่จางไปแล้วกลับมาอ่านซ้ำ
              // ไม่งั้นข้อความที่พลาดไปจะอ่านได้แค่ในแผงแชทข้างล่างเท่านั้น
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: state.showBubbleAgain,
                  child: MindAvatarView(
                    controller: widget.avatar,
                    mode: mode,
                    packBase: context.watch<AvatarPack>().baseUrl,
                  ),
                ),
              ),

              // วงแหวนเรืองรอบตัวเธอ ขยายออกแล้วจาง
              Positioned(
                left: w * _ringLeft,
                top: h * _ringTop,
                child: AnimatedBuilder(
                  animation: _ring,
                  builder: (_, _) {
                    final t = _ring.value;
                    return Opacity(
                      opacity: (.5 * (1 - t)).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 1 + .6 * t,
                        child: Container(
                          width: ring,
                          height: ring,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: mode.accentSoft, width: 1.5),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // ปุ่มเชิดหุ่น — อยู่บนเวทีไม่ใช่ในหน้าตั้งค่า เพราะเป็นสวิตช์
              // ที่คนกดขณะ**มองหน้าเธออยู่** ไม่ใช่ค่าที่ตั้งทิ้งไว้
              Positioned(
                right: 10,
                top: 10,
                child: _PuppetButton(avatar: widget.avatar, mode: mode),
              ),

              // แถบบอกสถานะกล้อง — ขึ้นเฉพาะตอนมีอะไรต้องบอกจริง ๆ
              Positioned(
                left: 12,
                right: 12,
                bottom: 8,
                child: _PuppetStatus(avatar: widget.avatar),
              ),

              // ฟองคำพูด — ซ่อนถ้ายังไม่ได้พูดอะไร (ฟองเปล่าดูเสีย)
              // และซ่อนระหว่างที่เธอกำลังพูด เพราะกล้องดึงเข้าเป็น bust
              // ฟองจะไปคร่อมหน้าเธอพอดี ข้อความเดียวกันอยู่ในแผงแชทอยู่แล้ว
              if (bubble.isNotEmpty)
                Positioned(
                  left: w * _bubbleLeft,
                  top: h * _bubbleTop,
                  // IgnorePointer ตอนจาง ไม่งั้นฟองที่มองไม่เห็นยังกินการแตะอยู่
                  // แล้วแตะตัวเธอเพื่อเรียกฟองกลับจะไม่ทำงานในบริเวณนั้น
                  child: IgnorePointer(
                    ignoring: !state.bubbleVisible,
                    child: AnimatedOpacity(
                      opacity: state.bubbleVisible ? 1 : 0,
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOut,
                      child: SpeechBubble(
                        text: bubble,
                        maxWidth: w * _bubbleMaxWidth,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── แผงแชทกระจกล่างสุด ──────────────────────────────────
  Widget _chatDock(MindState state, MindMode mode) {
    return GlassPanel(
      margin: const EdgeInsets.fromLTRB(MindSpace.screenX, 0, MindSpace.screenX, MindSpace.screenX),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      filter: MindGlass.heavy,
      shadows: MindShadows.dock(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MindSpace.gap,
        children: [
          for (final m in state.messages) _message(m, mode),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final label in mode.chipsOf(S.of(context)))
                GlassChip(label: label, onTap: () => state.send(label)),
            ],
          ),
          _composer(state, mode),
        ],
      ),
    );
  }

  Widget _message(ChatMessage m, MindMode mode) {
    return Align(
      alignment: m.fromHer ? Alignment.centerLeft : Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: null,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .86 - 44),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: m.fromHer ? mode.bubbleGradient : null,
              color: m.fromHer ? null : MindColors.glass85,
              borderRadius: BorderRadius.circular(MindRadius.message),
              border: Border.all(
                color: m.fromHer ? const Color(0x80FFFFFF) : MindColors.glassBorder,
                width: 1,
              ),
              boxShadow: MindShadows.soft(),
            ),
            child: Text(
              m.text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: m.fromHer ? Colors.white : MindColors.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _composer(MindState state, MindMode mode) {
    return Row(
      spacing: 7,
      children: [
        // ไมค์
        GestureDetector(
          onTap: state.toggleMic,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: state.mic ? const Color(0x33FF5C8A) : MindColors.glass80,
              borderRadius: BorderRadius.circular(MindRadius.control),
              border: Border.all(
                color: state.mic ? const Color(0x66FF5C8A) : MindColors.glassBorder,
                width: 1,
              ),
            ),
            child: Icon(
              state.mic ? Icons.mic_rounded : Icons.mic_none_rounded,
              size: 18,
              color: state.mic ? const Color(0xFFFF5C8A) : MindColors.ink60,
            ),
          ),
        ),

        Expanded(
          child: SizedBox(
            height: 38,
            child: TextField(
              controller: _draft,
              focusNode: _focus,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(state),
              style: const TextStyle(fontSize: 12.5, color: MindColors.ink),
              decoration: InputDecoration(
                isDense: true,
                hintText: S.of(context).composerHint,
                hintStyle: const TextStyle(fontSize: 12.5, color: MindColors.ink45),
                filled: true,
                fillColor: MindColors.glass80,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MindRadius.control),
                  borderSide: const BorderSide(color: Color(0xF2FFFFFF), width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MindRadius.control),
                  borderSide: const BorderSide(color: Color(0xF2FFFFFF), width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MindRadius.control),
                  borderSide: BorderSide(color: mode.accentSoft, width: 1),
                ),
              ),
            ),
          ),
        ),

        // ปุ่มส่ง — จางลงตอนกำลังส่งอยู่ กันกดซ้ำ
        Opacity(
          opacity: state.sending ? .5 : 1,
          child: GestureDetector(
            onTap: state.sending ? null : () => _send(state),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: mode.gradient,
                borderRadius: BorderRadius.circular(MindRadius.control),
                boxShadow: [
                  BoxShadow(color: mode.accentSoft, blurRadius: 18, offset: const Offset(0, 6)),
                ],
              ),
              child: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// ปุ่มกลม ๆ เปิด/ปิดโหมดหุ่นเชิด
///
/// เปลี่ยนสีตามสถานะจริงสามขั้น ไม่ใช่แค่ เปิด/ปิด: กำลังคาลิเบรตกับเชิดอยู่จริง
/// เป็นคนละเรื่องกัน คนกดต้องแยกออกว่าตอนนี้ต้อง**นิ่ง**หรือ**ขยับได้แล้ว**
class _PuppetButton extends StatefulWidget {
  const _PuppetButton({required this.avatar, required this.mode});

  final MindAvatarController avatar;
  final MindMode mode;

  @override
  State<_PuppetButton> createState() => _PuppetButtonState();
}

class _PuppetButtonState extends State<_PuppetButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    // startMocap เองก็กันซ้ำอยู่แล้ว แต่ระหว่างรอไดอะล็อกสิทธิ์ของระบบ
    // ปุ่มยังกดได้อยู่ ถ้าไม่กันตรงนี้จะได้ไดอะล็อกซ้อนกันสองอัน
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (widget.avatar.mocapOn) {
        await widget.avatar.stopMocap();
      } else {
        await widget.avatar.startMocap();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ListenableBuilder(
      listenable: widget.avatar,
      builder: (context, _) {
        final a = widget.avatar;
        final live = a.mocapPhase == MindMocapPhase.live;
        final warming = a.mocapPhase == MindMocapPhase.starting ||
            a.mocapPhase == MindMocapPhase.calibrating;

        final tint = live
            ? widget.mode.accent
            : warming
                ? MindColors.ink55
                : MindColors.ink45;

        return Semantics(
          button: true,
          toggled: a.mocapOn,
          label: a.mocapOn ? s.puppetStop : s.puppetStart,
          child: Tooltip(
            message: live
                ? '${s.puppetStop} · ${s.puppetRecalibrate}'
                : a.mocapOn
                    ? s.puppetStop
                    : s.puppetStart,
            child: GestureDetector(
              onTap: a.ready ? _toggle : null,
              // กดค้าง = จำหน้าใหม่ · ไม่ทำเป็นปุ่มแยกเพราะเป็นของที่ใช้นาน ๆ ครั้ง
              // (เปลี่ยนคนเชิด ย้ายที่นั่ง แสงเปลี่ยน) แต่ตอนต้องใช้ก็ต้องหาเจอ
              onLongPress: live ? widget.avatar.recalibrateMocap : null,
              child: GlassPanel(
                radius: 22,
                fill: MindColors.glass72,
                padding: const EdgeInsets.all(9),
                shadows: MindShadows.soft(),
                child: Icon(
                  live
                      ? Icons.videocam_rounded
                      : warming
                          ? Icons.hourglass_top_rounded
                          : Icons.videocam_off_rounded,
                  size: 20,
                  color: a.ready ? tint : MindColors.ink22,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// แถบบอกสถานะกล้อง
///
/// เงียบสนิทตอนทุกอย่างปกติ — แถบที่ขึ้นตลอดเวลาคือแถบที่ไม่มีใครอ่าน
/// ขึ้นเฉพาะตอนที่คนต้อง**ทำอะไรสักอย่าง** หรือตอนที่ของกำลังไม่ทำงาน
class _PuppetStatus extends StatelessWidget {
  const _PuppetStatus({required this.avatar});

  final MindAvatarController avatar;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ListenableBuilder(
      listenable: avatar,
      builder: (context, _) {
        final (text, progress, action) = _read(s);
        if (text == null) return const SizedBox.shrink();

        return GlassPanel(
          radius: 18,
          fill: MindColors.glass80,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          shadows: MindShadows.soft(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: MindColors.ink75),
              ),
              // คำสัญญาเรื่องกล้องต้องอยู่**ตรงจุดที่กล้องกำลังเปิด** ไม่ใช่
              // ซ่อนในหน้า privacy ที่ไม่มีใครกดเข้าไปอ่าน
              if (avatar.mocapOn)
                Text(
                  s.puppetPrivacy,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: MindColors.ink45),
                ),
              if (progress != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: MindColors.ink10,
                  ),
                ),
              if (action != null)
                Align(
                  alignment: Alignment.center,
                  child: TextButton(
                    onPressed: action.$2,
                    child: Text(action.$1),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// ข้อความ · ความคืบหน้า · ปุ่มลงมือ — null ทั้งชุดแปลว่าไม่ต้องขึ้นอะไรเลย
  (String?, double?, (String, VoidCallback)?) _read(S s) {
    if (avatar.mocapBlocked) {
      return (s.puppetBlocked, null, (s.openSettings, avatar.openCameraSettings));
    }
    if (avatar.mocapDenied) return (s.puppetDenied, null, null);

    switch (avatar.mocapPhase) {
      case MindMocapPhase.off:
        return (null, null, null);
      case MindMocapPhase.starting:
        return (s.puppetStarting, null, null);
      case MindMocapPhase.calibrating:
        // ไม่เห็นหน้า = หลอดจะไม่ขยับเลย ต้องบอกให้รู้ว่าติดตรงไหน ไม่ใช่ปล่อยให้
        // นั่งนิ่งรอ 0% ไปเรื่อย ๆ โดยเข้าใจว่าเครื่องกำลังคิดอยู่
        if (!avatar.mocapTracking) {
          return (s.puppetNoFace, avatar.mocapProgress, null);
        }
        return (s.puppetCalibrating, avatar.mocapProgress, null);
      case MindMocapPhase.failed:
        return (s.puppetFailed, null, null);
      case MindMocapPhase.live:
        // เชิดอยู่แล้วและเห็นหน้าอยู่ = ไม่ต้องบอกอะไร ปุ่มมุมบนบอกไปแล้ว
        if (avatar.mocapTracking) return (null, null, null);
        return (s.puppetNoFace, null, null);
    }
  }
}
