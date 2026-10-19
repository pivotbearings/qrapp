import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';

class PendingVerificationScreen extends StatefulWidget {
  const PendingVerificationScreen({super.key});

  @override
  State<PendingVerificationScreen> createState() => _PendingVerificationScreenState();
}

class _PendingVerificationScreenState extends State<PendingVerificationScreen>
    with SingleTickerProviderStateMixin {
  Timer? _pollingTimer;
  bool _isChecking = false;
  bool _isApprovedNow = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initial check
    _checkStatus(showFeedback: false);

    // Continuous auto-polling every 3 seconds for instant activation once approved by Admin
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && !_isApprovedNow && !_isChecking) {
        _checkStatus(showFeedback: false);
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }


  Future<void> _checkStatus({bool showFeedback = true}) async {
    if (_isChecking) return;
    setState(() => _isChecking = true);

    try {
      final isApproved = await AuthController.instance.checkApprovalStatus();
      if (!mounted) return;

      if (isApproved) {
        setState(() {
          _isApprovedNow = true;
          _isChecking = false;
        });

        // Cancel timer immediately
        _pollingTimer?.cancel();

        // Brief delay to display clearance confirmation then route
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;

        if (AuthController.instance.isAdmin) {
          Navigator.pushReplacementNamed(context, AppRoutes.adminDashboard);
        } else {
          Navigator.pushReplacementNamed(context, AppRoutes.customerHome);
        }
        return;
      } else if (showFeedback) {
        AppSnackBar.showInfo(
          context,
          'CLEARANCE STATUS: Still pending Administrator approval. Auto-refreshing...',
        );
      }
    } catch (_) {
      // Graceful fallback
    } finally {
      if (mounted && !_isApprovedNow) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _handleSignOut() async {
    _pollingTimer?.cancel();
    await AuthController.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.authLogin, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthController.instance;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const IndustrialAppBar(
        title: 'Clearance & Verification',
        showBackButton: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimensions.gutterMobile),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: IndustrialCard(
                padding: const EdgeInsets.all(AppDimensions.spaceXl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Brand / Radar Pulse Graphic
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: _isApprovedNow
                              ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                              : AppColors.primary.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isApprovedNow ? const Color(0xFF22C55E) : AppColors.primary,
                            width: 2.0,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            _isApprovedNow ? Icons.verified_user : Icons.hourglass_top,
                            size: 36,
                            color: _isApprovedNow ? const Color(0xFF22C55E) : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spaceLg),

                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: _isApprovedNow ? const Color(0xFF22C55E) : AppColors.primary,
                        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                      ),
                      child: Text(
                        _isApprovedNow
                            ? 'CLEARANCE GRANTED · ACTIVATING'
                            : 'ACCOUNT PENDING ADMIN APPROVAL',
                        style: const TextStyle(
                          color: AppColors.background,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),

                    Text(
                      _isApprovedNow
                          ? 'Access Authorized!'
                          : 'Clearance Under Review',
                      style: AppTypography.headlineMd,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),

                    Text(
                      _isApprovedNow
                          ? 'Your account has been approved by the administrator. Redirecting to your workstation...'
                          : 'Your account has been registered successfully. Enterprise security policy requires an Administrator to grant access before you can operate the application.',
                      style: AppTypography.bodySm,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppDimensions.spaceLg),

                    // User Details Information Card
                    Container(
                      padding: const EdgeInsets.all(AppDimensions.spaceMd),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDetailRow('Account Name:', auth.userName ?? 'Operator'),
                          const Divider(height: 16),
                          _buildDetailRow('Email Address:', auth.userEmail ?? '—'),
                          const Divider(height: 16),
                          _buildDetailRow('Assigned Role:', auth.role.displayTitle),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppDimensions.spaceLg),

                    // Continuous Auto-Refresh indicator
                    if (!_isApprovedNow) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Live sync active — updates the second admin approves',
                            style: AppTypography.caption.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.spaceMd),
                    ],

                    // Action Buttons
                    IndustrialButton(
                      label: _isChecking ? 'CHECKING...' : 'CHECK STATUS NOW',
                      icon: Icons.sync,
                      isLoading: _isChecking,
                      onPressed: _isApprovedNow ? null : () => _checkStatus(showFeedback: true),
                    ),
                    const SizedBox(height: AppDimensions.spaceSm),

                    IndustrialButton.secondary(
                      label: 'SIGN OUT / USE DIFFERENT ACCOUNT',
                      icon: Icons.logout,
                      onPressed: _handleSignOut,
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

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTypography.caption),
        Text(value, style: AppTypography.labelMd),
      ],
    );
  }
}
