import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pivot Bearings India - Application Configuration & Environment
class AppConfig {
  static const String defaultSupabaseUrl = 'https://cuasxehuuadkapehaxkh.supabase.co';
  static const String defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN1YXN4ZWh1dWFka2FwZWhheGtoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE1NjM0NDQsImV4cCI6MjEwNzEzOTQ0NH0.T60jcH4gy1cGnSqM7Qrv1dyebPQ0KllaGl3xGYKZ_H0';

  static String _supabaseUrl = defaultSupabaseUrl;
  static String _supabaseAnonKey = defaultSupabaseAnonKey;

  static String get supabaseUrl {
    if (_supabaseUrl.isEmpty ||
        _supabaseUrl.contains('sample') ||
        _supabaseUrl.contains('example')) {
      return defaultSupabaseUrl;
    }
    return _supabaseUrl;
  }

  static set supabaseUrl(String val) => _supabaseUrl = val;

  static String get supabaseAnonKey {
    if (_supabaseAnonKey.isEmpty ||
        _supabaseAnonKey.contains('sample') ||
        _supabaseAnonKey.contains('example')) {
      return defaultSupabaseAnonKey;
    }
    return _supabaseAnonKey;
  }

  static set supabaseAnonKey(String val) => _supabaseAnonKey = val;

  static int apiTimeoutSeconds = 15;
  static String appEnvironment = 'development';
  static bool enableAnalytics = false;
  static String defaultLocale = 'en';

  /// Initializes configuration from .env file with production defaults
  static Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('supabase_url');
      await prefs.remove('supabase_anon_key');
    } catch (_) {}

    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // In web or tests where .env might not be bundled directly, fallback gracefully
    }

    final envUrl = dotenv.env['SUPABASE_URL'];
    final envKey = dotenv.env['SUPABASE_ANON_KEY'];

    if (envUrl != null &&
        envUrl.isNotEmpty &&
        !envUrl.contains('sample') &&
        !envUrl.contains('example')) {
      _supabaseUrl = envUrl;
    } else {
      _supabaseUrl = defaultSupabaseUrl;
    }

    if (envKey != null &&
        envKey.isNotEmpty &&
        !envKey.contains('sample') &&
        !envKey.contains('example')) {
      _supabaseAnonKey = envKey;
    } else {
      _supabaseAnonKey = defaultSupabaseAnonKey;
    }

    apiTimeoutSeconds = int.tryParse(dotenv.env['API_TIMEOUT_SECONDS'] ?? '15') ?? 15;
    appEnvironment = dotenv.env['APP_ENVIRONMENT'] ?? 'development';
    enableAnalytics = (dotenv.env['ENABLE_ANALYTICS'] ?? 'false').toLowerCase() == 'true';
    defaultLocale = dotenv.env['DEFAULT_LOCALE'] ?? 'en';
    storageCdnUrl = dotenv.env['STORAGE_CDN_URL']?.trim();
  }

  static String? storageCdnUrl;
  static bool get isProduction => appEnvironment == 'production';
  static bool get hasRealSupabaseConfig => true;
}
