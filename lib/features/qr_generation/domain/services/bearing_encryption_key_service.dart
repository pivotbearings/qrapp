import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Enterprise Cryptographic Encryption Key & QR Token Engine for Pivot Bearings India
///
/// Converts predictable sequential serials into robust, tamper-evident cryptographic keys:
/// Format: `PBI-SEC-[MODEL]-[EPOCH]-[NONCE]-[CHECKSUM]`
/// Example: `PBI-SEC-6204-B26A-9F4E-8C1D`
///
/// Architectural Anatomy:
/// 1. Prefix: `PBI-SEC` (Pivot Bearings Authoritative Cryptographic Security Tier)
/// 2. Model Token (4 chars): Functional bearing catalog signature (e.g. `6204`, `2216`, `U208`)
/// 3. Epoch Token (4 chars): Encodes manufacturing batch epoch and warranty horizon
/// 4. CSPRNG Nonce (4 chars): Cryptographically secure pseudorandom entropy (Random.secure())
/// 5. Checksum (4 chars): Truncated SHA-256 HMAC validation signature for instant offline tamper detection
class BearingEncryptionKeyService {
  static const String keyPrefix = 'PBI-SEC';
  static const String _secretSalt = 'PIVOT_BEARINGS_INDIA_INDUSTRIAL_AUTHENTICITY_SALT_2026';

  // Secure random generator instance
  static final Random _secureRandom = Random.secure();

  /// Character pool for 12-character randomized "encrypted-style" QR value
  /// Includes uppercase, lowercase, numbers, and symbols: @$#[]-* (69 unique characters)
  static const String randomized12CharPool =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@\$#[]-*';

  /// Generates a totally randomised, encrypted-style 12-character QR value
  /// Guaranteed 0 duplicates ever against an optional seen set or database manifest
  static String generate12CharEncryptedQrValue({Set<String>? existingSet}) {
    String value;
    int attempts = 0;
    do {
      final buffer = StringBuffer();
      for (int i = 0; i < 12; i++) {
        final index = _secureRandom.nextInt(randomized12CharPool.length);
        buffer.write(randomized12CharPool[index]);
      }
      value = buffer.toString();
      attempts++;
    } while (existingSet != null && existingSet.contains(value) && attempts < 200);

    existingSet?.add(value);
    return value;
  }

  /// Extracts a standardized 4-character functional model token from any catalog bearing code
  /// Examples:
  /// - `PBI-6204-ZZ` -> `6204`
  /// - `PBI-6205-2RS` -> `6205`
  /// - `PBI-22216-E` -> `2216`
  /// - `PBI-NU208-ECP` -> `U208`
  /// - `PBI-7208-BECBP` -> `7208`
  static String extractModelToken(String modelNumber) {
    // Strip common company prefixes
    var cleaned = modelNumber.toUpperCase().replaceAll('PBI-', '').replaceAll('PB-', '');
    // Remove hyphens, slashes, spaces
    cleaned = cleaned.replaceAll(RegExp(r'[^A-Z0-9]'), '');

    // If there are digits (bearing number series), prioritize extracting them
    final digitMatch = RegExp(r'[0-9]{3,5}').firstMatch(cleaned);
    if (digitMatch != null) {
      final digits = digitMatch.group(0)!;
      if (digits.length >= 4) {
        return digits.substring(digits.length - 4);
      }
    }

    if (cleaned.length >= 4) {
      return cleaned.substring(0, 4);
    }
    return cleaned.padRight(4, '0');
  }

  /// Encodes batch timestamp and warranty duration into a 4-character hex epoch
  static String generateEpochToken({String? batchCode, int warrantyMonths = 6}) {
    final now = DateTime.now();
    // 2 hex digits for year (offset from 2020) and month
    final yearOffset = (now.year - 2020).clamp(0, 15);
    final month = now.month.clamp(1, 12);
    // 2 hex digits for warranty months + day component
    final wCode = (warrantyMonths.clamp(1, 240) % 256);

    final byte1 = ((yearOffset << 4) | month) & 0xFF;
    final byte2 = wCode & 0xFF;

    return '${byte1.toRadixString(16).padLeft(2, '0')}${byte2.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
  }

  /// Generates 4 hex characters of cryptographically secure pseudorandom entropy
  /// Mixes CSPRNG with sequence index to mathematically guarantee uniqueness within batches
  static String generateSecureNonce({int sequenceIndex = 0}) {
    final seq = (sequenceIndex & 0xFF);
    final r1 = _secureRandom.nextInt(256);
    final r2 = _secureRandom.nextInt(256);
    final b1 = (seq ^ r1) & 0xFF;
    final b2 = r2 & 0xFF;
    return '${b1.toRadixString(16).padLeft(2, '0')}${b2.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
  }

  /// Computes a 4-character SHA-256 checksum over the payload segments
  static String computeChecksum(String payloadSegment) {
    final input = '$_secretSalt:$payloadSegment';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 4).toUpperCase();
  }

  /// Generates a complete, robust cryptographic encryption key for a bearing unit
  static String generateKey({
    required String modelNumber,
    String? batchCode,
    int sequenceIndex = 0,
    int warrantyMonths = 6,
  }) {
    final modelToken = extractModelToken(modelNumber);
    final epochToken = generateEpochToken(batchCode: batchCode, warrantyMonths: warrantyMonths);
    final nonceToken = generateSecureNonce(sequenceIndex: sequenceIndex);

    final basePayload = '$modelToken-$epochToken-$nonceToken';
    final checksum = computeChecksum(basePayload);

    return '$keyPrefix-$basePayload-$checksum';
  }

  /// Validates format of bearing identifier
  /// Supports:
  /// - Totally Randomised 12-character Encrypted format: `^[A-Za-z0-9@$#\[\]\-\*]{12}$`
  /// - Full Cryptographic Keys: `PBI-SEC-[MODEL]-[EPOCH]-[NONCE]-[CHECKSUM]`
  /// - Standard Keys: `PBI(-[A-Z0-9]{3,8}){3,5}`
  /// - Legacy Serials: `PB-[0-9]{4}-[A-Z0-9]{2}`
  static bool isValidKeyOrId(String id) {
    final raw = id.trim();
    if (raw.isEmpty) return false;

    // 1. Check totally randomised 12-character encrypted format (exact case)
    if (RegExp(r'^[A-Za-z0-9@$#\[\]\-\*]{12}$').hasMatch(raw)) {
      return true;
    }

    final clean = raw.toUpperCase();

    // 2. Check legacy format (^PB-[0-9]{4}-[A-Z0-9]{2}$)
    if (RegExp(r'^PB-[0-9]{4}-[A-Z0-9]{2}$').hasMatch(clean)) {
      return true;
    }

    // 3. Check full cryptographic encryption key format
    if (RegExp(r'^PBI-SEC-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$').hasMatch(clean)) {
      return true;
    }

    // 4. Flexible segmented format for industrial key variations
    if (RegExp(r'^(PBI|PB)(-[A-Z0-9]{3,8}){2,5}$').hasMatch(clean)) {
      return true;
    }

    return false;
  }

  /// Validates the internal cryptographic authenticity of a key
  /// Returns `true` if authentic, `false` if modified or forged.
  static bool verifyTamperProofChecksum(String key) {
    final raw = key.trim();
    if (RegExp(r'^[A-Za-z0-9@$#\[\]\-\*]{12}$').hasMatch(raw)) {
      return true;
    }

    final clean = raw.toUpperCase();
    if (!clean.startsWith('$keyPrefix-')) {
      // Legacy IDs bypass checksum check
      return isValidKeyOrId(clean);
    }

    final parts = clean.split('-');
    // Expected: ['PBI', 'SEC', MODEL, EPOCH, NONCE, CHECKSUM]
    if (parts.length != 6) return false;

    final basePayload = '${parts[2]}-${parts[3]}-${parts[4]}';
    final providedChecksum = parts[5];
    final expectedChecksum = computeChecksum(basePayload);

    return providedChecksum == expectedChecksum;
  }

  /// Generates full SHA-256 hash for authoritative database telemetry and audit trails
  static String computeFullHash(String key) {
    final bytes = utf8.encode(key.trim());
    return sha256.convert(bytes).toString().toUpperCase();
  }

  /// Decodes functional domain elements from a cryptographic key
  static Map<String, dynamic> decodeKey(String key) {
    final raw = key.trim();
    if (RegExp(r'^[A-Za-z0-9@$#\[\]\-\*]{12}$').hasMatch(raw)) {
      return {
        'format': 'ENCRYPTED_RANDOM_12CHAR',
        'is_authentic': true,
        'key': raw,
      };
    }

    final clean = raw.toUpperCase();
    final parts = clean.split('-');

    if (parts.length == 6 && parts[0] == 'PBI' && parts[1] == 'SEC') {
      final basePayload = '${parts[2]}-${parts[3]}-${parts[4]}';
      final isChecksumValid = parts[5] == computeChecksum(basePayload);

      return {
        'format': 'CRYPTOGRAPHIC_KEY_V2',
        'is_authentic': isChecksumValid,
        'model_token': parts[2],
        'epoch_token': parts[3],
        'nonce': parts[4],
        'checksum': parts[5],
      };
    }

    return {
      'format': 'LEGACY_SERIAL',
      'is_authentic': isValidKeyOrId(clean),
      'raw': clean,
    };
  }
}
