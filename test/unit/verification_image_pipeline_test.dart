import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pivot_bearings_app/features/optical_capture/domain/services/image_compression_service.dart';
import 'package:pivot_bearings_app/features/optical_capture/domain/services/verification_image_service.dart';

void main() {
  group('Verification Image Processing & Compression Pipeline Tests', () {
    late Uint8List testBitmapBytes;

    setUp(() {
      // Create a test image with dimensions 2400 x 1600 (oversized)
      final image = img.Image(width: 2400, height: 1600);
      img.fill(image, color: img.ColorRgb8(0, 31, 89)); // Brand Primary #001F59
      testBitmapBytes = Uint8List.fromList(img.encodePng(image));
    });

    test('1. Rejects empty byte buffers strictly', () async {
      expect(
        () => ImageCompressionService.processProofImage(Uint8List(0)),
        throwsArgumentError,
      );
      expect(
        () => VerificationImageService.processAndUpload(
          rawBytes: Uint8List(0),
          qrCodeId: 'PB-9402-XJ',
          eventId: 'evt-001',
          imageType: 'IN_INSTALLATION',
        ),
        throwsArgumentError,
      );
    });

    test('2. Resizes oversized image within 1,600–2,000px bounds (default 1800px max)', () async {
      final processed = await ImageCompressionService.processProofImage(
        testBitmapBytes,
        maxDimension: 1800,
        quality: 78,
      );

      // Width was 2400, should be resized proportionally to 1800
      expect(processed.width, equals(1800));
      // Height was 1600, should be 1800 * (1600 / 2400) = 1200
      expect(processed.height, equals(1200));
      expect(processed.compressedBytes.isNotEmpty, isTrue);
    });

    test('3. Encodes to WebP format with adaptive industrial quality (70-82)', () async {
      final processed = await ImageCompressionService.processProofImage(
        testBitmapBytes,
        maxDimension: 1800,
        quality: 78,
      );

      expect(processed.format, anyOf(equals('webp'), equals('jpeg')));
      expect(processed.compressedSizeBytes, greaterThan(0));
      // Compressed size should be reasonable and significantly smaller than raw uncompressed bitmap
      expect(processed.compressedSizeBytes, lessThan(2400 * 1600 * 4));
    });

    test('4. Computes deterministic cryptographic SHA-256 checksum', () async {
      final processed = await ImageCompressionService.processProofImage(
        testBitmapBytes,
        maxDimension: 1800,
        quality: 78,
      );

      expect(processed.sha256Hash, startsWith('SHA-256: '));
      // SHA-256 hex is 64 characters
      final hashHex = processed.sha256Hash.replaceFirst('SHA-256: ', '');
      expect(hashHex.length, equals(64));

      // Direct calculation must match
      final directHash = ImageCompressionService.calculateHash(processed.compressedBytes);
      expect(processed.sha256Hash, equals(directHash));
    });

    test('5. Formats event-specific storage paths as {qr_id}/{event_id}.webp', () async {
      const qrId = 'PB-9402-XJ';
      const eventId = 'evt-install-20261010';

      final record = await VerificationImageService.processAndUpload(
        rawBytes: testBitmapBytes,
        qrCodeId: qrId,
        eventId: eventId,
        imageType: 'IN_INSTALLATION',
        maxDimension: 1800,
        quality: 78,
      );

      expect(record, isNotNull);
      expect(record!.storagePath, startsWith('$qrId/$eventId.'));
      expect(record.storagePath, endsWith('.webp'));
      expect(record.imageType, equals('IN_INSTALLATION'));
      expect(record.sha256Hash, startsWith('SHA-256: '));
      expect(record.width, equals(1800));
      expect(record.height, equals(1200));
    });

    test('6. Supports removal image type OUT_REMOVAL with correct metadata', () async {
      const qrId = 'PB-8812-KR';
      const eventId = 'evt-removal-20261010';

      final record = await VerificationImageService.processAndUpload(
        rawBytes: testBitmapBytes,
        qrCodeId: qrId,
        eventId: eventId,
        imageType: 'OUT_REMOVAL',
        maxDimension: 1600,
        quality: 75,
      );

      expect(record, isNotNull);
      expect(record!.imageType, equals('OUT_REMOVAL'));
      expect(record.width, equals(1600));
      expect(record.height, equals(1067));
    });

    test('7. Handles synthetic mock buffers safely with fallback hashing', () async {
      final mockBuffer = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      final processed = await ImageCompressionService.processProofImage(mockBuffer);

      expect(processed.compressedBytes, equals(mockBuffer));
      expect(processed.sha256Hash, startsWith('SHA-256: '));
      expect(processed.compressedSizeBytes, equals(10));
    });
  });
}
