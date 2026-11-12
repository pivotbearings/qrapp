import 'package:intl/intl.dart';

/// Represents a historical or active tracking entry for the Track Your Bearing module
class BearingHistoryItem {
  final String bearingId;
  final String modelNumber;
  final String batchCode;
  final String? productName;
  final DateTime inTimestamp;
  final DateTime? outTimestamp;
  final int? durationSeconds;
  final String? notes;
  final String? inNotes;
  final String? outNotes;
  final bool isOut;

  BearingHistoryItem({
    required this.bearingId,
    required this.modelNumber,
    required this.batchCode,
    this.productName,
    required this.inTimestamp,
    this.outTimestamp,
    this.durationSeconds,
    this.notes,
    this.inNotes,
    this.outNotes,
    required this.isOut,
  });

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  String get formattedInDate => _dateFormat.format(inTimestamp.toLocal());

  String get formattedOutDate =>
      outTimestamp != null ? _dateFormat.format(outTimestamp!.toLocal()) : 'Operating in system';

  String get formattedDuration {
    int totalSec = 0;
    if (durationSeconds != null && durationSeconds! > 0) {
      totalSec = durationSeconds!;
    } else if (outTimestamp != null) {
      totalSec = outTimestamp!.toLocal().difference(inTimestamp.toLocal()).inSeconds;
    } else {
      totalSec = DateTime.now().difference(inTimestamp.toLocal()).inSeconds;
    }

    if (totalSec < 0) totalSec = 0;
    final days = totalSec ~/ 86400;
    final hours = (totalSec % 86400) ~/ 3600;
    final mins = (totalSec % 3600) ~/ 60;

    final remSec = totalSec % 60;

    if (days > 0) {
      return '$days Days, $hours Hours, $mins Mins';
    } else if (hours > 0) {
      if (remSec == 0) return '$hours Hours, $mins Mins';
      return '$hours Hours, $mins Mins, $remSec Secs';
    } else if (mins > 0) {
      if (remSec == 0) return '$mins Mins';
      return '$mins Mins, $remSec Secs';
    } else {
      return '$totalSec Secs';
    }
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Resolves distinct Mark In and Mark Out notes, including legacy `' | Out: '` strings.
  (String?, String?) resolveInOutNotes() {
    var resolvedIn = _clean(inNotes);
    var resolvedOut = _clean(outNotes);
    final raw = _clean(notes);

    if (raw != null && raw.contains(' | Out: ')) {
      final parts = raw.split(' | Out: ');
      resolvedIn ??= _clean(parts.first);
      resolvedOut ??= _clean(parts.sublist(1).join(' | Out: '));
    } else if (!isOut && resolvedIn == null && raw != null) {
      resolvedIn = raw;
    }

    return (resolvedIn, resolvedOut);
  }

  /// Clean, readable WhatsApp sharing message (strictly no warranty details and no plant location)
  String generateWhatsAppMessage() {
    final (resolvedIn, resolvedOut) = resolveInOutNotes();
    final rawNotes = _clean(notes);
    final notesBuffer = StringBuffer();
    if (resolvedIn != null) {
      notesBuffer.write('*Mark In Notes:* $resolvedIn\n');
    }
    if (resolvedOut != null) {
      notesBuffer.write('*Mark Out Notes:* $resolvedOut\n');
    }
    if (resolvedIn == null && resolvedOut == null && rawNotes != null) {
      notesBuffer.write('*Notes:* $rawNotes\n');
    }
    final noteLine = notesBuffer.toString();

    if (isOut) {
      return '''*PIVOT BEARINGS INDIA - BEARING OUT RECORD*
--------------------------------
*Bearing ID:* $bearingId
*Model:* $modelNumber
*Status:* TRACKED OUT (COMPLETED)
*In Date:* $formattedInDate
*Out Date:* $formattedOutDate
*Total Operating Duration:* $formattedDuration
$noteLine--------------------------------
Official Tracking Record
Pivot Bearings India''';
    } else {
      return '''*PIVOT BEARINGS INDIA - BEARING IN RECORD*
--------------------------------
*Bearing ID:* $bearingId
*Model:* $modelNumber
*Status:* CURRENTLY IN (OPERATING)
*In Date:* $formattedInDate
$noteLine--------------------------------
Official Tracking Record
Pivot Bearings India''';
    }
  }

  String toWhatsAppText() => generateWhatsAppMessage();
}

