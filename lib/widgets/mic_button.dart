/// ปุ่มไมค์ในช่องแชท — ของจริง ไม่ใช่ปุ่มที่กดแล้วเปลี่ยนสีตัวเอง
///
/// สามสถานะที่ต้องแยกให้ออกจากกันตอนมองด้วยตา:
/// **ปิดอยู่** (เทา) · **กำลังฟัง** (แดง + วงเต้นตามเสียงจริง) ·
/// **กำลังถอดเสียง** (วงหมุน) · ถ้าสองอันหลังหน้าตาเหมือนกัน คนจะพูดต่อ
/// ระหว่างที่ไมค์ปิดไปแล้ว แล้วประโยคนั้นจะหายไปทั้งประโยค
///
/// แตะ = คุยต่อเนื่องด้วยเสียง ([VoiceChat] · สีของโหมด + วงเต้น) · กดค้าง = พูดลงช่องพิมพ์ (แบบเดิม · แดง)
library;

import 'package:flutter/material.dart';

import '../ai/voice_chat.dart';
import '../ai/voice_input.dart';
import '../i18n/strings.dart';
import '../i18n/strings_ai.dart';
import '../theme/tokens.dart';

class MicButton extends StatelessWidget {
  const MicButton({
    super.key,
    required this.voice,
    required this.mode,
    required this.onTap,
    required this.enabled,
    this.chat,
    this.onLongPress,
  });

  final VoiceInput voice;

  /// โหมดคุยต่อเนื่อง · เปิดอยู่ = ปุ่มนี้คือปุ่มปิด
  final VoiceChat? chat;
  final MindMode mode;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// ถอดเสียงได้ไหมด้วยสมองที่เลือกไว้ตอนนี้
  ///
  /// ปิดไม่ได้แปลว่าซ่อน — ปุ่มยังอยู่และยังกดได้ แต่กดแล้วจะได้ยินว่า
  /// **ทำไม**ยังใช้ไม่ได้ · ปุ่มที่หายไปเฉย ๆ ทำให้คนหาไม่เจอว่าฟีเจอร์นี้
  /// มีอยู่ไหม แล้วเดาเอาเองว่าแอปไม่มีความสามารถนี้
  final bool enabled;

  static const _size = 38.0;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);

    final c = chat;
    return ListenableBuilder(
      listenable: c == null ? voice : Listenable.merge([voice, c]),
      builder: (context, _) {
        final talking = c?.active ?? false;
        final listening = voice.stage == VoiceInputStage.listening;
        final working = voice.stage == VoiceInputStage.working ||
            voice.stage == VoiceInputStage.opening ||
            c?.phase == VoiceChatPhase.opening;
        final on = listening || talking;
        // คุยต่อเนื่อง = สีของโหมด (คนละสีกับพูดลงช่องพิมพ์ จะได้รู้ว่าเปิดโหมดไหนอยู่)
        final tint = talking ? mode.accent : const Color(0xFFFF5C8A);

        return Semantics(
          button: true,
          toggled: on,
          label: talking
              ? t.voiceChatClose
              : listening
                  ? t.micStop
                  : t.voiceChatMicHint,
          child: Tooltip(
            message: working
                ? (talking ? t.voiceChatOpening : t.micWorking)
                : talking
                    ? t.voiceChatClose
                    : listening
                        ? t.micListening
                        : t.voiceChatMicHint,
            child: GestureDetector(
              onTap: onTap,
              onLongPress: onLongPress,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: _size,
                height: _size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // วงที่เต้นตามเสียงจริง — บอกสิ่งที่สีแดงบอกไม่ได้
                    // ว่า **ไมค์ได้ยินเราอยู่** ไม่ใช่แค่เปิดค้างไว้เฉย ๆ
                    if (on)
                      _Halo(
                          level: talking ? c!.level : voice.level,
                          size: _size,
                          color: tint),
                    Container(
                      width: _size,
                      height: _size,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: on
                            ? tint.withValues(alpha: .2)
                            : MindColors.glass80,
                        borderRadius:
                            BorderRadius.circular(MindRadius.control),
                        border: Border.all(
                          color: on
                              ? tint.withValues(alpha: .4)
                              : MindColors.glassBorder,
                          width: 1,
                        ),
                      ),
                      child: working
                          ? SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: mode.accent,
                              ),
                            )
                          : Icon(
                              talking
                                  ? Icons.graphic_eq_rounded
                                  : listening
                                      ? Icons.mic_rounded
                                      : Icons.mic_none_rounded,
                              size: 18,
                              color: on
                                  ? tint
                                  : enabled
                                      ? MindColors.ink60
                                      : MindColors.ink22,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// วงเรืองรอบปุ่มที่โตตามระดับเสียง
///
/// ไม่ใช้ AnimationController เพราะ**ตัวขับคือเสียงจริง** ไม่ใช่นาฬิกา
/// [AnimatedContainer] ก็พอสำหรับหน่วงให้ลื่น โดยไม่ต้องมี ticker เพิ่มอีกตัว
class _Halo extends StatelessWidget {
  const _Halo({required this.level, required this.size, required this.color});

  final double level;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // เสียงพูดปกติวัดได้ราว .02–.25 · คูณขึ้นมาให้เห็นการเปลี่ยนแปลงจริง
    // แล้วบีบไว้ที่ 1 ไม่งั้นตะโกนทีเดียววงจะล้นออกนอกแถวปุ่ม
    final t = (level * 4).clamp(0.0, 1.0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      width: size * (.9 + .5 * t),
      height: size * (.9 + .5 * t),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .10 + .18 * t),
      ),
    );
  }
}
