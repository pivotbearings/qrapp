import 'package:flutter/material.dart';

/// Centralized Locale Controller for real-time dynamic language changes
class LocaleController {
  static final ValueNotifier<Locale> currentLocale = ValueNotifier<Locale>(const Locale('en'));

  static Locale get locale => currentLocale.value;

  static void setLocale(Locale newLocale) {
    if (['en', 'hi', 'gu'].contains(newLocale.languageCode)) {
      currentLocale.value = newLocale;
    }
  }

  static void setLanguageCode(String code) {
    setLocale(Locale(code));
  }
}
