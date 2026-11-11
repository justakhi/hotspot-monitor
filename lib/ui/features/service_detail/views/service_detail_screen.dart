import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:forui/forui.dart';

import '../../../../domain/models/service_usage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/service_explainer.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/usage_breakdown_bar.dart';
import '../../dashboard/view_models/dashboard_view_model.dart';
import '../../device_detail/views/device_detail_screen.dart';

class ServiceDetailScreen extends StatelessWidget {
  const ServiceDetailScreen({
    super.key,
    required this.service,
    required this.totalContextBytes,
    this.deviceName,
    this.deviceId,
    this.viewModel,
  });

  final ServiceUsage service;
  final int totalContextBytes;
  final String? deviceName;
  final String? deviceId;
  final DashboardViewModel? viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final catColor = AppTheme.categoryColor(service.category);
    final explanation = ServiceExplainer.explain(service);
    final tabular = [const FontFeature.tabularFigures()];

    // Gather live devices using this service when opened from global views.
    final usingDevices = <({String id, String name, String ip, ServiceUsage svc})>[];
    if (deviceId == null && viewModel != null) {
      for (final d in viewModel!.snapshot.devices) {
        for (final s in d.services) {
          if (s.serviceId == service.serviceId) {
            usingDevices.add((id: d.id, name: d.displayName, ip: d.ip, svc: s));
          }
        }
      }
      usingDevices.sort((a, b) => b.svc.totalBytes.compareTo(a.svc.totalBytes));
    }

    final sharePct = totalContextBytes > 0
        ? ((service.totalBytes / totalContextBytes) * 100).toStringAsFixed(1)
        : '0.0';

    return FScaffold(
      childPad: false,
      header: FHeader.nested(
        title: Text(service.displayName, overflow: TextOverflow.ellipsis),
        prefixes: [
          FHeaderAction.back(onPress: () => Navigator.of(context).pop()),
        ],
      ),
      child: ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: catColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        service.displayName,
                        style: theme.typography.body.md.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colors.foreground,
                        ),
                      ),
                    ),
                    FBadge(
                      variant: FBadgeVariant.secondary,
                      child: Text(service.category),
                    ),
                  ],
                ),
                if (deviceName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'On device: $deviceName',
                    style: theme.typography.body.xs.copyWith(
                      color: theme.colors.mutedForeground,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _MetricBlock(
                        label: 'Total ($sharePct%)',
                        value: Formatters.bytes(service.totalBytes),
                        color: theme.colors.foreground,
                        tabular: tabular,
                      ),
                    ),
                    Expanded(
                      child: _MetricBlock(
                        label: 'Download',
                        value: Formatters.bytes(service.downloadBytes),
                        color: AppTheme.downloadColor,
                        tabular: tabular,
                      ),
                    ),
                    Expanded(
                      child: _MetricBlock(
                        label: 'Upload',
                        value: Formatters.bytes(service.uploadBytes),
                        color: AppTheme.uploadColor,
                        tabular: tabular,
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
                      value: service.downloadBytes,
                      color: AppTheme.downloadColor,
                    ),
                    BarSegment(
                      label: 'Upload',
                      value: service.uploadBytes,
                      color: AppTheme.uploadColor,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  ServiceExplainer.directionSummary(
                    service.downloadBytes,
                    service.uploadBytes,
                  ),
                  style: theme.typography.body.xs.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What Is This?',
                  style: theme.typography.body.sm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colors.foreground,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  explanation.summary,
                  style: theme.typography.body.xs.copyWith(
                    color: theme.colors.foreground,
                    height: 1.45,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: FDivider(),
                ),
                Text(
                  'Likely App / PC Software',
                  style: theme.typography.body.xs2.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  explanation.likelyApps,
                  style: theme.typography.body.xs.copyWith(
                    color: theme.colors.foreground,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'How It Was Detected',
                  style: theme.typography.body.xs2.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colors.mutedForeground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  explanation.detectionBasis,
                  style: theme.typography.body.xs.copyWith(
                    color: theme.colors.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _EndpointsCard(
            service: service,
            tabular: tabular,
            viewModel: viewModel,
          ),
          if (usingDevices.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Devices Using This (${usingDevices.length})',
                    style: theme.typography.body.sm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colors.foreground,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < usingDevices.length; i++) ...[
                    FTappable(
                      onPress: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DeviceDetailScreen(
                              deviceId: usingDevices[i].id,
                              viewModel: viewModel!,
                            ),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  usingDevices[i].name,
                                  style: theme.typography.body.xs.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: theme.colors.foreground,
                                  ),
                                ),
                                Text(
                                  usingDevices[i].ip,
                                  style: theme.typography.body.xs2.copyWith(
                                    color: theme.colors.mutedForeground,
                                    fontFeatures: tabular,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            Formatters.bytes(usingDevices[i].svc.totalBytes),
                            style: theme.typography.body.xs.copyWith(
                              fontWeight: FontWeight.w700,
                              color: theme.colors.foreground,
                              fontFeatures: tabular,
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
                    ),
                    if (i < usingDevices.length - 1) const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          AppCard(
            child: Text(
              'Note on URLs & App Names: Plain HTTP links show their full URL path when unencrypted. On HTTPS apps (YouTube, Instagram, etc.), the exact video or page URL path (like /watch?v=...) is encrypted end-to-end inside TLS, so only the website domain or video CDN host can be shown and opened. Connected phones and PCs also keep local app package/.exe names private.',
              style: theme.typography.body.xs2.copyWith(
                color: theme.colors.mutedForeground,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
    required this.label,
    required this.value,
    required this.color,
    required this.tabular,
  });

  final String label;
  final String value;
  final Color color;
  final List<FontFeature> tabular;

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
            color: color,
            fontFeatures: tabular,
          ),
        ),
      ],
    );
  }
}

class _EndpointsCard extends StatelessWidget {
  const _EndpointsCard({
    required this.service,
    required this.tabular,
    required this.viewModel,
  });

  final ServiceUsage service;
  final List<FontFeature> tabular;
  final DashboardViewModel? viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final endpoints = service.endpoints;
    final domains = service.topDomains;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where Data Is Going',
            style: theme.typography.body.sm.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colors.foreground,
            ),
          ),
          const SizedBox(height: 8),
          if (endpoints.isNotEmpty) ...[
            for (var i = 0; i < endpoints.length; i++) ...[
              _EndpointRow(
                endpoint: endpoints[i],
                serviceTotalBytes: service.totalBytes,
                tabular: tabular,
                viewModel: viewModel,
              ),
              if (i < endpoints.length - 1) const SizedBox(height: 12),
            ],
          ] else if (domains.isNotEmpty) ...[
            for (final d in domains)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '• $d',
                  style: theme.typography.body.xs.copyWith(
                    color: theme.colors.foreground,
                    fontFeatures: tabular,
                  ),
                ),
              ),
          ] else
            Text(
              'No individual domains or server IPs recorded for this entry.',
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
        ],
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({
    required this.endpoint,
    required this.serviceTotalBytes,
    required this.tabular,
    required this.viewModel,
  });

  final EndpointUsage endpoint;
  final int serviceTotalBytes;
  final List<FontFeature> tabular;
  final DashboardViewModel? viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final share = serviceTotalBytes > 0
        ? (endpoint.totalBytes / serviceTotalBytes).clamp(0.0, 1.0)
        : 0.0;
    final roleHint = ServiceExplainer.explainEndpoint(endpoint.endpoint);
    final launchUrl = ServiceExplainer.launchableUrl(endpoint.endpoint);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                endpoint.endpoint,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.body.xs.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colors.foreground,
                  fontFeatures: tabular,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              Formatters.bytes(endpoint.totalBytes),
              style: theme.typography.body.xs.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colors.foreground,
                fontFeatures: tabular,
              ),
            ),
          ],
        ),
        if (roleHint != null) ...[
          const SizedBox(height: 2),
          Text(
            roleHint,
            style: theme.typography.body.xs2.copyWith(
              color: theme.colors.mutedForeground,
            ),
          ),
        ],
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 4,
            backgroundColor: theme.colors.muted,
            valueColor: const AlwaysStoppedAnimation<Color>(
              AppTheme.downloadColor,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                '↓ ${Formatters.bytes(endpoint.downloadBytes)} · ↑ ${Formatters.bytes(endpoint.uploadBytes)}',
                style: theme.typography.body.xs2.copyWith(
                  color: theme.colors.mutedForeground,
                  fontFeatures: tabular,
                ),
              ),
            ),
            FButton(
              size: FButtonSizeVariant.xs,
              variant: FButtonVariant.outline,
              mainAxisSize: MainAxisSize.min,
              onPress: () async {
                await Clipboard.setData(ClipboardData(text: endpoint.endpoint));
                if (context.mounted) {
                  showFToast(
                    context: context,
                    icon: const Icon(FLucideIcons.copy),
                    title: const Text('Copied destination'),
                    description: Text(endpoint.endpoint),
                  );
                }
              },
              child: const Text('Copy'),
            ),
            if (launchUrl != null && viewModel != null) ...[
              const SizedBox(width: 6),
              FButton(
                size: FButtonSizeVariant.xs,
                variant: FButtonVariant.secondary,
                mainAxisSize: MainAxisSize.min,
                onPress: () async {
                  await viewModel!.openUrl(launchUrl);
                },
                child: const Text('Open'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
