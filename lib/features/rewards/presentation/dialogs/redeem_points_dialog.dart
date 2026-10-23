import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_dimensions.dart';
import '../../../../core/widgets/industrial_button.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../domain/models/reward_models.dart';
import '../../data/services/reward_service.dart';

/// Pivot Bearings India - Redeem Points Dialog
///
/// Prominently displays:
/// 1. Active conversion rate: "10 Points = ₹X.XX"
/// 2. Mandatory T&C: "Pivot Bearings reserves the right to modify, adjust, or change the reward point conversion value at any time without prior notice."
/// 3. UPI / Bank Account details capture
class RedeemPointsDialog extends StatefulWidget {
  final RewardProfile profile;
  final VoidCallback onSuccess;

  const RedeemPointsDialog({
    super.key,
    required this.profile,
    required this.onSuccess,
  });

  @override
  State<RedeemPointsDialog> createState() => _RedeemPointsDialogState();
}

class _RedeemPointsDialogState extends State<RedeemPointsDialog> {
  final _formKey = GlobalKey<FormState>();

  String _payoutMethod = 'UPI'; // 'UPI' or 'BANK_TRANSFER'
  final TextEditingController _pointsCtrl = TextEditingController();
  final TextEditingController _upiCtrl = TextEditingController();

  // Bank Account Fields
  final TextEditingController _holderNameCtrl = TextEditingController();
  final TextEditingController _bankNameCtrl = TextEditingController();
  final TextEditingController _accountNumberCtrl = TextEditingController();
  final TextEditingController _confirmAccountCtrl = TextEditingController();
  final TextEditingController _ifscCtrl = TextEditingController();

  bool _isSubmitting = false;
  double _calculatedInr = 0.0;

  @override
  void initState() {
    super.initState();
    // Default to min redemption or full balance if lower
    final defaultPts = widget.profile.currentBalancePoints >= widget.profile.minRedemptionPoints
        ? widget.profile.minRedemptionPoints
        : widget.profile.currentBalancePoints;

    _pointsCtrl.text = defaultPts.toString();
    _recalculateInr();
  }

  @override
  void dispose() {
    _pointsCtrl.dispose();
    _upiCtrl.dispose();
    _holderNameCtrl.dispose();
    _bankNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _confirmAccountCtrl.dispose();
    _ifscCtrl.dispose();
    super.dispose();
  }

  void _recalculateInr() {
    final pts = int.tryParse(_pointsCtrl.text.trim()) ?? 0;
    setState(() {
      _calculatedInr = widget.profile.calculateInrForPoints(pts);
    });
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final pts = int.tryParse(_pointsCtrl.text.trim()) ?? 0;
    if (pts > widget.profile.currentBalancePoints) {
      AppSnackBar.showError(context, 'You cannot redeem more than your available balance (${widget.profile.currentBalancePoints} pts).');
      return;
    }

    if (pts < widget.profile.minRedemptionPoints) {
      AppSnackBar.showError(context, 'Minimum redemption threshold is ${widget.profile.minRedemptionPoints} points.');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final res = await RewardService.submitRedemptionRequest(
        points: pts,
        payoutMethod: _payoutMethod,
        upiId: _payoutMethod == 'UPI' ? _upiCtrl.text.trim() : null,
        bankAccountNumber: _payoutMethod == 'BANK_TRANSFER' ? _accountNumberCtrl.text.trim() : null,
        bankIfsc: _payoutMethod == 'BANK_TRANSFER' ? _ifscCtrl.text.trim().toUpperCase() : null,
        bankAccountHolderName: _payoutMethod == 'BANK_TRANSFER' ? _holderNameCtrl.text.trim() : null,
        bankName: _payoutMethod == 'BANK_TRANSFER' ? _bankNameCtrl.text.trim() : null,
      );

      if (mounted) {
        setState(() => _isSubmitting = false);
        if (res['success'] == true) {
          Navigator.of(context).pop();
          AppSnackBar.showSuccess(
            context,
            res['message']?.toString() ?? 'Redemption request submitted successfully!',
          );
          widget.onSuccess();
        } else {
          AppSnackBar.showError(
            context,
            res['message']?.toString() ?? 'Failed to submit request.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppSnackBar.showError(context, 'Error submitting redemption: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusDefault),
        side: const BorderSide(color: AppColors.primary, width: 2.0),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'REDEEM REWARD POINTS',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Available Balance: ${widget.profile.currentBalancePoints} Points',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.primary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Prominent Rate Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary, width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ACTIVE CONVERSION RATE:',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.profile.rateDisplayString,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Points to Redeem Input & Quick Selector
                Text(
                  'ENTER POINTS TO REDEEM (Min: ${widget.profile.minRedemptionPoints} pts)',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _pointsCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _recalculateInr(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'e.g. 50',
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
                  ),
                  validator: (val) {
                    final p = int.tryParse(val?.trim() ?? '');
                    if (p == null || p <= 0) return 'Enter a valid point amount';
                    if (p < widget.profile.minRedemptionPoints) {
                      return 'Minimum redemption is ${widget.profile.minRedemptionPoints} points';
                    }
                    if (p > widget.profile.currentBalancePoints) {
                      return 'Exceeds available balance (${widget.profile.currentBalancePoints} pts)';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 8),

                // Quick Chips
                Wrap(
                  spacing: 6,
                  children: [
                    _buildQuickChip(50),
                    _buildQuickChip(100),
                    _buildQuickChip(200),
                    InkWell(
                      onTap: () {
                        _pointsCtrl.text = widget.profile.currentBalancePoints.toString();
                        _recalculateInr();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'MAX BALANCE',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Live INR Equivalent Box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF0D8A4E), width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Total Cash Payout (INR):',
                        style: TextStyle(
                          color: Color(0xFF1B5E20),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '₹${_calculatedInr.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFF1B5E20),
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Payout Method Selector
                const Text(
                  'SELECT PAYOUT METHOD',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _payoutMethod = 'UPI'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _payoutMethod == 'UPI' ? AppColors.primary : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.primary, width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              'UPI TRANSFER',
                              style: TextStyle(
                                color: _payoutMethod == 'UPI' ? Colors.white : AppColors.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _payoutMethod = 'BANK_TRANSFER'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _payoutMethod == 'BANK_TRANSFER' ? AppColors.primary : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.primary, width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              'BANK TRANSFER',
                              style: TextStyle(
                                color: _payoutMethod == 'BANK_TRANSFER' ? Colors.white : AppColors.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Method Fields
                if (_payoutMethod == 'UPI') ...[
                  _buildLabel('UPI ID (GPay, PhonePe, Paytm, BHIM)'),
                  TextFormField(
                    controller: _upiCtrl,
                    decoration: _inputDeco('e.g. 9898857198@paytm or name@oksbi'),
                    validator: (v) {
                      if (_payoutMethod == 'UPI' && (v == null || v.trim().isEmpty)) {
                        return 'Enter a valid UPI ID';
                      }
                      return null;
                    },
                  ),
                ] else ...[
                  _buildLabel('Account Holder Full Name'),
                  TextFormField(
                    controller: _holderNameCtrl,
                    decoration: _inputDeco('As registered with bank'),
                    validator: (v) => _payoutMethod == 'BANK_TRANSFER' && (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  _buildLabel('Bank Name'),
                  TextFormField(
                    controller: _bankNameCtrl,
                    decoration: _inputDeco('e.g. State Bank of India, HDFC Bank'),
                    validator: (v) => _payoutMethod == 'BANK_TRANSFER' && (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  _buildLabel('Account Number'),
                  TextFormField(
                    controller: _accountNumberCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDeco('Bank Account Number'),
                    validator: (v) => _payoutMethod == 'BANK_TRANSFER' && (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  _buildLabel('Confirm Account Number'),
                  TextFormField(
                    controller: _confirmAccountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDeco('Re-enter Bank Account Number'),
                    validator: (v) {
                      if (_payoutMethod == 'BANK_TRANSFER') {
                        if (v != _accountNumberCtrl.text) {
                          return 'Account numbers do not match';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildLabel('Bank IFSC Code'),
                  TextFormField(
                    controller: _ifscCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _inputDeco('e.g. SBIN0001234'),
                    validator: (v) => _payoutMethod == 'BANK_TRANSFER' && (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ],

                const SizedBox(height: 16),

                // Terms & Conditions Disclaimer
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black26, width: 1.0),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.profile.termsAndConditions,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black87,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Submit Button
                IndustrialButton(
                  label: _isSubmitting ? 'PROCESSING...' : 'CONFIRM REDEMPTION (₹${_calculatedInr.toStringAsFixed(2)})',
                  isLoading: _isSubmitting,
                  onPressed: _isSubmitting ? null : _handleSubmit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickChip(int pts) {
    return InkWell(
      onTap: () {
        _pointsCtrl.text = pts.toString();
        _recalculateInr();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.primary, width: 1.0),
        ),
        child: Text(
          '$pts pts',
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
