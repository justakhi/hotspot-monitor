import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_card.dart';
import '../../dashboard/view_models/dashboard_view_model.dart';
import '../../history/views/connection_history_screen.dart';
import '../../reports/views/reports_screen.dart';

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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
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
              _SectionTitle(title: 'About & Credits'),
              const SizedBox(height: 8),
              FTileGroup(
                children: [
                  FTile(
                    prefix: const Icon(FLucideIcons.building2),
                    title: const Text('AP Labs · Akshay Kumar'),
                    subtitle: const Text('techyke.in · @justakhi'),
                    suffix: const Icon(FLucideIcons.externalLink),
                    onPress: () => viewModel.openUrl('https://techyke.in'),
                  ),
                  FTile(
                    prefix: const Icon(FLucideIcons.code),
                    title: const Text('Source Code & Releases'),
                    subtitle: const Text('github.com/justakhi/hotspot-monitor'),
                    suffix: const Icon(FLucideIcons.externalLink),
                    onPress: () => viewModel.openUrl(
                      'https://github.com/justakhi/hotspot-monitor',
                    ),
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
                    title: const Text('Hotspot Monitor v1.0.0'),
                    subtitle: const Text(
                      'PolyForm Noncommercial 1.0.0 · Free for personal use',
                    ),
                    onPress: () => viewModel.openUrl(
                      'https://github.com/justakhi/hotspot-monitor/blob/main/LICENSE',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppCard(
                child: Text(
                  'Copyright (c) 2026 AP Labs (Akshay Kumar). Provided for educational use and managing networks you own; AP Labs is not responsible for misuse.',
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
