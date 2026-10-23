// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'web_image_picker_stub.dart';

class WebImagePicker {
  static Future<WebPickedFile?> pickImage() async {
    final completer = Completer<WebPickedFile?>();
    try {
      final uploadInput = html.FileUploadInputElement()
        ..accept = '.webp,image/webp,image/png,image/jpeg,image/*';
      uploadInput.click();

      uploadInput.onChange.listen((e) {
        final files = uploadInput.files;
        if (files == null || files.isEmpty) {
          completer.complete(null);
          return;
        }
        final file = files[0];
        final reader = html.FileReader();

        reader.onLoadEnd.listen((e) {
          if (reader.result == null) {
            completer.complete(null);
            return;
          }
          final bytes = Uint8List.fromList(reader.result as List<int>);
          completer.complete(WebPickedFile(
            name: file.name,
            bytes: bytes,
            mimeType: file.type.isNotEmpty ? file.type : 'image/webp',
          ));
        });

        reader.onError.listen((e) {
          completer.complete(null);
        });

        reader.readAsArrayBuffer(file);
      });
    } catch (_) {
      completer.complete(null);
    }

    return completer.future;
  }
}
