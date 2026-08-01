import 'package:attendance_tracker/src/civil_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('epoch day conversion', () {
    test('matches known anchors', () {
      expect(epochDayFromYmd(1970, 1, 1), 0);
      expect(epochDayFromYmd(1969, 12, 31), -1);
      expect(epochDayFromYmd(2000, 3, 1), 11017);
      expect(epochDayFromYmd(2026, 7, 30), 20664);
    });

    test('round-trips every day across a wide range', () {
      // Covers leap years, century rules, and the pre-epoch branch.
      for (var day = -20000; day <= 30000; day++) {
        final ymd = ymdFromEpochDay(day);
        expect(
          epochDayFromYmd(ymd.year, ymd.month, ymd.day),
          day,
          reason: 'failed at $day -> $ymd',
        );
      }
    });

    test('agrees with DateTime for a decade of dates', () {
      var probe = DateTime(2020, 1, 1);
      final end = DateTime(2030, 1, 1);
      while (probe.isBefore(end)) {
        final day = epochDayFromYmd(probe.year, probe.month, probe.day);
        expect(weekdayOfEpochDay(day), probe.weekday);
        final back = ymdFromEpochDay(day);
        expect(
          [back.year, back.month, back.day],
          [probe.year, probe.month, probe.day],
        );
        probe = probe.add(const Duration(days: 1));
      }
    });
  });

  group('weekdayOccurrences', () {
    test('matches a day-by-day count over many random ranges', () {
      final start = epochDayFromYmd(2026, 1, 1);
      for (var offset = 0; offset < 120; offset++) {
        for (var span = 0; span < 40; span++) {
          final first = start + offset;
          final last = first + span;
          for (var weekday = 1; weekday <= 7; weekday++) {
            var expected = 0;
            for (var day = first; day <= last; day++) {
              if (weekdayOfEpochDay(day) == weekday) expected++;
            }
            expect(
              weekdayOccurrences(first, last, weekday),
              expected,
              reason: 'weekday $weekday over $first..$last',
            );
          }
        }
      }
    });

    test('is zero for an inverted range', () {
      expect(weekdayOccurrences(100, 99, 3), 0);
    });
  });

  group('calendar helpers', () {
    test('daysInMonth handles leap rules', () {
      expect(daysInMonth(2024, 2), 29);
      expect(daysInMonth(2025, 2), 28);
      expect(daysInMonth(2000, 2), 29);
      expect(daysInMonth(1900, 2), 28);
    });

    test('addMonths clamps the day of month', () {
      final jan31 = epochDayFromYmd(2026, 1, 31);
      final feb = ymdFromEpochDay(addMonths(jan31, 1));
      expect([feb.year, feb.month, feb.day], [2026, 2, 28]);

      final dec = ymdFromEpochDay(addMonths(jan31, -1));
      expect([dec.year, dec.month, dec.day], [2025, 12, 31]);
    });

    test('addMonths crosses years in both directions', () {
      final base = epochDayFromYmd(2026, 7, 15);
      final forward = ymdFromEpochDay(addMonths(base, 18));
      expect([forward.year, forward.month], [2028, 1]);
      final backward = ymdFromEpochDay(addMonths(base, -19));
      expect([backward.year, backward.month], [2024, 12]);
    });

    test('startOfWeek always lands on a Monday', () {
      for (var day = 20000; day < 20100; day++) {
        expect(weekdayOfEpochDay(startOfWeek(day)), DateTime.monday);
        expect(startOfWeek(day), lessThanOrEqualTo(day));
      }
    });

    test('startOfMonth lands on the first', () {
      for (var day = 20000; day < 20400; day += 7) {
        expect(ymdFromEpochDay(startOfMonth(day)).day, 1);
      }
    });
  });

  group('formatting', () {
    test('iso strings round-trip', () {
      final day = epochDayFromYmd(2026, 7, 5);
      expect(isoDateString(day), '2026-07-05');
      expect(parseIsoDateToEpochDay('2026-07-05'), day);
      expect(parseIsoDateToEpochDay('2026-07-05T10:00:00Z'), day);
    });

    test('rejects impossible dates instead of throwing', () {
      expect(parseIsoDateToEpochDay('2026-13-01'), isNull);
      expect(parseIsoDateToEpochDay('2026-02-30'), isNull);
      expect(parseIsoDateToEpochDay('nonsense'), isNull);
      expect(parseIsoDateToEpochDay(null), isNull);
      expect(parseIsoDateToEpochDay(''), isNull);
    });

    test('renders times the way a student reads them', () {
      expect(formatMinuteOfDay(0), '12:00 AM');
      expect(formatMinuteOfDay(9 * 60 + 5), '9:05 AM');
      expect(formatMinuteOfDay(12 * 60), '12:00 PM');
      expect(formatMinuteOfDay(13 * 60 + 30), '1:30 PM');
      expect(formatMinuteCompact(16 * 60), '4pm');
      expect(formatTimeRange(10 * 60, 90), '10am–11:30am');
    });
  });
}
