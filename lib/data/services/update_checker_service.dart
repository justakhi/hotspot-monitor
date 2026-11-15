import 'dart:convert';
import 'dart:io';

import '../../domain/models/app_release_info.dart';

/// Checks GitHub Releases API for app updates and parses release changelogs.
class UpdateCheckerService {
  static const String currentVersion = '1.0.0';
  static const String _latestReleaseApiUrl =
      'https://api.github.com/repos/justakhi/hotspot-monitor/releases/latest';

  static bool isVersionNewer(String current, String candidate) {
    List<int> parse(String v) {
      final clean =
          v.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
      return clean.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    }

    final cParts = parse(current);
    final nParts = parse(candidate);
    for (var i = 0; i < 3; i++) {
      final c = i < cParts.length ? cParts[i] : 0;
      final n = i < nParts.length ? nParts[i] : 0;
      if (n > c) return true;
      if (n < c) return false;
    }
    return false;
  }

  Future<AppReleaseInfo?> checkForUpdate({
    String? currentVersionOverride,
    HttpClient? customClient,
  }) async {
    final effectiveCurrent = currentVersionOverride ?? currentVersion;

    HttpClient? client;
    try {
      client = customClient ?? HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);

      final request =
          await client.getUrl(Uri.parse(_latestReleaseApiUrl));
      request.headers.set('User-Agent', 'HotspotMonitorApp/$effectiveCurrent');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        if (decoded is Map) {
          final mapped = Map<String, dynamic>.from(decoded);
          return AppReleaseInfo.fromJson(mapped, currentVersion: effectiveCurrent);
        }
        return null;
      }

      return AppReleaseInfo.fromJson(decoded, currentVersion: effectiveCurrent);
    } catch (_) {
      return null;
    } finally {
      if (customClient == null) {
        client?.close(force: true);
      }
    }
  }
}
