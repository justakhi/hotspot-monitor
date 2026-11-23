import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/quota_progress_card.dart';
import '../../../core/widgets/update_available_dialog.dart';
import '../../../../data/services/update_checker_service.dart';
import '../../dashboard/view_models/dashboard_view_model.dart';
import '../../history/views/connection_history_screen.dart';
import '../../reports/views/reports_screen.dart';
import '../widgets/faq_dialog.dart';
import '../widgets/privacy_policy_dialog.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.viewModel});

  final DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final theme = context.theme;
        final snapshot = viewModel.snapshot;
        final caps = snapshot.capabilities;

        return FScaffold(
          childPad: false,
          header: FHeader.nested(
            title: const Text('Menu & Settings'),
            prefixes: [
              FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
            ],
          ),
          child: ListView(
            key: const Key('settings_list_view'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _SectionTitle(title: 'Pro & Licensing'),
              const SizedBox(height: 8),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          viewModel.isPro
                              ? FLucideIcons.award
                              : FLucideIcons.sparkles,
                          color: viewModel.isPro
                              ? Colors.amber
                              : theme.colors.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                viewModel.isPro
                                    ? 'Hotspot Monitor Pro Active'
                                    : 'Hotspot Monitor Pro',
                                style: theme.typography.display.sm.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colors.foreground,
                                ),
                              ),
                              Text(
                                viewModel.isPro
                                    ? 'Lifetime ad-free license active'
                                    : 'Remove all ads & support development',
                                style: theme.typography.body.xs.copyWith(
                                  color: theme.colors.mutedForeground,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (viewModel.isPro)
                          FBadge(child: const Text('PRO')),
                      ],
                    ),
                    if (!viewModel.isPro) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FButton(
                              onPress: () async {
                                final ok = await viewModel.buyPro();
                                if (!ok && context.mounted) {
                                  showFToast(
                                    context: context,
                                    icon: const Icon(FLucideIcons.info),
                                    title: const Text('Store Notice'),
                                    description: const Text(
                                      'Connecting to Google Play Billing...',
                                    ),
                                  );
                                }
                              },
                              child: const Text('Remove Ads'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FButton(
                            variant: FButtonVariant.outline,
                            onPress: () async {
                              await viewModel.restorePurchases();
                              if (context.mounted) {
                                showFToast(
                                  context: context,
                                  icon: const Icon(FLucideIcons.check),
                                  title: const Text('Restore Purchases'),
                                  description: const Text(
                                    'Querying Google Play account for prior purchases.',
                                  ),
                                );
                              }
                            },
                            child: const Text('Restore'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionTitle(title: 'Mode & Permissions'),
              const SizedBox(height: 8),
              FTileGroup(
                children: [
                  FTile(
                    prefix: Icon(
                      snapshot.isRootMode
                          ? FLucideIcons.shieldCheck
                          : FLucideIcons.shield,
                      color: snapshot.isRootMode
                          ? AppTheme.rootAccent
                          : theme.colors.mutedForeground,
                    ),
                    title: const Text('Root Access'),
                    subtitle: Text(
                      snapshot.isRootMode
                          ? 'Active · Per-device & app traffic enabled'
                          : 'Not granted · Running in Non-Root mode',
                    ),
                    suffix: snapshot.isRootMode
                        ? FBadge(child: const Text('Active'))
                        : const Icon(FLucideIcons.chevronRight),
                    onPress: snapshot.isRootMode
                        ? null
                        : () async {
                            final granted =
                                await viewModel.requestRootAccess();
                            if (context.mounted && !granted) {
                              showFToast(
                                context: context,
                                icon: const Icon(FLucideIcons.shield),
                                title: const Text('Root access not granted'),
                                description: const Text(
                                  'Approve Hotspot Monitor in Magisk / KernelSU, then tap again.',
                                ),
                              );
                            }
                          },
                  ),
                  FTile(
                    prefix: Icon(
                      FLucideIcons.activity,
                      color: caps.usageAccessGranted
                          ? AppTheme.rootAccent
                          : AppTheme.uploadColor,
                    ),
                    title: const Text('Usage Access'),
                    subtitle: Text(
                      caps.usageAccessGranted
                          ? 'Granted · Non-root session totals enabled'
                          : 'Tap to allow Usage Access in Android Settings',
                    ),
                    suffix: const Icon(FLucideIcons.chevronRight),
                    onPress: viewModel.openUsageAccessSettings,
                  ),
                  FTile(
                    prefix: const Icon(FLucideIcons.wifi),
                    title: const Text('Hotspot Interface'),
                    subtitle: Text(
                      caps.hotspotActive
                          ? '${caps.hotspotInterface ?? caps.tetherType} · ${caps.gatewayIp ?? "No IP"}/${caps.prefixLength}'
                          : 'Hotspot is currently off',
                    ),
                    suffix: FBadge(
                      variant: snapshot.probeActive
                          ? FBadgeVariant.secondary
                          : FBadgeVariant.outline,
                      child: Text(snapshot.probeActive ? 'DPI On' : 'Idle'),
                    ),
                  ),
                  FTile(
                    prefix: const Icon(FLucideIcons.power),
                    title: const Text('Portable Hotspot'),
                    subtitle: Text(
                      caps.hotspotActive
                          ? 'Hotspot is active · Tap to open settings or toggle'
                          : 'Hotspot is turned off · Tap to turn on',
                    ),
                    suffix: const Icon(FLucideIcons.externalLink),
                    onPress: viewModel.openHotspotSettings,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionTitle(title: 'Background Execution & Power'),
              const SizedBox(height: 8),
              FTileGroup(
                children: [
                  FTile(
                    prefix: const Icon(FLucideIcons.bellRing),
                    title: const Text('Keep Running in Background'),
                    subtitle: const Text(
                      'Live notification with connected count and speeds; keeps packet engine alive',
                    ),
                    suffix: FSwitch(
                      value: viewModel.isBackgroundServiceEnabled,
                      onChange: (val) => viewModel.toggleBackgroundService(val),
                    ),
                  ),
                  FTile(
                    prefix: const Icon(FLucideIcons.batteryCharging),
                    title: const Text('Battery Optimization'),
                    subtitle: Text(
                      viewModel.isBatteryOptimizationIgnored
                          ? 'Unrestricted · System will not throttle or kill background monitoring'
                          : 'Optimized · Tap to exclude from battery restrictions',
                    ),
                    suffix: FBadge(
                      variant: viewModel.isBatteryOptimizationIgnored
                          ? FBadgeVariant.secondary
                          : FBadgeVariant.outline,
                      child: Text(
                        viewModel.isBatteryOptimizationIgnored
                            ? 'Unrestricted'
                            : 'Optimized',
                      ),
                    ),
                    onPress: viewModel.requestIgnoreBatteryOptimization,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionTitle(title: 'Data Quota & Limits'),
              const SizedBox(height: 8),
              FTileGroup(
                children: [
                  FTile(
                    prefix: const Icon(FLucideIcons.gauge),
                    title: const Text('Session Data Quota'),
                    subtitle: Text(
                      viewModel.globalQuota.enabled
                          ? '${Formatters.bytes(viewModel.globalQuota.limitBytes)} budget · Warn at ${viewModel.globalQuota.warningPercent}%'
                          : 'Disabled · Tap to set a session data limit',
                    ),
                    suffix: FBadge(
                      variant: viewModel.globalQuota.enabled
                          ? FBadgeVariant.primary
                          : FBadgeVariant.secondary,
                      child: Text(
                        viewModel.globalQuota.enabled ? 'Active' : 'Off',
                      ),
                    ),
                    onPress: () =>
                        QuotaProgressCard.showEditDialog(context, viewModel),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionTitle(title: 'History & Session'),
              const SizedBox(height: 8),
              FTileGroup(
                children: [
                  FTile(
                    prefix: const Icon(FLucideIcons.barChart2),
                    title: const Text('Usage Reports & History'),
                    subtitle: const Text(
                      'Hourly, daily, monthly, and yearly per-device usage',
                    ),
                    suffix: const Icon(FLucideIcons.chevronRight),
                    onPress: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReportsScreen(viewModel: viewModel),
                        ),
                      );
                    },
                  ),
                  FTile(
                    prefix: const Icon(FLucideIcons.history),
                    title: const Text('Connection History'),
                    subtitle: const Text(
                      'All old & past devices seen on your hotspot',
                    ),
                    suffix: const Icon(FLucideIcons.chevronRight),
                    onPress: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ConnectionHistoryScreen(viewModel: viewModel),
                        ),
                      );
                    },
                  ),
                  FTile(
                    prefix: const Icon(FLucideIcons.share2),
                    title: const Text('Export Connection Logs'),
                    subtitle: const Text(
                      'Export device connection history and traffic logs as CSV',
                    ),
                    suffix: const Icon(FLucideIcons.chevronRight),
                    onPress: () => viewModel.exportConnectionLogs(),
                  ),
                  FTile(
                    prefix: const Icon(FLucideIcons.rotateCcw),
                    title: const Text('Reset Session Counters'),
                    subtitle: const Text(
                      'Clears current live session counters (keeps saved history)',
                    ),
                    onPress: () async {
                      await viewModel.resetSession();
                      if (context.mounted) {
                        showFToast(
                          context: context,
                          icon: const Icon(FLucideIcons.rotateCcw),
                          title: const Text('Session reset'),
                        );
                      }
                    },
                  ),
                  FTile(
                    prefix: Icon(
                      FLucideIcons.trash2,
                      color: theme.colors.destructive,
                    ),
                    title: const Text('Clear Saved History'),
                    subtitle: const Text(
                      'Deletes all stored hourly, daily, and monthly records',
                    ),
                    onPress: () async {
                      await viewModel.clearHistory();
                      if (context.mounted) {
                        showFToast(
                          context: context,
                          icon: const Icon(FLucideIcons.trash2),
                          title: const Text('Saved history cleared'),
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionTitle(title: 'How Detection Works'),
              const SizedBox(height: 8),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device & App Visibility',
                      style: theme.typography.body.sm.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• Device names come from DHCP hostnames, mDNS, NetBIOS, and MAC OUI vendor lookup. Phones using Randomized MAC hide their hardware vendor.\n'
                      '• App attribution passively inspects DNS (UDP/TCP), multi-packet TLS SNI, QUIC Initial SNI, HTTP Host headers, and service IP ranges, saving learned IP-to-domain mappings privately inside app storage.\n'
                      '• All root inspection is strictly read-only: no firewall rules, certificates, or Android system files are ever modified.\n'
                      '• Full HTTPS URLs and payloads (such as exact video IDs or file types) remain encrypted between connected devices and the servers they visit.',
                      style: theme.typography.body.xs.copyWith(
                        color: theme.colors.mutedForeground,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionTitle(title: 'Help & Support'),
              const SizedBox(height: 8),
              FTileGroup(
                children: [
                  FTile(
                    prefix: const Icon(FLucideIcons.circleHelp),
                    title: const Text('Frequently Asked Questions'),
                    subtitle: const Text(
                      'Root vs non-root, randomized MACs & quotas',
                    ),
                    suffix: const Icon(FLucideIcons.chevronRight),
                    onPress: () => FaqDialog.show(context),
                  ),
                  FTile(
                    prefix: const Icon(FLucideIcons.star),
                    title: const Text('Rate on Google Play'),
                    subtitle: const Text('Help us improve with a review'),
                    suffix: const Icon(FLucideIcons.externalLink),
                    onPress: () => viewModel.openUrl(
                      'market://details?id=com.aplabs.hotspotmonitor',
                    ),
                  ),
                  FTile(
                    prefix: const Icon(FLucideIcons.shieldCheck),
                    title: const Text('Privacy Policy'),
                    subtitle: const Text(
                      'Offline data & zero telemetry commitment',
                    ),
                    suffix: const Icon(FLucideIcons.chevronRight),
                    onPress: () => PrivacyPolicyDialog.show(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionTitle(title: 'About'),
              const SizedBox(height: 8),
              FTileGroup(
                children: [
                  FTile(
                    prefix: const Icon(FLucideIcons.sparkles),
                    title: const Text('Check for Updates'),
                    subtitle: Text(
                      'Installed version: v${UpdateCheckerService.currentVersion}',
                    ),
                    suffix: const Icon(FLucideIcons.chevronRight),
                    onPress: () async {
                      showFToast(
                        context: context,
                        icon: const Icon(FLucideIcons.loader),
                        title: const Text('Checking for updates...'),
                      );
                      final update = await viewModel.checkForUpdate();
                      if (!context.mounted) return;
                      if (update != null && update.isNewer) {
                        UpdateAvailableDialog.show(
                          context,
                          release: update,
                          onDownload: () => viewModel.openUrl(
                            update.releasePageUrl.isNotEmpty
                                ? update.releasePageUrl
                                : update.downloadUrl,
                          ),
                          onDismiss: () => viewModel.dismissUpdate(),
                        );
                      } else {
                        showFToast(
                          context: context,
                          icon: const Icon(FLucideIcons.check),
                          title: const Text('App is up to date'),
                          description: Text(
                            'v${UpdateCheckerService.currentVersion} is the latest release.',
                          ),
                        );
                      }
                    },
                  ),
                  FTile(
                    prefix: const Icon(FLucideIcons.building2),
                    title: const Text('AP Labs'),
                    subtitle: const Text('techyke.in'),
                    suffix: const Icon(FLucideIcons.externalLink),
                    onPress: () => viewModel.openUrl('https://techyke.in'),
                  ),
                  FTile(
                    prefix: const Icon(FLucideIcons.send),
                    title: const Text('Telegram'),
                    subtitle: const Text('@God_Asura'),
                    suffix: const Icon(FLucideIcons.externalLink),
                    onPress: () =>
                        viewModel.openUrl('https://t.me/God_Asura'),
                  ),
                  FTile(
                    prefix: const Icon(FLucideIcons.mail),
                    title: const Text('Contact Email'),
                    subtitle: const Text('contact@techyke.in'),
                    suffix: const Icon(FLucideIcons.copy),
                    onPress: () async {
                      await Clipboard.setData(
                        const ClipboardData(text: 'contact@techyke.in'),
                      );
                      if (context.mounted) {
                        showFToast(
                          context: context,
                          icon: const Icon(FLucideIcons.check),
                          title: const Text('Email copied'),
                          description: const Text('contact@techyke.in'),
                        );
                      }
                    },
                  ),
                  FTile(
                    prefix: const Icon(FLucideIcons.scale),
                    title: Text('Hotspot Monitor v${UpdateCheckerService.currentVersion}'),
                    subtitle: const Text(
                      'Free for personal and network management use',
                    ),
                    onPress: () => viewModel.openUrl('https://techyke.in'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Text(
                  'Copyright (c) 2026 AP Labs. Provided for educational use and managing networks you own; AP Labs is not responsible for misuse.',
                  style: theme.typography.body.xs2.copyWith(
                    color: theme.colors.mutedForeground,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: theme.typography.body.xs2.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: theme.colors.mutedForeground,
        ),
      ),
    );
  }
}
