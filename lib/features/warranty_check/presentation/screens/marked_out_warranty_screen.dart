import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/auth/auth_controller.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../../core/widgets/industrial_status_badge.dart';
import '../../../bearing_verification/data/models/bearing_model.dart';
import '../../../bearing_verification/data/repositories/bearing_repository.dart';
import '../../../item_master/data/repositories/item_master_repository.dart';

/// Screen displaying all bearings that were marked OUT prior to warranty expiration,
/// allowing customers to directly claim warranty with their supplier via WhatsApp.
class MarkedOutWarrantyScreen extends StatefulWidget {
  const MarkedOutWarrantyScreen({super.key});

  @override
  State<MarkedOutWarrantyScreen> createState() => _MarkedOutWarrantyScreenState();
}

class _MarkedOutWarrantyScreenState extends State<MarkedOutWarrantyScreen> {
  final BearingRepository _bearingRepo = BearingRepositoryImpl();
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy, HH:mm');
  final DateFormat _dateOnlyFormat = DateFormat('dd MMM yyyy');

  List<BearingModel> _claimableBearings = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadClaimableBearings();
  }

  Future<void> _loadClaimableBearings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final all = await _bearingRepo.getAllBearings();
      // Filter for bearings marked out before warranty expiration
      final claimable = all.where((b) => b.isMarkedOutUnderWarranty).toList();

      if (mounted) {
        setState(() {
          _claimableBearings = claimable;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load marked-out bearings: $e';
          _isLoading = false;
        });
      }
    }
  }

  String _calculateDuration(BearingModel b) {
    final inDate = b.lastInDate ?? b.firstInDate;
    final outDate = b.lastOutDate ?? DateTime.now();
    if (inDate == null) return '0 Secs';

    final diff = outDate.difference(inDate);
    final totalSec = diff.inSeconds;
    if (totalSec < 0) return '0 Secs';
    if (totalSec < 60) {
      return '$totalSec ${totalSec == 1 ? "Sec" : "Secs"}';
    }
    final totalMin = diff.inMinutes;
    final remSec = totalSec % 60;
    if (totalMin < 60) {
      if (remSec == 0) return '$totalMin ${totalMin == 1 ? "Min" : "Mins"}';
      return '$totalMin ${totalMin == 1 ? "Min" : "Mins"}, $remSec ${remSec == 1 ? "Sec" : "Secs"}';
    }
    final totalHours = diff.inHours;
    final remMin = totalMin % 60;
    if (totalHours < 24) {
      if (remSec == 0) return '$totalHours ${totalHours == 1 ? "Hour" : "Hours"}, $remMin ${remMin == 1 ? "Min" : "Mins"}';
      return '$totalHours ${totalHours == 1 ? "Hour" : "Hours"}, $remMin ${remMin == 1 ? "Min" : "Mins"}, $remSec ${remSec == 1 ? "Sec" : "Secs"}';
    }
    final days = diff.inDays;
    final remHours = totalHours % 24;
    return '$days ${days == 1 ? "Day" : "Days"}, $remHours ${remHours == 1 ? "Hour" : "Hours"}, $remMin ${remMin == 1 ? "Min" : "Mins"}, $remSec ${remSec == 1 ? "Sec" : "Secs"}';
  }

  Future<void> _claimWarrantyViaWhatsApp(BearingModel b) async {
    final inDate = b.lastInDate ?? b.firstInDate;
    final inDateStr = inDate != null ? _dateFormat.format(inDate) : 'Session Recorded';
    final outDateStr = b.lastOutDate != null ? _dateFormat.format(b.lastOutDate!) : _dateFormat.format(DateTime.now());
    final durationStr = _calculateDuration(b);

    var modelCode = b.modelNumber;
    if (modelCode.isEmpty || modelCode == 'PBI-Standard' || modelCode == 'PBI-6204-ZZ') {
      final b1Item = ItemMasterRepository().findByCode('B1');
      if (b1Item != null) {
        modelCode = 'B1';
      }
    }
    final item = ItemMasterRepository().findByCode(modelCode) ?? ItemMasterRepository().findByCode('B1');
    final productName = b.productName ?? item?.itemName ?? 'Bearing 1(Ball Bearing)';
    final expiry = b.warrantyExpiryDate;
    final expiryStr = expiry != null ? _dateOnlyFormat.format(expiry) : 'Active Coverage';
    final daysLeft = b.daysLeftToExpiry ?? 0;

    final prefs = await SharedPreferences.getInstance();
    final storedNotes = prefs.getString('pbi_bearing_notes_${b.id}');
    final notesLine = (storedNotes != null && storedNotes.trim().isNotEmpty)
        ? '\n• *Customer Notes:* ${storedNotes.trim()}'
        :   '';

    final message = '''
*PIVOT BEARINGS INDIA - WARRANTY CLAIM REQUEST*
━━━━━━━━━━━━━━━━━━━━━━━━━
• *Bearing QR Serial:* ${b.id}
• *Model / Part No:* $modelCode
• *Assigned Product:* $productName
• *Bearing In (Installed):* $inDateStr
• *Bearing Out (Removed):* $outDateStr
• *Total Operating Duration:* $durationStr
• *Warranty Expiry Date:* $expiryStr
• *Remaining Warranty:* $daysLeft Days Remaining to Claim$notesLine
• *Notice:* Bearing removed prior to warranty expiry. Requesting supplier inspection and replacement under official manufacturer warranty terms.
━━━━━━━━━━━━━━━━━━━━━━━━━
Official Authorized Warranty Claim Record - Pivot Bearings India
'''.trim();

    final auth = AuthController.instance;
    String? authNumber;
    if (auth.authorisedNumbers.isNotEmpty) {
      authNumber = auth.authorisedNumbers.first;
    } else {
      authNumber = prefs.getString('pbi_authorised_number');
    }

    if (authNumber != null && authNumber.trim().isNotEmpty) {
      var cleanNum = authNumber.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanNum.length == 10) cleanNum = '91$cleanNum';
      final uri = Uri.parse('https://wa.me/$cleanNum?text=${Uri.encodeComponent(message)}');
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) AppSnackBar.showError(context, 'Could not open WhatsApp.');
      }
    } else {
      _showWhatsAppNumberDialog(message);
    }
  }

  void _showWhatsAppNumberDialog(String message) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
          side: const BorderSide(color: Color(0xFF25D366), width: 2.0),
        ),
        title: Row(
          children: const [
            Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 24),
            SizedBox(width: 8),
            Text(
              'Claim on WhatsApp',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the Supplier / Authorised Mobile Number to send your warranty claim request:',
              style: AppTypography.bodySm,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Supplier WhatsApp Number',
                hintText: 'e.g. +91 98988 57198',
                prefixIcon: const Icon(Icons.phone, color: Color(0xFF25D366)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () async {
              final raw = controller.text.trim();
              Navigator.pop(ctx);
              var cleanNum = raw.replaceAll(RegExp(r'[^0-9]'), '');
              if (cleanNum.length == 10) cleanNum = '91$cleanNum';
              final uri = cleanNum.isNotEmpty
                  ? Uri.parse('https://wa.me/$cleanNum?text=${Uri.encodeComponent(message)}')
                  : Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {
                if (mounted) AppSnackBar.showError(context, 'Could not open WhatsApp.');
              }
            },
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send Claim on WhatsApp'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const IndustrialAppBar(title: 'Claim Warranty (Marked Out)'),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _loadClaimableBearings,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppDimensions.gutterMobile),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Super Clean & Minimalistic Supplier Disclaimer
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'If your product is under warranty, all warranty claims, queries, and related matters must be handled directly with your supplier. Please do not contact the company directly regarding warranty issues. The company will not be responsible for handling such warranty claims.',
                              style: AppTypography.caption.copyWith(
                                color: Colors.black87,
                                height: 1.45,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header Summary Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.assignment_turned_in_rounded, size: 22, color: AppColors.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Marked Out Bearings Under Warranty',
                                  style: AppTypography.labelMd.copyWith(fontWeight: FontWeight.bold, color: AppColors.primary),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Removed from equipment prior to expiry — Claim ready',
                                  style: AppTypography.caption.copyWith(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_claimableBearings.length} READY',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // State Handlers: Loading / Error / Empty / List
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.0)),
                      )
                    else if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                          border: Border.all(color: const Color(0xFFEF4444)),
                        ),
                        child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFF991B1B))),
                      )
                    else if (_claimableBearings.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.verified_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'No Marked Out Bearings Under Warranty',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'When a bearing is tracked out before its warranty expires, it will appear here with an instant WhatsApp claim action.',
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _claimableBearings.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final bearing = _claimableBearings[index];
                          return _buildClaimableBearingCard(bearing);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClaimableBearingCard(BearingModel b) {
    final inDate = b.lastInDate ?? b.firstInDate;
    final inDateStr = inDate != null ? _dateFormat.format(inDate) : 'Session Recorded';
    final outDateStr = b.lastOutDate != null ? _dateFormat.format(b.lastOutDate!) : 'Marked Out';
    final durationStr = _calculateDuration(b);

    var modelCode = b.modelNumber;
    if (modelCode.isEmpty || modelCode == 'PBI-Standard' || modelCode == 'PBI-6204-ZZ') {
      final b1Item = ItemMasterRepository().findByCode('B1');
      if (b1Item != null) {
        modelCode = 'B1';
      }
    }
    final item = ItemMasterRepository().findByCode(modelCode) ?? ItemMasterRepository().findByCode('B1');
    final productName = b.productName ?? item?.itemName ?? 'Bearing 1(Ball Bearing)';
    final expiry = b.warrantyExpiryDate;
    final expiryStr = expiry != null ? _dateOnlyFormat.format(expiry) : 'Active Coverage';
    final daysLeft = b.daysLeftToExpiry ?? 0;

    return IndustrialCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Serial & Status Badge Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('BEARING SERIAL', style: AppTypography.caption.copyWith(fontSize: 10, letterSpacing: 0.8)),
                    const SizedBox(height: 2),
                    Text(b.id, style: AppTypography.headlineSm.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              const IndustrialStatusBadge(
                statusText: 'OUT (UNDER WARRANTY)',
                icon: Icons.shield_outlined,
                isSuccess: true,
              ),
            ],
          ),
          const Divider(height: 20),

          // Specs Grid / Rows
          _buildDetailRow('Model / Part No', modelCode, isMono: true),
          const SizedBox(height: 6),
          _buildDetailRow('Assigned Product', productName),
          const SizedBox(height: 6),
          _buildDetailRow('Bearing In (Installed)', inDateStr),
          const SizedBox(height: 6),
          _buildDetailRow('Bearing Out (Removed)', outDateStr),
          const SizedBox(height: 6),
          _buildDetailRow('Total Operating Duration', durationStr, isBold: true),
          const SizedBox(height: 6),
          _buildDetailRow('Warranty Expiry Date', expiryStr),
          const SizedBox(height: 6),
          _buildDetailRow('Remaining Coverage', '$daysLeft Days Remaining to Claim', isHighlight: true),

          const SizedBox(height: 16),

          // Direct WhatsApp Warranty Claim Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                elevation: 1,
              ),
              onPressed: () => _claimWarrantyViaWhatsApp(b),
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: const Text(
                'CLAIM WARRANTY ON WHATSAPP',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false, bool isMono = false, bool isHighlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: Colors.black54, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold || isHighlight ? FontWeight.bold : FontWeight.w600,
              fontFamily: isMono ? 'monospace' : null,
              color: isHighlight ? const Color(0xFF0D8A4E) : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
