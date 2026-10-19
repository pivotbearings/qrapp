/// Pivot Bearings India - Core Error & Exception Hierarchy
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  const AppException(this.message, {this.code, this.details});

  @override
  String toString() => '[$code] $message';
}

/// Thrown when a scanned QR code fails validation or checksum
class InvalidQrCodeException extends AppException {
  const InvalidQrCodeException(super.message, {super.code = 'INVALID_QR', super.details});
}

/// Thrown when camera initialization or optical capture fails
class CameraCaptureException extends AppException {
  const CameraCaptureException(super.message, {super.code = 'CAMERA_ERROR', super.details});
}

/// Thrown when Supabase or network request fails
class NetworkException extends AppException {
  const NetworkException(super.message, {super.code = 'NETWORK_ERROR', super.details});
}

/// Thrown when lifecycle state transition is illegal (e.g. OUT before IN)
class InvalidLifecycleTransitionException extends AppException {
  const InvalidLifecycleTransitionException(super.message, {super.code = 'INVALID_LIFECYCLE', super.details});
}

/// Thrown when image compression fails
class ImageCompressionException extends AppException {
  const ImageCompressionException(super.message, {super.code = 'COMPRESSION_ERROR', super.details});
}
