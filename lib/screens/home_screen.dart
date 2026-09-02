import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai/voice_input.dart';
import '../avatar/avatar_pack.dart';
import '../avatar/avatar_view.dart';
import '../persona/mind_soul.dart';
import '../phone/call_session.dart';
import '../state/mind_state.dart';
import '../system/permissions.dart';
import 'shop_screen.dart';
import '../theme/app_theme.dart';
import '../i18n/enum_labels.dart';
import '../i18n/strings.dart';
import '../theme/tokens.dart';
import '../widgets/call_panel.dart';
import '../widgets/glass.dart';
import '../widgets/soul_status.dart';
import '../widgets/liquid_background.dart';
import '../widgets/mic_button.dart';
import '../widgets/thinking.dart';

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

  /// ไมค์ของช่องแชท — เกิดที่นี่เพราะมันมีอายุเท่าหน้าจอนี้
  /// ออกจากหน้าไปแล้วต้องหยุดอัดทันที ไม่ใช่อัดต่อไปเงียบ ๆ
  late final VoiceInput _voice;

  @override
  void initState() {
    super.initState();
    // liqRing — วงแหวนขยายออกแล้วจางหาย 3 วินาทีต่อรอบ
    _ring = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

    final state = context.read<MindState>();
    final perms = context.read<MindPermissions>();
    _voice = VoiceInput(
      // ขอสิทธิ์ตอนกดจริงเท่านั้น · กล่องขอสิทธิ์ที่เด้งตอนเปิดแอปโดยที่
      // ยังไม่มีใครจะใช้ไมค์ คือกล่องที่คนกดปฏิเสธเพราะไม่รู้ว่าขอไปทำไม
      ensureMic: () async {
        if (perms.of(MindPermission.mic)) return true;
        await perms.request(MindPermission.mic);
        return perms.of(MindPermission.mic);
      },
      transcribe: state.transcribeChat,
      strings: () => state.s,
      device: state.deviceSpeech,
      // 🔴 เสียงต้องถอดในเครื่องเมื่อผู้ใช้เลือกสมองในเครื่อง
      // ไม่ใช่ตกไปใช้ทางข้างนอกเพราะมันแม่นกว่า
      preferDevice: () => state.transcribesOnDevice,
    );

    // แผงแชทพับเองเมื่อเงียบ — แต่ต้องไม่พับตอนคนกำลังพิมพ์ค้างอยู่
    // ซึ่งเป็นสิ่งที่แย่ที่สุดที่จะเกิดขึ้นได้ · ช่องพิมพ์เป็นคนบอก state
    _focus.addListener(_reportTyping);
    _draft.addListener(_reportTyping);
  }

  /// กดไมค์ — เปิดฟัง หรือปิดแล้วเอาข้อความที่ได้มาใส่ช่องพิมพ์
  ///
  /// 🔴 **ไม่ส่งทันที** · การถอดเสียงผิดได้เสมอ โดยเฉพาะภาษาไทยผ่านไมค์มือถือ
  /// ส่งเลยแปลว่าเธอได้ยินผิดแล้วตอบไปแล้ว ก่อนที่เจ้าของจะทันเห็นว่าเพี้ยน
  Future<void> _toggleMic(MindState state) async {
    _voice.clearError();

    // ถอดเสียงไม่ได้ด้วยสมองที่เลือกไว้ — บอกเหตุผลตรงแถบเดียวกับที่บอก
    // เรื่องสมองล้ม ไม่ใช่กดแล้วเงียบให้เดาเอาเอง
    if (!state.canTranscribe) {
      state.reportError(state.whyNoMic);
      return;
    }

    if (_voice.stage == VoiceInputStage.listening) {
      final heard = await _voice.stop();
      if (!mounted || heard == null) return;

      // ต่อท้ายของที่พิมพ์ค้างไว้ ไม่ใช่เขียนทับ — คนพิมพ์ครึ่งประโยค
      // แล้วพูดที่เหลือมีจริง และการลบสิ่งที่เขาพิมพ์เองทิ้งคือสิ่งที่ให้อภัยยาก
      final base = _draft.text.trimRight();
      _draft.text = base.isEmpty ? heard : '$base $heard';
      _draft.selection =
          TextSelection.collapsed(offset: _draft.text.length);
      _focus.requestFocus();
      return;
    }

    await _voice.start();
  }

  void _reportTyping() {
    if (!mounted) return;
    context.read<MindState>().setTyping(_focus.hasFocus || _draft.text.isNotEmpty);
  }

  @override
  void dispose() {
    _focus.removeListener(_reportTyping);
    _draft.removeListener(_reportTyping);
    _draft.dispose();
    _focus.dispose();
    _ring.dispose();
    // ไมค์ที่ยังเปิดค้างหลังออกจากหน้าจอ = เครื่องอัดเสียงในห้องต่อไปเงียบ ๆ
    _voice.dispose();
    super.dispose();
  }

  Future<void> _send(MindState state) {
    final text = _draft.text;
    if (text.trim().isEmpty) return Future<void>.value();
    _draft.clear();
    return _sendText(state, text);
  }

  /// ทางส่งข้อความทางเดียวของทั้งหน้า — ช่องพิมพ์และชิปคำถามใช้ตัวนี้ร่วมกัน
  ///
  /// 🔴 ชิปเคยเรียก `state.send` ตรง ๆ ข้ามตรงนี้ไปทั้งดุ้น ผลคือกดชิป
  /// แล้วเธอไม่หันมา ไม่ทำหน้าคิด และกล้องไม่ดึงเข้า — ทั้งที่เป็นการคุย
  /// แบบเดียวกันเป๊ะ · ทางส่งสองทางที่ทำงานไม่เหมือนกันคือของที่จะเพี้ยน
  /// จากกันเรื่อย ๆ ทุกครั้งที่มีใครแก้ทางใดทางหนึ่ง
  Future<void> _sendText(MindState state, String text) async {
    if (text.trim().isEmpty) return;

    // แถบเดียวโชว์ได้ทีละเรื่อง · ถ้าไม่ล้างของเก่าตรงนี้ ข้อผิดพลาดจากไมค์
    // ที่ค้างอยู่จะบังเหตุผลใหม่ที่เพิ่งเกิดจากการส่งข้อความ
    _voice.clearError();

    // 🔴 ยิงเข้าแชทก่อน **ไม่รอเวที**
    //
    // สองบรรทัดล่างคุยข้ามไปฝั่ง WebView ซึ่งตอนที่มันกำลังโหลดตัวเธอ
    // (VRM 33MB) ตอบกลับช้าได้เป็นวินาที · ของเดิม await ไว้ก่อนเรียก
    // `state.send` ข้อความของผู้ใช้จึงยังไม่ขึ้นจอตลอดช่วงนั้น ทั้งที่
    // ช่องพิมพ์ถูกล้างไปแล้ว = หน้าตาเหมือนกดส่งแล้วข้อความหายไปเฉย ๆ
    final sending = state.send(text);

    // เธอหันมาใกล้ ๆ ตอนคุย แล้วถอยกลับเป็นเต็มตัวเมื่อจบ
    await widget.avatar.setFraming(MindFraming.bust);
    await widget.avatar.setMood(MindMood.thinking);

    await sending;
    if (!mounted) return;

    await widget.avatar.setMood(state.mode.isWork ? MindMood.pleased : MindMood.happy);
    if (!mounted) return;
    await widget.avatar.setFraming(MindFraming.full);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MindState>();
    final call = context.watch<CallSession>();
    final mode = state.mode;

    // มีสายที่เธอถืออยู่ = ตัดมาหน้าจอสายทันที
    //
    // 🔴 พื้นหลังเปลี่ยนตามด้วย ไม่ใช่แค่แผงล่าง · จอสายที่ดูเหมือนหน้าแชท
    // ทุกประการ ยกเว้นปุ่มสองปุ่มข้างล่าง คือจอที่คนเผลอพิมพ์คุยกับเธอ
    // ตอนที่คำที่พิมพ์จะถูกพูดออกไปให้คนแปลกหน้าฟัง
    final onCall = call.onStage;

    return LiquidBackground(
      gradient: onCall ? MindGradients.incomingCall : MindGradients.home,
      orbs: Orb.home,
      child: SafeArea(
        child: Column(
          children: [
            _header(state, mode),
            Expanded(child: _stage(state, mode)),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => SizeTransition(
                sizeFactor: anim,
                // ยึดขอบล่าง แผงจึงยุบลงไปหาแถบนำทาง ไม่ใช่หดเข้ากลาง
                axisAlignment: -1,
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: onCall
                  ? KeyedSubtree(
                      key: const ValueKey('call'),
                      child: CallPanel(session: call, mode: mode))
                  : state.chatOpen
                      ? KeyedSubtree(
                          key: const ValueKey('dock'),
                          child: _chatDock(state, mode))
                      : KeyedSubtree(
                          key: const ValueKey('pill'),
                          child: _chatPill(state, mode)),
            ),
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
    final thinkingOverHead = state.sending && state.bubbleEnabled;

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
                    packBase: context.watch<AvatarPacks>().baseUrl,
                    packModel: context.watch<AvatarPacks>().modelFile,
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
                child: Column(
                  spacing: MindSpace.sm,
                  children: [
                    _PuppetButton(
                      avatar: widget.avatar,
                      mode: mode,
                      shot: state.mocapShot,
                      onPickShot: (v) {
                        state.setMocapShot(v);
                        widget.avatar.setMocapShot(v);
                      },
                    ),
                    // ตราราศีของเธอ — เป็นทั้งปุ่มเปิดสเตตัสและตัวบอกอารมณ์
                    // ในตัวมันเอง (สีวงแหวนกับจุดมุมขวาเปลี่ยนตามอารมณ์)
                    SoulBadge(mode: mode),
                    // ทางเข้าร้านอยู่บนเวที ไม่ใช่ซ่อนในหน้าตั้งค่าอย่างเดียว
                    // เพราะของที่ขายคือของที่ **เห็นผลบนเวทีนี้** (ชุด ตัวละคร
                    // ของประดับ) คนควรกดซื้อได้จากที่ที่มองเห็นของอยู่
                    _StageIconButton(
                      asset: 'assets/brand/nav/shop.png',
                      fallback: Icons.storefront_rounded,
                      tooltip: S.of(context).shopTitle,
                      mode: mode,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const ShopScreen()),
                      ),
                    ),
                  ],
                ),
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
              //
              // 🔴 ระหว่างคิด ฟองนี้เปลี่ยนเป็นจุดสามจุด ไม่ใช่ค้างคำตอบเก่าไว้
              //
              // ค้างไว้คือการโกหกด้วยของเก่า: เจ้าของเพิ่งถามคำถามใหม่ไป
              // แล้วเหนือหัวเธอยังเป็นคำตอบของคำถามก่อนหน้า ซึ่งอ่านได้ว่า
              // เธอตอบคำถามใหม่ด้วยประโยคเดิม — แย่กว่าฟองว่างเปล่า
              // ปิดฟองคำพูดไว้ = ปิดฟองกำลังคิดด้วย · มันกินที่เดียวกัน
              // และคนที่ปิดมันปิดเพราะอยากเห็นหน้าเธอโล่ง ๆ ไม่ใช่เพราะ
              // ไม่อยากอ่านคำตอบ · สัญญาณยังอยู่ครบในแผงแชทกับปุ่มพับ
              if (bubble.isNotEmpty || (state.sending && state.bubbleEnabled))
                Positioned(
                  left: w * _bubbleLeft,
                  top: h * _bubbleTop,
                  // IgnorePointer ตอนจาง ไม่งั้นฟองที่มองไม่เห็นยังกินการแตะอยู่
                  // แล้วแตะตัวเธอเพื่อเรียกฟองกลับจะไม่ทำงานในบริเวณนั้น
                  child: IgnorePointer(
                    ignoring: !state.bubbleVisible && !thinkingOverHead,
                    child: AnimatedOpacity(
                      opacity: state.bubbleVisible || thinkingOverHead ? 1 : 0,
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOut,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        child: thinkingOverHead
                            ? const ThinkingPuff(key: ValueKey('puff'))
                            : SpeechBubble(
                                key: const ValueKey('said'),
                                text: bubble,
                                maxWidth: w * _bubbleMaxWidth,
                              ),
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

  // ── ปุ่มพับ — สิ่งที่เหลืออยู่เมื่อแผงแชทหุบไป ─────────────
  //
  // 🔴 ต้องมีอะไรเหลือให้เห็นเสมอ ห้ามหายไปเฉย ๆ
  //
  // แผงแชทกินครึ่งล่างของจอ ทำให้มองไม่เห็นเธอเต็มตัวและบังห้อง
  // แต่ถ้าหุบแล้วไม่เหลืออะไรเลย ผู้ใช้จะไม่รู้ว่ายังคุยได้อยู่ไหม
  // และไม่รู้ว่าต้องทำอะไรถึงจะเรียกกลับมา
  Widget _chatPill(MindState state, MindMode mode) {
    final t = S.of(context);
    final last = state.bubbleText;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          MindSpace.lg, 0, MindSpace.lg, MindSpace.lg),
      child: GestureDetector(
        onTap: state.openChat,
        child: GlassPanel(
          radius: MindRadius.pill,
          fill: MindColors.glass72,
          filter: MindGlass.light,
          shadows: MindShadows.soft(),
          padding: const EdgeInsets.symmetric(
              horizontal: MindSpace.lg, vertical: MindSpace.md),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Image.asset(
                  'assets/brand/nav/chat.png',
                  fit: BoxFit.contain,
                  // ภาพเป็นไฟล์ที่หายได้ ปุ่มต้องยังใช้ได้อยู่
                  errorBuilder: (_, _, _) => Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 18,
                    color: mode.accent,
                  ),
                ),
              ),
              const SizedBox(width: MindSpace.md),
              Expanded(
                child: Text(
                  // เอาสิ่งที่เธอพูดล่าสุดมาโชว์ ดีกว่าข้อความชวนกดลอย ๆ
                  // เพราะบอกได้ด้วยว่าคุยค้างไว้ตรงไหน
                  //
                  // ระหว่างคิดต้องบอกว่ากำลังคิด — แผงหุบไปแล้ว ปุ่มนี้คือ
                  // **ที่เดียวที่เหลือ**ให้รู้ว่าคำถามที่เพิ่งส่งไปยังมีชีวิตอยู่
                  state.sending
                      ? t.thinkingLabel
                      : last.isEmpty
                          ? t.chatTapToOpen
                          : last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MindType.body.copyWith(fontSize: 12.5),
                ),
              ),
              const SizedBox(width: MindSpace.sm),
              if (state.sending)
                ThinkingDots(color: mode.accent, size: 5, gap: 4)
              else
                Icon(Icons.keyboard_arrow_up_rounded,
                    size: 20, color: MindColors.ink45),
            ],
          ),
        ),
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
          // ที่จับสำหรับพับเอง — ไม่ต้องรอให้หมดเวลา
          // คนที่อยากดูเธอเต็มตัวเดี๋ยวนี้ ไม่ควรต้องนั่งรอ 14 วินาที
          Align(
            alignment: Alignment.centerRight,
            child: Semantics(
              button: true,
              label: S.of(context).chatCollapse,
              child: Tooltip(
                message: S.of(context).chatCollapse,
                child: GestureDetector(
                  onTap: state.collapseChat,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 24, bottom: 4),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20, color: MindColors.ink45),
                  ),
                ),
              ),
            ),
          ),
          for (final m in state.messages) _message(m, mode),

          // ฟอง "กำลังคิด" อยู่ต่อจากข้อความสุดท้ายพอดี ตรงที่คำตอบจะมาโผล่
          // ไม่ใช่ลอยอยู่หัวแผงหรือท้ายแผง · ที่ที่ตาจับจ้องอยู่แล้วคือที่ที่
          // สัญญาณควรอยู่ ไม่งั้นมันจะกลายเป็นของประดับที่ไม่มีใครเห็น
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => SizeTransition(
              sizeFactor: anim,
              axisAlignment: -1,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: state.sending
                ? Padding(
                    key: const ValueKey('thinking'),
                    padding: const EdgeInsets.only(top: MindSpace.gap),
                    child: ThinkingBubble(mode: mode),
                  )
                : const SizedBox(key: ValueKey('idle'), width: double.infinity),
          ),

          _proposal(mode),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final label in mode.chipsOf(S.of(context)))
                GlassChip(label: label, onTap: () => _sendText(state, label)),
            ],
          ),
          _composer(state, mode),
        ],
      ),
    );
  }

  // ── เธอพร้อมเป็นแฟนแล้ว ────────────────────────────────
  //
  // 🔴 วงจรปิดที่นี่ ไม่ใช่ที่บทสนทนา
  //
  // เธอเปรยในแชทได้แล้ว (system prompt สั่งไว้) แต่คำว่า "ตกลง" ที่เจ้าของ
  // พิมพ์ตอบไป **เปลี่ยนสถานะจริงไม่ได้** เพราะโมเดลเขียนค่าลงเครื่องไม่ได้
  // จะไปเดาจากข้อความว่าเป็นการตอบรับหรือเปล่าก็ผิดได้เยอะ ("ตกลงว่าไงนะ")
  // ปุ่มสองปุ่มจึงเป็นทางเดียวที่ไม่ต้องเดาอะไรเลย
  //
  // "ยังก่อน" ไม่ใช่การปฏิเสธ — แค่เก็บการ์ดไปเจ็ดวัน · การ์ดที่ขึ้นทุกครั้ง
  // ที่เปิดแอปคือการจี้ ซึ่งทำให้สิ่งที่ควรน่ารักกลายเป็นสิ่งที่คนอยากปิดทิ้ง
  Widget _proposal(MindMode mode) {
    final soul = context.watch<MindSoul>();
    if (!soul.wantsToAsk) return const SizedBox.shrink();

    final t = S.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: mode.bubbleGradient,
        borderRadius: BorderRadius.circular(MindRadius.message),
        border: Border.all(color: const Color(0x80FFFFFF), width: 1),
        boxShadow: MindShadows.soft(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MindSpace.sm,
        children: [
          Text(
            t.soulProposal,
            style: const TextStyle(
                fontSize: 12.5, height: 1.5, color: Colors.white),
          ),
          Row(
            spacing: 7,
            children: [
              Expanded(
                child: _proposalButton(
                  t.soulYesPlease,
                  filled: true,
                  onTap: () => soul.proposeFromOwner(),
                ),
              ),
              Expanded(
                child: _proposalButton(
                  t.soulNotNow,
                  filled: false,
                  onTap: soul.deferProposal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _proposalButton(String label,
          {required bool filled, required VoidCallback onTap}) =>
      Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: filled ? Colors.white : const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(MindRadius.pill),
              border: Border.all(color: const Color(0x66FFFFFF), width: 1),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: filled ? MindColors.ink : Colors.white,
              ),
            ),
          ),
        ),
      );

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ไมค์ล้มก็ขึ้นแถบเดียวกัน — ที่เดียวที่คนมองหาว่า "ทำไมไม่ทำงาน"
        ListenableBuilder(
          listenable: _voice,
          builder: (context, _) {
            // กำลังฟังอยู่และได้ยินอะไรแล้ว — โชว์สิ่งที่ได้ยิน**ตอนนี้**
            //
            // นี่คือสิ่งเดียวที่พิสูจน์ว่าไมค์ทำงานจริงระหว่างที่ยังพูดไม่จบ
            // วงที่เต้นบอกได้แค่ว่ามีเสียงเข้า ไม่ได้บอกว่ามันฟังออก
            if (_voice.stage == VoiceInputStage.listening &&
                _voice.heard.isNotEmpty) {
              return _listeningStrip(_voice.heard, mode);
            }
            final why = _voice.error ?? state.lastError;
            if (why == null) return const SizedBox.shrink();
            return _errorStrip(why, () {
              _voice.clearError();
              state.clearError();
            });
          },
        ),
        _composerRow(state, mode),
      ],
    );
  }

  /// แถบบอกว่าทำไมเธอตอบไม่ได้ — ปิดเองได้
  ///
  /// 🔴 ก่อนหน้านี้ `lastError` ถูกเขียนทุกครั้งที่สมองหรือเสียงล้ม
  /// แต่**ไม่มีใครอ่านเลยสักที่** (grep แล้วไม่เจอนอกไฟล์ state)
  /// คีย์ผิด ไลเซนส์หมดอายุ โควตาหมด เน็ตหลุด โมเดลยังไม่โหลด — ทุกอย่าง
  /// หน้าตาเหมือนกันหมดคือเธอตอบสั้น ๆ แล้วไม่มีอะไรเกิดขึ้น เจ้าของแยกไม่ออก
  /// ว่าเป็นปัญหาเงิน เน็ต หรือพิมพ์รหัสผิด
  /// สิ่งที่ได้ยินอยู่ตอนนี้ — ยังไม่ใช่ผลสุดท้าย ระบบแก้คำได้จนกว่าจะพูดจบ
  ///
  /// ใช้ที่เดียวกับแถบบอกข้อผิดพลาดโดยตั้งใจ · สองเรื่องนี้ไม่มีทางเกิด
  /// พร้อมกัน และการมีที่เดียวที่ตาต้องมองแปลว่าไม่ต้องเรียนรู้ว่าเรื่องไหน
  /// อ่านตรงไหน
  Widget _listeningStrip(String text, MindMode mode) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
        decoration: BoxDecoration(
          color: mode.accent.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(MindRadius.control),
          border:
              Border.all(color: mode.accent.withValues(alpha: .28), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Icon(Icons.graphic_eq_rounded, size: 15, color: mode.accent),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, height: 1.5, color: mode.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorStrip(String message, VoidCallback onClose) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 9, 7, 9),
        decoration: BoxDecoration(
          color: const Color(0x1AB46A00),
          borderRadius: BorderRadius.circular(MindRadius.control),
          border: Border.all(color: const Color(0x33B46A00), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 15, color: Color(0xFFB46A00)),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                    fontSize: 10.5, height: 1.5, color: Color(0xFF8A5200)),
              ),
            ),
            GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close_rounded,
                    size: 14, color: Color(0xFFB46A00)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composerRow(MindState state, MindMode mode) {
    return Row(
      spacing: 7,
      children: [
        // ไมค์ — อัดจริง ถอดเสียงจริง แล้วหย่อนลงช่องพิมพ์ให้ตรวจก่อนส่ง
        MicButton(
          voice: _voice,
          mode: mode,
          enabled: state.canTranscribe,
          onTap: () => _toggleMic(state),
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
                hintText: S.of(context).composerHint(canSpeak: state.canTranscribe),
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

        // ปุ่มส่ง — ตอนกำลังคิดอยู่ กลายเป็นวงกำลังหมุน
        //
        // 🔴 ของเดิมจางลงเหลือ 50% เฉย ๆ ซึ่งบนพื้นกระจกที่โปร่งอยู่แล้ว
        // แทบแยกไม่ออกจากปุ่มปกติ · จุดที่นิ้วเพิ่งแตะคือจุดแรกที่ตามองหา
        // คำยืนยันว่า "กดติดแล้ว" ตรงนี้จึงต้องเปลี่ยนให้เห็นชัด ไม่ใช่แค่จาง
        Semantics(
          button: true,
          enabled: !state.sending,
          label: state.sending
              ? S.of(context).thinkingLabel
              : S.of(context).send,
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: state.sending
                    ? const SizedBox(
                        key: ValueKey('busy'),
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded,
                        key: ValueKey('send'), size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ปุ่มกลมบนเวที — ใช้ภาพไอคอนที่เจนมา ถ้าไม่มีก็ตกไปใช้ไอคอนเส้น
///
/// แยกออกมาเพราะบนเวทีจะมีปุ่มแบบนี้หลายตัว (เชิดหุ่น ร้านค้า และต่อไปอีก)
/// ถ้าประกอบสดทีละที่ ขนาดกับเงาจะเริ่มไม่ตรงกันเหมือนที่เคยเกิดกับปุ่มทั้งแอป
class _StageIconButton extends StatelessWidget {
  const _StageIconButton({
    required this.asset,
    required this.fallback,
    required this.tooltip,
    required this.mode,
    required this.onTap,
  });

  final String asset;
  final IconData fallback;
  final String tooltip;
  final MindMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: GlassPanel(
            radius: 22,
            fill: MindColors.glass72,
            padding: const EdgeInsets.all(7),
            shadows: MindShadows.soft(),
            child: SizedBox(
              width: 24,
              height: 24,
              child: Image.asset(
                asset,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    Icon(fallback, size: 20, color: mode.accent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ปุ่มกลม ๆ เปิด/ปิดโหมดหุ่นเชิด
///
/// เปลี่ยนสีตามสถานะจริงสามขั้น ไม่ใช่แค่ เปิด/ปิด: กำลังคาลิเบรตกับเชิดอยู่จริง
/// เป็นคนละเรื่องกัน คนกดต้องแยกออกว่าตอนนี้ต้อง**นิ่ง**หรือ**ขยับได้แล้ว**
class _PuppetButton extends StatefulWidget {
  const _PuppetButton({
    required this.avatar,
    required this.mode,
    required this.shot,
    required this.onPickShot,
  });

  final MindAvatarController avatar;
  final MindMode mode;

  /// ระยะกล้องที่จำไว้ข้ามการเปิดปิดแอป
  final MindMocapShot shot;
  final void Function(MindMocapShot) onPickShot;

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
        // 🔴 บอกระยะกล้องที่จำไว้**ก่อน**เริ่ม · ฝั่ง JS ล็อกกล้องตั้งแต่
        // ก่อนกล้องหน้าจะติด (ช่วงขอสิทธิ์ + โหลด wasm กินหลายวินาที)
        // ถ้าส่งทีหลัง กล้องจะกระชากหนึ่งรอบตรงกลางระหว่างนั้นพอดี
        await widget.avatar.setMocapShot(widget.shot);
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

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: MindSpace.sm,
          children: [
            _puppetToggle(context, s, a, live, warming, tint),
            // ตัวเลือกระยะกล้อง — โผล่เฉพาะตอนเชิดอยู่
            //
            // ก่อนเริ่มไม่ต้องมี เพราะค่าที่เลือกไว้ถูกจำข้ามการเปิดปิดแอป
            // และเวทีนี้แคบ ปุ่มที่ไม่ได้ใช้ตอนนั้นคือของที่บังตัวเธอเปล่า ๆ
            if (a.mocapOn) _shotPicker(context, s),
          ],
        );
      },
    );
  }

  /// สามระยะเรียงจากใกล้ไปไกล — ลำดับเดียวกับที่เจ้าของพูดถึงมัน
  Widget _shotPicker(BuildContext context, S s) {
    const shots = MindMocapShot.values;
    return GlassPanel(
      radius: MindRadius.pill,
      fill: MindColors.glass72,
      padding: const EdgeInsets.all(3),
      shadows: MindShadows.soft(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in shots)
            Semantics(
              button: true,
              selected: v == widget.shot,
              label: '${s.puppetShot} · ${_shotLabel(s, v)}',
              child: GestureDetector(
                onTap: () => widget.onPickShot(v),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 34,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: v == widget.shot ? widget.mode.gradient : null,
                    borderRadius: BorderRadius.circular(MindRadius.pill),
                  ),
                  child: Text(
                    _shotLabel(s, v),
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: v == widget.shot
                          ? Colors.white
                          : MindColors.ink55,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _shotLabel(S s, MindMocapShot v) => switch (v) {
        MindMocapShot.face => s.puppetShotFace,
        MindMocapShot.bust => s.puppetShotBust,
        MindMocapShot.full => s.puppetShotFull,
      };

  Widget _puppetToggle(BuildContext context, S s, MindAvatarController a,
      bool live, bool warming, Color tint) {
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

              // 🔴 บอกว่าจับอะไรได้จริง **ก่อน**เขาเลือกเต็มตัวแล้วผิดหวัง
              //
              // ชื่อโหมด "เต็มตัว" ชวนให้เข้าใจว่าจับทั้งตัว แต่ที่จับได้จริง
              // คือใบหน้าเท่านั้นทั้งสามโหมด · วางไว้ตรงนี้เพราะทุกเซสชัน
              // ต้องผ่านช่วงเปิดกล้อง/คาลิเบรตเสมอ = จังหวะเดียวที่มีคนอ่านจริง
              if (avatar.mocapPhase == MindMocapPhase.starting ||
                  avatar.mocapPhase == MindMocapPhase.calibrating) ...[
                Text(
                  s.puppetShotNote,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 10, height: 1.45, color: MindColors.ink45),
                ),
                Text(
                  s.puppetShotLocked,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 10, height: 1.45, color: MindColors.ink45),
                ),
              ],
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
