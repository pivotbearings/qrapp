import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../rewards/domain/models/reward_models.dart';
import '../../../rewards/data/services/reward_service.dart';

/// Pivot Bearings India - Admin Reward & Payouts Workstation
///
/// Features:
/// 1. Conversion Rate Setting: "10 points = how many Rs"
/// 2. Payout queue management: Approve as completed with UTR & notes, or Reject with reason & auto-refund
/// 3. Minimum redemption threshold & daily velocity limits
/// 4. Terms & Conditions configuration
class AdminRewardsView extends StatefulWidget {
  const AdminRewardsView({super.key});

  @override
  State<AdminRewardsView> createState() => _AdminRewardsViewState();
}

class _AdminRewardsViewState extends State<AdminRewardsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  bool _isLoading = true;
  String _selectedStatus = 'PENDING'; // 'ALL', 'PENDING', 'COMPLETED', 'REJECTED'

  int _redPage = 0;
  int _redTotalCount = 0;
  bool _redLoading = false;
  static const int _pageSize = 10;

  List<RewardRedemption> _redemptions = [];
  RewardSettings _settings = const RewardSettings();

  // Settings Controllers
  final TextEditingController _inrPer10PtsCtrl = TextEditingController();
  final TextEditingController _ptsPerScanCtrl = TextEditingController();
  final TextEditingController _minRedeemCtrl = TextEditingController();
  final TextEditingController _dailyLimitCtrl = TextEditingController();
  final TextEditingController _termsCtrl = TextEditingController();
  bool _isSystemEnabled = true;
  bool _isSavingSettings = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _inrPer10PtsCtrl.dispose();
    _ptsPerScanCtrl.dispose();
    _minRedeemCtrl.dispose();
    _dailyLimitCtrl.dispose();
    _termsCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final settings = await RewardService.fetchRewardSettings();
      final redRes = await RewardService.fetchAdminRedemptionsPaginated(
        statusFilter: _selectedStatus == 'ALL' ? null : _selectedStatus,
        page: 0,
        pageSize: _pageSize,
      );

      _inrPer10PtsCtrl.text = settings.inrPerBaseUnit.toStringAsFixed(2);
      _ptsPerScanCtrl.text = settings.pointsPerFirstScan.toString();
      _minRedeemCtrl.text = settings.minRedemptionPoints.toString();
      _dailyLimitCtrl.text = settings.dailyMaxScans.toString();
      _termsCtrl.text = settings.termsAndConditions;
      _isSystemEnabled = settings.isEnabled;

      if (mounted) {
        setState(() {
          _settings = settings;
          _redemptions = redRes.items;
          _redTotalCount = redRes.totalCount;
          _redPage = 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnackBar.showError(context, 'Failed to load rewards data: $e');
      }
    }
  }

  Future<void> _loadRedemptions({int page = 0}) async {
    setState(() => _redLoading = true);
    try {
      final res = await RewardService.fetchAdminRedemptionsPaginated(
        statusFilter: _selectedStatus == 'ALL' ? null : _selectedStatus,
        page: page,
        pageSize: _pageSize,
      );
      if (mounted) {
        setState(() {
          _redemptions = res.items;
          _redTotalCount = res.totalCount;
          _redPage = page;
          _redLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _redLoading = false);
        AppSnackBar.showError(context, 'Failed to load redemption queue: $e');
      }
    }
  }

  Future<void> _saveSettings() async {
    final inrPer10 = double.tryParse(_inrPer10PtsCtrl.text.trim());
    if (inrPer10 == null || inrPer10 <= 0) {
      AppSnackBar.showError(context, 'Please enter a valid Rupee amount for 10 points.');
      return;
    }

    final ptsPerScan = int.tryParse(_ptsPerScanCtrl.text.trim()) ?? 10;
    final minRedeem = int.tryParse(_minRedeemCtrl.text.trim()) ?? 50;
    final dailyCap = int.tryParse(_dailyLimitCtrl.text.trim()) ?? 50;

    setState(() => _isSavingSettings = true);

    try {
      final ok = await RewardService.updateRewardSettings(
        pointsBaseUnit: 10,
        inrPerBaseUnit: inrPer10,
        pointsPerFirstScan: ptsPerScan,
        minRedemptionPoints: minRedeem,
        isEnabled: _isSystemEnabled,
        dailyMaxScans: dailyCap,
        termsAndConditions: _termsCtrl.text.trim(),
      );

      if (mounted) {
        setState(() => _isSavingSettings = false);
        if (ok) {
          AppSnackBar.showSuccess(
            context,
            'REWARD SETTINGS SAVED: 10 Points = ₹${inrPer10.toStringAsFixed(2)} synchronized!',
          );
          _loadAllData();
        } else {
          AppSnackBar.showError(context, 'Failed to save settings.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingSettings = false);
        AppSnackBar.showError(context, 'Error saving settings: $e');
      }
    }
  }

  void _showApproveDialog(RewardRedemption req) {
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController(
      text: 'Paid ₹${req.amountInInr.toStringAsFixed(2)} to ${req.payoutMethod == "UPI" ? req.upiId : req.bankAccountHolderName}',
    );
    String paymentMode = req.payoutMethod == 'UPI' ? 'UPI / GPay' : 'IMPS';
    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppColors.primary, width: 2.0),
              ),
              title: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF0D8A4E)),
                  const SizedBox(width: 8),
                  Text(
                    'Approve Payout #${req.requestNumber}',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // User & Payout Summary
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recipient: ${req.userName ?? req.userEmail ?? "User"}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Amount to Pay: ₹${req.amountInInr.toStringAsFixed(2)} (${req.pointsRequested} pts)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: Color(0xFF0D8A4E),
                              ),
                            ),
                            const Divider(height: 16),
                            if (req.payoutMethod == 'UPI') ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'UPI ID: ${req.upiId ?? "N/A"}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 18),
                                    tooltip: 'Copy UPI ID',
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: req.upiId ?? ''));
                                      AppSnackBar.showSuccess(context, 'UPI ID copied to clipboard');
                                    },
                                  ),
                                ],
                              ),
                            ] else ...[
                              Text('Bank: ${req.bankName ?? "N/A"}'),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'A/C No: ${req.bankAccountNumber ?? "N/A"}',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 18),
                                    tooltip: 'Copy Account Number',
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: req.bankAccountNumber ?? ''));
                                      AppSnackBar.showSuccess(context, 'Account number copied');
                                    },
                                  ),
                                ],
                              ),
                              Text('IFSC: ${req.bankIfsc ?? "N/A"}'),
                              Text('Holder: ${req.bankAccountHolderName ?? "N/A"}'),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      const Text(
                        'Payment Mode',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.primary),
                      ),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue: paymentMode,
                        decoration: _inputDeco('Payment Method'),
                        items: const [
                          DropdownMenuItem(value: 'UPI / GPay', child: Text('UPI (GPay / PhonePe / Paytm)')),
                          DropdownMenuItem(value: 'IMPS', child: Text('IMPS Instant Bank Transfer')),
                          DropdownMenuItem(value: 'NEFT', child: Text('NEFT Bank Transfer')),
                          DropdownMenuItem(value: 'RTGS', child: Text('RTGS')),
                          DropdownMenuItem(value: 'DIRECT_CASH', child: Text('Direct Counter Payout')),
                        ],
                        onChanged: (v) => setDialogState(() => paymentMode = v ?? 'UPI / GPay'),
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        'Bank Transaction ID / UTR Reference *',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.primary),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: refCtrl,
                        decoration: _inputDeco('e.g. UTR-4291820491 or UPI Ref ID'),
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        'Admin Confirmation Notes',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.primary),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: notesCtrl,
                        maxLines: 2,
                        decoration: _inputDeco('Visible to user on their payout receipt'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isProcessing ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('CANCEL', style: TextStyle(color: Colors.black54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D8A4E),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isProcessing
                      ? null
                      : () async {
                          if (refCtrl.text.trim().isEmpty) {
                            AppSnackBar.showError(context, 'Please enter a Bank UTR / Payment Reference ID.');
                            return;
                          }

                          setDialogState(() => isProcessing = true);
                          final res = await RewardService.adminProcessRedemption(
                            redemptionId: req.id,
                            action: 'APPROVE',
                            paymentRef: refCtrl.text.trim(),
                            paymentMode: paymentMode,
                            notes: notesCtrl.text.trim(),
                          );

                          if (mounted && context.mounted) {
                            Navigator.of(ctx).pop();
                            if (res['success'] == true) {
                              AppSnackBar.showSuccess(context, 'Payout marked as COMPLETED.');
                              _loadAllData();
                            } else {
                              AppSnackBar.showError(context, res['message']?.toString() ?? 'Failed to approve.');
                            }
                          }
                        },
                  child: Text(isProcessing ? 'CONFIRMING...' : 'CONFIRM PAYMENT'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRejectDialog(RewardRedemption req) {
    final reasonCtrl = TextEditingController();
    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFD32F2F), width: 2.0),
              ),
              title: Row(
                children: [
                  const Icon(Icons.cancel_rounded, color: Color(0xFFD32F2F)),
                  const SizedBox(width: 8),
                  Text(
                    'Reject Request #${req.requestNumber}',
                    style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Are you sure you want to reject this payout request for ${req.pointsRequested} pts (₹${req.amountInInr.toStringAsFixed(2)})?',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'NOTE: Rejecting will automatically restore the ${req.pointsRequested} points back into the user\'s reward balance.',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0D8A4E)),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Mandatory Rejection Reason *',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.primary),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: reasonCtrl,
                      maxLines: 2,
                      decoration: _inputDeco('e.g. Invalid IFSC Code or Bank Account Mismatch'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isProcessing ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('CANCEL', style: TextStyle(color: Colors.black54)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isProcessing
                      ? null
                      : () async {
                          if (reasonCtrl.text.trim().isEmpty) {
                            AppSnackBar.showError(context, 'Please enter a rejection reason.');
                            return;
                          }

                          setDialogState(() => isProcessing = true);
                          final res = await RewardService.adminProcessRedemption(
                            redemptionId: req.id,
                            action: 'REJECT',
                            notes: reasonCtrl.text.trim(),
                          );

                          if (mounted && context.mounted) {
                            Navigator.of(ctx).pop();
                            if (res['success'] == true) {
                              AppSnackBar.showSuccess(context, 'Request rejected and points refunded.');
                              _loadAllData();
                            } else {
                              AppSnackBar.showError(context, res['message']?.toString() ?? 'Failed to reject.');
                            }
                          }
                        },
                  child: Text(isProcessing ? 'REJECTING...' : 'REJECT & REFUND'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Workstation Top Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          color: Colors.white,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.stars, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.primary, width: 1.2),
                      ),
                      child: Text(
                        'Active Rate: 10 Points = ₹${_settings.inrPerBaseUnit.toStringAsFixed(2)}  •  Min Payout: ${_settings.minRedemptionPoints} pts',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
                tooltip: 'Refresh Queue',
                onPressed: _loadAllData,
              ),
            ],
          ),
        ),

        // Tabs
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3.0,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.black54,
            labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            tabs: const [
              Tab(text: 'REDEMPTION PAYOUTS QUEUE'),
              Tab(text: 'RATE & PROGRAM SETTINGS'),
            ],
          ),
        ),

        // Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPayoutsQueueTab(),
              _buildSettingsTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 1: PAYOUTS QUEUE
  // ===========================================================================
  Widget _buildPayoutsQueueTab() {
    return Column(
      children: [
        // Status Filter Row
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: AppColors.background,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              const Text(
                'FILTER BY STATUS:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
              _buildFilterChip('PENDING', 'Pending Payouts'),
              _buildFilterChip('COMPLETED', 'Completed'),
              _buildFilterChip('REJECTED', 'Rejected'),
              _buildFilterChip('ALL', 'All'),
            ],
          ),
        ),

        if (_redLoading)
          const LinearProgressIndicator(color: AppColors.primary, minHeight: 2),

        // List
        Expanded(
          child: _redemptions.isEmpty && !_redLoading
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 54, color: Colors.black26),
                        const SizedBox(height: 12),
                        Text(
                          'No ${_selectedStatus == "ALL" ? "" : _selectedStatus} Redemption Requests',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _redemptions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (ctx, idx) {
                        final r = _redemptions[idx];
                        return _buildAdminRedemptionCard(r);
                      },
                    ),
                    _buildPaginationBar(
                      currentPage: _redPage,
                      totalCount: _redTotalCount,
                      pageSize: _pageSize,
                      isLoading: _redLoading,
                      itemName: 'requests',
                      onPageChanged: (newPage) => _loadRedemptions(page: newPage),
                    ),
                  ],
                ),
        ),
      ],
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

  Widget _buildFilterChip(String status, String label) {
    final isSelected = _selectedStatus == status;
    return InkWell(
      onTap: () {
        setState(() => _selectedStatus = status);
        _loadAllData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary, width: 1.0),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.primary,
            fontWeight: FontWeight.w900,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildAdminRedemptionCard(RewardRedemption r) {
    Color statusColor;
    Color statusBg;
    if (r.isCompleted) {
      statusColor = const Color(0xFF0D8A4E);
      statusBg = const Color(0xFFE8F5E9);
    } else if (r.isRejected) {
      statusColor = const Color(0xFFD32F2F);
      statusBg = const Color(0xFFFFEBEE);
    } else {
      statusColor = const Color(0xFFB45309);
      statusBg = const Color(0xFFFEF3C7);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 1.2),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    r.requestNumber,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.primary),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: statusColor, width: 1.0),
                    ),
                    child: Text(
                      r.status,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 10),
                    ),
                  ),
                ],
              ),
              Text(
                '₹${r.amountInInr.toStringAsFixed(2)} (${r.pointsRequested} pts)',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0D8A4E)),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // User info
          Row(
            children: [
              const Icon(Icons.person, size: 16, color: Colors.black54),
              const SizedBox(width: 6),
              Text(
                '${r.userName ?? "User"} • ${r.userEmail ?? r.userId}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              if (r.userPhone != null && r.userPhone!.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text('• Ph: ${r.userPhone}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ],
          ),

          const SizedBox(height: 8),

          // Payout Target Details
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.payoutMethod == 'UPI'
                            ? 'UPI ID: ${r.upiId ?? "N/A"}'
                            : 'Bank: ${r.bankName ?? ""} | A/C: ${r.bankAccountNumber ?? ""} | IFSC: ${r.bankIfsc ?? ""}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      if (r.payoutMethod == 'BANK_TRANSFER' && r.bankAccountHolderName != null)
                        Text('Holder Name: ${r.bankAccountHolderName}', style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy Payment Target',
                  onPressed: () {
                    final target = r.payoutMethod == 'UPI' ? r.upiId : r.bankAccountNumber;
                    Clipboard.setData(ClipboardData(text: target ?? ''));
                    AppSnackBar.showSuccess(context, 'Copied $target');
                  },
                ),
              ],
            ),
          ),

          if (r.createdAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Requested On: ${_dateFormat.format(r.createdAt!)}',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],

          // Completed / Rejected Details
          if (r.isCompleted) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F8E9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF81C784)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paid via ${r.paymentMode ?? "Transfer"} • Ref/UTR: ${r.paymentReferenceId ?? "Direct"}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF1B5E20)),
                  ),
                  if (r.adminNotes != null && r.adminNotes!.isNotEmpty)
                    Text('Admin Note: ${r.adminNotes}', style: const TextStyle(fontSize: 11, color: Color(0xFF1B5E20))),
                ],
              ),
            ),
          ] else if (r.isRejected) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF9A9A)),
              ),
              child: Text(
                'Rejected Reason: ${r.adminNotes ?? "Rejected by admin"} (Points Refunded)',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFC62828)),
              ),
            ),
          ],

          // Action Buttons (Only if pending)
          if (r.isPending) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D8A4E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('APPROVE & PAY', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                    onPressed: () => _showApproveDialog(r),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD32F2F),
                      side: const BorderSide(color: Color(0xFFD32F2F), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('REJECT & REFUND', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                    onPressed: () => _showRejectDialog(r),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 2: RATE & PROGRAM SETTINGS
  // ===========================================================================
  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Conversion Rate Setting Hero Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primary, width: 2.0),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.currency_rupee_rounded, color: AppColors.primary, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'POINTS-TO-RUPEE CONVERSION FORMULA',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Admins can configure the exact exchange value anytime. This formula is shown transparently to all users in their wallet.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '10 POINTS =',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text('₹', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextFormField(
                            controller: _inrPer10PtsCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.primary),
                            decoration: _inputDeco('Rupee Value for 10 Points (e.g. 10.00)'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // General Program Rules
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12, width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PROGRAM RULES & THRESHOLDS',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // First scan points
                    _buildFieldLabel('Points Awarded on 1st Scan of Genuine Bearing:'),
                    TextFormField(
                      controller: _ptsPerScanCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDeco('e.g. 10'),
                    ),

                    const SizedBox(height: 12),

                    // Min redemption
                    _buildFieldLabel('Minimum Points Required to Request Redemption:'),
                    TextFormField(
                      controller: _minRedeemCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDeco('e.g. 50'),
                    ),

                    const SizedBox(height: 12),

                    // Daily limit
                    _buildFieldLabel('Anti-Fraud Daily Scan Limit (per user):'),
                    TextFormField(
                      controller: _dailyLimitCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _inputDeco('e.g. 50 scans/day'),
                    ),

                    const SizedBox(height: 16),

                    // Active Toggle
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: AppColors.primary,
                      title: const Text(
                        'Reward Program Enabled',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      subtitle: const Text(
                        'Disable to temporarily pause points issuance and redemptions',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _isSystemEnabled,
                      onChanged: (v) => setState(() => _isSystemEnabled = v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Terms & Conditions Configuration
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black12, width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TERMS & CONDITIONS DISCLAIMER (Shown to Users)',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Explicit legal reservation that Pivot Bearings can change the point value anytime.',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _termsCtrl,
                      maxLines: 3,
                      decoration: _inputDeco('T&C text'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Save Button
              IndustrialButton(
                label: _isSavingSettings ? 'SAVING SETTINGS...' : 'SAVE & APPLY REWARD SETTINGS',
                isLoading: _isSavingSettings,
                onPressed: _isSavingSettings ? null : _saveSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 2.0),
      ),
    );
  }
}
