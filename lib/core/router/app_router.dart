import 'package:flutter/material.dart';
import '../auth/auth_controller.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_typography.dart';
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
import '../../features/rewards/presentation/screens/reward_wallet_screen.dart';
import 'app_routes.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    // Clean and normalize route name (strip trailing slash for web URLs)
    var routeName = settings.name ?? AppRoutes.initial;
    if (routeName.length > 1 && routeName.endsWith('/')) {
      routeName = routeName.substring(0, routeName.length - 1);
    }

    final auth = AuthController.instance;

    switch (routeName) {
      // Authentication Screen
      case AppRoutes.authLogin:
        if (auth.isAuthenticated) {
          if (auth.isAdmin) {
            return MaterialPageRoute(builder: (_) => const AdminDashboardScreen());
          }
          if (!auth.isApproved) {
            return MaterialPageRoute(builder: (_) => const PendingVerificationScreen());
          }
          return MaterialPageRoute(builder: (_) => const CustomerHomeScreen());
        }
        return MaterialPageRoute(builder: (_) => const LoginScreen());

      // Pending Verification
      case AppRoutes.pendingVerification:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (auth.isApproved || auth.isAdmin) {
          return MaterialPageRoute(
            builder: (_) => auth.isAdmin ? const AdminDashboardScreen() : const CustomerHomeScreen(),
          );
        }
        return MaterialPageRoute(builder: (_) => const PendingVerificationScreen());

      // Customer Profile & Account Details
      case AppRoutes.customerProfile:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        return MaterialPageRoute(builder: (_) => const CustomerProfileScreen());

      // Root Initial & Customer Home Routes
      case AppRoutes.initial:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (auth.isAdmin) {
          return MaterialPageRoute(builder: (_) => const AdminDashboardScreen());
        }
        if (!auth.isApproved) {
          return MaterialPageRoute(builder: (_) => const PendingVerificationScreen());
        }
        return MaterialPageRoute(builder: (_) => const CustomerHomeScreen());

      case AppRoutes.customerHome:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (!auth.isApproved && !auth.isAdmin) {
          return MaterialPageRoute(builder: (_) => const PendingVerificationScreen());
        }
        return MaterialPageRoute(builder: (_) => const CustomerHomeScreen());

      // Optical QR Viewfinder Scanner
      case AppRoutes.qrScanner:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (!auth.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        return MaterialPageRoute(builder: (_) => const QrScannerScreen());

      // Bearing Authentication (Always accessible to all authenticated users)
      case AppRoutes.bearingAuthentication:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        final initialPayload = (settings.arguments as String?);
        return MaterialPageRoute(
          builder: (_) => BearingAuthenticationScreen(initialPayload: initialPayload),
        );

      // Track Bearing
      case AppRoutes.trackBearing:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (!auth.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        final initialPayload = (settings.arguments as String?);
        return MaterialPageRoute(
          builder: (_) => TrackBearingScreen(initialPayload: initialPayload),
        );

      case AppRoutes.bearingVerification:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (!auth.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        final id = (settings.arguments as String?) ?? '';
        return MaterialPageRoute(builder: (_) => BearingVerificationScreen(bearingId: id));

      case AppRoutes.inConfirmation:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (!auth.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        final id = (settings.arguments as String?) ?? '';
        return MaterialPageRoute(builder: (_) => InConfirmationScreen(bearingId: id));

      case AppRoutes.inVerificationCapture:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (!auth.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        String id = '';
        String? notes;
        if (settings.arguments is Map) {
          final map = settings.arguments as Map;
          id = map['bearingId']?.toString() ?? '';
          notes = map['notes']?.toString();
        } else if (settings.arguments is String) {
          id = settings.arguments as String;
        }
        return MaterialPageRoute(
          builder: (_) => VerificationEvidenceCaptureScreen(
            bearingId: id,
            imageType: 'IN_INSTALLATION',
            notes: notes,
          ),
        );

      case AppRoutes.inSuccess:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (!auth.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        final id = (settings.arguments as String?) ?? '';
        return MaterialPageRoute(builder: (_) => InSuccessScreen(bearingId: id));

      case AppRoutes.outConfirmation:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (!auth.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        final id = (settings.arguments as String?) ?? '';
        return MaterialPageRoute(builder: (_) => OutConfirmationScreen(bearingId: id));

      case AppRoutes.outVerificationCapture:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (!auth.hasTrackBearingAccess) {
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
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (!auth.hasTrackBearingAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Track Your Bearing Module'),
          );
        }
        final id = (settings.arguments as String?) ?? '';
        return MaterialPageRoute(builder: (_) => OutResultScreen(bearingId: id));

      // RBAC Protected Admin Modules
      case AppRoutes.adminDashboard:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (!auth.isAdmin) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Executive Admin Dashboard'),
          );
        }
        return MaterialPageRoute(builder: (_) => const AdminDashboardScreen());

      case AppRoutes.qrBulkGeneration:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (!auth.isAdmin) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'QR Bulk Matrix Generator'),
          );
        }
        return MaterialPageRoute(builder: (_) => const QrBulkGenerationScreen());

      case AppRoutes.qrInventory:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (!auth.isAdmin) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'QR Registry & Master Inventory'),
          );
        }
        return MaterialPageRoute(builder: (_) => const QrInventoryScreen());

      case AppRoutes.accessDenied:
        return MaterialPageRoute(
          builder: (_) => const AccessDeniedScreen(attemptedModule: 'Requested Protected Area'),
        );

      case AppRoutes.warrantyCheck:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        if (!auth.hasWarrantyAccess) {
          return MaterialPageRoute(
            builder: (_) => const AccessDeniedScreen(attemptedModule: 'Warranty Module'),
          );
        }
        final initialId = (settings.arguments as String?);
        return MaterialPageRoute(builder: (_) => WarrantyCheckScreen(initialBearingId: initialId));

      case AppRoutes.rewardWallet:
        if (!auth.isAuthenticated) {
          return MaterialPageRoute(builder: (_) => const LoginScreen());
        }
        return MaterialPageRoute(builder: (_) => const RewardWalletScreen());

      default:
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(AppDimensions.gutterMobile),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.explore_off_rounded, color: Colors.white, size: 32),
                      ),
                      const SizedBox(height: AppDimensions.spaceMd),
                      const Text('PAGE NOT FOUND', style: AppTypography.headlineSm),
                      const SizedBox(height: 6),
                      Text(
                        'The requested URL path "$routeName" does not exist or has been moved.',
                        style: AppTypography.caption,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppDimensions.spaceLg),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.home, size: 18),
                        label: const Text('RETURN TO HOME'),
                        onPressed: () {
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            auth.isAdmin ? AppRoutes.adminDashboard : AppRoutes.customerHome,
                            (route) => false,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
    }
  }
}
