import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/widgets/app_card.dart';
import '../view_models/dashboard_view_model.dart';

/// Modal bottom sheet presented on first launch to guide users through
/// optional notification and battery optimization permissions in plain English.
class WelcomeOnboardingSheet extends StatelessWidget {
  const WelcomeOnboardingSheet({
    super.key,
    required this.viewModel,
    required this.onDismiss,
  });

  final DashboardViewModel viewModel;
  final VoidCallback onDismiss;

  static Future<void> show(
    BuildContext context, {
    required DashboardViewModel viewModel,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WelcomeOnboardingSheet(
        viewModel: viewModel,
        onDismiss: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final notificationsGranted = viewModel.isNotificationPermissionGranted;
        final batteryIgnored = viewModel.isBatteryOptimizationIgnored;

        return Container(
          decoration: BoxDecoration(
            color: theme.colors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: theme.colors.border.withValues(alpha: 0.6),
            ),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colors.mutedForeground.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: theme.colors.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Icon(
                          FLucideIcons.wifi,
                          color: theme.colors.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome to Hotspot Monitor',
                              style: theme.typography.display.sm.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colors.foreground,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Real-time tethering analytics & device controls.',
                              style: theme.typography.body.xs.copyWith(
                                color: theme.colors.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Setup & Background Permissions',
                    style: theme.typography.body.xs.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 1. Notifications Card
                  AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: notificationsGranted
                                ? Colors.green.withValues(alpha: 0.15)
                                : theme.colors.muted,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            notificationsGranted
                                ? FLucideIcons.check
                                : FLucideIcons.bell,
                            size: 18,
                            color: notificationsGranted
                                ? Colors.green
                                : theme.colors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Status Bar Live Speed',
                                style: theme.typography.body.sm.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colors.foreground,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Shows live upload/download speed and connected devices in the notification bar.',
                                style: theme.typography.body.xs2.copyWith(
                                  color: theme.colors.mutedForeground,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FButton(
                          variant: notificationsGranted
                              ? FButtonVariant.outline
                              : FButtonVariant.primary,
                          size: FButtonSizeVariant.sm,
                          onPress: notificationsGranted
                              ? null
                              : () => viewModel.requestNotificationPermission(),
                          child: Text(
                            notificationsGranted ? 'Enabled' : 'Allow',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 2. Battery Optimization Card
                  AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: batteryIgnored
                                ? Colors.green.withValues(alpha: 0.15)
                                : theme.colors.muted,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            batteryIgnored
                                ? FLucideIcons.check
                                : FLucideIcons.zap,
                            size: 18,
                            color: batteryIgnored
                                ? Colors.green
                                : theme.colors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Screen-Off Reliability',
                                style: theme.typography.body.sm.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colors.foreground,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Exempts the monitor from battery killing so traffic counts stay accurate when the screen locks.',
                                style: theme.typography.body.xs2.copyWith(
                                  color: theme.colors.mutedForeground,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FButton(
                          variant: batteryIgnored
                              ? FButtonVariant.outline
                              : FButtonVariant.primary,
                          size: FButtonSizeVariant.sm,
                          onPress: batteryIgnored
                              ? null
                              : () => viewModel.requestIgnoreBatteryOptimization(),
                          child: Text(
                            batteryIgnored ? 'Exempt' : 'Adjust',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 3. Privacy Guarantee Card
                  AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.colors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            FLucideIcons.shieldCheck,
                            size: 18,
                            color: theme.colors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '100% Offline & Private',
                                style: theme.typography.body.sm.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colors.foreground,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Traffic records and host logs stay entirely on your device. No cloud telemetry or third-party tracking.',
                                style: theme.typography.body.xs2.copyWith(
                                  color: theme.colors.mutedForeground,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: FButton(
                          onPress: () async {
                            await viewModel.completeOnboarding();
                            onDismiss();
                          },
                          child: const Text('Get Started'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
