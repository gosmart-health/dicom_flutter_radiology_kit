import 'dart:typed_data';
import 'pixel_frame.dart';

/// Value of Interest (VOI) Look-Up Table (LUT) calculations.
class VoiLut {
  /// Maps raw 16-bit scalar values to an 8-bit RGBA pixel byte array based on Window Center and Width.
  static Uint8List applyVoiLut({
    required PixelFrame frame,
    required double windowCenter,
    required double windowWidth,
  }) {
    final count = frame.pixelCount;
    final Uint8List rgbaBuffer = Uint8List(count * 4);

    if (count == 0) return rgbaBuffer;

    final double width = windowWidth < 1.0 ? 1.0 : windowWidth;
    final double center = windowCenter;
    final double slope = frame.rescaleSlope;
    final double intercept = frame.rescaleIntercept;
    final bool isMonochrome1 = frame.photometricInterpretation == 'MONOCHROME1';

    final double minWindow = center - 0.5 - ((width - 1.0) / 2.0);
    final double maxWindow = center - 0.5 + ((width - 1.0) / 2.0);

    final rawPixels = frame.rawPixels;

    if (rawPixels is Int16List) {
      _computeLinearLutInt16(
        rawPixels,
        rgbaBuffer,
        slope,
        intercept,
        minWindow,
        maxWindow,
        width,
        isMonochrome1,
      );
    } else if (rawPixels is Uint16List) {
      _computeLinearLutUint16(
        rawPixels,
        rgbaBuffer,
        slope,
        intercept,
        minWindow,
        maxWindow,
        width,
        isMonochrome1,
      );
    } else if (rawPixels is Uint8List) {
      _computeLinearLutUint8(
        rawPixels,
        rgbaBuffer,
        slope,
        intercept,
        minWindow,
        maxWindow,
        width,
        isMonochrome1,
      );
    }

    return rgbaBuffer;
  }

  static void _computeLinearLutInt16(
    Int16List src,
    Uint8List dest,
    double slope,
    double intercept,
    double minWin,
    double maxWin,
    double width,
    bool isMonochrome1,
  ) {
    int destIdx = 0;
    final len = src.length;
    for (int i = 0; i < len; i++) {
      final double modVal = (src[i] * slope) + intercept;
      int displayVal;
      if (modVal <= minWin) {
        displayVal = 0;
      } else if (modVal > maxWin) {
        displayVal = 255;
      } else {
        displayVal = (((modVal - (centerFromMinWin(minWin, width))) / width + 0.5) * 255.0).round().clamp(0, 255);
      }

      if (isMonochrome1) {
        displayVal = 255 - displayVal;
      }

      dest[destIdx] = displayVal;     // R
      dest[destIdx + 1] = displayVal; // G
      dest[destIdx + 2] = displayVal; // B
      dest[destIdx + 3] = 255;        // A
      destIdx += 4;
    }
  }

  static void _computeLinearLutUint16(
    Uint16List src,
    Uint8List dest,
    double slope,
    double intercept,
    double minWin,
    double maxWin,
    double width,
    bool isMonochrome1,
  ) {
    int destIdx = 0;
    final len = src.length;
    for (int i = 0; i < len; i++) {
      final double modVal = (src[i] * slope) + intercept;
      int displayVal;
      if (modVal <= minWin) {
        displayVal = 0;
      } else if (modVal > maxWin) {
        displayVal = 255;
      } else {
        displayVal = (((modVal - minWin) / width) * 255.0).round().clamp(0, 255);
      }

      if (isMonochrome1) {
        displayVal = 255 - displayVal;
      }

      dest[destIdx] = displayVal;
      dest[destIdx + 1] = displayVal;
      dest[destIdx + 2] = displayVal;
      dest[destIdx + 3] = 255;
      destIdx += 4;
    }
  }

  static void _computeLinearLutUint8(
    Uint8List src,
    Uint8List dest,
    double slope,
    double intercept,
    double minWin,
    double maxWin,
    double width,
    bool isMonochrome1,
  ) {
    int destIdx = 0;
    final len = src.length;
    for (int i = 0; i < len; i++) {
      final double modVal = (src[i] * slope) + intercept;
      int displayVal;
      if (modVal <= minWin) {
        displayVal = 0;
      } else if (modVal > maxWin) {
        displayVal = 255;
      } else {
        displayVal = (((modVal - minWin) / width) * 255.0).round().clamp(0, 255);
      }

      if (isMonochrome1) {
        displayVal = 255 - displayVal;
      }

      dest[destIdx] = displayVal;
      dest[destIdx + 1] = displayVal;
      dest[destIdx + 2] = displayVal;
      dest[destIdx + 3] = 255;
      destIdx += 4;
    }
  }

  static double centerFromMinWin(double minWin, double width) {
    return minWin + 0.5 + ((width - 1.0) / 2.0);
  }
}
