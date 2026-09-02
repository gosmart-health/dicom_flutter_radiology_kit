import 'dart:math' as math;
import 'dart:typed_data';
import 'package:dicom_flutter_radiology_kit/dicom_flutter_radiology_kit.dart';

/// Fixture generators for synthetic 16-bit scalar DICOM frames.
class SyntheticPatterns {
  /// Generates a realistic 512x512 synthetic CT Chest/Abdomen phantom with standard Hounsfield Units.
  static PixelFrame generateCtPhantom({int size = 512}) {
    final rawPixels = Int16List(size * size);
    const double rescaleSlope = 1.0;
    const double rescaleIntercept = -1024.0;

    // Helper to write HU into raw pixel buffer: raw = (HU - rescaleIntercept) / rescaleSlope
    void setHu(int x, int y, double hu) {
      if (x < 0 || x >= size || y < 0 || y >= size) return;
      final raw = ((hu - rescaleIntercept) / rescaleSlope).round().clamp(-32768, 32767);
      rawPixels[y * size + x] = raw;
    }

    final double cx = size / 2.0;
    final double cy = size / 2.0;

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final dx = (x - cx) / (size * 0.42);
        final dy = (y - cy) / (size * 0.35);
        final distBody = dx * dx + dy * dy;

        if (distBody > 1.0) {
          // Surrounding Air: -1000 HU
          setHu(x, y, -1000.0);
          continue;
        }

        // Subcutaneous Fat ring / Body contour: -90 HU to +40 HU
        double hu = 40.0; // Soft tissue base

        if (distBody > 0.88) {
          hu = -90.0; // Subcutaneous Fat
        }

        // Left Lung (anatomical right)
        final lx = (x - (cx - size * 0.18)) / (size * 0.14);
        final ly = (y - (cy - size * 0.05)) / (size * 0.22);
        if (lx * lx + ly * ly <= 1.0) {
          hu = -650.0; // Lung parenchyma
          // Small pulmonary vessel
          if (math.sin(x * 0.2) * math.cos(y * 0.2) > 0.8) {
            hu = 30.0;
          }
        }

        // Right Lung (anatomical left)
        final rx = (x - (cx + size * 0.18)) / (size * 0.14);
        final ry = (y - (cy - size * 0.05)) / (size * 0.22);
        if (rx * rx + ry * ry <= 1.0) {
          hu = -650.0; // Lung parenchyma
          if (math.sin(x * 0.25) * math.cos(y * 0.25) > 0.8) {
            hu = 30.0;
          }
        }

        // Mediastinum / Heart structure
        final hx = (x - (cx + size * 0.02)) / (size * 0.12);
        final hy = (y - (cy + size * 0.02)) / (size * 0.14);
        if (hx * hx + hy * hy <= 1.0) {
          hu = 45.0; // Heart muscle / blood pool
        }

        // Spine (Vertebral body): +700 to +1100 HU
        final sx = (x - cx) / (size * 0.06);
        final sy = (y - (cy + size * 0.24)) / (size * 0.07);
        if (sx * sx + sy * sy <= 1.0) {
          hu = 950.0; // Cortical Bone
          // Spinal canal
          final scx = (x - cx) / (size * 0.025);
          final scy = (y - (cy + size * 0.23)) / (size * 0.025);
          if (scx * scx + scy * scy <= 1.0) {
            hu = 15.0; // CSF / Spinal cord
          }
        }

        // Ribs / Sternum bone points around periphery
        final angle = math.atan2(y - cy, x - cx);
        final ribDist = (distBody - 0.78).abs();
        if (ribDist < 0.04 && (math.sin(angle * 9) > 0.5)) {
          hu = 850.0; // Rib bone
        }

        // Contrast-enhanced lesion / vessel nodule
        final noduleDx = (x - (cx + size * 0.15));
        final noduleDy = (y - (cy - size * 0.12));
        if (noduleDx * noduleDx + noduleDy * noduleDy < 25) {
          hu = 180.0; // Contrast nodule
        }

        setHu(x, y, hu);
      }
    }

    return PixelFrame(
      rawPixels: rawPixels,
      width: size,
      height: size,
      rescaleSlope: rescaleSlope,
      rescaleIntercept: rescaleIntercept,
      photometricInterpretation: 'MONOCHROME2',
      bitsStored: 12,
      bitsAllocated: 16,
      isSigned: true,
    );
  }

  /// Generates a TG18-QC / SMPTE medical display calibration test grid.
  static PixelFrame generateTg18QcPattern({int size = 512}) {
    final rawPixels = Uint16List(size * size);
    const int maxVal = 4095; // 12-bit dynamic range

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        int val = (maxVal * 0.5).round();

        // 16-step luminance staircase along the center band
        if (y >= size * 0.38 && y <= size * 0.62) {
          final int stepIndex = (x / (size / 16)).floor().clamp(0, 15);
          val = ((stepIndex / 15.0) * maxVal).round();

          // Low-contrast 5% and 95% target patches within 0% and 100% blocks
          if (stepIndex == 0 && (x % (size ~/ 16) > size ~/ 48) && (y > size * 0.45 && y < size * 0.55)) {
            val = (maxVal * 0.05).round();
          } else if (stepIndex == 15 && (x % (size ~/ 16) > size ~/ 48) && (y > size * 0.45 && y < size * 0.55)) {
            val = (maxVal * 0.95).round();
          }
        } else {
          // Grid lines and crossbars
          final bool isGridX = (x % (size ~/ 8)) == 0;
          final bool isGridY = (y % (size ~/ 8)) == 0;
          final bool isBorder = x < 4 || x >= size - 4 || y < 4 || y >= size - 4;

          if (isBorder || isGridX || isGridY) {
            val = maxVal;
          } else {
            // Background quadrant shades
            final int qx = x ~/ (size / 2);
            final int qy = y ~/ (size / 2);
            val = ((0.2 + 0.15 * (qx + qy * 2)) * maxVal).round();
          }
        }

        rawPixels[y * size + x] = val.clamp(0, maxVal);
      }
    }

    return PixelFrame(
      rawPixels: rawPixels,
      width: size,
      height: size,
      rescaleSlope: 1.0,
      rescaleIntercept: 0.0,
      photometricInterpretation: 'MONOCHROME2',
      bitsStored: 12,
      bitsAllocated: 16,
      isSigned: false,
    );
  }

  /// Generates a continuous dynamic ramp from -1024 HU to +3072 HU.
  static PixelFrame generateDynamicRamp({int size = 512}) {
    final rawPixels = Int16List(size * size);
    const double rescaleSlope = 1.0;
    const double rescaleIntercept = -1024.0;

    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final double t = x / (size - 1);
        final double hu = -1000.0 + (t * 2500.0);
        final raw = ((hu - rescaleIntercept) / rescaleSlope).round().clamp(-32768, 32767);
        rawPixels[y * size + x] = raw;
      }
    }

    return PixelFrame(
      rawPixels: rawPixels,
      width: size,
      height: size,
      rescaleSlope: rescaleSlope,
      rescaleIntercept: rescaleIntercept,
      photometricInterpretation: 'MONOCHROME2',
      bitsStored: 12,
      bitsAllocated: 16,
      isSigned: true,
    );
  }
}
