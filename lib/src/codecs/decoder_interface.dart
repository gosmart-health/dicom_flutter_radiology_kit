import 'dart:typed_data';

/// Parameter options provided to decoders.
class DecodeOptions {
  final int width;
  final int height;
  final int bitsAllocated;
  final int bitsStored;
  final bool isSigned;
  final String photometricInterpretation;

  const DecodeOptions({
    required this.width,
    required this.height,
    this.bitsAllocated = 16,
    this.bitsStored = 12,
    this.isSigned = false,
    this.photometricInterpretation = 'MONOCHROME2',
  });
}

/// Result returned from decoding a DICOM frame payload.
class DecodeResult {
  final TypedData pixelData; // Int16List or Uint16List or Uint8List
  final int width;
  final int height;
  final int bitsAllocated;
  final int bitsStored;
  final bool isSigned;

  const DecodeResult({
    required this.pixelData,
    required this.width,
    required this.height,
    required this.bitsAllocated,
    required this.bitsStored,
    required this.isSigned,
  });
}

/// Abstract contract for frame decoders.
abstract class FrameDecoder {
  Future<DecodeResult> decodeFrame(Uint8List encodedBytes, DecodeOptions options);
}
