import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'src/store.dart';
import 'src/ui/calendar_page.dart';
import 'src/ui/courses_page.dart';
import 'src/ui/design.dart';
import 'src/ui/manage_page.dart';
import 'src/ui/onboarding_page.dart';
import 'src/ui/subjects_page.dart';
import 'src/ui/timetable_page.dart';
import 'src/ui/update_banner.dart';
import 'src/update/app_version.dart';
import 'src/update/update_service.dart';

// Re-exported so `package:attendance_tracker/main.dart` remains the single
// import for tests and for anything embedding the app.
export 'src/civil_date.dart';
export 'src/migrations.dart';
export 'src/models.dart';
export 'src/scan/ocr_types.dart';
export 'src/scan/timetable_parser.dart';
export 'src/schedule_layout.dart';
export 'src/store.dart';
export 'src/sync.dart';
export 'src/update/app_version.dart';
export 'src/update/update_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AttendanceStore(directory: await resolveDataDirectory());
  await store.load();
  final updates = UpdateService(currentVersion: await resolveAppVersion());
  // Fire and forget: a failed check must never delay the first frame.
  unawaited(updates.check(silent: true));
  runApp(AttendanceApp(store: store, updates: updates));
}

/// The running build's version, taken from `pubspec.yaml` at build time so the
/// updater compares against the same string the release tag carries.
Future<AppVersion> resolveAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return AppVersion.tryParse(info.version) ?? const AppVersion(0, 0, 0);
  } catch (_) {
    return const AppVersion(0, 0, 0);
  }
}

/// Platform-correct storage. On Android the process working directory is not
/// writable, so the application support directory is the only durable choice.
Future<Directory?> resolveDataDirectory() async {
  try {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/attendance');
    await dir.create(recursive: true);
    return dir;
  } catch (_) {
    return null;
  }
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key, required this.store, this.updates});

  final AttendanceStore store;
  final UpdateService? updates;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Attendance Tracker',
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    home: HomeShell(store: store, updates: updates),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store, this.updates});

  final AttendanceStore store;
  final UpdateService? updates;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  static const List<(IconData, IconData, String)> _destinations = [
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Timetable'),
    (Icons.calendar_month_outlined, Icons.calendar_month_rounded, 'Calendar'),
    (Icons.donut_small_outlined, Icons.donut_small_rounded, 'Attendance'),
    (Icons.checklist_outlined, Icons.checklist_rounded, 'Subjects'),
    (Icons.tune_outlined, Icons.tune_rounded, 'Manage'),
  ];

  static const int _subjectsTab = 3;

  int _index = 0;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The app is often left open overnight. Without this tick, "today" stays
    // frozen on whichever day the window was opened: the grid highlights the
    // wrong column and the current-time line stops moving.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Commit any debounced write before the process can be killed.
        widget.store.flush();
      case AppLifecycleState.resumed:
        // Coming back from the background can cross midnight.
        if (mounted) setState(() {});
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      // Nothing to show on a first run, so onboarding takes the whole screen.
      if (widget.store.isEmpty) {
        return OnboardingPage(store: widget.store);
      }
      final wide = MediaQuery.sizeOf(context).width >= 840;
      // IndexedStack keeps each tab's scroll position and selected week or
      // month while switching.
      final body = IndexedStack(
        index: _index,
        children: [
          TimetablePage(store: widget.store),
          CalendarPage(store: widget.store),
          SubjectsPage(
            store: widget.store,
            onPickSubjects: () => setState(() => _index = _subjectsTab),
          ),
          CoursesPage(store: widget.store),
          ManagePage(store: widget.store, updates: widget.updates),
        ],
      );

      final updates = widget.updates;
      return Scaffold(
        body: Column(
          children: [
            if (updates != null) UpdateBanner(updates: updates),
            if (widget.store.isReadOnly)
              _ReadOnlyBanner(message: '${widget.store.lockedBy}'),
            Expanded(child: _buildBody(wide, body)),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (value) =>
                    setState(() => _index = value),
                destinations: [
                  for (final (icon, selected, label) in _destinations)
                    NavigationDestination(
                      icon: Icon(icon),
                      selectedIcon: Icon(selected),
                      label: label,
                    ),
                ],
              ),
      );
    },
  );

  Widget _buildBody(bool wide, Widget body) => wide
      ? Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (value) => setState(() => _index = value),
              leading: const Padding(
                padding: EdgeInsets.only(top: 16, bottom: 4),
                child: Icon(Icons.school_rounded, size: 26),
              ),
              destinations: [
                for (final (icon, selected, label) in _destinations)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(selected),
                    label: Text(label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        )
      : body;
}

/// Shown when the data file was written by a newer build. The store refuses to
/// write while this is up, so the newer version's fields cannot be lost.
class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$message Nothing you do here will be saved until you '
                  'update.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
