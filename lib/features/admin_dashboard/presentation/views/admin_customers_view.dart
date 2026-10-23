import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../../core/widgets/industrial_text_field.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../widgets/admin_view_header.dart';

/// Pivot Bearings India - Users & Customers Module Permissions View
///
/// Role-Based Access Control (RBAC) Management:
/// - Lists all registered users/customers
/// - Default permission: Access ONLY to Bearing Authentication page
/// - Clicking a user's email opens an expandable section with 2 independent toggles:
///   1. Warranty Module (OFF by default for new users)
///   2. Track Your Bearing Module (OFF by default for new users)
/// - Bearing Authentication remains permanently accessible to all registered users
/// - Real-time sync across multiple admin displays and web sessions
/// - Fully mobile responsive for compact and smaller Android displays
class AdminCustomersView extends StatefulWidget {
  const AdminCustomersView({super.key});

  @override
  State<AdminCustomersView> createState() => _AdminCustomersViewState();
}

class _AdminCustomersViewState extends State<AdminCustomersView> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _customers = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;
  RealtimeChannel? _profilesRealtimeChannel;

  int _currentPage = 0;
  static const int _pageSize = 10;

  // Track which user emails are currently expanded in the UI
  final Set<String> _expandedEmails = {};

  // Track async saving state per user ID to prevent race conditions
  final Set<String> _savingUserIds = {};

  // Controllers for adding new authorised numbers per user
  final Map<String, TextEditingController> _newNumberControllers = {};

  TextEditingController _getNumberController(String userId) {
    return _newNumberControllers.putIfAbsent(userId, () => TextEditingController());
  }

  static const Color _greenBackground = Color(0xFFE8F5E9);
  static const Color _greenBorder = Color(0xFF81C784);
  static const Color _greenTextDark = Color(0xFF1B5E20);

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _setupRealtimeSync();
  }

  void _setupRealtimeSync() {
    try {
      if (SupabaseService.isInitialized) {
        _profilesRealtimeChannel = SupabaseService.client
            .channel('public_profiles_admin_customers_${DateTime.now().millisecondsSinceEpoch}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'profiles',
              callback: (payload) {
                if (mounted) {
                  _loadCustomers(silent: true);
                }
              },
            )
            .subscribe();
      }
    } catch (e) {
      debugPrint('Realtime channel subscribe error: $e');
    }

    // Auto-sync every 4 seconds so Screen 2 immediately updates when Screen 1 toggles access or numbers
    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !_isLoading) {
        _loadCustomers(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    if (_profilesRealtimeChannel != null) {
      try {
        SupabaseService.client.removeChannel(_profilesRealtimeChannel!);
      } catch (_) {}
    }
    _searchCtrl.dispose();
    for (final c in _newNumberControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCustomers({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final res = await SupabaseService.fetchCustomerProfiles(
        query: _searchCtrl.text.trim(),
      );
      if (mounted) {
        setState(() {
          if (silent && _customers.isNotEmpty) {
            // Keep pending optimistic values for any user being actively modified
            final Map<String, Map<String, dynamic>> resMap = {
              for (final c in res) (c['id']?.toString() ?? ''): c
            };
            for (var i = 0; i < _customers.length; i++) {
              final uid = _customers[i]['id']?.toString() ?? '';
              if (_savingUserIds.contains(uid)) {
                continue;
              }
              if (resMap.containsKey(uid)) {
                _customers[i] = resMap[uid]!;
              }
            }
            final existingIds = _customers.map((c) => c['id']?.toString() ?? '').toSet();
            for (final c in res) {
              final uid = c['id']?.toString() ?? '';
              if (!existingIds.contains(uid)) {
                _customers.add(c);
              }
            }
          } else {
            _customers = res;
          }
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

  void _toggleEmailExpanded(String email) {
    setState(() {
      if (_expandedEmails.contains(email)) {
        _expandedEmails.remove(email);
      } else {
        _expandedEmails.add(email);
      }
    });
  }

  Future<void> _updateModulePermission({
    required Map<String, dynamic> user,
    required bool hasWarranty,
    required bool hasTrackBearing,
  }) async {
    final userId = user['id']?.toString() ?? '';
    final userEmail = user['email']?.toString() ?? '';

    setState(() {
      _savingUserIds.add(userId);
      user['has_warranty_access'] = hasWarranty;
      user['has_track_bearing_access'] = hasTrackBearing;
    });

    try {
      final ok = await SupabaseService.updateUserModulePermissions(
        userId: userId,
        hasWarranty: hasWarranty,
        hasTrackBearing: hasTrackBearing,
        email: userEmail,
      );

      if (mounted) {
        setState(() => _savingUserIds.remove(userId));
        if (ok) {
          AppSnackBar.showSuccess(
            context,
            'Permissions updated for $userEmail',
          );
        } else {
          AppSnackBar.showError(
            context,
            'Failed to sync permissions online. Saved to local cache.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingUserIds.remove(userId));
        AppSnackBar.showError(context, 'Error updating permissions: $e');
      }
    }
  }

  Future<void> _updateRewardEligibility({
    required Map<String, dynamic> user,
    required bool isEligible,
  }) async {
    final userId = user['id']?.toString() ?? '';
    final userEmail = user['email']?.toString() ?? '';

    setState(() {
      _savingUserIds.add(userId);
      user['is_reward_eligible'] = isEligible;
    });

    try {
      final ok = await SupabaseService.updateUserRewardEligibility(
        userId: userId,
        isEligible: isEligible,
        email: userEmail,
      );

      if (mounted) {
        setState(() => _savingUserIds.remove(userId));
        if (ok) {
          AppSnackBar.showSuccess(
            context,
            isEligible
                ? 'Reward points enabled for $userEmail'
                : 'Reward points blocked for $userEmail',
          );
        } else {
          AppSnackBar.showError(
            context,
            'Failed to sync online. Updated locally.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingUserIds.remove(userId));
        AppSnackBar.showError(context, 'Error updating reward status: $e');
      }
    }
  }

  Future<void> _updateAuthorisedNumbers({
    required Map<String, dynamic> user,
    required List<String> numbers,
  }) async {
    final userId = user['id']?.toString() ?? '';
    final userEmail = user['email']?.toString() ?? '';

    setState(() {
      _savingUserIds.add(userId);
      user['authorised_numbers'] = numbers;
    });

    try {
      final ok = await SupabaseService.updateUserAuthorisedNumbers(
        userId: userId,
        numbers: numbers,
        email: userEmail,
      );

      if (mounted) {
        setState(() => _savingUserIds.remove(userId));
        if (ok) {
          AppSnackBar.showSuccess(
            context,
            'Authorised numbers saved for $userEmail',
          );
        } else {
          AppSnackBar.showError(
            context,
            'Could not sync online. Saved locally.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingUserIds.remove(userId));
        AppSnackBar.showError(context, 'Failed to update numbers: $e');
      }
    }
  }

  void _addNumberForUser(Map<String, dynamic> user) {
    final userId = user['id']?.toString() ?? '';
    final controller = _getNumberController(userId);
    final rawInput = controller.text.trim();

    if (rawInput.isEmpty) return;

    final digits = rawInput.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 7) {
      AppSnackBar.showError(context, 'Please enter a valid mobile number with at least 7 digits.');
      return;
    }

    final currentNumbers = List<String>.from(
      (user['authorised_numbers'] as List<dynamic>?)?.map((e) => e.toString()) ?? [],
    );

    if (currentNumbers.isNotEmpty) {
      AppSnackBar.showError(context, 'Only one authorised number is allowed per user. Remove the existing number first to change.');
      return;
    }

    String formatted = rawInput;
    if (!formatted.startsWith('+') && digits.length == 10) {
      formatted = '+91 $digits';
    }

    controller.clear();
    _updateAuthorisedNumbers(user: user, numbers: [formatted]);
  }

  Future<void> _approveUser(Map<String, dynamic> user) async {
    final userId = user['id']?.toString() ?? '';
    final email = user['email']?.toString() ?? '';

    final ok = await SupabaseService.updateUserRoleAndClearance(
      userId: userId,
      role: 'USER',
      isApproved: true,
      email: email,
    );

    if (mounted) {
      if (ok) {
        AppSnackBar.showSuccess(context, 'User $email approved successfully!');
        _loadCustomers();
      } else {
        AppSnackBar.showError(context, 'Failed to approve user.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              AdminViewHeader(
                title: 'Users & Customers',
                actions: [
                  IndustrialButton(
                    label: 'REFRESH',
                    width: 120,
                    icon: Icons.refresh,
                    onPressed: _loadCustomers,
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spaceSm),

              // Search Bar
              IndustrialCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: IndustrialTextField(
                        controller: _searchCtrl,
                        hintText: 'Search by Email, Name, Company, or Facility Code',
                        prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                        onSubmitted: (_) => _loadCustomers(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IndustrialButton(
                      label: 'FILTER',
                      width: 90,
                      onPressed: _loadCustomers,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.spaceMd),

              // Content Area
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48.0),
                    child: Column(
                      children: [
                        CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
                        SizedBox(height: 12),
                        Text('LOADING USER & CUSTOMER DIRECTORY...', style: AppTypography.caption),
                      ],
                    ),
                  ),
                )
              else if (_errorMessage != null)
                Center(
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.primary),
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: AppTypography.bodySm),
                      const SizedBox(height: 16),
                      IndustrialButton(label: 'RETRY', width: 120, onPressed: _loadCustomers),
                    ],
                  ),
                )
              else if (_customers.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.primary, width: 1.5),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                  ),
                  child: const Center(
                    child: Column(
                      children: [
                        Icon(Icons.person_off, size: 48, color: AppColors.primary),
                        SizedBox(height: 12),
                        Text('NO USERS OR CUSTOMERS FOUND', style: AppTypography.headlineSm),
                        SizedBox(height: 4),
                        Text(
                          'New signups will automatically appear here with default permissions.',
                          style: AppTypography.caption,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Builder(
                  builder: (context) {
                    final isSearching = _searchCtrl.text.trim().isNotEmpty;
                    final totalCount = _customers.length;
                    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 9999);
                    final currentPage = _currentPage.clamp(0, totalPages - 1);
                    final startIndex = isSearching ? 0 : currentPage * _pageSize;
                    final endIndex = isSearching
                        ? totalCount
                        : (startIndex + _pageSize < totalCount ? startIndex + _pageSize : totalCount);
                    final displayedUsers = (totalCount == 0 || isSearching)
                        ? _customers
                        : _customers.sublist(startIndex, endIndex);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: displayedUsers.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final user = displayedUsers[index];
                            return _buildUserCard(user);
                          },
                        ),
                        if (!isSearching && totalCount > _pageSize) ...[
                          const SizedBox(height: 12),
                          _buildPaginationBar(
                            currentPage: currentPage,
                            totalCount: totalCount,
                            pageSize: _pageSize,
                            isLoading: _isLoading,
                            itemName: 'users',
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

  // ===========================================================================
  // Individual User Card with Clickable Email and Expandable Toggles
  // ===========================================================================
  Widget _buildUserCard(Map<String, dynamic> user) {
    final userId = user['id']?.toString() ?? '';
    final email = user['email']?.toString() ?? '—';
    final rawName = user['full_name']?.toString() ?? '';
    final name = rawName.isNotEmpty ? rawName : email.split('@').first;
    final company = user['company_name']?.toString().isNotEmpty == true
        ? user['company_name'].toString()
        : 'Industrial Account';
    final facility = user['facility_code']?.toString().isNotEmpty == true
        ? user['facility_code'].toString()
        : 'FAC-REG';
    final role = user['role']?.toString().toUpperCase() ?? 'USER';
    final isApproved = user['is_approved'] == true;
    final isAdmin = role == 'ADMIN';

    // Module Permissions & Reward Eligibility
    final hasWarranty = isAdmin || user['has_warranty_access'] == true;
    final hasTrack = isAdmin || user['has_track_bearing_access'] == true;
    final isRewardEligible = user['is_reward_eligible'] != false;

    final isExpanded = _expandedEmails.contains(email);
    final isSaving = _savingUserIds.contains(userId);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        border: Border.all(
          color: isExpanded ? AppColors.primary : Colors.black12,
          width: isExpanded ? 1.8 : 1.0,
        ),
        boxShadow: isExpanded
            ? [
                BoxShadow(
                  color: AppColors.primary.withAlpha(20),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Main Header Row: User Info & Clickable Email
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Company & Status Badges
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            company,
                            style: AppTypography.headlineSm.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$name • $facility',
                            style: AppTypography.bodySm.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      alignment: WrapAlignment.end,
                      children: [
                        // Role Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isAdmin ? AppColors.primary : AppColors.background,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.primary, width: 1.0),
                          ),
                          child: Text(
                            role,
                            style: TextStyle(
                              color: isAdmin ? AppColors.background : AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        // Approval Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isApproved ? const Color(0xFF22C55E) : const Color(0xFFEAB308),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isApproved ? 'APPROVED' : 'PENDING',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        // Rewards Blocked Pill
                        if (!isRewardEligible)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.black26, width: 1.0),
                            ),
                            child: const Text(
                              'REWARDS: BLOCKED',
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Interactive Clickable Email Button (No Underline)
                InkWell(
                  onTap: () => _toggleEmailExpanded(email),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isExpanded ? AppColors.primary.withAlpha(15) : AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isExpanded ? AppColors.primary : AppColors.primary.withAlpha(80),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.email_outlined, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            email,
                            style: AppTypography.labelMd.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.none,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          isExpanded ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),

                // Approve Button if unapproved
                if (!isApproved) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onPressed: () => _approveUser(user),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text(
                        'APPROVE USER CLEARANCE',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ===================================================================
          // Expandable Dropdown / Section: Module Access Toggles
          // ===================================================================
          if (isExpanded)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(AppDimensions.radiusDefault),
                ),
                border: Border(
                  top: BorderSide(color: Colors.black12, width: 1.0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'MODULE ACCESS PERMISSIONS',
                        style: AppTypography.labelMd.copyWith(
                          fontWeight: FontWeight.w900,
                          color: AppColors.primary,
                          letterSpacing: 0.5,
                          fontSize: 12,
                        ),
                      ),
                      if (isSaving)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Toggle 1: Warranty Module
                  _buildModuleToggleTile(
                    title: '1. Warranty Module',
                    icon: Icons.shield_outlined,
                    value: hasWarranty,
                    isDisabled: isAdmin, // Admins always have access
                    onChanged: (newVal) {
                      _updateModulePermission(
                        user: user,
                        hasWarranty: newVal,
                        hasTrackBearing: hasTrack,
                      );
                    },
                  ),

                  const SizedBox(height: 8),

                  // Toggle 2: Track Your Bearing Module
                  _buildModuleToggleTile(
                    title: '2. Track Your Bearing Module',
                    icon: Icons.sync_alt_rounded,
                    value: hasTrack,
                    isDisabled: isAdmin, // Admins always have access
                    onChanged: (newVal) {
                      _updateModulePermission(
                        user: user,
                        hasWarranty: hasWarranty,
                        hasTrackBearing: newVal,
                      );
                    },
                  ),

                  const SizedBox(height: 8),

                  // Toggle 3: Reward Points Eligibility (Can block user anytime)
                  _buildModuleToggleTile(
                    title: '3. Reward Points Eligibility',
                    subtitle: isRewardEligible
                        ? 'User is eligible to earn 1st scan reward points and request payouts.'
                        : 'User is blocked from reward points. Scan verification displays polite standard notice.',
                    icon: Icons.stars,
                    value: isRewardEligible,
                    isDisabled: false,
                    enabledLabel: 'ELIGIBLE',
                    disabledLabel: 'BLOCKED',
                    onChanged: (newVal) {
                      _updateRewardEligibility(
                        user: user,
                        isEligible: newVal,
                      );
                    },
                  ),

                  // Authorised Person Number Management (Strictly 1 Number)
                  _buildAuthorisedNumbersSection(user),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Authorised Person Number section (Strictly ONLY ONE number per user)
  Widget _buildAuthorisedNumbersSection(Map<String, dynamic> user) {
    final userId = user['id']?.toString() ?? '';
    final List<String> numbers = List<String>.from(
      (user['authorised_numbers'] as List<dynamic>?)?.map((e) => e.toString()) ?? [],
    );
    final controller = _getNumberController(userId);
    final isSaving = _savingUserIds.contains(userId);
    final hasNumber = numbers.isNotEmpty;
    final singleNumber = hasNumber ? numbers.first : null;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
        border: Border.all(color: Colors.black12, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_android_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Authorised Person Number',
                style: AppTypography.bodySm.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Single Number display or empty advisory & input
          if (hasNumber)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.primary.withAlpha(80), width: 1.0),
              ),
              child: Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    singleNumber!,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                    tooltip: 'Remove Authorised Number',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: isSaving
                        ? null
                        : () => _updateAuthorisedNumbers(user: user, numbers: []),
                  ),
                ],
              ),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFFDE68A), width: 1.0),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Color(0xFFB45309)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No authorised number configured. Add at least one mobile number below.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Add Single Number Input Row
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Enter mobile number (e.g. +91 98988 57198)',
                        hintStyle: const TextStyle(fontSize: 11, color: Colors.black45),
                        prefixIcon: const Icon(Icons.add_call, size: 16, color: AppColors.primary),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: const BorderSide(color: Colors.black26),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                      onSubmitted: (_) => _addNumberForUser(user),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onPressed: isSaving ? null : () => _addNumberForUser(user),
                  child: isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModuleToggleTile({
    required String title,
    String? subtitle,
    required IconData icon,
    required bool value,
    required bool isDisabled,
    String enabledLabel = 'ENABLED',
    String disabledLabel = 'DISABLED',
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
        border: Border.all(
          color: value ? AppColors.primary : Colors.black12,
          width: value ? 1.4 : 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: subtitle != null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: subtitle != null ? 2.0 : 0.0),
            child: Icon(icon, color: value ? AppColors.primary : Colors.black45, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: AppTypography.bodySm.copyWith(
                          fontWeight: FontWeight.bold,
                          color: value ? AppColors.primary : Colors.black87,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: value ? _greenBackground : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: value ? _greenBorder : Colors.black26,
                          width: 1.0,
                        ),
                      ),
                      child: Text(
                        value ? enabledLabel : disabledLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: value ? _greenTextDark : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            activeThumbColor: AppColors.background,
            activeTrackColor: AppColors.primary,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: Colors.black26,
            onChanged: isDisabled ? null : onChanged,
          ),
        ],
      ),
    );
  }
}
