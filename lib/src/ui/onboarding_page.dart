import 'package:flutter/material.dart';

import '../store.dart';
import 'design.dart';
import 'scan_page.dart';
import 'sheets.dart';

/// First run. The app ships with no data at all, so this is where a timetable
/// comes from.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key, required this.store});

  final AttendanceStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            children: [
              Icon(
                Icons.school_rounded,
                size: 58,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                'Attendance Tracker',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Keep a per-subject attendance percentage, see your week as a '
                'grid, and know exactly how many classes you can afford to '
                'miss.',
                textAlign: TextAlign.center,
                style: TextStyle(color: subtleInk(context), height: 1.35),
              ),
              const SizedBox(height: 28),
              _Option(
                icon: Icons.photo_camera_rounded,
                title: 'Scan your timetable',
                detail:
                    'Photograph the printed one. Everything is read on this '
                    'device and you confirm it before anything is saved.',
                primary: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ScanTimetablePage(store: store),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _Option(
                icon: Icons.edit_calendar_rounded,
                title: 'Add subjects by hand',
                detail: 'Start with one subject and build up the week.',
                onTap: () => showCourseSheet(context, store),
              ),
              const SizedBox(height: 10),
              _Option(
                icon: Icons.science_outlined,
                title: 'Try it with sample data',
                detail:
                    'A fictional timetable so you can look around. Clear it '
                    'later from Manage → Settings.',
                onTap: () => store.loadSampleTimetable(),
              ),
              const SizedBox(height: 24),
              const InfoNote(
                text:
                    'Everything stays on your device. There is no account, no '
                    'server, and nothing is uploaded.',
                icon: Icons.lock_outline_rounded,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: primary ? scheme.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: primary
            ? BorderSide.none
            : BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                color: primary ? scheme.onPrimaryContainer : scheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: primary ? scheme.onPrimaryContainer : null,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color: primary
                            ? scheme.onPrimaryContainer.withValues(alpha: 0.85)
                            : subtleInk(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
