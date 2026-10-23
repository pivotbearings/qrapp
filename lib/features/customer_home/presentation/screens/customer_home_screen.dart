import 'dart:async';
import 'dart:convert';
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
import '../../../rewards/domain/models/reward_models.dart';
import '../../../rewards/data/services/reward_service.dart';

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
  RewardProfile _rewardProfile = RewardProfile.defaultProfile();
  AdBannerConfig _adConfig = AdBannerConfig.defaultConfig();
  StreamSubscription<AdBannerConfig>? _adBannerSub;
  RealtimeChannel? _supabaseAdChannel;

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
                final minH = (constraints.maxHeight.isFinite && constraints.maxHeight > AppDimensions.gutterMobile * 2)
                    ? (constraints.maxHeight - (AppDimensions.gutterMobile * 2))
                    : 0.0;
                final bannerHeight = (constraints.maxWidth * 0.46).clamp(150.0, 240.0);

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppDimensions.gutterMobile),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: minH,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // --- TOP SECTION ---
                        Column(
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

                            // ADVERTISEMENT BANNER (Configured from Admin Panel, WebP format)
                            if (_adConfig.isActive) ...[
                              _buildAdvertisementBanner(bannerHeight),
                              const SizedBox(height: AppDimensions.spaceMd),
                            ],
                          ],
                        ),

                        // --- BOTTOM SECTION (Anchored at the bottom above navigation bar) ---
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: AppDimensions.spaceSm),
                            _buildRewardWalletCard(),
                            const SizedBox(height: AppDimensions.spaceSm),
                          ],
                        ),
                      ],
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

  /// Advertisement Banner dynamically configurable from Admin Panel
  Widget _buildAdvertisementBanner(double height) {
    return Container(
      width: double.infinity,
      height: height,
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
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openAdBannerLink,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildAdBannerImage(_adConfig),

              // Official Featured Badge
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24, width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new, color: Colors.white, size: 10),
                      SizedBox(width: 4),
                      Text(
                        'FEATURED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdBannerImage(AdBannerConfig config) {
    final fit = config.fitMode == 'cover' ? BoxFit.cover : BoxFit.contain;

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
