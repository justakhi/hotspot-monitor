import 'service_usage.dart';

enum HistoryRange {
  hour('1H', 'Last 1 Hour'),
  day('Day', 'Today'),
  month('Month', 'This Month'),
  year('Year', 'This Year'),
  all('All', 'All Time');

  const HistoryRange(this.shortLabel, this.title);

  final String shortLabel;
  final String title;
}

class TimelinePoint {
  const TimelinePoint({
    required this.label,
    required this.bucketStartMs,
    required this.downloadBytes,
    required this.uploadBytes,
  });

  final String label;
  final int bucketStartMs;
  final int downloadBytes;
  final int uploadBytes;

  int get totalBytes => downloadBytes + uploadBytes;
}

class DeviceHistorySummary {
  const DeviceHistorySummary({
    required this.deviceId,
    required this.ip,
    required this.mac,
    required this.hostname,
    required this.vendor,
    required this.isRandomizedMac,
    required this.customAlias,
    required this.downloadBytes,
    required this.uploadBytes,
    required this.firstSeenMs,
    required this.lastSeenMs,
  });

  final String deviceId;
  final String ip;
  final String? mac;
  final String? hostname;
  final String vendor;
  final bool isRandomizedMac;
  final String? customAlias;
  final int downloadBytes;
  final int uploadBytes;
  final int firstSeenMs;
  final int lastSeenMs;

  int get totalBytes => downloadBytes + uploadBytes;

  String get displayName {
    if (deviceId == '_hotspot_total_') return 'Hotspot Total (Non-Root)';
    if (customAlias != null && customAlias!.trim().isNotEmpty) {
      return customAlias!.trim();
    }
    if (hostname != null && hostname!.trim().isNotEmpty) {
      return hostname!.trim();
    }
    return ip;
  }
}

class UsageReport {
  const UsageReport({
    required this.range,
    required this.totalDownloadBytes,
    required this.totalUploadBytes,
    required this.timeline,
    required this.devices,
    required this.services,
    this.servicesByDevice = const {},
  });

  static const UsageReport empty = UsageReport(
    range: HistoryRange.day,
    totalDownloadBytes: 0,
    totalUploadBytes: 0,
    timeline: [],
    devices: [],
    services: [],
    servicesByDevice: {},
  );

  final HistoryRange range;
  final int totalDownloadBytes;
  final int totalUploadBytes;
  final List<TimelinePoint> timeline;
  final List<DeviceHistorySummary> devices;
  final List<ServiceUsage> services;
  final Map<String, List<ServiceUsage>> servicesByDevice;

  int get totalBytes => totalDownloadBytes + totalUploadBytes;
}
