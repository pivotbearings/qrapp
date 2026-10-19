import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/auth/auth_controller.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/industrial_app_bar.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/industrial_card.dart';
import '../../../../core/widgets/industrial_status_badge.dart';
import '../../../../core/widgets/whatsapp_icon.dart';

import '../../data/models/bearing_model.dart';
import '../../data/repositories/bearing_repository.dart';
import '../widgets/bearing_out_email_dialog.dart';

class OutResultScreen extends StatefulWidget {
  final String bearingId;

  const OutResultScreen({super.key, required this.bearingId});

  @override
  State<OutResultScreen> createState() => _OutResultScreenState();
}

class _OutResultScreenState extends State<OutResultScreen> {
  BearingModel? _bearing;

  @override
  void initState() {
    super.initState();
    _loadBearing();
  }

  Future<void> _loadBearing() async {
    final b = await BearingRepositoryImpl().getBearingById(widget.bearingId);
    if (mounted) {
      setState(() {
        _bearing = b;
      });
    }
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final inDate = _bearing?.lastInDate ?? _bearing?.firstInDate;
    final inDateStr = inDate != null
        ? '${_formatDate(inDate)}, ${inDate.hour.toString().padLeft(2, '0')}:${inDate.minute.toString().padLeft(2, '0')}'
        : 'Session Recorded';
    final outDateStr = '${_formatDate(now)}, ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final duration = inDate != null ? now.difference(inDate) : const Duration(minutes: 0);
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final mins = duration.inMinutes % 60;
    final cycleSummary = inDate != null ? '$days Days, $hours Hours, $mins Mins' : 'Cycle Closed';
    final totalDurationHeader = inDate != null ? 'Total Duration: $days Days' : 'Cycle Successfully Closed';

    final expiry = _bearing?.warrantyExpiryDate;
    final isWarrantyValid = !(_bearing?.isWarrantyExpired ?? false);
    final remainingDays = expiry?.difference(now).inDays;
    final warrantyStatusStr = expiry != null
        ? '${isWarrantyValid ? "Active" : "Expired"} (Valid until ${_formatDate(expiry)})'
        : 'Active Standard Warranty';
    final remainingBalanceStr = remainingDays != null
        ? (remainingDays > 0 ? '$remainingDays Days' : '0 Days (Expired)')
        : 'Active Balance';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const IndustrialAppBar(title: 'Bearing Lifecycle'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.gutterMobile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bearing Marked OUT', style: AppTypography.headlineLgMobile),
              const SizedBox(height: AppDimensions.spaceMd),

              // Hero Cycle Closed Card
              IndustrialCard(
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.primary, width: 2.0),
                        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                      ),
                      child: const Center(
                        child: Icon(Icons.verified, size: 28, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: AppDimensions.spaceMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const IndustrialStatusBadge(statusText: '[REMOVAL CONFIRMED — DECOMMISSIONED]'),
                          const SizedBox(height: 4),
                          Text(
                            totalDurationHeader,
                            style: AppTypography.headlineSm,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.spaceMd),

              // Details & Telemetry Card
              IndustrialCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildRow('Bearing ID', widget.bearingId, isMono: true),
                    const Divider(),
                    _buildRow('Installation (IN) Timestamp', inDateStr),
                    const Divider(),
                    _buildRow('Removal (OUT) Timestamp', outDateStr),
                    const Divider(),
                    _buildRow('Calculated Operating Cycle', cycleSummary, isHeadline: true),
                    const Divider(),
                    _buildRow('Warranty Status at Removal', warrantyStatusStr),
                    const Divider(),
                    _buildRow('Remaining Warranty Balance', remainingBalanceStr, isHeadline: true),
                    const SizedBox(height: AppDimensions.spaceSm),
                    const Text('Terminal Lifecycle Rule', style: AppTypography.caption),
                    const SizedBox(height: 2),
                    const Text(
                      'Lifecycle permanently concluded. Once marked OUT, re-installation is strictly prohibited. This bearing is now retired.',
                      style: AppTypography.bodyMd,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppDimensions.spaceLg),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                  ),
                  elevation: 2,
                ),
                onPressed: () {
                  BearingOutEmailDialog.show(
                    context,
                    bearingId: widget.bearingId,
                    modelNumber: _bearing?.modelNumber ?? 'PBI-Standard',
                    category: _bearing?.category ?? 'Deep Groove Ball Bearing',
                    inDate: inDate,
                    outDate: now,
                    durationString: cycleSummary,
                    warrantyPlan: _bearing?.warrantyDurationMonths != null
                        ? '${_bearing!.warrantyDurationMonths} Months Industrial Warranty'
                        : 'Standard Warranty',
                    warrantyExpiry: _bearing?.warrantyExpiryDate != null
                        ? _formatDate(_bearing!.warrantyExpiryDate!)
                        : 'Active / Calculated',
                    isUnderWarranty: _bearing != null ? !_bearing!.isWarrantyExpired : true,
                  );
                },
                icon: const Icon(Icons.mark_email_read_outlined, size: 20),
                label: const Text(
                  'Email the Information',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),

              const SizedBox(height: AppDimensions.spaceSm),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
                  ),
                  elevation: 2,
                ),
                onPressed: () => _shareViaWhatsApp(
                  inDateStr: inDateStr,
                  outDateStr: outDateStr,
                  cycleSummary: cycleSummary,
                  warrantyStatusStr: warrantyStatusStr,
                ),
                icon: const WhatsAppIcon(size: 20, color: Colors.white),
                label: const Text(
                  'Send via WhatsApp',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                ),
              ),

              const SizedBox(height: AppDimensions.spaceSm),

              IndustrialButton(
                label: 'Return to Home',
                icon: Icons.home,
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                  context,
                  AppRoutes.customerHome,
                  (route) => false,
                ),
              ),

              const SizedBox(height: AppDimensions.spaceSm),

              IndustrialButton.secondary(
                label: 'Scan Another Bearing',
                icon: Icons.qr_code_scanner,
                onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.qrScanner),
              ),
              const SizedBox(height: AppDimensions.spaceXl),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareViaWhatsApp({
    required String inDateStr,
    required String outDateStr,
    required String cycleSummary,
    required String warrantyStatusStr,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final storedNotes = prefs.getString('pbi_bearing_notes_${widget.bearingId}');
    final notesLine = (storedNotes != null && storedNotes.trim().isNotEmpty)
        ? '\n• *Notes:* ${storedNotes.trim()}'
        : '';

    final message = '''
*PIVOT BEARINGS INDIA - BEARING LIFECYCLE SUMMARY*
━━━━━━━━━━━━━━━━━━━━━━━━━
• *Bearing ID:* ${widget.bearingId}
• *Model Number:* ${_bearing?.modelNumber ?? 'PBI-Standard'}
• *Bearing In:* $inDateStr
• *Bearing Out:* $outDateStr
• *Total Duration:* $cycleSummary
• *Warranty:* $warrantyStatusStr
• *Status:* Decommissioned / Final Out$notesLine
━━━━━━━━━━━━━━━━━━━━━━━━━
Official Warranty Telemetry Record
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
      } catch (_) {}
    } else {
      final controller = TextEditingController();
      if (!mounted) return;
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
                'Send via WhatsApp',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the Authorised Person Mobile Number to send this bearing lifecycle summary:',
                style: AppTypography.bodySm,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Authorised Mobile Number',
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
                } catch (_) {}
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Send on WhatsApp'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildRow(String label, String value, {bool isHeadline = false, bool isMono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.labelSm),
          Text(
            value,
            style: isHeadline
                ? AppTypography.headlineSm
                : (isMono ? AppTypography.mono : AppTypography.labelMd),
          ),
        ],
      ),
    );
  }
}
