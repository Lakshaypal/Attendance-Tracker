import 'models.dart';

/// A small, entirely fictional timetable used by the "try it with sample data"
/// option on the welcome screen.
///
/// It exists so a new user can see what a filled-in app looks like before
/// committing to scanning their own. It deliberately contains no real
/// institution, no real faculty and no real student's registration — it does,
/// though, exercise the awkward cases: an elective band with three options, two
/// labs that clash in the same hour, and a class that runs two hours.
({List<Course> courses, List<TimetableClass> classes}) buildSampleTimetable() {
  final courses = <Course>[
    Course(id: 'sample-ma101', code: 'MA101', name: 'Calculus'),
    Course(id: 'sample-ph102', code: 'PH102', name: 'Physics'),
    Course(id: 'sample-cs103', code: 'CS103', name: 'Programming'),
    Course(
      id: 'sample-el201',
      code: 'EL201',
      name: 'Digital Design',
      electiveGroup: 'E1',
      enrolled: false,
    ),
    Course(
      id: 'sample-el202',
      code: 'EL202',
      name: 'Signals and Systems',
      electiveGroup: 'E1',
      enrolled: false,
    ),
    Course(
      id: 'sample-el203',
      code: 'EL203',
      name: 'Materials Science',
      electiveGroup: 'E1',
      enrolled: false,
    ),
  ];

  var counter = 0;
  final classes = <TimetableClass>[];
  void add(
    String courseId,
    int weekday,
    int start,
    int length, [
    String? title,
  ]) {
    classes.add(
      TimetableClass(
        id: 'sample-slot-${counter++}',
        courseId: courseId,
        weekday: weekday,
        startMinute: start,
        durationMinutes: length,
        title: title,
      ),
    );
  }

  void addBand(int weekday, int start, int length) {
    for (final id in ['sample-el201', 'sample-el202', 'sample-el203']) {
      add(id, weekday, start, length);
    }
  }

  add('sample-ma101', DateTime.monday, 9 * 60, 60);
  add('sample-ph102', DateTime.monday, 10 * 60, 60, 'Lab');
  add('sample-cs103', DateTime.monday, 10 * 60, 60, 'Lab'); // deliberate clash
  addBand(DateTime.monday, 14 * 60, 120);

  add('sample-cs103', DateTime.tuesday, 9 * 60, 120);
  add('sample-ma101', DateTime.tuesday, 12 * 60, 60);

  add('sample-ph102', DateTime.wednesday, 9 * 60, 60);
  addBand(DateTime.wednesday, 11 * 60, 60);

  add('sample-ma101', DateTime.thursday, 10 * 60, 60);
  add('sample-cs103', DateTime.thursday, 14 * 60, 120, 'Lab');

  add('sample-ph102', DateTime.friday, 9 * 60, 60);
  add('sample-ma101', DateTime.friday, 11 * 60, 60, 'Tutorial');

  return (courses: courses, classes: classes);
}
