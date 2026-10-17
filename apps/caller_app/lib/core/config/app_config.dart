/// Global configuration for the Orvyqmedia Caller Android App
class AppConfig {
  AppConfig._();

  static const String appName = 'Orvyqmedia Caller';
  static const String appVersion = '1.0.0';

  // Live Supabase project credentials
  static const String supabaseUrl = 'https://iewenwzafmcrjkjhtwzv.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_mJl47AeSOt31QwSZdWs7xg_Px2jAzpL';

  // Verification & calling rules (§1.1 & §5.1)
  static const String defaultCountry = 'IN';
  static const String defaultCountryCode = '+91';

  /// Minimum talk time in seconds to count as a verified "connected" call (§5.1)
  static const int minConnectedDurationSecs = 10;

  /// Call-log detection retry window after dialing (§5.3)
  static const Duration callLogPollWindow = Duration(seconds: 15);
  static const Duration callLogPollInterval = Duration(seconds: 2);
}
