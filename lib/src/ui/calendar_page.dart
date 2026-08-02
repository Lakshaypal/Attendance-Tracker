import 'package:flutter/material.dart';

import '../civil_date.dart';
import '../models.dart';
import '../store.dart';
import 'design.dart';
import 'sheets.dart';

/// Month calendar with a day panel underneath. Swipe or use the arrows to move
/// between months; tap a day to mark its classes.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.store});

  final AttendanceStore store;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  /// Arbitrary mid-point so the user can page backwards as far as forwards.
  static const int _originPage = 6000;

  /// Null means "follow today", so leaving the app open past midnight moves
  /// the selection with the date instead of stranding it on yesterday.
  int? _pinnedDay;
  late final int _originMonthStart = startOfMonth(todayEpochDay());
  late final PageController _controller = PageController(
    initialPage: _originPage,
  );

  AttendanceStore get store => widget.store;

  int get _selectedDay => _pinnedDay ?? todayEpochDay();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int _monthStartForPage(int page) =>
      addMonths(_originMonthStart, page - _originPage);

  void _jumpToToday() {
    final today = todayEpochDay();
    setState(() => _pinnedDay = null);
    final targetMonth = startOfMonth(today);
    final delta = _monthsBetween(_originMonthStart, targetMonth);
    _controller.animateToPage(
      _originPage + delta,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  static int _monthsBetween(int fromMonthStart, int toMonthStart) {
    final from = ymdFromEpochDay(fromMonthStart);
    final to = ymdFromEpochDay(toMonthStart);
    return (to.year - from.year) * 12 + (to.month - from.month);
  }

  @override
  Widget build(BuildContext context) {
    final today = todayEpochDay();
    return PageFrame(
      title: 'Calendar',
      subtitle: 'Tap any day to mark what happened',
      actions: [
        if (_selectedDay != today)
          TextButton(onPressed: _jumpToToday, child: const Text('Today')),
        IconButton(
          tooltip: 'Add a one-off class',
          onPressed: () =>
              showRecordSheet(context, store, initialDay: _selectedDay),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: Column(
        children: [
          SizedBox(
            height: _monthHeight(_monthStartForPage(_currentPage)),
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (_) => setState(() {}),
              itemBuilder: (context, page) => _MonthView(
                store: store,
                monthStart: _monthStartForPage(page),
                selectedDay: _selectedDay,
                onSelect: (day) => setState(() => _pinnedDay = day),
                onStep: (delta) => _controller.animateToPage(
                  page + delta,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Divider(),
          Expanded(
            child: _DayPanel(store: store, epochDay: _selectedDay),
          ),
        ],
      ),
    );
  }

  int get _currentPage => _controller.hasClients && _controller.page != null
      ? _controller.page!.round()
      : _originPage;

  /// Enough height for the weekday strip, the header, and however many week
  /// rows this month actually needs.
  double _monthHeight(int monthStart) {
    final ymd = ymdFromEpochDay(monthStart);
    final leading = weekdayOfEpochDay(monthStart) - 1;
    final rows = ((leading + daysInMonth(ymd.year, ymd.month)) / 7).ceil();
    return 40 + 22 + rows * _MonthView.rowHeight;
  }
}

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.store,
    required this.monthStart,
    required this.selectedDay,
    required this.onSelect,
    required this.onStep,
  });

  static const double rowHeight = 44;

  final AttendanceStore store;
  final int monthStart;
  final int selectedDay;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final ymd = ymdFromEpochDay(monthStart);
    final leading = weekdayOfEpochDay(monthStart) - 1;
    final length = daysInMonth(ymd.year, ymd.month);
    final rows = ((leading + length) / 7).ceil();
    final today = todayEpochDay();

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              IconButton(
                onPressed: () => onStep(-1),
                icon: const Icon(Icons.chevron_left_rounded),
                visualDensity: VisualDensity.compact,
                tooltip: 'Previous month',
              ),
              Expanded(
                child: Text(
                  formatMonthYear(monthStart),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => onStep(1),
                icon: const Icon(Icons.chevron_right_rounded),
                visualDensity: VisualDensity.compact,
                tooltip: 'Next month',
              ),
            ],
          ),
        ),
        SizedBox(
          height: 22,
          child: Row(
            children: [
              for (final name in shortWeekdayNames)
                Expanded(
                  child: Center(
                    child: Text(
                      name[0],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: subtleInk(context),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (var row = 0; row < rows; row++)
          SizedBox(
            height: rowHeight,
            child: Row(
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final dayOfMonth = row * 7 + column - leading + 1;
                        if (dayOfMonth < 1 || dayOfMonth > length) {
                          return const SizedBox.shrink();
                        }
                        final epochDay = monthStart + dayOfMonth - 1;
                        return _DayCell(
                          dayOfMonth: dayOfMonth,
                          summary: store.daySummary(epochDay),
                          isToday: epochDay == today,
                          isSelected: epochDay == selectedDay,
                          isPast: epochDay < today,
                          onTap: () => onSelect(epochDay),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.dayOfMonth,
    required this.summary,
    required this.isToday,
    required this.isSelected,
    required this.isPast,
    required this.onTap,
  });

  final int dayOfMonth;
  final DaySummary summary;
  final bool isToday;
  final bool isSelected;
  final bool isPast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unlogged = summary.scheduled > summary.marked;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.14)
              : (summary.scheduled > 0
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
                    : null),
          borderRadius: BorderRadius.circular(11),
          border: isSelected
              ? Border.all(color: scheme.primary, width: 1.4)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 21,
              height: 21,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday ? scheme.primary : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$dayOfMonth',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday || isSelected
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: isToday
                      ? scheme.onPrimary
                      : (summary.scheduled == 0 ? subtleInk(context) : null),
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ..._dots(),
                  if (unlogged && isPast)
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.outline.withValues(alpha: 0.7),
                          width: 1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// At most three filled dots, so a busy day stays readable.
  List<Widget> _dots() {
    final dots = <Widget>[];
    void add(int count, AttendanceStatus status) {
      if (count == 0 || dots.length >= 3) return;
      dots.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: StatusDot(status: status, size: 5),
        ),
      );
    }

    add(summary.attended, AttendanceStatus.attended);
    add(summary.bunked, AttendanceStatus.individualBunk);
    add(summary.massBunked, AttendanceStatus.massBunk);
    add(summary.holidays, AttendanceStatus.govtHoliday);
    return dots;
  }
}

class _DayPanel extends StatelessWidget {
  const _DayPanel({required this.store, required this.epochDay});

  final AttendanceStore store;
  final int epochDay;

  @override
  Widget build(BuildContext context) {
    final slots = store.classesOn(epochDay);
    final extras = store
        .recordsOn(epochDay)
        .where((record) => record.timetableClassId == null)
        .toList();

    final unmarked = slots
        .where((slot) => store.recordForSlot(slot.id, epochDay) == null)
        .length;

    return ListView(
      padding: const EdgeInsets.only(top: 10, bottom: 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                formatDayLong(epochDay),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (slots.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Mark the whole day',
                icon: const Icon(Icons.done_all_rounded, size: 20),
                onSelected: (choice) => _applyBulk(context, choice),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'attended',
                    enabled: unmarked > 0,
                    child: const Text('Mark remaining as attended'),
                  ),
                  const PopupMenuItem(
                    value: 'holiday',
                    child: Text('Whole day was a holiday'),
                  ),
                  const PopupMenuItem(
                    value: 'clear',
                    child: Text('Clear every mark'),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (slots.isEmpty && extras.isEmpty)
          _NothingScheduled(store: store, epochDay: epochDay)
        else ...[
          for (final slot in slots)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SlotRow(store: store, slot: slot, epochDay: epochDay),
            ),
          for (final record in extras)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ExtraRow(store: store, record: record),
            ),
        ],
      ],
    );
  }

  Future<void> _applyBulk(BuildContext context, String choice) async {
    switch (choice) {
      case 'attended':
        store.markWholeDay(epochDay, AttendanceStatus.attended);
      case 'holiday':
        store.markWholeDay(
          epochDay,
          AttendanceStatus.govtHoliday,
          overwrite: true,
        );
      case 'clear':
        final ok = await confirm(
          context,
          title: 'Clear this day?',
          message:
              'Every mark on ${formatDay(epochDay)} will be removed. '
              'The classes stay in your timetable.',
          confirmLabel: 'Clear',
        );
        if (ok) store.clearDay(epochDay);
    }
  }
}

class _NothingScheduled extends StatelessWidget {
  const _NothingScheduled({required this.store, required this.epochDay});

  final AttendanceStore store;
  final int epochDay;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 22),
    child: Column(
      children: [
        Icon(
          Icons.beach_access_rounded,
          size: 34,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 10),
        Text(
          'Nothing scheduled',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: subtleInk(context),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () =>
              showRecordSheet(context, store, initialDay: epochDay),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add a one-off class'),
        ),
      ],
    ),
  );
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.store,
    required this.slot,
    required this.epochDay,
  });

  final AttendanceStore store;
  final TimetableClass slot;
  final int epochDay;

  @override
  Widget build(BuildContext context) {
    final course = store.courseById(slot.courseId);
    if (course == null) return const SizedBox.shrink();
    final record = store.recordForSlot(slot.id, epochDay);

    return Card(
      child: InkWell(
        onTap: () =>
            showMarkSheet(context, store, slot: slot, epochDay: epochDay),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  formatMinuteCompact(slot.startMinute),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              CourseBadge(course: course, size: 38),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      [
                        formatTimeRange(slot.startMinute, slot.durationMinutes),
                        if (slot.title != null) slot.title!,
                        if (slot.room != null) slot.room!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: subtleInk(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (record != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: record.status.tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        record.status.icon,
                        size: 13,
                        color: record.status.tint,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        record.status.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: record.status.tint,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Icon(
                  Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.outline,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExtraRow extends StatelessWidget {
  const _ExtraRow({required this.store, required this.record});

  final AttendanceStore store;
  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final course = store.courseById(record.courseId);
    if (course == null) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        onTap: () => showRecordSheet(context, store, record: record),
        leading: CourseBadge(course: course, size: 38),
        title: Text(
          course.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            'One-off',
            record.status.label,
            if (record.note != null) record.note!,
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
          onPressed: () async {
            final ok = await confirm(
              context,
              title: 'Delete this record?',
              message: '${course.code} on ${formatDay(record.epochDay)}.',
            );
            if (ok) store.deleteRecord(record);
          },
        ),
      ),
    );
  }
}
