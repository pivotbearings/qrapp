import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_status_badge.dart';
import '../../../../core/widgets/whatsapp_icon.dart';
import '../../../bearing_verification/data/models/bearing_model.dart';
import '../../../bearing_verification/data/repositories/bearing_repository.dart';
import '../../../bearing_verification/domain/models/qr_verification_result.dart';
import '../../../bearing_verification/presentation/widgets/bearing_out_email_dialog.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../../core/services/anti_fraud_service.dart';
import '../../../item_master/data/repositories/item_master_repository.dart';

class WarrantyCheckScreen extends StatefulWidget {
  final String? initialBearingId;
  final int? initialTabIndex;

  const WarrantyCheckScreen({
    super.key,
    this.initialBearingId,
    this.initialTabIndex,
  });

  @override
  State<WarrantyCheckScreen> createState() => _WarrantyCheckScreenState();
}

class _WarrantyCheckScreenState extends State<WarrantyCheckScreen> {
  final BearingRepository _bearingRepo = BearingRepositoryImpl();
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _inputBearingCtrl = TextEditingController();
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  List<BearingModel> _allBearings = [];
  bool _isLoading = true;
  String? _errorMessage;

  // 0: ALL, 1: UNDER WARRANTY, 2: EXPIRING SOON (20% horizon), 3: EXPIRED, 4: MARKED OUT (UNDER WARRANTY)
  int _activeFilterTab = 0;
  bool _isCheckingSpecific = false;

  void _shareMarkedOutWarrantyOnWhatsApp(BearingModel item) {
    final itemMaster = ItemMasterRepository().findByCode(item.modelNumber);
    final pName = item.productName ?? itemMaster?.itemName ?? 'Bearing 1(Ball Bearing)';
    final mNumber = (item.modelNumber.isNotEmpty && item.modelNumber != 'PBI-6204-ZZ')
        ? item.modelNumber
        : (itemMaster?.itemCode ?? 'B1');
    final inStr = item.firstInDate != null ? _dateFormat.format(item.firstInDate!) : 'N/A';
    final outStr = item.lastOutDate != null ? _dateFormat.format(item.lastOutDate!) : _dateFormat.format(DateTime.now());
    final expStr = item.warrantyExpiryDate != null ? _dateFormat.format(item.warrantyExpiryDate!) : 'N/A';
    final daysLeft = item.daysLeftToExpiry ?? 0;
    final durStr = _calculateLifecycleDuration(item);

    final msg = '''*PIVOT BEARINGS INDIA - WARRANTY CLAIM NOTICE*
━━━━━━━━━━━━━━━━━━━━━━━━━
• *Bearing QR Serial:* ${item.id}
• *Model / Part No:* $mNumber
• *Product Name:* $pName
• *Current State:* Marked OUT (Decommissioned)
• *Warranty Status:* ACTIVE UNDER WARRANTY
• *Days Remaining:* $daysLeft Days Left
• *Bearing In (Installed):* $inStr
• *Bearing Out (Removed):* $outStr
• *Operating Duration:* $durStr
• *Warranty Expiry Date:* $expStr
━━━━━━━━━━━━━━━━━━━━━━━━━
*Claim Note:* Product was decommissioned prior to warranty expiry. Submitting official claim request with supplier as per warranty terms.
Pivot Bearings Authorized Traceability Ledger''';

    final url = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
    launchUrl(url, mode: LaunchMode.externalApplication).catchError((_) {
      if (mounted) AppSnackBar.showError(context, 'Could not launch WhatsApp.');
      return false;
    });
  }

  void _shareExpiredWarrantyOnWhatsApp(BearingModel item) {
    final inStr = item.firstInDate != null ? _dateFormat.format(item.firstInDate!) : 'N/A';
    final expStr = item.warrantyExpiryDate != null ? _dateFormat.format(item.warrantyExpiryDate!) : 'N/A';
    final outStr = item.lastOutDate != null ? _dateFormat.format(item.lastOutDate!) : 'N/A';
    final durStr = _calculateLifecycleDuration(item);

    final msg = '''*PIVOT BEARINGS INDIA - EXPIRED WARRANTY RECORD*
--------------------------------
*Bearing ID:* ${item.id}
*Model:* ${item.modelNumber}
*Category:* ${item.category}
*Status:* WARRANTY EXPIRED
*Warranty Start / In Date:* $inStr
*Warranty Expiry Date:* $expStr
*Track Out Date:* $outStr
*Total Lifecycle Duration:* $durStr
--------------------------------
Official Industrial Warranty Record
Pivot Bearings India''';

    final url = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(msg)}');
    launchUrl(url, mode: LaunchMode.externalApplication).catchError((_) {
      if (mounted) AppSnackBar.showError(context, 'Could not launch WhatsApp.');
      return false;
    });
  }

  String _calculateLifecycleDuration(BearingModel item) {
    if (item.firstInDate == null) return '${item.warrantyDurationMonths} Months';
    final endDate = item.lastOutDate ?? item.warrantyExpiryDate ?? DateTime.now();
    final diff = endDate.difference(item.firstInDate!);
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    if (days > 0) {
      return '$days Days, $hours Hours';
    } else {
      return '${item.warrantyDurationMonths} Months';
    }
  }

  Widget _buildLifecycleRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialTabIndex != null) {
      _activeFilterTab = widget.initialTabIndex!;
    }
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

  Future<void> _checkSpecificBearing(String input, {bool fromScan = false}) async {
    final clean = input.trim();
    if (clean.isEmpty) return;
    final cleanUpper = clean.toUpperCase();
    final cleanFuzzy = cleanUpper.replaceAll('L', 'I').replaceAll('1', 'I');
    final prefs = await SharedPreferences.getInstance();

    final isLocallyOut = prefs.getBool('pbi_bearing_permanently_out_$clean') == true ||
        prefs.getBool('pbi_bearing_permanently_out_$cleanUpper') == true ||
        prefs.getString('pbi_track_state_$clean') == 'FINAL_OUT' ||
        prefs.getString('pbi_track_state_$cleanUpper') == 'FINAL_OUT' ||
        prefs.getString('pbi_bearing_state_$clean') == 'CURRENTLY_OUT' ||
        prefs.getString('pbi_bearing_state_$cleanUpper') == 'CURRENTLY_OUT';

    final isLocallyIn = prefs.getString('pbi_track_state_$clean') == 'IN' ||
        prefs.getString('pbi_track_state_$cleanUpper') == 'IN' ||
        prefs.getString('pbi_bearing_state_$clean') == 'CURRENTLY_IN' ||
        prefs.getString('pbi_bearing_state_$cleanUpper') == 'CURRENTLY_IN';

    // 0ms instant display if already in loaded list
    final existing = _allBearings.cast<BearingModel?>().firstWhere(
      (b) {
        if (b == null) return false;
        final bId = b.id.trim();
        final bUpper = bId.toUpperCase();
        final bFuzzy = bUpper.replaceAll('L', 'I').replaceAll('1', 'I');
        return bId == clean || bUpper == cleanUpper || bFuzzy == cleanFuzzy;
      },
      orElse: () => null,
    );
    if (existing != null) {
      if (fromScan) {
        if (!mounted) return;
        if (isLocallyOut || existing.state == BearingLifecycleState.currentlyOut) {
          AppSnackBar.showError(
            context,
            'Bearing has already been marked OUT and is permanently decommissioned.',
          );
          _showWarrantyDiagnosticModal(existing, null);
          return;
        } else if (isLocallyIn || existing.state == BearingLifecycleState.currentlyIn) {
          AppSnackBar.showSuccess(
            context,
            'Bearing is already marked IN. Automatically switched to Mark Bearing OUT.',
          );
          Navigator.pushNamed(
            context,
            AppRoutes.outConfirmation,
            arguments: existing.id,
          ).then((_) => _loadUserBearings());
          return;
        } else {
          Navigator.pushNamed(
            context,
            AppRoutes.inConfirmation,
            arguments: existing.id,
          ).then((_) => _loadUserBearings());
          return;
        }
      }
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
        if (verifResult.status == QrVerificationStatus.qrUnknownOrInvalid || verifResult.isInvalid) {
          await AntiFraudService.recordInvalidScan(
            scannedPayload: clean,
            reason: verifResult.errorMessage ?? 'Unrecognized QR code in warranty search',
          );
        }

        final b = model ??
            BearingModel(
              id: verifResult.bearingId ?? clean,
              batchCode: verifResult.batchCode ?? 'BATCH-ACTIVE',
              modelNumber: verifResult.modelNumber ?? 'B1',
              customCategory: verifResult.category,
              productName: verifResult.productName,
              plantLocation: verifResult.plantLocation ?? 'Plant 02 — Chakan Industrial Complex',
              warrantyDurationMonths: verifResult.warrantyDurationMonths ?? 12,
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

        if (fromScan) {
          if (!mounted) return;
          final isOut = isLocallyOut ||
              b.state == BearingLifecycleState.currentlyOut ||
              verifResult.currentLifecycleState == 'CURRENTLY_OUT' ||
              verifResult.currentLifecycleState == 'DECOMMISSIONED' ||
              verifResult.status == QrVerificationStatus.decommissionedOut;

          final isIn = (isLocallyIn ||
              b.state == BearingLifecycleState.currentlyIn ||
              verifResult.currentLifecycleState == 'CURRENTLY_IN' ||
              verifResult.canMarkOut) && !isOut;

          if (isOut) {
            AppSnackBar.showError(
              context,
              'Bearing has already been marked OUT and is permanently decommissioned.',
            );
            _showWarrantyDiagnosticModal(b, verifResult);
            return;
          } else if (isIn) {
            AppSnackBar.showSuccess(
              context,
              'Bearing is already marked IN. Automatically switched to Mark Bearing OUT.',
            );
            Navigator.pushNamed(
              context,
              AppRoutes.outConfirmation,
              arguments: b.id,
            ).then((_) => _loadUserBearings());
            return;
          } else if (verifResult.canMarkIn || b.state == BearingLifecycleState.notActivated) {
            Navigator.pushNamed(
              context,
              AppRoutes.inConfirmation,
              arguments: b.id,
            ).then((_) => _loadUserBearings());
            return;
          }
        }

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

  Future<void> _openQrScanner() async {
    final locked = await AntiFraudService.isScannerLocked();
    if (locked) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          'Scanner locked: You must not scan any false QR codes from now else your ID will be banned.',
        );
      }
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _WarrantyQrScannerModal(
        onCodeScanned: (scannedCode) {
          Navigator.pop(ctx);
          _inputBearingCtrl.text = scannedCode;
          _checkSpecificBearing(scannedCode, fromScan: true);
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
        // Expiring soon (Within remaining 20% of warranty duration)
        if (!b.isExpiringSoon) return false;
      } else if (_activeFilterTab == 3) {
        // Expired
        if (!b.isWarrantyExpired) return false;
      } else if (_activeFilterTab == 4) {
        // Marked Out Under Warranty (Claimable with supplier)
        if (!b.isMarkedOutUnderWarranty) return false;
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
    final expiringSoonCount = _allBearings.where((b) => b.isExpiringSoon).length;
    final expiredCount = _allBearings.where((b) => b.isWarrantyExpired).length;
    final markedOutWarrantyCount = _allBearings.where((b) => b.isMarkedOutUnderWarranty).length;

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
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Track In and Track Out Action Buttons (Scan QR based)
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0D8A4E),
                                foregroundColor: Colors.white,
                                elevation: 1,
                                minimumSize: const Size.fromHeight(46),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(50),
                                ),
                              ),
                              icon: const Icon(Icons.login_rounded, size: 18),
                              label: const Text(
                                'TRACK IN',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                              ),
                              onPressed: () => Navigator.pushNamed(context, AppRoutes.qrScanner),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                                elevation: 1,
                                minimumSize: const Size.fromHeight(46),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(50),
                                ),
                              ),
                              icon: const Icon(Icons.logout_rounded, size: 18),
                              label: const Text(
                                'TRACK OUT',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                              ),
                              onPressed: () => Navigator.pushNamed(context, AppRoutes.qrScanner),
                            ),
                          ),
                        ],
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

                      // Minimalistic Official Warranty Claims Disclaimer Note
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
                        ),
                        child: const Text(
                          'If your product is under warranty, all warranty claims, queries, and related matters must be handled directly with your supplier. Please do not contact the company directly regarding warranty issues. The company will not be responsible for handling such warranty claims.',
                          style: TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 11.5,
                            height: 1.45,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
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
                      const SizedBox(width: 8),
                      _buildPillTab(index: 4, label: 'MARKED OUT ($markedOutWarrantyCount)'),
                    ],
                  ),
                ),
                if (markedOutWarrantyCount > 0) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => Navigator.pushNamed(context, AppRoutes.markedOutWarranty).then((_) => _loadUserBearings()),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.4), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFF25D366),
                              shape: BoxShape.circle,
                            ),
                            child: const WhatsAppIcon(size: 14),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Bearings Marked Out Prior to Expiry',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF166534)),
                                ),
                                Text(
                                  '$markedOutWarrantyCount items remain under active supplier warranty coverage.',
                                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF15803D)),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFF166534)),
                        ],
                      ),
                    ),
                  ),
                ],
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

  Widget _miniChip(String label, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled
            ? AppColors.primary.withValues(alpha: 0.1)
            : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: filled
              ? AppColors.primary.withValues(alpha: 0.25)
              : const Color(0xFFE5E7EB),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: filled ? AppColors.primary : Colors.black54,
          letterSpacing: 0.2,
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
    } else if (item.isMarkedOutUnderWarranty) {
      badgeBg = const Color(0xFFEFF6FF);
      badgeText = const Color(0xFF1D4ED8);
      daysLabel = '$daysLeft DAYS (OUT / CLAIMABLE)';
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpired
              ? const Color(0xFFEF4444).withValues(alpha: 0.25)
              : AppColors.primary.withValues(alpha: 0.12),
          width: 1.2,
        ),
      ),
      child: InkWell(
        onTap: () => _showWarrantyDiagnosticModal(item, null),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Bearing ID + Days badge
              Row(
                children: [
                  const Icon(Icons.qr_code_2_rounded, size: 17, color: AppColors.primary),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      item.id,
                      style: AppTypography.labelMd.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      daysLabel,
                      style: TextStyle(
                        color: badgeText,
                        fontWeight: FontWeight.bold,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Row 2: Category chip + Model chip + State badge
              Wrap(
                spacing: 6,
                runSpacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _miniChip(item.category.toUpperCase(), filled: true),
                  _miniChip(item.modelNumber),
                  IndustrialStatusBadge(statusText: item.stateDisplayString),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              const SizedBox(height: 10),

              // Row 3: Expiry + Actions
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 13, color: Colors.black38),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      item.warrantyExpiryDate != null
                          ? 'Expires: ${item.warrantyExpiryDate!.toLocal().toString().split(' ').first}'
                          : 'Coverage: ${item.warrantyDurationMonths} Months',
                      style: AppTypography.caption.copyWith(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    'DETAILS',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 15, color: AppColors.primary),
                ],
              ),
              if (item.isMarkedOutUnderWarranty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const WhatsAppIcon(size: 16),
                    label: const Text(
                      'CLAIM WARRANTY ON WHATSAPP',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.4),
                    ),
                    onPressed: () => _shareMarkedOutWarrantyOnWhatsApp(item),
                  ),
                ),
              ] else if (isExpired) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCA5A5).withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COMPLETE LIFECYCLE HISTORY',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 0.8,
                          color: const Color(0xFF991B1B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildLifecycleRow('Warranty Start (In Date)', item.firstInDate != null ? _dateFormat.format(item.firstInDate!) : 'N/A'),
                      _buildLifecycleRow('Warranty Expiry Date', item.warrantyExpiryDate != null ? _dateFormat.format(item.warrantyExpiryDate!) : 'N/A'),
                      _buildLifecycleRow('Track Out Date', item.lastOutDate != null ? _dateFormat.format(item.lastOutDate!) : 'Not tracked out'),
                      _buildLifecycleRow('Total Lifecycle Duration', _calculateLifecycleDuration(item)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const WhatsAppIcon(size: 16),
                    label: const Text(
                      'SHARE EXPIRED RECORD ON WHATSAPP',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.4),
                    ),
                    onPressed: () => _shareExpiredWarrantyOnWhatsApp(item),
                  ),
                ),
              ],
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
                                : (bearing.isMarkedOutUnderWarranty
                                    ? 'MARKED OUT (UNDER WARRANTY)'
                                    : (daysLeft == null ? 'ACTIVE COVERAGE' : 'UNDER WARRANTY')),
                            style: TextStyle(
                              color: isExpired
                                  ? const Color(0xFF991B1B)
                                  : (bearing.isMarkedOutUnderWarranty
                                      ? const Color(0xFF1D4ED8)
                                      : (daysLeft != null && daysLeft <= 30 ? const Color(0xFF92400E) : const Color(0xFF166534))),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            daysLeft != null
                                ? (daysLeft >= 0 ? '$daysLeft DAYS LEFT TO CLAIM' : 'EXPIRED ${daysLeft.abs()} DAYS AGO')
                                : '${bearing.warrantyDurationMonths} MONTHS (PENDING ACTIVATION)',
                            style: TextStyle(
                              color: isExpired
                                  ? const Color(0xFF991B1B)
                                  : (bearing.isMarkedOutUnderWarranty
                                      ? const Color(0xFF1D4ED8)
                                      : (daysLeft != null && daysLeft <= 30 ? const Color(0xFF92400E) : const Color(0xFF166534))),
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
              Builder(
                builder: (_) {
                  final resolvedModel = (bearing.modelNumber.isNotEmpty && bearing.modelNumber != 'PBI-6204-ZZ')
                      ? bearing.modelNumber
                      : 'B1';
                  final resolvedItem = ItemMasterRepository().findByCode(resolvedModel);
                  final resolvedCategory = (bearing.category != 'Deep Groove Ball Bearing' || resolvedModel != 'B1')
                      ? bearing.category
                      : (resolvedItem?.category ?? 'Ball Bearing');
                  final resolvedProduct = bearing.productName ?? resolvedItem?.itemName ?? 'Bearing 1(Ball Bearing)';

                  return Column(
                    children: [
                      _buildModalRow('Bearing Category', resolvedCategory, isBold: true),
                      const Divider(),
                      _buildModalRow('Model / Part No', resolvedModel, isMono: true),
                      const Divider(),
                      _buildModalRow('Assigned Product', resolvedProduct),
                    ],
                  );
                },
              ),
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

              // Bearing Out Action Button (Requires scanning physical QR code)
              if (bearing.state == BearingLifecycleState.currentlyIn) ...[
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
                      Navigator.pushNamed(context, AppRoutes.qrScanner);
                    },
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text(
                      'SCAN QR TO TRACK OUT',
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

              // Minimalistic Warranty Claims Disclaimer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1), width: 1.0),
                ),
                child: const Text(
                  'If your product is under warranty, all warranty claims, queries, and related matters must be handled directly with your supplier. Please do not contact the company directly regarding warranty issues. The company will not be responsible for handling such warranty claims.',
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 11,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (bearing.isMarkedOutUnderWarranty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const WhatsAppIcon(size: 16),
                    label: const Text(
                      'CLAIM WARRANTY ON WHATSAPP',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.4),
                    ),
                    onPressed: () => _shareMarkedOutWarrantyOnWhatsApp(bearing),
                  ),
                ),
              ] else if (isExpired) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5).withValues(alpha: 0.6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COMPLETE LIFECYCLE HISTORY',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 0.8,
                          color: const Color(0xFF991B1B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildLifecycleRow('Warranty Start (In Date)', bearing.firstInDate != null ? _dateFormat.format(bearing.firstInDate!) : 'N/A'),
                      _buildLifecycleRow('Warranty Expiry Date', bearing.warrantyExpiryDate != null ? _dateFormat.format(bearing.warrantyExpiryDate!) : 'N/A'),
                      _buildLifecycleRow('Track Out Date', bearing.lastOutDate != null ? _dateFormat.format(bearing.lastOutDate!) : 'Not tracked out'),
                      _buildLifecycleRow('Total Lifecycle Duration', _calculateLifecycleDuration(bearing)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: const WhatsAppIcon(size: 16),
                    label: const Text(
                      'SHARE EXPIRED RECORD ON WHATSAPP',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.4),
                    ),
                    onPressed: () => _shareExpiredWarrantyOnWhatsApp(bearing),
                  ),
                ),
              ],
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
                    errorBuilder: (context, error) {
                      final msg = error.errorDetails?.message ?? error.toString();
                      if (msg.contains('already running') ||
                          error.errorCode == MobileScannerErrorCode.controllerAlreadyInitialized) {
                        return const SizedBox.shrink();
                      }
                      return Center(
                        child: Text(
                          'Initializing scanner...',
                          style: AppTypography.bodySm.copyWith(color: Colors.white70),
                        ),
                      );
                    },
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
