import 'package:flutter/material.dart';

import '../civil_date.dart';
import '../models.dart';
import '../store.dart';
import 'design.dart';

/// Wraps sheet content with the drag handle, padding and keyboard inset that
/// every sheet in the app wants.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget Function(BuildContext context, StateSetter setState) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (innerContext, setState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.viewInsetsOf(innerContext).bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  innerContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(innerContext).textTheme.bodySmall?.copyWith(
                    color: subtleInk(innerContext),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              builder(innerContext, setState),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Marks one recurring slot on one date.
Future<void> showMarkSheet(
  BuildContext context,
  AttendanceStore store, {
  required TimetableClass slot,
  required int epochDay,
}) async {
  final course = store.courseById(slot.courseId);
  if (course == null) return;
  await showAppSheet<void>(
    context,
    title: '${course.code} · ${course.name}',
    subtitle:
        '${formatDayLong(epochDay)} · '
        '${formatTimeRange(slot.startMinute, slot.durationMinutes)}'
        '${slot.title == null ? '' : ' · ${slot.title}'}',
    builder: (sheetContext, setState) {
      final current = store.recordForSlot(slot.id, epochDay);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final status in AttendanceStatus.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _StatusTile(
                status: status,
                selected: current?.status == status,
                onTap: () {
                  store.markSlot(
                    slot: slot,
                    epochDay: epochDay,
                    status: status,
                  );
                  Navigator.pop(sheetContext);
                },
              ),
            ),
          if (current != null) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () {
                store.markSlot(slot: slot, epochDay: epochDay, status: null);
                Navigator.pop(sheetContext);
              },
              icon: const Icon(Icons.backspace_outlined, size: 18),
              label: const Text('Clear this mark'),
            ),
          ],
        ],
      );
    },
  );
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final AttendanceStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? status.tint.withValues(alpha: 0.16)
        : Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(status.icon, color: status.tint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    status.description,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: subtleInk(context)),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, color: status.tint, size: 20),
          ],
        ),
      ),
    ),
  );
}

/// Add or edit a course.
Future<void> showCourseSheet(
  BuildContext context,
  AttendanceStore store, {
  Course? course,
}) async {
  final code = TextEditingController(text: course?.code ?? '');
  final name = TextEditingController(text: course?.name ?? '');
  final option = TextEditingController(text: course?.electiveGroup ?? '');
  String? error;

  await showAppSheet<void>(
    context,
    title: course == null ? 'Add course' : 'Edit course',
    subtitle: 'Attendance is tracked separately for every course.',
    builder: (sheetContext, setState) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Course code',
            hintText: 'EE301',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Course name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: option,
          decoration: const InputDecoration(
            labelText: 'Elective option (optional)',
            hintText: 'E2',
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () {
            final trimmedCode = code.text.trim();
            if (trimmedCode.isEmpty) {
              setState(() => error = 'A course code is required.');
              return;
            }
            final clash = store.findCourseByCode(trimmedCode);
            if (clash != null && clash.id != course?.id) {
              setState(
                () => error = '${clash.code} already exists in your courses.',
              );
              return;
            }
            store.saveCourse(
              existing: course,
              code: trimmedCode,
              name: name.text,
              electiveGroup: option.text,
            );
            Navigator.pop(sheetContext);
          },
          child: const Text('Save course'),
        ),
      ],
    ),
  );
  code.dispose();
  name.dispose();
  option.dispose();
}

/// Add or edit one weekly slot.
Future<void> showSlotSheet(
  BuildContext context,
  AttendanceStore store, {
  TimetableClass? slot,
  int? initialWeekday,
  int? initialStartMinute,
}) async {
  if (store.courses.isEmpty) {
    showSnack(context, 'Add a course first.');
    return;
  }
  var courseId = slot?.courseId ?? store.courses.first.id;
  if (store.courseById(courseId) == null) courseId = store.courses.first.id;
  var weekday = slot?.weekday ?? initialWeekday ?? DateTime.monday;
  var start = slot?.startMinute ?? initialStartMinute ?? 9 * 60;
  var duration = slot?.durationMinutes ?? 60;
  final title = TextEditingController(text: slot?.title ?? '');

  await showAppSheet<void>(
    context,
    title: slot == null ? 'Add weekly class' : 'Edit weekly class',
    subtitle: 'This repeats every week on the chosen day.',
    builder: (sheetContext, setState) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: courseId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Course'),
          items: [
            for (final course in store.courses)
              DropdownMenuItem(
                value: course.id,
                child: Text(
                  '${course.code} · ${course.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => courseId = value);
          },
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 6,
          children: [
            for (var day = 1; day <= 7; day++)
              ChoiceChip(
                label: Text(weekdayName(day)),
                selected: weekday == day,
                onSelected: (_) => setState(() => weekday = day),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: sheetContext,
                    initialTime: TimeOfDay(
                      hour: start ~/ 60,
                      minute: start % 60,
                    ),
                  );
                  if (picked != null) {
                    setState(() => start = picked.hour * 60 + picked.minute);
                  }
                },
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text(formatMinuteOfDay(start)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue:
                    const [30, 45, 60, 90, 120, 180].contains(duration)
                    ? duration
                    : 60,
                decoration: const InputDecoration(labelText: 'Length'),
                items: const [
                  DropdownMenuItem(value: 30, child: Text('30 min')),
                  DropdownMenuItem(value: 45, child: Text('45 min')),
                  DropdownMenuItem(value: 60, child: Text('1 hour')),
                  DropdownMenuItem(value: 90, child: Text('1½ hours')),
                  DropdownMenuItem(value: 120, child: Text('2 hours')),
                  DropdownMenuItem(value: 180, child: Text('3 hours')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => duration = value);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: title,
          decoration: const InputDecoration(
            labelText: 'Label (optional)',
            hintText: 'Lab, tutorial, room…',
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () {
            store.saveTimetableClass(
              existing: slot,
              courseId: courseId,
              weekday: weekday,
              startMinute: start,
              durationMinutes: duration,
              title: title.text,
            );
            Navigator.pop(sheetContext);
          },
          child: const Text('Save class'),
        ),
      ],
    ),
  );
  title.dispose();
}

/// Add or edit a one-off record that is not tied to the weekly timetable.
Future<void> showRecordSheet(
  BuildContext context,
  AttendanceStore store, {
  AttendanceRecord? record,
  int? initialDay,
}) async {
  if (store.courses.isEmpty) {
    showSnack(context, 'Add a course first.');
    return;
  }
  var courseId = record?.courseId ?? store.courses.first.id;
  if (store.courseById(courseId) == null) courseId = store.courses.first.id;
  var status = record?.status ?? AttendanceStatus.attended;
  var day = record?.epochDay ?? initialDay ?? todayEpochDay();
  final note = TextEditingController(text: record?.note ?? '');

  await showAppSheet<void>(
    context,
    title: record == null ? 'Add a one-off class' : 'Edit record',
    subtitle: 'For extra or rescheduled classes outside the weekly timetable.',
    builder: (sheetContext, setState) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: courseId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Course'),
          items: [
            for (final course in store.courses)
              DropdownMenuItem(
                value: course.id,
                child: Text(
                  '${course.code} · ${course.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => courseId = value);
          },
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: sheetContext,
              initialDate: dateTimeFromEpochDay(day),
              firstDate: DateTime(2020),
              lastDate: DateTime(2040),
            );
            if (picked != null) setState(() => day = epochDayOf(picked));
          },
          icon: const Icon(Icons.calendar_today_rounded, size: 18),
          label: Text(formatDayLong(day)),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<AttendanceStatus>(
          initialValue: status,
          decoration: const InputDecoration(labelText: 'Status'),
          items: [
            for (final value in AttendanceStatus.values)
              DropdownMenuItem(value: value, child: Text(value.label)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => status = value);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: note,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: () {
            store.saveRecord(
              existing: record,
              courseId: courseId,
              epochDay: day,
              status: status,
              durationMinutes: record?.durationMinutes ?? 60,
              timetableClassId: record?.timetableClassId,
              note: note.text,
            );
            Navigator.pop(sheetContext);
          },
          child: const Text('Save record'),
        ),
      ],
    ),
  );
  note.dispose();
}
