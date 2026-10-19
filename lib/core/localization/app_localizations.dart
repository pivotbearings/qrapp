import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Pivot Bearings India - Multi-Language Localization
/// Supports English (en), Hindi (hi), and Gujarati (gu)
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizations(const Locale('en'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const List<Locale> supportedLocales = [
    Locale('en', ''), // English
    Locale('hi', ''), // Hindi
    Locale('gu', ''), // Gujarati
  ];

  static final Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'app_title': 'Pivot Bearings India',
      'home': 'Home',
      'my_bearings': 'My Bearings',
      'operations': 'Operations',
      'account': 'Account',
      'admin_dashboard': 'Admin Dashboard',
      'scan_bearing_qr': 'Scan Bearing QR',
      'optical_verification': 'Optical code verification',
      'currently_in': 'CURRENTLY IN',
      'currently_out': 'CURRENTLY OUT',
      'active_warranties': 'Active Warranties',
      'expired_warranties': 'Expired Warranties',
      'view_all_bearings': 'View All Bearings',
      'recent_activity': 'Recent Activity',
      'scan_qr_code': 'Scan QR Code',
      'cancel': 'Cancel',
      'confirm_in': 'Confirm Bearing IN',
      'confirm_out': 'Confirm Bearing OUT',
      'start_warranty': 'Start Warranty',
      'bearing_id': 'Bearing ID',
      'batch_code': 'Batch Reference',
      'warranty_period': 'Warranty Period',
      'status_operational': '[STATUS: OPERATIONAL]',
      'status_marked_in': '[STATUS: MARKED IN]',
      'status_marked_out': '[STATUS: MARKED OUT]',
      'proof_captured': '[PROOF CAPTURED]',
      'qr_generation': 'QR Bulk Generation',
      'warranty_assignment': 'Warranty Assignment',
      'qr_inventory': 'QR Inventory',

      // Understandable States
      'bearing_verified': 'BEARING VERIFIED',
      'warranty_active': 'WARRANTY ACTIVE',
      'warranty_expired': 'WARRANTY EXPIRED',
      'invalid_qr_code': 'INVALID QR CODE',
      'qr_blocked': 'BEARING BLOCKED',
      'network_error': 'NETWORK UNAVAILABLE',
      'camera_denied': 'CAMERA ACCESS REQUIRED',
      'upload_failed': 'IMAGE UPLOAD FAILED',
      'loading': 'Loading authoritative records...',
      'success': 'Action completed successfully',
      'empty': 'No records found',

      // Lifecycle & Duration
      'installation_duration': 'Installation Duration',
      'first_in_date': 'First Installation (Activation)',
      'last_in_date': 'Current Installation',
      'last_out_date': 'Last Removal',
      'expiry_date': 'Warranty Expiry Date',
      'operating_time': 'Total Operating Time',
      'lifecycle_history': 'Relevant Lifecycle History',
      'evidence_hash': 'SHA-256 Tamper Proof Hash',

      // Profile & Company
      'customer_profile': 'Customer Profile',
      'facility_code': 'Facility Code',
      'company_name': 'Company Name',
      'gst_number': 'GSTIN',
      'plant_location': 'Manufacturing Plant',
      'contact_helpline': 'Quality Helpline',
      'official_website': 'Official Portal',
      'registered_office': 'Registered Office',
      'language_settings': 'Language Settings',
      'sign_in': 'Sign In',
      'sign_out': 'Sign Out',
      'auth_welcome': 'Industrial Authentication',
      'auth_subtitle': 'Sign in to access verified telemetry & warranty records',
      'email': 'Email Address',
      'password': 'Password',
      'enter_bearing_id': 'Enter Bearing ID Manually',
    },
    'hi': {
      'app_title': 'पिवट बियरिंग्स इंडिया',
      'home': 'होम',
      'my_bearings': 'मेरे बियरिंग्स',
      'operations': 'संचालन',
      'account': 'खाता',
      'admin_dashboard': 'एडमिन डैशबोर्ड',
      'scan_bearing_qr': 'बियरिंग क्यूआर स्कैन करें',
      'optical_verification': 'ऑप्टिकल कोड सत्यापन',
      'currently_in': 'वर्तमान में स्थापित (IN)',
      'currently_out': 'वर्तमान में निकाला हुआ (OUT)',
      'active_warranties': 'सक्रिय वारंटी',
      'expired_warranties': 'समाप्त वारंटी',
      'view_all_bearings': 'सभी बियरिंग्स देखें',
      'recent_activity': 'हाल की गतिविधि',
      'scan_qr_code': 'क्यूआर कोड स्कैन करें',
      'cancel': 'रद्द करें',
      'confirm_in': 'बियरिंग IN पुष्टि करें',
      'confirm_out': 'बियरिंग OUT पुष्टि करें',
      'start_warranty': 'वारंटी शुरू करें',
      'bearing_id': 'बियरिंग आईडी',
      'batch_code': 'बैच संदर्भ',
      'warranty_period': 'वारंटी अवधि',
      'status_operational': '[स्थिति: चालू]',
      'status_marked_in': '[स्थिति: IN दर्ज]',
      'status_marked_out': '[स्थिति: OUT दर्ज]',
      'proof_captured': '[प्रमाण कैप्चर किया गया]',
      'qr_generation': 'क्यूआर बल्क जनरेशन',
      'warranty_assignment': 'वारंटी आवंटन',
      'qr_inventory': 'क्यूआर इन्वेंटरी',

      // Understandable States
      'bearing_verified': 'बियरिंग सत्यापित',
      'warranty_active': 'वारंटी सक्रिय',
      'warranty_expired': 'वारंटी समाप्त',
      'invalid_qr_code': 'अमान्य क्यूआर कोड',
      'qr_blocked': 'बियरिंग लॉक / ब्लॉक',
      'network_error': 'नेटवर्क अनुपलब्ध',
      'camera_denied': 'कैमरा अनुमति आवश्यक है',
      'upload_failed': 'छवि अपलोड विफल',
      'loading': 'डेटा लोड हो रहा है...',
      'success': 'कार्रवाई सफलतापूर्वक पूर्ण',
      'empty': 'कोई रिकॉर्ड नहीं मिला',

      // Lifecycle & Duration
      'installation_duration': 'स्थापना अवधि',
      'first_in_date': 'प्रथम स्थापना (सक्रियण)',
      'last_in_date': 'वर्तमान स्थापना',
      'last_out_date': 'अंतिम निष्कासन',
      'expiry_date': 'वारंटी समाप्ति तिथि',
      'operating_time': 'कुल परिचालन समय',
      'lifecycle_history': 'जीवनचक्र इतिहास',
      'evidence_hash': 'SHA-256 छेड़छाड़-रोधी हैश',

      // Profile & Company
      'customer_profile': 'ग्राहक प्रोफाइल',
      'facility_code': 'सुविधा कोड',
      'company_name': 'कंपनी का नाम',
      'gst_number': 'जीएसटीआईएन (GSTIN)',
      'plant_location': 'विनिर्माण संयंत्र',
      'contact_helpline': 'गुणवत्ता हेल्पलाइन',
      'official_website': 'आधिकारिक पोर्टल',
      'registered_office': 'पंजीकृत कार्यालय',
      'language_settings': 'भाषा सेटिंग्स',
      'sign_in': 'साइन इन करें',
      'sign_out': 'साइन आउट',
      'auth_welcome': 'औद्योगिक प्रमाणीकरण',
      'auth_subtitle': 'सत्यापित रिकॉर्ड और वारंटी देखने के लिए साइन इन करें',
      'email': 'ईमेल पता',
      'password': 'पासवर्ड',
      'enter_bearing_id': 'बियरिंग आईडी दर्ज करें',
    },
    'gu': {
      'app_title': 'પિવોટ બેયરિંગ્સ ઇન્ડિયા',
      'home': 'હોમ',
      'my_bearings': 'મારા બેરિંગ્સ',
      'operations': 'ઓપરેશન્સ',
      'account': 'ખાતું',
      'admin_dashboard': 'એડમિન ડેશબોર્ડ',
      'scan_bearing_qr': 'બેરિંગ ક્યૂઆર સ્કેન કરો',
      'optical_verification': 'ઓપ્ટિકલ કોડ વેરિફિકેશન',
      'currently_in': 'હાલમાં સ્થાપિત (IN)',
      'currently_out': 'હાલમાં દૂર કરેલ (OUT)',
      'active_warranties': 'સક્રિય વોરંટી',
      'expired_warranties': 'સમાપ્ત થયેલ વોરંટી',
      'view_all_bearings': 'બધા બેરિંગ્સ જુઓ',
      'recent_activity': 'તાજેતરની પ્રવૃત્તિ',
      'scan_qr_code': 'ક્યૂઆર કોડ સ્કેન કરો',
      'cancel': 'રદ કરો',
      'confirm_in': 'બેરિંગ IN પુષ્ટિ કરો',
      'confirm_out': 'બેરિંગ OUT પુષ્ટિ કરો',
      'start_warranty': 'વોરંટી શરૂ કરો',
      'bearing_id': 'બેરિંગ આઈડી',
      'batch_code': 'બેચ સંદર્ભ',
      'warranty_period': 'વોરંટી સમયગાળો',
      'status_operational': '[સ્થિતિ: કાર્યરત]',
      'status_marked_in': '[સ્થિતિ: IN નોંધાયેલ]',
      'status_marked_out': '[સ્થિતિ: OUT નોંધાયેલ]',
      'proof_captured': '[પુરાવો કેપ્ચર કર્યો]',
      'qr_generation': 'ક્યૂઆર બલ્ક જનરેશન',
      'warranty_assignment': 'વોરંટી ફાળવણી',
      'qr_inventory': 'ક્યૂઆર ઇન્વેન્ટરી',

      // Understandable States
      'bearing_verified': 'બેરિંગ ચકાસાયેલ',
      'warranty_active': 'વોરંટી સક્રિય',
      'warranty_expired': 'વોરંટી સમાપ્ત',
      'invalid_qr_code': 'અમાન્ય ક્યૂઆર કોડ',
      'qr_blocked': 'બેરિંગ બ્લોક કરેલ',
      'network_error': 'નેટવર્ક અનુપલબ્ધ',
      'camera_denied': 'કૅમેરા ઍક્સેસ આવશ્યક છે',
      'upload_failed': 'છબી અપલોડ નિષ્ફળ',
      'loading': 'ડેટા લોડ થઈ રહ્યો છે...',
      'success': 'ક્રિયા સફળતાપૂર્વક પૂર્ણ થઈ',
      'empty': 'કોઈ રેકોર્ડ મળ્યો નથી',

      // Lifecycle & Duration
      'installation_duration': 'ઇન્સ્ટોલેશન સમયગાળો',
      'first_in_date': 'પ્રથમ સ્થાપન (સક્રિયકરણ)',
      'last_in_date': 'હાલનું સ્થાપન',
      'last_out_date': 'છેલ્લું નિષ્કાસન',
      'expiry_date': 'વોરંટી સમાપ્તિ તારીખ',
      'operating_time': 'કુલ કાર્યકારી સમય',
      'lifecycle_history': 'જીવનચક્ર ઇતિહાસ',
      'evidence_hash': 'SHA-256 સુરક્ષા હેશ',

      // Profile & Company
      'customer_profile': 'ગ્રાહક પ્રોફાઇલ',
      'facility_code': 'સુવિધા કોડ',
      'company_name': 'કંપનીનું નામ',
      'gst_number': 'જીએસટી નંબર',
      'plant_location': 'મેન્યુફેક્ચરિંગ પ્લાન્ટ',
      'contact_helpline': 'ગુણવત્તા હેલ્પલાઇન',
      'official_website': 'સત્તાવાર પોર્ટલ',
      'registered_office': 'નોંધાયેલ ઓફિસ',
      'language_settings': 'ભાષા સેટિંગ્સ',
      'sign_in': 'સાઇન ઇન કરો',
      'sign_out': 'સાઇન આઉટ',
      'auth_welcome': 'ઔદ્યોગિક પ્રમાણીકરણ',
      'auth_subtitle': 'ચકાસાયેલ રેકોર્ડ્સ માટે સાઇન ઇન કરો',
      'email': 'ઈમેઈલ સરનામું',
      'password': 'પાસવર્ડ',
      'enter_bearing_id': 'બેરિંગ આઈડી દાખલ કરો',
    },
  };

  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'hi', 'gu'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
