import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../../core/widgets/industrial_status_badge.dart';
import '../../../../core/widgets/industrial_text_field.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../widgets/admin_view_header.dart';

/// Pivot Bearings India — Admin Role Assignment & Onboarding Clearance View
///
/// Strictly restricted to System Administrators.
/// Provides live monitoring of newly registered accounts, permission allocations,
/// role promotion (USER vs ADMIN), and instantaneous clearance authorization.
class AdminRoleAssignmentView extends StatefulWidget {
  const AdminRoleAssignmentView({super.key});

  @override
  State<AdminRoleAssignmentView> createState() => _AdminRoleAssignmentViewState();
}

class _AdminRoleAssignmentViewState extends State<AdminRoleAssignmentView> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;
  String _activeFilter = 'ALL'; // ALL, PENDING, APPROVED, ADMINS
  int _currentPage = 0;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _loadUsers();

    // Auto-poll every 8 seconds so newly registered users pop up immediately
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && !_isLoading) {
        _loadUsers(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final res = await SupabaseService.fetchUsersForRoleAssignment(
        query: _searchCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          _users = res;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _errorMessage = 'Failed to load user accounts: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateUserClearance({
    required Map<String, dynamic> user,
    required bool approve,
    required String role,
  }) async {
    final userId = user['id']?.toString() ?? '';
    final userEmail = user['email']?.toString() ?? '';
    final userName = user['full_name']?.toString() ?? 'User';

    // Optimistic UI update
    setState(() {
      for (final u in _users) {
        if (u['id'] == userId || u['email'] == userEmail) {
          u['is_approved'] = approve;
          u['role'] = role;
        }
      }
    });

    try {
      final success = await SupabaseService.updateUserRoleAndClearance(
        userId: userId,
        role: role,
        isApproved: approve,
        email: userEmail,
      );

      if (!mounted) return;

      if (success) {
        AppSnackBar.showSuccess(
          context,
          approve
              ? 'CLEARANCE GRANTED: $userName ($userEmail) authorized as [$role].'
              : 'CLEARANCE REVOKED: $userName ($userEmail) placed in Pending Review.',
        );
      } else {
        AppSnackBar.showError(
          context,
          'Notice: Could not persist change. Please check permissions.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Error updating user: $e');
      }
    } finally {
      _loadUsers(silent: true);
    }
  }

  void _showRoleChangeDialog(Map<String, dynamic> user) {
    String selectedRole = (user['role']?.toString().toUpperCase()) == 'ADMIN' ? 'ADMIN' : 'USER';
    final userEmail = user['email']?.toString() ?? '';
    final userName = user['full_name']?.toString() ?? 'Operator';
    final isApproved = user['is_approved'] == true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
              side: const BorderSide(color: AppColors.primary, width: 2.0),
            ),
            title: Row(
              children: [
                const Icon(Icons.admin_panel_settings, color: AppColors.primary, size: 24),
                const SizedBox(width: 8),
                Text('ASSIGN ROLE & CLEARANCE', style: AppTypography.headlineSm.copyWith(color: AppColors.primary)),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TARGET ACCOUNT:', style: AppTypography.caption),
                  const SizedBox(height: 4),
                  Text('$userName · $userEmail', style: AppTypography.labelMd),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: AppColors.primary),
                  const SizedBox(height: 16),
                  const Text('SELECT ENTERPRISE ROLE:', style: AppTypography.caption),
                  const SizedBox(height: 8),

                  // Role options
                  _buildRoleSelectorCard(
                    title: 'Standard User / Certified Operator',
                    subtitle: 'Optical QR scan, bearing verification, and IN/OUT lifecycle tracking.',
                    roleCode: 'USER',
                    isSelected: selectedRole == 'USER',
                    onTap: () => setDialogState(() => selectedRole = 'USER'),
                  ),
                  const SizedBox(height: 8),
                  _buildRoleSelectorCard(
                    title: 'System Administrator',
                    subtitle: 'Full factory clearance: QR batch engine, Item Master, warranty horizons, audit logs.',
                    roleCode: 'ADMIN',
                    isSelected: selectedRole == 'ADMIN',
                    onTap: () => setDialogState(() => selectedRole = 'ADMIN'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL', style: TextStyle(color: AppColors.primary)),
              ),
              IndustrialButton(
                label: 'SAVE ROLE',
                width: 140,
                onPressed: () {
                  Navigator.pop(ctx);
                  _updateUserClearance(
                    user: user,
                    approve: isApproved,
                    role: selectedRole,
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRoleSelectorCard({
    required String title,
    required String subtitle,
    required String roleCode,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.background,
          border: Border.all(
            color: AppColors.primary,
            width: isSelected ? 2.0 : 1.0,
          ),
          borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? AppColors.background : AppColors.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodySm.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? AppColors.background : AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(
                      fontSize: 11,
                      color: isSelected ? AppColors.background : AppColors.primary,
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

  @override
  Widget build(BuildContext context) {
    // Strict RBAC Guard: If authenticated and not admin, restrict view
    final auth = AuthController.instance;
    if (auth.isAuthenticated && !auth.isAdmin) {
      return _buildAccessDenied();
    }

    // Filter calculations
    final totalCount = _users.length;
    final pendingCount = _users.where((u) => u['is_approved'] != true).length;
    final approvedCount = _users.where((u) => u['is_approved'] == true && u['role'] != 'ADMIN').length;
    final adminCount = _users.where((u) => u['role'] == 'ADMIN').length;

    final filteredUsers = _users.where((u) {
      final isApproved = u['is_approved'] == true;
      final role = (u['role'] ?? 'USER').toString().toUpperCase();
      if (_activeFilter == 'PENDING') return !isApproved;
      if (_activeFilter == 'APPROVED') return isApproved && role != 'ADMIN';
      if (_activeFilter == 'ADMINS') return role == 'ADMIN';
      return true;
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 650;
        final contentPadding = isMobile
            ? const EdgeInsets.all(AppDimensions.gutterMobile)
            : const EdgeInsets.all(AppDimensions.gutterDesktop);

        return SingleChildScrollView(
          padding: contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Header
          AdminViewHeader(
            title: 'Role Assignment',
            actions: [
              IndustrialButton(
                label: 'REFRESH',
                width: 120,
                icon: Icons.refresh,
                onPressed: () => _loadUsers(),
              ),
            ],
          ),

          // Real-time Metrics Row
          _buildMetricsOverview(
            total: totalCount,
            pending: pendingCount,
            approved: approvedCount,
            admins: adminCount,
          ),
          const SizedBox(height: AppDimensions.spaceLg),

          // Search & Filter Toolbar
          IndustrialCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: IndustrialTextField(
                        controller: _searchCtrl,
                        hintText: 'Search registered user by Email, Name, or Facility',
                        prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                        onSubmitted: (_) => _loadUsers(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IndustrialButton(
                      label: 'SEARCH',
                      width: 110,
                      onPressed: () => _loadUsers(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFilterChip('ALL', 'All Registered ($totalCount)'),
                    _buildFilterChip('PENDING', 'Pending Clearance ($pendingCount)', isWarning: pendingCount > 0),
                    _buildFilterChip('APPROVED', 'Standard Operators ($approvedCount)'),
                    _buildFilterChip('ADMINS', 'Administrators ($adminCount)'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spaceLg),

          // User List / Table
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48.0),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
                    SizedBox(height: 12),
                    Text('SYNCHRONIZING REGISTERED OPERATOR DIRECTORY...', style: AppTypography.caption),
                  ],
                ),
              ),
            )
          else if (_errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: AppColors.primary),
                    const SizedBox(height: 12),
                    Text(_errorMessage!, style: AppTypography.bodySm),
                    const SizedBox(height: 16),
                    IndustrialButton(label: 'RETRY', width: 120, onPressed: () => _loadUsers()),
                  ],
                ),
              ),
            )
          else if (filteredUsers.isEmpty)
            Container(
              padding: const EdgeInsets.all(48),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 1.5),
                borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
              ),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 48, color: AppColors.primary),
                    const SizedBox(height: 12),
                    Text(
                      _activeFilter == 'PENDING'
                          ? 'NO OPERATORS CURRENTLY PENDING APPROVAL'
                          : 'NO MATCHING REGISTERED ACCOUNTS',
                      style: AppTypography.headlineSm,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'All accounts have been processed or matched by your active search criteria.',
                      style: AppTypography.caption,
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isSearching = _searchCtrl.text.trim().isNotEmpty;
                final totalCount = filteredUsers.length;
                final totalPages = (totalCount / _pageSize).ceil().clamp(1, 9999);
                final currentPage = _currentPage.clamp(0, totalPages - 1);
                final startIndex = isSearching ? 0 : currentPage * _pageSize;
                final endIndex = isSearching
                    ? totalCount
                    : (startIndex + _pageSize < totalCount ? startIndex + _pageSize : totalCount);
                final displayed = (totalCount == 0 || isSearching)
                    ? filteredUsers
                    : filteredUsers.sublist(startIndex, endIndex);

                final isWide = constraints.maxWidth >= 900;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    isWide
                        ? _buildDesktopTable(displayed)
                        : _buildMobileCardList(displayed),
                    if (!isSearching && totalCount > _pageSize) ...[
                      const SizedBox(height: 14),
                      _buildPaginationBar(
                        currentPage: currentPage,
                        totalCount: totalCount,
                        pageSize: _pageSize,
                        isLoading: _isLoading,
                        itemName: 'operators',
                        onPageChanged: (p) => setState(() => _currentPage = p),
                      ),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
      },
    );
  }

  /// Clean, minimal & strictly mobile-responsive pagination bar
  Widget _buildPaginationBar({
    required int currentPage,
    required int totalCount,
    required int pageSize,
    required bool isLoading,
    required String itemName,
    required ValueChanged<int> onPageChanged,
  }) {
    if (totalCount <= pageSize) {
      if (totalCount > 0) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Center(
            child: Text(
              'Showing all $totalCount $itemName',
              style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final totalPages = (totalCount / pageSize).ceil().clamp(1, 9999);
    final startIndex = currentPage * pageSize + 1;
    final endIndex = ((currentPage + 1) * pageSize).clamp(0, totalCount);

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 1.2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 360;

          final infoText = Text(
            'Showing $startIndex–$endIndex of $totalCount $itemName',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          );

          final controls = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Previous Page',
                icon: const Icon(Icons.chevron_left, color: AppColors.primary),
                onPressed: (currentPage > 0 && !isLoading)
                    ? () => onPageChanged(currentPage - 1)
                    : null,
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isLoading ? '...' : 'Page ${currentPage + 1} of $totalPages',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Next Page',
                icon: const Icon(Icons.chevron_right, color: AppColors.primary),
                onPressed: (currentPage < totalPages - 1 && !isLoading)
                    ? () => onPageChanged(currentPage + 1)
                    : null,
              ),
            ],
          );

          if (isNarrow) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                infoText,
                const SizedBox(height: 6),
                controls,
              ],
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              infoText,
              controls,
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricsOverview({
    required int total,
    required int pending,
    required int approved,
    required int admins,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 760;

        final items = [
          _buildStatCard('TOTAL REGISTERED', total.toString(), Icons.people_alt),
          _buildStatCard(
            'PENDING CLEARANCE',
            pending.toString(),
            Icons.hourglass_top,
            isHighlighted: pending > 0,
          ),
          _buildStatCard('CERTIFIED OPERATORS', approved.toString(), Icons.verified),
          _buildStatCard('ADMINISTRATORS', admins.toString(), Icons.admin_panel_settings),
        ];

        if (isDesktop) {
          return Row(
            children: items.map((w) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: w))).toList(),
          );
        } else {
          return Column(
            children: items.map((w) => Padding(padding: const EdgeInsets.only(bottom: 8), child: w)).toList(),
          );
        }
      },
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, {bool isHighlighted = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(
          color: AppColors.primary,
          width: isHighlighted ? 2.5 : 1.0,
        ),
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isHighlighted ? AppColors.primary : AppColors.background,
              border: Border.all(color: AppColors.primary, width: 1.0),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
            ),
            child: Icon(
              icon,
              color: isHighlighted ? AppColors.background : AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.caption.copyWith(fontSize: 10, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTypography.headlineLg.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, {bool isWarning = false}) {
    final isSelected = _activeFilter == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppColors.background : AppColors.primary,
        ),
      ),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.background,
      side: const BorderSide(color: AppColors.primary, width: 1.0),
      onSelected: (_) => setState(() => _activeFilter = key),
    );
  }

  Widget _buildDesktopTable(List<Map<String, dynamic>> users) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.primary, width: 1.5),
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.5), // Operator & Email
          1: FlexColumnWidth(1.8), // Facility / Company
          2: FlexColumnWidth(1.1), // Registration Date
          3: FlexColumnWidth(2.2), // Clearance Status
          4: FlexColumnWidth(1.4), // Assigned Role
          5: FlexColumnWidth(2.4), // Direct Actions
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          // Table Header
          TableRow(
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(bottom: BorderSide(color: AppColors.primary, width: 1.5)),
            ),
            children: const [
              _HeaderCell('OPERATOR / IDENTITY'),
              _HeaderCell('FACILITY / ENTERPRISE'),
              _HeaderCell('REGISTERED'),
              _HeaderCell('CLEARANCE STATUS'),
              _HeaderCell('ROLE ASSIGNED'),
              _HeaderCell('ACTIONS'),
            ],
          ),
          ...users.asMap().entries.map((e) => _buildTableRow(e.value, isLast: e.key == users.length - 1)),
        ],
      ),
    );
  }

  TableRow _buildTableRow(Map<String, dynamic> user, {bool isLast = false}) {
    final email = user['email']?.toString() ?? '—';
    final name = user['full_name']?.toString() ?? 'Operator';
    final company = user['company_name']?.toString() ?? '—';
    final facility = user['facility_code']?.toString() ?? '';
    final role = (user['role']?.toString().toUpperCase()) == 'ADMIN' ? 'ADMIN' : 'USER';
    final isApproved = user['is_approved'] == true;
    final createdAt = user['created_at']?.toString() ?? '';
    final formattedDate = _formatDate(createdAt);

    return TableRow(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.primary, width: 1.0)),
      ),
      children: [
        // Operator Name & Email
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: isApproved ? AppColors.primary : AppColors.background,
                child: Text(
                  name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'U',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isApproved ? AppColors.background : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(email, style: AppTypography.caption.copyWith(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Company & Facility
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(company.isNotEmpty ? company : 'Standard Field Account', style: AppTypography.bodySm),
              if (facility.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('CODE: $facility', style: AppTypography.caption.copyWith(fontSize: 11)),
              ],
            ],
          ),
        ),

        // Registration Date
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text(formattedDate, style: AppTypography.caption),
        ),

        // Clearance Status Badge
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: IndustrialStatusBadge(
                statusText: isApproved ? 'CLEARANCE ACTIVE' : 'PENDING REVIEW',
                icon: isApproved ? Icons.verified : Icons.hourglass_top,
              ),
            ),
          ),
        ),

        // Assigned Role Badge & Selector
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => _showRoleChangeDialog(user),
                borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: role == 'ADMIN' ? AppColors.primary : AppColors.background,
                    border: Border.all(color: AppColors.primary, width: 1.0),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        role == 'ADMIN' ? Icons.security : Icons.person,
                        size: 14,
                        color: role == 'ADMIN' ? AppColors.background : AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        role,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: role == 'ADMIN' ? AppColors.background : AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down,
                        size: 14,
                        color: role == 'ADMIN' ? AppColors.background : AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // Direct Actions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              if (!isApproved) ...[
                IndustrialButton(
                  label: 'APPROVE & CLEAR',
                  icon: Icons.check_circle_outline,
                  width: 140,
                  height: 36,
                  onPressed: () => _updateUserClearance(user: user, approve: true, role: role),
                ),
              ] else ...[
                IndustrialButton.secondary(
                  label: 'REVOKE',
                  icon: Icons.block,
                  width: 100,
                  height: 36,
                  onPressed: () => _updateUserClearance(user: user, approve: false, role: role),
                ),
              ],
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.manage_accounts, color: AppColors.primary, size: 20),
                tooltip: 'Modify Role',
                onPressed: () => _showRoleChangeDialog(user),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileCardList(List<Map<String, dynamic>> users) {
    return Column(
      children: users.map((u) {
        final email = u['email']?.toString() ?? '—';
        final name = u['full_name']?.toString() ?? 'Operator';
        final company = u['company_name']?.toString() ?? '—';
        final role = (u['role']?.toString().toUpperCase()) == 'ADMIN' ? 'ADMIN' : 'USER';
        final isApproved = u['is_approved'] == true;
        final formattedDate = _formatDate(u['created_at']?.toString() ?? '');

        return IndustrialCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: AppTypography.headlineSm),
                        const SizedBox(height: 2),
                        Text(email, style: AppTypography.caption),
                      ],
                    ),
                  ),
                  IndustrialStatusBadge(
                    statusText: isApproved ? 'CLEARANCE ACTIVE' : 'PENDING REVIEW',
                    icon: isApproved ? Icons.verified : Icons.hourglass_top,
                  ),
                ],
              ),
              const Divider(height: 20, color: AppColors.primary),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Facility / Enterprise:', style: AppTypography.caption),
                  Text(company.isNotEmpty ? company : 'Standard Field Account', style: AppTypography.bodySm),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Registration Date:', style: AppTypography.caption),
                  Text(formattedDate, style: AppTypography.caption),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Assigned Role:', style: AppTypography.caption),
                  InkWell(
                    onTap: () => _showRoleChangeDialog(u),
                    child: Row(
                      children: [
                        Text(
                          role == 'ADMIN' ? 'ADMINISTRATOR' : 'STANDARD OPERATOR',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: AppColors.primary, size: 16),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: isApproved
                        ? IndustrialButton.secondary(
                            label: 'REVOKE CLEARANCE',
                            icon: Icons.block,
                            onPressed: () => _updateUserClearance(user: u, approve: false, role: role),
                          )
                        : IndustrialButton(
                            label: 'APPROVE & CLEAR ACCESS',
                            icon: Icons.check_circle_outline,
                            onPressed: () => _updateUserClearance(user: u, approve: true, role: role),
                          ),
                  ),
                  const SizedBox(width: 8),
                  IndustrialButton.secondary(
                    label: 'ROLE',
                    icon: Icons.edit,
                    width: 90,
                    onPressed: () => _showRoleChangeDialog(u),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAccessDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: IndustrialCard(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.security, size: 56, color: AppColors.primary),
                const SizedBox(height: 16),
                const Text('ACCESS RESTRICTED', style: AppTypography.headlineLg),
                const SizedBox(height: 8),
                const Text(
                  'The Role Assignment & Operator Clearance Workstation requires elevated System Administrator privileges.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySm,
                ),
                const SizedBox(height: 24),
                IndustrialButton(
                  label: 'RETURN TO WORKSTATION',
                  icon: Icons.arrow_back,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(String isoString) {
    if (isoString.isEmpty) return '—';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final year = dt.year;
      final month = dt.month.toString().padLeft(2, '0');
      final day = dt.day.toString().padLeft(2, '0');
      final hour = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$day/$month/$year $hour:$min';
    } catch (_) {
      return isoString;
    }
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
