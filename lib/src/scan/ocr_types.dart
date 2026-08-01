/// Geometry types shared by the OCR backends and the timetable parser.
///
/// Coordinates are always normalised to the 0…1 range with the origin at the
/// top-left of the photo, so the parser behaves identically whatever the
/// camera resolution or the OCR engine.
library;

class TextBox {
  const TextBox(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  TextBox merge(TextBox other) => TextBox(
    left < other.left ? left : other.left,
    top < other.top ? top : other.top,
    right > other.right ? right : other.right,
    bottom > other.bottom ? bottom : other.bottom,
  );

  /// How much of the vertical extent is shared with [other], as a fraction of
  /// the smaller of the two heights. Used to decide whether two words sit on
  /// the same printed line.
  double verticalOverlap(TextBox other) {
    final top0 = top > other.top ? top : other.top;
    final bottom0 = bottom < other.bottom ? bottom : other.bottom;
    final shared = bottom0 - top0;
    if (shared <= 0) return 0;
    final smaller = height < other.height ? height : other.height;
    return smaller <= 0 ? 0 : shared / smaller;
  }

  @override
  String toString() =>
      'TextBox(${left.toStringAsFixed(3)}, ${top.toStringAsFixed(3)}, '
      '${right.toStringAsFixed(3)}, ${bottom.toStringAsFixed(3)})';
}

/// One word (or short run of characters) recognised in the photo.
class OcrWord {
  const OcrWord(this.text, this.box);

  final String text;
  final TextBox box;

  @override
  String toString() => '"$text" $box';
}

/// Raised when OCR is unavailable or fails on this platform, so the UI can
/// offer the manual builder instead of showing a stack trace.
class OcrUnavailable implements Exception {
  const OcrUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}
