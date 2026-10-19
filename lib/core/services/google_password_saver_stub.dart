/// Stub for non-web platforms (mobile/desktop VM)
void savePasswordToBrowser({required String username, required String password}) {
  // On mobile platforms (Android/iOS), TextInput.finishAutofillContext(shouldSave: true)
  // handles invoking Google Autofill / Apple Keychain natively.
}
