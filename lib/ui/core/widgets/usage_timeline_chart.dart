import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../domain/models/history_report.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

class UsageTimelineChart extends StatefulWidget {
  const UsageTimelineChart({
    super.key,
    required this.points,
    this.range,
    this.height = 110,
  });

  final List<TimelinePoint> points;
  final HistoryRange? range;
  final double height;

  @override
  State<UsageTimelineChart> createState() => _UsageTimelineChartState();
}

class _UsageTimelineChartState extends State<UsageTimelineChart> {
  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant UsageTimelineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points.length != widget.points.length ||
        oldWidget.range != widget.range) {
      _selectedIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final points = widget.points;
    if (points.isEmpty) {
      return SizedBox(
        height: 48,
        child: Center(
          child: Text(
            'No recorded timeline points for this period yet.',
            style: theme.typography.body.xs.copyWith(
              color: theme.colors.mutedForeground,
            ),
          ),
        ),
      );
    }

    final maxBytes = points.fold<int>(
      1,
      (max, p) => p.totalBytes > max ? p.totalBytes : max,
    );
    final selected = (_selectedIndex != null && _selectedIndex! < points.length)
        ? points[_selectedIndex!]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Peak: ${Formatters.bytes(maxBytes)}',
              style: theme.typography.body.xs2.copyWith(
                color: theme.colors.mutedForeground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LegendDot(color: AppTheme.downloadColor, label: 'Down'),
                const SizedBox(width: 10),
                _LegendDot(color: AppTheme.uploadColor, label: 'Up'),
              ],
            ),
          ],
        ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colors.secondary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${Formatters.timelineBucketDetail(selected.bucketStartMs, widget.range)} · '
              '${Formatters.bytes(selected.totalBytes)} '
              '(↓ ${Formatters.bytes(selected.downloadBytes)} · ↑ ${Formatters.bytes(selected.uploadBytes)})',
              style: theme.typography.body.xs2.copyWith(
                color: theme.colors.foreground,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: widget.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < points.length; i++)
                Expanded(
                  child: _TimelineBar(
                    point: points[i],
                    maxBytes: maxBytes,
                    maxBarHeight: widget.height - 22,
                    showLabel: _shouldShowLabel(i, points.length),
                    selected: _selectedIndex == i,
                    onTap: () {
                      setState(() {
                        _selectedIndex = _selectedIndex == i ? null : i;
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  bool _shouldShowLabel(int index, int count) {
    if (count <= 7) return true;
    final step = (count / 5).ceil();
    return index == 0 || index == count - 1 || index % step == 0;
  }
}

class _TimelineBar extends StatelessWidget {
  const _TimelineBar({
    required this.point,
    required this.maxBytes,
    required this.maxBarHeight,
    required this.showLabel,
    required this.selected,
    required this.onTap,
  });

  final TimelinePoint point;
  final int maxBytes;
  final double maxBarHeight;
  final bool showLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final totalRatio = (point.totalBytes / maxBytes).clamp(0.0, 1.0);
    final totalH = point.totalBytes > 0
        ? (totalRatio * maxBarHeight).clamp(4.0, maxBarHeight)
        : 2.0;
    final downH = point.totalBytes > 0
        ? totalH * (point.downloadBytes / point.totalBytes)
        : 0.0;
    final upH = (totalH - downH).clamp(0.0, totalH);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              decoration: selected
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: theme.colors.foreground,
                        width: 1.5,
                      ),
                    )
                  : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  width: 14,
                  height: totalH,
                  child: point.totalBytes == 0
                      ? ColoredBox(color: theme.colors.muted)
                      : Column(
                          children: [
                            if (upH > 0)
                              SizedBox(
                                height: upH,
                                width: double.infinity,
                                child: const ColoredBox(color: AppTheme.uploadColor),
                              ),
                            if (downH > 0)
                              Expanded(
                                child: const SizedBox.expand(
                                  child: ColoredBox(color: AppTheme.downloadColor),
                                ),
                              ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              showLabel ? point.label : '',
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: theme.typography.body.xs2.copyWith(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected
                    ? theme.colors.foreground
                    : theme.colors.mutedForeground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.typography.body.xs2.copyWith(
            color: theme.colors.mutedForeground,
          ),
        ),
      ],
    );
  }
}
