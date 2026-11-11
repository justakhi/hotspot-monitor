import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../../domain/models/history_report.dart';
import '../../../../domain/models/service_usage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/usage_breakdown_bar.dart';
import '../../../core/widgets/usage_timeline_chart.dart';
import '../../dashboard/view_models/dashboard_view_model.dart';
import '../../device_detail/views/device_detail_screen.dart';
import '../../service_detail/views/service_detail_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.viewModel});

  final DashboardViewModel viewModel;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  HistoryRange _range = HistoryRange.day;
  String? _selectedDeviceId;
  UsageReport? _report;
  List<DeviceHistorySummary> _knownDevices = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadKnownDevices();
    _loadReport();
    widget.viewModel.addListener(_onModelChanged);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onModelChanged);
    super.dispose();
  }

  void _onModelChanged() {
    _loadReport(silent: true);
  }

  Future<void> _loadKnownDevices() async {
    final allReport = await widget.viewModel.getUsageReport(HistoryRange.all);
    if (mounted) {
      setState(() {
        _knownDevices = allReport.devices;
      });
    }
  }

  Future<void> _loadReport({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loading = true);
    }
    final report = await widget.viewModel.getUsageReport(
      _range,
      deviceId: _selectedDeviceId,
    );
    if (mounted) {
      setState(() {
        _report = report;
        if (_selectedDeviceId == null && report.devices.isNotEmpty) {
          _knownDevices = _mergeKnownDevices(_knownDevices, report.devices);
        }
        _loading = false;
      });
    }
  }

  List<DeviceHistorySummary> _mergeKnownDevices(
    List<DeviceHistorySummary> existing,
    List<DeviceHistorySummary> latest,
  ) {
    final map = <String, DeviceHistorySummary>{};
    for (final d in existing) {
      map[d.deviceId] = d;
    }
    for (final d in latest) {
      map[d.deviceId] = d;
    }
    return map.values.toList()
      ..sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
  }

  List<({String id, String label})> _buildFilterChoices(UsageReport report) {
    final map = <String, String>{};
    for (final d in _knownDevices) {
      map[d.deviceId] = d.displayName;
    }
    for (final d in report.devices) {
      map[d.deviceId] = d.displayName;
    }
    for (final d in widget.viewModel.snapshot.devices) {
      map.putIfAbsent(d.id, () => d.displayName);
    }
    return map.entries
        .map((e) => (id: e.key, label: e.value))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final report = _report ?? UsageReport.empty;
    final tabular = [const FontFeature.tabularFigures()];
    final deviceChoices = _buildFilterChoices(report);
    final selectedDeviceMeta = _selectedDeviceId == null
        ? null
        : report.devices.where((d) => d.deviceId == _selectedDeviceId).firstOrNull ??
            _knownDevices.where((d) => d.deviceId == _selectedDeviceId).firstOrNull;

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: const Text('Usage Reports'),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
      ),
      child: ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final r in HistoryRange.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FButton(
                      size: FButtonSizeVariant.xs,
                      variant: r == _range
                          ? FButtonVariant.primary
                          : FButtonVariant.outline,
                      mainAxisSize: MainAxisSize.min,
                      onPress: () {
                        setState(() => _range = r);
                        _loadReport();
                      },
                      child: Text(r.shortLabel),
                    ),
                  ),
              ],
            ),
          ),
          if (deviceChoices.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FButton(
                      size: FButtonSizeVariant.xs,
                      variant: _selectedDeviceId == null
                          ? FButtonVariant.primary
                          : FButtonVariant.outline,
                      mainAxisSize: MainAxisSize.min,
                      onPress: () {
                        setState(() => _selectedDeviceId = null);
                        _loadReport();
                      },
                      child: const Text('All Devices'),
                    ),
                  ),
                  for (final choice in deviceChoices)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FButton(
                        size: FButtonSizeVariant.xs,
                        variant: _selectedDeviceId == choice.id
                            ? FButtonVariant.primary
                            : FButtonVariant.outline,
                        mainAxisSize: MainAxisSize.min,
                        onPress: () {
                          setState(() => _selectedDeviceId = choice.id);
                          _loadReport();
                        },
                        child: Text(choice.label),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_loading && _report == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: FCircularProgress()),
            )
          else ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          selectedDeviceMeta != null
                              ? '${selectedDeviceMeta.displayName} · ${_range.title}'
                              : _range.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.typography.body.sm.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colors.foreground,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (selectedDeviceMeta != null &&
                          selectedDeviceMeta.deviceId != '_hotspot_total_')
                        FTappable(
                          onPress: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => DeviceDetailScreen(
                                  deviceId: selectedDeviceMeta.deviceId,
                                  viewModel: widget.viewModel,
                                  initialRange: _range,
                                ),
                              ),
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Device Profile',
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
                        )
                      else
                        Text(
                          '${report.devices.length} devices',
                          style: theme.typography.body.xs.copyWith(
                            color: theme.colors.mutedForeground,
                            fontFeatures: tabular,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Formatters.rangeWindow(
                      _range,
                      firstSeenMs: report.devices
                          .map((d) => d.firstSeenMs)
                          .where((ms) => ms > 0)
                          .fold<int?>(
                            null,
                            (min, ms) => min == null || ms < min ? ms : min,
                          ),
                    ),
                    style: theme.typography.body.xs2.copyWith(
                      color: theme.colors.mutedForeground,
                      fontFeatures: tabular,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    Formatters.bytes(report.totalBytes),
                    style: theme.typography.display.xl2.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colors.foreground,
                      fontFeatures: tabular,
                    ),
                  ),
                  const SizedBox(height: 12),
                  UsageBreakdownBar(
                    height: 6,
                    segments: [
                      BarSegment(
                        label: 'Download',
                        value: report.totalDownloadBytes,
                        color: AppTheme.downloadColor,
                      ),
                      BarSegment(
                        label: 'Upload',
                        value: report.totalUploadBytes,
                        color: AppTheme.uploadColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '↓ ${Formatters.bytes(report.totalDownloadBytes)}',
                        style: theme.typography.body.xs.copyWith(
                          color: AppTheme.downloadColor,
                          fontWeight: FontWeight.w600,
                          fontFeatures: tabular,
                        ),
                      ),
                      Text(
                        '↑ ${Formatters.bytes(report.totalUploadBytes)}',
                        style: theme.typography.body.xs.copyWith(
                          color: AppTheme.uploadColor,
                          fontWeight: FontWeight.w600,
                          fontFeatures: tabular,
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: FDivider(),
                  ),
                  UsageTimelineChart(points: report.timeline, range: _range),
                ],
              ),
            ),
            if (_selectedDeviceId == null) ...[
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Device-Wise Usage History',
                        overflow: TextOverflow.ellipsis,
                        style: theme.typography.body.sm.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colors.foreground,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FBadge(
                      variant: FBadgeVariant.secondary,
                      child: Text('${report.devices.length}'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (report.devices.isEmpty)
                AppCard(
                  child: Text(
                    'No device usage saved in this period yet.',
                    style: theme.typography.body.xs.copyWith(
                      color: theme.colors.mutedForeground,
                    ),
                  ),
                )
              else
                for (var i = 0; i < report.devices.length; i++) ...[
                  _DeviceWiseHistoryCard(
                    device: report.devices[i],
                    totalPeriodBytes: report.totalBytes,
                    deviceServices:
                        report.servicesByDevice[report.devices[i].deviceId] ??
                        const [],
                    tabular: tabular,
                    onFilterDevice: () {
                      setState(
                        () => _selectedDeviceId = report.devices[i].deviceId,
                      );
                      _loadReport();
                    },
                    onOpenFullDevice:
                        report.devices[i].deviceId == '_hotspot_total_'
                            ? null
                            : () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => DeviceDetailScreen(
                                      deviceId: report.devices[i].deviceId,
                                      viewModel: widget.viewModel,
                                      initialRange: _range,
                                    ),
                                  ),
                                );
                              },
                    onSelectService: (svc) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ServiceDetailScreen(
                            service: svc,
                            totalContextBytes: report.devices[i].totalBytes,
                            deviceName: report.devices[i].displayName,
                            deviceId: report.devices[i].deviceId,
                            viewModel: widget.viewModel,
                          ),
                        ),
                      );
                    },
                  ),
                  if (i < report.devices.length - 1) const SizedBox(height: 10),
                ],
            ],
            const SizedBox(height: 16),
            _HistoryServicesSection(
              title: selectedDeviceMeta != null
                  ? '${selectedDeviceMeta.displayName} Apps & Traffic (${report.services.length})'
                  : 'All Apps & Traffic (${report.services.length})',
              report: report,
              onSelectService: (svc) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ServiceDetailScreen(
                      service: svc,
                      totalContextBytes: report.totalBytes,
                      deviceName: selectedDeviceMeta?.displayName,
                      deviceId: selectedDeviceMeta?.deviceId,
                      viewModel: widget.viewModel,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _DeviceWiseHistoryCard extends StatelessWidget {
  const _DeviceWiseHistoryCard({
    required this.device,
    required this.totalPeriodBytes,
    required this.deviceServices,
    required this.tabular,
    required this.onFilterDevice,
    required this.onOpenFullDevice,
    required this.onSelectService,
  });

  final DeviceHistorySummary device;
  final int totalPeriodBytes;
  final List<ServiceUsage> deviceServices;
  final List<FontFeature> tabular;
  final VoidCallback onFilterDevice;
  final VoidCallback? onOpenFullDevice;
  final ValueChanged<ServiceUsage> onSelectService;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final share = totalPeriodBytes > 0
        ? (device.totalBytes / totalPeriodBytes).clamp(0.0, 1.0)
        : 0.0;
    final sharePct = (share * 100).round();
    final visibleServices = deviceServices.take(4).toList(growable: false);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colors.secondary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  FLucideIcons.smartphone,
                  size: 17,
                  color: theme.colors.foreground,
                ),
              ),
              const SizedBox(width: 10),
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
                      '${device.vendor}${device.mac != null ? ' · ${device.mac}' : ''}',
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
                  Text(
                    '$sharePct% · ${Formatters.shortTimestamp(device.lastSeenMs)}',
                    style: theme.typography.body.xs2.copyWith(
                      color: theme.colors.mutedForeground,
                      fontFeatures: tabular,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
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
          const SizedBox(height: 6),
          if (device.firstSeenMs > 0 || device.lastSeenMs > 0)
            Text(
              'First seen ${Formatters.shortTimestamp(device.firstSeenMs)} · Last active ${Formatters.shortTimestamp(device.lastSeenMs)}',
              style: theme.typography.body.xs2.copyWith(
                color: theme.colors.mutedForeground,
                fontFeatures: tabular,
              ),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '↓ ${Formatters.bytes(device.downloadBytes)}',
                style: theme.typography.body.xs2.copyWith(
                  color: AppTheme.downloadColor,
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabular,
                ),
              ),
              Text(
                '↑ ${Formatters.bytes(device.uploadBytes)}',
                style: theme.typography.body.xs2.copyWith(
                  color: AppTheme.uploadColor,
                  fontWeight: FontWeight.w600,
                  fontFeatures: tabular,
                ),
              ),
            ],
          ),
          if (visibleServices.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: FDivider(),
            ),
            Text(
              'What this device used (${deviceServices.length})',
              style: theme.typography.body.xs2.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < visibleServices.length; i++) ...[
              _HistoryServiceRow(
                service: visibleServices[i],
                totalBytes: device.totalBytes,
                compact: true,
                onTap: () => onSelectService(visibleServices[i]),
              ),
              if (i < visibleServices.length - 1) const SizedBox(height: 4),
            ],
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FButton(
                  size: FButtonSizeVariant.xs,
                  variant: FButtonVariant.outline,
                  onPress: onFilterDevice,
                  child: const Text('Filter Timeline'),
                ),
              ),
              if (onOpenFullDevice != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FButton(
                    size: FButtonSizeVariant.xs,
                    variant: FButtonVariant.secondary,
                    onPress: onOpenFullDevice,
                    child: const Text('Full History'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryServicesSection extends StatelessWidget {
  const _HistoryServicesSection({
    required this.title,
    required this.report,
    required this.onSelectService,
  });

  final String title;
  final UsageReport report;
  final ValueChanged<ServiceUsage> onSelectService;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final services = report.services;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.typography.body.sm.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colors.foreground,
            ),
          ),
          const SizedBox(height: 10),
          if (services.isEmpty)
            Text(
              'No app or service traffic recorded in this period yet.',
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
              ),
            )
          else
            for (var i = 0; i < services.length && i < 20; i++) ...[
              _HistoryServiceRow(
                service: services[i],
                totalBytes: report.totalBytes,
                onTap: () => onSelectService(services[i]),
              ),
              if (i < services.length - 1 && i < 19) const SizedBox(height: 4),
            ],
        ],
      ),
    );
  }
}

class _HistoryServiceRow extends StatelessWidget {
  const _HistoryServiceRow({
    required this.service,
    required this.totalBytes,
    required this.onTap,
    this.compact = false,
  });

  final ServiceUsage service;
  final int totalBytes;
  final VoidCallback onTap;
  final bool compact;

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
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.body.xs.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colors.foreground,
                    ),
                  ),
                  if (!compact && service.topDomains.isNotEmpty)
                    Text(
                      service.topDomains.take(2).join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.body.xs2.copyWith(
                        color: theme.colors.mutedForeground,
                      ),
                    ),
                ],
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
              width: 68,
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
