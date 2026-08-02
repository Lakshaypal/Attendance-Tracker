import 'package:attendance_tracker/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the real widget tree against an in-memory store, which is the only
/// way to prove the grid, the calendar and the marking flow actually work
/// together.
void main() {
  late AttendanceStore store;

  setUp(() async {
    // Pinned so the suite does not quietly change behaviour depending on the
    // day it happens to run.
    Clock.now = () => DateTime(2026, 7, 29, 10, 30); // Wednesday
    store = AttendanceStore();
    await store.load();
    // The app ships empty, so the widget tests start from the bundled
    // fictional timetable: three compulsory subjects plus a three-way
    // elective band, with two labs that deliberately clash.
    store.loadSampleTimetable();
  });

  tearDown(Clock.reset);

  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(440, 950),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AttendanceApp(store: store));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the timetable grid with the week in view', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('Timetable'), findsWidgets);
    expect(find.text('This week'), findsOneWidget);
    // Monday's sample classes are on screen.
    expect(find.text('MA101'), findsWidgets);
    expect(find.text('PH102'), findsWidgets);
  });

  testWidgets('overlapping labs are both rendered side by side', (
    tester,
  ) async {
    await pumpApp(tester);

    // The sample Monday has two labs at 10:00. Both must be visible, neither
    // hidden behind the other.
    final labs = store
        .classesForWeekday(DateTime.monday)
        .where((slot) => slot.startMinute == 600)
        .toList();
    expect(labs, hasLength(2));

    final placedCodes = labs
        .map((slot) => store.courseById(slot.courseId)!.code)
        .toList();
    for (final code in placedCodes) {
      expect(find.text(code), findsWidgets, reason: '$code is missing');
    }
  });

  testWidgets('tapping a class marks it, and the mark shows up', (
    tester,
  ) async {
    await pumpApp(tester);

    final monday = startOfWeek(todayEpochDay());
    final slot = store.classesForWeekday(DateTime.monday).first;
    expect(store.recordForSlot(slot.id, monday), isNull);

    await tester.tap(find.text(store.courseById(slot.courseId)!.code).first);
    await tester.pumpAndSettle();

    expect(find.text('Attended'), findsOneWidget);
    expect(find.text('Mass bunk'), findsOneWidget);
    await tester.tap(find.text('Attended'));
    await tester.pumpAndSettle();

    final record = store.recordForSlot(slot.id, monday);
    expect(record, isNotNull);
    expect(record!.status, AttendanceStatus.attended);
  });

  testWidgets('the calendar shows the month and opens a day', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();

    expect(find.text(formatMonthYear(todayEpochDay())), findsOneWidget);
    expect(find.text(formatDayLong(todayEpochDay())), findsOneWidget);
  });

  testWidgets('subjects report a percentage per course, never a combined one', (
    tester,
  ) async {
    // Mark a couple of Monday classes so there is something to report.
    final monday = startOfWeek(todayEpochDay());
    final slots = store.classesForWeekday(DateTime.monday);
    store.markSlot(
      slot: slots[0],
      epochDay: monday,
      status: AttendanceStatus.attended,
    );
    store.markSlot(
      slot: slots[1],
      epochDay: monday,
      status: AttendanceStatus.individualBunk,
    );

    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.donut_small_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Attendance'), findsWidgets);
    expect(
      find.text('Each subject is tracked against its own target'),
      findsOneWidget,
    );

    final attendedCourse = store.courseById(slots[0].courseId)!;
    final bunkedCourse = store.courseById(slots[1].courseId)!;

    // Worst first, so both marked courses are above the fold.
    expect(find.text(attendedCourse.code), findsWidgets);
    expect(find.text(bunkedCourse.code), findsWidgets);

    // Two courses, two different figures — there is no combined percentage
    // anywhere on the page.
    expect(find.text('100%'), findsWidgets);
    expect(find.text('0%'), findsWidgets);
    expect(store.statsFor(attendedCourse.id).percent, 100);
    expect(store.statsFor(bunkedCourse.id).percent, 0);

    // Untouched courses show a dash rather than a misleading zero.
    expect(find.text('—'), findsWidgets);
    expect(find.text('Nothing marked yet'), findsWidgets);
  });

  testWidgets('a subject opens its own detail page', (tester) async {
    final monday = startOfWeek(todayEpochDay());
    final slot = store.classesForWeekday(DateTime.monday).first;
    store.markSlot(
      slot: slot,
      epochDay: monday,
      status: AttendanceStatus.attended,
    );

    await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.donut_small_outlined));
    await tester.pumpAndSettle();

    final course = store.courseById(slot.courseId)!;
    await tester.tap(find.text(course.code).first);
    await tester.pumpAndSettle();

    expect(find.text(course.name), findsWidgets);
    expect(find.text('Attendance'), findsWidgets);
    expect(find.text('Adjusted'), findsWidgets);
    expect(find.text('History'), findsOneWidget);
    expect(find.text(formatDayLong(monday)), findsWidgets);
  });

  testWidgets('manage lists courses, classes and the rules', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.tune_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Courses'), findsOneWidget);
    expect(find.text('Add course'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Semester start'), findsOneWidget);
    expect(find.text('Attendance target'), findsOneWidget);
    expect(find.text('Count by contact hours'), findsOneWidget);
    expect(find.text('Length of one period'), findsOneWidget);

    // The rules live further down the tab.
    await tester.scrollUntilVisible(
      find.text('How the percentages work'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('How the percentages work'), findsOneWidget);
  });

  testWidgets('a first run shows onboarding rather than empty tabs', (
    tester,
  ) async {
    final fresh = AttendanceStore();
    await fresh.load();
    expect(fresh.isEmpty, isTrue);

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(440, 950);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(AttendanceApp(store: fresh));
    await tester.pumpAndSettle();

    expect(find.text('Scan your timetable'), findsOneWidget);
    expect(find.text('Try it with sample data'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    // Choosing the sample leaves onboarding for the real app.
    await tester.tap(find.text('Try it with sample data'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Timetable'), findsWidgets);
  });

  testWidgets('an empty timetable inside a populated app invites a scan', (
    tester,
  ) async {
    store.replaceTimetable(const []);
    await pumpApp(tester);

    expect(find.text('Your timetable is empty'), findsOneWidget);
    expect(find.text('Scan a photo'), findsOneWidget);
  });

  testWidgets('the wide layout switches to a navigation rail', (tester) async {
    await pumpApp(tester, size: const Size(1200, 900));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  group('class details', () {
    testWidgets('venue, teacher and notes show when you tap the class', (
      tester,
    ) async {
      final slot = store.classesForWeekday(DateTime.monday).first;
      store.saveTimetableClass(
        existing: slot,
        courseId: slot.courseId,
        weekday: slot.weekday,
        startMinute: slot.startMinute,
        durationMinutes: slot.durationMinutes,
        room: 'AB3107',
        teacher: 'Dr Rao',
        link: 'meet.example.test/room',
        notes: 'Bring the manual',
      );

      await pumpApp(tester);
      await tester.tap(find.text(store.courseById(slot.courseId)!.code).first);
      await tester.pumpAndSettle();

      expect(find.text('AB3107'), findsWidgets);
      expect(find.text('Dr Rao'), findsOneWidget);
      expect(find.text('Bring the manual'), findsOneWidget);
      // The destination is shown in full, not hidden behind the button.
      expect(find.text('https://meet.example.test/room'), findsOneWidget);
      expect(find.text('Open link'), findsOneWidget);
      // Marking still works with the details panel present.
      expect(find.text('Attended'), findsOneWidget);
    });

    testWidgets('a class with no details shows no empty panel', (tester) async {
      await pumpApp(tester);
      final slot = store.classesForWeekday(DateTime.monday).first;
      await tester.tap(find.text(store.courseById(slot.courseId)!.code).first);
      await tester.pumpAndSettle();

      expect(find.text('Open link'), findsNothing);
      expect(find.byIcon(Icons.place_outlined), findsNothing);
      expect(find.text('Attended'), findsOneWidget);
    });

    testWidgets('an unopenable link is shown but not offered', (tester) async {
      final slot = store.classesForWeekday(DateTime.monday).first;
      store.saveTimetableClass(
        existing: slot,
        courseId: slot.courseId,
        weekday: slot.weekday,
        startMinute: slot.startMinute,
        durationMinutes: slot.durationMinutes,
        link: 'javascript:alert(1)',
      );

      await pumpApp(tester);
      await tester.tap(find.text(store.courseById(slot.courseId)!.code).first);
      await tester.pumpAndSettle();

      expect(find.text('javascript:alert(1)'), findsOneWidget);
      expect(find.text('Open link'), findsNothing);
      expect(
        find.text('This is not a web address, so it cannot be opened.'),
        findsOneWidget,
      );
    });

    testWidgets('the editor reveals the extra fields on request', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Classes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add class'));
      await tester.pumpAndSettle();

      // Hidden until asked for, so the common case stays short.
      expect(find.text('Venue'), findsNothing);
      await tester.tap(find.text('Add venue, teacher or link'));
      await tester.pumpAndSettle();

      expect(find.text('Venue'), findsOneWidget);
      expect(find.text('Teacher'), findsOneWidget);
      expect(find.text('Link'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
    });
  });

  group('the subject picker', () {
    testWidgets('groups the timetable into compulsory and elective bands', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.byIcon(Icons.checklist_outlined));
      await tester.pumpAndSettle();

      expect(find.text('My subjects'), findsWidgets);
      expect(find.text('Compulsory'), findsOneWidget);
      expect(find.text('Elective E1'), findsOneWidget);
      expect(find.text('Choose one of 3'), findsWidgets);
      // Every option in the band is offered.
      expect(find.text('Digital Design'), findsOneWidget);
      expect(find.text('EL202'), findsWidgets);
    });

    testWidgets('swapping an elective changes what the grid shows', (
      tester,
    ) async {
      await pumpApp(tester);
      // Wednesday 11am is an E1 hour, and nothing is picked to begin with.
      expect(
        store
            .classesForWeekday(DateTime.wednesday)
            .where((slot) => slot.startMinute == 11 * 60),
        isEmpty,
      );

      await tester.tap(find.byIcon(Icons.checklist_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EL202').first);
      await tester.pumpAndSettle();

      expect(store.findCourseByCode('EL202')!.enrolled, isTrue);
      expect(store.findCourseByCode('EL201')!.enrolled, isFalse);
      expect(
        store
            .classesForWeekday(DateTime.wednesday)
            .where((slot) => slot.startMinute == 11 * 60)
            .map((slot) => store.courseById(slot.courseId)!.code),
        ['EL202'],
      );
    });

    testWidgets('attendance lists only the subjects you picked', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.byIcon(Icons.donut_small_outlined));
      await tester.pumpAndSettle();

      // The elective options are in the timetable but none is picked.
      expect(find.text('EL201'), findsNothing);
      expect(find.text('EL202'), findsNothing);
      expect(find.text('MA101'), findsWidgets);
    });
  });

  group('the date rolling over while the app is open', () {
    testWidgets('moves the timetable to the new week', (tester) async {
      // Friday 31 July 2026, late evening.
      var now = DateTime(2026, 7, 31, 23, 59);
      Clock.now = () => now;

      await pumpApp(tester);
      expect(find.text('Mon, 27 Jul – Fri, 31 Jul'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);

      // Midnight passes, and with it the week.
      now = DateTime(2026, 8, 3, 0, 1); // Monday
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();

      expect(find.text('Mon, 3 Aug – Fri, 7 Aug'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
    });

    testWidgets('still shows today when today is a Saturday', (tester) async {
      var now = DateTime(2026, 7, 31, 23, 59);
      Clock.now = () => now;
      await pumpApp(tester);
      // No weekend classes are seeded, so Saturday starts hidden.
      expect(find.text('SAT'), findsNothing);

      now = DateTime(2026, 8, 1, 0, 1); // Saturday
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();

      expect(
        find.text('SAT'),
        findsOneWidget,
        reason: 'today must be visible even on a weekend',
      );
    });

    testWidgets('moves the calendar selection to the new day', (tester) async {
      var now = DateTime(2026, 7, 31, 23, 59);
      Clock.now = () => now;

      await pumpApp(tester);
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Friday, 31 July 2026'), findsOneWidget);

      now = DateTime(2026, 8, 1, 0, 1);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();

      expect(find.text('Saturday, 1 August 2026'), findsOneWidget);
    });

    testWidgets('leaves a day the user picked alone', (tester) async {
      var now = DateTime(2026, 7, 31, 23, 59);
      Clock.now = () => now;

      await pumpApp(tester);
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('29'));
      await tester.pumpAndSettle();
      expect(find.text('Wednesday, 29 July 2026'), findsOneWidget);

      now = DateTime(2026, 8, 1, 0, 1);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();

      expect(
        find.text('Wednesday, 29 July 2026'),
        findsOneWidget,
        reason: 'an explicit choice must survive the date change',
      );
    });
  });
}
