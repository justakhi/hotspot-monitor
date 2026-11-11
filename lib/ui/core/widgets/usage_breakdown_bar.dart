import 'package:flutter/material.dart';

class BarSegment {
  const BarSegment({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

class UsageBreakdownBar extends StatelessWidget {
  const UsageBreakdownBar({
    super.key,
    required this.segments,
    this.height = 10,
  });

  final List<BarSegment> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<int>(0, (sum, s) => sum + s.value);
    if (total <= 0) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      );
    }

    final nonZero = segments.where((s) => s.value > 0).toList(growable: false);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (var i = 0; i < nonZero.length; i++)
              Expanded(
                flex: nonZero[i].value.clamp(1, 1 << 30),
                child: Container(
                  margin: EdgeInsets.only(right: i == nonZero.length - 1 ? 0 : 1.5),
                  color: nonZero[i].color,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
