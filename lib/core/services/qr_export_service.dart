import 'export_downloader_stub.dart'
    if (dart.library.html) 'export_downloader_web.dart';

/// Enterprise Export Service for Pivot Bearings India QR Registry
/// Supports:
/// 1. TXT Export tailored for Windows Notepad
/// 2. CSV Export for industrial spreadsheet systems
/// 3. Word-Compatible HTML/DOC format for corporate documentation
class QrExportService {
  /// Generates clean TXT formatted for Windows Notepad (\r\n line breaks)
  static String generateTxtManifest({
    required String batchCode,
    required List<Map<String, dynamic>> items,
  }) {
    final buffer = StringBuffer();
    buffer.write('======================================================================\r\n');
    buffer.write('PIVOT BEARINGS INDIA - OFFICIAL QR PRODUCTION MANIFEST\r\n');
    buffer.write('Batch Reference : $batchCode\r\n');
    buffer.write('Generated Date  : ${DateTime.now().toIso8601String()}\r\n');
    buffer.write('Total Records   : ${items.length}\r\n');
    buffer.write('Security Type   : Cryptographic SHA-256 Sealed Payload\r\n');
    buffer.write('======================================================================\r\n\r\n');

    buffer.write('INDEX | BEARING ID    | MODEL       | WARRANTY | STATUS         | SHA-256 CHECKSUM\r\n');
    buffer.write('----------------------------------------------------------------------\r\n');

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final id = (item['bearing_id'] ?? item['id'] ?? 'PB-UNKNOWN').toString().padRight(14);
      final model = (item['model_number'] ?? item['model'] ?? 'PBI-6204-ZZ').toString().padRight(11);
      final warranty = '${item['duration_months'] ?? item['warranty_months'] ?? item['warranty'] ?? '6'}M'.padRight(8);
      final status = (item['current_lifecycle_state'] ?? item['status'] ?? 'NOT_ACTIVATED').toString().padRight(14);
      final hash = (item['payload_hash'] ?? 'N/A').toString();

      buffer.write('${(i + 1).toString().padLeft(4, '0')}  | $id | $model | $warranty | $status | $hash\r\n');
    }

    buffer.write('\r\n----------------------------------------------------------------------\r\n');
    buffer.write('VERIFICATION ENDPOINTS:\r\n');
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final id = item['bearing_id'] ?? item['id'] ?? 'PB-UNKNOWN';
      final payload = item['payload_value'] ?? id;
      buffer.write('[${(i + 1).toString().padLeft(4, '0')}] $id => $payload\r\n');
    }

    buffer.write('\r\n======================================================================\r\n');
    buffer.write('END OF MANIFEST - CONFIDENTIAL INDUSTRIAL PROPERTY OF PIVOT BEARINGS INDIA\r\n');
    buffer.write('======================================================================\r\n');

    return buffer.toString();
  }

  /// Generates CSV compatible with Excel, LibreOffice, and ERP data pipelines
  static String generateCsvManifest({
    required List<Map<String, dynamic>> items,
  }) {
    final buffer = StringBuffer();
    // CSV Header
    buffer.writeln('Bearing ID,Batch Code,Model Number,Warranty Duration,Lifecycle State,Is Blocked,Block Reason,QR Value,Cryptographic Hash,Created Timestamp');

    for (final item in items) {
      final id = _escapeCsv(item['bearing_id'] ?? item['id'] ?? '');
      final batch = _escapeCsv(item['batch_code'] ?? item['batch'] ?? '');
      final model = _escapeCsv(item['model_number'] ?? item['model'] ?? 'PBI-6204-ZZ');
      final warranty = _escapeCsv('${item['duration_months'] ?? item['warranty_months'] ?? item['warranty'] ?? '6'} Months');
      final state = _escapeCsv(item['current_lifecycle_state'] ?? item['status'] ?? 'NOT_ACTIVATED');
      final isFlagged = item['is_flagged'] == true ? 'YES' : 'NO';
      final flagReason = _escapeCsv(item['flag_reason'] ?? '');
      final payload = _escapeCsv(item['payload_value'] ?? item['bearing_id'] ?? '');
      final hash = _escapeCsv(item['payload_hash'] ?? '');
      final createdAt = _escapeCsv(item['created_at'] ?? DateTime.now().toIso8601String());

      buffer.writeln('$id,$batch,$model,$warranty,$state,$isFlagged,$flagReason,$payload,$hash,$createdAt');
    }

    return buffer.toString();
  }

  /// Generates Word-compatible (.doc) document using HTML/XML Office vocabulary
  static String generateWordDoc({
    required String batchCode,
    required List<Map<String, dynamic>> items,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(r'''<html xmlns:o='urn:schemas-microsoft-com:office:office' xmlns:w='urn:schemas-microsoft-com:office:word' xmlns='http://www.w3.org/TR/REC-html40'>
<head>
<meta charset='utf-8'>
<title>Pivot Bearings India - QR Manifest</title>
<!--[if gte mso 9]>
<xml>
 <w:WordDocument>
  <w:View>Print</w:View>
  <w:Zoom>100</w:Zoom>
  <w:DoNotOptimizeForBrowser/>
 </w:WordDocument>
</xml>
<![endif]-->
<style>
  body { font-family: 'Arial', 'Helvetica', sans-serif; background-color: #ECECEC; color: #001F59; margin: 30px; }
  h1 { color: #001F59; font-size: 20pt; margin-bottom: 4px; text-transform: uppercase; }
  .subtitle { font-size: 11pt; color: #001F59; margin-bottom: 20px; font-weight: bold; }
  .meta-box { border: 2px solid #001F59; padding: 12px; background-color: #ECECEC; margin-bottom: 24px; }
  table { width: 100%; border-collapse: collapse; margin-top: 10px; }
  th { background-color: #001F59; color: #ECECEC; border: 1px solid #001F59; padding: 8px; font-size: 9pt; text-align: left; }
  td { border: 1px solid #001F59; padding: 6px; font-size: 8.5pt; color: #001F59; }
  .footer { margin-top: 30px; font-size: 8pt; border-top: 1px solid #001F59; padding-top: 8px; text-align: center; }
</style>
</head>
<body>
<h1>PIVOT BEARINGS INDIA</h1>
<div class='subtitle'>OFFICIAL INDUSTRIAL QR REGISTRY MANIFEST</div>

<div class='meta-box'>
  <strong>Batch Code:</strong> $batchCode<br>
  <strong>Export Timestamp:</strong> ${DateTime.now().toIso8601String()}<br>
  <strong>Record Count:</strong> ${items.length}<br>
  <strong>Authority:</strong> Plant Quality Assurance & Supply Chain Directorate
</div>

<table>
  <thead>
    <tr>
      <th>No.</th>
      <th>Bearing ID</th>
      <th>Model</th>
      <th>Warranty</th>
      <th>State</th>
      <th>Blocked</th>
      <th>Verification Payload Endpoint</th>
    </tr>
  </thead>
  <tbody>''');

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final id = item['bearing_id'] ?? item['id'] ?? 'PB-UNKNOWN';
      final model = item['model_number'] ?? item['model'] ?? 'PBI-6204-ZZ';
      final warranty = '${item['duration_months'] ?? item['warranty_months'] ?? item['warranty'] ?? '6'} Months';
      final state = item['current_lifecycle_state'] ?? item['status'] ?? 'NOT_ACTIVATED';
      final isBlocked = item['is_flagged'] == true ? 'YES' : 'NO';
      final payload = item['payload_value'] ?? id;

      buffer.writeln('''    <tr>
      <td>${i + 1}</td>
      <td><strong>$id</strong></td>
      <td>$model</td>
      <td>$warranty</td>
      <td>$state</td>
      <td>$isBlocked</td>
      <td>$payload</td>
    </tr>''');
    }

    buffer.writeln(r'''  </tbody>
</table>

<div class='footer'>
  CONFIDENTIAL & PROPRIETARY — PIVOT BEARINGS INDIA INDUSTRIAL OPERATIONAL SYSTEM<br>
  Tamper-evident verification payload anchored to industrial cryptographic registry.
</div>
</body>
</html>''');

    return buffer.toString();
  }

  /// Triggers client-side download for TXT file
  static void downloadTxt({
    required String batchCode,
    required List<Map<String, dynamic>> items,
  }) {
    final content = generateTxtManifest(batchCode: batchCode, items: items);
    ExportDownloader.downloadFile(
      filename: '${batchCode}_manifest.txt',
      content: content,
      mimeType: 'text/plain;charset=utf-8',
    );
  }

  /// Triggers client-side download for CSV file
  static void downloadCsv({
    required String batchCode,
    required List<Map<String, dynamic>> items,
  }) {
    final content = generateCsvManifest(items: items);
    ExportDownloader.downloadFile(
      filename: '${batchCode}_registry.csv',
      content: content,
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  /// Triggers client-side download for Word-compatible file (.doc)
  static void downloadWordDoc({
    required String batchCode,
    required List<Map<String, dynamic>> items,
  }) {
    final content = generateWordDoc(batchCode: batchCode, items: items);
    ExportDownloader.downloadFile(
      filename: '${batchCode}_manifest.doc',
      content: content,
      mimeType: 'application/msword;charset=utf-8',
    );
  }

  /// Triggers client-side download for any arbitrary file content
  static void downloadCustomFile({
    required String filename,
    required String content,
    String mimeType = 'text/plain;charset=utf-8',
  }) {
    ExportDownloader.downloadFile(
      filename: filename,
      content: content,
      mimeType: mimeType,
    );
  }

  static String _escapeCsv(dynamic val) {
    final str = val?.toString() ?? '';
    if (str.contains(',') || str.contains('"') || str.contains('\n')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return str;
  }
}
