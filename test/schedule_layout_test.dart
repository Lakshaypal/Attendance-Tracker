import 'package:attendance_tracker/src/models.dart';
import 'package:attendance_tracker/src/schedule_layout.dart';
import 'package:flutter_test/flutter_test.dart';

TimetableClass slot(String id, int start, int duration) => TimetableClass(
  id: id,
  courseId: 'c',
  weekday: DateTime.monday,
  startMinute: start,
  durationMinutes: duration,
);

/// Two blocks collide on screen when they overlap in time *and* share a lane
/// range. Nothing the packer produces may collide.
void expectNoVisualOverlap(List<PlacedClass> placed) {
  for (var i = 0; i < placed.length; i++) {
    for (var j = i + 1; j < placed.length; j++) {
      final a = placed[i];
      final b = placed[j];
      final overlapInTime =
          a.slot.startMinute < b.slot.endMinute &&
          b.slot.startMinute < a.slot.endMinute;
      if (!overlapInTime) continue;
      final aLeft = a.leftFraction;
      final aRight = a.leftFraction + a.widthFraction;
      final bLeft = b.leftFraction;
      final bRight = b.leftFraction + b.widthFraction;
      expect(
        aLeft < bRight - 1e-9 && bLeft < aRight - 1e-9,
        isFalse,
        reason:
            '${a.slot.id} and ${b.slot.id} overlap in time and on screen '
            '(${a.lane}/${a.laneCount} vs ${b.lane}/${b.laneCount})',
      );
    }
  }
}

void main() {
  group('packOverlaps', () {
    test('a clear day uses one full-width lane', () {
      final placed = packOverlaps([
        slot('a', 540, 60),
        slot('b', 660, 60),
        slot('c', 780, 60),
      ]);
      expect(placed.map((item) => item.laneCount), everyElement(1));
      expect(placed.map((item) => item.lane), everyElement(0));
      expectNoVisualOverlap(placed);
    });

    test('two simultaneous labs split the column', () {
      // Exactly the seeded Monday: two labs both at 10:00.
      final placed = packOverlaps([
        slot('lab1', 600, 60),
        slot('lab2', 600, 60),
      ]);
      expect(placed, hasLength(2));
      expect(placed.every((item) => item.laneCount == 2), isTrue);
      expect(placed.map((item) => item.lane).toSet(), {0, 1});
      expect(placed.first.leftFraction, 0);
      expect(placed.last.leftFraction, 0.5);
      expectNoVisualOverlap(placed);
    });

    test('touching classes share a lane', () {
      final placed = packOverlaps([slot('a', 600, 60), slot('b', 660, 60)]);
      expect(placed.every((item) => item.laneCount == 1), isTrue);
      expectNoVisualOverlap(placed);
    });

    test('a long class overlapping two short ones needs two lanes', () {
      final placed = packOverlaps([
        slot('long', 600, 180),
        slot('short1', 620, 40),
        slot('short2', 700, 40),
      ]);
      expect(placed.every((item) => item.laneCount == 2), isTrue);
      // The two short ones can share the second lane because they do not
      // overlap each other.
      final short1 = placed.firstWhere((item) => item.slot.id == 'short1');
      final short2 = placed.firstWhere((item) => item.slot.id == 'short2');
      expect(short1.lane, short2.lane);
      expectNoVisualOverlap(placed);
    });

    test('separate overlap groups are sized independently', () {
      final placed = packOverlaps([
        slot('a', 540, 60),
        slot('b', 540, 60),
        slot('c', 540, 60),
        slot('solo', 720, 60),
      ]);
      expect(
        placed.firstWhere((item) => item.slot.id == 'solo').laneCount,
        1,
        reason: 'a later, unrelated class must not inherit the wide group',
      );
      expect(
        placed
            .where((item) => item.slot.id != 'solo')
            .every((item) => item.laneCount == 3),
        isTrue,
      );
      expectNoVisualOverlap(placed);
    });

    test('a chain of staggered overlaps never collides', () {
      final placed = packOverlaps([
        slot('a', 540, 120),
        slot('b', 600, 120),
        slot('c', 660, 120),
        slot('d', 720, 120),
      ]);
      expectNoVisualOverlap(placed);
    });

    test('an empty day is handled', () {
      expect(packOverlaps(const []), isEmpty);
    });
  });

  group('gridBounds', () {
    test('rounds out to whole hours around the real classes', () {
      final bounds = gridBounds([
        [slot('a', 9 * 60 + 30, 60)],
        [slot('b', 15 * 60, 90)],
      ]);
      expect(bounds.startMinute, 9 * 60);
      // 16:30 rounds out to a full 17:00 row.
      expect(bounds.endMinute, 17 * 60);
    });

    test('falls back to a sensible window when nothing is scheduled', () {
      final bounds = gridBounds([<TimetableClass>[]]);
      expect(bounds.startMinute, 8 * 60);
      expect(bounds.endMinute, 18 * 60);
    });

    test('keeps a minimum height so one class still reads as a grid', () {
      final bounds = gridBounds([
        [slot('a', 10 * 60, 60)],
      ]);
      expect(bounds.endMinute - bounds.startMinute, greaterThanOrEqualTo(180));
    });
  });
}
