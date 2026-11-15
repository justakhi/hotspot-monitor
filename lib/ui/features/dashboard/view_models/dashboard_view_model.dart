import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/hotspot_repository.dart';
import '../../../../domain/models/app_release_info.dart';
import '../../../../domain/models/connected_device.dart';
import '../../../../domain/models/device_quota.dart';
import '../../../../domain/models/history_report.dart';
import '../../../../domain/models/hotspot_snapshot.dart';
import '../../../../domain/models/quota_config.dart';

enum QuotaStatus {
  disabled,
  normal,
  warning,
  exceeded,
}

class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel({required this.repository});

  final HotspotRepository repository;

  StreamSubscription<HotspotSnapshot>? _sub;
  HotspotSnapshot _snapshot = HotspotSnapshot.empty;
  List<DeviceHistorySummary> _knownDeviceHistory = const [];
  int _lastHistoryRefreshMs = 0;
  bool _isInitializing = true;
  bool _isBusy = false;
  String? _errorMessage;
  AppReleaseInfo? _availableUpdate;
  bool _isBackgroundServiceEnabled = false;
  bool _isBatteryOptimizationIgnored = false;

  HotspotSnapshot get snapshot => _snapshot;
  List<DeviceHistorySummary> get knownDeviceHistory => _knownDeviceHistory;
  bool get isInitializing => _isInitializing;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  AppReleaseInfo? get availableUpdate => _availableUpdate;
  bool get isBackgroundServiceEnabled => _isBackgroundServiceEnabled;
  bool get isBatteryOptimizationIgnored => _isBatteryOptimizationIgnored;

  QuotaConfig get globalQuota => repository.globalQuota;
  Map<String, DeviceQuota> get deviceQuotas => repository.deviceQuotas;

  double get quotaRatio {
    if (!globalQuota.enabled || globalQuota.limitBytes <= 0) return 0.0;
    return _snapshot.sessionTotalBytes / globalQuota.limitBytes;
  }

  double get quotaProgress => quotaRatio.clamp(0.0, 1.0);

  QuotaStatus get quotaStatus {
    if (!globalQuota.enabled) return QuotaStatus.disabled;
    if (quotaRatio >= 1.0) return QuotaStatus.exceeded;
    if (quotaRatio >= (globalQuota.warningPercent / 100.0)) {
      return QuotaStatus.warning;
    }
    return QuotaStatus.normal;
  }

  Future<void> initialize() async {
    _isInitializing = true;
    notifyListeners();

    _sub ??= repository.snapshots.listen(
      (snap) {
        _snapshot = snap;
        _errorMessage = null;
        _maybeRefreshHistory();
        notifyListeners();
      },
      onError: (Object err) {
        _errorMessage = err.toString();
        notifyListeners();
      },
    );

    try {
      await repository.initialize();
      _snapshot = repository.latest;
      _knownDeviceHistory = await repository.getAllDeviceHistory();
      _lastHistoryRefreshMs = DateTime.now().millisecondsSinceEpoch;
      final preferredBg =
          await repository.getPreferredBackgroundServiceEnabled();
      final isRunning = await repository.isBackgroundServiceEnabled();
      if (preferredBg && !isRunning) {
        await repository.setBackgroundServiceEnabled(true);
        _isBackgroundServiceEnabled = true;
      } else {
        _isBackgroundServiceEnabled = isRunning;
      }
      _isBatteryOptimizationIgnored =
          await repository.isBatteryOptimizationIgnored();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
    unawaited(checkForUpdate());
  }

  void _maybeRefreshHistory() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastHistoryRefreshMs < 6000) return;
    _lastHistoryRefreshMs = now;
    refreshDeviceHistory();
  }

  Future<void> refreshDeviceHistory() async {
    try {
      final list = await repository.getAllDeviceHistory();
      _knownDeviceHistory = list;
      notifyListeners();
    } catch (_) {}
  }

  ConnectedDevice? findDeviceById(String id) {
    for (final d in _snapshot.devices) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> openUsageAccessSettings() async {
    await repository.openUsageAccessSettings();
  }

  Future<bool> openUrl(String url) => repository.openUrl(url);

  Future<bool> requestRootAccess() async {
    _setBusy(true);
    try {
      final caps = await repository.requestRootAccess();
      return caps.rootGranted;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> toggleRootMode(bool enabled) async {
    _setBusy(true);
    try {
      await repository.setRootModeEnabled(enabled);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> scanNow() async {
    _setBusy(true);
    try {
      await repository.scanNow();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> resetSession() async {
    _setBusy(true);
    try {
      await repository.resetSession();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> renameDevice(String deviceId, String alias) async {
    await repository.setDeviceAlias(deviceId, alias);
    await refreshDeviceHistory();
  }

  Future<UsageReport> getUsageReport(
    HistoryRange range, {
    String? deviceId,
  }) => repository.getUsageReport(range, deviceId: deviceId);

  Future<DeviceHistorySummary?> getDeviceHistorySummary(String deviceId) =>
      repository.getDeviceHistorySummary(deviceId);

  Future<List<DeviceHistorySummary>> getAllDeviceHistory() =>
      repository.getAllDeviceHistory();

  Future<void> updateGlobalQuota(QuotaConfig config) async {
    await repository.setGlobalQuota(config);
    notifyListeners();
  }

  Future<void> updateDeviceQuota(DeviceQuota quota) async {
    await repository.setDeviceQuota(quota);
    notifyListeners();
  }

  Future<void> removeDeviceQuota(String deviceId) async {
    await repository.removeDeviceQuota(deviceId);
    notifyListeners();
  }

  Future<bool> toggleDeviceBlock(
    String ip, {
    String? mac,
    required bool blocked,
  }) async {
    final success = await repository.setDeviceBlocked(
      ip: ip,
      mac: mac,
      blocked: blocked,
    );
    notifyListeners();
    return success;
  }

  Future<void> clearHistory() async {
    await repository.clearHistory();
    _knownDeviceHistory = const [];
    notifyListeners();
  }

  Future<AppReleaseInfo?> checkForUpdate() async {
    try {
      final info = await repository.checkForUpdate();
      if (info != null && info.isNewer) {
        _availableUpdate = info;
        notifyListeners();
      }
      return info;
    } catch (_) {
      return null;
    }
  }

  void dismissUpdate() {
    _availableUpdate = null;
    notifyListeners();
  }

  Future<bool> openHotspotSettings() => repository.openHotspotSettings();

  Future<bool> toggleHotspot() => repository.toggleHotspot();

  Future<void> toggleBackgroundService(bool enabled) async {
    await repository.setPreferredBackgroundServiceEnabled(enabled);
    final ok = await repository.setBackgroundServiceEnabled(enabled);
    if (ok) {
      _isBackgroundServiceEnabled = enabled;
      notifyListeners();
    }
  }

  Future<void> requestIgnoreBatteryOptimization() async {
    await repository.requestIgnoreBatteryOptimization();
    _isBatteryOptimizationIgnored =
        await repository.isBatteryOptimizationIgnored();
    notifyListeners();
  }

  Future<void> refreshSystemSettingsState() async {
    _isBackgroundServiceEnabled =
        await repository.isBackgroundServiceEnabled();
    _isBatteryOptimizationIgnored =
        await repository.isBatteryOptimizationIgnored();
    notifyListeners();
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
