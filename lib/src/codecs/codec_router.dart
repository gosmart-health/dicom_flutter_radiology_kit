import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'decoder_interface.dart';
import 'wasm_worker_bridge.dart';

/// DICOM Transfer Syntax UIDs
class DicomTransferSyntaxes {
  static const String implicitVRLittleEndian = '1.2.840.10008.1.2';
  static const String explicitVRLittleEndian = '1.2.840.10008.1.2.1';
  static const String jpegBaseline1 = '1.2.840.10008.1.2.4.50';
  static const String jpegExtended2_4 = '1.2.840.10008.1.2.4.51';
  static const String jpeg2000Lossless = '1.2.840.10008.1.2.4.90';
  static const String jpeg2000Lossy = '1.2.840.10008.1.2.4.91';
  static const String rleLossless = '1.2.840.10008.1.2.5';
  static const String htj2kLossless = '1.2.840.10008.1.2.4.201';
  static const String htj2kLossy = '1.2.840.10008.1.2.4.202';
}

/// Compression mode for WADO-RS RetrieveFrames request negotiation.
enum DicomCompressionMode {
  raw(
    label: 'RAW',
    transferSyntaxUID: DicomTransferSyntaxes.explicitVRLittleEndian,
    mediaType: 'application/octet-stream',
  ),
  jpeg2000Lossless(
    label: 'JPEG2000_LOSSLESS',
    transferSyntaxUID: DicomTransferSyntaxes.jpeg2000Lossless,
    mediaType: 'image/jp2',
  ),
  jpeg2000(
    label: 'JPEG2000',
    transferSyntaxUID: DicomTransferSyntaxes.jpeg2000Lossy,
    mediaType: 'image/jp2',
  ),
  rle(
    label: 'RLE',
    transferSyntaxUID: DicomTransferSyntaxes.rleLossless,
    mediaType: 'application/octet-stream',
  ),
  jpeg(
    label: 'JPEG',
    transferSyntaxUID: DicomTransferSyntaxes.jpegBaseline1,
    mediaType: 'image/jpeg',
  );

  final String label;
  final String transferSyntaxUID;
  final String mediaType;

  const DicomCompressionMode({
    required this.label,
    required this.transferSyntaxUID,
    required this.mediaType,
  });

  /// WADO-RS Accept header value for this compression mode.
  String get acceptHeader =>
      'multipart/related; type="$mediaType"; transfer-syntax="$transferSyntaxUID"';
}

/// Dispatcher routing frames to decoders based on bitstream signature and DICOM Transfer Syntax UID.
class CodecRouter {
  static final WasmWorkerBridge _wasmWorkerBridge = WasmWorkerBridge();

  static Future<DecodeResult> decode({
    required String transferSyntaxUID,
    required Uint8List frameBytes,
    required DecodeOptions options,
  }) async {
    // 1. Check magic bytes first (most reliable detection)
    if (frameBytes.length >= 2 && frameBytes[0] == 0xFF && frameBytes[1] == 0xD8) {
      return await _decodeJpegBaseline(frameBytes, options);
    }

    if ((frameBytes.length >= 2 && frameBytes[0] == 0xFF && frameBytes[1] == 0x4F) ||
        (frameBytes.length >= 12 && frameBytes[4] == 0x6A && frameBytes[5] == 0x50)) {
      return await _wasmWorkerBridge.decodeFrame(frameBytes, options);
    }

    // 2. Dispatch based on Transfer Syntax UID
    switch (transferSyntaxUID) {
      case DicomTransferSyntaxes.rleLossless:
        return await _decodeRle(frameBytes, options);

      case DicomTransferSyntaxes.jpegBaseline1:
      case DicomTransferSyntaxes.jpegExtended2_4:
        return await _decodeJpegBaseline(frameBytes, options);

      case DicomTransferSyntaxes.jpeg2000Lossless:
      case DicomTransferSyntaxes.jpeg2000Lossy:
      case DicomTransferSyntaxes.htj2kLossless:
      case DicomTransferSyntaxes.htj2kLossy:
        return await _wasmWorkerBridge.decodeFrame(frameBytes, options);

      case DicomTransferSyntaxes.implicitVRLittleEndian:
      case DicomTransferSyntaxes.explicitVRLittleEndian:
      default:
        return _decodeUncompressed(frameBytes, options);
    }
  }

  /// Decodes JPEG Baseline (Process 1, 8-bit) bitstreams into scalar pixel buffers.
  static Future<DecodeResult> _decodeJpegBaseline(
    Uint8List bytes,
    DecodeOptions options,
  ) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      final width = image.width;
      final height = image.height;
      final numPixels = width * height;

      if (byteData != null) {
        final list = Uint8List(numPixels);
        for (int i = 0; i < numPixels; i++) {
          list[i] = byteData.getUint8(i * 4);
        }

        if (!kIsWeb) {
          image.dispose();
        }

        return DecodeResult(
          pixelData: list,
          width: width,
          height: height,
          bitsAllocated: 8,
          bitsStored: 8,
          isSigned: false,
        );
      }
      if (!kIsWeb) {
        image.dispose();
      }
    } catch (_) {}

    return await _wasmWorkerBridge.decodeJpeg(bytes, options);
  }

  static DecodeResult _decodeUncompressed(Uint8List bytes, DecodeOptions options) {
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

  /// DICOM Part 5 Annex G RLE Decompressor offloaded to Web Worker / background isolate.
  static Future<DecodeResult> _decodeRle(Uint8List bytes, DecodeOptions options) async {
    try {
      return await _wasmWorkerBridge.decodeRle(bytes, options);
    } catch (_) {}

    return _decodeUncompressed(bytes, options);
  }

  static void dispose() {
    _wasmWorkerBridge.dispose();
  }
}
