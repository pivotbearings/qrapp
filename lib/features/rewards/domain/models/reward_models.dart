/// Pivot Bearings India - Reward Points & Redemption Domain Models
library;

class RewardProfile {
  final int currentBalancePoints;
  final double currentBalanceInr;
  final int pendingRedemptionPoints;
  final double pendingRedemptionInr;
  final int totalPointsEarned;
  final int totalPointsRedeemed;
  final int pointsBaseUnit;
  final double inrPerBaseUnit;
  final double rateMultiplier;
  final String rateDisplayString;
  final int minRedemptionPoints;
  final double minRedemptionInr;
  final bool isEnabled;
  final bool isRewardEligible;
  final String termsAndConditions;

  const RewardProfile({
    required this.currentBalancePoints,
    required this.currentBalanceInr,
    required this.pendingRedemptionPoints,
    required this.pendingRedemptionInr,
    required this.totalPointsEarned,
    required this.totalPointsRedeemed,
    required this.pointsBaseUnit,
    required this.inrPerBaseUnit,
    required this.rateMultiplier,
    required this.rateDisplayString,
    required this.minRedemptionPoints,
    required this.minRedemptionInr,
    required this.isEnabled,
    this.isRewardEligible = true,
    required this.termsAndConditions,
  });

  factory RewardProfile.defaultProfile() {
    return const RewardProfile(
      currentBalancePoints: 0,
      currentBalanceInr: 0.0,
      pendingRedemptionPoints: 0,
      pendingRedemptionInr: 0.0,
      totalPointsEarned: 0,
      totalPointsRedeemed: 0,
      pointsBaseUnit: 10,
      inrPerBaseUnit: 10.0,
      rateMultiplier: 1.0,
      rateDisplayString: '10 Points = ₹10.00',
      minRedemptionPoints: 50,
      minRedemptionInr: 50.0,
      isEnabled: true,
      isRewardEligible: true,
      termsAndConditions:
          'Pivot Bearings reserves the right to modify, adjust, or change the reward point conversion value (Points to INR rate) and program rules at any time without prior notice.',
    );
  }

  factory RewardProfile.fromJson(Map<String, dynamic> json) {
    final baseUnit = (json['points_base_unit'] as num?)?.toInt() ?? 10;
    final inrPerBase = (json['inr_per_base_unit'] as num?)?.toDouble() ?? 10.0;
    final mult = (json['rate_multiplier'] as num?)?.toDouble() ?? (inrPerBase / (baseUnit > 0 ? baseUnit : 1));

    return RewardProfile(
      currentBalancePoints: (json['current_balance_points'] as num?)?.toInt() ?? 0,
      currentBalanceInr: (json['current_balance_inr'] as num?)?.toDouble() ?? 0.0,
      pendingRedemptionPoints: (json['pending_redemption_points'] as num?)?.toInt() ?? 0,
      pendingRedemptionInr: (json['pending_redemption_inr'] as num?)?.toDouble() ?? 0.0,
      totalPointsEarned: (json['total_points_earned'] as num?)?.toInt() ?? 0,
      totalPointsRedeemed: (json['total_points_redeemed'] as num?)?.toInt() ?? 0,
      pointsBaseUnit: baseUnit,
      inrPerBaseUnit: inrPerBase,
      rateMultiplier: mult,
      rateDisplayString: json['rate_display_string']?.toString() ??
          '$baseUnit Points = ₹${inrPerBase.toStringAsFixed(2)}',
      minRedemptionPoints: (json['min_redemption_points'] as num?)?.toInt() ?? 50,
      minRedemptionInr: (json['min_redemption_inr'] as num?)?.toDouble() ?? 50.0,
      isEnabled: json['is_enabled'] == true,
      isRewardEligible: json['is_reward_eligible'] != false,
      termsAndConditions: json['terms_and_conditions']?.toString() ??
          'Pivot Bearings reserves the right to modify, adjust, or change the reward point conversion value (Points to INR rate) and program rules at any time without prior notice.',
    );
  }

  /// Calculates Rupee value for any given point amount using active admin conversion rate
  double calculateInrForPoints(int points) {
    if (points <= 0) return 0.0;
    return (points * rateMultiplier);
  }
}

class RewardClaimResult {
  final bool rewardAwarded;
  final bool alreadyClaimed;
  final bool isUserBlocked;
  final String? bearingId;
  final int pointsEarned;
  final double amountInr;
  final String rateDisplay;
  final int newBalance;
  final String message;
  final String? supplierName;
  final String? supplierContact;

  const RewardClaimResult({
    required this.rewardAwarded,
    this.alreadyClaimed = false,
    this.isUserBlocked = false,
    this.bearingId,
    this.pointsEarned = 0,
    this.amountInr = 0.0,
    this.rateDisplay = '',
    this.newBalance = 0,
    required this.message,
    this.supplierName,
    this.supplierContact,
  });

  factory RewardClaimResult.empty({String message = 'No reward applicable.'}) {
    return RewardClaimResult(
      rewardAwarded: false,
      isUserBlocked: false,
      message: message,
    );
  }

  factory RewardClaimResult.fromJson(Map<String, dynamic> json) {
    return RewardClaimResult(
      rewardAwarded: json['reward_awarded'] == true,
      alreadyClaimed: json['already_claimed'] == true,
      isUserBlocked: json['is_user_blocked'] == true,
      bearingId: json['bearing_id']?.toString(),
      pointsEarned: (json['points_awarded'] ?? json['points_earned'] as num?)?.toInt() ?? 0,
      amountInr: (json['inr_value'] ?? json['amount_inr'] as num?)?.toDouble() ?? 0.0,
      rateDisplay: json['rate_display']?.toString() ?? '',
      newBalance: (json['new_balance'] as num?)?.toInt() ?? 0,
      message: json['message']?.toString() ?? '',
      supplierName: json['supplier_name']?.toString(),
      supplierContact: json['supplier_contact']?.toString(),
    );
  }
}

class RewardRedemption {
  final String id;
  final String requestNumber;
  final String userId;
  final int pointsRequested;
  final double amountInInr;
  final String payoutMethod;
  final String? upiId;
  final String? bankAccountNumber;
  final String? bankIfsc;
  final String? bankAccountHolderName;
  final String? bankName;
  final String status; // 'PENDING', 'PROCESSING', 'COMPLETED', 'REJECTED'
  final String? paymentReferenceId;
  final String? paymentMode;
  final String? adminNotes;
  final DateTime? createdAt;
  final DateTime? actionedAt;
  final String? userEmail;
  final String? userName;
  final String? userPhone;

  const RewardRedemption({
    required this.id,
    required this.requestNumber,
    required this.userId,
    required this.pointsRequested,
    required this.amountInInr,
    required this.payoutMethod,
    this.upiId,
    this.bankAccountNumber,
    this.bankIfsc,
    this.bankAccountHolderName,
    this.bankName,
    required this.status,
    this.paymentReferenceId,
    this.paymentMode,
    this.adminNotes,
    this.createdAt,
    this.actionedAt,
    this.userEmail,
    this.userName,
    this.userPhone,
  });

  bool get isPending => status == 'PENDING' || status == 'PROCESSING';
  bool get isCompleted => status == 'COMPLETED';
  bool get isRejected => status == 'REJECTED';

  factory RewardRedemption.fromJson(Map<String, dynamic> json) {
    return RewardRedemption(
      id: json['id']?.toString() ?? '',
      requestNumber: json['request_number']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      pointsRequested: (json['points_requested'] as num?)?.toInt() ?? 0,
      amountInInr: (json['amount_in_inr'] as num?)?.toDouble() ?? 0.0,
      payoutMethod: json['payout_method']?.toString() ?? 'UPI',
      upiId: json['upi_id']?.toString(),
      bankAccountNumber: json['bank_account_number']?.toString(),
      bankIfsc: json['bank_ifsc']?.toString(),
      bankAccountHolderName: json['bank_account_holder_name']?.toString(),
      bankName: json['bank_name']?.toString(),
      status: json['status']?.toString() ?? 'PENDING',
      paymentReferenceId: json['payment_reference_id']?.toString(),
      paymentMode: json['payment_mode']?.toString(),
      adminNotes: json['admin_notes']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      actionedAt: json['actioned_at'] != null ? DateTime.tryParse(json['actioned_at'].toString()) : null,
      userEmail: json['user_email']?.toString(),
      userName: json['user_name']?.toString(),
      userPhone: json['user_phone']?.toString(),
    );
  }
}

class RewardTransaction {
  final String id;
  final String? bearingId;
  final String transactionType;
  final int points;
  final double amountInr;
  final String sourceModule;
  final String description;
  final DateTime? createdAt;

  const RewardTransaction({
    required this.id,
    this.bearingId,
    required this.transactionType,
    required this.points,
    required this.amountInr,
    required this.sourceModule,
    required this.description,
    this.createdAt,
  });

  bool get isCredit => points > 0;

  factory RewardTransaction.fromJson(Map<String, dynamic> json) {
    return RewardTransaction(
      id: json['id']?.toString() ?? '',
      bearingId: json['bearing_id']?.toString(),
      transactionType: json['transaction_type']?.toString() ?? 'FIRST_SCAN_REWARD',
      points: (json['points'] as num?)?.toInt() ?? 0,
      amountInr: (json['amount_inr'] as num?)?.toDouble() ?? 0.0,
      sourceModule: json['source_module']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
    );
  }
}

class RewardSettings {
  final int pointsBaseUnit;
  final double inrPerBaseUnit;
  final int pointsPerFirstScan;
  final int minRedemptionPoints;
  final bool isEnabled;
  final int dailyMaxScans;
  final String termsAndConditions;

  const RewardSettings({
    this.pointsBaseUnit = 10,
    this.inrPerBaseUnit = 10.0,
    this.pointsPerFirstScan = 10,
    this.minRedemptionPoints = 50,
    this.isEnabled = true,
    this.dailyMaxScans = 50,
    this.termsAndConditions =
        'Pivot Bearings reserves the right to modify, adjust, or change the reward point conversion value (Points to INR rate) and program rules at any time without prior notice.',
  });

  factory RewardSettings.fromJson(Map<String, dynamic> json) {
    return RewardSettings(
      pointsBaseUnit: (json['points_base_unit'] as num?)?.toInt() ?? 10,
      inrPerBaseUnit: (json['inr_per_base_unit'] as num?)?.toDouble() ?? 10.0,
      pointsPerFirstScan: (json['points_per_first_scan'] as num?)?.toInt() ?? 10,
      minRedemptionPoints: (json['min_redemption_points'] as num?)?.toInt() ?? 50,
      isEnabled: json['is_reward_system_enabled'] != false,
      dailyMaxScans: (json['daily_max_scans_per_user'] as num?)?.toInt() ?? 50,
      termsAndConditions: json['terms_and_conditions']?.toString() ??
          'Pivot Bearings reserves the right to modify, adjust, or change the reward point conversion value (Points to INR rate) and program rules at any time without prior notice.',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'points_base_unit': pointsBaseUnit,
      'inr_per_base_unit': inrPerBaseUnit,
      'points_per_first_scan': pointsPerFirstScan,
      'min_redemption_points': minRedemptionPoints,
      'is_reward_system_enabled': isEnabled,
      'daily_max_scans_per_user': dailyMaxScans,
      'terms_and_conditions': termsAndConditions,
    };
  }
}

/// Generic container for database-level paginated reward records
class PaginatedRewardResult<T> {
  final List<T> items;
  final int totalCount;
  final int page;
  final int pageSize;

  const PaginatedRewardResult({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  int get totalPages => (totalCount / pageSize).ceil().clamp(1, 9999);
  bool get hasNextPage => page < totalPages - 1;
  bool get hasPreviousPage => page > 0;
  int get startIndex => totalCount == 0 ? 0 : page * pageSize + 1;
  int get endIndex => ((page + 1) * pageSize).clamp(0, totalCount);
}

