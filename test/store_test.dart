import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:attendance_tracker/src/civil_date.dart';
import 'package:attendance_tracker/src/models.dart';
import 'package:attendance_tracker/src/store.dart';
import 'package:flutter_test/flutter_test.dart';

/// An intentionally slow, obvious implementation of the statistics, used to
/// prove that the indexed version in [AttendanceStore] returns the same
/// answers. It walks the calendar day by day and rescans every record, which
/// is exactly what the fast path avoids.
CourseStats naiveStats(AttendanceStore store, String courseId) {
  var attended = 0, bunked = 0, massBunked = 0, holidays = 0;
  for (final record in store.records) {
    if (record.courseId != courseId) continue;
    if (store.courseById(record.courseId) == null) continue;
    switch (record.status) {
      case AttendanceStatus.attended:
        attended++;
      case AttendanceStatus.individualBunk:
        bunked++;
      case AttendanceStatus.massBunk:
        massBunked++;
      case AttendanceStatus.govtHoliday:
        holidays++;
    }
  }

  var scheduled = 0;
  var marked = 0;
  final liveClassIds = store.timetable.map((slot) => slot.id).toSet();
  for (
    var day = store.settings.semesterStartDay;
    day <= todayEpochDay();
    day++
  ) {
    final weekday = weekdayOfEpochDay(day);
    for (final slot in store.timetable) {
      if (slot.weekday != weekday) continue;
      if (slot.courseId != courseId) continue;
      if (store.courseById(slot.courseId) == null) continue;
      scheduled++;
      final hit = store.records.any(
        (record) =>
            record.epochDay == day &&
            record.timetableClassId == slot.id &&
            liveClassIds.contains(record.timetableClassId),
      );
      if (hit) marked++;
    }
  }

  return CourseStats(
    attended: attended,
    bunked: bunked,
    massBunked: massBunked,
    holidays: holidays,
    scheduled: scheduled,
    markedScheduled: marked,
  );
}

void expectSameStats(CourseStats fast, CourseStats slow, String label) {
  expect(fast.attended, slow.attended, reason: '$label attended');
  expect(fast.bunked, slow.bunked, reason: '$label bunked');
  expect(fast.massBunked, slow.massBunked, reason: '$label mass bunked');
  expect(fast.holidays, slow.holidays, reason: '$label holidays');
  expect(fast.scheduled, slow.scheduled, reason: '$label scheduled');
  expect(fast.pending, slow.pending, reason: '$label pending');
  expect(fast.held, slow.held, reason: '$label held');
  expect(fast.percent, slow.percent, reason: '$label percent');
}

void main() {
  group('percentage rules', () {
    test(
      'holidays leave both figures alone, mass bunks only the adjusted one',
      () {
        const stats = CourseStats(
          attended: 8,
          bunked: 1,
          massBunked: 2,
          holidays: 3,
          scheduled: 14,
          markedScheduled: 14,
        );
        expect(stats.marked, 14);
        expect(stats.held, 11); // holidays excluded
        expect(stats.heldExcludingMassBunks, 9);
        expect(stats.percent, closeTo(72.73, 0.01));
        expect(stats.adjustedPercent, closeTo(88.89, 0.01));
        expect(stats.pending, 0);
      },
    );

    test('nothing marked reports null rather than a misleading zero', () {
      expect(CourseStats.empty.percent, isNull);
      expect(CourseStats.empty.adjustedPercent, isNull);
    });

    test('skip advice never claims room that does not exist', () {
      // 8 of 10 = 80%, target 75%.
      const stats = CourseStats(
        attended: 8,
        bunked: 2,
        massBunked: 0,
        holidays: 0,
        scheduled: 10,
        markedScheduled: 10,
      );
      final spare = stats.skipsAvailable(0.75);
      expect(spare, 0); // 8/11 = 72.7%, so there is no room at all
      expect(8 / (10 + spare) * 100, greaterThanOrEqualTo(75));

      const comfortable = CourseStats(
        attended: 20,
        bunked: 0,
        massBunked: 0,
        holidays: 0,
        scheduled: 20,
        markedScheduled: 20,
      );
      final room = comfortable.skipsAvailable(0.75);
      expect(20 / (20 + room) * 100, greaterThanOrEqualTo(75));
      expect(20 / (20 + room + 1) * 100, lessThan(75));
    });

    test('recovery advice is the smallest streak that reaches the target', () {
      const stats = CourseStats(
        attended: 5,
        bunked: 5,
        massBunked: 0,
        holidays: 0,
        scheduled: 10,
        markedScheduled: 10,
      );
      final needed = stats.classesNeeded(0.75);
      expect((5 + needed) / (10 + needed) * 100, greaterThanOrEqualTo(75));
      expect((5 + needed - 1) / (10 + needed - 1) * 100, lessThan(75));
    });

    test('a course already above target needs nothing', () {
      const stats = CourseStats(
        attended: 9,
        bunked: 1,
        massBunked: 0,
        holidays: 0,
        scheduled: 10,
        markedScheduled: 10,
      );
      expect(stats.classesNeeded(0.75), 0);
    });
  });

  group('indexed store versus a brute-force reference', () {
    test('agrees on randomly generated semesters', () {
      final random = Random(20260730);
      for (var trial = 0; trial < 12; trial++) {
        final store = AttendanceStore();
        final start = todayEpochDay() - 40 - random.nextInt(60);
        store.updateSettings(semesterStartDay: start);

        final courseIds = <String>[];
        final courseCount = 2 + random.nextInt(4);
        for (var c = 0; c < courseCount; c++) {
          courseIds.add(
            store.saveCourse(code: 'XX${100 + c}', name: 'Course $c').id,
          );
        }

        final slots = <TimetableClass>[];
        final slotCount = 3 + random.nextInt(10);
        for (var s = 0; s < slotCount; s++) {
          slots.add(
            store.saveTimetableClass(
              courseId: courseIds[random.nextInt(courseIds.length)],
              weekday: 1 + random.nextInt(7),
              startMinute: 8 * 60 + random.nextInt(9) * 60,
              durationMinutes: [60, 60, 90, 120][random.nextInt(4)],
            ),
          );
        }

        // Mark a random subset of real occurrences, plus some one-off records
        // and some records outside the semester window.
        for (var day = start - 5; day <= todayEpochDay() + 3; day++) {
          for (final slot in store.classesOn(day)) {
            if (random.nextInt(100) < 55) {
              store.markSlot(
                slot: slot,
                epochDay: day,
                status: AttendanceStatus
                    .values[random.nextInt(AttendanceStatus.values.length)],
              );
            }
          }
          if (random.nextInt(100) < 8) {
            store.saveRecord(
              courseId: courseIds[random.nextInt(courseIds.length)],
              epochDay: day,
              status: AttendanceStatus.attended,
              durationMinutes: 60,
            );
          }
        }

        for (final id in courseIds) {
          expectSameStats(
            store.statsFor(id),
            naiveStats(store, id),
            'trial $trial course $id',
          );
        }
      }
    });

    test('stays correct after deletions', () {
      final store = AttendanceStore();
      store.updateSettings(semesterStartDay: todayEpochDay() - 30);
      final keep = store.saveCourse(code: 'AA101', name: 'Keep');
      final drop = store.saveCourse(code: 'BB202', name: 'Drop');
      final keepSlot = store.saveTimetableClass(
        courseId: keep.id,
        weekday: weekdayOfEpochDay(todayEpochDay()),
        startMinute: 600,
        durationMinutes: 60,
      );
      final dropSlot = store.saveTimetableClass(
        courseId: drop.id,
        weekday: weekdayOfEpochDay(todayEpochDay()),
        startMinute: 720,
        durationMinutes: 60,
      );
      store.markSlot(
        slot: keepSlot,
        epochDay: todayEpochDay(),
        status: AttendanceStatus.attended,
      );
      store.markSlot(
        slot: dropSlot,
        epochDay: todayEpochDay(),
        status: AttendanceStatus.attended,
      );

      store.deleteCourse(drop);
      expect(store.statsFor(drop.id), same(CourseStats.empty));
      expectSameStats(
        store.statsFor(keep.id),
        naiveStats(store, keep.id),
        'after course deletion',
      );

      // Deleting the slot unlinks its record, so nothing is counted as a
      // marked occurrence of a slot that no longer exists.
      store.deleteTimetableClass(keepSlot);
      final stats = store.statsFor(keep.id);
      expect(stats.scheduled, 0);
      expect(stats.attended, 1, reason: 'the record itself survives');
      expect(stats.pending, 0);
    });
  });

  group('picking your own subjects out of a shared timetable', () {
    test(
      'a fresh install starts empty, not with someone else\'s timetable',
      () async {
        final store = AttendanceStore();
        await store.load();
        expect(store.isEmpty, isTrue);
        expect(store.courses, isEmpty);
        expect(store.timetable, isEmpty);
      },
    );

    test('the sample keeps every elective option, none of them picked', () {
      final store = AttendanceStore()..loadSampleTimetable();

      expect(store.courses.length, greaterThan(store.enrolledCourses.length));
      final groups = {
        for (final entry in store.electiveGroups) entry.group: entry.options,
      };
      expect(groups.keys, contains('E1'));
      expect(groups['E1']!, hasLength(3));
      for (final entry in store.electiveGroups) {
        expect(
          entry.options.where((course) => course.enrolled).length,
          lessThanOrEqualTo(1),
          reason: '${entry.group} must not have two options ticked',
        );
      }
      expect(store.enrolledCourses.map((course) => course.code).toSet(), {
        'MA101',
        'PH102',
        'CS103',
      });
    });

    test('the grid shows only the subjects you picked', () {
      final store = AttendanceStore()..loadSampleTimetable();

      final allMonday = store.allClassesForWeekday(DateTime.monday);
      final mineMonday = store.classesForWeekday(DateTime.monday);
      expect(allMonday.length, greaterThan(mineMonday.length));

      // The 2pm E1 band holds three options and none is picked yet.
      expect(
        allMonday.where((slot) => slot.startMinute == 14 * 60),
        hasLength(3),
      );
      expect(mineMonday.where((slot) => slot.startMinute == 14 * 60), isEmpty);
    });

    test('choosing an elective fills its slot', () {
      final store = AttendanceStore()..loadSampleTimetable();
      final option = store.findCourseByCode('EL202')!;

      store.chooseElective('E1', option.id);

      final band = store
          .classesForWeekday(DateTime.monday)
          .where((slot) => slot.startMinute == 14 * 60);
      expect(band, hasLength(1));
      expect(store.courseById(band.single.courseId)!.code, 'EL202');
      expect(store.findCourseByCode('EL201')!.enrolled, isFalse);
      expect(store.findCourseByCode('EL203')!.enrolled, isFalse);
    });

    test('swapping the pick swaps the slot over', () {
      final store = AttendanceStore()..loadSampleTimetable();
      store.chooseElective('E1', store.findCourseByCode('EL202')!.id);
      store.chooseElective('E1', store.findCourseByCode('EL203')!.id);

      final band = store
          .classesForWeekday(DateTime.monday)
          .where((slot) => slot.startMinute == 14 * 60);
      expect(band, hasLength(1));
      expect(store.courseById(band.single.courseId)!.code, 'EL203');
      expect(store.findCourseByCode('EL202')!.enrolled, isFalse);
    });

    test('dropping an elective empties its slot but keeps the timetable', () {
      final store = AttendanceStore()..loadSampleTimetable();
      store.chooseElective('E1', store.findCourseByCode('EL201')!.id);
      store.chooseElective('E1', null);

      expect(
        store
            .classesForWeekday(DateTime.monday)
            .where((slot) => slot.startMinute == 14 * 60),
        isEmpty,
      );
      expect(
        store
            .allClassesForWeekday(DateTime.monday)
            .where((slot) => slot.startMinute == 14 * 60),
        hasLength(3),
      );
      expect(store.findCourseByCode('MA101')!.enrolled, isTrue);
    });

    test('un-enrolling hides a subject but keeps its attendance', () {
      final store = AttendanceStore()..loadSampleTimetable();
      final maths = store.findCourseByCode('MA101')!;
      final slot = store.classesForCourse(maths.id).first;
      final day = startOfWeek(todayEpochDay()) + slot.weekday - 1;
      store.markSlot(
        slot: slot,
        epochDay: day,
        status: AttendanceStatus.attended,
      );
      expect(store.statsFor(maths.id).attended, 1);

      store.setEnrolled(maths.id, false);
      expect(
        store.enrolledCourses.any((course) => course.id == maths.id),
        isFalse,
      );
      expect(store.classesForWeekday(slot.weekday).contains(slot), isFalse);
      expect(
        store.statsFor(maths.id).attended,
        1,
        reason: 'the record must survive so re-ticking restores it',
      );

      store.setEnrolled(maths.id, true);
      expect(store.classesForWeekday(slot.weekday).contains(slot), isTrue);
    });

    test('enrolment survives a save and reload', () async {
      final dir = await Directory.systemTemp.createTemp('attendance-enrol');
      addTearDown(() => dir.delete(recursive: true));

      final first = AttendanceStore(directory: dir);
      await first.load();
      first.loadSampleTimetable();
      first.chooseElective('E1', first.findCourseByCode('EL203')!.id);
      await first.flush();

      final second = AttendanceStore(directory: dir);
      await second.load();
      expect(second.findCourseByCode('EL203')!.enrolled, isTrue);
      expect(second.findCourseByCode('EL201')!.enrolled, isFalse);
      expect(second.findCourseByCode('MA101')!.enrolled, isTrue);
    });

    test('data saved before subject picking stays fully enrolled', () {
      final store = AttendanceStore();
      store.applySnapshot({
        'courses': [
          {'id': 'a', 'code': 'AA111', 'name': 'Legacy', 'option': 'E1'},
        ],
        'timetable': const <dynamic>[],
        'records': const <dynamic>[],
      });
      final course = store.findCourseByCode('AA111')!;
      expect(course.enrolled, isTrue);
      expect(
        course.electiveGroup,
        'E1',
        reason: 'option maps to the new field',
      );
    });
  });

  group('data integrity', () {
    test('a slot can only be marked once per day', () {
      final store = AttendanceStore();
      final course = store.saveCourse(code: 'CC303', name: 'Course');
      final slot = store.saveTimetableClass(
        courseId: course.id,
        weekday: DateTime.monday,
        startMinute: 600,
        durationMinutes: 60,
      );
      final monday = startOfWeek(todayEpochDay());

      store.markSlot(
        slot: slot,
        epochDay: monday,
        status: AttendanceStatus.attended,
      );
      store.markSlot(
        slot: slot,
        epochDay: monday,
        status: AttendanceStatus.individualBunk,
      );

      expect(store.records.length, 1);
      expect(
        store.recordForSlot(slot.id, monday)!.status,
        AttendanceStatus.individualBunk,
      );
    });

    test('clearing a mark removes the record', () {
      final store = AttendanceStore();
      final course = store.saveCourse(code: 'DD404', name: 'Course');
      final slot = store.saveTimetableClass(
        courseId: course.id,
        weekday: DateTime.tuesday,
        startMinute: 600,
        durationMinutes: 60,
      );
      final day = startOfWeek(todayEpochDay()) + 1;
      store.markSlot(
        slot: slot,
        epochDay: day,
        status: AttendanceStatus.attended,
      );
      expect(store.records, hasLength(1));
      store.markSlot(slot: slot, epochDay: day, status: null);
      expect(store.records, isEmpty);
      expect(store.recordForSlot(slot.id, day), isNull);
    });

    test('markWholeDay leaves existing marks alone unless told otherwise', () {
      final store = AttendanceStore();
      final course = store.saveCourse(code: 'EE505', name: 'Course');
      final weekday = weekdayOfEpochDay(todayEpochDay());
      final first = store.saveTimetableClass(
        courseId: course.id,
        weekday: weekday,
        startMinute: 540,
        durationMinutes: 60,
      );
      store.saveTimetableClass(
        courseId: course.id,
        weekday: weekday,
        startMinute: 660,
        durationMinutes: 60,
      );
      final today = todayEpochDay();

      store.markSlot(
        slot: first,
        epochDay: today,
        status: AttendanceStatus.individualBunk,
      );
      store.markWholeDay(today, AttendanceStatus.attended);
      expect(
        store.recordForSlot(first.id, today)!.status,
        AttendanceStatus.individualBunk,
      );
      expect(store.recordsOn(today), hasLength(2));

      store.markWholeDay(today, AttendanceStatus.govtHoliday, overwrite: true);
      expect(
        store
            .recordsOn(today)
            .every((record) => record.status == AttendanceStatus.govtHoliday),
        isTrue,
      );

      store.clearDay(today);
      expect(store.recordsOn(today), isEmpty);
    });

    test('records for deleted courses are quarantined, not counted', () {
      final store = AttendanceStore();
      final course = store.saveCourse(code: 'FF606', name: 'Course');
      store.saveRecord(
        courseId: course.id,
        epochDay: todayEpochDay(),
        status: AttendanceStatus.attended,
        durationMinutes: 60,
      );
      store.applySnapshot({
        'courses': [
          {'id': 'other', 'code': 'GG707', 'name': 'Other'},
        ],
        'timetable': const <dynamic>[],
        'records': [
          {
            'id': 'ghost',
            'courseId': 'missing',
            'date': isoDateString(todayEpochDay()),
            'status': 'attended',
            'durationMinutes': 60,
          },
        ],
      });
      expect(store.orphanRecords, hasLength(1));
      final stats = store.statsFor('other');
      expect(stats.marked, 0, reason: 'the ghost record is not counted');
      expect(stats.percent, isNull);
      store.deleteOrphanRecords();
      expect(store.orphanRecords, isEmpty);
      expect(store.records, isEmpty);
    });

    test('nonsense values are clamped instead of corrupting the grid', () {
      final slot = TimetableClass(
        id: 'x',
        courseId: 'c',
        weekday: 99,
        startMinute: -400,
        durationMinutes: 100000,
      );
      expect(slot.weekday, 1);
      expect(slot.startMinute, 0);
      expect(slot.durationMinutes, 600);
    });

    test('a snapshot with no courses is rejected outright', () {
      final store = AttendanceStore();
      store.saveCourse(code: 'HH808', name: 'Keep me');
      expect(
        () => store.applySnapshot({'courses': const <dynamic>[]}),
        throwsA(isA<FormatException>()),
      );
      expect(store.courses, hasLength(1));
    });

    test('malformed rows are skipped without losing the good ones', () {
      final store = AttendanceStore();
      store.applySnapshot({
        'courses': [
          {'id': 'a', 'code': 'AA111', 'name': 'Good'},
          'not a map',
          {'id': 'b', 'code': 'BB222', 'name': 'Also good'},
        ],
        'timetable': [
          {
            'id': 's1',
            'courseId': 'a',
            'weekday': 1,
            'startMinute': 600,
            'durationMinutes': 60,
          },
          {'garbage': true},
        ],
        'records': const <dynamic>[],
      });
      expect(store.courses, hasLength(2));
      // Both rows are kept verbatim, but the one with no usable course never
      // reaches the grid.
      expect(store.timetable, hasLength(2));
      expect(store.classesForWeekday(1), hasLength(1));
      expect(store.classesForWeekday(1).single.courseId, 'a');
    });
  });

  group('persistence', () {
    test('survives a save and reload, and repairs a corrupt file', () async {
      final dir = await Directory.systemTemp.createTemp('attendance-test');
      addTearDown(() => dir.delete(recursive: true));

      final first = AttendanceStore(directory: dir);
      await first.load();
      final course = first.saveCourse(code: 'ZZ999', name: 'Persisted');
      final slot = first.saveTimetableClass(
        courseId: course.id,
        weekday: DateTime.wednesday,
        startMinute: 600,
        durationMinutes: 90,
      );
      final day = startOfWeek(todayEpochDay()) + 2;
      first.markSlot(
        slot: slot,
        epochDay: day,
        status: AttendanceStatus.massBunk,
      );
      first.updateSettings(thresholdPercent: 80, semesterStartDay: day - 20);
      await first.flush();
      // The backup holds the *previous* good save, so a second flush is what
      // promotes this state into it.
      await first.flush();

      final second = AttendanceStore(directory: dir);
      await second.load();
      final restored = second.findCourseByCode('zz 999')!;
      expect(restored.name, 'Persisted');
      expect(second.settings.thresholdPercent, 80);
      expect(second.settings.semesterStartDay, day - 20);
      final restoredSlot = second.classesForCourse(restored.id).single;
      expect(restoredSlot.weekday, DateTime.wednesday);
      expect(restoredSlot.durationMinutes, 90);
      expect(
        second.recordForSlot(restoredSlot.id, day)!.status,
        AttendanceStatus.massBunk,
      );
      expect(second.statsFor(restored.id).massBunked, 1);

      // A half-written main file must fall back to the backup rather than
      // dropping the semester on the floor.
      await File('${dir.path}/data.json').writeAsString('{"courses": [{');
      final third = AttendanceStore(directory: dir);
      await third.load();
      final recovered = third.findCourseByCode('ZZ999');
      expect(recovered, isNotNull);
      expect(third.statsFor(recovered!.id).massBunked, 1);
    });

    test('an unreadable file still opens the app, on onboarding', () async {
      final dir = await Directory.systemTemp.createTemp('attendance-broken');
      addTearDown(() => dir.delete(recursive: true));
      await File('${dir.path}/data.json').writeAsString('not json at all');
      await File('${dir.path}/data.backup.json').writeAsString(']]]');

      final store = AttendanceStore(directory: dir);
      await store.load();
      // Nothing is invented; the user is asked where their timetable comes
      // from instead.
      expect(store.isEmpty, isTrue);
      expect(store.isReadOnly, isFalse);
    });

    test('the snapshot is valid json and re-imports cleanly', () {
      final source = AttendanceStore()..loadSampleTimetable();
      final encoded = jsonEncode(source.snapshot);
      final target = AttendanceStore();
      target.applySnapshot(
        Map<String, dynamic>.from(jsonDecode(encoded) as Map),
      );
      expect(target.courses.length, source.courses.length);
      expect(target.timetable.length, source.timetable.length);
    });
  });

  test('code matching ignores case, spaces and dashes', () {
    expect(normaliseCode('ee 301'), 'EE301');
    expect(normaliseCode('EE-301'), 'EE301');
    expect(normaliseCode('  Ee301 '), 'EE301');
    expect(normaliseCode(''), '');
  });
}
