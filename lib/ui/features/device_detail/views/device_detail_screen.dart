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
import '../../service_detail/views/service_detail_screen.dart';

class DeviceDetailScreen extends StatefulWidget {
  const DeviceDetailScreen({
    super.key,
    required this.deviceId,
    required this.viewModel,
    this.initialRange,
  });

  final String deviceId;
  final DashboardViewModel viewModel;
  final HistoryRange? initialRange;

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  String _selectedCategory = 'All';
  HistoryRange? _historyRange;
  UsageReport? _historyReport;
  DeviceHistorySummary? _savedSummary;
  bool _loadingHistory = false;

  @override
  void initState() {
    super.initState();
    _historyRange = widget.initialRange;
    _loadSavedMetadata();
    if (_historyRange != null) {
      _loadDeviceReport(_historyRange!);
    }
    widget.viewModel.addListener(_onModelChanged);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onModelChanged);
    super.dispose();
  }

  void _onModelChanged() {
    final range = _historyRange;
    if (range != null) {
      _loadDeviceReport(range, silent: true);
    }
  }

  Future<void> _loadSavedMetadata() async {
    final summary = await widget.viewModel.getDeviceHistorySummary(
      widget.deviceId,
    );
    if (mounted && summary != null) {
      setState(() => _savedSummary = summary);
    }
  }

  Future<void> _loadDeviceReport(
    HistoryRange range, {
    bool silent = false,
  }) async {
    if (!silent && mounted) {
      setState(() => _loadingHistory = true);
    }
    final report = await widget.viewModel.getUsageReport(
      range,
      deviceId: widget.deviceId,
    );
    if (mounted) {
      setState(() {
        _historyReport = report;
        _loadingHistory = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final snapshot = widget.viewModel.snapshot;
        final liveDevice = widget.viewModel.findDeviceById(widget.deviceId);
        final fallback = _savedSummary;

        if (liveDevice == null && fallback == null) {
          return FScaffold(
            header: FHeader.nested(
              title: const Text('Device Details'),
              prefixes: [
                FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
              ],
            ),
            child: const Center(
              child: Text('Device record not found.'),
            ),
          );
        }

        final displayName =
            liveDevice?.displayName ?? fallback!.displayName;
        final customAlias =
            liveDevice?.customAlias ?? fallback?.customAlias;
        final hostname = liveDevice?.hostname ?? fallback?.hostname;
        final ip = liveDevice?.ip ?? fallback!.ip;
        final mac = liveDevice?.mac ?? fallback?.mac;
        final vendor = liveDevice?.vendor ?? fallback!.vendor;
        final isRandomizedMac =
            liveDevice?.isRandomizedMac ?? fallback?.isRandomizedMac ?? false;
        final isOnline = liveDevice?.isOnline ?? false;
        final neighborState = liveDevice?.neighborState ?? 'HISTORY';
        final rssiDbm = liveDevice?.rssiDbm;
        final txBitrateMbps = liveDevice?.txBitrateMbps;
        final rxBitrateMbps = liveDevice?.rxBitrateMbps;

        final isRoot = snapshot.isRootMode;
        final activeRange = _historyRange;

        final int downBytes;
        final int upBytes;
        final int downBps;
        final int upBps;
        final List<ServiceUsage> allServices;

        if (activeRange == null && liveDevice != null) {
          downBytes = liveDevice.downloadBytes;
          upBytes = liveDevice.uploadBytes;
          downBps = liveDevice.currentDownloadBps;
          upBps = liveDevice.currentUploadBps;
          allServices = liveDevice.services;
        } else {
          final report = _historyReport ?? UsageReport.empty;
          downBytes = report.totalDownloadBytes;
          upBytes = report.totalUploadBytes;
          downBps = 0;
          upBps = 0;
          allServices = report.services;
        }

        final totalBytes = downBytes + upBytes;
        final categories = <String>{'All'};
        for (final s in allServices) {
          categories.add(s.category);
        }
        if (!categories.contains(_selectedCategory)) {
          _selectedCategory = 'All';
        }

        final visibleServices = _selectedCategory == 'All'
            ? allServices
            : allServices
                  .where((s) => s.category == _selectedCategory)
                  .toList(growable: false);

        return FScaffold(
          childPad: false,
          header: FHeader.nested(
            title: Text(displayName, overflow: TextOverflow.ellipsis),
            prefixes: [
              FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
            ],
            suffixes: [
              FHeaderAction(
                semanticsLabel: 'Rename device',
                icon: const Icon(FLucideIcons.pencil),
                onPress: () => _showRenameDialog(
                  context,
                  deviceId: widget.deviceId,
                  currentAlias: customAlias,
                  fallbackHint: hostname ?? ip,
                ),
              ),
            ],
          ),
          child: ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              _DeviceIdentityCard(
                displayName: displayName,
                ip: ip,
                mac: mac,
                vendor: vendor,
                isRandomizedMac: isRandomizedMac,
                hostname: hostname,
                isOnline: isOnline,
                neighborState: neighborState,
                rssiDbm: rssiDbm,
                txBitrateMbps: txBitrateMbps,
                rxBitrateMbps: rxBitrateMbps,
                isRoot: isRoot,
              ),
              const SizedBox(height: 12),
              if (isRoot || activeRange != null || fallback != null) ...[
                _PeriodSelector(
                  showLive: liveDevice != null,
                  selectedRange: activeRange,
                  onSelect: (range) {
                    setState(() => _historyRange = range);
                    if (range != null) {
                      _loadDeviceReport(range);
                    }
                  },
                ),
                const SizedBox(height: 10),
                if (activeRange != null && _loadingHistory && _historyReport == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: FCircularProgress()),
                  )
                else ...[
                  _DeviceTrafficCard(
                    title: activeRange == null
                        ? 'Session Data Usage'
                        : '${activeRange.title} Usage',
                    timeWindow: activeRange == null
                        ? 'Started ${Formatters.shortTimestamp(snapshot.sessionStartMs)}'
                        : Formatters.rangeWindow(
                            activeRange,
                            firstSeenMs: fallback?.firstSeenMs,
                          ),
                    downloadBytes: downBytes,
                    uploadBytes: upBytes,
                    downBps: downBps,
                    upBps: upBps,
                    showSpeed: activeRange == null,
                    timeline: activeRange == null
                        ? null
                        : (_historyReport?.timeline ?? const []),
                    range: activeRange,
                  ),
                  const SizedBox(height: 12),
                  _ServiceSection(
                    allServices: allServices,
                    visibleServices: visibleServices,
                    totalBytes: totalBytes,
                    categories: categories.toList(growable: false),
                    selectedCategory: _selectedCategory,
                    onSelectCategory: (cat) =>
                        setState(() => _selectedCategory = cat),
                    onSelectService: (svc) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ServiceDetailScreen(
                            service: svc,
                            totalContextBytes: totalBytes,
                            deviceName: displayName,
                            deviceId: widget.deviceId,
                            viewModel: widget.viewModel,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ] else
                const _RootLockedCard(),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context, {
    required String deviceId,
    required String? currentAlias,
    required String fallbackHint,
  }) async {
    final controller = TextEditingController(text: currentAlias ?? '');
    final saved = await showFDialog<String>(
      context: context,
      builder: (ctx, style, animation) => FDialog(
        style: style,
        animation: animation,
        builder: (dialogCtx, _) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Label Device',
                style: dialogCtx.theme.typography.display.lg.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              FTextField(
                control: .managed(controller: controller),
                autofocus: true,
                label: const Text('Friendly name'),
                hint: fallbackHint,
                description: const Text('Leave empty to reset to default name.'),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FButton(
                    variant: FButtonVariant.outline,
                    size: FButtonSizeVariant.sm,
                    mainAxisSize: MainAxisSize.min,
                    onPress: () => Navigator.of(dialogCtx).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FButton(
                    size: FButtonSizeVariant.sm,
                    mainAxisSize: MainAxisSize.min,
                    onPress: () =>
                        Navigator.of(dialogCtx).pop(controller.text),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (saved != null) {
      await widget.viewModel.renameDevice(deviceId, saved);
    }
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.showLive,
    required this.selectedRange,
    required this.onSelect,
  });

  final bool showLive;
  final HistoryRange? selectedRange;
  final ValueChanged<HistoryRange?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (showLive)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FButton(
                size: FButtonSizeVariant.xs,
                variant: selectedRange == null
                    ? FButtonVariant.primary
                    : FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: () => onSelect(null),
                child: const Text('Live'),
              ),
            ),
          for (final r in HistoryRange.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FButton(
                size: FButtonSizeVariant.xs,
                variant: selectedRange == r
                    ? FButtonVariant.primary
                    : FButtonVariant.outline,
                mainAxisSize: MainAxisSize.min,
                onPress: () => onSelect(r),
                child: Text(r.shortLabel),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceIdentityCard extends StatelessWidget {
  const _DeviceIdentityCard({
    required this.displayName,
    required this.ip,
    required this.mac,
    required this.vendor,
    required this.isRandomizedMac,
    required this.hostname,
    required this.isOnline,
    required this.neighborState,
    required this.rssiDbm,
    required this.txBitrateMbps,
    required this.rxBitrateMbps,
    required this.isRoot,
  });

  final String displayName;
  final String ip;
  final String? mac;
  final String vendor;
  final bool isRandomizedMac;
  final String? hostname;
  final bool isOnline;
  final String neighborState;
  final int? rssiDbm;
  final double? txBitrateMbps;
  final double? rxBitrateMbps;
  final bool isRoot;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isOnline
                      ? AppTheme.rootAccent.withValues(alpha: 0.14)
                      : theme.colors.muted,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  FLucideIcons.smartphone,
                  size: 20,
                  color: isOnline
                      ? AppTheme.rootAccent
                      : theme.colors.mutedForeground,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: theme.typography.body.md.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colors.foreground,
                      ),
                    ),
                    Text(
                      isOnline ? 'Connected' : 'Offline / Saved Record',
                      style: theme.typography.body.xs.copyWith(
                        color: isOnline
                            ? AppTheme.rootAccent
                            : theme.colors.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              FBadge(
                variant: FBadgeVariant.outline,
                child: Text(neighborState),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: FDivider(),
          ),
          _InfoRow(label: 'IP Address', value: ip),
          _InfoRow(
            label: 'MAC Address',
            value: mac ?? (isRoot ? 'Unavailable' : 'Root required'),
          ),
          _InfoRow(
            label: 'Manufacturer',
            value: isRandomizedMac ? '$vendor (Randomized)' : vendor,
          ),
          _InfoRow(
            label: 'Hostname',
            value: hostname ?? 'Not advertised',
          ),
          if (rssiDbm != null)
            _InfoRow(
              label: 'Wi-Fi Signal',
              value: Formatters.signalLabel(rssiDbm),
            ),
          if (txBitrateMbps != null || rxBitrateMbps != null)
            _InfoRow(
              label: 'Link Speed',
              value:
                  'TX ${txBitrateMbps?.toStringAsFixed(0) ?? '-'} Mbps / '
                  'RX ${rxBitrateMbps?.toStringAsFixed(0) ?? '-'} Mbps',
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.typography.body.xs.copyWith(
              color: theme.colors.mutedForeground,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.typography.body.xs.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colors.foreground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTrafficCard extends StatelessWidget {
  const _DeviceTrafficCard({
    required this.title,
    required this.timeWindow,
    required this.downloadBytes,
    required this.uploadBytes,
    required this.downBps,
    required this.upBps,
    required this.showSpeed,
    required this.timeline,
    this.range,
  });

  final String title;
  final String timeWindow;
  final int downloadBytes;
  final int uploadBytes;
  final int downBps;
  final int upBps;
  final bool showSpeed;
  final List<TimelinePoint>? timeline;
  final HistoryRange? range;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final totalBytes = downloadBytes + uploadBytes;

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
          const SizedBox(height: 3),
          Text(
            timeWindow,
            style: theme.typography.body.xs2.copyWith(
              color: theme.colors.mutedForeground,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Total',
                  value: Formatters.bytes(totalBytes),
                  subValue: showSpeed
                      ? Formatters.speed(downBps + upBps)
                      : 'Saved',
                  accent: theme.colors.foreground,
                ),
              ),
              Expanded(
                child: _StatTile(
                  label: 'Download',
                  value: Formatters.bytes(downloadBytes),
                  subValue: showSpeed ? Formatters.speed(downBps) : '',
                  accent: AppTheme.downloadColor,
                ),
              ),
              Expanded(
                child: _StatTile(
                  label: 'Upload',
                  value: Formatters.bytes(uploadBytes),
                  subValue: showSpeed ? Formatters.speed(upBps) : '',
                  accent: AppTheme.uploadColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          UsageBreakdownBar(
            height: 6,
            segments: [
              BarSegment(
                label: 'Download',
                value: downloadBytes,
                color: AppTheme.downloadColor,
              ),
              BarSegment(
                label: 'Upload',
                value: uploadBytes,
                color: AppTheme.uploadColor,
              ),
            ],
          ),
          if (timeline != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: FDivider(),
            ),
            UsageTimelineChart(points: timeline!, range: range),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.subValue,
    required this.accent,
  });

  final String label;
  final String value;
  final String subValue;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.typography.body.xs2.copyWith(
            color: theme.colors.mutedForeground,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.typography.body.md.copyWith(
            fontWeight: FontWeight.w700,
            color: accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (subValue.isNotEmpty)
          Text(
            subValue,
            style: theme.typography.body.xs2.copyWith(
              color: theme.colors.mutedForeground,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

class _ServiceSection extends StatelessWidget {
  const _ServiceSection({
    required this.allServices,
    required this.visibleServices,
    required this.totalBytes,
    required this.categories,
    required this.selectedCategory,
    required this.onSelectCategory,
    required this.onSelectService,
  });

  final List<ServiceUsage> allServices;
  final List<ServiceUsage> visibleServices;
  final int totalBytes;
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onSelectCategory;
  final ValueChanged<ServiceUsage> onSelectService;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Apps & Services',
            style: theme.typography.body.sm.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colors.foreground,
            ),
          ),
          const SizedBox(height: 10),
          if (allServices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No traffic recorded for this device in this period.',
                style: theme.typography.body.xs.copyWith(
                  color: theme.colors.mutedForeground,
                ),
              ),
            )
          else ...[
            UsageBreakdownBar(
              height: 8,
              segments: allServices
                  .take(8)
                  .map(
                    (s) => BarSegment(
                      label: s.displayName,
                      value: s.totalBytes,
                      color: AppTheme.categoryColor(s.category),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final cat in categories)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FButton(
                        size: FButtonSizeVariant.xs,
                        variant: cat == selectedCategory
                            ? FButtonVariant.primary
                            : FButtonVariant.outline,
                        mainAxisSize: MainAxisSize.min,
                        onPress: () => onSelectCategory(cat),
                        child: Text(cat),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            for (final svc in visibleServices)
              _ServiceTile(
                service: svc,
                deviceTotalBytes: totalBytes,
                onTap: () => onSelectService(svc),
              ),
          ],
        ],
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.service,
    required this.deviceTotalBytes,
    required this.onTap,
  });

  final ServiceUsage service;
  final int deviceTotalBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final share = deviceTotalBytes > 0
        ? (service.totalBytes / deviceTotalBytes).clamp(0.0, 1.0)
        : 0.0;
    final catColor = AppTheme.categoryColor(service.category);

    return FTappable(
      onPress: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: catColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    service.displayName,
                    style: theme.typography.body.sm.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colors.foreground,
                    ),
                  ),
                ),
                Text(
                  '${Formatters.bytes(service.totalBytes)} (${(share * 100).toStringAsFixed(0)}%)',
                  style: theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colors.foreground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  FLucideIcons.chevronRight,
                  size: 14,
                  color: theme.colors.mutedForeground,
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 5,
                backgroundColor: theme.colors.muted,
                valueColor: AlwaysStoppedAnimation<Color>(catColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '${service.category} · ↓ ${Formatters.bytes(service.downloadBytes)} · ↑ ${Formatters.bytes(service.uploadBytes)}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.body.xs2.copyWith(
                      color: theme.colors.mutedForeground,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (service.topDomains.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      service.topDomains.take(2).join(', '),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.typography.body.xs2.copyWith(
                        color: theme.colors.mutedForeground,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RootLockedCard extends StatelessWidget {
  const _RootLockedCard();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(FLucideIcons.lock, size: 18, color: theme.colors.primary),
              const SizedBox(width: 8),
              Text(
                'Per-Device Usage & Services',
                style: theme.typography.body.sm.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colors.foreground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Standard Android blocks third-party apps from reading per-client hotspot packets and MAC addresses. Root permission is required (see Menu & Settings if you want to retry).',
            style: theme.typography.body.xs.copyWith(
              color: theme.colors.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}
