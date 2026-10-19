import 'google_password_saver_stub.dart'
    if (dart.library.html) 'google_password_saver_web.dart';

/// Integrates directly with Google Password Manager & Browser Credential Management API
class GooglePasswordSaver {
  /// Prompts Google Password Manager / Chrome to store the user credentials
  static void save({required String username, required String password}) {
    if (username.trim().isEmpty || password.trim().isEmpty) return;
    savePasswordToBrowser(username: username.trim(), password: password.trim());
  }
}
