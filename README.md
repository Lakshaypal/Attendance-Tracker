# Attendance Tracker

[![CI](https://github.com/Lakshaypal/attendance-tracker/actions/workflows/ci.yml/badge.svg)](https://github.com/Lakshaypal/attendance-tracker/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/Lakshaypal/attendance-tracker?sort=semver)](https://github.com/Lakshaypal/attendance-tracker/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Track class attendance **per subject**, see your week as a real grid, and build your timetable by photographing the printed one. For macOS and Android. No account, no server — everything stays on your device.

**[Download the latest release →](https://github.com/Lakshaypal/attendance-tracker/releases/latest)**

---

## What it does

**Timetable grid.** Time down the side, one column per day, classes positioned by their real start and length. Classes that clash — two labs in the same hour — are packed into side-by-side lanes rather than hiding each other. Tap a block to mark it, long-press to edit it. Today is tinted and carries a live current-time line.

**Calendar.** A swipeable month view. Coloured dots show what was marked; a hollow dot flags a past day with classes you never logged. Tap a day to mark it, declare a holiday, or add a one-off class.

**My subjects.** A printed timetable belongs to a whole class group, not to one student — the same 2 PM slot is one subject for you and another for the person beside you. So the app stores the *entire* timetable, including every option in every elective band, and this tab is where you say which ones are yours. Tick your compulsory subjects, pick one option per elective, or none. Everything else follows that choice.

**Attendance.** Reported **per subject only** — never a combined figure, because a college checks each subject against the threshold on its own. Each card gives the percentage, the mass-bunk-adjusted percentage, and the sentence you actually want: *"You can miss 3 more classes and stay above 75%"* or *"Attend the next 4 in a row to get back to 75%."* Subjects in trouble sort to the top. Nothing marked yet shows `—`, never a misleading 0%.

**Scan a timetable.** Photograph the printed grid; the app reads it on-device and shows you every class it found before anything is saved.

## Install

Grab the assets from [the latest release](https://github.com/Lakshaypal/attendance-tracker/releases/latest).

**Android** — download the `.apk` and open it. You will need to allow installs from unknown sources. Builds are signed with a debug keystore, so this is a sideload, not a Play Store app.

**macOS** — download the `.zip`, unzip, drag to Applications. The app is unsigned, so the first launch needs right-click → **Open** → Open. Once only.

## Staying up to date

The app asks GitHub whether a newer release exists, on launch and whenever you tap **Manage → Settings → Version**. If there is one you get a banner with the release notes and a download button. You can skip a version and it stops asking about that one.

The check is anonymous against the public Releases API — no token is shipped in the app, which is exactly why this repository is public. Every failure mode (offline, rate-limited, malformed release, unparseable tag, draft release) resolves to "no update" and is never allowed to interrupt the app.

The download hands the file to your browser or Finder; installing is one deliberate tap. There is no silent self-install: on macOS that would need a framework like Sparkle, and on Android it would mean shipping `REQUEST_INSTALL_PACKAGES`, which is a large amount of trust for a sideloaded app to ask for.

## Updating without losing data

This is designed for, not hoped for. Two devices on two versions will meet each other's files — through sync, a restored backup, or one phone simply not being updated yet.

| Situation | What happens |
| --- | --- |
| New app opens an **older** file | Migrated forward through an ordered chain of steps, then saved in the current format. |
| Old app opens a **newer** file | Refuses to migrate and **refuses to write**. A banner explains why. The file is left byte-for-byte as the newer app wrote it. |
| Old app edits data containing fields it does not know | Unknown fields are carried through untouched and written back out, so nothing is silently dropped. |
| Sync receives a payload from a newer device | Rejected whole. A half-applied import is worse than none. |

Every rule above has a test in [`test/migrations_test.dart`](test/migrations_test.dart), including a full round trip where an old build opens a new build's file, edits it, saves, and the new field is still there afterwards.

Saves are debounced, written to a temporary file, then renamed into place, so a crash mid-write cannot corrupt anything. The previous good save is kept and used automatically if the main file is unreadable.

## Performance

Data lives in three lists; every question the UI asks is answered from indexes rebuilt lazily, at most once per change, in **O(C + T + R)** time and space. After that rebuild, course lookup, classes-on-a-date, is-this-slot-marked, per-subject statistics and calendar day summaries are all **O(1)**.

The naive approach recomputes a subject's pending count by walking every day of the semester and rescanning every record — O(C · D · T · R) to draw one screen. Counting weekday occurrences arithmetically removes the calendar walk; hashing records by day removes the rescans. [`test/store_test.dart`](test/store_test.dart) cross-checks the fast path against a deliberately slow brute-force implementation over randomly generated semesters.

All date maths uses integer epoch days rather than `DateTime` — allocation-free, and immune to time zones and daylight saving.

## How the photo scan works

1. Read by the platform's own recogniser: ML Kit on Android, Apple Vision on macOS. Nothing is uploaded.
2. The parser rebuilds the grid **geometrically** — it finds the day headings and the time headings, works out which axis carries which, derives row and column bands from their positions, then assigns every remaining word to a cell. Days across the top and days down the side both work.
3. It copes with `9:00` / `9 AM` / `9:00-9:55`, afternoon slots printed as `1, 2, 3`, bare period numbers, and a lab spanning two rows folded into one longer class.
4. Recogniser output is normalised for Unicode homoglyphs first. Not theoretical: Vision returned `EЕ303` where the second character is a **Cyrillic Ie**, identical on screen and silently unmatchable. Genuine confusions like `0` for `O` are deliberately left alone — "fixing" those would corrupt correctly-read codes.
5. A review screen lists every cell it read. Nothing is applied until you confirm, and you choose replace or merge.

If the grid cannot be parsed the app says exactly what was missing and offers manual entry with the photo on screen. It never guesses. A cell the recogniser garbled is reported in its correct slot with no subject attached, rather than invented or dropped.

[`test/vision_fixture_test.dart`](test/vision_fixture_test.dart) runs the parser against recorded output from a real Vision pass, complete with a page heading above the grid, a homoglyph, and a genuine misread.

## Building

```bash
flutter pub get && flutter test
```

```bash
flutter run -d macos
```

```bash
flutter build apk --release
```

`flutter doctor` may warn that Android cmdline-tools are missing; the build still works. It will also warn that the ML Kit plugins apply the Kotlin Gradle Plugin, which a future Flutter release will reject.

## Releasing

Releases are cut by CI, never by hand.

1. Bump `version:` in `pubspec.yaml`.
2. Commit, then tag it: `git tag v1.1.0 && git push --tags`.

[`release.yml`](.github/workflows/release.yml) refuses to publish if the tag and the pubspec version disagree — the in-app updater compares the release tag against the version baked into the build, so a mismatch would make updates silently wrong. It then builds both platforms, runs the tests again, and publishes the assets with the names the updater looks for (`*.apk`, `*-macos.zip`).

## Layout

```
lib/
  main.dart                      entry, theme, navigation shell, onboarding gate
  src/
    civil_date.dart              epoch-day arithmetic and the Clock seam
    models.dart                  Course, TimetableClass, AttendanceRecord, CourseStats
    migrations.dart              schema versioning, forward migration, field preservation
    store.dart                   data, indexes, persistence, settings
    schedule_layout.dart         side-by-side lane packing for clashing classes
    sample_timetable.dart        the fictional demo timetable
    sync.dart                    code-protected local-network transfer
    scan/                        OCR backends and the geometric grid parser
    update/                      version comparison and the GitHub release check
    ui/                          five tabs, sheets, onboarding, shared widgets
test/                            135 tests
tool/ocr_fixture/                regenerates the recorded OCR fixture
```

## Licence

MIT — see [LICENSE](LICENSE).
