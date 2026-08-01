import 'package:attendance_tracker/src/models.dart';
import 'package:attendance_tracker/src/store.dart';
import 'package:attendance_tracker/src/sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sync address parsing', () {
    test('accepts a bare host and fills in the default port', () {
      final uri = LocalSyncClient.syncUri('192.168.1.24', '123456');
      expect(uri.host, '192.168.1.24');
      expect(uri.port, kPreferredSyncPort);
      expect(uri.path, '/sync');
      expect(uri.queryParameters['code'], '123456');
    });

    test('keeps an explicit port', () {
      expect(
        LocalSyncClient.syncUri('192.168.1.24:50000', '123456').port,
        50000,
      );
    });

    test('refuses input that would silently do the wrong thing', () {
      expect(
        () => LocalSyncClient.syncUri('', '123456'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => LocalSyncClient.syncUri('192.168.1.24', '12345'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => LocalSyncClient.syncUri('192.168.1.24', 'abcdef'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('local pairing', () {
    test('shares a snapshot only with the right code', () async {
      final source = AttendanceStore();
      source.saveCourse(code: 'EE301', name: 'Power Electronics');
      await LocalSyncHost.start(source);
      addTearDown(LocalSyncHost.stop);

      final address = '127.0.0.1:${LocalSyncHost.port}';
      final snapshot = await LocalSyncClient.receive(
        address: address,
        code: LocalSyncHost.pairCode!,
      );
      expect((snapshot['courses'] as List).single['code'], 'EE301');

      await expectLater(
        LocalSyncClient.receive(address: address, code: '000000'),
        throwsA(isA<Exception>()),
      );
    });

    test('a push replaces the host and survives the round trip', () async {
      final host = AttendanceStore();
      host.saveCourse(code: 'OLD100', name: 'Stale');
      await LocalSyncHost.start(host);
      addTearDown(LocalSyncHost.stop);

      final sender = AttendanceStore();
      final course = sender.saveCourse(code: 'EE303', name: 'Power Systems');
      final slot = sender.saveTimetableClass(
        courseId: course.id,
        weekday: DateTime.friday,
        startMinute: 600,
        durationMinutes: 90,
      );
      sender.markSlot(
        slot: slot,
        epochDay: sender.windowEnd,
        status: AttendanceStatus.massBunk,
      );

      await LocalSyncClient.send(
        address: '127.0.0.1:${LocalSyncHost.port}',
        code: LocalSyncHost.pairCode!,
        data: sender.snapshot,
      );

      expect(host.findCourseByCode('OLD100'), isNull);
      final received = host.findCourseByCode('EE303')!;
      expect(host.classesForCourse(received.id), hasLength(1));
      expect(host.statsFor(received.id).massBunked, 1);
    });

    test(
      'a malformed push is rejected and leaves the host untouched',
      () async {
        final host = AttendanceStore();
        host.saveCourse(code: 'KEEP99', name: 'Keep');
        await LocalSyncHost.start(host);
        addTearDown(LocalSyncHost.stop);

        await expectLater(
          LocalSyncClient.send(
            address: '127.0.0.1:${LocalSyncHost.port}',
            code: LocalSyncHost.pairCode!,
            data: const {'courses': <dynamic>[]},
          ),
          throwsA(isA<Exception>()),
        );
        expect(host.findCourseByCode('KEEP99'), isNotNull);
      },
    );
  });
}
