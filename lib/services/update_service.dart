import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;

/// The version baked in at build time via --dart-define=NOTERR_APP_VERSION
const _currentVersion = String.fromEnvironment(
  'NOTERR_APP_VERSION',
  defaultValue: '0.2.0',
);

/// GitHub repository owner/name
const _repo = 'simplyzubair/noterr';

class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    required this.releaseUrl,
  });

  final String latestVersion;
  final String downloadUrl;   // direct asset URL
  final String releaseUrl;    // GitHub release page

  bool get isNewerThan {
    try {
      final current = _parseVersion(_currentVersion);
      final latest = _parseVersion(latestVersion);
      for (var i = 0; i < latest.length; i++) {
        final c = i < current.length ? current[i] : 0;
        if (latest[i] > c) return true;
        if (latest[i] < c) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static List<int> _parseVersion(String v) {
    return v
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
  }
}

class UpdateService {
  UpdateService._();

  static const _apiUrl =
      'https://api.github.com/repos/$_repo/releases/latest';

  /// Check for a newer version.  Returns null if up to date or on error.
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http
          .get(
            Uri.parse(_apiUrl),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final tag = (data['tag_name'] as String? ?? '').replaceAll('v', '');
      if (tag.isEmpty) return null;

      final releaseUrl = data['html_url'] as String? ?? '';
      final assets = (data['assets'] as List? ?? const [])
          .whereType<Map>()
          .cast<Map<String, dynamic>>()
          .toList();

      final downloadUrl = _bestAssetUrl(assets) ?? releaseUrl;

      final info = UpdateInfo(
        latestVersion: tag,
        downloadUrl: downloadUrl,
        releaseUrl: releaseUrl,
      );

      return info.isNewerThan ? info : null;
    } catch (_) {
      return null;
    }
  }

  /// Returns the best download URL for the current platform.
  static String? _bestAssetUrl(List<Map<String, dynamic>> assets) {
    if (Platform.isAndroid) {
      // Prefer arm64, fall back to universal
      final arm64 = assets.firstWhere(
        (a) => (a['name'] as String? ?? '').contains('arm64'),
        orElse: () => <String, dynamic>{},
      );
      if (arm64.isNotEmpty) {
        return arm64['browser_download_url'] as String?;
      }
      final apk = assets.firstWhere(
        (a) => (a['name'] as String? ?? '').endsWith('.apk'),
        orElse: () => <String, dynamic>{},
      );
      return apk['browser_download_url'] as String?;
    }

    if (Platform.isWindows) {
      final exe = assets.firstWhere(
        (a) => (a['name'] as String? ?? '').endsWith('.exe'),
        orElse: () => <String, dynamic>{},
      );
      return exe['browser_download_url'] as String?;
    }

    return null;
  }

  static String get currentVersion => _currentVersion;
}
