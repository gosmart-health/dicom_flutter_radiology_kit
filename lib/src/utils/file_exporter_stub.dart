import 'package:flutter/services.dart';

/// Platform-agnostic file exporter stub for VM / desktop.
class FileExporter {
  static Future<String> exportFile({
    required String content,
    required String filename,
    required String mimeType,
  }) async {
    await Clipboard.setData(ClipboardData(text: content));
    return 'Copied $filename content (${content.length} bytes) to clipboard.';
  }
}
