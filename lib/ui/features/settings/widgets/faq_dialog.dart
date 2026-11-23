import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/widgets/app_card.dart';

/// Interactive FAQ & Help guide explaining Root vs Non-Root, randomized MACs, and quotas.
class FaqDialog extends StatelessWidget {
  const FaqDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showAdaptiveDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const FaqDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  FLucideIcons.circleHelp,
                  size: 22,
                  color: theme.colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Frequently Asked Questions',
                    style: theme.typography.display.sm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colors.foreground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              constraints: const BoxConstraints(maxHeight: 340),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colors.muted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FaqItem(
                      question: 'What is the difference between Root and Non-Root?',
                      answer:
                          'In Non-Root mode, Hotspot Monitor tracks connected clients via the device ARP/neighbour table and Android traffic statistics. In Root mode, the app uses packet inspection to classify specific services (like YouTube, Netflix, Steam) and enforce per-device bandwidth blocking.',
                    ),
                    const Divider(height: 20),
                    _FaqItem(
                      question: 'Why does a client show "Randomized MAC"?',
                      answer:
                          'Modern Android, iOS, and Windows devices generate randomized MAC addresses by default for Wi-Fi privacy. You can assign custom names or aliases to easily recognize your devices.',
                    ),
                    const Divider(height: 20),
                    _FaqItem(
                      question: 'Why does background monitoring pause?',
                      answer:
                          'Some phone manufacturers aggressively close background apps when the screen is locked. To ensure continuous live tracking, tap "Optimize Background Reliability" in Settings to exempt Hotspot Monitor from battery restrictions.',
                    ),
                    const Divider(height: 20),
                    _FaqItem(
                      question: 'How do Data Quotas work?',
                      answer:
                          'You can configure global or per-device data budgets. When a quota threshold is reached, Hotspot Monitor alerts you immediately, and in Root mode can automatically block further internet access for that client.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FButton(
                  size: FButtonSizeVariant.sm,
                  onPress: () => Navigator.of(context).pop(),
                  child: const Text('Got It'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  const _FaqItem({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: theme.typography.body.sm.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colors.foreground,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          answer,
          style: theme.typography.body.xs2.copyWith(
            color: theme.colors.mutedForeground,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
