class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const dataProfile = String.fromEnvironment('NOTERR_DATA_PROFILE');
  static const mobilePreview = bool.fromEnvironment('NOTERR_MOBILE_PREVIEW');

  static bool get hasSupabase =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;
}
