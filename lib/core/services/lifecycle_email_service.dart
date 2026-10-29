import 'package:intl/intl.dart';
import '../auth/auth_controller.dart';
import 'supabase_service.dart';

/// Result entity returned from LifecycleEmailService
class LifecycleEmailResult {
  final bool success;
  final String message;
  final String? recipientEmail;

  const LifecycleEmailResult({
    required this.success,
    required this.message,
    this.recipientEmail,
  });
}

/// Secure client-side orchestrator for dispatching bearing lifecycle reports via Resend
class LifecycleEmailService {
  static final Set<String> _inFlightBearingIds = {};
  static final DateFormat _dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  /// Determines whether an email request is currently in flight for a given bearing ID
  static bool isSending(String bearingId) => _inFlightBearingIds.contains(bearingId.toUpperCase().trim());

  /// Automatically sends the bearing lifecycle report to the signed-in user's email address
  static Future<LifecycleEmailResult> sendBearingOutLifecycleEmail({
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
  }) async {
    final cleanId = bearingId.toUpperCase().trim();
    final auth = AuthController.instance;
    final recipientEmail = auth.userEmail;

    if (recipientEmail == null || recipientEmail.isEmpty) {
      return const LifecycleEmailResult(
        success: false,
        message: 'No signed-in account email found. Please ensure you are logged in.',
      );
    }

    if (_inFlightBearingIds.contains(cleanId)) {
      return LifecycleEmailResult(
        success: false,
        message: 'An email request for $cleanId is already in progress. Please wait.',
        recipientEmail: recipientEmail,
      );
    }

    _inFlightBearingIds.add(cleanId);

    try {
      final now = outDate ?? DateTime.now();
      final subject = 'Pivot Bearings India — Official Lifecycle Summary for $cleanId';

      final htmlContent = _buildHtmlTemplate(
        bearingId: cleanId,
        modelNumber: modelNumber,
        category: category,
        inDateStr: inDate != null ? _dateTimeFormat.format(inDate.toLocal()) : 'N/A',
        outDateStr: _dateTimeFormat.format(now.toLocal()),
        durationStr: durationString,
        warrantyPlan: warrantyPlan,
        warrantyExpiry: warrantyExpiry,
        isUnderWarranty: isUnderWarranty,
        recipientEmail: recipientEmail,
        customerName: auth.userName ?? 'Valued Partner',
        cycleRecords: cycleRecords,
      );

      final rpcResult = await SupabaseService.sendBearingLifecycleEmail(
        bearingId: cleanId,
        htmlContent: htmlContent,
        subject: subject,
      );

      final isSuccess = rpcResult['success'] == true;
      final serverMessage = rpcResult['message']?.toString();
      final serverError = rpcResult['error']?.toString();

      if (isSuccess) {
        return LifecycleEmailResult(
          success: true,
          message: serverMessage ?? 'Lifecycle summary sent successfully to $recipientEmail.',
          recipientEmail: recipientEmail,
        );
      } else {
        // Human-friendly error translation
        String readableError = serverError ?? 'Email delivery failed.';
        if (readableError.contains('app_secrets') || readableError.contains('Resend API key')) {
          readableError = 'Resend API key is not configured in Supabase. Please add your Resend API key in the app_secrets table.';
        } else if (readableError.contains('net.http_post') || readableError.contains('extension')) {
          readableError = 'Database HTTP extension (pg_net) required. Please run the provided SQL in Supabase.';
        }

        return LifecycleEmailResult(
          success: false,
          message: readableError,
          recipientEmail: recipientEmail,
        );
      }
    } catch (e) {
      return LifecycleEmailResult(
        success: false,
        message: 'Could not connect to email delivery service: $e',
        recipientEmail: recipientEmail,
      );
    } finally {
      _inFlightBearingIds.remove(cleanId);
    }
  }

  /// Builds a high-end, responsive HTML email template branded with Pivot Bearings India styling
  static String _buildHtmlTemplate({
    required String bearingId,
    required String modelNumber,
    required String category,
    required String inDateStr,
    required String outDateStr,
    required String durationStr,
    required String warrantyPlan,
    required String warrantyExpiry,
    required bool isUnderWarranty,
    required String recipientEmail,
    required String customerName,
    required List<Map<String, dynamic>> cycleRecords,
  }) {
    final statusColor = isUnderWarranty ? '#16A34A' : '#DC2626';
    final statusText = isUnderWarranty ? 'UNDER WARRANTY' : 'WARRANTY EXPIRED';

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Pivot Bearings India — Lifecycle Summary</title>
  <style>
    body { margin: 0; padding: 0; background-color: #F8FAFC; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #0F172A; }
    .wrapper { max-width: 600px; margin: 30px auto; background-color: #FFFFFF; border-radius: 12px; border: 1px solid #E2E8F0; overflow: hidden; box-shadow: 0 4px 12px rgba(15, 23, 42, 0.05); }
    .header { background-color: #0F172A; padding: 24px 28px; text-align: left; }
    .brand-title { color: #FFFFFF; font-size: 18px; font-weight: 800; letter-spacing: 0.5px; margin: 0; }
    .brand-subtitle { color: #94A3B8; font-size: 11px; margin-top: 4px; text-transform: uppercase; letter-spacing: 1px; }
    .content { padding: 28px; }
    .hero-card { background-color: #FEF2F2; border: 1.5px solid #FCA5A5; border-radius: 8px; padding: 18px; margin-bottom: 24px; text-align: center; }
    .hero-title { color: #991B1B; font-size: 11px; font-weight: 800; letter-spacing: 1.5px; margin: 0; }
    .hero-id { color: #0F172A; font-size: 24px; font-weight: 900; margin: 6px 0 2px 0; font-family: monospace; }
    .hero-duration { color: #DC2626; font-size: 16px; font-weight: 700; margin-top: 4px; }
    .table-container { width: 100%; border-collapse: collapse; margin-bottom: 24px; }
    .table-container td { padding: 10px 12px; font-size: 13px; border-bottom: 1px solid #F1F5F9; }
    .label-cell { color: #64748B; font-weight: 500; width: 40%; }
    .value-cell { color: #0F172A; font-weight: 600; text-align: right; }
    .badge { display: inline-block; padding: 3px 8px; border-radius: 4px; font-size: 10px; font-weight: 800; letter-spacing: 0.5px; }
    .footer { background-color: #F8FAFC; padding: 20px 28px; border-top: 1px solid #E2E8F0; font-size: 11px; color: #64748B; text-align: center; }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="header">
      <h1 class="brand-title">PIVOT BEARINGS INDIA</h1>
      <div class="brand-subtitle">Industrial Quality Directorate • Lifecycle Audit Report</div>
    </div>

    <div class="content">
      <p style="font-size: 14px; margin-top: 0; color: #334155;">Hello <strong>$customerName</strong>,</p>
      <p style="font-size: 13px; color: #475569; line-height: 1.5;">
        You have recorded a <strong>Bearing Out</strong> event for asset <strong>$bearingId</strong>. Below is your official, tamper-evident usage lifecycle record:
      </p>

      <div class="hero-card">
        <div class="hero-title">BEARING OUT — LIFECYCLE CLOSED</div>
        <div class="hero-id">$bearingId</div>
        <div class="hero-duration">Total Duration: $durationStr</div>
      </div>

      <table class="table-container">
        <tr>
          <td class="label-cell">Bearing Identifier</td>
          <td class="value-cell" style="font-family: monospace;">$bearingId</td>
        </tr>
        <tr>
          <td class="label-cell">Bearing Category</td>
          <td class="value-cell">$category</td>
        </tr>
        <tr>
          <td class="label-cell">Model Number</td>
          <td class="value-cell" style="font-family: monospace;">$modelNumber</td>
        </tr>
        <tr>
          <td class="label-cell">First Installation (IN)</td>
          <td class="value-cell">$inDateStr</td>
        </tr>
        <tr>
          <td class="label-cell">Decommissioned (OUT)</td>
          <td class="value-cell" style="color: #DC2626;">$outDateStr</td>
        </tr>
        <tr>
          <td class="label-cell">Coverage Plan</td>
          <td class="value-cell">$warrantyPlan</td>
        </tr>
        <tr>
          <td class="label-cell">Warranty Expiry Date</td>
          <td class="value-cell">$warrantyExpiry</td>
        </tr>
        <tr>
          <td class="label-cell">Warranty Status</td>
          <td class="value-cell">
            <span class="badge" style="background-color: ${isUnderWarranty ? '#DCFCE7' : '#FEE2E2'}; color: $statusColor;">
              $statusText
            </span>
          </td>
        </tr>
      </table>

      <p style="font-size: 12px; color: #64748B; margin-top: 20px; line-height: 1.4;">
        This automated email was requested directly by your authenticated account (<strong>$recipientEmail</strong>). No administrator intervention was involved.
      </p>
    </div>

    <div class="footer">
      <strong>Pivot Bearings India</strong> — Precision Engineering & Quality Assurance.<br>
      © 2026 Pivot Bearings India. All rights reserved.
    </div>
  </div>
</body>
</html>
''';
  }
}
