import 'service_usage.dart';

/// Represents a client device connected to (or recently seen on) the hotspot.
class ConnectedDevice {
  const ConnectedDevice({
    required this.id,
    required this.ip,
    required this.mac,
    required this.hostname,
    required this.customAlias,
    required this.vendor,
    required this.isRandomizedMac,
    required this.neighborState,
    required this.rssiDbm,
    required this.txBitrateMbps,
    required this.rxBitrateMbps,
    required this.isOnline,
    required this.lastSeenMs,
    required this.downloadBytes,
    required this.uploadBytes,
    required this.currentDownloadBps,
    required this.currentUploadBps,
    required this.services,
  });

  factory ConnectedDevice.fromMap(
    Map<Object?, Object?> map, {
    String? customAlias,
  }) {
    final rawServices = map['services'] as List<Object?>? ?? const [];
    final services = rawServices
        .whereType<Map<Object?, Object?>>()
        .map(ServiceUsage.fromMap)
        .toList(growable: false);

    return ConnectedDevice(
      id: (map['id'] as String?) ?? (map['ip'] as String? ?? 'unknown'),
      ip: (map['ip'] as String?) ?? '0.0.0.0',
      mac: map['mac'] as String?,
      hostname: map['hostname'] as String?,
      customAlias: customAlias,
      vendor: (map['vendor'] as String?) ?? 'Unknown',
      isRandomizedMac: map['isRandomizedMac'] == true,
      neighborState: (map['neighborState'] as String?) ?? 'UNKNOWN',
      rssiDbm: (map['rssiDbm'] as num?)?.toInt(),
      txBitrateMbps: (map['txBitrateMbps'] as num?)?.toDouble(),
      rxBitrateMbps: (map['rxBitrateMbps'] as num?)?.toDouble(),
      isOnline: map['isOnline'] == true,
      lastSeenMs: (map['lastSeenMs'] as num?)?.toInt() ?? 0,
      downloadBytes: (map['downloadBytes'] as num?)?.toInt() ?? 0,
      uploadBytes: (map['uploadBytes'] as num?)?.toInt() ?? 0,
      currentDownloadBps: (map['currentDownloadBps'] as num?)?.toInt() ?? 0,
      currentUploadBps: (map['currentUploadBps'] as num?)?.toInt() ?? 0,
      services: services,
    );
  }

  final String id;
  final String ip;
  final String? mac;
  final String? hostname;
  final String? customAlias;
  final String vendor;
  final bool isRandomizedMac;
  final String neighborState;
  final int? rssiDbm;
  final double? txBitrateMbps;
  final double? rxBitrateMbps;
  final bool isOnline;
  final int lastSeenMs;
  final int downloadBytes;
  final int uploadBytes;
  final int currentDownloadBps;
  final int currentUploadBps;
  final List<ServiceUsage> services;

  int get totalBytes => downloadBytes + uploadBytes;
  int get currentTotalBps => currentDownloadBps + currentUploadBps;

  String get displayName {
    if (customAlias != null && customAlias!.trim().isNotEmpty) {
      return customAlias!.trim();
    }
    if (hostname != null && hostname!.trim().isNotEmpty) {
      return hostname!.trim();
    }
    return ip;
  }

  ConnectedDevice copyWith({String? customAlias}) {
    return ConnectedDevice(
      id: id,
      ip: ip,
      mac: mac,
      hostname: hostname,
      customAlias: customAlias,
      vendor: vendor,
      isRandomizedMac: isRandomizedMac,
      neighborState: neighborState,
      rssiDbm: rssiDbm,
      txBitrateMbps: txBitrateMbps,
      rxBitrateMbps: rxBitrateMbps,
      isOnline: isOnline,
      lastSeenMs: lastSeenMs,
      downloadBytes: downloadBytes,
      uploadBytes: uploadBytes,
      currentDownloadBps: currentDownloadBps,
      currentUploadBps: currentUploadBps,
      services: services,
    );
  }
}
