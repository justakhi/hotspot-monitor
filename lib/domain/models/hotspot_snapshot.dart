import 'capability_state.dart';
import 'connected_device.dart';
import 'service_usage.dart';

enum MonitorMode { nonRoot, root }

/// Full telemetry snapshot emitted by the native Android engine.
class HotspotSnapshot {
  const HotspotSnapshot({
    required this.timestampMs,
    required this.sessionStartMs,
    required this.mode,
    required this.capabilities,
    required this.probeActive,
    required this.probeError,
    required this.sessionDownloadBytes,
    required this.sessionUploadBytes,
    required this.liveDownloadBps,
    required this.liveUploadBps,
    required this.devices,
    required this.topServices,
  });

  factory HotspotSnapshot.fromMap(
    Map<Object?, Object?> map, {
    Map<String, String> aliases = const {},
  }) {
    final capMap = map['capabilities'] as Map<Object?, Object?>? ?? const {};
    final rawDevices = map['devices'] as List<Object?>? ?? const [];
    final devices = rawDevices
        .whereType<Map<Object?, Object?>>()
        .map((d) {
          final id = (d['id'] as String?) ?? (d['ip'] as String? ?? '');
          return ConnectedDevice.fromMap(d, customAlias: aliases[id]);
        })
        .toList(growable: false);

    final modeStr = map['mode'] as String?;
    return HotspotSnapshot(
      timestampMs: (map['timestampMs'] as num?)?.toInt() ?? 0,
      sessionStartMs: (map['sessionStartMs'] as num?)?.toInt() ?? 0,
      mode: modeStr == 'root' ? MonitorMode.root : MonitorMode.nonRoot,
      capabilities: CapabilityState.fromMap(capMap),
      probeActive: map['probeActive'] == true,
      probeError: map['probeError'] as String?,
      sessionDownloadBytes:
          (map['sessionDownloadBytes'] as num?)?.toInt() ?? 0,
      sessionUploadBytes: (map['sessionUploadBytes'] as num?)?.toInt() ?? 0,
      liveDownloadBps: (map['liveDownloadBps'] as num?)?.toInt() ?? 0,
      liveUploadBps: (map['liveUploadBps'] as num?)?.toInt() ?? 0,
      devices: devices,
      topServices: aggregateServices(devices),
    );
  }

  static final HotspotSnapshot empty = HotspotSnapshot(
    timestampMs: 0,
    sessionStartMs: DateTime.now().millisecondsSinceEpoch,
    mode: MonitorMode.nonRoot,
    capabilities: CapabilityState.initial,
    probeActive: false,
    probeError: null,
    sessionDownloadBytes: 0,
    sessionUploadBytes: 0,
    liveDownloadBps: 0,
    liveUploadBps: 0,
    devices: const [],
    topServices: const [],
  );

  final int timestampMs;
  final int sessionStartMs;
  final MonitorMode mode;
  final CapabilityState capabilities;
  final bool probeActive;
  final String? probeError;
  final int sessionDownloadBytes;
  final int sessionUploadBytes;
  final int liveDownloadBps;
  final int liveUploadBps;
  final List<ConnectedDevice> devices;
  final List<ServiceUsage> topServices;

  int get sessionTotalBytes => sessionDownloadBytes + sessionUploadBytes;
  int get liveTotalBps => liveDownloadBps + liveUploadBps;
  int get onlineDeviceCount => devices.where((d) => d.isOnline).length;
  bool get isRootMode => mode == MonitorMode.root;

  HotspotSnapshot withAliases(Map<String, String> aliases) {
    final updated = devices
        .map((d) => d.copyWith(customAlias: aliases[d.id]))
        .toList(growable: false);
    return HotspotSnapshot(
      timestampMs: timestampMs,
      sessionStartMs: sessionStartMs,
      mode: mode,
      capabilities: capabilities,
      probeActive: probeActive,
      probeError: probeError,
      sessionDownloadBytes: sessionDownloadBytes,
      sessionUploadBytes: sessionUploadBytes,
      liveDownloadBps: liveDownloadBps,
      liveUploadBps: liveUploadBps,
      devices: updated,
      topServices: topServices,
    );
  }

  static List<ServiceUsage> aggregateServices(List<ConnectedDevice> devices) {
    final byId = <String, _ServiceAccumulator>{};
    for (final device in devices) {
      for (final svc in device.services) {
        final acc = byId.putIfAbsent(
          svc.serviceId,
          () => _ServiceAccumulator(
            serviceId: svc.serviceId,
            displayName: svc.displayName,
            category: svc.category,
          ),
        );
        acc.downloadBytes += svc.downloadBytes;
        acc.uploadBytes += svc.uploadBytes;
        if (svc.lastActiveMs > acc.lastActiveMs) {
          acc.lastActiveMs = svc.lastActiveMs;
        }
        for (final domain in svc.topDomains) {
          if (acc.domains.length < 6) acc.domains.add(domain);
        }
        for (final ep in svc.endpoints) {
          final existingEp = acc.endpoints[ep.endpoint];
          if (existingEp == null) {
            acc.endpoints[ep.endpoint] = EndpointUsage(
              endpoint: ep.endpoint,
              downloadBytes: ep.downloadBytes,
              uploadBytes: ep.uploadBytes,
              lastActiveMs: ep.lastActiveMs,
            );
          } else {
            acc.endpoints[ep.endpoint] = EndpointUsage(
              endpoint: ep.endpoint,
              downloadBytes: existingEp.downloadBytes + ep.downloadBytes,
              uploadBytes: existingEp.uploadBytes + ep.uploadBytes,
              lastActiveMs: ep.lastActiveMs > existingEp.lastActiveMs
                  ? ep.lastActiveMs
                  : existingEp.lastActiveMs,
            );
          }
        }
      }
    }

    final list = byId.values
        .map(
          (a) {
            final eps = a.endpoints.values.toList()
              ..sort((x, y) => y.totalBytes.compareTo(x.totalBytes));
            return ServiceUsage(
              serviceId: a.serviceId,
              displayName: a.displayName,
              category: a.category,
              downloadBytes: a.downloadBytes,
              uploadBytes: a.uploadBytes,
              topDomains: a.domains.toList(growable: false),
              lastActiveMs: a.lastActiveMs,
              endpoints: eps.take(15).toList(growable: false),
            );
          },
        )
        .toList();
    list.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
    return list;
  }
}

class _ServiceAccumulator {
  _ServiceAccumulator({
    required this.serviceId,
    required this.displayName,
    required this.category,
  });

  final String serviceId;
  final String displayName;
  final String category;
  int downloadBytes = 0;
  int uploadBytes = 0;
  int lastActiveMs = 0;
  final Set<String> domains = <String>{};
  final Map<String, EndpointUsage> endpoints = <String, EndpointUsage>{};
}
