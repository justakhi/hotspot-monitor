import 'package:flutter_test/flutter_test.dart';
import 'package:hotspot_monitor/data/services/quota_service.dart';
import 'package:hotspot_monitor/domain/models/device_quota.dart';
import 'package:hotspot_monitor/domain/models/quota_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('QuotaService', () {
    test('loads default global quota config when unset', () async {
      final service = QuotaService();
      final config = await service.loadGlobalQuota();

      expect(config.enabled, false);
      expect(config.limitBytes, 1024 * 1024 * 1024); // 1 GB default
      expect(config.warningPercent, 80);
    });

    test('saves and loads custom global quota config', () async {
      final service = QuotaService();
      const custom = QuotaConfig(
        enabled: true,
        limitBytes: 2 * 1024 * 1024 * 1024,
        warningPercent: 90,
      );

      await service.saveGlobalQuota(custom);
      final loaded = await service.loadGlobalQuota();

      expect(loaded.enabled, true);
      expect(loaded.limitBytes, 2 * 1024 * 1024 * 1024);
      expect(loaded.warningPercent, 90);
    });

    test('saves, loads, and clears per-device quotas', () async {
      final service = QuotaService();
      expect(await service.loadDeviceQuotas(), isEmpty);

      const device1 = DeviceQuota(
        deviceId: '192.168.43.101',
        limitBytes: 500 * 1024 * 1024,
        autoBlockExceeded: true,
        isBlocked: false,
      );

      await service.saveDeviceQuota(device1);
      var quotas = await service.loadDeviceQuotas();
      expect(quotas['192.168.43.101']?.limitBytes, 500 * 1024 * 1024);
      expect(quotas['192.168.43.101']?.autoBlockExceeded, true);

      // Update block state
      await service.setDeviceBlocked('192.168.43.101', true);
      quotas = await service.loadDeviceQuotas();
      expect(quotas['192.168.43.101']?.isBlocked, true);

      // Remove device quota
      await service.removeDeviceQuota('192.168.43.101');
      quotas = await service.loadDeviceQuotas();
      expect(quotas.containsKey('192.168.43.101'), false);
    });
  });
}
