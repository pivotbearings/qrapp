import '../../domain/services/warranty_calculator.dart';

/// Pivot Bearings India - Lifecycle Status
enum BearingLifecycleState {
  notActivated, // Generated QR, never marked IN
  currentlyIn,   // Installed in machine / facility
  currentlyOut,  // Removed / De-installed
}

/// Core Bearing Domain Model
class BearingModel {
  final String id; // e.g. "PB-9402-XJ"
  final String batchCode; // e.g. "BATCH-2026-OCT-A"
  final int warrantyDurationMonths; // e.g. 6
  final BearingLifecycleState state;
  final DateTime? firstInDate;
  final DateTime? lastInDate;
  final DateTime? lastOutDate;
  final String plantLocation; // e.g. "Chakan Industrial Complex"
  final String modelNumber; // e.g. "6204-ZZ"
  final String? customCategory;
  final String? productName;
  final String? customerName;
  final String? assignedCustomerId;
  final String? assignedCustomerEmail;
  final String? facilityCode;
  final String? lastProofImageHash;
  final DateTime? explicitExpiryDate;

  const BearingModel({
    required this.id,
    required this.batchCode,
    this.warrantyDurationMonths = 12,
    this.state = BearingLifecycleState.notActivated,
    this.firstInDate,
    this.lastInDate,
    this.lastOutDate,
    this.plantLocation = 'Plant 02 — Chakan Industrial Complex',
    this.modelNumber = 'B1',
    this.customCategory,
    this.productName,
    this.customerName,
    this.assignedCustomerId,
    this.assignedCustomerEmail,
    this.facilityCode,
    this.lastProofImageHash,
    this.explicitExpiryDate,
  });

  bool get isActivated => firstInDate != null;

  DateTime? get warrantyExpiryDate {
    if (firstInDate != null && warrantyDurationMonths > 0) {
      return WarrantyCalculator.calculateExpiryDate(
        firstInDate: firstInDate!,
        durationMonths: warrantyDurationMonths,
      );
    }
    return explicitExpiryDate;
  }

  bool get isWarrantyExpired {
    if (warrantyExpiryDate == null) return false;
    return DateTime.now().isAfter(warrantyExpiryDate!);
  }

  bool get isUnderWarranty {
    if (state == BearingLifecycleState.currentlyOut) return false;
    final expiry = warrantyExpiryDate;
    if (expiry == null) return true; // Active pending installation
    return DateTime.now().isBefore(expiry);
  }

  /// Whether the bearing has been marked OUT before its warranty expired
  /// (i.e. Removed/decommissioned from machine, but still within active warranty coverage -> eligible for supplier claim!)
  bool get isMarkedOutUnderWarranty {
    final isOut = state == BearingLifecycleState.currentlyOut || lastOutDate != null;
    if (!isOut) return false;
    final expiry = warrantyExpiryDate;
    if (expiry == null) return false;
    return DateTime.now().isBefore(expiry);
  }

  /// Whether warranty is nearing expiration: within the final 20% of its duration
  /// (e.g. on day 80 of a 100-day warranty).
  bool get isExpiringSoon {
    if (isWarrantyExpired) return false;
    if (state == BearingLifecycleState.currentlyOut) return false;
    final expiry = warrantyExpiryDate;
    if (expiry == null) return false;

    final start = firstInDate;
    final totalDays = start != null
        ? expiry.difference(start).inDays
        : (warrantyDurationMonths > 0 ? warrantyDurationMonths * 30 : 0);
    if (totalDays <= 0) return false;

    final daysLeft = daysLeftToExpiry;
    if (daysLeft == null || daysLeft < 0) return false;

    return daysLeft <= (totalDays * 0.20);
  }

  int? get daysLeftToExpiry {
    final expiry = warrantyExpiryDate;
    if (expiry == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiryDateOnly = DateTime(expiry.year, expiry.month, expiry.day);
    return expiryDateOnly.difference(today).inDays;
  }

  String get warrantyDaysLeftDisplay {
    final days = daysLeftToExpiry;
    if (days == null) {
      return '$warrantyDurationMonths Months (Pending Activation)';
    }
    if (days > 0) {
      return '$days Days Left';
    } else if (days == 0) {
      return 'Expiring Today';
    } else {
      return 'Expired ${days.abs()} Days Ago';
    }
  }

  String get category {
    if (customCategory != null && customCategory!.trim().isNotEmpty) {
      return customCategory!.trim();
    }
    if (productName != null && productName!.trim().isNotEmpty) {
      final p = productName!.toUpperCase();
      if (p.contains('BALL')) return 'Ball Bearing';
      if (p.contains('SPHERICAL')) return 'Spherical Roller Bearing';
      if (p.contains('TAPER')) return 'Tapered Roller Bearing';
      if (p.contains('CYLINDRICAL')) return 'Cylindrical Roller Bearing';
      if (p.contains('THRUST')) return 'Thrust Ball Bearing';
    }
    final m = modelNumber.toUpperCase();
    if (m == 'B1' || m.contains('BALL') || m.contains('620') || m.contains('630') || m.contains('600')) {
      return 'Ball Bearing';
    } else if (m.contains('222') || m.contains('223') || m.contains('SPHERICAL')) {
      return 'Spherical Roller Bearing';
    } else if (m.contains('302') || m.contains('303') || m.contains('320') || m.contains('TAPER')) {
      return 'Tapered Roller Bearing';
    } else if (m.contains('NU') || m.contains('NJ') || m.contains('CYLINDRICAL')) {
      return 'Cylindrical Roller Bearing';
    } else if (m.contains('720') || m.contains('730') || m.contains('ANGULAR')) {
      return 'Angular Contact Bearing';
    } else if (m.contains('511') || m.contains('512') || m.contains('THRUST')) {
      return 'Thrust Ball Bearing';
    }
    return 'Ball Bearing';
  }

  String get stateDisplayString {
    switch (state) {
      case BearingLifecycleState.notActivated:
        return 'PENDING ACTIVATION';
      case BearingLifecycleState.currentlyIn:
        return 'MARKED IN';
      case BearingLifecycleState.currentlyOut:
        return 'MARKED OUT';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'batch_code': batchCode,
      'warranty_duration_months': warrantyDurationMonths,
      'state': state.name,
      'first_in_date': firstInDate?.toIso8601String(),
      'last_in_date': lastInDate?.toIso8601String(),
      'last_out_date': lastOutDate?.toIso8601String(),
      'plant_location': plantLocation,
      'model_number': modelNumber,
      'category': customCategory ?? category,
      'product_name': productName,
      'customer_name': customerName,
      'assigned_customer_id': assignedCustomerId,
      'assigned_customer_email': assignedCustomerEmail,
      'facility_code': facilityCode,
      'last_proof_image_hash': lastProofImageHash,
      'explicit_expiry_date': (explicitExpiryDate ?? warrantyExpiryDate)?.toIso8601String(),
    };
  }

  factory BearingModel.fromJson(Map<String, dynamic> json) {
    return BearingModel(
      id: json['id'] as String,
      batchCode: json['batch_code'] as String? ?? 'BATCH-ACTIVE',
      warrantyDurationMonths: (json['warranty_duration_months'] as num?)?.toInt() ??
          (json['duration_months'] as num?)?.toInt() ?? 12,
      state: BearingLifecycleState.values.firstWhere(
        (e) => e.name == (json['state'] as String?),
        orElse: () => BearingLifecycleState.notActivated,
      ),
      firstInDate: json['first_in_date'] != null
          ? DateTime.tryParse(json['first_in_date'].toString())?.toLocal()
          : null,
      lastInDate: json['last_in_date'] != null
          ? DateTime.tryParse(json['last_in_date'].toString())?.toLocal()
          : null,
      lastOutDate: json['last_out_date'] != null
          ? DateTime.tryParse(json['last_out_date'].toString())?.toLocal()
          : null,
      plantLocation: json['plant_location'] as String? ?? 'Plant 02 — Chakan Industrial Complex',
      modelNumber: json['model_number'] as String? ?? 'B1',
      customCategory: json['category'] as String?,
      productName: json['product_name'] as String?,
      customerName: json['customer_name'] as String?,
      assignedCustomerId: json['assigned_customer_id'] as String?,
      assignedCustomerEmail: json['assigned_customer_email'] as String?,
      facilityCode: json['facility_code'] as String?,
      lastProofImageHash: json['last_proof_image_hash'] as String?,
      explicitExpiryDate: (json['explicit_expiry_date'] ?? json['warranty_expiry_timestamp']) != null
          ? DateTime.tryParse((json['explicit_expiry_date'] ?? json['warranty_expiry_timestamp']).toString())?.toLocal()
          : null,
    );
  }
}
