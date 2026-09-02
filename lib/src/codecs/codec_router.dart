import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
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
    mediaType: 'image/jpx',
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
      'multipart/related; type="$mediaType"; transfer-syntax="$transferSyntaxUID", $mediaType, application/octet-stream';
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

      case DicomTransferSyntaxes.rleLossless:
        return _decodeRle(frameBytes, options);

      case DicomTransferSyntaxes.jpegBaseline1:
      case DicomTransferSyntaxes.jpegExtended2_4:
        return await _decodeJpegBaseline(frameBytes, options);

      case DicomTransferSyntaxes.jpeg2000Lossless:
      case DicomTransferSyntaxes.jpeg2000Lossy:
      case DicomTransferSyntaxes.htj2kLossless:
      case DicomTransferSyntaxes.htj2kLossy:
        return await _wasmWorkerBridge.decodeFrame(frameBytes, options);

      default:
        // Check if magic bytes start with JPEG SOI (0xFF, 0xD8)
        if (frameBytes.length >= 2 && frameBytes[0] == 0xFF && frameBytes[1] == 0xD8) {
          return await _decodeJpegBaseline(frameBytes, options);
        }
        // Check if magic bytes start with J2K SOC (0xFF, 0x4F) or JP2 signature
        if ((frameBytes.length >= 2 && frameBytes[0] == 0xFF && frameBytes[1] == 0x4F) ||
            (frameBytes.length >= 12 && frameBytes[4] == 0x6A && frameBytes[5] == 0x50)) {
          return await _wasmWorkerBridge.decodeFrame(frameBytes, options);
        }
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

      if (byteData == null) {
        return _decodeUncompressed(bytes, options);
      }

      final TypedData pixels;
      if (options.bitsAllocated == 16) {
        final list = Uint16List(numPixels);
        for (int i = 0; i < numPixels; i++) {
          list[i] = byteData.getUint8(i * 4); // Extract red/luminance channel
        }
        pixels = list;
      } else {
        final list = Uint8List(numPixels);
        for (int i = 0; i < numPixels; i++) {
          list[i] = byteData.getUint8(i * 4);
        }
        pixels = list;
      }

      image.dispose();

      return DecodeResult(
        pixelData: pixels,
        width: width,
        height: height,
        bitsAllocated: options.bitsAllocated,
        bitsStored: options.bitsStored <= 8 ? 8 : options.bitsStored,
        isSigned: options.isSigned,
      );
    } catch (_) {
      return _decodeUncompressed(bytes, options);
    }
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

  /// DICOM Part 5 Annex G RLE Decompressor.
  static DecodeResult _decodeRle(Uint8List bytes, DecodeOptions options) {
    final numPixels = options.width * options.height;
    if (bytes.length < 64) {
      return _decodeUncompressed(bytes, options);
    }

    final byteData = ByteData.sublistView(bytes);
    final numSegments = byteData.getUint32(0, Endian.little);
    if (numSegments < 1 || numSegments > 15) {
      return _decodeUncompressed(bytes, options);
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

      final segData = _unpackPackBits(bytes.sublist(start, end.clamp(start, bytes.length)), numPixels);
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
          list[i] = (m << 8) | l;
        }
        pixels = list;
      }
    } else if (decompressedSegments.isNotEmpty) {
      pixels = decompressedSegments[0];
    } else {
      return _decodeUncompressed(bytes, options);
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

  static Uint8List _unpackPackBits(Uint8List input, int expectedSize) {
    final output = BytesBuilder(copy: false);
    int i = 0;
    while (i < input.length && output.length < expectedSize) {
      final n = input[i++];
      if (n >= 0 && n <= 127) {
        final count = n + 1;
        if (i + count <= input.length) {
          output.add(input.sublist(i, i + count));
          i += count;
        }
      } else if (n >= 129 && n <= 255) {
        final count = 257 - n;
        if (i < input.length) {
          final val = input[i++];
          output.add(Uint8List(count)..fillRange(0, count, val));
        }
      }
    }
    return output.toBytes();
  }

  static void dispose() {
    _wasmWorkerBridge.dispose();
  }
}
