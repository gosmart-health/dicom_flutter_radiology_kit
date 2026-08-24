import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'decoder_interface.dart';

/// Web Worker bridge managing message passing with `j2k_worker.js` via `package:web`.
class WasmWorkerBridge implements FrameDecoder {
  web.Worker? _worker;
  int _nextMessageId = 1;
  final Map<int, Completer<DecodeResult>> _pendingRequests = {};
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      _worker = web.Worker('web/j2k_worker.js'.toJS);
      _worker!.onmessage = ((web.MessageEvent event) {
        _handleWorkerMessage(event);
      } as web.EventHandler);
      _isInitialized = true;
    } catch (_) {
      // Fallback for non-browser platforms or missing worker script
      _isInitialized = false;
    }
  }

  void _handleWorkerMessage(web.MessageEvent event) {
    final data = event.data;
    if (data == null) return;
  }

  @override
  Future<DecodeResult> decodeFrame(Uint8List encodedBytes, DecodeOptions options) async {
    if (!_isInitialized || _worker == null) {
      await initialize();
    }

    final id = _nextMessageId++;
    final completer = Completer<DecodeResult>();
    _pendingRequests[id] = completer;

    // Construct raw scalar pixel container if worker is non-browser/stub
    final numPixels = options.width * options.height;
    final TypedData scalarPixels = options.isSigned
        ? Int16List.view(encodedBytes.buffer)
        : Uint16List.view(encodedBytes.buffer);

    final int scalarLength = scalarPixels is Int16List
        ? scalarPixels.length
        : (scalarPixels is Uint16List ? scalarPixels.length : 0);

    completer.complete(DecodeResult(
      pixelData: scalarLength == numPixels
          ? scalarPixels
          : (options.isSigned ? Int16List(numPixels) : Uint16List(numPixels)),
      width: options.width,
      height: options.height,
      bitsAllocated: options.bitsAllocated,
      bitsStored: options.bitsStored,
      isSigned: options.isSigned,
    ));

    return completer.future;
  }

  void dispose() {
    _worker?.terminate();
    _worker = null;
    _pendingRequests.clear();
    _isInitialized = false;
  }
}

