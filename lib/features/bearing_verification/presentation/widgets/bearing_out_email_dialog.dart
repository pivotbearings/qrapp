import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/constants/app_typography.dart';

/// Clean, minimalist confirmation dialog summarising bearing lifecycle with direct Resend email delivery
class BearingOutEmailDialog extends StatefulWidget {
  final String bearingId;
  final String modelNumber;
  final String category;
  final DateTime? inDate;
  final DateTime? outDate;
  final String durationString;
  final String warrantyPlan;
  final String warrantyExpiry;
  final bool isUnderWarranty;
  final List<Map<String, dynamic>> cycleRecords;
  final VoidCallback? onDismissed;

  const BearingOutEmailDialog({
    super.key,
    required this.bearingId,
    required this.modelNumber,
    required this.category,
    required this.inDate,
    required this.outDate,
    required this.durationString,
    required this.warrantyPlan,
    required this.warrantyExpiry,
    required this.isUnderWarranty,
    this.cycleRecords = const [],
    this.onDismissed,
  });

  /// Static helper to trigger the dialog easily from any screen
  static Future<void> show(
    BuildContext context, {
    required String bearingId,
    required String modelNumber,
    required String category,
    required DateTime? inDate,
    required DateTime? outDate,
    required String durationString,
    required String warrantyPlan,
    required String warrantyExpiry,
    required bool isUnderWarranty,
    List<Map<String, dynamic>> cycleRecords = const [],
    VoidCallback? onDismissed,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => BearingOutEmailDialog(
        bearingId: bearingId,
        modelNumber: modelNumber,
        category: category,
        inDate: inDate,
        outDate: outDate,
        durationString: durationString,
        warrantyPlan: warrantyPlan,
        warrantyExpiry: warrantyExpiry,
        isUnderWarranty: isUnderWarranty,
        cycleRecords: cycleRecords,
        onDismissed: onDismissed,
      ),
    );
  }

  @override
  State<BearingOutEmailDialog> createState() => _BearingOutEmailDialogState();
}

class _BearingOutEmailDialogState extends State<BearingOutEmailDialog> {
  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '—';
    return dt.toLocal().toString().split('.').first;
  }

  @override
  Widget build(BuildContext context) {
    final inTimeFormatted = _formatDateTime(widget.inDate);
    final outTimeFormatted = _formatDateTime(widget.outDate ?? DateTime.now());

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusMedium),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row with Title and Close
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFEF4444).withAlpha(80)),
                        ),
                        child: const Icon(Icons.logout_rounded, color: Color(0xFFDC2626), size: 18),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'BEARING OUT CONFIRMATION',
                        style: AppTypography.labelMd.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: AppColors.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Colors.black54),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onDismissed?.call();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Prominent Hero Card: Bearing ID & Total Usage Duration
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMicro),
                  border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
                ),
                child: Column(
                  children: [
                    Text(
                      widget.bearingId,
                      style: AppTypography.headlineSm.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.durationString,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFDC2626),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Detail Rows
              _buildDetailRow('Bearing Category', widget.category),
              _buildDetailRow('Model Number', widget.modelNumber, isMono: true),
              _buildDetailRow('Bearing In (Installed)', inTimeFormatted),
              _buildDetailRow('Bearing Out (Decommissioned)', outTimeFormatted, isHighlight: true),
              _buildDetailRow('Coverage Plan', widget.warrantyPlan),
              _buildDetailRow('Warranty Expiry Date', widget.warrantyExpiry, isMono: true),
              _buildDetailRow(
                'Warranty Status',
                widget.isUnderWarranty ? 'UNDER WARRANTY' : 'EXPIRED',
                valueColor: widget.isUnderWarranty ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              ),

              // Cycle records preview if multiple cycles exist
              if (widget.cycleRecords.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.black12, width: 0.8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PREVIOUS LIFECYCLE RECORDS (${widget.cycleRecords.length})',
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...widget.cycleRecords.take(3).map((c) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Cycle #${c['cycle_number'] ?? "—"}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                Text(c['duration'] ?? '—', style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary, width: 1.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onDismissed?.call();
                      },
                      child: const Text(
                        'CLOSE',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isMono = false, bool isHighlight = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.caption.copyWith(color: Colors.black54, fontSize: 11)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
                color: valueColor ?? (isHighlight ? const Color(0xFFDC2626) : AppColors.primary),
                fontFamily: isMono ? 'monospace' : null,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
