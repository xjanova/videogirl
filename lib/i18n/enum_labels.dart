import '../ai/brain_provider.dart';
import '../ai/device_capability.dart';
import '../ai/local_brain.dart';
import '../ai/speech_service.dart';
import '../ai/voice_profile.dart';
import '../state/mind_state.dart';
import '../theme/tokens.dart';
import 'strings.dart';
import 'strings_ai.dart';

/// ป้ายชื่อของ enum ตามภาษา
///
/// enum เก็บ **ตัวตน** (ค่า id ที่บันทึกลงเครื่อง) ส่วนป้ายที่ผู้ใช้เห็นอยู่ที่นี่
/// ถ้าเอาข้อความไทยไปฝังใน enum ตรง ๆ จะแปลไม่ได้ และการเปลี่ยนคำที่แสดง
/// จะไปเปลี่ยนค่าที่บันทึกไว้ในเครื่องผู้ใช้ด้วย ซึ่งพังทันที
extension BrainProviderLabels on BrainProvider {
  String labelOf(S s) => switch (this) {
        BrainProvider.openai => s.brainOpenAi,
        BrainProvider.homeServer => s.brainHome,
        BrainProvider.onDevice => s.brainOnDevice,
      };

  String summaryOf(S s) => switch (this) {
        BrainProvider.openai => s.brainOpenAiSummary,
        BrainProvider.homeServer => s.brainHomeSummary,
        BrainProvider.onDevice => s.brainOnDeviceSummary,
      };

  String tradeoffOf(S s) => switch (this) {
        BrainProvider.openai => s.brainOpenAiTradeoff,
        BrainProvider.homeServer => s.brainHomeTradeoff,
        BrainProvider.onDevice => s.brainOnDeviceTradeoff,
      };
}

extension TtsEngineLabels on TtsEngine {
  String labelOf(S s) => switch (this) {
        TtsEngine.openai => s.ttsOpenAi,
        TtsEngine.device => s.ttsDevice,
        TtsEngine.clone => s.ttsClone,
      };

  String hintOf(S s) => switch (this) {
        TtsEngine.openai => s.ttsOpenAiHint,
        TtsEngine.device => s.ttsDeviceHint,
        TtsEngine.clone => s.ttsCloneHint,
      };
}

extension VoiceChannelLabels on VoiceChannel {
  String labelOf(S s) => switch (this) {
        VoiceChannel.chat => s.channelChat,
        VoiceChannel.answer => s.channelAnswer,
        VoiceChannel.outgoing => s.channelOutgoing,
      };

  String hintOf(S s) => switch (this) {
        VoiceChannel.chat => s.channelChatHint,
        VoiceChannel.answer => s.channelAnswerHint,
        VoiceChannel.outgoing => s.channelOutgoingHint,
      };
}

extension GemmaVariantLabels on GemmaVariant {
  String hintOf(S s) => switch (this) {
        GemmaVariant.e2bGpu => s.gemmaE2bGpuHint,
        GemmaVariant.e2bCpu => s.gemmaE2bCpuHint,
        GemmaVariant.e4bGpu => s.gemmaE4bHint,
      };
}

extension MindModeLabels on MindMode {
  String labelOf(S s) => isWork ? s.modeWork : s.modeLove;
  String statusOf(S s) => isWork ? s.statusWork : s.statusLove;
  List<String> chipsOf(S s) => isWork ? s.workChips : s.loveChips;
}

extension PersonaSettingLabels on PersonaSetting {
  String labelOf(S s) => switch (this) {
        PersonaSetting.work => s.modeWork,
        PersonaSetting.love => s.modeLove,
        PersonaSetting.auto => s.modeAuto,
      };
}

/// ผลตรวจแรม — เก็บเป็น "ระดับ" แล้วค่อยแปลตอนแสดง
/// ถ้าเก็บเป็นข้อความไทยตั้งแต่ตอนตรวจ จะแปลไม่ได้เลย
extension RamTierLabels on RamTier {
  String headlineOf(S s) => switch (this) {
        RamTier.unknown => s.ramUnknown,
        RamTier.tooSmall => s.ramTooSmall,
        RamTier.tight => s.ramTight,
        RamTier.comfortable => s.ramComfortable,
        RamTier.roomy => s.ramRoomy,
      };

  String detailOf(S s, String gb) => switch (this) {
        RamTier.unknown => s.ramUnknownDetail,
        RamTier.tooSmall => s.ramTooSmallDetail(gb),
        RamTier.tight => s.ramTightDetail(gb),
        RamTier.comfortable => s.ramComfortableDetail(gb),
        RamTier.roomy => s.ramRoomyDetail(gb),
      };
}
