import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../i18n/strings_settings.dart';
import '../phone/call_lessons.dart';
import '../phone/identity_gate.dart';
import '../phone/owner_gate.dart';
import '../state/mind_state.dart';
import '../theme/tokens.dart';

/// What she learned from calls (see each, delete each), the owner's secret code, and the identity questions.
/// Owner: "ยิ่งคุย ยิ่งเจอ ยิ่งสั่ง ก็ยิ่งเก่ง" · "เธออ่านและเรียกใช้ได้ แต่หลอกถามให้พูดไม่ได้ ยกเว้น คนมีโค๊ดลับ" ·
/// "ให้ยืนยันด้วยคำถาม ยืนยันตัวตน อย่างน้อย 3 ข้อ เพื่อเข้าถึงสิทธิ์ เรากำหนดได้ในแอพว่าต้องตอบอะไร".
/// The code itself is never shown again after it is saved. Answers appear only inside the question editor.
class CallLessonsPanel extends StatefulWidget {
  const CallLessonsPanel({super.key, required this.accent});
  final Color accent;
  @override
  State<CallLessonsPanel> createState() => _CallLessonsPanelState();
}

class _CallLessonsPanelState extends State<CallLessonsPanel> {
  static const _green = Color(0xFF1E8E3E), _warn = Color(0xFFB46A00), _red = Color(0xFFC62828);

  /// One code change at a time · double taps do nothing.
  bool _busy = false;
  String? _notice;
  String? _idNotice;
  bool _showAll = false;

  Future<bool> _confirm(String text, String action) async {
    final t = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(action, style: const TextStyle(color: _red))),
        ],
      ),
    );
    return ok == true && mounted;
  }

  Future<void> _setCode(MindState state) async {
    if (_busy) return;
    final code = await showDialog<String>(context: context, builder: (_) => const _CodeDialog());
    if (code == null || !mounted) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    final ok = await state.setCallCode(code);
    if (!mounted) return;
    final t = S.of(context);
    setState(() {
      _busy = false;
      _notice = ok ? t.clCodeSaved : t.clCodeSaveFailed;
    });
  }

  Future<void> _removeCode(MindState state) async {
    if (_busy) return;
    final t = S.of(context);
    if (!await _confirm(t.clCodeRemoveAsk, t.clCodeRemove)) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    final ok = await state.clearCallCode();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = ok ? S.of(context).clCodeRemoved : S.of(context).clCodeSaveFailed;
    });
  }

  Future<void> _editQuiz(MindState state) async {
    if (_busy) return;
    // Buttons stay disabled while the editor is open · a double tap cannot open two editors.
    setState(() {
      _busy = true;
      _idNotice = null;
    });
    IdentityQuiz? quiz;
    try {
      quiz = await Navigator.of(context).push<IdentityQuiz>(
        MaterialPageRoute(builder: (_) => _QuizEditor(initial: state.callQuizForEditing())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (quiz == null || !mounted) return;
    setState(() => _busy = true);
    final ok = await state.setCallQuiz(quiz);
    if (!mounted) return;
    final t = S.of(context);
    setState(() {
      _busy = false;
      _idNotice = ok ? t.clIdSaved : t.clIdSaveFailed;
    });
  }

  Future<void> _removeQuiz(MindState state) async {
    if (_busy) return;
    final t = S.of(context);
    if (!await _confirm(t.clIdRemoveAsk, t.clIdRemove)) return;
    setState(() {
      _busy = true;
      _idNotice = null;
    });
    final ok = await state.clearCallQuiz();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _idNotice = ok ? S.of(context).clIdRemoved : S.of(context).clIdSaveFailed;
    });
  }

  Future<void> _delete(MindState state, CallLesson l) async {
    final t = S.of(context);
    if (!await _confirm(t.clDeleteAsk(l.text), t.clDelete)) return;
    state.removeCallLesson(l.id);
  }

  Future<void> _clearAll(MindState state) async {
    final t = S.of(context);
    if (!await _confirm(t.clClearAllAsk(state.callLessons.length), t.clClearAll)) return;
    state.clearCallLessons();
  }

  String _kind(S t, LessonKind k) => switch (k) {
        LessonKind.owner => t.clKindOwner,
        LessonKind.contact => t.clKindContact,
        LessonKind.how => t.clKindHow,
      };

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final state = context.watch<MindState>();
    final locked = state.callCodeLockedUntil;
    final idLocked = state.identityLockedUntil;
    final quiz = state.callQuiz;
    final quizReady = state.callQuizReady;
    final lessons = [...state.callLessons]..sort((a, b) => b.at.compareTo(a.at));
    final shown = _showAll ? lessons : lessons.take(8).toList();
    const small = TextStyle(fontSize: 12, height: 1.45, color: MindColors.ink55);

    String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── โค้ดลับ ──
        Text(t.clCodeTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(t.clCodeHint, style: small),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              locked != null ? Icons.lock_clock : (state.hasCallCode ? Icons.verified_user : Icons.lock_outline),
              size: 18,
              color: locked != null ? _warn : (state.hasCallCode ? _green : MindColors.ink55),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                locked != null ? t.clCodeLocked(hhmm(locked)) : (state.hasCallCode ? t.clCodeOn : t.clCodeOff),
                style: TextStyle(fontSize: 12.5, color: locked != null ? _warn : null),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : () => _setCode(state),
              child: Text(state.hasCallCode ? t.clCodeChange : t.clCodeSet),
            ),
            if (state.hasCallCode)
              TextButton(
                onPressed: _busy ? null : () => _removeCode(state),
                child: Text(t.clCodeRemove, style: const TextStyle(color: _red)),
              ),
          ],
        ),
        if (_notice != null) Text(_notice!, style: small),
        const Divider(height: 24),
        // ── คำถามยืนยันตัวตน ──
        Text(t.clIdTitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(t.clIdHint, style: small),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              idLocked != null ? Icons.lock_clock : (quizReady ? Icons.verified_user : Icons.lock_outline),
              size: 18,
              color: idLocked != null ? _warn : (quizReady ? _green : MindColors.ink55),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                idLocked != null
                    ? t.clIdLocked(hhmm(idLocked))
                    : (quizReady ? t.clIdReady(quiz.items.length, quiz.asks) : t.clIdOff),
                style: TextStyle(fontSize: 12.5, color: idLocked != null ? _warn : null),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : () => _editQuiz(state),
              child: Text(quiz.items.isEmpty ? t.clIdSetUp : t.clIdEdit),
            ),
            if (quiz.items.isNotEmpty)
              TextButton(
                onPressed: _busy ? null : () => _removeQuiz(state),
                child: Text(t.clIdRemove, style: const TextStyle(color: _red)),
              ),
          ],
        ),
        if (_idNotice != null) Text(_idNotice!, style: small),
        const Divider(height: 24),
        // ── บทเรียน ──
        Text(t.clIntro, style: small),
        const SizedBox(height: 8),
        if (lessons.isEmpty)
          Text(t.clEmpty, style: small)
        else ...[
          for (final l in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 2, right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_kind(t, l.kind), style: TextStyle(fontSize: 10.5, color: widget.accent)),
                  ),
                  Expanded(child: Text(l.text, style: const TextStyle(fontSize: 12.5, height: 1.4))),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: t.clDelete,
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => _delete(state, l),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Text(t.clCount(lessons.length), style: small),
              const Spacer(),
              if (lessons.length > shown.length || _showAll)
                TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(_showAll ? '−' : '+${lessons.length - shown.length}'),
                ),
              TextButton(
                onPressed: () => _clearAll(state),
                child: Text(t.clClearAll, style: const TextStyle(color: _red)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Two hidden fields · checks length and match before closing · owns and disposes its controllers.
class _CodeDialog extends StatefulWidget {
  const _CodeDialog();
  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _save() {
    final t = S.of(context);
    if (!OwnerCode.acceptable(_a.text)) {
      setState(() => _error = t.clCodeTooShort);
      return;
    }
    if (_a.text.trim() != _b.text.trim()) {
      setState(() => _error = t.clCodeMismatch);
      return;
    }
    Navigator.pop(context, _a.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return AlertDialog(
      title: Text(t.clCodeTitle, style: const TextStyle(fontSize: 15)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _a,
              autofocus: true,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(labelText: t.clCodeField),
            ),
            TextField(
              controller: _b,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: t.clCodeAgain,
                helperText: t.clCodeHelper,
                helperMaxLines: 4,
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.cancel)),
        TextButton(onPressed: _save, child: Text(t.clSave)),
      ],
    );
  }
}

/// Add, edit and remove identity questions · answers hidden unless shown · checks the rules before closing ·
/// owns and disposes every controller · pops with the new quiz, the panel saves it.
class _QuizEditor extends StatefulWidget {
  const _QuizEditor({required this.initial});
  final IdentityQuiz initial;
  @override
  State<_QuizEditor> createState() => _QuizEditorState();
}

class _QuizRow {
  _QuizRow(String q, String a)
      : question = TextEditingController(text: q),
        answer = TextEditingController(text: a);
  final TextEditingController question;
  final TextEditingController answer;

  void dispose() {
    question.dispose();
    answer.dispose();
  }
}

class _QuizEditorState extends State<_QuizEditor> {
  static const _red = Color(0xFFC62828);

  final _rows = <_QuizRow>[];
  late int _ask;
  late final String _start;
  bool _show = false;
  bool _closing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final items = widget.initial.items;
    for (final q in items) {
      _rows.add(_QuizRow(q.question, q.answer));
    }
    while (_rows.length < IdentityQuiz.minItems) {
      _rows.add(_QuizRow('', ''));
    }
    _ask = items.length < IdentityQuiz.minItems ? IdentityQuiz.minItems : widget.initial.asks;
    _start = _quiz().encode();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  IdentityQuiz _quiz() => IdentityQuiz(
        [for (final r in _rows) IdentityQuestion(r.question.text.trim(), r.answer.text.trim())],
        ask: _ask,
      );

  bool get _dirty => _quiz().encode() != _start;

  int get _maxAsk => _rows.length < IdentityQuiz.minItems ? IdentityQuiz.minItems : _rows.length;

  void _add() {
    if (_rows.length >= IdentityQuiz.maxItems) return;
    setState(() {
      _rows.add(_QuizRow('', ''));
      _error = null;
    });
  }

  void _removeRow(_QuizRow r) {
    setState(() {
      _rows.remove(r);
      _ask = _ask.clamp(IdentityQuiz.minItems, _maxAsk);
      _error = null;
    });
    // The removed fields stay mounted until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => r.dispose());
  }

  String _problemText(S t, QuizProblem p) => switch (p) {
        QuizProblem.tooFew => t.clIdTooFew,
        QuizProblem.tooMany => t.clIdTooMany,
        QuizProblem.emptyQuestion => t.clIdEmptyQuestion,
        QuizProblem.tooLong => t.clIdTooLong,
        QuizProblem.answerTooShort => t.clIdAnswerShort,
        QuizProblem.duplicate => t.clIdDuplicate,
        QuizProblem.answerInQuestion => t.clIdAnswerInQuestion,
        QuizProblem.askOutOfRange => t.clIdAskRange,
      };

  void _save() {
    if (_closing) return;
    final quiz = _quiz();
    final problem = quiz.problem;
    if (problem != null) {
      setState(() => _error = _problemText(S.of(context), problem));
      return;
    }
    _closing = true;
    Navigator.of(context).pop(quiz);
  }

  Future<void> _leave() async {
    if (_closing) return;
    if (!_dirty) {
      _closing = true;
      Navigator.of(context).pop();
      return;
    }
    final t = S.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t.discardTitle),
        content: Text(t.discardBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.keepTyping)),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.discard, style: const TextStyle(color: _red)),
          ),
        ],
      ),
    );
    if (go != true || !mounted || _closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    const small = TextStyle(fontSize: 12, height: 1.45, color: MindColors.ink55);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close), tooltip: t.cancel, onPressed: _leave),
          title: Text(t.clIdTitle, style: const TextStyle(fontSize: 16)),
          actions: [
            IconButton(
              tooltip: _show ? t.clIdHideAnswers : t.clIdShowAnswers,
              icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _show = !_show),
            ),
            TextButton(onPressed: _save, child: Text(t.clSave)),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text(t.clIdHelper, style: small),
              if (widget.initial.items.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(t.clIdReplaceNote, style: small),
              ],
              const SizedBox(height: 8),
              for (final (i, r) in _rows.indexed)
                Padding(
                  key: ObjectKey(r),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            TextField(
                              controller: r.question,
                              maxLength: IdentityQuiz.questionMax,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => setState(() => _error = null),
                              decoration: InputDecoration(labelText: t.clIdQuestion(i + 1), counterText: ''),
                            ),
                            TextField(
                              controller: r.answer,
                              maxLength: IdentityQuiz.answerMax,
                              obscureText: !_show,
                              enableSuggestions: false,
                              autocorrect: false,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => setState(() => _error = null),
                              decoration: InputDecoration(labelText: t.clIdAnswer, counterText: ''),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: t.clIdRemoveOne,
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: () => _removeRow(r),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _rows.length >= IdentityQuiz.maxItems ? null : _add,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(t.clIdAdd),
                ),
              ),
              Row(
                children: [
                  Text(t.clIdAskLabel),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: _ask.clamp(IdentityQuiz.minItems, _maxAsk),
                    items: [
                      for (var n = IdentityQuiz.minItems; n <= _maxAsk; n++)
                        DropdownMenuItem(value: n, child: Text(t.clIdAskCount(n))),
                    ],
                    onChanged: (v) => setState(() {
                      if (v != null) _ask = v;
                      _error = null;
                    }),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(fontSize: 12.5, color: _red)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
