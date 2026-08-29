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
import '../state/mind_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';
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

class _SettingsScreenState extends State<SettingsScreen> {
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
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 14),
              child: Text(t.settingsTitle,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.2)),
            ),
            _languageCard(state, mode, t),
            const SizedBox(height: 11),
            if (!OpenAiConfig.configured) _noKeyBanner(),
            _modeCard(state, mode),
            const SizedBox(height: 11),
            _flirtCard(state, mode),
            const SizedBox(height: 11),
            _bubbleCard(state, mode),
            const SizedBox(height: 11),
            _brainCard(state, mode),
            const SizedBox(height: 11),
            _voiceCard(state, mode),
            const SizedBox(height: 11),
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
            const SizedBox(height: 11),
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
            const SizedBox(height: 11),
            _callCard(state, mode),
            const SizedBox(height: 11),
            _switchCard(mode),
            const SizedBox(height: 11),
            UpdateCard(mode: mode),
          ],
        ),
      ),
    );
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
          Text(label,
              style: mindMono(size: 10, color: mode.accent, letterSpacing: .1)),
          const SizedBox(height: 10),
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
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected ? mode.gradient : null,
          color: selected ? null : MindColors.glass80,
          borderRadius: BorderRadius.circular(MindRadius.control),
          border: Border.all(color: MindColors.glassBorder, width: 1),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
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
