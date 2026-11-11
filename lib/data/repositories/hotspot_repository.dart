import 'dart:async';

import '../../domain/models/capability_state.dart';
import '../../domain/models/history_report.dart';
import '../../domain/models/hotspot_snapshot.dart';
import '../../domain/models/service_usage.dart';
import '../services/device_alias_service.dart';
import '../services/history_store.dart';
import '../services/hotspot_platform_service.dart';

/// Single source of truth merging native telemetry, aliases, and SQLite history.
class HotspotRepository {
  HotspotRepository({
    required this.platformService,
    required this.aliasService,
    HistoryStore? historyStore,
  }) : historyStore = historyStore ?? SqliteHistoryStore();

  final HotspotPlatformService platformService;
  final DeviceAliasService aliasService;
  final HistoryStore historyStore;

  Map<String, String> _aliases = const {};
  HotspotSnapshot _latest = HotspotSnapshot.empty;
  final StreamController<HotspotSnapshot> _controller =
      StreamController<HotspotSnapshot>.broadcast();
  StreamSubscription<Map<Object?, Object?>>? _nativeSub;

  final Map<String, ({int rx, int tx})> _lastRecordedByKey = {};
  final Map<String, ({int rx, int tx})> _lastEndpointByKey = {};
  (int rx, int tx) _lastNonRootTotals = (0, 0);
  Future<void> _writeQueue = Future<void>.value();

  HotspotSnapshot get latest => _latest;
  Map<String, String> get aliases => _aliases;
  Stream<HotspotSnapshot> get snapshots => _controller.stream;

  Future<void> initialize() async {
    await historyStore.initialize();
    _aliases = await aliasService.loadAliases();
    _nativeSub ??= platformService.telemetryStream.listen(
      (rawMap) {
        final snap = HotspotSnapshot.fromMap(rawMap, aliases: _aliases);
        _latest = snap;
        _enqueueRecord(snap);
        if (!_controller.isClosed) {
          _controller.add(_latest);
        }
      },
      onError: (Object error) {
        if (!_controller.isClosed) {
          _controller.addError(error);
        }
      },
    );

    var caps = await platformService.getCapabilities();
    if (!caps.rootGranted) {
      caps = await platformService.requestRootAccess();
    }
    _applyCapabilities(caps);
  }

  Future<CapabilityState> refreshCapabilities() =>
      platformService.getCapabilities();

  Future<void> openUsageAccessSettings() =>
      platformService.openUsageAccessSettings();

  Future<bool> openUrl(String url) => platformService.openUrl(url);

  Future<CapabilityState> requestRootAccess() async {
    final caps = await platformService.requestRootAccess();
    _applyCapabilities(caps);
    await scanNow();
    return caps;
  }

  Future<CapabilityState> setRootModeEnabled(bool enabled) async {
    final caps = await platformService.setRootModeEnabled(enabled);
    _applyCapabilities(caps);
    await scanNow();
    return caps;
  }

  Future<void> resetSession() async {
    _lastRecordedByKey.clear();
    _lastEndpointByKey.clear();
    _lastNonRootTotals = (0, 0);
    await platformService.resetSession();
    await scanNow();
  }

  Future<HotspotSnapshot> scanNow() async {
    final raw = await platformService.scanNow();
    if (raw.isNotEmpty) {
      final snap = HotspotSnapshot.fromMap(raw, aliases: _aliases);
      _latest = snap;
      _enqueueRecord(snap);
      if (!_controller.isClosed) {
        _controller.add(_latest);
      }
    }
    return _latest;
  }

  Future<void> setDeviceAlias(String deviceId, String alias) async {
    _aliases = await aliasService.saveAlias(deviceId, alias);
    _latest = _latest.withAliases(_aliases);
    if (!_controller.isClosed) {
      _controller.add(_latest);
    }
  }

  Future<UsageReport> getUsageReport(
    HistoryRange range, {
    String? deviceId,
    DateTime? now,
  }) async {
    await _writeQueue;
    return historyStore.queryReport(
      range: range,
      aliases: _aliases,
      deviceId: deviceId,
      now: now,
    );
  }

  Future<DeviceHistorySummary?> getDeviceHistorySummary(String deviceId) async {
    await _writeQueue;
    return historyStore.queryDeviceSummary(deviceId, aliases: _aliases);
  }

  Future<List<DeviceHistorySummary>> getAllDeviceHistory() async {
    await _writeQueue;
    return historyStore.queryAllDevices(aliases: _aliases);
  }

  Future<void> clearHistory() async {
    await _writeQueue;
    await historyStore.clearAll();
  }

  void _enqueueRecord(HotspotSnapshot snap) {
    _writeQueue = _writeQueue
        .then((_) => _recordSnapshotDeltas(snap))
        .catchError((Object _) {});
  }

  Future<void> _recordSnapshotDeltas(HotspotSnapshot snap) async {
    final ts = snap.timestampMs > 0
        ? snap.timestampMs
        : DateTime.now().millisecondsSinceEpoch;
    final deltas = <UsageDeltaRecord>[];

    if (snap.isRootMode) {
      for (final device in snap.devices) {
        if (device.services.isEmpty && device.totalBytes > 0) {
          final key = '${device.id}|unclassified';
          final prev = _lastRecordedByKey[key];
          final dRx = prev == null || device.downloadBytes < prev.rx
              ? device.downloadBytes
              : device.downloadBytes - prev.rx;
          final dTx = prev == null || device.uploadBytes < prev.tx
              ? device.uploadBytes
              : device.uploadBytes - prev.tx;
          _lastRecordedByKey[key] = (rx: device.downloadBytes, tx: device.uploadBytes);
          if (dRx > 0 || dTx > 0) {
            deltas.add(
              UsageDeltaRecord(
                deviceId: device.id,
                serviceId: 'unclassified',
                displayName: 'Other IP Traffic',
                category: 'Other',
                topDomains: const [],
                downloadDelta: dRx,
                uploadDelta: dTx,
              ),
            );
          }
          continue;
        }

        for (final svc in device.services) {
          final key = '${device.id}|${svc.serviceId}';
          final prev = _lastRecordedByKey[key];
          final dRx = prev == null || svc.downloadBytes < prev.rx
              ? svc.downloadBytes
              : svc.downloadBytes - prev.rx;
          final dTx = prev == null || svc.uploadBytes < prev.tx
              ? svc.uploadBytes
              : svc.uploadBytes - prev.tx;
          _lastRecordedByKey[key] = (rx: svc.downloadBytes, tx: svc.uploadBytes);
          final endpointDeltas = <EndpointUsage>[];
          for (final ep in svc.endpoints) {
            final epKey = '$key|${ep.endpoint}';
            final prevEp = _lastEndpointByKey[epKey];
            final epDRx = prevEp == null || ep.downloadBytes < prevEp.rx
                ? ep.downloadBytes
                : ep.downloadBytes - prevEp.rx;
            final epDTx = prevEp == null || ep.uploadBytes < prevEp.tx
                ? ep.uploadBytes
                : ep.uploadBytes - prevEp.tx;
            _lastEndpointByKey[epKey] = (
              rx: ep.downloadBytes,
              tx: ep.uploadBytes,
            );
            if (epDRx > 0 || epDTx > 0) {
              endpointDeltas.add(
                EndpointUsage(
                  endpoint: ep.endpoint,
                  downloadBytes: epDRx,
                  uploadBytes: epDTx,
                  lastActiveMs: ep.lastActiveMs,
                ),
              );
            }
          }
          if (dRx > 0 || dTx > 0) {
            deltas.add(
              UsageDeltaRecord(
                deviceId: device.id,
                serviceId: svc.serviceId,
                displayName: svc.displayName,
                category: svc.category,
                topDomains: svc.topDomains,
                downloadDelta: dRx,
                uploadDelta: dTx,
                endpoints: endpointDeltas,
              ),
            );
          }
        }
      }
    } else {
      final rx = snap.sessionDownloadBytes;
      final tx = snap.sessionUploadBytes;
      final dRx = rx < _lastNonRootTotals.$1 ? rx : rx - _lastNonRootTotals.$1;
      final dTx = tx < _lastNonRootTotals.$2 ? tx : tx - _lastNonRootTotals.$2;
      _lastNonRootTotals = (rx, tx);
      if (dRx > 0 || dTx > 0) {
        deltas.add(
          UsageDeltaRecord(
            deviceId: '_hotspot_total_',
            serviceId: 'tether_total',
            displayName: 'Hotspot Total (Non-Root)',
            category: 'Network',
            topDomains: const [],
            downloadDelta: dRx,
            uploadDelta: dTx,
          ),
        );
      }
    }

    if (snap.devices.isNotEmpty || deltas.isNotEmpty) {
      await historyStore.recordBatch(
        timestampMs: ts,
        devices: snap.devices,
        deltas: deltas,
      );
    }
  }

  void _applyCapabilities(CapabilityState caps) {
    _latest = HotspotSnapshot(
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      sessionStartMs: _latest.sessionStartMs,
      mode: caps.rootGranted ? MonitorMode.root : MonitorMode.nonRoot,
      capabilities: caps,
      probeActive: _latest.probeActive,
      probeError: _latest.probeError,
      sessionDownloadBytes: _latest.sessionDownloadBytes,
      sessionUploadBytes: _latest.sessionUploadBytes,
      liveDownloadBps: _latest.liveDownloadBps,
      liveUploadBps: _latest.liveUploadBps,
      devices: _latest.devices,
      topServices: _latest.topServices,
    );
    if (!_controller.isClosed) {
      _controller.add(_latest);
    }
  }

  void dispose() {
    _nativeSub?.cancel();
    _nativeSub = null;
    historyStore.close();
    _controller.close();
  }
}
