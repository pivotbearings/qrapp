import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../domain/models/reward_models.dart';
import '../../data/services/reward_service.dart';
import '../dialogs/redeem_points_dialog.dart';

/// Pivot Bearings India - User Reward Points Wallet & Payout Center
///
/// Features:
/// - Real-time wallet balance in Points & INR
/// - Prominent display: "10 Points = ₹X.XX"
/// - Explicit Terms & Conditions disclaimer: conversion value can be modified anytime
/// - Payout status tracking with Admin Notes & Bank UTR / Payment Ref IDs
/// - Complete immutable scan transaction history
class RewardWalletScreen extends StatefulWidget {
  const RewardWalletScreen({super.key});

  @override
  State<RewardWalletScreen> createState() => _RewardWalletScreenState();
}

class _RewardWalletScreenState extends State<RewardWalletScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  bool _isLoading = true;
  RewardProfile _profile = RewardProfile.defaultProfile();
  List<RewardTransaction> _transactions = [];
  List<RewardRedemption> _redemptions = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final prof = await RewardService.fetchUserRewardProfile();
      final txns = await RewardService.fetchUserTransactions();
      final reds = await RewardService.fetchUserRedemptions();

      if (mounted) {
        setState(() {
          _profile = prof;
          _transactions = txns;
          _redemptions = reds;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnackBar.showError(context, 'Failed to refresh wallet: $e');
      }
    }
  }

  void _openRedeemDialog() {
    if (!_profile.isRewardEligible) {
      AppSnackBar.showInfo(
        context,
        'Reward points redemption is currently inactive for this account profile. Please contact support.',
      );
      return;
    }

    if (_profile.currentBalancePoints < _profile.minRedemptionPoints) {
      AppSnackBar.showInfo(
        context,
        'Minimum ${_profile.minRedemptionPoints} points required to request redemption.',
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => RedeemPointsDialog(
        profile: _profile,
        onSuccess: _loadData,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: IndustrialAppBar(
        title: 'Reward Wallet',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            tooltip: 'Refresh Wallet',
            onPressed: _loadData,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3))
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: NestedScrollView(
                    headerSliverBuilder: (context, innerBoxIsScrolled) {
                      return [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(AppDimensions.gutterMobile),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (!_profile.isRewardEligible) ...[
                                  _buildAccountNoticeBanner(),
                                  const SizedBox(height: AppDimensions.spaceSm),
                                ],
                                _buildBalanceHeroCard(),
                                const SizedBox(height: AppDimensions.spaceSm),
                                _buildTermsBanner(),
                                const SizedBox(height: AppDimensions.spaceSm),
                              ],
                            ),
                          ),
                        ),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _SliverTabHeaderDelegate(
                            TabBar(
                              controller: _tabController,
                              indicatorColor: AppColors.primary,
                              indicatorWeight: 3.0,
                              labelColor: AppColors.primary,
                              unselectedLabelColor: Colors.black54,
                              labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                              tabs: const [
                                Tab(text: 'REDEMPTIONS'),
                                Tab(text: 'POINTS LEDGER'),
                              ],
                            ),
                          ),
                        ),
                      ];
                    },
                    body: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildRedemptionsList(),
                        _buildTransactionsList(),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildBalanceHeroCard() {
    final canRedeem = _profile.isRewardEligible &&
        _profile.currentBalancePoints >= _profile.minRedemptionPoints;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 1.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Label & Active Conversion Rate
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.stars_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'PIVOT REWARD WALLET',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _profile.rateDisplayString,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Main Balance
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '${_profile.currentBalancePoints}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 42,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Points',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '≈ ₹${_profile.currentBalanceInr.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Secondary Statistics Grid
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('In Payout Review', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 10, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        '${_profile.pendingRedemptionPoints} pts (₹${_profile.pendingRedemptionInr.toStringAsFixed(2)})',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 28, color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Redeemed', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 10, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        '${_profile.totalPointsRedeemed} pts',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Redeem CTA Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: canRedeem ? Colors.white : Colors.transparent,
              foregroundColor: canRedeem ? AppColors.primary : Colors.white,
              elevation: 0,
              side: BorderSide(
                color: canRedeem ? Colors.white : Colors.white.withValues(alpha: 0.4),
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              minimumSize: const Size(double.infinity, 48),
            ),
            onPressed: canRedeem ? _openRedeemDialog : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.account_balance_wallet_rounded,
                  color: canRedeem ? AppColors.primary : Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  canRedeem
                      ? 'REDEEM POINTS (MIN ${_profile.minRedemptionPoints} PTS)'
                      : 'NEED MIN ${_profile.minRedemptionPoints} PTS TO REDEEM',
                  style: TextStyle(
                    color: canRedeem ? AppColors.primary : Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountNoticeBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.primary),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACCOUNT REWARDS NOTICE',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Your account profile is currently in standard verification mode without active promotional point credits. Bearing authenticity checks remain fully supported. For questions, contact support.',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermsBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PROGRAM TERMS & CONDITIONS',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _profile.termsAndConditions,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 10.5,
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

  Widget _buildRedemptionsList() {
    if (_redemptions.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history_rounded,
        title: 'No Redemption Requests Yet',
        subtitle: 'When you redeem points for cash, your payout requests and bank payment receipts will appear here.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppDimensions.gutterMobile),
      itemCount: _redemptions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, idx) {
        final r = _redemptions[idx];
        return _buildRedemptionCard(r);
      },
    );
  }

  Widget _buildRedemptionCard(RewardRedemption r) {
    Color statusColor;
    Color statusBg;
    String statusLabel = r.status;

    if (r.isCompleted) {
      statusColor = const Color(0xFF0D8A4E);
      statusBg = const Color(0xFFE8F5E9);
      statusLabel = 'COMPLETED / PAID';
    } else if (r.isRejected) {
      statusColor = const Color(0xFFD32F2F);
      statusBg = const Color(0xFFFFEBEE);
      statusLabel = 'REJECTED (POINTS REFUNDED)';
    } else {
      statusColor = const Color(0xFFB45309);
      statusBg = const Color(0xFFFEF3C7);
      statusLabel = 'IN REVIEW / PENDING';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Line: Req Number & Status Tag
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                r.requestNumber,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.primary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor, width: 1.0),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 10),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Payout Details
          Row(
            children: [
              Text(
                '${r.pointsRequested} pts ➔ ₹${r.amountInInr.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.black87),
              ),
              const Spacer(),
              Text(
                r.payoutMethod == 'UPI' ? 'UPI: ${r.upiId ?? "N/A"}' : 'Bank: ${r.bankName ?? "Account"}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54),
              ),
            ],
          ),

          if (r.createdAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Submitted: ${_dateFormat.format(r.createdAt!)}',
              style: const TextStyle(fontSize: 10.5, color: Colors.black45),
            ),
          ],

          // Admin Notes & Bank Payment Reference (UTR)
          if (r.isCompleted) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F8E9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF81C784), width: 1.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Color(0xFF2E7D32), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Payment Ref / UTR: ${r.paymentReferenceId ?? "Direct Transfer"}',
                        style: const TextStyle(color: Color(0xFF1B5E20), fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ],
                  ),
                  if (r.adminNotes != null && r.adminNotes!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Admin Note: ${r.adminNotes!}',
                      style: const TextStyle(color: Color(0xFF1B5E20), fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (r.isRejected && r.adminNotes != null && r.adminNotes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF9A9A), width: 1.0),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cancel_outlined, color: Color(0xFFC62828), size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Rejection Reason: ${r.adminNotes!}',
                      style: const TextStyle(color: Color(0xFFB71C1C), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransactionsList() {
    if (_transactions.isEmpty) {
      return _buildEmptyState(
        icon: Icons.receipt_long_rounded,
        title: 'No Transactions Recorded',
        subtitle: 'Scan any authentic Pivot Bearing QR code to claim your first-scan reward points.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppDimensions.gutterMobile),
      itemCount: _transactions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, idx) {
        final t = _transactions[idx];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black12, width: 1.0),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: t.isCredit ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  t.isCredit ? Icons.add_circle_outline : Icons.remove_circle_outline,
                  color: t.isCredit ? const Color(0xFF0D8A4E) : const Color(0xFFD32F2F),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.description,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                    ),
                    if (t.createdAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        _dateFormat.format(t.createdAt!),
                        style: const TextStyle(fontSize: 10, color: Colors.black45),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${t.isCredit ? "+" : ""}${t.points} pts',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: t.isCredit ? const Color(0xFF0D8A4E) : const Color(0xFFD32F2F),
                    ),
                  ),
                  Text(
                    '₹${t.amountInr.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: Colors.black26),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primary),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliverTabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _SliverTabHeaderDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.background,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverTabHeaderDelegate oldDelegate) {
    return false;
  }
}
