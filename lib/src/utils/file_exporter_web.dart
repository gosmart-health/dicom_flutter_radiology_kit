import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

/// Web implementation triggering browser download and clipboard copy.
class FileExporter {
  static Future<String> exportFile({
    required String content,
    required String filename,
    required String mimeType,
  }) async {
    try {
      final bytes = utf8.encode(content);
      final jsArray = bytes.toJS;
      final blob =
          web.Blob([jsArray].toJS, web.BlobPropertyBag(type: mimeType));
      final url = web.URL.createObjectURL(blob);
      final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
      anchor.href = url;
      anchor.download = filename;
      anchor.click();
      web.URL.revokeObjectURL(url);
      await Clipboard.setData(ClipboardData(text: content));
      return 'Downloaded $filename and copied to clipboard.';
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: content));
      return 'Copied $filename content to clipboard.';
    }
  }
}
