/// Pivot Bearings India - Role-Based Access Control (RBAC) System
///
/// Exactly two authorized enterprise system roles:
/// 1. ADMIN - Full factory management, QR generation, item master, warranty allocation, audit logs
/// 2. USER  - Certified field operator, customer, optical QR verification, lifecycle IN/OUT tracking
enum AppRole {
  admin,
  user;

  bool get isAdmin => this == AppRole.admin;
  bool get isUser => this == AppRole.user;

  String get code => this == AppRole.admin ? 'ADMIN' : 'USER';

  String get displayTitle => this == AppRole.admin ? 'Administrator' : 'Standard User / Operator';

  String get shortBadge => this == AppRole.admin ? 'ADMIN' : 'USER';

  String get description => this == AppRole.admin
      ? 'Directorate & Quality Control: Unrestricted access to QR manufacturing, Item Master, warranty horizons, and security audit logs.'
      : 'Field Operator & Certified Customer: Optical scanning, bearing verification, and IN/OUT lifecycle reporting.';

  static AppRole fromString(String? roleStr) {
    if (roleStr == null) return AppRole.user;
    final normalized = roleStr.trim().toUpperCase();
    if (normalized == 'ADMIN' || normalized == 'ADMINISTRATOR') {
      return AppRole.admin;
    }
    return AppRole.user;
  }
}
