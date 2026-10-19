import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/auth/auth_controller.dart';
import 'core/config/app_config.dart';
import 'core/localization/app_localizations.dart';
import 'core/localization/locale_controller.dart';
import 'core/router/app_router.dart';
import 'core/router/app_routes.dart';
import 'core/services/supabase_service.dart';
import 'core/theme/app_theme.dart';
import 'features/qr_generation/data/repositories/qr_management_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize environment configuration and services
  await AppConfig.initialize();
  await SupabaseService.initialize();
  await AuthController.instance.initialize();
  await QrManagementRepository.loadFromLocalStorage();

  runApp(const PivotBearingsApp());
}

class PivotBearingsApp extends StatelessWidget {
  const PivotBearingsApp({super.key});

  String _determineInitialRoute() {
    if (!AuthController.instance.isAuthenticated) {
      return AppRoutes.authLogin;
    }
    if (AuthController.instance.isAdmin) {
      return AppRoutes.adminDashboard;
    }
    if (!AuthController.instance.isApproved) {
      return AppRoutes.pendingVerification;
    }
    return AppRoutes.customerHome;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LocaleController.currentLocale,
      builder: (context, currentLocale, _) {
        return MaterialApp(
          title: 'Pivot Bearings India',
          debugShowCheckedModeBanner: false,
          locale: currentLocale,
          theme: AppTheme.industrialTheme,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          initialRoute: _determineInitialRoute(),
          onGenerateRoute: AppRouter.onGenerateRoute,
        );
      },
    );
  }
}
