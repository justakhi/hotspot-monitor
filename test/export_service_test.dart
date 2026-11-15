import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotspot_monitor/data/services/export_service.dart';
import 'package:hotspot_monitor/domain/models/capability_state.dart';
import 'package:hotspot_monitor/domain/models/history_report.dart';
import 'package:hotspot_monitor/domain/models/service_usage.dart';

void main() {
  const exportService = ExportService();

  const testCaps = CapabilityState(
    usageAccessGranted: true,
    rootBinaryPresent: true,
    rootGranted: true,
    nativeProbeAvailable: true,
    hotspotActive: true,
    hotspotInterface: 'wlan1',
    gatewayIp: '192.168.43.1',
    prefixLength: 24,
    tetherType: 'wifi_ap',
    upstreamConnected: true,
    upstreamType: 'cellular',
    upstreamInterface: 'rmnet_data0',
    upstreamCarrier: 'Jio 5G',
    upstreamDetails: 'Jio 5G Mobile Data',
  );

  const testDevice = DeviceHistorySummary(
    deviceId: '192.168.43.100',
    ip: '192.168.43.100',
    mac: 'F0:77:C3:D4:83:E3',
    hostname: 'DESKTOP-PC',
    vendor: 'Intel Corporate',
    isRandomizedMac: false,
    customAlias: 'My Work Laptop',
    downloadBytes: 104857600, // 100 MB
    uploadBytes: 20971520, // 20 MB
    firstSeenMs: 1700000000000,
    lastSeenMs: 1700003600000,
  );

  const testService = ServiceUsage(
    serviceId: 'youtube',
    displayName: 'YouTube',
    category: 'Streaming',
    downloadBytes: 83886080,
    uploadBytes: 2097152,
    topDomains: ['googlevideo.com', 'youtube.com'],
    lastActiveMs: 1700003600000,
  );

  const testTimeline = TimelinePoint(
    label: '12:00',
    bucketStartMs: 1700000000000,
    downloadBytes: 52428800,
    uploadBytes: 10485760,
  );

  final testReport = UsageReport(
    range: HistoryRange.day,
    totalDownloadBytes: 104857600,
    totalUploadBytes: 20971520,
    timeline: const [testTimeline],
    devices: const [testDevice],
    services: const [testService],
  );

  test('ExportService generates valid CSV with headers, devices, and services', () {
    final csv = exportService.exportReportCsv(
      testReport,
      capabilities: testCaps,
      generatedMs: 1700005000000,
    );

    expect(csv.contains('# Hotspot Monitor - Traffic & Usage Report'), isTrue);
    expect(csv.contains('Upstream Network: Jio 5G Mobile Data'), isTrue);
    expect(csv.contains('Hotspot Interface: wlan1'), isTrue);
    expect(csv.contains('My Work Laptop'), isTrue);
    expect(csv.contains('192.168.43.100'), isTrue);
    expect(csv.contains('F0:77:C3:D4:83:E3'), isTrue);
    expect(csv.contains('YouTube,Streaming'), isTrue);
    expect(csv.contains('googlevideo.com; youtube.com'), isTrue);
  });

  test('ExportService generates valid JSON parseable payload', () {
    final jsonStr = exportService.exportReportJson(
      testReport,
      capabilities: testCaps,
      generatedMs: 1700005000000,
    );

    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    expect(decoded['metadata']['appName'], 'Hotspot Monitor');
    expect(decoded['network']['upstreamDetails'], 'Jio 5G Mobile Data');
    expect(decoded['network']['hotspotInterface'], 'wlan1');
    expect(decoded['totals']['downloadBytes'], 104857600);

    final devices = decoded['devices'] as List;
    expect(devices.length, 1);
    expect(devices.first['name'], 'My Work Laptop');
    expect(devices.first['ip'], '192.168.43.100');

    final services = decoded['services'] as List;
    expect(services.length, 1);
    expect(services.first['displayName'], 'YouTube');
  });

  test('ExportService exports connection logs and single device CSV', () {
    final logsCsv = exportService.exportConnectionLogsCsv(
      const [testDevice],
      capabilities: testCaps,
      generatedMs: 1700005000000,
    );
    expect(logsCsv.contains('Device Connection History & Logs'), isTrue);
    expect(logsCsv.contains('My Work Laptop'), isTrue);

    final singleCsv = exportService.exportDeviceHistoryCsv(
      testDevice,
      const [testService],
      const [testTimeline],
      capabilities: testCaps,
      generatedMs: 1700005000000,
    );
    expect(singleCsv.contains('Single Device Usage Log'), isTrue);
    expect(singleCsv.contains('YouTube'), isTrue);
  });
}
