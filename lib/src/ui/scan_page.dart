import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../civil_date.dart';
import '../models.dart';
import '../scan/ocr_service.dart';
import '../scan/ocr_types.dart';
import '../scan/timetable_parser.dart';
import '../store.dart';
import 'design.dart';
import 'sheets.dart';

enum _Stage { pick, working, review, failed }

/// Photograph a printed timetable, read it, then confirm what goes in.
///
/// Nothing is applied until the user presses the button on the review step —
/// OCR is never right often enough to be trusted silently.
class ScanTimetablePage extends StatefulWidget {
  const ScanTimetablePage({super.key, required this.store});

  final AttendanceStore store;

  @override
  State<ScanTimetablePage> createState() => _ScanTimetablePageState();
}

class _ScanTimetablePageState extends State<ScanTimetablePage> {
  final ImagePicker _picker = ImagePicker();

  _Stage _stage = _Stage.pick;
  File? _image;
  ScanResult? _result;
  String _error = '';
  List<_ReviewRow> _rows = [];
  bool _replaceExisting = true;

  AttendanceStore get store => widget.store;

  bool get _cameraAvailable =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 2600,
        imageQuality: 92,
      );
      if (picked == null || !mounted) return;
      setState(() {
        _image = File(picked.path);
        _stage = _Stage.working;
        _result = null;
        _rows = [];
      });
      await _read(picked.path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = 'That image could not be opened: $error';
      });
    }
  }

  Future<void> _read(String path) async {
    List<OcrWord> words;
    try {
      words = await OcrService.recognise(path);
    } on OcrUnavailable catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = error.message;
      });
      return;
    }
    if (!mounted) return;

    final result = parseTimetable(words);
    if (!result.isUsable) {
      setState(() {
        _stage = _Stage.failed;
        _result = result;
        _error = result.warnings.isEmpty
            ? 'That photo could not be turned into a timetable.'
            : result.warnings.first;
      });
      return;
    }
    setState(() {
      _result = result;
      _rows = [for (final slot in result.slots) _ReviewRow.from(slot, store)];
      _stage = _Stage.review;
    });
  }

  void _apply() {
    final rows = _rows.where((row) => row.include && row.isResolved).toList();
    if (rows.isEmpty) {
      showSnack(context, 'Pick a course for at least one class first.');
      return;
    }

    // Create every new course once, even when several cells share a code.
    final created = <String, Course>{};
    for (final row in rows) {
      if (row.courseId != null) continue;
      final code = row.newCode!;
      created[code] ??= store.saveCourse(code: code, name: code);
    }

    final classes = <TimetableClass>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final courseId = row.courseId ?? created[row.newCode!]!.id;
      classes.add(
        TimetableClass(
          id: 'scan-${DateTime.now().microsecondsSinceEpoch}-$i',
          courseId: courseId,
          weekday: row.slot.weekday,
          startMinute: row.slot.startMinute,
          durationMinutes: row.slot.durationMinutes,
          title: row.slot.label,
        ),
      );
    }

    if (_replaceExisting) {
      store.replaceTimetable(classes);
    } else {
      store.addTimetableClasses(classes);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    showSnack(
      context,
      '${classes.length} ${classes.length == 1 ? 'class' : 'classes'} '
      '${_replaceExisting ? 'imported' : 'added'}.',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Scan timetable'),
      actions: [
        if (_stage == _Stage.review || _stage == _Stage.failed)
          TextButton(
            onPressed: () => setState(() {
              _stage = _Stage.pick;
              _image = null;
              _result = null;
              _rows = [];
            }),
            child: const Text('Retake'),
          ),
      ],
    ),
    body: switch (_stage) {
      _Stage.pick => _buildPicker(),
      _Stage.working => _buildWorking(),
      _Stage.failed => _buildFailed(),
      _Stage.review => _buildReview(),
    },
    bottomNavigationBar: _stage == _Stage.review ? _buildApplyBar() : null,
  );

  Widget _buildPicker() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
    children: [
      Icon(
        Icons.document_scanner_rounded,
        size: 62,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 16),
      Text(
        'Point the camera at your timetable',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        'The day headings and the time column both need to be in the frame. '
        'A flat, straight, well-lit shot reads best.',
        textAlign: TextAlign.center,
        style: TextStyle(color: subtleInk(context)),
      ),
      const SizedBox(height: 24),
      if (_cameraAvailable) ...[
        FilledButton.icon(
          onPressed: () => _pick(ImageSource.camera),
          icon: const Icon(Icons.photo_camera_rounded),
          label: const Text('Take a photo'),
        ),
        const SizedBox(height: 10),
      ],
      OutlinedButton.icon(
        onPressed: () => _pick(ImageSource.gallery),
        icon: const Icon(Icons.image_outlined),
        label: Text(
          _cameraAvailable ? 'Choose from photos' : 'Choose an image file',
        ),
      ),
      const SizedBox(height: 22),
      const InfoNote(
        text:
            'The photo is read on this device and is never uploaded. Nothing '
            'is changed until you confirm the classes on the next screen.',
        icon: Icons.lock_outline_rounded,
      ),
      if (!OcrService.isSupported) ...[
        const SizedBox(height: 10),
        InfoNote(
          text: OcrService.unsupportedReason,
          icon: Icons.warning_amber_rounded,
          tone: const Color(0xFFCC7A00),
        ),
      ],
    ],
  );

  Widget _buildWorking() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (_image != null)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(_image!, fit: BoxFit.contain),
            ),
          ),
        ),
      const CircularProgressIndicator(),
      const SizedBox(height: 14),
      Text(
        'Reading the timetable…',
        style: TextStyle(color: subtleInk(context)),
      ),
      const SizedBox(height: 40),
    ],
  );

  Widget _buildFailed() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
    children: [
      if (_image != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: InteractiveViewer(
              child: Image.file(_image!, fit: BoxFit.contain),
            ),
          ),
        ),
      const SizedBox(height: 18),
      InfoNote(
        text: _error,
        icon: Icons.error_outline_rounded,
        tone: Theme.of(context).colorScheme.error,
      ),
      if (_result != null && _result!.wordCount > 0) ...[
        const SizedBox(height: 8),
        Text(
          '${_result!.wordCount} pieces of text were recognised.',
          style: TextStyle(fontSize: 12, color: subtleInk(context)),
        ),
      ],
      const SizedBox(height: 18),
      Text(
        'What you can do',
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      const Text(
        '• Retake the photo straight on, with the whole grid inside the frame.\n'
        '• Make sure the day names and the times are readable.\n'
        '• Or add the classes yourself — the photo stays on screen while you '
        'do.',
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: () => showSlotSheet(context, store),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add a class by hand'),
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: () => setState(() => _stage = _Stage.pick),
        child: const Text('Try another photo'),
      ),
    ],
  );

  Widget _buildReview() {
    final result = _result!;
    final byDay = <int, List<_ReviewRow>>{};
    for (final row in _rows) {
      (byDay[row.slot.weekday] ??= <_ReviewRow>[]).add(row);
    }
    final days = byDay.keys.toList()..sort();
    final selected = _rows.where((row) => row.include && row.isResolved).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        if (_image != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 190),
              child: InteractiveViewer(
                child: Image.file(_image!, fit: BoxFit.contain),
              ),
            ),
          ),
        const SizedBox(height: 14),
        InfoNote(
          text:
              'Found $selected ${selected == 1 ? 'class' : 'classes'} across '
              '${days.length} ${days.length == 1 ? 'day' : 'days'}, with days '
              '${result.daysAreColumns ? 'across the top' : 'down the side'}. '
              'Check each one before importing.',
          icon: Icons.checklist_rounded,
        ),
        for (final warning in result.warnings) ...[
          const SizedBox(height: 8),
          InfoNote(
            text: warning,
            icon: Icons.warning_amber_rounded,
            tone: const Color(0xFFCC7A00),
          ),
        ],
        const SizedBox(height: 16),
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
            child: Text(
              longWeekdayNames[day - 1],
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          for (final row in byDay[day]!)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ReviewTile(
                row: row,
                store: store,
                onChanged: () => setState(() {}),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildApplyBar() {
    final selected = _rows.where((row) => row.include && row.isResolved).length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('Replace'),
                  icon: Icon(Icons.swap_horiz_rounded, size: 18),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('Add to existing'),
                  icon: Icon(Icons.playlist_add_rounded, size: 18),
                ),
              ],
              selected: {_replaceExisting},
              onSelectionChanged: (value) =>
                  setState(() => _replaceExisting = value.first),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: selected == 0 ? null : _confirmApply,
                child: Text(
                  _replaceExisting
                      ? 'Replace timetable with $selected '
                            '${selected == 1 ? 'class' : 'classes'}'
                      : 'Add $selected ${selected == 1 ? 'class' : 'classes'}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmApply() async {
    if (_replaceExisting && store.timetable.isNotEmpty) {
      final ok = await confirm(
        context,
        title: 'Replace your timetable?',
        message:
            'The ${store.timetable.length} weekly classes you have now will be '
            'removed. Your attendance records are kept.',
        confirmLabel: 'Replace',
      );
      if (!ok || !mounted) return;
    }
    _apply();
  }
}

/// One scanned cell awaiting confirmation.
class _ReviewRow {
  _ReviewRow({
    required this.slot,
    required this.courseId,
    required this.newCode,
    required this.include,
  });

  factory _ReviewRow.from(ScannedSlot slot, AttendanceStore store) {
    final match = slot.code.isEmpty ? null : store.findCourseByCode(slot.code);
    return _ReviewRow(
      slot: slot,
      courseId: match?.id,
      newCode: match == null && slot.code.isNotEmpty ? slot.code : null,
      // Cells with no readable code start switched off so nothing is imported
      // by accident.
      include: slot.code.isNotEmpty,
    );
  }

  ScannedSlot slot;

  /// Set when the cell maps onto a course that already exists.
  String? courseId;

  /// Set when importing should create a new course with this code.
  String? newCode;

  bool include;

  bool get isResolved => courseId != null || newCode != null;
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.row,
    required this.store,
    required this.onChanged,
  });

  final _ReviewRow row;
  final AttendanceStore store;
  final VoidCallback onChanged;

  static const String _createValue = '__create__';
  static const String _noneValue = '__none__';

  @override
  Widget build(BuildContext context) {
    final existing = row.courseId == null
        ? null
        : store.courseById(row.courseId);
    final value = existing != null
        ? existing.id
        : (row.newCode != null ? _createValue : _noneValue);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
        child: Row(
          children: [
            Checkbox(
              value: row.include,
              onChanged: (checked) {
                row.include = checked ?? false;
                onChanged();
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatTimeRange(
                      row.slot.startMinute,
                      row.slot.durationMinutes,
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Read as "${row.slot.rawText}"',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: subtleInk(context)),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: value,
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: _noneValue,
                        child: Text('Choose a course…'),
                      ),
                      if (row.slot.code.isNotEmpty)
                        DropdownMenuItem(
                          value: _createValue,
                          child: Text('Create ${row.slot.code}'),
                        ),
                      for (final course in store.courses)
                        DropdownMenuItem(
                          value: course.id,
                          child: Text(
                            '${course.code} · ${course.name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (next) {
                      switch (next) {
                        case null:
                          return;
                        case _noneValue:
                          row.courseId = null;
                          row.newCode = null;
                          row.include = false;
                        case _createValue:
                          row.courseId = null;
                          row.newCode = row.slot.code;
                          row.include = true;
                        default:
                          row.courseId = next;
                          row.newCode = null;
                          row.include = true;
                      }
                      onChanged();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
