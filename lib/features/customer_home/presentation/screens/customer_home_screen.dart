import 'package:flutter/material.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../bearing_verification/data/models/bearing_model.dart';
import '../../../bearing_verification/data/repositories/bearing_repository.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  int _currentNavIndex = 0;
  final BearingRepository _bearingRepo = BearingRepositoryImpl();
  int _inCount = 0;
  int _outCount = 0;
  int _activeCount = 0;
  bool _isNavigating = false;

  void _safeNavigate(String routeName) {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    Navigator.pushNamed(context, routeName).then((_) {
      if (mounted) {
        setState(() {
          _isNavigating = false;
          _currentNavIndex = 0;
        });
        _loadDashboardData();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    AuthController.instance.addListener(_onAuthChanged);
    _loadDashboardData();
  }

  @override
  void dispose() {
    AuthController.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDashboardData() async {
    final profile = await SupabaseService.fetchUserProfile();
    final auth = AuthController.instance;
    final bearings = await _bearingRepo.getAllBearings(
      customerId: profile['id']?.toString() ?? auth.userId,
      customerEmail: profile['email']?.toString() ?? auth.userEmail,
      facilityCode: profile['facility_code']?.toString(),
    );
    if (mounted) {
      setState(() {
        _inCount = bearings.where((b) => b.state == BearingLifecycleState.currentlyIn).length;
        _outCount = bearings.where((b) => b.state == BearingLifecycleState.currentlyOut).length;
        _activeCount = bearings.where((b) => !b.isWarrantyExpired && b.state != BearingLifecycleState.notActivated).length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final auth = AuthController.instance;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppDimensions.gutterMobile),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - (AppDimensions.gutterMobile * 2),
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header & Brand Title
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                                        border: Border.all(color: AppColors.primary, width: 1.2),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Image.asset(
                                        'assets/webappicon.png',
                                        width: 38,
                                        height: 38,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'PIVOT BEARINGS',
                                            style: AppTypography.headlineSm.copyWith(
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 1.2,
                                              color: AppColors.primary,
                                              fontSize: 16,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (auth.isAdmin)
                                IconButton(
                                  icon: const Icon(Icons.admin_panel_settings_rounded, color: AppColors.primary, size: 26),
                                  tooltip: 'Open Admin Workstation',
                                  onPressed: () => Navigator.pushNamed(context, AppRoutes.adminDashboard),
                                ),
                              IconButton(
                                icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
                                tooltip: 'Refresh Dashboard',
                                onPressed: _loadDashboardData,
                              ),
                            ],
                          ),

                          const SizedBox(height: AppDimensions.spaceMd),

                          // Admin Workstation Quick Access Banner
                          if (auth.isAdmin) ...[
                            InkWell(
                              mouseCursor: SystemMouseCursors.click,
                              onTap: () => Navigator.pushNamed(context, AppRoutes.adminDashboard),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.admin_panel_settings, color: Colors.white, size: 28),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'ADMIN WORKSTATION',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13,
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'Tap to open telemetry, QR generation & registry',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'OPEN',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: AppDimensions.spaceMd),
                          ],

                          // Dynamic Metric Row (visible if Warranty or Track module is enabled)
                          if (auth.hasTrackBearingAccess || auth.hasWarrantyAccess) ...[
                            Row(
                              children: [
                                if (auth.hasTrackBearingAccess) ...[
                                  Expanded(
                                    child: _buildMetricTile(count: '$_inCount', label: loc.translate('currently_in')),
                                  ),
                                  const SizedBox(width: AppDimensions.spaceSm),
                                  Expanded(
                                    child: _buildMetricTile(count: '$_outCount', label: loc.translate('currently_out')),
                                  ),
                                ],
                                if (auth.hasTrackBearingAccess && auth.hasWarrantyAccess)
                                  const SizedBox(width: AppDimensions.spaceSm),
                                if (auth.hasWarrantyAccess)
                                  Expanded(
                                    child: InkWell(
                                      mouseCursor: SystemMouseCursors.click,
                                      onTap: () => _safeNavigate(AppRoutes.warrantyCheck),
                                      borderRadius: BorderRadius.circular(24),
                                      child: _buildMetricTile(
                                        count: '$_activeCount',
                                        label: loc.translate('active_warranties'),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppDimensions.spaceMd),
                          ] else ...[
                            // Standard default badge for newly registered users
                            _buildDefaultAuthenticationBadge(),
                            const SizedBox(height: AppDimensions.spaceMd),
                          ],

                          // 1. BEARING AUTHENTICATION PAGE (Always Available to All Registered Users)
                          _buildAuthenticationCard(),

                          const SizedBox(height: AppDimensions.spaceSm),

                          // 2. TRACK YOUR BEARING MODULE (Only visible when permitted by admin)
                          if (auth.hasTrackBearingAccess) ...[
                            _buildTrackBearingCard(),
                            const SizedBox(height: AppDimensions.spaceSm),
                          ],

                          // 3. WARRANTY MODULE (Only visible when permitted by admin)
                          if (auth.hasWarrantyAccess) ...[
                            _buildWarrantyInOutCard(),
                            const SizedBox(height: AppDimensions.spaceSm),
                            _buildWarrantyHistoryCard(loc),
                            const SizedBox(height: AppDimensions.spaceSm),
                          ],

                          const Spacer(),
                          const SizedBox(height: AppDimensions.spaceSm),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(loc),
    );
  }

  /// Default banner shown when only Bearing Authentication is active
  Widget _buildDefaultAuthenticationBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0D8A4E), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFF0D8A4E),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'STANDARD ACCESS ACTIVE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1B5E20),
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Bearing Authentication is enabled. Additional modules (Warranty & Tracking) can be enabled by your administrator.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black87,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Bearing Authentication Card - Unconditionally available for all users
  Widget _buildAuthenticationCard() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        side: const BorderSide(color: Color(0xFF0D8A4E), width: 1.8),
      ),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () => _safeNavigate(AppRoutes.bearingAuthentication),
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF0D8A4E), width: 1.5),
                ),
                child: const Center(
                  child: Icon(
                    Icons.verified_user_rounded,
                    color: Color(0xFF0D8A4E),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AUTHENTICATE BEARING',
                      style: AppTypography.labelMd.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF1B5E20),
                        letterSpacing: 0.5,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Verify genuine Pivot bearing & check official scan counter',
                      style: AppTypography.caption.copyWith(
                        color: Colors.black87,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Color(0xFF0D8A4E),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Track Your Bearing Card - Role Protected
  Widget _buildTrackBearingCard() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        side: const BorderSide(color: AppColors.primary, width: 1.8),
      ),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () => _safeNavigate(AppRoutes.trackBearing),
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: const Center(
                  child: Icon(
                    Icons.sync_alt_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TRACK YOUR BEARING',
                      style: AppTypography.labelMd.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        letterSpacing: 0.5,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Instant QR-only IN / OUT logging & usage duration tracking',
                      style: AppTypography.caption.copyWith(
                        color: Colors.black87,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.primary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Warranty Bearing In & Out Card (Scan QR, upload proof & assign warranty)
  Widget _buildWarrantyInOutCard() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        side: const BorderSide(color: AppColors.primary, width: 1.8),
      ),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () => _safeNavigate(AppRoutes.qrScanner),
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: const Center(
                  child: Icon(
                    Icons.camera_alt_outlined,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BEARING IN / OUT (WARRANTY)',
                      style: AppTypography.labelMd.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        letterSpacing: 0.5,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Mark Bearing In & upload proof photo to activate official warranty',
                      style: AppTypography.caption.copyWith(
                        color: Colors.black87,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.primary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Warranty Products & History Card
  Widget _buildWarrantyHistoryCard(AppLocalizations loc) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        side: const BorderSide(color: AppColors.primary, width: 1.8),
      ),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () => _safeNavigate(AppRoutes.warrantyCheck),
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: const Center(
                  child: Icon(
                    Icons.shield_outlined,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WARRANTY CHECK & PRODUCTS',
                      style: AppTypography.labelMd.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        letterSpacing: 0.5,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Check active warranties, expiry status & registered bearings',
                      style: AppTypography.caption.copyWith(
                        color: Colors.black87,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.primary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Dynamic Bottom Navigation Bar that automatically adjusts based on active modules
  Widget _buildBottomNav(AppLocalizations loc) {
    final auth = AuthController.instance;

    final navItems = <_HomeNavItem>[
      _HomeNavItem(
        icon: Icons.home,
        label: loc.translate('home'),
        onTap: () {},
      ),
      _HomeNavItem(
        icon: Icons.verified_user_rounded,
        label: 'Authenticate',
        onTap: () => _safeNavigate(AppRoutes.bearingAuthentication),
      ),
      if (auth.hasTrackBearingAccess)
        _HomeNavItem(
          icon: Icons.sync_alt_rounded,
          label: 'Track',
          onTap: () => _safeNavigate(AppRoutes.trackBearing),
        ),
      if (auth.hasWarrantyAccess)
        _HomeNavItem(
          icon: Icons.shield_outlined,
          label: 'Warranty',
          onTap: () => _safeNavigate(AppRoutes.warrantyCheck),
        ),
      if (auth.isAdmin)
        _HomeNavItem(
          icon: Icons.admin_panel_settings_rounded,
          label: 'Admin',
          onTap: () => _safeNavigate(AppRoutes.adminDashboard),
        )
      else
        _HomeNavItem(
          icon: Icons.manage_accounts,
          label: loc.translate('account'),
          onTap: () => _safeNavigate(AppRoutes.customerProfile),
        ),
    ];

    final safeIndex = _currentNavIndex < navItems.length ? _currentNavIndex : 0;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.primary, width: 1.0)),
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: safeIndex,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        backgroundColor: AppColors.background,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.black54,
        onTap: (index) {
          if (index == 0) return;
          if (index < navItems.length) {
            setState(() => _currentNavIndex = index);
            navItems[index].onTap();
          }
        },
        items: navItems.map((item) {
          return BottomNavigationBarItem(
            icon: Icon(item.icon),
            label: item.label,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMetricTile({required String count, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 8.0),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Column(
        children: [
          Text(count, style: AppTypography.headlineMd.copyWith(fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 4.0),
          Text(
            label.toUpperCase(),
            style: AppTypography.caption.copyWith(
              letterSpacing: 0.2,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _HomeNavItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _HomeNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}
