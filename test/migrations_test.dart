import 'dart:convert';
import 'dart:io';

import 'package:attendance_tracker/src/civil_date.dart';
import 'package:attendance_tracker/src/migrations.dart';
import 'package:attendance_tracker/src/models.dart';
import 'package:attendance_tracker/src/store.dart';
import 'package:flutter_test/flutter_test.dart';

/// A version-1 document, exactly as the first release wrote it.
Map<String, dynamic> legacyV1() => {
  'courses': [
    {'id': 'c1', 'code': 'EE301', 'name': 'Power Electronics'},
    {'id': 'c2', 'code': 'EE323', 'name': 'Machine Learning', 'option': 'E2'},
  ],
  'timetable': [
    {
      'id': 's1',
      'courseId': 'c1',
      'weekday': 1,
      'startMinute': 600,
      'durationMinutes': 60,
      'title': 'PECC Lab',
    },
  ],
  'records': [
    {
      'id': 'r1',
      'courseId': 'c1',
      'date': '2026-07-27',
      'status': 'attended',
      'durationMinutes': 60,
      'timetableClassId': 's1',
    },
  ],
};

void main() {
  group('version detection', () {
    test('a document with no marker is version 1', () {
      expect(schemaVersionOf(legacyV1()), 1);
    });

    test('the v2 format marker is understood', () {
      expect(schemaVersionOf({'format': 2}), 2);
    });

    test('an explicit schemaVersion wins', () {
      expect(schemaVersionOf({'format': 2, 'schemaVersion': 3}), 3);
    });
  });

  group('migrating forward', () {
    test('a version 1 file becomes current without losing anything', () {
      final migrated = migrateToCurrent(legacyV1());
      expect(migrated['schemaVersion'], kSchemaVersion);

      final store = AttendanceStore()..applySnapshot(migrated);
      expect(store.courses, hasLength(2));
      expect(store.timetable, hasLength(1));
      expect(store.records, hasLength(1));

      // `option` became `electiveGroup`.
      final elective = store.findCourseByCode('EE323')!;
      expect(elective.electiveGroup, 'E2');

      // Everything a v1 user had was a subject they were taking.
      expect(store.enrolledCourses, hasLength(2));

      // The attendance itself survives, still linked to its slot.
      final day = parseIsoDateToEpochDay('2026-07-27')!;
      final slot = store.timetable.single;
      expect(
        store.recordForSlot(slot.id, day)!.status,
        AttendanceStatus.attended,
      );
    });

    test('migration is idempotent', () {
      final once = migrateToCurrent(legacyV1());
      final twice = migrateToCurrent(Map<String, dynamic>.from(once));
      expect(jsonEncode(twice), jsonEncode(once));
    });

    test('the original map is not mutated', () {
      final original = legacyV1();
      final before = jsonEncode(original);
      migrateToCurrent(original);
      expect(jsonEncode(original), before);
    });
  });

  group('refusing to go backwards', () {
    test('a file from a future release is rejected, not mangled', () {
      final future = {...legacyV1(), 'schemaVersion': kSchemaVersion + 5};
      expect(
        () => migrateToCurrent(future),
        throwsA(isA<SchemaTooNewException>()),
      );
    });

    test('the store loads read-only and never writes over it', () async {
      final dir = await Directory.systemTemp.createTemp('attendance-future');
      addTearDown(() => dir.delete(recursive: true));

      final futureDocument = {
        'schemaVersion': kSchemaVersion + 1,
        'courses': [
          {
            'id': 'c1',
            'code': 'ZZ999',
            'name': 'From the future',
            'somethingNew': 42,
          },
        ],
        'timetable': const <dynamic>[],
        'records': const <dynamic>[],
      };
      final file = File('${dir.path}/data.json');
      final written = jsonEncode(futureDocument);
      await file.writeAsString(written);

      final store = AttendanceStore(directory: dir);
      await store.load();

      expect(store.isReadOnly, isTrue);
      expect(store.lockedBy, isA<SchemaTooNewException>());

      // Any attempt to save must be a no-op — this is the whole point.
      store.saveCourse(code: 'NEW101', name: 'Should not persist');
      await store.flush();
      expect(await file.readAsString(), written);
    });
  });

  group('unknown fields survive an older app', () {
    test('a course keeps fields this version does not know about', () {
      final course = Course.fromJson({
        'id': 'c1',
        'code': 'EE301',
        'name': 'Power Electronics',
        'creditHours': 4,
        'instructor': {'name': 'Someone'},
      });
      expect(course.extra, isNotNull);

      final round = course.toJson();
      expect(round['creditHours'], 4);
      expect(round['instructor'], {'name': 'Someone'});
      expect(round['code'], 'EE301');
    });

    test('a slot and a record keep theirs too', () {
      final slot = TimetableClass.fromJson({
        'id': 's1',
        'courseId': 'c1',
        'weekday': 1,
        'startMinute': 600,
        'durationMinutes': 60,
        'room': 'AB3107',
      }).toJson();
      expect(slot['room'], 'AB3107');

      final record = AttendanceRecord.fromJson({
        'id': 'r1',
        'courseId': 'c1',
        'date': '2026-07-27',
        'status': 'attended',
        'durationMinutes': 60,
        'verifiedBy': 'qr',
      }).toJson();
      expect(record['verifiedBy'], 'qr');
    });

    test('a field this version owns is never shadowed by a stale copy', () {
      // A carried value must not win over the real one after an edit.
      final course = Course.fromJson({
        'id': 'c1',
        'code': 'EE301',
        'name': 'Old name',
        'extraThing': 1,
      });
      course.name = 'New name';
      expect(course.toJson()['name'], 'New name');
      expect(course.toJson()['extraThing'], 1);
    });

    test('a full round trip through an older app preserves the new field', () {
      // Simulates: new app writes -> old app opens, edits and saves -> new app
      // reads. The unknown field must still be there.
      final fromNewerApp = {
        'schemaVersion': kSchemaVersion,
        'courses': [
          {
            'id': 'c1',
            'code': 'EE301',
            'name': 'Power Electronics',
            'enrolled': true,
            'targetOverride': 85,
          },
        ],
        'timetable': const <dynamic>[],
        'records': const <dynamic>[],
      };

      final olderApp = AttendanceStore()..applySnapshot(fromNewerApp);
      olderApp.saveCourse(
        existing: olderApp.findCourseByCode('EE301'),
        code: 'EE301',
        name: 'Renamed',
      );
      final rewritten = olderApp.snapshot;

      final courses = rewritten['courses'] as List<dynamic>;
      final course = courses.single as Map<String, dynamic>;
      expect(course['name'], 'Renamed');
      expect(
        course['targetOverride'],
        85,
        reason: 'the older app must not drop what it did not understand',
      );
    });
  });

  group('sync across versions', () {
    test('a payload from a newer device is refused whole', () {
      final store = AttendanceStore()..loadSampleTimetable();
      final before = store.courses.length;
      expect(
        () => store.applySnapshot({
          'schemaVersion': kSchemaVersion + 2,
          'courses': [
            {'id': 'x', 'code': 'XX100', 'name': 'Newer'},
          ],
        }),
        throwsA(isA<SchemaTooNewException>()),
      );
      expect(
        store.courses.length,
        before,
        reason: 'a refused sync must leave the device untouched',
      );
    });

    test('a payload from an older device is migrated on the way in', () {
      final store = AttendanceStore()..loadSampleTimetable();
      store.applySnapshot(legacyV1());
      expect(store.findCourseByCode('EE323')!.electiveGroup, 'E2');
      expect(store.findCourseByCode('MA101'), isNull);
    });
  });
}
