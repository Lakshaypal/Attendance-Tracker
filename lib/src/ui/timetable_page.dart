import 'package:flutter/material.dart';

import '../civil_date.dart';
import '../models.dart';
import '../schedule_layout.dart';
import '../store.dart';
import 'design.dart';
import 'scan_page.dart';
import 'sheets.dart';

/// The weekly timetable in grid form: real time down the side, one column per
/// day, overlapping classes packed into side-by-side lanes.
class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key, required this.store});

  final AttendanceStore store;

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  /// Null means "follow today". Storing the week only once the user has moved
  /// away keeps the page correct when the date rolls over while the app is
  /// open.
  int? _pinnedWeekStart;

  AttendanceStore get store => widget.store;

  int get _weekStart => _pinnedWeekStart ?? startOfWeek(todayEpochDay());

  void _shiftWeek(int weeks) =>
      setState(() => _pinnedWeekStart = _weekStart + weeks * 7);

  @override
  Widget build(BuildContext context) {
    final days = _visibleWeekdays();
    final today = todayEpochDay();
    final weekStart = _weekStart;
    final isCurrentWeek = weekStart == startOfWeek(today);
    final lastDay = weekStart + (days.isEmpty ? 6 : days.last - 1);

    return PageFrame(
      title: 'Timetable',
      subtitle: '${formatDay(weekStart)} – ${formatDay(lastDay)}',
      actions: [
        IconButton(
          tooltip: 'Add class',
          onPressed: () => showSlotSheet(context, store),
          icon: const Icon(Icons.add_rounded),
        ),
        IconButton.filledTonal(
          tooltip: 'Scan a timetable photo',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ScanTimetablePage(store: store),
            ),
          ),
          icon: const Icon(Icons.photo_camera_rounded),
        ),
      ],
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 0),
      child: Column(
        children: [
          _WeekBar(
            onPrevious: () => _shiftWeek(-1),
            onNext: () => _shiftWeek(1),
            onToday: isCurrentWeek
                ? null
                : () => setState(() => _pinnedWeekStart = null),
            label: isCurrentWeek ? 'This week' : formatMonthYear(weekStart),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: days.isEmpty
                ? EmptyState(
                    icon: Icons.grid_view_rounded,
                    title: 'Your timetable is empty',
                    message:
                        'Photograph your printed timetable and the classes '
                        'will be filled in for you.',
                    action: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ScanTimetablePage(store: store),
                        ),
                      ),
                      icon: const Icon(Icons.photo_camera_rounded),
                      label: const Text('Scan a photo'),
                    ),
                  )
                : WeekGrid(store: store, weekStart: weekStart, weekdays: days),
          ),
        ],
      ),
    );
  }

  /// Monday–Friday by default, plus any weekend day that holds a class, that
  /// the user has asked for, or that happens to be today — a Saturday should
  /// never leave the student staring at a week with no "today" in it.
  List<int> _visibleWeekdays() {
    if (store.timetable.isEmpty) return const [];
    final todayWeekday = weekdayOfEpochDay(todayEpochDay());
    final days = <int>[for (var day = 1; day <= 5; day++) day];
    for (final day in [DateTime.saturday, DateTime.sunday]) {
      if (store.settings.showWeekends ||
          store.classesForWeekday(day).isNotEmpty ||
          (day == todayWeekday && _pinnedWeekStart == null)) {
        days.add(day);
      }
    }
    return days;
  }
}

class _WeekBar extends StatelessWidget {
  const _WeekBar({
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.label,
  });

  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onToday;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        onPressed: onPrevious,
        icon: const Icon(Icons.chevron_left_rounded),
        tooltip: 'Previous week',
        visualDensity: VisualDensity.compact,
      ),
      Expanded(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      IconButton(
        onPressed: onNext,
        icon: const Icon(Icons.chevron_right_rounded),
        tooltip: 'Next week',
        visualDensity: VisualDensity.compact,
      ),
      if (onToday != null)
        TextButton(onPressed: onToday, child: const Text('Today')),
    ],
  );
}

class WeekGrid extends StatelessWidget {
  const WeekGrid({
    super.key,
    required this.store,
    required this.weekStart,
    required this.weekdays,
  });

  final AttendanceStore store;
  final int weekStart;
  final List<int> weekdays;

  static const double _gutterWidth = 44;
  static const double _headerHeight = 46;
  static const double _minColumnWidth = 104;
  static const double _minPixelsPerMinute = 0.85;

  @override
  Widget build(BuildContext context) {
    // One packing pass per day, reused for both measuring and painting.
    final packedDays = [
      for (final weekday in weekdays)
        packOverlaps(store.classesForWeekday(weekday)),
    ];
    final bounds = gridBounds(weekdays.map(store.classesForWeekday));
    final totalMinutes = bounds.endMinute - bounds.startMinute;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bodyHeight = constraints.maxHeight - _headerHeight;
        final pixelsPerMinute = bodyHeight <= 0
            ? _minPixelsPerMinute
            : (bodyHeight / totalMinutes).clamp(_minPixelsPerMinute, 1.6);
        final gridHeight = totalMinutes * pixelsPerMinute;
        final columnWidth =
            ((constraints.maxWidth - _gutterWidth) / weekdays.length).clamp(
              _minColumnWidth,
              double.infinity,
            );
        final totalWidth = _gutterWidth + columnWidth * weekdays.length;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth,
            child: Column(
              children: [
                SizedBox(
                  height: _headerHeight,
                  child: Row(
                    children: [
                      const SizedBox(width: _gutterWidth),
                      for (final weekday in weekdays)
                        SizedBox(
                          width: columnWidth,
                          child: _DayHeader(epochDay: weekStart + weekday - 1),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: SizedBox(
                      height: gridHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: _gutterWidth,
                            child: _HourGutter(
                              startMinute: bounds.startMinute,
                              endMinute: bounds.endMinute,
                              pixelsPerMinute: pixelsPerMinute,
                            ),
                          ),
                          for (var i = 0; i < weekdays.length; i++)
                            SizedBox(
                              width: columnWidth,
                              child: _DayColumn(
                                store: store,
                                epochDay: weekStart + weekdays[i] - 1,
                                placed: packedDays[i],
                                startMinute: bounds.startMinute,
                                endMinute: bounds.endMinute,
                                pixelsPerMinute: pixelsPerMinute,
                                width: columnWidth,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.epochDay});

  final int epochDay;

  @override
  Widget build(BuildContext context) {
    final isToday = epochDay == todayEpochDay();
    final ymd = ymdFromEpochDay(epochDay);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          weekdayName(weekdayOfEpochDay(epochDay)).toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w700,
            color: isToday ? scheme.primary : subtleInk(context),
          ),
        ),
        const SizedBox(height: 3),
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isToday ? scheme.primary : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Text(
            '${ymd.day}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isToday ? scheme.onPrimary : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _HourGutter extends StatelessWidget {
  const _HourGutter({
    required this.startMinute,
    required this.endMinute,
    required this.pixelsPerMinute,
  });

  final int startMinute;
  final int endMinute;
  final double pixelsPerMinute;

  @override
  Widget build(BuildContext context) {
    final labels = <Widget>[];
    for (var minute = startMinute; minute < endMinute; minute += 60) {
      labels.add(
        Positioned(
          top: (minute - startMinute) * pixelsPerMinute - 6,
          right: 6,
          child: Text(
            formatMinuteCompact(minute),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: subtleInk(context),
            ),
          ),
        ),
      );
    }
    return Stack(clipBehavior: Clip.none, children: labels);
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.store,
    required this.epochDay,
    required this.placed,
    required this.startMinute,
    required this.endMinute,
    required this.pixelsPerMinute,
    required this.width,
  });

  final AttendanceStore store;
  final int epochDay;
  final List<PlacedClass> placed;
  final int startMinute;
  final int endMinute;
  final double pixelsPerMinute;
  final double width;

  @override
  Widget build(BuildContext context) {
    final isToday = epochDay == todayEpochDay();
    final nowMinute = nowMinuteOfDay();
    final showNowLine =
        isToday && nowMinute >= startMinute && nowMinute <= endMinute;
    final scheme = Theme.of(context).colorScheme;
    // The usable width leaves a hairline gutter so neighbouring columns read
    // as separate.
    const horizontalPadding = 2.0;
    final usableWidth = width - horizontalPadding * 2;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isToday ? scheme.primary.withValues(alpha: 0.04) : null,
        border: Border(
          left: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Hour rules are one paint for the whole column rather than a widget
          // per line.
          Positioned.fill(
            child: CustomPaint(
              painter: _HourRulePainter(
                startMinute: startMinute,
                endMinute: endMinute,
                pixelsPerMinute: pixelsPerMinute,
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          for (final item in placed)
            Positioned(
              top: (item.slot.startMinute - startMinute) * pixelsPerMinute,
              height: item.slot.durationMinutes * pixelsPerMinute,
              left: horizontalPadding + usableWidth * item.leftFraction,
              width: usableWidth * item.widthFraction,
              child: _SlotBlock(
                store: store,
                slot: item.slot,
                epochDay: epochDay,
              ),
            ),
          if (showNowLine)
            Positioned(
              top: (nowMinute - startMinute) * pixelsPerMinute,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: scheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Container(height: 1.4, color: scheme.error),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HourRulePainter extends CustomPainter {
  const _HourRulePainter({
    required this.startMinute,
    required this.endMinute,
    required this.pixelsPerMinute,
    required this.color,
  });

  final int startMinute;
  final int endMinute;
  final double pixelsPerMinute;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var minute = startMinute; minute <= endMinute; minute += 60) {
      final y = (minute - startMinute) * pixelsPerMinute;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_HourRulePainter oldDelegate) =>
      oldDelegate.startMinute != startMinute ||
      oldDelegate.endMinute != endMinute ||
      oldDelegate.pixelsPerMinute != pixelsPerMinute ||
      oldDelegate.color != color;
}

class _SlotBlock extends StatelessWidget {
  const _SlotBlock({
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
    final accent = courseColor(course);
    final marked = record != null;

    return Padding(
      padding: const EdgeInsets.only(right: 2, bottom: 2),
      child: Material(
        color: marked
            ? record.status.tint.withValues(alpha: 0.15)
            : courseSurface(context, course),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () =>
              showMarkSheet(context, store, slot: slot, epochDay: epochDay),
          onLongPress: () => showSlotSheet(context, store, slot: slot),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border(
                left: BorderSide(
                  color: marked ? record.status.tint : accent,
                  width: 3,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(5, 4, 3, 4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tall = constraints.maxHeight >= 46;
                final roomy = constraints.maxHeight >= 68;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            course.code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: courseInk(context, course),
                            ),
                          ),
                        ),
                        if (marked)
                          Icon(
                            record.status.icon,
                            size: 12,
                            color: record.status.tint,
                          ),
                      ],
                    ),
                    if (tall)
                      Text(
                        formatMinuteCompact(slot.startMinute),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: subtleInk(context),
                        ),
                      ),
                    if (roomy && slot.title != null)
                      Expanded(
                        child: Text(
                          slot.title!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.5,
                            height: 1.15,
                            color: subtleInk(context),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
