import 'package:attendance_tracker/src/scan/ocr_types.dart';
import 'package:attendance_tracker/src/scan/timetable_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds the word boxes a camera would produce for a printed grid.
///
/// Text always runs horizontally, exactly as it does on a real page — the two
/// layouts differ only in which axis carries the days.
class _Sheet {
  _Sheet({
    required this.days,
    required this.times,
    required this.cells,
    this.daysAcrossTop = true,
  });

  /// Day headings, in order.
  final List<String> days;

  /// Time headings, in order.
  final List<String> times;

  /// `cells[timeIndex][dayIndex]` — null for a free period.
  final List<List<String?>> cells;

  final bool daysAcrossTop;

  static const double _gridLeft = 0.15;
  static const double _gridRight = 0.95;
  static const double _gridTop = 0.12;
  static const double _gridBottom = 0.92;
  static const double _gutterX = 0.07;
  static const double _headerY = 0.06;
  static const double _textHeight = 0.026;

  int get _columns => daysAcrossTop ? days.length : times.length;
  int get _rows => daysAcrossTop ? times.length : days.length;

  double _columnCentre(int index) =>
      _gridLeft + (_gridRight - _gridLeft) * (index + 0.5) / _columns;
  double _rowCentre(int index) =>
      _gridTop + (_gridBottom - _gridTop) * (index + 0.5) / _rows;

  /// Lays a string out as separate words with a realistic inter-word gap, so
  /// the parser's phrase merging is exercised rather than bypassed.
  List<OcrWord> _words(String text, double centreX, double centreY) {
    final parts = text.split(' ').where((part) => part.isNotEmpty).toList();
    const charWidth = 0.008;
    const gap = 0.004;
    final total =
        parts.fold<double>(0, (sum, part) => sum + part.length * charWidth) +
        gap * (parts.length - 1);
    var cursor = centreX - total / 2;
    final out = <OcrWord>[];
    for (final part in parts) {
      final width = part.length * charWidth;
      out.add(
        OcrWord(
          part,
          TextBox(
            cursor,
            centreY - _textHeight / 2,
            cursor + width,
            centreY + _textHeight / 2,
          ),
        ),
      );
      cursor += width + gap;
    }
    return out;
  }

  List<OcrWord> build() {
    final words = <OcrWord>[];

    for (var i = 0; i < days.length; i++) {
      words.addAll(
        daysAcrossTop
            ? _words(days[i], _columnCentre(i), _headerY)
            : _words(days[i], _gutterX, _rowCentre(i)),
      );
    }
    for (var i = 0; i < times.length; i++) {
      words.addAll(
        daysAcrossTop
            ? _words(times[i], _gutterX, _rowCentre(i))
            : _words(times[i], _columnCentre(i), _headerY),
      );
    }
    for (var time = 0; time < times.length; time++) {
      for (var day = 0; day < days.length; day++) {
        final text = cells[time][day];
        if (text == null) continue;
        words.addAll(
          daysAcrossTop
              ? _words(text, _columnCentre(day), _rowCentre(time))
              : _words(text, _columnCentre(time), _rowCentre(day)),
        );
      }
    }
    return words;
  }
}

ScannedSlot? slotOn(ScanResult result, int weekday, int startMinute) {
  for (final slot in result.slots) {
    if (slot.weekday == weekday && slot.startMinute == startMinute) return slot;
  }
  return null;
}

void main() {
  group('day headings', () {
    test('accepts the usual spellings', () {
      expect(weekdayFromLabel('Mon'), DateTime.monday);
      expect(weekdayFromLabel('MONDAY'), DateTime.monday);
      expect(weekdayFromLabel('tue'), DateTime.tuesday);
      expect(weekdayFromLabel('Thurs'), DateTime.thursday);
      expect(weekdayFromLabel('TH'), DateTime.thursday);
      expect(weekdayFromLabel('Sat.'), DateTime.saturday);
    });

    test('does not mistake ordinary words for days', () {
      expect(weekdayFromLabel('Monitor'), isNull);
      expect(weekdayFromLabel('Satellite'), isNull);
      expect(weekdayFromLabel('Sunlight'), isNull);
      expect(weekdayFromLabel('EE301'), isNull);
      expect(weekdayFromLabel(''), isNull);
    });
  });

  group('time headings', () {
    test('reads the common printed formats', () {
      expect(parseTimeLabel('9:00')!.startMinute, 540);
      expect(parseTimeLabel('09.30')!.startMinute, 570);
      expect(parseTimeLabel('9 AM')!.startMinute, 540);
      expect(parseTimeLabel('2 PM')!.startMinute, 840);
      expect(parseTimeLabel('12:00')!.startMinute, 720);
      expect(parseTimeLabel('12 AM')!.startMinute, 0);
    });

    test('reads ranges and keeps the end time', () {
      final parsed = parseTimeLabel('9:00-10:00')!;
      expect(parsed.startMinute, 540);
      expect(parsed.endMinute, 600);

      final dashed = parseTimeLabel('10.00 – 11.55')!;
      expect(dashed.startMinute, 600);
      expect(dashed.endMinute, 715);
    });

    test('rolls an end time past noon', () {
      final parsed = parseTimeLabel('11-1')!;
      expect(parsed.startMinute, 660);
      expect(parsed.endMinute, 780);
    });

    test('rejects text that is not a time', () {
      expect(parseTimeLabel('EE301'), isNull);
      expect(parseTimeLabel('Lunch'), isNull);
      expect(parseTimeLabel('25:00'), isNull);
      expect(parseTimeLabel('9:75'), isNull);
      expect(parseTimeLabel(''), isNull);
    });
  });

  group('course codes', () {
    test('pulls the code out of messy cell text', () {
      expect(extractCourseCode('EE301'), 'EE301');
      expect(extractCourseCode('EE 301 Lab'), 'EE301');
      expect(extractCourseCode('ee-301'), 'EE301');
      expect(extractCourseCode('Lab EE301 room 12'), 'EE301');
      expect(extractCourseCode('HU327'), 'HU327');
    });

    test('returns empty when there is no code', () {
      expect(extractCourseCode('Lunch break'), '');
      expect(extractCourseCode(''), '');
    });
  });

  group('full grids', () {
    test('reads a days-across-the-top timetable', () {
      final result = parseTimetable(
        _Sheet(
          days: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
          times: const ['9:00', '10:00', '11:00', '12:00'],
          cells: const [
            ['EE301', null, 'EE305', 'EE301', null],
            ['EE303 Lab', 'EE301', null, 'HU301', 'EE305'],
            [null, 'EE303', 'EE305', null, null],
            ['HU301', null, null, 'EE323', 'EE323'],
          ],
        ).build(),
      );

      expect(result.outcome, ScanOutcome.parsed);
      expect(result.daysAreColumns, isTrue);
      expect(result.slots, hasLength(12)); // one per filled cell

      final monday9 = slotOn(result, DateTime.monday, 540)!;
      expect(monday9.code, 'EE301');
      expect(monday9.durationMinutes, 60);

      final monday10 = slotOn(result, DateTime.monday, 600)!;
      expect(monday10.code, 'EE303');
      expect(monday10.label, 'Lab');

      expect(slotOn(result, DateTime.friday, 720)!.code, 'EE323');
      expect(slotOn(result, DateTime.tuesday, 540), isNull);
      expect(result.codeCoverage, 1.0);
    });

    test('reads a days-down-the-side timetable', () {
      final result = parseTimetable(
        _Sheet(
          daysAcrossTop: false,
          days: const ['Monday', 'Tuesday', 'Wednesday'],
          times: const ['9:00', '10:00', '11:00', '12:00'],
          cells: const [
            // cells[timeIndex][dayIndex]
            ['EE301', 'EE303', null],
            ['HU301', null, 'EE305'],
            [null, 'EE323', 'EE323'],
            ['EE305', 'EE301', 'HU301'],
          ],
        ).build(),
      );

      expect(result.outcome, ScanOutcome.parsed);
      expect(result.daysAreColumns, isFalse);
      expect(slotOn(result, DateTime.monday, 540)!.code, 'EE301');
      expect(slotOn(result, DateTime.wednesday, 600)!.code, 'EE305');
      expect(slotOn(result, DateTime.tuesday, 720)!.code, 'EE301');
    });

    test('folds a repeated code into one longer class', () {
      final result = parseTimetable(
        _Sheet(
          days: const ['Mon', 'Tue'],
          times: const ['9:00', '10:00', '11:00'],
          cells: const [
            ['EE301 Lab', 'HU301'],
            ['EE301 Lab', 'EE303'],
            ['EE305', 'EE303'],
          ],
        ).build(),
      );

      final lab = slotOn(result, DateTime.monday, 540)!;
      expect(lab.code, 'EE301');
      expect(
        lab.durationMinutes,
        120,
        reason: 'the two-row lab becomes a single two-hour class',
      );
      expect(slotOn(result, DateTime.monday, 660)!.code, 'EE305');

      final tuesday = slotOn(result, DateTime.tuesday, 600)!;
      expect(tuesday.code, 'EE303');
      expect(tuesday.durationMinutes, 120);
    });

    test('reads explicit time ranges and honours the printed end time', () {
      final result = parseTimetable(
        _Sheet(
          days: const ['Mon', 'Tue'],
          times: const ['9:00-9:55', '10:00-10:55'],
          cells: const [
            ['EE301', 'EE303'],
            ['EE305', 'HU301'],
          ],
        ).build(),
      );
      final first = slotOn(result, DateTime.monday, 540)!;
      expect(first.durationMinutes, 55);
    });

    test('turns afternoon 1, 2, 3 headings into 1 pm, 2 pm, 3 pm', () {
      final result = parseTimetable(
        _Sheet(
          days: const ['Mon', 'Tue'],
          times: const ['11:00', '12:00', '1:00', '2:00'],
          cells: const [
            ['EE301', null],
            [null, 'EE303'],
            ['EE305', null],
            [null, 'HU301'],
          ],
        ).build(),
      );
      expect(slotOn(result, DateTime.monday, 13 * 60)!.code, 'EE305');
      expect(slotOn(result, DateTime.tuesday, 14 * 60)!.code, 'HU301');
    });

    test('treats a 1..n heading run as period numbers', () {
      final result = parseTimetable(
        _Sheet(
          days: const ['Mon', 'Tue'],
          times: const ['1', '2', '3', '4'],
          cells: const [
            ['EE301', null],
            ['EE303', 'EE305'],
            [null, 'HU301'],
            ['EE323', null],
          ],
        ).build(),
      );
      // Periods are laid out as hour-long slots from 9 am.
      expect(slotOn(result, DateTime.monday, 9 * 60)!.code, 'EE301');
      expect(slotOn(result, DateTime.tuesday, 10 * 60)!.code, 'EE305');
      expect(slotOn(result, DateTime.monday, 12 * 60)!.code, 'EE323');
    });

    test('keeps cells that have no readable code, flagged for the user', () {
      final result = parseTimetable(
        _Sheet(
          days: const ['Mon', 'Tue'],
          times: const ['9:00', '10:00'],
          cells: const [
            ['EE301', 'Library'],
            ['Sports', 'EE303'],
          ],
        ).build(),
      );
      expect(result.outcome, ScanOutcome.parsed);
      expect(result.slots, hasLength(4));
      expect(result.codeCoverage, 0.5);
      expect(
        result.warnings.any((warning) => warning.contains('no recognisable')),
        isTrue,
      );
      final library = slotOn(result, DateTime.tuesday, 540)!;
      expect(library.code, isEmpty);
      expect(library.rawText, 'Library');
    });
  });

  group('failure is reported, never guessed', () {
    test('an almost blank photo', () {
      expect(
        parseTimetable(const [
          OcrWord('a', TextBox(0.1, 0.1, 0.2, 0.2)),
        ]).outcome,
        ScanOutcome.unrecognised,
      );
    });

    test('a page with no day headings', () {
      final result = parseTimetable(
        _Sheet(
          days: const ['Alpha', 'Beta', 'Gamma'],
          times: const ['9:00', '10:00'],
          cells: const [
            ['EE301', 'EE303', 'EE305'],
            ['EE305', 'HU301', 'EE301'],
          ],
        ).build(),
      );
      expect(result.outcome, ScanOutcome.unrecognised);
      expect(result.warnings.single, contains('day headings'));
      expect(result.slots, isEmpty);
    });

    test('a page with days but no times', () {
      final result = parseTimetable(
        _Sheet(
          days: const ['Mon', 'Tue', 'Wed'],
          times: const ['First', 'Second'],
          cells: const [
            ['EE301', 'EE303', 'EE305'],
            ['EE305', 'HU301', 'EE301'],
          ],
        ).build(),
      );
      expect(result.outcome, ScanOutcome.unrecognised);
      expect(result.warnings.single, contains('class times'));
    });

    test('an empty word list', () {
      expect(parseTimetable(const []).outcome, ScanOutcome.unrecognised);
    });
  });
}
