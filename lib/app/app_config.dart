class AppConfig {
  static const syncUrl = String.fromEnvironment('NOTERR_SYNC_URL');
  static const dataProfile = String.fromEnvironment('NOTERR_DATA_PROFILE');
  static const mobilePreview = bool.fromEnvironment('NOTERR_MOBILE_PREVIEW');
  static const androidUpdateUrl = String.fromEnvironment(
    'NOTERR_ANDROID_UPDATE_URL',
    defaultValue: 'https://github.com/simplyzubair/noterr/releases/latest',
  );

  static bool get hasCloudSync => syncUrl.trim().isNotEmpty;
}
