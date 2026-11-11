import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/repositories/hotspot_repository.dart';
import '../../../../domain/models/connected_device.dart';
import '../../../../domain/models/history_report.dart';
import '../../../../domain/models/hotspot_snapshot.dart';

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

  HotspotSnapshot get snapshot => _snapshot;
  List<DeviceHistorySummary> get knownDeviceHistory => _knownDeviceHistory;
  bool get isInitializing => _isInitializing;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;

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
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
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

  Future<void> clearHistory() async {
    await repository.clearHistory();
    _knownDeviceHistory = const [];
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
