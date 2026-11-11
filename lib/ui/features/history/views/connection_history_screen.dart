import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../../domain/models/history_report.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../dashboard/view_models/dashboard_view_model.dart';
import '../../device_detail/views/device_detail_screen.dart';

class ConnectionHistoryScreen extends StatefulWidget {
  const ConnectionHistoryScreen({super.key, required this.viewModel});

  final DashboardViewModel viewModel;

  @override
  State<ConnectionHistoryScreen> createState() =>
      _ConnectionHistoryScreenState();
}

class _ConnectionHistoryScreenState extends State<ConnectionHistoryScreen> {
  List<DeviceHistorySummary> _devices = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    widget.viewModel.addListener(_onModelChanged);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onModelChanged);
    super.dispose();
  }

  void _onModelChanged() {
    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loading = true);
    }
    final list = await widget.viewModel.getAllDeviceHistory();
    if (mounted) {
      setState(() {
        _devices = list;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final onlineIds = widget.viewModel.snapshot.devices
        .where((d) => d.isOnline)
        .map((d) => d.id)
        .toSet();
    final tabular = [const FontFeature.tabularFigures()];

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: const Text('Connection History'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
      ),
      child: _loading && _devices.isEmpty
          ? const Center(child: FCircularProgress())
          : _devices.isEmpty
          ? ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                AppCard(
                  child: Column(
                    children: [
                      Icon(
                        FLucideIcons.history,
                        size: 28,
                        color: theme.colors.mutedForeground,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No past device connections yet',
                        style: theme.typography.body.sm.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colors.foreground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Devices that connect to your hotspot are saved here automatically with timestamps and total data usage.',
                        textAlign: TextAlign.center,
                        style: theme.typography.body.xs.copyWith(
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : ListView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 2, right: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'All Seen Devices (${_devices.length})',
                        style: theme.typography.body.xs.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                      Text(
                        'Sorted by most recent',
                        style: theme.typography.body.xs2.copyWith(
                          color: theme.colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final device in _devices) ...[
                  _HistoryDeviceCard(
                    device: device,
                    isOnline: onlineIds.contains(device.deviceId),
                    tabular: tabular,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DeviceDetailScreen(
                            deviceId: device.deviceId,
                            viewModel: widget.viewModel,
                            initialRange: HistoryRange.all,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }
}

class _HistoryDeviceCard extends StatelessWidget {
  const _HistoryDeviceCard({
    required this.device,
    required this.isOnline,
    required this.tabular,
    required this.onTap,
  });

  final DeviceHistorySummary device;
  final bool isOnline;
  final List<FontFeature> tabular;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final hasHost = device.displayName != device.ip;
    final subtitle = hasHost
        ? '${device.ip} · ${device.vendor}${device.mac != null ? ' · ${device.mac}' : ''}'
        : '${device.vendor}${device.mac != null ? ' · ${device.mac}' : ''}';

    return AppCard(
      onPress: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isOnline
                      ? AppTheme.rootAccent.withValues(alpha: 0.14)
                      : theme.colors.secondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  FLucideIcons.smartphone,
                  size: 17,
                  color: isOnline
                      ? AppTheme.rootAccent
                      : theme.colors.foreground,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.typography.body.sm.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colors.foreground,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isOnline
                                ? AppTheme.rootAccent.withValues(alpha: 0.14)
                                : theme.colors.muted,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isOnline
                                ? 'Connected'
                                : Formatters.relativeAgo(device.lastSeenMs),
                            style: theme.typography.body.xs2.copyWith(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isOnline
                                  ? AppTheme.rootAccent
                                  : theme.colors.mutedForeground,
                            ),
                          ),
                        ),
                      ],
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
              const SizedBox(width: 8),
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
                  Icon(
                    FLucideIcons.chevronRight,
                    size: 14,
                    color: theme.colors.mutedForeground,
                  ),
                ],
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: FDivider(),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '↓ ${Formatters.bytes(device.downloadBytes)} · ↑ ${Formatters.bytes(device.uploadBytes)}',
                style: theme.typography.body.xs2.copyWith(
                  color: theme.colors.mutedForeground,
                  fontFeatures: tabular,
                ),
              ),
              Text(
                'Last: ${Formatters.shortTimestamp(device.lastSeenMs)}',
                style: theme.typography.body.xs2.copyWith(
                  color: theme.colors.mutedForeground,
                  fontFeatures: tabular,
                ),
              ),
            ],
          ),
          if (device.firstSeenMs > 0) ...[
            const SizedBox(height: 3),
            Text(
              'First connected: ${Formatters.fullDateTime(device.firstSeenMs)}',
              style: theme.typography.body.xs2.copyWith(
                color: theme.colors.mutedForeground,
                fontFeatures: tabular,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
