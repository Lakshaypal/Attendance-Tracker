import 'package:flutter/material.dart';

import '../civil_date.dart';
import '../models.dart';
import '../store.dart';
import '../update/update_service.dart';
import 'design.dart';
import 'scan_page.dart';
import 'sheets.dart';
import 'subjects_page.dart';
import 'sync_page.dart';
import 'update_banner.dart';

class ManagePage extends StatefulWidget {
  const ManagePage({super.key, required this.store, this.updates});

  final AttendanceStore store;
  final UpdateService? updates;

  @override
  State<ManagePage> createState() => _ManagePageState();
}

class _ManagePageState extends State<ManagePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Manage',
    subtitle: 'Courses, weekly classes, and how the maths works',
    child: Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Courses'),
            Tab(text: 'Classes'),
            Tab(text: 'Settings'),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _CoursesTab(store: widget.store),
              _ClassesTab(store: widget.store),
              _SettingsTab(store: widget.store, updates: widget.updates),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CoursesTab extends StatelessWidget {
  const _CoursesTab({required this.store});

  final AttendanceStore store;

  @override
  Widget build(BuildContext context) {
    final orphans = store.orphanRecords;
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 28),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => showCourseSheet(context, store),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add course'),
          ),
        ),
        const SizedBox(height: 10),
        if (orphans.isNotEmpty) ...[
          InfoNote(
            text:
                '${orphans.length} records belong to courses that were '
                'deleted. They are not counted anywhere.',
            icon: Icons.cleaning_services_rounded,
            tone: const Color(0xFFCC7A00),
            action: TextButton(
              onPressed: () async {
                final ok = await confirm(
                  context,
                  title: 'Delete leftover records?',
                  message:
                      '${orphans.length} records will be removed permanently.',
                );
                if (ok) store.deleteOrphanRecords();
              },
              child: const Text('Clean up'),
            ),
          ),
          const SizedBox(height: 10),
        ],
        for (final course in store.courses)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SubjectDetailPage(store: store, course: course),
                  ),
                ),
                leading: CourseBadge(course: course),
                title: Text(
                  course.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    if (course.electiveGroup != null)
                      'Elective ${course.electiveGroup}',
                    '${store.classesForCourse(course.id).length} weekly '
                        '${store.classesForCourse(course.id).length == 1 ? 'class' : 'classes'}',
                  ].join(' · '),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (choice) async {
                    if (choice == 'edit') {
                      await showCourseSheet(context, store, course: course);
                    } else if (choice == 'delete') {
                      final stats = store.statsFor(course.id);
                      if (!context.mounted) return;
                      final ok = await confirm(
                        context,
                        title: 'Delete ${course.code}?',
                        message:
                            'Its weekly classes and ${stats.marked} attendance '
                            'records go too. This cannot be undone.',
                      );
                      if (ok) store.deleteCourse(course);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            ),
          ),
        if (store.courses.isEmpty)
          const InfoNote(
            text: 'No courses yet. Add one, or scan your timetable photo.',
          ),
      ],
    );
  }
}

class _ClassesTab extends StatelessWidget {
  const _ClassesTab({required this.store});

  final AttendanceStore store;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 28),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ScanTimetablePage(store: store),
                ),
              ),
              icon: const Icon(Icons.photo_camera_rounded, size: 18),
              label: const Text('Scan'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => showSlotSheet(context, store),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add class'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const InfoNote(
          text:
              'This is the full timetable for your class group. Which of these '
              'you actually attend is set under Courses.',
        ),
        const SizedBox(height: 12),
        for (var weekday = 1; weekday <= 7; weekday++)
          ..._daySection(context, weekday),
        if (store.timetable.isEmpty)
          const InfoNote(
            text:
                'No weekly classes yet. Scan a photo of your printed timetable '
                'to fill this in.',
          ),
      ],
    );
  }

  List<Widget> _daySection(BuildContext context, int weekday) {
    // The whole stored timetable, so subjects you are not taking can still be
    // corrected or removed here.
    final slots = store.allClassesForWeekday(weekday);
    if (slots.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
        child: Text(
          longWeekdayNames[weekday - 1],
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      for (final slot in slots)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _SlotTile(store: store, slot: slot),
        ),
      const SizedBox(height: 6),
    ];
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.store, required this.slot});

  final AttendanceStore store;
  final TimetableClass slot;

  @override
  Widget build(BuildContext context) {
    final course = store.courseById(slot.courseId);
    if (course == null) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        onTap: () => showSlotSheet(context, store, slot: slot),
        leading: CourseBadge(course: course),
        title: Text(
          formatTimeRange(slot.startMinute, slot.durationMinutes),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [course.name, if (slot.title != null) slot.title!].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            final ok = await confirm(
              context,
              title: 'Delete this weekly class?',
              message:
                  '${course.code} on ${longWeekdayNames[slot.weekday - 1]} at '
                  '${formatMinuteOfDay(slot.startMinute)}. Attendance you have '
                  'already marked is kept.',
            );
            if (ok) store.deleteTimetableClass(slot);
          },
        ),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({required this.store, this.updates});

  final AttendanceStore store;
  final UpdateService? updates;

  @override
  Widget build(BuildContext context) {
    final settings = store.settings;
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 28),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.event_rounded),
                title: const Text('Semester start'),
                subtitle: Text(formatDayLong(settings.semesterStartDay)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: dateTimeFromEpochDay(
                      settings.semesterStartDay,
                    ),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2040),
                    helpText: 'First day of the semester',
                  );
                  if (picked != null) {
                    store.updateSettings(semesterStartDay: epochDayOf(picked));
                  }
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.flag_rounded),
                title: const Text('Attendance target'),
                subtitle: Text(
                  '${settings.thresholdPercent.round()}% per course',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _editThreshold(context),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.hourglass_bottom_rounded),
                title: const Text('Count by contact hours'),
                subtitle: Text(
                  settings.countByPeriods
                      ? 'A ${settings.periodMinutes}-minute class counts once, '
                            'a two-hour class counts twice'
                      : 'Every class counts once, however long it runs',
                ),
                value: settings.countByPeriods,
                onChanged: (value) =>
                    store.updateSettings(countByPeriods: value),
              ),
              if (settings.countByPeriods) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.timelapse_rounded),
                  title: const Text('Length of one period'),
                  subtitle: Text('${settings.periodMinutes} minutes'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _editPeriodLength(context),
                ),
              ],
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.weekend_rounded),
                title: const Text('Show weekends in the grid'),
                subtitle: const Text(
                  'Saturday and Sunday appear anyway when they hold a class',
                ),
                value: settings.showWeekends,
                onChanged: (value) => store.updateSettings(showWeekends: value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.sync_rounded),
                title: const Text('Sync with another device'),
                subtitle: const Text('Over your own Wi-Fi, no account needed'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SyncPage(store: store),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: const Text('Start over'),
                subtitle: const Text(
                  'Clears every subject, class and record on this device',
                ),
                onTap: () async {
                  final ok = await confirm(
                    context,
                    title: 'Delete everything?',
                    message:
                        'Your whole timetable and all attendance on this '
                        'device will be removed. Sync it to another device '
                        'first if you want to keep it.',
                    confirmLabel: 'Delete all',
                  );
                  if (ok) store.resetEverything();
                },
              ),
            ],
          ),
        ),
        if (updates != null) ...[
          const SizedBox(height: 12),
          _UpdateCard(updates: updates!),
        ],
        const SizedBox(height: 16),
        Text(
          'How the percentages work',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const _RuleRow(
          status: AttendanceStatus.attended,
          text: 'Counts in the numerator and the denominator.',
        ),
        const _RuleRow(
          status: AttendanceStatus.individualBunk,
          text: 'Counts in the denominator only — it pulls the figure down.',
        ),
        const _RuleRow(
          status: AttendanceStatus.massBunk,
          text:
              'Counts as an absence in Attendance, but is removed entirely '
              'from Adjusted attendance.',
        ),
        const _RuleRow(
          status: AttendanceStatus.govtHoliday,
          text: 'Removed from both figures — the class never happened.',
        ),
        if (settings.countByPeriods)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.hourglass_bottom_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    const TextSpan(
                      children: [
                        TextSpan(
                          text: 'Longer classes count more. ',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text:
                              'A two-hour lab moves the percentage twice as '
                              'much as a one-hour lecture, on both sides of '
                              'the fraction.',
                        ),
                      ],
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        InfoNote(
          text:
              'Scheduled classes since ${formatDay(settings.semesterStartDay)} '
              'that you have not marked show up as "unlogged". They do not '
              'affect any percentage until you mark them.',
        ),
      ],
    );
  }

  Future<void> _editPeriodLength(BuildContext context) async {
    var value = store.settings.periodMinutes;
    await showAppSheet<void>(
      context,
      title: 'Length of one period',
      subtitle:
          'A class is worth its length divided by this, rounded to the '
          'nearest whole period. Set it to match your timetable.',
      builder: (sheetContext, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final option in const [45, 50, 55, 60, 90])
                ChoiceChip(
                  label: Text('$option min'),
                  selected: value == option,
                  onSelected: (_) => setState(() => value = option),
                ),
            ],
          ),
          const SizedBox(height: 16),
          InfoNote(
            text:
                'With $value-minute periods, a two-hour class counts as '
                '${periodsFor(120, value)} and a one-hour class counts as '
                '${periodsFor(60, value)}.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              store.updateSettings(periodMinutes: value);
              Navigator.pop(sheetContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editThreshold(BuildContext context) async {
    var value = store.settings.thresholdPercent;
    await showAppSheet<void>(
      context,
      title: 'Attendance target',
      subtitle: 'Applies to every course.',
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

/// Version, update status, and a manual check.
class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.updates});

  final UpdateService updates;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: updates,
    builder: (context, _) {
      final (String subtitle, Widget? trailing) = switch (updates.state) {
        UpdateState.checking => (
          'Checking…',
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        UpdateState.available => (
          'Version ${updates.available!.version} is available',
          const Icon(Icons.chevron_right_rounded),
        ),
        UpdateState.upToDate => ('This is the latest version', null),
        UpdateState.failed => (
          updates.message ?? 'Could not check',
          const Icon(Icons.refresh_rounded),
        ),
        UpdateState.idle => ('Tap to check for a new version', null),
      };

      return Card(
        child: ListTile(
          leading: const Icon(Icons.system_update_rounded),
          title: Text('Version ${updates.currentVersion}'),
          subtitle: Text(subtitle),
          trailing: trailing,
          onTap: updates.state == UpdateState.checking
              ? null
              : () async {
                  if (updates.state == UpdateState.available) {
                    await showUpdateSheet(context, updates);
                    return;
                  }
                  await updates.check();
                  if (!context.mounted) return;
                  if (updates.state == UpdateState.available) {
                    await showUpdateSheet(context, updates);
                  }
                },
        ),
      );
    },
  );
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.status, required this.text});

  final AttendanceStatus status;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(status.icon, size: 18, color: status.tint),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${status.label}. ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: text),
              ],
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}
