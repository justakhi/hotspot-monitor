import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// Forui [FCard] wrapper that applies [FCardStyle.padding] cleanly,
/// clips children to the superellipse border, and optionally handles taps.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onPress,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onPress;

  @override
  Widget build(BuildContext context) {
    final card = FCard(
      clipBehavior: Clip.antiAlias,
      builder: (_, style, content) => Padding(
        padding: padding ?? style.padding,
        child: content,
      ),
      child: child,
    );

    if (onPress == null) return card;
    return FTappable(onPress: onPress, child: card);
  }
}
