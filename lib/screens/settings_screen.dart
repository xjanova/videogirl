import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai/brain_provider.dart';
import '../i18n/enum_labels.dart';
import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import '../ai/local_brain.dart';
import '../ai/mind_persona.dart';
import '../ai/openai_config.dart';
import '../ai/speech_service.dart';
import '../ai/voice_profile.dart';
import '../avatar/avatar_pack.dart';
import '../background/mind_watch.dart';
import 'shop_screen.dart';
import '../memory/mind_memory.dart';
import '../system/permissions.dart';
import '../state/mind_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';
import '../widgets/screen_header.dart';
import '../widgets/update_card.dart';
import 'text_editor_screen.dart';

/// ตั้งค่าบุคลิก — artboard 2g ขยายให้ครบของจริง
/// โหมด · ระดับการจีบ · สมอง · เสียง · ข้อมูลเกี่ยวกับเรา · ขอบเขต · รับสาย
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// ความสามารถที่เปิด/ปิดได้ — enum เก็บตัวตน ป้ายมาจากตารางแปล
enum _Feature { morningMail, sendMail, alwaysOn, bubbleOverlay }

extension _FeatureLabels on _Feature {
  String labelOf(S s) => switch (this) {
        _Feature.morningMail => s.featMorningMail,
        _Feature.sendMail => s.featSendMail,
        _Feature.alwaysOn => s.featAlwaysOn,
        _Feature.bubbleOverlay => s.featBubbleOverlay,
      };

  String hintOf(S s) => switch (this) {
        _Feature.morningMail => s.featMorningMailHint,
        _Feature.sendMail => s.featSendMailHint,
        _Feature.alwaysOn => s.featAlwaysOnHint,
        _Feature.bubbleOverlay => s.featBubbleOverlayHint,
      };
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  /// 🔴 สิทธิ์ที่ต้องไปกดในหน้าตั้งค่าของระบบ (ยกเว้นแบต, ติดตั้งแอปไม่รู้จัก)
  /// เปลี่ยนค่าตอนที่แอปเรา**ไม่ได้อยู่หน้าจอ** ถ้าไม่อ่านใหม่ตอนกลับมา
  /// การ์ดจะบอกว่ายังไม่ได้ให้ ทั้งที่เพิ่งไปกดให้มาหมาด ๆ
  /// แล้วผู้ใช้จะกดวนอยู่อย่างนั้นโดยไม่รู้ว่าจริง ๆ สำเร็จไปแล้ว
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    context.read<MindPermissions>().refresh();
    context.read<MindWatch>().refresh();
  }

  /// ช่องทางเสียงที่กำลังตั้งค่าอยู่ในการ์ด "เสียงพูด"
  VoiceChannel _voiceTab = VoiceChannel.chat;

  // สวิตช์ที่ยังไม่มีระบบหลังบ้านรองรับ เก็บไว้ในหน่วยความจำก่อน
  // TODO(permissions): ตัวที่ต้องขอสิทธิ์ Android ต้องผูกกับสถานะสิทธิ์จริง
  // ไม่ใช่ค่าที่ผู้ใช้กดเอง ไม่งั้นเปิดไว้แต่ระบบไม่ให้ = โกหกผู้ใช้
  final _switches = <_Feature, bool>{
    _Feature.morningMail: true,
    _Feature.sendMail: false,
    _Feature.alwaysOn: true,
    _Feature.bubbleOverlay: true,
  };



  @override
  Widget build(BuildContext context) {
    final state = context.watch<MindState>();
    final mode = state.mode;
    final t = S.of(context);

    return LiquidBackground(
      gradient: MindGradients.settings,
      orbs: Orb.settings,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              MindSpace.lg, 0, MindSpace.lg, MindSpace.lg),
          children: [
            // ListView มีขอบซ้ายขวาอยู่แล้ว หัวจอจึงต้องไม่ใส่ซ้ำ
            // ไม่งั้นจะเยื้องเข้าเป็นสองเท่าของอีกสามจอ
            MindScreenHeader(
              overline: t.tabSettings,
              title: t.settingsTitle,
              padding: const EdgeInsets.fromLTRB(
                  0, MindSpace.lg, 0, MindSpace.md),
            ),
            _languageCard(state, mode, t),
            const SizedBox(height: MindSpace.md),
            // วางไว้บนสุด ๆ เพราะถ้ายังไม่มีชุด ผู้ใช้จะเห็นกรอบแทนตัวเธอ
            // ตั้งแต่เปิดแอป ซึ่งเป็นคำถามแรกที่จะเกิดขึ้นในหัว
            _avatarPackCard(context, state, mode, t),
            const SizedBox(height: MindSpace.md),
            _watchCard(context, mode, t),
            const SizedBox(height: MindSpace.md),
            _permissionCard(context, mode, t),
            const SizedBox(height: MindSpace.md),
            _memoryCard(context, state, mode, t),
            const SizedBox(height: MindSpace.md),
            if (!OpenAiConfig.configured) _noKeyBanner(),
            _modeCard(state, mode),
            const SizedBox(height: MindSpace.md),
            _flirtCard(state, mode),
            const SizedBox(height: MindSpace.md),
            _bubbleCard(state, mode),
            const SizedBox(height: MindSpace.md),
            _brainCard(state, mode),
            const SizedBox(height: MindSpace.md),
            _voiceCard(state, mode),
            const SizedBox(height: MindSpace.md),
            _longTextCard(
              state: state,
              mode: mode,
              title: t.ownerProfileTitle,
              hint: t.ownerProfileHint,
              value: state.ownerProfile,
              editorHint: t.ownerProfileEditorHint,
              onSave: state.setOwnerProfile,
              onReset: () => MindPersona.defaultOwnerProfile(state.lang),
            ),
            const SizedBox(height: MindSpace.md),
            _longTextCard(
              state: state,
              mode: mode,
              title: t.boundariesTitle,
              hint: t.boundariesHint,
              value: state.boundaries,
              editorHint: t.boundariesEditorHint,
              onSave: state.setBoundaries,
              onReset: () => MindPersona.defaultBoundaries(state.lang),
            ),
            const SizedBox(height: MindSpace.md),
            _callCard(state, mode),
            const SizedBox(height: MindSpace.md),
            _switchCard(mode),
            const SizedBox(height: MindSpace.md),
            UpdateCard(mode: mode),
          ],
        ),
      ),
    );
  }

  /// สิ่งที่เธอจำได้
  ///
  /// 🔴 การ์ดนี้ไม่ใช่ของแถม — ระบบที่สะสมโปรไฟล์ของคนไว้เงียบ ๆ โดยเจ้าตัว
  /// เปิดดูไม่ได้ ไม่ใช่ผู้ช่วย · ทุกข้อที่เธอจำต้องเห็น แก้ และลบได้
  Widget _memoryCard(
      BuildContext context, MindState state, MindMode mode, S t) {
    final mem = context.watch<MindMemory>();
    final facts = mem.forPrompt(limit: 200);

    return _card(
      mode: mode,
      label: t.memTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(mem.isEmpty ? t.memEmpty : t.memCount(mem.count),
              style: MindType.title),
          const SizedBox(height: MindSpace.sm),
          Text(t.memWhy, style: MindType.caption),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: MindSpace.md),
            for (final f in facts)
              Padding(
                padding: const EdgeInsets.only(bottom: MindSpace.sm),
                child: _memoryRow(context, mem, mode, t, f),
              ),
            const SizedBox(height: MindSpace.xs),
            MindButton(
              label: t.memForgetAll,
              icon: Icons.delete_sweep_rounded,
              mode: mode,
              expand: true,
              onTap: () => _confirmForgetAll(context, mem, t),
            ),
          ],
        ],
      ),
    );
  }

  Widget _memoryRow(BuildContext context, MindMemory mem, MindMode mode, S t,
      MemoryFact f) {
    return Container(
      padding: const EdgeInsets.all(MindSpace.md),
      decoration: BoxDecoration(
        color: MindColors.glass80,
        borderRadius: BorderRadius.circular(MindRadius.control),
        border: Border.all(
          color: f.pinned
              ? mode.accent.withValues(alpha: .35)
              : MindColors.glassBorder,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.memKind(f.kind.name),
                    style: MindType.overline
                        .copyWith(fontSize: 9.5, color: mode.accent)),
                const SizedBox(height: 3),
                Text(f.text, style: MindType.body.copyWith(fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: MindSpace.sm),
          // ปักหมุด — กันไม่ให้เรื่องสำคัญโดนตัดตอนความจำเต็ม
          GestureDetector(
            onTap: () => mem.setPinned(f.id, !f.pinned),
            child: Tooltip(
              message: f.pinned ? t.memPinned : t.memPinWhy,
              child: Icon(
                f.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                size: 17,
                color: f.pinned ? mode.accent : MindColors.ink22,
              ),
            ),
          ),
          const SizedBox(width: MindSpace.md),
          GestureDetector(
            onTap: () => mem.forget(f.id),
            child: Tooltip(
              message: t.memForget,
              child: const Icon(Icons.close_rounded,
                  size: 17, color: MindColors.ink45),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmForgetAll(
      BuildContext context, MindMemory mem, S t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t.memForgetAllConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t.memForgetAll)),
        ],
      ),
    );
    if (ok == true) await mem.forgetAll();
  }

  /// สิทธิ์ทั้งหมดในที่เดียว
  ///
  /// ขอตอนจะใช้จริงฟังดูสุภาพ แต่ผลคือเจ้าของค้นพบว่ายังไม่ได้ให้สิทธิ์
  /// **ตอนที่กำลังจะใช้งานพอดี** — และบางตัวแย่กว่านั้น (ดู permInstallWhy)
  /// การ์ดนี้บอกครบว่าต้องใช้อะไร เพื่ออะไร และยังขาดตัวไหน
  Widget _permissionCard(BuildContext context, MindMode mode, S t) {
    final perms = context.watch<MindPermissions>();

    return _card(
      mode: mode,
      label: t.permTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                perms.allGranted
                    ? Icons.verified_user_rounded
                    : Icons.shield_outlined,
                size: 18,
                color: perms.allGranted ? mode.accent : MindColors.ink45,
              ),
              const SizedBox(width: MindSpace.sm),
              Expanded(
                child: Text(
                  perms.allGranted
                      ? t.permAllSet
                      : t.permMissing(perms.missing),
                  style: MindType.title,
                ),
              ),
            ],
          ),
          const SizedBox(height: MindSpace.md),
          for (final p in MindPermission.values) ...[
            _permRow(mode, t, perms, p),
            const SizedBox(height: MindSpace.sm),
          ],
          if (!perms.allGranted) ...[
            const SizedBox(height: MindSpace.xs),
            MindButton(
              label: t.permGrantAll,
              kind: MindButtonKind.primary,
              icon: Icons.done_all_rounded,
              mode: mode,
              expand: true,
              onTap: perms.busy ? null : perms.requestAllMissing,
            ),
          ],
        ],
      ),
    );
  }

  Widget _permRow(
      MindMode mode, S t, MindPermissions perms, MindPermission p) {
    final ok = perms.of(p);
    final blocked = perms.isBlocked(p);

    final (name, why) = switch (p) {
      MindPermission.camera => (t.permCamera, t.permCameraWhy),
      MindPermission.mic => (t.permMic, t.permMicWhy),
      MindPermission.notify => (t.permNotify, t.permNotifyWhy),
      MindPermission.battery => (t.permBattery, t.bgBatteryWhy),
      MindPermission.install => (t.permInstall, t.permInstallWhy),
    };

    return Container(
      padding: const EdgeInsets.all(MindSpace.md),
      decoration: BoxDecoration(
        color: ok ? mode.accent.withValues(alpha: .07) : MindColors.glass80,
        borderRadius: BorderRadius.circular(MindRadius.control),
        border: Border.all(
          color: ok ? mode.accent.withValues(alpha: .30) : MindColors.glassBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                size: 17,
                color: ok ? mode.accent : MindColors.ink22,
              ),
              const SizedBox(width: MindSpace.sm),
              Expanded(child: Text(name, style: MindType.title.copyWith(fontSize: 13.5))),
              Text(ok ? t.permOk : t.permNo,
                  style: MindType.caption.copyWith(
                      fontSize: 11,
                      color: ok ? mode.accent : MindColors.ink45)),
            ],
          ),
          const SizedBox(height: MindSpace.xs),
          Padding(
            padding: const EdgeInsets.only(left: 25),
            child: Text(why, style: MindType.caption.copyWith(fontSize: 11)),
          ),
          if (!ok) ...[
            if (blocked)
              Padding(
                padding: const EdgeInsets.only(left: 25, top: MindSpace.xs),
                child: Text(t.permBlocked,
                    style: MindType.caption
                        .copyWith(fontSize: 11, color: const Color(0xFFB46A00))),
              )
            // ตัวที่ต้องออกไปหน้าตั้งค่า บอกล่วงหน้าว่าแอปจะเด้งออกไปที่อื่น
            else if (!p.inApp)
              Padding(
                padding: const EdgeInsets.only(left: 25, top: MindSpace.xs),
                child: Text(t.permGoesToSettings,
                    style: MindType.caption.copyWith(fontSize: 10.5)),
              ),
            const SizedBox(height: MindSpace.sm),
            MindButton(
              label: t.permGrant,
              mode: mode,
              expand: true,
              onTap: perms.busy ? null : () => perms.request(p),
            ),
          ],
        ],
      ),
    );
  }

  /// ให้เธอเฝ้างานตอนแอปปิด
  ///
  /// การ์ดนี้ต้องโชว์ **เวลาที่ตื่นครั้งล่าสุด** เสมอ ไม่ใช่แค่สวิตช์เปิด/ปิด
  /// บริการเบื้องหลังบน Android ตายเงียบเป็นเรื่องปกติ ถ้ามีแต่สวิตช์
  /// ผู้ใช้จะเห็น "เปิดอยู่" ตลอดทั้งที่ตายไปตั้งแต่เมื่อวาน แล้วเชื่อผิด ๆ
  /// ว่าของมันทำงาน · ตัวเลขที่ขยับคือหลักฐานชิ้นเดียวที่มี
  Widget _watchCard(BuildContext context, MindMode mode, S t) {
    final watch = context.watch<MindWatch>();

    return _card(
      mode: mode,
      label: t.bgTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  watch.on ? t.bgWatching : t.bgNeverRan,
                  style: MindType.title,
                ),
              ),
              Switch(
                value: watch.on,
                onChanged: watch.busy
                    ? null
                    : (v) => v ? watch.start() : watch.stop(),
              ),
            ],
          ),
          const SizedBox(height: MindSpace.sm),
          Text(t.bgWhy, style: MindType.caption),

          if (watch.on) ...[
            const SizedBox(height: MindSpace.md),
            Row(
              children: [
                Icon(Icons.favorite_rounded, size: 15, color: mode.accent),
                const SizedBox(width: MindSpace.sm),
                Expanded(
                  child: Text(
                    watch.lastBeat == null
                        ? t.bgNeverRan
                        : '${t.bgLastBeat(_ago(t, watch.lastBeat!))} · '
                            '${t.bgBeats(watch.beats)}',
                    style: MindType.caption,
                  ),
                ),
              ],
            ),
            if (watch.found != null) ...[
              const SizedBox(height: MindSpace.xs),
              Text(t.bgUpdateFound(watch.found!),
                  style: MindType.caption.copyWith(color: mode.accent)),
            ],
          ],

          const SizedBox(height: MindSpace.md),
          Container(
            padding: const EdgeInsets.all(MindSpace.md),
            decoration: BoxDecoration(
              color: watch.batteryExempt
                  ? mode.accent.withValues(alpha: .08)
                  : const Color(0x14FFAB3D),
              borderRadius: BorderRadius.circular(MindRadius.control),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      watch.batteryExempt
                          ? Icons.check_circle_rounded
                          : Icons.battery_alert_rounded,
                      size: 16,
                      color: watch.batteryExempt
                          ? mode.accent
                          : const Color(0xFFB46A00),
                    ),
                    const SizedBox(width: MindSpace.sm),
                    Expanded(
                      child: Text(
                        watch.batteryExempt
                            ? t.bgBatteryOn
                            : t.bgBatteryOff,
                        style: MindType.title.copyWith(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                if (!watch.batteryExempt) ...[
                  const SizedBox(height: MindSpace.sm),
                  Text(t.bgBatteryWhy, style: MindType.caption),
                  const SizedBox(height: MindSpace.sm),
                  MindButton(
                    label: t.bgBatteryAsk,
                    mode: mode,
                    expand: true,
                    onTap: watch.askBatteryExempt,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "เมื่อไหร่" แบบหยาบ ๆ ก็พอ — คนอ่านอยากรู้ว่า "เพิ่งตื่น" หรือ "หายไปนาน"
  /// ไม่ได้อยากรู้วินาทีที่เท่าไหร่
  static String _ago(S t, DateTime at) {
    final m = DateTime.now().difference(at).inMinutes;
    if (m < 1) return t.agoJustNow;
    if (m < 60) return t.agoMinutes(m);
    return t.agoHours(m ~/ 60);
  }

  Widget _avatarPackCard(
      BuildContext context, MindState state, MindMode mode, S t) {
    final packs = context.watch<AvatarPacks>();
    final busy = packs.stage == AvatarPackStage.downloading ||
        packs.stage == AvatarPackStage.verifying ||
        packs.stage == AvatarPackStage.unpacking;

    final err = switch (packs.error) {
      AvatarPackError.noUrl => t.packErrNoUrl,
      AvatarPackError.network => t.packErrNetwork,
      AvatarPackError.hashMismatch => t.packErrHash,
      AvatarPackError.badPack => t.packErrBadPack,
      AvatarPackError.noServer => t.packErrServer,
      null => null,
    };

    final busyLabel = switch (packs.stage) {
      AvatarPackStage.downloading => '${t.packDownloading} · ${packs.sizeLabel}',
      AvatarPackStage.verifying => t.packVerifying,
      AvatarPackStage.unpacking => t.packUnpacking,
      _ => null,
    };

    return _card(
      mode: mode,
      label: t.packTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (packs.installed.isEmpty) ...[
            Row(
              children: [
                const Icon(Icons.download_for_offline_outlined,
                    size: 18, color: MindColors.ink45),
                const SizedBox(width: MindSpace.sm),
                Expanded(child: Text(t.packMissing, style: MindType.title)),
              ],
            ),
            const SizedBox(height: MindSpace.sm),
            Text(t.packWhy, style: MindType.caption),
          ] else ...[
            MindSectionLabel(t.packInstalled),
            const SizedBox(height: MindSpace.sm),
            for (final p in packs.installed)
              Padding(
                padding: const EdgeInsets.only(bottom: MindSpace.sm),
                child: _packRow(context, state, packs, mode, t, p, busy),
              ),
          ],

          if (busyLabel != null) ...[
            const SizedBox(height: MindSpace.md),
            Text(busyLabel, style: MindType.caption),
            const SizedBox(height: MindSpace.sm),
            // ระหว่างแตกไฟล์ไม่รู้ความคืบหน้า ให้แถบวิ่งไปเรื่อย ๆ ดีกว่าแถบ 0%
            // ที่ค้างนิ่ง ซึ่งอ่านได้ว่าค้างจริง
            LinearProgressIndicator(
              value: packs.stage == AvatarPackStage.downloading
                  ? packs.progress
                  : null,
            ),
          ],
          if (err != null) ...[
            const SizedBox(height: MindSpace.sm),
            Text(err,
                style: MindType.caption.copyWith(color: const Color(0xFFB4004E))),
          ],

          const SizedBox(height: MindSpace.md),
          // ทางเข้าร้าน — ปลายทางจริงของการได้ชุดใหม่ ส่วนช่อง URL ข้างล่าง
          // เก็บไว้สำหรับทดสอบชุดที่ยังไม่ขึ้นร้าน
          MindButton(
            label: t.shopOpen,
            kind: MindButtonKind.primary,
            icon: Icons.storefront_rounded,
            mode: mode,
            expand: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ShopScreen()),
            ),
          ),
          const SizedBox(height: MindSpace.md),
          MindSectionLabel(t.packAdd),
          const SizedBox(height: MindSpace.sm),
          Container(
            decoration: BoxDecoration(
              color: MindColors.glass80,
              borderRadius: BorderRadius.circular(MindRadius.control),
              border: Border.all(color: MindColors.glassBorder, width: 1),
            ),
            child: TextFormField(
              initialValue: state.avatarPackUrl,
              enabled: !busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              style: MindType.body.copyWith(fontSize: 12.5),
              decoration: InputDecoration(hintText: t.packUrlLabel),
              onChanged: state.setAvatarPackUrl,
            ),
          ),
          const SizedBox(height: MindSpace.sm),
          MindButton(
            label: t.packDownload,
            kind: MindButtonKind.primary,
            icon: Icons.download_rounded,
            mode: mode,
            expand: true,
            onTap: busy || state.avatarPackUrl.isEmpty
                ? null
                : () => packs.install(state.avatarPackUrl),
          ),
        ],
      ),
    );
  }

  /// หนึ่งแถว = หนึ่งชุดที่มีในเครื่อง · แตะเพื่อใส่ กดถังขยะเพื่อลบ
  Widget _packRow(BuildContext context, MindState state, AvatarPacks packs,
      MindMode mode, S t, AvatarPackInfo p, bool busy) {
    final wearing = packs.selected?.id == p.id;
    final kind = p.kind == AvatarPackKind.outfit
        ? t.packKindOutfit
        : t.packKindCharacter;

    return GestureDetector(
      onTap: busy || wearing
          ? null
          : () {
              packs.select(p.id);
              // จำไว้ข้ามการเปิดปิดแอป — ทะเบียนชุดไม่รู้จัก SharedPreferences
              // และไม่ควรรู้จัก หน้าจอเป็นคนเชื่อมสองฝั่งนี้
              state.setAvatarPackId(p.id);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
            horizontal: MindSpace.md, vertical: MindSpace.md),
        decoration: BoxDecoration(
          color: wearing
              ? mode.accent.withValues(alpha: .10)
              : MindColors.glass80,
          borderRadius: BorderRadius.circular(MindRadius.control),
          border: Border.all(
            color: wearing ? mode.accent.withValues(alpha: .45)
                           : MindColors.glassBorder,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              wearing ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 18,
              color: wearing ? mode.accent : MindColors.ink22,
            ),
            const SizedBox(width: MindSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nameFor(t.isThai),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MindType.title),
                  const SizedBox(height: 2),
                  Text(wearing ? '$kind · ${t.packWearing}' : kind,
                      style: MindType.caption.copyWith(fontSize: 11)),
                ],
              ),
            ),
            // ลบได้เฉพาะชุดที่ไม่ได้ใส่อยู่ — ลบชุดที่ใส่อยู่แล้วเธอจะหายไปทันที
            // โดยที่คนกดไม่ได้ตั้งใจให้เป็นแบบนั้น
            if (!wearing)
              MindIconButton(
                icon: Icons.delete_outline_rounded,
                tooltip: t.packRemove,
                mode: mode,
                onTap: busy
                    ? null
                    : () => _confirmRemove(context, packs, t, p),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, AvatarPacks packs, S t,
      AvatarPackInfo p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t.packRemoveConfirm(p.nameFor(t.isThai))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(c, true), child: Text(t.packRemove)),
        ],
      ),
    );
    if (ok == true) await packs.remove(p.id);
  }

  Widget _noKeyBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: GlassPanel(
        radius: MindRadius.avatarThumb,
        fill: const Color(0x33FFAB3D),
        border: const Color(0x66FFAB3D),
        padding: const EdgeInsets.all(13),
        child: Row(
          spacing: 10,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 18, color: Color(0xFFB46A00)),
            Expanded(
              child: Text(
                S.of(context).noKeyBanner,
                style: const TextStyle(
                    fontSize: 11, height: 1.6, color: MindColors.ink75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ภาษา ────────────────────────────────────────────────
  Widget _languageCard(MindState state, MindMode mode, S t) {
    return _card(
      mode: mode,
      label: t.language,
      child: Row(
        spacing: 7,
        children: [
          for (final l in AppLang.values)
            Expanded(
              child: _segment(
                // ชื่อภาษาเขียนด้วยภาษาของตัวเองเสมอ ผู้ใช้ต้องอ่านออก
                // ไม่ว่าตอนนี้แอปจะตั้งภาษาอะไรอยู่ ไม่งั้นคนที่เผลอตั้งผิด
                // จะหาทางกลับไม่เจอ
                text: l.nativeName,
                selected: state.lang == l,
                mode: mode,
                onTap: () => state.setLang(l),
              ),
            ),
        ],
      ),
    );
  }

  // ── โหมด ────────────────────────────────────────────────
  Widget _modeCard(MindState state, MindMode mode) {
    return _card(
      mode: mode,
      label: S.of(context).sectionMode,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Row(
            spacing: 7,
            children: [
              for (final p in PersonaSetting.values)
                Expanded(
                  child: _segment(
                    text: p.labelOf(S.of(context)),
                    selected: state.persona == p,
                    mode: mode,
                    onTap: () => state.setPersona(p),
                  ),
                ),
            ],
          ),
          Text(
            S.of(context).autoModeExplained,
            style: const TextStyle(
                fontSize: 11, height: 1.6, color: MindColors.ink55),
          ),
          if (state.persona == PersonaSetting.auto)
            Text(S.of(context).nowInMode(mode.labelOf(S.of(context))),
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: mode.accent)),
        ],
      ),
    );
  }

  // ── ระดับการจีบ ─────────────────────────────────────────
  Widget _flirtCard(MindState state, MindMode mode) {
    return _card(
      mode: mode,
      label: S.of(context).flirtTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 5,
              activeTrackColor: mode.accent,
              inactiveTrackColor: MindColors.ink10,
              thumbColor: Colors.white,
              overlayColor: mode.accentSoft,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            ),
            child: Slider(value: state.flirt, onChanged: state.setFlirt),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(S.of(context).flirtLow,
                  style: const TextStyle(fontSize: 10.5, color: MindColors.ink50)),
              Text(S.of(context).flirtHigh,
                  style: const TextStyle(fontSize: 10.5, color: MindColors.ink50)),
            ],
          ),
          const SizedBox(height: 12),
          _quote('“${S.of(context).flirtSample(state.effectiveFlirt)}”'),
          const SizedBox(height: 7),
          Text(S.of(context).flirtNote,
              style: const TextStyle(fontSize: 10.5, color: MindColors.ink50)),
        ],
      ),
    );
  }

  // ── ฟองคำพูด ────────────────────────────────────────────
  Widget _bubbleCard(MindState state, MindMode mode) {
    final t = S.of(context);
    return _card(
      mode: mode,
      label: t.bubbleTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(t.bubbleEnabled,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(t.bubbleHint,
                        style: const TextStyle(
                            fontSize: 10.5, height: 1.5, color: MindColors.ink55)),
                  ],
                ),
              ),
              _toggle(
                on: state.bubbleEnabled,
                mode: mode,
                onTap: () => state.setBubbleEnabled(!state.bubbleEnabled),
              ),
            ],
          ),
          if (!state.bubbleEnabled) ...[
            const SizedBox(height: 8),
            Text(t.bubbleOffNote,
                style: const TextStyle(
                    fontSize: 10.5, height: 1.5, color: MindColors.ink55)),
          ] else ...[
            const SizedBox(height: 14),
            Text(t.bubbleDuration,
                style: mindMono(
                    size: 10, color: mode.accent, letterSpacing: .1)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final sec in MindState.bubbleSecondChoices)
                  GestureDetector(
                    onTap: () => state.setBubbleSeconds(sec),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 7),
                      decoration: BoxDecoration(
                        gradient:
                            state.bubbleSeconds == sec ? mode.gradient : null,
                        color: state.bubbleSeconds == sec
                            ? null
                            : MindColors.glass80,
                        borderRadius: BorderRadius.circular(MindRadius.pill),
                        border: Border.all(
                            color: MindColors.glassBorder, width: 1),
                      ),
                      child: Text(
                        sec == 0 ? t.bubbleStay : t.bubbleSeconds(sec),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: state.bubbleSeconds == sec
                              ? Colors.white
                              : MindColors.ink60,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              state.bubbleSeconds == 0
                  ? t.bubbleStayNote
                  : t.bubbleFadeNote(state.bubbleSeconds),
              style: const TextStyle(
                  fontSize: 10.5, height: 1.5, color: MindColors.ink55),
            ),
          ],
        ],
      ),
    );
  }

  // ── สมอง ─────────────────────────────────
  Widget _brainCard(MindState state, MindMode mode) {
    return _card(
      mode: mode,
      label: S.of(context).sectionBrain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in BrainProvider.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _choiceRow(
                title: b.labelOf(S.of(context)),
                subtitle: b.summaryOf(S.of(context)),
                selected: state.brain == b,
                mode: mode,
                onTap: () => state.setBrain(b),
              ),
            ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: MindColors.glass80,
              borderRadius: BorderRadius.circular(MindRadius.control),
              border: Border.all(color: MindColors.glassBorder, width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 9,
              children: [
                Icon(
                  state.brain.leavesDevice
                      ? Icons.cloud_upload_outlined
                      : Icons.lock_outline_rounded,
                  size: 16,
                  color: state.brain.leavesDevice
                      ? const Color(0xFFB46A00)
                      : const Color(0xFF00A894),
                ),
                Expanded(
                  child: Text(
                    state.brain.tradeoffOf(S.of(context)),
                    style: const TextStyle(
                        fontSize: 10.5, height: 1.6, color: MindColors.ink75),
                  ),
                ),
              ],
            ),
          ),
          if (state.brain == BrainProvider.openai) ...[
            const SizedBox(height: 12),
            Text(S.of(context).sectionBrain,
                style: mindMono(
                    size: 9.5, color: MindColors.ink50, letterSpacing: .1)),
            const SizedBox(height: 7),
            for (final m in OpenAiConfig.brainChoices)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _choiceRow(
                  title: m.label,
                  subtitle: S.of(context).brainModelHint(m.id),
                  trailing: m.id,
                  selected: state.brainModel == m.id,
                  mode: mode,
                  onTap: () => state.setBrainModel(m.id),
                ),
              ),
          ],
          if (state.brain == BrainProvider.homeServer) ...[
            const SizedBox(height: 12),
            _linkRow(
              title: S.of(context).homeServerAddress,
              value: state.homeServerUrl,
              mode: mode,
              onTap: () => _editText(
                state: state,
                mode: mode,
                title: S.of(context).homeServerAddress,
                hint: S.of(context).homeServerHint,
                value: state.homeServerUrl,
                onSave: state.setHomeServerUrl,
                onReset: () => HomeServerDefaults.baseUrl,
              ),
            ),
            const SizedBox(height: 7),
            _linkRow(
              title: S.of(context).homeServerModel,
              value: state.homeServerModel,
              mode: mode,
              onTap: () => _editText(
                state: state,
                mode: mode,
                title: S.of(context).homeServerModel,
                hint: S.of(context).homeServerModelHint,
                value: state.homeServerModel,
                onSave: state.setHomeServerModel,
                onReset: () => HomeServerDefaults.model,
              ),
            ),
          ],
          if (state.brain == BrainProvider.onDevice) ...[
            const SizedBox(height: 12),
            _onDeviceSection(state, mode),
          ],
        ],
      ),
    );
  }

  /// จัดการโมเดล Gemma 4 ที่รันบนมือถือ
  Widget _onDeviceSection(MindState state, MindMode mode) {
    return ListenableBuilder(
      listenable: state.localBrain,
      builder: (context, _) {
        final lb = state.localBrain;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.of(context).gemmaVariant,
                style: mindMono(
                    size: 9.5, color: MindColors.ink50, letterSpacing: .1)),
            const SizedBox(height: 7),
            for (final v in GemmaVariant.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _choiceRow(
                  title: v.label,
                  subtitle: v.hintOf(S.of(context)),
                  trailing: v.sizeLabel,
                  selected: lb.variant == v,
                  mode: mode,
                  onTap: () => lb.selectVariant(v),
                ),
              ),
            const SizedBox(height: 4),
            switch (lb.stage) {
              LocalModelStage.ready => Row(
                  spacing: 9,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 16, color: Color(0xFF00A894)),
                    Expanded(
                      child: Text(S.of(context).gemmaReady,
                          style: const TextStyle(
                              fontSize: 11, color: MindColors.ink75)),
                    ),
                    GestureDetector(
                      onTap: lb.remove,
                      child: Text(S.of(context).gemmaRemove,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFE0357A))),
                    ),
                  ],
                ),
              LocalModelStage.downloading => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(MindRadius.pill),
                      child: LinearProgressIndicator(
                        value: lb.progress / 100,
                        minHeight: 5,
                        backgroundColor: MindColors.ink10,
                        valueColor: AlwaysStoppedAnimation(mode.accent),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${S.of(context).downloadingPct(lb.progress, lb.sizeProgressLabel)}'
                      '${lb.speedLabel.isEmpty ? '' : ' · ${lb.speedLabel}'}',
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: MindColors.ink75),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      lb.etaLabel.isEmpty
                          ? S.of(context).gemmaKeepOpen
                          : S.of(context).etaWithNote(lb.etaLabel),
                      style: const TextStyle(
                          fontSize: 10.5, color: MindColors.ink55),
                    ),
                  ],
                ),
              LocalModelStage.failed => Text(
                  lb.error ?? S.of(context).somethingWrong,
                  style: const TextStyle(
                      fontSize: 11, height: 1.5, color: Color(0xFFB46A00)),
                ),
              _ => GestureDetector(
                  onTap: lb.download,
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
                    child: Text(
                      S.of(context).gemmaDownload(lb.variant.sizeLabel),
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ),
                ),
            },
          ],
        );
      },
    );
  }

  // ── เสียง แยกตามช่องทาง ──────────────────────
  Widget _voiceCard(MindState state, MindMode mode) {
    final channel = _voiceTab;
    final profile = state.voiceFor(channel);
    final usingOpenAi = profile.engine == TtsEngine.openai;
    final canInstruct = OpenAiConfig.supportsInstructions(profile.model);

    return _card(
      mode: mode,
      label: S.of(context).sectionVoice,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(S.of(context).voiceEnabled,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              _toggle(
                on: state.voiceEnabled,
                mode: mode,
                onTap: () => state.setVoiceEnabled(!state.voiceEnabled),
              ),
            ],
          ),
          if (!state.voiceEnabled) ...[
            const SizedBox(height: 6),
            Text(S.of(context).voiceDisabledNote,
                style: const TextStyle(fontSize: 10.5, color: MindColors.ink55)),
          ] else ...[
            const SizedBox(height: 14),

            // เลือกช่องทางก่อน แล้วค่าทั้งหมดข้างล่างเป็นของช่องนั้น
            // ไม่รวมเป็นชุดเดียว เพราะคุยกับเจ้าของกับคุยกับคนแปลกหน้า
            // ต้องการน้ำเสียงคนละแบบจริง ๆ
            Row(
              spacing: 6,
              children: [
                for (final c in VoiceChannel.values)
                  Expanded(
                    child: _segment(
                      text: c.labelOf(S.of(context)),
                      selected: channel == c,
                      mode: mode,
                      onTap: () => setState(() => _voiceTab = c),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(channel.hintOf(S.of(context)),
                style: const TextStyle(fontSize: 10.5, color: MindColors.ink55)),

            const SizedBox(height: 14),
            Text(S.of(context).voiceEngine,
                style: mindMono(
                    size: 9.5, color: MindColors.ink50, letterSpacing: .1)),
            const SizedBox(height: 7),
            Row(
              spacing: 7,
              children: [
                for (final e in TtsEngine.values)
                  Expanded(
                    child: _segment(
                      text: e.labelOf(S.of(context)),
                      selected: profile.engine == e,
                      mode: mode,
                      onTap: () =>
                          state.setVoice(channel, profile.copyWith(engine: e)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(profile.engine.hintOf(S.of(context)),
                style: const TextStyle(fontSize: 10.5, color: MindColors.ink55)),

            if (usingOpenAi) ...[
              const SizedBox(height: 14),
              Text(S.of(context).voiceModel,
                  style: mindMono(
                      size: 9.5, color: MindColors.ink50, letterSpacing: .1)),
              const SizedBox(height: 7),
              for (final m in OpenAiConfig.ttsChoices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _choiceRow(
                    title: m,
                    subtitle: S.of(context).ttsModelHint(m),
                    selected: profile.model == m,
                    mode: mode,
                    onTap: () =>
                        state.setVoice(channel, profile.copyWith(model: m)),
                  ),
                ),
              const SizedBox(height: 7),
              Text(S.of(context).voicePick,
                  style: mindMono(
                      size: 9.5, color: MindColors.ink50, letterSpacing: .1)),
              const SizedBox(height: 7),
              for (final v in OpenAiConfig.voiceChoices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _choiceRow(
                    title: S.of(context).voiceLabel(v),
                    selected: profile.voice == v,
                    mode: mode,
                    onTap: () =>
                        state.setVoice(channel, profile.copyWith(voice: v)),
                  ),
                ),
              if (canInstruct)
                _linkRow(
                  title: S.of(context).voiceInstructions,
                  value: profile.instructions,
                  mode: mode,
                  onTap: () => _editText(
                    state: state,
                    mode: mode,
                    title: S.of(context).toneFor(channel.labelOf(S.of(context))),
                    hint: S.of(context).toneEditorHint(profile.model),
                    value: profile.instructions,
                    onSave: (v) => state.setVoice(
                        channel, profile.copyWith(instructions: v)),
                    onReset: () =>
                        VoiceProfile.defaultFor(channel, state.lang).instructions,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0x22FFAB3D),
                    borderRadius: BorderRadius.circular(MindRadius.control),
                  ),
                  child: Text(
                    S.of(context).noInstructionSupport(profile.model),
                    style: const TextStyle(
                        fontSize: 10.5, height: 1.5, color: MindColors.ink75),
                  ),
                ),
            ],

            if (channel != VoiceChannel.chat) ...[
              const SizedBox(height: 14),
              Text(S.of(context).realtimeModel,
                  style: mindMono(
                      size: 9.5, color: MindColors.ink50, letterSpacing: .1)),
              const SizedBox(height: 7),
              for (final r in OpenAiConfig.realtimeChoices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _choiceRow(
                    title: r.label,
                    subtitle: S.of(context).realtimeHint(r.id),
                    trailing: r.id,
                    selected: state.realtimeModel == r.id,
                    mode: mode,
                    onTap: () => state.setRealtimeModel(r.id),
                  ),
                ),
              Text(
                S.of(context).realtimeNote,
                style: const TextStyle(fontSize: 10.5, color: MindColors.ink55),
              ),
            ],

            const SizedBox(height: 12),
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => state.previewVoice(channel),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: MindColors.glass85,
                        borderRadius: BorderRadius.circular(MindRadius.control),
                        border:
                            Border.all(color: MindColors.glassBorder, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 7,
                        children: [
                          Icon(Icons.volume_up_rounded,
                              size: 16, color: mode.accent),
                          Text(
                              S.of(context)
                                  .listenTo(channel.labelOf(S.of(context))),
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => state.resetVoice(channel),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                    decoration: BoxDecoration(
                      color: MindColors.glass85,
                      borderRadius: BorderRadius.circular(MindRadius.control),
                      border:
                          Border.all(color: MindColors.glassBorder, width: 1),
                    ),
                    child: Text(S.of(context).reset,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── รับสายอัตโนมัติ ─────────────────────────────────────
  Widget _callCard(MindState state, MindMode mode) {
    return _card(
      mode: mode,
      label: S.of(context).sectionCall,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(S.of(context).autoAnswer,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(S.of(context).autoAnswerHint,
                        style: const TextStyle(
                            fontSize: 10.5, height: 1.5, color: MindColors.ink55)),
                  ],
                ),
              ),
              _toggle(
                on: state.autoAnswer,
                mode: mode,
                onTap: () => state.setAutoAnswer(!state.autoAnswer),
              ),
            ],
          ),
          if (state.autoAnswer) ...[
            const SizedBox(height: 14),
            Text(S.of(context).ringDelayTitle,
                style: mindMono(size: 10, color: mode.accent, letterSpacing: .1)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final s in MindState.ringChoices)
                  GestureDetector(
                    onTap: () => state.setRingSeconds(s),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                      decoration: BoxDecoration(
                        gradient: state.ringSeconds == s ? mode.gradient : null,
                        color: state.ringSeconds == s ? null : MindColors.glass80,
                        borderRadius: BorderRadius.circular(MindRadius.pill),
                        border:
                            Border.all(color: MindColors.glassBorder, width: 1),
                      ),
                      child: Text(
                        s == 0
                            ? S.of(context).ringImmediate
                            : S.of(context).ringSeconds(s),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: state.ringSeconds == s
                              ? Colors.white
                              : MindColors.ink60,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              state.ringSeconds == 0
                  ? S.of(context).ringImmediateNote
                  : S.of(context).ringDelayNote(state.ringSeconds),
              style: const TextStyle(
                  fontSize: 10.5, height: 1.5, color: MindColors.ink55),
            ),
          ],
        ],
      ),
    );
  }

  // ── สวิตช์อื่น ๆ ────────────────────────────────────────
  Widget _switchCard(MindMode mode) {
    final keys = _switches.keys.toList();

    return GlassPanel(
      radius: MindRadius.card,
      fill: MindColors.glass62,
      filter: MindGlass.light,
      shadows: MindShadows.card(),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: MindColors.ink10),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        Text(keys[i].labelOf(S.of(context)),
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                        Text(keys[i].hintOf(S.of(context)),
                            style: const TextStyle(
                                fontSize: 10.5,
                                height: 1.5,
                                color: MindColors.ink55)),
                      ],
                    ),
                  ),
                  _toggle(
                    on: _switches[keys[i]]!,
                    mode: mode,
                    onTap: () =>
                        setState(() => _switches[keys[i]] = !_switches[keys[i]]!),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══ ชิ้นส่วนที่ใช้ซ้ำ ═══════════════════════════════════

  Widget _card({
    required MindMode mode,
    required String label,
    required Widget child,
  }) {
    return GlassPanel(
      radius: MindRadius.card,
      fill: MindColors.glass62,
      filter: MindGlass.light,
      shadows: MindShadows.card(),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ป้ายหัวการ์ด — ของเดิม 10px น้ำหนักปกติสีเน้นจาง ๆ กลืนไปกับการ์ด
          // ป้ายที่อ่านไม่ออกคือป้ายที่ไม่มีอยู่ โครงของหน้าก็หายไปด้วย
          Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: mode.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: MindSpace.sm),
              Expanded(
                child: Text(label.toUpperCase(),
                    style: MindType.overline.copyWith(color: mode.accent)),
              ),
            ],
          ),
          const SizedBox(height: MindSpace.md),
          child,
        ],
      ),
    );
  }

  Widget _segment({
    required String text,
    required bool selected,
    required MindMode mode,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: MindSpace.tapHeight,
        padding: const EdgeInsets.symmetric(horizontal: MindSpace.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? mode.gradient : null,
          color: selected ? null : MindColors.glass80,
          borderRadius: BorderRadius.circular(MindRadius.control),
          border: Border.all(
              color: selected ? Colors.transparent : MindColors.glassBorder,
              width: 1),
          // เงาเรืองเฉพาะอันที่เลือกอยู่ ทำให้ตาจับได้ทันทีว่าตอนนี้อยู่ตรงไหน
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: mode.accentSoft,
                      blurRadius: 16,
                      offset: const Offset(0, 6)),
                ]
              : null,
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: MindType.button.copyWith(
            color: selected ? Colors.white : MindColors.ink60,
          ),
        ),
      ),
    );
  }

  Widget _choiceRow({
    required String title,
    String? subtitle,
    String? trailing,
    required bool selected,
    required MindMode mode,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? null : MindColors.glass80,
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    mode.gradient.colors.first.withValues(alpha: .20),
                    mode.gradient.colors.last.withValues(alpha: .14),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(MindRadius.control),
          border: Border.all(
            color: selected ? mode.accentSoft : MindColors.glassBorder,
            width: 1,
          ),
        ),
        child: Row(
          spacing: 10,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 16,
              color: selected ? mode.accent : MindColors.ink22,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                  if (subtitle != null)
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 10.5, color: MindColors.ink55)),
                ],
              ),
            ),
            if (trailing != null)
              Text(trailing, style: mindMono(size: 9.5, color: MindColors.ink45)),
          ],
        ),
      ),
    );
  }

  Widget _longTextCard({
    required MindState state,
    required MindMode mode,
    required String title,
    required String hint,
    required String value,
    required String editorHint,
    required void Function(String) onSave,
    required String Function() onReset,
  }) {
    final lines = value.trim().split('\n').where((l) => l.trim().isNotEmpty).length;

    return _card(
      mode: mode,
      label: title,
      child: GestureDetector(
        onTap: () => _editText(
          state: state,
          mode: mode,
          title: title,
          hint: editorHint,
          value: value,
          onSave: onSave,
          onReset: onReset,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 9,
          children: [
            Text(hint,
                style: const TextStyle(
                    fontSize: 11, height: 1.6, color: MindColors.ink55)),
            _quote(value.trim(), maxLines: 4),
            Row(
              children: [
                Text(S.of(context).lines(lines),
                    style: mindMono(size: 10, color: MindColors.ink45)),
                const Spacer(),
                Text(S.of(context).tapToEdit,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: mode.accent)),
                const SizedBox(width: 3),
                Icon(Icons.chevron_right_rounded, size: 16, color: mode.accent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _linkRow({
    required String title,
    required String value,
    required MindMode mode,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: MindColors.glass80,
          borderRadius: BorderRadius.circular(MindRadius.control),
          border: Border.all(color: MindColors.glassBorder, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  Text(value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10.5, height: 1.5, color: MindColors.ink55)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: mode.accent),
          ],
        ),
      ),
    );
  }

  Widget _quote(String text, {int? maxLines}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: MindColors.glass85,
        borderRadius: BorderRadius.circular(MindRadius.message),
        border: Border.all(color: MindColors.glassBorder, width: 1),
      ),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, height: 1.7),
      ),
    );
  }

  Widget _toggle({
    required bool on,
    required MindMode mode,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        width: 40,
        height: 22,
        padding: const EdgeInsets.all(2),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          gradient: on ? mode.gradient : null,
          color: on ? null : MindColors.ink10,
          borderRadius: BorderRadius.circular(MindRadius.pill),
          border: Border.all(
              color: on ? const Color(0xB3FFFFFF) : MindColors.ink10, width: 1),
          boxShadow: on
              ? [
                  BoxShadow(
                      color: mode.accentSoft,
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]
              : null,
        ),
        child: Container(
          width: 16,
          height: 16,
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
      ),
    );
  }

  Future<void> _editText({
    required MindState state,
    required MindMode mode,
    required String title,
    required String hint,
    required String value,
    required void Function(String) onSave,
    required String Function() onReset,
  }) async {
    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => TextEditorScreen(
          title: title,
          hint: hint,
          initial: value,
          mode: mode,
          onReset: onReset,
        ),
      ),
    );
    if (result != null) onSave(result);
  }
}
