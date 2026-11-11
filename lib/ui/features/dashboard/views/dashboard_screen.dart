import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../../domain/models/connected_device.dart';
import '../../../../domain/models/history_report.dart';
import '../../../../domain/models/hotspot_snapshot.dart';
import '../../../../domain/models/service_usage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/usage_breakdown_bar.dart';
import '../../device_detail/views/device_detail_screen.dart';
import '../../history/views/connection_history_screen.dart';
import '../../reports/views/reports_screen.dart';
import '../../service_detail/views/service_detail_screen.dart';
import '../../settings/views/settings_screen.dart';
import '../view_models/dashboard_view_model.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.viewModel});

  final DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final snapshot = viewModel.snapshot;
        final caps = snapshot.capabilities;
        final connectedDevices = snapshot.devices
            .where((d) => d.isOnline)
            .toList(growable: false);
        final recentDisconnected = _collectRecentDisconnected(
          snapshot,
          viewModel.knownDeviceHistory,
        );

        return FScaffold(
          childPad: false,
          header: FHeader(
            title: const Text('Hotspot Monitor'),
            suffixes: [
              FHeaderAction(
                semanticsLabel: 'Usage reports',
                icon: const Icon(FLucideIcons.barChart2),
                onPress: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReportsScreen(viewModel: viewModel),
                    ),
                  );
                },
              ),
              FHeaderAction(
                semanticsLabel: 'Menu and settings',
                icon: const Icon(FLucideIcons.menu),
                onPress: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsScreen(viewModel: viewModel),
                    ),
                  );
                },
              ),
            ],
          ),
          child: viewModel.isInitializing
              ? const Center(child: FCircularProgress())
              : ListView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    if (!caps.usageAccessGranted && !snapshot.isRootMode) ...[
                      _UsagePromptBanner(
                        onOpenSettings: viewModel.openUsageAccessSettings,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (snapshot.isRootMode && snapshot.probeError != null) ...[
                      FAlert(
                        variant: FAlertVariant.destructive,
                        icon: const Icon(FLucideIcons.circleAlert),
                        title: const Text('Packet Probe Notice'),
                        subtitle: Text(snapshot.probeError!),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _SessionOverviewCard(
                      snapshot: snapshot,
                      connectedCount: connectedDevices.length,
                    ),
                    if (snapshot.isRootMode &&
                        snapshot.topServices.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _GlobalServicesCard(
                        snapshot: snapshot,
                        viewModel: viewModel,
                      ),
                    ],
                    const SizedBox(height: 18),
                    _SectionHeader(
                      title: 'Connected Devices',
                      trailing: '${connectedDevices.length}',
                    ),
                    const SizedBox(height: 8),
                    if (connectedDevices.isEmpty)
                      _EmptyDevicesCard(snapshot: snapshot)
                    else
                      for (final device in connectedDevices)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DeviceCard(
                            device: device,
                            isRoot: snapshot.isRootMode,
                            sessionTotalBytes: snapshot.sessionTotalBytes,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => DeviceDetailScreen(
                                    deviceId: device.id,
                                    viewModel: viewModel,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    if (recentDisconnected.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _SectionHeader(
                        title: 'Recently Disconnected (1h)',
                        trailing: '${recentDisconnected.length}',
                        actionLabel: 'All History',
                        onAction: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ConnectionHistoryScreen(
                                viewModel: viewModel,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      for (final item in recentDisconnected)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RecentDisconnectedCard(
                            item: item,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => DeviceDetailScreen(
                                    deviceId: item.id,
                                    viewModel: viewModel,
                                    initialRange: HistoryRange.day,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ] else if (viewModel.knownDeviceHistory.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      AppCard(
                        onPress: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ConnectionHistoryScreen(
                                viewModel: viewModel,
                              ),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            Icon(
                              FLucideIcons.history,
                              size: 18,
                              color: context.theme.colors.mutedForeground,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Connection History',
                                    style: context.theme.typography.body.sm
                                        .copyWith(
                                          fontWeight: FontWeight.w700,
                                          color:
                                              context.theme.colors.foreground,
                                        ),
                                  ),
                                  Text(
                                    '${viewModel.knownDeviceHistory.length} past device(s) saved',
                                    style: context.theme.typography.body.xs2
                                        .copyWith(
                                          color: context
                                              .theme
                                              .colors
                                              .mutedForeground,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              FLucideIcons.chevronRight,
                              size: 16,
                              color: context.theme.colors.mutedForeground,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  List<_RecentDisconnectedItem> _collectRecentDisconnected(
    HotspotSnapshot snapshot,
    List<DeviceHistorySummary> dbHistory,
  ) {
    final nowMs = snapshot.timestampMs > 0
        ? snapshot.timestampMs
        : DateTime.now().millisecondsSinceEpoch;
    const oneHourMs = 3600 * 1000;
    final onlineIds = snapshot.devices
        .where((d) => d.isOnline)
        .map((d) => d.id)
        .toSet();
    final dbById = <String, DeviceHistorySummary>{
      for (final h in dbHistory) h.deviceId: h,
    };
    final map = <String, _RecentDisconnectedItem>{};

    for (final d in snapshot.devices) {
      if (d.isOnline || d.id == '_hotspot_total_') continue;
      final h = dbById[d.id];
      final effectiveLastSeen = (h != null && h.lastSeenMs > d.lastSeenMs)
          ? h.lastSeenMs
          : d.lastSeenMs;
      if (effectiveLastSeen <= 0 || (nowMs - effectiveLastSeen) > oneHourMs) {
        continue;
      }
      final useDbTotals = d.totalBytes == 0 && h != null && h.totalBytes > 0;
      map[d.id] = _RecentDisconnectedItem(
        id: d.id,
        displayName: d.displayName,
        ip: d.ip.isNotEmpty ? d.ip : (h?.ip ?? ''),
        mac: d.mac ?? h?.mac,
        vendor: d.vendor != 'Unknown Device' ? d.vendor : (h?.vendor ?? d.vendor),
        lastSeenMs: effectiveLastSeen,
        downloadBytes: useDbTotals ? h.downloadBytes : d.downloadBytes,
        uploadBytes: useDbTotals ? h.uploadBytes : d.uploadBytes,
      );
    }

    for (final h in dbHistory) {
      if (onlineIds.contains(h.deviceId) ||
          h.deviceId == '_hotspot_total_' ||
          map.containsKey(h.deviceId)) {
        continue;
      }
      if (h.lastSeenMs <= 0 || (nowMs - h.lastSeenMs) > oneHourMs) continue;
      map[h.deviceId] = _RecentDisconnectedItem(
        id: h.deviceId,
        displayName: h.displayName,
        ip: h.ip,
        mac: h.mac,
        vendor: h.vendor,
        lastSeenMs: h.lastSeenMs,
        downloadBytes: h.downloadBytes,
        uploadBytes: h.uploadBytes,
      );
    }

    final list = map.values.toList()
      ..sort((a, b) => b.lastSeenMs.compareTo(a.lastSeenMs));
    return list;
  }
}

class _RecentDisconnectedItem {
  const _RecentDisconnectedItem({
    required this.id,
    required this.displayName,
    required this.ip,
    required this.mac,
    required this.vendor,
    required this.lastSeenMs,
    required this.downloadBytes,
    required this.uploadBytes,
  });

  final String id;
  final String displayName;
  final String ip;
  final String? mac;
  final String vendor;
  final int lastSeenMs;
  final int downloadBytes;
  final int uploadBytes;

  int get totalBytes => downloadBytes + uploadBytes;
}

class _UsagePromptBanner extends StatelessWidget {
  const _UsagePromptBanner({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return AppCard(
      child: Row(
        children: [
          Icon(
            FLucideIcons.activity,
            size: 20,
            color: theme.colors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Usage Access Required',
                  style: theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colors.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Allow Usage Access to read session hotspot totals.',
                  style: theme.typography.body.xs.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FButton(
            size: FButtonSizeVariant.xs,
            mainAxisSize: MainAxisSize.min,
            onPress: onOpenSettings,
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }
}

class _SessionOverviewCard extends StatelessWidget {
  const _SessionOverviewCard({
    required this.snapshot,
    required this.connectedCount,
  });

  final HotspotSnapshot snapshot;
  final int connectedCount;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final caps = snapshot.capabilities;
    final active = caps.hotspotActive;
    final tabular = [const FontFeature.tabularFigures()];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? AppTheme.rootAccent
                      : theme.colors.mutedForeground,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  active ? 'Hotspot On' : 'Hotspot Off',
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colors.foreground,
                  ),
                ),
              ),
              if (caps.hotspotInterface != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colors.secondary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    caps.hotspotInterface!,
                    style: theme.typography.body.xs2.copyWith(
                      color: theme.colors.mutedForeground,
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabular,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              FBadge(
                variant: FBadgeVariant.outline,
                child: Text(
                  Formatters.durationSince(
                    snapshot.sessionStartMs,
                    nowMs: snapshot.timestampMs > 0
                        ? snapshot.timestampMs
                        : null,
                  ),
                  style: TextStyle(fontFeatures: tabular),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session Data',
                      style: theme.typography.body.xs2.copyWith(
                        color: theme.colors.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.bytes(snapshot.sessionTotalBytes),
                      style: theme.typography.display.xl2.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colors.foreground,
                        fontFeatures: tabular,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Connected',
                    style: theme.typography.body.xs2.copyWith(
                      color: theme.colors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$connectedCount',
                    style: theme.typography.display.lg.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colors.foreground,
                      fontFeatures: tabular,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          UsageBreakdownBar(
            height: 6,
            segments: [
              BarSegment(
                label: 'Download',
                value: snapshot.sessionDownloadBytes,
                color: AppTheme.downloadColor,
              ),
              BarSegment(
                label: 'Upload',
                value: snapshot.sessionUploadBytes,
                color: AppTheme.uploadColor,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    FLucideIcons.arrowDown,
                    size: 13,
                    color: AppTheme.downloadColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${Formatters.bytes(snapshot.sessionDownloadBytes)} (${Formatters.speed(snapshot.liveDownloadBps)})',
                    style: theme.typography.body.xs.copyWith(
                      color: AppTheme.downloadColor,
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabular,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    FLucideIcons.arrowUp,
                    size: 13,
                    color: AppTheme.uploadColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${Formatters.bytes(snapshot.sessionUploadBytes)} (${Formatters.speed(snapshot.liveUploadBps)})',
                    style: theme.typography.body.xs.copyWith(
                      color: AppTheme.uploadColor,
                      fontWeight: FontWeight.w600,
                      fontFeatures: tabular,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlobalServicesCard extends StatelessWidget {
  const _GlobalServicesCard({required this.snapshot, required this.viewModel});

  final HotspotSnapshot snapshot;
  final DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final significant = snapshot.topServices
        .where((s) => s.totalBytes >= 1024)
        .take(3)
        .toList(growable: false);
    final topServices = significant.isNotEmpty
        ? significant
        : snapshot.topServices.take(3).toList(growable: false);
    final total = snapshot.topServices.fold<int>(
      0,
      (sum, s) => sum + s.totalBytes,
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Top Traffic',
                style: theme.typography.body.sm.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colors.foreground,
                ),
              ),
              Text(
                Formatters.bytes(total),
                style: theme.typography.body.xs.copyWith(
                  color: theme.colors.mutedForeground,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          UsageBreakdownBar(
            height: 6,
            segments: topServices
                .map(
                  (s) => BarSegment(
                    label: s.displayName,
                    value: s.totalBytes,
                    color: AppTheme.categoryColor(s.category),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < topServices.length; i++) ...[
            _CompactServiceRow(
              service: topServices[i],
              totalBytes: total,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ServiceDetailScreen(
                      service: topServices[i],
                      totalContextBytes: total,
                      viewModel: viewModel,
                    ),
                  ),
                );
              },
            ),
            if (i < topServices.length - 1) const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

class _CompactServiceRow extends StatelessWidget {
  const _CompactServiceRow({
    required this.service,
    required this.totalBytes,
    required this.onTap,
  });

  final ServiceUsage service;
  final int totalBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final color = AppTheme.categoryColor(service.category);
    final pct = totalBytes > 0
        ? ((service.totalBytes / totalBytes) * 100).round()
        : 0;

    return FTappable(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                service.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.body.xs.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colors.foreground,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$pct%',
              style: theme.typography.body.xs2.copyWith(
                color: theme.colors.mutedForeground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 70,
              child: Text(
                Formatters.bytes(service.totalBytes),
                textAlign: TextAlign.end,
                style: theme.typography.body.xs.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colors.foreground,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              FLucideIcons.chevronRight,
              size: 13,
              color: theme.colors.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.trailing,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String trailing;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Text(
            title,
            style: theme.typography.body.sm.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colors.foreground,
            ),
          ),
          const SizedBox(width: 8),
          FBadge(
            variant: FBadgeVariant.secondary,
            child: Text(trailing),
          ),
          const Spacer(),
          if (actionLabel != null && onAction != null)
            FTappable(
              onPress: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: theme.typography.body.xs.copyWith(
                      color: theme.colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    FLucideIcons.chevronRight,
                    size: 14,
                    color: theme.colors.primary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentDisconnectedCard extends StatelessWidget {
  const _RecentDisconnectedCard({required this.item, required this.onTap});

  final _RecentDisconnectedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tabular = [const FontFeature.tabularFigures()];
    final hasHost = item.displayName != item.ip;
    final subtitle = hasHost
        ? '${item.ip} · ${item.vendor}${item.mac != null ? ' · ${item.mac}' : ''}'
        : '${item.vendor}${item.mac != null ? ' · ${item.mac}' : ''}';

    return AppCard(
      onPress: onTap,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colors.muted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              FLucideIcons.wifiOff,
              size: 16,
              color: theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colors.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.body.xs2.copyWith(
                    color: theme.colors.mutedForeground,
                    fontFeatures: tabular,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Disconnected ${Formatters.relativeAgo(item.lastSeenMs)} · ${Formatters.shortTimestamp(item.lastSeenMs)}',
                  style: theme.typography.body.xs2.copyWith(
                    color: theme.colors.mutedForeground,
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Formatters.bytes(item.totalBytes),
                style: theme.typography.body.xs.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colors.foreground,
                  fontFeatures: tabular,
                ),
              ),
              const SizedBox(height: 2),
              Icon(
                FLucideIcons.chevronRight,
                size: 14,
                color: theme.colors.mutedForeground,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyDevicesCard extends StatelessWidget {
  const _EmptyDevicesCard({required this.snapshot});

  final HotspotSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final active = snapshot.capabilities.hotspotActive;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Icon(
              active ? FLucideIcons.wifi : FLucideIcons.wifiOff,
              size: 28,
              color: theme.colors.mutedForeground,
            ),
            const SizedBox(height: 10),
            Text(
              active
                  ? 'Waiting for connected devices'
                  : 'Turn on Mobile Hotspot',
              style: theme.typography.body.sm.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colors.foreground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              active
                  ? 'Devices will appear automatically as they connect or exchange packets.'
                  : 'Connected devices and usage details will show up once hotspot is enabled.',
              textAlign: TextAlign.center,
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.isRoot,
    required this.sessionTotalBytes,
    required this.onTap,
  });

  final ConnectedDevice device;
  final bool isRoot;
  final int sessionTotalBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final share = sessionTotalBytes > 0
        ? (device.totalBytes / sessionTotalBytes).clamp(0.0, 1.0)
        : 0.0;
    final topServices = device.services
        .where((s) => s.totalBytes >= 1024)
        .take(2)
        .toList(growable: false);
    final displayServices = topServices.isNotEmpty
        ? topServices
        : device.services.take(2).toList(growable: false);
    final tabular = [const FontFeature.tabularFigures()];

    final hasCustomOrHost = device.displayName != device.ip;
    final subtitle = isRoot
        ? (hasCustomOrHost
              ? '${device.ip} · ${device.vendor}${device.mac != null ? ' · ${device.mac}' : ''}'
              : '${device.vendor}${device.mac != null ? ' · ${device.mac}' : ''}')
        : device.ip;

    return AppCard(
      onPress: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: theme.colors.secondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      FLucideIcons.smartphone,
                      size: 18,
                      color: theme.colors.foreground,
                    ),
                  ),
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: device.isOnline
                            ? AppTheme.rootAccent
                            : theme.colors.mutedForeground,
                        border: Border.all(
                          color: theme.colors.card,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.body.sm.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.body.xs2.copyWith(
                        color: theme.colors.mutedForeground,
                        fontFeatures: tabular,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (isRoot)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Formatters.bytes(device.totalBytes),
                      style: theme.typography.body.sm.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colors.foreground,
                        fontFeatures: tabular,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.speed(device.currentTotalBps),
                      style: theme.typography.body.xs2.copyWith(
                        color: AppTheme.downloadColor,
                        fontFeatures: tabular,
                      ),
                    ),
                  ],
                )
              else
                Icon(
                  FLucideIcons.chevronRight,
                  size: 16,
                  color: theme.colors.mutedForeground,
                ),
            ],
          ),
          if (isRoot) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 5,
                backgroundColor: theme.colors.muted,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppTheme.downloadColor,
                ),
              ),
            ),
            if (displayServices.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final svc in displayServices)
                    _CompactServiceChip(service: svc, tabular: tabular),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _CompactServiceChip extends StatelessWidget {
  const _CompactServiceChip({
    required this.service,
    required this.tabular,
  });

  final ServiceUsage service;
  final List<FontFeature> tabular;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final catColor = AppTheme.categoryColor(service.category);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: catColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: catColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${service.displayName} · ${Formatters.bytes(service.totalBytes)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.body.xs2.copyWith(
                color: catColor,
                fontWeight: FontWeight.w600,
                fontFeatures: tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
