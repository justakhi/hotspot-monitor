/// Represents traffic to a specific domain or IP:port inside a service.
class EndpointUsage {
  const EndpointUsage({
    required this.endpoint,
    required this.downloadBytes,
    required this.uploadBytes,
    required this.lastActiveMs,
  });

  factory EndpointUsage.fromMap(Map<Object?, Object?> map) {
    return EndpointUsage(
      endpoint: (map['endpoint'] as String?) ?? '',
      downloadBytes: (map['downloadBytes'] as num?)?.toInt() ?? 0,
      uploadBytes: (map['uploadBytes'] as num?)?.toInt() ?? 0,
      lastActiveMs: (map['lastActiveMs'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> toJson() => {
    'endpoint': endpoint,
    'downloadBytes': downloadBytes,
    'uploadBytes': uploadBytes,
    'lastActiveMs': lastActiveMs,
  };

  final String endpoint;
  final int downloadBytes;
  final int uploadBytes;
  final int lastActiveMs;

  int get totalBytes => downloadBytes + uploadBytes;
}

/// Represents data consumed by a specific service (e.g. YouTube, WhatsApp).
class ServiceUsage {
  const ServiceUsage({
    required this.serviceId,
    required this.displayName,
    required this.category,
    required this.downloadBytes,
    required this.uploadBytes,
    required this.topDomains,
    required this.lastActiveMs,
    this.endpoints = const [],
  });

  factory ServiceUsage.fromMap(Map<Object?, Object?> map) {
    final rawDomains = map['topDomains'] as List<Object?>? ?? const [];
    final rawEndpoints = map['endpoints'] as List<Object?>? ?? const [];
    final endpoints = rawEndpoints
        .whereType<Map<Object?, Object?>>()
        .map(EndpointUsage.fromMap)
        .where((e) => e.endpoint.isNotEmpty)
        .toList(growable: false);

    return ServiceUsage(
      serviceId: (map['serviceId'] as String?) ?? 'unknown',
      displayName: (map['displayName'] as String?) ?? 'Unknown',
      category: (map['category'] as String?) ?? 'Other',
      downloadBytes: (map['downloadBytes'] as num?)?.toInt() ?? 0,
      uploadBytes: (map['uploadBytes'] as num?)?.toInt() ?? 0,
      topDomains: rawDomains.whereType<String>().toList(growable: false),
      lastActiveMs: (map['lastActiveMs'] as num?)?.toInt() ?? 0,
      endpoints: endpoints,
    );
  }

  final String serviceId;
  final String displayName;
  final String category;
  final int downloadBytes;
  final int uploadBytes;
  final List<String> topDomains;
  final int lastActiveMs;
  final List<EndpointUsage> endpoints;

  int get totalBytes => downloadBytes + uploadBytes;
}
