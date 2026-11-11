import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotspot_monitor/data/repositories/hotspot_repository.dart';
import 'package:hotspot_monitor/data/services/device_alias_service.dart';
import 'package:hotspot_monitor/data/services/history_store.dart';
import 'package:hotspot_monitor/data/services/hotspot_platform_service.dart';
import 'package:hotspot_monitor/domain/models/capability_state.dart';
import 'package:hotspot_monitor/domain/models/history_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeHotspotPlatformService implements HotspotPlatformService {
  final StreamController<Map<Object?, Object?>> controller =
      StreamController<Map<Object?, Object?>>.broadcast();

  CapabilityState capabilities = const CapabilityState(
    usageAccessGranted: true,
    rootBinaryPresent: true,
    rootGranted: false,
    nativeProbeAvailable: true,
    hotspotActive: true,
    hotspotInterface: 'wlan1',
    gatewayIp: '192.168.43.1',
    prefixLength: 24,
    tetherType: 'wifi_ap',
  );

  bool grantRootOnRequest = true;
  Map<Object?, Object?> nextScanPayload = const {};

  @override
  Stream<Map<Object?, Object?>> get telemetryStream => controller.stream;

  @override
  Future<CapabilityState> getCapabilities() async => capabilities;

  @override
  Future<void> openUsageAccessSettings() async {}

  @override
  Future<CapabilityState> requestRootAccess() async {
    capabilities = CapabilityState(
      usageAccessGranted: true,
      rootBinaryPresent: true,
      rootGranted: grantRootOnRequest,
      nativeProbeAvailable: true,
      hotspotActive: true,
      hotspotInterface: 'wlan1',
      gatewayIp: '192.168.43.1',
      prefixLength: 24,
      tetherType: 'wifi_ap',
    );
    return capabilities;
  }

  @override
  Future<void> resetSession() async {}

  @override
  Future<Map<Object?, Object?>> scanNow() async => nextScanPayload;

  @override
  Future<bool> openUrl(String url) async => true;

  @override
  Future<CapabilityState> setRootModeEnabled(bool enabled) async {
    capabilities = CapabilityState(
      usageAccessGranted: true,
      rootBinaryPresent: true,
      rootGranted: enabled,
      nativeProbeAvailable: true,
      hotspotActive: true,
      hotspotInterface: 'wlan1',
      gatewayIp: '192.168.43.1',
      prefixLength: 24,
      tetherType: 'wifi_ap',
    );
    return capabilities;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('aggregates top services, aliases, and delta history without double counting', () async {
    SharedPreferences.setMockInitialValues({});
    final fakePlatform = FakeHotspotPlatformService();
    final repo = HotspotRepository(
      platformService: fakePlatform,
      aliasService: DeviceAliasService(),
      historyStore: InMemoryHistoryStore(),
    );

    await repo.initialize();

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    Map<Object?, Object?> makePayload(int ytRx, int ytTx) => {
      'timestampMs': nowMs,
      'sessionStartMs': nowMs - 1000,
      'mode': 'root',
      'capabilities': {
        'usageAccessGranted': true,
        'rootBinaryPresent': true,
        'rootGranted': true,
        'nativeProbeAvailable': true,
        'hotspotActive': true,
        'hotspotInterface': 'wlan1',
        'gatewayIp': '192.168.43.1',
        'prefixLength': 24,
        'tetherType': 'wifi_ap',
      },
      'probeActive': true,
      'sessionDownloadBytes': ytRx + 1000,
      'sessionUploadBytes': ytTx + 200,
      'liveDownloadBps': 1000,
      'liveUploadBps': 200,
      'devices': [
        {
          'id': 'AA:BB:CC:11:22:33',
          'ip': '192.168.43.10',
          'mac': 'AA:BB:CC:11:22:33',
          'hostname': 'Pixel-8',
          'vendor': 'Google',
          'isRandomizedMac': false,
          'neighborState': 'REACHABLE',
          'isOnline': true,
          'downloadBytes': ytRx,
          'uploadBytes': ytTx,
          'services': [
            {
              'serviceId': 'youtube_video',
              'displayName': 'YouTube · Video Stream',
              'category': 'Video',
              'downloadBytes': ytRx,
              'uploadBytes': ytTx,
              'topDomains': ['googlevideo.com'],
              'endpoints': [
                {
                  'endpoint': 'rr1---sn.googlevideo.com',
                  'downloadBytes': ytRx,
                  'uploadBytes': ytTx,
                  'lastActiveMs': nowMs,
                },
              ],
              'lastActiveMs': nowMs,
            },
          ],
        },
        {
          'id': 'AA:BB:CC:44:55:66',
          'ip': '192.168.43.11',
          'mac': 'AA:BB:CC:44:55:66',
          'hostname': 'iPhone',
          'vendor': 'Apple',
          'isRandomizedMac': false,
          'neighborState': 'REACHABLE',
          'isOnline': true,
          'downloadBytes': 1000,
          'uploadBytes': 200,
          'services': [
            {
              'serviceId': 'youtube_video',
              'displayName': 'YouTube · Video Stream',
              'category': 'Video',
              'downloadBytes': 1000,
              'uploadBytes': 200,
              'topDomains': ['googlevideo.com'],
              'endpoints': [
                {
                  'endpoint': 'rr1---sn.googlevideo.com',
                  'downloadBytes': 1000,
                  'uploadBytes': 200,
                  'lastActiveMs': nowMs,
                },
              ],
              'lastActiveMs': nowMs,
            },
          ],
        },
      ],
    };

    fakePlatform.controller.add(makePayload(1800, 200));
    await Future<void>.delayed(const Duration(milliseconds: 25));

    // Second tick adds only +1200 download / +100 upload delta for device 1.
    fakePlatform.controller.add(makePayload(3000, 300));
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(repo.latest.devices.length, 2);
    expect(repo.latest.topServices.single.serviceId, 'youtube_video');
    expect(repo.latest.topServices.single.totalBytes, 4500);
    expect(repo.latest.topServices.single.endpoints.single.endpoint, 'rr1---sn.googlevideo.com');
    expect(repo.latest.topServices.single.endpoints.single.totalBytes, 4500);

    await repo.setDeviceAlias('AA:BB:CC:11:22:33', 'Living Room Phone');
    expect(repo.latest.devices.first.displayName, 'Living Room Phone');

    final dayReport = await repo.getUsageReport(HistoryRange.day);
    expect(dayReport.totalDownloadBytes, 4000); // 3000 + 1000
    expect(dayReport.totalUploadBytes, 500); // 300 + 200
    expect(dayReport.devices.length, 2);
    expect(dayReport.devices.first.displayName, 'Living Room Phone');
    expect(dayReport.services.single.endpoints.single.endpoint, 'rr1---sn.googlevideo.com');
    expect(dayReport.services.single.endpoints.single.totalBytes, 4500);
    expect(
      dayReport.servicesByDevice['AA:BB:CC:11:22:33']?.single.totalBytes,
      3300,
    );
    expect(
      dayReport.servicesByDevice['AA:BB:CC:44:55:66']?.single.totalBytes,
      1200,
    );

    final deviceMonthReport = await repo.getUsageReport(
      HistoryRange.month,
      deviceId: 'AA:BB:CC:11:22:33',
    );
    expect(deviceMonthReport.totalBytes, 3300);
    expect(deviceMonthReport.services.single.displayName, 'YouTube · Video Stream');

    final allHistory = await repo.getAllDeviceHistory();
    expect(allHistory.length, 2);

    repo.dispose();
    await fakePlatform.controller.close();
  });
}
