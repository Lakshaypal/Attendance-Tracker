import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'design.dart';
import 'sheets.dart';
import 'subjects_page.dart';

/// Pick which subjects are yours.
///
/// A stored timetable covers a whole class group, so it contains every option
/// inside each elective band. This screen is what turns that shared timetable
/// into one student's timetable: tick the compulsory subjects you attend and
/// choose one option per elective. Everything else in the app — the grid, the
/// calendar, the percentages — follows this selection.
class CoursesPage extends StatelessWidget {
  const CoursesPage({super.key, required this.store});

  final AttendanceStore store;

  @override
  Widget build(BuildContext context) {
    final groups = store.electiveGroups;
    final core = store.coreCourses;
    final chosen = store.enrolledCourses.length;

    return PageFrame(
      title: 'My subjects',
      subtitle: chosen == 0
          ? 'Tick the subjects you are registered for'
          : '$chosen picked out of ${store.courses.length} in the timetable',
      actions: [
        IconButton(
          tooltip: 'Add a subject',
          onPressed: () => showCourseSheet(context, store),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: store.courses.isEmpty
          ? const EmptyState(
              icon: Icons.checklist_rounded,
              title: 'No subjects in the timetable',
              message:
                  'Scan your printed timetable or add subjects by hand, then '
                  'come back here to pick yours.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 30),
              children: [
                if (chosen == 0)
                  const InfoNote(
                    text:
                        'Nothing is picked yet, so the timetable and the '
                        'attendance figures are empty. Tick your subjects '
                        'below.',
                    icon: Icons.arrow_downward_rounded,
                  ),
                if (core.isNotEmpty) ...[
                  const _SectionHeading(
                    'Compulsory',
                    'Everyone in the class group attends these',
                  ),
                  for (final course in core)
                    _CourseTile(
                      store: store,
                      course: course,
                      selected: course.enrolled,
                      isRadio: false,
                      onChanged: (value) => store.setEnrolled(course.id, value),
                    ),
                ],
                for (final group in groups) ...[
                  _SectionHeading(
                    'Elective ${group.group}',
                    group.options.length == 1
                        ? 'One subject runs in this slot'
                        : 'Choose one of ${group.options.length}',
                  ),
                  for (final course in group.options)
                    _CourseTile(
                      store: store,
                      course: course,
                      selected: course.enrolled,
                      isRadio: true,
                      onChanged: (value) => store.chooseElective(
                        group.group,
                        value ? course.id : null,
                      ),
                    ),
                  if (group.options.any((course) => course.enrolled))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                      child: TextButton.icon(
                        onPressed: () =>
                            store.chooseElective(group.group, null),
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        label: Text(
                          'I am not taking ${group.group}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 10),
                const InfoNote(
                  text:
                      'Un-ticking a subject only hides it. Attendance you have '
                      'already marked is kept, and comes back if you tick it '
                      'again.',
                ),
              ],
            ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title, this.detail);

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          detail,
          style: TextStyle(fontSize: 11.5, color: subtleInk(context)),
        ),
      ],
    ),
  );
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({
    required this.store,
    required this.course,
    required this.selected,
    required this.isRadio,
    required this.onChanged,
  });

  final AttendanceStore store;
  final Course course;
  final bool selected;

  /// Electives are single-choice, compulsory subjects are independent.
  final bool isRadio;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final slots = store.classesForCourse(course.id);
    final hasSlots = slots.isNotEmpty;
    final weekly = slots.fold<int>(
      0,
      (sum, slot) => sum + slot.durationMinutes,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: InkWell(
          onTap: () => onChanged(!selected),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
            child: Row(
              children: [
                if (isRadio)
                  // Single-choice within the band, but tapping the chosen one
                  // again clears it — "not taking this elective" is valid.
                  IconButton(
                    onPressed: () => onChanged(!selected),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                  )
                else
                  Checkbox(
                    value: selected,
                    onChanged: (value) => onChanged(value ?? false),
                  ),
                CourseBadge(course: course, size: 40),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasSlots
                            ? '${slots.length} '
                                  '${slots.length == 1 ? 'class' : 'classes'} · '
                                  '${_hours(weekly)} a week'
                            : 'No time in the timetable yet',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: hasSlots
                              ? subtleInk(context)
                              : const Color(0xFFCC7A00),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Details',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          SubjectDetailPage(store: store, course: course),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _hours(int minutes) {
    if (minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return '$hours ${hours == 1 ? 'hour' : 'hours'}';
    }
    return '${(minutes / 60).toStringAsFixed(1)} hours';
  }
}
