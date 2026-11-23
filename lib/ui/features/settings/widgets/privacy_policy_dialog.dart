import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../core/widgets/app_card.dart';

/// Shows the official Hotspot Monitor Privacy Policy directly in-app.
class PrivacyPolicyDialog extends StatelessWidget {
  const PrivacyPolicyDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showAdaptiveDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const PrivacyPolicyDialog(),
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
                  FLucideIcons.shieldCheck,
                  size: 22,
                  color: theme.colors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Privacy Policy',
                    style: theme.typography.display.sm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colors.foreground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Hotspot Monitor by AP Labs · Effective November 2026',
              style: theme.typography.body.xs.copyWith(
                color: theme.colors.mutedForeground,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colors.muted,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                child: Text(
                  '''1. OVERVIEW
Hotspot Monitor is an offline-first tethering utility built to help you monitor networks you own. We respect your privacy and do not collect, sell, or transmit your personal data.

2. LOCAL DATA COLLECTION
All traffic data, IP addresses, MAC addresses, device aliases, and network interface metrics are queried directly from your device's Linux kernel network subsystem and stored in a private local SQLite database on your device.

3. NETWORK PERMISSIONS
The app uses network state permissions (ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE) to identify upstream carriers and hotspot interfaces. No personal browsing activity is uploaded to any remote server.

4. THIRD-PARTY SERVICES
• Google Play Billing: Used to process in-app purchases (e.g. Pro / Remove Ads). Google handles billing information securely.
• Google Mobile Ads (AdMob): Displays non-personalized or personalized advertising banners in the free version. You can remove ads permanently with Hotspot Monitor Pro.

5. SECURITY
All local Pro purchase tokens are cryptographically hashed using SHA-256 to ensure integrity.

6. CONTACT
For questions or concerns, contact AP Labs at contact@techyke.in.''',
                  style: theme.typography.body.xs2.copyWith(
                    color: theme.colors.foreground,
                    height: 1.45,
                  ),
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
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
