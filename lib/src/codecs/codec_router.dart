import 'dart:typed_data';
import 'decoder_interface.dart';
import 'wasm_worker_bridge.dart';

/// Transfer Syntax UIDs
class DicomTransferSyntaxes {
  static const String implicitVRLittleEndian = '1.2.840.10008.1.2';
  static const String explicitVRLittleEndian = '1.2.840.10008.1.2.1';
  static const String jpeg2000Lossless = '1.2.840.10008.1.2.4.90';
  static const String jpeg2000Lossy = '1.2.840.10008.1.2.4.91';
  static const String htj2kLossless = '1.2.840.10008.1.2.4.201';
  static const String htj2kLossy = '1.2.840.10008.1.2.4.202';
}

/// Dispatcher routing frames to decoders based on DICOM Transfer Syntax UID.
class CodecRouter {
  static final WasmWorkerBridge _wasmWorkerBridge = WasmWorkerBridge();

  static Future<DecodeResult> decode({
    required String transferSyntaxUID,
    required Uint8List frameBytes,
    required DecodeOptions options,
  }) async {
    switch (transferSyntaxUID) {
      case DicomTransferSyntaxes.implicitVRLittleEndian:
      case DicomTransferSyntaxes.explicitVRLittleEndian:
        return _decodeUncompressed(frameBytes, options);

      case DicomTransferSyntaxes.jpeg2000Lossless:
      case DicomTransferSyntaxes.jpeg2000Lossy:
      case DicomTransferSyntaxes.htj2kLossless:
      case DicomTransferSyntaxes.htj2kLossy:
        return await _wasmWorkerBridge.decodeFrame(frameBytes, options);

      default:
        // Default to WASM worker bridge or uncompressed fallback
        return _decodeUncompressed(frameBytes, options);
    }
  }

  static DecodeResult _decodeUncompressed(Uint8List bytes, DecodeOptions options) {
    final numPixels = options.width * options.height;
    final TypedData pixels;

    if (options.bitsAllocated == 16) {
      if (options.isSigned) {
        pixels = bytes.buffer.lengthInBytes >= numPixels * 2
            ? Int16List.view(bytes.buffer, bytes.offsetInBytes, numPixels)
            : Int16List(numPixels);
      } else {
        pixels = bytes.buffer.lengthInBytes >= numPixels * 2
            ? Uint16List.view(bytes.buffer, bytes.offsetInBytes, numPixels)
            : Uint16List(numPixels);
      }
    } else {
      pixels = bytes.length >= numPixels
          ? Uint8List.view(bytes.buffer, bytes.offsetInBytes, numPixels)
          : Uint8List(numPixels);
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

  static void dispose() {
    _wasmWorkerBridge.dispose();
  }
}
