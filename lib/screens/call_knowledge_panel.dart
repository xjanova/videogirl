import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../i18n/strings_settings.dart';
import '../phone/call_knowledge.dart';
import '../state/mind_state.dart';
import '../system/permissions.dart';
import '../theme/tokens.dart';

/// What she may tell a caller: the owner's own links, files and notes, plus the BrainX folders
/// the owner ticks. Owner: "ทำหน้าตั้งค่านั้นให้ดี และเรื่องใน brainx เลือกได้ว่าจะให้ตอบเรื่องไหน
/// ได้บ้าง ติ๊กเลือกได้". The test box runs the exact lookup a call runs, so the owner sees what she
/// would see.
class CallKnowledgePanel extends StatefulWidget {
  const CallKnowledgePanel({super.key, required this.accent});
  final Color accent;
  @override
  State<CallKnowledgePanel> createState() => _CallKnowledgePanelState();
}

class _CallKnowledgePanelState extends State<CallKnowledgePanel> {
  static const _green = Color(0xFF1E8E3E), _warn = Color(0xFFB46A00);

  /// Big folders mix private notes in · ticking one asks first.
  static const _bigFolder = 50;

  /// Which add/refresh/remove is running · one at a time (double taps do nothing).
  String? _busy;
  String? _error;
  String? _notice;

  List<({String scope, int notes})>? _scopes;
  bool _scopesLoading = false, _scopesFailed = false;
  final Set<String> _expanded = {};
  final _filter = TextEditingController();
  final _query = TextEditingController();
  List<({String title, String text, String source})>? _results;
  bool _searching = false;
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(context.read<MindState>().callKnowledge.load());
    _filter.addListener(_onFilter);
  }

  @override
  void dispose() {
    _filter.removeListener(_onFilter);
    _filter.dispose();
    _query.dispose();
    super.dispose();
  }

  void _onFilter() => setState(() {});

  String _errorText(S t, Object e) => switch (e) {
        KnowledgeError(code: 'bad_url') => t.kbErrBadUrl,
        KnowledgeError(code: 'fetch_failed') => t.kbErrFetch,
        KnowledgeError(code: 'unsupported_type') => t.kbErrType,
        KnowledgeError(code: 'empty') => t.kbErrEmpty,
        KnowledgeError(code: 'too_large') => t.kbErrTooLarge,
        KnowledgeError(code: 'read_failed') => t.kbErrRead,
        _ => t.kbErrOther,
      };

  /// Runs one store change with a spinner on [tag] · errors become a sentence on screen.
  Future<void> _run(String tag, Future<void> Function() job, {bool added = false}) async {
    if (_busy != null) return;
    final t = S.of(context);
    setState(() {
      _busy = tag;
      _error = null;
      _notice = null;
    });
    String? error;
    try {
      await job();
    } on Object catch (e) {
      error = _errorText(t, e);
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      _error = error;
      _notice = error == null && added ? t.kbAdded : null;
      // Old answers came from the store before this change.
      _results = null;
    });
  }

  Future<void> _addLink(CallKnowledge kb) async {
    final url = await _ask(
      title: (t) => t.kbLinkTitle,
      fields: [(label: 'https://', lines: 1, keyboard: TextInputType.url)],
      helper: (t) => t.kbLinkHint,
    );
    if (url == null || !mounted) return;
    await _run('link', () => kb.addLink(url[0]), added: true);
  }

  Future<void> _addText(CallKnowledge kb) async {
    final t = S.of(context);
    final v = await _ask(
      title: (t) => t.kbTextTitle,
      fields: [
        (label: t.kbTextName, lines: 1, keyboard: TextInputType.text),
        (label: t.kbTextBody, lines: 6, keyboard: TextInputType.multiline),
      ],
    );
    if (v == null || !mounted) return;
    await _run('text', () => kb.addText(v[0], v[1]), added: true);
  }

  Future<void> _addFile(CallKnowledge kb) async {
    if (_busy != null) return;
    Map<Object?, Object?>? picked;
    try {
      picked = await kSystemChannel.invokeMethod<Map<Object?, Object?>>('pickTextFile');
    } on PlatformException {
      picked = {'error': 'read_failed'};
    }
    if (picked == null || !mounted) return; // cancelled
    final error = picked['error'], name = picked['name'], bytes = picked['bytes'];
    if (error is String || name is! String || bytes is! Uint8List) {
      final t = S.of(context);
      setState(() => _error = _errorText(t, KnowledgeError(error is String ? error : 'read_failed')));
      return;
    }
    await _run('file', () => kb.addFile(name, bytes), added: true);
  }

  Future<void> _remove(CallKnowledge kb, KnowledgeSource s) async {
    final t = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(t.kbDeleteAsk(s.title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(t.kbDelete, style: const TextStyle(color: Color(0xFFC62828))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run('remove:${s.id}', () => kb.remove(s.id));
  }

  void _preview(KnowledgeSource s) {
    final t = S.of(context);
    final body = s.text.length > 4000 ? '${s.text.substring(0, 4000)}\n…' : s.text;
    unawaited(showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(s.title, style: const TextStyle(fontSize: 15)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.kbPreviewNote, style: const TextStyle(fontSize: 11, color: MindColors.ink55)),
              const SizedBox(height: 8),
              SelectableText(body, style: const TextStyle(fontSize: 12.5, height: 1.5)),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(t.kbClose))],
      ),
    ));
  }

  /// A small form in a dialog · null = cancelled. Controllers die after the close animation.
  Future<List<String>?> _ask({
    required String Function(S) title,
    required List<({String label, int lines, TextInputType keyboard})> fields,
    String Function(S)? helper,
  }) async {
    final ctls = [for (final _ in fields) TextEditingController()];
    try {
      return await showDialog<List<String>>(
        context: context,
        builder: (c) {
          final t = S.of(c);
          return AlertDialog(
            title: Text(title(t), style: const TextStyle(fontSize: 15)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < fields.length; i++)
                    TextField(
                      controller: ctls[i],
                      autofocus: i == 0,
                      keyboardType: fields[i].keyboard,
                      minLines: fields[i].lines,
                      maxLines: fields[i].lines == 1 ? 1 : 12,
                      decoration: InputDecoration(
                        labelText: fields[i].label,
                        helperText: i == fields.length - 1 && helper != null ? helper(t) : null,
                        helperMaxLines: 4,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: Text(t.cancel)),
              TextButton(
                onPressed: () {
                  final v = [for (final ctl in ctls) ctl.text];
                  if (v.last.trim().isEmpty) return;
                  Navigator.pop(c, v);
                },
                child: Text(t.kbAdd),
              ),
            ],
          );
        },
      );
    } finally {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 600), () {
        for (final ctl in ctls) {
          ctl.dispose();
        }
      }));
    }
  }

  Future<void> _loadScopes(MindState state) async {
    if (_scopesLoading) return;
    setState(() {
      _scopesLoading = true;
      _scopesFailed = false;
    });
    final got = await state.brainx.scopes();
    if (!mounted) return;
    setState(() {
      _scopesLoading = false;
      _scopesFailed = got.isEmpty;
      _scopes = got.isEmpty ? null : got;
    });
  }

  Future<void> _toggle(MindState state, String scope, int notes, bool on) async {
    final t = S.of(context);
    final ticked = {...state.callBrainxScopes};
    if (on) {
      if (notes >= _bigFolder) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            content: Text(t.kbBigAsk(scope, notes)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
              TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t.kbBigYes)),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
      // The parent covers its children · keeping both would search them twice.
      ticked.removeWhere((s) => s.startsWith('$scope/'));
      ticked.add(scope);
    } else {
      ticked.remove(scope);
    }
    state.setCallBrainxScopes(ticked);
    setState(() => _results = null);
  }

  Future<void> _search(MindState state) async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    final seq = ++_searchSeq;
    setState(() => _searching = true);
    final hits = await state.callLookup(q);
    // A newer search (or leaving the page) wins.
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _searching = false;
      _results = hits;
    });
  }

  static String _num(int n) {
    final s = '$n';
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String _when(DateTime d) => '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final state = context.watch<MindState>();
    final kb = state.callKnowledge;
    return ListenableBuilder(
      listenable: kb,
      builder: (context, _) {
        final scopes = state.callBrainxScopes;
        final brainOn = state.brainx.connected;
        final ready = state.callLookupReady;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(t, kb, ready, brainOn ? scopes.length : 0),
            if (!state.realtimeCallsReady) ...[
              const SizedBox(height: 6),
              Text(t.kbNeedsLive, style: const TextStyle(fontSize: 11, height: 1.4, color: _warn)),
            ],
            const SizedBox(height: 14),
            _subhead(t.kbMine),
            const SizedBox(height: 8),
            _addRow(t, kb),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(fontSize: 11.5, height: 1.4, color: _warn)),
            ],
            if (_notice != null) ...[
              const SizedBox(height: 8),
              Text(_notice!, style: const TextStyle(fontSize: 11.5, height: 1.4, color: _green)),
            ],
            const SizedBox(height: 6),
            if (kb.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(t.kbNone, style: const TextStyle(fontSize: 11.5, height: 1.45, color: MindColors.ink55)),
              )
            else ...[
              for (final s in kb.sources) _sourceRow(t, kb, s),
              const SizedBox(height: 4),
              _usage(t, kb),
            ],
            const SizedBox(height: 16),
            _subhead(t.kbBrainx),
            const SizedBox(height: 4),
            Text(t.kbBrainxWarn, style: const TextStyle(fontSize: 11, height: 1.45, color: MindColors.ink55)),
            const SizedBox(height: 8),
            if (!brainOn)
              Text(t.kbBrainxOff, style: const TextStyle(fontSize: 11.5, height: 1.45, color: MindColors.ink55))
            else
              _brainx(t, state, scopes),
            const SizedBox(height: 16),
            _subhead(t.kbTry),
            const SizedBox(height: 6),
            _tryBox(t, state, ready),
          ],
        );
      },
    );
  }

  Widget _header(S t, CallKnowledge kb, bool ready, int scopes) => Row(
        children: [
          Icon(ready ? Icons.menu_book_rounded : Icons.import_contacts_rounded,
              size: 26, color: ready ? _green : widget.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(t.kbTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                Text(
                  ready ? t.kbReady(kb.sources.length, scopes) : t.kbEmpty,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    fontWeight: ready ? FontWeight.w600 : FontWeight.w400,
                    color: ready ? _green : MindColors.ink55,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _subhead(String text) =>
      Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: widget.accent));

  Widget _addRow(S t, CallKnowledge kb) {
    Widget button(String tag, IconData icon, String label, VoidCallback onTap) => Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.accent,
              side: BorderSide(color: widget.accent.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
            ),
            onPressed: _busy == null ? onTap : null,
            icon: _busy == tag
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(icon, size: 17),
            label: Text(label, style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis),
          ),
        );
    return Row(
      spacing: 8,
      children: [
        button('link', Icons.link_rounded, t.kbAddLink, () => unawaited(_addLink(kb))),
        button('file', Icons.upload_file_rounded, t.kbAddFile, () => unawaited(_addFile(kb))),
        button('text', Icons.edit_note_rounded, t.kbAddText, () => unawaited(_addText(kb))),
      ],
    );
  }

  Widget _sourceRow(S t, CallKnowledge kb, KnowledgeSource s) {
    final icon = switch (s.kind) {
      'link' => Icons.public_rounded,
      'file' => Icons.description_rounded,
      _ => Icons.notes_rounded,
    };
    final origin = switch (s.kind) {
      'link' => Uri.tryParse(s.origin)?.host ?? s.origin,
      'file' => s.origin,
      _ => t.kbTyped,
    };
    final refreshing = _busy == 'refresh:${s.id}', removing = _busy == 'remove:${s.id}';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _preview(s),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: widget.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(
                    '$origin · ${t.kbChars(_num(s.text.length))} · ${t.kbUpdated(_when(s.updatedAt))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: MindColors.ink55),
                  ),
                ],
              ),
            ),
            if (s.kind == 'link')
              IconButton(
                tooltip: t.kbRefresh,
                visualDensity: VisualDensity.compact,
                onPressed: _busy == null ? () => unawaited(_run('refresh:${s.id}', () => kb.refresh(s.id))) : null,
                icon: refreshing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 20),
              ),
            IconButton(
              tooltip: t.kbDelete,
              visualDensity: VisualDensity.compact,
              onPressed: _busy == null ? () => unawaited(_remove(kb, s)) : null,
              icon: removing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _usage(S t, CallKnowledge kb) {
    final used = kb.totalChars;
    final frac = (used / CallKnowledge.maxTotalChars).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 4,
            color: frac > 0.9 ? _warn : widget.accent,
            backgroundColor: widget.accent.withValues(alpha: 0.12),
          ),
        ),
        Text(t.kbUsage(_num(used), _num(CallKnowledge.maxTotalChars)),
            style: const TextStyle(fontSize: 10.5, color: MindColors.ink55)),
      ],
    );
  }

  Widget _brainx(S t, MindState state, Set<String> ticked) {
    final scopes = _scopes;
    if (scopes == null) {
      if (!_scopesLoading && !_scopesFailed) {
        // First look at this card · fetch once, not on every rebuild.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scopes == null && !_scopesLoading && !_scopesFailed) unawaited(_loadScopes(state));
        });
      }
      return Row(
        children: [
          if (_scopesLoading || !_scopesFailed)
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_scopesFailed ? t.kbBrainxFailed : t.kbBrainxLoading,
                style: TextStyle(fontSize: 11.5, color: _scopesFailed ? _warn : MindColors.ink55)),
          ),
          if (_scopesFailed)
            TextButton(onPressed: () => unawaited(_loadScopes(state)), child: Text(t.kbBrainxRetry)),
        ],
      );
    }

    // Folders → their direct children · the cloud lists both levels flat.
    final tops = <String, int>{};
    final kids = <String, List<({String scope, int notes})>>{};
    for (final s in scopes) {
      final cut = s.scope.indexOf('/');
      if (cut < 0) {
        tops[s.scope] = s.notes;
      } else {
        final top = s.scope.substring(0, cut);
        tops.putIfAbsent(top, () => 0);
        (kids[top] ??= []).add(s);
      }
    }
    final f = _filter.text.trim().toLowerCase();
    bool shown(String scope) => f.isEmpty || scope.toLowerCase().contains(f);
    final order = tops.keys.toList()..sort((a, b) => tops[b]!.compareTo(tops[a]!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ticked.isEmpty)
          Text(t.kbBrainxNoneTicked, style: const TextStyle(fontSize: 11.5, color: MindColors.ink55))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in ticked.toList()..sort())
                InputChip(
                  label: Text(s, style: const TextStyle(fontSize: 11.5)),
                  selected: true,
                  selectedColor: widget.accent.withValues(alpha: 0.14),
                  showCheckmark: false,
                  onDeleted: () => unawaited(_toggle(state, s, 0, false)),
                ),
            ],
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _filter,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 18),
            hintText: t.kbBrainxFilter,
            border: const OutlineInputBorder(),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 4),
        for (final top in order)
          if (shown(top) || (kids[top]?.any((k) => shown(k.scope)) ?? false)) ...[
            _scopeRow(
              t,
              state,
              ticked,
              scope: top,
              label: top,
              notes: tops[top]!,
              depth: 0,
              hasKids: kids[top]?.isNotEmpty ?? false,
            ),
            if (_expanded.contains(top) || f.isNotEmpty)
              for (final k in kids[top] ?? const <({String scope, int notes})>[])
                if (shown(k.scope) || shown(top))
                  _scopeRow(t, state, ticked,
                      scope: k.scope, label: k.scope.substring(top.length + 1), notes: k.notes, depth: 1, hasKids: false),
          ],
      ],
    );
  }

  Widget _scopeRow(
    S t,
    MindState state,
    Set<String> ticked, {
    required String scope,
    required String label,
    required int notes,
    required int depth,
    required bool hasKids,
  }) {
    final parent = depth > 0 ? scope.substring(0, scope.indexOf('/')) : null;
    final viaParent = parent != null && ticked.contains(parent);
    final on = ticked.contains(scope) || viaParent;
    final someKids = depth == 0 && !on && ticked.any((s) => s.startsWith('$scope/'));
    final open = _expanded.contains(scope);
    return Padding(
      padding: EdgeInsets.only(left: depth * 22.0),
      child: Row(
        children: [
          Checkbox(
            value: someKids ? null : on,
            tristate: someKids,
            activeColor: widget.accent,
            visualDensity: VisualDensity.compact,
            onChanged: viaParent ? null : (_) => unawaited(_toggle(state, scope, notes, !on)),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: hasKids ? () => setState(() => open ? _expanded.remove(scope) : _expanded.add(scope)) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: label,
                        style: TextStyle(fontSize: 13, fontWeight: depth == 0 ? FontWeight.w600 : FontWeight.w400)),
                    TextSpan(
                      text: notes > 0 ? '  ${t.kbNotes(notes)}' : '',
                      style: const TextStyle(fontSize: 10.5, color: MindColors.ink55),
                    ),
                    if (viaParent)
                      TextSpan(text: '  · ${t.kbIncluded}', style: const TextStyle(fontSize: 10.5, color: MindColors.ink55)),
                  ]),
                ),
              ),
            ),
          ),
          if (hasKids)
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => open ? _expanded.remove(scope) : _expanded.add(scope)),
              icon: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _tryBox(S t, MindState state, bool ready) {
    final results = _results;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                enabled: ready,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => unawaited(_search(state)),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: t.kbTryHint,
                  border: const OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: widget.accent),
              onPressed: ready && !_searching ? () => unawaited(_search(state)) : null,
              icon: _searching
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search_rounded, size: 20),
            ),
          ],
        ),
        if (results != null) ...[
          const SizedBox(height: 8),
          if (results.isEmpty)
            Text(t.kbTryNone, style: const TextStyle(fontSize: 11.5, height: 1.45, color: _warn))
          else
            for (final r in results)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text('${r.source == 'brainx' ? 'BrainX' : t.kbFromMine} · ${r.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: widget.accent)),
                    Text(r.text.length > 400 ? '${r.text.substring(0, 400)}…' : r.text,
                        style: const TextStyle(fontSize: 12, height: 1.45)),
                  ],
                ),
              ),
        ],
      ],
    );
  }
}
