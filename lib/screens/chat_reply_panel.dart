import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chats/chat_inbox.dart';
import '../i18n/strings.dart';
import '../i18n/strings_chats.dart';
import '../state/mind_state.dart';
import '../theme/tokens.dart';

/// สวิตช์ "ช่วยตอบแชท WhatsApp" + ปุ่มไปให้สิทธิ์เข้าถึงการแจ้งเตือน
///
/// เจ้าของ: "ทำให้เธอตอบ what app ได้ด้วย · เมื่อมีคนแชทมา" · ปิดเป็นค่าเริ่มต้น · สิทธิ์เจ้าของกดเองในหน้าของระบบ
class ChatReplyPanel extends StatefulWidget {
  const ChatReplyPanel({super.key, required this.accent});
  final Color accent;
  @override
  State<ChatReplyPanel> createState() => _ChatReplyPanelState();
}

class _ChatReplyPanelState extends State<ChatReplyPanel> with WidgetsBindingObserver {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<MindState>().refreshChats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// กลับมาจากหน้าให้สิทธิ์ของระบบ · อ่านใหม่ ไม่งั้นการ์ดยังบอกว่าไม่ได้ให้
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && mounted) context.read<MindState>().refreshChats();
  }

  Future<void> _grant(MindState state, S t) async {
    final ok = await state.openChatAccess();
    if (!mounted) return;
    setState(() => _error = ok ? null : t.chatsGrantFailed);
  }

  /// เปิด = เตือนก่อนเสมอ (ส่งจากบัญชีเจ้าของโดยไม่ถาม) · ปิด = ปิดเลย
  Future<void> _setAuto(MindState state, S t, bool v) async {
    if (!v) return state.setChatsAuto(false);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.chatsAutoWarnTitle),
        content: Text(t.chatsAutoWarnBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t.chatsAutoWarnOk)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await state.setChatsAuto(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final state = context.watch<MindState>();
    final on = state.chatsOn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t.chatsIntro, style: const TextStyle(fontSize: 11, height: 1.45, color: MindColors.ink55)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 3,
                children: [
                  Text(t.chatsSwitch, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  Text(t.chatsSwitchHint, style: const TextStyle(fontSize: 10.5, height: 1.45, color: MindColors.ink55)),
                ],
              ),
            ),
            Switch(value: on, activeTrackColor: widget.accent, onChanged: state.setChatsOn),
          ],
        ),
        if (on) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 3,
                  children: [
                    Text(t.chatsAuto, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    Text(t.chatsAutoHint, style: const TextStyle(fontSize: 10.5, height: 1.45, color: MindColors.ink55)),
                  ],
                ),
              ),
              Switch(value: state.chatsAuto, activeTrackColor: widget.accent, onChanged: (v) => _setAuto(state, t, v)),
            ],
          ),
          const SizedBox(height: 10),
          Text(t.chatsTrusted, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (state.chatsTrusted.isEmpty)
            Text(t.chatsTrustedNone, style: const TextStyle(fontSize: 10.5, height: 1.45, color: MindColors.ink55))
          else
            for (final c in state.chatsTrusted)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${c.name.isEmpty ? '?' : c.name} · ${chatAppName(c.app)}',
                      style: const TextStyle(fontSize: 11.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(onPressed: () => state.untrustChat(c.contact), child: Text(t.chatsUntrust)),
                ],
              ),
          const SizedBox(height: 10),
          if (state.chatsAccess)
            Text(t.chatsReady, style: TextStyle(fontSize: 11, color: widget.accent, fontWeight: FontWeight.w600))
          else ...[
            Text(t.chatsNeedAccess, style: const TextStyle(fontSize: 11, height: 1.45, color: Color(0xFFB46A00))),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(onPressed: () => _grant(state, t), child: Text(t.chatsGrant)),
            ),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(fontSize: 11, color: Color(0xFFC62828))),
        ],
      ],
    );
  }
}
