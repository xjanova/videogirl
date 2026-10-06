import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../ai/brain_provider.dart';
import '../i18n/enum_labels.dart';
import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import '../ai/device_capability.dart';
import '../ai/local_brain.dart';
import '../ai/mind_persona.dart';
import '../ai/openai_config.dart';
import '../ai/secret_store.dart';
import '../license/mind_license.dart';
import 'package:url_launcher/url_launcher.dart';
import '../ai/speech_service.dart';
import '../ai/voice_profile.dart';
import '../avatar/avatar_pack.dart';
import '../avatar/avatar_view.dart';
import '../background/mind_watch.dart';
import 'shop_screen.dart';
import '../memory/mind_memory.dart';
import '../system/permissions.dart';
import '../persona/mind_soul.dart';
import '../state/mind_state.dart';
import '../diagnostics/debug_report.dart';
import '../diagnostics/debug_reporter.dart';
import '../store/mind_vault.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';
import '../widgets/screen_header.dart';
import '../ai/openai_client.dart';
import '../i18n/strings_settings.dart';
import '../phone/call_session.dart';
import '../studio/mind_studio.dart';
import '../system/app_life.dart';
import '../i18n/strings_voice.dart';
import '../ai/local_server_scan.dart';
import '../ai/premium_catalog.dart';
import '../ai/premium_tts.dart';
import '../widgets/update_card.dart';
import 'text_editor_screen.dart';

/// หมวดของหน้าตั้งค่า — เรียงตามคำถามที่คนถามบ่อยก่อน
///
/// 🔴 ของเดิมเป็นการ์ดเรียงยาวสิบเจ็ดใบในหน้าเดียว · คนที่อยากรู้ว่า "ซีเรียล
/// อยู่ไหน" หรือ "ใช้โมเดลไหน" ต้องเลื่อนหาเอง แล้วหาไม่เจอ (ซีเรียลเคยโผล่
/// เฉพาะตอนเลือกสมองแบบพร็อกซีด้วยซ้ำ)
enum SettingsSection { account, her, brain, you, calls, general, data }

/// ตั้งค่า — หน้าแรกเป็นเมนูหมวด แตะแล้วเข้าไปดูการ์ดของหมวดนั้น
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.section});

  /// หมวดที่เปิดอยู่ · null = หน้าเมนู
  ///
  /// shell ถือตัวนี้ไว้ เพราะปุ่ม Back ของ Android ต้องปิดหมวดก่อน ไม่ใช่
  /// พาออกจากแท็บตั้งค่าไปเลย
  final ValueNotifier<SettingsSection?>? section;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  /// 🔴 สิทธิ์ที่ต้องไปกดในหน้าตั้งค่าของระบบ (ยกเว้นแบต, ติดตั้งแอปไม่รู้จัก)
  /// เปลี่ยนค่าตอนที่แอปเรา**ไม่ได้อยู่หน้าจอ** ถ้าไม่อ่านใหม่ตอนกลับมา
  /// การ์ดจะบอกว่ายังไม่ได้ให้ ทั้งที่เพิ่งไปกดให้มาหมาด ๆ
  /// แล้วผู้ใช้จะกดวนอยู่อย่างนั้นโดยไม่รู้ว่าจริง ๆ สำเร็จไปแล้ว
  late final ValueNotifier<SettingsSection?> _open =
      widget.section ?? ValueNotifier<SettingsSection?>(null);

  void _onSection() {
    if (mounted) setState(() {});
  }

  /// ซีเรียลโชว์เต็มอยู่ไหม · ค่าตั้งต้นซ่อนกลาง — หน้าจอถูกแคปไปถามคนอื่นได้เสมอ
  bool _showSerial = false;

  @override
  void initState() {
    super.initState();
    _open.addListener(_onSection);
    WidgetsBinding.instance.addObserver(this);
    // การ์ดข้อมูลต้องบอกสถานะจริงตั้งแต่วินาทีที่เห็น ไม่ใช่ค้างที่
    // "ยังไม่ได้ให้สิทธิ์" ทั้งที่ให้ไปแล้ว จนกว่าจะมีอะไรมากระตุก
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      unawaited(context.read<MindVault>().check());
      final n = await context.read<MindState>().storedMessageCount();
      if (mounted) setState(() => _storedMessages = n);
    });
  }

  @override
  void dispose() {
    _open.removeListener(_onSection);
    if (widget.section == null) _open.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final perms = context.read<MindPermissions>();
    final vault = context.read<MindVault>();
    // 🔴 ต้องอ่านสิทธิ์ให้เสร็จก่อนถามสำเนา — vault ตัดสินจากสิทธิ์
    // ถามพร้อมกันจะได้คำตอบจากค่าสิทธิ์เก่า แล้วการ์ดจะบอกว่ายังไม่ได้ให้
    // ทั้งที่ผู้ใช้เพิ่งไปกดให้มาหมาด ๆ ในหน้าตั้งค่าของระบบ
    unawaited(perms.refresh().then((_) => vault.check()));
    context.read<MindWatch>().refresh();
  }

  /// ช่องทางเสียงที่กำลังตั้งค่าอยู่ในการ์ด "เสียงพูด"
  VoiceChannel _voiceTab = VoiceChannel.chat;

  /// จำนวนข้อความที่เก็บไว้จริง — นับครั้งเดียวตอนเปิดหน้า
  int _storedMessages = 0;

  // 🔴 การ์ด "สวิตช์อื่น ๆ" (สรุปเมลตอนเช้า / ให้เธอส่งเมลเอง / Always-on /
  // ฟองลอยทับแอปอื่น) ถูกถอดออก 2026-10-05 · ทั้งสี่ตัวไม่ถูกบันทึกและไม่มีใคร
  // อ่านค่า — สวิตช์ที่กดได้แต่ไม่มีผลคือการโกหกผู้ใช้ · Always-on ตัวจริงคือ
  // การ์ดเฝ้างาน (_watchCard) · วันที่ฟีเจอร์ไหนมีของจริง ค่อยเพิ่มกลับทีละตัว

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MindState>();
    final mode = state.mode;
    final t = S.of(context);
    final open = _open.value;

    return LiquidBackground(
      gradient: MindGradients.settings,
      orbs: Orb.settings,
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: open == null
              ? _menu(state, mode, t)
              : _sectionPage(open, state, mode, t),
        ),
      ),
    );
  }

  static const _listPadding =
      EdgeInsets.fromLTRB(MindSpace.lg, 0, MindSpace.lg, MindSpace.lg);

  // ── หน้าเมนูหมวด ─────────────────────────────────────────

  Widget _menu(MindState state, MindMode mode, S t) {
    return ListView(
      key: const ValueKey('settings-menu'),
      padding: _listPadding,
      children: [
        // ListView มีขอบซ้ายขวาอยู่แล้ว หัวจอจึงต้องไม่ใส่ซ้ำ
        // ไม่งั้นจะเยื้องเข้าเป็นสองเท่าของอีกสามจอ
        MindScreenHeader(
          overline: t.tabSettings,
          title: t.settingsMenuTitle,
          padding: const EdgeInsets.fromLTRB(0, MindSpace.lg, 0, MindSpace.md),
          trailing: Semantics(
            button: true,
            label: t.exitApp,
            child: Tooltip(
              message: t.exitApp,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _exitApp(state),
                child: GlassPanel(
                  radius: MindRadius.pill,
                  fill: MindColors.glass80,
                  padding: const EdgeInsets.all(9),
                  child: const Icon(Icons.power_settings_new_rounded,
                      size: 20, color: Color(0xFFE0357A)),
                ),
              ),
            ),
          ),
        ),
        for (final sec in SettingsSection.values) ...[
          _menuTile(sec, state, mode, t),
          const SizedBox(height: MindSpace.sm),
        ],
      ],
    );
  }

  static IconData _iconOf(SettingsSection sec) => switch (sec) {
        SettingsSection.account => Icons.vpn_key_rounded,
        SettingsSection.her => Icons.face_retouching_natural_rounded,
        SettingsSection.brain => Icons.psychology_rounded,
        SettingsSection.you => Icons.person_rounded,
        SettingsSection.calls => Icons.call_rounded,
        SettingsSection.general => Icons.tune_rounded,
        SettingsSection.data => Icons.shield_outlined,
      };

  static String _titleOf(SettingsSection sec, S t) => switch (sec) {
        SettingsSection.account => t.settingsSecAccount,
        SettingsSection.her => t.settingsSecHer,
        SettingsSection.brain => t.settingsSecBrain,
        SettingsSection.you => t.settingsSecYou,
        SettingsSection.calls => t.settingsSecCalls,
        SettingsSection.general => t.settingsSecGeneral,
        SettingsSection.data => t.settingsSecData,
      };

  /// บรรทัดใต้ชื่อหมวด — สถานะจริงของหมวดนั้น ไม่ใช่คำอธิบายลอย ๆ ถ้าบอกได้
  /// · (ข้อความ, เป็นเรื่องที่ต้องแก้ไหม)
  (String, bool) _summaryOf(SettingsSection sec, MindState state, S t) {
    switch (sec) {
      case SettingsSection.account:
        if (state.licenseKey.isNotEmpty) {
          return ('${_licenseTypeLabel(state, t)} · ${SecretStore.mask(state.licenseKey)}', false);
        }
        if (state.licenseBusy) return (t.licenseRegistering, false);
        if (state.licenseFailed) return (t.licenseRegisterFailed, true);
        return (t.licenseNone, true);
      case SettingsSection.brain:
        final brain = state.brain.labelOf(t);
        if (state.brain != BrainProvider.onDevice) return (brain, false);
        final lb = state.localBrain;
        final backend = switch (lb.runningOnGpu) {
          true => ' · GPU',
          false => ' · CPU',
          null => '',
        };
        final missing = lb.stage == LocalModelStage.missing ||
            lb.stage == LocalModelStage.failed;
        return ('$brain · ${lb.variant.label}$backend', missing);
      case SettingsSection.her:
        return (t.settingsSecHerHint, false);
      case SettingsSection.you:
        return (t.settingsSecYouHint, false);
      case SettingsSection.calls:
        return (t.settingsSecCallsHint, false);
      case SettingsSection.general:
        return (t.settingsSecGeneralHint, false);
      case SettingsSection.data:
        return (t.settingsSecDataHint, false);
    }
  }

  Widget _menuTile(SettingsSection sec, MindState state, MindMode mode, S t) {
    final (summary, warn) = _summaryOf(sec, state, t);
    return Semantics(
      button: true,
      label: _titleOf(sec, t),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open.value = sec,
        child: GlassPanel(
          radius: MindRadius.card,
          fill: MindColors.glass62,
          filter: MindGlass.light,
          shadows: MindShadows.card(),
          padding: const EdgeInsets.symmetric(
              horizontal: MindSpace.md, vertical: 13),
          child: Row(
            spacing: MindSpace.md,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mode.accent.withValues(alpha: .12),
                ),
                child: Icon(_iconOf(sec), size: 20, color: mode.accent),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(_titleOf(sec, t), style: MindType.title),
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.45,
                        color: warn ? const Color(0xFFB46A00) : MindColors.ink55,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: mode.accent),
            ],
          ),
        ),
      ),
    );
  }

  // ── หน้าของหมวด ──────────────────────────────────────────

  Widget _sectionPage(
      SettingsSection sec, MindState state, MindMode mode, S t) {
    final cards = <Widget>[
      ...switch (sec) {
        SettingsSection.account => [
            _licenseCard(state, mode, t),
            UpdateCard(mode: mode),
          ],
        SettingsSection.her => [
            // ยังไม่มีชุด = เห็นกรอบแทนตัวเธอตั้งแต่เปิดแอป · เป็นเรื่องแรกของหมวดนี้
            _avatarPackCard(context, state, mode, t),
            // ตัวตนอยู่ติดกับชุด เพราะเป็นคำถามเดียวกันในหัวคนดู — "เธอเป็นใคร"
            _soulCard(context, mode, t),
            _modeCard(state, mode),
            _flirtCard(state, mode),
            _bubbleCard(state, mode),
          ],
        SettingsSection.brain => [
            // เตือนเฉพาะตอนที่ "เลือกใช้คีย์ตัวเองแล้วแต่ยังไม่ได้ใส่คีย์"
            if (state.brain.needsOwnKey && !state.hasOwnKey) _noKeyBanner(),
            _brainCard(state, mode),
            _voiceCard(state, mode),
          ],
        SettingsSection.you => [
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
            _memoryCard(context, state, mode, t),
          ],
        SettingsSection.calls => [_callCard(state, mode)],
        SettingsSection.general => [
            _languageCard(state, mode, t),
            _permissionCard(context, mode, t),
            _watchCard(context, mode, t),
            _exitCard(state, mode, t),
          ],
        SettingsSection.data => [
            _dataCard(context, state, mode, t),
            _debugCard(context, state, mode, t),
          ],
      },
    ];

    return ListView(
      key: ValueKey(sec),
      padding: _listPadding,
      children: [
        MindScreenHeader(
          overline: t.settingsMenuTitle,
          title: _titleOf(sec, t),
          padding: const EdgeInsets.fromLTRB(0, MindSpace.lg, 0, MindSpace.md),
          trailing: Semantics(
            button: true,
            label: t.settingsBack,
            child: Tooltip(
              message: t.settingsBack,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _open.value = null,
                child: GlassPanel(
                  radius: MindRadius.pill,
                  fill: MindColors.glass80,
                  padding: const EdgeInsets.all(9),
                  child: Icon(Icons.close_rounded, size: 20, color: mode.accent),
                ),
              ),
            ),
          ),
        ),
        for (final c in cards) ...[c, const SizedBox(height: MindSpace.md)],
      ],
    );
  }

  // ── ออกจากแอป ───────────────────────────────────────────

  Widget _exitCard(MindState state, MindMode mode, S t) {
    return _card(
      mode: mode,
      label: t.exitApp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MindSpace.sm,
        children: [
          Text(t.exitCardHint,
              style: const TextStyle(fontSize: 11, height: 1.5, color: MindColors.ink60)),
          MindButton(
            label: t.exitApp,
            icon: Icons.power_settings_new_rounded,
            mode: mode,
            expand: true,
            onTap: () => _exitApp(state),
          ),
        ],
      ),
    );
  }

  /// ปิดแอปจริง — ทางเดียวที่ปิดแอปได้ (ปุ่มย้อนกลับแค่พักไว้เบื้องหลัง)
  ///
  /// เก็บกวาดก่อนเสมอ: คลิปที่อัดค้างต้องถูกบันทึก กล้องต้องปิด สมองต้องถูก
  /// ปล่อย · มีสายอยู่ = ไม่ปิด (ปิดตอนนั้นคือสายที่เธอถืออยู่หลุดมือ)
  Future<void> _exitApp(MindState state) async {
    final t = S.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (context.read<CallSession>().live) {
      messenger?.showSnackBar(SnackBar(content: Text(t.exitDuringCall)));
      return;
    }
    if (!await _confirm(context, title: t.exitTitle, body: t.exitBody, ok: t.exitOk, t: t)) {
      return;
    }
    if (!mounted) return;
    final studio = context.read<MindStudio>();
    final avatar = context.read<MindAvatarController>();
    // 🔴 ทุกขั้นมีเวลาหมด · ขั้นไหนค้าง (เวที สมอง เครื่องเล่น) ต้องไม่ขวาง
    // ทางออก — เจ้าของกดออกเพราะเครื่องร้อนและช้า แล้วปุ่มนี้ค้างตามไปด้วย
    try {
      await studio.exit().timeout(const Duration(seconds: 2));
      if (avatar.mocapOn) await avatar.stopMocap().timeout(const Duration(seconds: 1));
    } on Object catch (e) {
      debugPrint('ออกจากแอป: ปิดสตูดิโอไม่ทัน — ${e.runtimeType}');
    }
    await state.prepareExit();
    await AppLife.exit();
  }

  // ── ไลเซนส์ ─────────────────────────────────────────────

  static String _licenseTypeLabel(MindState state, S t) => switch (state.licenseType) {
        '' => t.licenseManual,
        'free' => t.licenseTypeFree,
        final other => t.licenseTypeOf(other),
      };

  /// ซีเรียลของเครื่องนี้ — อยู่ให้เห็นเสมอ ไม่ว่าจะเลือกสมองแบบไหน
  ///
  /// 🔴 ของเดิมโผล่เฉพาะตอนเลือกสมองแบบพร็อกซี · คนที่ใช้สมองในเครื่อง (ค่า
  /// ตั้งต้น) ไม่มีทางรู้เลยว่าเครื่องตัวเองลงทะเบียนแล้วหรือยัง และไม่มีที่ให้
  /// ใส่ซีเรียลที่ซื้อมา
  Widget _licenseCard(MindState state, MindMode mode, S t) {
    final key = state.licenseKey;
    final has = key.isNotEmpty;
    final (status, tone, icon) = has
        ? (t.licenseRegistered(_licenseTypeLabel(state, t)), const Color(0xFF00A894),
            Icons.verified_rounded)
        : state.licenseBusy
            ? (t.licenseRegistering, MindColors.ink55, Icons.hourglass_top_rounded)
            : state.licenseFailed
                ? (t.licenseRegisterFailed, const Color(0xFFB46A00),
                    Icons.error_outline_rounded)
                : (t.licenseNone, const Color(0xFFB46A00), Icons.error_outline_rounded);

    return _card(
      mode: mode,
      label: t.licenseSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: MindSpace.sm,
        children: [
          Text(t.licenseSerial,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: MindColors.glass80,
              borderRadius: BorderRadius.circular(MindRadius.control),
              border: Border.all(color: MindColors.glassBorder, width: 1),
            ),
            child: SelectableText(
              !has
                  ? t.licenseNone
                  : _showSerial
                      ? key
                      : SecretStore.mask(key),
              style: mindMono(size: 13, weight: FontWeight.w600, color: MindColors.ink),
            ),
          ),
          Row(
            spacing: 7,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 15, color: tone),
              Expanded(
                child: Text(status,
                    style: TextStyle(fontSize: 11, height: 1.45, color: tone)),
              ),
            ],
          ),
          Wrap(
            spacing: MindSpace.sm,
            runSpacing: MindSpace.sm,
            children: [
              if (has) ...[
                _plainButton(
                  label: _showSerial ? t.licenseHide : t.licenseShow,
                  mode: mode,
                  onTap: () => setState(() => _showSerial = !_showSerial),
                ),
                _plainButton(
                  label: t.licenseCopy,
                  mode: mode,
                  onTap: () async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    await Clipboard.setData(ClipboardData(text: key));
                    messenger?.showSnackBar(SnackBar(content: Text(t.licenseCopied)));
                  },
                ),
              ],
              if (!has && !state.licenseBusy)
                _plainButton(
                  label: t.licenseRetry,
                  mode: mode,
                  onTap: () => state.ensureLicense(retry: true),
                ),
              _plainButton(
                label: t.licenseEnter,
                mode: mode,
                onTap: () => _editText(
                  state: state,
                  mode: mode,
                  title: t.licenseSerial,
                  hint: t.licenseEnterHint,
                  value: key,
                  onSave: (v) {
                    state.setLicenseKey(v);
                    // ลบซีเรียลทิ้ง = ขอไลเซนส์ฟรีของเครื่องนี้กลับมา
                    if (v.trim().isEmpty) {
                      unawaited(state.ensureLicense(retry: true));
                    }
                  },
                  onReset: () => '',
                ),
              ),
            ],
          ),
          // ชุดที่ซื้อบนเว็บผูกกับ**บัญชีเว็บ** ส่วนไลเซนส์ของแอปผูกกับ**เครื่อง**
          if (has)
            _linkRow(
              title: t.licenseLinkAccount,
              value: t.licenseLinkCopied,
              mode: mode,
              onTap: () => _linkAccount(state, t),
            ),
          Text(t.licenseWhy,
              style: const TextStyle(fontSize: 10.5, height: 1.55, color: MindColors.ink55)),
        ],
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
          // พื้นที่แตะ 40dp ทั้งสองปุ่ม · ไอคอน 17px ที่อยู่ห่างกัน 12dp คือปุ่มที่
          // แตะพลาดไปโดนอีกปุ่มได้ง่ายมาก และปุ่มหนึ่งในนั้นลบความจำทิ้ง
          GestureDetector(
            onTap: () => mem.setPinned(f.id, !f.pinned),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Tooltip(
                message: f.pinned ? t.memPinned : t.memPinWhy,
                child: Icon(
                  f.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  size: 17,
                  color: f.pinned ? mode.accent : MindColors.ink22,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              // ลืมแล้วเอาคืนไม่ได้ · ถามก่อนพร้อมโชว์ว่ากำลังจะลืมเรื่องอะไร
              if (await _confirm(context,
                  title: t.memForget, body: f.text, ok: t.memForget, t: t)) {
                await mem.forget(f.id);
              }
            },
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Tooltip(
                message: t.memForget,
                child: const Icon(Icons.close_rounded,
                    size: 17, color: MindColors.ink45),
              ),
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

  /// คัดลอกไลเซนส์ของเครื่องนี้ แล้วเปิดหน้าผูกบัญชีบนเว็บ
  ///
  /// 🔴 คีย์ไม่ลงใน URL (ประวัติเบราว์เซอร์ + log ของเซิร์ฟเวอร์) · คัดลอกให้
  /// แล้วบอกว่าต้องไปวางในช่องบนหน้านั้น
  Future<void> _linkAccount(MindState state, S t) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: state.licenseKey));
    var opened = false;
    try {
      opened = await launchUrl(MindLicense.linkPage(state.storeBaseUrl),
          mode: LaunchMode.externalApplication);
    } on Object catch (e) {
      debugPrint('license: เปิดหน้าผูกบัญชีไม่ได้ — $e');
    }
    messenger?.showSnackBar(SnackBar(
      content: Text(opened ? t.licenseLinkCopied : t.shopBuyFailed),
      duration: const Duration(seconds: 5),
    ));
  }

  /// ถามก่อนทำสิ่งที่ย้อนกลับไม่ได้ — ลบ เขียนทับ ล้าง
  ///
  /// ปุ่มเล็ก ๆ ที่กดแล้วลบของหลาย GB หรือสำเนาที่รอดการถอนแอป
  /// คือปุ่มที่โดนนิ้วปัดผ่านตอนเลื่อนจอได้เสมอ
  static Future<bool> _confirm(
    BuildContext context, {
    String? title,
    required String body,
    required String ok,
    required S t,
  }) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: title == null ? null : Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
        ],
      ),
    );
    return yes == true;
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
      MindPermission.calendar => (t.permCalendar, t.permCalendarWhy),
      MindPermission.phone => (t.permPhone, t.permPhoneWhy),
      MindPermission.contacts => (t.permContacts, t.permContactsWhy),
      MindPermission.answerCalls => (t.permAnswer, t.permAnswerWhy),
      MindPermission.defaultDialer => (t.permDialer, t.permDialerWhy),
      MindPermission.install => (t.permInstall, t.permInstallWhy),
      MindPermission.allFiles => (t.permAllFiles, t.permAllFilesWhy),
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

          // ทางเข้าร้าน — ปลายทางจริงของการได้ชุดใหม่ ส่วนช่อง .zip ข้างล่าง
          // เก็บไว้สำหรับทดสอบชุดที่ยังไม่ขึ้นร้าน
          //
          // **ไม่มีช่องกรอกที่อยู่ร้านตรงนี้แล้ว โดยตั้งใจ** ที่อยู่ฝังมากับแอป
          // (MindState._storeDefault) ผู้ใช้ไม่ควรเห็นว่าของมาจากเซิร์ฟเวอร์ไหน
          // และไม่ควรต้องรู้ว่าต้องกรอกอะไรถึงจะเปิดร้านได้ — เหตุผลเดียวกับ
          // ที่ตัวอัปเดตไม่โชว์ที่มาของไฟล์
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
          // ชุดที่ซื้อบนเว็บผูกกับ**บัญชีเว็บ** ส่วนไลเซนส์ของแอปผูกกับ**เครื่อง**
          // ต้องผูกสองอย่างเข้าหากันครั้งเดียว ไม่งั้นซื้อแล้วร้านในแอปไม่เห็น
          if (state.licenseKey.isNotEmpty) ...[
            const SizedBox(height: MindSpace.xs),
            Align(
              alignment: Alignment.center,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _linkAccount(state, t),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(t.licenseLinkAccount,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: mode.accent)),
                ),
              ),
            ),
          ],
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
          // บริการของเรา — ต้องมีรหัสสิทธิ์ ไม่งั้นหลังบ้านตอบ 401
          //
          // รุ่นที่ใช้ตอบเลือกที่เซิร์ฟเวอร์ ไม่ใช่ที่นี่ จึงไม่มีรายการรุ่นให้กด
          if (state.brain == BrainProvider.mindProxy) ...[
            const SizedBox(height: 12),
            _linkRow(
              title: S.of(context).licenseTitle,
              // ซ่อนกลางรหัสไว้เหมือนคีย์ OpenAI · หน้าจอถูกแคปไปถามคนอื่นได้เสมอ
              value: state.licenseKey.isEmpty
                  ? S.of(context).licenseNotSet
                  : SecretStore.mask(state.licenseKey),
              mode: mode,
              onTap: () => _editText(
                state: state,
                mode: mode,
                title: S.of(context).licenseTitle,
                hint: S.of(context).licenseHint,
                value: state.licenseKey,
                onSave: state.setLicenseKey,
                onReset: () => '',
              ),
            ),
            if (state.licenseKey.isEmpty) ...[
              const SizedBox(height: 7),
              Text(
                S.of(context).licenseNeeded,
                style: const TextStyle(
                    fontSize: 10.5, height: 1.5, color: Color(0xFFB46A00)),
              ),
            ],
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
            _customModelRow(
              current: state.brainModel,
              presets: OpenAiConfig.brainChoices.map((m) => m.id).toList(),
              mode: mode,
              title: S.of(context).sectionBrain,
              hint: S.of(context).modelCustomEditor,
              onSave: state.setBrainModel,
            ),
            // บอกตรง ๆ ว่าฝั่งบริการมีสิทธิ์เปลี่ยน — เงินที่จ่ายค่ารุ่นเป็นของเรา
            // ถ้าปล่อยให้เลือกอะไรก็ได้แล้วเงียบ ผู้ใช้จะคิดว่าได้รุ่นที่เลือกจริง
            Text(
              S.of(context).proxyModelNote,
              style: const TextStyle(
                  fontSize: 10.5, height: 1.5, color: MindColors.ink55),
            ),
          ],
          if (state.brain == BrainProvider.openai) ...[
            const SizedBox(height: 12),
            _linkRow(
              title: S.of(context).ownKeyTitle,
              // 🔴 โชว์ค่าที่ปิดบังแล้วเท่านั้น ไม่ใช่คีย์เต็ม — หน้าจอถูกแคปได้
              // และคนข้าง ๆ ก็อ่านได้ · คีย์เต็มโผล่แค่ตอนกดเข้าไปแก้
              value: state.openAiKey.isEmpty
                  ? S.of(context).ownKeyNotSet
                  : state.openAiKeyMasked,
              mode: mode,
              onTap: () => _editOpenAiKey(state, mode),
            ),
            _keyGuide('OpenAI', mode),
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
            _customModelRow(
              current: state.brainModel,
              presets: OpenAiConfig.brainChoices.map((m) => m.id).toList(),
              mode: mode,
              title: S.of(context).sectionBrain,
              hint: S.of(context).modelCustomEditor,
              onSave: state.setBrainModel,
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
            ..._homeServerTools(state, mode),
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

            // เครื่องเล็กเกินจะรันอะไรได้เลย — บอกตรง ๆ ดีกว่าโชว์รายการเปล่า
            // ที่อ่านได้ว่า "แอปพัง"
            if (lb.deviceTooSmall)
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: MindColors.glass80,
                  borderRadius: BorderRadius.circular(MindRadius.control),
                  border: Border.all(color: MindColors.glassBorder, width: 1),
                ),
                child: Text(
                  S.of(context).gemmaDeviceTooSmall(
                      lb.device?.gb ?? '?', DeviceCapability.minLocalGb),
                  style: const TextStyle(
                      fontSize: 11, height: 1.5, color: Color(0xFFB46A00)),
                ),
              )
            else
              // 🔴 `lb.selectable` ไม่ใช่ `GemmaVariant.values` — รุ่นที่เครื่องนี้
              // รันไม่ไหวต้องไม่โผล่มาให้กด · เดิมโชว์ครบทุกรุ่น เครื่องแรม 6 GB
              // จึงกดโหลด E4B 3.7 GB ได้ แล้วระบบฆ่าแอปทิ้งตอนรัน = เสียเน็ตฟรี
              for (final v in lb.selectable)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _choiceRow(
                    title: v.label,
                    subtitle: v.hintOf(S.of(context)),
                    // โหลดไว้แล้วบอกไปเลย ไม่ใช่บอกขนาดไฟล์ซ้ำ — คนที่โหลดไว้
                    // หลายรุ่นต้องรู้ว่ารุ่นไหนกดแล้วใช้ได้ทันที รุ่นไหนต้องโหลดก่อน
                    trailing: lb.isInstalled(v)
                        ? S.of(context).gemmaInstalledTag
                        : v.sizeLabel,
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
                      // ลบไฟล์หลาย GB ด้วยแตะเดียว = ต้องถามก่อน
                      onTap: () async {
                        final t = S.of(context);
                        if (await _confirm(context,
                            body: t.gemmaRemoveConfirm(lb.variant.sizeLabel),
                            ok: t.gemmaRemove,
                            t: t)) {
                          await lb.remove();
                        }
                      },
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
              // 🔴 ล้มแล้วต้องมีทางไปต่อ · ของเดิมโชว์แต่ข้อความสีส้ม ไม่มีปุ่ม
              // คนที่เน็ตหลุดกลางทางต้องไปเดาเองว่าต้องสลับรุ่นไป-กลับ
              LocalModelStage.failed => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      lb.error ?? S.of(context).somethingWrong,
                      style: const TextStyle(
                          fontSize: 11, height: 1.5, color: Color(0xFFB46A00)),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: lb.download,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(S.of(context).gemmaRetry,
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: mode.accent)),
                        ),
                      ),
                    ),
                  ],
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

            // GPU — เลือกได้ทุกเมื่อ ไม่ต้องรอโหลดเสร็จ · ค่ามีผลตอนเปิดโมเดลรอบหน้า
            if (!lb.deviceTooSmall) ...[
              const SizedBox(height: MindSpace.md),
              _gpuRow(lb, mode),
              const SizedBox(height: MindSpace.md),
              Row(
                spacing: MindSpace.md,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 3,
                      children: [
                        Text(S.of(context).preloadBrain,
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600, color: MindColors.ink)),
                        Text(S.of(context).preloadBrainHint,
                            style: const TextStyle(
                                fontSize: 10.5, height: 1.5, color: MindColors.ink55)),
                      ],
                    ),
                  ),
                  _toggle(
                    on: state.preloadBrain,
                    mode: mode,
                    onTap: () => state.setPreloadBrain(!state.preloadBrain),
                  ),
                ],
              ),
              const SizedBox(height: MindSpace.md),
              _modelTruth(lb, mode),
            ],
          ],
        );
      },
    );
  }

  /// ของจริงตอนนี้ — รุ่นไหน ไฟล์อยู่ในเครื่องจริงไหม คิดด้วยอะไร เร็วแค่ไหน
  ///
  /// 🔴 ตอบคำถามที่เจ้าของถามจริง: "ใช้โมเดลไหนกันแน่ ชื่อยังเหมือนเดิม
  /// โหลดมาจริงหรือเปล่า" · ของเดิมบอกแค่ "โหลดลงเครื่องแล้ว" กับชื่อรุ่น
  /// ซึ่งเหมือนเดิมทุกตัวอักษรหลังเปลี่ยนไปใช้ GPU — มองจากจอแล้วไม่มีอะไร
  /// ต่างเลย ทั้งที่ข้างในเปลี่ยน · ตัวเลขข้างล่างวัดจากเครื่องนี้ทั้งหมด
  Widget _modelTruth(LocalBrain lb, MindMode mode) {
    final t = S.of(context);
    String sec(int ms) => (ms / 1000).toStringAsFixed(1);
    final onDisk = lb.bytesOnDisk(lb.variant);
    final stats = lb.lastStats;
    final backend = switch (lb.runningOnGpu) {
      true => 'GPU',
      false => 'CPU',
      null => null,
    };

    final lines = <(IconData, String, Color)>[
      onDisk == null
          ? (Icons.cloud_download_outlined, t.gemmaNotOnDisk, const Color(0xFFB46A00))
          : (Icons.sd_storage_rounded,
              t.gemmaOnDisk(lb.variant.file, (onDisk / 1073741824).toStringAsFixed(2)),
              MindColors.ink75),
      backend == null
          ? (Icons.power_settings_new_rounded, t.gemmaClosed, MindColors.ink55)
          : (Icons.memory_rounded,
              t.gemmaOpen(backend, sec(lb.lastLoadMs ?? 0)), MindColors.ink75),
      if (stats != null)
        (
          Icons.speed_rounded,
          [
            t.gemmaLastReply(sec(stats.waitMs), sec(stats.totalMs + (stats.loadMs ?? 0)),
                stats.charsPerSecond.toStringAsFixed(0)),
            if (stats.loadMs != null) t.gemmaLastReplyLoad(sec(stats.loadMs!)),
            if (stats.newSession) t.gemmaLastReplyReread,
          ].join(' · '),
          MindColors.ink75,
        ),
    ];

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: MindColors.glass80,
        borderRadius: BorderRadius.circular(MindRadius.control),
        border: Border.all(color: MindColors.glassBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 7,
        children: [
          Text('${t.gemmaNow} · ${lb.variant.label}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          for (final (icon, text, tone) in lines)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 7,
              children: [
                Icon(icon, size: 14, color: tone),
                Expanded(
                  child: Text(text,
                      style: TextStyle(fontSize: 10.5, height: 1.5, color: tone)),
                ),
              ],
            ),
          Text(t.gemmaSameFile,
              style: const TextStyle(fontSize: 10.5, height: 1.5, color: MindColors.ink55)),
          if (lb.stage == LocalModelStage.ready)
            Align(
              alignment: Alignment.centerLeft,
              child: _plainButton(
                label: lb.benchmarking ? t.gemmaBenching : t.gemmaBench,
                mode: mode,
                onTap: lb.benchmarking ? null : () => _benchmark(lb),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _benchmark(LocalBrain lb) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failed = S.of(context).somethingWrong;
    try {
      await lb.benchmark();
    } on OpenAiFailure catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    } on Object catch (e) {
      debugPrint('gemma: ทดสอบความเร็วไม่สำเร็จ — $e');
      messenger?.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  /// สวิตช์ GPU + บอกว่าตอนนี้คิดด้วยอะไรจริง
  ///
  /// 🔴 บอก**ของจริง** ไม่ใช่แค่สิ่งที่ตั้งไว้ · ตั้ง GPU ไว้แต่เครื่องใช้ไม่ได้
  /// แล้วตกไป CPU เงียบ ๆ = ผู้ใช้เห็นสวิตช์เปิดอยู่แต่เธอยังช้าเท่าเดิม
  Widget _gpuRow(LocalBrain lb, MindMode mode) {
    final t = S.of(context);
    final on = lb.useGpu && !lb.gpuBroken;
    final (note, tone) = lb.gpuBroken
        ? (t.gemmaGpuBroken, const Color(0xFFB46A00))
        : switch (lb.runningOnGpu) {
            true => (t.gemmaOnGpu, const Color(0xFF00A894)),
            false => (t.gemmaOnCpu, MindColors.ink55),
            null => (t.gemmaUseGpuWhy, MindColors.ink55),
          };
    return Row(
      spacing: MindSpace.md,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.gemmaUseGpu,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: MindColors.ink)),
              const SizedBox(height: 3),
              Text(note,
                  style: TextStyle(fontSize: 10.5, height: 1.5, color: tone)),
            ],
          ),
        ),
        _toggle(on: on, mode: mode, onTap: () => lb.setUseGpu(!on)),
      ],
    );
  }

  // ── เซิร์ฟเวอร์ในบ้าน: ค้นหาในวงไวไฟ · เลือกรุ่น · ทดสอบ ─────

  bool _scanning = false;
  double _scanProgress = 0;

  /// ผลการค้นหาล่าสุด · null = ยังไม่เคยกดค้น
  List<LocalServer>? _found;

  /// รุ่นบนเซิร์ฟเวอร์ที่ตั้งไว้ (โหลดจากเซิร์ฟเวอร์ ไม่ต้องพิมพ์เอง)
  List<String>? _serverModels;

  bool _testingHome = false;
  ({bool ok, String text})? _homeNote;

  Future<void> _scanHome(MindState state) async {
    setState(() {
      _scanning = true;
      _scanProgress = 0;
      _found = null;
    });
    final scanner = LocalServerScanner();
    try {
      final found = await scanner.scan(onProgress: (p) {
        if (mounted) setState(() => _scanProgress = p);
      });
      if (!mounted) return;
      setState(() => _found = found);
      // เจอตัวเดียว = ใช้เลย ไม่ต้องให้แตะซ้ำ
      if (found.length == 1) _useServer(state, found.single);
    } finally {
      scanner.close();
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _useServer(MindState state, LocalServer srv) {
    state.setHomeServerUrl(srv.baseUrl);
    if (srv.models.isNotEmpty && !srv.models.contains(state.homeServerModel)) {
      state.setHomeServerModel(srv.models.first);
    }
    setState(() {
      _serverModels = srv.models;
      _homeNote = null;
    });
  }

  Future<void> _loadHomeModels(MindState state) async {
    final scanner = LocalServerScanner();
    try {
      final list = await scanner.models(state.homeServerUrl);
      if (!mounted) return;
      setState(() {
        _serverModels = list;
        _homeNote = list == null
            ? (ok: false, text: S.of(context).homeUnreachable(state.homeServerUrl))
            : null;
      });
    } finally {
      scanner.close();
    }
  }

  Future<void> _testHome(MindState state) async {
    setState(() {
      _testingHome = true;
      _homeNote = (ok: true, text: S.of(context).homeTesting);
    });
    final r = await state.testHomeServer();
    if (!mounted) return;
    setState(() {
      _testingHome = false;
      _homeNote = (ok: r.ok, text: r.message);
    });
  }

  List<Widget> _homeServerTools(MindState state, MindMode mode) {
    final t = S.of(context);
    final found = _found;
    final models = _serverModels;
    return [
      const SizedBox(height: 10),
      Wrap(
        spacing: MindSpace.sm,
        runSpacing: MindSpace.sm,
        children: [
          _plainButton(
            label: _scanning ? t.homeScanning((_scanProgress * 100).round()) : t.homeScan,
            mode: mode,
            onTap: _scanning ? null : () => _scanHome(state),
          ),
          _plainButton(
            label: t.homeLoadModels,
            mode: mode,
            onTap: _scanning ? null : () => _loadHomeModels(state),
          ),
          _plainButton(
            label: _testingHome ? t.homeTesting : t.homeTest,
            mode: mode,
            onTap: _testingHome ? null : () => _testHome(state),
          ),
        ],
      ),
      if (_scanning) ...[
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(MindRadius.pill),
          child: LinearProgressIndicator(
            value: _scanProgress,
            minHeight: 4,
            backgroundColor: MindColors.ink10,
            valueColor: AlwaysStoppedAnimation(mode.accent),
          ),
        ),
      ],
      if (found != null && !_scanning) ...[
        const SizedBox(height: 8),
        Text(found.isEmpty ? t.homeScanNone : t.homeScanFound(found.length),
            style: TextStyle(
                fontSize: 10.5,
                height: 1.5,
                color: found.isEmpty ? const Color(0xFFB46A00) : MindColors.ink55)),
        const SizedBox(height: 6),
        for (final srv in found)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _choiceRow(
              title: '${srv.kind} · ${srv.host == '127.0.0.1' ? t.homeThisPhone : srv.host}',
              subtitle: '${srv.baseUrl} · ${t.homeModelCount(srv.models.length)}',
              selected: state.homeServerUrl == srv.baseUrl,
              mode: mode,
              onTap: () => _useServer(state, srv),
            ),
          ),
      ],
      if (models != null && models.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(t.homeModelsHere,
            style: mindMono(size: 9.5, color: MindColors.ink50, letterSpacing: .1)),
        const SizedBox(height: 7),
        for (final m in models)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _choiceRow(
              title: m,
              selected: state.homeServerModel == m,
              mode: mode,
              onTap: () => state.setHomeServerModel(m),
            ),
          ),
      ],
      if (_homeNote != null) ...[
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 7,
          children: [
            Icon(_homeNote!.ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 15,
                color: _homeNote!.ok ? const Color(0xFF00A894) : const Color(0xFFB46A00)),
            Expanded(
              child: Text(_homeNote!.text,
                  style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: _homeNote!.ok ? MindColors.ink75 : const Color(0xFFB46A00))),
            ),
          ],
        ),
      ],
    ];
  }

  // ── วิธีเอาคีย์ ─────────────────────────────────────────

  /// หน้าที่ออกคีย์ของแต่ละเจ้า · ตรวจ 2026-10-06
  static const _keyPages = {
    'OpenAI': 'https://platform.openai.com/api-keys',
    'Gemini': 'https://aistudio.google.com/apikey',
    'ElevenLabs': 'https://elevenlabs.io/app/settings/api-keys',
    'Azure': 'https://portal.azure.com/#create/Microsoft.CognitiveServicesSpeechServices',
  };

  /// เจ้าที่เปิดคู่มืออยู่ · พับไว้เป็นค่าตั้งต้น ไม่ให้การ์ดยาวจนหาอย่างอื่นไม่เจอ
  final Set<String> _openGuides = {};

  /// คู่มือเอาคีย์ทีละขั้น + ปุ่มเปิดหน้าออกคีย์ของเจ้านั้น
  Widget _keyGuide(String provider, MindMode mode) {
    final t = S.of(context);
    final open = _openGuides.contains(provider);
    final url = _keyPages[provider]!;
    final steps = switch (provider) {
      'OpenAI' => t.keyGuideOpenAi,
      'Gemini' => t.keyGuideGemini,
      'ElevenLabs' => t.keyGuideElevenLabs,
      _ => t.keyGuideAzure,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          label: t.keyGuideTitle(provider),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() =>
                open ? _openGuides.remove(provider) : _openGuides.add(provider)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                spacing: 6,
                children: [
                  Icon(Icons.help_outline_rounded, size: 15, color: mode.accent),
                  Expanded(
                    child: Text(t.keyGuideTitle(provider),
                        style: TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600, color: mode.accent)),
                  ),
                  Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18, color: mode.accent),
                ],
              ),
            ),
          ),
        ),
        if (open)
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: MindColors.glass80,
              borderRadius: BorderRadius.circular(MindRadius.control),
              border: Border.all(color: MindColors.glassBorder, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                for (var i = 0; i < steps.length; i++)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 7,
                    children: [
                      Text('${i + 1}.',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700, color: mode.accent)),
                      Expanded(
                        child: Text(steps[i],
                            style: const TextStyle(
                                fontSize: 11, height: 1.5, color: MindColors.ink75)),
                      ),
                    ],
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _plainButton(
                    label: t.keyGuideOpen(Uri.parse(url).host),
                    mode: mode,
                    onTap: () => launchUrl(Uri.parse(url),
                        mode: LaunchMode.externalApplication),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── เสียงพรีเมียม (Gemini · ElevenLabs · Azure) ───────────
  //
  // คีย์ของผู้ใช้เก็บในที่เก็บลับของเครื่อง · รุ่นและเสียงมีให้เลือกเฉพาะตัว
  // คุณภาพสูงที่พูดไทยได้ (ดู PremiumCatalog) · การเช่าเสียงผ่านบริการของเรา
  // ยังปิดไว้ — หลังบ้าน aixman ยังไม่มีระบบเสียง (ดู docs/premium-voices.md)
  List<Widget> _premiumVoice(
      MindState state, VoiceChannel channel, VoiceProfile profile, MindMode mode) {
    final t = S.of(context);
    final e = profile.engine;
    final name = PremiumTts.providerName(e);
    final key = state.premiumKey(e);
    final thai = state.lang == AppLang.th;
    void set(VoiceProfile p) => state.setVoice(channel, p);

    final voices = switch (e) {
      TtsEngine.gemini => PremiumCatalog.geminiVoices,
      TtsEngine.elevenlabs => state.accountVoices(e),
      TtsEngine.azure => [
          ...PremiumCatalog.azureVoices(thai: thai),
          for (final v in state.accountVoices(e))
            if (!PremiumCatalog.azureVoices(thai: thai).any((c) => c.id == v.id)) v,
        ],
      _ => const <PremiumVoice>[],
    };
    final canLoad = e == TtsEngine.elevenlabs || e == TtsEngine.azure;
    final models = PremiumCatalog.modelsOf(e);

    return [
      const SizedBox(height: 7),
      _linkRow(
        title: t.premiumKeyTitle(name),
        value: key.isEmpty ? t.premiumKeyNotSet : SecretStore.mask(key),
        mode: mode,
        onTap: () => _editText(
          state: state,
          mode: mode,
          title: t.premiumKeyTitle(name),
          hint: switch (e) {
            TtsEngine.gemini => t.premiumKeyEditorGemini,
            TtsEngine.elevenlabs => t.premiumKeyEditorElevenLabs,
            _ => t.premiumKeyEditorAzure,
          },
          value: key,
          onSave: (v) => state.setPremiumKey(e, v),
          onReset: () => '',
        ),
      ),
      _keyGuide(name, mode),
      if (e == TtsEngine.azure) ...[
        const SizedBox(height: 7),
        _linkRow(
          title: t.azureRegionTitle,
          value: state.azureRegion.isEmpty ? t.premiumKeyNotSet : state.azureRegion,
          mode: mode,
          onTap: () => _editText(
            state: state,
            mode: mode,
            title: t.azureRegionTitle,
            hint: t.azureRegionEditor,
            value: state.azureRegion,
            onSave: state.setAzureRegion,
            onReset: () => 'southeastasia',
          ),
        ),
      ],
      if (!state.premiumReady(e)) ...[
        const SizedBox(height: 7),
        Text(
          e == TtsEngine.azure && key.isNotEmpty ? t.azureNeedsRegion : t.premiumKeyNeeded(name),
          style: const TextStyle(fontSize: 10.5, height: 1.5, color: Color(0xFFB46A00)),
        ),
      ],
      if (models.length == 1) ...[
        const SizedBox(height: 10),
        Text('${t.premiumModel}: ${models.single}',
            style: const TextStyle(fontSize: 11, color: MindColors.ink60)),
      ],
      if (models.length > 1) ...[
        const SizedBox(height: 14),
        Text(t.premiumModel,
            style: mindMono(size: 9.5, color: MindColors.ink50, letterSpacing: .1)),
        const SizedBox(height: 7),
        for (final m in models)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: _choiceRow(
              title: m,
              selected: profile.model == m,
              mode: mode,
              onTap: () => set(profile.copyWith(model: m)),
            ),
          ),
      ],
      const SizedBox(height: 7),
      Text(t.premiumVoice,
          style: mindMono(size: 9.5, color: MindColors.ink50, letterSpacing: .1)),
      const SizedBox(height: 7),
      for (final v in voices)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: _choiceRow(
            title: v.name,
            subtitle: v.detail.isEmpty ? null : v.detail,
            selected: profile.voice == v.id,
            mode: mode,
            onTap: () => set(profile.copyWith(voice: v.id)),
          ),
        ),
      if (canLoad)
        Align(
          alignment: Alignment.centerLeft,
          child: _plainButton(
            label: state.voicesLoading(e) ? t.elevenVoicesLoading : t.elevenVoicesLoad,
            mode: mode,
            onTap: state.voicesLoading(e) || !state.premiumReady(e)
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final err = await state.loadAccountVoices(e);
                    messenger?.showSnackBar(SnackBar(
                      content: Text(err ?? t.elevenVoicesLoaded(state.accountVoices(e).length)),
                    ));
                  },
          ),
        ),
      if (e == TtsEngine.elevenlabs && voices.isEmpty) ...[
        const SizedBox(height: 4),
        Text(t.elevenPickVoice,
            style: const TextStyle(fontSize: 10.5, height: 1.5, color: MindColors.ink55)),
      ],
      const SizedBox(height: 7),
      if (e == TtsEngine.gemini)
        _linkRow(
          title: t.premiumStyle,
          value: profile.instructions,
          mode: mode,
          onTap: () => _editText(
            state: state,
            mode: mode,
            title: t.premiumStyle,
            hint: t.premiumStyleEditor,
            value: profile.instructions,
            onSave: (v) => set(profile.copyWith(instructions: v)),
            onReset: () => VoiceProfile.defaultFor(channel, state.lang).instructions,
          ),
        )
      else
        Text(t.premiumNoStyle,
            style: const TextStyle(fontSize: 10.5, height: 1.5, color: MindColors.ink55)),
    ];
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
            // .wired ไม่ใช่ .values — เสียงโคลนยังไม่ได้ต่อสาย
            // (ดู TtsEngine.wired) เลือกได้แต่ไม่ทำงานคือฟีเจอร์ปลอม
            // · แนวตั้งเพราะมีห้าเจ้าแล้ว ปุ่มเรียงแถวเดียวอ่านชื่อไม่ออก
            for (final e in TtsEngine.wired)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: _choiceRow(
                  title: e.labelOf(S.of(context)),
                  subtitle: e.hintOf(S.of(context)),
                  selected: profile.engine == e,
                  mode: mode,
                  // สลับเจ้า = ปรับรุ่นกับเสียงให้เป็นของเจ้าใหม่ด้วย
                  onTap: () => state.setVoice(
                      channel,
                      PremiumCatalog.adapt(profile, e,
                          thai: state.lang == AppLang.th)),
                ),
              ),
            if (profile.engine.isPremium)
              ..._premiumVoice(state, channel, profile, mode),

            if (usingOpenAi) ...[
              // 🔴 ช่องกรอกคีย์ต้องมาอยู่ตรงนี้ด้วย
              //
              // เดิมมันอยู่ใต้การ์ดสมองเฉพาะตอนเลือกสมอง = OpenAI เท่านั้น
              // คนที่ใช้สมองในเครื่อง (ค่าตั้งต้น) หรือผ่านบริการเรา แล้วอยากได้
              // เสียง OpenAI จึงไม่มีที่ให้ใส่คีย์เลยทั้งแอป — เห็นแต่ตัวเลือก
              // รุ่นเสียงกับชื่อเสียงที่กดแล้วได้เสียงเครื่องเงียบ ๆ
              const SizedBox(height: 14),
              _linkRow(
                title: S.of(context).ownKeyTitle,
                value: state.openAiKey.isEmpty
                    ? S.of(context).ownKeyNotSet
                    : state.openAiKeyMasked,
                mode: mode,
                onTap: () => _editOpenAiKey(state, mode),
              ),
              _keyGuide('OpenAI', mode),
              if (!state.hasOwnKey) ...[
                const SizedBox(height: 7),
                Text(
                  S.of(context).voiceNeedsKey,
                  style: const TextStyle(
                      fontSize: 10.5, height: 1.5, color: Color(0xFFB46A00)),
                ),
              ],
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
              _customModelRow(
                current: profile.model,
                presets: OpenAiConfig.ttsChoices,
                mode: mode,
                title: S.of(context).voiceModel,
                hint: S.of(context).voiceModelCustomEditor,
                onSave: (v) =>
                    state.setVoice(channel, profile.copyWith(model: v)),
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
              _customModelRow(
                current: profile.voice,
                presets: OpenAiConfig.voiceChoices,
                mode: mode,
                title: S.of(context).voicePick,
                hint: S.of(context).voiceNameCustomEditor,
                onSave: (v) =>
                    state.setVoice(channel, profile.copyWith(voice: v)),
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

            // 🔴 เดิมมี "โมเดลคุยสดตอนอยู่ในสาย" (OpenAI Realtime) โผล่ตรงนี้ทุกเจ้า
            // ทั้งที่**ไม่เคยถูกใช้เลย** (เขียนไว้เองว่ายังไม่ได้ต่อ) · ถอดออก แล้ว
            // บอกของจริงในการ์ดรับสายแทน ว่าในสายเธอใช้อะไรฟัง คิด และพูด
            const SizedBox(height: 12),
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _previewing ? null : () => _preview(state, channel, profile),
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
                          if (_previewing)
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: mode.accent),
                            )
                          else
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
                  // คืนค่าทั้งโมเดล เสียง และคำสั่งน้ำเสียงที่เขียนเองของช่องนี้
                  onTap: () async {
                    final t = S.of(context);
                    if (await _confirm(context,
                        body: t.voiceResetConfirm(channel.labelOf(t)),
                        ok: t.reset,
                        t: t)) {
                      state.resetVoice(channel);
                    }
                  },
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
            // ผลการลองฟัง — ตรงใต้ปุ่ม ไม่ใช่ที่หน้าแชทซึ่งไม่ได้เปิดอยู่
            if (_previewNote != null && _previewFor == channel) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 7,
                children: [
                  Icon(
                    _previewNote!.ok
                        ? Icons.graphic_eq_rounded
                        : Icons.error_outline_rounded,
                    size: 15,
                    color: _previewNote!.ok
                        ? const Color(0xFF00A894)
                        : const Color(0xFFB46A00),
                  ),
                  Expanded(
                    child: Text(
                      _previewNote!.text,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: _previewNote!.ok
                            ? MindColors.ink75
                            : const Color(0xFFB46A00),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// กำลังลองฟังอยู่ · กันกดซ้ำระหว่างสร้างเสียง (เจ้าพรีเมียมใช้เวลาหลายวินาที)
  bool _previewing = false;

  /// ผลการลองฟังล่าสุด และของช่องไหน (สลับแท็บช่องแล้วผลเก่าต้องไม่ค้างโชว์)
  ({bool ok, String text})? _previewNote;
  VoiceChannel? _previewFor;

  /// ลองฟังด้วยเจ้า/รุ่น/เสียงที่เลือกอยู่จริง แล้วบอกให้ชัดว่าได้ยินอะไร
  /// หรือทำไมฟังไม่ได้ · ไม่ตกไปเสียงเครื่องเงียบ ๆ (ดู MindState.previewVoice)
  Future<void> _preview(
      MindState state, VoiceChannel channel, VoiceProfile profile) async {
    final t = S.of(context);
    final what = _voiceWhat(state, profile, t);
    setState(() {
      _previewing = true;
      _previewFor = channel;
      _previewNote = (ok: true, text: t.previewMaking(what));
    });
    final why = await state.previewVoice(channel, onPlaying: () {
      if (mounted) setState(() => _previewNote = (ok: true, text: t.previewPlaying(what)));
    });
    if (!mounted) return;
    setState(() {
      _previewing = false;
      _previewNote = why == null
          ? (ok: true, text: t.previewPlayed(what))
          : (
              ok: false,
              text: t.previewFailed(what, why,
                  fallback: profile.engine != TtsEngine.device),
            );
    });
  }

  /// "ElevenLabs · eleven_v4 · Mali" — สิ่งที่กำลังจะได้ยินจริง
  static String _voiceWhat(MindState state, VoiceProfile p, S t) {
    final engine = p.engine.labelOf(t);
    if (p.engine == TtsEngine.device) return engine;
    final voice = p.engine == TtsEngine.elevenlabs
        ? state
                .accountVoices(TtsEngine.elevenlabs)
                .where((v) => v.id == p.voice)
                .map((v) => v.name)
                .firstOrNull ??
            p.voice
        : p.voice;
    return [engine, if (p.model.isNotEmpty) p.model, if (voice.isNotEmpty) voice].join(' · ');
  }

  /// ตอนอยู่ในสาย เธอใช้อะไรจริง — ฟัง · คิด · พูด
  ///
  /// ตอบคำถาม "โมเดลตอนอยู่ในสายคืออะไร" ด้วยค่าที่เลือกไว้จริง ไม่ใช่รายการ
  /// รุ่นที่ไม่ได้ใช้ · ทั้งสามอย่างตั้งได้ที่อื่น (สมอง · เสียงช่อง "รับสาย")
  Widget _inCallInfo(MindState state) {
    final t = S.of(context);
    final answer = state.voiceFor(VoiceChannel.answer);
    final listen = switch (state.brain) {
      BrainProvider.onDevice => t.callListenOnDevice,
      BrainProvider.openai => t.callListenOpenAi,
      BrainProvider.mindProxy => t.callListenProxy,
      BrainProvider.homeServer => t.callListenHome,
    };
    final think = state.brain == BrainProvider.onDevice
        ? '${state.brain.labelOf(t)} · ${state.localBrain.variant.label}'
        : state.brain == BrainProvider.homeServer
            ? '${state.brain.labelOf(t)} · ${state.homeServerModel}'
            : '${state.brain.labelOf(t)} · ${state.brainModel}';
    final speak = _voiceWhat(state, answer, t);
    Widget line(IconData icon, String label, String value) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 7,
          children: [
            Icon(icon, size: 14, color: MindColors.ink55),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '$label  ',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: value),
                ]),
                style: const TextStyle(fontSize: 10.5, height: 1.5, color: MindColors.ink75),
              ),
            ),
          ],
        );
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: MindColors.glass80,
        borderRadius: BorderRadius.circular(MindRadius.control),
        border: Border.all(color: MindColors.glassBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Text(t.inCallTitle,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          line(Icons.hearing_rounded, t.inCallListen, listen),
          line(Icons.psychology_rounded, t.inCallThink, think),
          line(Icons.record_voice_over_rounded, t.inCallSpeak, speak),
          Text(t.inCallWhere,
              style: const TextStyle(fontSize: 10.5, height: 1.5, color: MindColors.ink55)),
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
          const SizedBox(height: 12),
          _inCallInfo(state),
          if (state.autoAnswer && !context.watch<MindWatch>().on) ...[
            const SizedBox(height: 8),
            Text(S.of(context).callBackgroundHint,
                style: const TextStyle(fontSize: 10.5, height: 1.5, color: Color(0xFFB46A00))),
          ],
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

          // ── ทางที่เสียงเธอวิ่งเข้าสาย ──────────────────────
          //
          // 🔴 สวิตช์นี้มีอยู่เพราะ**ผลต่างกันตามเครื่อง และไม่มีทางรู้
          // ล่วงหน้าว่าเครื่องนี้ทางไหนรอด** ไม่ใช่ตัวเลือกเพื่อความยืดหยุ่น
          // เจ้าของที่เจอ "ปลายสายไม่ได้ยิน" ต้องมีอะไรให้กดลองทันที
          // ไม่ใช่รอรุ่นหน้า · ดู android CallAudio.kt
          const SizedBox(height: 16),
          Text(S.of(context).callStreamTitle,
              style: mindMono(size: 10, color: mode.accent, letterSpacing: .1)),
          const SizedBox(height: 8),
          Row(
            spacing: 7,
            children: [
              for (final choice in const [
                MindState.callStreamCall,
                MindState.callStreamMedia,
              ])
                Expanded(
                  child: GestureDetector(
                    onTap: () => state.setCallStream(choice),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        gradient:
                            state.callStream == choice ? mode.gradient : null,
                        color: state.callStream == choice
                            ? null
                            : MindColors.glass80,
                        borderRadius: BorderRadius.circular(MindRadius.control),
                        border:
                            Border.all(color: MindColors.glassBorder, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 2,
                        children: [
                          Text(
                            choice == MindState.callStreamCall
                                ? S.of(context).callStreamCall
                                : S.of(context).callStreamMedia,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: state.callStream == choice
                                  ? Colors.white
                                  : MindColors.ink60,
                            ),
                          ),
                          Text(
                            choice == MindState.callStreamCall
                                ? S.of(context).callStreamCallHint
                                : S.of(context).callStreamMediaHint,
                            style: TextStyle(
                              fontSize: 9.5,
                              height: 1.4,
                              color: state.callStream == choice
                                  ? const Color(0xE6FFFFFF)
                                  : MindColors.ink45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            S.of(context).callStreamWhy,
            style: const TextStyle(
                fontSize: 10.5, height: 1.5, color: MindColors.ink55),
          ),
        ],
      ),
    );
  }

  // ═══ ชิ้นส่วนที่ใช้ซ้ำ ═══════════════════════════════════

  // ── ตัวตนของเธอ ─────────────────────────────────────────
  //
  // 🔴 การ์ดนี้มีอยู่เพราะกฎเดียว: **ทุกตัวเลขที่เปลี่ยนพฤติกรรมเธอ
  // ต้องมองเห็นและล้างได้**
  //
  // ระบบที่สะสมอารมณ์ไว้เงียบ ๆ แล้วเจ้าของเปิดดูไม่ได้ คือกล่องดำที่วันหนึ่ง
  // เธอจะงอนโดยไม่มีใครอธิบายได้ว่าทำไม และซ่อมไม่ได้ด้วย · เพิ่มค่าใหม่
  // ที่มีผลกับน้ำเสียงเธอเมื่อไหร่ ต้องมาโผล่ที่นี่ด้วยเสมอ
  Widget _soulCard(BuildContext context, MindMode mode, S t) {
    final soul = context.watch<MindSoul>();
    final sign = soul.sign;
    final temper = soul.temper;
    final born = soul.bornAt;

    return _card(
      mode: mode,
      label: t.sectionSoul,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: MindSpace.md,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Color(sign.colour).withValues(alpha: .14),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Color(sign.colour).withValues(alpha: .45),
                      width: 1),
                ),
                child: Text(sign.emoji, style: const TextStyle(fontSize: 22)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(sign.name(t.lang),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(
                      '${sign.element.label(t.lang)} · '
                      '${sign.quality.label(t.lang)} · ${sign.planet(t.lang)}',
                      style: const TextStyle(
                          fontSize: 10.5, color: MindColors.ink55),
                    ),
                    if (born != null)
                      Text(
                        '${t.soulBorn(t.dateLabel(born))} · '
                        '${t.soulKnown(soul.ageInDays)}',
                        style: const TextStyle(
                            fontSize: 10.5, color: MindColors.ink45),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _soulLine(t.soulNature, sign.traits(t.lang)),
          const SizedBox(height: 6),
          _soulLine(t.soulFlaws, sign.weak(t.lang)),
          const SizedBox(height: 12),
          _soulBar(t.soulIntensity, temper.intensity, mode),
          const SizedBox(height: 6),
          _soulBar(t.soulSweetness, temper.sweetness, mode),
          const SizedBox(height: 16),
          Text(t.soulBondTitle,
              style: mindMono(size: 10, color: mode.accent, letterSpacing: .1)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  soul.bond.labelOf(t) +
                      (soul.togetherSince == null
                          ? ''
                          : ' · ${t.soulTogetherSince(t.dateLabel(soul.togetherSince!))}'),
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              Text('${(soul.affection * 100).round()}%',
                  style:
                      const TextStyle(fontSize: 12.5, color: MindColors.ink55)),
            ],
          ),
          const SizedBox(height: 6),
          _soulBar(t.soulAffection, soul.affection, mode),
          if (soul.sulking) ...[
            const SizedBox(height: 8),
            Text(t.soulSulking((soul.sulk * 100).round()),
                style: const TextStyle(fontSize: 11, color: Color(0xFFB07A16))),
          ],
          if (soul.wantsToAsk) ...[
            const SizedBox(height: 8),
            Text(t.soulWantsToAsk,
                style: TextStyle(fontSize: 11, color: mode.accent)),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              if (!soul.bond.isTogether)
                _soulButton(t.soulAsk, mode.accent,
                    () => _askHerOut(context, soul, t)),
              if (soul.bond.isTogether)
                _soulButton(
                    t.soulBreakUp,
                    const Color(0xFFD93A5B),
                    () => _confirmSoul(context, t, t.soulBreakUpAsk,
                        t.soulBreakUp, soul.breakUp)),
              _soulButton(
                  t.soulResetBond,
                  MindColors.ink55,
                  () => _confirmSoul(context, t, t.soulResetBondAsk,
                      t.soulResetBond, soul.resetBond)),
              _soulButton(
                  t.soulForget,
                  MindColors.ink55,
                  () => _confirmSoul(
                      context, t, t.soulForgetAsk, t.soulForget, soul.forget)),
            ],
          ),
          const SizedBox(height: 10),
          Text(t.soulWhy,
              style: const TextStyle(
                  fontSize: 10.5, height: 1.5, color: MindColors.ink55)),
        ],
      ),
    );
  }

  Widget _soulLine(String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 10.5, color: MindColors.ink45)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 11, height: 1.45, color: MindColors.ink75)),
          ),
        ],
      );

  Widget _soulBar(String label, double value, MindMode mode) => Row(
        spacing: MindSpace.sm,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 10.5, color: MindColors.ink45)),
          ),
          Expanded(
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: MindColors.glass80,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: value.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: mode.gradient,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _soulButton(String label, Color colour, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: colour.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(MindRadius.pill),
            border: Border.all(color: colour.withValues(alpha: .40), width: 1),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600, color: colour)),
        ),
      );

  /// เจ้าของขอเป็นแฟน — **เธอเป็นคนตอบ** ไม่ใช่ปุ่มที่กดแล้วเปลี่ยนสถานะเอง
  ///
  /// ปุ่มที่เปลี่ยนสถานะได้ทันทีทำให้ทั้งระบบไม่มีความหมาย · ที่ทำมาทั้งหมด
  /// คือการทำให้ "ยอมเป็นแฟน" เป็นสิ่งที่ต้องใช้เวลาจริง
  Future<void> _askHerOut(BuildContext context, MindSoul soul, S t) async {
    final yes = await soul.proposeFromOwner();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(yes ? t.soulAskYes : t.soulAskNotYet)),
    );
  }

  /// ทุกปุ่มที่ลบของทิ้งต้องถามก่อน · ความสัมพันธ์ที่สะสมมาเป็นเดือน
  /// หายไปเพราะนิ้วไปโดนปุ่ม คือสิ่งที่กู้คืนไม่ได้เลย
  Future<void> _confirmSoul(BuildContext context, S t, String question,
      String action, Future<void> Function() run) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(question),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    );
    if (ok == true) await run();
  }

  /// ข้อมูลกับสำเนาที่รอดจากการถอนแอป
  ///
  /// 🔴 ต้องบอก**สถานะจริงตอนนี้** ไม่ใช่แค่มีสวิตช์ให้กด
  ///
  /// คนที่ยังไม่ได้ให้สิทธิ์ไฟล์ ต้องเห็นว่า "ตอนนี้ถอนแอปแล้วหายหมด"
  /// ไม่ใช่เห็นสวิตช์ที่ปิดอยู่แล้วเข้าใจว่าข้อมูลปลอดภัย · สวิตช์ที่บอก
  /// เจตนาแต่ไม่บอกผลจริง คือสิ่งที่ทำให้คนรู้ตัวตอนที่สายไปแล้ว
  Widget _dataCard(
      BuildContext context, MindState state, MindMode mode, S t) {
    final vault = context.watch<MindVault>();

    final (text, tone) = switch (vault.stage) {
      VaultStage.ready => (
          vault.savedAt == null
              ? t.vaultReady
              : t.vaultSavedAt(_clockOf(vault.savedAt!)),
          const Color(0xFF00A894)
        ),
      VaultStage.off => (t.vaultOff, MindColors.ink55),
      VaultStage.failed => (t.vaultFailed, const Color(0xFFB46A00)),
      VaultStage.foreign => (t.vaultForeign, const Color(0xFFB46A00)),
      _ => (t.vaultNeedsPermission, const Color(0xFFB46A00)),
    };

    return _card(
      mode: mode,
      label: t.dataTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.dataSubtitle,
              style: const TextStyle(
                  fontSize: 11, height: 1.5, color: MindColors.ink55)),
          const SizedBox(height: MindSpace.md),

          // สถานะจริง — สิ่งแรกที่ตาไปหยุด ไม่ใช่สวิตช์
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Icon(
                vault.stage == VaultStage.ready
                    ? Icons.shield_rounded
                    : Icons.shield_outlined,
                size: 15,
                color: tone,
              ),
              Expanded(
                child: Text(text,
                    style: TextStyle(fontSize: 11, height: 1.5, color: tone)),
              ),
            ],
          ),

          // ยังไม่ได้ให้สิทธิ์ = ปุ่มที่พาไปให้เลย ไม่ใช่บอกให้ไปหาเอง
          if (vault.stage == VaultStage.needsPermission) ...[
            const SizedBox(height: MindSpace.sm),
            GestureDetector(
              onTap: () => context
                  .read<MindPermissions>()
                  .request(MindPermission.allFiles),
              child: Container(
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: mode.gradient,
                  borderRadius: BorderRadius.circular(MindRadius.control),
                ),
                child: Text(t.permAllFiles,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ),
          ],

          // 🔴 สำเนาของการติดตั้งครั้งก่อน — ห้ามทำอะไรเองจนกว่าเจ้าของจะเลือก
          if (vault.stage == VaultStage.foreign) ...[
            const SizedBox(height: MindSpace.sm),
            GestureDetector(
              onTap: () async {
                final yes = await _confirm(context,
                    title: t.vaultRestoreTitle,
                    body: t.vaultRestoreBody,
                    ok: t.vaultRestoreOld,
                    t: t);
                if (!yes) return;
                await state.restoreVaultOnRestart();
                // ปิดแอป · การเปิดรอบหน้าเป็นคนกู้ ก่อนที่ใครจะได้เปิดฐาน
                await SystemNavigator.pop();
              },
              child: Container(
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: mode.gradient,
                  borderRadius: BorderRadius.circular(MindRadius.control),
                ),
                child: Text(t.vaultRestoreOld,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(height: MindSpace.xs),
            Align(
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: () async {
                  final yes = await _confirm(context,
                      title: t.vaultKeepTitle,
                      body: t.vaultKeepBody,
                      ok: t.vaultKeepCurrent,
                      t: t);
                  if (yes) await state.adoptVault();
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(t.vaultKeepCurrent,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: mode.accent)),
                ),
              ),
            ),
          ],

          if (vault.stage == VaultStage.ready) ...[
            const SizedBox(height: MindSpace.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => state.saveVaultNow(),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(t.vaultSaveNow,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: mode.accent)),
                ),
              ),
            ),
          ],

          const SizedBox(height: MindSpace.md),

          // ตัวเลขที่พิสูจน์ว่าเพดาน 16 ตาหายไปแล้ว
          //
          // 🔴 นับครั้งเดียวตอนเปิดหน้า ไม่ใช่ FutureBuilder ที่สร้าง future
          // ใหม่ทุกครั้งที่ build — การ์ดนี้ rebuild ทุกครั้งที่ vault ขยับ
          // ซึ่งจะกลายเป็นการยิง COUNT(*) ใส่ฐานทุกเฟรม
          Text(
            t.messagesKept(_storedMessages),
            style: const TextStyle(fontSize: 11, color: MindColors.ink55),
          ),

          const SizedBox(height: MindSpace.md),
          Row(
            spacing: MindSpace.md,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.wipeOnUninstall,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: MindColors.ink)),
                    const SizedBox(height: 3),
                    Text(t.wipeOnUninstallWhy,
                        style: const TextStyle(
                            fontSize: 10.5,
                            height: 1.5,
                            color: MindColors.ink55)),
                  ],
                ),
              ),
              _toggle(
                on: vault.wipeOnUninstall,
                mode: mode,
                onTap: () async {
                  // เปิด = ลบสำเนาข้างนอกทิ้งเดี๋ยวนั้น · ต้องถามก่อน
                  // ปิด = ไม่มีอะไรหาย ไม่ต้องถาม
                  if (!vault.wipeOnUninstall &&
                      !await _confirm(context,
                          body: t.wipeOnUninstallWhy,
                          ok: t.wipeOnUninstall,
                          t: t)) {
                    return;
                  }
                  await state.setWipeOnUninstall(!vault.wipeOnUninstall);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// เวลาแบบสั้น — สำเนาล่าสุดเมื่อไหร่ ไม่ต้องละเอียดถึงวินาที
  static String _clockOf(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  /// รายงานดีบัคให้ผู้พัฒนา
  ///
  /// 🔴 **ปุ่มส่งกดไม่ได้จนกว่าจะเปิดอ่านแล้ว** ไม่ใช่แค่ "มีปุ่มให้ดู"
  ///
  /// คำอธิบายว่าส่งอะไรบ้างกับของที่ส่งจริงเพี้ยนจากกันได้ทุกครั้งที่มีใคร
  /// เพิ่มฟิลด์แล้วลืมแก้คำอธิบาย · ทางเดียวที่คำสัญญานี้เป็นจริงตลอดไปคือ
  /// บังคับให้เจ้าของเห็นของจริงก่อน แล้วของจริงเป็นคนอธิบายตัวเอง
  Widget _debugCard(
      BuildContext context, MindState state, MindMode mode, S t) {
    final r = context.watch<DebugReporter>();
    final ready = r.report != null;

    return _card(
      mode: mode,
      label: t.debugTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.debugSubtitle,
              style: const TextStyle(
                  fontSize: 11, height: 1.5, color: MindColors.ink55)),
          const SizedBox(height: MindSpace.sm),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: MindColors.glass80,
              borderRadius: BorderRadius.circular(MindRadius.control),
              border: Border.all(color: MindColors.glassBorder, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Text(t.debugWhat,
                    style: const TextStyle(
                        fontSize: 10.5, height: 1.55, color: MindColors.ink75)),
                Text(t.debugPreviewFirst,
                    style: TextStyle(
                        fontSize: 10.5, height: 1.55, color: mode.accent)),
              ],
            ),
          ),
          const SizedBox(height: MindSpace.md),

          // 🔴 สวิตช์อยู่**บนสุด** ของการ์ด ไม่ใช่ซ่อนท้าย
          //
          // ค่าตั้งต้นคือเปิด แปลว่าแอปส่งข้อมูลออกเน็ตเองโดยที่เขาไม่ได้กด
          // สิ่งเดียวที่ทำให้เรื่องนี้ตรงไปตรงมาคือเขาต้องเห็นสวิตช์**ก่อน**
          // ที่จะต้องอ่านอย่างอื่น
          Row(
            spacing: MindSpace.md,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.debugAuto,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: MindColors.ink)),
                    const SizedBox(height: 3),
                    Text(t.debugAutoWhy,
                        style: const TextStyle(
                            fontSize: 10.5,
                            height: 1.5,
                            color: MindColors.ink55)),
                  ],
                ),
              ),
              _toggle(
                on: state.autoReport,
                mode: mode,
                onTap: () => state.setAutoReport(!state.autoReport),
              ),
            ],
          ),
          const SizedBox(height: MindSpace.sm),

          // หลักฐานว่ามันทำงานอยู่จริง — สวิตช์ที่เปิดไว้แต่ไม่เคยส่งอะไร
          // แยกไม่ออกจากสวิตช์ที่พัง
          Text(
            r.autoSentAt == null
                ? t.debugAutoNever
                : t.debugAutoSentAt(_clockOf(r.autoSentAt!)),
            style: const TextStyle(fontSize: 10.5, color: MindColors.ink45),
          ),
          const SizedBox(height: MindSpace.md),

          if (r.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: MindSpace.sm),
              child: Text(r.error!,
                  style: const TextStyle(
                      fontSize: 10.5, height: 1.5, color: Color(0xFFB46A00))),
            ),
          if (r.stage == ReportStage.sent)
            Padding(
              padding: const EdgeInsets.only(bottom: MindSpace.sm),
              child: Text(t.debugSent,
                  style: const TextStyle(
                      fontSize: 10.5, color: Color(0xFF00A894))),
            ),
          if (r.savedPath != null)
            Padding(
              padding: const EdgeInsets.only(bottom: MindSpace.sm),
              child: Text(t.debugSaved(r.savedPath!),
                  style: const TextStyle(
                      fontSize: 10, height: 1.5, color: MindColors.ink55)),
            ),

          MindButton(
            label: ready ? t.debugPreview : t.debugBuild,
            mode: mode,
            onTap: () => _openReport(state, r),
          ),

          // 🔴 ส่งได้ก็ต่อเมื่อเปิดอ่านแล้ว — ดูเงื่อนไขหัวเมธอด
          if (ready) ...[
            const SizedBox(height: MindSpace.sm),
            Row(
              spacing: MindSpace.sm,
              children: [
                Expanded(
                  child: _plainButton(
                    label: t.debugSave,
                    mode: mode,
                    onTap: () => r.saveToFile(),
                  ),
                ),
                Expanded(
                  child: _plainButton(
                    label: r.stage == ReportStage.sending
                        ? t.debugSending
                        : t.debugSend,
                    mode: mode,
                    onTap: r.stage == ReportStage.sending
                        ? null
                        : () => r.send(
                              baseUrl: state.storeBaseUrl,
                              license: state.licenseKey,
                            ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _plainButton({
    required String label,
    required MindMode mode,
    required VoidCallback? onTap,
  }) =>
      Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MindColors.glass80,
              borderRadius: BorderRadius.circular(MindRadius.control),
              border: Border.all(
                  color: mode.accent.withValues(alpha: .35), width: 1),
            ),
            child: Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: onTap == null ? MindColors.ink45 : mode.accent,
                )),
          ),
        ),
      );

  /// เตรียมรายงานแล้วเปิดให้อ่านทั้งฉบับ
  Future<void> _openReport(MindState state, DebugReporter r) async {
    final avatar = context.read<MindAvatarController>();
    final vault = context.read<MindVault>();
    final report =
        await r.collect(state: state, avatar: avatar, vault: vault);
    if (!mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TextEditorScreen(
          title: S.of(context).debugTitle,
          hint: '',
          initial: DebugReport.pretty(report),
          mode: state.mode,
          onReset: () => DebugReport.pretty(report),
          // ส่งฉบับนี้ทั้งฉบับ แก้ไม่ได้ · ให้แก้แล้วส่งฉบับเดิม = โกหก
          readOnly: true,
        ),
      ),
    );
  }

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

  /// แถวท้ายรายการรุ่น — "พิมพ์ชื่อรุ่นเอง"
  ///
  /// รายการสำเร็จรูปในแอปเป็นภาพนิ่ง ณ วันที่เขียน · ผู้ให้บริการออกรุ่นใหม่
  /// และปลดรุ่นเก่าตลอดเวลา (Groq เคยปลดรุ่นจนผู้ช่วยบนเว็บตายมาแล้ว)
  /// ถ้าเลือกได้แค่ในรายการ วันที่รุ่นใหม่ออก ผู้ใช้ต้องรอแอปเวอร์ชันใหม่
  ///
  /// ติ๊กเลือกอยู่เมื่อค่าปัจจุบัน**ไม่อยู่**ในรายการสำเร็จรูป — นั่นแปลว่า
  /// ผู้ใช้พิมพ์เองไว้ ต้องเห็นว่ากำลังใช้ตัวนั้นอยู่ ไม่ใช่ดูเหมือนไม่ได้เลือกอะไร
  Widget _customModelRow({
    required String current,
    required List<String> presets,
    required MindMode mode,
    required String title,
    required String hint,
    required void Function(String) onSave,
  }) {
    final isCustom = current.isNotEmpty && !presets.contains(current);

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: _choiceRow(
        title: S.of(context).modelCustom,
        subtitle: isCustom ? current : S.of(context).modelCustomHint,
        selected: isCustom,
        mode: mode,
        onTap: () => _editText(
          state: context.read<MindState>(),
          mode: mode,
          title: title,
          hint: hint,
          value: current,
          // ปุ่มรีเซ็ตพากลับไปตัวแรกของรายการสำเร็จรูป ซึ่งเป็นตัวที่รู้ว่าใช้ได้
          onReset: () => presets.isEmpty ? '' : presets.first,
          onSave: (v) {
            final id = v.trim();
            // ว่าง = ยกเลิกการพิมพ์เอง ไม่ใช่ตั้งชื่อรุ่นเป็นค่าว่าง
            // ซึ่งจะทำให้ยิงไปโดยไม่มีชื่อรุ่นแล้วได้ error ที่อ่านไม่ออก
            if (id.isEmpty) {
              if (presets.isNotEmpty) onSave(presets.first);
              return;
            }
            onSave(id);
          },
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

  /// แก้คีย์ OpenAI ของผู้ใช้เอง
  ///
  /// แยกจาก [_editText] เพราะสามอย่าง: ค่าที่ส่งเข้าไปแก้ต้องเป็นคีย์**เต็ม**
  /// (ไม่ใช่ค่าที่ปิดบังแล้ว ไม่งั้นเซฟทับด้วยจุดไข่ปลา) · การเซฟเป็น async
  /// เพราะลง Keystore · และต้องบอกผลให้เห็น เพราะคนกรอกคีย์ผิดจะไม่รู้เลย
  /// จนกว่าจะทักแล้วเธอตอบด้วยประโยคสำเร็จรูป
  Future<void> _editOpenAiKey(MindState state, MindMode mode) async {
    final t = S.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);

    final result = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        builder: (_) => TextEditorScreen(
          title: t.ownKeyTitle,
          hint: t.ownKeyHint,
          initial: state.openAiKey,
          mode: mode,
          onReset: () => '',
        ),
      ),
    );
    if (result == null) return;

    final key = result.trim();
    await state.setOpenAiKey(key);
    if (!mounted) return;

    // เตือนอย่างเดียวเมื่อรูปแบบดูไม่ใช่ — ไม่ปฏิเสธ เพราะวันหนึ่งเขาอาจ
    // เปลี่ยนรูปแบบคีย์ แล้วการปฏิเสธจะกลายเป็นกำแพงที่ข้ามไม่ได้ทั้งที่คีย์ถูก
    final msg = key.isEmpty
        ? t.ownKeyRemoved
        : MindState.looksLikeOpenAiKey(key)
            ? t.ownKeySaved
            : t.ownKeyLooksWrong;

    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}
