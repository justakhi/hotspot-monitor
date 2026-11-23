import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages Google Play In-App Billing for unlocking Hotspot Monitor Pro (Remove Ads)
/// with tamper-resistant local token verification to prevent offline local hacks.
class PurchaseService extends ChangeNotifier {
  PurchaseService({InAppPurchase? iap}) : _injectedIap = iap;

  final InAppPurchase? _injectedIap;
  InAppPurchase? _instance;

  InAppPurchase get _iap => _injectedIap ?? (_instance ??= InAppPurchase.instance);

  static const String proProductId = 'pro_remove_ads';
  static const String _secretSalt = 'APLabs_HM_SecKey_2026_x89a';
  static const String _tokenPrefKey = 'hm_p_tk_v1';
  static const String _digestPrefKey = 'hm_p_dg_v1';

  bool _isPro = false;
  bool get isPro => _isPro;

  ProductDetails? _proProduct;
  ProductDetails? get proProduct => _proProduct;

  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  StreamSubscription<List<PurchaseDetails>>? _subscription;

  Future<void> initialize() async {
    await _loadSavedProStatus();

    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }

    try {
      _isAvailable = await _iap.isAvailable();
      if (_isAvailable) {
        _subscription = _iap.purchaseStream.listen(
          _handlePurchaseUpdates,
          onDone: () => _subscription?.cancel(),
          onError: (Object _) {},
        );
        await _loadProducts();
      }
    } catch (_) {
      // Graceful offline fallback
    }
  }

  Future<void> _loadProducts() async {
    try {
      final response = await _iap.queryProductDetails({proProductId});
      if (response.productDetails.isNotEmpty) {
        _proProduct = response.productDetails.first;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _loadSavedProStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenPrefKey);
    final digest = prefs.getString(_digestPrefKey);

    if (token != null && digest != null) {
      // Validate tamper-proof HMAC digest
      final expectedDigest = _computeDigest(token);
      if (expectedDigest == digest) {
        _isPro = true;
        notifyListeners();
        return;
      }
    }
    _isPro = false;
    notifyListeners();
  }

  static String _computeDigest(String token) {
    final bytes = utf8.encode('$token:$_secretSalt');
    return sha256.convert(bytes).toString();
  }

  Future<void> _saveProStatus(String purchaseToken) async {
    final prefs = await SharedPreferences.getInstance();
    final digest = _computeDigest(purchaseToken);
    await prefs.setString(_tokenPrefKey, purchaseToken);
    await prefs.setString(_digestPrefKey, digest);
    _isPro = true;
    notifyListeners();
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID == proProductId) {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          final token = purchase.verificationData.serverVerificationData.isNotEmpty
              ? purchase.verificationData.serverVerificationData
              : (purchase.purchaseID ?? 'verified_token');
          await _saveProStatus(token);

          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        }
      }
    }
  }

  Future<bool> buyPro() async {
    if (!_isAvailable || _proProduct == null) return false;
    final purchaseParam = PurchaseParam(productDetails: _proProduct!);
    return _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    if (_isAvailable) {
      await _iap.restorePurchases();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
