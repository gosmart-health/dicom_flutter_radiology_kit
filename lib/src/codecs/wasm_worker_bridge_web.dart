import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'decoder_interface.dart';

@JS('decodeJpeg2000')
external JSPromise<J2kDecodeResultJs> decodeJpeg2000Js(
  JSUint8Array encodedBytes,
  JSNumber width,
  JSNumber height,
  JSBoolean isSigned,
  JSNumber bitsAllocated,
);

@JS('decodeJpegBaseline')
external JSPromise<J2kDecodeResultJs> decodeJpegBaselineJs(
  JSUint8Array encodedBytes,
  JSNumber width,
  JSNumber height,
);

extension type J2kDecodeResultJs(JSObject _) implements JSObject {
  external JSUint16Array? get pixelData16;
  external JSUint8Array? get pixelData8;
  external JSNumber get width;
  external JSNumber get height;
  external JSBoolean get isSigned;
  external JSNumber get bitsAllocated;
}

extension type WorkerResponseJs(JSObject _) implements JSObject {
  external JSNumber get id;
  external JSString get status;
  external JSString? get message;
  external JSArrayBuffer? get pixelData;
  external JSNumber? get width;
  external JSNumber? get height;
  external JSBoolean? get isSigned;
  external JSNumber? get bitsAllocated;
}

extension type WorkerRequestJs._(JSObject _) implements JSObject {
  external factory WorkerRequestJs({
    required JSNumber id,
    required JSString command,
    required JSUint8Array encodedBytes,
    required JSNumber width,
    required JSNumber height,
    required JSBoolean isSigned,
    required JSNumber bitsAllocated,
  });
}

/// Web Worker / WASM bridge for offloading JPEG 2000 and JPEG decoding to a dedicated Web Worker thread.
class WasmWorkerBridge implements FrameDecoder {
  static web.Worker? _worker;
  static bool _workerInitAttempted = false;
  static bool _workerFailed = false;
  static int _nextRequestId = 1;
  static final Map<int, Completer<DecodeResult>> _pendingRequests = {};

  Future<void> initialize() async {
    _ensureWorker();
  }

  static void _ensureWorker() {
    if (_workerInitAttempted) return;
    _workerInitAttempted = true;

    try {
      final worker = web.Worker('j2k_worker.js'.toJS);
      _setupWorkerListeners(worker);
      _worker = worker;
    } catch (_) {
      try {
        final worker = web.Worker('assets/packages/dicom_flutter_radiology_kit/web/j2k_worker.js'.toJS);
        _setupWorkerListeners(worker);
        _worker = worker;
      } catch (e) {
        _workerFailed = true;
      }
    }
  }

  static void _setupWorkerListeners(web.Worker worker) {
    worker.onmessage = ((web.MessageEvent event) {
      final data = event.data;
      if (data == null) return;
      try {
        final response = data as WorkerResponseJs;
        final id = response.id.toDartInt;
        final completer = _pendingRequests.remove(id);
        if (completer == null) return;

        final status = response.status.toDart;
        if (status == 'ready') {
          return;
        }

        if (status == 'success') {
          final width = response.width?.toDartInt ?? 512;
          final height = response.height?.toDartInt ?? 512;
          final isSigned = response.isSigned?.toDart ?? false;
          final bitsAllocated = response.bitsAllocated?.toDartInt ?? 16;
          final buffer = response.pixelData?.toDart;

          final TypedData pixels;
          final numPixels = width * height;

          if (buffer != null) {
            if (bitsAllocated > 8) {
              final available = buffer.lengthInBytes ~/ 2;
              final count = math.min(numPixels, available);
              if (isSigned) {
                if (count == numPixels) {
                  pixels = buffer.asInt16List(0, numPixels);
                } else {
                  final list = Int16List(numPixels);
                  list.setRange(0, count, buffer.asInt16List(0, count));
                  pixels = list;
                }
              } else {
                if (count == numPixels) {
                  pixels = buffer.asUint16List(0, numPixels);
                } else {
                  final list = Uint16List(numPixels);
                  list.setRange(0, count, buffer.asUint16List(0, count));
                  pixels = list;
                }
              }
            } else {
              final available = buffer.lengthInBytes;
              final count = math.min(numPixels, available);
              if (count == numPixels) {
                pixels = buffer.asUint8List(0, numPixels);
              } else {
                final list = Uint8List(numPixels);
                list.setRange(0, count, buffer.asUint8List(0, count));
                pixels = list;
              }
            }
          } else {
            pixels = Uint16List(numPixels);
          }

          completer.complete(
            DecodeResult(
              pixelData: pixels,
              width: width,
              height: height,
              bitsAllocated: bitsAllocated,
              bitsStored: bitsAllocated <= 8 ? 8 : 12,
              isSigned: isSigned,
            ),
          );
        } else {
          final msg = response.message?.toDart ?? 'Worker decoding failed';
          completer.completeError(Exception(msg));
        }
      } catch (err) {
        // Ignored
      }
    }).toJS;

    worker.onerror = ((web.Event event) {
      _workerFailed = true;
      for (final completer in _pendingRequests.values) {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Worker error event'));
        }
      }
      _pendingRequests.clear();
    }).toJS;
  }

  @override
  Future<DecodeResult> decodeFrame(Uint8List encodedBytes, DecodeOptions options) async {
    _ensureWorker();

    if (_worker != null && !_workerFailed) {
      try {
        return await _decodeViaWorker(encodedBytes, options, 'decode');
      } catch (e) {
        print('[DICOM-BRIDGE] Worker J2K decode failed: $e. Attempting in-window fallback...');
      }
    }

    return await _decodeViaWindow(encodedBytes, options);
  }

  /// Offload JPEG Baseline to Web Worker using OffscreenCanvas, or fallback to in-window.
  Future<DecodeResult> decodeJpeg(Uint8List encodedBytes, DecodeOptions options) async {
    _ensureWorker();

    if (_worker != null && !_workerFailed) {
      try {
        return await _decodeViaWorker(encodedBytes, options, 'decodeJpeg');
      } catch (e) {
        print('[DICOM-BRIDGE] Worker JPEG decode failed: $e. Attempting in-window fallback...');
      }
    }

    return await _decodeJpegViaWindow(encodedBytes, options);
  }

  /// Offload RLE PackBits decoding to Web Worker thread, with zero-allocation fallback.
  Future<DecodeResult> decodeRle(Uint8List encodedBytes, DecodeOptions options) async {
    _ensureWorker();

    if (_worker != null && !_workerFailed) {
      try {
        return await _decodeViaWorker(encodedBytes, options, 'decodeRle');
      } catch (e) {
        print('[DICOM-BRIDGE] Worker RLE decode failed: $e. Using in-Dart fallback...');
      }
    }

    return _decodeRleInDart(encodedBytes, options);
  }

  Future<DecodeResult> _decodeViaWorker(
    Uint8List encodedBytes,
    DecodeOptions options,
    String command,
  ) async {
    final id = _nextRequestId++;
    final completer = Completer<DecodeResult>();
    _pendingRequests[id] = completer;

    final request = WorkerRequestJs(
      id: id.toJS,
      command: command.toJS,
      encodedBytes: encodedBytes.toJS,
      width: options.width.toJS,
      height: options.height.toJS,
      isSigned: options.isSigned.toJS,
      bitsAllocated: options.bitsAllocated.toJS,
    );

    final sw = Stopwatch()..start();
    _worker!.postMessage(request);

    try {
      final result = await completer.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          _pendingRequests.remove(id);
          throw TimeoutException('Web Worker decode timed out for request #$id ($command, ${encodedBytes.length} bytes)');
        },
      );
      sw.stop();
      return result;
    } catch (e) {
      sw.stop();
      print('[DICOM-BRIDGE] WARNING: Worker request #$id ($command) failed after ${sw.elapsedMilliseconds}ms: $e');
      rethrow;
    }
  }

  Future<DecodeResult> _decodeViaWindow(Uint8List encodedBytes, DecodeOptions options) async {
    try {
      final promise = decodeJpeg2000Js(
        encodedBytes.toJS,
        options.width.toJS,
        options.height.toJS,
        options.isSigned.toJS,
        options.bitsAllocated.toJS,
      );

      final jsResult = await promise.toDart;
      final width = jsResult.width.toDartInt;
      final height = jsResult.height.toDartInt;
      final isSigned = jsResult.isSigned.toDart;
      final bitsAllocated = jsResult.bitsAllocated.toDartInt;

      final TypedData pixels;
      if (jsResult.pixelData16 != null) {
        pixels = jsResult.pixelData16!.toDart;
      } else if (jsResult.pixelData8 != null) {
        pixels = jsResult.pixelData8!.toDart;
      } else {
        pixels = Uint16List(width * height);
      }

      return DecodeResult(
        pixelData: pixels,
        width: width,
        height: height,
        bitsAllocated: bitsAllocated,
        bitsStored: bitsAllocated <= 8 ? 8 : 12,
        isSigned: isSigned,
      );
    } catch (e) {
      throw Exception('Failed to decode JPEG 2000 frame: $e');
    }
  }

  Future<DecodeResult> _decodeJpegViaWindow(Uint8List encodedBytes, DecodeOptions options) async {
    try {
      final promise = decodeJpegBaselineJs(
        encodedBytes.toJS,
        options.width.toJS,
        options.height.toJS,
      );

      final jsResult = await promise.toDart;
      final width = jsResult.width.toDartInt;
      final height = jsResult.height.toDartInt;

      final TypedData pixels;
      if (jsResult.pixelData8 != null) {
        pixels = jsResult.pixelData8!.toDart;
      } else if (jsResult.pixelData16 != null) {
        pixels = jsResult.pixelData16!.toDart;
      } else {
        pixels = Uint8List(width * height);
      }

      return DecodeResult(
        pixelData: pixels,
        width: width,
        height: height,
        bitsAllocated: 8,
        bitsStored: 8,
        isSigned: false,
      );
    } catch (e) {
      throw Exception('Failed to decode JPEG frame: $e');
    }
  }

  static DecodeResult _decodeRleInDart(Uint8List bytes, DecodeOptions options) {
    final numPixels = options.width * options.height;
    if (bytes.length < 64) {
      return _decodeUncompressedInDart(bytes, options);
    }

    final byteData = ByteData.sublistView(bytes);
    final numSegments = byteData.getUint32(0, Endian.little);
    if (numSegments < 1 || numSegments > 15) {
      return _decodeUncompressedInDart(bytes, options);
    }

    final segmentOffsets = <int>[];
    for (int s = 0; s < numSegments; s++) {
      segmentOffsets.add(byteData.getUint32((s + 1) * 4, Endian.little));
    }

    final decompressedSegments = <Uint8List>[];
    for (int s = 0; s < numSegments; s++) {
      final start = segmentOffsets[s];
      final end = (s + 1 < numSegments) ? segmentOffsets[s + 1] : bytes.length;
      if (start >= bytes.length) break;

      final segData = _unpackPackBitsFast(bytes, start, end.clamp(start, bytes.length), numPixels);
      decompressedSegments.add(segData);
    }

    final TypedData pixels;
    if (options.bitsAllocated == 16 && decompressedSegments.length >= 2) {
      final msb = decompressedSegments[0];
      final lsb = decompressedSegments[1];
      if (options.isSigned) {
        final list = Int16List(numPixels);
        for (int i = 0; i < numPixels; i++) {
          final m = i < msb.length ? msb[i] : 0;
          final l = i < lsb.length ? lsb[i] : 0;
          final val = (m << 8) | l;
          list[i] = val > 32767 ? val - 65536 : val;
        }
        pixels = list;
      } else {
        final list = Uint16List(numPixels);
        for (int i = 0; i < numPixels; i++) {
          final m = i < msb.length ? msb[i] : 0;
          final l = i < lsb.length ? lsb[i] : 0;
          final val = (m << 8) | l;
          list[i] = val;
        }
        pixels = list;
      }
    } else if (decompressedSegments.isNotEmpty) {
      pixels = decompressedSegments[0];
    } else {
      return _decodeUncompressedInDart(bytes, options);
    }

    return DecodeResult(
      pixelData: pixels,
      width: options.width,
      height: options.height,
      bitsAllocated: options.bitsAllocated,
      bitsStored: options.bitsStored,
      isSigned: options.isSigned,
    );
  }

  static Uint8List _unpackPackBitsFast(Uint8List input, int start, int end, int expectedSize) {
    final output = Uint8List(expectedSize);
    int inIdx = start;
    int outIdx = 0;

    while (inIdx < end && outIdx < expectedSize) {
      final n = input[inIdx++];
      if (n <= 127) {
        final count = n + 1;
        final availableIn = end - inIdx;
        final neededOut = expectedSize - outIdx;
        final copyLen = math.min(count, math.min(availableIn, neededOut));
        if (copyLen > 0) {
          output.setRange(outIdx, outIdx + copyLen, input, inIdx);
          inIdx += count;
          outIdx += copyLen;
        } else {
          inIdx += count;
        }
      } else if (n >= 129) {
        final count = 257 - n;
        if (inIdx < end) {
          final val = input[inIdx++];
          final neededOut = expectedSize - outIdx;
          final fillLen = math.min(count, neededOut);
          if (fillLen > 0) {
            output.fillRange(outIdx, outIdx + fillLen, val);
            outIdx += fillLen;
          }
        }
      }
      // n == 128 is a no-op
    }
    return output;
  }

  static DecodeResult _decodeUncompressedInDart(Uint8List bytes, DecodeOptions options) {
    final numPixels = options.width * options.height;
    final TypedData pixels;

    if (options.bitsAllocated == 16) {
      if (options.isSigned) {
        if (bytes.offsetInBytes % 2 == 0 && bytes.lengthInBytes >= numPixels * 2) {
          pixels = Int16List.view(bytes.buffer, bytes.offsetInBytes, numPixels);
        } else {
          final list = Int16List(numPixels);
          final bd = ByteData.sublistView(bytes);
          final count = (bytes.lengthInBytes ~/ 2).clamp(0, numPixels);
          for (int i = 0; i < count; i++) {
            list[i] = bd.getInt16(i * 2, Endian.little);
          }
          pixels = list;
        }
      } else {
        if (bytes.offsetInBytes % 2 == 0 && bytes.lengthInBytes >= numPixels * 2) {
          pixels = Uint16List.view(bytes.buffer, bytes.offsetInBytes, numPixels);
        } else {
          final list = Uint16List(numPixels);
          final bd = ByteData.sublistView(bytes);
          final count = (bytes.lengthInBytes ~/ 2).clamp(0, numPixels);
          for (int i = 0; i < count; i++) {
            list[i] = bd.getUint16(i * 2, Endian.little);
          }
          pixels = list;
        }
      }
    } else {
      if (bytes.lengthInBytes >= numPixels) {
        pixels = Uint8List.view(bytes.buffer, bytes.offsetInBytes, numPixels);
      } else {
        final list = Uint8List(numPixels);
        final count = bytes.lengthInBytes.clamp(0, numPixels);
        for (int i = 0; i < count; i++) {
          list[i] = bytes[i];
        }
        pixels = list;
      }
    }

    return DecodeResult(
      pixelData: pixels,
      width: options.width,
      height: options.height,
      bitsAllocated: options.bitsAllocated,
      bitsStored: options.bitsStored,
      isSigned: options.isSigned,
    );
  }

  void dispose() {
    _worker?.terminate();
    _worker = null;
    _workerInitAttempted = false;
    _pendingRequests.clear();
  }
}
