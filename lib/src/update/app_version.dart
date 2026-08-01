/// A comparable `major.minor.patch` version, tolerant of the shapes release
/// tags actually take: `v1.2.3`, `1.2.3+45`, `1.2`, `1.2.3-beta.1`.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, {this.preRelease});

  final int major;
  final int minor;
  final int patch;

  /// `beta.1` in `1.2.3-beta.1`. A pre-release sorts *below* the same numbers
  /// without one, so 1.2.0-beta never counts as newer than 1.2.0.
  final String? preRelease;

  static final RegExp _pattern = RegExp(
    r'^[vV]?(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:-([0-9A-Za-z.-]+))?(?:\+.*)?$',
  );

  /// Returns null rather than throwing — a malformed tag on a release must not
  /// crash the updater.
  static AppVersion? tryParse(String? value) {
    if (value == null) return null;
    final match = _pattern.firstMatch(value.trim());
    if (match == null) return null;
    return AppVersion(
      int.parse(match.group(1)!),
      int.tryParse(match.group(2) ?? '0') ?? 0,
      int.tryParse(match.group(3) ?? '0') ?? 0,
      preRelease: match.group(4),
    );
  }

  @override
  int compareTo(AppVersion other) {
    final byMajor = major.compareTo(other.major);
    if (byMajor != 0) return byMajor;
    final byMinor = minor.compareTo(other.minor);
    if (byMinor != 0) return byMinor;
    final byPatch = patch.compareTo(other.patch);
    if (byPatch != 0) return byPatch;
    if (preRelease == other.preRelease) return 0;
    if (preRelease == null) return 1; // a release beats its own pre-release
    if (other.preRelease == null) return -1;
    return preRelease!.compareTo(other.preRelease!);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  @override
  String toString() =>
      '$major.$minor.$patch${preRelease == null ? '' : '-$preRelease'}';
}
