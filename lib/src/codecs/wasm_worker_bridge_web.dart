import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
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

/// Web Worker / WASM bridge for decoding JPEG 2000 and JPEG bitstreams via OpenJPEG.
class WasmWorkerBridge implements FrameDecoder {
  Future<void> initialize() async {}

  @override
  Future<DecodeResult> decodeFrame(Uint8List encodedBytes, DecodeOptions options) async {
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

  /// Helper for decoding JPEG Baseline on Web using browser native decoding.
  Future<DecodeResult> decodeJpeg(Uint8List encodedBytes, DecodeOptions options) async {
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

  void dispose() {}
}
