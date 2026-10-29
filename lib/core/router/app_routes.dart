/// Pivot Bearings India - Route Names
abstract class AppRoutes {
  static const String initial = '/';
  static const String authLogin = '/login';
  static const String pendingVerification = '/pending-verification';
  static const String customerHome = '/home';
  static const String customerProfile = '/profile';
  static const String qrScanner = '/scanner';
  static const String bearingAuthentication = '/bearing/authenticate';
  static const String trackBearing = '/track-bearing';
  static const String bearingVerification = '/bearing/verification';
  static const String inConfirmation = '/bearing/confirm-in';
  static const String inVerificationCapture = '/bearing/capture-in-proof';
  static const String inSuccess = '/bearing/success-in';
  static const String outConfirmation = '/bearing/confirm-out';
  static const String outVerificationCapture = '/bearing/capture-out-proof';
  static const String outResult = '/bearing/success-out';

  // Admin Web / Desktop Routes
  static const String adminDashboard = '/admin';
  static const String qrBulkGeneration = '/admin/qr-generation';
  static const String qrInventory = '/admin/qr-inventory';
  static const String warrantyCheck = '/warranty-check';
  static const String markedOutWarranty = '/marked-out-warranty';
  static const String rewardWallet = '/rewards';
  static const String accessDenied = '/access-denied';
}
