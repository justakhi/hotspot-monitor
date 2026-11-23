import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../data/services/ad_service.dart';

/// Renders an anchored AdMob banner ad that hides gracefully if the user has Pro
/// or if the ad fails to load / is offline.
class AdBannerWidget extends StatefulWidget {
  const AdBannerWidget({
    super.key,
    required this.isPro,
    this.adUnitId,
  });

  final bool isPro;
  final String? adUnitId;

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  bool get _canLoadAds =>
      !widget.isPro && !kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    if (_canLoadAds) {
      _loadBanner();
    }
  }

  @override
  void didUpdateWidget(covariant AdBannerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPro && !oldWidget.isPro) {
      _disposeBanner();
    } else if (_canLoadAds && _bannerAd == null) {
      _loadBanner();
    }
  }

  void _loadBanner() {
    try {
      _bannerAd = AdService.createBannerAd(
        adUnitId: widget.adUnitId,
        onAdLoaded: () {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (_) {
          if (mounted) setState(() => _isLoaded = false);
        },
      )..load();
    } catch (_) {
      // Safe fallback if Google Play Services is missing
    }
  }

  void _disposeBanner() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isLoaded = false;
  }

  @override
  void dispose() {
    _disposeBanner();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPro || !_isLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    return Container(
      alignment: Alignment.center,
      width: _bannerAd!.size.width.toDouble(),
      height: _bannerAd!.size.height.toDouble(),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
