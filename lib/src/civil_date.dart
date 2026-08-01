/// Integer calendar arithmetic on the proleptic Gregorian calendar.
///
/// Dates are represented as an *epoch day*: a signed count of days since
/// 1970-01-01. Every function here is O(1), allocation free, and immune to time
/// zones and daylight saving, which makes it safe to call from the hot paths
/// that rebuild indexes, paint month grids, or count weekday occurrences.
///
/// The conversions are Howard Hinnant's `days_from_civil` / `civil_from_days`,
/// which are exact for any year in the Dart integer range.
library;

const int _daysToEpoch = 719468; // 0000-03-01 -> 1970-01-01

/// Days since 1970-01-01 for the given calendar date.
int epochDayFromYmd(int year, int month, int day) {
  final y = month <= 2 ? year - 1 : year;
  // Floor division: `~/` truncates toward zero, so negative years are biased
  // first.
  final era = (y >= 0 ? y : y - 399) ~/ 400;
  final yearOfEra = y - era * 400; // [0, 399]
  final dayOfYear =
      (153 * (month + (month > 2 ? -3 : 9)) + 2) ~/ 5 + day - 1; // [0, 365]
  final dayOfEra =
      yearOfEra * 365 +
      yearOfEra ~/ 4 -
      yearOfEra ~/ 100 +
      dayOfYear; // [0, 146096]
  return era * 146097 + dayOfEra - _daysToEpoch;
}

/// The calendar date for an epoch day.
({int year, int month, int day}) ymdFromEpochDay(int epochDay) {
  final z = epochDay + _daysToEpoch;
  final era = (z >= 0 ? z : z - 146096) ~/ 146097;
  final dayOfEra = z - era * 146097; // [0, 146096]
  final yearOfEra =
      (dayOfEra - dayOfEra ~/ 1460 + dayOfEra ~/ 36524 - dayOfEra ~/ 146096) ~/
      365; // [0, 399]
  final dayOfYear =
      dayOfEra -
      (365 * yearOfEra + yearOfEra ~/ 4 - yearOfEra ~/ 100); // [0, 365]
  final mp = (5 * dayOfYear + 2) ~/ 153; // [0, 11]
  final day = dayOfYear - (153 * mp + 2) ~/ 5 + 1; // [1, 31]
  final month = mp + (mp < 10 ? 3 : -9); // [1, 12]
  return (
    year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0),
    month: month,
    day: day,
  );
}

/// ISO weekday (Monday = 1 … Sunday = 7). 1970-01-01 was a Thursday.
///
/// Dart's `%` always returns a non-negative result for a positive divisor, so
/// this is correct for dates before the epoch too.
int weekdayOfEpochDay(int epochDay) => (epochDay + 3) % 7 + 1;

int epochDayOf(DateTime date) =>
    epochDayFromYmd(date.year, date.month, date.day);

DateTime dateTimeFromEpochDay(int epochDay) {
  final ymd = ymdFromEpochDay(epochDay);
  return DateTime(ymd.year, ymd.month, ymd.day);
}

/// The single place the app asks what time it is.
///
/// Everything that depends on "today" goes through here, which keeps the
/// date-rollover behaviour testable instead of being a bug you only meet at
/// midnight.
class Clock {
  Clock._();

  static DateTime Function() now = DateTime.now;

  static void reset() => now = DateTime.now;
}

int todayEpochDay() => epochDayOf(Clock.now());

/// Minutes past midnight, used for the current-time line on the grid.
int nowMinuteOfDay() {
  final now = Clock.now();
  return now.hour * 60 + now.minute;
}

/// How many times [isoWeekday] occurs in the inclusive range
/// [firstDay] … [lastDay].
///
/// O(1). This is what lets the store price "how many classes were scheduled
/// this semester" without ever walking the calendar day by day.
int weekdayOccurrences(int firstDay, int lastDay, int isoWeekday) {
  if (lastDay < firstDay) return 0;
  final span = lastDay - firstDay + 1;
  final whole = span ~/ 7;
  final remainder = span % 7;
  // The remainder covers the weekdays of firstDay … firstDay + remainder - 1.
  final offset = (isoWeekday - weekdayOfEpochDay(firstDay)) % 7;
  return whole + (offset < remainder ? 1 : 0);
}

bool isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

int daysInMonth(int year, int month) => switch (month) {
  1 || 3 || 5 || 7 || 8 || 10 || 12 => 31,
  4 || 6 || 9 || 11 => 30,
  _ => isLeapYear(year) ? 29 : 28,
};

/// First epoch day of the month containing [epochDay].
int startOfMonth(int epochDay) {
  final ymd = ymdFromEpochDay(epochDay);
  return epochDayFromYmd(ymd.year, ymd.month, 1);
}

/// Moves [epochDay] by [delta] whole months, clamping the day of month
/// (31 Jan + 1 month = 28/29 Feb rather than overflowing into March).
int addMonths(int epochDay, int delta) {
  final ymd = ymdFromEpochDay(epochDay);
  final absolute = ymd.year * 12 + (ymd.month - 1) + delta;
  final year = absolute >= 0 ? absolute ~/ 12 : (absolute - 11) ~/ 12;
  final month = absolute - year * 12 + 1;
  final day = ymd.day <= daysInMonth(year, month)
      ? ymd.day
      : daysInMonth(year, month);
  return epochDayFromYmd(year, month, day);
}

/// The Monday on or before [epochDay].
int startOfWeek(int epochDay) => epochDay - (weekdayOfEpochDay(epochDay) - 1);

String isoDateString(int epochDay) {
  final ymd = ymdFromEpochDay(epochDay);
  final month = ymd.month < 10 ? '0${ymd.month}' : '${ymd.month}';
  final day = ymd.day < 10 ? '0${ymd.day}' : '${ymd.day}';
  return '${ymd.year.toString().padLeft(4, '0')}-$month-$day';
}

/// Parses `YYYY-MM-DD` (ignoring any time suffix). Returns null when the text
/// is not a usable date, so callers can fall back instead of throwing.
int? parseIsoDateToEpochDay(String? value) {
  if (value == null || value.length < 10) return null;
  final year = int.tryParse(value.substring(0, 4));
  final month = int.tryParse(value.substring(5, 7));
  final day = int.tryParse(value.substring(8, 10));
  if (year == null || month == null || day == null) return null;
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > daysInMonth(year, month)) return null;
  return epochDayFromYmd(year, month, day);
}

const List<String> shortWeekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const List<String> longWeekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> shortMonthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> longMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String weekdayName(int isoWeekday) => shortWeekdayNames[isoWeekday - 1];

String formatDay(int epochDay) {
  final ymd = ymdFromEpochDay(epochDay);
  return '${weekdayName(weekdayOfEpochDay(epochDay))}, '
      '${ymd.day} ${shortMonthNames[ymd.month - 1]}';
}

String formatDayLong(int epochDay) {
  final ymd = ymdFromEpochDay(epochDay);
  return '${longWeekdayNames[weekdayOfEpochDay(epochDay) - 1]}, '
      '${ymd.day} ${longMonthNames[ymd.month - 1]} ${ymd.year}';
}

String formatMonthYear(int epochDay) {
  final ymd = ymdFromEpochDay(epochDay);
  return '${longMonthNames[ymd.month - 1]} ${ymd.year}';
}

/// Minutes past midnight rendered as `9:05 AM`.
String formatMinuteOfDay(int minuteOfDay) {
  final minutes = minuteOfDay % 1440;
  final hour = minutes ~/ 60;
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final display = hour % 12 == 0 ? 12 : hour % 12;
  return '$display:${(minutes % 60).toString().padLeft(2, '0')} $suffix';
}

/// Compact form used inside timetable blocks: `9 AM`, `9:30 AM`.
String formatMinuteCompact(int minuteOfDay) {
  final minutes = minuteOfDay % 1440;
  final hour = minutes ~/ 60;
  final suffix = hour >= 12 ? 'pm' : 'am';
  final display = hour % 12 == 0 ? 12 : hour % 12;
  final minute = minutes % 60;
  return minute == 0
      ? '$display$suffix'
      : '$display:${minute.toString().padLeft(2, '0')}$suffix';
}

String formatTimeRange(int startMinute, int durationMinutes) =>
    '${formatMinuteCompact(startMinute)}–'
    '${formatMinuteCompact(startMinute + durationMinutes)}';
