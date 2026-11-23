import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../domain/models/app_release_info.dart';
import 'app_card.dart';

class UpdateAvailableDialog extends StatelessWidget {
  const UpdateAvailableDialog({
    super.key,
    required this.release,
    required this.onDownload,
    required this.onDismiss,
  });

  final AppReleaseInfo release;
  final VoidCallback onDownload;
  final VoidCallback onDismiss;

  static Future<void> show(
    BuildContext context, {
    required AppReleaseInfo release,
    required VoidCallback onDownload,
    required VoidCallback onDismiss,
  }) {
    return showAdaptiveDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => UpdateAvailableDialog(
        release: release,
        onDownload: () {
          Navigator.of(ctx).pop();
          onDownload();
        },
        onDismiss: () {
          Navigator.of(ctx).pop();
          onDismiss();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  FLucideIcons.sparkles,
                  size: 20,
                  color: theme.colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Update Available',
                    style: theme.typography.display.sm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colors.foreground,
                    ),
                  ),
                ),
                FBadge(
                  child: Text(release.tagName),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              release.title.isNotEmpty ? release.title : 'New release ready',
              style: theme.typography.body.sm.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colors.foreground,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'What\'s New & Changelog:',
              style: theme.typography.body.xs.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colors.muted,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  release.changelog.isNotEmpty
                      ? release.changelog
                      : 'Improvements, stability fixes, and updates.',
                  style: theme.typography.body.xs.copyWith(
                    color: theme.colors.foreground,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FButton(
                  variant: FButtonVariant.outline,
                  size: FButtonSizeVariant.sm,
                  mainAxisSize: MainAxisSize.min,
                  onPress: onDismiss,
                  child: const Text('Later'),
                ),
                const SizedBox(width: 8),
                FButton(
                  size: FButtonSizeVariant.sm,
                  mainAxisSize: MainAxisSize.min,
                  onPress: onDownload,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(FLucideIcons.externalLink, size: 14),
                      SizedBox(width: 6),
                      Text('View Update'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
