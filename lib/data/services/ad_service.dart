import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Wraps Google Mobile Ads SDK initialization and ad unit configuration.
class AdService {
  static bool _initialized = false;

  /// Official Google Mobile Ads test banner ad unit ID for Android.
  /// Replace with your production AdMob banner ID before store release.
  static const String testBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';

  static Future<void> initialize() async {
    if (_initialized || kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
    } catch (_) {
      // Graceful fallback for offline, tests, or non-Google environments
    }
  }

  static BannerAd createBannerAd({
    required void Function() onAdLoaded,
    required void Function(LoadAdError) onAdFailedToLoad,
    String? adUnitId,
  }) {
    return BannerAd(
      adUnitId: adUnitId ?? testBannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => onAdLoaded(),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          onAdFailedToLoad(error);
        },
      ),
    );
  }
}
