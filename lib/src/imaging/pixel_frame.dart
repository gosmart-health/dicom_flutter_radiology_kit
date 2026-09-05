import 'dart:typed_data';

/// Core container for a single DICOM frame preserving 16-bit scalar pixel buffers.
class PixelFrame {
  /// Raw scalar pixel data (`Int16List`, `Uint16List`, or `Uint8List`).
  final TypedData rawPixels;

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// Modality Rescale Slope (m).
  final double rescaleSlope;

  /// Modality Rescale Intercept (b).
  final double rescaleIntercept;

  /// Photometric Interpretation (MONOCHROME1, MONOCHROME2, RGB).
  final String photometricInterpretation;

  /// Bits stored per pixel (e.g. 12, 16).
  final int bitsStored;

  /// Bits allocated per pixel (e.g. 8, 16).
  final int bitsAllocated;

  /// Pixel representation (0 = unsigned, 1 = signed).
  final bool isSigned;

  PixelFrame({
    required this.rawPixels,
    required this.width,
    required this.height,
    this.rescaleSlope = 1.0,
    this.rescaleIntercept = 0.0,
    this.photometricInterpretation = 'MONOCHROME2',
    this.bitsStored = 12,
    this.bitsAllocated = 16,
    this.isSigned = false,
  });

  /// Total number of pixels in frame.
  int get pixelCount => width * height;

  /// Calculates minimum and maximum pixel values in the raw buffer.
  (num min, num max) getMinMax() {
    if (pixelCount == 0) return (0, 0);

    if (rawPixels is Int16List) {
      final list = rawPixels as Int16List;
      int min = list[0];
      int max = list[0];
      for (int i = 1; i < list.length; i++) {
        final val = list[i];
        if (val < min) min = val;
        if (val > max) max = val;
      }
      return (min, max);
    } else if (rawPixels is Uint16List) {
      final list = rawPixels as Uint16List;
      int min = list[0];
      int max = list[0];
      for (int i = 1; i < list.length; i++) {
        final val = list[i];
        if (val < min) min = val;
        if (val > max) max = val;
      }
      return (min, max);
    } else if (rawPixels is Uint8List) {
      final list = rawPixels as Uint8List;
      int min = list[0];
      int max = list[0];
      for (int i = 1; i < list.length; i++) {
        final val = list[i];
        if (val < min) min = val;
        if (val > max) max = val;
      }
      return (min, max);
    }

    return (0, 255);
  }

  /// Converts a raw scalar pixel value to a Modality-scaled value (e.g. Hounsfield Units).
  double getModalityValue(int rawValue) {
    return (rawValue * rescaleSlope) + rescaleIntercept;
  }
}
