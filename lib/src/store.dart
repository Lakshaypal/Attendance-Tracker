import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'civil_date.dart';
import 'migrations.dart';
import 'models.dart';
import 'sample_timetable.dart';

/// User-tunable knobs that affect every derived number.
class Settings {
  Settings({
    required this.semesterStartDay,
    this.thresholdPercent = 75,
    this.showWeekends = false,
    this.countByPeriods = true,
    this.periodMinutes = 60,
    this.extra,
  });

  int semesterStartDay;

  /// Target attendance, in percent. Drives the "can I skip?" advice.
  double thresholdPercent;

  /// Whether the timetable grid renders Saturday and Sunday columns.
  bool showWeekends;

  /// When true (the usual convention), a class counts once per contact hour,
  /// so a two-hour lab is worth two periods. Turn it off for an institution
  /// that counts one mark per session however long it runs.
  bool countByPeriods;

  /// The length of one period, used to convert a class duration into periods.
  int periodMinutes;

  /// Settings written by a newer version of the app, carried through so an
  /// older build cannot drop them.
  final Map<String, dynamic>? extra;

  static const Set<String> _known = {
    'semesterStart',
    'thresholdPercent',
    'showWeekends',
    'countByPeriods',
    'periodMinutes',
  };

  double get thresholdFraction => thresholdPercent / 100;

  /// The weight one class of [durationMinutes] carries.
  int weightFor(int durationMinutes) =>
      countByPeriods ? periodsFor(durationMinutes, periodMinutes) : 1;

  Map<String, dynamic> toJson() => withExtras({
    'semesterStart': isoDateString(semesterStartDay),
    'thresholdPercent': thresholdPercent,
    'showWeekends': showWeekends,
    'countByPeriods': countByPeriods,
    'periodMinutes': periodMinutes,
  }, extra);

  factory Settings.fromJson(Map<String, dynamic>? json) {
    final raw = (json?['thresholdPercent'] as num?)?.toDouble() ?? 75;
    final period = (json?['periodMinutes'] as num?)?.toInt() ?? 60;
    return Settings(
      semesterStartDay:
          parseIsoDateToEpochDay(json?['semesterStart'] as String?) ??
          defaultSemesterStart,
      thresholdPercent: raw.clamp(1, 100).toDouble(),
      showWeekends: json?['showWeekends'] as bool? ?? false,
      // Files written before periods existed counted one mark per session.
      // Keeping that default for them would be wrong — the figures they
      // already show are the ones being corrected — so weighting is on for
      // everyone and the toggle is there for the rare college that differs.
      countByPeriods: json?['countByPeriods'] as bool? ?? true,
      periodMinutes: period.clamp(15, 240),
      extra: json == null ? null : extraFieldsOf(json, _known),
    );
  }

  static final int defaultSemesterStart = epochDayFromYmd(2026, 7, 28);
}

/// Mutable tally used only while an index rebuild is in flight.
class _Tally {
  int attended = 0;
  int bunked = 0;
  int massBunked = 0;
  int holidays = 0;
  int markedScheduled = 0;
  int scheduled = 0;
  int markedSessions = 0;
}

/// The single source of truth.
///
/// ## Complexity
///
/// The canonical data lives in three lists. Every question the UI asks is
/// answered from indexes that are rebuilt lazily, at most once per mutation,
/// in **O(C + T + R)** time and **O(C + T + R)** space (C courses, T weekly
/// slots, R records — the indexes hold references, never copies).
///
/// After the rebuild every read is O(1) or O(size of the answer):
///
/// | query                       | cost |
/// |-----------------------------|------|
/// | `courseById`                | O(1) |
/// | `classesOn(day)`            | O(1) |
/// | `recordForSlot(class, day)` | O(1) |
/// | `recordsOn(day)`            | O(1) |
/// | `statsFor(course)`          | O(1) |
/// | `daySummary(day)`           | O(1) |
///
/// The naive version of this app recomputed a course's pending count by
/// walking every day of the semester and rescanning every record, which is
/// O(C · D · T · R) per rebuild of the overview. Counting weekday occurrences
/// arithmetically (see [weekdayOccurrences]) removes the calendar walk, and
/// hashing the records by day removes the rescans.
class AttendanceStore extends ChangeNotifier {
  AttendanceStore({this.directory});

  /// Where `data.json` lives. Null keeps the store purely in memory, which is
  /// what the unit tests use.
  final Directory? directory;

  final List<Course> _courses = [];
  final List<TimetableClass> _timetable = [];
  final List<AttendanceRecord> _records = [];
  Settings _settings = Settings(
    semesterStartDay: Settings.defaultSemesterStart,
  );

  // ---------------------------------------------------------------- indexes
  bool _indexDirty = true;
  final Map<String, Course> _courseById = {};
  final Map<String, TimetableClass> _classById = {};

  /// Slots for enrolled courses only — what the grid, the calendar and the
  /// figures are built from.
  final List<List<TimetableClass>> _classesByWeekday = List.generate(
    7,
    (_) => <TimetableClass>[],
    growable: false,
  );

  /// Every slot in the stored timetable, enrolled or not, for the screens that
  /// manage the timetable itself.
  final List<List<TimetableClass>> _allClassesByWeekday = List.generate(
    7,
    (_) => <TimetableClass>[],
    growable: false,
  );
  final Map<String, List<TimetableClass>> _classesByCourse = {};
  final Map<int, List<AttendanceRecord>> _recordsByDay = {};
  final Map<String, List<AttendanceRecord>> _recordsByCourse = {};
  final Map<int, Map<String, AttendanceRecord>> _slotsByDay = {};
  final Map<String, CourseStats> _statsByCourse = {};
  final Map<int, DaySummary> _daySummaries = {};
  List<AttendanceRecord> _orphanRecords = const [];

  Timer? _saveTimer;
  bool _disposed = false;
  int _idCounter = 0;

  // ------------------------------------------------------------- public API
  List<Course> get courses => List.unmodifiable(_courses);

  /// The subjects the student actually takes. Everything the app reports is
  /// scoped to these.
  List<Course> get enrolledCourses =>
      List.unmodifiable(_courses.where((course) => course.enrolled));

  /// Elective slot ids (`E1`, `E2`, …) in printed order, each with the courses
  /// competing for it.
  List<({String group, List<Course> options})> get electiveGroups {
    final grouped = <String, List<Course>>{};
    for (final course in _courses) {
      final group = course.electiveGroup;
      if (group == null) continue;
      (grouped[group] ??= <Course>[]).add(course);
    }
    final keys = grouped.keys.toList()..sort(_compareGroupNames);
    return [for (final key in keys) (group: key, options: grouped[key]!)];
  }

  /// Courses that belong to no elective slot — the ones everyone attends.
  List<Course> get coreCourses => List.unmodifiable(
    _courses.where((course) => course.electiveGroup == null),
  );

  /// Groups sort by their letters first, then numerically, so `E2` comes
  /// before `E10` and a differently-named band such as `MOOC5` stays with its
  /// own kind instead of landing between `E5` and `E6`.
  static int _compareGroupNames(String a, String b) {
    final letters = RegExp(r'[^0-9]+');
    final prefixA = letters.stringMatch(a) ?? '';
    final prefixB = letters.stringMatch(b) ?? '';
    final byPrefix = prefixA.compareTo(prefixB);
    if (byPrefix != 0) return byPrefix;

    final numberA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), ''));
    final numberB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), ''));
    if (numberA != null && numberB != null) {
      final byNumber = numberA.compareTo(numberB);
      if (byNumber != 0) return byNumber;
    }
    return a.compareTo(b);
  }

  List<TimetableClass> get timetable => List.unmodifiable(_timetable);
  List<AttendanceRecord> get records => List.unmodifiable(_records);
  Settings get settings => _settings;

  /// Records that point at a course that no longer exists. They are kept on
  /// disk (deleting user data silently would be worse) but excluded from every
  /// statistic, and the Manage screen offers to clean them up.
  List<AttendanceRecord> get orphanRecords {
    _ensureIndex();
    return _orphanRecords;
  }

  Course? courseById(String? id) {
    if (id == null) return null;
    _ensureIndex();
    return _courseById[id];
  }

  TimetableClass? classById(String? id) {
    if (id == null) return null;
    _ensureIndex();
    return _classById[id];
  }

  /// Weekly slots for an ISO weekday that belong to an enrolled course,
  /// pre-sorted by start time. The returned list is the index's own, so
  /// callers must not mutate it.
  List<TimetableClass> classesForWeekday(int isoWeekday) {
    _ensureIndex();
    if (isoWeekday < 1 || isoWeekday > 7) return const [];
    return _classesByWeekday[isoWeekday - 1];
  }

  /// Every slot on a weekday, including subjects the student is not taking.
  List<TimetableClass> allClassesForWeekday(int isoWeekday) {
    _ensureIndex();
    if (isoWeekday < 1 || isoWeekday > 7) return const [];
    return _allClassesByWeekday[isoWeekday - 1];
  }

  List<TimetableClass> classesOn(int epochDay) =>
      classesForWeekday(weekdayOfEpochDay(epochDay));

  List<TimetableClass> classesForCourse(String courseId) {
    _ensureIndex();
    return _classesByCourse[courseId] ?? const [];
  }

  List<AttendanceRecord> recordsOn(int epochDay) {
    _ensureIndex();
    return _recordsByDay[epochDay] ?? const [];
  }

  /// Every record for one course, newest first.
  List<AttendanceRecord> recordsForCourse(String courseId) {
    _ensureIndex();
    return _recordsByCourse[courseId] ?? const [];
  }

  /// The record for one recurring slot on one date, or null when unmarked.
  AttendanceRecord? recordForSlot(String timetableClassId, int epochDay) {
    _ensureIndex();
    return _slotsByDay[epochDay]?[timetableClassId];
  }

  CourseStats statsFor(String courseId) {
    _ensureIndex();
    return _statsByCourse[courseId] ?? CourseStats.empty;
  }

  DaySummary daySummary(int epochDay) {
    _ensureIndex();
    final cached = _daySummaries[epochDay];
    if (cached != null) return cached;
    // Days with no records still have scheduled slots; compute and memoise so
    // scrolling a month grid stays O(1) per cell.
    final scheduled = classesForWeekday(weekdayOfEpochDay(epochDay)).length;
    final summary = scheduled == 0
        ? DaySummary.empty
        : DaySummary(
            attended: 0,
            bunked: 0,
            massBunked: 0,
            holidays: 0,
            scheduled: scheduled,
          );
    return _daySummaries[epochDay] = summary;
  }

  /// The last day that counts toward "scheduled so far".
  int get windowEnd => todayEpochDay();
  int get windowStart => _settings.semesterStartDay;

  // ------------------------------------------------------------- index core
  void _ensureIndex() {
    if (!_indexDirty) return;
    _rebuildIndex();
  }

  void _rebuildIndex() {
    _indexDirty = false;
    _courseById.clear();
    _classById.clear();
    _classesByCourse.clear();
    _recordsByDay.clear();
    _recordsByCourse.clear();
    _slotsByDay.clear();
    _statsByCourse.clear();
    _daySummaries.clear();
    for (final bucket in _classesByWeekday) {
      bucket.clear();
    }
    for (final bucket in _allClassesByWeekday) {
      bucket.clear();
    }

    // O(C)
    for (final course in _courses) {
      _courseById[course.id] = course;
    }

    // O(T)
    for (final item in _timetable) {
      final course = _courseById[item.courseId];
      if (course == null) continue;
      _classById[item.id] = item;
      _allClassesByWeekday[item.weekday - 1].add(item);
      if (course.enrolled) _classesByWeekday[item.weekday - 1].add(item);
      (_classesByCourse[item.courseId] ??= <TimetableClass>[]).add(item);
    }
    // O(T log T) once per rebuild, not once per read.
    for (final bucket in _classesByWeekday) {
      bucket.sort(_compareSlots);
    }
    for (final bucket in _allClassesByWeekday) {
      bucket.sort(_compareSlots);
    }
    for (final bucket in _classesByCourse.values) {
      bucket.sort((a, b) {
        final byDay = a.weekday.compareTo(b.weekday);
        return byDay != 0 ? byDay : a.startMinute.compareTo(b.startMinute);
      });
    }

    final tallies = <String, _Tally>{};
    for (final course in _courses) {
      tallies[course.id] = _Tally();
    }

    // Scheduled occurrences per course: O(T), no calendar walk.
    final firstDay = _settings.semesterStartDay;
    final lastDay = todayEpochDay();
    for (final item in _timetable) {
      final tally = tallies[item.courseId];
      if (tally == null) continue;
      // Weighted, so a two-hour lab contributes two periods per occurrence.
      tally.scheduled +=
          weekdayOccurrences(firstDay, lastDay, item.weekday) *
          _settings.weightFor(item.durationMinutes);
    }

    // O(R)
    final orphans = <AttendanceRecord>[];
    final dayTallies = <int, _Tally>{};
    for (final record in _records) {
      final tally = tallies[record.courseId];
      if (tally == null) {
        orphans.add(record);
        continue;
      }
      (_recordsByDay[record.epochDay] ??= <AttendanceRecord>[]).add(record);
      (_recordsByCourse[record.courseId] ??= <AttendanceRecord>[]).add(record);

      // One mark on a two-hour class is worth two periods everywhere below.
      final weight = _settings.weightFor(record.durationMinutes);

      final slotId = record.timetableClassId;
      if (slotId != null && _classById.containsKey(slotId)) {
        // `_normalize` guarantees at most one record per (slot, day), so this
        // never overwrites a different record.
        (_slotsByDay[record.epochDay] ??=
                <String, AttendanceRecord>{})[slotId] =
            record;
        if (record.epochDay >= firstDay && record.epochDay <= lastDay) {
          tally.markedScheduled += weight;
        }
      }

      tally.markedSessions++;
      // Day summaries drive calendar dots, which are about "did anything
      // happen", so they stay as plain session counts.
      final dayTally = dayTallies[record.epochDay] ??= _Tally();
      switch (record.status) {
        case AttendanceStatus.attended:
          tally.attended += weight;
          dayTally.attended++;
        case AttendanceStatus.individualBunk:
          tally.bunked += weight;
          dayTally.bunked++;
        case AttendanceStatus.massBunk:
          tally.massBunked += weight;
          dayTally.massBunked++;
        case AttendanceStatus.govtHoliday:
          tally.holidays += weight;
          dayTally.holidays++;
      }
    }
    _orphanRecords = List.unmodifiable(orphans);

    for (final entry in tallies.entries) {
      final tally = entry.value;
      _statsByCourse[entry.key] = CourseStats(
        attended: tally.attended,
        bunked: tally.bunked,
        massBunked: tally.massBunked,
        holidays: tally.holidays,
        scheduled: tally.scheduled,
        markedScheduled: tally.markedScheduled,
        markedSessions: tally.markedSessions,
      );
    }

    for (final entry in dayTallies.entries) {
      final tally = entry.value;
      _daySummaries[entry.key] = DaySummary(
        attended: tally.attended,
        bunked: tally.bunked,
        massBunked: tally.massBunked,
        holidays: tally.holidays,
        scheduled: _classesByWeekday[weekdayOfEpochDay(entry.key) - 1].length,
      );
    }

    // Records sit in insertion order inside each bucket; sorting once here
    // keeps the day sheet and the course history stable without sorting on
    // every build.
    for (final bucket in _recordsByDay.values) {
      if (bucket.length > 1) bucket.sort(_compareRecords);
    }
    for (final bucket in _recordsByCourse.values) {
      if (bucket.length > 1) {
        bucket.sort((a, b) {
          final byDay = b.epochDay.compareTo(a.epochDay);
          return byDay != 0 ? byDay : _compareRecords(a, b);
        });
      }
    }
  }

  static int _compareSlots(TimetableClass a, TimetableClass b) {
    final byStart = a.startMinute.compareTo(b.startMinute);
    if (byStart != 0) return byStart;
    final byEnd = a.endMinute.compareTo(b.endMinute);
    return byEnd != 0 ? byEnd : a.id.compareTo(b.id);
  }

  int _compareRecords(AttendanceRecord a, AttendanceRecord b) {
    final slotA = _classById[a.timetableClassId];
    final slotB = _classById[b.timetableClassId];
    final startA = slotA?.startMinute ?? 1 << 20;
    final startB = slotB?.startMinute ?? 1 << 20;
    final byStart = startA.compareTo(startB);
    return byStart != 0 ? byStart : a.id.compareTo(b.id);
  }

  void _touch({bool persist = true}) {
    _indexDirty = true;
    if (persist) _scheduleSave();
    notifyListeners();
  }

  // ------------------------------------------------------------- mutations
  String _nextId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  void updateSettings({
    int? semesterStartDay,
    double? thresholdPercent,
    bool? showWeekends,
    bool? countByPeriods,
    int? periodMinutes,
  }) {
    if (semesterStartDay != null) {
      _settings.semesterStartDay = semesterStartDay;
    }
    if (thresholdPercent != null) {
      _settings.thresholdPercent = thresholdPercent.clamp(1, 100).toDouble();
    }
    if (showWeekends != null) _settings.showWeekends = showWeekends;
    if (countByPeriods != null) _settings.countByPeriods = countByPeriods;
    if (periodMinutes != null) {
      _settings.periodMinutes = periodMinutes.clamp(15, 240);
    }
    _touch();
  }

  Course saveCourse({
    Course? existing,
    required String code,
    required String name,
    String? electiveGroup,
    bool? enrolled,
  }) {
    final trimmedCode = code.trim().toUpperCase();
    final trimmedName = name.trim().isEmpty ? trimmedCode : name.trim();
    final course =
        existing ??
        Course(id: _nextId('course'), code: trimmedCode, name: trimmedName);
    course
      ..code = trimmedCode
      ..name = trimmedName
      ..electiveGroup = electiveGroup?.trim().toUpperCase().nullIfEmpty;
    if (enrolled != null) course.enrolled = enrolled;
    if (existing == null) _courses.add(course);
    _touch();
    return course;
  }

  /// Adds or removes a subject from the student's own list. Attendance already
  /// recorded is kept, just hidden, so un-ticking a course by mistake costs
  /// nothing.
  void setEnrolled(String courseId, bool enrolled) {
    final course = courseById(courseId);
    if (course == null || course.enrolled == enrolled) return;
    course.enrolled = enrolled;
    _touch();
  }

  /// Picks one option out of an elective slot, clearing the others. Passing a
  /// null [courseId] means "I am not taking this elective".
  void chooseElective(String group, String? courseId) {
    var changed = false;
    for (final course in _courses) {
      if (course.electiveGroup != group) continue;
      final shouldEnrol = course.id == courseId;
      if (course.enrolled != shouldEnrol) {
        course.enrolled = shouldEnrol;
        changed = true;
      }
    }
    if (changed) _touch();
  }

  void deleteCourse(Course course) {
    _courses.removeWhere((item) => item.id == course.id);
    _timetable.removeWhere((item) => item.courseId == course.id);
    _records.removeWhere((item) => item.courseId == course.id);
    _touch();
  }

  /// Finds a course by code, ignoring case, spaces and dashes. Used when a
  /// scanned timetable mentions `EE 301` and the library already holds
  /// `EE301`.
  Course? findCourseByCode(String code) {
    final needle = normaliseCode(code);
    if (needle.isEmpty) return null;
    for (final course in _courses) {
      if (normaliseCode(course.code) == needle) return course;
    }
    return null;
  }

  TimetableClass saveTimetableClass({
    TimetableClass? existing,
    required String courseId,
    required int weekday,
    required int startMinute,
    required int durationMinutes,
    String? title,
  }) {
    final item =
        existing ??
        TimetableClass(
          id: _nextId('class'),
          courseId: courseId,
          weekday: weekday,
          startMinute: startMinute,
          durationMinutes: durationMinutes,
        );
    item.update(
      courseId: courseId,
      weekday: weekday,
      startMinute: startMinute,
      durationMinutes: durationMinutes,
      title: title,
    );
    if (existing == null) _timetable.add(item);
    _touch();
    return item;
  }

  void deleteTimetableClass(TimetableClass item) {
    _timetable.removeWhere((entry) => entry.id == item.id);
    // Records that pointed at the slot stay, but lose the link so they are not
    // mistaken for a marked occurrence of a slot that no longer exists.
    for (final record in _records) {
      if (record.timetableClassId == item.id) record.timetableClassId = null;
    }
    _touch();
  }

  /// Replaces the whole weekly timetable (used by the scan importer).
  void replaceTimetable(List<TimetableClass> classes) {
    final keptIds = classes.map((item) => item.id).toSet();
    for (final record in _records) {
      if (record.timetableClassId != null &&
          !keptIds.contains(record.timetableClassId)) {
        record.timetableClassId = null;
      }
    }
    _timetable
      ..clear()
      ..addAll(classes);
    _touch();
  }

  void addTimetableClasses(List<TimetableClass> classes) {
    _timetable.addAll(classes);
    _touch();
  }

  /// Marks (or re-marks) one recurring slot on one date. Passing a null
  /// [status] clears the mark.
  void markSlot({
    required TimetableClass slot,
    required int epochDay,
    required AttendanceStatus? status,
  }) {
    final existing = recordForSlot(slot.id, epochDay);
    if (status == null) {
      if (existing == null) return;
      _records.remove(existing);
      _touch();
      return;
    }
    if (existing != null) {
      existing
        ..courseId = slot.courseId
        ..status = status
        ..durationMinutes = slot.durationMinutes;
      _touch();
      return;
    }
    _records.add(
      AttendanceRecord(
        id: _nextId('record'),
        courseId: slot.courseId,
        epochDay: epochDay,
        status: status,
        durationMinutes: slot.durationMinutes,
        timetableClassId: slot.id,
        note: slot.title,
      ),
    );
    _touch();
  }

  /// Marks every slot on a date at once — the "the whole day was a holiday"
  /// shortcut. The reads happen before any write, so the index is rebuilt once
  /// rather than once per slot.
  void markWholeDay(
    int epochDay,
    AttendanceStatus status, {
    bool overwrite = false,
  }) {
    final slots = classesOn(epochDay);
    if (slots.isEmpty) return;
    final marked = _slotsByDay[epochDay];
    var changed = false;
    for (final slot in slots) {
      final existing = marked?[slot.id];
      if (existing != null) {
        if (!overwrite || existing.status == status) continue;
        existing
          ..status = status
          ..courseId = slot.courseId;
        changed = true;
        continue;
      }
      _records.add(
        AttendanceRecord(
          id: _nextId('record'),
          courseId: slot.courseId,
          epochDay: epochDay,
          status: status,
          durationMinutes: slot.durationMinutes,
          timetableClassId: slot.id,
          note: slot.title,
        ),
      );
      changed = true;
    }
    if (changed) _touch();
  }

  /// Removes every mark on a date.
  void clearDay(int epochDay) {
    final onDay = recordsOn(epochDay);
    if (onDay.isEmpty) return;
    final ids = onDay.map((record) => record.id).toSet();
    _records.removeWhere((record) => ids.contains(record.id));
    _touch();
  }

  AttendanceRecord saveRecord({
    AttendanceRecord? existing,
    required String courseId,
    required int epochDay,
    required AttendanceStatus status,
    required int durationMinutes,
    String? timetableClassId,
    String? note,
  }) {
    final record =
        existing ??
        AttendanceRecord(
          id: _nextId('record'),
          courseId: courseId,
          epochDay: epochDay,
          status: status,
          durationMinutes: durationMinutes,
        );
    record
      ..courseId = courseId
      ..epochDay = epochDay
      ..status = status
      ..durationMinutes = durationMinutes < 5 ? 5 : durationMinutes
      ..timetableClassId = timetableClassId
      ..note = note?.nullIfEmpty;
    if (existing == null) _records.add(record);
    _normalise();
    _touch();
    return record;
  }

  void deleteRecord(AttendanceRecord record) {
    _records.removeWhere((item) => item.id == record.id);
    _touch();
  }

  /// True on a first run: nothing to show, so the UI offers onboarding.
  bool get isEmpty => _courses.isEmpty && _timetable.isEmpty;

  /// Fills an empty store with the fictional demo timetable.
  void loadSampleTimetable() {
    final sample = buildSampleTimetable();
    _courses
      ..clear()
      ..addAll(sample.courses);
    _timetable
      ..clear()
      ..addAll(sample.classes);
    _records.clear();
    _touch();
  }

  /// Wipes everything and returns to the welcome screen.
  void resetEverything() {
    _courses.clear();
    _timetable.clear();
    _records.clear();
    _touch();
  }

  void deleteOrphanRecords() {
    final ids = orphanRecords.map((item) => item.id).toSet();
    if (ids.isEmpty) return;
    _records.removeWhere((item) => ids.contains(item.id));
    _touch();
  }

  // ----------------------------------------------------------- persistence
  /// Set when the data on disk came from a newer build than this one. While it
  /// is true the store never writes, so an out-of-date app cannot truncate
  /// fields it does not understand.
  SchemaTooNewException? _lockedBy;
  SchemaTooNewException? get lockedBy => _lockedBy;
  bool get isReadOnly => _lockedBy != null;

  Map<String, dynamic> get snapshot => {
    'schemaVersion': kSchemaVersion,
    // Kept so a v2 build still recognises the envelope.
    'format': 2,
    'exportedAt': DateTime.now().toIso8601String(),
    'settings': _settings.toJson(),
    'courses': _courses.map((item) => item.toJson()).toList(),
    'timetable': _timetable.map((item) => item.toJson()).toList(),
    'records': _records.map((item) => item.toJson()).toList(),
  };

  /// Applies a snapshot from disk or from a paired device.
  ///
  /// Throws [FormatException] when the payload is unusable, so the caller can
  /// leave the existing data untouched.
  void applySnapshot(Map<String, dynamic> raw, {bool keepSettings = false}) {
    // Throws SchemaTooNewException for a payload from a future release, so a
    // sync from a newer device is refused rather than half-applied.
    final data = migrateToCurrent(raw);
    final incomingCourses = _decodeList(data['courses'], Course.fromJson)
        .where((course) => course.code.isNotEmpty || course.name.isNotEmpty)
        .toList();
    if (incomingCourses.isEmpty) {
      throw const FormatException('That snapshot contains no courses.');
    }
    final incomingTimetable = _decodeList(
      data['timetable'],
      TimetableClass.fromJson,
    );
    final incomingRecords = _decodeList(
      data['records'],
      AttendanceRecord.fromJson,
    );

    _courses
      ..clear()
      ..addAll(incomingCourses);
    _timetable
      ..clear()
      ..addAll(incomingTimetable);
    _records
      ..clear()
      ..addAll(incomingRecords);
    if (!keepSettings) {
      _settings = Settings.fromJson(data['settings'] as Map<String, dynamic>?);
    }
    _normalise();
    _touch();
  }

  static List<T> _decodeList<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (raw is! List) return <T>[];
    final out = <T>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        out.add(parse(Map<String, dynamic>.from(entry)));
      } catch (_) {
        // Skip the individual bad row rather than losing the whole import.
      }
    }
    return out;
  }

  /// Repairs the invariants the indexes rely on:
  ///  * ids are unique,
  ///  * a slot is never marked twice on the same date,
  ///  * slot links point at slots that exist.
  void _normalise() {
    final seenCourseIds = <String>{};
    _courses.retainWhere((course) => seenCourseIds.add(course.id));

    final seenClassIds = <String>{};
    _timetable.retainWhere((item) => seenClassIds.add(item.id));

    final seenRecordIds = <String>{};
    _records.retainWhere((record) => seenRecordIds.add(record.id));

    // Later entries win, so a re-imported day replaces the older mark.
    final claimed = <String, AttendanceRecord>{};
    final duplicates = <String>{};
    for (final record in _records) {
      final slotId = record.timetableClassId;
      if (slotId == null) continue;
      if (!seenClassIds.contains(slotId)) {
        record.timetableClassId = null;
        continue;
      }
      final key = '$slotId@${record.epochDay}';
      final previous = claimed[key];
      if (previous != null) duplicates.add(previous.id);
      claimed[key] = record;
    }
    if (duplicates.isNotEmpty) {
      _records.removeWhere((record) => duplicates.contains(record.id));
    }
    _indexDirty = true;
  }

  File get _dataFile => File('${directory!.path}/data.json');
  File get _backupFile => File('${directory!.path}/data.backup.json');

  Future<void> load() async {
    if (directory == null) {
      _indexDirty = true;
      return;
    }
    for (final file in [_dataFile, _backupFile]) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        applySnapshotQuietly(Map<String, dynamic>.from(decoded));
        return;
      } on SchemaTooNewException catch (error) {
        // Written by a newer build. Load nothing and, above all, write
        // nothing — the file stays exactly as the newer app left it.
        _lockedBy = error;
        _indexDirty = true;
        return;
      } catch (_) {
        // Fall through to the backup, then to an empty store. A corrupt file
        // must never stop the app from opening.
      }
    }
    // A first run: no data, and the UI offers to scan or add a timetable.
    _indexDirty = true;
  }

  /// Same as [applySnapshot] but without notifying or scheduling a save — used
  /// while loading, before any listener exists.
  void applySnapshotQuietly(Map<String, dynamic> raw) {
    final data = migrateToCurrent(raw);
    _courses
      ..clear()
      ..addAll(_decodeList(data['courses'], Course.fromJson));
    _timetable
      ..clear()
      ..addAll(_decodeList(data['timetable'], TimetableClass.fromJson));
    _records
      ..clear()
      ..addAll(_decodeList(data['records'], AttendanceRecord.fromJson));
    _settings = Settings.fromJson(data['settings'] as Map<String, dynamic>?);
    _normalise();
    _indexDirty = true;
  }

  void _scheduleSave() {
    if (directory == null || _disposed || isReadOnly) return;
    _saveTimer?.cancel();
    // Coalesce bursts (dragging a slider, marking a whole day) into one write.
    _saveTimer = Timer(const Duration(milliseconds: 350), flush);
  }

  /// Writes the snapshot atomically: a temporary file is written in full and
  /// then renamed over `data.json`, so a crash mid-write can never leave a
  /// half-written file behind. The previous good file is kept as a backup.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final dir = directory;
    if (dir == null || isReadOnly) return;
    try {
      await dir.create(recursive: true);
      final payload = jsonEncode(snapshot);
      final temp = File('${dir.path}/data.json.tmp');
      await temp.writeAsString(payload, flush: true);
      if (await _dataFile.exists()) {
        try {
          await _dataFile.copy(_backupFile.path);
        } catch (_) {
          // A missing backup is not worth failing the save for.
        }
      }
      await temp.rename(_dataFile.path);
    } catch (_) {
      // The in-memory tracker stays usable if the platform blocks storage.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    super.dispose();
  }
}

/// `EE 301`, `ee-301` and `EE301` all normalise to `EE301`.
String normaliseCode(String value) {
  final buffer = StringBuffer();
  for (final unit in value.toUpperCase().codeUnits) {
    final isDigit = unit >= 0x30 && unit <= 0x39;
    final isLetter = unit >= 0x41 && unit <= 0x5A;
    if (isDigit || isLetter) buffer.writeCharCode(unit);
  }
  return buffer.toString();
}
