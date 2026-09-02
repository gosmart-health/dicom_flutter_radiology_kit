import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'decoder_interface.dart';

@JS('decodeJpeg2000')
external JSPromise<JSObject>? _decodeJpeg2000Js(
  JSUint8Array encodedBytes,
  JSNumber width,
  JSNumber height,
  JSBoolean isSigned,
  JSNumber bitsAllocated,
);

/// Web Worker / WASM bridge for decoding JPEG 2000 bitstreams via OpenJPEG.
class WasmWorkerBridge implements FrameDecoder {
  Future<void> initialize() async {}

  @override
  Future<DecodeResult> decodeFrame(Uint8List encodedBytes, DecodeOptions options) async {
    try {
      if (globalContext.hasProperty('decodeJpeg2000'.toJS).toDart) {
        final promise = _decodeJpeg2000Js(
          encodedBytes.toJS,
          options.width.toJS,
          options.height.toJS,
          options.isSigned.toJS,
          options.bitsAllocated.toJS,
        );

        if (promise != null) {
          final jsResult = await promise.toDart;
          final jsPixelData = jsResult.getProperty('pixelData'.toJS) as JSUint8Array;
          final dartBytes = jsPixelData.toDart;

          final width = (jsResult.getProperty('width'.toJS) as JSNumber?)?.toDartInt ?? options.width;
          final height = (jsResult.getProperty('height'.toJS) as JSNumber?)?.toDartInt ?? options.height;
          final bitsAllocated = (jsResult.getProperty('bitsAllocated'.toJS) as JSNumber?)?.toDartInt ?? options.bitsAllocated;
          final isSigned = (jsResult.getProperty('isSigned'.toJS) as JSBoolean?)?.toDart ?? options.isSigned;

          final numPixels = width * height;
          final TypedData pixels;

          if (bitsAllocated == 16) {
            final bd = ByteData.sublistView(dartBytes);
            final count = (dartBytes.lengthInBytes ~/ 2).clamp(0, numPixels);
            if (isSigned) {
              final int16List = Int16List(numPixels);
              for (int i = 0; i < count; i++) {
                int16List[i] = bd.getInt16(i * 2, Endian.little);
              }
              pixels = int16List;
            } else {
              final uint16List = Uint16List(numPixels);
              for (int i = 0; i < count; i++) {
                uint16List[i] = bd.getUint16(i * 2, Endian.little);
              }
              pixels = uint16List;
            }
          } else {
            pixels = Uint8List.fromList(dartBytes);
          }

          return DecodeResult(
            pixelData: pixels,
            width: width,
            height: height,
            bitsAllocated: bitsAllocated,
            bitsStored: bitsAllocated <= 8 ? 8 : 12,
            isSigned: isSigned,
          );
        }
      }
    } catch (_) {
      // Fallback
    }

    final numPixels = options.width * options.height;
    final TypedData pixels = options.bitsAllocated == 16
        ? (options.isSigned ? Int16List(numPixels) : Uint16List(numPixels))
        : Uint8List(numPixels);

    return DecodeResult(
      pixelData: pixels,
      width: options.width,
      height: options.height,
      bitsAllocated: options.bitsAllocated,
      bitsStored: options.bitsStored,
      isSigned: options.isSigned,
    );
  }

  void dispose() {}
}
