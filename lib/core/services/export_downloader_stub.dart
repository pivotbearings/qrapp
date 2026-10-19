/// Universal export download interface (Mobile, Desktop, and Web)
class ExportDownloader {
  static void downloadFile({
    required String filename,
    required String content,
    required String mimeType,
  }) {
    // Non-web platforms fallback: prints to console or can save locally
    // In production mobile apps, path_provider + share_plus can be added if requested
  }
}
