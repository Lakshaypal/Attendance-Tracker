import 'package:flutter/material.dart';

import '../models.dart';

/// A fixed palette so every course keeps the same colour on every device and
/// across restarts. Picking from `Object.hashCode` would not — it varies per
/// run — so the seed is a stable hash of the course id.
const List<Color> kCoursePalette = [
  Color(0xFF3B62D9),
  Color(0xFF12876A),
  Color(0xFFB4442E),
  Color(0xFF7B4BC9),
  Color(0xFFC07A00),
  Color(0xFF0E7490),
  Color(0xFFB03060),
  Color(0xFF4F6D2E),
  Color(0xFF8A5A2B),
  Color(0xFF2F6FB0),
];

/// FNV-1a. Deterministic across runs and platforms, unlike `String.hashCode`.
int stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

Color courseColor(Course course) =>
    kCoursePalette[(course.colorSeed ?? stableHash(course.id)) %
        kCoursePalette.length];

/// Blends a course colour into the current surface so blocks stay readable in
/// both light and dark mode.
Color courseSurface(BuildContext context, Course course) {
  final base = courseColor(course);
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark
      ? Color.alphaBlend(base.withValues(alpha: 0.30), const Color(0xFF16181D))
      : Color.alphaBlend(base.withValues(alpha: 0.14), Colors.white);
}

Color courseInk(BuildContext context, Course course) {
  final base = courseColor(course);
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark
      ? Color.alphaBlend(base.withValues(alpha: 0.45), Colors.white)
      : Color.alphaBlend(Colors.black.withValues(alpha: 0.25), base);
}

/// Green above the target, amber just under it, red well under it.
Color percentColor(BuildContext context, double? percent, double threshold) {
  if (percent == null) return Theme.of(context).colorScheme.outline;
  if (percent >= threshold) return const Color(0xFF18865A);
  if (percent >= threshold - 10) return const Color(0xFFCC7A00);
  return const Color(0xFFD6353B);
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF315CDE),
    brightness: brightness,
  );
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF101216)
        : const Color(0xFFF6F7FB),
    cardTheme: CardThemeData(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: isDark ? const Color(0xFF191C22) : Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF22262E) : const Color(0xFFEFF1F6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide.none,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

/// Muted body colour used for secondary lines throughout the app.
Color subtleInk(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant;

/// Standard page scaffolding: big title, one-line subtitle, optional trailing
/// action, then the body.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(18, 14, 18, 0),
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: subtleInk(context),
                      ),
                    ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
          const SizedBox(height: 14),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

class CourseBadge extends StatelessWidget {
  const CourseBadge({super.key, required this.course, this.size = 44});

  final Course course;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 3),
    decoration: BoxDecoration(
      color: courseSurface(context, course),
      borderRadius: BorderRadius.circular(12),
    ),
    child: FittedBox(
      child: Text(
        course.code.isEmpty ? '—' : course.code,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          color: courseInk(context, course),
        ),
      ),
    ),
  );
}

/// Percentage ring with the value in the middle.
class PercentRing extends StatelessWidget {
  const PercentRing({
    super.key,
    required this.percent,
    required this.color,
    this.size = 62,
    this.strokeWidth = 7,
    this.label,
  });

  final double? percent;
  final Color color;
  final double size;
  final double strokeWidth;
  final String? label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      fit: StackFit.expand,
      children: [
        CircularProgressIndicator(
          value: (percent ?? 0) / 100,
          strokeWidth: strokeWidth,
          strokeCap: StrokeCap.round,
          color: color,
          backgroundColor: color.withValues(alpha: 0.15),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                percent == null ? '—' : '${percent!.round()}%',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.26,
                  color: color,
                ),
              ),
              if (label != null)
                Text(
                  label!,
                  style: TextStyle(
                    fontSize: size * 0.14,
                    color: subtleInk(context),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.status, this.size = 6});

  final AttendanceStatus status;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: status.tint, shape: BoxShape.circle),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: subtleInk(context)),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}

class InfoNote extends StatelessWidget {
  const InfoNote({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.tone,
    this.action,
  });

  final String text;
  final IconData icon;
  final Color? tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = tone ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
      ),
    );
}
