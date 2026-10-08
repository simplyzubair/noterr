class AppConfig {
  // Self-hosted sync server on Contabo. Not a secret: notes are encrypted
  // with the PIN before they leave the device. Override with
  // --dart-define=NOTERR_SYNC_URL=... (an empty value turns sync off).
  static const syncUrl = String.fromEnvironment(
    'NOTERR_SYNC_URL',
    defaultValue: 'https://noterr.skillsgeek.com/sync',
  );
  static const dataProfile = String.fromEnvironment('NOTERR_DATA_PROFILE');
  static const mobilePreview = bool.fromEnvironment('NOTERR_MOBILE_PREVIEW');
  static const androidUpdateUrl = String.fromEnvironment(
    'NOTERR_ANDROID_UPDATE_URL',
    defaultValue: 'https://github.com/simplyzubair/noterr/releases/latest',
  );

  static bool get hasCloudSync => syncUrl.trim().isNotEmpty;
}
