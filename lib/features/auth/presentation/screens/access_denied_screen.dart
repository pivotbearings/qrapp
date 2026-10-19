import 'package:flutter/material.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';

class AccessDeniedScreen extends StatelessWidget {
  final String attemptedModule;

  const AccessDeniedScreen({
    super.key,
    this.attemptedModule = 'Administrative Workstation',
  });

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.instance;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const IndustrialAppBar(
        title: 'Access Restricted',
        showBackButton: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimensions.gutterMobile),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: IndustrialCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary, width: 2.0),
                        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                      ),
                      child: const Center(
                        child: Icon(Icons.lock_outline, size: 36, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spaceMd),
                    const Text(
                      'ROLE-BASED RESTRICTION',
                      style: AppTypography.caption,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Access Denied: $attemptedModule',
                      style: AppTypography.headlineSm,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppDimensions.spaceMd),
                    Text(
                      'Your authenticated account (${auth.userEmail ?? 'Operator'}) has the role [${auth.role.code}].\n\nAccess to bulk QR generation, item master cataloging, warranty horizons, and telemetry audit history is restricted strictly to accounts with [ADMIN] privileges.',
                      style: AppTypography.bodySm,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppDimensions.spaceLg),
                    IndustrialButton(
                      label: 'RETURN TO OPERATOR WORKSTATION',
                      icon: Icons.home,
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, AppRoutes.customerHome);
                      },
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),
                    IndustrialButton.secondary(
                      label: 'SWITCH / SIGN IN AS ADMIN',
                      icon: Icons.switch_account,
                      onPressed: () {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          AppRoutes.authLogin,
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
      ),
    );
  }
}
