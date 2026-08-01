import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../update/update_service.dart';
import 'design.dart';

/// A slim strip that appears above the tabs when a newer release exists.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.updates});

  final UpdateService updates;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: updates,
    builder: (context, _) {
      if (!updates.hasUpdate) return const SizedBox.shrink();
      final info = updates.available!;
      final scheme = Theme.of(context).colorScheme;
      return Material(
        color: scheme.primaryContainer,
        child: SafeArea(
          bottom: false,
          child: InkWell(
            onTap: () => showUpdateSheet(context, updates),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 9, 8, 9),
              child: Row(
                children: [
                  Icon(
                    Icons.system_update_rounded,
                    size: 18,
                    color: scheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Version ${info.version} is available',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => showUpdateSheet(context, updates),
                    child: const Text('View'),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: scheme.onPrimaryContainer,
                    ),
                    onPressed: () => updates.skip(info.version),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Full details, release notes, and the download button.
Future<void> showUpdateSheet(
  BuildContext context,
  UpdateService updates,
) async {
  final info = updates.available;
  if (info == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${info.version}',
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              'You are on ${updates.currentVersion}',
              style: TextStyle(color: subtleInk(sheetContext), fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            if (info.notes.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(
                    sheetContext,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  info.notes,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ),
            const SizedBox(height: 16),
            const InfoNote(
              text:
                  'Your attendance data is not touched by an update. The new '
                  'version reads the same file and upgrades its format if it '
                  'needs to.',
              icon: Icons.shield_outlined,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final target = info.downloadUrl ?? info.pageUrl;
                  final opened = await launchUrl(
                    Uri.parse(target),
                    mode: LaunchMode.externalApplication,
                  );
                  if (!sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                  if (!opened) {
                    showSnack(context, 'Could not open $target');
                  }
                },
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  info.downloadUrl == null
                      ? 'Open the release page'
                      : 'Download ${info.assetName}',
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  updates.skip(info.version);
                  Navigator.pop(sheetContext);
                },
                child: const Text('Skip this version'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
