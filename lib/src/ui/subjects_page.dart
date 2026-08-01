import 'package:flutter/material.dart';

import '../civil_date.dart';
import '../models.dart';
import '../store.dart';
import 'design.dart';
import 'sheets.dart';

/// Attendance is reported per subject only — there is deliberately no combined
/// figure, because a college checks each course against the threshold on its
/// own.
class SubjectsPage extends StatelessWidget {
  const SubjectsPage({
    super.key,
    required this.store,
    required this.onPickSubjects,
  });

  final AttendanceStore store;

  /// Sends the user to the subject picker when they have chosen nothing yet.
  final VoidCallback onPickSubjects;

  @override
  Widget build(BuildContext context) {
    final threshold = store.settings.thresholdPercent;
    // Only the subjects the student actually takes; the rest of the stored
    // timetable belongs to other people in the class group.
    final courses = [...store.enrolledCourses]
      ..sort((a, b) {
        final left = store.statsFor(a.id).percent;
        final right = store.statsFor(b.id).percent;
        // Courses in trouble float to the top; unmarked courses sink.
        if (left == null && right == null) return a.code.compareTo(b.code);
        if (left == null) return 1;
        if (right == null) return -1;
        return left.compareTo(right);
      });

    return PageFrame(
      title: 'Attendance',
      subtitle: 'Each subject is tracked against its own target',
      actions: [
        TextButton.icon(
          onPressed: () => _editThreshold(context),
          icon: const Icon(Icons.flag_rounded, size: 18),
          label: Text('${threshold.round()}%'),
        ),
      ],
      child: courses.isEmpty
          ? EmptyState(
              icon: Icons.school_rounded,
              title: 'You have not picked any subjects',
              message:
                  'Choose the ones you are registered for and their attendance '
                  'shows up here.',
              action: FilledButton.icon(
                onPressed: onPickSubjects,
                icon: const Icon(Icons.checklist_rounded),
                label: const Text('Pick my subjects'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: 28),
              itemCount: courses.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _SubjectCard(
                store: store,
                course: courses[index],
                threshold: threshold,
              ),
            ),
    );
  }

  Future<void> _editThreshold(BuildContext context) async {
    var value = store.settings.thresholdPercent;
    await showAppSheet<void>(
      context,
      title: 'Attendance target',
      subtitle: 'Used for the colour coding and the skip advice.',
      builder: (sheetContext, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${value.round()}%',
            textAlign: TextAlign.center,
            style: Theme.of(
              sheetContext,
            ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          Slider(
            value: value,
            min: 50,
            max: 100,
            divisions: 50,
            label: '${value.round()}%',
            onChanged: (next) => setState(() => value = next),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              store.updateSettings(thresholdPercent: value);
              Navigator.pop(sheetContext);
            },
            child: const Text('Save target'),
          ),
        ],
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({
    required this.store,
    required this.course,
    required this.threshold,
  });

  final AttendanceStore store;
  final Course course;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final stats = store.statsFor(course.id);
    final color = percentColor(context, stats.percent, threshold);

    return Card(
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SubjectDetailPage(store: store, course: course),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PercentRing(percent: stats.percent, color: color, size: 62),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              course.code,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: courseInk(context, course),
                              ),
                            ),
                            if (course.electiveGroup != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                course.electiveGroup!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: subtleInk(context),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          course.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: subtleInk(context)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          stats.held == 0
                              ? 'Nothing marked yet'
                              : '${stats.attended} of ${stats.held} classes held',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _AdviceLine(stats: stats, threshold: threshold),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Pill(
                    label: 'Adjusted',
                    value: stats.adjustedPercent == null
                        ? '—'
                        : '${stats.adjustedPercent!.round()}%',
                    tone: percentColor(
                      context,
                      stats.adjustedPercent,
                      threshold,
                    ),
                  ),
                  if (stats.bunked > 0)
                    _Pill(
                      label: 'Bunked',
                      value: '${stats.bunked}',
                      tone: AttendanceStatus.individualBunk.tint,
                    ),
                  if (stats.massBunked > 0)
                    _Pill(
                      label: 'Mass bunk',
                      value: '${stats.massBunked}',
                      tone: AttendanceStatus.massBunk.tint,
                    ),
                  if (stats.holidays > 0)
                    _Pill(
                      label: 'Holiday',
                      value: '${stats.holidays}',
                      tone: AttendanceStatus.govtHoliday.tint,
                    ),
                  if (stats.pending > 0)
                    _Pill(
                      label: 'Unlogged',
                      value: '${stats.pending}',
                      tone: Theme.of(context).colorScheme.outline,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Turns the numbers into the sentence a student actually wants: how many more
/// classes can be missed, or how many must be attended to recover.
class _AdviceLine extends StatelessWidget {
  const _AdviceLine({required this.stats, required this.threshold});

  final CourseStats stats;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final fraction = threshold / 100;
    final percent = stats.percent;

    final (IconData icon, String text, Color tone) = switch (percent) {
      null => (
        Icons.hourglass_empty_rounded,
        'Mark a few classes to see how much room you have.',
        Theme.of(context).colorScheme.outline,
      ),
      final value when value >= threshold => () {
        final spare = stats.skipsAvailable(fraction);
        return (
          Icons.check_circle_outline_rounded,
          spare == 0
              ? 'Exactly on target — the next miss drops you below $threshold%.'
              : 'You can miss $spare more ${spare == 1 ? 'class' : 'classes'} '
                    'and stay above ${threshold.round()}%.',
          const Color(0xFF18865A),
        );
      }(),
      _ => () {
        final needed = stats.classesNeeded(fraction);
        return (
          Icons.trending_up_rounded,
          'Attend the next $needed ${needed == 1 ? 'class' : 'classes'} '
              'in a row to get back to ${threshold.round()}%.',
          const Color(0xFFD6353B),
        );
      }(),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: tone),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, height: 1.25, color: tone),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value, required this.tone});

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.11),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$value ',
            style: TextStyle(fontWeight: FontWeight.w800, color: tone),
          ),
          TextSpan(
            text: label,
            style: TextStyle(color: subtleInk(context), fontSize: 11.5),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 12),
    ),
  );
}

class SubjectDetailPage extends StatelessWidget {
  const SubjectDetailPage({
    super.key,
    required this.store,
    required this.course,
  });

  final AttendanceStore store;
  final Course course;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      // The course can be deleted while this page is open.
      final live = store.courseById(course.id);
      if (live == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const EmptyState(
            icon: Icons.info_outline_rounded,
            title: 'Course removed',
            message: 'This course is no longer in your list.',
          ),
        );
      }
      final stats = store.statsFor(live.id);
      final threshold = store.settings.thresholdPercent;
      final records = store.recordsForCourse(live.id);
      final slots = store.classesForCourse(live.id);

      return Scaffold(
        appBar: AppBar(
          title: Text(live.code),
          actions: [
            IconButton(
              tooltip: 'Edit course',
              onPressed: () => showCourseSheet(context, store, course: live),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 30),
          children: [
            Text(
              live.name,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _BigStat(
                    caption: 'Attendance',
                    detail: 'Mass bunks count as absences',
                    percent: stats.percent,
                    numerator: stats.attended,
                    denominator: stats.held,
                    color: percentColor(context, stats.percent, threshold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _BigStat(
                    caption: 'Adjusted',
                    detail: 'Mass-bunked classes removed',
                    percent: stats.adjustedPercent,
                    numerator: stats.attended,
                    denominator: stats.heldExcludingMassBunks,
                    color: percentColor(
                      context,
                      stats.adjustedPercent,
                      threshold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Weekly classes',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (slots.isEmpty)
              InfoNote(
                text:
                    '${live.code} has no weekly slot yet, so nothing is '
                    'counted as scheduled. Add one from Manage, or scan your '
                    'timetable.',
                icon: Icons.warning_amber_rounded,
                tone: const Color(0xFFCC7A00),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final slot in slots)
                    Chip(
                      label: Text(
                        '${weekdayName(slot.weekday)} '
                        '${formatTimeRange(slot.startMinute, slot.durationMinutes)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'History',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${records.length} marked',
                  style: TextStyle(fontSize: 12, color: subtleInk(context)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (records.isEmpty)
              InfoNote(
                text: 'Nothing marked for ${live.code} yet.',
                icon: Icons.history_rounded,
              )
            else
              for (final record in records)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Card(
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        record.status.icon,
                        color: record.status.tint,
                      ),
                      title: Text(
                        formatDayLong(record.epochDay),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        [
                          record.status.label,
                          if (record.note != null) record.note!,
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => store.deleteRecord(record),
                      ),
                    ),
                  ),
                ),
          ],
        ),
      );
    },
  );
}

class _BigStat extends StatelessWidget {
  const _BigStat({
    required this.caption,
    required this.detail,
    required this.percent,
    required this.numerator,
    required this.denominator,
    required this.color,
  });

  final String caption;
  final String detail;
  final double? percent;
  final int numerator;
  final int denominator;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PercentRing(percent: percent, color: color, size: 66),
          const SizedBox(height: 10),
          Text(
            caption,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          Text(
            '$numerator of $denominator',
            style: TextStyle(fontSize: 12, color: subtleInk(context)),
          ),
          const SizedBox(height: 3),
          Text(
            detail,
            style: TextStyle(fontSize: 11, color: subtleInk(context)),
          ),
        ],
      ),
    ),
  );
}
