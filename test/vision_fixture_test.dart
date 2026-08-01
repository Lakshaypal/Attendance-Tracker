import 'dart:convert';
import 'dart:io';

import 'package:attendance_tracker/src/scan/ocr_types.dart';
import 'package:attendance_tracker/src/scan/timetable_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// End-to-end check against output from a real text recogniser.
///
/// `test/fixtures/vision_timetable_words.json` was produced by rendering
/// `tool/ocr_fixture/timetable.html` to a PNG and running it through Apple's
/// Vision with the same request settings the macOS app uses (see
/// `tool/ocr_fixture/README.md`). The synthetic-geometry tests in
/// `timetable_parser_test.dart` prove the algorithm; this one proves it copes
/// with what an actual recogniser hands back — including the page title above
/// the grid and a genuine misread.
List<OcrWord> loadFixture() {
  final raw =
      jsonDecode(
            File(
              'test/fixtures/vision_timetable_words.json',
            ).readAsStringSync(),
          )
          as List<dynamic>;
  return [
    for (final entry in raw.cast<Map<String, dynamic>>())
      OcrWord(
        entry['text'] as String,
        TextBox(
          (entry['left'] as num).toDouble(),
          (entry['top'] as num).toDouble(),
          (entry['right'] as num).toDouble(),
          (entry['bottom'] as num).toDouble(),
        ),
      ),
  ];
}

ScannedSlot? slotAt(ScanResult result, int weekday, int startMinute) {
  for (final slot in result.slots) {
    if (slot.weekday == weekday && slot.startMinute == startMinute) return slot;
  }
  return null;
}

void main() {
  late ScanResult result;

  setUpAll(() => result = parseTimetable(loadFixture()));

  test('parses a photographed days-down-the-side timetable', () {
    expect(result.outcome, ScanOutcome.parsed);
    expect(result.daysAreColumns, isFalse);
    expect(result.slots, hasLength(17));
    // 16 of 17 cells yield a code; the seventeenth is a real misread.
    expect(result.codeCoverage, greaterThan(0.9));
  });

  test('recovers the printed start times and 55-minute periods', () {
    expect(slotAt(result, DateTime.monday, 9 * 60)!.code, 'EE301');
    expect(slotAt(result, DateTime.monday, 9 * 60)!.durationMinutes, 55);
    expect(slotAt(result, DateTime.tuesday, 9 * 60)!.code, 'EE305');
    expect(slotAt(result, DateTime.friday, 10 * 60)!.code, 'HU327');
  });

  test('reads an afternoon 2:00 heading as 2 pm, not 2 am', () {
    final tuesday = slotAt(result, DateTime.tuesday, 14 * 60);
    expect(tuesday, isNotNull);
    expect(tuesday!.code, 'EE303');
    expect(slotAt(result, DateTime.wednesday, 14 * 60)!.code, 'EE325');
  });

  test('folds a lab spanning two periods into one class', () {
    final mondayLab = slotAt(result, DateTime.monday, 10 * 60)!;
    expect(mondayLab.code, 'EE303');
    expect(mondayLab.label, 'Lab');
    // 10:00 through the end of the 11:00-11:55 period.
    expect(mondayLab.durationMinutes, 115);

    final thursdayLab = slotAt(result, DateTime.thursday, 10 * 60)!;
    expect(thursdayLab.code, 'EE301');
    expect(thursdayLab.durationMinutes, 115);
  });

  test('ignores the heading and room line above the grid', () {
    for (final slot in result.slots) {
      expect(slot.rawText, isNot(contains('Semester')));
      expect(slot.rawText, isNot(contains('Academic')));
      expect(slot.rawText, isNot(contains('2026')));
    }
    expect(
      result.warnings.any((warning) => warning.contains('outside the grid')),
      isTrue,
    );
  });

  test('surfaces a misread cell instead of guessing or dropping it', () {
    // Vision read Monday's "HU301" as "LOENH". The cell is still reported, in
    // the right place, with no code — the review screen asks the user.
    final misread = slotAt(result, DateTime.monday, 12 * 60)!;
    expect(misread.code, isEmpty);
    expect(misread.rawText, 'LOENH');
    expect(
      result.warnings.any(
        (warning) => warning.contains('no recognisable course code'),
      ),
      isTrue,
    );
  });

  group('unicode homoglyphs', () {
    test('the fixture contains a real Cyrillic lookalike', () {
      final hasCyrillic = loadFixture().any(
        (word) => word.text.codeUnits.any((unit) => unit == 0x0415),
      );
      expect(
        hasCyrillic,
        isTrue,
        reason: 'the fixture must keep the raw EЕ303 that motivated this',
      );
    });

    test('it still becomes a usable course code', () {
      expect(slotAt(result, DateTime.tuesday, 14 * 60)!.code, 'EE303');
    });

    test('normaliseOcrText maps lookalikes onto ASCII', () {
      expect(normaliseOcrText('EЕ303'), 'EE303');
      expect(normaliseOcrText('МON'), 'MON'); // Cyrillic Em
      expect(normaliseOcrText('ΗU301'), 'HU301'); // Greek Eta
      expect(normaliseOcrText('ＥＥ３０１'), 'EE301');
    });

    test('leaves ordinary text and genuine confusions alone', () {
      expect(normaliseOcrText('EE301 Lab'), 'EE301 Lab');
      expect(normaliseOcrText('9:00-9:55'), '9:00-9:55');
      // 0/O is a recognition error, not a homoglyph — correcting it would
      // corrupt codes that were read correctly.
      expect(normaliseOcrText('EE3O1'), 'EE3O1');
    });

    test('a day heading with a Cyrillic letter is still recognised', () {
      expect(weekdayFromLabel(normaliseOcrText('МON')), DateTime.monday);
      expect(weekdayFromLabel(normaliseOcrText('ТUE')), DateTime.tuesday);
    });
  });
}
