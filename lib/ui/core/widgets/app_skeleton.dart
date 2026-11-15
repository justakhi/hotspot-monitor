import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import 'app_card.dart';

/// A pulsing skeleton placeholder for content loading states.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: theme.colors.secondary,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}

/// A complete dashboard skeleton screen replicating the home overview cards.
class DashboardSkeletonView extends StatelessWidget {
  const DashboardSkeletonView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        // 1. Session Overview Card Skeleton
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  AppSkeleton(width: 88, height: 26, borderRadius: 999),
                  SizedBox(width: 6),
                  AppSkeleton(width: 48, height: 24, borderRadius: 999),
                  SizedBox(width: 6),
                  AppSkeleton(width: 100, height: 24, borderRadius: 999),
                  Spacer(),
                  AppSkeleton(width: 50, height: 24, borderRadius: 999),
                ],
              ),
              const SizedBox(height: 18),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AppSkeleton(width: 76, height: 12),
                  AppSkeleton(width: 58, height: 12),
                ],
              ),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  AppSkeleton(width: 130, height: 32, borderRadius: 6),
                  AppSkeleton(width: 24, height: 22, borderRadius: 6),
                ],
              ),
              const SizedBox(height: 14),
              const AppSkeleton(width: double.infinity, height: 5, borderRadius: 999),
              const SizedBox(height: 12),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  AppSkeleton(width: 110, height: 14),
                  AppSkeleton(width: 95, height: 14),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2. Data Quota Card Skeleton
        const AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppSkeleton(width: 18, height: 18, borderRadius: 999),
                  SizedBox(width: 8),
                  AppSkeleton(width: 130, height: 15),
                  Spacer(),
                  AppSkeleton(width: 42, height: 24, borderRadius: 999),
                ],
              ),
              SizedBox(height: 10),
              AppSkeleton(width: double.infinity, height: 12),
              SizedBox(height: 14),
              AppSkeleton(width: double.infinity, height: 36, borderRadius: 8),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 3. Connected Devices Section Skeleton
        const Row(
          children: [
            AppSkeleton(width: 125, height: 15),
            SizedBox(width: 6),
            AppSkeleton(width: 20, height: 18, borderRadius: 999),
          ],
        ),
        const SizedBox(height: 8),

        // Placeholder device card 1
        const AppCard(
          child: Row(
            children: [
              AppSkeleton(width: 38, height: 38, borderRadius: 10),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeleton(width: 150, height: 14),
                    SizedBox(height: 6),
                    AppSkeleton(width: 100, height: 11),
                  ],
                ),
              ),
              SizedBox(width: 8),
              AppSkeleton(width: 14, height: 14, borderRadius: 999),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Placeholder device card 2
        const AppCard(
          child: Row(
            children: [
              AppSkeleton(width: 38, height: 38, borderRadius: 10),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeleton(width: 120, height: 14),
                    SizedBox(height: 6),
                    AppSkeleton(width: 85, height: 11),
                  ],
                ),
              ),
              SizedBox(width: 8),
              AppSkeleton(width: 14, height: 14, borderRadius: 999),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4. Connection History Card Skeleton
        const AppCard(
          child: Row(
            children: [
              AppSkeleton(width: 20, height: 20, borderRadius: 6),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeleton(width: 130, height: 14),
                    SizedBox(height: 5),
                    AppSkeleton(width: 90, height: 11),
                  ],
                ),
              ),
              AppSkeleton(width: 14, height: 14, borderRadius: 999),
            ],
          ),
        ),
      ],
    );
  }
}
