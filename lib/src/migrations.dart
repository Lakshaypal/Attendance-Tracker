/// Forward and backward compatibility for the saved data file.
///
/// Two devices running two versions of the app will read each other's files —
/// through sync, through a restored backup, or simply because one of them has
/// not been updated yet. The rules that make that safe:
///
///  1. **Every file carries a `schemaVersion`.** Files written before the
///     field existed are treated as version 1.
///  2. **Older files are migrated forward** by a chain of small, ordered steps.
///     Each step is pure and independently testable.
///  3. **Newer files are never migrated backwards and never overwritten.** An
///     old app that meets a file from a future version loads what it
///     understands and refuses to save, rather than silently truncating fields
///     it does not know about.
///  4. **Unknown fields survive a round trip.** Anything the running version
///     does not recognise is carried in [kExtraKey] and written back out
///     untouched, so an old app cannot destroy a new app's data just by
///     opening it.
library;

/// Bumped whenever the on-disk shape changes in a way that needs a migration.
///
/// History:
///  * 1 — original release: courses/timetable/records, `option` on a course.
///  * 2 — added `settings`.
///  * 3 — `option` became `electiveGroup`, courses gained `enrolled`.
const int kSchemaVersion = 3;

/// Where a model stashes fields written by a newer version of the app.
const String kExtraKey = '_extra';

/// Keys that belong to the schema itself rather than to a model.
const Set<String> kEnvelopeKeys = {
  'schemaVersion',
  'format',
  'exportedAt',
  'appVersion',
  'settings',
  'courses',
  'timetable',
  'records',
};

class SchemaTooNewException implements Exception {
  const SchemaTooNewException(this.fileVersion, this.appVersion);

  final int fileVersion;
  final int appVersion;

  @override
  String toString() =>
      'This data was saved by a newer version of Attendance Tracker '
      '(format $fileVersion, this app understands $appVersion). '
      'Update the app to open it safely.';
}

/// Reads the version out of an envelope, tolerating the pre-versioning format.
int schemaVersionOf(Map<String, dynamic> data) {
  final explicit = (data['schemaVersion'] as num?)?.toInt();
  if (explicit != null && explicit > 0) return explicit;
  // v2 shipped a `format: 2` marker before `schemaVersion` existed.
  final legacy = (data['format'] as num?)?.toInt();
  if (legacy != null && legacy >= 2) return 2;
  return 1;
}

/// One ordered, self-contained upgrade step.
typedef Migration = Map<String, dynamic> Function(Map<String, dynamic> data);

/// `_migrations[n]` upgrades a version-`n` document to version `n + 1`.
final Map<int, Migration> _migrations = {1: _v1ToV2, 2: _v2ToV3};

/// Brings [data] up to [kSchemaVersion].
///
/// Throws [SchemaTooNewException] when the document comes from a future
/// version, so the caller can decline to touch it.
Map<String, dynamic> migrateToCurrent(Map<String, dynamic> data) {
  var version = schemaVersionOf(data);
  if (version > kSchemaVersion) {
    throw SchemaTooNewException(version, kSchemaVersion);
  }
  var working = Map<String, dynamic>.from(data);
  while (version < kSchemaVersion) {
    final step = _migrations[version];
    if (step == null) {
      // No step registered: nothing structural changed, so just move the
      // marker rather than refusing to load.
      version++;
      continue;
    }
    working = step(working);
    version++;
    working['schemaVersion'] = version;
  }
  working['schemaVersion'] = kSchemaVersion;
  return working;
}

/// v1 had no `settings` block; the defaults are filled in by `Settings`.
Map<String, dynamic> _v1ToV2(Map<String, dynamic> data) {
  final out = Map<String, dynamic>.from(data);
  out['settings'] ??= <String, dynamic>{};
  return out;
}

/// v2 called an elective band `option` and had no notion of enrolment: every
/// stored course was one the student was taking.
Map<String, dynamic> _v2ToV3(Map<String, dynamic> data) {
  final out = Map<String, dynamic>.from(data);
  final courses = data['courses'];
  if (courses is! List) return out;
  out['courses'] = [
    for (final entry in courses)
      if (entry is Map)
        () {
          final course = Map<String, dynamic>.from(entry);
          course['electiveGroup'] ??= course['option'];
          course.remove('option');
          course['enrolled'] ??= true;
          return course;
        }()
      else
        entry,
  ];
  return out;
}

/// Splits a decoded model map into the fields [known] covers and everything
/// else, so the remainder can be preserved verbatim.
Map<String, dynamic>? extraFieldsOf(
  Map<String, dynamic> json,
  Set<String> known,
) {
  Map<String, dynamic>? extra;
  final carried = json[kExtraKey];
  if (carried is Map) extra = Map<String, dynamic>.from(carried);
  for (final entry in json.entries) {
    if (entry.key == kExtraKey || known.contains(entry.key)) continue;
    (extra ??= <String, dynamic>{})[entry.key] = entry.value;
  }
  return extra;
}

/// Merges preserved unknown fields back into an encoded model map.
Map<String, dynamic> withExtras(
  Map<String, dynamic> json,
  Map<String, dynamic>? extra,
) {
  if (extra == null || extra.isEmpty) return json;
  final out = Map<String, dynamic>.from(json);
  for (final entry in extra.entries) {
    // Never let a stale carried value shadow a field this version owns.
    out.putIfAbsent(entry.key, () => entry.value);
  }
  return out;
}
