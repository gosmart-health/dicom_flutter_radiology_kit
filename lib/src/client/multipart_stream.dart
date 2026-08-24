import 'dart:async';
import 'dart:typed_data';

/// Parser for DICOM WADO-RS `multipart/related` stream responses.
class MultipartStreamReader {
  /// Extracts binary frame payloads from raw bytes or byte streams using boundary markers.
  static Stream<Uint8List> parseMultipartStream(
    Stream<List<int>> byteStream,
    String boundary,
  ) async* {
    final List<int> buffer = [];
    final boundaryBytes = '--$boundary'.codeUnits;

    await for (final chunk in byteStream) {
      buffer.addAll(chunk);

      // Search for boundary delimiters in buffer
      int matchIndex;
      while ((matchIndex = _indexOfSublist(buffer, boundaryBytes)) != -1) {
        if (matchIndex > 0) {
          final part = Uint8List.fromList(buffer.sublist(0, matchIndex));
          final payload = _stripMultipartHeaders(part);
          if (payload.isNotEmpty) {
            yield payload;
          }
        }
        buffer.removeRange(0, matchIndex + boundaryBytes.length);
      }
    }

    if (buffer.isNotEmpty) {
      final payload = _stripMultipartHeaders(Uint8List.fromList(buffer));
      if (payload.isNotEmpty) {
        yield payload;
      }
    }
  }

  static int _indexOfSublist(List<int> list, List<int> sublist) {
    if (sublist.isEmpty) return 0;
    for (int i = 0; i <= list.length - sublist.length; i++) {
      bool match = true;
      for (int j = 0; j < sublist.length; j++) {
        if (list[i + j] != sublist[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  static Uint8List _stripMultipartHeaders(Uint8List part) {
    // Header block is separated from body by double CRLF (\r\n\r\n) or double LF (\n\n)
    final doubleCrlf = [13, 10, 13, 10];
    final doubleLf = [10, 10];

    int headerEnd = _indexOfSublist(part, doubleCrlf);
    if (headerEnd != -1) {
      return part.sublist(headerEnd + 4);
    }
    headerEnd = _indexOfSublist(part, doubleLf);
    if (headerEnd != -1) {
      return part.sublist(headerEnd + 2);
    }
    return part;
  }
}
