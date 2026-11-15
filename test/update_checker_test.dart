import 'package:flutter_test/flutter_test.dart';
import 'package:hotspot_monitor/data/services/update_checker_service.dart';
import 'package:hotspot_monitor/domain/models/app_release_info.dart';

void main() {
  group('AppReleaseInfo', () {
    test('compares semver versions correctly', () {
      expect(UpdateCheckerService.isVersionNewer('1.0.0', 'v1.0.1'), isTrue);
      expect(UpdateCheckerService.isVersionNewer('1.0.0', '1.1.0'), isTrue);
      expect(UpdateCheckerService.isVersionNewer('1.0.0', '2.0.0'), isTrue);
      expect(UpdateCheckerService.isVersionNewer('1.0.0', 'v1.0.0'), isFalse);
      expect(UpdateCheckerService.isVersionNewer('1.0.0', '0.9.9'), isFalse);
      expect(UpdateCheckerService.isVersionNewer('1.0.0', 'v1.0.0+1'), isFalse);
      expect(UpdateCheckerService.isVersionNewer('1.0.0+1', 'v1.0.1+1'), isTrue);
    });

    test('parses GitHub release JSON payload', () {
      final json = {
        'tag_name': 'v1.1.0',
        'name': 'Hotspot Monitor v1.1.0',
        'body': '### Added\n- Data quota alerts\n- Internet blocking for devices',
        'html_url': 'https://github.com/justakhi/hotspot-monitor/releases/tag/v1.1.0',
        'published_at': '2026-11-15T18:00:00Z',
        'assets': [
          {
            'name': 'HotspotMonitor-arm64-v8a.apk',
            'browser_download_url':
                'https://github.com/justakhi/hotspot-monitor/releases/download/v1.1.0/HotspotMonitor-arm64-v8a.apk',
          },
          {
            'name': 'HotspotMonitor-universal.apk',
            'browser_download_url':
                'https://github.com/justakhi/hotspot-monitor/releases/download/v1.1.0/HotspotMonitor-universal.apk',
          },
        ],
      };

      final info = AppReleaseInfo.fromJson(json, currentVersion: '1.0.0');
      expect(info.tagName, 'v1.1.0');
      expect(info.title, 'Hotspot Monitor v1.1.0');
      expect(info.changelog, contains('Data quota alerts'));
      expect(info.releasePageUrl, contains('releases/tag/v1.1.0'));
      expect(info.downloadUrl, contains('HotspotMonitor-arm64-v8a.apk'));
      expect(info.isNewer, isTrue);
    });
  });
}
