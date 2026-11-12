import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pivot_bearings_app/features/bearing_verification/data/services/bearing_track_service.dart';
import 'package:pivot_bearings_app/features/bearing_verification/domain/models/bearing_history_item.dart';
import 'package:pivot_bearings_app/features/qr_generation/data/repositories/qr_management_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Track Your Bearing WhatsApp Mark In & Mark Out Notes', () {
    test('BearingHistoryItem includes both Mark In Notes and Mark Out Notes in WhatsApp message', () {
      final item = BearingHistoryItem(
        bearingId: 'lUstY*vzlagg',
        modelNumber: 'PBI-6021-C3',
        batchCode: 'BATCH-01',
        inTimestamp: DateTime(2026, 11, 12, 20, 54),
        outTimestamp: DateTime(2026, 11, 12, 20, 55),
        durationSeconds: 52,
        inNotes: 'Installed on Spindle Unit #2',
        outNotes: 'Removed during routine PM check',
        isOut: true,
      );

      final msg = item.toWhatsAppText();
      expect(msg, contains('*Mark In Notes:* Installed on Spindle Unit #2'));
      expect(msg, contains('*Mark Out Notes:* Removed during routine PM check'));
    });

    test('BearingHistoryItem parses legacy pipe Out format into both Mark In and Mark Out Notes', () {
      final item = BearingHistoryItem(
        bearingId: 'PB-9402-XJ',
        modelNumber: 'B1',
        batchCode: 'BATCH-02',
        inTimestamp: DateTime(2026, 11, 12, 10, 0),
        outTimestamp: DateTime(2026, 11, 12, 12, 0),
        durationSeconds: 7200,
        notes: 'Shaft Line A | Out: Vibration detected',
        isOut: true,
      );

      final msg = item.toWhatsAppText();
      expect(msg, contains('*Mark In Notes:* Shaft Line A'));
      expect(msg, contains('*Mark Out Notes:* Vibration detected'));
    });

    test('BearingTrackService preserves both Mark In & Mark Out notes through Track In -> Track Out -> fetchTrackOutHistory', () async {
      const bearingId = 'PB-9402-XJ';
      await QrManagementRepository.syncBearingStateChange(
        bearingId: bearingId,
        newState: 'NOT_ACTIVATED',
      );

      final inRes = await BearingTrackService.trackScan(
        bearingId,
        notes: 'Initial fitment on Pump #4',
      );
      expect(inRes.isBearingIn, true);
      expect(inRes.inNotes, 'Initial fitment on Pump #4');

      final outRes = await BearingTrackService.trackScan(
        bearingId,
        notes: 'Replaced after scheduled run',
      );
      expect(outRes.isBearingOut, true);
      expect(outRes.inNotes, 'Initial fitment on Pump #4');
      expect(outRes.outNotes, 'Replaced after scheduled run');

      final history = await BearingTrackService.fetchTrackOutHistory();
      expect(history, isNotEmpty);
      final record = history.firstWhere((e) => e.bearingId.toUpperCase() == bearingId);
      final msg = record.toWhatsAppText();
      expect(msg, contains('*Mark In Notes:* Initial fitment on Pump #4'));
      expect(msg, contains('*Mark Out Notes:* Replaced after scheduled run'));
    });
  });
}

