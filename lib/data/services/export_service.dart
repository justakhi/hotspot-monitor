import 'dart:convert';

import '../../domain/models/capability_state.dart';
import '../../domain/models/history_report.dart';
import '../../domain/models/service_usage.dart';
import '../../ui/core/utils/formatters.dart';

/// Formats hotspot traffic data, network capabilities, and device connection history
/// into RFC 4180 CSV and JSON files ready for export or sharing.
class ExportService {
  const ExportService();

  static const String appName = 'Hotspot Monitor';

  /// Exports a full usage report as CSV with metadata, device tables, and service breakdowns.
  String exportReportCsv(
    UsageReport report, {
    required CapabilityState capabilities,
    int? generatedMs,
  }) {
    final nowMs = generatedMs ?? DateTime.now().millisecondsSinceEpoch;
    final generatedAt = DateTime.fromMillisecondsSinceEpoch(nowMs).toIso8601String();
    final buffer = StringBuffer();

    // 1. Report Metadata
    buffer.writeln('# Hotspot Monitor - Traffic & Usage Report');
    buffer.writeln('# Application: $appName');
    buffer.writeln('# Export Time: $generatedAt (epoch: $nowMs)');
    buffer.writeln('# Period: ${report.range.title} (${report.range.shortLabel})');
    buffer.writeln('# Upstream Network: ${_csvCell(capabilities.upstreamDetails)}');
    buffer.writeln('# Upstream Interface: ${_csvCell(capabilities.upstreamInterface ?? "none")}');
    buffer.writeln('# Hotspot Interface: ${_csvCell(capabilities.hotspotInterface ?? "unknown")}');
    buffer.writeln('# Gateway IP: ${_csvCell(capabilities.gatewayIp ?? "unknown")}');
    buffer.writeln('# Total Download: ${Formatters.bytes(report.totalDownloadBytes)} (${report.totalDownloadBytes} bytes)');
    buffer.writeln('# Total Upload: ${Formatters.bytes(report.totalUploadBytes)} (${report.totalUploadBytes} bytes)');
    buffer.writeln('# Total Data: ${Formatters.bytes(report.totalBytes)} (${report.totalBytes} bytes)');
    buffer.writeln();

    // 2. Connected / Historical Devices
    buffer.writeln('--- PER-DEVICE USAGE BREAKDOWN ---');
    buffer.writeln(
      'Device ID,Name / Alias,IP Address,MAC Address,Vendor,Download Bytes,Download Formatted,Upload Bytes,Upload Formatted,Total Bytes,Total Formatted,First Seen,Last Seen',
    );
    for (final d in report.devices) {
      buffer.writeln([
        _csvCell(d.deviceId),
        _csvCell(d.displayName),
        _csvCell(d.ip),
        _csvCell(d.mac ?? 'N/A'),
        _csvCell(d.vendor),
        d.downloadBytes,
        _csvCell(Formatters.bytes(d.downloadBytes)),
        d.uploadBytes,
        _csvCell(Formatters.bytes(d.uploadBytes)),
        d.totalBytes,
        _csvCell(Formatters.bytes(d.totalBytes)),
        _csvCell(Formatters.fullDateTime(d.firstSeenMs)),
        _csvCell(Formatters.fullDateTime(d.lastSeenMs)),
      ].join(','));
    }
    buffer.writeln();

    // 3. Classified Services Breakdown
    buffer.writeln('--- IDENTIFIED SERVICES & DOMAINS ---');
    buffer.writeln(
      'Service ID,Service Name,Category,Download Bytes,Download Formatted,Upload Bytes,Upload Formatted,Total Bytes,Total Formatted,Top Domains / Endpoints',
    );
    for (final s in report.services) {
      final domains = s.topDomains.join('; ');
      buffer.writeln([
        _csvCell(s.serviceId),
        _csvCell(s.displayName),
        _csvCell(s.category),
        s.downloadBytes,
        _csvCell(Formatters.bytes(s.downloadBytes)),
        s.uploadBytes,
        _csvCell(Formatters.bytes(s.uploadBytes)),
        s.totalBytes,
        _csvCell(Formatters.bytes(s.totalBytes)),
        _csvCell(domains),
      ].join(','));
    }
    buffer.writeln();

    // 4. Timeline Data Points
    buffer.writeln('--- TIMELINE INTERVALS ---');
    buffer.writeln(
      'Interval Label,Bucket Start Timestamp (ms),Bucket Start Time,Download Bytes,Download Formatted,Upload Bytes,Upload Formatted,Total Bytes,Total Formatted',
    );
    for (final p in report.timeline) {
      final timeStr = DateTime.fromMillisecondsSinceEpoch(p.bucketStartMs).toIso8601String();
      buffer.writeln([
        _csvCell(p.label),
        p.bucketStartMs,
        _csvCell(timeStr),
        p.downloadBytes,
        _csvCell(Formatters.bytes(p.downloadBytes)),
        p.uploadBytes,
        _csvCell(Formatters.bytes(p.uploadBytes)),
        p.totalBytes,
        _csvCell(Formatters.bytes(p.totalBytes)),
      ].join(','));
    }

    return buffer.toString();
  }

  /// Exports a full usage report as structured JSON.
  String exportReportJson(
    UsageReport report, {
    required CapabilityState capabilities,
    int? generatedMs,
  }) {
    final nowMs = generatedMs ?? DateTime.now().millisecondsSinceEpoch;
    final payload = {
      'metadata': {
        'appName': appName,
        'generatedAtMs': nowMs,
        'generatedAt': DateTime.fromMillisecondsSinceEpoch(nowMs).toIso8601String(),
        'range': report.range.shortLabel,
        'rangeTitle': report.range.title,
      },
      'network': {
        'upstreamConnected': capabilities.upstreamConnected,
        'upstreamType': capabilities.upstreamType,
        'upstreamInterface': capabilities.upstreamInterface,
        'upstreamCarrier': capabilities.upstreamCarrier,
        'upstreamDetails': capabilities.upstreamDetails,
        'hotspotActive': capabilities.hotspotActive,
        'hotspotInterface': capabilities.hotspotInterface,
        'gatewayIp': capabilities.gatewayIp,
        'prefixLength': capabilities.prefixLength,
        'tetherType': capabilities.tetherType,
      },
      'totals': {
        'downloadBytes': report.totalDownloadBytes,
        'downloadFormatted': Formatters.bytes(report.totalDownloadBytes),
        'uploadBytes': report.totalUploadBytes,
        'uploadFormatted': Formatters.bytes(report.totalUploadBytes),
        'totalBytes': report.totalBytes,
        'totalFormatted': Formatters.bytes(report.totalBytes),
      },
      'devices': report.devices.map((d) => {
        'deviceId': d.deviceId,
        'name': d.displayName,
        'ip': d.ip,
        'mac': d.mac,
        'vendor': d.vendor,
        'isRandomizedMac': d.isRandomizedMac,
        'firstSeenMs': d.firstSeenMs,
        'lastSeenMs': d.lastSeenMs,
        'downloadBytes': d.downloadBytes,
        'uploadBytes': d.uploadBytes,
        'totalBytes': d.totalBytes,
      }).toList(),
      'services': report.services.map((s) => {
        'serviceId': s.serviceId,
        'displayName': s.displayName,
        'category': s.category,
        'downloadBytes': s.downloadBytes,
        'uploadBytes': s.uploadBytes,
        'totalBytes': s.totalBytes,
        'topDomains': s.topDomains,
        'endpoints': s.endpoints.map((e) => {
          'endpoint': e.endpoint,
          'downloadBytes': e.downloadBytes,
          'uploadBytes': e.uploadBytes,
        }).toList(),
      }).toList(),
      'timeline': report.timeline.map((p) => {
        'label': p.label,
        'bucketStartMs': p.bucketStartMs,
        'downloadBytes': p.downloadBytes,
        'uploadBytes': p.uploadBytes,
        'totalBytes': p.totalBytes,
      }).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Exports all device connection history and network logs as CSV.
  String exportConnectionLogsCsv(
    List<DeviceHistorySummary> devices, {
    required CapabilityState capabilities,
    int? generatedMs,
  }) {
    final nowMs = generatedMs ?? DateTime.now().millisecondsSinceEpoch;
    final generatedAt = DateTime.fromMillisecondsSinceEpoch(nowMs).toIso8601String();
    final buffer = StringBuffer();

    buffer.writeln('# Hotspot Monitor - Device Connection History & Logs');
    buffer.writeln('# Application: $appName');
    buffer.writeln('# Export Time: $generatedAt (epoch: $nowMs)');
    buffer.writeln('# Upstream Network: ${_csvCell(capabilities.upstreamDetails)}');
    buffer.writeln('# Hotspot Interface: ${_csvCell(capabilities.hotspotInterface ?? "unknown")}');
    buffer.writeln('# Total Devices Recorded: ${devices.length}');
    buffer.writeln();

    buffer.writeln(
      'Device ID,Name / Alias,IP Address,MAC Address,Vendor,Randomized MAC,First Seen Date,Last Seen Date,Download Bytes,Download Formatted,Upload Bytes,Upload Formatted,Total Bytes,Total Formatted',
    );

    for (final d in devices) {
      buffer.writeln([
        _csvCell(d.deviceId),
        _csvCell(d.displayName),
        _csvCell(d.ip),
        _csvCell(d.mac ?? 'N/A'),
        _csvCell(d.vendor),
        d.isRandomizedMac ? 'Yes' : 'No',
        _csvCell(Formatters.fullDateTime(d.firstSeenMs)),
        _csvCell(Formatters.fullDateTime(d.lastSeenMs)),
        d.downloadBytes,
        _csvCell(Formatters.bytes(d.downloadBytes)),
        d.uploadBytes,
        _csvCell(Formatters.bytes(d.uploadBytes)),
        d.totalBytes,
        _csvCell(Formatters.bytes(d.totalBytes)),
      ].join(','));
    }

    return buffer.toString();
  }

  /// Exports detailed device traffic history and services as CSV.
  String exportDeviceHistoryCsv(
    DeviceHistorySummary device,
    List<ServiceUsage> services,
    List<TimelinePoint> timeline, {
    required CapabilityState capabilities,
    int? generatedMs,
  }) {
    final nowMs = generatedMs ?? DateTime.now().millisecondsSinceEpoch;
    final generatedAt = DateTime.fromMillisecondsSinceEpoch(nowMs).toIso8601String();
    final buffer = StringBuffer();

    buffer.writeln('# Hotspot Monitor - Single Device Usage Log');
    buffer.writeln('# Application: $appName');
    buffer.writeln('# Export Time: $generatedAt (epoch: $nowMs)');
    buffer.writeln('# Device: ${_csvCell(device.displayName)} (${device.ip})');
    buffer.writeln('# MAC: ${_csvCell(device.mac ?? "N/A")} · Vendor: ${_csvCell(device.vendor)}');
    buffer.writeln('# Upstream Network: ${_csvCell(capabilities.upstreamDetails)}');
    buffer.writeln('# Hotspot Interface: ${_csvCell(capabilities.hotspotInterface ?? "unknown")}');
    buffer.writeln('# First Seen: ${_csvCell(Formatters.fullDateTime(device.firstSeenMs))}');
    buffer.writeln('# Last Seen: ${_csvCell(Formatters.fullDateTime(device.lastSeenMs))}');
    buffer.writeln('# Total Data: ${Formatters.bytes(device.totalBytes)} (↓ ${Formatters.bytes(device.downloadBytes)}, ↑ ${Formatters.bytes(device.uploadBytes)})');
    buffer.writeln();

    buffer.writeln('--- APP & SERVICE TRAFFIC ---');
    buffer.writeln(
      'Service Name,Category,Download Bytes,Download Formatted,Upload Bytes,Upload Formatted,Total Bytes,Top Domains / Endpoints',
    );
    for (final s in services) {
      final domains = s.topDomains.join('; ');
      buffer.writeln([
        _csvCell(s.displayName),
        _csvCell(s.category),
        s.downloadBytes,
        _csvCell(Formatters.bytes(s.downloadBytes)),
        s.uploadBytes,
        _csvCell(Formatters.bytes(s.uploadBytes)),
        s.totalBytes,
        _csvCell(domains),
      ].join(','));
    }
    buffer.writeln();

    buffer.writeln('--- TIMELINE ACTIVITY ---');
    buffer.writeln('Interval Label,Bucket Timestamp,Download Formatted,Upload Formatted,Total Formatted');
    for (final p in timeline) {
      buffer.writeln([
        _csvCell(p.label),
        p.bucketStartMs,
        _csvCell(Formatters.bytes(p.downloadBytes)),
        _csvCell(Formatters.bytes(p.uploadBytes)),
        _csvCell(Formatters.bytes(p.totalBytes)),
      ].join(','));
    }

    return buffer.toString();
  }

  static String _csvCell(String text) {
    if (text.contains(',') || text.contains('"') || text.contains('\n') || text.contains('\r')) {
      return '"${text.replaceAll('"', '""')}"';
    }
    return text;
  }
}
