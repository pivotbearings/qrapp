import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/localization/locale_controller.dart';
import '../../../../core/router/app_routes.dart';
import '../../../qr_generation/presentation/screens/qr_bulk_generation_screen.dart';
import '../../../qr_inventory/presentation/screens/qr_inventory_screen.dart';
import '../../../item_master/presentation/views/admin_item_master_view.dart';
import '../views/admin_customers_view.dart';
import '../views/admin_images_view.dart';
import '../views/admin_overview_view.dart';
import '../views/admin_role_assignment_view.dart';
import '../views/admin_settings_view.dart';
import '../views/admin_warranty_analytics_view.dart';

/// Enterprise Admin Workstation for Pivot Bearings India
/// Clean, minimalistic, strictly responsive on both Desktop/Web and Mobile/App.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedTabIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<_NavTabItem> _navigationTabs = const [
    _NavTabItem(title: 'Dashboard', icon: Icons.grid_view, subtitle: 'Real-time Telemetry'),
    _NavTabItem(title: 'Role Assignment', icon: Icons.admin_panel_settings, subtitle: 'User Clearance & Permissions'),
    _NavTabItem(title: 'QR Generation', icon: Icons.qr_code_2, subtitle: 'Batch Creation Engine'),
    _NavTabItem(title: 'Item Master', icon: Icons.precision_manufacturing, subtitle: 'Catalog & Specifications'),
    _NavTabItem(title: 'QR Registry', icon: Icons.inventory_2, subtitle: 'Search, Block & Exports'),
    _NavTabItem(title: 'Warranty Analytics', icon: Icons.analytics_outlined, subtitle: 'Customer & Product Insights'),
    _NavTabItem(title: 'Users / Customers', icon: Icons.people_alt_rounded, subtitle: 'Role-Based Access & Module Permissions'),
    _NavTabItem(title: 'Verification Proofs', icon: Icons.photo_library, subtitle: 'Signed Private Images'),
    _NavTabItem(title: 'Company Settings', icon: Icons.settings, subtitle: 'Identity & Configuration'),
  ];

  @override
  void initState() {
    super.initState();
    if (!AuthController.instance.isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.accessDenied);
        }
      });
      return;
    }
    _restoreActiveTab();
  }

  Future<void> _restoreActiveTab() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTab = prefs.getInt('pbi_admin_active_tab');
      if (savedTab != null && savedTab >= 0 && savedTab < _navigationTabs.length && mounted) {
        setState(() => _selectedTabIndex = savedTab);
      }
    } catch (_) {}
  }

  void _onTabSelected(int index) {
    setState(() => _selectedTabIndex = index);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setInt('pbi_admin_active_tab', index);
    });
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  Future<void> _handleSignOut() async {
    await AuthController.instance.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.authLogin, (route) => false);
    }
  }

  Widget _buildActiveView() {
    switch (_selectedTabIndex) {
      case 0:
        return AdminOverviewView(
          onNavigateToGeneration: () => setState(() => _selectedTabIndex = 2),
          onNavigateToWarranty: () {},
          onNavigateToRegistry: () => setState(() => _selectedTabIndex = 4),
          onNavigateToSecurity: () {},
          onNavigateToRoles: () => setState(() => _selectedTabIndex = 1),
          onNavigateToCustomers: () => setState(() => _selectedTabIndex = 6),
        );
      case 1:
        return const AdminRoleAssignmentView();
      case 2:
        return QrBulkGenerationScreen(
          isEmbedded: true,
          onNavigateToItemMaster: () => setState(() => _selectedTabIndex = 3),
        );
      case 3:
        return const AdminItemMasterView();
      case 4:
        return const QrInventoryScreen(isEmbedded: true);
      case 5:
        return const AdminWarrantyAnalyticsView();
      case 6:
        return const AdminCustomersView();
      case 7:
        return const AdminImagesView();
      case 8:
        return const AdminSettingsView();
      default:
        return AdminOverviewView(
          onNavigateToGeneration: () => setState(() => _selectedTabIndex = 2),
          onNavigateToWarranty: () {},
          onNavigateToRegistry: () => setState(() => _selectedTabIndex = 4),
          onNavigateToSecurity: () {},
          onNavigateToRoles: () => setState(() => _selectedTabIndex = 1),
          onNavigateToCustomers: () => setState(() => _selectedTabIndex = 6),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1000;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: isDesktop ? null : _buildDrawer(context),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxHeight < 80 || constraints.maxWidth < 80) {
              return const SizedBox.shrink();
            }

            return isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left persistent sidebar on Desktop
                      SizedBox(
                        width: 250,
                        child: _buildSidebar(context),
                      ),

                      // Main workspace area
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTopAppBar(context, isDesktop: true),
                            Expanded(
                              child: _buildActiveView(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTopAppBar(context, isDesktop: false),
                      Expanded(
                        child: _buildActiveView(),
                      ),
                    ],
                  );
          },
        ),
      ),
    );
  }

  /// Pinned Top App Bar
  Widget _buildTopAppBar(BuildContext context, {required bool isDesktop}) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 680;
    final auth = AuthController.instance;

    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? AppDimensions.gutterDesktop : AppDimensions.spaceMd,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.primary, width: 1.5)),
      ),
      child: Row(
        children: [
          // Drawer Hamburger button on mobile / tablet
          if (!isDesktop) ...[
            IconButton(
              icon: const Icon(Icons.menu, color: AppColors.primary, size: 22),
              tooltip: 'Navigation Menu',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            ),
            const SizedBox(width: 6),
          ],

          // Active Module Title
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _navigationTabs[_selectedTabIndex].title.toUpperCase(),
                    style: AppTypography.labelMd.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Multi-Language Selector
          ValueListenableBuilder<Locale>(
            valueListenable: LocaleController.currentLocale,
            builder: (context, currentLocale, _) {
              return PopupMenuButton<String>(
                tooltip: 'Interface Language',
                color: AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: AppColors.primary, width: 1.0),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 1.0),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.language, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        currentLocale.languageCode.toUpperCase(),
                        style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                onSelected: (code) {
                  LocaleController.setLocale(Locale(code));
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'en', child: Text('English (Global)', style: AppTypography.caption)),
                  const PopupMenuItem(value: 'hi', child: Text('हिन्दी (Hindi)', style: AppTypography.caption)),
                  const PopupMenuItem(value: 'gu', child: Text('ગુજરાતી (Gujarati)', style: AppTypography.caption)),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
          const SizedBox(width: 8),

          // Role Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.verified_user, size: 13, color: AppColors.background),
                if (!isCompact) ...[
                  const SizedBox(width: 4),
                  const Text(
                    'ADMIN',
                    style: TextStyle(
                      color: AppColors.background,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Sign Out Icon Button
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.logout, size: 18, color: AppColors.primary),
            tooltip: 'Sign Out (${auth.userEmail ?? 'Admin'})',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _handleSignOut,
          ),
        ],
      ),
    );
  }

  /// Persistent Left Sidebar (Desktop)
  Widget _buildSidebar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(right: BorderSide(color: AppColors.primary, width: 1.5)),
      ),
      child: Column(
        children: [
          // Brand Header
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.primary, width: 1.5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                    border: Border.all(color: AppColors.primary, width: 1.2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Image.asset(
                    'assets/webappicon.png',
                    width: 28,
                    height: 28,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PIVOT BEARINGS', style: AppTypography.labelMd, overflow: TextOverflow.ellipsis),
                      Text('ENTERPRISE ADMIN', style: AppTypography.caption, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Navigation Items List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              itemCount: _navigationTabs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final tab = _navigationTabs[index];
                final isSelected = _selectedTabIndex == index;

                return InkWell(
                  onTap: () => _onTabSelected(index),
                  borderRadius: BorderRadius.circular(50),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          tab.icon,
                          color: isSelected ? AppColors.background : AppColors.primary,
                          size: 16,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tab.title,
                            style: AppTypography.labelMd.copyWith(
                              color: isSelected ? AppColors.background : AppColors.primary,
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom Actions in Sidebar

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
            child: InkWell(
              onTap: _handleSignOut,
              borderRadius: BorderRadius.circular(50),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout, color: AppColors.background, size: 15),
                    SizedBox(width: 6),
                    Text(
                      'SIGN OUT',
                      style: TextStyle(
                        color: AppColors.background,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Slide-Out Drawer (Mobile & Tablet)
  Widget _buildDrawer(BuildContext context) {
    final auth = AuthController.instance;

    return Drawer(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.primary, width: 1.5)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                      border: Border.all(color: AppColors.primary, width: 1.2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/webappicon.png',
                      width: 28,
                      height: 28,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PIVOT BEARINGS INDIA', style: AppTypography.labelMd),
                        Text(
                          '${auth.userName ?? 'Admin'} (${auth.userEmail ?? '—'}) • [${auth.role.code}]',
                          style: AppTypography.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                itemCount: _navigationTabs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 2),
                itemBuilder: (context, index) {
                  final tab = _navigationTabs[index];
                  final isSelected = _selectedTabIndex == index;

                  return InkWell(
                    onTap: () => _onTabSelected(index),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            tab.icon,
                            color: isSelected ? AppColors.background : AppColors.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tab.title,
                              style: AppTypography.labelMd.copyWith(
                                color: isSelected ? AppColors.background : AppColors.primary,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      _handleSignOut();
                    },
                    borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout, color: AppColors.background, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'SIGN OUT',
                            style: TextStyle(
                              color: AppColors.background,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTabItem {
  final String title;
  final IconData icon;
  final String subtitle;

  const _NavTabItem({
    required this.title,
    required this.icon,
    required this.subtitle,
  });
}
