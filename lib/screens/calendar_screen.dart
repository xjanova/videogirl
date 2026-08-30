import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../calendar/device_calendar.dart';
import '../i18n/strings.dart';
import '../state/mind_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_background.dart';
import '../widgets/screen_header.dart';

/// ตารางนัดจริงของเจ้าของ อ่านจากปฏิทินของเครื่อง
///
/// **ของเดิมเป็นภาพนิ่ง** — `_Slot(title: t.calStandup, time: '09:00–09:30')`
/// กับการ์ด "เธอเสนอ 15:00–15:30" และคนสองคนชื่อคุณต้นกับคุณนภาที่ไม่มีตัวตน
/// สวย แต่ไม่ใช่ตารางของใครทั้งนั้น และปุ่มทุกปุ่มเปิดกล่อง "นี่คือตัวอย่าง"
///
/// ตอนนี้อ่านของจริงจาก [DeviceCalendar] · สิ่งที่เธอทำไม่ได้ (จองเวลา
/// ส่งคำเชิญ หาเวลาที่ทุกคนว่าง) **เอาปุ่มออกแล้ว** ปุ่มที่กดแล้วบอกว่า
/// "นี่คือตัวอย่าง" แย่กว่าไม่มีปุ่ม เพราะมันสัญญาสิ่งที่แอปทำไม่ได้
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  @override
  void initState() {
    super.initState();
    // โหลดหลังเฟรมแรก ไม่ใช่ระหว่าง build — build ต้องไม่มีผลข้างเคียง
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    await context.read<DeviceCalendar>().load();
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.select<MindState, MindMode>((s) => s.mode);
    final cal = context.watch<DeviceCalendar>();
    final t = S.of(context);

    return LiquidBackground(
      gradient: MindGradients.calendar,
      orbs: Orb.calendar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MindScreenHeader(
              overline: t.tabCalendar,
              title: t.dayLabel(DateTime.now()),
              subtitle: _subtitle(cal, t),
            ),
            Expanded(child: _body(context, cal, mode, t)),
          ],
        ),
      ),
    );
  }

  /// พาดหัวรองบอกภาพรวม ไม่ใช่คำโฆษณา
  String _subtitle(DeviceCalendar cal, S t) => switch (cal.stage) {
        CalendarStage.ready =>
          cal.events.isEmpty ? t.calNoneToday : t.calCount(cal.events.length),
        CalendarStage.denied => t.calNeedPermission,
        CalendarStage.failed => t.calFailed,
        _ => t.calLoading,
      };

  Widget _body(BuildContext context, DeviceCalendar cal, MindMode mode, S t) {
    switch (cal.stage) {
      case CalendarStage.idle:
      case CalendarStage.loading:
        return const Center(child: CircularProgressIndicator());

      case CalendarStage.denied:
        return _message(
          mode,
          icon: Icons.event_busy_rounded,
          title: t.calNeedPermission,
          body: t.calNeedPermissionWhy,
          action: (t.calGrant, Icons.check_rounded, () => cal.requestThenLoad()),
        );

      case CalendarStage.failed:
        return _message(
          mode,
          icon: Icons.error_outline_rounded,
          title: t.calFailed,
          body: t.calNeedPermissionWhy,
          action: (t.refresh, Icons.refresh_rounded, _load),
        );

      case CalendarStage.ready:
        return RefreshIndicator(onRefresh: _load, child: _agenda(cal, mode, t));
    }
  }

  /// รายการนัดจริง จัดกลุ่มตามวัน
  ///
  /// ต้องเป็น ListView เสมอแม้ไม่มีนัด ไม่งั้น RefreshIndicator ดึงไม่ลง
  /// แล้วคนที่เพิ่งเพิ่มนัดในปฏิทินจะรีเฟรชไม่ได้
  Widget _agenda(DeviceCalendar cal, MindMode mode, S t) {
    final days = cal.byDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          MindSpace.lg, 0, MindSpace.lg, MindSpace.xxl),
      children: [
        if (cal.today.isEmpty) _restOfDay(cal, mode, t),
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, MindSpace.md, 4, MindSpace.sm),
            child: MindSectionLabel(_dayHeading(day.key, t)),
          ),
          for (final e in day.value) ...[
            _Slot(event: e, mode: mode, t: t),
            const SizedBox(height: MindSpace.sm),
          ],
        ],
        if (cal.today.isNotEmpty && cal.next == null) ...[
          const SizedBox(height: MindSpace.md),
          _restOfDay(cal, mode, t),
        ],
      ],
    );
  }

  /// วันนี้/พรุ่งนี้อ่านง่ายกว่าวันที่เสมอ ที่เหลือใช้ชื่อวัน
  String _dayHeading(DateTime day, S t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return t.calToday;
    if (diff == 1) return t.calTomorrow;
    return t.dayLabel(day);
  }

  /// ปิดท้ายด้วยคำตอบ ไม่ใช่ปล่อยว่าง
  ///
  /// ที่ว่างครึ่งจอที่ไม่มีอะไรเลยอ่านได้สองแบบ — "โหลดไม่เสร็จ" กับ
  /// "ไม่มีนัดแล้ว" · แบบหลังเป็นข่าวดีแต่ไม่มีใครรู้เพราะไม่ได้พูดออกมา
  Widget _restOfDay(DeviceCalendar cal, MindMode mode, S t) {
    final free = _freeHoursLeft(cal);

    return GlassPanel(
      radius: MindRadius.card,
      fill: MindColors.glass55,
      shadows: MindShadows.soft(),
      padding: const EdgeInsets.symmetric(
          vertical: MindSpace.xl, horizontal: MindSpace.lg),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                mode.accent.withValues(alpha: .18),
                mode.accent.withValues(alpha: .02),
              ]),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.wb_twilight_rounded,
                size: 34, color: mode.accent.withValues(alpha: .85)),
          ),
          const SizedBox(height: MindSpace.md),
          Text(cal.today.isEmpty ? t.calNoneToday : t.calRestClear,
              style: MindType.title, textAlign: TextAlign.center),
          if (free > 0) ...[
            const SizedBox(height: MindSpace.xs),
            Text(t.calRestHours(free),
                style: MindType.caption, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  /// ชั่วโมงว่างที่เหลือของวันนี้ — นับถึงเที่ยงคืน ไม่ใช่ตัวเลขที่ตั้งไว้ตายตัว
  ///
  /// ของเดิมเขียน `t.calRestHours(4)` ไว้ตรง ๆ ซึ่งแปลว่าตอนตีหนึ่งก็ยังบอก
  /// ว่าเหลือสี่ชั่วโมง
  int _freeHoursLeft(DeviceCalendar cal) {
    final now = DateTime.now();
    final endOfDay = DateTime(now.year, now.month, now.day + 1);
    final last = cal.today
        .where((e) => e.end.isAfter(now))
        .fold<DateTime>(now, (a, e) => e.end.isAfter(a) ? e.end : a);
    return endOfDay.difference(last).inHours.clamp(0, 24);
  }

  Widget _message(
    MindMode mode, {
    required IconData icon,
    required String title,
    required String body,
    required (String, IconData, Future<void> Function()) action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MindSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: MindColors.ink22),
            const SizedBox(height: MindSpace.md),
            Text(title, style: MindType.title, textAlign: TextAlign.center),
            const SizedBox(height: MindSpace.sm),
            Text(body, style: MindType.caption, textAlign: TextAlign.center),
            const SizedBox(height: MindSpace.lg),
            MindButton(
              label: action.$1,
              kind: MindButtonKind.primary,
              icon: action.$2,
              mode: mode,
              onTap: action.$3,
            ),
          ],
        ),
      ),
    );
  }
}

/// นัดหนึ่งนัดที่มีอยู่จริงในปฏิทิน
class _Slot extends StatelessWidget {
  const _Slot({required this.event, required this.mode, required this.t});

  final CalendarEvent event;
  final MindMode mode;
  final S t;

  @override
  Widget build(BuildContext context) {
    final now = event.isNow;

    return GlassPanel(
      radius: 22,
      fill: MindColors.glass62,
      filter: MindGlass.light,
      shadows: MindShadows.soft(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          // แถบสีของปฏิทินต้นทาง — เครื่องหนึ่งมักมีหลายบัญชี
          // งานกับส่วนตัวปนกัน สีเป็นทางเดียวที่แยกออกโดยไม่ต้องอ่าน
          Container(
            width: 3,
            height: 34,
            margin: const EdgeInsets.only(right: 11),
            decoration: BoxDecoration(
              color: event.color != null
                  ? Color(event.color!).withValues(alpha: .85)
                  : mode.accent.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // นัดที่ไม่มีชื่อยังเป็นนัด — โชว์เวลาแทนดีกว่าโชว์ช่องว่าง
                  event.title.isEmpty ? _time() : event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: event.isPast ? MindColors.ink45 : null,
                  ),
                ),
                if (now || (event.location?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 2),
                  Text(
                    now ? t.calNow : event.location!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MindType.caption.copyWith(
                      fontSize: 10.5,
                      color: now ? mode.accent : MindColors.ink55,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: MindSpace.sm),
          Text(_time(),
              style: mindMono(
                size: 11,
                color: event.isPast ? MindColors.ink22 : MindColors.ink55,
              )),
        ],
      ),
    );
  }

  String _time() {
    if (event.allDay) return t.calAllDay;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(event.begin.hour)}:${two(event.begin.minute)}'
        '–${two(event.end.hour)}:${two(event.end.minute)}';
  }
}
