import 'dart:typed_data';

class WebPickedFile {
  final String name;
  final Uint8List bytes;
  final String mimeType;

  const WebPickedFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });
}

class WebImagePicker {
  static Future<WebPickedFile?> pickImage() async {
    return null;
  }
}
