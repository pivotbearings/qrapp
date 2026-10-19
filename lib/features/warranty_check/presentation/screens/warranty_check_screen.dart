import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_status_badge.dart';
import '../../../bearing_verification/data/models/bearing_model.dart';
import '../../../bearing_verification/data/repositories/bearing_repository.dart';
import '../../../bearing_verification/domain/models/qr_verification_result.dart';
import '../../../bearing_verification/presentation/widgets/bearing_out_email_dialog.dart';
import '../../../../core/widgets/app_snack_bar.dart';

class WarrantyCheckScreen extends StatefulWidget {
  final String? initialBearingId;

  const WarrantyCheckScreen({
    super.key,
    this.initialBearingId,
  });

  @override
  State<WarrantyCheckScreen> createState() => _WarrantyCheckScreenState();
}

class _WarrantyCheckScreenState extends State<WarrantyCheckScreen> {
  final BearingRepository _bearingRepo = BearingRepositoryImpl();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _inputBearingCtrl = TextEditingController();

  List<BearingModel> _allBearings = [];
  bool _isLoading = true;
  String? _errorMessage;

  // 0: ALL, 1: UNDER WARRANTY, 2: EXPIRING SOON (<30d), 3: EXPIRED
  int _activeFilterTab = 0;
  bool _isCheckingSpecific = false;

  @override
  void initState() {
    super.initState();
    _loadUserBearings();
    if (widget.initialBearingId != null && widget.initialBearingId!.isNotEmpty) {
      _checkSpecificBearing(widget.initialBearingId!);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _inputBearingCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserBearings() async {
    setState(() => _isLoading = true);
    try {
      final auth = AuthController.instance;
      final bearings = await _bearingRepo.getAllBearings(
        customerId: auth.userId,
        customerEmail: auth.userEmail,
      );
      if (mounted) {
        setState(() {
          _allBearings = bearings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load warranty registry: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _checkSpecificBearing(String input) async {
    final clean = input.trim().toUpperCase();
    if (clean.isEmpty) return;

    // 0ms instant display if already in loaded list
    final existing = _allBearings.cast<BearingModel?>().firstWhere(
      (b) => b?.id == clean,
      orElse: () => null,
    );
    if (existing != null) {
      _showWarrantyDiagnosticModal(existing, null);
      return;
    }

    setState(() {
      _isCheckingSpecific = true;
      _errorMessage = null;
    });

    try {
      // Execute lookups concurrently in parallel
      final results = await Future.wait([
        _bearingRepo.verifyScannedPayload(clean),
        _bearingRepo.getBearingById(clean),
      ]);
      final verifResult = results[0] as QrVerificationResult;
      final model = results[1] as BearingModel?;

      if (mounted) {
        final b = model ??
            BearingModel(
              id: clean,
              batchCode: verifResult.batchCode ?? 'UNKNOWN',
              modelNumber: verifResult.modelNumber ?? 'PBI-MODEL',
              plantLocation: verifResult.plantLocation ?? 'Plant 02 — Chakan',
              warrantyDurationMonths: verifResult.warrantyDurationMonths ?? 6,
              state: verifResult.currentLifecycleState == 'CURRENTLY_IN'
                  ? BearingLifecycleState.currentlyIn
                  : (verifResult.currentLifecycleState == 'CURRENTLY_OUT'
                      ? BearingLifecycleState.currentlyOut
                      : BearingLifecycleState.notActivated),
              firstInDate: verifResult.firstInTimestamp,
              explicitExpiryDate: verifResult.warrantyExpiryTimestamp,
            );

        setState(() {
          _isCheckingSpecific = false;
        });

        _showWarrantyDiagnosticModal(b, verifResult);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingSpecific = false;
          _errorMessage = 'Could not verify bearing: $e';
        });
      }
    }
  }

  void _openQrScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _WarrantyQrScannerModal(
        onCodeScanned: (scannedCode) {
          Navigator.pop(ctx);
          _inputBearingCtrl.text = scannedCode;
          _checkSpecificBearing(scannedCode);
        },
      ),
    );
  }

  List<BearingModel> get _filteredBearings {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _allBearings.where((b) {
      // Tab Filter
      if (_activeFilterTab == 1) {
        // Under Warranty
        if (!b.isUnderWarranty) return false;
      } else if (_activeFilterTab == 2) {
        // Expiring soon (<30 days)
        final days = b.daysLeftToExpiry;
        if (days == null || days < 0 || days > 30) return false;
      } else if (_activeFilterTab == 3) {
        // Expired
        if (!b.isWarrantyExpired) return false;
      }

      // Search Query
      if (query.isNotEmpty) {
        final id = b.id.toLowerCase();
        final model = b.modelNumber.toLowerCase();
        final cat = b.category.toLowerCase();
        final batch = b.batchCode.toLowerCase();
        if (!id.contains(query) &&
            !model.contains(query) &&
            !cat.contains(query) &&
            !batch.contains(query)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredBearings;
    final totalCount = _allBearings.length;
    final underWarrantyCount = _allBearings.where((b) => b.isUnderWarranty).length;
    final expiringSoonCount = _allBearings.where((b) {
      final d = b.daysLeftToExpiry;
      return d != null && d >= 0 && d <= 30;
    }).length;
    final expiredCount = _allBearings.where((b) => b.isWarrantyExpired).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const IndustrialAppBar(
        title: 'Warranty Check',
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _loadUserBearings,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppDimensions.gutterMobile),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Header Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: AppColors.primary, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: const Center(
                              child: Icon(Icons.verified_user, color: AppColors.background, size: 24),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'WARRANTY CHECK',
                                  style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'INSTANT EXPIRY COUNTDOWN & CATEGORY AUDIT',
                                  style: AppTypography.caption.copyWith(fontSize: 10, letterSpacing: 0.8),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Action 1: Mark Bearing IN / OUT (With Proof Upload & Warranty Assignment)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.background,
                          elevation: 2,
                          minimumSize: const Size.fromHeight(48),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                        ),
                        icon: const Icon(Icons.camera_alt_outlined, size: 20),
                        label: Text(
                          'MARK BEARING IN / OUT (WITH PROOF)',
                          style: AppTypography.labelMd.copyWith(
                            color: AppColors.background,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        onPressed: () => Navigator.pushNamed(context, AppRoutes.qrScanner),
                      ),
                      const SizedBox(height: 10),

                      // Action 2: Scan QR to Search / Audit
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary, width: 1.4),
                          minimumSize: const Size.fromHeight(44),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                        ),
                        icon: const Icon(Icons.qr_code_scanner, size: 18),
                        label: Text(
                          'SCAN QR TO AUDIT / SEARCH',
                          style: AppTypography.labelMd.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        onPressed: _openQrScanner,
                      ),
                      const SizedBox(height: 12),

                      // Pill-Shaped Manual Input Field
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: TextField(
                                controller: _inputBearingCtrl,
                                style: AppTypography.bodyMd,
                                textCapitalization: TextCapitalization.characters,
                                onSubmitted: _checkSpecificBearing,
                                decoration: InputDecoration(
                                  hintText: 'Bearing ID / Serial (e.g. PB-9402)',
                                  hintStyle: AppTypography.bodyMd.copyWith(
                                    color: AppColors.primary.withValues(alpha: 0.5),
                                  ),
                                  prefixIcon: const Icon(Icons.search, color: AppColors.primary, size: 20),
                                  filled: true,
                                  fillColor: AppColors.background,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(50),
                                    borderSide: BorderSide(
                                      color: AppColors.primary.withValues(alpha: 0.3),
                                      width: 1.2,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(50),
                                    borderSide: BorderSide(
                                      color: AppColors.primary.withValues(alpha: 0.3),
                                      width: 1.2,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(50),
                                    borderSide: const BorderSide(
                                      color: AppColors.primary,
                                      width: 2.0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.background,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                              ),
                              onPressed: _isCheckingSpecific
                                  ? null
                                  : () => _checkSpecificBearing(_inputBearingCtrl.text),
                              child: _isCheckingSpecific
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.background),
                                    )
                                  : const Text('CHECK', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Error Banner
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 20, color: Color(0xFFDC2626)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_errorMessage!, style: AppTypography.bodySm.copyWith(color: const Color(0xFF991B1B)))),
                        GestureDetector(
                          onTap: () => setState(() => _errorMessage = null),
                          child: const Icon(Icons.close, size: 18, color: Color(0xFFDC2626)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                // Section Title: My Bearings Under Warranty
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(
                      'MY QR CODES UNDER WARRANTY',
                      style: AppTypography.headlineSm.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Text(
                        '$totalCount REGISTERED',
                        style: AppTypography.caption.copyWith(fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Pill Filter Tabs Switcher
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildPillTab(index: 0, label: 'ALL ($totalCount)'),
                      const SizedBox(width: 8),
                      _buildPillTab(index: 1, label: 'UNDER WARRANTY ($underWarrantyCount)'),
                      const SizedBox(width: 8),
                      _buildPillTab(index: 2, label: 'EXPIRING SOON ($expiringSoonCount)'),
                      const SizedBox(width: 8),
                      _buildPillTab(index: 3, label: 'EXPIRED ($expiredCount)'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Search Bar
                Container(
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    style: AppTypography.bodySm,
                    decoration: InputDecoration(
                      hintText: 'Search by Bearing ID, category, model...',
                      hintStyle: AppTypography.caption.copyWith(
                        color: AppColors.primary.withValues(alpha: 0.5),
                      ),
                      prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.primary),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16, color: AppColors.primary),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(50),
                        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.25), width: 1.2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(50),
                        borderSide: BorderSide(color: AppColors.primary.withValues(alpha: 0.25), width: 1.2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(50),
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Bearings List
                if (_isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(48.0),
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  )
                else if (filtered.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.shield_outlined, size: 48, color: AppColors.primary),
                        const SizedBox(height: 12),
                        Text(
                          _allBearings.isEmpty
                              ? 'No Bearings Registered To Your Tenant'
                              : 'No Bearings Match Selected Filter',
                          style: AppTypography.headlineSm,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _allBearings.isEmpty
                              ? 'Scan a bearing QR code or enter a Bearing ID above to run an instant warranty check.'
                              : 'Try adjusting your search query or tab filter.',
                          style: AppTypography.caption,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _buildWarrantyItemCard(item);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPillTab({required int index, required String label}) {
    final isSelected = _activeFilterTab == index;
    return GestureDetector(
      onTap: () => setState(() => _activeFilterTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelMd.copyWith(
            color: isSelected ? AppColors.background : AppColors.primary,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildWarrantyItemCard(BearingModel item) {
    final daysLeft = item.daysLeftToExpiry;
    final isExpired = item.isWarrantyExpired;

    Color badgeBg;
    Color badgeText;
    String daysLabel;

    if (daysLeft == null) {
      badgeBg = AppColors.primary.withValues(alpha: 0.1);
      badgeText = AppColors.primary;
      daysLabel = 'PENDING ACTIVATION';
    } else if (daysLeft > 30) {
      badgeBg = const Color(0xFFDCFCE7); // Light green
      badgeText = const Color(0xFF166534); // Dark green
      daysLabel = '$daysLeft DAYS LEFT';
    } else if (daysLeft >= 0) {
      badgeBg = const Color(0xFFFEF3C7); // Light amber
      badgeText = const Color(0xFF92400E); // Dark amber
      daysLabel = '$daysLeft DAYS LEFT (SOON)';
    } else {
      badgeBg = const Color(0xFFFEE2E2); // Light red
      badgeText = const Color(0xFF991B1B); // Dark red
      daysLabel = 'EXPIRED ${daysLeft.abs()}d AGO';
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isExpired
              ? const Color(0xFFEF4444).withValues(alpha: 0.4)
              : AppColors.primary.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showWarrantyDiagnosticModal(item, null),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Bearing ID & Warranty Days Pill Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.qr_code, size: 20, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            item.id,
                            style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Prominent Days Left Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: badgeText.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isExpired
                              ? Icons.warning_amber
                              : (daysLeft != null && daysLeft <= 30 ? Icons.timer : Icons.shield),
                          size: 13,
                          color: badgeText,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          daysLabel,
                          style: TextStyle(
                            color: badgeText,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Bearing Category Chip, Model & Status Badge (Responsive Wrap: zero overlap on any screen)
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      item.category.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.background,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      item.modelNumber,
                      style: AppTypography.caption.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  IndustrialStatusBadge(statusText: item.stateDisplayString),
                ],
              ),
              const Divider(height: 20),

              // Bottom Details Row: Expiry Date & Coverage (Responsive Wrap)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        item.warrantyExpiryDate != null
                            ? 'Expires: ${item.warrantyExpiryDate!.toLocal().toString().split(' ').first}'
                            : 'Coverage: ${item.warrantyDurationMonths} Months',
                        style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'CHECK DETAILS',
                        style: AppTypography.labelMd.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _markBearingOutAndOpenEmailDialog(BearingModel bearing) async {
    setState(() => _isLoading = true);
    try {
      final updated = await _bearingRepo.markBearingOut(bearing.id);
      final inDate = updated.firstInDate;
      final outDate = updated.lastOutDate ?? DateTime.now();
      String durationStr = 'Completed operational cycle';
      if (inDate != null) {
        final diff = outDate.difference(inDate);
        final days = diff.inDays;
        final hours = diff.inHours % 24;
        final mins = diff.inMinutes % 60;
        durationStr = '$days Days, $hours Hours, $mins Mins';
      }

      await _loadUserBearings();

      if (mounted) {
        setState(() => _isLoading = false);
        BearingOutEmailDialog.show(
          context,
          bearingId: updated.id,
          modelNumber: updated.modelNumber,
          category: updated.category,
          inDate: inDate,
          outDate: outDate,
          durationString: durationStr,
          warrantyPlan: '${updated.warrantyDurationMonths} Months Industrial Warranty',
          warrantyExpiry: updated.warrantyExpiryDate != null
              ? updated.warrantyExpiryDate!.toLocal().toString().split('.').first
              : 'N/A',
          isUnderWarranty: !updated.isWarrantyExpired,
          onDismissed: () => _loadUserBearings(),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnackBar.showError(context, 'Could not mark bearing OUT: $e');
      }
    }
  }

  void _showEmailDialogForExistingBearing(BearingModel bearing) {
    final inDate = bearing.firstInDate;
    final outDate = bearing.lastOutDate ?? DateTime.now();
    String durationStr = 'Completed operational cycle';
    if (inDate != null) {
      final diff = outDate.difference(inDate);
      final days = diff.inDays;
      final hours = diff.inHours % 24;
      final mins = diff.inMinutes % 60;
      durationStr = '$days Days, $hours Hours, $mins Mins';
    }

    BearingOutEmailDialog.show(
      context,
      bearingId: bearing.id,
      modelNumber: bearing.modelNumber,
      category: bearing.category,
      inDate: inDate,
      outDate: outDate,
      durationString: durationStr,
      warrantyPlan: '${bearing.warrantyDurationMonths} Months Industrial Warranty',
      warrantyExpiry: bearing.warrantyExpiryDate != null
          ? bearing.warrantyExpiryDate!.toLocal().toString().split('.').first
          : 'N/A',
      isUnderWarranty: !bearing.isWarrantyExpired,
      onDismissed: () => _loadUserBearings(),
    );
  }

  void _showWarrantyDiagnosticModal(BearingModel bearing, QrVerificationResult? verif) {
    final daysLeft = bearing.daysLeftToExpiry;
    final isExpired = bearing.isWarrantyExpired;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle drag bar
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Modal Header
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Center(
                      child: Icon(Icons.verified, color: AppColors.background, size: 28),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('WARRANTY AUDIT REPORT', style: AppTypography.caption.copyWith(fontSize: 10, letterSpacing: 1.0)),
                        Text(bearing.id, style: AppTypography.headlineMd),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.primary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // PROMINENT DAYS LEFT BANNER (Hero Pill)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: isExpired
                      ? const Color(0xFFFEF2F2)
                      : (daysLeft != null && daysLeft <= 30 ? const Color(0xFFFEF3C7) : const Color(0xFFF0FDF4)),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: isExpired
                        ? const Color(0xFFEF4444)
                        : (daysLeft != null && daysLeft <= 30 ? const Color(0xFFF59E0B) : const Color(0xFF22C55E)),
                    width: 2.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isExpired ? Icons.cancel : Icons.check_circle,
                      size: 28,
                      color: isExpired
                          ? const Color(0xFFDC2626)
                          : (daysLeft != null && daysLeft <= 30 ? const Color(0xFFD97706) : const Color(0xFF16A34A)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isExpired
                                ? 'WARRANTY EXPIRED'
                                : (daysLeft == null ? 'ACTIVE COVERAGE' : 'UNDER WARRANTY'),
                            style: TextStyle(
                              color: isExpired
                                  ? const Color(0xFF991B1B)
                                  : (daysLeft != null && daysLeft <= 30 ? const Color(0xFF92400E) : const Color(0xFF166534)),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            daysLeft != null
                                ? (daysLeft >= 0 ? '$daysLeft DAYS LEFT TO EXPIRE' : 'EXPIRED ${daysLeft.abs()} DAYS AGO')
                                : '${bearing.warrantyDurationMonths} MONTHS (PENDING ACTIVATION)',
                            style: TextStyle(
                              color: isExpired
                                  ? const Color(0xFF991B1B)
                                  : (daysLeft != null && daysLeft <= 30 ? const Color(0xFF92400E) : const Color(0xFF166534)),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Detail Rows
              _buildModalRow('Bearing Category', bearing.category, isBold: true),
              const Divider(),
              _buildModalRow('Model Number', bearing.modelNumber, isMono: true),
              const Divider(),
              _buildModalRow('Operational State', bearing.stateDisplayString),
              const Divider(),
              _buildModalRow('Coverage Plan', '${bearing.warrantyDurationMonths} Months Industrial Warranty'),
              const Divider(),
              _buildModalRow(
                'First Installation (IN)',
                bearing.firstInDate != null ? bearing.firstInDate!.toLocal().toString().split('.').first : 'Not yet installed',
              ),
              const Divider(),
              _buildModalRow(
                'Warranty Expiry Date',
                bearing.warrantyExpiryDate != null ? bearing.warrantyExpiryDate!.toLocal().toString().split('.').first : 'Calculated on First IN',
                isBold: true,
              ),
              const SizedBox(height: 24),

              // Bearing Out Action Button (Available directly in Warranty module)
              if (bearing.state == BearingLifecycleState.currentlyIn) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 1,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _markBearingOutAndOpenEmailDialog(bearing);
                    },
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text(
                      'MARK BEARING OUT & EMAIL LIFECYCLE',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ] else if (bearing.state == BearingLifecycleState.currentlyOut) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 1,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showEmailDialogForExistingBearing(bearing);
                    },
                    icon: const Icon(Icons.email_outlined, size: 18),
                    label: const Text(
                      'EMAIL LIFECYCLE INFORMATION',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Primary Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('CLOSE', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.background,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, AppRoutes.bearingVerification, arguments: bearing.id);
                      },
                      child: const Text('VERIFY / ACTIONS', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModalRow(String label, String value, {bool isBold = false, bool isMono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.caption),
          Flexible(
            child: Text(
              value,
              style: isMono
                  ? AppTypography.mono.copyWith(fontWeight: isBold ? FontWeight.bold : FontWeight.normal)
                  : AppTypography.bodySm.copyWith(fontWeight: isBold ? FontWeight.bold : FontWeight.normal),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// Scanner modal sheet for scanning QR directly within Warranty Check
class _WarrantyQrScannerModal extends StatefulWidget {
  final void Function(String scannedCode) onCodeScanned;

  const _WarrantyQrScannerModal({required this.onCodeScanned});

  @override
  State<_WarrantyQrScannerModal> createState() => _WarrantyQrScannerModalState();
}

class _WarrantyQrScannerModalState extends State<_WarrantyQrScannerModal> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _hasDetected = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('SCAN QR FOR WARRANTY CHECK', style: AppTypography.headlineSm),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.primary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: (capture) {
                      if (_hasDetected) return;
                      for (final barcode in capture.barcodes) {
                        final val = barcode.rawValue?.trim();
                        if (val != null && val.isNotEmpty) {
                          _hasDetected = true;
                          widget.onCodeScanned(val);
                          break;
                        }
                      }
                    },
                  ),
                  // Reticle frame
                  Center(
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary, width: 3),
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Align bearing QR code within frame for instant warranty calculation.',
              style: AppTypography.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
