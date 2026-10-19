/// Pivot Bearings India - Warranty & Lifecycle Calculator
///
/// Business Rules:
/// 1. Scanning alone NEVER activates warranty.
/// 2. First confirmed IN event starts the warranty period.
/// 3. OUT event closes the active operating duration cycle.
/// 4. Reinstallation after OUT does NOT reset or extend the original warranty.
/// 5. Remaining warranty is calculated against first IN timestamp + warranty duration.
class WarrantyCalculator {
  /// Calculates the warranty expiration date given the first IN date and duration in months.
  static DateTime calculateExpiryDate({
    required DateTime firstInDate,
    required int durationMonths,
  }) {
    final int newYear = firstInDate.year + ((firstInDate.month + durationMonths - 1) ~/ 12);
    final int newMonth = ((firstInDate.month + durationMonths - 1) % 12) + 1;
    final int lastDayOfMonth = DateTime(newYear, newMonth + 1, 0).day;
    final int day = firstInDate.day > lastDayOfMonth ? lastDayOfMonth : firstInDate.day;

    return firstInDate.isUtc
        ? DateTime.utc(
            newYear,
            newMonth,
            day,
            firstInDate.hour,
            firstInDate.minute,
            firstInDate.second,
            firstInDate.millisecond,
          )
        : DateTime(
            newYear,
            newMonth,
            day,
            firstInDate.hour,
            firstInDate.minute,
            firstInDate.second,
            firstInDate.millisecond,
          );
  }

  /// Determines whether the warranty is currently active at a given reference time.
  static bool isWarrantyActive({
    required DateTime? firstInDate,
    required int durationMonths,
    DateTime? currentTime,
  }) {
    if (firstInDate == null) return false;
    final now = currentTime ?? DateTime.now();
    final expiry = calculateExpiryDate(firstInDate: firstInDate, durationMonths: durationMonths);
    return now.isBefore(expiry);
  }

  /// Calculates remaining warranty days balance. Returns 0 if expired or not started.
  static int calculateRemainingDays({
    required DateTime? firstInDate,
    required int durationMonths,
    DateTime? currentTime,
  }) {
    if (firstInDate == null) return 0;
    final now = currentTime ?? DateTime.now();
    final expiry = calculateExpiryDate(firstInDate: firstInDate, durationMonths: durationMonths);
    final diff = expiry.difference(now).inDays;
    return diff > 0 ? diff : 0;
  }

  /// Calculates operating duration between an IN timestamp and an OUT timestamp.
  static Duration calculateOperatingDuration({
    required DateTime inTimestamp,
    required DateTime outTimestamp,
  }) {
    if (outTimestamp.isBefore(inTimestamp)) {
      return Duration.zero;
    }
    return outTimestamp.difference(inTimestamp);
  }

  /// Formats operating duration into human-readable industrial specification (e.g., "73 Days, 04 Hours, 48 Mins")
  static String formatOperatingDuration(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    return '$days Days, ${hours.toString().padLeft(2, '0')} Hours, ${minutes.toString().padLeft(2, '0')} Mins';
  }
}
