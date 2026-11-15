import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../domain/models/quota_config.dart';
import '../../features/dashboard/view_models/dashboard_view_model.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'app_card.dart';

class QuotaProgressCard extends StatelessWidget {
  const QuotaProgressCard({
    super.key,
    required this.viewModel,
  });

  final DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final quota = viewModel.globalQuota;
    final usedBytes = viewModel.snapshot.sessionTotalBytes;
    final status = viewModel.quotaStatus;
    final ratio = viewModel.quotaRatio;
    final progress = viewModel.quotaProgress;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FLucideIcons.gauge,
                size: 16,
                color: _iconColor(status, theme),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Hotspot Data Quota',
                  style: theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colors.foreground,
                  ),
                ),
              ),
              _buildBadge(status, ratio),
              const SizedBox(width: 8),
              FTappable(
                onPress: () => showEditDialog(context, viewModel),
                child: Icon(
                  FLucideIcons.settings,
                  size: 15,
                  color: theme.colors.mutedForeground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!quota.enabled) ...[
            Text(
              'No session limit set. Tap below to set a data budget and prevent accidental overages.',
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 10),
            FButton(
              size: FButtonSizeVariant.sm,
              variant: FButtonVariant.outline,
              onPress: () => showEditDialog(context, viewModel),
              child: const Text('Set Session Limit'),
            ),
          ] else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: theme.colors.muted,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _progressColor(status, theme),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${Formatters.bytes(usedBytes)} of ${Formatters.bytes(quota.limitBytes)}',
                  style: theme.typography.body.xs.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colors.foreground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  _remainingText(usedBytes, quota.limitBytes),
                  style: theme.typography.body.xs.copyWith(
                    color: status == QuotaStatus.exceeded
                        ? const Color(0xFFEF4444)
                        : theme.colors.mutedForeground,
                    fontWeight: status == QuotaStatus.exceeded
                        ? FontWeight.w600
                        : FontWeight.normal,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _iconColor(QuotaStatus status, FThemeData theme) {
    switch (status) {
      case QuotaStatus.exceeded:
        return const Color(0xFFEF4444);
      case QuotaStatus.warning:
        return const Color(0xFFF59E0B);
      case QuotaStatus.normal:
        return AppTheme.downloadColor;
      case QuotaStatus.disabled:
        return theme.colors.mutedForeground;
    }
  }

  Color _progressColor(QuotaStatus status, FThemeData theme) {
    switch (status) {
      case QuotaStatus.exceeded:
        return const Color(0xFFEF4444);
      case QuotaStatus.warning:
        return const Color(0xFFF59E0B);
      case QuotaStatus.normal:
      case QuotaStatus.disabled:
        return AppTheme.downloadColor;
    }
  }

  Widget _buildBadge(QuotaStatus status, double ratio) {
    final pct = (ratio * 100).toInt();
    switch (status) {
      case QuotaStatus.disabled:
        return FBadge(
          child: const Text('Off'),
        );
      case QuotaStatus.normal:
        return FBadge(
          child: Text('$pct%'),
        );
      case QuotaStatus.warning:
        return FBadge(
          variant: FBadgeVariant.outline,
          child: Text('$pct% Warning'),
        );
      case QuotaStatus.exceeded:
        return FBadge(
          variant: FBadgeVariant.destructive,
          child: Text('$pct% Exceeded'),
        );
    }
  }

  String _remainingText(int usedBytes, int limitBytes) {
    final diff = limitBytes - usedBytes;
    if (diff > 0) {
      return '${Formatters.bytes(diff)} left';
    }
    return '${Formatters.bytes(-diff)} over limit';
  }

  static Future<void> showEditDialog(
    BuildContext context,
    DashboardViewModel viewModel,
  ) async {
    final quota = viewModel.globalQuota;
    var enabled = quota.enabled;
    var limitMb = quota.limitBytes ~/ (1024 * 1024);
    var warningPercent = quota.warningPercent;

    final controller = TextEditingController(text: '$limitMb');

    final saved = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setState) {
          final dialogTheme = ctx.theme;
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: AppCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(FLucideIcons.gauge, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Session Data Quota',
                        style: dialogTheme.typography.display.sm.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Enable Quota Limit',
                        style: dialogTheme.typography.body.sm,
                      ),
                      FSwitch(
                        value: enabled,
                        onChange: (val) => setState(() => enabled = val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (enabled) ...[
                    Text(
                      'Budget Presets',
                      style: dialogTheme.typography.body.xs.copyWith(
                        color: dialogTheme.colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final preset in [500, 1024, 2048, 5120])
                          FTappable(
                            onPress: () {
                              setState(() {
                                limitMb = preset;
                                controller.text = '$preset';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: limitMb == preset
                                    ? dialogTheme.colors.primary
                                    : dialogTheme.colors.muted,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                preset >= 1024
                                    ? '${preset ~/ 1024} GB'
                                    : '$preset MB',
                                style: dialogTheme.typography.body.xs.copyWith(
                                  color: limitMb == preset
                                      ? dialogTheme.colors.primaryForeground
                                      : dialogTheme.colors.foreground,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FTextField(
                      control: .managed(controller: controller),
                      keyboardType: TextInputType.number,
                      label: const Text('Custom Limit (MB)'),
                      hint: '1024',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Warning at: $warningPercent% of limit',
                      style: dialogTheme.typography.body.xs.copyWith(
                        color: dialogTheme.colors.mutedForeground,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FButton(
                        variant: FButtonVariant.outline,
                        size: FButtonSizeVariant.sm,
                        mainAxisSize: MainAxisSize.min,
                        onPress: () => Navigator.of(dialogCtx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FButton(
                        size: FButtonSizeVariant.sm,
                        mainAxisSize: MainAxisSize.min,
                        onPress: () {
                          final parsed = int.tryParse(controller.text.trim());
                          if (parsed != null && parsed > 0) {
                            limitMb = parsed;
                          }
                          Navigator.of(dialogCtx).pop(true);
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    controller.dispose();

    if (saved == true) {
      await viewModel.updateGlobalQuota(
        QuotaConfig(
          enabled: enabled,
          limitBytes: limitMb * 1024 * 1024,
          warningPercent: warningPercent,
        ),
      );
    }
  }
}
