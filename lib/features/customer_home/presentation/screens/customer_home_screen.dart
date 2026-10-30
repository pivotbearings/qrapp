import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../bearing_verification/data/models/bearing_model.dart';
import '../../../bearing_verification/data/repositories/bearing_repository.dart';
import '../../../bearing_verification/data/services/bearing_track_service.dart';
import '../../../rewards/data/services/reward_service.dart';
import '../../../../core/widgets/app_snack_bar.dart';

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
  int _underWarrantyCount = 0;
  int _expiringSoonCount = 0;
  int _expiredWarrantyCount = 0;
  int _markedOutUnderWarrantyCount = 0;
  bool _isNavigating = false;
  bool? _isRefreshing = false;
  double? _refreshTurns = 0.0;

  @override
  void reassemble() {
    super.reassemble();
    _refreshTurns ??= 0.0;
    _isRefreshing ??= false;
  }
  RewardProfile _rewardProfile = RewardProfile.defaultProfile();
  AdBannerConfig _adConfig = AdBannerConfig.defaultConfig();
  StreamSubscription<AdBannerConfig>? _adBannerSub;
  RealtimeChannel? _supabaseAdChannel;

  void _safeNavigate(String routeName, {Object? arguments}) {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    Navigator.pushNamed(context, routeName, arguments: arguments).then((_) {
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
    _adConfig = AdBannerService.currentConfig;
    
    // 1. Listen for immediate in-app real-time broadcasts
    _adBannerSub = AdBannerService.onBannerConfigChanged.listen((newConfig) {
      if (mounted) {
        setState(() => _adConfig = newConfig);
      }
    });

    // 2. Listen for remote Supabase Realtime changes across any browser / device
    _initSupabaseRealtimeAdBanner();

    _loadDashboardData();
  }

  void _initSupabaseRealtimeAdBanner() {
    if (!SupabaseService.isInitialized) return;
    try {
      final client = SupabaseService.client;
      _supabaseAdChannel = client
          .channel('public:app_settings:ad_banner')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'app_settings',
            filter: const PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'setting_key',
              value: 'home_ad_banner',
            ),
            callback: (payload) {
              final newRecord = payload.newRecord;
              if (newRecord.isNotEmpty && newRecord['setting_value'] != null) {
                final val = newRecord['setting_value'];
                final Map<String, dynamic> configMap = val is Map<String, dynamic>
                    ? val
                    : (val is String ? jsonDecode(val) : Map<String, dynamic>.from(val as Map));
                final updated = AdBannerConfig.fromJson(configMap);
                AdBannerService.notifyBannerUpdated(updated);
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('AdBanner realtime subscription notice: $e');
    }
  }

  @override
  void dispose() {
    _adBannerSub?.cancel();
    if (_supabaseAdChannel != null) {
      try {
        SupabaseService.client.removeChannel(_supabaseAdChannel!);
      } catch (_) {}
    }
    AuthController.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDashboardData({bool showFeedback = false}) async {
    if (_isRefreshing ?? false) return;
    if (mounted) {
      setState(() {
        _isRefreshing = true;
        _refreshTurns = (_refreshTurns ?? 0.0) + 1.0;
      });
    }

    try {
      try {
        await AuthController.instance.refreshPermissions();
      } catch (_) {}

      final profile = await SupabaseService.fetchUserProfile();
      final auth = AuthController.instance;
      final bearings = await _bearingRepo.getAllBearings(
        customerId: profile['id']?.toString() ?? auth.userId,
        customerEmail: profile['email']?.toString() ?? auth.userEmail,
        facilityCode: profile['facility_code']?.toString(),
      );

      final inHistory = await BearingTrackService.fetchTrackInHistory();
      final outHistory = await BearingTrackService.fetchTrackOutHistory();
      final inFromBearings = bearings.where((b) => b.state == BearingLifecycleState.currentlyIn).length;
      final outFromBearings = bearings.where((b) => b.state == BearingLifecycleState.currentlyOut).length;

      if (mounted) {
        setState(() {
          _inCount = math.max(inHistory.length, inFromBearings);
          _outCount = math.max(outHistory.length, outFromBearings);
          _underWarrantyCount = bearings.where((b) => b.isUnderWarranty).length;
          _expiringSoonCount = bearings.where((b) => b.isExpiringSoon).length;
          _expiredWarrantyCount = bearings.where((b) => b.isWarrantyExpired).length;
          _markedOutUnderWarrantyCount = bearings.where((b) => b.isMarkedOutUnderWarranty).length;
        });
      }

      try {
        final rp = await RewardService.fetchUserRewardProfile();
        if (mounted) {
          setState(() => _rewardProfile = rp);
        }
      } catch (_) {}

      try {
        final ad = await AdBannerService.fetchBannerConfig(forceRefresh: true);
        if (mounted) {
          setState(() => _adConfig = ad);
        }
      } catch (_) {}

      if (showFeedback && mounted) {
        AppSnackBar.showSuccess(context, 'Dashboard data refreshed');
      }
    } catch (e) {
      if (showFeedback && mounted) {
        AppSnackBar.showError(context, 'Refresh failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
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
                final bool hasReward = auth.hasRewardPointsAccess && _rewardProfile.isEnabled && _rewardProfile.isRewardEligible;
                // If screen is unusually short (e.g. landscape or < 480px), allow scrolling fallback
                final bool isShortScreen = constraints.maxHeight.isFinite && constraints.maxHeight < 480;

                Widget buildContent({required bool useExpanded}) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header & Brand Title with Personalized Customer Greeting (Enlarged)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Image.asset(
                                  'assets/company_logo.webp',
                                  height: 50,
                                  fit: BoxFit.contain,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Namaste, ${auth.userName?.trim().isNotEmpty == true && auth.userName != "Operator" ? auth.userName!.trim() : "Valued Customer"}',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                            icon: AnimatedRotation(
                              turns: _refreshTurns ?? 0.0,
                              duration: const Duration(milliseconds: 650),
                              curve: Curves.easeInOut,
                              child: (_isRefreshing ?? false)
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.primary),
                                    )
                                  : const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 28),
                            ),
                            tooltip: 'Refresh Dashboard',
                            onPressed: (_isRefreshing ?? false) ? null : () => _loadDashboardData(showFeedback: true),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      // Admin Workstation Quick Access Banner
                      if (auth.isAdmin) ...[
                        InkWell(
                          mouseCursor: SystemMouseCursors.click,
                          onTap: () => Navigator.pushNamed(context, AppRoutes.adminDashboard),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                                const Icon(Icons.admin_panel_settings, color: Colors.white, size: 26),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                        const SizedBox(height: 8),
                      ],

                      // Dynamic Metric Row / Dashboard:
                      // Requirement 3: Both modules must not be active simultaneously.
                      // Requirement 8: When Warranty is enabled, display 3 summary counts (Under Warranty, Expiring Soon, Warranty Expired).
                      // Requirement 7: When Track Your Bearing is enabled, display two separate options (Product In, Product Out).
                      if (auth.hasWarrantyAccess) ...[
                        _buildWarrantyDashboard(),
                        const SizedBox(height: 8),
                      ] else if (auth.hasTrackBearingAccess) ...[
                        _buildTrackBearingDashboard(),
                        const SizedBox(height: 8),
                      ] else ...[
                        _buildDefaultAuthenticationBadge(),
                        const SizedBox(height: 8),
                      ],

                      // ADVERTISEMENT BANNER: Expanded to occupy 100% of remaining viewport with ZERO scroll
                      if (_adConfig.isActive)
                        if (useExpanded)
                          Expanded(
                            child: _buildAdvertisementBanner(expand: true),
                          )
                        else
                          _buildAdvertisementBanner(height: 220.0),

                      // Reward Points Wallet
                      if (hasReward) ...[
                        const SizedBox(height: 8),
                        _buildRewardWalletCard(),
                      ],
                    ],
                  );
                }

                if (isShortScreen) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: buildContent(useExpanded: false),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: buildContent(useExpanded: true),
                );
              },
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(loc),
    );
  }

  /// Advertisement Banner dynamically configurable from Admin Panel
  Widget _buildAdvertisementBanner({double height = 220.0, bool expand = false}) {
    return Container(
      width: double.infinity,
      height: expand ? null : height,
      decoration: BoxDecoration(
        color: const Color(0xFF001F59),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF001F59), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18001F59),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      // ClipRRect ensures the image is clipped inside the border — not on top of it
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.5),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openAdBannerLink,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(14.5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildAdBannerImage(_adConfig),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdBannerImage(AdBannerConfig config) {
    final fit = config.fitMode == 'contain' ? BoxFit.contain : BoxFit.cover;

    if (config.image.startsWith('assets/')) {
      return Image.asset(
        config.image,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _buildFallbackAdImage(config),
      );
    }

    if (config.image.startsWith('data:')) {
      try {
        final raw = config.image.contains(',') ? config.image.split(',')[1] : config.image;
        final bytes = base64Decode(raw);
        return Image.memory(
          bytes,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => _buildFallbackAdImage(config),
        );
      } catch (_) {
        return _buildFallbackAdImage(config);
      }
    }

    if (config.image.startsWith('http')) {
      return Image.network(
        config.image,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => _buildFallbackAdImage(config),
      );
    }

    return _buildFallbackAdImage(config);
  }

  Widget _buildFallbackAdImage(AdBannerConfig config) {
    return Container(
      color: const Color(0xFF001F59),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.precision_manufacturing_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 8),
            const Text(
              'PIVOT INDUSTRIAL BEARINGS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Heavy-Duty Precision Engineering & High-Load Reliability',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAdBannerLink() async {
    final target = _adConfig.targetUrl.trim();
    if (target.isEmpty) return;
    try {
      final uri = Uri.parse(target);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Could not launch ad target link: $e');
    }
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

  /// Reward Points Wallet Card
  Widget _buildRewardWalletCard() {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        side: const BorderSide(color: AppColors.primary, width: 1.8),
      ),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () => _safeNavigate(AppRoutes.rewardWallet),
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.stars,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'REWARD POINTS WALLET',
                      style: AppTypography.labelMd.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        letterSpacing: 0.5,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_rewardProfile.currentBalancePoints} Points',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'VIEW WALLET',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const SizedBox(width: 6),
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

  /// Requirement 7: When only Track Your Bearing is enabled, display two separate options:
  /// - Product In: Bearings currently tracked in
  /// - Product Out: Bearings that have been tracked out
  Widget _buildTrackBearingDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildTrackBearingOptionCard(
                title: 'Product In',
                subtitle: 'Currently tracked in',
                count: '$_inCount',
                icon: Icons.login_rounded,
                onTap: () => _safeNavigate(AppRoutes.trackBearing, arguments: 1),
              ),
            ),
            const SizedBox(width: AppDimensions.spaceSm),
            Expanded(
              child: _buildTrackBearingOptionCard(
                title: 'Product Out',
                subtitle: 'Tracked out bearings',
                count: '$_outCount',
                icon: Icons.logout_rounded,
                onTap: () => _safeNavigate(AppRoutes.trackBearing, arguments: 2),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrackBearingOptionCard({
    required String title,
    required String subtitle,
    required String count,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 18),
                ),
                Text(
                  count,
                  style: AppTypography.headlineMd.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: AppTypography.labelMd.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
                fontSize: 13,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: AppTypography.caption.copyWith(
                fontSize: 10.5,
                color: Colors.black54,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Requirement 8: When the Warranty module is enabled, display three summary counts:
  /// - Under Warranty: Total bearings currently under warranty
  /// - Expiring Soon: Total bearings whose warranty is nearing expiration (20% near time of expiry)
  /// - Warranty Expired: Total bearings whose warranty has expired
  Widget _buildWarrantyDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildWarrantySummaryCard(
                title: 'Under Warranty',
                count: '$_underWarrantyCount',
                icon: Icons.shield_rounded,
                onTap: () => Navigator.pushNamed(context, AppRoutes.warrantyCheck, arguments: 1).then((_) => _loadDashboardData()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildWarrantySummaryCard(
                title: 'Expiring Soon',
                count: '$_expiringSoonCount',
                icon: Icons.timer_outlined,
                onTap: () => Navigator.pushNamed(context, AppRoutes.warrantyCheck, arguments: 2).then((_) => _loadDashboardData()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildWarrantySummaryCard(
                title: 'Warranty Expired',
                count: '$_expiredWarrantyCount',
                icon: Icons.history_rounded,
                onTap: () => Navigator.pushNamed(context, AppRoutes.warrantyCheck, arguments: 3).then((_) => _loadDashboardData()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Dedicated Section: Marked Out Bearings Under Warranty
        InkWell(
          onTap: () => Navigator.pushNamed(context, AppRoutes.markedOutWarranty).then((_) => _loadDashboardData()),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.15), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.assignment_turned_in_rounded, size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Marked Out Under Warranty',
                        style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 12),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '$_markedOutUnderWarrantyCount bearings removed before expiry',
                        style: AppTypography.caption.copyWith(color: Colors.black54, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: AppColors.primary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWarrantySummaryCard({
    required String title,
    required String count,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.22), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 15),
            ),
            const SizedBox(height: 4),
            Text(
              count,
              style: AppTypography.headlineMd.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: AppTypography.labelMd.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                fontSize: 10.5,
                color: AppColors.primary,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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
