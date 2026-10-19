import 'package:flutter/material.dart';
import '../auth/auth_controller.dart';
import '../../features/admin_dashboard/presentation/screens/admin_dashboard_screen.dart';
import '../../features/auth/presentation/screens/access_denied_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/pending_verification_screen.dart';
import '../../features/bearing_verification/presentation/screens/bearing_authentication_screen.dart';
import '../../features/bearing_verification/presentation/screens/bearing_verification_screen.dart';
import '../../features/bearing_verification/presentation/screens/track_bearing_screen.dart';
import '../../features/bearing_verification/presentation/screens/in_confirmation_screen.dart';
import '../../features/bearing_verification/presentation/screens/in_success_screen.dart';
import '../../features/bearing_verification/presentation/screens/out_confirmation_screen.dart';
import '../../features/bearing_verification/presentation/screens/out_result_screen.dart';
import '../../features/customer_home/presentation/screens/customer_home_screen.dart';
import '../../features/customer_profile/presentation/screens/customer_profile_screen.dart';
import '../../features/optical_capture/presentation/screens/verification_evidence_capture_screen.dart';
import '../../features/qr_generation/presentation/screens/qr_bulk_generation_screen.dart';
import '../../features/qr_inventory/presentation/screens/qr_inventory_screen.dart';
import '../../features/qr_scanner/presentation/screens/qr_scanner_screen.dart';
import '../../features/warranty_check/presentation/screens/warranty_check_screen.dart';
import 'app_routes.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.authLogin:
        return MaterialPageRoute(builder: (_) => const LoginScreen());

      case AppRoutes.pendingVerification:
        return MaterialPageRoute(builder: (_) => const PendingVerificationScreen());

      case AppRoutes.customerProfile:
        return MaterialPageRoute(builder: (_) => const CustomerProfileScreen());

      case AppRoutes.initial:
      case AppRoutes.customerHome:
        if (!AuthController.instance.isApproved && !AuthController.instance.isAdmin) {
          return MaterialPageRoute(builder: (_) => const PendingVerificationScreen());
        }
        return MaterialPageRoute(builder: (_) => const CustomerHomeScreen());

      case AppRoutes.qrScanner:
        if (!AuthController.instance.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        return MaterialPageRoute(builder: (_) => const QrScannerScreen());

      case AppRoutes.bearingAuthentication:
        // Bearing Authentication is universally accessible to all registered users
        final initialPayload = (settings.arguments as String?);
        return MaterialPageRoute(
          builder: (_) => BearingAuthenticationScreen(initialPayload: initialPayload),
        );

      case AppRoutes.trackBearing:
        if (!AuthController.instance.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        final initialPayload = (settings.arguments as String?);
        return MaterialPageRoute(
          builder: (_) => TrackBearingScreen(initialPayload: initialPayload),
        );

      case AppRoutes.bearingVerification:
        if (!AuthController.instance.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        final id = (settings.arguments as String?) ?? '';
        return MaterialPageRoute(builder: (_) => BearingVerificationScreen(bearingId: id));

      case AppRoutes.inConfirmation:
        if (!AuthController.instance.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        final id = (settings.arguments as String?) ?? '';
        return MaterialPageRoute(builder: (_) => InConfirmationScreen(bearingId: id));

      case AppRoutes.inVerificationCapture:
        if (!AuthController.instance.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        final id = (settings.arguments as String?) ?? '';
        return MaterialPageRoute(
          builder: (_) => VerificationEvidenceCaptureScreen(
            bearingId: id,
            imageType: 'IN_INSTALLATION',
          ),
        );

      case AppRoutes.inSuccess:
        if (!AuthController.instance.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        final id = (settings.arguments as String?) ?? '';
        return MaterialPageRoute(builder: (_) => InSuccessScreen(bearingId: id));

      case AppRoutes.outConfirmation:
        if (!AuthController.instance.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        final id = (settings.arguments as String?) ?? '';
        return MaterialPageRoute(builder: (_) => OutConfirmationScreen(bearingId: id));

      case AppRoutes.outVerificationCapture:
        if (!AuthController.instance.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        final id = (settings.arguments as String?) ?? '';
        return MaterialPageRoute(
          builder: (_) => VerificationEvidenceCaptureScreen(
            bearingId: id,
            imageType: 'OUT_REMOVAL',
          ),
        );

      case AppRoutes.outResult:
        if (!AuthController.instance.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        final id = (settings.arguments as String?) ?? '';
        return MaterialPageRoute(builder: (_) => OutResultScreen(bearingId: id));

      // RBAC Protected Admin Modules
      case AppRoutes.adminDashboard:
        if (!AuthController.instance.isAdmin) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Executive Admin Dashboard'),
          );
        }
        return MaterialPageRoute(builder: (_) => const AdminDashboardScreen());

      case AppRoutes.qrBulkGeneration:
        if (!AuthController.instance.isAdmin) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'QR Bulk Matrix Generator'),
          );
        }
        return MaterialPageRoute(builder: (_) => const QrBulkGenerationScreen());

      case AppRoutes.qrInventory:
        if (!AuthController.instance.isAdmin) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'QR Registry & Master Inventory'),
          );
        }
        return MaterialPageRoute(builder: (_) => const QrInventoryScreen());

      case AppRoutes.accessDenied:
        return MaterialPageRoute(
          builder: (_) => const AccessDeniedScreen(attemptedModule: 'Executive Admin Dashboard'),
        );

      case AppRoutes.warrantyCheck:
        if (!AuthController.instance.hasWarrantyAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Warranty Module'),
          );
        }
        final initialId = (settings.arguments as String?);
        return MaterialPageRoute(builder: (_) => WarrantyCheckScreen(initialBearingId: initialId));

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('Route not found: ${settings.name}'),
            ),
          ),
        );
    }
  }
}
