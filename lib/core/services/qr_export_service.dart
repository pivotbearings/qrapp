import 'export_downloader_stub.dart'
    if (dart.library.html) 'export_downloader_web.dart';

/// Enterprise Export Service for Pivot Bearings India QR Registry
/// Supports:
/// 1. TXT Export tailored for Windows Notepad
/// 2. CSV Export for industrial spreadsheet systems
/// 3. Word-Compatible HTML/DOC format for corporate documentation
class QrExportService {
  /// Formats the current local date & time for manifest filenames (e.g. 2026-10-19_17-15-30)
  static String formatFileTimestamp([DateTime? dateTime]) {
    final dt = dateTime ?? DateTime.now();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-${d}_$hh-$mm-$ss';
  }

  /// Strictly generates single-column QR values row by row
  /// Only one column is used, no headers, no metadata lines
  static String generateSingleColumnQrManifest(List<dynamic> items) {
    final buffer = StringBuffer();
    for (final item in items) {
      String qrValue = '';
      if (item is String) {
        qrValue = item.trim();
      } else if (item is Map) {
        qrValue = (item['payload_value'] ?? item['bearing_id'] ?? item['id'] ?? '').toString().trim();
      }
      if (qrValue.isNotEmpty) {
        buffer.write('$qrValue\r\n');
      }
    }
    return buffer.toString();
  }

  /// Generates clean single-column TXT formatted row by row for industrial labelers and Notepad
  static String generateTxtManifest({
    String? batchCode,
    required List<dynamic> items,
  }) {
    return generateSingleColumnQrManifest(items);
  }

  /// Generates clean single-column CSV row by row with zero extraneous columns or headers
  static String generateCsvManifest({
    required List<dynamic> items,
  }) {
    return generateSingleColumnQrManifest(items);
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
  body { font-family: 'Arial', 'Helvetica', sans-serif; background-color: #FFFFFF; color: #001F59; margin: 30px; }
  h1 { color: #001F59; font-size: 20pt; margin-bottom: 4px; text-transform: uppercase; }
  .subtitle { font-size: 11pt; color: #001F59; margin-bottom: 20px; font-weight: bold; }
  .meta-box { border: 2px solid #001F59; padding: 12px; background-color: #FFFFFF; margin-bottom: 24px; }
  table { width: 100%; border-collapse: collapse; margin-top: 10px; }
  th { background-color: #001F59; color: #FFFFFF; border: 1px solid #001F59; padding: 8px; font-size: 9pt; text-align: left; }
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

  /// Triggers client-side download for Whole File in TXT format (row by row, single column, with generated date & time)
  static void downloadWholeFileTxt({
    required List<dynamic> items,
    DateTime? timestamp,
  }) {
    final ts = formatFileTimestamp(timestamp);
    final content = generateSingleColumnQrManifest(items);
    ExportDownloader.downloadFile(
      filename: 'qr_registry_$ts.txt',
      content: content,
      mimeType: 'text/plain;charset=utf-8',
    );
  }

  /// Triggers client-side download for Whole File in CSV format (row by row, single column, with generated date & time)
  static void downloadWholeFileCsv({
    required List<dynamic> items,
    DateTime? timestamp,
  }) {
    final ts = formatFileTimestamp(timestamp);
    final content = generateSingleColumnQrManifest(items);
    ExportDownloader.downloadFile(
      filename: 'qr_registry_$ts.csv',
      content: content,
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  /// Triggers client-side download for TXT file (strictly single column row by row with timestamp)
  static void downloadTxt({
    String? batchCode,
    required List<dynamic> items,
    DateTime? timestamp,
  }) {
    final ts = formatFileTimestamp(timestamp);
    final content = generateSingleColumnQrManifest(items);
    final prefix = (batchCode != null && batchCode.isNotEmpty && batchCode != 'REGISTRY_EXPORT')
        ? '${batchCode}_'
        : 'qr_export_';
    ExportDownloader.downloadFile(
      filename: '$prefix$ts.txt',
      content: content,
      mimeType: 'text/plain;charset=utf-8',
    );
  }

  /// Triggers client-side download for CSV file (strictly single column row by row with timestamp)
  static void downloadCsv({
    String? batchCode,
    required List<dynamic> items,
    DateTime? timestamp,
  }) {
    final ts = formatFileTimestamp(timestamp);
    final content = generateSingleColumnQrManifest(items);
    final prefix = (batchCode != null && batchCode.isNotEmpty && batchCode != 'REGISTRY_EXPORT')
        ? '${batchCode}_'
        : 'qr_export_';
    ExportDownloader.downloadFile(
      filename: '$prefix$ts.csv',
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
}
