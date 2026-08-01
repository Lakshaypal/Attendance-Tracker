import 'dart:math' as math;

import 'ocr_types.dart';

/// One class recovered from a photographed timetable.
class ScannedSlot {
  ScannedSlot({
    required this.code,
    required this.label,
    required this.weekday,
    required this.startMinute,
    required this.durationMinutes,
    required this.rawText,
  });

  /// Normalised course code (`EE301`), or empty when the cell held no code.
  final String code;

  /// Whatever else was in the cell — lab name, room number.
  final String? label;

  final int weekday;
  final int startMinute;
  final int durationMinutes;

  /// The untouched cell text, shown in the review screen so the user can see
  /// what the camera actually read.
  final String rawText;

  int get endMinute => startMinute + durationMinutes;
}

enum ScanOutcome {
  /// Both axes were found; [ScanResult.slots] is worth reviewing.
  parsed,

  /// The photo was read but its structure was not recognisable.
  unrecognised,
}

class ScanResult {
  const ScanResult({
    required this.outcome,
    required this.slots,
    required this.warnings,
    required this.daysAreColumns,
    required this.wordCount,
  });

  final ScanOutcome outcome;
  final List<ScannedSlot> slots;
  final List<String> warnings;

  /// True when the photo had days across the top, false when days ran down the
  /// side. Both layouts are supported.
  final bool daysAreColumns;
  final int wordCount;

  bool get isUsable => outcome == ScanOutcome.parsed && slots.isNotEmpty;

  /// Share of recovered cells that yielded a recognisable course code.
  double get codeCoverage {
    if (slots.isEmpty) return 0;
    final coded = slots.where((slot) => slot.code.isNotEmpty).length;
    return coded / slots.length;
  }

  static ScanResult failure(String reason, {int wordCount = 0}) => ScanResult(
    outcome: ScanOutcome.unrecognised,
    slots: const [],
    warnings: [reason],
    daysAreColumns: true,
    wordCount: wordCount,
  );
}

/// A run of words that sit next to each other on one printed line.
class _Phrase {
  _Phrase(this.text, this.box, this.line);
  final String text;
  final TextBox box;
  final int line;
}

class _Band {
  _Band(this.lo, this.hi, this.centre);
  double lo;
  double hi;
  final double centre;
  bool contains(double value) => value >= lo && value <= hi;
}

class _DayBand extends _Band {
  _DayBand(super.lo, super.hi, super.centre, this.weekday);
  final int weekday;
}

class _TimeBand extends _Band {
  _TimeBand(super.lo, super.hi, super.centre, this.startMinute, this.endMinute);
  int startMinute;
  int endMinute;
  int get duration => endMinute - startMinute;
}

/// Rebuilds a weekly timetable from the words a photo produced.
///
/// The approach is purely geometric, which is what makes it survive real
/// photographs: it never assumes a reading order, only that the day labels lie
/// along one axis and the time labels along the other. Both a days-across-the-
/// top and a days-down-the-side layout parse the same way.
///
/// The pass is O(W log W) in the number of words, dominated by the sorts.
ScanResult parseTimetable(List<OcrWord> words) {
  // Normalise first, at the one choke point. Text recognisers really do return
  // Cyrillic and Greek lookalikes for Latin letters, and a single stray
  // homoglyph is enough to lose a course code or a day heading.
  final usable = <OcrWord>[
    for (final word in words)
      if (word.text.trim().isNotEmpty)
        OcrWord(normaliseOcrText(word.text), word.box),
  ];
  if (usable.length < 4) {
    return ScanResult.failure(
      'Almost no text was found in that photo. Try a straighter, brighter '
      'shot that fills the frame.',
      wordCount: usable.length,
    );
  }

  final phrases = _buildPhrases(usable);
  final warnings = <String>[];

  // ------------------------------------------------------------ day labels
  final dayPhrases = <_Phrase, int>{};
  for (final phrase in phrases) {
    final weekday = weekdayFromLabel(phrase.text);
    if (weekday != null) dayPhrases[phrase] = weekday;
  }
  if (dayPhrases.length < 2) {
    return ScanResult.failure(
      'No day headings (Mon, Tue, …) were found, so the grid could not be '
      'laid out.',
      wordCount: usable.length,
    );
  }

  // Days run along whichever axis their labels are more spread out on.
  final dayBoxes = dayPhrases.keys.map((phrase) => phrase.box).toList();
  final spreadX = _spread(dayBoxes.map((box) => box.centerX));
  final spreadY = _spread(dayBoxes.map((box) => box.centerY));
  final daysAreColumns = spreadX >= spreadY;

  double dayPos(TextBox box) => daysAreColumns ? box.centerX : box.centerY;
  double dayLo(TextBox box) => daysAreColumns ? box.left : box.top;
  double dayHi(TextBox box) => daysAreColumns ? box.right : box.bottom;
  double timePos(TextBox box) => daysAreColumns ? box.centerY : box.centerX;
  double timeLo(TextBox box) => daysAreColumns ? box.top : box.left;
  double timeHi(TextBox box) => daysAreColumns ? box.bottom : box.right;

  // One band per weekday. Duplicate labels (a heading repeated in two rows)
  // collapse into the outermost extent.
  final dayExtents = <int, ({double lo, double hi})>{};
  for (final entry in dayPhrases.entries) {
    final lo = dayLo(entry.key.box);
    final hi = dayHi(entry.key.box);
    final existing = dayExtents[entry.value];
    dayExtents[entry.value] = existing == null
        ? (lo: lo, hi: hi)
        : (lo: math.min(existing.lo, lo), hi: math.max(existing.hi, hi));
  }
  final orderedDays = dayExtents.entries.toList()
    ..sort((a, b) => a.value.lo.compareTo(b.value.lo));
  final dayBands = <_DayBand>[
    for (final entry in orderedDays)
      _DayBand(
        entry.value.lo,
        entry.value.hi,
        (entry.value.lo + entry.value.hi) / 2,
        entry.key,
      ),
  ];
  _expandBands(dayBands);

  // ----------------------------------------------------------- time labels
  final timeCandidates = <({_Phrase phrase, ParsedTime time})>[];
  for (final phrase in phrases) {
    if (dayPhrases.containsKey(phrase)) continue;
    final time = parseTimeLabel(phrase.text);
    if (time != null) timeCandidates.add((phrase: phrase, time: time));
  }

  final timeBands = _buildTimeBands(
    timeCandidates,
    timePos: (box) => timePos(box),
    timeLo: (box) => timeLo(box),
    timeHi: (box) => timeHi(box),
  );
  if (timeBands.isEmpty) {
    return ScanResult.failure(
      'Day headings were found but no class times were, so the rows could not '
      'be placed. Make sure the time column or header is in the photo.',
      wordCount: usable.length,
    );
  }
  if (timeBands.length < 2) {
    warnings.add(
      'Only one time slot was readable, so most of the grid may be missing.',
    );
  }

  // --------------------------------------------------------- cell contents
  final timeLabelPhrases = timeCandidates
      .map((candidate) => candidate.phrase)
      .toSet();
  final cells = <int, Map<int, List<_Phrase>>>{};
  var unplaced = 0;
  for (final phrase in phrases) {
    if (dayPhrases.containsKey(phrase)) continue;
    if (timeLabelPhrases.contains(phrase)) continue;
    final dayIndex = _bandIndexFor(dayBands, dayPos(phrase.box));
    final timeIndex = _bandIndexFor(timeBands, timePos(phrase.box));
    if (dayIndex < 0 || timeIndex < 0) {
      unplaced++;
      continue;
    }
    ((cells[dayIndex] ??= {})[timeIndex] ??= <_Phrase>[]).add(phrase);
  }
  if (unplaced > 0) {
    warnings.add(
      '$unplaced piece${unplaced == 1 ? '' : 's'} of text fell outside the '
      'grid and ${unplaced == 1 ? 'was' : 'were'} ignored.',
    );
  }
  if (cells.isEmpty) {
    return ScanResult.failure(
      'The grid lines were found but every cell came out empty.',
      wordCount: usable.length,
    );
  }

  // ------------------------------------------- cell text, codes, and spans
  final slots = <ScannedSlot>[];
  for (var dayIndex = 0; dayIndex < dayBands.length; dayIndex++) {
    final dayCells = cells[dayIndex];
    if (dayCells == null) continue;
    final weekday = dayBands[dayIndex].weekday;
    final indices = dayCells.keys.toList()..sort();

    var cursor = 0;
    while (cursor < indices.length) {
      final startIndex = indices[cursor];
      final text = _cellText(dayCells[startIndex]!);
      final code = extractCourseCode(text);

      // A two-hour lab prints its code once per slot it covers; fold the
      // contiguous repeats into one longer class.
      var endIndex = startIndex;
      var lookahead = cursor + 1;
      while (lookahead < indices.length && indices[lookahead] == endIndex + 1) {
        final nextText = _cellText(dayCells[indices[lookahead]]!);
        final nextCode = extractCourseCode(nextText);
        final sameCell = code.isNotEmpty
            ? nextCode == code
            : _squash(nextText) == _squash(text);
        if (!sameCell) break;
        endIndex = indices[lookahead];
        lookahead++;
      }

      final start = timeBands[startIndex].startMinute;
      final end = timeBands[endIndex].endMinute;
      slots.add(
        ScannedSlot(
          code: code,
          label: _labelFrom(text, code),
          weekday: weekday,
          startMinute: start,
          durationMinutes: math.max(5, end - start),
          rawText: text,
        ),
      );
      cursor = lookahead;
    }
  }

  if (slots.isEmpty) {
    return ScanResult.failure(
      'No classes could be read out of the grid.',
      wordCount: usable.length,
    );
  }

  final uncoded = slots.where((slot) => slot.code.isEmpty).length;
  if (uncoded > 0) {
    warnings.add(
      '$uncoded cell${uncoded == 1 ? '' : 's'} had no recognisable course '
      'code — pick the course by hand below.',
    );
  }

  slots.sort((a, b) {
    final byDay = a.weekday.compareTo(b.weekday);
    return byDay != 0 ? byDay : a.startMinute.compareTo(b.startMinute);
  });

  return ScanResult(
    outcome: ScanOutcome.parsed,
    slots: slots,
    warnings: warnings,
    daysAreColumns: daysAreColumns,
    wordCount: usable.length,
  );
}

// --------------------------------------------------------------- phrasing
/// Groups words into printed lines, then joins neighbours that are close
/// enough to belong to the same cell. `EE` + `301` becomes `EE 301`, while two
/// separate columns stay apart.
List<_Phrase> _buildPhrases(List<OcrWord> words) {
  final sorted = [...words]
    ..sort((a, b) => a.box.centerY.compareTo(b.box.centerY));

  final lines = <List<OcrWord>>[];
  for (final word in sorted) {
    var placed = false;
    // Only the most recent lines can still match, because input is sorted by
    // vertical position.
    for (var i = lines.length - 1; i >= 0 && i >= lines.length - 3; i--) {
      final last = lines[i].last;
      if (word.box.verticalOverlap(last.box) >= 0.5) {
        lines[i].add(word);
        placed = true;
        break;
      }
    }
    if (!placed) lines.add([word]);
  }

  final phrases = <_Phrase>[];
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex]
      ..sort((a, b) => a.box.left.compareTo(b.box.left));
    var text = StringBuffer(line.first.text);
    var box = line.first.box;
    for (var i = 1; i < line.length; i++) {
      final word = line[i];
      final gap = word.box.left - box.right;
      final reference = math.min(box.height, word.box.height);
      if (gap <= reference * 0.9) {
        text.write(' ');
        text.write(word.text);
        box = box.merge(word.box);
      } else {
        phrases.add(_Phrase(text.toString(), box, lineIndex));
        text = StringBuffer(word.text);
        box = word.box;
      }
    }
    phrases.add(_Phrase(text.toString(), box, lineIndex));
  }
  return phrases;
}

// ------------------------------------------------------------------ bands
double _spread(Iterable<double> values) {
  var lowest = double.infinity;
  var highest = -double.infinity;
  for (final value in values) {
    if (value < lowest) lowest = value;
    if (value > highest) highest = value;
  }
  return highest - lowest;
}

/// Grows label extents outward until they meet, so a band covers the whole
/// column or row rather than just the width of its heading.
void _expandBands(List<_Band> bands) {
  if (bands.isEmpty) return;
  if (bands.length == 1) {
    bands.first
      ..lo = 0
      ..hi = 1;
    return;
  }
  final pitch = (bands.last.centre - bands.first.centre) / (bands.length - 1);
  for (var i = 0; i < bands.length; i++) {
    final lower = i == 0
        ? bands[i].centre - pitch / 2
        : (bands[i - 1].hi + bands[i].lo) / 2;
    final upper = i == bands.length - 1
        ? bands[i].centre + pitch / 2
        : (bands[i].hi + bands[i + 1].lo) / 2;
    bands[i]
      ..lo = math.max(0, math.min(lower, bands[i].lo))
      ..hi = math.min(1, math.max(upper, bands[i].hi));
  }
}

int _bandIndexFor(List<_Band> bands, double value) {
  for (var i = 0; i < bands.length; i++) {
    if (bands[i].contains(value)) return i;
  }
  // Fall back to the nearest band when a cell overhangs its column slightly.
  var best = -1;
  var bestDistance = double.infinity;
  for (var i = 0; i < bands.length; i++) {
    final distance = value < bands[i].lo
        ? bands[i].lo - value
        : value - bands[i].hi;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = i;
    }
  }
  final tolerance = bands.length > 1
      ? (bands.last.centre - bands.first.centre) / (bands.length - 1) * 0.35
      : 0.1;
  return bestDistance <= tolerance ? best : -1;
}

List<_TimeBand> _buildTimeBands(
  List<({_Phrase phrase, ParsedTime time})> candidates, {
  required double Function(TextBox) timePos,
  required double Function(TextBox) timeLo,
  required double Function(TextBox) timeHi,
}) {
  if (candidates.isEmpty) return const [];
  final sorted = [...candidates]
    ..sort((a, b) => timePos(a.phrase.box).compareTo(timePos(b.phrase.box)));

  final extents =
      sorted
          .map((entry) => timeHi(entry.phrase.box) - timeLo(entry.phrase.box))
          .toList()
        ..sort();
  final medianExtent = extents[extents.length ~/ 2];
  final tolerance = math.max(medianExtent * 0.6, 0.005);

  // Cluster labels that describe the same row (or column).
  final clusters = <List<({_Phrase phrase, ParsedTime time})>>[];
  for (final entry in sorted) {
    if (clusters.isEmpty ||
        timePos(entry.phrase.box) - timePos(clusters.last.last.phrase.box) >
            tolerance) {
      clusters.add([entry]);
    } else {
      clusters.last.add(entry);
    }
  }

  // Period numbers (1, 2, 3 …) are not clock times. Detect the run and lay it
  // out as hour-long periods from 9 am instead.
  final firstTimes = clusters
      .map((cluster) => cluster.first.time)
      .toList(growable: false);
  final looksLikePeriods =
      firstTimes.length >= 3 &&
      firstTimes.every(
        (time) => time.isBareNumber && time.startMinute <= 12 * 60,
      ) &&
      firstTimes.first.startMinute == 60 &&
      _isConsecutive(firstTimes.map((time) => time.startMinute ~/ 60));

  final bands = <_TimeBand>[];
  for (var i = 0; i < clusters.length; i++) {
    final cluster = clusters[i];
    var lo = double.infinity;
    var hi = -double.infinity;
    for (final entry in cluster) {
      lo = math.min(lo, timeLo(entry.phrase.box));
      hi = math.max(hi, timeHi(entry.phrase.box));
    }
    final time = cluster.first.time;
    final start = looksLikePeriods ? 9 * 60 + i * 60 : time.startMinute;
    final end = looksLikePeriods ? start + 60 : (time.endMinute ?? start + 60);
    bands.add(_TimeBand(lo, hi, (lo + hi) / 2, start, end));
  }

  if (!looksLikePeriods) {
    _makeMonotonic(bands);
    _fillDurations(bands);
  }
  _expandBands(bands);
  return bands;
}

bool _isConsecutive(Iterable<int> values) {
  int? previous;
  for (final value in values) {
    if (previous != null && value != previous + 1) return false;
    previous = value;
  }
  return true;
}

/// Timetables routinely print afternoon slots as 1, 2, 3. Once the rows are in
/// positional order, any step backwards that a 12-hour shift would fix is one.
void _makeMonotonic(List<_TimeBand> bands) {
  for (var i = 1; i < bands.length; i++) {
    while (bands[i].startMinute < bands[i - 1].startMinute &&
        bands[i].startMinute + 12 * 60 < 24 * 60) {
      bands[i].startMinute += 12 * 60;
      bands[i].endMinute += 12 * 60;
    }
  }
}

/// A row whose label gave no end time ends where the next row begins.
void _fillDurations(List<_TimeBand> bands) {
  final explicit = <int>[];
  for (final band in bands) {
    if (band.duration > 0 && band.duration <= 240) explicit.add(band.duration);
  }
  explicit.sort();
  final fallback = explicit.isEmpty ? 60 : explicit[explicit.length ~/ 2];
  for (var i = 0; i < bands.length; i++) {
    final band = bands[i];
    final nextStart = i + 1 < bands.length ? bands[i + 1].startMinute : null;
    if (band.duration <= 0 || band.duration > 240) {
      band.endMinute = band.startMinute + fallback;
    }
    if (nextStart != null && band.endMinute > nextStart) {
      band.endMinute = nextStart;
    }
    if (band.endMinute <= band.startMinute) {
      band.endMinute = band.startMinute + math.max(5, fallback);
    }
  }
}

// ------------------------------------------------------------- cell text
String _cellText(List<_Phrase> phrases) {
  final ordered = [...phrases]
    ..sort((a, b) {
      final byLine = a.line.compareTo(b.line);
      return byLine != 0 ? byLine : a.box.left.compareTo(b.box.left);
    });
  return ordered.map((phrase) => phrase.text.trim()).join(' ').trim();
}

String _squash(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

String? _labelFrom(String text, String code) {
  if (code.isEmpty) return null;
  // Remove the code (however it was spaced) and keep whatever describes the
  // class — "Lab", a room number, an elective marker.
  final stripped = text.replaceAll(_codePattern, ' ');
  final cleaned = stripped.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return null;
  return cleaned.length > 40 ? cleaned.substring(0, 40).trim() : cleaned;
}

// ------------------------------------------------------------ day labels
const Map<String, int> _dayWords = {
  'MON': DateTime.monday,
  'MO': DateTime.monday,
  'MONDAY': DateTime.monday,
  'TUE': DateTime.tuesday,
  'TU': DateTime.tuesday,
  'TUES': DateTime.tuesday,
  'TUESDAY': DateTime.tuesday,
  'WED': DateTime.wednesday,
  'WE': DateTime.wednesday,
  'WEDS': DateTime.wednesday,
  'WEDNESDAY': DateTime.wednesday,
  'THU': DateTime.thursday,
  'TH': DateTime.thursday,
  'THUR': DateTime.thursday,
  'THURS': DateTime.thursday,
  'THURSDAY': DateTime.thursday,
  'FRI': DateTime.friday,
  'FR': DateTime.friday,
  'FRIDAY': DateTime.friday,
  'SAT': DateTime.saturday,
  'SA': DateTime.saturday,
  'SATURDAY': DateTime.saturday,
  'SUN': DateTime.sunday,
  'SU': DateTime.sunday,
  'SUNDAY': DateTime.sunday,
};

/// Matches a heading against a whitelist of spellings, so `MONITOR` or
/// `SATELLITE` never become days.
int? weekdayFromLabel(String text) {
  final letters = text.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
  if (letters.isEmpty || letters.length > 9) return null;
  return _dayWords[letters];
}

// ------------------------------------------------------------ time labels
class ParsedTime {
  const ParsedTime(
    this.startMinute,
    this.endMinute, {
    this.isBareNumber = false,
  });
  final int startMinute;
  final int? endMinute;

  /// True for a label like `10` that carries no colon and no am/pm, which may
  /// turn out to be a period number rather than a clock time.
  final bool isBareNumber;
}

final RegExp _rangePattern = RegExp(
  r'^(\d{1,2})(?:[:.](\d{2}))?\s*([AP]\.?M\.?)?\s*(?:-|–|—|TO)\s*'
  r'(\d{1,2})(?:[:.](\d{2}))?\s*([AP]\.?M\.?)?$',
  caseSensitive: false,
);

final RegExp _singlePattern = RegExp(
  r'^(\d{1,2})(?:[:.](\d{2}))?\s*([AP]\.?M\.?)?$',
  caseSensitive: false,
);

/// Understands `9`, `9:00`, `09.30`, `9 AM`, `9:00-10:00`, `1–2 PM`.
ParsedTime? parseTimeLabel(String text) {
  final cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.isEmpty || cleaned.length > 20) return null;

  final range = _rangePattern.firstMatch(cleaned);
  if (range != null) {
    final endMeridiem = range.group(6);
    final start = _toMinutes(
      range.group(1)!,
      range.group(2),
      range.group(3) ?? endMeridiem,
    );
    final end = _toMinutes(range.group(4)!, range.group(5), endMeridiem);
    if (start == null || end == null) return null;
    // `11:00-12:00` is fine; `11-1` means the end rolled past noon.
    final adjustedEnd = end <= start ? end + 12 * 60 : end;
    if (adjustedEnd - start > 300) return ParsedTime(start, null);
    return ParsedTime(
      start,
      adjustedEnd,
      isBareNumber: range.group(2) == null && range.group(3) == null,
    );
  }

  final single = _singlePattern.firstMatch(cleaned);
  if (single != null) {
    final start = _toMinutes(
      single.group(1)!,
      single.group(2),
      single.group(3),
    );
    if (start == null) return null;
    return ParsedTime(
      start,
      null,
      isBareNumber: single.group(2) == null && single.group(3) == null,
    );
  }
  return null;
}

int? _toMinutes(String hourText, String? minuteText, String? meridiem) {
  var hour = int.tryParse(hourText);
  final minute = minuteText == null ? 0 : int.tryParse(minuteText);
  if (hour == null || minute == null) return null;
  if (hour > 23 || minute > 59) return null;
  final marker = meridiem?.toUpperCase().replaceAll('.', '');
  if (marker == 'PM' && hour < 12) hour += 12;
  if (marker == 'AM' && hour == 12) hour = 0;
  return hour * 60 + minute;
}

// ------------------------------------------------------------- homoglyphs
/// Characters that are visually identical to a Latin letter or digit but sit
/// in another Unicode block. Observed in practice: Apple's Vision returned
/// `EЕ303` for `EE303`, where the second character is a Cyrillic Ie (U+0415).
///
/// Only exact visual twins are listed. Genuine recognition confusions such as
/// `0` for `O` are deliberately left alone — "fixing" those would corrupt
/// correctly read codes.
const Map<int, int> _homoglyphs = {
  // Cyrillic uppercase
  0x0410: 0x41, // А -> A
  0x0412: 0x42, // В -> B
  0x0421: 0x43, // С -> C
  0x0415: 0x45, // Е -> E
  0x041D: 0x48, // Н -> H
  0x0406: 0x49, // І -> I
  0x0408: 0x4A, // Ј -> J
  0x041A: 0x4B, // К -> K
  0x041C: 0x4D, // М -> M
  0x041E: 0x4F, // О -> O
  0x0420: 0x50, // Р -> P
  0x0405: 0x53, // Ѕ -> S
  0x0422: 0x54, // Т -> T
  0x0423: 0x59, // У -> Y
  0x0425: 0x58, // Х -> X
  // Greek uppercase
  0x0391: 0x41, // Α -> A
  0x0392: 0x42, // Β -> B
  0x0395: 0x45, // Ε -> E
  0x0397: 0x48, // Η -> H
  0x0399: 0x49, // Ι -> I
  0x039A: 0x4B, // Κ -> K
  0x039C: 0x4D, // Μ -> M
  0x039D: 0x4E, // Ν -> N
  0x039F: 0x4F, // Ο -> O
  0x03A1: 0x50, // Ρ -> P
  0x03A4: 0x54, // Τ -> T
  0x03A5: 0x59, // Υ -> Y
  0x03A7: 0x58, // Χ -> X
  0x0396: 0x5A, // Ζ -> Z
};

/// Maps homoglyphs and full-width forms onto plain ASCII, leaving everything
/// else untouched.
String normaliseOcrText(String value) {
  var changed = false;
  final units = List<int>.of(value.codeUnits);
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit < 0x80) continue;
    final mapped = _homoglyphs[unit];
    if (mapped != null) {
      units[i] = mapped;
      changed = true;
      continue;
    }
    // Full-width digits, uppercase and lowercase letters.
    if (unit >= 0xFF10 && unit <= 0xFF19) {
      units[i] = unit - 0xFF10 + 0x30;
      changed = true;
    } else if (unit >= 0xFF21 && unit <= 0xFF3A) {
      units[i] = unit - 0xFF21 + 0x41;
      changed = true;
    } else if (unit >= 0xFF41 && unit <= 0xFF5A) {
      units[i] = unit - 0xFF41 + 0x61;
      changed = true;
    }
  }
  return changed ? String.fromCharCodes(units) : value;
}

// ----------------------------------------------------------- course codes
final RegExp _codePattern = RegExp(
  r'\b([A-Z]{2,4})\s?[-_.]?\s?(\d{2,4})\b',
  caseSensitive: false,
);

/// Pulls `EE301` out of `EE 301 Lab`, `ee-301`, or `EE301(P)`.
String extractCourseCode(String text) {
  final match = _codePattern.firstMatch(text);
  if (match == null) return '';
  return '${match.group(1)!.toUpperCase()}${match.group(2)!}';
}
