import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotspot_monitor/data/repositories/hotspot_repository.dart';
import 'package:hotspot_monitor/data/services/device_alias_service.dart';
import 'package:hotspot_monitor/data/services/history_store.dart';
import 'package:hotspot_monitor/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hotspot_repository_test.dart';

void main() {
  testWidgets(
    'auto-enables root on startup, opens Reports and Menu & Settings pages',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final fakePlatform = FakeHotspotPlatformService();
      final repo = HotspotRepository(
        platformService: fakePlatform,
        aliasService: DeviceAliasService(),
        historyStore: InMemoryHistoryStore(),
      );

      await tester.pumpWidget(HotspotMonitorApp(repository: repo));
      await tester.pumpAndSettle();

      expect(find.text('Hotspot Monitor'), findsOneWidget);
      expect(find.text('ROOT'), findsNothing);
      expect(find.text('NON-ROOT'), findsNothing);
      expect(repo.latest.isRootMode, isTrue);

      await tester.tap(find.bySemanticsLabel('Usage reports'));
      await tester.pumpAndSettle();
      expect(find.text('Usage Reports'), findsOneWidget);
      expect(find.text('1H'), findsOneWidget);
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Month'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Menu and settings'));
      await tester.pumpAndSettle();

      expect(find.text('Menu & Settings'), findsOneWidget);
      expect(find.text('Root Access'), findsOneWidget);
      expect(find.text('Clear Saved History'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('AP Labs · Akshay Kumar'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('AP Labs · Akshay Kumar'), findsOneWidget);
      expect(find.text('github.com/justakhi/hotspot-monitor'), findsOneWidget);
      expect(find.text('contact@techyke.in'), findsOneWidget);

      await fakePlatform.controller.close();
    },
  );

  testWidgets(
    'falls back cleanly to non-root mode when root is denied',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final fakePlatform = FakeHotspotPlatformService()
        ..grantRootOnRequest = false;
      final repo = HotspotRepository(
        platformService: fakePlatform,
        aliasService: DeviceAliasService(),
        historyStore: InMemoryHistoryStore(),
      );

      await tester.pumpWidget(HotspotMonitorApp(repository: repo));
      await tester.pumpAndSettle();

      expect(repo.latest.isRootMode, isFalse);
      await fakePlatform.controller.close();
    },
  );

  testWidgets(
    'tapping a service opens ServiceDetailScreen with plain-English info and endpoints',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final fakePlatform = FakeHotspotPlatformService();
      final repo = HotspotRepository(
        platformService: fakePlatform,
        aliasService: DeviceAliasService(),
        historyStore: InMemoryHistoryStore(),
      );

      await tester.pumpWidget(HotspotMonitorApp(repository: repo));
      await tester.pumpAndSettle();

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      fakePlatform.controller.add({
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
        'sessionDownloadBytes': 20480,
        'sessionUploadBytes': 2048,
        'liveDownloadBps': 1024,
        'liveUploadBps': 256,
        'devices': [
          {
            'id': 'AA:BB:CC:11:22:33',
            'ip': '192.168.43.10',
            'mac': 'AA:BB:CC:11:22:33',
            'hostname': 'DESKTOP-PC1',
            'vendor': 'Intel',
            'isRandomizedMac': false,
            'neighborState': 'REACHABLE',
            'isOnline': true,
            'downloadBytes': 20480,
            'uploadBytes': 2048,
            'services': [
              {
                'serviceId': 'youtube_video',
                'displayName': 'YouTube · Video Stream',
                'category': 'Video',
                'downloadBytes': 20480,
                'uploadBytes': 2048,
                'topDomains': ['rr1---sn.googlevideo.com'],
                'endpoints': [
                  {
                    'endpoint': 'rr1---sn.googlevideo.com',
                    'downloadBytes': 20480,
                    'uploadBytes': 2048,
                    'lastActiveMs': nowMs,
                  },
                ],
                'lastActiveMs': nowMs,
              },
            ],
          },
        ],
      });
      await tester.pumpAndSettle();

      await tester.tap(find.text('YouTube · Video Stream'));
      await tester.pumpAndSettle();

      expect(find.text('What Is This?'), findsOneWidget);
      expect(find.text('Likely App / PC Software'), findsOneWidget);
      expect(find.text('Where Data Is Going'), findsOneWidget);
      expect(find.text('rr1---sn.googlevideo.com'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Usage reports'));
      await tester.pumpAndSettle();

      expect(find.text('Device-Wise Usage History'), findsOneWidget);
      expect(find.text('All Devices'), findsOneWidget);
      expect(find.text('DESKTOP-PC1'), findsWidgets);

      await fakePlatform.controller.close();
    },
  );

  testWidgets(
    'home separates live connected vs recently disconnected (1h) and opens Connection History',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final fakePlatform = FakeHotspotPlatformService();
      final repo = HotspotRepository(
        platformService: fakePlatform,
        aliasService: DeviceAliasService(),
        historyStore: InMemoryHistoryStore(),
      );

      await tester.pumpWidget(HotspotMonitorApp(repository: repo));
      await tester.pumpAndSettle();

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      fakePlatform.controller.add({
        'timestampMs': nowMs,
        'sessionStartMs': nowMs - 60000,
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
        'sessionDownloadBytes': 5000,
        'sessionUploadBytes': 1000,
        'liveDownloadBps': 500,
        'liveUploadBps': 100,
        'devices': [
          {
            'id': 'AA:BB:CC:11:22:33',
            'ip': '192.168.43.10',
            'mac': 'AA:BB:CC:11:22:33',
            'hostname': 'Live-Laptop',
            'vendor': 'Intel',
            'isRandomizedMac': false,
            'neighborState': 'REACHABLE',
            'isOnline': true,
            'lastSeenMs': nowMs,
            'downloadBytes': 3000,
            'uploadBytes': 500,
            'services': [],
          },
          {
            'id': 'AA:BB:CC:44:55:66',
            'ip': '192.168.43.11',
            'mac': 'AA:BB:CC:44:55:66',
            'hostname': 'Recent-Phone',
            'vendor': 'Xiaomi',
            'isRandomizedMac': false,
            'neighborState': 'OFFLINE',
            'isOnline': false,
            'lastSeenMs': nowMs - 300000, // 5 mins ago
            'downloadBytes': 2000,
            'uploadBytes': 500,
            'services': [],
          },
          {
            'id': 'AA:BB:CC:77:88:99',
            'ip': '192.168.43.12',
            'mac': 'AA:BB:CC:77:88:99',
            'hostname': 'Old-Phone',
            'vendor': 'Lava',
            'isRandomizedMac': false,
            'neighborState': 'OFFLINE',
            'isOnline': false,
            'lastSeenMs': nowMs - 7200000, // 2 hours ago
            'downloadBytes': 500,
            'uploadBytes': 100,
            'services': [],
          },
        ],
      });
      await tester.pumpAndSettle();

      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('1'), findsNWidgets(3)); // Overview + Connected + Recently Disconnected badges
      expect(find.text('Live-Laptop'), findsOneWidget);
      expect(find.text('Recently Disconnected (1h)'), findsOneWidget);
      expect(find.text('Recent-Phone'), findsOneWidget);
      expect(find.text('Old-Phone'), findsNothing);

      await tester.ensureVisible(find.text('All History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All History'));
      await tester.pumpAndSettle();

      expect(find.text('Connection History'), findsOneWidget);
      expect(find.text('Old-Phone'), findsOneWidget);

      await fakePlatform.controller.close();
    },
  );
}
