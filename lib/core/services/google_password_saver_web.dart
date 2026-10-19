// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

/// Web implementation triggering Chrome / Google Password Manager saving
void savePasswordToBrowser({required String username, required String password}) {
  try {
    // 1. Invoke custom window function if defined in index.html
    if (js.context.hasProperty('saveToGooglePasswords')) {
      js.context.callMethod('saveToGooglePasswords', [username, password]);
      return;
    }

    // 2. Fall back to standard Web Credential Management API (PasswordCredential)
    if (js.context.hasProperty('PasswordCredential') &&
        js.context['navigator'] != null &&
        js.context['navigator']['credentials'] != null) {
      final cred = js.JsObject(js.context['PasswordCredential'], [
        js.JsObject.jsify({
          'id': username,
          'password': password,
          'name': username,
        })
      ]);
      js.context['navigator']['credentials'].callMethod('store', [cred]);
    }
  } catch (e) {
    html.window.console.warn('Google Password Manager store error: $e');
  }
}
