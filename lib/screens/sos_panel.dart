import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.dart';
import '../i18n/strings_sos.dart';
import '../sos/mind_sos.dart';
import '../sos/sos_directory.dart';
import '../sos/sos_profile.dart';
import '../system/permissions.dart';
import '../theme/tokens.dart';

/// ตั้งค่า › ฉุกเฉิน · เปิดระบบ ข้อมูลสำหรับเจ้าหน้าที่ ผู้ติดต่อ ซ้อม ตำแหน่ง
///
/// เจ้าของ: "ให้เรากรอกข้อมูลเราไว้ในส่วนนี้เพื่อใช้แจ้งเจ้าหน้าที่" · สถานะถามฝั่ง Android ทุกครั้ง
/// (สิทธิ์ถูกถอนจากการตั้งค่าของเครื่อง และระบบปิดบริการได้โดยหน้านี้ไม่รู้)
class SosPanel extends StatefulWidget {
  const SosPanel({super.key, required this.accent, this.sos});

  final Color accent;

  /// เทสต์ใส่ตัวปลอม
  final MindSos? sos;

  @override
  State<SosPanel> createState() => _SosPanelState();
}

class _SosPanelState extends State<SosPanel> with WidgetsBindingObserver {
  late final MindSos _sos = widget.sos ?? MindSos.instance;

  final _name = TextEditingController();
  final _birth = TextEditingController();
  final _blood = TextEditingController();
  final _conditions = TextEditingController();
  final _medicines = TextEditingController();
  final _allergies = TextEditingController();
  final _plate = TextEditingController();
  final _notes = TextEditingController();
  final _test = TextEditingController();

  SosProfile _saved = const SosProfile();
  List<SosContactInfo> _contacts = const [];
  bool _armed = false;
  bool _autoCall = false;
  int _consent = 0;
  int _countdown = 30;
  int _sensitivity = 1;

  SosStatus _status = SosStatus.empty;
  SosPlace? _place;
  bool _loaded = false;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sos.onChanged = _refresh;
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sos.onChanged = null;
    _keep();
    for (final c in [_name, _birth, _blood, _conditions, _medicines, _allergies, _plate, _notes, _test]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // กลับจากหน้าสิทธิ์ของเครื่อง · รายการความพร้อมต้องเปลี่ยนตาม
    if (state == AppLifecycleState.resumed) _refresh();
    if (state == AppLifecycleState.paused) _keep();
  }

  /// ออกจากหน้าแล้วข้อมูลต้องไม่หาย · ข้อมูลที่จะช่วยชีวิตไม่ควรรอให้กดบันทึก
  ///
  /// 🔴 ถามตอนออกไม่ได้ · ปุ่มย้อนของหมวดตั้งค่าเปลี่ยนหน้าด้วยค่าใน ValueNotifier ไม่ผ่าน PopScope
  void _keep() {
    if (!_dirty || !_valid) return;
    final draft = _draft;
    _saved = draft;
    unawaited(_sos.save(draft));
  }

  Future<void> _load() async {
    final p = await _sos.profile();
    final st = await _sos.status();
    final place = await _sos.location();
    if (!mounted) return;
    _saved = p;
    _name.text = p.name;
    _birth.text = p.birthYear?.toString() ?? '';
    _blood.text = p.blood;
    _conditions.text = p.conditions;
    _medicines.text = p.medicines;
    _allergies.text = p.allergies;
    _plate.text = p.plate;
    _notes.text = p.notes;
    _test.text = p.testNumber;
    setState(() {
      _contacts = p.contacts;
      _armed = p.armed;
      _autoCall = p.autoCall;
      _consent = p.consent;
      _countdown = p.countdownSec;
      _sensitivity = p.sensitivity;
      _status = st;
      _place = place;
      _loaded = true;
    });
  }

  void _refresh() => unawaited(_check());

  /// ไม่แตะช่องกรอก · เจ้าของอาจพิมพ์ค้างอยู่
  Future<void> _check() async {
    final st = await _sos.status();
    if (!mounted) return;
    setState(() => _status = st);
  }

  int? get _birthYear => int.tryParse(_birth.text.trim());

  SosProfile get _draft => SosProfile(
        name: _name.text.trim(),
        birthYear: _birthYear,
        blood: _blood.text.trim(),
        conditions: _conditions.text.trim(),
        medicines: _medicines.text.trim(),
        allergies: _allergies.text.trim(),
        plate: _plate.text.trim(),
        notes: _notes.text.trim(),
        contacts: _contacts,
        testNumber: _test.text.trim(),
        armed: _armed,
        autoCall: _autoCall,
        consent: _consent,
        countdownSec: _countdown,
        sensitivity: _sensitivity,
      );

  bool get _dirty => _loaded && _draft.encode() != _saved.encode();

  /// เบอร์มือถือเต็ม · ด่านจริงอยู่ฝั่งเนทีฟ (SosRouter) ตรงนี้แค่บอกเจ้าของให้เร็ว
  static bool _fullNumber(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 9 && !digits.startsWith('1');
  }

  bool get _birthOk => _birth.text.trim().isEmpty || _draft.ageIn(DateTime.now().year) != null;
  bool get _testOk => _test.text.trim().isEmpty || _fullNumber(_test.text);
  bool get _valid => _birthOk && _testOk;

  Future<bool> _save() async {
    final t = S.of(context);
    if (!_birthOk) {
      setState(() => _message = t.sosBirthYearBad);
      return false;
    }
    if (!_testOk) {
      setState(() => _message = t.sosTestBad);
      return false;
    }
    final draft = _draft;
    final ok = await _sos.save(draft);
    if (!mounted) return false;
    if (ok) _saved = draft;
    setState(() => _message = ok ? t.sosSaved : t.sosSaveFailed);
    await _check();
    return ok;
  }

  Future<bool> _confirm(String body, String yes, {String? title}) async {
    final t = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: title == null ? null : Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.sosCancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _ask(String method) async {
    try {
      await kSystemChannel.invokeMethod<Object?>(method);
    } on PlatformException {
      // หน้าระบบเปิดไม่ได้ · รายการความพร้อมยังบอกสถานะจริง
    }
    await _check();
  }

  /// 🔴 เปิดระบบต้องผ่านการยอมรับข้อจำกัดทุกครั้งที่เนื้อหาเปลี่ยน · แจ้งเหตุเท็จมีผลจริง
  Future<void> _setArmed(bool on) async {
    if (_busy) return;
    _busy = true;
    try {
      final t = S.of(context);
      if (on && _consent < kSosConsentVersion) {
        if (!await _confirm(t.sosConsentBody, t.sosConsentYes, title: t.sosConsentTitle)) return;
        if (!mounted) return;
        setState(() => _consent = kSosConsentVersion);
      }
      if (on) {
        await _ask('requestSos');
        final st = await _sos.status();
        if (!mounted) return;
        if (st.location && !st.background) await _ask('requestSosBackground');
        if (!mounted) return;
        final perms = context.read<MindPermissions>();
        if (!perms.of(MindPermission.notify)) await perms.request(MindPermission.notify);
      }
      if (!mounted) return;
      setState(() {
        _armed = on;
        // ปิดระบบ = ด่านโทรอัตโนมัติปิดด้วย · เปิดกลับมาต้องตั้งใจเปิดอีกรอบ
        if (!on) _autoCall = false;
      });
      final saved = await _save();
      if (!mounted) return;
      // บันทึกไม่ผ่าน = ฝั่งเนทีฟยังไม่เปิด · สวิตช์ต้องไม่บอกว่าเปิดแล้ว
      if (!saved) {
        setState(() => _armed = !on);
      } else if (on && !(_status.location && _status.sms && _status.call)) {
        setState(() => _message = t.sosPermsDenied);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _setAutoCall(bool on) async {
    setState(() => _autoCall = on);
    if (await _save() || !mounted) return;
    setState(() => _autoCall = !on);
  }

  Future<void> _manual() async {
    final ok = await _sos.trigger(SosKindName.other);
    if (!mounted) return;
    if (!ok) setState(() => _message = S.of(context).sosTriggerFailed);
  }

  Future<void> _drill({bool silent = false}) async {
    final t = S.of(context);
    final number = _test.text.trim();
    if (!_fullNumber(number)) {
      setState(() => _message = t.sosTestBad);
      return;
    }
    final ask = silent ? t.sosDrillSilentAsk(number) : t.sosDrillAsk(number);
    if (!await _confirm(ask, silent ? t.sosDrillSilentRun : t.sosDrillRun)) return;
    if (!mounted || !await _save()) return;
    final ok = await _sos.drill(silent: silent);
    if (!mounted) return;
    if (!ok) setState(() => _message = t.sosDrillFailed);
  }

  Future<void> _addContact() async {
    final t = S.of(context);
    final added = await showDialog<SosContactInfo>(context: context, builder: (_) => const _ContactDialog());
    if (added == null || !mounted) return;
    if (!_fullNumber(added.number)) {
      setState(() => _message = t.sosContactBad);
      return;
    }
    setState(() {
      _contacts = [..._contacts, added];
      _message = null;
    });
  }

  Future<void> _removeContact(SosContactInfo c) async {
    final t = S.of(context);
    if (!await _confirm(t.sosContactDeleteAsk(c.name), t.sosDelete)) return;
    if (!mounted) return;
    setState(() => _contacts = [
          for (final x in _contacts)
            if (!identical(x, c)) x,
        ]);
  }

  Future<void> _wipe() async {
    final t = S.of(context);
    if (!await _confirm(t.sosWipeAsk, t.sosDelete)) return;
    await _sos.wipe();
    if (!mounted) return;
    setState(() => _loaded = false);
    await _load();
  }

  Future<void> _readPlace() async {
    final p = await _sos.location();
    if (!mounted) return;
    setState(() => _place = p);
  }

  Future<void> _share(String target) async {
    final ok = await _sos.share(target);
    if (!mounted || ok) return;
    setState(() => _message = S.of(context).sosShareFailed);
  }

  static const _small = TextStyle(fontSize: 10.5, height: 1.5, color: MindColors.ink55);
  static const _body = TextStyle(fontSize: 11.5, height: 1.45, color: MindColors.ink);
  static const _title = TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w700, color: MindColors.ink);

  Widget _field(TextEditingController c, String label, {TextInputType? type, int lines = 1}) => TextField(
        controller: c,
        keyboardType: type,
        minLines: 1,
        maxLines: lines,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label, isDense: true),
      );

  Widget _ready(String label, bool good, {VoidCallback? fix}) {
    final t = S.of(context);
    return Row(
      spacing: 6,
      children: [
        Icon(good ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 16, color: good ? const Color(0xFF1E8E3E) : const Color(0xFFB3261E)),
        Expanded(child: Text(label, style: _body)),
        if (!good && fix != null) TextButton(onPressed: fix, child: Text(t.sosFix)),
      ],
    );
  }

  Widget _group(String title, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [Text(title, style: _title), ...children],
      );

  Widget _watch(S t) {
    final st = _status;
    return _group(t.sosWatchCard, [
      Text(t.sosWatchHint, style: _small),
      Row(
        spacing: MindSpace.md,
        children: [
          Expanded(
            child: Text(t.sosWatchOn,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: MindColors.ink)),
          ),
          Switch(value: _armed, activeTrackColor: widget.accent, onChanged: (v) => unawaited(_setArmed(v))),
        ],
      ),
      if (_armed)
        _ready(st.running ? t.sosRunning : t.sosNotRunning, st.running,
            fix: () => unawaited(_sos.sync().then((_) => _check()))),
      if (st.busy)
        OutlinedButton(
          onPressed: () => unawaited(_sos.stop().then((_) => _check())),
          child: Text(st.silent ? '${t.sosSilentRunning} · ${t.sosStopNow}' : t.sosStopNow),
        ),
      if (_armed)
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E)),
          onPressed: st.busy ? null : () => unawaited(_manual()),
          icon: const Icon(Icons.sos_rounded),
          label: Text(t.sosManualButton),
        ),
      if (_armed) Text(t.sosManualHint, style: _small),
    ]);
  }

  Widget _readiness(S t) {
    final st = _status;
    final perms = context.read<MindPermissions>();
    return _group(t.sosReadyCard, [
      _ready(t.sosReadySensor, st.accel),
      _ready(t.sosReadyLocation, st.location, fix: () => unawaited(_ask('requestSos'))),
      _ready(t.sosReadyBackground, st.background, fix: () => unawaited(_ask('requestSosBackground'))),
      _ready(t.sosReadySms, st.sms, fix: () => unawaited(_ask('requestSos'))),
      _ready(t.sosReadyCall, st.call && st.phone, fix: () => unawaited(_ask('requestSos'))),
      _ready(t.sosReadyDialer, st.dialer, fix: () => unawaited(perms.request(MindPermission.defaultDialer).then((_) => _check()))),
      _ready(t.sosReadyMic, st.mic, fix: () => unawaited(_ask('requestSos'))),
      _ready(t.sosReadyThaiVoice, st.thaiVoice, fix: () => unawaited(_sos.openSetting('tts'))),
      _ready(t.sosReadyNotify, st.notify, fix: () => unawaited(perms.request(MindPermission.notify).then((_) => _check()))),
      _ready(t.sosReadyFullScreen, st.fullScreen, fix: () => unawaited(_sos.openSetting('fullScreen'))),
      _ready(t.sosReadyBattery, st.battExempt, fix: () => unawaited(perms.request(MindPermission.battery).then((_) => _check()))),
      if (st.notEcc.isNotEmpty) Text(t.sosNotEcc(st.notEcc.join(', ')), style: _small),
      Text(t.sosVivoNote, style: _small),
    ]);
  }

  Widget _you(S t) => _group(t.sosYouCard, [
        Text(t.sosYouHint, style: _small),
        _field(_name, t.sosName),
        Row(
          spacing: 8,
          children: [
            Expanded(child: _field(_birth, t.sosBirthYear, type: TextInputType.number)),
            Expanded(child: _field(_blood, t.sosBlood)),
          ],
        ),
        _field(_allergies, t.sosAllergies, lines: 2),
        _field(_conditions, t.sosConditions, lines: 2),
        _field(_medicines, t.sosMedicines, lines: 2),
        _field(_plate, t.sosPlate),
        _field(_notes, t.sosNotes, lines: 3),
      ]);

  Widget _people(S t) => _group(t.sosContactsCard, [
        Text(t.sosContactsHint, style: _small),
        for (final (i, c) in _contacts.indexed)
          Row(
            spacing: 6,
            children: [
              Text('${i + 1}.', style: _body),
              Expanded(child: Text('${c.name} · ${c.number}', style: _body)),
              IconButton(
                onPressed: () => unawaited(_removeContact(c)),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                tooltip: t.sosDelete,
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => unawaited(_addContact()),
            icon: const Icon(Icons.person_add_alt_rounded, size: 16),
            label: Text(t.sosContactAdd),
          ),
        ),
      ]);

  Widget _drills(S t) {
    final drilled = _status.drills >= 1;
    return _group(t.sosDrillCard, [
      Text(t.sosDrillHint, style: _small),
      _field(_test, t.sosTestNumber, type: TextInputType.phone),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _armed && !_status.busy ? () => unawaited(_drill()) : null,
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: Text(t.sosDrillRun),
          ),
          OutlinedButton.icon(
            onPressed: _armed && !_status.busy ? () => unawaited(_drill(silent: true)) : null,
            icon: const Icon(Icons.volume_off_rounded, size: 16),
            label: Text(t.sosDrillSilentRun),
          ),
          Text(t.sosDrillCount(_status.drills), style: _small),
        ],
      ),
      Row(
        spacing: MindSpace.md,
        children: [
          Expanded(
            child: Text(t.sosAutoCall,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: MindColors.ink)),
          ),
          Switch(
            value: _autoCall && drilled,
            activeTrackColor: widget.accent,
            onChanged: drilled && _armed ? (v) => unawaited(_setAutoCall(v)) : null,
          ),
        ],
      ),
      Text(drilled ? t.sosAutoCallHint : t.sosAutoCallLocked, style: _small),
      if (_armed && !_status.dialer) Text(t.sosDialerWarn, style: _small),
      Text(t.sosCountdown(_countdown), style: _body),
      Slider(
        value: _countdown.toDouble(),
        min: 10,
        max: 120,
        divisions: 22,
        activeColor: widget.accent,
        onChanged: (v) => setState(() => _countdown = v.round()),
      ),
      Text(t.sosSensitivity, style: _body),
      SegmentedButton<int>(
        segments: [
          ButtonSegment(value: 0, label: Text(t.sosSensLow)),
          ButtonSegment(value: 1, label: Text(t.sosSensMid)),
          ButtonSegment(value: 2, label: Text(t.sosSensHigh)),
        ],
        selected: {_sensitivity},
        onSelectionChanged: (s) => setState(() => _sensitivity = s.first),
      ),
    ]);
  }

  Widget _location(S t) {
    final p = _place;
    return _group(t.sosPlaceCard, [
      if (p == null)
        Text(t.sosPlaceNone, style: _body)
      else ...[
        SelectableText(p.link, style: _body),
        SelectableText('${p.coords} · Plus ${p.plus}', style: _body),
        Text(
          '${p.accuracy == null ? '' : '±${p.accuracy!.toStringAsFixed(0)} m · '}${t.sosPlaceAge(p.ageMinutes)}',
          style: _small,
        ),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          TextButton(onPressed: () => unawaited(_readPlace()), child: Text(t.sosPlaceRefresh)),
          if (p != null) ...[
            OutlinedButton(onPressed: () => unawaited(_share('copy')), child: Text(t.sosShareCopy)),
            OutlinedButton(onPressed: () => unawaited(_share('sms')), child: Text(t.sosShareSms)),
            OutlinedButton(onPressed: () => unawaited(_share('line')), child: Text(t.sosShareLine)),
            OutlinedButton(onPressed: () => unawaited(_share('any')), child: Text(t.sosShareAny)),
          ],
        ],
      ),
      Text(t.sosShareNote, style: _small),
    ]);
  }

  Widget _log(S t) {
    final st = _status;
    final last = st.lastReport;
    return _group(t.sosLogCard, [
      Text(t.sosLogBattery(st.armedMinutes, st.tripMinutes, st.batteryDrop), style: _body),
      if (!st.lowPower && st.accel) Text(t.sosLowPowerMissing, style: _small),
      if (st.readings.isEmpty)
        Text(t.sosLogEmpty, style: _small)
      else
        for (final r in st.readings.take(8))
          Text(
            '${DateTime.fromMillisecondsSinceEpoch(r.atMs).toLocal().toString().substring(5, 16)} · '
            '${r.peakG.toStringAsFixed(1)} g · Δv ${r.deltaV.toStringAsFixed(1)} · '
            '${r.before?.toStringAsFixed(0) ?? '?'} km/h · ${t.sosVerdict(r.verdict)}',
            style: _small,
          ),
      if (last.isNotEmpty) ...[
        Text(st.lastCancelled ? '${t.sosLastCard} · ${t.sosLastCancelled}' : t.sosLastCard, style: _body),
        for (final o in last) Text(t.sosOutcome(o.who, o.outcome), style: _small),
      ],
    ]);
  }

  Widget _numbers(S t) => _group(t.sosNumbersCard, [
        for (final n in SosDirectory.reference)
          Text('${n.number}  ${t.pick(n.th, n.en)}', style: _body),
        Text(t.sosNumbersHint, style: _small),
      ]);

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    if (!_loaded) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: MindSpace.lg,
      children: [
        _watch(t),
        if (_armed) _readiness(t),
        _you(t),
        _people(t),
        _drills(t),
        if (_message != null) Text(_message!, style: _body),
        FilledButton(
          onPressed: _dirty ? () => unawaited(_save()) : null,
          style: FilledButton.styleFrom(backgroundColor: widget.accent),
          child: Text(t.sosSave),
        ),
        _location(t),
        _log(t),
        _numbers(t),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => unawaited(_wipe()),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: Text(t.sosWipe),
          ),
        ),
      ],
    );
  }
}

/// สร้าง controller ใน State · ตัวแปรใน builder ของ StatefulBuilder รีเซ็ตทุกรอบ และต้อง dispose เอง
class _ContactDialog extends StatefulWidget {
  const _ContactDialog();

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final _name = TextEditingController();
  final _number = TextEditingController();
  bool _health = true;

  @override
  void dispose() {
    _name.dispose();
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return AlertDialog(
      title: Text(t.sosContactAdd),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _name, decoration: InputDecoration(labelText: t.sosContactName)),
          TextField(
            controller: _number,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: t.sosContactNumber),
          ),
          CheckboxListTile(
            value: _health,
            contentPadding: EdgeInsets.zero,
            title: Text(t.sosContactHealth, style: const TextStyle(fontSize: 12)),
            onChanged: (v) => setState(() => _health = v ?? false),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(t.sosCancel)),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final number = _number.text.trim();
            if (name.isEmpty || number.isEmpty) return;
            Navigator.pop(context, SosContactInfo(name: name, number: number, health: _health));
          },
          child: Text(t.sosSave),
        ),
      ],
    );
  }
}
