/// Metadata about a published release fetched from GitHub Releases API.
class AppReleaseInfo {
  final String tagName;
  final String title;
  final String changelog;
  final String releasePageUrl;
  final String downloadUrl;
  final DateTime? publishedAt;
  final bool isNewer;

  const AppReleaseInfo({
    required this.tagName,
    required this.title,
    required this.changelog,
    required this.releasePageUrl,
    required this.downloadUrl,
    this.publishedAt,
    required this.isNewer,
  });

  factory AppReleaseInfo.fromJson(
    Map<String, dynamic> json, {
    required String currentVersion,
    bool? isNewerOverride,
  }) {
    final tag = json['tag_name'] as String? ?? '';
    final name = json['name'] as String? ?? tag;
    final body = json['body'] as String? ?? 'No release notes provided.';
    final htmlUrl = json['html_url'] as String? ??
        'https://github.com/justakhi/hotspot-monitor/releases';
    final publishedStr = json['published_at'] as String?;
    final published =
        publishedStr != null ? DateTime.tryParse(publishedStr) : null;

    var bestDownloadUrl = htmlUrl;
    final rawAssets = json['assets'] as List<dynamic>? ?? const [];
    // Prioritize arm64-v8a apk, then universal, then any apk
    for (final candidate in rawAssets) {
      if (candidate is Map) {
        final assetName = candidate['name']?.toString() ?? '';
        final downloadUrl = candidate['browser_download_url']?.toString();
        if (downloadUrl != null && assetName.endsWith('.apk')) {
          if (assetName.contains('arm64-v8a')) {
            bestDownloadUrl = downloadUrl;
            break;
          } else if (bestDownloadUrl == htmlUrl) {
            bestDownloadUrl = downloadUrl;
          }
        }
      }
    }

    final isNewer = isNewerOverride ?? _compareVersions(currentVersion, tag);

    return AppReleaseInfo(
      tagName: tag,
      title: name,
      changelog: body.trim(),
      releasePageUrl: htmlUrl,
      downloadUrl: bestDownloadUrl,
      publishedAt: published,
      isNewer: isNewer,
    );
  }

  static bool _compareVersions(String current, String candidate) {
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
}
