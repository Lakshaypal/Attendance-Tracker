import 'package:flutter/material.dart';

import 'civil_date.dart';
import 'migrations.dart';

/// What happened to one scheduled class.
enum AttendanceStatus {
  attended,
  individualBunk,
  massBunk,
  govtHoliday;

  /// Whether the class actually took place. Government holidays did not, so
  /// they never reach any denominator.
  bool get wasHeld => this != AttendanceStatus.govtHoliday;

  /// Whether the student was in the room.
  bool get wasPresent => this == AttendanceStatus.attended;
}

extension AttendanceStatusInfo on AttendanceStatus {
  String get label => switch (this) {
    AttendanceStatus.attended => 'Attended',
    AttendanceStatus.individualBunk => 'Bunked',
    AttendanceStatus.massBunk => 'Mass bunk',
    AttendanceStatus.govtHoliday => 'Holiday',
  };

  String get description => switch (this) {
    AttendanceStatus.attended => 'You were present',
    AttendanceStatus.individualBunk => 'You skipped, the class ran',
    AttendanceStatus.massBunk => 'The whole class skipped',
    AttendanceStatus.govtHoliday => 'No class took place',
  };

  IconData get icon => switch (this) {
    AttendanceStatus.attended => Icons.check_circle_rounded,
    AttendanceStatus.individualBunk => Icons.person_off_rounded,
    AttendanceStatus.massBunk => Icons.groups_rounded,
    AttendanceStatus.govtHoliday => Icons.event_busy_rounded,
  };

  Color get tint => switch (this) {
    AttendanceStatus.attended => const Color(0xFF18865A),
    AttendanceStatus.individualBunk => const Color(0xFFD6353B),
    AttendanceStatus.massBunk => const Color(0xFFE08205),
    AttendanceStatus.govtHoliday => const Color(0xFF6D7785),
  };
}

AttendanceStatus statusFromName(String? value) {
  for (final status in AttendanceStatus.values) {
    if (status.name == value) return status;
  }
  return AttendanceStatus.attended;
}

/// A subject in the department timetable.
///
/// A stored timetable describes a whole class group, so it holds every subject
/// on offer — including all the options inside an elective slot. [enrolled]
/// is what makes it *yours*: only enrolled courses appear in the grid, on the
/// calendar, and in the attendance figures.
class Course {
  Course({
    required this.id,
    required this.code,
    required this.name,
    this.electiveGroup,
    this.enrolled = true,
    this.colorSeed,
    this.extra,
  });

  static const Set<String> _known = {
    'id',
    'code',
    'name',
    'electiveGroup',
    'option',
    'enrolled',
    'colorSeed',
  };

  final String id;
  String code;
  String name;

  /// The elective slot this course competes for, e.g. `E1`. Null for a core
  /// subject that everyone in the group attends.
  String? electiveGroup;

  /// Whether the student is taking this subject.
  bool enrolled;

  /// Optional override for the auto-assigned palette slot.
  int? colorSeed;

  /// Fields written by a newer version of the app, carried through untouched.
  final Map<String, dynamic>? extra;

  bool get isElective => electiveGroup != null;

  Map<String, dynamic> toJson() => withExtras({
    'id': id,
    'code': code,
    'name': name,
    'electiveGroup': electiveGroup,
    'enrolled': enrolled,
    'colorSeed': colorSeed,
  }, extra);

  factory Course.fromJson(Map<String, dynamic> json) => Course(
    id: (json['id'] as String?) ?? 'course-${json.hashCode}',
    code: ((json['code'] as String?) ?? '').trim(),
    name: ((json['name'] as String?) ?? '').trim(),
    // `option` is the pre-elective-group field name.
    electiveGroup:
        (json['electiveGroup'] as String?)?.trim().nullIfEmpty ??
        (json['option'] as String?)?.trim().nullIfEmpty,
    // Data saved before subject picking existed describes courses the student
    // was already taking, so it defaults to enrolled.
    enrolled: json['enrolled'] as bool? ?? true,
    colorSeed: (json['colorSeed'] as num?)?.toInt(),
    extra: extraFieldsOf(json, _known),
  );
}

/// One recurring weekly slot.
class TimetableClass {
  TimetableClass({
    required this.id,
    required this.courseId,
    required int weekday,
    required int startMinute,
    required int durationMinutes,
    this.title,
    this.extra,
  }) : weekday = clampWeekday(weekday),
       startMinute = clampStartMinute(startMinute),
       durationMinutes = clampDuration(durationMinutes);

  final String id;
  String courseId;
  int weekday;
  int startMinute;
  int durationMinutes;
  String? title;

  /// Fields written by a newer version of the app, carried through untouched.
  final Map<String, dynamic>? extra;

  static const Set<String> _known = {
    'id',
    'courseId',
    'weekday',
    'startMinute',
    'durationMinutes',
    'title',
  };

  int get endMinute => startMinute + durationMinutes;

  void update({
    String? courseId,
    int? weekday,
    int? startMinute,
    int? durationMinutes,
    String? title,
  }) {
    if (courseId != null) this.courseId = courseId;
    if (weekday != null) this.weekday = clampWeekday(weekday);
    if (startMinute != null) this.startMinute = clampStartMinute(startMinute);
    if (durationMinutes != null) {
      this.durationMinutes = clampDuration(durationMinutes);
    }
    this.title = title?.trim().nullIfEmpty;
  }

  Map<String, dynamic> toJson() => withExtras({
    'id': id,
    'courseId': courseId,
    'weekday': weekday,
    'startMinute': startMinute,
    'durationMinutes': durationMinutes,
    'title': title,
  }, extra);

  factory TimetableClass.fromJson(Map<String, dynamic> json) => TimetableClass(
    id: (json['id'] as String?) ?? 'class-${json.hashCode}',
    courseId: (json['courseId'] as String?) ?? '',
    weekday: (json['weekday'] as num?)?.toInt() ?? DateTime.monday,
    startMinute: (json['startMinute'] as num?)?.toInt() ?? 540,
    durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 60,
    title: (json['title'] as String?)?.trim().nullIfEmpty,
    extra: extraFieldsOf(json, _known),
  );

  /// Keeps a slot inside a single day even if a bad import or a hand-edited
  /// file supplies nonsense.
  static int clampWeekday(int value) => value < 1 || value > 7 ? 1 : value;
  static int clampStartMinute(int value) =>
      value < 0 ? 0 : (value > 1439 ? 1439 : value);
  static int clampDuration(int value) =>
      value < 5 ? 5 : (value > 600 ? 600 : value);
}

/// One marked class on one date.
class AttendanceRecord {
  AttendanceRecord({
    required this.id,
    required this.courseId,
    required this.epochDay,
    required this.status,
    required this.durationMinutes,
    this.timetableClassId,
    this.note,
    this.extra,
  });

  final String id;
  String courseId;
  int epochDay;
  AttendanceStatus status;
  int durationMinutes;

  /// Set when the record belongs to a recurring slot; null for manual one-offs.
  String? timetableClassId;
  String? note;

  /// Fields written by a newer version of the app, carried through untouched.
  final Map<String, dynamic>? extra;

  static const Set<String> _known = {
    'id',
    'courseId',
    'date',
    'status',
    'durationMinutes',
    'timetableClassId',
    'note',
  };

  DateTime get date => dateTimeFromEpochDay(epochDay);
  int get weekday => weekdayOfEpochDay(epochDay);

  Map<String, dynamic> toJson() => withExtras({
    'id': id,
    'courseId': courseId,
    'date': isoDateString(epochDay),
    'status': status.name,
    'durationMinutes': durationMinutes,
    'timetableClassId': timetableClassId,
    'note': note,
  }, extra);

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) =>
      AttendanceRecord(
        id: (json['id'] as String?) ?? 'record-${json.hashCode}',
        courseId: (json['courseId'] as String?) ?? '',
        epochDay:
            parseIsoDateToEpochDay(json['date'] as String?) ?? todayEpochDay(),
        status: statusFromName(json['status'] as String?),
        durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 60,
        timetableClassId: (json['timetableClassId'] as String?)?.nullIfEmpty,
        note: (json['note'] as String?)?.trim().nullIfEmpty,
        extra: extraFieldsOf(json, _known),
      );
}

/// Everything the UI needs about one course, all of it derived in a single
/// pass over the records when the store rebuilds its index.
class CourseStats {
  const CourseStats({
    required this.attended,
    required this.bunked,
    required this.massBunked,
    required this.holidays,
    required this.scheduled,
    required this.markedScheduled,
  });

  static const empty = CourseStats(
    attended: 0,
    bunked: 0,
    massBunked: 0,
    holidays: 0,
    scheduled: 0,
    markedScheduled: 0,
  );

  final int attended;
  final int bunked;
  final int massBunked;
  final int holidays;

  /// Slot occurrences between the semester start and today, from the weekly
  /// timetable alone.
  final int scheduled;

  /// How many of those occurrences already carry a record.
  final int markedScheduled;

  int get marked => attended + bunked + massBunked + holidays;

  /// Classes that actually took place. Holidays are excluded from both the
  /// numerator and the denominator.
  int get held => attended + bunked + massBunked;

  /// Denominator once mass-bunked classes are removed as well.
  int get heldExcludingMassBunks => attended + bunked;

  /// Scheduled classes that have not been marked yet.
  int get pending =>
      scheduled > markedScheduled ? scheduled - markedScheduled : 0;

  /// Null when nothing has been held yet — the UI shows "—" instead of a
  /// misleading 0%.
  double? get percent => held == 0 ? null : attended / held * 100;

  double? get adjustedPercent => heldExcludingMassBunks == 0
      ? null
      : attended / heldExcludingMassBunks * 100;

  /// How many further classes can be skipped while staying at or above
  /// [threshold] (0…1). Solves `attended / (held + k) >= threshold`.
  int skipsAvailable(double threshold) {
    if (threshold <= 0) return 999;
    final limit = attended / threshold;
    final slack = limit.floor() - held;
    return slack > 0 ? slack : 0;
  }

  /// How many consecutive classes must be attended to reach [threshold].
  /// Solves `(attended + k) / (held + k) >= threshold`.
  int classesNeeded(double threshold) {
    if (threshold >= 1) return held == attended ? 0 : 1 << 30;
    if (held == 0) return 0;
    if (attended >= threshold * held) return 0;
    final needed = (threshold * held - attended) / (1 - threshold);
    return needed.ceil();
  }
}

/// Aggregate shown on a calendar cell. Kept as counts so the cell can paint
/// without walking the day's records again.
class DaySummary {
  const DaySummary({
    required this.attended,
    required this.bunked,
    required this.massBunked,
    required this.holidays,
    required this.scheduled,
  });

  static const empty = DaySummary(
    attended: 0,
    bunked: 0,
    massBunked: 0,
    holidays: 0,
    scheduled: 0,
  );

  final int attended;
  final int bunked;
  final int massBunked;
  final int holidays;

  /// Slots on that weekday, from the timetable.
  final int scheduled;

  int get marked => attended + bunked + massBunked + holidays;
  bool get isEmpty => marked == 0 && scheduled == 0;
  bool get hasAbsence => bunked > 0 || massBunked > 0;
}

extension NullIfEmpty on String {
  String? get nullIfEmpty {
    final trimmed = trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
