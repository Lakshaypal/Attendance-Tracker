import 'models.dart';

/// One slot together with the horizontal band it should occupy inside its day
/// column.
class PlacedClass {
  PlacedClass(this.slot, this.lane, this.laneCount);

  final TimetableClass slot;

  /// Zero-based column within the overlapping group.
  final int lane;

  /// How many lanes the group needs. `lane / laneCount` and
  /// `(lane + 1) / laneCount` give the block's left and right edges as
  /// fractions of the day column.
  int laneCount;

  double get leftFraction => lane / laneCount;
  double get widthFraction => 1 / laneCount;
}

/// Assigns overlapping classes to side-by-side lanes, the way a week view in a
/// calendar app does.
///
/// [slots] must already be sorted by start time — the store's weekday buckets
/// are. The pass is O(n · L) where L is the number of lanes in the widest
/// overlap group (2 in a normal timetable), so effectively linear, and it
/// allocates one [PlacedClass] per slot and nothing else.
///
/// Classes that merely touch (one ends exactly when the next begins) do not
/// overlap and share a lane.
List<PlacedClass> packOverlaps(List<TimetableClass> slots) {
  if (slots.isEmpty) return const [];
  final placed = <PlacedClass>[];
  final laneEnds = <int>[]; // last end minute currently occupying each lane
  var groupStart = 0; // index in `placed` of the current overlap group
  var groupEnd = -1; // latest end minute seen in the current group

  void closeGroup() {
    final laneCount = laneEnds.length;
    if (laneCount == 0) return;
    for (var i = groupStart; i < placed.length; i++) {
      placed[i].laneCount = laneCount;
    }
  }

  for (final slot in slots) {
    if (slot.startMinute >= groupEnd) {
      // Nothing in the current group reaches this slot, so the group is final.
      closeGroup();
      groupStart = placed.length;
      groupEnd = -1;
      laneEnds.clear();
    }
    var lane = 0;
    while (lane < laneEnds.length && laneEnds[lane] > slot.startMinute) {
      lane++;
    }
    if (lane == laneEnds.length) {
      laneEnds.add(slot.endMinute);
    } else {
      laneEnds[lane] = slot.endMinute;
    }
    placed.add(PlacedClass(slot, lane, 1));
    if (slot.endMinute > groupEnd) groupEnd = slot.endMinute;
  }
  closeGroup();
  return placed;
}

/// The vertical extent a grid needs to show [slots], rounded out to whole
/// hours, with a sane fallback for an empty timetable.
({int startMinute, int endMinute}) gridBounds(
  Iterable<List<TimetableClass>> days, {
  int fallbackStart = 8 * 60,
  int fallbackEnd = 18 * 60,
}) {
  var earliest = 1 << 30;
  var latest = -1;
  for (final day in days) {
    for (final slot in day) {
      if (slot.startMinute < earliest) earliest = slot.startMinute;
      if (slot.endMinute > latest) latest = slot.endMinute;
    }
  }
  if (latest < 0) return (startMinute: fallbackStart, endMinute: fallbackEnd);
  final start = (earliest ~/ 60) * 60;
  final end = ((latest + 59) ~/ 60) * 60;
  // Always show at least three hours so a one-class day still looks like a
  // grid rather than a single stripe.
  return end - start >= 180
      ? (startMinute: start, endMinute: end)
      : (startMinute: start, endMinute: start + 180);
}
